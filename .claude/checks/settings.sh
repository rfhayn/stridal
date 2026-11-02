#!/bin/sh
# Agent least privilege (OWASP LLM01/LLM06; item 10 of the change process): .claude/settings.json
# denies Claude the project's secrets and the few commands no session should run, and turns the Bash
# sandbox on. A deny rule is enforced by Claude Code whatever the permission mode, and the sandbox
# confines what a command can write and reach at the OS level: both are structure, not prose
# (*Reach is set by structure, not by the prompt*).
#
# Fails when: the deny list or the sandbox is missing; a rule from the required set below is gone;
# a deny rule is not `Tool(...)` with a tool Claude Code knows (a misspelt rule denies nothing);
# the sandbox is not enabled, or has no network allowlist; a credential file is not denied to the
# sandbox; `~/.config/gh` or a directory above it is denied; a general tool is excluded from the
# sandbox. Add your own rules freely; remove one of
# the required set only by editing this list in a PR that says why. A tool that needs a host gets it
# per machine in .claude/settings.local.json (sandbox.network.allowedDomains merges across scopes),
# never by turning the sandbox off here. sandbox.excludedCommands is not honoured on Claude Code
# 2.1.316 (spike S5h), so until Stridal's OPS-216 a tool that fails in the sandbox for another reason, the gate
# included, runs from the orchestrating session with the sandbox off, through
# sandbox.allowUnsandboxedCommands. A project that gates outside Claude Code may set that either way;
# the value shipped is true until OPS-216 (TestShippedSettingsKeepTheGatesWayOut, framework/). The list
# names the gate alone, so the
# instructions and install's entries do not part, and promises no other tool a lift it does not give.
# `~/.config/gh` is deliberately not denied, to a tool or to the sandbox: a `Read(...)` deny rule also
# reaches the sandbox's read list (OPS-75 saw that rule make sandboxed gh report "not logged in"), and
# a sandboxed script's gh must read hosts.yml to find its keyring account. So gh's token belongs in a
# keyring (docs/playbook.md), and the health line gh-token-file reports one left in that file, at each
# session. What a sandboxed session cannot write is the health line sandbox-writes: both run from
# extensions.sh, and this holds their verdicts on fixtures (OPS-220). The keys are Claude Code's
# (code.claude.com/docs/en/permissions, /docs/en/sandboxing; checked 2026-09-30).
. "$(dirname "$0")/lib.sh"
need jq

REQUIRED_DENY='Read(./.env)
Read(./.env.*)
Edit(./.env)
Edit(./.env.*)
Read(~/.ssh/**)
Read(~/.aws/**)
Read(~/.git-credentials)
Read(~/.netrc)
Read(~/.npmrc)
Bash(git push --force *)
Bash(git push -f *)
Bash(tmux *kill-server*)
Bash(cmd.exe *)
Bash(powershell.exe *)
Bash(pwsh.exe *)
Bash(wsl.exe *)
Bash(explorer.exe *)
Bash(clip.exe *)
Bash(notepad.exe *)
Bash(/mnt/c/*)'
# A deny rule binds Claude's tools; sandbox.credentials binds what a sandboxed command opens. Each file
# below is named in both, as ~/.ssh and ~/.aws already were.
REQUIRED_CREDENTIALS='~/.ssh
~/.aws
~/.git-credentials
~/.netrc
~/.npmrc'
# The tools the list once named. The list is not honoured on 2.1.316 (S5h), so each entry promised a
# lift it did not give, and only that not-honoured behaviour kept `git` from writing the plugin's data
# directory: where the list is honoured, each would run outside the sandbox (OPS-184's review, M2).
# The gate's entries stay, as the one form of its command the instructions may name (below). These
# names are retiredEntries' in settings.go, and TestRetiredEntriesAgreeOnEveryRoad holds the two equal.
TOOL_EXCLUSION_RE='^([^ ]*/)?(git|gh|tmux|stridal|docker)( |$)'
# What fixes a settings.json the template has moved past: the merge each road runs.
settings_fix() {
  if [ -n "${STRIDAL_FW:-}" ]; then echo "re-run /stridal:init, which merges settings.json"
  else echo "run stridal update, which merges settings.json"; fi
}
# gh_denied FILE: prints each deny that covers gh's config directory or its hosts.yml, in a Read rule,
# a sandbox credential or the sandbox's denyRead, the directories above it included: a rule on
# ~/.config breaks gh the same way. Each entry is read as the glob it is, against the file and each
# directory above it. A Read rule's // is the filesystem's root and its single / the project's; a
# sandbox path's single / is absolute (Claude Code 2.1.316's resolver and schema); anything else is the
# project's own path. An absolute path naming .config or .config/gh under any home counts too, since
# the gate's HOME is a fixture and the settings name the real one.
gh_denied() {
  jq -r '((.permissions.deny // [])[] | select(type == "string") | capture("^Read\\((?<p>.*)\\)$").p | "R " + .),
    ((.sandbox.credentials.files // [])[] | .path // empty | "S " + .),
    ((.sandbox.filesystem.denyRead // [])[] | "S " + .)' "$1" | while IFS= read -r _l; do
    _k=${_l%% *}; _e=${_l#* }; _p=$_e
    case $_k$_p in
      ?'~') _p=$HOME ;;
      ?'~/'*) _p=$HOME/${_p#'~/'} ;;
      R//*) _p=${_p#/} ;;
      S/*) ;;
      *) continue ;;
    esac
    [ "$_p" = / ] || _p=${_p%/}
    case $_p in */.config | */.config/gh | */.config/gh/* | */.config/'*' | */.config/'**') echo "$_e"; continue ;; esac
    _c=$HOME/.config/gh/hosts.yml
    while :; do
      # shellcheck disable=SC2254
      case $_c in $_p) echo "$_e"; break ;; esac
      [ "$_c" != / ] && [ "$_c" != . ] || break
      _c=$(dirname "$_c")
    done
  done
}
# Windows interop (WSL2): WSL hands a launch of cmd.exe, powershell.exe or anything under /mnt/c/ to
# the Windows host over a Unix socket, so it runs OUTSIDE the sandbox unless the optional seccomp
# filter blocks that socket (code.claude.com/docs/en/sandboxing, WSL2 notes; checked 2026-10-01),
# and sandbox.autoAllowBashIfSandboxed would approve it without a prompt. The deny rules above stop
# the forms Claude writes (a deny rule is respected even in auto-allow mode); the seccomp filter,
# which docs/playbook.md makes required on WSL2, is the boundary for the rest. Where
# sandbox.excludedCommands is honoured (not on Claude Code 2.1.316, S5h), listing any of them would
# run them unsandboxed, so that fails.
# /mnt/c/ only, not /mnt/: a rule has no character class for "a drive letter", a deny rule cannot
# be undone by a narrower allow, and /mnt/ also holds ordinary Linux mounts. C: holds Windows
# itself; programs on other drives are left to the seccomp filter. `code` (VS Code's WSL shim) is
# NOT denied: on macOS and Linux `code <file>` is the plain editor launcher, not interop, and on
# WSL2 its launch of the Windows editor is covered by the seccomp filter.
INTEROP_RE='(^|[ /])(cmd|powershell|pwsh|wsl|explorer|clip|notepad)\.exe|^/mnt/c/'
KNOWN_TOOLS=" Read Edit Write MultiEdit NotebookEdit Bash WebFetch WebSearch Agent Task Skill Glob Grep ${CHECK_EXTRA_TOOLS:-} "

check_settings() {  # check_settings FILE: prints ok/FAIL lines
  f=$1
  jq -e . "$f" >/dev/null 2>&1 || { echo "FAIL $f is missing or not valid JSON"; return; }
  if ! jq -e '.permissions.deny | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    echo "FAIL settings.json has no permissions.deny list"
  else
    printf '%s\n' "$REQUIRED_DENY" | while IFS= read -r r; do
      jq -e --arg r "$r" '.permissions.deny | index($r)' "$f" >/dev/null && echo "ok   denies $r" || echo "FAIL permissions.deny lacks $r: $(settings_fix)"
    done
    jq -r '.permissions.deny[]' "$f" | while IFS= read -r r; do
      t=$(printf '%s' "$r" | sed -n 's/^\([A-Za-z]*\)(.*)$/\1/p')
      [ -z "$t" ] && t=$(printf '%s' "$r" | grep -E '^[A-Za-z]+$')
      case "$t" in mcp__*) continue ;; esac
      case "$KNOWN_TOOLS" in *" ${t:-?} "*) ;; *) echo "FAIL deny rule '$r' is not Tool(...) with a known tool (typo? else CHECK_EXTRA_TOOLS)" ;; esac
    done
  fi
  # A deny that names gh's folder or file, by a rule or as a credential, breaks every sandboxed `gh`
  # with "not logged in", and the health lines and session context then read CANNOT CHECK.
  _x=$(gh_denied "$f")
  [ -z "$_x" ] && echo "ok   no Read rule, sandbox credential or denyRead covers ~/.config/gh: sandboxed gh can find its keyring account" \
    || echo "FAIL ~/.config/gh is denied ($(printf '%s' "$_x" | tr '\n' ' ')): a Read rule reaches the sandbox too, and a credential's mask degrades to deny on macOS and Windows, so sandboxed gh would report 'not logged in' (OPS-75). A token in hosts.yml is the health line's to report. $(settings_fix) if the template retired it"
  if ! jq -e '.sandbox | type == "object"' "$f" >/dev/null 2>&1; then
    echo "FAIL settings.json has no sandbox settings"
  else
    jq -e '.sandbox.enabled == true' "$f" >/dev/null && echo "ok   the Bash sandbox is enabled" || echo "FAIL sandbox.enabled is not true (a host goes in .claude/settings.local.json instead: sandbox.network.allowedDomains; a command the sandbox refuses runs from the orchestrating session with the sandbox off, since sandbox.excludedCommands is not honoured on Claude Code 2.1.316)"
    jq -e '(.sandbox.network.allowedDomains | type == "array" and length > 0)' "$f" >/dev/null \
      && echo "ok   the sandbox's network allowlist names $(jq '.sandbox.network.allowedDomains | length' "$f") domain(s)" \
      || echo "FAIL sandbox.network.allowedDomains is missing or empty: a sandboxed command's network would be unbounded or prompt every time"
    jq -e '.sandbox.allowUnsandboxedCommands | type == "boolean"' "$f" >/dev/null \
      && echo "ok   sandbox.allowUnsandboxedCommands is set ($(jq .sandbox.allowUnsandboxedCommands "$f"))" \
      || echo "FAIL sandbox.allowUnsandboxedCommands is not set: say whether a command that fails in the sandbox may retry outside it (through the permission flow)"
    printf '%s\n' "$REQUIRED_CREDENTIALS" | while IFS= read -r _c; do
      jq -e --arg c "$_c" '[(.sandbox.credentials.files // [])[] | select(.path == $c and .mode == "deny")] | length > 0' "$f" >/dev/null \
        && echo "ok   sandbox.credentials denies $_c to a sandboxed command" \
        || echo "FAIL sandbox.credentials.files lacks {\"path\": \"$_c\", \"mode\": \"deny\"}: a deny rule alone binds Claude's tools, so a sandboxed command would still open it: $(settings_fix)"
    done
    _x=$(jq -r '(.sandbox.excludedCommands // [])[]' "$f" | grep -E "$TOOL_EXCLUSION_RE")
    [ -z "$_x" ] && echo "ok   sandbox.excludedCommands names no general tool (git, gh, tmux, stridal, docker)" \
      || echo "FAIL sandbox.excludedCommands lists $(printf '%s' "$_x" | tr '\n' ' '): not honoured on Claude Code 2.1.316 (S5h), so it promises a lift it does not give, and where it is honoured the tool runs outside the sandbox, free to write the plugin's data directory: $(settings_fix)"
    _x=$(jq -r '(.sandbox.excludedCommands // [])[]' "$f" | grep -E "$INTEROP_RE")
    [ -z "$_x" ] && echo "ok   no Windows interop command (cmd.exe, powershell.exe, pwsh.exe, wsl.exe, /mnt/...) is listed in sandbox.excludedCommands" \
      || echo "FAIL sandbox.excludedCommands lists Windows interop: where the list is honoured it would run outside the sandbox (not on Claude Code 2.1.316): $(printf '%s' "$_x" | tr '\n' ' ')"
    # The gate and gate-wait need the sandbox off (OPS-72): their process checks use `ps`, tmux and
    # loopback, which the sandbox refuses. These entries do not give them that: the list is not
    # honoured on Claude Code 2.1.316 (S5h), so until Stridal's OPS-216 the orchestrating session runs
    # them with the sandbox off. An entry names the script run ALONE, bare or with arguments, so both forms are
    # listed: the receipt runs the gate bare, and a lane's is named with `-C <worktree>` (OPS-161). gate-wait.sh is where install put it (gate_wait_path, conf.sh):
    # beside the template's runner, but at scripts/ci/ beside a project's own runner.
    # Both as install writes them: the gate as a command (gate_cmd), gate-wait where it put it.
    # An empty GATE is the template's gate: build-change runs scripts/ci/gate.sh then (`c.gate ||`),
    # and the settings an install wrote before it emptied still name that (OPS-87). Only empty: any
    # other value, absolute or outside the repo included, build-change runs as given.
    _gt=$(gate_cmd "$GATE"); [ -n "$_gt" ] || _gt=scripts/ci/gate.sh
    for _g in "$_gt" "$(gate_wait_path)"; do
      for _p in "$_g" "$_g *"; do
        jq -e --arg p "$_p" '(.sandbox.excludedCommands // []) | index($p)' "$f" >/dev/null \
          && echo "ok   sandbox.excludedCommands lists '$_p'" \
          || echo "FAIL sandbox.excludedCommands lacks '$_p': the list and the instructions' gate commands have parted (the list does not lift the sandbox on Claude Code 2.1.316: the gate runs from the orchestrating session with the sandbox off)"
      done
    done
  fi
}

# ── Every gate command an instruction gives matches the list (OPS-161) ───────────────────────
# An exclusion names a command that IS the script: `P` exactly, `P *` with arguments, and nothing
# chained, piped or redirected around it. It does not lift the sandbox: the list is not honoured on
# Claude Code 2.1.316 (S5h), so until Stridal's OPS-216 the orchestrating session runs the gate with
# the sandbox off, and this holds the one form it names a worktree in. A subagent lane's Bash starts in the
# main checkout, so `cd <worktree> && <gate>` was the natural instruction, and it ran the gate
# sandboxed, where `ps`, git's caches and the loopback name fail whatever the code does. The lane
# form is `<gate> -C <worktree>`. This reads the Markdown instructions (AGENTS.md, CLAUDE.md, the
# skills' and agents' files, the playbook and the conventions) in UNITS: a paragraph's code spans,
# read across its line breaks as Markdown renders them, a table row's, or a code block, read as
# commands unless its label (any case) names prose or another language (text, diff, json, go, …);
# its `#` comments and `$ ` prompts dropped. Two rules:
#   1. each span or block line that names the gate or gate-wait matches an entry of settings.json's
#      own list, `<placeholder>`s filled with a path, so an instruction and the exclusion cannot part;
#   2. no unit both changes directory (cd, pushd) and names the gate or gate-wait without -C. A
#      deliberate over-read with no shell grammar (ADR-0012 rejected chasing each form): a cd on the
#      line before, a backslash continuation or a subshell is caught the same way.
# A counter-example is exempt only when `<!-- gate-check: example -->` stands on a line of its own
# before its paragraph or block, and the exemption covers that one unit. build-change's gate prompts
# are JavaScript, held to its LONE rule by checks/build-change.sh instead.
GATE_EXAMPLE='<!-- gate-check: example -->'
excluded() {  # excluded SETTINGS CMD: CMD matches an entry of SETTINGS' excludedCommands
  case $2 in *'&'* | *'|'* | *';'* | *'>'* | *'<'* | *'$('* | *'`'* | *'
'*) return 1 ;; esac
  jq -r '(.sandbox.excludedCommands // [])[]' "$1" | {
    while IFS= read -r _e; do
      case $_e in
        *' *') case $2 in "${_e% \*} "?*) exit 0 ;; esac ;;
        *) [ "$2" = "$_e" ] && exit 0 ;;
      esac
    done
    exit 1
  }
}
# gate_units FILE...: `C<TAB>file<TAB>unit<TAB>command` for each span or block line, and
# `U<TAB>file<TAB>unit<TAB>the unit's commands joined by " ; "`, for every unit not marked an example.
gate_units() {
  awk -v example="$GATE_EXAMPLE" '
    # A tab is a space to the shell, and the field separator here: kept, it would cut the command.
    function add(s) { gsub(/\t/, " ", s); c[++n] = s; j = j (j == "" ? "" : " ; ") s }
    function out(i) {
      if (unit) {
        if (pending) pending = 0
        else if (n > 0) { u++; for (i = 1; i <= n; i++) print "C\t" file "\t" u "\t" c[i]; print "U\t" file "\t" u "\t" j }
      }
      n = 0; j = ""; unit = 0
    }
    function flush(l) {
      if (para == "") return
      l = para; para = ""; unit = 1
      while (match(l, /`[^`]+`/)) { add(substr(l, RSTART + 1, RLENGTH - 2)); l = substr(l, RSTART + RLENGTH) }
      out()
    }
    FNR == 1 { flush(); out(); file = FILENAME; fence = ""; pending = 0 }
    fence != "" {
      l = $0; sub(/^[ \t]+/, "", l)
      if (substr(l, 1, 3) == fence) { out(); fence = ""; next }
      if (!cmds) next
      gsub(/[ \t]+$/, "", l); sub(/^\$ /, "", l)
      if (l == "" || l ~ /^#/) next
      sub(/[ \t]+#.*/, "", l); add(l); next
    }
    /^[ \t]*(```|~~~)/ {
      flush(); l = $0; sub(/^[ \t]+/, "", l); fence = substr(l, 1, 3)
      info = tolower(l); sub(/^[`~]+[ \t]*/, "", info); sub(/[ \t{].*/, "", info)
      # Fail closed: a block reads as commands unless its label names something else.
      cmds = (info !~ /^(text|txt|plaintext|diff|json|yaml|yml|toml|go|js|javascript|ts|typescript|python|py|html|css|md|markdown)$/); unit = 1; next
    }
    { l = $0; gsub(/^[ \t]+|[ \t]+$/, "", l) }
    l == example { flush(); pending = 1; next }
    l == "" { flush(); next }
    l ~ /^\|/ { flush(); para = l; flush(); next }
    { para = para (para == "" ? "" : " ") l }
    END { flush(); out() }
  ' "$@" 2>/dev/null
}
check_lane_gates() {  # check_lane_gates SETTINGS FILE...: prints ok/FAIL lines
  _s=$1; shift
  _gt=$(gate_cmd "$GATE"); [ -n "$_gt" ] || _gt=scripts/ci/gate.sh
  _re=$(printf '%s\n%s\n' "$_gt" "$(gate_wait_path)" | sed 's/[].[\*^$]/\\&/g' | paste -sd'|' -)
  _names="(^|[[:space:];&|(])(\\./)?($_re)([[:space:];&|)]|\$)"
  # FILE<TAB>TEXT: the tab is the only one, so a pattern after it reads TEXT alone.
  _infield="	(.*[[:space:];&|(])?(\\./)?($_re)([[:space:];&|)]|\$)"
  _how="Give the lane form (\`<gate> -C <worktree>\`), never cd before the gate or pipe it. To quote one as what NOT to do, put $GATE_EXAMPLE on its own line before its paragraph or block"
  gate_units "$@" > "$d/units"
  awk -F'\t' '$1 == "C" { print $2 "\t" $4 }' "$d/units" | grep -E "$_infield" > "$d/gatecmds"
  _n=0
  while IFS='	' read -r _f _c; do
    _n=$((_n + 1))
    _x=$(printf '%s' "$_c" | sed 's|<[A-Za-z_-]*>|/abs/lane|g')
    excluded "$_s" "$_x" || echo "FAIL ${_f#"$ROOT"/}: \`$_c\` matches no sandbox.excludedCommands entry: the instruction and the list have parted. $_how"
  done < "$d/gatecmds"
  awk -F'\t' '$1 == "U" { print $2 "\t" $4 }' "$d/units" | grep -E "$_infield" | while IFS='	' read -r _f _u; do
    printf '%s\n' "$_u" | grep -qE '(^|[[:space:];&|(])(cd|pushd)([[:space:]]|$)' || continue
    # What names the gate once every `<gate> -C` is taken out: a gate this unit runs where it cd'd.
    printf '%s\n' "$_u" | sed -E "s#(\\./)?($_re) -C##g" | grep -qE "$_names" || continue
    echo "FAIL ${_f#"$ROOT"/}: a paragraph or block changes directory and names the gate or gate-wait without -C ($(printf '%s' "$_u" | cut -c1-240)): a gate run that way tests whichever checkout the directory change reached, not a named one. $_how"
  done
  echo "ok   $_n gate command(s) in the instructions checked against sandbox.excludedCommands"
  grep -q ' -C ' "$d/gatecmds" && echo "ok   an instruction gives the lane form, the gate with -C <worktree>" \
    || echo "FAIL no instruction gives the lane form (\`<gate> -C <worktree>\`): a subagent lane is left to cd into its worktree rather than name it"
}

# Self-test: the template's settings pass; each broken shape fails.
st="$ROOT/.claude/settings.json"
d=$(scratch)
selftest() {  # selftest WANT LABEL JQ-FILTER [GATE_RUN] [GATE]: the last two, for a project whose gate moved
  jq "$3" "$st" > "$d/s.json"
  n=$(GATE_RUN=${4:-$GATE_RUN}; GATE=${5-$GATE}; check_settings "$d/s.json" | grep -c '^FAIL')
  if [ "$1" = pass ] && [ "$n" -eq 0 ]; then ok "self-test: $2 passes"
  elif [ "$1" = fail ] && [ "$n" -gt 0 ]; then ok "self-test: $2 fails"
  else fail "self-test: $2 ($n FAIL line(s), want $1)"; fi
}
selftest pass "the template's settings" '.'
selftest fail "no deny list" 'del(.permissions.deny)'
selftest fail "a required deny rule removed" '.permissions.deny -= ["Read(./.env)"]'
selftest fail "a misspelt deny rule" '.permissions.deny += ["Raed(./secrets/**)"]'
selftest fail "no sandbox" 'del(.sandbox)'
selftest fail "the sandbox turned off" '.sandbox.enabled = false'
selftest fail "no network allowlist" 'del(.sandbox.network)'
selftest fail "allowUnsandboxedCommands unset" 'del(.sandbox.allowUnsandboxedCommands)'
selftest pass "allowUnsandboxedCommands false (a project that gates outside Claude Code)" '.sandbox.allowUnsandboxedCommands = false'
# OPS-220: each credential file, in each list; each tool the list must not name, bare and by path.
for _r in '~/.git-credentials' '~/.netrc' '~/.npmrc'; do
  selftest fail "$_r no longer a Read deny" ".permissions.deny -= [\"Read($_r)\"]"
  selftest fail "$_r no longer in sandbox.credentials" ".sandbox.credentials.files |= map(select(.path != \"$_r\"))"
done
selftest fail "a credential file masked, not denied, in sandbox.credentials" '(.sandbox.credentials.files[] | select(.path == "~/.netrc") | .mode) = "mask"'
for _r in 'git *' 'gh *' 'tmux *' 'stridal *' 'docker *' 'git' '/usr/bin/git *'; do
  selftest fail "the exclusion '$_r' back in the list" ".sandbox.excludedCommands += [\"$_r\"]"
done
selftest pass "a tool whose name starts like one (github-tool *, dockerize *) stays the project's call" '.sandbox.excludedCommands += ["github-tool *", "dockerize *"]'
selftest fail "gh's folder denied by a Read rule (OPS-75's break)" '.permissions.deny += ["Read(~/.config/gh/**)"]'
selftest fail "gh's hosts.yml denied by a Read rule" '.permissions.deny += ["Read(~/.config/gh/hosts.yml)"]'
selftest fail "gh's folder denied as a sandbox credential" '.sandbox.credentials.files += [{path: "~/.config/gh", mode: "deny"}]'
selftest fail "gh's folder in the sandbox's denyRead" '.sandbox.filesystem.denyRead = ["~/.config/gh"]'
selftest fail "~/.config in the sandbox's denyRead (an ancestor)" '.sandbox.filesystem.denyRead = ["~/.config"]'
selftest fail "Read(~/.config/**) (an ancestor, as a glob)" '.permissions.deny += ["Read(~/.config/**)"]'
selftest fail "~/.config as a sandbox credential (an ancestor)" '.sandbox.credentials.files += [{path: "~/.config", mode: "deny"}]'
selftest fail "the home directory denied (Read(~/**))" '.permissions.deny += ["Read(~/**)"]'
selftest fail "an absolute rule above the home directory (Read(//**))" '.permissions.deny += ["Read(//**)"]'
selftest fail "a glob that takes in gh's folder (Read(~/.conf*/**))" '.permissions.deny += ["Read(~/.conf*/**)"]'
selftest pass "a sibling of gh's folder denied (~/.config/other)" '.permissions.deny += ["Read(~/.config/other/**)"] | .sandbox.filesystem.denyRead = ["~/.config/other"]'
selftest pass "a name that only starts the same (~/.configure, ~/.config/ghost)" '.permissions.deny += ["Read(~/.configure/**)"] | .sandbox.filesystem.denyRead = ["~/.config/ghost"]'
selftest fail "a credential masked under gh's folder (mask degrades to deny on macOS and Windows)" '.sandbox.credentials.files += [{path: "~/.config/gh", mode: "mask"}]'
# An absolute path naming the home the session has, when this run's HOME is another: how the gate runs.
selftest fail "gh's folder by an absolute path, in denyRead" '.sandbox.filesystem.denyRead = ["/Users/someone/.config/gh"]'
selftest fail "gh's folder by an absolute Read rule" '.permissions.deny += ["Read(//Users/someone/.config/gh/**)"]'
selftest fail "~/.config by an absolute path, in denyRead" '.sandbox.filesystem.denyRead = ["/Users/someone/.config"]'
selftest pass "an absolute sibling of gh's folder" '.sandbox.filesystem.denyRead = ["/Users/someone/.config/ghost", "/Users/someone/.config/other"]'
# A Read rule's single slash is the project root, two are the filesystem's (Claude Code 2.1.316's resolver);
# a sandbox path's single slash is absolute (its schema: "absolute, ~ expanded, or relative").
selftest pass "Read(/**), which is the project's root" '.permissions.deny += ["Read(/**)"]'
selftest pass "Read(/.config/gh/**), which is under the project" '.permissions.deny += ["Read(/.config/gh/**)"]'
selftest fail "the filesystem's root in denyRead" '.sandbox.filesystem.denyRead = ["/"]'
# OPS-220: a settings.json the template has moved past names the merge that fixes it, on each road.
jq 'del(.permissions.deny[] | select(. == "Read(~/.netrc)")) | .sandbox.excludedCommands += ["git *"]' "$st" > "$d/old.json"
_n=$(STRIDAL_FW=; check_settings "$d/old.json" | grep -c '^FAIL.*run stridal update, which merges')
[ "$_n" -eq 2 ] && ok "self-test: old settings name 'stridal update' on a copy install" || fail "self-test: old settings: $_n FAIL line(s) name stridal update, want 2"
_n=$(STRIDAL_FW=/fw; check_settings "$d/old.json" | grep -c '^FAIL.*re-run /stridal:init, which merges')
[ "$_n" -eq 2 ] && ok "self-test: old settings name '/stridal:init' in a plugin project" || fail "self-test: old settings: $_n FAIL line(s) name /stridal:init, want 2"
selftest fail "Windows interop no longer denied (cmd.exe)" '.permissions.deny -= ["Bash(cmd.exe *)"]'
selftest fail "Windows paths no longer denied (/mnt/c/)" '.permissions.deny -= ["Bash(/mnt/c/*)"]'
selftest fail "explorer.exe no longer denied" '.permissions.deny -= ["Bash(explorer.exe *)"]'
selftest fail "clip.exe excluded from the sandbox" '.sandbox.excludedCommands += ["clip.exe *"]'
selftest pass "an ordinary Linux mount (/mnt/data) excluded from the sandbox" '.sandbox.excludedCommands += ["/mnt/data/tool *"]'
selftest fail "powershell.exe excluded from the sandbox" '.sandbox.excludedCommands += ["powershell.exe *"]'
selftest fail "a /mnt/c binary excluded from the sandbox" '.sandbox.excludedCommands += ["/mnt/c/Windows/System32/cmd.exe *"]'
selftest fail "gate-wait no longer excluded from the sandbox" '.sandbox.excludedCommands -= ["scripts/ci/gate-wait.sh *"]'
selftest fail "the bare gate no longer excluded from the sandbox" '.sandbox.excludedCommands -= ["scripts/ci/gate.sh"]'
# Where gate-wait.sh is depends on the runner, as install placed it (RenderSettings renders these).
selftest pass "a project's own runner (GATE_RUN=bin/ci.sh): gate-wait stays at scripts/ci/" \
  '.sandbox.excludedCommands |= map(sub("^scripts/ci/run-local\\.sh"; "bin/ci.sh"))' bin/ci.sh
selftest pass "the template's runner moved (GATE_RUN=ci/run-local.sh): gate-wait moved with it" \
  '.sandbox.excludedCommands |= map(sub("^scripts/ci/(?<f>run-local|gate-wait)\\.sh"; "ci/\(.f).sh"))' ci/run-local.sh
selftest fail "the template's runner moved, gate-wait's exclusion left at scripts/ci/" '.' ci/run-local.sh
# A runner at the repository root puts gate-wait at ./gate-wait.sh (path.Dir is "."), as Go writes it.
selftest pass "a runner at the repository root (GATE_RUN=run-local.sh): gate-wait at ./" \
  '.sandbox.excludedCommands |= map(sub("^scripts/ci/gate-wait\\.sh"; "./gate-wait.sh"))' run-local.sh
selftest pass "a runner at the repository root (GATE_RUN=./run-local.sh): gate-wait at ./" \
  '.sandbox.excludedCommands |= map(sub("^scripts/ci/gate-wait\\.sh"; "./gate-wait.sh"))' ./run-local.sh
# Install writes the paths CLEANED (path.Clean), so the check reads GATE and GATE_RUN the same way.
selftest pass "GATE written ./scripts/ci/gate.sh: the settings name it scripts/ci/gate.sh" '.' '' ./scripts/ci/gate.sh
# A gate at the repository root keeps ./ (a bare gate.sh would be looked up on PATH), as install writes it.
selftest pass "a gate at the repository root (GATE=./gate.sh): the settings name ./gate.sh" \
  '(.sandbox.excludedCommands, .permissions.allow) |= map(sub("scripts/ci/gate\\.sh"; "./gate.sh"))' '' ./gate.sh
selftest fail "a gate at the repository root, excluded only as a bare gate.sh" \
  '(.sandbox.excludedCommands, .permissions.allow) |= map(sub("scripts/ci/gate\\.sh"; "gate.sh"))' '' ./gate.sh
selftest pass "GATE written scripts/ci//gate.sh, GATE_RUN ci/../scripts/ci/run-local.sh/" '.' ci/../scripts/ci/run-local.sh/ scripts/ci//gate.sh
# GATE="" runs the template's gate (build-change's fallback), so its exclusion is the one read (OPS-87).
selftest pass "GATE empty: the settings name scripts/ci/gate.sh, which build-change then runs" '.' '' ''
selftest fail "GATE empty, the default gate no longer excluded" '.sandbox.excludedCommands -= ["scripts/ci/gate.sh"]' '' ''
selftest fail "GATE absolute (/abs/gate.sh), the settings naming only the default gate" '.' '' /abs/gate.sh

check_settings "$st" > "$d/real"
cat "$d/real"; _fails=$((_fails + $(grep -c '^FAIL' "$d/real")))

# The lane's gate commands, self-tested at the template's paths whatever this project's are: each
# broken instruction fails, against settings that exclude both scripts bare and with arguments.
jq -n '{sandbox: {excludedCommands: ["scripts/ci/gate.sh", "scripts/ci/gate.sh *", "scripts/ci/gate-wait.sh", "scripts/ci/gate-wait.sh *"]}}' > "$d/lane.json"
lanes_at_template() {  # lanes_at_template SETTINGS FILE...: check_lane_gates with the template's gate paths
  (GATE=scripts/ci/gate.sh; GATE_RUN=scripts/ci/run-local.sh; check_lane_gates "$@")
}
lanetest() {  # lanetest pass|fail LABEL LINE...: instructions holding LINEs after the lane form
  _want=$1 _lbl=$2; shift 2
  { printf 'Lane: `scripts/ci/gate.sh -C <worktree>`, then `scripts/ci/gate-wait.sh -C <worktree>`.\n\n'
    printf '%s\n' "$@"; } > "$d/lane.md"
  n=$(lanes_at_template "$d/lane.json" "$d/lane.md" | grep -c '^FAIL')
  if [ "$_want" = pass ] && [ "$n" -eq 0 ]; then ok "lane self-test: $_lbl passes"
  elif [ "$_want" = fail ] && [ "$n" -gt 0 ]; then ok "lane self-test: $_lbl fails"
  else fail "lane self-test: $_lbl ($n FAIL line(s), want $_want)"; fi
}
lanetest pass "the lane form, a quick gate with -C, the bare gate" 'Run `scripts/ci/gate.sh -C <worktree> --quick` or `scripts/ci/gate.sh`.'
lanetest pass "a fenced block naming the gate, with a comment" '```bash' 'scripts/ci/gate.sh -C <worktree>   # the full gate' '```'
lanetest pass "a script of the same file name (tools/ci/gate.sh) is no gate" 'Run `cd x && sh tools/ci/gate.sh`.'
lanetest fail "a gate started by cd (S16's lanes)" 'Run `cd <worktree> && scripts/ci/gate.sh`.'
lanetest fail "a piped gate" 'Run `scripts/ci/gate.sh -C <worktree> | tail -n 40`.'
lanetest fail "a gate-wait started by cd" 'Then `cd <worktree>; scripts/ci/gate-wait.sh`.'
lanetest fail "a fenced cd && gate" '```' 'cd /abs/lane && scripts/ci/gate.sh' '```'
lanetest fail "a cd && gate span hard-wrapped across two lines" 'Run `cd <worktree> &&' '  scripts/ci/gate.sh` from the lane.'
lanetest pass "a fenced # comment naming a cd && gate" '```sh' '# not: cd <worktree> && scripts/ci/gate.sh' 'scripts/ci/gate.sh -C <worktree>' '```'
lanetest pass "a counter-example with the gate's path left out" 'Never `cd <worktree> && …`.'
lanetest pass "spans in two paragraphs are never joined" 'Run `cd <worktree>` first.' '' 'Then `scripts/ci/gate.sh`.'
lanetest pass "spans in two table rows are never joined" '| a | `cd <worktree>` |' '| b | `scripts/ci/gate-wait.sh` |'
lanetest fail "a table row that cds and names the gate" '| a | `cd <worktree>`, then `scripts/ci/gate.sh` |'
# A unit that changes directory and names the gate without -C fails, whatever the shell form.
lanetest fail "a block: cd on one line, the gate on the next" '```' 'cd <worktree>' 'scripts/ci/gate.sh' '```'
lanetest fail "a block: a backslash continuation after cd &&" '```bash' 'cd <worktree> && \' 'scripts/ci/gate.sh --quick' '```'
lanetest fail "a ~~~sh block: cd, then the gate" '~~~sh' 'cd /abs/lane' 'scripts/ci/gate.sh' '~~~'
lanetest fail "a paragraph: cd in one span, the gate in the next" 'Run `cd <worktree>`, then `scripts/ci/gate-wait.sh`.'
lanetest fail "a pushd before the gate" '```console' '$ pushd <worktree>' '$ scripts/ci/gate.sh' '```'
lanetest pass "a block that cds and runs the gate with -C" '```sh' 'cd <worktree>' 'scripts/ci/gate.sh -C <worktree>' '```'
lanetest pass "a counter-example marked $GATE_EXAMPLE (a block)" "$GATE_EXAMPLE" '```' 'cd <worktree> && scripts/ci/gate.sh' '```'
lanetest pass "a counter-example marked $GATE_EXAMPLE (a paragraph)" "$GATE_EXAMPLE" 'Never `cd <worktree> && scripts/ci/gate.sh`.'
lanetest fail "the mark covers one unit only" "$GATE_EXAMPLE" 'Never `cd <worktree> && scripts/ci/gate.sh`.' '' 'Run `cd <worktree> && scripts/ci/gate.sh`.'
lanetest fail "a tab between cd && and the gate" "Run \`cd <worktree> &&	scripts/ci/gate.sh\`."
lanetest fail "a \`\`\`Bash block (fail closed: a label not listed as prose reads as commands)" '```Bash' 'cd <worktree>' 'scripts/ci/gate.sh' '```'
lanetest pass "a \`\`\`Text block quoting gate-wait's hint (labels any case)" '```Text' 'NO RESULT: Start a gate in the FOREGROUND: cd <worktree> && scripts/ci/gate.sh (Bash timeout 600000).' '```'
lanetest fail "a \`\`\`shell-session block" '```shell-session' '$ cd <worktree> && scripts/ci/gate.sh' '```'
lanetest pass "a console block's lane form after its prompt" '```console' '$ scripts/ci/gate.sh -C <worktree>' '```'
lanetest pass "a text block quoting gate-wait's hint (not commands)" '```text' 'NO RESULT: Start a gate in the FOREGROUND: cd <worktree> && scripts/ci/gate.sh (Bash timeout 600000).' '```'
lanetest fail "the gate as ./scripts/ci/gate.sh (no entry names it)" 'Run `./scripts/ci/gate.sh --quick`.'
printf 'Run `scripts/ci/gate.sh`.\n' > "$d/nolane.md"
lanes_at_template "$d/lane.json" "$d/nolane.md" | grep -q '^FAIL no instruction gives the lane form' \
  && ok "lane self-test: instructions with no -C form fail" || fail "lane self-test: instructions with no -C form passed"
jq '.sandbox.excludedCommands -= ["scripts/ci/gate.sh *"]' "$d/lane.json" > "$d/nostar.json"
printf 'Lane: `scripts/ci/gate.sh -C <worktree>`.\n' > "$d/lane.md"
n=$(lanes_at_template "$d/nostar.json" "$d/lane.md" | grep -c '^FAIL')
[ "$n" -gt 0 ] && ok "lane self-test: the lane form fails once \`scripts/ci/gate.sh *\` leaves the settings" || fail "lane self-test: the lane form passed with no \`scripts/ci/gate.sh *\` entry"

# The real instructions: the Markdown agents load, the playbook and the conventions. The skills and
# agents are the model's copy: the project's, or the plugin's (STRIDAL_FW).
FW=${STRIDAL_FW:-$ROOT/.claude}
set -- "$FW"/skills/*/*.md "$FW"/agents/*.md
for f in "$ROOT/AGENTS.md" "$ROOT/CLAUDE.md" "$ROOT/docs/playbook.md" "$ROOT/docs/conventions.md"; do [ -f "$f" ] && set -- "$@" "$f"; done
check_lane_gates "$st" "$@" > "$d/lanes"
cat "$d/lanes"; _fails=$((_fails + $(grep -c '^FAIL' "$d/lanes")))

# ── The gh token health line (OPS-220), on fixtures only ─────────────────────────────────────
# GH_CONFIG_DIR is set on every run, so no path here reaches this machine's real hosts.yml: what the
# line says about that file is the session's to read, at session start. The fixture token's bytes
# must never reach the output, whatever the verdict.
# A subshell sets the variable as a caller would and sources lib.sh again, so this fails without its
# unset on any run. A subshell, not a child: a plugin's root is not exported.
_go=$(GH_CONFIG_DIR=$d/caller-set; . "$(dirname "$0")/lib.sh"; printf %s "${GH_CONFIG_DIR-cleared}" 2>&1)
[ "$_go" = cleared ] && ok "health gh-token: lib.sh clears a GH_CONFIG_DIR the caller set, so no check reads the real file" || fail "health gh-token: GH_CONFIG_DIR reached a check from its caller: $_go"
GHTOKEN=gho_FIXTUREnotAtoken0123456789
gh_line() {  # gh_line DIR: the library's line, in a subshell, so a plugin's unexported root still holds
  (. "$ROOT/.claude/lib/health.sh"; GH_CONFIG_DIR=$1; health_gh_token) 2>&1
}
ghcase() {  # ghcase VERDICT LABEL HOSTS-CONTENT
  _gd=$(mktemp -d "${TMPDIR:-/tmp}/ghcase.XXXXXX") || { fail "health gh-token: no fixture directory"; return; }
  printf '%b' "$3" > "$_gd/hosts.yml"
  _go=$(gh_line "$_gd"); rm -rf "$_gd"
  case $_go in
    *"$GHTOKEN"*|*QUOTEDFIXTURE*) fail "health gh-token: $2: the line printed the token" ;;
    "$1 "*) ok "health gh-token: $2 reads $1" ;;
    *) fail "health gh-token: $2: want $1, got: $_go" ;;
  esac
}
ghcase OK "a keyring login (hosts.yml names the account only)" 'github.com:\n    users:\n        fixture:\n    git_protocol: https\n    user: fixture\n'
ghcase OK "an empty file" ''
ghcase OK "an empty oauth_token key" 'github.com:\n    oauth_token: ""\n    user: fixture\n'
ghcase OK "a user whose name ends in token" 'github.com:\n    user: mytoken\n'
ghcase FAILED "gh's plain-text form" "github.com:\n    users:\n        fixture:\n            oauth_token: $GHTOKEN\n    oauth_token: $GHTOKEN\n    user: fixture\n"
ghcase FAILED "a quoted token value" 'github.com:\n    token: "QUOTEDFIXTURE"\n'
ghcase FAILED "a token's shape under another key" "github.com:\n    other: $GHTOKEN\n"
ghcase FAILED "a token's shape in a comment" "# was: $GHTOKEN\n"
_go=$(gh_line "$d/no-such-gh-dir")
case $_go in "OK no $d/no-such-gh-dir/hosts.yml "*) ok "health gh-token: no file reads OK, naming the file" ;; *) fail "health gh-token: no file: $_go" ;; esac
# A path that exists and cannot be read as a file: a CANNOT CHECK, on any machine and as any user.
mkdir -p "$d/gh-dir/hosts.yml"
_go=$(gh_line "$d/gh-dir")
case $_go in "CANNOT CHECK — could not read $d/gh-dir/hosts.yml"*) ok "health gh-token: an unreadable file says CANNOT CHECK, naming it, never OK" ;; *) fail "health gh-token: an unreadable file: $_go" ;; esac

# ── The sandbox-writes health line (OPS-220): its verdicts, on stubs and fixtures ────────────
# The line's real caller is session start (extensions.sh health), the one process that runs inside a
# real session's sandbox. This cannot prove the boundary: a whole-set run re-executes into a fresh HOME
# (lib.sh, bare_exec), and the gate runs with the sandbox off. So this holds what the line says for each
# answer the sandbox could give, and the session's own line reports what the sandbox did give.
# The stub takes a path the line asks about: a path that is not there would have answered for its parent
# once (a plugin project's hooks read as the writable .claude/), so it says "wrote" to catch that.
sw_line() {  # sw_line HOME REPO [WRITES [OTHER]]: the line, the probe stubbed, at fixture paths
  (. "$ROOT/.claude/lib/health.sh"
   HOME=$1; ROOT=$2; SW_WRITES=${3:-none}; SW_OTHER=${4:-none}
   CLAUDE_CONFIG_DIR=$SW_CFG; [ -n "$SW_CFG" ] || unset CLAUDE_CONFIG_DIR
   health_probe_write() {
     [ -e "$1" ] || { echo wrote; return 0; }
     case $1 in
       "$HOME") echo refused ;;
       "$SW_WRITES"|"$SW_WRITES"/*) echo wrote ;;
       "$SW_OTHER") echo "other: a stubbed answer" ;;
       *) echo refused ;;
     esac
   }
   health_sandbox_writes) 2>&1
}
SW_CFG=
_h=$d/sw/home; mkdir -p "$_h/.claude/hooks" "$_h/.claude/plugins/data" "$_h/.claude/plugins/cache"; : > "$_h/.claude/settings.json"
_r=$d/sw/repo; new_repo "$_r"; mkdir -p "$_r/.claude/hooks"; : > "$_r/.claude/settings.json"
_go=$(TMPDIR=/nonexistent/tmp; sw_line "$_h" "$_r")
case $_go in
  "OK a write was refused at: "*"($_h)"*"$_h/.claude/settings.json"*"$_h/.claude/plugins/data"*) ok "health sandbox-writes: all refused reads OK, naming what was refused" ;;
  *) fail "health sandbox-writes: all refused: $_go" ;;
esac
_go=$(TMPDIR=/nonexistent/tmp; sw_line "$_h" "$_r" "$_h/.claude/plugins/data")
case $_go in
  "FAILED a write went through at a plugin's data directory ($_h/.claude/plugins/data)"*) ok "health sandbox-writes: a path that took a write reads FAILED, naming it" ;;
  *) fail "health sandbox-writes: a path that took a write: $_go" ;;
esac
_go=$(TMPDIR=/nonexistent/tmp; sw_line "$_h" "$_r" none "$_h/.claude/hooks")
case $_go in
  "CANNOT CHECK — Claude's user hooks ($_h/.claude/hooks): other: a stubbed answer"*) ok "health sandbox-writes: an answer that is neither reads CANNOT CHECK, naming the path" ;;
  *) fail "health sandbox-writes: an answer that is neither: $_go" ;;
esac
mkdir -p "$d/sw/cache/data" "$d/sw/cache/cache"
_go=$(TMPDIR=/nonexistent/tmp; CLAUDE_CODE_PLUGIN_CACHE_DIR=$d/sw/cache; sw_line "$_h" "$_r" "$d/sw/cache/data")
case $_go in
  "FAILED a write went through at a plugin's data directory ($d/sw/cache/data)"*) ok "health sandbox-writes: CLAUDE_CODE_PLUGIN_CACHE_DIR moves the plugin's paths" ;;
  *) fail "health sandbox-writes: CLAUDE_CODE_PLUGIN_CACHE_DIR ignored: $_go" ;;
esac
# A path that is not there says nothing about that path: no verdict, whichever way its parent would go.
_p=$d/sw/plugin-project; new_repo "$_p"; mkdir -p "$_p/.claude"; : > "$_p/.claude/settings.json"
_go=$(TMPDIR=/nonexistent/tmp; sw_line "$_h" "$_p")
case $_go in
  "FAILED"*) fail "health sandbox-writes: a project with no .claude/hooks read FAILED: $_go" ;;
  "OK "*"not there: the main checkout's hooks"*) ok "health sandbox-writes: a project with no .claude/hooks reads no FAILED, and says that path is not there" ;;
  *) fail "health sandbox-writes: a project with no .claude/hooks: $_go" ;;
esac
case $_go in *"the main checkout's hooks ($_p"*) fail "health sandbox-writes: a path that is not there was listed as refused: $_go" ;; *) ok "health sandbox-writes: a path that is not there is never listed as refused" ;; esac
# This checkout's own hooks: the result alone, and the OPS-145 note only where they took a write.
_go=$(TMPDIR=/nonexistent/tmp; sw_line "$_h" "$_r")
case $_go in
  *OPS-145*) fail "health sandbox-writes: hooks that refused a write still name OPS-145: $_go" ;;
  *"; this checkout's own hooks: refused"*) ok "health sandbox-writes: this checkout's hooks that refuse a write read refused, with no OPS-145 note" ;;
  *) fail "health sandbox-writes: this checkout's hooks that refused: $_go" ;;
esac
_go=$(TMPDIR=/nonexistent/tmp; sw_line "$_h" "$_r" "$_r/.claude/hooks")
case $_go in
  *"; this checkout's own hooks: wrote (open until Stridal's OPS-145)"*) ok "health sandbox-writes: this checkout's hooks that take a write name OPS-145" ;;
  *) fail "health sandbox-writes: this checkout's hooks that took a write: $_go" ;;
esac
# A clone under the temporary directory: the sandbox allows that directory, so its paths prove nothing.
_go=$(TMPDIR=$_r; sw_line "$_h" "$_r" "$_r/.git/config")
case $_go in
  "OK "*"not tried, under the temporary directory"*"git's config"*) ok "health sandbox-writes: a repository under the temporary directory is not tried, and says so" ;;
  *) fail "health sandbox-writes: a repository under the temporary directory: $_go" ;;
esac
# OK means something was refused: with nothing refused it never reads OK, FAILED lines or not.
_go=$(TMPDIR=$d/sw; sw_line "$_h" "$_r")
case $_go in
  "NOT PROVEN "*) ok "health sandbox-writes: everything under the temporary directory, so nothing tried, reads NOT PROVEN" ;;
  *) fail "health sandbox-writes: nothing tried: $_go" ;;
esac
mkdir -p "$d/sw2/cfg/hooks" "$d/sw2/tmp/home"; : > "$d/sw2/cfg/settings.json"; new_repo "$d/sw2/tmp/repo"
_go=$(TMPDIR=$d/sw2/tmp; SW_CFG=$d/sw2/cfg; sw_line "$d/sw2/tmp/home" "$d/sw2/tmp/repo" "$d/sw2/cfg")
_go=$(printf '%s\n' "$_go" | sed -n '$p')
case $_go in
  "NOT PROVEN "*) ok "health sandbox-writes: FAILED lines with nothing refused end NOT PROVEN, not OK" ;;
  *) fail "health sandbox-writes: FAILED with nothing refused ends: $_go" ;;
esac
# The real probe, and the line with no sandbox to prove: never OK, and nothing left behind.
_go=$(mkdir -p "$d/sw-home" && (. "$ROOT/.claude/lib/health.sh"; health_probe_write "$d/sw-home"))
[ "$_go" = wrote ] && [ -z "$(ls -A "$d/sw-home")" ] && ok "health sandbox-writes: the probe reports a directory that takes a write, and leaves nothing there" || fail "health sandbox-writes: the probe on a writable directory: $_go; holds: $(ls -A "$d/sw-home")"
_go=$( (. "$ROOT/.claude/lib/health.sh"; health_probe_write "$d/sw-home/no/such/hooks") )
[ "$_go" != wrote ] && [ "$_go" != refused ] && [ ! -e "$d/sw-home/no" ] && ok "health sandbox-writes: the probe gives no verdict on a path that is not there, and creates nothing" || fail "health sandbox-writes: the probe on a missing path: $_go"
_go=$( (. "$ROOT/.claude/lib/health.sh"; HOME=$d/sw-home; health_sandbox_writes) 2>&1)
case $_go in
  "NOT PROVEN $d/sw-home took a write"*"cannot tell"*) ok "health sandbox-writes: a home that takes a write reads NOT PROVEN, says it cannot tell why, and never reads OK" ;;
  *) fail "health sandbox-writes: a home that takes a write: $_go" ;;
esac
(. "$ROOT/.claude/lib/health.sh"
 health_sandbox_refused "sh: 1: cannot create /x: Operation not permitted" && health_sandbox_refused "(eval):1: operation not permitted: /x" && health_sandbox_refused "cannot create /x: Read-only file system" && ! health_sandbox_refused "cannot create /x: Permission denied") \
  && ok "health sandbox-writes: only the sandbox's own errors read as refused (macOS, Linux)" || fail "health sandbox-writes: a refusal was misread"
finish

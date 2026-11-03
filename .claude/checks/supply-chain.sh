#!/bin/sh
# Dependency hygiene (item 11 of the change process):
#   - a dependency-update config holds each update back until the release has aged: every
#     Dependabot entry has `cooldown: default-days: N`, or renovate.json has "minimumReleaseAge";
#     N at least SUPPLY_MIN_AGE_DAYS (default 3);
#   - the scheduled dependency audit exists (.github/workflows/dependency-audit.yml, on a schedule and
#     on demand), and its health line reports it: ADVISORIES on a failed run, CANNOT CHECK offline;
#   - the audit's tools are versions, not @latest, and each tool line has a listed form (OPS-222): the
#     framework's own repository (framework/internal/template decides, as a project may own a
#     template/.claude/) and its template/ FAIL on any other. A project only gets a note: `stridal
#     update` never touches its copy of that workflow, so a check it updates must not fail on a file
#     it cannot fix. pnpm is named, not pinned (the workflow's header says why).
# Raising a pin when a tool's release matters: **Nothing. You.** Dependabot cannot see a `run:` line.
# The secret scan is a gate step (scripts/ci/run-local.sh), falsified by checks/gate.sh.
. "$(dirname "$0")/lib.sh"
need jq

min=${SUPPLY_MIN_AGE_DAYS:-3}
d=$(scratch)

# ages DIR: prints ok/FAIL lines for the update config in DIR.
ages() {
  if [ -f "$1/.github/dependabot.yml" ]; then
    awk -v min="$min" '
      /^[[:space:]]*-[[:space:]]*package-ecosystem:/ { if (eco != "") report(); eco = $0; sub(/.*package-ecosystem:[[:space:]]*/, "", eco); gsub(/"/, "", eco); days = ""; next }
      /^[[:space:]]*default-days:/ { days = $2 }
      function report() { if (days == "") printf "FAIL dependabot %s has no cooldown default-days (a minimum release age)\n", eco
                          else if (days + 0 < min) printf "FAIL dependabot %s cooldown is %s day(s), under %s\n", eco, days, min
                          else printf "ok   dependabot %s waits %s days before proposing a release\n", eco, days }
      END { if (eco != "") report(); else print "FAIL .github/dependabot.yml has no update entry" }' "$1/.github/dependabot.yml"
  elif [ -f "$1/renovate.json" ]; then
    age=$(jq -r '.minimumReleaseAge // empty' "$1/renovate.json" 2>/dev/null)
    n=$(printf '%s' "$age" | sed -n 's/^\([0-9][0-9]*\) days\{0,1\}$/\1/p')
    if [ -z "$age" ]; then echo "FAIL renovate.json has no minimumReleaseAge"
    elif [ -z "$n" ] || [ "$n" -lt "$min" ]; then echo "FAIL renovate.json minimumReleaseAge is '$age', want at least '$min days'"
    else echo "ok   renovate waits $age before proposing a release"; fi
  else
    echo "FAIL no dependency-update config (.github/dependabot.yml or renovate.json)"
  fi
}

# audit_unpinned FILE: one line per unpinned tool in the file's audit block; none when all are held.
# Tokens, not lines: a second tool on a pinned line has its own verdict. Comments say nothing.
audit_unpinned() {
  sed -n '/# audit: begin/,/# audit: end/p' "$1" | sed -E 's/(^|[[:space:]])#.*$//' \
    | sed -e ':a' -e '/\\$/{N' -e 's/\\\n//' -e 'ta' -e '}' > "$d/pin.block"
  # An allowlist, not a list of bad spellings: every arm of the block's case, and any other `run <tool>
  # "$dir"` line, is one of these forms, so a new tool, or a listed one run another way, is not vouched
  # for until it is added here. An arm is read whole: it can span lines.
  _ver='v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?'
  _run='^([^[:space:]]+\) )?run '
  _end='( ;;)? ?$'
  awk '
    /(^|[[:space:]])esac([[:space:];]|$)/ { if (arm != "") print arm; arm = ""; inc = 0; next }
    /(^|[[:space:]])case[[:space:]]/ { inc = 1; next }
    inc { arm = arm " " $0; if ($0 ~ /;;[[:space:]]*$/) { print arm; arm = "" } next }
    /(^|[[:space:]])run [[:alnum:]_-]+ "\$dir"/ { print }
  ' "$d/pin.block" | sed -E 's/[[:space:]]+/ /g; s/^ //' | grep -vE \
    -e "$_run"'govulncheck "\$dir" go run golang\.org/x/vuln/cmd/govulncheck@'"$_ver"' \./\.\.\.'"$_end" \
    -e "$_run"'npm "\$dir" npm audit --omit=dev --audit-level=high'"$_end" \
    -e "$_run"'pnpm "\$dir" sh -c '\''corepack enable \&\& pnpm audit --prod --audit-level high'\'"$_end" \
    -e "$_run"'pip-audit "\$dir" pipx run --spec pip-audit==[0-9]+(\.[0-9]+)+ pip-audit (-r "\$\(basename "\$m"\)"|\.)'"$_end"
  # Any line that runs a package by name, one verdict per tool@version: a full version, not latest, a
  # branch or @v1. Only those lines: a credential in a URL or a mail address has an @ and runs nothing.
  grep -E '(go (run|install)|pipx|npx|uvx|corepack|pnpm|npm|yarn)[[:space:]]' "$d/pin.block" \
    | grep -oE "[[:alnum:]_./-]+@[^[:space:]\"';)]*" | while IFS= read -r _t; do
    printf '%s\n' "${_t##*@}" | grep -Eq "^$_ver\$" || printf '%s\n' "$_t"
  done
  # The same tools with no @ to judge.
  grep -oE "golang\.org/x/vuln/cmd/govulncheck[^[:space:]\"';)]*" "$d/pin.block" | grep -v '@'
  grep -oE 'pipx run( --spec [^[:space:]]+)?' "$d/pin.block" | grep -vE -- '--spec [[:alnum:]_.-]+==[0-9]+(\.[0-9]+)+$'
  return 0
}
# pin_verdict ROOT: ok, FAIL or note, one line. Only the framework's own template/ fails.
pin_verdict() {
  _pv=$(audit_unpinned "$1/.github/workflows/dependency-audit.yml" | sort -u | tr '\n' ';')
  if [ -z "$_pv" ]; then echo "ok   dependency-audit.yml names a version of govulncheck and pip-audit, and no @latest"
  elif [ -d "$1/framework/internal/template" ] || { [ "${1##*/}" = template ] && [ -d "$1/../framework/internal/template" ]; }; then echo "FAIL dependency-audit.yml runs an unpinned tool; name a released version: $_pv"
  else echo "note this project's dependency-audit.yml runs an unpinned tool ($_pv): stridal update does not touch that file, so this is not a failure. The template's copy has the pinned lines."; fi
}

# Self-test.
mkdir -p "$d/a/.github" "$d/b/.github" "$d/c" "$d/e"
printf 'version: 2\nupdates:\n  - package-ecosystem: "npm"\n    directory: "/"\n    cooldown:\n      default-days: 7\n  - package-ecosystem: "gomod"\n    directory: "/"\n' > "$d/a/.github/dependabot.yml"
ages "$d/a" | grep -q '^FAIL dependabot gomod has no cooldown' && ok "self-test: a Dependabot entry with no cooldown fails" || fail "self-test: a Dependabot entry with no cooldown passed"
printf 'version: 2\nupdates:\n  - package-ecosystem: "npm"\n    cooldown:\n      default-days: 1\n' > "$d/b/.github/dependabot.yml"
ages "$d/b" | grep -q '^FAIL' && ok "self-test: a one-day cooldown fails" || fail "self-test: a one-day cooldown passed"
printf '{"extends":["config:recommended"]}\n' > "$d/c/renovate.json"
ages "$d/c" | grep -q '^FAIL' && ok "self-test: renovate.json with no minimumReleaseAge fails" || fail "self-test: renovate.json with no minimumReleaseAge passed"
printf '{"minimumReleaseAge":"7 days"}\n' > "$d/c/renovate.json"
ages "$d/c" | grep -q '^FAIL' && fail "self-test: renovate.json with 7 days failed" || ok "self-test: renovate.json with minimumReleaseAge 7 days passes"
ages "$d/e" | grep -q '^FAIL no dependency-update config' && ok "self-test: no update config at all fails" || fail "self-test: no update config passed"

ages "$ROOT" > "$d/real"; cat "$d/real"; _fails=$((_fails + $(grep -c '^FAIL' "$d/real")))

# The scheduled audit and its reader.
wf="$ROOT/.github/workflows/dependency-audit.yml"
if [ -f "$wf" ]; then
  grep -qE '^[[:space:]]*schedule:' "$wf" && grep -qE '^[[:space:]]*workflow_dispatch:' "$wf" \
    && ok "dependency-audit.yml runs on a schedule and on demand" || fail "dependency-audit.yml needs both schedule: and workflow_dispatch: triggers"
  # It audits every tracked manifest at any depth, not only the root's (OPS-8 rehearsal: a Go
  # module in framework/ was never audited). The block between its markers runs, dry, in a repo
  # whose manifests are nested.
  sed -n '/# audit: begin/,/# audit: end/p' "$wf" | sed 's/^          //' > "$d/audit.sh"
  if [ -s "$d/audit.sh" ]; then
    new_repo "$d/m"
    mkdir -p "$d/m/framework" "$d/m/web" "$d/m/svc/api" "$d/m/framework/x/testdata" "$d/m/.claude/evals/r/before"
    : > "$d/m/framework/go.mod"; : > "$d/m/web/package-lock.json"; : > "$d/m/svc/api/requirements.txt"; : > "$d/m/framework/x/testdata/go.mod"; : > "$d/m/.claude/evals/r/before/go.mod"
    git -C "$d/m" add -A && git -C "$d/m" commit -qm m
    out=$(cd "$d/m" && AUDIT_DRY_RUN=1 sh "$d/audit.sh" 2>&1)
    case "$out" in *"govulncheck framework "*"npm web "*|*"npm web "*"govulncheck framework "*) ok "the audit finds manifests below the root (framework/go.mod, web/package-lock.json)" ;; *) fail "the audit missed nested manifests: $out" ;; esac
    case "$out" in *"pip-audit svc/api "*) ok "the audit finds a nested requirements.txt" ;; *) fail "the audit missed svc/api/requirements.txt: $out" ;; esac
    case "$out" in *testdata* | *evals*) fail "the audit ran on a test fixture's manifest: $out" ;; *) ok "the audit skips test fixtures (testdata/, the evals' cases)" ;; esac
    new_repo "$d/empty"; out=$(cd "$d/empty" && AUDIT_DRY_RUN=1 sh "$d/audit.sh" 2>&1)
    case "$out" in "no dependency manifest"*) ok "a repo with no manifest says so" ;; *) fail "a repo with no manifest printed: $out" ;; esac
    # The pins: the matcher, in both directions.
    gv=golang.org/x/vuln/cmd/govulncheck
    pinned() { printf '# audit: begin\n%s\n# audit: end\n' "$2" > "$d/pin.yml"; [ -z "$(audit_unpinned "$d/pin.yml")" ] && ok "pin: passes: $1" || fail "pin: $1 read as unpinned: $(audit_unpinned "$d/pin.yml")"; }
    unpinned() { printf '# audit: begin\n%s\n# audit: end\n' "$2" > "$d/pin.yml"; [ -n "$(audit_unpinned "$d/pin.yml")" ] && ok "pin: fails: $1" || fail "pin: $1 passed"; }
    pinned "a full version" "go.mod) run govulncheck \"\$dir\" go run $gv@v1.9.0 ./... ;;"
    pinned "go install at the end of a line" "go install $gv@v1.9.0"
    pinned "a pin before a closing quote" "sh -c 'go run $gv@v1.9.0'"
    pinned "a pseudo-version" "go run $gv@v0.0.0-20261010193011-f71dc92da45e ./..."
    pinned "a comment naming govulncheck" '# govulncheck is held to a version, never @latest'
    pinned "a trailing comment naming @latest" "go run $gv@v1.9.0 ./... # not example.com/x@latest"
    pinned "pip-audit by --spec, on a requirements file" 'requirements*.txt) run pip-audit "$dir" pipx run --spec pip-audit==2.10.1 pip-audit -r "$(basename "$m")" ;;'
    pinned "pip-audit by --spec, on a project" 'pyproject.toml) run pip-audit "$dir" pipx run --spec pip-audit==2.10.1 pip-audit . ;;'
    pinned "npm's own audit" 'package-lock.json) run npm "$dir" npm audit --omit=dev --audit-level=high ;;'
    pinned "pnpm's line, which names no version on purpose" "pnpm-lock.yaml) run pnpm \"\$dir\" sh -c 'corepack enable && pnpm audit --prod --audit-level high' ;;"
    pinned "a clone URL with a credential" 'git clone https://ci-user@example.com/r.git'
    pinned "an scp-style remote" 'git clone git@github.com:o/r.git'
    pinned "a mail address" 'curl -u me@example.com https://example.com/x'
    unpinned "a new tool's line, in no listed form" 'run trivy "$dir" trivy fs . ;;'
    unpinned "a listed tool run another way" 'run npm "$dir" npx audit-ci@9.0.0 ;;'
    unpinned "a tool@latest through npx" 'npx audit-ci@latest'
    unpinned "pipx run on a line that is no tool line" 'pipx run safety check'
    # Every arm of the case is a listed form, with continuations joined.
    pinned "a listed arm split over a continuation" 'case $x in
  package-lock.json) run npm "$dir" npm audit \
       --omit=dev --audit-level=high ;;
esac'
    pinned "a listed arm with its body on its own line" 'case $x in
  package-lock.json)
    run npm "$dir" npm audit --omit=dev --audit-level=high ;;
esac'
    unpinned "an arm that names no tool line" 'case $x in
  go.mod) curl -s https://example.com/x | sh ;;
esac'
    unpinned "an arm whose body is on its own line" 'case $x in
  go.mod)
    curl -s https://example.com/x | sh ;;
esac'
    unpinned "a pinned tool run outside the listed form" "case \$x in
  go.mod) go run $gv@v1.9.0 ./... ;;
esac"
    unpinned "a second command joined by a continuation" 'case $x in
  package-lock.json) run npm "$dir" npm audit --omit=dev --audit-level=high \
       && curl -s https://example.com/x | sh ;;
esac'
    unpinned "a last arm with no ;;" 'case $x in
  package-lock.json) run npm "$dir" npm audit --omit=dev --audit-level=high ;;
  *) curl -s https://example.com/x | sh
esac'
    pinned "the runner's own \"\$@\"" 'run() { ( cd "$2" && shift 2 && "$@" ) || failed=1; }'
    unpinned "@latest" "go run $gv@latest ./..."
    unpinned "@v1, a moving query" "go run $gv@v1 ./..."
    unpinned "@master" "go run $gv@master ./..."
    unpinned "govulncheck with no version" "go run $gv ./..."
    unpinned "an installed govulncheck on its tool line" 'go.mod) run govulncheck "$dir" govulncheck ./... ;;'
    unpinned "a second tool unpinned on a pinned line" "go run $gv@v1.9.0 ./... && go run example.com/lint@latest ./..."
    unpinned "pipx run pip-audit with no version" 'run pip-audit "$dir" pipx run pip-audit . ;;'
    unpinned "another tool through pipx on a pinned line" 'run pip-audit "$dir" pipx run --spec pip-audit==2.10.1 pip-audit . && pipx run safety check ;;'
    unpinned "--spec with no version" 'run pip-audit "$dir" pipx run --spec pip-audit pip-audit . ;;'
    unpinned "--spec with a range" 'run pip-audit "$dir" pipx run --spec pip-audit>=2 pip-audit . ;;'
    unpinned "pnpm at @latest" "run pnpm \"\$dir\" sh -c 'corepack pnpm@latest audit'"
    # Who fails: a fixture project with the old line stays green with a note, and only this repository
    # and its template fail. The project has no go.mod: the line's own use is not what is judged.
    old="go.mod) run govulncheck \"\$dir\" go run $gv@latest ./... ;;"
    mkdir -p "$d/pinp/.github/workflows" "$d/pinf/framework/internal/template" "$d/pinf/.github/workflows" "$d/pinf/template/.github/workflows"
    printf '# audit: begin\n%s\n# audit: end\n' "$old" | tee "$d/pinp/.github/workflows/dependency-audit.yml" "$d/pinf/.github/workflows/dependency-audit.yml" > "$d/pinf/template/.github/workflows/dependency-audit.yml"
    case "$(pin_verdict "$d/pinp")" in "note this project's"*"stridal update"*) ok "pin: a project on the old line gets a named note, and no failure" ;; *) fail "pin: a project on the old line read: $(pin_verdict "$d/pinp")" ;; esac
    case "$(pin_verdict "$d/pinf")" in FAIL*) ok "pin: this repository's root fails on @latest" ;; *) fail "pin: the framework's root passed @latest: $(pin_verdict "$d/pinf")" ;; esac
    case "$(pin_verdict "$d/pinf/template")" in FAIL*) ok "pin: template/ fails on @latest" ;; *) fail "pin: template/ passed @latest: $(pin_verdict "$d/pinf/template")" ;; esac
    # A project may own a template/.claude/ of its own: only the framework's source decides.
    mkdir -p "$d/pino/.github/workflows" "$d/pino/template/.claude" "$d/pino/template/.github/workflows"
    cp "$d/pinp/.github/workflows/dependency-audit.yml" "$d/pino/.github/workflows/"; cp "$d/pinp/.github/workflows/dependency-audit.yml" "$d/pino/template/.github/workflows/"
    case "$(pin_verdict "$d/pino")" in "note this project's"*) ok "pin: a project with its own template/ on the old line gets the note" ;; *) fail "pin: a project with its own template/ read: $(pin_verdict "$d/pino")" ;; esac
    case "$(pin_verdict "$d/pino/template")" in "note this project's"*) ok "pin: ...and so does that template/ itself" ;; *) fail "pin: that project's template/ read: $(pin_verdict "$d/pino/template")" ;; esac
    # The parent's framework/ speaks only for a directory called template/: not for a project beside it.
    mkdir -p "$d/pins/framework/internal/template" "$d/pins/proj/.github/workflows"
    cp "$d/pinp/.github/workflows/dependency-audit.yml" "$d/pins/proj/.github/workflows/"
    case "$(pin_verdict "$d/pins/proj")" in "note this project's"*) ok "pin: a project beside a framework/internal/template gets the note" ;; *) fail "pin: a project beside a framework/internal/template read: $(pin_verdict "$d/pins/proj")" ;; esac
    # The real file.
    pin_verdict "$ROOT" > "$d/pin.real"; cat "$d/pin.real"; _fails=$((_fails + $(grep -c '^FAIL' "$d/pin.real")))
    case $(cat "$d/audit.sh") in *"pnpm audit"*) echo "note pnpm via corepack names no version here: a project's packageManager key names its own, and the workflow's header says why no one pin fits" ;; esac
  else
    fail "dependency-audit.yml has no '# audit: begin' … '# audit: end' block (the audit this check runs)"
  fi
else
  fail "no .github/workflows/dependency-audit.yml (the scheduled dependency audit)"
fi
h="$ROOT/.claude/health/dependency-audit.sh"
if [ -f "$h" ]; then
  out=$(CONTEXT_OFFLINE=1 sh "$h"); case "$out" in "CANNOT CHECK — offline"*|"OK no "*) ok "the advisories health line makes no network call offline" ;; *) fail "health line offline said: $out" ;; esac
  mkdir -p "$d/bin" "$d/h/.claude/health" "$d/h/.github/workflows"; cp "$h" "$d/h/.claude/health/"; : > "$d/h/.github/workflows/dependency-audit.yml"
  printf '#!/bin/sh\necho "$GH_RUNS"\n' > "$d/bin/gh"; chmod +x "$d/bin/gh"
  runs='[{"conclusion":"failure","status":"completed","createdAt":"2099-01-05T06:17:00Z","headSha":"abcdef0123456","url":"https://x/1"}]'
  out=$(GH_RUNS=$runs CONTEXT_OFFLINE= PATH="$d/bin:$PATH" sh "$d/h/.claude/health/dependency-audit.sh")
  case "$out" in ADVISORIES*"high severity"*"abcdef012"*) ok "a failed audit reads ADVISORIES, naming the run's commit" ;; *) fail "failed audit read as: $out" ;; esac
  out=$(GH_RUNS='[{"conclusion":"success","status":"completed","createdAt":"2020-01-05T06:17:00Z","headSha":"abcdef0123456","url":"u"}]' CONTEXT_OFFLINE= PATH="$d/bin:$PATH" sh "$d/h/.claude/health/dependency-audit.sh")
  case "$out" in STALE*) ok "an audit more than two weeks old reads STALE" ;; *) fail "old audit read as: $out" ;; esac
  out=$(GH_RUNS='[]' CONTEXT_OFFLINE= PATH="$d/bin:$PATH" sh "$d/h/.claude/health/dependency-audit.sh")
  case "$out" in "NEVER RAN"*) ok "no audit on record reads NEVER RAN" ;; *) fail "no runs read as: $out" ;; esac
else
  fail "no .claude/health/dependency-audit.sh (the advisories health line)"
fi
finish

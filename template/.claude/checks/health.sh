#!/bin/sh
# Health lines run per their own #! line (P1.8, B4): session-start runs them through
# `.claude/extensions.sh health`, which must never force a bash script through sh (dash on Ubuntu,
# where bash-only syntax is a syntax error and the line reads as a broken subject). Fixtures:
#   - a bash-only line (`[[ ]]`, and it refuses to run in POSIX mode, which is what bash invoked as
#     `sh` is, so the fixture fails on macOS too if it is forced through sh);
#   - a line whose #! names an interpreter only this check provides (proves the #! is honoured, on
#     any platform);
#   - a line with no #! (runs under sh), one whose interpreter is missing (CANNOT CHECK, by name),
#     and one that exits non-zero (CANNOT CHECK, never silence).
# Run with the host shell AND, where it is installed, under dash itself.
. "$(dirname "$0")/lib.sh"
need git bash awk

d=$(scratch)
R="$d/p"; new_repo "$R"
mkdir -p "$R/.claude/lib" "$R/.claude/health" "$d/bin"
cp "$ROOT/.claude/lib/conf.sh" "$ROOT/.claude/lib/modules.sh" "$ROOT/.claude/lib/health.sh" "$R/.claude/lib/"
cp "$ROOT/.claude/extensions.sh" "$R/.claude/"
# The model's own lines run with nothing of theirs in .claude/health/, and with no project's lines at
# all (OPS-220). The token line reads only the fixture: CONTEXT_OFFLINE keeps it off the real file.
mkdir -p "$d/gh"; printf 'github.com:\n    user: fixture\n' > "$d/gh/hosts.yml"
out=$(cd "$R" && GH_CONFIG_DIR="$d/gh" sh .claude/extensions.sh health 2>&1)
case "$out" in *"- Health: gh-token-file"*"OK no token in $d/gh/hosts.yml"*) ok "the model's gh-token-file line runs from extensions.sh, with no file in .claude/health/" ;; *) fail "gh-token-file line: $out" ;; esac
# model_verdict NAME: the last line printed under NAME's heading in $out. model_line prints the heading
# before it runs anything, so the heading alone proves nothing: a function that is gone still has one.
# The last line, as sandbox-writes prints a FAILED line per path before the line that sums them.
model_verdict() {
  printf '%s\n' "$out" | awk -v h="- Health: $1" '$0 == h { on = 1; next } /^- Health: / { on = 0 } on { sub(/^ +/, ""); last = $0 } END { print last }'
}
case "$(model_verdict sandbox-writes)" in "OK a write was refused at: "*|"NOT PROVEN "*) ok "the model's sandbox-writes line runs from extensions.sh and gives its verdict, with no file in .claude/health/" ;; *) fail "sandbox-writes line: $out" ;; esac
# A git this check runs on may print what the line cannot read; that verdict is honest. A function
# that is gone says CANNOT CHECK too, naming the function, and must still fail here.
case "$(model_verdict git-floor)" in "OK git "*|"FAILED git "*|"CANNOT CHECK — git --version"*) ok "the model's git-floor line runs from extensions.sh and gives its verdict, with no file in .claude/health/" ;; *) fail "git-floor line: $out" ;; esac
out=$(cd "$R" && sh .claude/extensions.sh health 2>&1)
case "$out" in *"CANNOT CHECK — offline: under the checks this machine's hosts.yml is not read"*) ok "under the checks, with no GH_CONFIG_DIR, the token line reads no real file and says so" ;; *) fail "the token line under the checks with no GH_CONFIG_DIR: $out" ;; esac
mv "$R/.claude/lib/health.sh" "$d/health.sh.kept"
out=$(cd "$R" && sh .claude/extensions.sh health 2>&1)
case "$out" in *"- Health: gh-token-file"*"CANNOT CHECK — .claude/lib/health.sh is missing"*) ok "with no lib/health.sh the model's lines say CANNOT CHECK, by name" ;; *) fail "no lib/health.sh: $out" ;; esac
mv "$d/health.sh.kept" "$R/.claude/lib/health.sh"
cat > "$R/.claude/health/bashonly.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -o posix ]]; then echo "FAILED forced through sh (bash in POSIX mode)"; exit 0; fi
arr=(one two); echo "OK bash-only line ran under bash (${#arr[@]} items)"
EOF
printf '#!/usr/bin/env fakeinterp\nanything\n' > "$R/.claude/health/fake.sh"
printf '#!/bin/sh\necho "fakeinterp ran $1"\n' > "$d/bin/fakeinterp"; chmod +x "$d/bin/fakeinterp"
printf 'echo "OK plain line"\n' > "$R/.claude/health/plain.sh"
printf '#!/usr/bin/env no-such-interpreter-here\necho never\n' > "$R/.claude/health/missing.sh"
printf 'echo "half a verdict"\nexit 4\n' > "$R/.claude/health/broken.sh"

for shell in sh dash; do
  command -v "$shell" >/dev/null 2>&1 || { ok "SKIPPED under $shell: not installed (CI's Ubuntu runner has it as sh)"; continue; }
  out=$(cd "$R" && PATH="$d/bin:$PATH" "$shell" .claude/extensions.sh health 2>&1)
  case "$out" in *"OK bash-only line ran under bash (2 items)"*) ok "[$shell] a bash health line runs under bash, not forced through sh" ;; *) fail "[$shell] bash-only line: $(printf '%s' "$out" | grep -A1 bashonly)" ;; esac
  case "$out" in *"fakeinterp ran $R/.claude/health/fake.sh"*) ok "[$shell] a line runs under the interpreter its #! names" ;; *) fail "[$shell] #! not honoured: $(printf '%s' "$out" | grep -A1 'Health: fake')" ;; esac
  case "$out" in *"OK plain line"*) ok "[$shell] a line with no #! runs under sh" ;; *) fail "[$shell] plain line: $out" ;; esac
  case "$out" in *"CANNOT CHECK — $R/.claude/health/missing.sh needs no-such-interpreter-here"*) ok "[$shell] a missing interpreter is CANNOT CHECK, by name" ;; *) fail "[$shell] missing interpreter: $(printf '%s' "$out" | grep -A1 'Health: missing')" ;; esac
  case "$out" in *"half a verdict"*"CANNOT CHECK — .claude/health/broken.sh exited 4"*) ok "[$shell] a line that exits non-zero keeps its output and says CANNOT CHECK" ;; *) fail "[$shell] broken line: $(printf '%s' "$out" | grep -A2 'Health: broken')" ;; esac
done
finish

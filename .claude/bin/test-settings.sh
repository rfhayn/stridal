#!/usr/bin/env bash
# Self-test for .claude/settings.json's dispatcher rules (#453). The kit's own; not copied to new projects.
# Run: bash .claude/bin/test-settings.sh (from any cwd). Reads settings.json only; runs none of the commands.
#
# A Bash command a pass runs without a prompt needs: (1) a matching allow rule, (2) no matching ask or deny rule (they
# beat allow), and (3) for a command that fails inside the sandbox, a sandbox.excludedCommands match, so it runs outside.
# Claude's Bash rule is a glob over the whole command text where `*` matches anything, which `[[ == ]]` reproduces.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
S=${SETTINGS_UNDER_TEST:-$here/../settings.json}
total=0; fail=0
bad() { fail=$((fail+1)); echo "FAIL $1"; }
jq empty "$S" || { echo "FAIL settings.json is not valid JSON"; exit 1; }

# rules KEY: the Bash patterns of permissions.<KEY> (or sandbox.excludedCommands for "excluded"), one per line.
rules() {
  case "$1" in
    excluded) jq -r '.sandbox.excludedCommands[]?' "$S" ;;
    *) jq -r --arg k "$1" '.permissions[$k][]? | select(startswith("Bash(") and endswith(")")) | .[5:-1]' "$S" ;;
  esac
}
# matches KEY COMMAND: 0 when some rule of KEY matches the command.
matches() {
  local p
  while IFS= read -r p; do
    # shellcheck disable=SC2053  # the unquoted right side is the glob on purpose
    [[ $2 == $p ]] && return 0
  done < <(rules "$1")
  return 1
}
expect() { # expect "name" KEY COMMAND yes|no
  total=$((total+1))
  if matches "$2" "$3"; then got=yes; else got=no; fi
  [ "$got" = "$4" ] || bad "$1: '$3' ${2}-match is $got, want $4"
}

# 1. Every command named under Why of #453, as a pass runs it: allowed, and not asked about or denied.
why=(
  "ps -axo command="
  "bash .claude/bin/dispatch-next.sh --name-key"
  "bash .claude/bin/dispatch-next.sh --list-now --owner rfhayn --project 4"
  "bash .claude/bin/dispatch-next.sh --why 453 --owner rfhayn --project 4"
  "bash .claude/bin/dispatch-next.sh --owner rfhayn --project 4"
  "gh api graphql --paginate -f owner=rfhayn -F number=4 -f query=query{x}"
  "gh project field-list 4 --owner rfhayn"
  "bash .claude/bin/session.sh open feat 453-x --key stridal --report-to dispatch-stridal"
  "bash .claude/bin/session.sh watch 453-x --timeout 3600"
)
# The rest of a pass from an idle Now column to an armed watch (SKILL.md sections 1 to 4).
pass=(
  "bash .claude/bin/token-expiry.sh --state /x/agent-token"
  "gh api user --jq .login"
  "gh label create agent:working --force"
  "gh label create agent:blocked --force"
  "gh issue list --state all --label agent:working --json number,title,state,labels"
  "gh issue view 453 --json title,url,comments"
  "gh issue comment 453 --body-file /x/c.md"
  "gh issue edit 453 --add-label agent:working"
  "gh pr list --state all --head fix/453-x --json number,state,labels"
  "gh pr checks 9 --json name,bucket,link"
  "gh pr update-branch 9"
  "gh api repos/{owner}/{repo}/compare/main...abc --jq .behind_by"
  "gh api repos/{owner}/{repo}/rules/branches/main --jq ."
  "git fetch origin main"
  "git worktree list"
)
for c in "${why[@]}" "${pass[@]}"; do
  expect "allowed" allow "$c" yes
  expect "not asked" ask "$c" no
  expect "not denied" deny "$c" no
done

# 2. What fails inside the sandbox runs outside it: ps (operation not permitted), the scripts that call gh over TLS
# (x509 OSStatus -26276), gh itself, and the terminal drivers.
for c in "ps -axo command=" "bash .claude/bin/dispatch-next.sh --list-now --owner o --project 4" \
  "bash .claude/bin/token-expiry.sh --state /x" "gh api graphql -f query=query{x}" "gh project field-list 4 --owner o" \
  "bash .claude/bin/session.sh open feat x" "bash .claude/bin/session.sh watch x --timeout 3600"; do
  expect "excluded from the sandbox" excluded "$c" yes
done

# 3. The deny rules: every one that existed before #453 is still there, word for word (none removed or narrowed), and
# the approval label, a mutation over GraphQL and the rulesets stay refused.
baseline=(
  'Read(./.env)' 'Read(./.env.*)' 'Read(./**/*.pem)' 'Read(./secrets/**)' 'Read(~/.ssh/**)' 'Read(~/.aws/**)'
  'Read(~/.git-credentials)' 'Read(~/.netrc)' 'Read(~/.npmrc)' 'Edit(./PERSONAL_DATA/**)' 'Read(./PERSONAL_DATA/**)'
  'Bash(gh pr merge * --admin*)' 'Bash(gh pr merge --admin*)' 'Bash(gh repo delete*)' 'Bash(gh api *rulesets*)'
  'Bash(git push origin main*)' 'Bash(git push origin HEAD:main*)' 'Bash(git push --force origin main*)'
  'Bash(git push * main)' 'Bash(git push * main *)' 'Bash(git push * +main)' 'Bash(git push * *:main)'
  'Bash(git push * *:refs/heads/main)' 'Bash(gh * --body-file *.env*)' 'Bash(gh * --body-file=*.env*)'
  'Bash(gh * -F *.env*)' 'Bash(gh gist *)' 'Bash(*merge-ok*)' 'Bash(*gh auth *)' 'Bash(*gh auth)'
  'Bash(*security find-*)' 'Bash(*security dump-keychain*)' 'Bash(rm -rf /*)' 'Bash(rm -rf ~*)' 'Bash(sed -i*)'
  'Bash(perl -pi*)' 'Bash(git worktree remove -f*)' 'Bash(git worktree remove --force*)' 'Bash(pkill*)'
  'Bash(killall*)' 'Bash(git add -f*)' 'Bash(git add --force*)' 'Bash(git add * -f*)' 'Bash(git add * --force*)'
  'mcp__claude_ai_*'
)
for r in "${baseline[@]}"; do
  total=$((total+1))
  jq -e --arg r "$r" '.permissions.deny | index($r) != null' "$S" >/dev/null || bad "deny rule removed or changed: $r"
done
expect "approval label stays denied" deny "gh pr edit 9 --add-label merge-ok" yes
expect "graphql mutation denied" deny "gh api graphql -f query=mutation{x}" yes
expect "rulesets stay denied" deny "gh api repos/o/r/rulesets" yes
expect "ask stays for a sandbox bypass" ask "dangerouslyDisableSandbox:true" yes
# Nothing wider was allowed: these must still stop for a person.
expect "no blanket gh allow" allow "gh repo edit --visibility public" no
expect "no blanket ps allow" allow "ps aux" no
expect "no label deletion" allow "gh label delete agent:working" no

echo "test-settings: $((total - fail))/$total passed"
[ "$fail" -eq 0 ]

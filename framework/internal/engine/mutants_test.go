package engine

import (
	"os"
	"strings"
	"testing"

	"github.com/rfhayn/stridal/internal/testbin"
)

// The recovery corpus: what a refused repository may and may not still run. Each entry is a
// launcher case (the sh allowlist) and an IsRecovery case (its Go twin), so the two cannot drift.
var recoveryCorpus = []struct {
	command string
	allowed bool
}{
	{"git fetch", true},
	{"git fetch origin", true},
	{"git fetch origin main", true},
	{"git fetch --prune origin", true},
	{"git  fetch   -q  origin ", true},
	{"git fetch origin\n", true}, // $(...) drops a trailing newline, and so does IsRecovery
	{"stridal doctor", true},
	{"stridal doctor --template-dir /x/y", true},
	{"claude plugin update stridal@stridal", true},
	{"claude plugin install stridal@stridal", true},
	{"claude plugin marketplace update stridal", true},
	{"git fetch origin;touch build", false},
	{"git fetch origin && touch build", false},
	{"git fetch origin | sh", false},
	{"git fetch $(touch build)", false},
	{"git fetch `touch build`", false},
	{"git fetch origin\ntouch build", false},
	{"git fetch 'origin'", false},
	{"git fetch --upload-pack=touch origin", false},
	{"git fetch -c x=y origin", false},
	{"git -c core.sshCommand=x fetch", false},
	{"git fetchx", false},
	{"git", false},
	{"stridal doctorx", false},
	{"stridal doctor >x", false},
	{"stridal panel", false},
	{"claude plugin update other@stridal", false},
	{"claude plugin update stridal@stridal --scope user", false},
	{"rm -rf build", false},
	{"", false},
}

func init() {
	for _, e := range recoveryCorpus {
		e := e
		check := recovered
		if !e.allowed {
			check = refused("no .claude/stridal.lock", "git fetch origin")
		}
		launcherCases = append(launcherCases, launcherCase{
			name: "recovery " + strings.ReplaceAll(e.command, "\n", `\n`), verdict: Refuse, check: check,
			setup: func(f *fixture) string { f.setOriginLock(""); bash(f, e.command); return "" },
		})
	}
}

func TestIsRecoveryMatchesTheCorpus(t *testing.T) {
	for _, e := range recoveryCorpus {
		if got := IsRecovery(e.command); got != e.allowed {
			t.Errorf("IsRecovery(%q) = %v, want %v", e.command, got, e.allowed)
		}
	}
	if PayloadIsRecovery([]byte(`{"tool_name":"Read","tool_input":{"command":"git fetch"}}`)) {
		t.Error("a Read payload is not a recovery command")
	}
	if !PayloadIsRecovery([]byte(`{"tool_name":"Bash","tool_input":{"command":"git fetch"}}`)) {
		t.Error("PayloadIsRecovery misses git fetch")
	}
}

// A mutant is the launcher with one control removed: old (which must occur in the launcher
// exactly once) becomes new. Every case it names must FAIL against it, so each case is shown
// failing without the control it tests, and every case is named by at least one mutant.
type mutant struct {
	control  string
	old, new string
	kills    []string
}

var mutants = []mutant{
	{"stand aside without a marker", `[ -f "$proj/.claude/stridal-template" ] || exit 0`, `[ -f "$proj/.claude/stridal-template" ] || :`,
		[]string{"no marker stands aside with the payload unread"}},
	{"the install marker counts", `[ -f "$proj/.claude/stridal-plugin" ] || [ -f "$proj/.claude/stridal-template" ] ||`, `[ -f "$proj/.claude/stridal-plugin" ] ||`,
		[]string{"stridal-template marks a repository too"}},
	{"a missing lock refuses", `refuse "no .claude/stridal.lock at $ref" "git fetch origin"`, `exit 0`,
		[]string{"no lock on origin/main refuses"}},
	{"with an origin, a missing lock never falls back to the local main", "  if git -C \"$proj\" config --get remote.origin.url >/dev/null 2>&1; then\n    refuse", "  if false; then\n    refuse",
		[]string{"no lock on origin/main refuses"}},
	{"with no origin, a missing lock refuses", `lock=$(read_lock "$ref") || refuse "no .claude/stridal.lock at $ref" "stridal doctor"`, `lock=$(read_lock "$ref") || exit 0`,
		[]string{"with no origin, a lock on another branch does not count"}},
	{"a bad lock refuses", `"" | bad) refuse ".claude/stridal.lock at $ref does not parse (stridal doctor names the line)" "stridal doctor" ;;`, `"" | bad) exit 0 ;;`,
		[]string{"a lock that does not parse refuses", "a lock with an unknown line refuses", "lock: no release", "lock: no engine", "lock: only comments"}},
	{"two releases are bad", `|| rel != "") bad = 1`, `) bad = 1`,
		[]string{"lock: two releases"}},
	{"a platform twice is bad", ` || ($2 in sum)) bad = 1`, `) bad = 1`,
		[]string{"lock: a platform twice"}},
	{"a sha256 is 64 characters", ` || length($3) != 64`, ``,
		[]string{"lock: a short sha256"}},
	{"a sha256 is lower-case hex", `$3 !~ /^[0-9a-f]+$/`, `$3 !~ /^[0-9a-fA-F]+$/`,
		[]string{"lock: an upper-case sha256"}},
	{"an engine line has three fields", `if (NF != 3 ||`, `if (NF < 3 ||`,
		[]string{"lock: an extra field"}},
	{"a CR is not part of a field", `{ sub(/\r$/, "") }`, `{ }`,
		[]string{"lock: comments, blank lines, CRLF and indentation"}},
	{"an unknown lock line is bad", "  { bad = 1 }\n  END", "  END",
		[]string{"a lock with an unknown line refuses", "lock: an unknown keyword"}},
	{"a release line has two fields", `if (NF != 2 ||`, `if (NF < 2 ||`,
		[]string{"lock: a release with a space"}},
	{"a platform is goos/goarch", `$2 !~ /^[a-z0-9]+\/[a-z0-9]+$/`, `$2 !~ /^[a-z0-9\/]+$/`,
		[]string{"lock: a platform with no arch"}},
	{"no engine for this platform refuses", `[ "$want" != - ] || refuse "the lock at $ref pins no engine for $platform" "stridal doctor"`, `[ "$want" != - ] || exit 0`,
		[]string{"no engine pinned for this platform refuses"}},
	{"no plugin root refuses", `[ -n "$root" ] || refuse`, `[ -n "$root" ] || exit 0; refuse`,
		[]string{"no plugin root refuses"}},
	{"the plugin must be the pinned release", `[ "$version" = "$release" ] ||`, `: ||`,
		[]string{"a plugin that is not the pinned release refuses", "the copy-install path refuses the same mismatch"}},
	{"a missing engine refuses", `|| refuse "no executable engine at $engine" "claude plugin update stridal@stridal"`, `|| exit 0`,
		[]string{"a missing engine refuses"}},
	{"the engine must match its sha256", `[ "$got" = "$want" ] ||`, `: ||`,
		[]string{"a mismatched engine refuses and never runs", "STRIDAL_ENGINE outside a fixture HOME is ignored",
			"a fixture marker in a HOME outside TMPDIR does not count", "a worktree's own lock cannot verify an engine main's does not"}},
	{"an engine that cannot start refuses", `  126 | 127) refuse`, `  126x | 127x) refuse`,
		[]string{"a pinned engine that cannot start (126, 127) refuses"}},
	{"a recovery command is allowed", `recovery "$payload" && exit 0`, `:`,
		[]string{"no lock still allows git fetch", "a missing engine still allows stridal doctor", "a mismatched engine still allows the plugin update",
			"recovery git fetch", "recovery stridal doctor", "recovery claude plugin update stridal@stridal"}},
	{"only plain characters in a recovery command", `case $cmd in *[!A-Za-z0-9@:/._=+,\ -]*) return 1 ;; esac`, `:`,
		[]string{"recovery git fetch origin;touch build", "recovery git fetch $(touch build)", "recovery git fetch origin && touch build", "recovery git fetch origin\\ntouch build", "recovery git fetch 'origin'"}},
	{"no fetch option but the listed ones", `-*) return 1 ;; esac`, `-*) ;; esac`,
		[]string{"recovery git fetch --upload-pack=touch origin", "recovery git fetch -c x=y origin"}},
	{"STRIDAL_ENGINE needs the fixture marker", `[ -f "$HOME/.stridal-fixture-home" ]`, `:`,
		[]string{"STRIDAL_ENGINE outside a fixture HOME is ignored"}},
	{"a fixture HOME is inside TMPDIR", `case $h in "${t%/}"/?*)`, `case $h in *)`,
		[]string{"a fixture marker in a HOME outside TMPDIR does not count"}},
	{"the lock is origin's main", "ref=refs/remotes/origin/$main\n", "ref=HEAD\n",
		[]string{"a worktree's own lock cannot verify an engine main's does not", "a worktree whose own lock differs is still guarded by main's"}},
	{"the lock is origin's ref, by its full name", "ref=refs/remotes/origin/$main\n", "ref=origin/$main\n",
		[]string{"a local branch named origin/main does not stand in for origin's"}},
	{"the lock is read through git, not the working tree", `read_lock() { git -C "$proj" cat-file blob "$1:.claude/stridal.lock" 2>/dev/null; }`, `read_lock() { cat "$proj/.claude/stridal.lock" 2>/dev/null; }`,
		[]string{"a worktree's own lock cannot verify an engine main's does not", "with no origin, a lock on another branch does not count"}},
	{"with no origin, the lock is main's", "ref=refs/heads/$main\n", "ref=HEAD\n",
		[]string{"with no origin, a lock on another branch does not count"}},
	{"with no origin, the lock is the repository's own", "ref=refs/heads/$main\n", "ref=refs/remotes/origin/$main\n",
		[]string{"a repository with no origin reads its own main"}},
	{"the last MAIN_BRANCH wins", `main=${main##*"$nl"}`, `main=${main%%"$nl"*}`,
		[]string{"the last MAIN_BRANCH assignment wins"}},
	{"MAIN_BRANCH is read", "main=${main:-main}\n", "main=main\n",
		[]string{"MAIN_BRANCH names the branch the lock is read from"}},
	{"the copy-install path finds the recorded plugin root", `[ -f "$f" ] && IFS= read -r root < "$f"`, `:`,
		[]string{"the copy-install path reads the same lock and engine"}},
	{"the engine is handed the control beside the launcher", `"$engine" hook "$dir/$hook"`, `"$engine" hook "$hook"`,
		[]string{"a verified engine runs the control", "the copy-install path reads the same lock and engine", "lock: the canonical form", "lock: two platforms"}},
	{"the engine is handed the payload", `"$engine" hook "$dir/$hook"`, `"$engine" hook "$dir/$hook" </dev/null`,
		[]string{"a verified engine runs the control", "STRIDAL_ENGINE under a fixture HOME is honoured"}},
	{"the engine's status is the verdict", "esac\nexit \"$rc\"\n", "esac\nexit 0\n",
		[]string{"the engine's exit 2 is the verdict"}},
}

func TestEachLauncherCaseFailsWithoutItsControl(t *testing.T) {
	src, err := os.ReadFile(launcherSrc)
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]launcherCase{}
	for _, c := range launcherCases {
		byName[c.name] = c
	}
	named := map[string]bool{}
	for _, m := range mutants {
		if n := strings.Count(string(src), m.old); n != 1 {
			t.Errorf("mutant %q: its text occurs %d times in the launcher, want 1: %q", m.control, n, m.old)
			continue
		}
		body := strings.Replace(string(src), m.old, m.new, 1)
		for _, k := range m.kills {
			named[k] = true
			c, ok := byName[k]
			if !ok {
				t.Errorf("mutant %q names no case %q", m.control, k)
				continue
			}
			t.Run(m.control+"/"+k, func(t *testing.T) {
				t.Parallel()
				f, _, r := runCase(t, c, func(f *fixture) { testbin.Write(t, f.launcher, body) })
				if c.check(f, r) == nil {
					t.Errorf("passed with %q removed from the launcher: the case does not test it", m.control)
				}
			})
		}
	}
	for _, c := range launcherCases {
		if !named[c.name] && !strings.HasPrefix(c.name, "recovery ") {
			t.Errorf("case %q is killed by no mutant: nothing shows it failing without its control", c.name)
		}
	}
}

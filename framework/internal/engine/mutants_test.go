package engine

import (
	"os"
	"regexp"
	"slices"
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
	{"git fetch --prune origin", true},
	{"git fetch -q --tags origin", true},
	{"git  fetch   -q  origin ", true},
	{"git fetch origin\n", true}, // $(...) drops a trailing newline, and so does IsRecovery
	{"stridal doctor", true},
	{"git remote set-head origin --auto", true},
	{"claude plugin update stridal@stridal", true},
	{"claude plugin install stridal@stridal", true},
	{"claude plugin marketplace update stridal", true},
	// Review round 1: each repoints a ref the launcher trusts, or runs a transport's program.
	{"git fetch . +HEAD:refs/remotes/origin/main", false},
	{"git fetch origin +ops/x:refs/heads/main", false},
	{"git fetch ext::sh", false},
	{"git fetch origin main", false},
	{"git fetch . main", false},
	{"git fetch upstream", false},
	{"git fetch origin origin", false},
	{"git fetch --all", false},
	{"git fetch --upload-pack touch origin", false},
	{"git fetch --upload-pack=touch origin", false},
	{"git fetch -c x=y origin", false},
	{"git -c core.sshCommand=x fetch", false},
	{"git remote set-head origin ops/x", false},
	{"git remote set-url origin /tmp/x", false},
	{"stridal doctor --template-dir /x/y", false},
	{"git fetch origin;touch build", false},
	{"git fetch origin && touch build", false},
	{"git fetch origin | sh", false},
	{"git fetch $(touch build)", false},
	{"git fetch `touch build`", false},
	{"git fetch origin\ntouch build", false},
	{"git fetch 'origin'", false},
	{"git\tfetch origin", false},
	{"stridal\ndoctor", false},
	{"git fetchx", false},
	{"git", false},
	{"touch origin", false},
	{"stridal doctorx", false},
	{"stridal panel", false},
	{"claude plugin update other@stridal", false},
	{"claude plugin update stridal@stridal --scope user", false},
	{"rm -rf build", false},
	{"", false},
}

func corpusName(command string) string {
	return "recovery " + strings.NewReplacer("\n", `\n`, "\t", `\t`).Replace(command)
}

func init() {
	for _, e := range recoveryCorpus {
		e := e
		check := recovered
		if !e.allowed {
			check = refused("no .claude/stridal.lock", "git fetch origin")
		}
		launcherCases = append(launcherCases, launcherCase{
			name: corpusName(e.command), verdict: Refuse, check: check,
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
// failing without the control it tests. Two authorities are enumerated, so neither can be missed:
// every case is named by a mutant, and every control site in the launcher itself (each refusal,
// each `return 1`, each `exit 2`: controlSites) lies inside some mutant's text.
type mutant struct {
	control  string
	old, new string
	kills    []string
}

const (
	fixPlugin = "claude plugin update stridal@stridal"
	steered   = "a lane's MAIN_BRANCH naming its own pushed branch does not choose the pin"
	// noOriginMain is where the launcher names main with no origin.
	noOriginMain = `main=$(git -C "$proj" config --local --get stridal.mainBranch 2>/dev/null) || main=main`
	// goodBranchCase is good_branch's pattern, one alternative per way a name is refused.
	goodBranchCase = `case $1 in "" | -* | /* | */ | *..* | *.lock | *[!A-Za-z0-9/._-]*) return 1 ;; esac`
)

// badMainCases names the bad-stridal.mainBranch cases for the alternatives given, or all of them.
func badMainCases(alternatives []string) []string {
	var out []string
	for _, b := range badMains {
		if alternatives == nil || slices.Contains(alternatives, b.alternative) {
			out = append(out, badMainCase(b.alternative))
		}
	}
	return out
}

var mutants = []mutant{
	// Standing aside, and the control's name.
	{"stand aside without a marker", `[ -f "$proj/.claude/stridal-template" ] || exit 0`, `[ -f "$proj/.claude/stridal-template" ] || :`,
		[]string{"no marker stands aside with the payload unread"}},
	{"the install marker counts", `[ -f "$proj/.claude/stridal-plugin" ] || [ -f "$proj/.claude/stridal-template" ] ||`, `[ -f "$proj/.claude/stridal-plugin" ] ||`,
		[]string{"stridal-template marks a repository too"}},
	{"a control name is a plain file name", `"" | *[!A-Za-z0-9_.-]* | .*) printf`, `"") printf`,
		[]string{"a control name with a path refuses"}},
	{"an empty control name refuses", `"" | *[!A-Za-z0-9_.-]* | .*) printf`, `*[!A-Za-z0-9_.-]* | .*) printf`,
		[]string{"an empty control name refuses"}},

	// The recovery allowlist.
	{"without jq the refusal says so", `command -v jq >/dev/null 2>&1 || { nojq=1; return 1; }`, `command -v jq >/dev/null 2>&1 || { return 1; }`,
		[]string{"without jq, the refusal says jq is required"}},
	{"only a Bash payload is a recovery command", `.tool_name == "Bash"`, `.tool_name != ""`,
		[]string{"a recovery command in a Read payload is refused"}},
	{"a payload jq cannot read is no recovery command", `else empty end' 2>/dev/null) || return 1`, `else empty end' 2>/dev/null) || return 0`,
		[]string{"a payload that is not JSON is refused"}},
	{"only plain characters in a recovery command", `case $cmd in "" | *[!A-Za-z0-9@._\ -]*) return 1 ;; esac`, `:`,
		[]string{corpusName("git\tfetch origin"), corpusName("stridal\ndoctor")}},
	{"only the exact commands, or git fetch", `[ $# -ge 2 ] && [ "$1 $2" = "git fetch" ] || return 1`, `[ $# -ge 2 ] || return 0`,
		[]string{corpusName("touch origin"), corpusName("stridal panel")}},
	{"git fetch names origin at most once", `origin) [ -z "$operand" ] || return 1; operand=1 ;;`, `origin) operand=1 ;;`,
		[]string{corpusName("git fetch origin origin")}},
	{"git fetch takes no other flag or operand", "      *) return 1 ;;\n    esac\n  done", "      *) ;;\n    esac\n  done",
		[]string{corpusName("git fetch upstream"),
			corpusName("git fetch origin main"), corpusName("git fetch . main"), corpusName("git fetch --all"), corpusName("git fetch --upload-pack touch origin")}},
	{"a recovery command is allowed", `recovery "$payload" && exit 0`, `:`,
		[]string{"no lock still allows git fetch", "a missing engine still allows stridal doctor", "a mismatched engine still allows the plugin update",
			"origin with no HEAD still allows git remote set-head origin --auto", corpusName("git fetch"), corpusName("stridal doctor")}},
	{"a refusal is exit 2", "  exit 2\n}", "  exit 0\n}",
		[]string{"no lock on origin/main refuses", "a mismatched engine refuses and never runs", "origin with no HEAD refuses"}},

	// Which branch is main, and where its lock is read.
	{"main is origin's HEAD, not the lane's project.conf", `main=${head#refs/remotes/origin/}`,
		`main=$(sed -n 's/^MAIN_BRANCH="\([^"]*\)"$/\1/p' "$proj/.claude/project.conf" 2>/dev/null); main=${main:-${head#refs/remotes/origin/}}`,
		[]string{steered}},
	{"origin's HEAD must name a branch of origin", `[ "$main" != "$head" ] && good_branch`, `good_branch`,
		[]string{"origin's HEAD naming a ref off origin refuses"}},
	{"a bad origin HEAD refuses", `{ unverified "origin's HEAD names $head, not a branch of origin" "git remote set-head origin --auto"; return 1; }`, `exit 0`,
		[]string{"origin's HEAD naming a ref off origin refuses", "origin's HEAD naming a branch outside the plain characters refuses"}},
	{"a branch is plain characters", `*[!A-Za-z0-9/._-]*) return 1 ;; esac`, `*[!A-Za-z0-9/._-]*) ;; esac`,
		[]string{"origin's HEAD naming a branch outside the plain characters refuses"}},
	{"a missing lock refuses", `lock=$(read_lock "$ref") || { unverified "no .claude/stridal.lock at $ref" "git fetch origin"; return 1; }`, `lock=$(read_lock "$ref") || exit 0`,
		[]string{"no lock on origin/main refuses"}},
	{"an origin with no HEAD is refused, never read as no origin", `elif git -C "$proj" config --get remote.origin.url >/dev/null 2>&1; then`, `elif false; then`,
		[]string{"origin with no HEAD refuses"}},
	{"an origin with no HEAD refuses", `unverified "origin has no HEAD, so which of its branches is main is unknown" "git remote set-head origin --auto"; return 1`, `exit 0`,
		[]string{"origin with no HEAD refuses"}},
	// Review round 2: with no origin, main came from the main worktree's checkout.
	{"with no origin, main is not the main worktree's branch", noOriginMain,
		`main=$(git -C "$proj" worktree list --porcelain 2>/dev/null | sed -n '1,/^$/s/^branch refs\/heads\///p')`,
		[]string{"with no origin, a lock on another branch does not count"}},
	{"with no origin, main is not this checkout's branch", noOriginMain, `main=$(git -C "$proj" symbolic-ref --short HEAD 2>/dev/null)`,
		[]string{"with no origin, a lock on another branch does not count", "with no origin, a lane's own branch does not count"}},
	{"with no origin, only the common dir's config names main", `config --local --get stridal.mainBranch`, `config --get stridal.mainBranch`,
		[]string{"with no origin, a worktree's own config does not name main"}},
	{"with no origin, stridal.mainBranch is read", `config --local --get stridal.mainBranch 2>/dev/null) || main=main`, `config --local --get stridal.nothing 2>/dev/null) || main=main`,
		[]string{"with no origin, stridal.mainBranch names the branch"}},
	{"with no origin, unset means main", `2>/dev/null) || main=main`, `2>/dev/null) || main=`,
		[]string{"a repository with no origin reads its own main", "with no origin, a detached main checkout still reads main"}},
	{"a bad stridal.mainBranch refuses", `good_branch "$main" || { unverified "stridal.mainBranch names $main, not a plain branch name" "stridal doctor"; return 1; }`, `:`,
		badMainCases(nil)},
	{"good_branch refuses an empty name", goodBranchCase, strings.Replace(goodBranchCase, `"" | `, ``, 1),
		badMainCases([]string{"empty"})},
	{"good_branch refuses a leading dash", goodBranchCase, strings.Replace(goodBranchCase, `-* | `, ``, 1),
		badMainCases([]string{"a leading dash"})},
	{"good_branch refuses a leading slash", goodBranchCase, strings.Replace(goodBranchCase, `/* | `, ``, 1),
		badMainCases([]string{"a leading slash"})},
	{"good_branch refuses a trailing slash", goodBranchCase, strings.Replace(goodBranchCase, `*/ | `, ``, 1),
		badMainCases([]string{"a trailing slash"})},
	{"good_branch refuses two dots", goodBranchCase, strings.Replace(goodBranchCase, `*..* | `, ``, 1),
		badMainCases([]string{"two dots"})},
	{"good_branch refuses a .lock suffix", goodBranchCase, strings.Replace(goodBranchCase, `*.lock | `, ``, 1),
		badMainCases([]string{"a .lock suffix"})},
	{"good_branch refuses a character outside the plain set", goodBranchCase, strings.Replace(goodBranchCase, ` | *[!A-Za-z0-9/._-]*`, ``, 1),
		badMainCases([]string{"a revision expression", "a character outside the plain set"})},
	{"with no origin, a missing lock refuses", `lock=$(read_lock "$ref") || { unverified "no .claude/stridal.lock at $ref" "stridal doctor"; return 1; }`, `lock=$(read_lock "$ref") || exit 0`,
		[]string{"with no origin, a missing lock refuses"}},
	{"the lock is origin's ref, by its full name", "ref=refs/remotes/origin/$main\n", "ref=origin/$main\n",
		[]string{"a local branch named origin/main does not stand in for origin's"}},
	{"the lock is origin's main, not HEAD", "ref=refs/remotes/origin/$main\n", "ref=HEAD\n",
		[]string{"a worktree's own lock cannot verify an engine main's does not", "a worktree whose own lock differs is still guarded by main's"}},
	{"the lock is read through git, not the working tree", `read_lock() { git -C "$proj" cat-file blob "$1:.claude/stridal.lock" 2>/dev/null; }`, `read_lock() { cat "$proj/.claude/stridal.lock" 2>/dev/null; }`,
		[]string{"a worktree's own lock cannot verify an engine main's does not", "with no origin, a missing lock refuses"}},
	{"with no origin, the lock is the repository's own", "ref=refs/heads/$main\n", "ref=refs/remotes/origin/$main\n",
		[]string{"a repository with no origin reads its own main"}},

	// The lock's format.
	{"a bad lock refuses", `"" | bad) unverified ".claude/stridal.lock at $ref does not parse (stridal doctor names the line)" "stridal doctor"; return 1 ;;`, `"" | bad) exit 0 ;;`,
		[]string{"a lock that does not parse refuses", "a lock with an unknown line refuses", "lock: no release", "lock: no engine", "lock: only comments"}},
	{"two releases are bad", `|| rel != "") bad = 1`, `) bad = 1`, []string{"lock: two releases"}},
	{"a platform twice is bad", ` || ($2 in sum)) bad = 1`, `) bad = 1`, []string{"lock: a platform twice"}},
	{"a sha256 is 64 characters", ` || length($3) != 64`, ``, []string{"lock: a short sha256"}},
	{"a sha256 is lower-case hex", `$3 !~ /^[0-9a-f]+$/`, `$3 !~ /^[0-9a-fA-F]+$/`, []string{"lock: an upper-case sha256"}},
	{"an engine line has three fields", `if (NF != 3 ||`, `if (NF < 3 ||`, []string{"lock: an extra field"}},
	{"a CR is not part of a field", `{ sub(/\r$/, "") }`, `{ }`, []string{"lock: comments, blank lines, CRLF and indentation"}},
	{"an unknown lock line is bad", "    { bad = 1 }\n    END", "    END", []string{"a lock with an unknown line refuses", "lock: an unknown keyword"}},
	{"a release line has two fields", `if (NF != 2 ||`, `if (NF < 2 ||`, []string{"lock: a release with a space"}},
	{"a platform is goos/goarch", `$2 !~ /^[a-z0-9]+\/[a-z0-9]+$/`, `$2 !~ /^[a-z0-9\/]+$/`, []string{"lock: a platform with no arch"}},
	{"no engine for this platform refuses", `[ "$want" != - ] || { unverified "the lock at $ref pins no engine for $platform" "stridal doctor"; return 1; }`, `[ "$want" != - ] || exit 0`,
		[]string{"no engine pinned for this platform refuses"}},

	// The plugin and the engine.
	{"no plugin root refuses", `[ -n "$root" ] || { unverified "no stridal plugin root`, `[ -n "$root" ] || exit 0; { unverified "no stridal plugin root`,
		[]string{"no plugin root refuses"}},
	{"the plugin must be the pinned release", "[ \"$version\" = \"$release\" ] ||\n    { unverified", ": ||\n    { unverified",
		[]string{"a plugin that is not the pinned release refuses", "the copy-install path refuses the same mismatch"}},
	{"a missing engine refuses", `|| { unverified "no executable engine at $engine" "claude plugin update stridal@stridal"; return 1; }`, `|| exit 0`,
		[]string{"a missing engine refuses"}},
	{"STRIDAL_ENGINE needs the fixture marker", `[ -f "$HOME/.stridal-fixture-home" ]`, `:`,
		[]string{"STRIDAL_ENGINE outside a fixture HOME is ignored"}},
	{"a fixture HOME is inside TMPDIR", `case $h in "${t%/}"/?*)`, `case $h in *)`,
		[]string{"a fixture marker in a HOME outside TMPDIR does not count"}},
	{"the default arm hashes the engine", `        got=$(sha256sum "$engine" 2>/dev/null)`, `        got=$want`,
		[]string{"a mismatched engine refuses and never runs"}},
	{"openssl's sum is the engine's", `openssl) got=$(openssl dgst -sha256 -r "$engine" 2>/dev/null) ;;`, `openssl) got=$want ;;`,
		[]string{"hashed with openssl, a mismatched engine is refused"}},
	{"shasum's sum is the engine's", `shasum) got=$(shasum -a 256 "$engine" 2>/dev/null) ;;`, `shasum) got=$want ;;`,
		[]string{"hashed with shasum, a mismatched engine is refused"}},
	{"a sum is the first field of the tool's line", `got=${got%% *}`, `:`,
		[]string{"a verified engine runs the control", "hashed with openssl, the pinned engine verifies", "hashed with shasum, the pinned engine verifies"}},
	{"the engine must match its sha256", "[ \"$got\" = \"$want\" ] ||\n    { unverified", ": ||\n    { unverified",
		[]string{"hashed with openssl, a mismatched engine is refused", "hashed with shasum, a mismatched engine is refused", "a mismatched engine refuses and never runs",
			"STRIDAL_ENGINE outside a fixture HOME is ignored", "a fixture marker in a HOME outside TMPDIR does not count",
			"a worktree's own lock cannot verify an engine main's does not", steered, "a lane's MAIN_BRANCH naming an older main does not choose the pin",
			"with no origin, a lane's own branch does not count"}},
	{"an unverified engine refuses", `verified_engine || refuse "$why" "$fix"`, `verified_engine || exit 0`,
		[]string{"no lock on origin/main refuses", "a mismatched engine refuses and never runs", "a missing engine refuses"}},
	{"the copy-install path finds the recorded plugin root", `[ -f "$f" ] && IFS= read -r root < "$f"`, `:`,
		[]string{"the copy-install path reads the same lock and engine"}},

	// Running the engine.
	{"the engine is handed the control beside the launcher", `"$engine" hook "$dir/$hook"`, `"$engine" hook "$hook"`,
		[]string{"a verified engine runs the control", "the copy-install path reads the same lock and engine", "lock: the canonical form", "lock: two platforms",
			"origin's HEAD names the branch the lock is read from"}},
	{"the engine is handed the payload", `"$engine" hook "$dir/$hook"`, `"$engine" hook "$dir/$hook" </dev/null`,
		[]string{"a verified engine runs the control", "STRIDAL_ENGINE under a fixture HOME is honoured"}},
	{"an engine that cannot start refuses", `  126 | 127) refuse`, `  126x | 127x) refuse`,
		[]string{"a pinned engine that cannot start (126, 127) refuses"}},
	{"the engine's status is the verdict", "esac\nexit \"$rc\"\n", "esac\nexit 0\n",
		[]string{"the engine's exit 2 is the verdict"}},
}

// controlSite is a launcher line that refuses or declines: a refuse or unverified call, a
// `return 1`, an `exit 2`. Comments are not code.
var controlSite = regexp.MustCompile(`\brefuse "|\bunverified "|\breturn 1\b|\bexit 2\b`)

// controlSites are the launcher's control lines, numbered from 1: the authority the mutant table
// is held to, so a control added without a mutant fails the test.
func controlSites(src string) map[int]string {
	sites := map[int]string{}
	for i, line := range strings.Split(src, "\n") {
		if t := strings.TrimSpace(line); !strings.HasPrefix(t, "#") && controlSite.MatchString(t) {
			sites[i+1] = t
		}
	}
	return sites
}

func TestEachLauncherCaseFailsWithoutItsControl(t *testing.T) {
	data, err := os.ReadFile(launcherSrc)
	if err != nil {
		t.Fatal(err)
	}
	src := string(data)
	byName := map[string]launcherCase{}
	for _, c := range launcherCases {
		byName[c.name] = c
	}
	named := map[string]bool{}
	covered := map[int]bool{}
	for _, m := range mutants {
		if len(m.kills) == 0 {
			t.Errorf("mutant %q names no case: nothing shows its control is tested", m.control)
		}
		if n := strings.Count(src, m.old); n != 1 {
			t.Errorf("mutant %q: its text occurs %d times in the launcher, want 1: %q", m.control, n, m.old)
			continue
		}
		at := strings.Index(src, m.old)
		first := strings.Count(src[:at], "\n") + 1
		for l := first; l <= first+strings.Count(m.old, "\n"); l++ {
			covered[l] = true
		}
		body := strings.Replace(src, m.old, m.new, 1)
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
				err := c.check(f, r)
				if err == nil {
					t.Errorf("passed with %q removed from the launcher: the case does not test it", m.control)
					return
				}
				t.Logf("fails without it, as it must: %v", err)
			})
		}
	}
	for _, c := range launcherCases {
		if !named[c.name] && !strings.HasPrefix(c.name, "recovery ") {
			t.Errorf("case %q is killed by no mutant: nothing shows it failing without its control", c.name)
		}
	}
	for line, text := range controlSites(src) {
		if !covered[line] {
			t.Errorf("launcher line %d is a control no mutant removes: %s", line, text)
		}
	}
}

// The authority above is read from the launcher, so it must see the launcher's controls: a
// guard that iterates nothing passes everything.
func TestControlSitesSeeTheLaunchersControls(t *testing.T) {
	data, err := os.ReadFile(launcherSrc)
	if err != nil {
		t.Fatal(err)
	}
	if n := len(controlSites(string(data))); n < 20 {
		t.Errorf("controlSites found %d control lines in the launcher; it has more than 20", n)
	}
}

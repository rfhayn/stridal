package engine

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/rfhayn/stridal/internal/testbin"
)

// A launcher case is one row of the launcher's decision table, run against the real launcher in a
// fixture. check returns an error rather than failing the test, so the mutant table below can
// require the same check to FAIL against a launcher with that row's control removed: each case is
// seen failing without its control (AGENTS.md rule 2), every run, not once by hand.
type launcherCase struct {
	name string
	// setup changes the fixture and returns the directory to run in ("" is the clone).
	setup func(f *fixture) string
	check func(f *fixture, r result) error
	// verdict is what the Go twin (Decide) must say about the same fixture. Decide does not read
	// the control's name, so a bad name is still Run to it.
	verdict Verdict
	// control is the control name the launcher is given: "" is guard.sh, "-" is none.
	control string
}

func standAside(_ *fixture, r result) error {
	switch {
	case r.code != 0:
		return fmt.Errorf("exit %d, want 0 (stand aside); stderr: %s", r.code, r.stderr)
	case r.ran:
		return fmt.Errorf("the engine ran (%s); standing aside runs nothing", r.args)
	case r.unread != r.payloadIn:
		return fmt.Errorf("%d of %d payload bytes were read; standing aside reads none", r.payloadIn-r.unread, r.payloadIn)
	}
	return nil
}

// ranControl is a verified run: the engine got `hook <dir>/<control>` and the whole payload.
func ranControl(control func(f *fixture) string, code int) func(f *fixture, r result) error {
	return func(f *fixture, r result) error {
		want := "hook " + control(f)
		switch {
		case !r.ran:
			return fmt.Errorf("the engine did not run (exit %d); stderr: %s", r.code, r.stderr)
		case r.args != want:
			return fmt.Errorf("the engine got %q, want %q", r.args, want)
		case r.got != f.payload:
			return fmt.Errorf("the engine read %q, want the payload %q", r.got, f.payload)
		case r.code != code:
			return fmt.Errorf("exit %d, want the engine's %d", r.code, code)
		}
		return nil
	}
}

func pluginGuard(f *fixture) string { return filepath.Join(f.plugin, "hooks", "guard.sh") }

func refused(reason, fix string) func(f *fixture, r result) error {
	return func(_ *fixture, r result) error {
		switch {
		case r.code != 2:
			return fmt.Errorf("exit %d, want 2 (refused); stderr: %s", r.code, r.stderr)
		case r.ran:
			return fmt.Errorf("the engine ran (%s); a refused call runs no engine", r.args)
		case !strings.Contains(r.stderr, "stridal: refused: ") || !strings.Contains(r.stderr, reason):
			return fmt.Errorf("stderr %q does not say refused: ...%s", r.stderr, reason)
		case !strings.Contains(r.stderr, "\nfix: "+fix+"\n"):
			return fmt.Errorf("stderr %q does not name the fix %q", r.stderr, fix)
		}
		return nil
	}
}

func recovered(_ *fixture, r result) error {
	switch {
	case r.code != 0:
		return fmt.Errorf("exit %d, want 0 (a recovery command is allowed); stderr: %s", r.code, r.stderr)
	case r.ran:
		return fmt.Errorf("the engine ran (%s); a refused repository runs none", r.args)
	}
	return nil
}

func bash(f *fixture, command string) {
	f.payload = fmt.Sprintf(`{"tool_name":"Bash","tool_input":{"command":%q}}`, command)
}

const altEngine = "#!/bin/sh\n# the fixture's STRIDAL_ENGINE\nprintf '%s\\n' \"$*\" > \"$FAKE_LOG\"\ncat > \"$FAKE_LOG.stdin\"\n"

// altFixtureEngine pins a second engine and leaves the plugin's own unpinned, so only
// STRIDAL_ENGINE can verify.
func altFixtureEngine(f *fixture) {
	alt := filepath.Join(f.root, "alt", "stridal")
	must(f.t, os.MkdirAll(filepath.Dir(alt), 0o755))
	testbin.Write(f.t, alt, altEngine)
	sum, err := FileSHA256(alt)
	must(f.t, err)
	f.setOriginLock(f.lockFor(sum))
	f.env["STRIDAL_ENGINE"] = alt
}

func worktree(f *fixture, lock string) string {
	wt := filepath.Join(f.root, "wt")
	f.git(f.proj, "worktree", "add", "-q", "-b", "lane", wt)
	f.commitLock(wt, lock)
	f.mark(wt)
	return wt
}

var garbage = strings.Repeat("ab", 32)

var launcherCases = []launcherCase{
	{name: "no marker stands aside with the payload unread", verdict: StandAside,
		setup: func(f *fixture) string {
			must(f.t, os.Remove(filepath.Join(f.proj, ".claude", "stridal-plugin")))
			return ""
		},
		check: standAside},
	{name: "a verified engine runs the control", verdict: Run, check: ranControl(pluginGuard, 0)},
	{name: "the engine's exit 2 is the verdict", verdict: Run,
		setup: func(f *fixture) string { f.env["FAKE_RC"] = "2"; return "" },
		check: ranControl(pluginGuard, 2)},
	{name: "stridal-template marks a repository too", verdict: Run,
		setup: func(f *fixture) string {
			must(f.t, os.Rename(filepath.Join(f.proj, ".claude", "stridal-plugin"), filepath.Join(f.proj, ".claude", "stridal-template")))
			return ""
		},
		check: ranControl(pluginGuard, 0)},
	{name: "no lock on origin/main refuses", verdict: Refuse,
		setup: func(f *fixture) string { f.setOriginLock(""); return "" },
		check: refused("no .claude/stridal.lock at refs/remotes/origin/main", "git fetch origin")},
	{name: "no lock still allows git fetch", verdict: Refuse,
		setup: func(f *fixture) string { f.setOriginLock(""); bash(f, "git fetch origin --prune"); return "" },
		check: recovered},
	{name: "a lock that does not parse refuses", verdict: Refuse,
		setup: func(f *fixture) string { f.setOriginLock("release 9.8.7\nengine darwin/arm64 nothex\n"); return "" },
		check: refused("does not parse", "stridal doctor")},
	{name: "a lock with an unknown line refuses", verdict: Refuse,
		setup: func(f *fixture) string { f.setOriginLock(f.lockFor(f.engineSum()) + "allow everything\n"); return "" },
		check: refused("does not parse", "stridal doctor")},
	{name: "no engine pinned for this platform refuses", verdict: Refuse,
		setup: func(f *fixture) string {
			f.setOriginLock("release 9.8.7\nengine plan9/mips " + garbage + "\n")
			return ""
		},
		check: refused("pins no engine for "+Platform(), "stridal doctor")},
	{name: "a plugin that is not the pinned release refuses", verdict: Refuse,
		setup: func(f *fixture) string { f.setPluginVersion("9.9.9"); return "" },
		check: refused("pins release 9.8.7, and the plugin is 9.9.9", "claude plugin update stridal@stridal")},
	{name: "no plugin root refuses", verdict: Refuse,
		setup: func(f *fixture) string { f.env["CLAUDE_PLUGIN_ROOT"] = ""; return "" },
		check: refused("no stridal plugin root", "claude plugin install stridal@stridal")},
	{name: "a missing engine refuses", verdict: Refuse,
		setup: func(f *fixture) string { must(f.t, os.Remove(f.enginePath())); return "" },
		check: refused("no executable engine at", "claude plugin update stridal@stridal")},
	{name: "a missing engine still allows stridal doctor", verdict: Refuse,
		setup: func(f *fixture) string { must(f.t, os.Remove(f.enginePath())); bash(f, "stridal doctor"); return "" },
		check: recovered},
	{name: "a mismatched engine refuses and never runs", verdict: Refuse,
		setup: func(f *fixture) string { f.writeEngine(fakeEngine + "# not the pinned build\n"); return "" },
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "a mismatched engine still allows the plugin update", verdict: Refuse,
		setup: func(f *fixture) string {
			f.writeEngine(fakeEngine + "# not the pinned build\n")
			bash(f, "claude plugin update stridal@stridal")
			return ""
		},
		check: recovered},
	{name: "a pinned engine that cannot start (126, 127) refuses", verdict: Run,
		setup: func(f *fixture) string {
			f.writeEngine("#!/nonexistent/interpreter\n")
			f.setOriginLock(f.lockFor(f.engineSum()))
			return ""
		},
		check: refused("did not start", "claude plugin update stridal@stridal")},
	{name: "STRIDAL_ENGINE outside a fixture HOME is ignored", verdict: Refuse,
		setup: func(f *fixture) string { altFixtureEngine(f); return "" },
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "STRIDAL_ENGINE under a fixture HOME is honoured", verdict: Run,
		setup: func(f *fixture) string {
			altFixtureEngine(f)
			must(f.t, os.WriteFile(filepath.Join(f.home, FixtureHomeMarker), nil, 0o644))
			return ""
		},
		check: ranControl(pluginGuard, 0)},
	{name: "a fixture marker in a HOME outside TMPDIR does not count", verdict: Refuse,
		setup: func(f *fixture) string {
			altFixtureEngine(f)
			must(f.t, os.WriteFile(filepath.Join(f.home, FixtureHomeMarker), nil, 0o644))
			f.tmp = filepath.Join(f.root, "elsewhere")
			must(f.t, os.MkdirAll(f.tmp, 0o755))
			return ""
		},
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "a worktree's own lock cannot verify an engine main's does not", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.setOriginLock(f.lockFor(garbage))
			return worktree(f, good)
		},
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "a worktree whose own lock differs is still guarded by main's", verdict: Run,
		setup: func(f *fixture) string { return worktree(f, f.lockFor(garbage)) },
		check: ranControl(pluginGuard, 0)},
	{name: "a local branch named origin/main does not stand in for origin's", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.setOriginLock("")
			f.git(f.proj, "checkout", "-q", "-b", "side")
			f.commitLock(f.proj, good)
			f.git(f.proj, "branch", "origin/main", "side")
			return ""
		},
		check: refused("no .claude/stridal.lock at refs/remotes/origin/main", "git fetch origin")},
	{name: "with no origin, a missing lock refuses", verdict: Refuse,
		setup: func(f *fixture) string {
			f.git(f.proj, "remote", "remove", "origin")
			f.commitLock(f.proj, "")
			must(f.t, os.WriteFile(filepath.Join(f.proj, ".claude", "stridal.lock"), []byte(f.lockFor(f.engineSum())), 0o644))
			return ""
		},
		check: refused("no .claude/stridal.lock at refs/heads/main", "stridal doctor")},
	{name: "a repository with no origin reads its own main", verdict: Run,
		setup: func(f *fixture) string { f.git(f.proj, "remote", "remove", "origin"); return "" },
		check: ranControl(pluginGuard, 0)},
	{name: "with no origin, a lane's own branch does not count", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.git(f.proj, "remote", "remove", "origin")
			f.commitLock(f.proj, f.lockFor(garbage))
			wt := worktree(f, good)
			laneConf(f, wt, "lane")
			return wt
		},
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "with no origin, a lock on another branch does not count", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.git(f.proj, "remote", "remove", "origin")
			f.commitLock(f.proj, "")
			f.git(f.proj, "checkout", "-q", "-b", "side") // the main checkout itself moves
			f.commitLock(f.proj, good)
			return ""
		},
		check: refused("no .claude/stridal.lock at refs/heads/main", "stridal doctor")},
	{name: "with no origin, a detached main checkout still reads main", verdict: Run,
		setup: func(f *fixture) string {
			f.git(f.proj, "remote", "remove", "origin")
			f.git(f.proj, "checkout", "-q", "--detach")
			return ""
		},
		check: ranControl(pluginGuard, 0)},
	{name: "with no origin, stridal.mainBranch names the branch", verdict: Run,
		setup: func(f *fixture) string {
			f.git(f.proj, "remote", "remove", "origin")
			f.commitLock(f.proj, f.lockFor(garbage))
			f.git(f.proj, "branch", "trunk", "HEAD~1") // the clone's first commit: the good lock
			f.git(f.proj, "config", "stridal.mainBranch", "trunk")
			return ""
		},
		check: ranControl(pluginGuard, 0)},
	{name: "with no origin, a worktree's own config does not name main", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.git(f.proj, "remote", "remove", "origin")
			f.commitLock(f.proj, f.lockFor(garbage))
			wt := worktree(f, good)
			f.git(f.proj, "config", "extensions.worktreeConfig", "true")
			f.git(wt, "config", "--worktree", "stridal.mainBranch", "lane")
			return wt
		},
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "a lane's MAIN_BRANCH naming its own pushed branch does not choose the pin", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.setOriginLock(f.lockFor(garbage))
			wt := worktree(f, good)
			laneConf(f, wt, "lane")
			f.git(wt, "push", "-q", "origin", "lane")
			f.git(f.proj, "fetch", "-q", "origin")
			return wt
		},
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "a lane's MAIN_BRANCH naming an older main does not choose the pin", verdict: Refuse,
		setup: func(f *fixture) string {
			f.setOriginLock(f.lockFor(garbage)) // main~1 still holds the good lock
			wt := worktree(f, f.lockFor(garbage))
			laneConf(f, wt, "main~1")
			return wt
		},
		check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")},
	{name: "origin's HEAD names the branch the lock is read from", verdict: Run,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.setOriginLock("")
			f.git(f.up, "checkout", "-q", "-b", "trunk")
			f.setOriginLock(good)
			f.git(f.proj, "remote", "set-head", "origin", "trunk")
			return ""
		},
		check: ranControl(pluginGuard, 0)},
	{name: "origin with no HEAD refuses", verdict: Refuse,
		setup: func(f *fixture) string { f.git(f.proj, "remote", "set-head", "origin", "--delete"); return "" },
		check: refused("origin has no HEAD", "git remote set-head origin --auto")},
	{name: "origin with no HEAD still allows git remote set-head origin --auto", verdict: Refuse,
		setup: func(f *fixture) string {
			f.git(f.proj, "remote", "set-head", "origin", "--delete")
			bash(f, "git remote set-head origin --auto")
			return ""
		},
		check: recovered},
	{name: "origin's HEAD naming a ref off origin refuses", verdict: Refuse,
		setup: func(f *fixture) string {
			f.git(f.proj, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/heads/main")
			return ""
		},
		check: refused("origin's HEAD names refs/heads/main, not a branch of origin", "git remote set-head origin --auto")},
	{name: "origin's HEAD naming a branch outside the plain characters refuses", verdict: Refuse,
		setup: func(f *fixture) string {
			f.git(f.up, "branch", "a+b")
			f.git(f.proj, "fetch", "-q", "origin")
			f.git(f.proj, "remote", "set-head", "origin", "a+b")
			return ""
		},
		check: refused("not a branch of origin", "git remote set-head origin --auto")},
	{name: "a control name with a path refuses", verdict: Run, control: "../guard.sh",
		check: refused("registered without a control name", "claude plugin update stridal@stridal")},
	{name: "an empty control name refuses", verdict: Run, control: "-",
		check: refused("registered without a control name", "claude plugin update stridal@stridal")},
	{name: "a recovery command in a Read payload is refused", verdict: Refuse,
		setup: func(f *fixture) string {
			f.setOriginLock("")
			f.payload = `{"tool_name":"Read","tool_input":{"command":"git fetch origin"}}`
			return ""
		},
		check: refused("no .claude/stridal.lock", "git fetch origin")},
	{name: "a payload that is not JSON is refused", verdict: Refuse,
		setup: func(f *fixture) string { f.setOriginLock(""); f.payload = "git fetch origin"; return "" },
		check: refused("no .claude/stridal.lock", "git fetch origin")},
	{name: "without jq, the refusal says jq is required", verdict: Refuse,
		setup: func(f *fixture) string {
			f.setOriginLock("")
			bash(f, "git fetch origin")
			f.env["PATH"] = pathWithout(f, "jq")
			return ""
		},
		check: func(f *fixture, r result) error {
			if err := refused("no .claude/stridal.lock", "git fetch origin")(f, r); err != nil {
				return err
			}
			if !strings.Contains(r.stderr, "jq is not on PATH") {
				return fmt.Errorf("stderr %q does not say jq is required", r.stderr)
			}
			return nil
		}},
}

// laneConf commits a project.conf naming main in a lane's worktree: the steering a lane can do.
func laneConf(f *fixture, wt, main string) {
	must(f.t, os.WriteFile(filepath.Join(wt, ".claude", "project.conf"), []byte("MAIN_BRANCH=\""+main+"\"\n"), 0o644))
	f.git(wt, "add", "-A")
	f.git(wt, "commit", "-q", "-m", "steer")
}

// pathWithout is a PATH of the tools the launcher and the fixture use, links into one directory,
// with the named ones left out.
func pathWithout(f *fixture, drop ...string) string {
	bin := filepath.Join(f.root, "bin")
	must(f.t, os.MkdirAll(bin, 0o755))
	for _, tool := range []string{"sh", "git", "sed", "awk", "uname", "dirname", "cat", "sha256sum", "shasum", "openssl", "jq", "xcrun"} {
		if slices.Contains(drop, tool) {
			continue
		}
		if p, err := exec.LookPath(tool); err == nil {
			_ = os.Symlink(p, filepath.Join(bin, tool))
		}
	}
	return bin
}

// copyInstall is a `stridal install` project's registration path: the launcher is the project's
// own copy, and there is no CLAUDE_PLUGIN_ROOT, so the plugin root is the one the plugin's
// SessionStart recorded (plugin-session.sh).
func copyInstall(f *fixture) {
	hooks := filepath.Join(f.proj, ".claude", "hooks")
	must(f.t, os.MkdirAll(hooks, 0o755))
	src, err := os.ReadFile(f.launcher)
	must(f.t, err)
	f.launcher = filepath.Join(hooks, "stridal-engine.sh")
	testbin.Write(f.t, f.launcher, string(src))
	testbin.Write(f.t, filepath.Join(hooks, "guard.sh"), "#!/bin/sh\nexit 0\n")
	data := filepath.Join(f.home, ".claude", "plugins", "data", "stridal-stridal")
	must(f.t, os.MkdirAll(data, 0o755))
	must(f.t, os.WriteFile(filepath.Join(data, "root"), []byte(f.plugin+"\n"), 0o644))
	f.env["CLAUDE_PLUGIN_ROOT"] = ""
}

// badMains are names good_branch refuses, one per alternative of its pattern, each reachable:
// stridal.mainBranch is a free string, so each is set there (an origin's HEAD can name
// refs/remotes/origin/-x too, a valid refname).
var badMains = []struct{ alternative, name string }{
	{"empty", ""},
	{"a leading dash", "-x"},
	{"a leading slash", "/x"},
	{"a trailing slash", "x/"},
	{"two dots", "main..x"},
	{"a .lock suffix", "x.lock"},
	{"a revision expression", "main~1"},
	{"a character outside the plain set", "a+b"},
}

func badMainCase(alternative string) string {
	return "with no origin, a stridal.mainBranch with " + alternative + " refuses"
}

func init() {
	for _, b := range badMains {
		b := b
		launcherCases = append(launcherCases, launcherCase{name: badMainCase(b.alternative), verdict: Refuse,
			setup: func(f *fixture) string {
				f.git(f.proj, "remote", "remove", "origin")
				f.git(f.proj, "config", "stridal.mainBranch", b.name)
				return ""
			},
			check: refused("stridal.mainBranch names "+b.name+", not a plain branch name", "stridal doctor")})
	}
	for _, tool := range []string{"openssl", "shasum"} {
		tool := tool
		launcherCases = append(launcherCases,
			launcherCase{name: "hashed with " + tool + ", the pinned engine verifies", verdict: Run,
				setup: func(f *fixture) string { f.env["STRIDAL_SHA256"] = tool; return "" },
				check: ranControl(pluginGuard, 0)},
			launcherCase{name: "hashed with " + tool + ", a mismatched engine is refused", verdict: Refuse,
				setup: func(f *fixture) string {
					f.env["STRIDAL_SHA256"] = tool
					f.writeEngine(fakeEngine + "# not the pinned build\n")
					return ""
				},
				check: refused("is not the one the lock pins", "claude plugin update stridal@stridal")})
	}
	launcherCases = append(launcherCases,
		launcherCase{name: "the copy-install path reads the same lock and engine", verdict: Run,
			setup: func(f *fixture) string { copyInstall(f); return "" },
			check: ranControl(func(f *fixture) string { return filepath.Join(f.proj, ".claude", "hooks", "guard.sh") }, 0)},
		launcherCase{name: "the copy-install path refuses the same mismatch", verdict: Refuse,
			setup: func(f *fixture) string { copyInstall(f); f.setPluginVersion("9.9.9"); return "" },
			check: refused("pins release 9.8.7, and the plugin is 9.9.9", "claude plugin update stridal@stridal")},
	)
}

func runCase(t *testing.T, c launcherCase, mutate func(f *fixture)) (*fixture, string, result) {
	t.Helper()
	f := newFixture(t)
	if mutate != nil {
		mutate(f)
	}
	dir := ""
	if c.setup != nil {
		dir = c.setup(f)
	}
	if dir == "" {
		dir = f.proj
	}
	control := "guard.sh"
	switch c.control {
	case "":
	case "-":
		control = ""
	default:
		control = c.control
	}
	return f, dir, f.runIn(dir, control)
}

func TestLauncherDecisionTable(t *testing.T) {
	for _, c := range launcherCases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f, dir, r := runCase(t, c, nil)
			if err := c.check(f, r); err != nil {
				t.Error(err)
			}
			// The Go twin says the same. A pinned engine that cannot start is Run to Decide: only
			// the launcher, after starting it, can see it fail.
			if d := f.decide(dir); d.Verdict != c.verdict {
				t.Errorf("Decide = %v (%s), want %v", d.Verdict, d.Reason, c.verdict)
			}
		})
	}
}

// A control name is a plain file name beside the launcher; anything else is a registration fault.
func TestABadControlNameRefuses(t *testing.T) {
	f := newFixture(t)
	for _, h := range []string{"", "../guard.sh", "a b.sh", ".hidden.sh"} {
		r := f.run(h)
		if r.code != 2 || r.ran {
			t.Errorf("control %q: exit %d, ran %v; want refused", h, r.code, r.ran)
		}
	}
}

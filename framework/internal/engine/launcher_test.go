package engine

import (
	"fmt"
	"os"
	"path/filepath"
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
	// verdict is what the Go twin (Decide) must say about the same fixture.
	verdict Verdict
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
	{name: "a repository with no origin reads its own main", verdict: Run,
		setup: func(f *fixture) string { f.git(f.proj, "remote", "remove", "origin"); return "" },
		check: ranControl(pluginGuard, 0)},
	{name: "with no origin, a lock on another branch does not count", verdict: Refuse,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.git(f.proj, "remote", "remove", "origin")
			f.commitLock(f.proj, "")
			f.git(f.proj, "checkout", "-q", "-b", "side")
			f.commitLock(f.proj, good)
			return ""
		},
		check: refused("no .claude/stridal.lock at refs/heads/main", "stridal doctor")},
	{name: "the last MAIN_BRANCH assignment wins", verdict: Run,
		setup: func(f *fixture) string {
			must(f.t, os.WriteFile(filepath.Join(f.proj, ".claude", "project.conf"), []byte("MAIN_BRANCH=\"trunk\"\nMAIN_BRANCH=main\n"), 0o644))
			return ""
		},
		check: ranControl(pluginGuard, 0)},
	{name: "MAIN_BRANCH names the branch the lock is read from", verdict: Run,
		setup: func(f *fixture) string {
			good := f.lockFor(f.engineSum())
			f.setOriginLock("")
			f.git(f.up, "checkout", "-q", "-b", "trunk")
			f.setOriginLock(good)
			must(f.t, os.WriteFile(filepath.Join(f.proj, ".claude", "project.conf"), []byte("MAIN_BRANCH=\"trunk\"\n"), 0o644))
			return ""
		},
		check: ranControl(pluginGuard, 0)},
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

func init() {
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
	return f, dir, f.runIn(dir, "guard.sh")
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

func TestABadControlNameRefuses(t *testing.T) {
	f := newFixture(t)
	for _, h := range []string{"", "../guard.sh", "a b.sh", ".hidden.sh"} {
		r := f.run(h)
		if r.code != 2 || r.ran {
			t.Errorf("control %q: exit %d, ran %v; want refused", h, r.code, r.ran)
		}
	}
}

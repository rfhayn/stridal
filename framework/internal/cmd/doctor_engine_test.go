package cmd

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/rfhayn/stridal/internal/engine"
	"github.com/rfhayn/stridal/internal/testbin"
)

// lockedRepo is a repository /stridal:init set up, on main, with no origin, whose main holds lock
// ("" for none).
func lockedRepo(t *testing.T, lock string) string {
	t.Helper()
	dir := newRepo(t)
	gitIn(t, dir, "symbolic-ref", "HEAD", "refs/heads/main")
	write(t, dir, pluginMarker, "the plugin\n")
	if lock != "" {
		write(t, dir, engine.LockPath, lock)
		gitIn(t, dir, "add", engine.LockPath)
	}
	gitIn(t, dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "init")
	return dir
}

// fakePlugin is a plugin root at version holding an engine for this platform; it returns the root
// and the engine's sha256.
func fakePlugin(t *testing.T, version string) (string, string) {
	t.Helper()
	root := t.TempDir()
	write(t, root, ".claude-plugin/plugin.json", `{"name": "stridal", "version": "`+version+`"}`+"\n")
	bin := filepath.Join(root, "engine", runtime.GOOS+"-"+runtime.GOARCH, "stridal")
	if err := os.MkdirAll(filepath.Dir(bin), 0o755); err != nil {
		t.Fatal(err)
	}
	testbin.Write(t, bin, "#!/bin/sh\nexit 0\n")
	sum, err := engine.FileSHA256(bin)
	if err != nil {
		t.Fatal(err)
	}
	return root, sum
}

// Doctor names what the launcher would decide in a marked repository, from the same table
// (engine.Decide): a missing lock is a note with its fix, a verified engine is ok, and a
// repository with no model gets no engine line.
func TestDoctorEngineLineIsTheLaunchersDecision(t *testing.T) {
	tmplDir(t)
	root, sum := fakePlugin(t, "1.2.3")
	t.Setenv("CLAUDE_PLUGIN_ROOT", root)

	t.Chdir(lockedRepo(t, ""))
	out, err := doctor(t, gitPath(t, allTools...))
	if err != nil {
		t.Fatal(err)
	}
	l := needLine(t, out, "note", "engine", "no .claude/stridal.lock at refs/heads/main")
	if !strings.Contains(detailOf(out, l), "nothing is refused today") {
		t.Errorf("the note does not say the launcher is not registered yet: %s", l)
	}
	needExact(t, out, "fix: stridal doctor")
	// With no origin, doctor says where main comes from and how to name another.
	if l := needLine(t, out, "note", "main", "git config stridal.mainBranch"); !strings.Contains(detailOf(out, l), "never the checked-out branch") {
		t.Errorf("the main line does not say the checkout never names main: %s", l)
	}

	lock := string((&engine.Lock{Release: "1.2.3", Engines: map[string]string{engine.Platform(): sum}}).Format())
	t.Chdir(lockedRepo(t, lock))
	out, err = doctor(t, gitPath(t, allTools...))
	if err != nil {
		t.Fatal(err)
	}
	needLine(t, out, "ok", "engine", "pins release 1.2.3", "verifies")

	t.Chdir(lockedRepo(t, strings.Replace(lock, "1.2.3", "1.2.4", 1)))
	out, _ = doctor(t, gitPath(t, allTools...))
	needLine(t, out, "note", "engine", "pins release 1.2.4, and the plugin is 1.2.3")
	needExact(t, out, "fix: claude plugin update stridal@stridal")

	t.Chdir(newRepo(t))
	out, _ = doctor(t, gitPath(t, allTools...))
	if subjectLine(out, "engine") != "" {
		t.Errorf("a repository with no model has an engine line:\n%s", out)
	}
}

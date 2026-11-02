package plugin

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// ifProject is one repository and the hook as the plugin build ships it, with a stand-in control.
type ifProject struct {
	t    *testing.T
	hook string
	dir  string
	e    []string
}

func newIfProject(t *testing.T) *ifProject {
	t.Helper()
	need(t, "git", "sh")
	src, err := os.ReadFile(filepath.Join("assets", "hooks", "if-project.sh"))
	if err != nil {
		t.Fatal(err)
	}
	hooks := filepath.Join(t.TempDir(), "hooks")
	if err := os.MkdirAll(hooks, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, body := range map[string]string{"if-project.sh": string(src), "ran.sh": "#!/bin/sh\necho RAN\n"} {
		if err := os.WriteFile(filepath.Join(hooks, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return &ifProject{t: t, hook: filepath.Join(hooks, "if-project.sh"), e: env(t, t.TempDir())}
}

func (p *ifProject) git(dir string, args ...string) {
	p.t.Helper()
	if out, code := run(p.t, dir, p.e, "", "git", args...); code != 0 {
		p.t.Fatalf("git %v: %s", args, out)
	}
}

// commitMarker makes dir a repository on branch whose tree holds the plugin's marker.
func (p *ifProject) commitMarker(dir, branch string) {
	p.t.Helper()
	p.git(dir, "init", "-q", "-b", branch)
	p.writeMarker(dir)
	p.git(dir, "add", "-A")
	p.git(dir, "commit", "-qm", "marker")
}

func (p *ifProject) writeMarker(dir string) {
	p.t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
		p.t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".claude", "stridal-plugin"), []byte("m\n"), 0o644); err != nil {
		p.t.Fatal(err)
	}
}

func (p *ifProject) deleteMarker(dir string) {
	p.t.Helper()
	if err := os.Remove(filepath.Join(dir, ".claude", "stridal-plugin")); err != nil {
		p.t.Fatal(err)
	}
}

// ran says the control ran for a session rooted at dir, under extra environment.
func (p *ifProject) ran(dir string, extra ...string) bool {
	p.t.Helper()
	e := append(append(append([]string{}, p.e...), "CLAUDE_PROJECT_DIR="+dir), extra...)
	out, code := run(p.t, dir, e, "", "sh", p.hook, "ran.sh")
	if code != 0 {
		p.t.Fatalf("exit %d: %s", code, out)
	}
	return strings.Contains(out, "RAN")
}

// clone is a clone of a repository whose main holds the marker.
func (p *ifProject) clone() string {
	p.t.Helper()
	up := p.t.TempDir()
	p.commitMarker(up, "main")
	dir := filepath.Join(p.t.TempDir(), "clone")
	p.git(filepath.Dir(dir), "clone", "-q", up, dir)
	return dir
}

// ADR-0018 decision 5's amendment, each sentence that holds in a repository, as the hook reads it.
func TestIfProjectCountsAMarkerInTheWorktreeOrOnMain(t *testing.T) {
	t.Run("in the worktree", func(t *testing.T) {
		p := newIfProject(t)
		dir := t.TempDir()
		p.git(dir, "init", "-q", "-b", "main")
		p.writeMarker(dir)
		if !p.ran(dir) {
			t.Error("stood aside")
		}
	})
	t.Run("nowhere", func(t *testing.T) {
		p := newIfProject(t)
		dir := t.TempDir()
		p.git(dir, "init", "-q", "-b", "main")
		p.git(dir, "commit", "-q", "--allow-empty", "-m", "x")
		if p.ran(dir) {
			t.Error("ran in an unmarked repository")
		}
	})
	t.Run("on origin's main, gone from the worktree", func(t *testing.T) {
		p := newIfProject(t)
		dir := p.clone()
		p.deleteMarker(dir)
		if !p.ran(dir) {
			t.Error("stood aside")
		}
	})
	t.Run("on origin's main with no local main, gone from the worktree", func(t *testing.T) {
		p := newIfProject(t)
		dir := p.clone()
		p.git(dir, "branch", "-m", "main", "lane")
		p.deleteMarker(dir)
		if !p.ran(dir) {
			t.Error("stood aside")
		}
	})
	t.Run("on a local main with no origin, gone from the worktree", func(t *testing.T) {
		p := newIfProject(t)
		dir := t.TempDir()
		p.commitMarker(dir, "main")
		p.deleteMarker(dir)
		if !p.ran(dir) {
			t.Error("stood aside")
		}
	})
	t.Run("a branch with no .claude of a marked repository", func(t *testing.T) {
		p := newIfProject(t)
		dir := p.clone()
		p.git(dir, "checkout", "-q", "--orphan", "other")
		p.git(dir, "rm", "-rfq", ".")
		if !p.ran(dir) {
			t.Error("stood aside")
		}
	})
}

// The hook reads only origin's HEAD and a branch named main, which keeps it to one git process, so a
// repository with no origin and another main is known by its worktree's marker alone.
func TestIfProjectsNoOriginException(t *testing.T) {
	p := newIfProject(t)
	dir := t.TempDir()
	p.commitMarker(dir, "trunk")
	if !p.ran(dir) {
		t.Error("the marker in the worktree did not count")
	}
	p.deleteMarker(dir)
	if p.ran(dir) {
		t.Error("the exception no longer holds: the amendment in ADR-0018 says otherwise")
	}
}

// A session rooted below a repository's top stands aside, as it always has, reading nothing.
func TestIfProjectStandsAsideBelowTheTop(t *testing.T) {
	p := newIfProject(t)
	dir := p.clone()
	sub := filepath.Join(dir, "sub")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	if p.ran(sub) {
		t.Error("ran in a session below the top")
	}
}

// stubGit puts a git first on PATH that logs each run with the settings the read must carry.
func stubGit(t *testing.T) (pathEnv, log string) {
	t.Helper()
	real, err := exec.LookPath("git")
	if err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	log = filepath.Join(t.TempDir(), "git.log")
	script := "#!/bin/sh\necho \"lazy=$GIT_NO_LAZY_FETCH replace=$GIT_NO_REPLACE_OBJECTS\" >> '" + log + "'\nexec '" + real + "' \"$@\"\n"
	if err := os.WriteFile(filepath.Join(bin, "git"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return "PATH=" + bin + ":" + os.Getenv("PATH"), log
}

// It fires about ten times per Bash call in every repository a user-scope plugin sees: one git
// process where there is a .git, none where there is not. And the read stays local and literal: it
// never fetches a missing object and never takes a replacement for one.
func TestIfProjectsMarkerReadIsOneLocalGitProcess(t *testing.T) {
	p := newIfProject(t)
	dir := p.clone()
	p.deleteMarker(dir)
	path, log := stubGit(t)
	if !p.ran(dir, path) {
		t.Fatal("stood aside")
	}
	data, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(string(data)); got != "lazy=1 replace=1" {
		t.Errorf("git ran as %q, want one process with lazy=1 replace=1", got)
	}

	path, log = stubGit(t)
	plain := t.TempDir()
	if p.ran(plain, path) {
		t.Error("ran in a directory with no repository")
	}
	if _, err := os.Stat(log); err == nil {
		t.Error("a directory with no .git still ran git")
	}
}

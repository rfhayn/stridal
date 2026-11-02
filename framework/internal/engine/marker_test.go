package engine

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rfhayn/stridal/internal/testbin"
)

// commitMarkerOnMain puts the plugin's marker on origin's main and fetches it, leaving the checkout's
// own file for the test to keep or delete.
func commitMarkerOnMain(f *fixture) {
	f.t.Helper()
	f.mark(f.up)
	f.git(f.up, "add", ".claude/stridal-plugin")
	f.git(f.up, "commit", "-q", "-m", "marker")
	f.git(f.proj, "fetch", "-q", "origin")
}

func TestHasMarkerReadsTheWorktreeThenMainsTree(t *testing.T) {
	t.Parallel()
	gone := func(f *fixture) { must(f.t, os.Remove(filepath.Join(f.proj, ".claude", "stridal-plugin"))) }
	cases := []struct {
		name  string
		setup func(f *fixture) string
		want  bool
	}{
		{"in the worktree", func(f *fixture) string { return f.proj }, true},
		{"nowhere", func(f *fixture) string { gone(f); return f.proj }, false},
		{"on origin's main, gone from the worktree", func(f *fixture) string { commitMarkerOnMain(f); gone(f); return f.proj }, true},
		{"on a branch of no origin that origin's HEAD names", func(f *fixture) string {
			f.git(f.proj, "add", ".claude/stridal-plugin")
			f.git(f.proj, "commit", "-q", "-m", "marker")
			f.git(f.proj, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/heads/main")
			gone(f)
			return f.proj
		}, false},
		{"with no origin, on the branch the key names", func(f *fixture) string {
			f.git(f.proj, "checkout", "-q", "-b", "trunk")
			f.git(f.proj, "add", ".claude/stridal-plugin")
			f.git(f.proj, "commit", "-q", "-m", "marker")
			f.git(f.proj, "remote", "remove", "origin")
			f.git(f.proj, "config", MainBranchKey, "trunk")
			gone(f)
			return f.proj
		}, true},
		{"with no origin, a key that names no plain branch", func(f *fixture) string {
			f.git(f.proj, "add", ".claude/stridal-plugin")
			f.git(f.proj, "commit", "-q", "-m", "marker")
			f.git(f.proj, "remote", "remove", "origin")
			f.git(f.proj, "config", MainBranchKey, "main~0")
			gone(f)
			return f.proj
		}, false},
		{"a session below the top", func(f *fixture) string {
			commitMarkerOnMain(f)
			gone(f)
			sub := filepath.Join(f.proj, "sub")
			must(f.t, os.MkdirAll(sub, 0o755))
			return sub
		}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			if got := HasMarker(c.setup(f)); got != c.want {
				t.Errorf("HasMarker = %v, want %v", got, c.want)
			}
		})
	}
}

// The read stays local and literal: it never fetches a missing object and never takes a replacement
// for one. Not parallel: HasMarker takes PATH from this process.
func TestHasMarkersReadIsLocalAndLiteral(t *testing.T) {
	f := newFixture(t)
	commitMarkerOnMain(f)
	must(t, os.Remove(filepath.Join(f.proj, ".claude", "stridal-plugin")))
	real, err := exec.LookPath("git")
	must(t, err)
	bin := filepath.Join(f.root, "bin")
	must(t, os.MkdirAll(bin, 0o755))
	log := filepath.Join(f.root, "catfile.log")
	testbin.Write(t, filepath.Join(bin, "git"), "#!/bin/sh\ncase \" $* \" in *\" cat-file \"*) echo \"lazy=$GIT_NO_LAZY_FETCH replace=$GIT_NO_REPLACE_OBJECTS\" >> '"+log+"' ;; esac\nexec '"+real+"' \"$@\"\n")
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
	if !HasMarker(f.proj) {
		t.Fatal("HasMarker missed the marker on main's tree")
	}
	got, err := os.ReadFile(log)
	must(t, err)
	if strings.TrimSpace(string(got)) != "lazy=1 replace=1" {
		t.Errorf("cat-file ran as %q", got)
	}
}

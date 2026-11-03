package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/rfhayn/stridal/internal/panel/install"
	"github.com/rfhayn/stridal/internal/testbin"
	"github.com/rfhayn/stridal/internal/testgit"
	"github.com/rfhayn/stridal/internal/testwait"
)

// The merge guard takes main from origin's HEAD (OPS-219), which `git init` and a first push leave
// unset, so install and init set it. With no origin there is nothing to set, and with one it cannot
// reach, they say how.
func TestSetOriginHead(t *testing.T) {
	bare := filepath.Join(t.TempDir(), "origin.git")
	gitIn(t, filepath.Dir(bare), "init", "-q", "--bare", "-b", "main", bare)
	dir := newRepo(t)
	gitIn(t, dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "first")
	gitIn(t, dir, "branch", "-M", "main")

	var out bytes.Buffer
	setOriginHead(&out, dir)
	if out.Len() != 0 {
		t.Errorf("no origin: said %q", out.String())
	}

	gitIn(t, dir, "remote", "add", "origin", bare)
	gitIn(t, dir, "push", "-q", "origin", "main")
	setOriginHead(&out, dir)
	head, err := testgit.Command(dir, "symbolic-ref", "refs/remotes/origin/HEAD").Output()
	if err != nil || strings.TrimSpace(string(head)) != "refs/remotes/origin/main" {
		t.Errorf("origin's HEAD after setOriginHead: %q, %v; said %q", head, err, out.String())
	}

	gitIn(t, dir, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
	gitIn(t, dir, "remote", "set-url", "origin", filepath.Join(t.TempDir(), "gone.git"))
	out.Reset()
	setOriginHead(&out, dir)
	if !strings.Contains(out.String(), "git remote set-head origin") {
		t.Errorf("an origin it cannot reach: said %q, want the fix", out.String())
	}

	// The note's own command, in a clone that has never fetched: the fix it states must be one that works.
	clone := newRepo(t)
	gitIn(t, clone, "remote", "add", "origin", filepath.Join(t.TempDir(), "gone.git"))
	out.Reset()
	setOriginHead(&out, clone)
	_, command, ok := strings.Cut(strings.TrimSpace(out.String()), "first merge: ")
	if !ok {
		t.Fatalf("a never-fetched clone: said %q, want the fix", out.String())
	}
	gitIn(t, clone, "remote", "set-url", "origin", bare)
	run := execCommand("/bin/sh", "-c", strings.ReplaceAll(command, "<your main branch>", "main"))
	run.Dir = clone
	if said, err := run.CombinedOutput(); err != nil {
		t.Errorf("the note's command %q: %v\n%s", command, err, said)
	}
	head, err = testgit.Command(clone, "symbolic-ref", "refs/remotes/origin/HEAD").Output()
	if err != nil || strings.TrimSpace(string(head)) != "refs/remotes/origin/main" {
		t.Errorf("origin's HEAD after the note's command: %q, %v", head, err)
	}
}

// An origin that never answers holds neither update nor install: the question has a time limit, the
// note is printed, the update finishes, and what git started on the way is ended with it.
func TestUpdateOutlivesAnOriginThatHangs(t *testing.T) {
	dir := repoWithUnsetOriginHead(t)
	bin := t.TempDir()
	child := filepath.Join(t.TempDir(), "child.pid")
	prompt := filepath.Join(t.TempDir(), "prompt")
	testbin.Write(t, filepath.Join(bin, "git"), "#!/bin/sh\ncase \"$*\" in *set-head*) echo \"$GIT_TERMINAL_PROMPT\" > "+install.ShellWord(prompt)+"; sleep 30 & echo $! > "+install.ShellWord(child)+"; wait ;; esac\nexec "+install.ShellWord(testgit.Path)+" \"$@\"\n")
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	oldLimit := originHeadTimeout
	originHeadTimeout = 200 * time.Millisecond
	t.Cleanup(func() { originHeadTimeout = oldLimit })
	oldIn := stdin
	stdin = bufioReader("")
	t.Cleanup(func() { stdin = oldIn })
	var out bytes.Buffer
	updateCmd.SetOut(&out)
	t.Cleanup(func() { updateCmd.SetOut(nil) })

	if err := runUpdate(t, dir, false); err != nil {
		t.Fatalf("update: %v", err)
	}
	// With no limit the stand-in ends by itself, exit 0, and no note is printed.
	if !strings.Contains(out.String(), "git fetch origin && git remote set-head origin") {
		t.Errorf("no note on a timeout:\n%s", out.String())
	}
	if !strings.Contains(out.String(), "Update complete.") {
		t.Errorf("update did not carry on to its end:\n%s", out.String())
	}
	// git must not wait on a prompt that nobody in a background group can answer.
	if saw, err := os.ReadFile(prompt); err != nil || strings.TrimSpace(string(saw)) != "0" {
		t.Errorf("set-head ran with GIT_TERMINAL_PROMPT=%q, want 0 (%v)", saw, err)
	}
	raw, err := os.ReadFile(child)
	if err != nil {
		t.Fatalf("the stand-in never started its child: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatalf("child pid %q: %v", raw, err)
	}
	testwait.For(t, "the hung git's child to end with the timeout", 5*time.Second, func() bool {
		return syscall.Kill(pid, 0) != nil
	})
}

// repoWithUnsetOriginHead is a project with an origin added after its install: a first push leaves
// origin's HEAD unset.
func repoWithUnsetOriginHead(t *testing.T) string {
	t.Helper()
	dir := newRepo(t)
	if err := writeInstallMarker(dir); err != nil {
		t.Fatal(err)
	}
	if out, err := runInstall(t, dir, false); err != nil {
		t.Fatalf("install: %v\n%s", err, out)
	}
	bare := filepath.Join(t.TempDir(), "origin.git")
	gitIn(t, dir, "init", "-q", "--bare", "-b", "main", bare)
	gitIn(t, dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "first")
	gitIn(t, dir, "branch", "-M", "main")
	gitIn(t, dir, "remote", "add", "origin", bare)
	gitIn(t, dir, "push", "-q", "origin", "main")
	return dir
}

// `stridal update` sets it on every way out, for a clone that predates the guard reading main: with
// nothing to review, after a review, and when the review is cancelled. --dry-run changes nothing.
func TestUpdateSetsOriginHead(t *testing.T) {
	originHead := func(dir string) bool {
		return testgit.Command(dir, "symbolic-ref", "-q", "refs/remotes/origin/HEAD").Run() == nil
	}
	for _, c := range []struct {
		name, answers string
		edited        bool
	}{
		{"nothing to review", "", false},
		{"after a review", "s\n", true},
		{"a cancelled review", "c\n", true},
	} {
		t.Run(c.name, func(t *testing.T) {
			dir := repoWithUnsetOriginHead(t)
			if c.edited {
				write(t, dir, ".claude/hooks/format.sh", "# a project's own edit\n")
			}
			old := stdin
			stdin = bufioReader(c.answers)
			t.Cleanup(func() { stdin = old })

			if err := runUpdate(t, dir, true); err != nil {
				t.Fatalf("update --dry-run: %v", err)
			}
			if originHead(dir) {
				t.Fatal("update --dry-run set origin's HEAD")
			}
			if err := runUpdate(t, dir, false); err != nil {
				t.Fatalf("update: %v", err)
			}
			if !originHead(dir) {
				t.Errorf("update left origin's HEAD unset")
			}
		})
	}
}

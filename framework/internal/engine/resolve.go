package engine

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// goodBranchRe and GoodBranch are the launcher's good_branch: a plain branch name. git already
// refuses an invalid symbolic ref (an origin/HEAD naming main~1 reads as no HEAD), and this is
// stricter than git check-ref-format --branch.
var goodBranchRe = regexp.MustCompile(`^[A-Za-z0-9/._-]+$`)

// GoodBranch says name is a plain branch name the launcher accepts as main.
func GoodBranch(name string) bool {
	return goodBranchRe.MatchString(name) && !strings.HasPrefix(name, "-") && !strings.HasPrefix(name, "/") &&
		!strings.HasSuffix(name, "/") && !strings.Contains(name, "..") && !strings.HasSuffix(name, ".lock")
}

// ErrNoLock is a lock that is not there: no ref to read it from, or no file at the ref.
var ErrNoLock = errors.New("no lock")

// lockError is why no lock could be read, and the one command that clears it (the launcher's).
type lockError struct {
	msg, fix string
	noLock   bool
}

func (e lockError) Error() string { return e.msg }
func (e lockError) Unwrap() error {
	if e.noLock {
		return ErrNoLock
	}
	return nil
}

// FixOf is the fix line for an error ReadLock returned, or "" for another error.
func FixOf(err error) string {
	var le lockError
	if errors.As(err, &le) {
		return le.fix
	}
	return ""
}

// MainRef is the ref a repository's lock is read from, the launcher's way. Which branch is main
// comes from git's own record, never from the working tree, which a lane can edit (its
// project.conf could name a branch it pushed, or main~1, an older pin):
//   - with an origin, origin's HEAD (set by clone; `git remote set-head origin --auto` sets it
//     again), and a repository whose origin has no HEAD is refused;
//   - with no origin, the branch the main worktree has checked out (the first entry of git
//     worktree list), which a lane's own worktree does not change.
//
// Full ref names, so a local branch named "origin/main" cannot stand in for the remote's.
func MainRef(ctx context.Context, projectDir string) (string, error) {
	if out, err := gitOut(ctx, projectDir, "symbolic-ref", "-q", "refs/remotes/origin/HEAD"); err == nil {
		head := strings.TrimSpace(string(out))
		main, ok := strings.CutPrefix(head, "refs/remotes/origin/")
		if !ok || !GoodBranch(main) {
			return "", lockError{msg: "origin's HEAD names " + head + ", not a branch of origin", fix: FixSetHead}
		}
		return "refs/remotes/origin/" + main, nil
	}
	if _, err := gitOut(ctx, projectDir, "config", "--get", "remote.origin.url"); err == nil {
		return "", lockError{msg: "origin has no HEAD, so which of its branches is main is unknown", fix: FixSetHead}
	}
	out, _ := gitOut(ctx, projectDir, "worktree", "list", "--porcelain")
	main := ""
	sc := bufio.NewScanner(bytes.NewReader(out))
	for sc.Scan() {
		line := sc.Text()
		if line == "" {
			break // the first entry is the main worktree
		}
		if b, ok := strings.CutPrefix(line, "branch refs/heads/"); ok {
			main = b
		}
	}
	if !GoodBranch(main) {
		return "", lockError{msg: "with no origin, the main worktree has no branch to read the lock from", fix: FixDoctor}
	}
	return "refs/heads/" + main, nil
}

// ReadLock reads and parses the lock at MainRef, and says which ref it read. Every worktree of a
// repository shares its refs, so a worktree reads main's lock and never its own working-tree
// copy: that is what makes main's pin the one that guards every lane. There is no fallback to the
// working tree, nor from origin to a local ref: a guard that falls back reads a pin its subject
// can edit. The error carries the launcher's fix line (FixOf).
func ReadLock(ctx context.Context, projectDir string) (*Lock, string, error) {
	ref, err := MainRef(ctx, projectDir)
	if err != nil {
		return nil, "", err
	}
	fix := FixFetch
	if strings.HasPrefix(ref, "refs/heads/") {
		fix = FixDoctor // with no origin there is nothing to fetch: the lock is committed to main
	}
	data, err := gitOut(ctx, projectDir, "cat-file", "blob", ref+":"+LockPath)
	if err != nil {
		return nil, ref, lockError{msg: "no " + LockPath + " at " + ref, fix: fix, noLock: true}
	}
	l, err := Parse(data)
	if err != nil {
		return nil, ref, lockError{msg: fmt.Sprintf("%s at %s does not parse: %v", LockPath, ref, err), fix: FixDoctor}
	}
	return l, ref, nil
}

func gitOut(ctx context.Context, dir string, args ...string) ([]byte, error) {
	cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return exec.CommandContext(cctx, "git", append([]string{"-C", dir}, args...)...).Output()
}

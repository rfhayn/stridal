package engine

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// mainBranchRe reads MAIN_BRANCH from .claude/project.conf the way the launcher's sed does: a
// plain assignment, quoted or not, the last one winning. A value that needs a shell to expand
// is read as it stands, names no ref, and so reads as a missing lock: refused, never allowed.
var mainBranchRe = regexp.MustCompile(`^MAIN_BRANCH="?([^" \t]*)"?[ \t]*$`)

// MainBranch is the project's MAIN_BRANCH, or "main" when project.conf has none.
func MainBranch(projectDir string) string {
	data, err := os.ReadFile(filepath.Join(projectDir, ".claude", "project.conf"))
	if err != nil {
		return "main"
	}
	main := ""
	for _, line := range strings.Split(string(data), "\n") {
		if m := mainBranchRe.FindStringSubmatch(line); m != nil {
			main = m[1]
		}
	}
	if main == "" {
		return "main"
	}
	return main
}

// ErrNoLock is a lock that is not there: no ref to read it from, or no file at the ref.
var ErrNoLock = errors.New("no lock")

// noLock says which ref held no lock, and is ErrNoLock.
type noLock struct{ ref string }

func (e noLock) Error() string { return "no " + LockPath + " at " + e.ref }
func (e noLock) Unwrap() error { return ErrNoLock }

// ReadLock reads and parses the lock, and says which ref it read: origin's main, or, only in a
// repository with no origin at all, its own main (a fork, or a project not yet pushed; ADR-0018
// decision 2). Full ref names, so a local branch named "origin/main" cannot stand in for the
// remote's. The launcher reads the same refs in the same order.
//
// Every worktree of a repository shares its refs, so a worktree reads main's lock and never its
// own working-tree copy: that is what makes main's pin the one that guards every lane. A ref or
// file that is missing is ErrNoLock; a lock that does not parse is an error naming the line. There
// is no fallback to the working tree, nor from origin to a local ref: a guard that falls back reads
// a pin its subject can edit.
func ReadLock(ctx context.Context, projectDir string) (*Lock, string, error) {
	main := MainBranch(projectDir)
	ref := "refs/remotes/origin/" + main
	data, err := catLock(ctx, projectDir, ref)
	if err != nil && git(ctx, projectDir, "config", "--get", "remote.origin.url") != nil {
		ref = "refs/heads/" + main
		data, err = catLock(ctx, projectDir, ref)
	}
	if err != nil {
		return nil, ref, noLock{ref}
	}
	l, err := Parse(data)
	if err != nil {
		return nil, ref, fmt.Errorf("%s at %s does not parse: %w", LockPath, ref, err)
	}
	return l, ref, nil
}

func catLock(ctx context.Context, dir, ref string) ([]byte, error) {
	cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return exec.CommandContext(cctx, "git", "-C", dir, "cat-file", "blob", ref+":"+LockPath).Output()
}

func git(ctx context.Context, dir string, args ...string) error {
	cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return exec.CommandContext(cctx, "git", append([]string{"-C", dir}, args...)...).Run()
}

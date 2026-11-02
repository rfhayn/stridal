// Package engine is the floor under the operating model's controls (ADR-0016 to ADR-0018): the
// lock that pins the plugin release guarding a repository, where that lock is read from, and the
// state a guarded call is judged in. The bootstrap launcher (template/.claude/hooks/
// stridal-engine.sh) makes the same decision in sh, because it runs before any engine is trusted;
// this package is its Go twin, for `stridal doctor` and for the tests that hold the two equal.
package engine

import (
	"bytes"
	"fmt"
	"regexp"
	"runtime"
	"sort"
	"strings"
)

// LockPath is where a repository pins its release, relative to its root. It is read from
// origin/<main>, never from the working tree (ReadLock).
const LockPath = ".claude/stridal.lock"

// Lock is a parsed .claude/stridal.lock: the plugin release a repository is guarded by, and the
// sha256 of that release's engine for each platform.
//
// The format is line-based, like go.sum, so the sh launcher reads it with awk and no JSON tool:
//
//	# comments and blank lines are ignored
//	release 0.4.2
//	engine darwin/arm64 <64 lowercase hex>
//	engine linux/amd64 <64 lowercase hex>
//
// Exactly one release line, at least one engine line, no platform twice, and nothing else. A
// line Parse does not know is an error, not a line skipped: a lock is read by guards, and a
// guard that skips what it does not understand allows what it was meant to refuse.
type Lock struct {
	Release string
	Engines map[string]string // "goos/goarch" -> sha256 hex
}

var (
	releaseRe  = regexp.MustCompile(`^[0-9A-Za-z][0-9A-Za-z.+-]*$`)
	platformRe = regexp.MustCompile(`^[a-z0-9]+/[a-z0-9]+$`)
	sha256Re   = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

// Parse reads a lock, refusing anything but the format above.
func Parse(data []byte) (*Lock, error) {
	l := &Lock{Engines: map[string]string{}}
	for i, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Fields(line)
		n := i + 1
		switch f[0] {
		case "release":
			if len(f) != 2 || !releaseRe.MatchString(f[1]) {
				return nil, fmt.Errorf("line %d: want `release <version>`, got %q", n, line)
			}
			if l.Release != "" {
				return nil, fmt.Errorf("line %d: a second release line", n)
			}
			l.Release = f[1]
		case "engine":
			if len(f) != 3 || !platformRe.MatchString(f[1]) || !sha256Re.MatchString(f[2]) {
				return nil, fmt.Errorf("line %d: want `engine <goos>/<goarch> <sha256, 64 lowercase hex>`, got %q", n, line)
			}
			if _, dup := l.Engines[f[1]]; dup {
				return nil, fmt.Errorf("line %d: %s is pinned twice", n, f[1])
			}
			l.Engines[f[1]] = f[2]
		default:
			return nil, fmt.Errorf("line %d: unknown keyword %q (a lock holds only release and engine lines)", n, f[0])
		}
	}
	if l.Release == "" {
		return nil, fmt.Errorf("no release line")
	}
	if len(l.Engines) == 0 {
		return nil, fmt.Errorf("no engine line")
	}
	return l, nil
}

// Format writes a lock Parse reads back as the same value, platforms sorted.
func (l *Lock) Format() []byte {
	var b bytes.Buffer
	b.WriteString("# The plugin release that guards this repository, and its engines' sha256s (ADR-0018).\n")
	b.WriteString("# Read from origin/<main>, so every worktree is guarded by main's pin.\n")
	fmt.Fprintf(&b, "release %s\n", l.Release)
	platforms := make([]string, 0, len(l.Engines))
	for p := range l.Engines {
		platforms = append(platforms, p)
	}
	sort.Strings(platforms)
	for _, p := range platforms {
		fmt.Fprintf(&b, "engine %s %s\n", p, l.Engines[p])
	}
	return b.Bytes()
}

// Platform is the running platform as the lock names it.
func Platform() string { return runtime.GOOS + "/" + runtime.GOARCH }

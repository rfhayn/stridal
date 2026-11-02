package engine

import (
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rfhayn/stridal/internal/testbin"
)

var (
	builtOnce sync.Once
	builtPath string
	builtErr  error
)

// realEngine builds this checkout's stridal once per test binary, the engine a release carries.
func realEngine(t *testing.T) string {
	t.Helper()
	if testing.Short() {
		t.Skip("builds the stridal binary")
	}
	builtOnce.Do(func() {
		dir, err := os.MkdirTemp("", "engine-build-")
		if err != nil {
			builtErr = err
			return
		}
		builtPath = filepath.Join(dir, "stridal")
		out, err := exec.Command("go", "build", "-trimpath", "-o", builtPath, "../../cmd/stridal").CombinedOutput()
		if err != nil {
			builtErr = err
			builtPath = string(out)
		}
	})
	if builtErr != nil {
		t.Fatalf("go build: %v\n%s", builtErr, builtPath)
	}
	return builtPath
}

// realFixture is a fixture whose engine is the real stridal, pinned by origin's lock.
func realFixture(t *testing.T) *fixture {
	t.Helper()
	bin := realEngine(t)
	f := newFixture(t)
	data, err := os.ReadFile(bin)
	must(t, err)
	testbin.Write(t, f.enginePath(), string(data))
	f.setOriginLock(f.lockFor(f.engineSum()))
	return f
}

// The real engine's `hook` runs the shell control in its place: the control's exit status and
// stderr are the verdict, and the control reads the payload the launcher left unread.
func TestTheRealEngineRunsTheControl(t *testing.T) {
	f := realFixture(t)
	testbin.Write(t, filepath.Join(f.plugin, "hooks", "guard.sh"),
		"#!/bin/sh\npayload=$(cat)\ncase $payload in *'rm -rf'*) echo 'guard: no rm -rf' >&2; exit 2 ;; esac\nexit 0\n")
	r := f.run("guard.sh")
	if r.code != 2 || !strings.Contains(r.stderr, "guard: no rm -rf") {
		t.Errorf("a control that refuses: exit %d, stderr %q; want 2 and the control's own line", r.code, r.stderr)
	}
	bash(f, "ls")
	if r := f.run("guard.sh"); r.code != 0 {
		t.Errorf("a control that allows: exit %d, stderr %q", r.code, r.stderr)
	}
	if r := f.run("absent.sh"); r.code != 2 || !strings.Contains(r.stderr, "no such control") {
		t.Errorf("a control that is not there: exit %d, stderr %q; want the engine's refusal (2)", r.code, r.stderr)
	}
}

// TestLauncherLatency measures one guarded call through the launcher and the real engine, the
// per-call cost the row asks for. Resolve once, at SessionStart (ADR-0018 decision 3), would take
// the git read and the hash off this path; it rests on OPS-199's CLAUDE_ENV_FILE spike, so this
// is the cost until then. It reports; the 10 ms ceiling is OPS-185's latency test, on the
// one dispatcher per event.
func TestLauncherLatency(t *testing.T) {
	f := realFixture(t)
	bash(f, "ls")
	measure := func(name string, fn func()) time.Duration {
		var ds []time.Duration
		for range 25 {
			start := time.Now()
			fn()
			ds = append(ds, time.Since(start))
		}
		sort.Slice(ds, func(i, j int) bool { return ds[i] < ds[j] })
		t.Logf("%s: median %v, p90 %v (25 runs)", name, ds[len(ds)/2], ds[len(ds)*9/10])
		return ds[len(ds)/2]
	}
	launcher := measure("launcher + engine + control", func() {
		if r := f.run("guard.sh"); r.code != 0 {
			t.Fatalf("exit %d: %s", r.code, r.stderr)
		}
	})
	bare := measure("sh control alone", func() {
		c := exec.Command("sh", filepath.Join(f.plugin, "hooks", "guard.sh"))
		c.Stdin = strings.NewReader(f.payload)
		if err := c.Run(); err != nil {
			t.Fatal(err)
		}
	})
	t.Logf("launcher overhead per call: %v", launcher-bare)
}

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

// TestLauncherLatency measures one guarded call, verify plus exec, through the launcher and the
// real engine, with each hash tool the launcher can use: the per-call cost the row asks for.
// Resolve once, at SessionStart (ADR-0018 decision 3), would take the git read and the hash off
// this path; it rests on OPS-199's CLAUDE_ENV_FILE spike, so this is the cost until then.
//
// It asserts nothing yet, and only reports. The number that gates activation is OPS-184's: the
// launcher is not switched on until, with resolve once in place and outside the sandbox, a
// guarded call costs about S4's 3.87 ms median (launcher plus engine) and stays within ADR-0018's
// 10 ms per-call ceiling, which OPS-185's latency test then holds.
func TestLauncherLatency(t *testing.T) {
	f := realFixture(t)
	bash(f, "ls")
	const runs = 40
	measure := func(name string, fn func()) time.Duration {
		var ds []time.Duration
		for range runs {
			start := time.Now()
			fn()
			ds = append(ds, time.Since(start))
		}
		sort.Slice(ds, func(i, j int) bool { return ds[i] < ds[j] })
		med, p95 := ds[len(ds)/2], ds[len(ds)*95/100]
		t.Logf("%-38s median %8v  p95 %8v  (%d runs)", name, med.Round(10*time.Microsecond), p95.Round(10*time.Microsecond), runs)
		return med
	}
	bare := measure("sh control alone", func() {
		c := exec.Command("sh", filepath.Join(f.plugin, "hooks", "guard.sh"))
		c.Stdin = strings.NewReader(f.payload)
		if err := c.Run(); err != nil {
			t.Fatal(err)
		}
	})
	for _, tool := range []string{"default (sha256sum first)", "openssl", "shasum"} {
		f.env["STRIDAL_SHA256"] = strings.Fields(tool)[0]
		med := measure("launcher, "+tool, func() {
			if r := f.run("guard.sh"); r.code != 0 {
				t.Fatalf("exit %d: %s", r.code, r.stderr)
			}
		})
		t.Logf("%-38s %v over the bare control", "  overhead, "+tool, (med - bare).Round(10*time.Microsecond))
	}
}

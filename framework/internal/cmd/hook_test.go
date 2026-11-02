package cmd

import (
	"path/filepath"
	"strings"
	"testing"
)

// The engine's hook door runs only an absolute control that exists, in its own place (exec), so
// the control's status is the verdict; a bad argument is a refusal, never a fallthrough. The real
// exec, through the launcher, is internal/engine's TestTheRealEngineRunsTheControl.
func TestHookRunsOnlyAnExistingAbsoluteControl(t *testing.T) {
	var got []string
	hookExec = func(argv0 string, argv []string, env []string) error { got = argv; return nil }
	t.Cleanup(func() { hookExec = defaultHookExec })

	dir := t.TempDir()
	write(t, dir, "guard.sh", "exit 0\n")
	for _, bad := range []string{"guard.sh", filepath.Join(dir, "absent.sh"), dir} {
		got = nil
		if err := runHook(bad); err == nil || got != nil {
			t.Errorf("runHook(%q) = %v and ran %v; want a refusal that runs nothing", bad, err, got)
		}
	}
	script := filepath.Join(dir, "guard.sh")
	if err := runHook(script); err != nil {
		t.Fatal(err)
	}
	if strings.Join(got, " ") != "sh "+script {
		t.Errorf("exec %v, want sh %s", got, script)
	}
}

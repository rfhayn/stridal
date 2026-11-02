package engine

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/rfhayn/stridal/internal/plugin"
	"github.com/rfhayn/stridal/internal/testbin"
)

// ifProjectSrc is the plugin's if-project.sh as the plugin build writes it.
var ifProjectSrc = filepath.Join("..", "plugin", "assets", "hooks", "if-project.sh")

// Both registration paths, as plugin.LaunchControls and the plugin build write them and as
// Claude Code runs them (sh -c), read the one lock: each runs the verified engine, and each
// refuses the same way when origin's main holds no lock.
func TestBothRegistrationPathsReadTheOneLock(t *testing.T) {
	paths := []struct {
		name  string
		setup func(f *fixture) string // returns the control the engine is handed
	}{
		{"a stridal install project's settings.json", func(f *fixture) string {
			copyInstall(f)
			f.registered = plugin.ProjectLauncherPrefix + "guard.sh"
			return filepath.Join(f.proj, ".claude", "hooks", "guard.sh")
		}},
		{"the plugin's hooks.json", func(f *fixture) string {
			src, err := os.ReadFile(ifProjectSrc)
			must(f.t, err)
			testbin.Write(f.t, filepath.Join(f.plugin, "hooks", "if-project.sh"), string(src))
			f.registered = plugin.PluginLauncherPrefix + "guard.sh"
			return pluginGuard(f)
		}},
	}
	for _, p := range paths {
		t.Run(p.name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			control := p.setup(f)
			if err := ranControl(func(*fixture) string { return control }, 0)(f, f.run("")); err != nil {
				t.Errorf("verified: %v", err)
			}
			f.setOriginLock("")
			if err := refused("no .claude/stridal.lock at refs/remotes/origin/main", "git fetch origin")(f, f.run("")); err != nil {
				t.Errorf("no lock on origin/main: %v", err)
			}
		})
	}
}

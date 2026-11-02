package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"github.com/spf13/cobra"
)

// hookCmd is the engine's door for a control hook. The bootstrap launcher
// (template/.claude/hooks/stridal-engine.sh) runs it only once it has verified this binary against
// the repository's lock, with the hook's payload still unread on stdin.
//
// No control has been ported yet (ADR-0017's port order: OPS-185, then OPS-187 onward), so the
// engine runs the shell control it is handed, in this process's place, so its exit status and its
// stderr reach Claude Code unchanged. One dispatcher per event, which judges in Go, is OPS-185's.
var hookCmd = &cobra.Command{
	Use:    "hook <control.sh>",
	Short:  "Run a control hook (called by the plugin's launcher, never by hand)",
	Hidden: true,
	Args:   cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		// A failure here exits 2, never Main's 1: Claude Code lets a call through on any status
		// but 0 and 2 unless the registration says onFailure block, and a guard fails closed.
		if err := runHook(args[0]); err != nil {
			fmt.Fprintf(cmd.ErrOrStderr(), "stridal: refused: %v\n", err)
			os.Exit(2)
		}
	},
}

// hookExec replaces the process; a test stands in for it.
var (
	defaultHookExec = syscall.Exec
	hookExec        = defaultHookExec
)

func runHook(script string) error {
	if !filepath.IsAbs(script) {
		return fmt.Errorf("hook %s: the launcher passes an absolute path", script)
	}
	if fi, err := os.Stat(script); err != nil || fi.IsDir() {
		return fmt.Errorf("hook %s: no such control", script)
	}
	sh, err := exec.LookPath("sh")
	if err != nil {
		return fmt.Errorf("hook %s: no sh on PATH", script)
	}
	if err := hookExec(sh, []string{"sh", script}, os.Environ()); err != nil {
		return fmt.Errorf("hook %s: %v", script, err)
	}
	return nil
}

func init() { rootCmd.AddCommand(hookCmd) }

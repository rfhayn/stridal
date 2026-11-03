package cmd

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"

	"github.com/rfhayn/stridal/internal/panel/install"
	"github.com/rfhayn/stridal/internal/template"
	"github.com/spf13/cobra"
)

var initCmd = &cobra.Command{
	Use:   "init [path]",
	Short: "Create a new project with Stridal framework",
	Long: `Initialize a new project directory with the Stridal operating model: skills,
hooks, checks, agents, docs and settings. If path doesn't exist, it will be created.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		targetDir, err := filepath.Abs(args[0])
		if err != nil {
			return fmt.Errorf("invalid path: %w", err)
		}

		// Check if directory already has content
		if info, err := os.Stat(targetDir); err == nil && info.IsDir() {
			entries, _ := os.ReadDir(targetDir)
			if len(entries) > 0 {
				return fmt.Errorf("%s is not empty — use 'stridal install' to add framework to an existing project", targetDir)
			}
		}

		// Create directory if needed
		if err := os.MkdirAll(targetDir, 0755); err != nil {
			return fmt.Errorf("could not create directory: %w", err)
		}

		fmt.Printf("Initializing new Stridal project in %s\n", targetDir)
		src, err := announceTemplate(cmd.OutOrStdout())
		if err != nil {
			return err
		}

		// Copy template files
		if err := template.CopyTemplate(targetDir); err != nil {
			return fmt.Errorf("failed to copy template: %w", err)
		}
		if err := writeInstallMarker(targetDir); err != nil {
			return fmt.Errorf("could not mark the install: %w", err)
		}

		// Initialize git if not already a repo
		if _, err := os.Stat(filepath.Join(targetDir, ".git")); os.IsNotExist(err) {
			fmt.Println("  Initializing git repository...")
			if err := runCommand(targetDir, "git", "init"); err != nil {
				fmt.Printf("  Warning: could not init git: %v\n", err)
			}
		}
		setOriginHead(cmd.OutOrStdout(), targetDir)

		printPrereqs(cmd.OutOrStdout(), src.Dir)
		fmt.Println("\nDone! Next steps:")
		fmt.Printf("  cd %s\n", install.ShellWord(targetDir)) // runs as printed (PANEL-47)
		fmt.Println("  claude")
		fmt.Println("  /session-start")
		return nil
	},
}

func init() { addTemplateFlag(initCmd) }

// originHeadTimeout bounds setOriginHead's question to origin.
var originHeadTimeout = 15 * time.Second

// setOriginHead records which branch of origin is main, as `git init` and a first push leave that
// unset and the merge guard takes main from it, never from a key a branch can edit (OPS-219).
func setOriginHead(out io.Writer, dir string) {
	quiet := func(args ...string) error {
		cmd := execCommand("git", args...)
		cmd.Dir = dir
		return cmd.Run()
	}
	if quiet("remote", "get-url", "origin") != nil || quiet("symbolic-ref", "-q", "refs/remotes/origin/HEAD") == nil {
		return
	}
	// This one asks origin: an unreachable host must not hold install or update for git's own timeout.
	// Its own process group, so the timeout also ends what git started (ssh, a remote helper).
	ctx, cancel := context.WithTimeout(context.Background(), originHeadTimeout)
	defer cancel()
	ask := exec.CommandContext(ctx, "git", "remote", "set-head", "origin", "--auto")
	ask.Dir = dir
	// A background group cannot answer a prompt, so git must fail at once rather than wait out the limit.
	ask.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	ask.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	ask.Cancel = func() error { return syscall.Kill(-ask.Process.Pid, syscall.SIGKILL) }
	if ask.Run() != nil {
		fmt.Fprintln(out, "  Note: set origin's HEAD before the first merge: git fetch origin && git remote set-head origin <your main branch>")
	}
}

func runCommand(dir string, name string, args ...string) error {
	cmd := execCommand(name, args...)
	cmd.Dir = dir
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

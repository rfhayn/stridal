package cmd

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/rfhayn/stridal/internal/panel/install"
	"github.com/rfhayn/stridal/internal/template"
	"github.com/rfhayn/stridal/internal/testbin"
	"github.com/rfhayn/stridal/internal/testgit"
)

// OPS-231: the git floor has two roads, `stridal doctor` and the model's health line for a project
// with no binary, and each parses git's version itself. One table drives both, so a floor or a
// parse that drifts on either road fails here.
var gitFloorCases = []struct {
	prints  string // git --version's output
	version string // what the line must name
	below   bool
}{
	{"git version 2.30.2", "2.30.2", true},
	{"git version 2.31.0", "2.31.0", false},
	{"git version 2.54.0 (Apple Git-157)", "2.54.0 (Apple Git-157)", false},
	{"git version 2.30.1 (Apple Git-130)", "2.30.1 (Apple Git-130)", true},
	{"git version 2.43.0.windows.1", "2.43.0.windows.1", false},
	// A release candidate counts as its release.
	{"git version 2.31.0.rc1", "2.31.0.rc1", false},
	{"git version 2.30.0.rc2", "2.30.0.rc2", true},
	// Compared as numbers: as text 2.9 sorts above 2.31, and a later major has a smaller minor.
	{"git version 2.9.5", "2.9.5", true},
	{"git version 3.0.0", "3.0.0", false},
	{"git version 1.99.0", "1.99.0", true},
}

// The output neither road can read: never an OK, and never a version guessed from part of it.
var gitFloorUnreadable = []string{
	"not git at all",
	"git version",
	"git version 2",
	"git version two.thirty",
	"git version 99999999.1",
	"git version 2.9999999",
	"prefix git version 2.54.0",
}

// stubGit is a git in bin that prints prints for --version and exits status, and is the real git
// for anything else: doctor's project lines and extensions.sh ask git other things.
func stubGit(t *testing.T, bin, prints string, status int) {
	t.Helper()
	testbin.Write(t, filepath.Join(bin, "git"), "#!/bin/sh\ncase ${1:-} in --version) printf '%s\\n' "+
		install.ShellWord(prints)+"; exit "+strconv.Itoa(status)+" ;; esac\nexec "+install.ShellWord(testgit.Path)+" \"$@\"\n")
}

// [DOCTOR-1-S8] A git below the model's floor warns, and does not fail; at or above it is ok,
// the Apple form included.
func TestDoctorGitFloor(t *testing.T) {
	for _, c := range gitFloorCases {
		t.Run(c.prints, func(t *testing.T) {
			tmplDir(t)
			t.Chdir(t.TempDir())
			bin := stubPath(t, without("git")...)
			stubGit(t, bin, c.prints, 0)
			out, err := doctor(t, bin)
			if err != nil {
				t.Fatalf("a git version is a warning at most, never a failure: %v\n%s", err, out)
			}
			// The floor has a subject of its own, so a check for the tools line's `ok git` cannot
			// be answered by it.
			needLine(t, out, "ok", "git", filepath.Join(bin, "git"))
			needNoLine(t, out, "ok", "git", "the floor")
			if c.below {
				needLine(t, out, "warn", "git-floor", c.version, "2.31", "--path-format")
				needLine(t, out, "install: ", "git-scm.com/downloads")
				needNoLine(t, out, "ok", "git-floor")
				return
			}
			needLine(t, out, "ok", "git-floor", c.version, "2.31")
			needNoLine(t, out, "warn", "git-floor")
		})
	}
}

// [DOCTOR-1-S8] Output it cannot read as a version is a note, never ok.
func TestDoctorGitFloorUnreadableIsANote(t *testing.T) {
	for _, prints := range gitFloorUnreadable {
		t.Run(prints, func(t *testing.T) {
			tmplDir(t)
			t.Chdir(t.TempDir())
			bin := stubPath(t, without("git")...)
			stubGit(t, bin, prints, 0)
			out, err := doctor(t, bin)
			if err != nil {
				t.Fatalf("doctor failed: %v\n%s", err, out)
			}
			needLine(t, out, "note", "git-floor", "2.31", "could not")
			needNoLine(t, out, "warn", "git-floor")
			if strings.Contains(out, "at or above") {
				t.Errorf("an unread version reads as meeting the floor:\n%s", out)
			}
		})
	}
	t.Run("git --version fails", func(t *testing.T) {
		tmplDir(t)
		t.Chdir(t.TempDir())
		bin := stubPath(t, without("git")...)
		stubGit(t, bin, "git version 2.54.0", 3)
		out, err := doctor(t, bin)
		if err != nil {
			t.Fatalf("doctor failed: %v\n%s", err, out)
		}
		needLine(t, out, "note", "git-floor", "2.31", "could not", "git --version failed")
	})
}

// With `.` first on PATH, LookPath finds a git it will not run (exec.ErrDot). That is a git doctor
// cannot read, not a missing one, so the floor says it could not tell, rather than nothing.
func TestDoctorGitFloorDotOnPathIsANote(t *testing.T) {
	tmplDir(t)
	bin := stubPath(t, without("git")...)
	stubGit(t, bin, "git version 2.54.0", 0)
	t.Chdir(bin)
	out, _ := doctor(t, ".")
	needLine(t, out, "note", "git-floor", "2.31", "could not")
}

// The floor is a machine line, and needs no template: doctor reports it when the tools cannot be read.
func TestDoctorGitFloorNeedsNoTemplate(t *testing.T) {
	tmplDir(t)
	t.Chdir(t.TempDir())
	bin := stubPath(t, without("git")...)
	stubGit(t, bin, "git version 2.30.2", 0)
	template.OverrideDir = filepath.Join(t.TempDir(), "no-template")
	out, _ := doctor(t, bin)
	needLine(t, out, "FAIL", "template")
	needLine(t, out, "note", "tools", "could not be checked")
	needLine(t, out, "warn", "git-floor", "2.30.2", "2.31")
}

// A missing git is the tools line's FAIL, with no second line about its version.
func TestDoctorGitFloorMissingGitSaysOnlyMissing(t *testing.T) {
	tmplDir(t)
	t.Chdir(t.TempDir())
	out, _ := doctor(t, stubPath(t, without("git")...))
	needLine(t, out, "FAIL", "git", "missing")
	if l := subjectLine(out, "git-floor"); l != "" {
		t.Errorf("a missing git also has a floor line: %s", l)
	}
}

// copyFromTemplate copies the template's rel into the project p.
func copyFromTemplate(t *testing.T, tmpl, p, rel string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(tmpl, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatal(err)
	}
	write(t, p, rel, string(raw))
}

// gitFloorHealth runs `.claude/extensions.sh health`, the call session-start's context makes, in a
// project with nothing in .claude/health/, on a PATH with bin first. It returns what the line printed
// under its heading, indented as the run prints it. A run with no such heading fails the test.
// libHealth is the project's lib/health.sh: empty for the template's, or "-" for none.
func gitFloorHealth(t *testing.T, bin, libHealth string) string {
	t.Helper()
	return gitFloorHealthOn(t, bin+":"+os.Getenv("PATH"), libHealth)
}

// gitFloorHealthOn is gitFloorHealth on exactly this PATH.
func gitFloorHealthOn(t *testing.T, path, libHealth string) string {
	t.Helper()
	tmpl := tmplDir(t)
	p := t.TempDir()
	for _, rel := range []string{".claude/extensions.sh", ".claude/lib/conf.sh", ".claude/lib/modules.sh"} {
		copyFromTemplate(t, tmpl, p, rel)
	}
	switch libHealth {
	case "":
		copyFromTemplate(t, tmpl, p, ".claude/lib/health.sh")
	case "-":
	default:
		write(t, p, ".claude/lib/health.sh", libHealth)
	}
	c := exec.Command("/bin/sh", ".claude/extensions.sh", "health")
	c.Dir = p
	c.Env = []string{"PATH=" + path, "HOME=" + t.TempDir(), "CONTEXT_OFFLINE=1"}
	raw, err := c.CombinedOutput()
	if err != nil {
		t.Fatalf("extensions.sh health: %v\n%s", err, raw)
	}
	_, rest, found := strings.Cut(string(raw), "- Health: git-floor\n")
	if !found {
		t.Fatalf("the health run has no git-floor line:\n%s", raw)
	}
	section, _, _ := strings.Cut(rest, "- Health: ")
	return section
}

func TestGitFloorHealthLine(t *testing.T) {
	for _, c := range gitFloorCases {
		t.Run(c.prints, func(t *testing.T) {
			bin := t.TempDir()
			stubGit(t, bin, c.prints, 0)
			out := gitFloorHealth(t, bin, "")
			// The subject is the git this PATH finds, and its version as git prints it.
			subject := "git " + c.version + " at " + filepath.Join(bin, "git")
			want := "    OK " + subject
			if c.below {
				want = "    FAILED " + subject
			}
			if !strings.HasPrefix(out, want) || !strings.Contains(out, "2.31") {
				t.Errorf("want a line starting %q and naming 2.31, got: %s", want, out)
			}
			if strings.Count(strings.TrimRight(out, "\n"), "\n") != 0 {
				t.Errorf("one subject, one line: %s", out)
			}
		})
	}
}

// Never silence and never OK for what it could not read (.claude/health/README.md, the contract).
func TestGitFloorHealthLineCannotCheck(t *testing.T) {
	need := func(t *testing.T, out, why string) {
		t.Helper()
		if !strings.HasPrefix(out, "    CANNOT CHECK — ") || !strings.Contains(out, why) {
			t.Errorf("want CANNOT CHECK saying %q, got: %s", why, out)
		}
	}
	for _, prints := range gitFloorUnreadable {
		t.Run(prints, func(t *testing.T) {
			bin := t.TempDir()
			stubGit(t, bin, prints, 0)
			need(t, gitFloorHealth(t, bin, ""), "git --version")
		})
	}
	t.Run("git --version fails", func(t *testing.T) {
		bin := t.TempDir()
		stubGit(t, bin, "git version 2.54.0", 3)
		need(t, gitFloorHealth(t, bin, ""), "git --version")
	})
	t.Run("no library", func(t *testing.T) {
		bin := t.TempDir()
		stubGit(t, bin, "git version 2.54.0", 0)
		need(t, gitFloorHealth(t, bin, "-"), "lib/health.sh is missing")
	})
	t.Run("a library older than the line", func(t *testing.T) {
		bin := t.TempDir()
		stubGit(t, bin, "git version 2.54.0", 0)
		need(t, gitFloorHealth(t, bin, "# a health.sh from before OPS-231\n"), "health_git_floor")
	})
}

// No git at all: the real extensions.sh health call, on a PATH of the machine's tools minus git.
func TestGitFloorHealthLineNoGitOnPath(t *testing.T) {
	bin := t.TempDir()
	for _, dir := range []string{"/bin", "/usr/bin"} {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue // not every system has both
		}
		for _, e := range entries {
			if e.Name() == "git" || strings.HasPrefix(e.Name(), "git-") {
				continue
			}
			// A name both directories hold keeps the first, as PATH would.
			if err := os.Symlink(filepath.Join(dir, e.Name()), filepath.Join(bin, e.Name())); err != nil && !errors.Is(err, os.ErrExist) {
				t.Fatal(err)
			}
		}
	}
	out := gitFloorHealthOn(t, bin, "")
	if !strings.HasPrefix(out, "    CANNOT CHECK — git is not on PATH") {
		t.Errorf("want CANNOT CHECK naming the missing git, got: %s", out)
	}
}

// An EMULATION of a git below the floor, not a run of one: the stub answers
// `rev-parse --path-format=...` by echoing the flag and exiting 0, as the review's reproduction
// did. No real git below 2.31 has run here. Modern git underneath every other stub in this file
// understands the flag, so this is the one health run that hears the old answer. sandbox-writes is
// the line that asks, and it stops before asking in a home that takes a write, as a fixture's does;
// so the fixture's library answers its probe as a sandbox would (plugin_test.go does the same).
func TestGitFloorHealthLineOnAnEmulatedOldGit(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join(tmplDir(t), ".claude/lib/health.sh"))
	if err != nil {
		t.Fatal(err)
	}
	lib := string(raw) + "\nhealth_probe_write() { echo refused; }\n"
	bin := t.TempDir()
	testbin.Write(t, filepath.Join(bin, "git"), "#!/bin/sh\ncase \"$*\" in\n"+
		"  --version) echo 'git version 2.30.2'; exit 0 ;;\n"+
		"  *'rev-parse --path-format'*) : > "+install.ShellWord(filepath.Join(bin, "asked"))+"; for a; do case $a in --path-format*) printf '%s\\n' \"$a\" ;; esac; done; exit 0 ;;\n"+
		"esac\nexec "+install.ShellWord(testgit.Path)+" \"$@\"\n")
	out := gitFloorHealth(t, bin, lib)
	if want := "    FAILED git 2.30.2 at " + filepath.Join(bin, "git"); !strings.HasPrefix(out, want) {
		t.Errorf("want a line starting %q, got: %s", want, out)
	}
	if _, err := os.Stat(filepath.Join(bin, "asked")); err != nil {
		t.Errorf("the run never asked the emulated form: %v", err)
	}
}

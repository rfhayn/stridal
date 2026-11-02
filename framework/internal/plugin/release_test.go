package plugin

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The release scripts, run on a tiny repository of their own shape, so a name in template/ can be
// any name and a build takes seconds.
func releaseRepo(t *testing.T) (dir string, e []string) {
	t.Helper()
	need(t, "git", "go", "tar")
	dir = t.TempDir()
	write := func(p, s string) {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	root := repoRoot(t)
	for _, s := range []string{"build-release.sh", "check-release-repro.sh", "check-release-tag.sh"} {
		data, err := os.ReadFile(filepath.Join(root, "scripts", s))
		if err != nil {
			t.Fatal(err)
		}
		write("scripts/"+s, string(data))
	}
	write("framework/go.mod", "module x\n\ngo 1.21\n")
	write("framework/cmd/stridal/main.go", "package main\n\nfunc main() {}\n")
	write("framework/internal/cmd/root.go", "package cmd\n\nvar Version = \"1.2.3\"\n")
	write("LICENSE", "l\n")
	write("README.md", "r\n")
	for _, n := range oddTemplateNames {
		write(filepath.Join("template", n), n)
	}
	e = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_NOSYSTEM=1", "GIT_AUTHOR_NAME=a", "GIT_AUTHOR_EMAIL=a@a", "GIT_COMMITTER_NAME=a", "GIT_COMMITTER_EMAIL=a@a")
	for _, a := range [][]string{{"init", "-q", "-b", "main"}, {"add", "-A"}, {"commit", "-qm", "x"}} {
		if out, code := run(t, dir, e, "", "git", a...); code != 0 {
			t.Fatal(out)
		}
	}
	return dir, e
}

// Names a newline-separated list misreads, and flags tar would obey.
var oddTemplateNames = []string{"plain", "-dash", "new\nline", "sp ace", "back\\slash", "-C", ".x/--null"}

// Under whichever tar this machine has, in short runs too: CI's Ubuntu is what runs GNU tar, and
// only bsdtar had run this until then.
func TestReleaseCarriesEveryTemplateName(t *testing.T) {
	dir, e := releaseRepo(t)
	if v, err := exec.Command("tar", "--version").Output(); err == nil {
		t.Logf("tar: %s", strings.SplitN(string(v), "\n", 2)[0])
	}
	out := t.TempDir()
	if s, code := run(t, dir, e, "", "sh", "scripts/build-release.sh", "--out", out, "linux/amd64"); code != 0 {
		t.Fatal(s)
	}
	list, err := exec.Command("tar", "-tzf", filepath.Join(out, "stridal-linux-amd64.tar.gz")).Output()
	if err != nil {
		t.Fatal(err)
	}
	x := t.TempDir()
	if s, code := run(t, x, e, "", "tar", "-xzf", filepath.Join(out, "stridal-linux-amd64.tar.gz")); code != 0 {
		t.Fatalf("%s\n%s", s, list)
	}
	for _, n := range oddTemplateNames {
		got, err := os.ReadFile(filepath.Join(x, "stridal-linux-amd64", "template", n))
		if err != nil || string(got) != n {
			t.Errorf("template/%q in the archive: %q, %v", n, got, err)
		}
	}
	info, err := exec.Command("go", "version", "-m", filepath.Join(x, "stridal-linux-amd64", "stridal")).Output()
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(info), "vcs.") {
		t.Errorf("the engine's hash depends on the checkout's commit:\n%s", info)
	}
}

func TestReleaseReproduces(t *testing.T) {
	if testing.Short() {
		t.Skip("builds a release with an empty cache")
	}
	dir, e := releaseRepo(t)
	out := t.TempDir()
	if s, code := run(t, dir, e, "", "sh", "scripts/build-release.sh", "--out", out, "linux/amd64"); code != 0 {
		t.Fatal(s)
	}
	sums := filepath.Join(out, "engines.sha256")
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-repro.sh", sums, "linux/amd64"); code != 0 {
		t.Fatalf("an honest rebuild does not reproduce: %s", s)
	}
	good, err := os.ReadFile(sums)
	if err != nil {
		t.Fatal(err)
	}
	tampered := filepath.Join(t.TempDir(), "engines.sha256")
	if err := os.WriteFile(tampered, []byte("0000"+string(good)[4:]), 0o644); err != nil {
		t.Fatal(err)
	}
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-repro.sh", tampered, "linux/amd64"); code == 0 {
		t.Errorf("a tampered sum passed: %s", s)
	}
	// All targets asked: a missing or extra line fails too.
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-repro.sh", tampered); code == 0 {
		t.Errorf("a tampered file passed a full rebuild: %s", s)
	}
}

func TestReleaseTagMustBeOnMainAndNameTheVersion(t *testing.T) {
	dir, e := releaseRepo(t)
	gitx := func(a ...string) {
		t.Helper()
		if out, code := run(t, dir, e, "", "git", a...); code != 0 {
			t.Fatal(out)
		}
	}
	gitx("update-ref", "refs/remotes/origin/main", "HEAD")
	gitx("tag", "v1.2.3")
	gitx("tag", "v9.9.9")
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-tag.sh", "v1.2.3"); code != 0 {
		t.Errorf("the right tag was refused: %s", s)
	}
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-tag.sh", "v9.9.9"); code == 0 || !strings.Contains(s, "is not v1.2.3") {
		t.Errorf("another version passed: %d %s", code, s)
	}
	gitx("checkout", "-q", "-b", "side")
	gitx("commit", "-q", "--allow-empty", "-m", "side")
	gitx("tag", "-f", "v1.2.3")
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-tag.sh", "v1.2.3"); code == 0 || !strings.Contains(s, "not on origin/main") {
		t.Errorf("a tag off main passed: %d %s", code, s)
	}
}

// The workflow's shape: nothing that compiles holds a write token or a cache, and the one job that
// can write runs after the tag check and the reproduction, and runs no repository code.
func TestReleaseWorkflowKeepsTheWriteTokenAwayFromTheBuild(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(repoRoot(t), ".github", "workflows", "release.yml"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(data)
	job := func(name, next string) string {
		_, rest, ok := strings.Cut(src, "\n  "+name+":\n")
		if !ok {
			t.Fatalf("release.yml has no job %s", name)
		}
		if next != "" {
			rest, _, _ = strings.Cut(rest, "\n  "+next+":\n")
		}
		return rest
	}
	build, reproduce, draft := job("build", "reproduce"), job("reproduce", "draft"), job("draft", "")
	if head, _, _ := strings.Cut(src, "\njobs:"); !strings.Contains(head, "contents: read") || strings.Contains(head, "contents: write") {
		t.Error("the workflow's default token is not read-only")
	}
	for name, body := range map[string]string{"build": build, "reproduce": reproduce} {
		for _, want := range []string{"persist-credentials: false", "cache: false"} {
			if !strings.Contains(body, want) {
				t.Errorf("job %s lacks %s", name, want)
			}
		}
		if strings.Contains(body, "contents: write") {
			t.Errorf("job %s can write", name)
		}
	}
	if !strings.Contains(build, "scripts/check-release-tag.sh") || strings.Index(build, "check-release-tag") > strings.Index(build, "build-release") {
		t.Error("the build job does not check the tag before it builds")
	}
	if !strings.Contains(reproduce, "scripts/check-release-repro.sh") {
		t.Error("the reproduce job does not reproduce")
	}
	if !strings.Contains(draft, "needs: [build, reproduce]") || !strings.Contains(draft, "--draft") {
		t.Error("the draft job does not wait for both, or does not open a draft")
	}
	if strings.Contains(draft, "actions/checkout") || strings.Contains(draft, "scripts/") {
		t.Error("the job that can write runs repository code")
	}
}

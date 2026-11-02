package plugin

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
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

// A newline and a backslash are what a newline-separated list misreads; the rest hold the ordinary
// and flag-like names beside them.
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
	first, e := releaseRepo(t)
	out := t.TempDir()
	if s, code := run(t, first, e, "", "sh", "scripts/build-release.sh", "--out", out); code != 0 {
		t.Fatal(s)
	}
	// The rebuild runs from another directory, as a second runner's would: -trimpath is what makes
	// that the same binary.
	dir := filepath.Join(t.TempDir(), "elsewhere")
	if s, code := run(t, filepath.Dir(dir), e, "", "git", "clone", "-q", first, dir); code != 0 {
		t.Fatal(s)
	}
	sums := filepath.Join(out, "engines.sha256")
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-repro.sh", sums, "linux/amd64"); code != 0 {
		t.Fatalf("an honest rebuild of one target does not reproduce: %s", s)
	}
	// All targets, as release.yml's reproduce job runs it: both ways, so the comparison is shown
	// passing on what matches and failing on what does not.
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-repro.sh", sums); code != 0 {
		t.Fatalf("an honest full rebuild does not reproduce: %s", s)
	}
	good, err := os.ReadFile(sums)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(good)), "\n")
	if len(lines) != 4 {
		t.Fatalf("%d engines, want the four release targets:\n%s", len(lines), good)
	}
	for i, l := range lines {
		lines[i] = "0000" + l[4:]
	}
	tampered := filepath.Join(t.TempDir(), "engines.sha256")
	if err := os.WriteFile(tampered, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if s, code := run(t, dir, e, "", "sh", "scripts/check-release-repro.sh", tampered, "linux/amd64"); code == 0 {
		t.Errorf("a tampered sum passed: %s", s)
	}
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
	// Only what is listed: an allowlist, so a scope nobody thought of cannot pass.
	_, jobs, _ := strings.Cut(src, "\njobs:\n")
	names := regexp.MustCompile(`(?m)^  ([^\s#:]+):\s*$`).FindAllStringSubmatch(jobs, -1)
	if len(names) != 3 {
		t.Errorf("release.yml has %d jobs, want build, reproduce and draft alone: %q", len(names), names)
	}
	head, _, _ := strings.Cut(src, "\njobs:")
	if got := permissionLines(head, ""); len(got) != 1 || got[0] != "contents: read" {
		t.Errorf("the workflow's permissions are %q, want exactly contents: read", got)
	}
	if got := permissionLines(draft, "    "); len(got) != 1 || got[0] != "contents: write" {
		t.Errorf("the draft job's permissions are %q, want exactly contents: write", got)
	}
	for name, body := range map[string]string{"build": build, "reproduce": reproduce} {
		for _, want := range []string{"persist-credentials: false", "cache: false"} {
			if !strings.Contains(body, want) {
				t.Errorf("job %s lacks %s", name, want)
			}
		}
		if regexp.MustCompile(`(?m)^\s*["']?permissions["']?\s*:`).MatchString(body) {
			t.Errorf("job %s has a permissions key: it takes the workflow's read-only token alone", name)
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

// Every workflow's actions are pinned to a full commit, each with its version beside it: a tag can
// move, and the release job's token is one of what a moved tag would reach. A Go test and not
// checks/supply-chain.sh, which ships in the template: it would hold adopters' workflows to this repo's
// choice.
func TestEveryWorkflowsActionsArePinned(t *testing.T) {
	files, err := actionFiles(repoRoot(t))
	if err != nil || len(files) == 0 {
		t.Fatalf("no workflows: %v", err)
	}
	seen := 0
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		refs, bad := unpinnedActions(string(data))
		seen += refs
		for _, b := range bad {
			t.Errorf("%s: %q is not pinned to a commit with its version beside it", filepath.Base(f), b)
		}
	}
	if seen == 0 {
		t.Fatal("no action found: this test learned nothing")
	}
}

func TestUnpinnedActionsReadsEveryFormOfUses(t *testing.T) {
	const sha = "3d3c42e5aac5ba805825da76410c181273ba90b1"
	cases := []struct {
		name, line string
		refs, bad  int
	}{
		{"pinned", "- uses: actions/checkout@" + sha + " # v7.0.1", 1, 0},
		{"pinned, a key of its own line", "uses: actions/checkout@" + sha + " # v7", 1, 0},
		{"pinned, a quoted value", `- uses: "actions/checkout@` + sha + `" # v7`, 1, 0},
		{"a local action needs no pin", "- uses: ./.github/actions/x", 1, 0},
		{"a digest-pinned image", "- uses: docker://alpine@sha256:" + strings.Repeat("a", 64) + " # v3", 1, 0},
		{"a comment is not a use", "# uses: actions/checkout@v7", 0, 0},
		{"a word ending in uses is not a use", "refuses: actions/checkout@v7", 0, 0},
		{"a tag", "- uses: actions/checkout@v7", 1, 1},
		{"a branch", "uses: actions/checkout@main", 1, 1},
		{"no version beside the pin", "- uses: actions/checkout@" + sha, 1, 1},
		{"a short commit", "- uses: actions/checkout@3d3c42e # v7", 1, 1},
		{"no ref at all", "- uses: actions/checkout", 1, 1},
		{"a quoted key", `- "uses": actions/checkout@v7`, 1, 1},
		{"a single-quoted key and value", `- 'uses': 'actions/checkout@v7'`, 1, 1},
		{"flow form", "- {uses: actions/checkout@v7, with: {fetch-depth: 0}}", 1, 1},
		{"flow form, pinned", "- {uses: actions/checkout@" + sha + "} # v7", 1, 0},
		{"an image on a tag", "- uses: docker://alpine:3", 1, 1},
	}
	for _, c := range cases {
		refs, bad := unpinnedActions(c.line + "\n")
		if refs != c.refs || len(bad) != c.bad {
			t.Errorf("%s: %d uses and %d unpinned (%q), want %d and %d", c.name, refs, len(bad), bad, c.refs, c.bad)
		}
	}
}

// What GitHub runs: a workflow in either extension, directly under .github/workflows, and a composite
// action anywhere under .github/actions.
func TestActionFilesIteratesWhatGitHubRuns(t *testing.T) {
	root := t.TempDir()
	want := []string{
		".github/actions/deep/er/action.yaml",
		".github/actions/x/action.yml",
		".github/workflows/a.yml",
		".github/workflows/b.yaml",
	}
	for _, p := range append([]string{".github/workflows/README.md", ".github/workflows/sub/not-run.yml", ".github/actions/x/README.md"}, want...) {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	files, err := actionFiles(root)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, f := range files {
		rel, err := filepath.Rel(root, f)
		if err != nil {
			t.Fatal(err)
		}
		got = append(got, filepath.ToSlash(rel))
	}
	sort.Strings(got)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("files %q, want %q", got, want)
	}
}

// actionFiles lists the files whose uses GitHub runs.
func actionFiles(root string) ([]string, error) {
	isYAML := func(p string) bool { return strings.HasSuffix(p, ".yml") || strings.HasSuffix(p, ".yaml") }
	var files []string
	entries, err := os.ReadDir(filepath.Join(root, ".github", "workflows"))
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if !e.IsDir() && isYAML(e.Name()) {
			files = append(files, filepath.Join(root, ".github", "workflows", e.Name()))
		}
	}
	actions := filepath.Join(root, ".github", "actions")
	if _, err := os.Stat(actions); os.IsNotExist(err) {
		return files, nil
	}
	err = filepath.WalkDir(actions, func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && isYAML(p) {
			files = append(files, p)
		}
		return err
	})
	return files, err
}

var (
	usesKey    = regexp.MustCompile(`(?:^|[\s{,])["']?uses["']?\s*:\s*["']?([^\s"',}]+)`)
	pinnedUse  = regexp.MustCompile(`^[^@\s]+/[^@\s]+@[0-9a-f]{40}$`)
	pinnedDock = regexp.MustCompile(`^docker://[^@\s]+@sha256:[0-9a-f]{64}$`)
	versionTag = regexp.MustCompile(`#\s*v\S+`)
)

// unpinnedActions reads text line by line: how many uses it holds, and the ones not pinned to a full
// commit (or an image's digest) with the version in a comment on the same line. A local action
// lives in the commit that runs it, so it needs no pin. A line that only mentions uses in a comment
// is not a use.
func unpinnedActions(text string) (refs int, bad []string) {
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		code, comment := line, ""
		if i := strings.Index(line, " #"); i >= 0 {
			code, comment = line[:i], line[i:]
		}
		m := usesKey.FindStringSubmatch(code)
		if m == nil {
			continue
		}
		refs++
		ref := m[1]
		switch {
		case strings.HasPrefix(ref, "./"):
		case (pinnedUse.MatchString(ref) || pinnedDock.MatchString(ref)) && versionTag.MatchString(comment):
		default:
			bad = append(bad, strings.TrimSpace(line))
		}
	}
	return refs, bad
}

// permissionLines is the permissions block in text, whose key sits at indent, as its trimmed lines;
// an inline value (write-all) comes back as itself.
func permissionLines(text, indent string) []string {
	var got []string
	in := false
	for _, line := range strings.Split(text, "\n") {
		if !in {
			if v, ok := strings.CutPrefix(line, indent+"permissions:"); ok {
				in = true
				if v = strings.TrimSpace(v); v != "" {
					got = append(got, v)
				}
			}
			continue
		}
		if strings.TrimSpace(line) == "" || !strings.HasPrefix(line, indent+" ") {
			break
		}
		got = append(got, strings.TrimSpace(line))
	}
	return got
}

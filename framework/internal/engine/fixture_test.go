package engine

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/rfhayn/stridal/internal/testbin"
)

// launcherSrc is the launcher as the template ships it; the plugin build copies it unchanged
// (TestCommittedPluginIsCurrent holds plugin/ to the template).
var launcherSrc = filepath.Join("..", "..", "..", "template", ".claude", "hooks", "stridal-engine.sh")

const fixtureVersion = "9.8.7"

// fakeEngine records that it ran, its arguments and the payload it was handed, and exits with
// FAKE_RC. Its sha256 is what a fixture's lock pins.
const fakeEngine = `#!/bin/sh
printf '%s\n' "$*" > "$FAKE_LOG"
cat > "$FAKE_LOG.stdin"
exit "${FAKE_RC:-0}"
`

// fixture is one repository guarded by one plugin, on disk under t.TempDir():
//
//	up/        the origin: main holds the lock
//	proj/      a clone of up, marked .claude/stridal-plugin
//	plugin/    a plugin root: .claude-plugin/plugin.json, engine/<goos>-<goarch>/stridal, hooks/
//	home/      HOME, inside TMPDIR
type fixture struct {
	t        *testing.T
	root     string
	up, proj string
	plugin   string
	home     string
	tmp      string // TMPDIR the launcher sees
	launcher string // the launcher the run uses (the template's, or a mutant)
	log      string // the fake engine's record
	env      map[string]string
	payload  string
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	root := t.TempDir()
	f := &fixture{
		t: t, root: root,
		up: filepath.Join(root, "up"), proj: filepath.Join(root, "proj"),
		plugin: filepath.Join(root, "plugin"), home: filepath.Join(root, "home"),
		tmp: root, log: filepath.Join(root, "engine.log"),
		env:     map[string]string{},
		payload: `{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}`,
	}
	for _, d := range []string{f.up, f.home, filepath.Join(f.plugin, ".claude-plugin"), filepath.Join(f.plugin, "hooks")} {
		must(t, os.MkdirAll(d, 0o755))
	}
	f.setPluginVersion(fixtureVersion)
	f.writeEngine(fakeEngine)
	src, err := os.ReadFile(launcherSrc)
	must(t, err)
	f.launcher = filepath.Join(f.plugin, "hooks", "stridal-engine.sh")
	testbin.Write(t, f.launcher, string(src))
	testbin.Write(t, filepath.Join(f.plugin, "hooks", "guard.sh"), "#!/bin/sh\nexit 0\n")

	f.git(f.up, "init", "-q", "-b", "main")
	f.commitLock(f.up, f.lockFor(f.engineSum()))
	f.git(root, "clone", "-q", f.up, f.proj)
	f.mark(f.proj)
	return f
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) git(dir string, args ...string) string {
	f.t.Helper()
	c := exec.Command("git", append([]string{"-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"}, args...)...)
	c.Dir = dir
	c.Env = gitEnv(f.home)
	out, err := c.CombinedOutput()
	if err != nil {
		f.t.Fatalf("git %v in %s: %v\n%s", args, dir, err, out)
	}
	return strings.TrimSpace(string(out))
}

// gitEnv keeps the user's git configuration out of a fixture, and the fixture's out of the user's.
func gitEnv(home string) []string {
	return []string{"PATH=" + os.Getenv("PATH"), "HOME=" + home, "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL=/dev/null", "TMPDIR=" + os.TempDir()}
}

func (f *fixture) mark(dir string) {
	f.t.Helper()
	must(f.t, os.MkdirAll(filepath.Join(dir, ".claude"), 0o755))
	must(f.t, os.WriteFile(filepath.Join(dir, ".claude", "stridal-plugin"), []byte("x\n"), 0o644))
}

func (f *fixture) enginePath() string {
	return filepath.Join(f.plugin, "engine", runtime.GOOS+"-"+runtime.GOARCH, "stridal")
}

func (f *fixture) writeEngine(body string) {
	f.t.Helper()
	must(f.t, os.MkdirAll(filepath.Dir(f.enginePath()), 0o755))
	testbin.Write(f.t, f.enginePath(), body)
}

func (f *fixture) engineSum() string {
	f.t.Helper()
	s, err := FileSHA256(f.enginePath())
	must(f.t, err)
	return s
}

func (f *fixture) setPluginVersion(v string) {
	f.t.Helper()
	m := fmt.Sprintf("{\n  \"name\": \"stridal\",\n  \"version\": %q\n}\n", v)
	must(f.t, os.WriteFile(filepath.Join(f.plugin, ".claude-plugin", "plugin.json"), []byte(m), 0o644))
}

func (f *fixture) lockFor(sum string) string {
	return string((&Lock{Release: fixtureVersion, Engines: map[string]string{Platform(): sum, "plan9/mips": strings.Repeat("0", 64)}}).Format())
}

// commitLock commits a lock (or, for "", removes it) on dir's current branch.
func (f *fixture) commitLock(dir, lock string) {
	f.t.Helper()
	p := filepath.Join(dir, ".claude", "stridal.lock")
	must(f.t, os.MkdirAll(filepath.Dir(p), 0o755))
	if lock == "" {
		_ = os.Remove(p)
	} else {
		must(f.t, os.WriteFile(p, []byte(lock), 0o644))
	}
	f.git(dir, "add", "-A")
	f.git(dir, "commit", "-q", "--allow-empty", "-m", "lock")
}

// setOriginLock moves origin's main to a commit holding lock (or none), and fetches it.
func (f *fixture) setOriginLock(lock string) {
	f.t.Helper()
	f.commitLock(f.up, lock)
	f.git(f.proj, "fetch", "-q", "origin")
}

// result is what one launcher run did.
type result struct {
	code      int
	stderr    string
	ran       bool   // the engine started
	args      string // the engine's arguments
	got       string // the payload the engine read
	unread    int    // payload bytes nobody read
	payloadIn int
}

func (f *fixture) run(hook string) result {
	f.t.Helper()
	return f.runIn(f.proj, hook)
}

func (f *fixture) runIn(proj, hook string) result {
	f.t.Helper()
	_ = os.Remove(f.log)
	_ = os.Remove(f.log + ".stdin")
	r, w, err := os.Pipe()
	must(f.t, err)
	defer r.Close()
	if _, err := w.WriteString(f.payload); err != nil {
		f.t.Fatal(err)
	}
	w.Close()
	c := exec.Command("sh", f.launcher, hook)
	c.Dir = proj
	c.Stdin = r
	var stderr bytes.Buffer
	c.Stderr = &stderr
	env := map[string]string{
		"PATH": os.Getenv("PATH"), "HOME": f.home, "TMPDIR": f.tmp,
		"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
		"CLAUDE_PROJECT_DIR": proj, "CLAUDE_PLUGIN_ROOT": f.plugin, "FAKE_LOG": f.log,
	}
	for k, v := range f.env {
		if v == "" {
			delete(env, k)
		} else {
			env[k] = v
		}
	}
	for k, v := range env {
		c.Env = append(c.Env, k+"="+v)
	}
	err = c.Run()
	res := result{stderr: stderr.String(), payloadIn: len(f.payload)}
	var ee *exec.ExitError
	switch {
	case errors.As(err, &ee):
		res.code = ee.ExitCode()
	case err != nil:
		f.t.Fatal(err)
	}
	if a, err := os.ReadFile(f.log); err == nil {
		res.ran, res.args = true, strings.TrimSpace(string(a))
		g, _ := os.ReadFile(f.log + ".stdin")
		res.got = string(g)
	}
	rest, _ := readAll(r)
	res.unread = len(rest)
	return res
}

func readAll(r *os.File) ([]byte, error) {
	var b bytes.Buffer
	_, err := b.ReadFrom(r)
	return b.Bytes(), err
}

// decide is the Go twin's verdict on the same fixture, read from the environment the launcher got.
func (f *fixture) decide(proj string) Decision {
	env := map[string]string{"HOME": f.home, "TMPDIR": f.tmp, "CLAUDE_PLUGIN_ROOT": f.plugin}
	for k, v := range f.env {
		env[k] = v
	}
	return Decide(context.Background(), EnvFrom(func(k string) string { return env[k] }, proj))
}

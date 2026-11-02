package engine

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/rfhayn/stridal/internal/brand"
)

// FixtureHomeMarker marks a check's fixture HOME. STRIDAL_ENGINE is honoured only under one:
// a HOME that resolves inside the temporary directory and holds this file (ADR-0018 decision 6).
// A hook's environment is Claude Code's, which an agent's Bash cannot change, so a real session
// never runs under one.
const FixtureHomeMarker = ".stridal-fixture-home"

// Env is what a decision reads from the hook's environment. Empty fields read as unset.
type Env struct {
	ProjectDir     string // CLAUDE_PROJECT_DIR, or the git toplevel
	PluginRoot     string // CLAUDE_PLUGIN_ROOT, or the root the plugin's SessionStart recorded
	EngineOverride string // STRIDAL_ENGINE
	Home           string // HOME
	TempDir        string // TMPDIR, or /tmp
}

// EnvFrom reads an Env the way the launcher reads its environment. Without CLAUDE_PLUGIN_ROOT (a
// `stridal install` project's registration, or doctor at a terminal), the plugin root is the one
// the plugin's SessionStart recorded (plugin-session.sh).
func EnvFrom(getenv func(string) string, projectDir string) Env {
	e := Env{
		ProjectDir:     projectDir,
		PluginRoot:     getenv("CLAUDE_PLUGIN_ROOT"),
		EngineOverride: getenv("STRIDAL_ENGINE"),
		Home:           getenv("HOME"),
		TempDir:        getenv("TMPDIR"),
	}
	if e.PluginRoot == "" {
		e.PluginRoot = RecordedPluginRoot(getenv)
	}
	return e
}

// RecordedPluginRoot is the plugin root plugin-session.sh recorded in the plugin's data directory,
// or "" when it has recorded none. Its path is the launcher's, and StatusLineCommand's.
func RecordedPluginRoot(getenv func(string) string) string {
	base := getenv("CLAUDE_CODE_PLUGIN_CACHE_DIR")
	if base == "" {
		conf := getenv("CLAUDE_CONFIG_DIR")
		if conf == "" {
			conf = filepath.Join(getenv("HOME"), ".claude")
		}
		base = filepath.Join(conf, "plugins")
	}
	data, err := os.ReadFile(filepath.Join(base, "data", "stridal-stridal", "root"))
	if err != nil {
		return ""
	}
	return strings.SplitN(string(data), "\n", 2)[0]
}

// Verdict is what the launcher does with a call.
type Verdict int

const (
	// StandAside: the repository runs no model, so the call goes through with its payload unread.
	StandAside Verdict = iota
	// Run: the lock and the engine verified, so the engine judges the call.
	Run
	// Refuse: a marked repository whose pin or engine cannot be trusted. Every guarded call is
	// refused with Reason and Fix, except a recovery command (IsRecovery).
	Refuse
)

func (v Verdict) String() string {
	switch v {
	case StandAside:
		return "stand aside"
	case Run:
		return "run"
	case Refuse:
		return "refuse"
	}
	return fmt.Sprintf("Verdict(%d)", int(v))
}

// Decision is the launcher's verdict, with the facts doctor prints.
type Decision struct {
	Verdict Verdict
	Reason  string // why a call is refused
	Fix     string // the one command that clears it
	LockRef string // the ref the lock was read from
	Lock    *Lock
	Engine  string // the engine path that verified, or was refused
}

// HasMarker says the repository runs the model: from the plugin, or from `stridal install`.
func HasMarker(projectDir string) bool {
	for _, m := range []string{brand.PluginMarker(brand.Name), brand.InstallMarker(brand.Name)} {
		if fi, err := os.Stat(filepath.Join(projectDir, m)); err == nil && !fi.IsDir() {
			return true
		}
	}
	return false
}

// PlatformDir is the engine's directory name for this platform under the plugin's engine/.
func PlatformDir() string { return runtime.GOOS + "-" + runtime.GOARCH }

// EnginePath is where the plugin's engine for this platform lives, or the fixture's
// STRIDAL_ENGINE when HOME is a fixture HOME. Where a release puts its engines is OPS-184's,
// once OPS-199 has found where they can live; until then this is plugin/engine/<goos>-<goarch>.
func EnginePath(e Env) string {
	if e.EngineOverride != "" && IsFixtureHome(e.Home, e.TempDir) {
		return e.EngineOverride
	}
	if e.PluginRoot == "" {
		return ""
	}
	return filepath.Join(e.PluginRoot, "engine", PlatformDir(), brand.Name)
}

// IsFixtureHome says HOME is a check's fixture HOME: it holds FixtureHomeMarker and resolves
// inside the temporary directory.
func IsFixtureHome(home, tmp string) bool {
	if home == "" {
		return false
	}
	if fi, err := os.Stat(filepath.Join(home, FixtureHomeMarker)); err != nil || fi.IsDir() {
		return false
	}
	if tmp == "" {
		tmp = "/tmp"
	}
	h, err1 := filepath.EvalSymlinks(home)
	t, err2 := filepath.EvalSymlinks(tmp)
	if err1 != nil || err2 != nil {
		return false
	}
	return strings.HasPrefix(h, strings.TrimSuffix(t, "/")+"/")
}

// PluginVersion is the version in the plugin root's .claude-plugin/plugin.json.
func PluginVersion(root string) string {
	data, err := os.ReadFile(filepath.Join(root, ".claude-plugin", "plugin.json"))
	if err != nil {
		return ""
	}
	var m struct {
		Version string `json:"version"`
	}
	if json.Unmarshal(data, &m) != nil {
		return ""
	}
	return m.Version
}

// FileSHA256 is a file's sha256, hex.
func FileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// Fix lines, one per refusal, shared with the launcher's.
const (
	FixFetch   = "git fetch origin"
	FixPlugin  = "claude plugin update stridal@stridal"
	FixInstall = "claude plugin install stridal@stridal"
	FixDoctor  = "stridal doctor"
	FixSetHead = "git remote set-head origin --auto"
)

// Decide is the launcher's decision table, in the launcher's order. The first failing row is
// the answer:
//
//	no marker                                  stand aside, payload unread
//	origin with no HEAD, or one off origin     refuse: set origin's HEAD again
//	no origin, main worktree on no branch      refuse: ask doctor
//	no lock at MainRef, or one that won't parse refuse: fetch main's lock (doctor with no origin)
//	no engine pinned for this platform         refuse: the release does not carry one
//	no plugin root                             refuse: install the plugin
//	plugin version != the lock's release       refuse: update the plugin (or the lock, OPS-201)
//	engine missing or not executable           refuse: update the plugin
//	engine sha256 != the lock's                refuse: update the plugin
//	otherwise                                  run the engine
func Decide(ctx context.Context, e Env) Decision {
	if !HasMarker(e.ProjectDir) {
		return Decision{Verdict: StandAside}
	}
	d := Decision{Verdict: Refuse}
	l, ref, err := ReadLock(ctx, e.ProjectDir)
	d.LockRef = ref
	if err != nil {
		d.Reason, d.Fix = err.Error(), FixOf(err)
		return d
	}
	d.Lock = l
	want, ok := l.Engines[Platform()]
	if !ok {
		d.Reason, d.Fix = fmt.Sprintf("the lock at %s pins no engine for %s", ref, Platform()), FixDoctor
		return d
	}
	if e.PluginRoot == "" {
		d.Reason, d.Fix = "no stridal plugin root (CLAUDE_PLUGIN_ROOT is unset and the plugin has recorded none)", FixInstall
		return d
	}
	if v := PluginVersion(e.PluginRoot); v != l.Release {
		if v == "" {
			v = "unknown"
		}
		d.Reason, d.Fix = fmt.Sprintf("the lock at %s pins release %s, and the plugin is %s", ref, l.Release, v), FixPlugin
		return d
	}
	d.Engine = EnginePath(e)
	if fi, err := os.Stat(d.Engine); err != nil || fi.IsDir() || fi.Mode().Perm()&0o111 == 0 {
		d.Reason, d.Fix = "no executable engine at "+d.Engine, FixPlugin
		return d
	}
	got, err := FileSHA256(d.Engine)
	if err != nil || got != want {
		d.Reason, d.Fix = fmt.Sprintf("the engine at %s is not the one the lock pins (sha256 %s, pinned %s)", d.Engine, got, want), FixPlugin
		return d
	}
	return Decision{Verdict: Run, LockRef: ref, Lock: l, Engine: d.Engine}
}

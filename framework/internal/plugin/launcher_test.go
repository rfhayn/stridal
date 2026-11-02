package plugin

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

type handler struct {
	event, matcher string
	h              map[string]any
}

func handlers(t *testing.T, settings []byte) []handler {
	t.Helper()
	var s struct {
		Hooks map[string][]struct {
			Matcher string           `json:"matcher"`
			Hooks   []map[string]any `json:"hooks"`
		} `json:"hooks"`
	}
	if err := json.Unmarshal(settings, &s); err != nil {
		t.Fatal(err)
	}
	events := make([]string, 0, len(s.Hooks))
	for e := range s.Hooks {
		events = append(events, e)
	}
	sort.Strings(events)
	var out []handler
	for _, event := range events {
		for _, g := range s.Hooks[event] {
			for _, h := range g.Hooks {
				out = append(out, handler{event, g.Matcher, h})
			}
		}
	}
	return out
}

// The generator puts exactly the controls (onFailure block, the authority OPS-214's check holds)
// behind the launcher, on the template's real settings.json: every other entry and every other
// key is unchanged, and a second run changes nothing.
func TestLaunchControlsPutsEveryControlBehindTheLauncher(t *testing.T) {
	path := filepath.Join(repoRoot(t), "template", ".claude", "settings.json")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	after, err := LaunchControls(before)
	if err != nil {
		t.Fatal(err)
	}
	var b, a map[string]any
	if err := json.Unmarshal(before, &b); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(after, &a); err != nil {
		t.Fatalf("the generated settings.json does not parse: %v\n%s", err, after)
	}
	delete(b, "hooks")
	delete(a, "hooks")
	if !reflect.DeepEqual(a, b) {
		t.Error("LaunchControls changed a key other than hooks")
	}
	hb, ha := handlers(t, before), handlers(t, after)
	if len(hb) != len(ha) {
		t.Fatalf("%d handlers before, %d after", len(hb), len(ha))
	}
	controls := 0
	for i := range hb {
		cmd := hb[i].h["command"].(string)
		got := ha[i].h["command"].(string)
		if hb[i].h["onFailure"] == "block" {
			controls++
			script := cmd[strings.LastIndex(cmd, "/")+1:]
			if got != ProjectLauncherPrefix+script {
				t.Errorf("%s %s: control %s registered as %q, want it behind the launcher", hb[i].event, hb[i].matcher, script, got)
			}
		} else if got != cmd {
			t.Errorf("%s %s: %q, not a control, became %q", hb[i].event, hb[i].matcher, cmd, got)
		}
		for k, v := range hb[i].h {
			if k != "command" && !reflect.DeepEqual(ha[i].h[k], v) {
				t.Errorf("%s %s: %s changed from %v to %v", hb[i].event, hb[i].matcher, k, v, ha[i].h[k])
			}
		}
	}
	if controls == 0 {
		t.Fatal("the template registers no control: this test learned nothing")
	}
	again, err := LaunchControls(after)
	if err != nil || string(again) != string(after) {
		t.Errorf("a second run changed the settings (err %v)", err)
	}

	// The plugin build carries the launcher form into hooks.json, still through if-project.sh.
	hooks, err := pluginHooks(after)
	if err != nil {
		t.Fatal(err)
	}
	ph := handlers(t, hooks)
	launched := 0
	for _, h := range ph {
		cmd := h.h["command"].(string)
		switch {
		case strings.HasPrefix(cmd, PluginLauncherPrefix):
			launched++
			if h.h["onFailure"] != "block" {
				t.Errorf("%s: %q runs through the launcher without onFailure block", h.event, cmd)
			}
		case h.h["onFailure"] == "block":
			t.Errorf("%s: control %q is not behind the launcher in hooks.json", h.event, cmd)
		}
	}
	if launched == 0 {
		t.Error("hooks.json has no control behind the launcher")
	}
}

// Until OPS-184 ships an engine, the committed registrations stay as they are: OPS-183 ships
// inactive, because a marked repository with no engine refuses every guarded call.
func TestTheCommittedRegistrationsDoNotYetRunTheLauncher(t *testing.T) {
	for _, p := range []string{
		filepath.Join(repoRoot(t), "template", ".claude", "settings.json"),
		filepath.Join(repoRoot(t), PluginDir, "hooks", "hooks.json"),
	} {
		data, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(data), LauncherHook) {
			t.Errorf("%s registers %s before any release carries an engine (OPS-184 registers it)", p, LauncherHook)
		}
	}
}

package plugin

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
)

// The registration forms of a hook, on the two paths that register the model's hooks: a
// `stridal install` project's settings.json (until OPS-145) and the plugin's hooks.json.
const (
	// PluginHookPrefix runs a hook straight from the plugin, as every hook does today.
	PluginHookPrefix = `sh "${CLAUDE_PLUGIN_ROOT}/hooks/if-project.sh" `
	// LauncherHook is the engine's bootstrap launcher (ADR-0018 decision 7), beside the hooks.
	LauncherHook = "stridal-engine.sh"
	// ProjectLauncherPrefix runs a control through the launcher from a project's settings.json.
	ProjectLauncherPrefix = `sh "$CLAUDE_PROJECT_DIR"/.claude/hooks/` + LauncherHook + ` `
	// PluginLauncherPrefix is the same from the plugin: if-project.sh still stands aside where
	// `stridal install` registered the hooks itself, so the two paths never both judge a call.
	PluginLauncherPrefix = PluginHookPrefix + LauncherHook + ` `
)

// launchedCmd matches a control registered through the launcher in a project's settings.json.
var launchedCmd = regexp.MustCompile(`^sh "\$CLAUDE_PROJECT_DIR"/\.claude/hooks/` + regexp.QuoteMeta(LauncherHook) + ` ([A-Za-z0-9_.-]+\.sh)$`)

// LaunchControls is the generator OPS-184 runs once the first release carries an engine: it
// rewrites a settings.json so every control runs through the launcher, which verifies the
// engine against main's lock first. The plugin build then carries the same form into hooks.json
// (pluginHooks reads the launcher form), so both registration paths read the one lock.
//
// A control is an entry registered with "onFailure": "block", the property OPS-214's registration
// check holds every guard to; every other entry (a nudge, a formatter, a hook that fails open on
// purpose) is left as it is. It is idempotent. Until OPS-184 nothing calls it outside its tests:
// a marked repository with no engine refuses every guarded call, so the committed registrations
// stay as they are (OPS-183 ships inactive).
func LaunchControls(settings []byte) ([]byte, error) {
	keys, vals, err := orderedObject(settings)
	if err != nil {
		return nil, fmt.Errorf("settings.json: %w", err)
	}
	var b bytes.Buffer
	b.WriteString("{\n")
	for i, k := range keys {
		v := vals[i]
		if k == "hooks" {
			if v, err = launchHooks(v); err != nil {
				return nil, err
			}
		}
		var pretty bytes.Buffer
		if err := json.Indent(&pretty, v, "  ", "  "); err != nil {
			return nil, err
		}
		if i > 0 {
			b.WriteString(",\n")
		}
		kb, _ := json.Marshal(k)
		fmt.Fprintf(&b, "  %s: %s", kb, pretty.Bytes())
	}
	b.WriteString("\n}\n")
	return b.Bytes(), nil
}

func launchHooks(raw []byte) ([]byte, error) {
	events, groups, err := orderedObject(raw)
	if err != nil {
		return nil, fmt.Errorf("settings.json hooks: %w", err)
	}
	var b bytes.Buffer
	b.WriteString("{")
	for i, event := range events {
		var gs []struct {
			Matcher string           `json:"matcher,omitempty"`
			Hooks   []map[string]any `json:"hooks"`
		}
		if err := json.Unmarshal(groups[i], &gs); err != nil {
			return nil, fmt.Errorf("settings.json hooks.%s: %w", event, err)
		}
		for _, g := range gs {
			for _, h := range g.Hooks {
				if h["onFailure"] != "block" {
					continue
				}
				cmd, _ := h["command"].(string)
				if launchedCmd.MatchString(cmd) {
					continue
				}
				m := hookCmd.FindStringSubmatch(cmd)
				if m == nil {
					return nil, fmt.Errorf("control %q (%s): not of the form sh \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/<x>.sh, so it cannot be put behind the launcher", cmd, event)
				}
				h["command"] = ProjectLauncherPrefix + m[1]
			}
		}
		out, err := marshalCompact(gs)
		if err != nil {
			return nil, err
		}
		if i > 0 {
			b.WriteString(",")
		}
		kb, _ := json.Marshal(event)
		fmt.Fprintf(&b, "%s:%s", kb, bytes.TrimSpace(out))
	}
	b.WriteString("}")
	return b.Bytes(), nil
}

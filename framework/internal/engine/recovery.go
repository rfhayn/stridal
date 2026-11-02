package engine

import (
	"encoding/json"
	"strings"
)

// The recovery allowlist: the commands a refused repository may still run, because they repair
// what it was refused for (ADR-0018 decision 5): fetch main's lock, update the plugin, ask doctor.
// It is the launcher's (recovery() in stridal-engine.sh), because it must run when no engine can
// be trusted; this is its Go twin, held equal to it by TestRecoveryAllowlistMatchesTheLauncher.
//
// The match is exact and coarse on purpose. Only these characters may appear, so no shell
// operator, quote, substitution or newline can carry a second command; git fetch takes only
// operands and a few flags, so no option (--upload-pack, -c) can run a program.
const recoveryChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@:/._=+,- "

var fetchFlags = map[string]bool{"--prune": true, "-p": true, "--all": true, "--quiet": true, "-q": true, "--tags": true, "--no-tags": true}

var pluginCommands = map[string]bool{
	"claude plugin update stridal@stridal":     true,
	"claude plugin install stridal@stridal":    true,
	"claude plugin marketplace update stridal": true,
}

// IsRecovery says whether a Bash command is one the refused repository may still run.
func IsRecovery(command string) bool {
	// The launcher reads the command through $(...), which drops trailing newlines.
	command = strings.TrimRight(command, "\n")
	if command == "" {
		return false
	}
	for _, r := range command {
		if !strings.ContainsRune(recoveryChars, r) {
			return false
		}
	}
	w := strings.Fields(command)
	if pluginCommands[strings.Join(w, " ")] {
		return true
	}
	if len(w) < 2 {
		return false
	}
	switch w[0] + " " + w[1] {
	case "git fetch":
		for _, a := range w[2:] {
			if strings.HasPrefix(a, "-") && !fetchFlags[a] {
				return false
			}
		}
		return true
	case "stridal doctor":
		return true
	}
	return false
}

// PayloadIsRecovery reads a hook payload: a Bash call whose command IsRecovery.
func PayloadIsRecovery(payload []byte) bool {
	var p struct {
		ToolName  string `json:"tool_name"`
		ToolInput struct {
			Command any `json:"command"`
		} `json:"tool_input"`
	}
	if json.Unmarshal(payload, &p) != nil || p.ToolName != "Bash" {
		return false
	}
	c, ok := p.ToolInput.Command.(string)
	return ok && IsRecovery(c)
}

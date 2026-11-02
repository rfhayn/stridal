package engine

import (
	"encoding/json"
	"strings"
)

// The recovery allowlist: the commands a refused repository may still run, because they repair
// what it was refused for (ADR-0018 decision 5): fetch main's lock, set origin's HEAD again,
// update the plugin, ask doctor. It is the launcher's (recovery() in stridal-engine.sh), because it
// must run when no engine can be trusted; this is its Go twin, held equal to it by the recovery
// corpus (TestIsRecoveryMatchesTheCorpus and the launcher's "recovery" cases).
//
// It allows nothing that could repoint what the launcher trusts. Only these characters, so no
// shell operator, quote, substitution, refspec (: +) or transport (::) can appear; git fetch takes
// only the listed flags and the one operand origin, so it can neither run a program
// (--upload-pack, -c) nor write a ref of its choosing (git fetch . +HEAD:refs/remotes/origin/main).
const recoveryChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@._- "

var fetchFlags = map[string]bool{"--prune": true, "-p": true, "--quiet": true, "-q": true, "--tags": true, "--no-tags": true}

var exactRecovery = map[string]bool{
	"stridal doctor":                           true,
	FixSetHead:                                 true,
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
	if exactRecovery[strings.Join(w, " ")] {
		return true
	}
	if len(w) < 2 || w[0] != "git" || w[1] != "fetch" {
		return false
	}
	operand := false
	for _, a := range w[2:] {
		switch {
		case fetchFlags[a]:
		case a == "origin" && !operand:
			operand = true
		default:
			return false
		}
	}
	return true
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

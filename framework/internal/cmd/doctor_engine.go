package cmd

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/rfhayn/stridal/internal/engine"
)

// doctorGetenv is the environment doctor reads the engine's pin through; a test stands in for it.
var doctorGetenv = os.Getenv

// checkEngine is the engine line: what the bootstrap launcher (stridal-engine.sh) would decide
// here, from engine.Decide, its Go twin. Until OPS-224 registers the launcher, no hook runs through
// it, so a refusal is a note: what would be refused, and its fix.
func checkEngine(rep *doctorReport, r *doctorRepo) {
	d := engine.Decide(context.Background(), engine.EnvFrom(doctorGetenv, r.top))
	// With no origin, which branch is main is git config's, never the checkout's: say how to set it.
	if d.Verdict != engine.StandAside && (strings.HasPrefix(d.LockRef, "refs/heads/") || strings.Contains(d.Reason, engine.MainBranchKey)) {
		rep.add(groupProject, doctorLine{level: levelNote, subject: "main",
			detail: fmt.Sprintf("with no origin, the engine's pin is read from the branch git config %s names (%s when unset), never the checked-out branch; to name another: git config %s <branch>",
				engine.MainBranchKey, engine.DefaultMain, engine.MainBranchKey)})
	}
	switch d.Verdict {
	case engine.StandAside:
		return
	case engine.Run:
		rep.add(groupProject, doctorLine{level: levelOK, subject: "engine",
			detail: fmt.Sprintf("the lock at %s pins release %s, and the engine at %s verifies", d.LockRef, d.Lock.Release, d.Engine)})
	default:
		rep.add(groupProject, doctorLine{level: levelNote, subject: "engine",
			detail: d.Reason + "; no hook runs through the engine's launcher yet, so nothing is refused today; once one does, every guarded call here is refused until this is fixed",
			fixes:  []string{d.Fix}})
	}
}

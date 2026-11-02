package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/rfhayn/stridal/internal/engine"
)

// doctorGetenv is the environment doctor reads the engine's pin through; a test stands in for it.
var doctorGetenv = os.Getenv

// checkEngine is the engine line: what the bootstrap launcher (stridal-engine.sh) would decide
// here, from engine.Decide, its Go twin. Until OPS-184 ships the first engine and registers the
// launcher, no hook runs through it, so a refusal is a note: what would be refused, and its fix.
func checkEngine(rep *doctorReport, r *doctorRepo) {
	d := engine.Decide(context.Background(), engine.EnvFrom(doctorGetenv, r.top))
	switch d.Verdict {
	case engine.StandAside:
		return
	case engine.Run:
		rep.add(groupProject, doctorLine{level: levelOK, subject: "engine",
			detail: fmt.Sprintf("the lock at %s pins release %s, and the engine at %s verifies", d.LockRef, d.Lock.Release, d.Engine)})
	default:
		rep.add(groupProject, doctorLine{level: levelNote, subject: "engine",
			detail: d.Reason + "; no hook runs through the engine's launcher yet (OPS-184 registers it), so nothing is refused today; once one does, every guarded call here is refused until this is fixed",
			fixes:  []string{d.Fix}})
	}
}

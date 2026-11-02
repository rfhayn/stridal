package engine

import (
	"strings"
	"testing"
)

// The lock corpus: texts engine.Parse and the launcher's awk must agree on. SUM stands for the
// fixture engine's sha256, PLATFORM for this platform. Each entry is a launcher case and a Parse
// case, so the two readers of one format cannot drift.
var lockCorpus = []struct {
	name, text string
	ok         bool
}{
	{"the canonical form", "release 9.8.7\nengine PLATFORM SUM\n", true},
	{"comments, blank lines, CRLF and indentation", "# pin\r\n\r\n  release 9.8.7\r\n\tengine PLATFORM SUM  \r\n", true},
	{"two platforms", "release 9.8.7\nengine plan9/mips " + strings.Repeat("1", 64) + "\nengine PLATFORM SUM\n", true},
	{"no release", "engine PLATFORM SUM\n", false},
	{"two releases", "release 9.8.7\nrelease 9.8.7\nengine PLATFORM SUM\n", false},
	{"no engine", "release 9.8.7\n", false},
	{"a platform twice", "release 9.8.7\nengine PLATFORM SUM\nengine PLATFORM SUM\n", false},
	{"an upper-case sha256", "release 9.8.7\nengine PLATFORM SUMUPPER\n", false},
	{"a short sha256", "release 9.8.7\nengine PLATFORM SUMSHORT\n", false},
	{"an extra field", "release 9.8.7\nengine PLATFORM SUM extra\n", false},
	{"a release with a space", "release 9.8 .7\nengine PLATFORM SUM\n", false},
	{"an unknown keyword", "release 9.8.7\nengine PLATFORM SUM\nallow all\n", false},
	{"a platform with no arch", "release 9.8.7\nengine " + "darwin SUM\n", false},
	{"only comments", "# nothing pinned\n", false},
}

func lockText(text, sum string) string {
	return strings.NewReplacer("SUMUPPER", strings.ToUpper(sum), "SUMSHORT", sum[:63], "SUM", sum, "PLATFORM", Platform()).Replace(text)
}

func init() {
	for _, e := range lockCorpus {
		e := e
		c := launcherCase{name: "lock: " + e.name,
			setup: func(f *fixture) string { f.setOriginLock(lockText(e.text, f.engineSum())); return "" }}
		if e.ok {
			c.verdict, c.check = Run, ranControl(pluginGuard, 0)
		} else {
			c.verdict, c.check = Refuse, refused("does not parse", "stridal doctor")
		}
		launcherCases = append(launcherCases, c)
	}
}

func TestParseMatchesTheLockCorpus(t *testing.T) {
	sum := strings.Repeat("a", 64)
	for _, e := range lockCorpus {
		l, err := Parse([]byte(lockText(e.text, sum)))
		if (err == nil) != e.ok {
			t.Errorf("%s: Parse error %v, want ok=%v", e.name, err, e.ok)
		}
		if err == nil {
			if back, err := Parse(l.Format()); err != nil || back.Release != l.Release || len(back.Engines) != len(l.Engines) {
				t.Errorf("%s: Format does not read back: %v", e.name, err)
			}
		}
	}
}

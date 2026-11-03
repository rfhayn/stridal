package template

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// project.conf's keys are an allowlist (OPS-219, lib/conf.sh): a shipped module's default key that is
// not on _conf_known would be refused the moment the module is switched on. A project's own module takes
// the prefix PROJECT_, so this holds the shipped modules here, in the framework's own run, and not in a
// check an adopter's vendored module could turn red.
func TestEveryShippedModuleKeyIsOnTheAllowlist(t *testing.T) {
	root := filepath.Join(repoRoot(t), "template", ".claude")
	conf, err := os.ReadFile(filepath.Join(root, "lib", "conf.sh"))
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?s)_conf_known="([^"]*)"`).FindSubmatch(conf)
	if m == nil {
		t.Fatal("conf.sh has no _conf_known")
	}
	known := map[string]bool{}
	for _, k := range strings.Fields(strings.ReplaceAll(string(m[1]), "\\\n", " ")) {
		known[k] = true
	}
	files, err := filepath.Glob(filepath.Join(root, "modules", "*", "module.conf"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no shipped module.conf (%v): this would pass with nothing to read", err)
	}
	key := regexp.MustCompile(`(?m)^([A-Z][A-Z0-9_]*)=`)
	seen := 0
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		for _, k := range key.FindAllSubmatch(data, -1) {
			seen++
			if !known[string(k[1])] {
				t.Errorf("%s sets %s, which is not on _conf_known (lib/conf.sh): conf.sh would refuse it", f, k[1])
			}
		}
	}
	if seen == 0 {
		t.Error("no shipped module sets a key: this test holds nothing")
	}
}

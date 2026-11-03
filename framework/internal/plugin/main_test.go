package plugin

// testgit's init drops a git hook's GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE from this test
// binary before any of its code runs, so no process these tests start reaches the hook's
// repository (#302). TestEveryTestPackageImportsTestgit requires the import.
import (
	"os"
	"testing"

	_ "github.com/rfhayn/stridal/internal/testgit"
)

// The package's one Build (plugin_test.go) outlives every test, so no t.TempDir holds it.
func TestMain(m *testing.M) {
	code := m.Run()
	if sharedBuild.dir != "" {
		os.RemoveAll(sharedBuild.dir)
	}
	os.Exit(code)
}

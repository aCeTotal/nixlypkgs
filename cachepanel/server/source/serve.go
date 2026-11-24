package source

import (
	"errors"
	"os"
	"os/exec"
	"regexp"
	"syscall"
)

var (
	gitCommand = regexp.MustCompile(`^git-(upload-pack|receive-pack) '?/?` + regexp.QuoteMeta(repoName) + `/?'?$`)
	errCommand = errors.New("only git fetch and push of " + repoName + " are allowed")
)

// Serve runs one SSH git request.
func (r *Repo) Serve(request string) error {
	match := gitCommand.FindStringSubmatch(request)
	if match == nil {
		return errCommand
	}
	git, err := exec.LookPath("git")
	if err != nil {
		return err
	}
	return syscall.Exec(git, []string{"git", match[1], r.dir}, os.Environ())
}

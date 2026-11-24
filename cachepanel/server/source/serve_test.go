package source

import "testing"

func TestGitCommand(t *testing.T) {
	allowed := []string{
		"git-receive-pack 'source.git'",
		"git-upload-pack '/source.git'",
		"git-upload-pack source.git",
	}
	for _, request := range allowed {
		if !gitCommand.MatchString(request) {
			t.Errorf("%q rejected", request)
		}
	}
	denied := []string{
		"", "ls", "git-upload-archive 'source.git'", "git-receive-pack 'nixlypkgs.git'",
		"git-receive-pack '../source.git'", "git-receive-pack 'source.git'; rm -rf /",
	}
	for _, request := range denied {
		if gitCommand.MatchString(request) {
			t.Errorf("%q allowed", request)
		}
	}
}

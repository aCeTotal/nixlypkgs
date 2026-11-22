package analyse

import (
	"slices"
	"testing"
)

const pyproject = `[build-system]
build-backend = "hatchling.build"
requires = [
  "hatch-vcs>=0.5",
  "hatchling>=1.32.4",
]

[project]
name = "pipx"
license = { text = "MIT" }
dependencies = ["argcomplete>=1.9.4", 'packaging>=20']

[tool.poetry.dependencies]
python = "^3.9"
requests = "^2"
`

func TestReadTOML(t *testing.T) {
	build := readTOML(pyproject, "build-system")
	if !slices.Equal(build.arrays["requires"], []string{"hatch-vcs>=0.5", "hatchling>=1.32.4"}) {
		t.Errorf("requires = %v", build.arrays["requires"])
	}
	project := readTOML(pyproject, "project")
	if project.values["name"] != "pipx" || project.values["license.table"] != "MIT" || len(project.arrays["dependencies"]) != 2 {
		t.Errorf("project = %+v", project)
	}
	if keys := sectionKeys(pyproject, "tool.poetry.dependencies"); !slices.Equal(keys, []string{"python", "requests"}) {
		t.Errorf("keys = %v", keys)
	}
}

func TestTarname(t *testing.T) {
	cases := map[[2]string]string{{"GNU Hello", ""}: "hello", {"Foo Bar+", ""}: "foo-bar-", {"GNU Hello", "hello2"}: "hello2"}
	for input, want := range cases {
		if got := tarname(input[0], input[1]); got != want {
			t.Errorf("tarname(%q) = %q, want %q", input, got, want)
		}
	}
}

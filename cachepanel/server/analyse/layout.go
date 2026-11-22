package analyse

import (
	"bufio"
	"bytes"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"cachepanel/recipe"
)

const electronDepth = 4

// Chromium helper binaries.
var helpers = map[string]bool{"chrome-sandbox": true, "chrome_crashpad_handler": true, "crashpad_handler": true, "xdg-open": true}

var desktopKeys = []string{"Exec", "TryExec", "Icon"}

// Packages inspects an extracted deb or rpm.
func Packages(root, pname string) recipe.Layout {
	l := recipe.Layout{Mode: recipe.FHSLayout, Electron: electron(root)}
	for _, dir := range []string{"usr", "opt", "etc"} {
		if isDir(filepath.Join(root, dir)) {
			l.Dirs = append(l.Dirs, dir)
		}
	}
	if isDir(filepath.Join(root, "usr/lib/.build-id")) {
		l.Drop = []string{"lib/.build-id"}
	}
	l.Programs = linkedPrograms(root)
	if len(l.Programs) == 0 {
		for _, dir := range subdirs(filepath.Join(root, "opt")) {
			l.Programs = append(l.Programs, programsIn(filepath.Join(root, "opt", dir), "opt/"+dir, pname)...)
		}
	}
	l.Desktops = desktops(filepath.Join(root, "usr/share/applications"), "share/applications", l.Programs)
	return l
}

// archiveLayout inspects an unpacked prebuilt archive.
func archiveLayout(root, pname string) (recipe.Layout, bool) {
	l := recipe.Layout{Electron: electron(root)}
	if isDir(filepath.Join(root, "bin")) {
		l.Mode = recipe.TreeLayout
		l.Desktops = desktops(filepath.Join(root, "share/applications"), "share/applications", nil)
		return l, true
	}
	l.Mode = recipe.AppLayout
	l.Programs = programsIn(root, "opt/"+pname, pname)
	return l, len(l.Programs) > 0
}

// AppImage inspects extracted AppImage contents.
func AppImage(root, pname string) recipe.Layout {
	var l recipe.Layout
	matches, _ := filepath.Glob(filepath.Join(root, "*.desktop"))
	for _, file := range matches {
		desktop := recipe.Desktop{Path: filepath.Base(file)}
		if exec := desktopValue(file, "Exec"); exec != "" {
			desktop.Rewrite = []recipe.Rewrite{{From: "Exec=" + exec, To: "Exec=" + pname}}
		}
		l.Desktops = append(l.Desktops, desktop)
		icon := desktopValue(file, "Icon")
		for _, ext := range []string{".png", ".svg"} {
			if icon != "" && exists(os.DirFS(root), icon+ext) {
				l.Icons = append(l.Icons, icon+ext)
			}
		}
	}
	if isDir(filepath.Join(root, "usr/share/icons")) {
		l.Icons = []string{"usr/share/icons"}
	}
	return l
}

// linkedPrograms follows absolute usr/bin links.
func linkedPrograms(root string) []recipe.Program {
	entries, err := os.ReadDir(filepath.Join(root, "usr/bin"))
	if err != nil {
		return nil
	}
	var programs []recipe.Program
	for _, entry := range entries {
		target, err := os.Readlink(filepath.Join(root, "usr/bin", entry.Name()))
		if err != nil || !path.IsAbs(target) {
			continue
		}
		rel := strings.TrimPrefix(target, "/")
		if usr, ok := strings.CutPrefix(rel, "usr/"); ok {
			rel = usr
		}
		programs = append(programs, recipe.Program{Name: entry.Name(), Path: rel})
	}
	return programs
}

// programsIn lists executables, pname first.
func programsIn(dir, installed, pname string) []recipe.Program {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var programs []recipe.Program
	for _, entry := range entries {
		if helpers[entry.Name()] || strings.Contains(entry.Name(), ".so") || !executable(filepath.Join(dir, entry.Name())) {
			continue
		}
		programs = append(programs, recipe.Program{Name: entry.Name(), Path: installed + "/" + entry.Name()})
	}
	named := slices.IndexFunc(programs, func(p recipe.Program) bool { return normalized(p.Name) == normalized(pname) })
	if named >= 0 {
		return programs[named : named+1]
	}
	return programs
}

// desktops rewrites absolute FHS paths in launchers.
func desktops(dir, installed string, programs []recipe.Program) []recipe.Desktop {
	matches, _ := filepath.Glob(filepath.Join(dir, "*.desktop"))
	var found []recipe.Desktop
	for _, file := range matches {
		desktop := recipe.Desktop{Path: installed + "/" + filepath.Base(file)}
		for _, key := range desktopKeys {
			value := desktopValue(file, key)
			if to, ok := relocated(value, programs); ok {
				desktop.Rewrite = append(desktop.Rewrite, recipe.Rewrite{From: key + "=" + value, To: key + "=" + to})
			}
		}
		if len(desktop.Rewrite) > 0 {
			found = append(found, desktop)
		}
	}
	return found
}

// relocated maps FHS paths into $out.
func relocated(value string, programs []recipe.Program) (string, bool) {
	if !path.IsAbs(value) {
		return "", false
	}
	rel := strings.TrimPrefix(value, "/")
	if usr, ok := strings.CutPrefix(rel, "usr/"); ok {
		rel = usr
	}
	for _, program := range programs {
		if program.Path == rel || "bin/"+program.Name == rel {
			return program.Name, true
		}
	}
	if name, ok := strings.CutPrefix(rel, "bin/"); ok {
		return name, true
	}
	return "$out/" + rel, true
}

// desktopValue reads a key's first token.
func desktopValue(file, key string) string {
	content, err := readIn(file)
	if err != nil {
		return ""
	}
	scanner := bufio.NewScanner(bytes.NewReader(content))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "[") && line != "[Desktop Entry]" {
			return ""
		}
		if value, ok := strings.CutPrefix(line, key+"="); ok {
			first, _, _ := strings.Cut(strings.TrimSpace(value), " ")
			return strings.Trim(first, `"`)
		}
	}
	return ""
}

func electron(root string) bool {
	found := false
	_ = filepath.WalkDir(root, func(file string, entry fs.DirEntry, err error) error {
		if err != nil || found {
			return fs.SkipAll
		}
		rel, _ := filepath.Rel(root, file)
		if entry.IsDir() && strings.Count(rel, string(filepath.Separator)) >= electronDepth {
			return fs.SkipDir
		}
		found = strings.HasSuffix(file, "resources/app.asar") || entry.Name() == "chrome-sandbox"
		return nil
	})
	return found
}

func executable(file string) bool {
	info, err := os.Stat(file)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return false
	}
	head := make([]byte, 4)
	f, err := openIn(file)
	if err != nil {
		return false
	}
	defer func() { _ = f.Close() }()
	n, _ := f.Read(head)
	return n == 4 && (bytes.Equal(head, []byte("\x7fELF")) || bytes.HasPrefix(head, []byte("#!")))
}

func isDir(dir string) bool {
	info, err := os.Stat(dir)
	return err == nil && info.IsDir()
}

func normalized(name string) string {
	return strings.ToLower(strings.NewReplacer("-", "", "_", "", " ", "").Replace(name))
}

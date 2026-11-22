package recipe

import "path"

// Ozone Wayland flags, opt-in.
const ozoneFlags = `--add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"`

// Libraries Electron opens at runtime.
var electronRuntime = []string{"systemdLibs", "libGL", "vulkan-loader"}

var unpackers = map[Builder]struct{ tool, command string }{
	Deb: {"dpkg", "dpkg-deb -x $curSrc source"},
	Rpm: {"libarchive", "mkdir source && bsdtar -xf $curSrc -C source"},
}

func prebuilt(w *writer, s Spec) {
	native := with(s.Native, "autoPatchelfHook")
	w.printf("%s {\n", w.use("stdenv")+".mkDerivation")
	w.head(s)
	w.src(s)
	if unpack, ok := unpackers[s.Builder]; ok {
		native = with(native, unpack.tool)
		w.str("unpackCmd", unpack.command)
	}
	if s.Builder == Prebuilt && s.Layout.Flat {
		native = with(native, "libarchive")
		w.str("unpackCmd", unpackers[Rpm].command)
	}
	w.flag("dontUnpack", s.Layout.Mode == FileLayout)
	if s.Layout.Electron || len(s.Layout.Programs) > 0 && s.Layout.Mode == AppLayout {
		native = with(native, "makeWrapper")
	}
	w.attrs("nativeBuildInputs", native)
	w.attrs("buildInputs", s.Inputs)
	if s.Layout.Electron {
		w.attrs("runtimeDependencies", electronRuntime)
	}
	w.strings("autoPatchelfIgnoreMissingDeps", s.Ignored)
	w.script("installPhase", installLines(s))
	w.flag("dontStrip", s.NoStrip)
	w.meta(s, x86)
	w.printf("}\n")
}

func installLines(s Spec) []string {
	lines := []string{"runHook preInstall", ""}
	switch s.Layout.Mode {
	case FileLayout:
		return append(lines, "install -Dm755 $src $out/bin/"+lit(s.Pname), "", "runHook postInstall")
	case FHSLayout:
		lines = append(lines, "mkdir -p $out")
		for _, dir := range s.Layout.Dirs {
			if dir == "usr" {
				lines = append(lines, "cp -r usr/. $out")
				continue
			}
			lines = append(lines, "cp -r "+lit(dir)+" $out")
		}
	case TreeLayout:
		lines = append(lines, "mkdir -p $out", "cp -r . $out")
	case AppLayout:
		lines = append(lines, "mkdir -p "+outPath("opt/"+s.Pname), "cp -r . "+outPath("opt/"+s.Pname))
	}
	for _, leftover := range s.Layout.Drop {
		lines = append(lines, "rm -rf "+outPath(leftover))
	}
	lines = append(lines, programLines(s)...)
	lines = append(lines, desktopLines(s.Layout.Desktops, "$out/")...)
	return append(lines, "", "runHook postInstall")
}

func programLines(s Spec) []string {
	if len(s.Layout.Programs) == 0 {
		return nil
	}
	lines := []string{"", "mkdir -p $out/bin"}
	for _, program := range s.Layout.Programs {
		link := outPath("bin/" + program.Name)
		if s.Layout.Electron {
			lines = append(lines, "makeWrapper "+outPath(program.Path)+" "+link+" "+ozoneFlags)
			continue
		}
		lines = append(lines, "ln -sf "+outPath(program.Path)+" "+link)
	}
	return lines
}

func desktopLines(desktops []Desktop, base string) []string {
	var lines []string
	for _, desktop := range desktops {
		file := target(base + desktop.Path)
		for _, rewrite := range desktop.Rewrite {
			lines = append(lines, "substituteInPlace "+file+" --replace-fail "+lit(rewrite.From)+" "+target(rewrite.To))
		}
	}
	return lines
}

func appImage(w *writer, s Spec) {
	w.printf("let\n")
	w.head(s)
	w.printf("\n  src = %s;\n\n", indent(w.fetcher(s.Sources[0], 0)))
	w.printf("  appimageContents = %s.extractType2 { inherit pname version src; };\nin\n", w.use("appimageTools"))
	w.printf("%s.wrapType2 {\n  inherit pname version src;\n\n", w.use("appimageTools"))
	var lines []string
	for _, desktop := range s.Layout.Desktops {
		lines = append(lines, "install -Dm444 ${appimageContents}/"+lit(desktop.Path)+" -t $out/share/applications")
		renamed := Desktop{Path: "share/applications/" + path.Base(desktop.Path), Rewrite: desktop.Rewrite}
		lines = append(lines, desktopLines([]Desktop{renamed}, "$out/")...)
	}
	for _, icon := range s.Layout.Icons {
		if path.Base(icon) == "icons" {
			lines = append(lines, "mkdir -p $out/share", "cp -r ${appimageContents}/"+lit(icon)+" $out/share")
			continue
		}
		lines = append(lines, "install -Dm444 ${appimageContents}/"+lit(icon)+" -t $out/share/pixmaps")
	}
	w.script("extraInstallCommands", lines)
	w.meta(s, x86)
	w.printf("}\n")
}

package recipe

func cargo(w *writer, s Spec) {
	w.printf("%s {\n", w.use("rustPlatform")+".buildRustPackage")
	w.head(s)
	w.src(s)
	w.str("sourceRoot", s.Root)
	w.str("cargoHash", hashOr(s.VendorHash, VendorSlot))
	w.attrs("nativeBuildInputs", s.Native)
	w.attrs("buildInputs", s.Inputs)
	w.printf("  doCheck = false;\n")
	w.meta(s, linux)
	w.printf("}\n")
}

func goModule(w *writer, s Spec) {
	w.printf("%s {\n", w.use("buildGoModule"))
	w.head(s)
	w.src(s)
	w.str("sourceRoot", s.Root)
	if s.Vendored {
		w.printf("  vendorHash = null;\n")
	} else {
		w.str("vendorHash", hashOr(s.VendorHash, VendorSlot))
	}
	w.strings("subPackages", s.SubPackages)
	w.attrs("nativeBuildInputs", s.Native)
	w.attrs("buildInputs", s.Inputs)
	w.strings("ldflags", []string{"-s", "-w"})
	w.printf("  doCheck = false;\n")
	w.meta(s, linux)
	w.printf("}\n")
}

func python(w *writer, s Spec) {
	w.printf("%s {\n", w.use("python3Packages")+".buildPythonApplication")
	w.head(s)
	w.printf("  pyproject = true;\n")
	w.src(s)
	w.str("sourceRoot", s.Root)
	w.attrs("build-system", s.BuildSystem)
	w.attrs("nativeBuildInputs", s.Native)
	w.attrs("buildInputs", s.Inputs)
	w.attrs("dependencies", s.PythonDeps)
	w.strings("pypaBuildFlags", s.Flags)
	w.printf("  pythonRelaxDeps = true;\n  doCheck = false;\n")
	w.meta(s, linux)
	w.printf("}\n")
}

func npm(w *writer, s Spec) {
	w.printf("%s {\n", w.use("buildNpmPackage"))
	w.head(s)
	w.src(s)
	w.str("sourceRoot", s.Root)
	w.str("npmDepsHash", hashOr(s.VendorHash, VendorSlot))
	w.flag("dontNpmBuild", s.NoBuild)
	w.attrs("nativeBuildInputs", s.Native)
	w.attrs("buildInputs", s.Inputs)
	w.meta(s, linux)
	w.printf("}\n")
}

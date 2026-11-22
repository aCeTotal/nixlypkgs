package recipe

// Flag attribute and tools per builder.
var compiledFlags = map[Builder]struct {
	name  string
	tools []string
}{
	CMake:     {"cmakeFlags", []string{"cmake"}},
	Meson:     {"mesonFlags", []string{"meson", "ninja"}},
	Autotools: {"configureFlags", nil},
	Make:      {"makeFlags", nil},
}

func compiled(w *writer, s Spec) {
	flags := compiledFlags[s.Builder]
	w.printf("%s {\n", w.use("stdenv")+".mkDerivation")
	w.head(s)
	w.src(s)
	w.str("sourceRoot", s.Root)
	w.attrs("nativeBuildInputs", with(s.Native, flags.tools...))
	w.attrs("buildInputs", s.Inputs)
	w.strings(flags.name, s.Flags)
	w.flag("dontStrip", s.NoStrip)
	w.meta(s, linux)
	w.printf("}\n")
}

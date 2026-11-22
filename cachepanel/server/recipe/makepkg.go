package recipe

import "cachepanel/nixexpr"

var vendorAttrs = map[Vendor]string{CargoVendor: "cargoHash", GoVendor: "goHash", NpmVendor: "npmHash"}

func makepkg(w *writer, s Spec) {
	w.printf("%s {\n", w.use("buildArchPackage"))
	w.head(s)
	w.printf("  pkgbuild = ./PKGBUILD;\n\n  srcs = [\n")
	for i, source := range s.Sources {
		expr := w.fetcher(source, i)
		if source.Kind != File {
			expr = "(" + indent(indent(expr)) + ")"
		}
		w.printf("    %s\n", expr)
	}
	w.printf("  ];\n\n")
	w.str("split", s.Split)
	w.strings("noextract", s.NoExtract)
	w.attrs("nativeBuildInputs", s.Native)
	w.attrs("buildInputs", s.Inputs)
	w.attrs("depends", s.Depends)
	w.attrs("pythonDepends", s.PythonDeps)
	if attr, ok := vendorAttrs[s.Vendor]; ok {
		w.printf("  %s = %s;\n", attr, nixexpr.String(hashOr(s.VendorHash, VendorSlot)))
	}
	w.strings("autoPatchelfIgnoreMissingDeps", s.Ignored)
	w.flag("dontStrip", s.NoStrip)
	w.meta(s, linux)
	w.printf("}\n")
}

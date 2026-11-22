package nixexpr

// System is the recipe platform.
const System = "x86_64-linux"

// Pkgs is the cached package set.
func Pkgs(flakeRef string) string {
	return "((builtins.getFlake " + String(flakeRef) + ").lib.nixlyos.pkgs " + String(System) + ")"
}

// Nixpkgs is that set without nixlypkgs.
func Nixpkgs(flakeRef string) string {
	return "((builtins.getFlake " + String(flakeRef) + ").lib.nixlyos.nixpkgs " + String(System) + ")"
}

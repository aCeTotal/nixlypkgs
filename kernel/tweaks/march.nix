# x86-64-nivå per variant.
let
  level = v: {
    flags = [
      "-e GENERIC_CPU"
      "-d MZEN4"
      "-d X86_NATIVE_CPU"
      "--set-val X86_64_VERSION ${toString v}"
    ];
    check = "X86_64_VERSION=${toString v}";
  };
in
{
  generic = level 1;
  v3 = level 3;
}

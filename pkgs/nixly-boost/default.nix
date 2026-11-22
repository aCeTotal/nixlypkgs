{ runCommandCC, makeBinaryWrapper, nixly-dgpu }:

# Full priority and dGPU for one command.
runCommandCC "nixly-boost" { nativeBuildInputs = [ makeBinaryWrapper ]; } ''
  mkdir -p $out/libexec
  $CC -O2 -Wall -Wextra -Werror ${./boost.c} -o $out/libexec/nixly-boost
  makeBinaryWrapper ${nixly-dgpu}/bin/nixly-dgpu $out/bin/nixly-boost \
    --add-flag $out/libexec/nixly-boost
''

{ stdenvNoCC, lib }:

stdenvNoCC.mkDerivation {
  pname = "nixly-hello";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/nixly-hello <<'EOF'
    #!/usr/bin/env bash
    echo "Hello from nixlypkgs!"
    echo "System: $(uname -sm)"
    EOF
    chmod +x $out/bin/nixly-hello
  '';

  meta = with lib; {
    description = "Simple example package from nixlypkgs";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}


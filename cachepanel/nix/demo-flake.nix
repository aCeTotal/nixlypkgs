# Demo nixlypkgs for tests.
{
  outputs = { self }:
    let
      system = "x86_64-linux";
      # Dev stacks may lend packages.
      packageSet = builtins.getFlake (builtins.getEnv "CACHEPANEL_DEMO_PACKAGES");
      revision = builtins.readFile ./revision;
      demo = name: steps: derivation {
        inherit name system;
        builder = "/bin/sh";
        args = [ "-c" ''
          echo "building ${name} at revision ${revision}"
          i=0
          while [ $i -lt ${toString steps} ]; do
            echo "step $i of ${toString steps}"
            j=0
            while [ $j -lt 100000 ]; do j=$((j + 1)); done
            i=$((i + 1))
          done
          echo ${revision} > $out
        '' ];
      };
    in
    {
      packages.${system} = {
        hello-demo = demo "hello-demo" 3;
        clock-demo = demo "clock-demo" 8;
        # Stands in for a newer panel.
        cachepanel = derivation {
          name = "cachepanel-demo";
          inherit system;
          builder = "/bin/sh";
          args = [ "-c" "echo panel > $out" ];
        };
        steady-demo = derivation {
          name = "steady-demo";
          inherit system;
          builder = "/bin/sh";
          args = [ "-c" "echo steady > $out" ];
        };
      };

      lib.nixlyos = {
        pinnable = _: [ "hello-demo" "clock-demo" ];
        kernels = _: {
          performance = {
            title = "Performance";
            description = "Demo kernel.";
            settings.tickRate = {
              title = "Timer frequency";
              description = "Ticks per second.";
              kind = "build";
              options = [ "300" "1000" ];
              default = "1000";
            };
          };
        };
        pkgs = system: packageSet.lib.nixlyos.pkgs system;
        nixpkgs = system: packageSet.lib.nixlyos.nixpkgs system;
      };
    };
}

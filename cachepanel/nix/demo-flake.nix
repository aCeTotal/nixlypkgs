# Demo nixlypkgs for tests.
{
  outputs = { self }:
    let
      system = "x86_64-linux";
      # Dev stacks may lend packages.
      packageSet = builtins.getFlake (builtins.getEnv "CACHEPANEL_DEMO_PACKAGES");
      revision = builtins.readFile ./revision;
      # A derivation the panel keeps in step with its upstream.
      tracked = builtins.fromJSON (builtins.readFile ./pkgs/tracked-demo/source.json);
      trackedSrc = builtins.fetchTree { type = "git"; inherit (tracked) url rev; narHash = tracked.hash; };
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
      } // (if builtins.pathExists ./pkgs/tracked-demo/source.json then {
        tracked-demo = derivation {
          name = "tracked-demo-${tracked.version}";
          inherit system;
          builder = "/bin/sh";
          args = [ "-c" "while read -r line; do echo \"$line\"; done < ${trackedSrc}/value > $out" ];
        };
      } else { });

      lib.nixlyos = {
        pinnable = _: [ "hello-demo" "clock-demo" ] ++ (if builtins.pathExists ./pkgs/tracked-demo/source.json then [ "tracked-demo" ] else [ ]);
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
        editor = system: {
          options = [ { name = "nixlyos.demo.enable"; type = "boolean"; description = "Turns the demo on."; } ];
          packages = builtins.attrNames self.packages.${system};
          lib = [ "mkIf" "mkOption" ];
          builtins = builtins.attrNames builtins;
        };
      };
    };
}

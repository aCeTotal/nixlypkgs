# Kernelinnstillinger en profil kan endre.
{ lib }:
let
  rates = [ "100" "250" "300" "1000" ];

  knobs = {
    tickRate = {
      title = "Timer frequency";
      description = "Ticks per second. Higher reacts sooner, lower leaves more time for work.";
      kind = "build";
      owns = [ "HZ" ] ++ map (rate: "HZ_${rate}") rates;
      options = lib.genAttrs rates (rate: {
        tweaks = map (other: "-d HZ_${other}") rates ++ [ "-e HZ_${rate}" "--set-val HZ ${rate}" ];
        checks = [ "HZ=${rate}" ];
      });
    };

    tickless = {
      title = "Idle ticks";
      description = "Full stops the tick on busy cores too, idle only on idle cores, periodic never.";
      kind = "build";
      owns = [ "NO_HZ_FULL" "NO_HZ_IDLE" "HZ_PERIODIC" ];
      options = {
        full = {
          tweaks = [ "-d HZ_PERIODIC" "-d NO_HZ_IDLE" "-e NO_HZ_FULL" ];
          checks = [ "NO_HZ_FULL=y" ];
        };
        idle = {
          tweaks = [ "-d HZ_PERIODIC" "-d NO_HZ_FULL" "-e NO_HZ_IDLE" ];
          checks = [ "NO_HZ_IDLE=y" ];
        };
        periodic = {
          tweaks = [ "-d NO_HZ_FULL" "-d NO_HZ_IDLE" "-e HZ_PERIODIC" ];
          checks = [ "HZ_PERIODIC=y" ];
        };
      };
    };

    preemption = {
      title = "Preemption";
      description = "Full switches to urgent work at once; lazy batches switches for throughput.";
      kind = "boot";
      param = "preempt";
      options = {
        full.checks = [ "PREEMPT=y" ];
        lazy.checks = [ "PREEMPT_LAZY=y" ];
      };
    };

    hugepages = {
      title = "Transparent huge pages";
      description = "Always speeds up memory-hungry games; madvise leaves it to programs that ask.";
      kind = "boot";
      param = "transparent_hugepage";
      options = {
        always.checks = [ "TRANSPARENT_HUGEPAGE_ALWAYS=y" ];
        madvise.checks = [ "TRANSPARENT_HUGEPAGE_MADVISE=y" ];
        never.checks = [ "TRANSPARENT_HUGEPAGE_NEVER=y" ];
      };
    };

    congestion = {
      title = "TCP congestion control";
      description = "BBR keeps latency low under load; CUBIC is the classic choice.";
      kind = "sysctl";
      sysctl = "net.ipv4.tcp_congestion_control";
      options = {
        bbr3 = {
          value = "bbr3";
          cachy = true;
          checks = [ "DEFAULT_TCP_CONG=.bbr3." ];
        };
        bbr = {
          value = "bbr";
          checks = [ "DEFAULT_TCP_CONG=.bbr." ];
        };
        cubic = {
          value = "cubic";
          checks = [ "DEFAULT_TCP_CONG=.cubic." ];
        };
      };
    };

    scheduler = {
      title = "Scheduler";
      description = "BORE favours interactive tasks; EEVDF is the vanilla fair scheduler.";
      kind = "sysctl";
      sysctl = "kernel.sched_bore";
      options = {
        bore = {
          value = "1";
          checks = [ "SCHED_BORE=y" ];
        };
        eevdf = {
          value = "0";
          checks = [ "SCHED_BORE=y" ];
        };
      };
    };
  };
in
{
  inherit knobs;

  # Verdiene hver kernel godtar, per innstilling.
  available = entry: lib.mapAttrs
    (knob: _: lib.attrNames (lib.filterAttrs (_: option: entry.cachy || !(option.cachy or false)) knobs.${knob}.options))
    entry.defaults;
}

# The slice nixly-gfn launches into. Weights are relative to the other
# app.slice scopes (default 100), so anything else in the session yields
# CPU and disk to the stream. MemoryLow keeps its working set out of
# reclaim; the cgroup path is also what the runtime DSCP rule matches.
{ ... }:

{
  systemd.user.slices.gfn = {
    description = "GeForce NOW stream";
    sliceConfig = {
      CPUWeight = 10000;
      IOWeight = 1000;
      MemoryLow = "4G";
    };
  };
}

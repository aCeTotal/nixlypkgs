# Kernelene en profil kan velge.
{
  performance = {
    title = "Performance";
    description = "CachyOS with BORE for the fastest start-up and games. CPUs without AVX2 get the same kernel for any x86-64.";
    variant = "v3";
    fallback = "generic";
    level = 3;
    cachy = true;
    inTree = false;
    lockModules = false;
    defaults = {
      tickRate = "1000";
      tickless = "full";
      preemption = "full";
      hugepages = "always";
      congestion = "bbr3";
      scheduler = "bore";
    };
  };

  server = {
    title = "Server";
    description = "Hardened vanilla for every kind of service: games, web and files.";
    variant = "server";
    fallback = "server";
    level = 0;
    cachy = false;
    inTree = false;
    lockModules = false;
    defaults = {
      tickRate = "1000";
      tickless = "idle";
      preemption = "lazy";
      hugepages = "madvise";
      congestion = "bbr";
    };
  };

  enterprise = {
    title = "Enterprise";
    description = "Vanilla, minimal and fully hardened. Module loading locks once the machine has booted.";
    variant = "enterprise";
    fallback = "enterprise";
    level = 0;
    cachy = false;
    inTree = true;
    lockModules = true;
    defaults = {
      tickRate = "1000";
      tickless = "idle";
      preemption = "full";
      hugepages = "madvise";
      congestion = "bbr";
    };
  };
}

{ ... }:

{
  # Throttle at 90 °C; acpitz kills power at 100.
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="proc_thermal", ATTR{tcc_offset_degree_celsius}="10"
  '';
}

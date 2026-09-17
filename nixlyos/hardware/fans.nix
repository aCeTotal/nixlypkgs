{ ... }:

{
  # Desktop board fans hang off a SuperIO chip that nothing probes on its
  # own, so hwmon shows no pwm until these are loaded. Both drivers bind
  # only to chips they recognise and are harmless elsewhere.
  boot.kernelModules = [ "nct6775" "it87" ];

  # ITE chips usually sit in an IO range ACPI has already claimed.
  boot.extraModprobeConfig = ''
    options it87 ignore_resource_conflict=1
  '';
}

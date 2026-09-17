{ nixlyUser, ... }:

let
  home = "/home/${nixlyUser}";
in
{
  # Path watches only, plus the three module syscalls: they cost nothing
  # until something actually touches a persistence point, unlike a
  # syscall-wide execve rule that taxes every process start.
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      "-w /etc/shadow -p wa -k creds"
      "-w /etc/passwd -p wa -k creds"
      "-w /etc/group -p wa -k creds"
      "-w /root/.ssh -p wa -k ssh-keys"
      "-w ${home}/.ssh -p wa -k ssh-keys"
      # Autostart: where a backdoor installs itself to survive a reboot.
      "-w ${home}/.config/autostart -p wa -k autostart"
      "-w ${home}/.config/systemd/user -p wa -k autostart"
      "-w ${home}/.config/environment.d -p wa -k autostart"
      "-w ${home}/.bashrc -p wa -k autostart"
      "-w ${home}/.profile -p wa -k autostart"
      "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules"
    ];
  };
}

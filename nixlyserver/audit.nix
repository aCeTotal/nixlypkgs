{ nixlyUser, ... }:

{
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      "-w /etc/shadow -p wa -k creds"
      "-w /etc/passwd -p wa -k creds"
      "-w /etc/group -p wa -k creds"
      "-w /etc/ssh -p wa -k ssh"
      "-w /home/${nixlyUser}/.ssh -p wa -k ssh"
      "-w /etc/nixlyserver -p wa -k config"
      "-w /var/lib/sbctl -p rwa -k secureboot"
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k root-exec"
    ];
  };
}

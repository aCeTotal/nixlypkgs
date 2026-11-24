# Signaturkrav og lockdown.
caCert: [
  "-e MODULE_SIG"
  "-e MODULE_SIG_FORCE"
  "-d MODULE_SIG_ALL"
  "-e MODULE_SIG_SHA512"
  "--set-str MODULE_SIG_HASH sha512"
  "--set-str MODULE_SIG_KEY ${caCert}"
  # Signaturen henger på ukomprimert modul.
  "-d MODULE_COMPRESS"

  "-e SECURITY_LOCKDOWN_LSM"
  "-e SECURITY_LOCKDOWN_LSM_EARLY"
  "-d LOCK_DOWN_KERNEL_FORCE_NONE"
  "-d LOCK_DOWN_KERNEL_FORCE_INTEGRITY"
  "-e LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY"
]

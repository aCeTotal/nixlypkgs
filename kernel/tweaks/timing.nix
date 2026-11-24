# 1000Hz tick, full tickless, full preempt (tilsvarer _HZ_ticks=1000,
# _tickrate=full, _preempt=full) — lav latens og jevn framepacing.
[
  "-d HZ_300"
  "-e HZ_1000"
  "--set-val HZ 1000"

  "-d HZ_PERIODIC"
  "-d NO_HZ_IDLE"
  "-d CONTEXT_TRACKING_FORCE"
  "-e NO_HZ_FULL_NODEF"
  "-e NO_HZ_FULL"
  "-e NO_HZ"
  "-e NO_HZ_COMMON"
  "-e CONTEXT_TRACKING"

  "-e PREEMPT"
  "-d PREEMPT_LAZY"
]

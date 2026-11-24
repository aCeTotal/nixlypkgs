# -O3, THP, thin-LTO, BBR3.
[
  "-d CC_OPTIMIZE_FOR_PERFORMANCE"
  "-e CC_OPTIMIZE_FOR_PERFORMANCE_O3"

  "-d TRANSPARENT_HUGEPAGE_MADVISE"
  "-e TRANSPARENT_HUGEPAGE_ALWAYS"

  "-e LTO_CLANG_THIN"

  # "bbr" er vanilla BBR v1.
  "-m TCP_CONG_CUBIC"
  "-d DEFAULT_CUBIC"
  "-e TCP_CONG_BBR3"
  "-e DEFAULT_BBR3"
  "--set-str DEFAULT_TCP_CONG bbr3"
  "-m NET_SCH_FQ_CODEL"
  "-e NET_SCH_FQ"
  "-d DEFAULT_FQ_CODEL"
  "-e DEFAULT_FQ"

  # Wine-synkronisering uten modullasting.
  "-e NTSYNC"

  # Latens foran strømsparing.
  "-d WQ_POWER_EFFICIENT_DEFAULT"
  "-d RCU_LAZY"
]

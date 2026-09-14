#!/usr/bin/env python3
# HTPC silence gate. Apps play into a PCM null sink ("nixly_gate") that is the
# default output; a loopback carries that sink's monitor to the real display
# (HDMI/DP) sink. When the mixed signal is truly silent for GRACE seconds the
# loopback is dropped, the display sink goes idle and WirePlumber suspends it,
# which pulls the HDMI/DP audio infoframe and lets the TV amp mute (no idle
# hiss). The first non-silent sample re-adds the loopback and the sink resumes.
#
# Why a null sink and not the display monitor: detection has to keep working
# while the display sink is suspended, so the level is read from the always-hot
# null-sink monitor (kept alive by suspend-timeout=0 plus this parec), never
# from the sink we are suspending.
#
# Fail-open: the loopback starts UP, so if this daemon dies mid-playback audio
# keeps flowing. Encoded/passthrough streams (AC3/EAC3/DTS) cannot open the PCM
# null sink, so WirePlumber routes them straight to the display sink, untouched.
import os, sys, time, signal, array, re, subprocess as sp

PACTL = os.environ.get("PACTL", "pactl")
PAREC = os.environ.get("PAREC", "parec")
PWCLI = os.environ.get("PWCLI", "pw-cli")
NULL = "nixly_gate"
GRACE = float(os.environ.get("GATE_GRACE", "1.0"))   # silence before muting
THRESH = int(os.environ.get("GATE_THRESH", "100"))   # s16 peak floor to ignore
RATE = 8000
CHUNK = 1600                                          # ~100 ms of s16 mono


def pactl(*a):
    return sp.run([PACTL, *a], capture_output=True, text=True).stdout.strip()


def find_display_sink():
    # HDMI and DisplayPort audio share the alsa "hdmi" node name; skip our own
    # null sink. First match wins (htpc/audio.nix pins the display sink first).
    for line in pactl("list", "short", "sinks").splitlines():
        f = line.split("\t")
        if len(f) >= 2 and "hdmi" in f[1] and NULL not in f[1]:
            return f[1]
    return None


def destroy_stale():
    # A null sink loaded via the pulse layer gets a pipewire-range module id
    # that "pactl unload-module" cannot always remove, so a crashed instance
    # leaves the sink behind. Destroy the node directly by name; harmless when
    # none exists.
    out = sp.run([PWCLI, "ls", "Node"], capture_output=True, text=True).stdout
    cur = None
    for line in out.splitlines():
        m = re.search(r"id (\d+),", line)
        if m:
            cur = m.group(1)
        if 'node.name = "%s"' % NULL in line and cur:
            sp.run([PWCLI, "destroy", cur], capture_output=True)


state = {"loop": None, "null": None, "sink": None, "parec": None}


def loop_up():
    if state["loop"]:
        return
    mid = pactl("load-module", "module-loopback",
                "source=%s.monitor" % NULL, "sink=%s" % state["sink"],
                "latency_msec=20", "sink_dont_move=true", "source_dont_move=true")
    state["loop"] = mid or None


def loop_down():
    if not state["loop"]:
        return
    pactl("unload-module", state["loop"])
    state["loop"] = None


def cleanup(*_):
    if state["parec"]:
        try:
            state["parec"].kill()
        except Exception:
            pass
    loop_down()
    if state["null"]:
        pactl("unload-module", state["null"])
        state["null"] = None
    destroy_stale()
    if state["sink"]:
        pactl("set-default-sink", state["sink"])   # hand default back to display
    sys.exit(0)


signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

# Wait for pipewire-pulse to answer.
for _ in range(30):
    if pactl("info"):
        break
    time.sleep(1)

state["sink"] = find_display_sink()
if not state["sink"]:
    sys.exit(0)   # no display sink: no gate, audio stays direct

destroy_stale()
state["null"] = pactl(
    "load-module", "module-null-sink", "sink_name=%s" % NULL,
    "sink_properties=session.suspend-timeout-seconds=0 "
    "node.description=NixlyGate priority.session=4000 priority.driver=4000") or None
pactl("set-default-sink", NULL)
loop_up()   # fail-open: audio flows immediately


def start_parec():
    state["parec"] = sp.Popen(
        [PAREC, "-d", "%s.monitor" % NULL, "--format=s16le",
         "--rate=%d" % RATE, "--channels=1", "--latency-msec=50"],
        stdout=sp.PIPE, stderr=sp.DEVNULL)


start_parec()
last_signal = time.monotonic()
while True:
    buf = state["parec"].stdout.read(CHUNK)
    if not buf:
        try:
            state["parec"].kill()
        except Exception:
            pass
        time.sleep(0.2)
        start_parec()
        continue
    samples = array.array("h")
    samples.frombytes(buf[:len(buf) // 2 * 2])
    peak = 0
    for s in samples:
        v = -s if s < 0 else s
        if v > peak:
            peak = v
    now = time.monotonic()
    if peak > THRESH:
        last_signal = now
        loop_up()
    elif now - last_signal > GRACE:
        loop_down()

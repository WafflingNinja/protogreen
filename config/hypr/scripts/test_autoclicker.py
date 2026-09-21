#!/usr/bin/env python3
"""Checks the popup's settings -> engine-args mapping, plus engine start/stop
and click rate. Run: python3 test_autoclicker.py

Injection itself is checked separately by: autoclicker.py --selftest
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PyQt6.QtWidgets import QApplication  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("acg", os.path.join(HERE, "autoclicker_gui.py"))
acg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acg)
acg.CONFIG = os.path.join(tempfile.mkdtemp(), "autoclicker.json")  # never touch the real one

app = QApplication(sys.argv)
g = acg.Gui()

# interval maths: 1h 2m 3s 4ms
g.hours.setText("1"); g.minutes.setText("2"); g.seconds.setText("3"); g.millis.setText("4")
assert g.interval_ms() == 3_600_000 + 120_000 + 3_000 + 4, g.interval_ms()

g.button.setCurrentText("e")
g.clicktype.setCurrentText("Double")
g.repeat.setChecked(True); g.repeat_n.setText("25")
g.custom_pos.setChecked(True); g.x.setText("800"); g.y.setText("450")
g.rand.setChecked(True); g.rand_ms.setText("30")
g.hold.setChecked(True); g.hold_ms.setText("40")
assert g.settings() == {"key": "e", "interval_ms": 3_723_004, "double": True, "repeat": 25,
                        "pos": "800,450", "jitter": 0.03, "hold_ms": 40}, g.settings()

# unchecked boxes must not leak into the args
g.repeat.setChecked(False); g.custom_pos.setChecked(False); g.rand.setChecked(False); g.hold.setChecked(False)
g.clicktype.setCurrentText("Single")
assert set(g.settings()) == {"key", "interval_ms"}, g.settings()

# round-trip through the file the engine reads with --config
g.clicktype.setCurrentText("Double")
g.repeat.setChecked(True); g.custom_pos.setChecked(True); g.rand.setChecked(True); g.hold.setChecked(True)
g.write_config()
assert acg.Gui().settings() == json.load(open(acg.CONFIG))

# empty form must not divide by zero in the engine
g3 = acg.Gui()
for f in (g3.hours, g3.minutes, g3.seconds, g3.millis):
    f.setText("")
assert g3.interval_ms() == 100

print("ok: interval maths, option gating, config round-trip, empty-form fallback")

# ── engine: click rate must hold up at small intervals ──
ENGINE = os.path.join(HERE, "autoclicker.py")


def timed(*args):
    t0 = time.monotonic()
    subprocess.run([sys.executable, ENGINE, "--key", "f13", *args], capture_output=True, check=True)
    return time.monotonic() - t0


# A single-click run measures everything that isn't the loop — interpreter start,
# the evdev import, the libinput settle, the release drain — so the rate check
# below stays honest when any of those shift.
STARTUP = min(timed("--repeat", "1", "--interval-ms", "1") for _ in range(2))

for interval_ms, clicks in ((1, 1000), (5, 200)):
    want = interval_ms * clicks / 1000
    took = timed("--repeat", str(clicks), "--interval-ms", str(interval_ms)) - STARTUP
    assert took <= want * 1.1, f"{clicks} clicks at {interval_ms}ms wanted {want:.2f}s, took {took:.2f}s"
    print(f"ok: {clicks} clicks at {interval_ms}ms in {took:.2f}s (target {want:.2f}s)")

# ── engine: --start must be idempotent, or self-clicks toggle the run off ──


def engines():
    live = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            argv = open(f"/proc/{pid}/cmdline").read().split("\0")
        except OSError:
            continue
        # basename, not endswith: this test file endswith "autoclicker.py" too
        if len(argv) > 1 and "python" in argv[0] and os.path.basename(argv[1]) == "autoclicker.py":
            live.append(pid)
    return live


def settled(timeout=3.0):
    """engines() once the previous run has actually left /proc."""
    end = time.monotonic() + timeout
    while engines() and time.monotonic() < end:
        time.sleep(0.05)
    return engines()


def spawn(*args):
    subprocess.Popen([sys.executable, ENGINE, "--key", "f13", "--interval-ms", "50", *args],
                     start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.2)


assert settled() == [], f"stale engines before test: {engines()}"
spawn("--start")
assert len(engines()) == 1, engines()
spawn("--start")  # what a self-click on the Start button does
assert len(engines()) == 1, f"--start toggled the run instead of no-op: {engines()}"
subprocess.run([sys.executable, ENGINE, "--stop"], check=True)
assert settled() == [], f"--stop left something running: {engines()}"
print("ok: --start idempotent under self-clicks, --stop kills it")

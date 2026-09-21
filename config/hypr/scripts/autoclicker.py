#!/usr/bin/env python3
"""Wayland-safe autoclicker: injects key/button events through /dev/uinput.

Works under Hyprland (and any compositor) because events enter at the kernel
level, below the compositor — same path a real mouse takes. Input lands in the
focused window, on any workspace, fullscreen games included.

Running it a second time toggles the running instance off (pidfile).

  autoclicker.py                     # left click, 15 cps
  autoclicker.py --key right --cps 8
  autoclicker.py --key e --cps 20 --jitter 0.15
  autoclicker.py --selftest          # verify uinput works (uses F13, harmless)
"""

import argparse
import errno
import json
import os
import random
import signal
import socket
import sys
import time

from evdev import UInput, ecodes

PIDFILE = f"/run/user/{os.getuid()}/autoclicker.pid"
CONFIG = os.path.expanduser("~/.config/autoclicker.json")

ALIASES = {
    "LEFT": "BTN_LEFT",
    "RIGHT": "BTN_RIGHT",
    "MIDDLE": "BTN_MIDDLE",
    "MOUSE4": "BTN_SIDE",
    "MOUSE5": "BTN_EXTRA",
}


def resolve(name):
    """'left' -> BTN_LEFT, 'e' -> KEY_E, 'KEY_F13' -> KEY_F13."""
    n = name.upper()
    n = ALIASES.get(n, n)
    if not n.startswith(("KEY_", "BTN_")):
        n = "KEY_" + n
    code = ecodes.ecodes.get(n)
    if code is None:
        sys.exit(f"unknown key: {name} (try left, right, middle, mouse4, e, space, f5)")
    return n, code


def make_device(code):
    # Advertise ONLY the code being injected. Carrying every keycode made udev
    # tag this a full keyboard, and keyd (/etc/keyd/default.conf matches `*`)
    # then grabbed it exclusively: clicks detoured through keyd's remapper, and
    # closing the device mid-stream left keyd's own virtual pointer holding the
    # button down — dead clicks and dead keybinds until keyd itself restarts.
    caps = {
        ecodes.EV_KEY: [code],
        ecodes.EV_REL: [ecodes.REL_X, ecodes.REL_Y, ecodes.REL_WHEEL],
    }
    if code < ecodes.BTN_MISC:
        # A real key, not a mouse button: udev only tags ID_INPUT_KEYBOARD when
        # the whole KEY_ESC..KEY_D block is present, and libinput drops key
        # events from a device that isn't tagged one. keyd grabs this shape too
        # — unavoidable, it's the same shape as any keyboard.
        caps[ecodes.EV_KEY] = sorted({*range(ecodes.KEY_ESC, ecodes.KEY_D + 1), code})
    try:
        return UInput(caps, name="autoclicker-virtual", version=1)
    except PermissionError:
        sys.exit("no write access to /dev/uinput — need to be in the 'input' group")
    except FileNotFoundError:
        sys.exit("/dev/uinput missing — run: sudo modprobe uinput")


def running_pid():
    """PID of the live instance, or None."""
    try:
        with open(PIDFILE) as f:
            pid = int(f.read())
        os.kill(pid, 0)
        return pid
    except (FileNotFoundError, ValueError, ProcessLookupError):
        return None


def stop_running():
    """Kill a running instance. Returns True if one was killed."""
    try:
        with open(PIDFILE) as f:
            pid = int(f.read())
    except (FileNotFoundError, ValueError):
        return False
    try:
        os.kill(pid, signal.SIGTERM)
        return True
    except OSError as e:
        if e.errno == errno.ESRCH:  # stale pidfile
            os.unlink(PIDFILE)
            return False
        raise


def hypr(cmd):
    """One-shot command over the Hyprland IPC socket (cheaper than hyprctl)."""
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not his:
        return
    path = f"/run/user/{os.getuid()}/hypr/{his}/.socket.sock"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(path)
            s.sendall(cmd.encode())
            s.recv(64)
    except OSError:
        pass


def click_loop(ui, code, interval, hold, jitter, double, repeat, pos):
    hold = min(hold, interval * 0.4)  # press must finish before the next one starts
    n = 0
    # Absolute deadlines, not sleep(gap): per-click overhead (~0.3ms) would
    # otherwise accumulate and the real rate drifts below the requested one.
    due = time.perf_counter()
    while True:
        if pos:
            hypr(f"dispatch movecursor {pos[0]} {pos[1]}")
        for _ in range(2 if double else 1):
            ui.write(ecodes.EV_KEY, code, 1)
            ui.syn()
            time.sleep(hold)
            ui.write(ecodes.EV_KEY, code, 0)
            ui.syn()
            if double:
                time.sleep(0.04)  # inside the double-click threshold
        n += 1
        if repeat and n >= repeat:
            return
        due += interval + (random.uniform(-jitter, jitter) if jitter else 0.0)
        left = due - time.perf_counter()
        if left > 0:
            time.sleep(left)
        else:
            due = time.perf_counter()  # fell behind; resync instead of sprinting


def selftest():
    """Verify injection actually reaches the compositor.

    Clicks can't be checked without stealing input from a real window, so this
    injects cursor movement instead (same write path) and asks Hyprland where
    the cursor ended up.
    """
    import subprocess

    assert resolve("left") == ("BTN_LEFT", ecodes.BTN_LEFT)
    assert resolve("e") == ("KEY_E", ecodes.KEY_E)
    assert resolve("KEY_F13") == ("KEY_F13", ecodes.KEY_F13)

    def cursorpos():
        out = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout
        return [int(v) for v in out.strip().split(",")]

    started = time.strftime("%Y-%m-%d %H:%M:%S")  # journalctl window for the keyd check below
    ui = make_device(ecodes.BTN_LEFT)
    time.sleep(0.5)  # libinput needs to bind the device before events count
    start = cursorpos()
    subprocess.run(["hyprctl", "dispatch", "movecursor", "200", "200"], capture_output=True)
    time.sleep(0.2)
    before = cursorpos()

    steps, px, cps = 20, 5, 20.0
    t0 = time.monotonic()
    for _ in range(steps):
        ui.write(ecodes.EV_REL, ecodes.REL_X, px)
        ui.syn()
        time.sleep(1.0 / cps)
    elapsed = time.monotonic() - t0
    time.sleep(0.3)
    after = cursorpos()

    subprocess.run(["hyprctl", "dispatch", "movecursor", str(start[0]), str(start[1])], capture_output=True)
    ui.close()

    moved = after[0] - before[0]
    # ponytail: loose bound on purpose — libinput pointer accel means injected
    # units never map 1:1 to screen px. This only proves the events landed.
    assert steps * px * 0.5 <= moved <= steps * px * 2, f"injected {steps * px}px, cursor moved {moved}px"
    assert 0.8 <= elapsed <= 1.6, f"{steps} events at {cps}/s took {elapsed:.2f}s"

    # keyd holds an exclusive grab on everything it matches. If it ever matches
    # this device again, a mid-stream close strands the button down in keyd's
    # virtual pointer and the whole desktop stops taking input.
    if subprocess.run(["systemctl", "is-active", "--quiet", "keyd"]).returncode == 0:
        log = subprocess.run(["journalctl", "-u", "keyd", "--since", started, "-o", "cat"],
                             capture_output=True, text=True).stdout
        grabbed = [l for l in log.splitlines() if "autoclicker-virtual" in l and "match" in l]
        assert not grabbed, f"keyd grabbed the virtual device: {grabbed}"
        print("ok: keyd left the virtual device alone")

    print(f"ok: {steps} events reached the compositor ({moved}px in {elapsed:.2f}s)")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--key", default="left", help="left/right/middle/mouse4/mouse5 or any key: e, space, f5")
    p.add_argument("--cps", type=float, default=15.0, help="clicks per second (default 15)")
    p.add_argument("--jitter", type=float, default=0.0, help="randomize gap by +/- this many seconds")
    p.add_argument("--interval-ms", type=float, help="gap between clicks in ms (overrides --cps)")
    p.add_argument("--hold-ms", type=float, help="how long the button stays down (default 12ms)")
    p.add_argument("--double", action="store_true", help="double click instead of single")
    p.add_argument("--repeat", type=int, default=0, help="stop after N clicks (0 = forever)")
    p.add_argument("--pos", help="click at a fixed X,Y instead of wherever the cursor is")
    p.add_argument("--config", action="store_true", help="load settings from ~/.config/autoclicker.json")
    p.add_argument("--start", action="store_true", help="start only; do nothing if already running")
    p.add_argument("--stop", action="store_true", help="stop a running instance")
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()

    if a.selftest:
        selftest()
        return
    if a.stop:
        stop_running()
        return
    if a.start:
        # Idempotent on purpose: the clicker flooding its own Start button must
        # not toggle the run off and on again.
        if running_pid():
            return
    elif stop_running():  # no flag = toggle, for the F8 / HUD binds
        return
    if a.config:
        try:
            with open(CONFIG) as f:
                for k, v in json.load(f).items():
                    setattr(a, k, v)
        except (FileNotFoundError, json.JSONDecodeError):
            pass  # no saved settings yet -> defaults

    interval = a.interval_ms / 1000.0 if a.interval_ms else 1.0 / a.cps
    if interval <= 0:
        sys.exit("interval must be > 0")
    hold = a.hold_ms / 1000.0 if a.hold_ms else 0.012
    pos = [int(v) for v in a.pos.replace(",", " ").split()] if a.pos else None

    name, code = resolve(a.key)
    ui = make_device(code)
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))

    stopped = False

    def stop(*_):
        # Signal handler and the finally block can both land here; releasing a
        # closed device throws.
        nonlocal stopped
        if stopped:
            sys.exit(0)
        stopped = True
        # Release first — dying mid-press would leave the button stuck down.
        ui.write(ecodes.EV_KEY, code, 0)
        ui.syn()
        time.sleep(0.05)  # readers must drain the release before the device vanishes
        ui.close()
        try:
            os.unlink(PIDFILE)
        except FileNotFoundError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    time.sleep(0.3)  # libinput needs a moment to bind the new device
    print(f"autoclicker: {name} every {interval * 1000:.0f}ms", flush=True)
    try:
        click_loop(ui, code, interval, hold, a.jitter, a.double, a.repeat, pos)
    finally:
        stop()


if __name__ == "__main__":
    main()

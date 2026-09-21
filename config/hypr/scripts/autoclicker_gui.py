#!/usr/bin/env python3
"""Settings popup for autoclicker.py — XClicker's layout, PROTO//GREEN paint.

The window only builds the argument list and starts/stops the engine; all the
actual clicking lives in autoclicker.py so the hotkey works without this open.
"""

import json
import os
import signal
import subprocess
import sys

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QIntValidator
from PyQt6.QtWidgets import (
    QApplication, QCheckBox, QComboBox, QGridLayout, QGroupBox, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QVBoxLayout, QWidget,
)

ENGINE = os.path.expanduser("~/.config/hypr/scripts/autoclicker.py")
CONFIG = os.path.expanduser("~/.config/autoclicker.json")
PIDFILE = f"/run/user/{os.getuid()}/autoclicker.pid"

BG, SURFACE, SURFACE2 = "#0a0f0c", "#13201a", "#1a2420"
GREEN, GREEN2, BRIGHT = "#39ff6a", "#1fae52", "#90ffa8"
FG, MUTED = "#d4f5df", "#4f8f68"

QSS = f"""
QWidget {{ background: {BG}; color: {FG}; font-family: "JetBrainsMono Nerd Font"; font-size: 12px; }}
QGroupBox {{ border: 1px solid {GREEN2}; border-radius: 10px; margin-top: 10px; padding: 12px 10px 10px 10px; }}
QGroupBox::title {{ subcontrol-origin: margin; left: 12px; padding: 0 4px; color: {BRIGHT}; }}
QLineEdit {{ background: #000; border: 1px solid {GREEN2}; border-radius: 6px; padding: 6px; color: {GREEN};
             selection-background-color: {GREEN2}; }}
QLineEdit:focus {{ border: 1px solid {GREEN}; }}
QLineEdit:disabled {{ color: {MUTED}; border-color: #24382c; }}
QComboBox {{ background: {SURFACE2}; border: 1px solid {GREEN2}; border-radius: 6px; padding: 5px 8px; color: {FG}; }}
/* no ::drop-down override — QSS can't draw a triangle, and Fusion's own arrow looks right */
QComboBox QAbstractItemView {{ background: {SURFACE}; border: 1px solid {GREEN2}; color: {FG};
                               selection-background-color: {GREEN2}; }}
QCheckBox::indicator {{ width: 14px; height: 14px; border: 1px solid {GREEN2}; border-radius: 3px; background: #000; }}
QCheckBox::indicator:checked {{ background: {GREEN}; }}
QPushButton {{ background: {SURFACE2}; border: 1px solid {GREEN2}; border-radius: 8px; padding: 10px 16px; color: {FG}; }}
QPushButton:hover {{ border-color: {GREEN}; color: {BRIGHT}; }}
QPushButton:pressed {{ background: {GREEN2}; }}
QPushButton:disabled {{ color: {MUTED}; border-color: #24382c; }}
QLabel#status {{ color: {MUTED}; }}
"""

BUTTONS = ["Left", "Right", "Middle", "Mouse4", "Mouse5"]


def num(width=64, placeholder=""):
    e = QLineEdit()
    e.setValidator(QIntValidator(0, 10_000_000))
    e.setFixedWidth(width)
    e.setPlaceholderText(placeholder)
    e.setAlignment(Qt.AlignmentFlag.AlignCenter)
    return e


class Gui(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("autoclicker")
        self.setStyleSheet(QSS)
        root = QVBoxLayout(self)
        root.setSpacing(10)

        # ── click interval ──
        box = QGroupBox("Click Interval")
        grid = QGridLayout(box)
        self.hours, self.minutes, self.seconds, self.millis = num(), num(), num(), num()
        for col, (field, name) in enumerate(
            [(self.hours, "Hours"), (self.minutes, "Minutes"), (self.seconds, "Seconds"), (self.millis, "Milliseconds")]
        ):
            grid.addWidget(field, 0, col)
            lbl = QLabel(name)
            lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            grid.addWidget(lbl, 1, col)
        root.addWidget(box)

        cols = QHBoxLayout()

        # ── options ──
        opts = QGroupBox("Options")
        og = QGridLayout(opts)
        self.button = QComboBox()
        self.button.setEditable(True)  # type any key name here: e, space, f5, ...
        self.button.addItems(BUTTONS)
        self.clicktype = QComboBox()
        self.clicktype.addItems(["Single", "Double"])
        self.hotkey = QLabel("F8 / SUPER+ALT+C")
        self.repeat = QCheckBox("Repeat")
        self.repeat_n = num(90, "# of times")
        og.addWidget(QLabel("Mouse Button"), 0, 0)
        og.addWidget(self.button, 0, 1)
        og.addWidget(QLabel("Click Type"), 1, 0)
        og.addWidget(self.clicktype, 1, 1)
        og.addWidget(QLabel("Hotkey"), 2, 0)
        og.addWidget(self.hotkey, 2, 1)
        og.addWidget(self.repeat, 3, 0)
        og.addWidget(self.repeat_n, 3, 1)
        cols.addWidget(opts)

        # ── more options ──
        more = QGroupBox("More Options")
        mg = QGridLayout(more)
        self.custom_pos = QCheckBox("Custom Location")
        self.x, self.y = num(70, "X"), num(70, "Y")
        self.get = QPushButton("Get")
        self.rand = QCheckBox("Random Interval")
        self.rand_ms = num(70, "+/- ms")
        self.hold = QCheckBox("Hold Time")
        self.hold_ms = num(70, "ms")
        mg.addWidget(self.custom_pos, 0, 0, 1, 3)
        mg.addWidget(self.x, 1, 0)
        mg.addWidget(self.y, 1, 1)
        mg.addWidget(self.get, 1, 2)
        mg.addWidget(self.rand, 2, 0, 1, 2)
        mg.addWidget(self.rand_ms, 2, 2)
        mg.addWidget(self.hold, 3, 0, 1, 2)
        mg.addWidget(self.hold_ms, 3, 2)
        cols.addWidget(more)
        root.addLayout(cols)

        # ── actions ──
        row = QHBoxLayout()
        self.start = QPushButton("Start (F8)")
        self.stop = QPushButton("Stop (F8)")
        self.save = QPushButton("Save")
        for b in (self.start, self.stop, self.save):
            row.addWidget(b)
        root.addLayout(row)

        self.status = QLabel("idle")
        self.status.setObjectName("status")
        self.status.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(self.status)

        self.get.clicked.connect(self.grab_cursor)
        self.start.clicked.connect(self.do_start)
        self.stop.clicked.connect(self.do_stop)
        self.save.clicked.connect(lambda: (self.write_config(), self.status.setText("saved")))
        for cb, fields in ((self.custom_pos, (self.x, self.y, self.get)), (self.rand, (self.rand_ms,)),
                           (self.hold, (self.hold_ms,)), (self.repeat, (self.repeat_n,))):
            cb.toggled.connect(lambda on, f=fields: [w.setEnabled(on) for w in f])
            for w in fields:
                w.setEnabled(False)

        self.load_config()
        self.poll()
        t = QTimer(self)
        t.timeout.connect(self.poll)
        t.start(500)

    # ── engine state ──
    def running_pid(self):
        try:
            with open(PIDFILE) as f:
                pid = int(f.read())
            os.kill(pid, 0)
            return pid
        except (FileNotFoundError, ValueError, ProcessLookupError):
            return None

    def poll(self):
        on = self.running_pid() is not None
        self.start.setEnabled(not on)
        self.stop.setEnabled(on)
        if self.status.text() != "saved" or on:
            self.status.setText("clicking" if on else "idle")

    def interval_ms(self):
        def v(field):
            return int(field.text() or 0)
        ms = v(self.millis) + v(self.seconds) * 1000 + v(self.minutes) * 60_000 + v(self.hours) * 3_600_000
        return ms or 100

    def settings(self):
        s = {"key": self.button.currentText().strip() or "left", "interval_ms": self.interval_ms()}
        if self.clicktype.currentText() == "Double":
            s["double"] = True
        if self.repeat.isChecked() and self.repeat_n.text():
            s["repeat"] = int(self.repeat_n.text())
        if self.custom_pos.isChecked() and self.x.text() and self.y.text():
            s["pos"] = f"{self.x.text()},{self.y.text()}"
        if self.rand.isChecked() and self.rand_ms.text():
            s["jitter"] = int(self.rand_ms.text()) / 1000.0
        if self.hold.isChecked() and self.hold_ms.text():
            s["hold_ms"] = int(self.hold_ms.text())
        return s

    def write_config(self):
        with open(CONFIG, "w") as f:
            json.dump(self.settings(), f, indent=2)

    def load_config(self):
        try:
            with open(CONFIG) as f:
                s = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            self.millis.setText("100")
            return
        self.button.setCurrentText(s.get("key", "left"))
        ms = int(s.get("interval_ms", 100))
        self.hours.setText(str(ms // 3_600_000) if ms >= 3_600_000 else "")
        self.minutes.setText(str(ms // 60_000 % 60) if ms >= 60_000 else "")
        self.seconds.setText(str(ms // 1000 % 60) if ms >= 1000 else "")
        self.millis.setText(str(ms % 1000))
        self.clicktype.setCurrentText("Double" if s.get("double") else "Single")
        for key, cb, field, scale in (("repeat", self.repeat, self.repeat_n, 1),
                                      ("jitter", self.rand, self.rand_ms, 1000),
                                      ("hold_ms", self.hold, self.hold_ms, 1)):
            if s.get(key):
                cb.setChecked(True)
                field.setText(str(int(s[key] * scale)))
        if s.get("pos"):
            self.custom_pos.setChecked(True)
            x, y = s["pos"].split(",")
            self.x.setText(x)
            self.y.setText(y)

    # ── actions ──
    def grab_cursor(self):
        out = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout
        try:
            x, y = [v.strip() for v in out.split(",")]
        except ValueError:
            self.status.setText("cursorpos failed")
            return
        self.x.setText(x)
        self.y.setText(y)

    def do_start(self):
        self.write_config()
        # --start, not the toggle: the clicker ends up clicking this very button
        # (the cursor is sitting on it), and a toggle would flip itself off.
        # Disabling now rather than on the next poll closes the same race.
        self.start.setEnabled(False)
        subprocess.Popen([sys.executable, ENGINE, "--config", "--start"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.status.setText("clicking")

    def do_stop(self):
        pid = self.running_pid()
        if pid:
            os.kill(pid, signal.SIGTERM)
        self.status.setText("idle")


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")  # native style draws combo arrows as blobs under this QSS
    app.setApplicationName("autoclicker")  # matches the hyprland float windowrule
    app.setDesktopFileName("autoclicker")
    g = Gui()
    g.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

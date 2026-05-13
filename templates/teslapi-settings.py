#!/usr/bin/env python3
"""maziX TeslaPI Settings — unified control panel.

Replaces the two earlier standalone GUIs (btaudio.py and tesla-display-gui.py)
with a single tabbed window:
    - Bluetooth: scan/pair/trust/connect a BT device, set as default audio sink
    - Display:   pick KasmVNC vs hwaccel backend, change boot default
    - About:     project info + GitHub link

Design notes:
- ttk.Notebook for tabs (native look)
- ttk theme 'clam' for a more modern feel than the platform default
- Subprocesses to system tools are wrapped through systemd-run --user --scope
  (display switcher specifically) so a backend switch that kills KasmVNC
  doesn't drag the GUI's helper down with its cgroup — see the
  /tmp/tesla-display.log diagnostic story in CHANGELOG.
"""
import os
import re
import subprocess
import threading
import time
import tkinter as tk
import webbrowser
from tkinter import font as tkfont
from tkinter import messagebox, ttk

# --------------------------------------------------------------------------
# Project metadata
# --------------------------------------------------------------------------

PROJECT_NAME = "maziX TeslaPI"
PROJECT_TAGLINE = "Turn a Raspberry Pi 5 into a Tesla-friendly connectivity + media station"
PROJECT_VERSION = "v1.0"
PROJECT_GITHUB = "https://github.com/mazix/mazix-teslapi"
PROJECT_ISSUES = "https://github.com/mazix/mazix-teslapi/issues"
PROJECT_LICENSE = "MIT"

# --------------------------------------------------------------------------
# Theme
# --------------------------------------------------------------------------

COLOR_BG = "#1c2230"
COLOR_FG = "#e8ecf1"
COLOR_MUTED = "#8a93a4"
COLOR_ACCENT = "#3aa56a"
COLOR_DANGER = "#e74c3c"
COLOR_WARN = "#f1c40f"
COLOR_CARD = "#262d3e"


def apply_theme(root):
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass

    root.configure(bg=COLOR_BG)
    style.configure(".", background=COLOR_BG, foreground=COLOR_FG)
    style.configure("TFrame", background=COLOR_BG)
    style.configure("TLabel", background=COLOR_BG, foreground=COLOR_FG)
    style.configure("Card.TFrame", background=COLOR_CARD)
    style.configure("Card.TLabel", background=COLOR_CARD, foreground=COLOR_FG)
    style.configure("Muted.TLabel", background=COLOR_BG, foreground=COLOR_MUTED)
    style.configure("Heading.TLabel", background=COLOR_BG, foreground=COLOR_FG,
                    font=("DejaVu Sans", 11, "bold"))
    style.configure("TButton", padding=(10, 6))
    style.configure("Accent.TButton", padding=(10, 6))
    style.map("Accent.TButton",
              background=[("active", COLOR_ACCENT), ("!disabled", COLOR_ACCENT)],
              foreground=[("!disabled", "white")])
    style.configure("TNotebook", background=COLOR_BG, borderwidth=0)
    style.configure("TNotebook.Tab", background=COLOR_BG, foreground=COLOR_MUTED,
                    padding=(16, 8), borderwidth=0)
    style.map("TNotebook.Tab",
              background=[("selected", COLOR_CARD)],
              foreground=[("selected", COLOR_FG)])
    style.configure("Treeview", background=COLOR_CARD, foreground=COLOR_FG,
                    fieldbackground=COLOR_CARD, borderwidth=0)
    style.configure("Treeview.Heading", background=COLOR_BG, foreground=COLOR_FG,
                    font=("DejaVu Sans", 9, "bold"))
    style.map("Treeview", background=[("selected", COLOR_ACCENT)],
              foreground=[("selected", "white")])
    style.configure("TRadiobutton", background=COLOR_BG, foreground=COLOR_FG)
    style.configure("Card.TRadiobutton", background=COLOR_CARD, foreground=COLOR_FG)
    style.configure("TSeparator", background=COLOR_MUTED)


# --------------------------------------------------------------------------
# Bluetooth tab
# --------------------------------------------------------------------------

class BluetoothTab(ttk.Frame):
    """Wraps bluetoothctl + pactl for scan/pair/trust/connect/set-default-sink."""

    def __init__(self, parent):
        super().__init__(parent, padding=14)
        self.scanning = False

        top = ttk.Frame(self)
        top.pack(fill="x", pady=(0, 8))
        self.scan_btn = ttk.Button(top, text="Start Scan", command=self.toggle_scan)
        self.scan_btn.pack(side="left")
        ttk.Button(top, text="Refresh", command=self.refresh).pack(side="left", padx=6)
        self.status_var = tk.StringVar(value="Ready")
        ttk.Label(top, textvariable=self.status_var, style="Muted.TLabel").pack(side="left", padx=10)

        cols = ("mac", "name", "paired", "trusted", "connected")
        widths = (170, 280, 70, 70, 90)
        self.tv = ttk.Treeview(self, columns=cols, show="headings", height=10)
        for c, w in zip(cols, widths):
            self.tv.heading(c, text=c.title())
            self.tv.column(c, width=w, anchor="w")
        self.tv.pack(fill="both", expand=True, pady=4)

        actions = ttk.Frame(self)
        actions.pack(fill="x", pady=(8, 4))
        for label, fn in [
                ("Pair", self.pair),
                ("Trust", self.trust),
                ("Connect", self.connect),
                ("Disconnect", self.disconnect),
                ("Remove", self.remove)]:
            ttk.Button(actions, text=label, command=fn).pack(side="left", padx=2)
        ttk.Button(actions, text="Set as Audio Out",
                   command=self.set_sink,
                   style="Accent.TButton").pack(side="right", padx=2)

        self.sink_var = tk.StringVar(value="Default sink: ?")
        ttk.Label(self, textvariable=self.sink_var,
                  style="Muted.TLabel").pack(anchor="w", pady=(8, 0))

        self.refresh()

    def bt(self, *args, timeout=15):
        try:
            r = subprocess.run(["bluetoothctl", *args],
                               capture_output=True, text=True, timeout=timeout)
            return r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            return "TIMEOUT"

    def refresh(self):
        for i in self.tv.get_children():
            self.tv.delete(i)
        out = self.bt("devices")
        for line in out.splitlines():
            m = re.match(r"Device\s+(\S+)\s+(.+)", line.strip())
            if not m:
                continue
            mac, name = m.group(1), m.group(2)
            info = self.bt("info", mac)
            self.tv.insert("", tk.END, values=(
                mac, name,
                "yes" if "Paired: yes" in info else "no",
                "yes" if "Trusted: yes" in info else "no",
                "yes" if "Connected: yes" in info else "no",
            ))
        try:
            r = subprocess.run(["pactl", "get-default-sink"],
                               capture_output=True, text=True)
            self.sink_var.set(f"Default sink: {r.stdout.strip() or '?'}")
        except Exception:
            pass

    def toggle_scan(self):
        if not self.scanning:
            self.scanning = True
            self.scan_btn.config(text="Stop Scan")
            self.status_var.set("Scanning…")
            threading.Thread(target=self._scan, daemon=True).start()
        else:
            self.scanning = False
            self.scan_btn.config(text="Start Scan")
            self.status_var.set("Stopped")

    def _scan(self):
        p = subprocess.Popen(["bluetoothctl"], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             text=True)
        try:
            p.stdin.write("power on\nagent on\ndefault-agent\nscan on\n")
            p.stdin.flush()
            while self.scanning:
                time.sleep(3)
                self.after(0, self.refresh)
        finally:
            try:
                p.stdin.write("scan off\nexit\n")
                p.stdin.flush()
            except Exception:
                pass
            p.wait(timeout=5)

    def sel_mac(self):
        s = self.tv.selection()
        if not s:
            messagebox.showwarning("Select", "Pick a device first.")
            return None
        return self.tv.item(s[0])["values"][0]

    def _do(self, label, cmd, *args):
        mac = self.sel_mac()
        if not mac:
            return
        self.status_var.set(f"{label} {mac}…")
        out = self.bt(cmd, mac, *args, timeout=30)
        self.status_var.set(out.strip().splitlines()[-1] if out.strip() else label)
        self.refresh()

    def pair(self):       self._do("Pair", "pair")
    def trust(self):      self._do("Trust", "trust")
    def connect(self):    self._do("Connect", "connect")
    def disconnect(self): self._do("Disconnect", "disconnect")
    def remove(self):
        mac = self.sel_mac()
        if mac and messagebox.askyesno("Remove", f"Remove {mac}?"):
            self.bt("remove", mac)
            self.refresh()

    def set_sink(self):
        try:
            r = subprocess.run(["pactl", "list", "short", "sinks"],
                               capture_output=True, text=True)
            for line in r.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2 and "bluez_output" in parts[1]:
                    subprocess.run(["pactl", "set-default-sink", parts[1]])
                    self.status_var.set(f"Default sink: {parts[1]}")
                    self.refresh()
                    return
            messagebox.showinfo("No BT sink",
                                "Connect to a Bluetooth device first.")
        except Exception as e:
            messagebox.showerror("Error", str(e))


# --------------------------------------------------------------------------
# Display tab
# --------------------------------------------------------------------------

ACTIVE_FILE = "/etc/tesla-display/active"
_RUN_LOG = "/tmp/teslapi-settings-run.log"
BACKENDS = (("kasmvnc", "KasmVNC (video-optimized, software render)"),
            ("hwaccel", "Hwaccel (V3D-accelerated :0, IDE/dev work)"))


def _read_active():
    try:
        with open(ACTIVE_FILE) as f:
            v = f.read().strip()
            if v in ("kasmvnc", "hwaccel"):
                return v
    except OSError:
        pass
    return "kasmvnc"


def _run_switcher(*args, timeout=20):
    try:
        open(_RUN_LOG, "w").close()
        with open(_RUN_LOG, "wb") as out:
            r = subprocess.run(
                ["systemd-run", "--user", "--scope", "--quiet", "--collect",
                 "--", "sudo", "-n", "/usr/local/bin/tesla-display", *args],
                stdin=subprocess.DEVNULL,
                stdout=out, stderr=subprocess.STDOUT,
                timeout=timeout, start_new_session=True)
        try:
            with open(_RUN_LOG) as f:
                output = f.read()
        except OSError:
            output = ""
        return (r.returncode == 0, output)
    except subprocess.TimeoutExpired:
        return (False, "Timeout — tesla-display didn't return in time.")
    except FileNotFoundError as e:
        return (False, f"Couldn't run tesla-display: {e}")


class DisplayTab(ttk.Frame):
    """Wraps tesla-display switch/status."""

    def __init__(self, parent):
        super().__init__(parent, padding=14)

        self.active_var = tk.StringVar(value=_read_active())
        self.default_var = tk.StringVar(value=_read_active())

        ttk.Label(self, text="Active backend (right now):",
                  style="Heading.TLabel").pack(anchor="w", pady=(0, 4))
        active_card = ttk.Frame(self, style="Card.TFrame", padding=10)
        active_card.pack(fill="x", pady=(0, 10))
        for value, label in BACKENDS:
            ttk.Radiobutton(active_card, text=label, variable=self.active_var,
                            value=value, style="Card.TRadiobutton").pack(anchor="w")

        ttk.Label(self, text="Boot default (after reboot):",
                  style="Heading.TLabel").pack(anchor="w", pady=(0, 4))
        default_card = ttk.Frame(self, style="Card.TFrame", padding=10)
        default_card.pack(fill="x", pady=(0, 10))
        for value, label in BACKENDS:
            ttk.Radiobutton(default_card, text=label.split(" (")[0],
                            variable=self.default_var, value=value,
                            style="Card.TRadiobutton").pack(anchor="w")

        btns = ttk.Frame(self)
        btns.pack(fill="x", pady=(2, 10))
        ttk.Button(btns, text="Apply switch now",
                   command=self.apply_switch,
                   style="Accent.TButton").pack(side="left", padx=2)
        ttk.Button(btns, text="Save boot default",
                   command=self.save_default).pack(side="left", padx=2)
        ttk.Button(btns, text="Refresh",
                   command=self.refresh).pack(side="left", padx=2)

        self.status = tk.Text(self, height=8, wrap="none",
                              font=("DejaVu Sans Mono", 9),
                              bg=COLOR_CARD, fg=COLOR_FG, insertbackground=COLOR_FG,
                              relief="flat", borderwidth=0)
        self.status.pack(fill="both", expand=True)
        self.status.config(state="disabled")

        self.refresh()

    def _show_status(self, text):
        self.status.config(state="normal")
        self.status.delete("1.0", tk.END)
        self.status.insert(tk.END, text)
        self.status.config(state="disabled")

    def refresh(self):
        active = _read_active()
        self.active_var.set(active)
        self.default_var.set(active)
        ok, out = _run_switcher("status")
        if not ok:
            out = ("Couldn't fetch status. From a terminal, try:\n"
                   "  sudo /usr/local/bin/tesla-display status\n\n" + out)
        self._show_status(out)

    def apply_switch(self):
        target = self.active_var.get()
        ok, out = _run_switcher("switch", target)
        if ok:
            messagebox.showinfo("Switched",
                                f"Now active: {target}\n\n{out.strip()[-400:]}")
        else:
            messagebox.showerror("Switch failed", out[-800:])
        self.refresh()

    def save_default(self):
        target = self.default_var.get()
        ok, out = _run_switcher("set-default", target)
        if ok:
            messagebox.showinfo("Boot default",
                                f"On next boot: {target}\n\n{out.strip()}")
        else:
            messagebox.showerror("Save failed", out[-800:])
        self.refresh()


# --------------------------------------------------------------------------
# About tab
# --------------------------------------------------------------------------

class AboutTab(ttk.Frame):
    def __init__(self, parent):
        super().__init__(parent, padding=20)

        title_font = tkfont.Font(family="DejaVu Sans", size=20, weight="bold")
        sub_font = tkfont.Font(family="DejaVu Sans", size=10)

        ttk.Label(self, text=PROJECT_NAME, font=title_font,
                  foreground=COLOR_FG, background=COLOR_BG).pack(anchor="w", pady=(0, 2))
        ttk.Label(self, text=PROJECT_TAGLINE, font=sub_font,
                  style="Muted.TLabel").pack(anchor="w")

        ttk.Separator(self, orient="horizontal").pack(fill="x", pady=14)

        meta = ttk.Frame(self)
        meta.pack(anchor="w", fill="x")
        for label, value in [
                ("Version", PROJECT_VERSION),
                ("License", PROJECT_LICENSE),
                ("Project", PROJECT_GITHUB)]:
            row = ttk.Frame(meta)
            row.pack(fill="x", pady=2)
            ttk.Label(row, text=f"{label}:", width=12,
                      style="Muted.TLabel").pack(side="left")
            ttk.Label(row, text=value).pack(side="left")

        ttk.Separator(self, orient="horizontal").pack(fill="x", pady=14)

        ttk.Label(self, text="What this control panel does",
                  style="Heading.TLabel").pack(anchor="w")
        for line in (
                "•  Bluetooth — pair Tesla / a speaker, route Pi audio to it",
                "•  Display  — switch between KasmVNC and the V3D-accelerated stack",
                "•  Boot default lives in /etc/tesla-display/active",
                "•  Switcher subprocesses run under their own systemd scope, so a",
                "   KasmVNC restart no longer kills the switch mid-step",
        ):
            ttk.Label(self, text=line, style="Muted.TLabel",
                      font=sub_font).pack(anchor="w")

        ttk.Separator(self, orient="horizontal").pack(fill="x", pady=14)

        btns = ttk.Frame(self)
        btns.pack(anchor="w")
        ttk.Button(btns, text="Open GitHub repo",
                   style="Accent.TButton",
                   command=lambda: webbrowser.open(PROJECT_GITHUB)).pack(side="left", padx=(0, 6))
        ttk.Button(btns, text="Report an issue",
                   command=lambda: webbrowser.open(PROJECT_ISSUES)).pack(side="left", padx=6)


# --------------------------------------------------------------------------
# Main window
# --------------------------------------------------------------------------

def main():
    root = tk.Tk()
    root.title(f"{PROJECT_NAME} Settings")
    root.geometry("780x600")
    root.minsize(640, 520)
    apply_theme(root)

    header = ttk.Frame(root, padding=(16, 12))
    header.pack(fill="x")
    title_font = tkfont.Font(family="DejaVu Sans", size=14, weight="bold")
    ttk.Label(header, text=PROJECT_NAME, font=title_font).pack(side="left")
    ttk.Label(header, text="Settings", style="Muted.TLabel").pack(side="left", padx=8)

    notebook = ttk.Notebook(root)
    notebook.pack(fill="both", expand=True, padx=12, pady=(0, 12))
    notebook.add(BluetoothTab(notebook), text="Bluetooth")
    notebook.add(DisplayTab(notebook), text="Display")
    notebook.add(AboutTab(notebook), text="About")

    footer = ttk.Frame(root, padding=(16, 8))
    footer.pack(fill="x")
    ttk.Button(footer, text="Close", command=root.destroy).pack(side="right")

    root.mainloop()


if __name__ == "__main__":
    main()

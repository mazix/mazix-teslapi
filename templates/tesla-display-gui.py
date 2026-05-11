#!/usr/bin/env python3
"""Tesla display backend switcher GUI.

Wraps the `tesla-display` CLI in a Tk window so the user can flip
between KasmVNC and hwaccel without opening a terminal. Relies on the
sudoers rule installed by module 11 (NOPASSWD on /usr/local/bin/tesla-display).
"""
import subprocess
import tkinter as tk
from tkinter import messagebox, ttk

ACTIVE_FILE = "/etc/tesla-display/active"
BACKENDS = (("kasmvnc", "KasmVNC (video-optimized, software render)"),
            ("hwaccel", "Hwaccel (V3D-accelerated :0, IDE/dev work)"))


def run_cli(*args, timeout=20):
    try:
        r = subprocess.run(
            ["sudo", "-n", "/usr/local/bin/tesla-display", *args],
            capture_output=True, text=True, timeout=timeout)
        return (r.returncode == 0, r.stdout + r.stderr)
    except subprocess.TimeoutExpired:
        return (False, "Timeout — tesla-display didn't return in time.")
    except FileNotFoundError as e:
        return (False, f"Couldn't run tesla-display: {e}")


def read_active():
    try:
        with open(ACTIVE_FILE) as f:
            v = f.read().strip()
            if v in ("kasmvnc", "hwaccel"):
                return v
    except OSError:
        pass
    return "kasmvnc"


class App:
    def __init__(self, root):
        root.title("Tesla Display Backend")
        root.geometry("520x440")
        root.minsize(440, 380)
        self.root = root

        pad = {"padx": 14, "pady": 6}

        ttk.Label(root, text="Active backend (right now):",
                  font=("TkDefaultFont", 10, "bold")).pack(anchor="w", **pad)
        self.active_var = tk.StringVar(value=read_active())
        for value, label in BACKENDS:
            ttk.Radiobutton(root, text=label, variable=self.active_var,
                            value=value).pack(anchor="w", padx=28)

        ttk.Separator(root).pack(fill="x", pady=(12, 6))

        ttk.Label(root, text="Boot default (after reboot):",
                  font=("TkDefaultFont", 10, "bold")).pack(anchor="w", **pad)
        self.default_var = tk.StringVar(value=read_active())
        for value, label in BACKENDS:
            ttk.Radiobutton(root, text=label.split(" (")[0],
                            variable=self.default_var,
                            value=value).pack(anchor="w", padx=28)

        btns = ttk.Frame(root)
        btns.pack(fill="x", padx=14, pady=12)
        ttk.Button(btns, text="Apply switch now",
                   command=self.apply_switch).pack(side="left", padx=2)
        ttk.Button(btns, text="Save boot default",
                   command=self.save_default).pack(side="left", padx=2)
        ttk.Button(btns, text="Refresh",
                   command=self.refresh).pack(side="left", padx=2)
        ttk.Button(btns, text="Close",
                   command=root.destroy).pack(side="right", padx=2)

        self.status = tk.Text(root, height=8, font=("TkFixedFont", 9),
                              wrap="none")
        self.status.pack(fill="both", expand=True, padx=14, pady=(0, 12))
        self.status.config(state="disabled")

        self.refresh()

    def _show_status(self, text):
        self.status.config(state="normal")
        self.status.delete("1.0", tk.END)
        self.status.insert(tk.END, text)
        self.status.config(state="disabled")

    def refresh(self):
        active = read_active()
        self.active_var.set(active)
        self.default_var.set(active)
        ok, out = run_cli("status")
        if not ok:
            out = (f"Couldn't fetch tesla-display status. Open a terminal "
                   f"once and run `sudo -v` (or `sudo tesla-display status`) "
                   f"to confirm sudoers is wired up.\n\n{out}")
        self._show_status(out)

    def apply_switch(self):
        target = self.active_var.get()
        ok, out = run_cli("switch", target)
        if ok:
            messagebox.showinfo("Switched",
                                f"Now active: {target}\n\n{out.strip()[-400:]}")
        else:
            messagebox.showerror("Switch failed", out[-800:])
        self.refresh()

    def save_default(self):
        target = self.default_var.get()
        ok, out = run_cli("set-default", target)
        if ok:
            messagebox.showinfo("Boot default",
                                f"On next boot: {target}\n\n{out.strip()}")
        else:
            messagebox.showerror("Save failed", out[-800:])
        self.refresh()


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()

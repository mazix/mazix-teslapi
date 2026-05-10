#!/usr/bin/env python3
"""Pi Bluetooth Audio Manager — minimal Tk GUI.
Pair/connect BT devices and route Pi audio to them."""
import tkinter as tk
from tkinter import ttk, messagebox
import subprocess, re, threading, time

class App:
    def __init__(self, root):
        root.title("Pi BT Audio")
        root.geometry("760x500")
        self.root = root
        self.scanning = False

        top = ttk.Frame(root, padding=10); top.pack(fill=tk.X)
        self.scan_btn = ttk.Button(top, text="Start Scan", command=self.toggle_scan)
        self.scan_btn.pack(side=tk.LEFT)
        ttk.Button(top, text="Refresh", command=self.refresh).pack(side=tk.LEFT, padx=4)
        self.status = tk.StringVar(value="Ready")
        ttk.Label(top, textvariable=self.status).pack(side=tk.LEFT, padx=10)

        cols = ("mac", "name", "paired", "trusted", "connected")
        self.tv = ttk.Treeview(root, columns=cols, show="headings", height=14)
        for c, w in [("mac", 170), ("name", 290), ("paired", 70),
                     ("trusted", 70), ("connected", 90)]:
            self.tv.heading(c, text=c.title()); self.tv.column(c, width=w)
        self.tv.pack(fill=tk.BOTH, expand=True, padx=10)

        b = ttk.Frame(root, padding=10); b.pack(fill=tk.X)
        for txt, fn in [("Pair", self.pair), ("Trust", self.trust),
                        ("Connect", self.connect), ("Disconnect", self.disconnect),
                        ("Remove", self.remove), ("Set as Audio Out", self.set_sink)]:
            ttk.Button(b, text=txt, command=fn).pack(side=tk.LEFT, padx=2)

        self.sink_var = tk.StringVar(value="Sink: ?")
        ttk.Label(b, textvariable=self.sink_var).pack(side=tk.RIGHT)

        self.refresh()

    def bt(self, *args, timeout=15):
        try:
            r = subprocess.run(["bluetoothctl", *args], capture_output=True,
                               text=True, timeout=timeout)
            return r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            return "TIMEOUT"

    def refresh(self):
        for i in self.tv.get_children(): self.tv.delete(i)
        out = self.bt("devices")
        for line in out.splitlines():
            m = re.match(r"Device\s+(\S+)\s+(.+)", line.strip())
            if not m: continue
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
            self.sink_var.set(f"Sink: {r.stdout.strip() or '?'}")
        except Exception:
            pass

    def toggle_scan(self):
        if not self.scanning:
            self.scanning = True
            self.scan_btn.config(text="Stop Scan")
            self.status.set("Scanning…")
            threading.Thread(target=self._scan, daemon=True).start()
        else:
            self.scanning = False
            self.scan_btn.config(text="Start Scan")
            self.status.set("Stopped")

    def _scan(self):
        p = subprocess.Popen(["bluetoothctl"], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             text=True)
        try:
            p.stdin.write("power on\nagent on\ndefault-agent\nscan on\n")
            p.stdin.flush()
            while self.scanning:
                time.sleep(3); self.root.after(0, self.refresh)
        finally:
            try:
                p.stdin.write("scan off\nexit\n"); p.stdin.flush()
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
        if not mac: return
        self.status.set(f"{label} {mac}…")
        out = self.bt(cmd, mac, *args, timeout=30)
        self.status.set(out.strip().splitlines()[-1] if out.strip() else label)
        self.refresh()

    def pair(self):       self._do("Pair", "pair")
    def trust(self):      self._do("Trust", "trust")
    def connect(self):    self._do("Connect", "connect")
    def disconnect(self): self._do("Disconnect", "disconnect")
    def remove(self):
        mac = self.sel_mac()
        if mac and messagebox.askyesno("Remove", f"Remove {mac}?"):
            self.bt("remove", mac); self.refresh()

    def set_sink(self):
        try:
            r = subprocess.run(["pactl", "list", "short", "sinks"],
                               capture_output=True, text=True)
            for line in r.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2 and "bluez_output" in parts[1]:
                    subprocess.run(["pactl", "set-default-sink", parts[1]])
                    self.status.set(f"Default sink: {parts[1]}")
                    self.refresh(); return
            messagebox.showinfo("No BT sink", "Connect to a BT device first.")
        except Exception as e:
            messagebox.showerror("Error", str(e))

if __name__ == "__main__":
    root = tk.Tk(); App(root); root.mainloop()

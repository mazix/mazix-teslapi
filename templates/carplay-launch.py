#!/usr/bin/env python3
"""CarPlay / Android Auto kiosk launcher.

Launches Chromium in `--app=` mode pointed at the local static React build
of carplay-web-app. Adds a half-transparent floating close button in the
bottom-right corner (same pattern as hdmi-capture.py) so the user can quit
from a touchscreen.

Audio comes out of the dongle as a USB audio class device and is loop-routed
to the default sink (the BT-to-Tesla audio path, normally) via PipeWire.
"""
import os
import re
import signal
import subprocess
import threading
import tkinter as tk

KIOSK_URL = os.environ.get("CARPLAY_URL", "http://localhost:5005/")


def detect_audio_source():
    """USB-audio source for the Carlinkit dongle (Auto Box). Returns None if absent."""
    try:
        r = subprocess.run(["pactl", "list", "short", "sources"],
                           capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            cols = line.split()
            if len(cols) >= 2 and re.search(
                    r"Auto_Box|Magic_Communication|Carlinkit|CCPA",
                    cols[1], re.I):
                return cols[1]
    except Exception:
        pass
    return None


def load_loopback(src):
    if not src:
        return None
    try:
        r = subprocess.run(
            ["pactl", "load-module", "module-loopback",
             f"source={src}", "latency_msec=80", "adjust_time=0"],
            capture_output=True, text=True, timeout=5)
        mid = r.stdout.strip()
        return mid if mid.isdigit() else None
    except Exception:
        return None


def unload_loopback(mid):
    if mid:
        subprocess.run(["pactl", "unload-module", mid], timeout=5)


def spawn_chromium():
    # Separate user-data dir so kiosk profile doesn't fight the regular
    # browser session (extensions, cookies, etc).
    profile = os.path.expanduser("~/carplay/chromium-profile")
    os.makedirs(profile, exist_ok=True)
    args = [
        "/usr/bin/chromium",
        f"--user-data-dir={profile}",
        f"--app={KIOSK_URL}",
        "--start-fullscreen",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-features=TranslateUI,CalculateNativeWinOcclusion",
        "--autoplay-policy=no-user-gesture-required",
        # KasmVNC's Xvnc virtual display doesn't expose a GPU, so Chromium's
        # default GL stack returns a null WebGL context — which the
        # carplay-web-app renderer depends on. Force ANGLE's SwiftShader
        # backend (software WebGL) so video frames can at least be drawn.
        # If perf is bad, switch the system to the hwaccel display backend
        # (tesla-display switch hwaccel) — :0 has real V3D access.
        "--use-angle=swiftshader",
        "--ignore-gpu-blocklist",
        "--enable-unsafe-swiftshader",
        "--enable-features=VaapiVideoDecoder",
        # CarPlay web-app calls getUserMedia({audio:true}) for Siri voice
        # capture, which otherwise opens a permission prompt the user never
        # sees in kiosk mode and the audio init chain bails out. Auto-allow.
        "--use-fake-ui-for-media-stream",
        # Web Audio's AudioContext stays suspended until a user gesture
        # under default policy. We already allow autoplay; also force Web
        # Audio to ignore the gesture requirement so PcmPlayer starts.
        "--disable-features=MediaSessionService",
    ]
    return subprocess.Popen(args, stdin=subprocess.DEVNULL)


def build_overlay(on_close):
    root = tk.Tk()
    root.title("CarPlay Controls")
    root.overrideredirect(True)
    root.attributes("-topmost", True)
    try:
        root.attributes("-type", "dock")
    except tk.TclError:
        pass
    try:
        root.attributes("-alpha", 0.4)
    except tk.TclError:
        pass

    btn_size = 70
    pad = 20
    sw = root.winfo_screenwidth()
    sh = root.winfo_screenheight()
    root.geometry(f"{btn_size}x{btn_size}+{sw - btn_size - pad}+{sh - btn_size - pad}")
    root.configure(bg="#000000")

    inset = 18
    canvas = tk.Canvas(root, width=btn_size, height=btn_size,
                       bg="#000000", highlightthickness=0, cursor="hand2")
    canvas.pack(fill="both", expand=True)
    canvas.create_line(inset, inset,
                       btn_size - inset, btn_size - inset,
                       fill="white", width=5, capstyle="round")
    canvas.create_line(btn_size - inset, inset,
                       inset, btn_size - inset,
                       fill="white", width=5, capstyle="round")
    canvas.bind("<Button-1>", lambda _e: on_close())
    return root


def main():
    audio_src = os.environ.get("CARPLAY_AUDIO_SRC") or detect_audio_source()
    loopback_id = load_loopback(audio_src)

    chromium = spawn_chromium()
    closed = {"flag": False}

    def cleanup():
        if chromium.poll() is None:
            chromium.terminate()
            try:
                chromium.wait(timeout=3)
            except subprocess.TimeoutExpired:
                chromium.kill()
        unload_loopback(loopback_id)

    def shutdown_then_exit():
        if closed["flag"]:
            return
        closed["flag"] = True
        cleanup()
        try:
            root.destroy()
        except Exception:
            pass

    root = build_overlay(on_close=shutdown_then_exit)

    def watcher():
        chromium.wait()
        if not closed["flag"]:
            root.after(0, shutdown_then_exit)

    threading.Thread(target=watcher, daemon=True).start()

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            signal.signal(sig, lambda *_: shutdown_then_exit())
        except (ValueError, OSError):
            pass

    try:
        root.mainloop()
    finally:
        cleanup()


if __name__ == "__main__":
    main()

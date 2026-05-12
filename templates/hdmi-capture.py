#!/usr/bin/env python3
"""HDMI capture viewer.

Starts mpv fullscreen on the USB capture device, routes audio via a
PipeWire loopback to the default sink (Tesla BT, HDMI out, whatever
the user has chosen), and overlays a small always-on-top close button
in the bottom-right corner so the viewer can be dismissed with a tap
even on a touchscreen without a keyboard.

Override knobs (env vars):
    HDMI_DEV         /dev/videoX                   (default: /dev/video0)
    HDMI_AUDIO_SRC   PulseAudio source             (default: auto, MACROSILICON match)
    HDMI_FPS         requested framerate           (default: 60)
    HDMI_W / HDMI_H  requested resolution          (default: 1920x1080)
"""
import os
import re
import signal
import subprocess
import threading
import tkinter as tk
import tkinter.font as tkfont


def detect_audio_source():
    """Return the USB capture source name, or None."""
    try:
        r = subprocess.run(["pactl", "list", "short", "sources"],
                           capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            cols = line.split()
            if len(cols) >= 2 and re.search(
                    r"MACROSILICON|USB_Video|HDMI_Capture", cols[1], re.I):
                return cols[1]
    except Exception:
        pass
    return None


def load_loopback(src):
    """pactl load-module module-loopback; returns module id (str) or None."""
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
        subprocess.run(["pactl", "unload-module", mid],
                       capture_output=False, timeout=5)


def spawn_mpv():
    dev = os.environ.get("HDMI_DEV", "/dev/video0")
    fps = os.environ.get("HDMI_FPS", "60")
    w = os.environ.get("HDMI_W", "1920")
    h = os.environ.get("HDMI_H", "1080")
    args = [
        "/usr/bin/mpv",
        f"av://v4l2:{dev}",
        f"--demuxer-lavf-o=input_format=mjpeg,video_size={w}x{h},framerate={fps}",
        "--profile=low-latency",
        "--untimed",
        "--no-cache",
        "--no-audio",
        "--fs",
        "--osd-level=0",
        "--input-default-bindings=yes",
        "--cursor-autohide=1000",
    ]
    return subprocess.Popen(args, stdin=subprocess.DEVNULL)


def build_overlay(on_close):
    root = tk.Tk()
    root.title("HDMI Capture Controls")
    root.overrideredirect(True)         # no titlebar
    root.attributes("-topmost", True)   # float over mpv fullscreen
    try:
        root.attributes("-type", "dock")
    except tk.TclError:
        pass
    # Half-transparent window; works when a compositor is running, otherwise
    # falls back to opaque dark grey — still readable, white X stays sharp.
    try:
        root.attributes("-alpha", 0.4)
    except tk.TclError:
        pass

    btn_size = 70
    pad = 20
    sw = root.winfo_screenwidth()
    sh = root.winfo_screenheight()
    x = sw - btn_size - pad
    y = sh - btn_size - pad
    root.geometry(f"{btn_size}x{btn_size}+{x}+{y}")
    root.configure(bg="#000000")

    # Draw the X on a Canvas as two diagonal white lines so we don't depend
    # on a font glyph for the cross. The whole canvas is the click target.
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

    def _click(_event=None):
        on_close()
    canvas.bind("<Button-1>", _click)
    return root


def main():
    audio_src = os.environ.get("HDMI_AUDIO_SRC") or detect_audio_source()
    loopback_id = load_loopback(audio_src)

    mpv = spawn_mpv()

    def cleanup():
        if mpv.poll() is None:
            mpv.terminate()
            try:
                mpv.wait(timeout=2)
            except subprocess.TimeoutExpired:
                mpv.kill()
        unload_loopback(loopback_id)

    closed = {"flag": False}

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

    # If mpv exits on its own (user hit q), tear the overlay down too.
    def watcher():
        mpv.wait()
        if not closed["flag"]:
            root.after(0, shutdown_then_exit)

    threading.Thread(target=watcher, daemon=True).start()

    # Honor termination signals so PipeWire loopback always unloads.
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

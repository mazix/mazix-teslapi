#!/bin/bash
# hdmi-capture — open USB HDMI capture (e.g. MS2109) in fullscreen mpv,
# with audio routed via a PipeWire loopback into the default sink (so it
# follows whatever the user has set as audio out: BT to Tesla, HDMI, etc).
#
# Override knobs (env vars):
#   HDMI_DEV         /dev/videoX                   (default: /dev/video0)
#   HDMI_AUDIO_SRC   PulseAudio/PipeWire source    (default: auto-detected MACROSILICON)
#   HDMI_FPS         requested framerate           (default: 60)
#   HDMI_W x HDMI_H  requested resolution          (default: 1920x1080)

set -e

HDMI_DEV="${HDMI_DEV:-/dev/video0}"
HDMI_FPS="${HDMI_FPS:-60}"
HDMI_W="${HDMI_W:-1920}"
HDMI_H="${HDMI_H:-1080}"

# Auto-detect the USB capture audio source if not set explicitly. Matches
# MS2109-class devices by name; users with other chipsets can override.
if [ -z "${HDMI_AUDIO_SRC:-}" ]; then
    HDMI_AUDIO_SRC=$(pactl list short sources 2>/dev/null \
        | awk '/MACROSILICON|USB_Video|HDMI_Capture/{print $2; exit}')
fi

# Start audio loopback (capture source → default sink). Save module id for cleanup.
LOOPBACK_ID=""
if [ -n "$HDMI_AUDIO_SRC" ]; then
    LOOPBACK_ID=$(pactl load-module module-loopback \
        source="$HDMI_AUDIO_SRC" \
        latency_msec=80 \
        adjust_time=0 \
        2>/dev/null || true)
fi

cleanup() {
    if [ -n "$LOOPBACK_ID" ]; then
        pactl unload-module "$LOOPBACK_ID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM HUP

# Run mpv video-only fullscreen. --untimed + --no-cache for live source.
exec /usr/bin/mpv \
    "av://v4l2:$HDMI_DEV" \
    --demuxer-lavf-o="input_format=mjpeg,video_size=${HDMI_W}x${HDMI_H},framerate=${HDMI_FPS}" \
    --profile=low-latency \
    --untimed \
    --no-cache \
    --no-audio \
    --fs \
    --osd-level=1 \
    --osd-msg1="HDMI ${HDMI_W}x${HDMI_H}@${HDMI_FPS} — q to quit, f to toggle fullscreen"

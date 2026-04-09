#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — run this (or double-click the desktop icon) on event day
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV="$SCRIPT_DIR/.venv"
HTTP_PORT="${HTTP_PORT:-8080}"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [ ! -d "$VENV" ]; then
    echo ""
    echo "  ✗ Setup hasn't been run yet."
    echo "    Please run setup.sh first."
    echo ""
    read -p "  Press Enter to close…"
    exit 1
fi

source "$VENV/bin/activate"

# ── Check microphone ──────────────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │   WhisperLive — Starting up…        │"
echo "  └─────────────────────────────────────┘"
echo ""

MIC_COUNT=$(python3 -c "
import pyaudio
pa = pyaudio.PyAudio()
count = pa.get_device_count()
inputs = [pa.get_device_info_by_index(i) for i in range(count) if pa.get_device_info_by_index(i)['maxInputChannels'] > 0]
print(len(inputs))
" 2>/dev/null || echo "0")

if [ "$MIC_COUNT" = "0" ]; then
    echo "  ✗ No microphone detected!"
    echo "    Please plug in a microphone and try again."
    echo ""
    read -p "  Press Enter to close…"
    exit 1
fi

echo "  ✓ Microphone detected"

# ── Start HTTP server for display.html ────────────────────────────────────────
# ThreadingHTTPServer handles concurrent page loads (fonts are ~1MB, would queue
# on the default single-threaded server when many clients connect at once)
python3 -c "
import os, sys
from http.server import SimpleHTTPRequestHandler
from socketserver import ThreadingTCPServer

os.chdir('$SCRIPT_DIR')
ThreadingTCPServer.allow_reuse_address = True
httpd = ThreadingTCPServer(('0.0.0.0', $HTTP_PORT), SimpleHTTPRequestHandler)
httpd.serve_forever()
" &>/dev/null &
HTTP_PID=$!

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "  ✓ Display server: http://${LOCAL_IP:-localhost}:$HTTP_PORT/display.html"

# ── Clean up background processes on exit ─────────────────────────────────────
cleanup() {
    kill "$HTTP_PID" 2>/dev/null
    echo "  Stopped."
    exit 0
}
trap cleanup INT TERM

# ── Open display in browser after a short delay ───────────────────────────────
(
    sleep 4   # wait for server to be ready
    DISPLAY_URL="http://localhost:$HTTP_PORT/display.html"

    # Try to open on the second display (TV) if one is connected
    # Falls back gracefully to default display if not
    if command -v xrandr &>/dev/null; then
        SECOND=$(xrandr --query | grep ' connected' | awk '{print $1}' | sed -n '2p')
        if [ -n "$SECOND" ]; then
            echo "  ✓ Second display detected ($SECOND) — opening transcript there"
        fi
    fi

    xdg-open "$DISPLAY_URL" 2>/dev/null || \
    google-chrome --new-window "$DISPLAY_URL" 2>/dev/null || \
    firefox "$DISPLAY_URL" 2>/dev/null || \
    echo "  → Open $DISPLAY_URL manually in your browser"
) &

# ── Start server with auto-restart ────────────────────────────────────────────
echo "  ✓ Starting transcription server…"
echo "  ✓ Display will open automatically in ~4 seconds"
echo ""
echo "  ─────────────────────────────────────────"
echo "  Press Ctrl+C to stop"
echo "  ─────────────────────────────────────────"
echo ""

CRASH_COUNT=0
MAX_CRASHES=5

while true; do
    # Filter ALSA/JACK warnings from stderr (C-level PortAudio noise, not Python warnings)
    python3 "$SCRIPT_DIR/server.py" 2> >(grep -v -E "^(ALSA|jack)" >&2)
    EXIT_CODE=$?

    # Clean exit (Ctrl+C) — stop
    if [ $EXIT_CODE -eq 0 ]; then
        break
    fi

    CRASH_COUNT=$((CRASH_COUNT + 1))
    if [ $CRASH_COUNT -ge $MAX_CRASHES ]; then
        echo ""
        echo "  ✗ Server crashed $MAX_CRASHES times. Stopping."
        break
    fi

    echo ""
    echo "  ⚠ Server exited unexpectedly (code $EXIT_CODE). Restarting in 3s…"
    echo "    (crash $CRASH_COUNT of $MAX_CRASHES before giving up)"
    sleep 3
done

cleanup

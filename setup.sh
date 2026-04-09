#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# WhisperLive Setup — run this once before the event
# ─────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │   WhisperLive Setup                 │"
echo "  │   This takes about 5 minutes.       │"
echo "  └─────────────────────────────────────┘"
echo ""

# ── System packages ───────────────────────────────────────────────────────────
echo "▶ Installing system packages (needs sudo)…"
sudo apt-get update -qq
sudo apt-get install -y -qq \
    python3 python3-pip python3-venv \
    ffmpeg portaudio19-dev \
    xdg-utils

# ── Python venv ───────────────────────────────────────────────────────────────
echo "▶ Creating Python environment…"
python3 -m venv "$SCRIPT_DIR/.venv"
source "$SCRIPT_DIR/.venv/bin/activate"

pip install --quiet --upgrade pip

# ── Detect GPU ────────────────────────────────────────────────────────────────
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo "▶ NVIDIA GPU detected — installing GPU-accelerated PyTorch…"
    pip install --quiet torch torchaudio --index-url https://download.pytorch.org/whl/cu121
    GPU_FOUND=true
else
    echo "▶ No NVIDIA GPU found — installing CPU PyTorch…"
    pip install --quiet torch torchaudio --index-url https://download.pytorch.org/whl/cpu
    GPU_FOUND=false
fi

# ── Python packages ───────────────────────────────────────────────────────────
echo "▶ Installing Python packages…"
pip install --quiet \
    faster-whisper \
    websockets \
    pyaudio \
    numpy

# ── Pre-download the Whisper model ────────────────────────────────────────────
# Model size options:
#   small    — ~460MB, fastest, less accurate
#   medium   — ~1.5GB, good balance (default)
#   large-v3 — ~3GB, best accuracy, ~2x slower on CPU
# Override: export WHISPER_MODEL=large-v3 before running setup.sh
MODEL_SIZE="${WHISPER_MODEL:-medium}"
echo "▶ Downloading Whisper '$MODEL_SIZE' model — do this before the event…"
"$SCRIPT_DIR/.venv/bin/python3" << PYEOF
import sys
model_size = "$MODEL_SIZE"
print(f"  Downloading '{model_size}' model (this happens once)…")
try:
    from faster_whisper import WhisperModel
    WhisperModel(model_size, device="cpu", compute_type="int8")
    print(f"  ✓ Model '{model_size}' ready.")
except Exception as e:
    print(f"  ✗ Model download failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# ── Download fonts for offline display ─────────────────────────────────────────
echo "▶ Downloading fonts for offline display…"
FONT_DIR="$SCRIPT_DIR/fonts"
mkdir -p "$FONT_DIR"
curl -sL -o "$FONT_DIR/Inter.ttf"                  "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf"
curl -sL -o "$FONT_DIR/JetBrainsMono-Light.ttf"     "https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf/JetBrainsMono-Light.ttf"
curl -sL -o "$FONT_DIR/JetBrainsMono-Regular.ttf"   "https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf/JetBrainsMono-Regular.ttf"
echo "  ✓ Fonts cached for offline use"

# ── Desktop launcher ──────────────────────────────────────────────────────────
echo "▶ Creating desktop launcher…"
DESKTOP_FILE="$HOME/Desktop/Start Transcription.desktop"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Start Transcription
Comment=Start the live transcription server
Exec=bash -c 'cd "$SCRIPT_DIR" && bash start.sh'
Icon=audio-input-microphone
Terminal=true
StartupNotify=true
EOF
chmod +x "$DESKTOP_FILE"
# Mark as trusted (Ubuntu 22+)
gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │   ✓ Setup complete!                                 │"
echo "  │                                                     │"
if [ "$GPU_FOUND" = true ]; then
echo "  │   GPU mode: ON  (fast — ~1s latency)                │"
else
echo "  │   GPU mode: OFF (CPU — ~2-3s latency)               │"
fi
echo "  │                                                     │"
echo "  │   To start: double-click 'Start Transcription'      │"
echo "  │             on the Desktop                          │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""

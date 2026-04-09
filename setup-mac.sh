#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Cleartext Setup (macOS) — run this once before the event
# Requires Homebrew (https://brew.sh)
# ─────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │   Cleartext Setup (macOS)           │"
echo "  │   This takes about 5 minutes.       │"
echo "  └─────────────────────────────────────┘"
echo ""

# ── Check Homebrew ────────────────────────────────────────────────────────────
if ! command -v brew &> /dev/null; then
    echo "  ✗ Homebrew is not installed."
    echo "    Install it from https://brew.sh, then re-run this script."
    echo ""
    exit 1
fi

# ── System packages ───────────────────────────────────────────────────────────
echo "▶ Installing system packages via Homebrew…"
brew install python@3.11 portaudio ffmpeg

# Pick the python that brew just installed (avoid the system python)
PYTHON_BIN="$(brew --prefix python@3.11)/bin/python3.11"
if [ ! -x "$PYTHON_BIN" ]; then
    PYTHON_BIN="python3"
fi

# ── Python venv ───────────────────────────────────────────────────────────────
echo "▶ Creating Python environment…"
"$PYTHON_BIN" -m venv "$SCRIPT_DIR/.venv"
source "$SCRIPT_DIR/.venv/bin/activate"

pip install --quiet --upgrade pip

# ── PyTorch (CPU — Apple Silicon uses Metal via CTranslate2 directly) ─────────
echo "▶ Installing PyTorch (CPU build)…"
pip install --quiet torch torchaudio

# ── Python packages ───────────────────────────────────────────────────────────
# pyaudio needs portaudio headers; brew put them in a non-default location on
# Apple Silicon, so point pip at them explicitly.
echo "▶ Installing Python packages…"
PORTAUDIO_PREFIX="$(brew --prefix portaudio)"
CFLAGS="-I${PORTAUDIO_PREFIX}/include" \
LDFLAGS="-L${PORTAUDIO_PREFIX}/lib" \
pip install --quiet pyaudio

pip install --quiet \
    faster-whisper \
    websockets \
    numpy

# ── Pre-download the Whisper model ────────────────────────────────────────────
# Model size options:
#   small    — ~460MB, fastest, less accurate
#   medium   — ~1.5GB, good balance (default)
#   large-v3 — ~3GB, best accuracy, much slower on CPU
# Override: export WHISPER_MODEL=large-v3 before running setup-mac.sh
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

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │   ✓ Setup complete!                                 │"
echo "  │                                                     │"
echo "  │   To start: bash start.sh                           │"
echo "  │                                                     │"
echo "  │   First run will ask for microphone permission.     │"
echo "  │   Approve it in System Settings → Privacy.          │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""

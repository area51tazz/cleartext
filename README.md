# Cleartext

Real-time speech transcription for live events — displayed on a TV or any screen on the network. Designed to make panels, talks, and roundtables accessible without a captioning service.

**No internet required at runtime. No API keys. No cloud.**

---

## How it works

A laptop listens to a microphone, transcribes speech using [faster-whisper](https://github.com/SYSTRAN/faster-whisper), and broadcasts a rolling transcript over WebSocket. Any device on the same network — TV, phone, tablet, laptop — can open the display in a browser.

```
Microphone → server.py → WebSocket (port 9090)
                       → display.html (TV, phones, tablets)
```

Silence gaps between speakers automatically start a new paragraph. The display is fullscreen, high-contrast, and readable from across a room.

---

## Quick start — Ubuntu (recommended)

**One-time setup** (needs internet + sudo, ~5–10 minutes):

```bash
git clone https://github.com/area51tazz/cleartext.git
cd cleartext
bash setup.sh
```

This installs dependencies, creates a Python venv, downloads the Whisper model, bundles fonts, and creates a desktop shortcut.

**Event day** (no internet needed):

```bash
bash start.sh
```

The display opens automatically in your browser. Drag it to the HDMI-connected TV and press **F** for fullscreen.

### Audience access

`start.sh` prints a URL like `http://192.168.x.x:8080/display.html`. Anyone on the same WiFi can open it on their phone or laptop — the WebSocket address is detected automatically, no configuration needed.

---

## Quick start — Docker (Mac / NUC / homelab)

```bash
git clone https://github.com/area51tazz/cleartext.git
cd cleartext

# Apple Silicon Mac
docker compose --profile mac build   # first time only
docker compose --profile mac up -d

# x86 CPU-only
docker compose --profile cpu up -d

# x86 + NVIDIA GPU
docker compose --profile gpu up -d
```

Then open `display.html` in a browser and press **C** to configure the server address.

### Docker deployment profiles

| Profile | Target | Notes |
|---------|--------|-------|
| `mac` | Apple Silicon | Built locally (ARM64), CPU-only |
| `cpu` | x86_64 NUC | Pre-built image, pull-and-run |
| `gpu` | x86_64 + NVIDIA | Requires nvidia-container-toolkit |

---

## Display features

- **Fullscreen, dark background** — readable from across a large room
- **Paragraph breaks** — silence gaps of 3+ seconds start a new paragraph automatically
- **Status dot** — green (live), amber (signal delayed 8s+), red (no signal 15s+)
- **Auto-reconnect** — clients reconnect automatically if the server restarts
- **Multi-client** — up to 50 simultaneous viewers (configurable)
- **Mobile responsive** — works on phones and tablets
- **Offline fonts** — Inter + JetBrains Mono bundled, no internet needed

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `F` | Toggle fullscreen |
| `C` | Open config panel (server address, event name) |
| `R` | Clear transcript |
| `Esc` | Close config panel |

---

## Configuration

### Ubuntu native (server.py / start.sh)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WHISPER_MODEL` | `medium` | Model size: `small`, `medium`, `large-v3` |
| `WHISPER_PORT` | `9090` | WebSocket port |
| `HTTP_PORT` | `8080` | Display HTTP server port |
| `MAX_CLIENTS` | `50` | Max simultaneous display connections |

```bash
WHISPER_MODEL=large-v3 bash start.sh
```

### Docker (run_server.py)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WHISPER_MODEL` | `small` | Model size |
| `WHISPER_BACKEND` | `faster_whisper` | Backend engine |
| `MAX_CLIENTS` | `4` | Concurrent client limit |
| `MAX_CONNECTION_TIME` | `600` | Client timeout (seconds) |
| `OMP_NUM_THREADS` | `4` | CPU thread count |

### Model size guide

| Model | Size | GPU latency | CPU latency | Notes |
|-------|------|-------------|-------------|-------|
| small | 460MB | <1s | ~2-3s | Fast, good for clear speech |
| **medium** | 1.5GB | <1s | ~5-8s | **Default — best balance** |
| large-v3 | 3GB | ~1s | ~15s+ | Best accuracy, slow on CPU |

---

## Hardware

**Best:** Ubuntu laptop with NVIDIA GPU — sub-second latency, simple mic setup.

**Also works:** Any x86/ARM64 machine with Docker. CPU-only is fine for small events (medium model ~5-8s latency). GPU drops that to under 1 second.

---

## Troubleshooting

**No microphone detected on startup**
Plug in a microphone and re-run `start.sh`. The built-in mic works; a USB or XLR interface is better for a room.

**Display connects but text stops appearing**
The server logs to `transcription-YYYY-MM-DD.log` — check that for errors. The status dot will go amber/red if the server stops sending.

**Transcript appears on server but not in browser**
Check that port 9090 isn't blocked by a firewall. On Ubuntu: `sudo ufw allow 9090`.

**Docker: slow transcription**
Lower `OMP_NUM_THREADS` — too many threads can hurt performance. Try `OMP_NUM_THREADS=4` as a baseline.

**Docker: build fails on M1/M2/M3**
Make sure Docker Desktop is the Apple Silicon native version (not Rosetta):
```bash
docker info | grep Architecture   # should show aarch64 or arm64
```

**Port conflict**
Change `HTTP_PORT` or `WHISPER_PORT` via environment variable, or edit the port mapping in `docker-compose.yml`.

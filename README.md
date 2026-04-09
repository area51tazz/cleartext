# WhisperLive Docker Setup

Real-time speech transcription via WebSocket, running fully locally.
Server-client model: the server does all the heavy lifting, the client just streams audio.

## Quick Start (Mac — Apple Silicon)

```bash
# 1. Clone this setup
git clone <this-repo> whisperlive && cd whisperlive

# 2. Build the native ARM64 image (first build ~3-5 mins, downloads ~1GB)
docker compose --profile mac build

# 3. Start the server
docker compose --profile mac up -d

# 4. Check it's healthy
docker compose logs -f

# 5. Install the Python client on your Mac (outside Docker)
pip install whisper-live

# 6. Test with mic input
python3 test_client.py

# 7. Test with a file
python3 test_client.py --file /path/to/audio.wav
```

The server listens on `ws://localhost:9090`.

---

## Architecture

```
┌─────────────────────────────────────────┐
│  Your Mac / any client                  │
│  • Python client (test_client.py)       │
│  • Chrome/Firefox extension             │
│  • iOS app                              │
└──────────────┬──────────────────────────┘
               │ WebSocket ws://host:9090
               │
┌──────────────▼──────────────────────────┐
│  WhisperLive Server (Docker)            │
│  • faster-whisper (CTranslate2)         │
│  • VAD (Silero)                         │
│  • Multi-client WebSocket server        │
└─────────────────────────────────────────┘
```

---

## Deployment Profiles

| Profile  | Target            | Image                              | Notes                              |
|----------|-------------------|------------------------------------|-------------------------------------|
| `mac`    | Apple Silicon Mac | Built locally (ARM64)              | CPU-only, ~3-4x real-time on M-series |
| `cpu`    | NUC x86_64       | `ghcr.io/collabora/whisperlive-cpu` | Pre-built, pull-and-run            |
| `gpu`    | NUC + NVIDIA      | `ghcr.io/collabora/whisperlive-gpu` | Requires nvidia-container-toolkit  |

### NUC (x86_64, CPU)
```bash
docker compose --profile cpu up -d
```

### NUC (x86_64, NVIDIA GPU)
```bash
# Prerequisites: nvidia-container-toolkit installed on host
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html
docker compose --profile gpu up -d
```

### Future: Asus Ascent GX-10 (if running Linux)
The GX-10 uses NVIDIA Jetson AGX Orin under the hood. Use the GPU profile but
you may need to build from source targeting `linux/arm64` with CUDA support.
Contact Collabora for TensorRT engine builds — that backend gives the best
latency on Jetson hardware.

---

## Configuration

All server parameters are set via environment variables:

| Variable              | Default          | Options                                    |
|-----------------------|------------------|--------------------------------------------|
| `WHISPER_MODEL`       | `small`          | `tiny`, `base`, `small`, `medium`, `large-v3` |
| `WHISPER_BACKEND`     | `faster_whisper` | `faster_whisper`, `openvino`, `tensorrt`   |
| `MAX_CLIENTS`         | `4`              | Any integer                                |
| `MAX_CONNECTION_TIME` | `600`            | Seconds                                    |
| `OMP_NUM_THREADS`     | `4`              | Match your CPU core count                  |

Override in `docker-compose.yml` under `environment:` or pass via `-e`:

```bash
docker run -e WHISPER_MODEL=medium -e OMP_NUM_THREADS=8 -p 9090:9090 whisperlive-arm64:local
```

### Model size guide (Apple Silicon performance, faster-whisper backend)

| Model    | Size  | ~VRAM / RAM | Approx speed on M2 Pro | Use case                    |
|----------|-------|-------------|------------------------|-----------------------------|
| tiny     | 75MB  | ~1GB        | ~10x realtime          | Quick demos, low latency    |
| base     | 145MB | ~1GB        | ~7x realtime           | Good accuracy, fast         |
| **small**| 460MB | ~2GB        | ~4x realtime           | **Recommended starting point** |
| medium   | 1.5GB | ~5GB        | ~2x realtime           | High accuracy, multilingual |
| large-v3 | 3GB   | ~10GB       | ~0.5-1x realtime       | Best quality, slower        |

`small` is the sweet spot for real-time use on a Mac.

---

## Model caching

Models are cached in `./models/` (bind-mounted into the container).
First run will download automatically. Subsequent starts are instant.

To pre-download a specific model:
```bash
docker run --rm -v $(pwd)/models:/root/.cache/whisper-live \
    -e WHISPER_MODEL=medium \
    whisperlive-arm64:local \
    python3 -c "from faster_whisper import WhisperModel; WhisperModel('medium', download_root='/root/.cache/whisper-live')"
```

---

## Live Display (HDMI TV)

`display.html` is a full-screen transcript viewer that connects directly to the WhisperLive
WebSocket and renders a rolling, large-type transcript — designed to be readable from across a room.

### Setup at the event (Ubuntu native)

```
Laptop
  ├── HDMI cable → TV
  ├── server.py (WebSocket on port 9090) + HTTP server (port 8080)
  ├── Microphone → laptop audio input
  └── Browser: display opens automatically, drag to TV, press F for fullscreen
```

**Step by step:**

1. Run `bash start.sh` (or double-click "Start Transcription" on the Desktop)
2. Display opens automatically in the browser after ~4 seconds
3. Press **C** to set the event name, click Connect
4. Drag the browser window to the TV display, press **F** for fullscreen
5. Start speaking — transcript appears in under 1 second with GPU

The server auto-restarts if it crashes (up to 5 times). Logs are saved to `transcription-YYYY-MM-DD.log`.

### Setup at the event (Docker — Mac/NUC)

1. Start the server: `docker compose --profile mac up -d`
2. Open `http://localhost:8080/display.html` in a browser
3. Press **C** to configure, click Connect

### Keyboard shortcuts (while display.html is focused)

| Key | Action |
|-----|--------|
| `F` | Toggle fullscreen |
| `C` | Open/close config panel |
| `R` | Clear transcript (new session) |
| `Esc` | Close config panel |

### Running the display on a different laptop

`start.sh` runs an HTTP server on port 8080. From another machine on the same network:

1. Open `http://<transcription-laptop-ip>:8080/display.html`
2. Press **C** and set the server address to `<transcription-laptop-ip>:9090`

The page auto-reconnects if the connection drops.

### Status indicator

The dot in the top-right corner shows connection health:
- **Green** — connected and receiving messages
- **Amber** — connected but no message received for 8+ seconds
- **Red** — no signal for 15+ seconds or disconnected

---

## Browser Extension

Once the server is running, install the Chrome or Firefox extension
from the `Audio-Transcription-Chrome` / `Audio-Transcription-Firefox` directories
in the WhisperLive repo. These let you transcribe browser audio directly.

```bash
git clone https://github.com/collabora/WhisperLive
# Chrome: Load unpacked from Audio-Transcription-Chrome/
# Firefox: Load temporary add-on from Audio-Transcription-Firefox/
```

---

## Homelab: Running on a NUC as a service

On your NUC host, copy this directory and create a systemd service:

```bash
scp -r . user@nuc-hostname:/opt/whisperlive

# On the NUC:
cat > /etc/systemd/system/whisperlive.service << 'EOF'
[Unit]
Description=WhisperLive Transcription Server
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/opt/whisperlive
ExecStart=/usr/bin/docker compose --profile cpu up
ExecStop=/usr/bin/docker compose --profile cpu down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now whisperlive
```

Then point your Mac client at the NUC's IP:
```bash
python3 test_client.py --server 192.168.1.x
```

---

## Troubleshooting

**Build fails on M1/M2/M3:**
Make sure Docker Desktop is the Apple Silicon version (not Rosetta). Check:
```bash
docker info | grep Architecture
# Should show: aarch64 or arm64
```

**Server starts but client can't connect:**
```bash
# Check the container is running and port is exposed
docker ps
# Check server logs
docker compose logs whisperlive
# Test port directly
nc -zv localhost 9090
```

**Slow transcription:**
- Reduce `OMP_NUM_THREADS` if overloading CPU (counter-intuitively, too many threads can hurt)
- Switch to `tiny` or `base` model for lower latency
- `small` with `OMP_NUM_THREADS=4` is usually the best balance on M-series

**"Model not found" on first start:**
Normal — it's downloading. Watch `docker compose logs -f` and wait for
`INFO: Model loaded` before connecting a client.

**Port 9090 conflict:**
Change the host port mapping in docker-compose.yml: `"9091:9090"` then
connect clients with `--port 9091`.

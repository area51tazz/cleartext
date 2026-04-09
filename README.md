# Cleartext

Real-time speech transcription for live events — displayed on a TV or any screen on the network. Designed to make panels, talks, and roundtables accessible without a captioning service.

**No internet required at runtime. No API keys. No cloud.**

---

## What it does

You run this on a laptop. It listens to a microphone, converts speech to text in near real-time, and shows a rolling transcript on any screen — a TV over HDMI, or any phone/tablet/laptop on the same WiFi.

Silence gaps between speakers automatically create a new paragraph. The display is large, high-contrast, and readable from across a room.

---

## System requirements

### Ubuntu (recommended path)

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| OS | Ubuntu 20.04+ | Other Linux distros may work with minor adjustments |
| Python | 3.9+ | Usually pre-installed on Ubuntu |
| RAM | 4GB | 8GB+ recommended |
| Disk | 5GB free | ~1.5GB for the AI model, rest for dependencies |
| CPU | Any modern x86_64 | Works without a GPU |
| GPU | NVIDIA (optional) | Cuts transcription delay from ~5s to under 1s |
| Microphone | Any | USB mic or XLR interface recommended for rooms |

### Mac / other hardware (Docker path)

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | [Install here](https://docs.docker.com/desktop/) |
| Apple Silicon or x86_64 | M1/M2/M3 Macs work great |
| 8GB RAM | Model download ~460MB–1.5GB depending on quality setting |

---

## Setup — Ubuntu

> **You only do this once, before the event.** You'll need internet access and administrator (sudo) access on the laptop.

**Step 1: Get the code**

Open a terminal and run:

```bash
git clone https://github.com/area51tazz/cleartext.git
cd cleartext
```

> If you don't have `git`, run `sudo apt install git` first.

**Step 2: Run setup**

```bash
bash setup.sh
```

This will:
- Install required system packages (needs your sudo password once)
- Create a self-contained Python environment in a `.venv/` folder — this keeps all dependencies isolated from the rest of your system and means you don't need to install anything globally
- Detect whether you have an NVIDIA GPU and install the right version of PyTorch automatically
- Download the Whisper AI model (~1.5GB, happens once)
- Download fonts so the display works offline
- Create a "Start Transcription" shortcut on your Desktop

This takes about 5–10 minutes depending on your internet speed.

**That's it for setup.** Everything is self-contained in the `cleartext/` folder. To uninstall, just delete the folder.

---

## Running on event day — Ubuntu

Double-click **"Start Transcription"** on your Desktop, or open a terminal and run:

```bash
bash start.sh
```

What happens:
1. Checks that a microphone is connected
2. Starts the transcription server
3. Opens the display in your browser automatically after ~4 seconds
4. Prints a URL like `http://192.168.x.x:8080/display.html` for audience access

**To show on a TV:** drag the browser window to your HDMI-connected display and press **F** for fullscreen.

**To give audience access:** share the printed URL. Anyone on the same WiFi can open it on their phone or laptop — no app to install, no configuration needed.

Press **Ctrl+C** in the terminal to stop. The server auto-restarts if it crashes (up to 5 times).

---

## Setup & running — Mac / Docker

```bash
git clone https://github.com/area51tazz/cleartext.git
cd cleartext

# Apple Silicon Mac
docker compose --profile mac build   # first time only (~5 mins)
docker compose --profile mac up -d

# x86 CPU-only (NUC, PC)
docker compose --profile cpu up -d

# x86 + NVIDIA GPU
docker compose --profile gpu up -d
```

Then open `display.html` in a browser. Press **C** to enter the server address (`localhost:9090`) and your event name.

| Profile | Target | Notes |
|---------|--------|-------|
| `mac` | Apple Silicon Mac | Built locally, CPU-only |
| `cpu` | x86_64, no GPU | Pre-built image, pull-and-run |
| `gpu` | x86_64 + NVIDIA | Requires nvidia-container-toolkit |

---

## Display controls

| Key | Action |
|-----|--------|
| `F` | Toggle fullscreen |
| `C` | Open settings (server address, event name) |
| `R` | Clear transcript |
| `Esc` | Close settings |

**Status dot** (top right):
- Green — live and receiving
- Amber — connected but no signal for 8+ seconds
- Red — disconnected or no signal for 15+ seconds

---

## Transcription quality

The `medium` model is the default and works well for most accents and environments. If you need higher accuracy (e.g. strong accents, technical vocabulary), use `large-v3` — but it's slower on CPU.

| Model | Download size | GPU delay | CPU delay |
|-------|--------------|-----------|-----------|
| small | 460MB | <1s | ~2-3s |
| **medium** _(default)_ | 1.5GB | <1s | ~5-8s |
| large-v3 | 3GB | ~1s | 15s+ |

To change model (Ubuntu):
```bash
WHISPER_MODEL=large-v3 bash start.sh
```

To change model (setup, so it downloads the right one):
```bash
WHISPER_MODEL=large-v3 bash setup.sh
```

---

## Troubleshooting

**"No microphone detected"**
Plug in a microphone and re-run `start.sh`. Built-in laptop mics work but pick up a lot of room noise — a USB mic or lavalier is better for events.

**Text appears in the terminal but not in the browser**
Make sure ports 9090 and 8080 are not blocked. On Ubuntu:
```bash
sudo ufw allow 9090
sudo ufw allow 8080
```

**Display connects but text stops updating**
The status dot will turn amber then red. The server logs to `transcription-YYYY-MM-DD.log` in the project folder — that's the first place to look. Restarting `start.sh` usually recovers it.

**Docker: build fails on M1/M2/M3**
Make sure you installed the Apple Silicon version of Docker Desktop (not Rosetta). Check with:
```bash
docker info | grep Architecture   # should show: aarch64 or arm64
```

**Docker: first start is slow**
It's downloading the AI model (~460MB for `small`). Watch progress with `docker compose logs -f` — it's ready when you see `Model loaded`.

**Port already in use**
```bash
HTTP_PORT=8081 WHISPER_PORT=9091 bash start.sh
```

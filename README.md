# Cleartext

Real-time speech transcription for live events — displayed on a TV or any screen on the network. Designed to make panels, talks, and roundtables accessible without a captioning service.

**No internet required at runtime. No API keys. No cloud.**

---

## What it does

You run this on a laptop. It listens to a microphone, converts speech to text in near real-time, and shows a rolling transcript on any screen — a TV over HDMI, or any phone/tablet/laptop on the same WiFi.

Silence gaps between speakers automatically create a new paragraph. The display is large, high-contrast, and readable from across a room.

---

## System requirements

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| OS | Ubuntu 20.04+, macOS 12+, or Windows 11 (WSL2) | |
| Python | 3.9+ | Pre-installed on Ubuntu and macOS |
| RAM | 4GB | 8GB+ recommended |
| Disk | 5GB free | ~1.5GB for the AI model, rest for dependencies |
| CPU | Any modern x86_64 or Apple Silicon | Works without a GPU |
| GPU | NVIDIA (optional) | Cuts transcription delay from ~5s to under 1s |
| Microphone | Any | USB mic or XLR interface recommended for rooms |

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

## Setup — macOS

> Requires [Homebrew](https://brew.sh). If you don't have it, install it first.

```bash
git clone https://github.com/area51tazz/cleartext.git
cd cleartext
bash setup-mac.sh
```

This installs Python, PortAudio, and FFmpeg via Homebrew, creates the same self-contained `.venv/`, downloads the model and fonts.

To run on event day:

```bash
bash start.sh
```

The first time you start it, macOS will ask permission to access the microphone — approve it in **System Settings → Privacy & Security → Microphone**.

---

## Setup — Windows (WSL2)

> Cleartext runs inside [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) on Windows 11. WSL2 doesn't expose your microphone by default, so there's an extra step to share it.

**Step 1: Install WSL2 and Ubuntu**

In PowerShell (as Administrator):

```powershell
wsl --install -d Ubuntu
```

Reboot when prompted, then open **Ubuntu** from the Start menu.

**Step 2: Share your microphone with WSL2**

WSL2 needs USB passthrough to see your mic. Install [usbipd-win](https://github.com/dorssel/usbipd-win/releases) on Windows, then in PowerShell (as Administrator):

```powershell
usbipd list                              # find your mic's BUSID, e.g. 2-3
usbipd bind --busid 2-3                  # one-time
usbipd attach --wsl --busid 2-3          # each session
```

In your Ubuntu (WSL) terminal, confirm the mic is visible:

```bash
arecord -l    # should list your mic
```

**Step 3: Run the Ubuntu setup**

Inside the Ubuntu terminal:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/area51tazz/cleartext.git
cd cleartext
bash setup.sh
```

To run on event day:

```bash
bash start.sh
```

The display URL will work from any browser on your Windows host or any other device on the same network.

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

To change model:
```bash
WHISPER_MODEL=large-v3 bash start.sh
```

To change the model that gets downloaded during setup:
```bash
WHISPER_MODEL=large-v3 bash setup.sh        # Ubuntu / WSL
WHISPER_MODEL=large-v3 bash setup-mac.sh    # macOS
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

**macOS: "operation not permitted" or no audio**
macOS blocks mic access until you grant it. Open **System Settings → Privacy & Security → Microphone** and enable Terminal (or whichever app you're running `start.sh` from). Restart `start.sh` after granting permission.

**WSL: `arecord -l` shows no devices**
Your mic isn't shared with WSL yet. From an Administrator PowerShell, run `usbipd list` to find your mic's BUSID, then `usbipd attach --wsl --busid <id>`. You need to re-run `attach` after every reboot.

**Port already in use**
```bash
HTTP_PORT=8081 WHISPER_PORT=9091 bash start.sh
```

---

## Credits

Cleartext is a thin layer over a stack of excellent open-source projects. If this tool is useful to you, the credit belongs to them:

- **[OpenAI Whisper](https://github.com/openai/whisper)** — the speech-recognition model that does the actual transcription. Released under MIT license.
- **[faster-whisper](https://github.com/SYSTRAN/faster-whisper)** — a re-implementation of Whisper using CTranslate2, ~4× faster and uses less memory. The reason this runs in real time on a laptop. MIT license.
- **[CTranslate2](https://github.com/OpenNMT/CTranslate2)** — the inference engine underneath faster-whisper. MIT license.
- **[PyTorch](https://pytorch.org/)** — used for GPU detection and acceleration. BSD license.
- **[PyAudio](https://people.csail.mit.edu/hubert/pyaudio/)** + **[PortAudio](http://www.portaudio.com/)** — the cross-platform audio capture layer. MIT-style licenses.
- **[websockets](https://github.com/python-websockets/websockets)** — the WebSocket server library. BSD license.
- **[NumPy](https://numpy.org/)** — audio buffer math. BSD license.
- **[Inter](https://rsms.me/inter/)** by Rasmus Andersson — the display font, designed for screen readability. SIL Open Font License.
- **[JetBrains Mono](https://www.jetbrains.com/lp/mono/)** — the monospace font used in the config panel. SIL Open Font License.

The tools above do all the hard work. Cleartext just wires them together for live events and ships a display you can put on a TV.

---

## License

Cleartext is released under the [MIT License](LICENSE) — use it, fork it, modify it, ship it, sell it. Just keep the copyright notice. The bundled fonts retain their original SIL Open Font License terms.


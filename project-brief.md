# Live Transcription Display — Project Brief

## What we're building

A self-contained live transcription system for **panel/roundtable events**. A laptop listens via microphone, transcribes speech in near-real-time using OpenAI Whisper, and displays a rolling full-screen transcript on an HDMI-connected TV — readable from across a room.

No internet required at runtime. No API keys. No cloud services. One double-click to start.

---

## Target hardware

- **Primary:** Ubuntu laptop (GPU unknown — must work CPU-only, accelerate automatically if NVIDIA present)
- **Secondary/homelab:** x86 NUCs (CPU or NVIDIA GPU), Asus Ascent GX-10, Synology NAS
- **Mac:** Earlier Docker-based setup exists but Ubuntu native is the current focus

---

## Current stack

| Component | Choice | Notes |
|---|---|---|
| Transcription | `faster-whisper` medium model | CPU: ~5–8s latency. GPU: <1s. `int8` on CPU, `float16` on CUDA |
| Language | Locked to `en` | Various accents; `condition_on_previous_text=False` to prevent hallucination loops |
| Audio capture | `pyaudio` | 16kHz mono, 0.5s chunks |
| VAD | RMS energy threshold + faster-whisper's built-in VAD filter | Flushes on 1.2s silence or 12s max buffer |
| Transport | `websockets` WebSocket server on port 9090 | asyncio-native; thread-safe handoff via `call_soon_threadsafe` |
| Display | `display.html` — plain HTML/CSS/JS, no framework | Opens in browser, drag to TV, press F for fullscreen |

### Key architecture decisions

- **Single Python process** (`server.py`) — audio thread → transcription thread → asyncio event loop → WebSocket broadcast
- **`asyncio.Queue`** bridges the transcription thread and the async broadcast loop (thread-safe via `call_soon_threadsafe`)
- **No Docker** on Ubuntu — native Python venv for simplicity and mic access reliability
- **No speaker diarization** in this iteration — was evaluated (pyannote community-1, diart) but adds latency and complexity. Deferred to v2.

---

## File structure

```
/
├── server.py          # Main process: audio capture, Whisper transcription, WebSocket server
├── display.html       # Full-screen transcript display page (connects to ws://localhost:9090)
├── setup.sh           # One-time install: apt packages, venv, PyTorch, model download, desktop launcher
├── start.sh           # Event-day launcher: mic check, starts server, opens browser
└── README.md          # Non-technical operator guide
```

---

## server.py — current state

```python
MODEL_SIZE   = "medium"
LANGUAGE     = "en"
WS_PORT      = 9090
VAD_SILENCE_SEC  = 1.2
MAX_BUFFER_SEC   = 12
```

### Async coroutines running in gather:
- `broadcast_loop()` — awaits `asyncio.Queue`, fans out transcript segments to all connected clients
- `heartbeat_loop()` — sends `{"type": "heartbeat"}` every 5s so display can detect silent-but-connected failure mode

### Known issues / remaining work:
- `transcribe()` is called with `condition_on_previous_text=False` and no `initial_prompt` — resolved hallucination loop where prompt text bled into output ("Welcome. Thank you thank you thank you")
- WebSocket connection was silently staying "green" while messages stopped — fixed by app-level heartbeat + client-side staleness timer (8s → amber, 15s → red)
- `audio_queue` maxsize set to 500 to prevent blocking the audio thread during long CPU inference

---

## display.html — current state

- **Aesthetic:** Dark background (`#0a0a0a`), off-white serif text (`Lora` font), `IBM Plex Mono` for UI chrome
- **Layout:** Header (event name + status dot), scrolling transcript area with top fade, footer (word count)
- **Scroll behaviour:** Transcript div translates upward via CSS transform so newest line is always at bottom
- **Status dot:** Green (live + messages flowing), amber (connected but no message >8s), red (>15s or error)
- **Heartbeat:** Any received message resets the staleness clock — heartbeat packets are swallowed, not displayed
- **Reconnect:** Auto-reconnects every 3s on disconnect; does NOT re-show waiting overlay if transcript already has content
- **Keyboard:** `F` = fullscreen, `R` = clear transcript

---

## Things explicitly decided against (and why)

| Option | Decision | Reason |
|---|---|---|
| Docker on Ubuntu | Dropped | Extra layer to debug when mic isn't showing up at 9am |
| pyannote community-1 diarization | Deferred | Batch model, not streaming; 10–30s latency on CPU |
| diart streaming diarization | Deferred | Requires HuggingFace token + licence accept; ops complexity |
| Silence-gap speaker colour coding | Removed | Too unreliable; mid-thought pauses trigger false turns |
| `initial_prompt` for accent hinting | Removed | Bleeds into transcript output; `language="en"` + medium model sufficient |
| WhisperLive (collabora) | Replaced with custom server | Didn't need the full WhisperLive stack; simpler to own the code |

---

## Known remaining issues / what to work on next

1. **Intermittent display freezes** — believed fixed (heartbeat + asyncio queue refactor) but needs field testing
2. **ALSA warnings on startup** — harmless Linux audio device probing noise, can be suppressed with `PYTHONWARNINGS` or redirected in `start.sh`
3. **setup.sh model pre-download** — currently uses a `python3 -c` one-liner to trigger download; should be made more robust with progress output
4. **No graceful restart** — if server crashes mid-event, operator has to re-run `start.sh`; could add a `while true; do python3 server.py; done` wrapper in `start.sh`
5. **Display page served from filesystem** (`file://`) — works fine for same-machine use; if display laptop is separate, needs a simple HTTP server to serve `display.html`
6. **Font loading** — `display.html` loads Lora + IBM Plex Mono from Google Fonts; needs internet on first load, cached after. Should bundle fonts for offline use.
7. **No logging to file** — console only; useful to add `logging.FileHandler` for post-event debugging
8. **Accent accuracy** — medium model is good but not perfect on strong non-native accents; `large-v3` would help at the cost of ~2x CPU latency

---

## Setup flow (for reference)

```bash
# One-time (before event, needs internet)
bash setup.sh

# Event day (no internet needed)
# Double-click "Start Transcription" desktop icon
# OR:
bash start.sh
```

`setup.sh` handles: apt deps, Python venv, GPU detection, correct PyTorch variant, faster-whisper, websockets, pyaudio, numpy, model download (~1.5GB for medium), desktop launcher creation.

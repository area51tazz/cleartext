#!/usr/bin/env python3
"""
WhisperLive server — minimal edition
Captures mic audio, transcribes with faster-whisper, broadcasts over WebSocket.
No Docker, no external services, no API keys.
"""

import asyncio
import json
import logging
import queue
import threading
import time
import re
import sys
import os
from datetime import date
import numpy as np
import websockets

LOG_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(LOG_DIR, f"transcription-{date.today()}.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(LOG_FILE, mode="a"),
    ],
)
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
MODEL_SIZE        = os.environ.get("WHISPER_MODEL", "medium")
WS_HOST           = "0.0.0.0"
WS_PORT           = int(os.environ.get("WHISPER_PORT", "9090"))
SAMPLE_RATE       = 16000
CHUNK_SECONDS     = 0.5          # audio chunk fed to mic thread
VAD_SILENCE_SEC   = 1.2          # seconds of silence → flush segment
MAX_BUFFER_SEC    = 12           # force flush after this many seconds
LANGUAGE          = "en"         # locked to English; speakers may have various accents
MAX_CLIENTS       = int(os.environ.get("MAX_CLIENTS", "50"))

# ── Globals ───────────────────────────────────────────────────────────────────
connected_clients: set = set()

# ── Whisper loader ────────────────────────────────────────────────────────────
def load_model():
    log.info(f"Loading Whisper model '{MODEL_SIZE}' — first run downloads it (~1.5GB for medium)…")
    from faster_whisper import WhisperModel
    # Use GPU if available, fall back to CPU automatically
    try:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
    except ImportError:
        device = "cpu"
    compute = "float16" if device == "cuda" else "int8"
    log.info(f"Running on {device.upper()} with {compute} precision")
    model = WhisperModel(MODEL_SIZE, device=device, compute_type=compute)
    log.info("Model ready.")
    return model

# ── Audio capture ─────────────────────────────────────────────────────────────
def audio_thread(audio_queue: queue.Queue):
    """Continuously reads mic audio and puts chunks onto audio_queue."""
    try:
        import pyaudio
    except ImportError:
        log.error("pyaudio not installed. Run setup.sh to fix this.")
        sys.exit(1)

    pa = pyaudio.PyAudio()

    # Find default input device
    try:
        dev_info = pa.get_default_input_device_info()
        log.info(f"Microphone: {dev_info['name']}")
    except OSError:
        log.error("No microphone found. Please plug one in and restart.")
        sys.exit(1)

    chunk_size = int(SAMPLE_RATE * CHUNK_SECONDS)
    stream = pa.open(
        format=pyaudio.paFloat32,
        channels=1,
        rate=SAMPLE_RATE,
        input=True,
        frames_per_buffer=chunk_size,
    )

    log.info("Microphone open. Listening…")
    while True:
        try:
            raw = stream.read(chunk_size, exception_on_overflow=False)
            audio = np.frombuffer(raw, dtype=np.float32)
            audio_queue.put(audio)
        except Exception as e:
            log.warning(f"Audio read error: {e}")
            time.sleep(0.1)

# ── Simple VAD: RMS energy threshold ─────────────────────────────────────────
def is_speech(audio: np.ndarray, threshold: float = 0.005) -> bool:
    return float(np.sqrt(np.mean(audio ** 2))) > threshold

# ── Transcription thread ──────────────────────────────────────────────────────
def transcription_thread(model, audio_queue: queue.Queue, bcast_queue: asyncio.Queue, loop: asyncio.AbstractEventLoop):
    """
    Accumulates audio chunks, flushes to Whisper when silence detected or buffer full.
    Puts transcript text onto broadcast queue.
    """
    buffer = np.array([], dtype=np.float32)
    last_speech_time = time.time()
    buffer_start_time = time.time()

    while True:
        try:
            # Drain the audio queue
            try:
                chunk = audio_queue.get(timeout=0.1)
                buffer = np.concatenate([buffer, chunk])
            except queue.Empty:
                pass

            if len(buffer) == 0:
                continue

            now = time.time()
            buffer_duration = len(buffer) / SAMPLE_RATE

            # Update last-speech timestamp
            latest_chunk = buffer[-int(SAMPLE_RATE * CHUNK_SECONDS):]
            if is_speech(latest_chunk):
                last_speech_time = now

            silence_duration = now - last_speech_time
            should_flush = (
                silence_duration >= VAD_SILENCE_SEC and buffer_duration >= 0.5
            ) or buffer_duration >= MAX_BUFFER_SEC

            if not should_flush:
                continue

            # Transcribe
            segments, info = model.transcribe(
                buffer,
                language=LANGUAGE,
                condition_on_previous_text=False,
                vad_filter=True,
                vad_parameters={"min_silence_duration_ms": 300},
                beam_size=3,
            )
            text = " ".join(s.text.strip() for s in segments).strip()
            # Filter out punctuation-only output (whisper sometimes emits
            # bare periods/ellipses for silence or background noise)
            if text and re.search(r'[a-zA-Z0-9]', text):
                log.info(f"  → {text}")
                # Include actual silence duration so client can decide
                # paragraph breaks based on real pauses, not message timing
                msg = {"text": text, "silence_sec": round(silence_duration, 1)}
                loop.call_soon_threadsafe(bcast_queue.put_nowait, msg)

            # Reset buffer
            buffer = np.array([], dtype=np.float32)
            last_speech_time = time.time()
            buffer_start_time = time.time()

        except Exception as e:
            log.error(f"Transcription thread error: {e}")
            # Reset buffer and continue — don't let the thread die
            buffer = np.array([], dtype=np.float32)
            last_speech_time = time.time()
            buffer_start_time = time.time()
            time.sleep(0.1)

# ── WebSocket server ──────────────────────────────────────────────────────────

# asyncio queue — safe to use from the event loop; transcription thread
# posts via call_soon_threadsafe (see transcription_thread below)
broadcast_queue: asyncio.Queue = None   # initialised in main()

async def broadcast_loop():
    """Pulls from broadcast_queue and fans out to all connected clients."""
    while True:
        try:
            data = await broadcast_queue.get()
            if not connected_clients:
                continue
            msg = json.dumps({
                "segments": [{"text": data["text"], "completed": True}],
                "silence_sec": data.get("silence_sec", 0),
            })
            # Send to all clients concurrently with a timeout so one slow
            # client can't block the others
            dead = set()
            async def _send(client):
                try:
                    await asyncio.wait_for(client.send(msg), timeout=5)
                except Exception:
                    dead.add(client)
            await asyncio.gather(*[_send(c) for c in list(connected_clients)])
            connected_clients.difference_update(dead)
        except Exception as e:
            log.warning(f"Broadcast error: {e}")
            await asyncio.sleep(0.1)

async def heartbeat_loop():
    """Sends a lightweight heartbeat every 5s so the display can verify message flow."""
    heartbeat_count = 0
    while True:
        await asyncio.sleep(5)
        if not connected_clients:
            continue
        msg = json.dumps({"type": "heartbeat"})
        dead = set()
        async def _send(client):
            try:
                await asyncio.wait_for(client.send(msg), timeout=5)
            except Exception:
                dead.add(client)
        await asyncio.gather(*[_send(c) for c in list(connected_clients)])
        connected_clients.difference_update(dead)
        # Log client count every ~60s (12 heartbeats)
        heartbeat_count += 1
        if heartbeat_count % 12 == 0:
            log.info(f"Clients connected: {len(connected_clients)}")


async def ws_handler(websocket):
    """Handle a new display client connection."""
    addr = websocket.remote_address

    # Enforce client limit
    if len(connected_clients) >= MAX_CLIENTS:
        log.warning(f"Rejected {addr[0]}:{addr[1]} — at capacity ({MAX_CLIENTS} clients)")
        await websocket.send(json.dumps({"message": "FULL", "max_clients": MAX_CLIENTS}))
        await websocket.close(1013, "Server at capacity")
        return

    connected_clients.add(websocket)
    log.info(f"Display connected: {addr[0]}:{addr[1]}  (total: {len(connected_clients)})")
    try:
        await websocket.send(json.dumps({"message": "SERVER_READY"}))
        await websocket.wait_closed()
    except Exception:
        pass
    finally:
        connected_clients.discard(websocket)
        log.info(f"Display disconnected: {addr[0]}:{addr[1]}  (total: {len(connected_clients)})")

async def main():
    global broadcast_queue
    broadcast_queue = asyncio.Queue()

    # Load model (blocking, before starting the hot path)
    model = load_model()

    # Grab the running loop so transcription thread can post to it safely
    loop = asyncio.get_running_loop()

    # Start audio capture thread
    audio_q: queue.Queue = queue.Queue(maxsize=500)  # ~250s of chunks, never blocks audio thread
    threading.Thread(target=audio_thread, args=(audio_q,), daemon=True).start()

    # Start transcription thread — pass loop + broadcast_queue so it can
    # use call_soon_threadsafe instead of a thread-unsafe queue
    threading.Thread(
        target=transcription_thread,
        args=(model, audio_q, broadcast_queue, loop),
        daemon=True,
    ).start()

    log.info(f"WebSocket server listening on ws://localhost:{WS_PORT}")
    log.info(f"Open display.html in a browser to see the transcript.")

    async with websockets.serve(
        ws_handler,
        WS_HOST,
        WS_PORT,
        ping_interval=30,   # server-side ping every 30s as belt-and-braces
        ping_timeout=10,
    ):
        await asyncio.gather(broadcast_loop(), heartbeat_loop())

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Stopped.")

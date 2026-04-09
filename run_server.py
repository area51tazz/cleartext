#!/usr/bin/env python3
"""
WhisperLive server entry point.
Used by the ARM64 Docker image as the CMD.

Reads config from environment variables so the same image
works for any deployment target.
"""
import os
from whisper_live.server import TranscriptionServer

BACKEND = os.getenv("WHISPER_BACKEND", "faster_whisper")
HOST = os.getenv("WHISPER_HOST", "0.0.0.0")
PORT = int(os.getenv("WHISPER_PORT", "9090"))
MAX_CLIENTS = int(os.getenv("MAX_CLIENTS", "4"))
MAX_CONNECTION_TIME = int(os.getenv("MAX_CONNECTION_TIME", "600"))
CUSTOM_MODEL_PATH = os.getenv("WHISPER_MODEL_PATH", None)  # optional custom model

print(f"Starting WhisperLive server")
print(f"  backend : {BACKEND}")
print(f"  host    : {HOST}:{PORT}")
print(f"  clients : max {MAX_CLIENTS}, timeout {MAX_CONNECTION_TIME}s")
if CUSTOM_MODEL_PATH:
    print(f"  model   : {CUSTOM_MODEL_PATH}")
else:
    model = os.getenv("WHISPER_MODEL", "small")
    print(f"  model   : {model} (will download if not cached)")

server = TranscriptionServer()
server.run(
    host=HOST,
    port=PORT,
    backend=BACKEND,
    faster_whisper_custom_model_path=CUSTOM_MODEL_PATH,
    whisper_tensorrt_path=None,
    trt_multilingual=False,
)

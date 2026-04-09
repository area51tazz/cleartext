#!/usr/bin/env python3
"""
Quick connectivity test for WhisperLive server.
Run this on your Mac (outside Docker) once the server is up.

Usage:
    pip install whisper-live
    python3 test_client.py                    # test with microphone (5 seconds)
    python3 test_client.py --file audio.wav   # test with a file
    python3 test_client.py --server 192.168.x.x  # test remote server (e.g. NUC)
"""
import argparse
import time
import threading
from whisper_live.client import TranscriptionClient

def main():
    parser = argparse.ArgumentParser(description="WhisperLive test client")
    parser.add_argument("--server", default="localhost", help="Server hostname or IP")
    parser.add_argument("--port", type=int, default=9090)
    parser.add_argument("--file", default=None, help="Audio file to transcribe")
    parser.add_argument("--lang", default="en", help="Language code (e.g. en, de, fr)")
    parser.add_argument("--model", default="small", help="Whisper model size")
    parser.add_argument("--duration", type=int, default=10,
                        help="Seconds to record from mic (if no --file)")
    args = parser.parse_args()

    print(f"Connecting to WhisperLive at {args.server}:{args.port}")
    print(f"Model: {args.model}  |  Language: {args.lang}")

    client = TranscriptionClient(
        host=args.server,
        port=args.port,
        lang=args.lang,
        translate=False,
        model=args.model,
        use_vad=True,
        save_output_recording=False,
    )

    if args.file:
        print(f"Transcribing file: {args.file}")
        client(args.file)
    else:
        print(f"Recording from microphone for {args.duration}s... speak now!")
        # Run client in a thread, stop after duration
        t = threading.Thread(target=client)
        t.daemon = True
        t.start()
        time.sleep(args.duration)
        print("\nDone.")

if __name__ == "__main__":
    main()

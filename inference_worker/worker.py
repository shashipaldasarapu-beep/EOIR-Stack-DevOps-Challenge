from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
import re
from pathlib import Path

ENGINE_PATH = Path(os.environ.get("ENGINE_PATH", "/app/models/eo_detector_fp16.engine"))
MANIFEST_PATH = Path(os.environ.get("MANIFEST_PATH", "/app/models/manifest.json"))
PORT = int(os.environ.get("WORKER_PORT", "9000"))

def verify_engine():
    try:
        if not ENGINE_PATH.is_file():
            return False, "engine_missing"

        if not MANIFEST_PATH.is_file():
            return False, "manifest_missing"

        with MANIFEST_PATH.open("r", encoding="utf-8") as file:
            manifest = json.load(file)

        expected = manifest.get("sha256", "")

        if not isinstance(expected, str):
            return False, "invalid_checksum"

        if not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
            return False, "invalid_checksum"

        digest = hashlib.sha256()

        with ENGINE_PATH.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(chunk)

        actual = digest.hexdigest()

        if actual.lower() != expected.lower():
            return False, "checksum_mismatch"

        return True, "engine_integrity_verified"

    except (OSError, ValueError, TypeError) as exc:
        print(f"Engine verification error: {exc}", flush=True)
        return False, "verification_error"


def worker_status():
    valid, reason = verify_engine()

    return {
        "service": "inference_worker",
        "engine_loaded": valid,
        "checksum_valid": valid,
        "ready": valid,
        "reason": reason,
        "inference_mode": "cpu_simulation"
    }


class WorkerHandler(BaseHTTPRequestHandler):

    def send_json(self, status_code, payload):
        body = json.dumps(payload).encode("utf-8")

        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):

        if self.path in ("/status", "/health"):
            status = worker_status()
            code = 200 if status["ready"] else 503
            self.send_json(code, status)
            return

        if self.path == "/detect":
            status = worker_status()

            if not status["ready"]:
                self.send_json(503, status)
                return

            self.send_json(200, {
                "success": True,
                "inference_mode": "cpu_simulation",
                "detections": [
                    {
                        "class": "vehicle",
                        "confidence": 0.96,
                        "bbox": [120, 80, 420, 310]
                    }
                ]
            })
            return

        self.send_json(404, {"error": "Not found"})

    def log_message(self, format, *args):
        print(f"Worker: {format % args}", flush=True)


if __name__ == "__main__":
    print("Starting inference worker...", flush=True)

    valid, reason = verify_engine()
    print(f"Engine verification: {reason}", flush=True)

    server = ThreadingHTTPServer(("0.0.0.0", PORT), WorkerHandler)

    print(f"Inference worker listening on port {PORT}", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()

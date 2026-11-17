from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import urllib.request
import urllib.error

WORKER_URL = os.environ.get(
    "WORKER_URL",
    "http://inference_worker:9000"
).rstrip("/")

APP_PORT = int(os.environ.get("APP_PORT", "8000"))


def worker_request(endpoint):
    try:
        request = urllib.request.Request(
            f"{WORKER_URL}{endpoint}",
            headers={"Accept": "application/json"}
        )

        with urllib.request.urlopen(request, timeout=3) as response:
            data = json.loads(response.read().decode("utf-8"))
            return response.status, data

    except urllib.error.HTTPError as exc:
        try:
            data = json.loads(exc.read().decode("utf-8"))
        except (ValueError, OSError):
            data = {"error": "Worker returned an invalid response"}

        return exc.code, data

    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        return 503, {"error": str(exc)}


class Handler(BaseHTTPRequestHandler):

    def send_json(self, status_code, payload):
        body = json.dumps(payload).encode("utf-8")

        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):

        if self.path == "/health":
            code, worker = worker_request("/status")

            ready = (
                code == 200
                and worker.get("ready") is True
                and worker.get("checksum_valid") is True
            )

            self.send_json(
                200 if ready else 503,
                {
                    "status": "healthy" if ready else "unhealthy",
                    "worker_ready": ready
                }
            )
            return

        if self.path == "/api/v1/detect":
            code, result = worker_request("/detect")

            if code != 200:
                self.send_json(503, {
                    "error": "Inference worker unavailable",
                    "worker_response": result
                })
                return

            self.send_json(200, result)
            return

        self.send_json(404, {"error": "Not found"})

    def log_message(self, format, *args):
        print(f"Vision API: {format % args}", flush=True)


if __name__ == "__main__":
    print(f"Starting Vision API on port {APP_PORT}", flush=True)

    server = ThreadingHTTPServer(
        ("0.0.0.0", APP_PORT),
        Handler
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()

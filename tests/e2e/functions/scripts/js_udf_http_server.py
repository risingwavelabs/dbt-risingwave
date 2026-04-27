#!/usr/bin/env python3
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _write_json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

    def do_POST(self):
        if self.path != "/echo":
            self._write_json({"error": "unsupported_path"}, status=404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length or 0)
        payload = json.loads(raw.decode() or "{}")
        prefix = payload.get("prefix", "")
        value = payload.get("value", "")
        self._write_json({"result": f"{prefix}:{value}"})


def main():
    bind_host = os.getenv("JS_UDF_HTTP_BIND_HOST", "127.0.0.1")
    server = ThreadingHTTPServer((bind_host, 18080), Handler)
    print(f"js udf http server listening on {bind_host}:18080", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

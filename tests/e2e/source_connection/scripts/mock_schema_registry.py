from http.server import BaseHTTPRequestHandler, HTTPServer


class MockSchemaRegistryHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"compatibilityLevel":"BACKWARD"}')

    def log_message(self, fmt, *args):
        return


HTTPServer(("127.0.0.1", 18081), MockSchemaRegistryHandler).serve_forever()

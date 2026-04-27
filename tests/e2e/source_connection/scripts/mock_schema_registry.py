import socketserver


RESPONSE_BODY = b'{"compatibilityLevel":"BACKWARD"}'
RESPONSE = (
    b"HTTP/1.1 200 OK\r\n"
    b"Content-Type: application/json\r\n"
    + f"Content-Length: {len(RESPONSE_BODY)}\r\n".encode()
    + b"Connection: close\r\n\r\n"
    + RESPONSE_BODY
)


class MockSchemaRegistryHandler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            request_bytes = self.request.recv(4096)
            if not request_bytes:
                return
            self.request.sendall(RESPONSE)
        except OSError:
            return


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


ReusableTCPServer(("0.0.0.0", 18081), MockSchemaRegistryHandler).serve_forever()

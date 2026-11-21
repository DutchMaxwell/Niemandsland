"""Independent fake for the optional GDExtension e2e; no model dependencies."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import sys


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        body = json.dumps({"schema": 1, "values": [0.0] * len(request["leaves"]),
                           "brain": {"name": "constant-test", "hash": "zeros-v1"}}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    port_file = Path(sys.argv[1])
    # Publish the port atomically: a reader that sees the file sees the whole number, never the empty
    # file between create and write.
    staging = port_file.with_name(port_file.name + ".tmp")
    staging.write_text(str(server.server_port))
    staging.replace(port_file)
    server.serve_forever()

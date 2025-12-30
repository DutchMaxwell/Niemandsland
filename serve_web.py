#!/usr/bin/env python3
"""
Simple HTTP server with COOP/COEP headers for Godot 4 web exports.
Run this script from the project root, then open http://localhost:8060

Usage:
    python3 serve_web.py

Godot 4 web exports require SharedArrayBuffer for multi-threading.
SharedArrayBuffer requires these HTTP headers:
- Cross-Origin-Opener-Policy: same-origin
- Cross-Origin-Embedder-Policy: require-corp

Without these headers, you'll see "Failed to fetch" errors.
"""

import http.server
import socketserver
import os

PORT = 8060
DIRECTORY = "build/web"

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # Required headers for SharedArrayBuffer (Godot 4 multi-threading)
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def guess_type(self, path):
        # Ensure .wasm files are served with correct MIME type
        if path.endswith('.wasm'):
            return 'application/wasm'
        return super().guess_type(path)

if __name__ == '__main__':
    # Check if build directory exists
    if not os.path.exists(DIRECTORY):
        print(f"Error: {DIRECTORY} does not exist.")
        print("Please export your Godot project first:")
        print("  Project → Export → Web → Export Project")
        exit(1)

    # Check if index.html exists
    if not os.path.exists(os.path.join(DIRECTORY, "index.html")):
        print(f"Error: {DIRECTORY}/index.html not found.")
        print("Please export your Godot project first:")
        print("  Project → Export → Web → Export Project")
        exit(1)

    with socketserver.TCPServer(("", PORT), CORSRequestHandler) as httpd:
        print(f"Serving Godot web export from {DIRECTORY}/")
        print(f"Open http://localhost:{PORT} in your browser")
        print("Press Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")

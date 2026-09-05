#!/usr/bin/env python3
"""Developer-only loopback leaf scorer. Standard library; no bundled model."""
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import importlib
import ipaddress
import json
import math
import os
from pathlib import Path
import re

MAX_BYTES = 16 * 1024 * 1024


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def tensor(value, shape):
    if not shape:
        return finite(value)
    return isinstance(value, list) and len(value) == shape[0] and all(tensor(v, shape[1:]) for v in value)


def validate_tokens(tokens):
    # Exact policy_tokens/leaf_value_fn shape from nml-core/src/tokens.rs.
    shapes = {"units": (24, 72), "objs": (6, 12), "terr": (18, 12), "cands": (160, 40)}
    shapes.update({key + "_mask": (shape[0],) for key, shape in list(shapes.items())})
    shapes.update(glob=(16,), actor=(160,), target=(160,), label=())
    if not isinstance(tokens, dict) or set(tokens) != set(shapes):
        raise ValueError("leaf must be a policy_tokens dictionary")
    if any(not tensor(tokens[key], shape) for key, shape in shapes.items()):
        raise ValueError("token dimensions/numbers")
    if tokens["label"] != -1 or any(tokens["cands_mask"]):
        raise ValueError("leaf tokens must be state-only")


def validate_identity(identity):
    if not isinstance(identity, dict) or set(identity) != {"name", "hash"}:
        raise ValueError("brain identity requires name and hash")
    if any(not isinstance(v, str) or not v or len(v) > 128 or any(ord(c) < 32 or ord(c) == 127 for c in v)
           for v in identity.values()):
        raise ValueError("invalid brain identity")


def evaluate(request, scorer, identity):
    if not isinstance(request, dict) or type(request.get("schema")) is not int or request["schema"] != 1:
        raise ValueError("unsupported schema")
    if type(request.get("side")) is not int or request["side"] not in (1, 2):
        raise ValueError("side must be 1 or 2")
    if not isinstance(request.get("core_commit"), str) or not re.fullmatch(r"[0-9a-fA-F]{40}|unknown", request["core_commit"]):
        raise ValueError("invalid core_commit")
    if type(request.get("rules_epoch")) is not int or request["rules_epoch"] < 0:
        raise ValueError("invalid rules_epoch")
    leaves = request.get("leaves")
    if not isinstance(leaves, list) or len(leaves) > 1024:
        raise ValueError("invalid batch length")
    for leaf in leaves:
        validate_tokens(leaf)
    validate_identity(identity)
    # Empty batch is the client's game-start metadata probe; no model call.
    values = scorer(leaves, request["side"]) if leaves else []
    if not isinstance(values, list) or len(values) != len(leaves) or not all(map(finite, values)):
        raise ValueError("scorer must return one finite float per leaf")
    return {"schema": 1, "values": values, "brain": identity}


def make_server(host, port, scorer, identity):
    if not ipaddress.ip_address(host).is_loopback:
        raise ValueError("loopback binding required")
    validate_identity(identity)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(2)

        def do_POST(self):
            if not ipaddress.ip_address(self.client_address[0]).is_loopback or "Origin" in self.headers:
                self.send_error(403, "loopback developer clients only")
                return
            if self.path != "/" or self.headers.get_content_type() != "application/json":
                self.send_error(400, "POST application/json to /")
                return
            try:
                lengths = self.headers.get_all("Content-Length", [])
                if len(lengths) != 1 or "Transfer-Encoding" in self.headers:
                    raise ValueError("one Content-Length required")
                length = int(lengths[0])
                if not 0 < length <= MAX_BYTES:
                    raise ValueError("request too large/empty")
                data = self.rfile.read(length)
                if len(data) != length:
                    raise ValueError("truncated request")
                response = evaluate(json.loads(data), scorer, identity)
                body = json.dumps(response, allow_nan=False).encode()
            except (ValueError, TypeError, OverflowError, RecursionError):
                self.send_error(400, "invalid brain request or scorer output")
                return
            except Exception:
                # No private model paths/tracebacks on the wire.
                self.send_error(503, "scorer unavailable")
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except OSError:
                pass  # client already declined its deadline

        def log_message(self, *_args):
            pass

    return HTTPServer((host, port), Handler)


def load_scorer():
    path = os.environ.get("NML_BRAIN_MODULE", "")
    if not path:
        raise ValueError("set NML_BRAIN_MODULE to a trusted importable Python module")
    module = importlib.import_module(path)
    scorer = getattr(module, "score", None)
    if not callable(scorer):
        raise ValueError("adapter must export score(states, side)")
    identity = {"name": getattr(module, "BRAIN_NAME", "local-evaluator"),
                "hash": getattr(module, "BRAIN_HASH", None) or hashlib.sha256(Path(module.__file__).read_bytes()).hexdigest()}
    validate_identity(identity)
    return scorer, identity


def main():
    scorer, identity = load_scorer()
    server = make_server("127.0.0.1", int(os.environ.get("NML_BRAIN_PORT", "8765")), scorer, identity)
    print("brain: %(name)s %(hash)s" % identity, "at http://127.0.0.1:%d" % server.server_port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

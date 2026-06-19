#!/usr/bin/env python3
"""Headless 2-client multiplayer soak orchestrator.

Starts a local relay, launches two headless Godot clients (host + guest) running
test/mp/mp_harness.tscn, scrapes the room code from the host, runs them for a fixed
duration, then parses both clients' MP_HARNESS summaries and asserts the stability
invariants. Exit 0 = green, 1 = a drop / failure was observed.

Usage (local, Flatpak Godot):
  relay/.venv/bin/python test/mp/run_soak.py \
      --godot "flatpak run --filesystem=home --share=network org.godotengine.Godot" \
      --duration 120 --workload synthetic

Usage (CI, godot on PATH):
  python test/mp/run_soak.py --duration 60 --workload synthetic
"""

import argparse
import os
import re
import shlex
import socket
import subprocess
import sys
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HARNESS_SCENE = "res://test/mp/mp_harness.tscn"
CODE_RE = re.compile(r"MP_HARNESS: CODE ([A-Z0-9]+)")
SUMMARY_RE = re.compile(r"MP_HARNESS: SUMMARY (.+)")


def _wait_for_port(port: int, timeout: float = 15.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), 0.3):
                return True
        except OSError:
            time.sleep(0.2)
    return False


class Client:
    """A headless Godot harness process whose stdout is drained in a thread."""

    def __init__(self, name: str, cmd: list):
        self.name = name
        self.lines: list[str] = []
        self.code: str | None = None
        self.proc = subprocess.Popen(
            cmd, cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        self._thread = threading.Thread(target=self._drain, daemon=True)
        self._thread.start()

    def _drain(self) -> None:
        for line in self.proc.stdout:
            line = line.rstrip("\n")
            self.lines.append(line)
            m = CODE_RE.search(line)
            if m and self.code is None:
                self.code = m.group(1)

    def wait_for_code(self, timeout: float) -> str | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.code:
                return self.code
            if self.proc.poll() is not None:
                return self.code
            time.sleep(0.2)
        return self.code

    def wait(self, timeout: float) -> int | None:
        try:
            return self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            return None

    def summary(self) -> dict:
        for line in reversed(self.lines):
            m = SUMMARY_RE.search(line)
            if m:
                out = {}
                for tok in m.group(1).split():
                    if "=" in tok:
                        k, v = tok.split("=", 1)
                        out[k] = v
                return out
        return {}

    def tail(self, n: int = 25) -> str:
        return "\n".join("    " + l for l in self.lines[-n:])


def _godot_cmd(godot: str, role: str, relay_url: str, args) -> list:
    cmd = shlex.split(godot) + [
        "--headless", "--path", REPO, HARNESS_SCENE, "--",
        "--role", role, "--relay-url", relay_url,
        "--duration", str(args.duration), "--workload", args.workload,
        "--fault", args.fault,
    ]
    if args.target_fps:
        cmd += ["--target-fps", str(args.target_fps)]
    return cmd


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT_CMD", "godot"),
                    help="Godot launch command (shell-split).")
    ap.add_argument("--duration", type=int, default=60)
    ap.add_argument("--workload", default="synthetic", choices=["synthetic", "opr"])
    ap.add_argument("--fault", default="none")
    ap.add_argument("--target-fps", type=int, default=0)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--relay-python", default=sys.executable,
                    help="Python used to launch the relay (needs websockets).")
    args = ap.parse_args()

    relay_url = f"ws://127.0.0.1:{args.port}"
    relay = subprocess.Popen(
        [args.relay_python, os.path.join("relay", "relay_server.py"), "--port", str(args.port)],
        cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    failures: list[str] = []
    host = guest = None
    try:
        if not _wait_for_port(args.port):
            print("FATAL: relay did not start on port", args.port)
            return 1
        print(f"[soak] relay up on {relay_url} | duration={args.duration}s "
              f"workload={args.workload} fault={args.fault}")

        host = Client("host", _godot_cmd(args.godot, "host", relay_url, args))
        code = host.wait_for_code(timeout=40.0)
        if not code:
            print("FATAL: host never produced a room code")
            print(host.tail())
            return 1
        print(f"[soak] host room code = {code}; launching guest")

        guest_cmd = _godot_cmd(args.godot, "guest", relay_url, args) + ["--code", code]
        guest = Client("guest", guest_cmd)

        budget = args.duration + 60
        host.wait(budget)
        guest.wait(20)

        # --- Assertions ---
        for c in (host, guest):
            s = c.summary()
            if not s:
                failures.append(f"{c.name}: no summary (crash/timeout)")
                continue
            if s.get("ok") != "true":
                failures.append(f"{c.name}: ok={s.get('ok')} failures={s.get('failures')}")
            if s.get("connected") != "true":
                failures.append(f"{c.name}: never connected")
            if args.fault == "none" and s.get("reconnects", "0") != "0":
                failures.append(f"{c.name}: {s.get('reconnects')} unexpected reconnect(s)")
        hs = host.summary()
        gs = guest.summary()
        if hs and int(hs.get("peers", "0")) < 1:
            failures.append("host never saw the guest join (peers=0)")
        if args.workload == "synthetic" and hs and gs:
            hm = int(hs.get("minis", "0"))
            gm = int(gs.get("minis", "0"))
            if hm < 1:
                failures.append(f"host spawned no minis (minis={hm})")
            elif hm != gm:
                failures.append(f"state not converged: host minis={hm}, guest minis={gm}")
    finally:
        for c in (host, guest):
            if c and c.proc.poll() is None:
                c.proc.kill()
        relay.terminate()

    print("\n===== SOAK REPORT =====")
    print("host : ", host.summary() if host else "(none)")
    print("guest: ", guest.summary() if guest else "(none)")
    if failures:
        print("\nFAILURES:")
        for f in failures:
            print("  -", f)
        for c in (host, guest):
            if c:
                print(f"\n--- {c.name} tail ---\n{c.tail()}")
        print("\nRESULT: FAIL")
        return 1
    print("\nRESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

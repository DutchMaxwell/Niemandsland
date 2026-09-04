#!/usr/bin/env python3
"""Run deterministic multiplayer regression scenarios against two real Godot peers."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from typing import Callable


REPO = Path(__file__).resolve().parents[2]
HARNESS_SCENE = "res://test/mp/mp_two_instance_harness.tscn"
ROOM_RE = re.compile(r"MP2: host CODE ([A-Z0-9]+)")
SCRIPT_ERROR_RE = re.compile(
    r"SCRIPT ERROR|SKRIPTFEHLER|Parse Error|Parser Error|Parser-Fehler|Skriptfehler",
    re.IGNORECASE,
)
MIN_AVAILABLE_MB = 3500


class HarnessFailure(RuntimeError):
    pass


def atomic_json(path: Path, value: object) -> None:
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def available_memory_mb() -> int:
    for line in Path("/proc/meminfo").read_text(encoding="ascii").splitlines():
        if line.startswith("MemAvailable:"):
            return int(line.split()[1]) // 1024
    raise HarnessFailure("cannot read MemAvailable from /proc/meminfo")


def wait_for_memory(timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while True:
        available = available_memory_mb()
        if available >= MIN_AVAILABLE_MB:
            print(f"[mp2] memory gate: {available} MB available")
            return
        if time.monotonic() >= deadline:
            raise HarnessFailure(
                f"memory gate timed out: {available} MB available, {MIN_AVAILABLE_MB} MB required"
            )
        time.sleep(1.0)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_for_port(port: int, timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.05)
    raise HarnessFailure(f"relay did not listen on 127.0.0.1:{port} within {timeout:.0f}s")


def kill_group(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        proc.wait(timeout=3)
    except (ProcessLookupError, PermissionError, subprocess.TimeoutExpired):
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            proc.wait(timeout=3)
        except (ProcessLookupError, PermissionError):
            pass
        except subprocess.TimeoutExpired:
            pass


class Client:
    def __init__(self, role: str, cmd: list[str], env: dict[str, str], run_dir: Path):
        self.role = role
        self.run_dir = run_dir
        self.log_path = run_dir / f"{role}.log"
        self.log_file = self.log_path.open("w", encoding="utf-8", buffering=1)
        self.lines: list[str] = []
        self.room_code: str | None = None
        self.proc = subprocess.Popen(
            cmd,
            cwd=REPO,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        self.thread = threading.Thread(target=self._drain, daemon=True)
        self.thread.start()

    @property
    def state_path(self) -> Path:
        return self.run_dir / f"{self.role}.state.json"

    @property
    def ack_path(self) -> Path:
        return self.run_dir / f"{self.role}.ack.json"

    @property
    def command_path(self) -> Path:
        return self.run_dir / f"{self.role}.command.json"

    def _drain(self) -> None:
        assert self.proc.stdout is not None
        for raw in self.proc.stdout:
            line = raw.rstrip("\n")
            self.lines.append(line)
            self.log_file.write(line + "\n")
            match = ROOM_RE.search(line)
            if match and self.room_code is None:
                self.room_code = match.group(1)

    def state(self) -> dict:
        return read_json(self.state_path)

    def fatal_log_line(self) -> str | None:
        return next((line for line in self.lines if SCRIPT_ERROR_RE.search(line)), None)

    def assert_alive(self) -> None:
        fatal = self.fatal_log_line()
        if fatal:
            raise HarnessFailure(f"{self.role}: script error in log: {fatal}")
        code = self.proc.poll()
        if code is not None:
            raise HarnessFailure(f"{self.role}: Godot exited unexpectedly with code {code}")
        state = self.state()
        if state.get("failed"):
            raise HarnessFailure(f"{self.role}: {state.get('failure', 'harness failure')}")

    def close_log(self) -> None:
        self.thread.join(timeout=2)
        self.log_file.close()


class Run:
    def __init__(self, args: argparse.Namespace, run_dir: Path):
        self.args = args
        self.run_dir = run_dir
        self.seq = {"host": 0, "guest": 0}
        self.relay: subprocess.Popen | None = None
        self.relay_log = None
        self.clients: dict[str, Client] = {}
        self.xdg_dirs: list[Path] = []
        self.checkpoints: list[dict] = []
        self.scenario_deadline: float | None = None
        self.shutdown_failure: str | None = None

    def deadline(self, timeout: float) -> float:
        deadline = time.monotonic() + timeout
        if self.scenario_deadline is not None:
            return min(deadline, self.scenario_deadline)
        return deadline

    def start(self) -> None:
        wait_for_memory(self.args.memory_timeout)
        port = self.args.port or free_port()
        relay_url = f"ws://127.0.0.1:{port}"
        self.relay_log = (self.run_dir / "relay.log").open("w", encoding="utf-8")
        self.relay = subprocess.Popen(
            [self.args.relay_python, str(REPO / "relay" / "relay_server.py"), "--port", str(port)],
            cwd=REPO,
            stdout=self.relay_log,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        wait_for_port(port)
        print(f"[mp2] relay: {relay_url}")

        host = self._start_client("host", relay_url)
        room = self.wait_value(
            "host room code",
            lambda: host.room_code,
            timeout=40,
            clients=(host,),
        )
        guest = self._start_client("guest", relay_url, str(room))
        self.wait_condition(
            "both peers report the same room and slots [1, 2]",
            lambda states: (
                all(state.get("session_ready") for state in states.values())
                and {state.get("room") for state in states.values()} == {room}
                and all(state.get("occupied_slots") == [1, 2] for state in states.values())
            ),
            timeout=40,
        )

    def _start_client(self, role: str, relay_url: str, room: str = "") -> Client:
        xdg = self.run_dir / f".xdg-{role}"
        xdg.mkdir()
        self.xdg_dirs.append(xdg)
        env = os.environ.copy()
        env["XDG_DATA_HOME"] = str(xdg)
        cmd = shlex.split(self.args.godot) + [
            "--headless",
            "--path",
            str(REPO),
            HARNESS_SCENE,
            "--",
            "--role",
            role,
            "--relay-url",
            relay_url,
            "--run-dir",
            str(self.run_dir),
            "--seed",
            str(self.args.seed),
        ]
        if room:
            cmd += ["--code", room]
        client = Client(role, cmd, env, self.run_dir)
        self.clients[role] = client
        return client

    def wait_value(
        self,
        label: str,
        supplier: Callable[[], object],
        timeout: float,
        clients: tuple[Client, ...] | None = None,
    ) -> object:
        deadline = self.deadline(timeout)
        watched = clients or tuple(self.clients.values())
        while time.monotonic() < deadline:
            for client in watched:
                client.assert_alive()
            value = supplier()
            if value:
                return value
            time.sleep(0.05)
        raise HarnessFailure(f"timeout waiting for {label}")

    def states(self) -> dict[str, dict]:
        return {role: client.state() for role, client in self.clients.items()}

    def wait_condition(
        self,
        label: str,
        predicate: Callable[[dict[str, dict]], bool],
        timeout: float | None = None,
        diagnostic: Callable[[dict[str, dict]], str] | None = None,
    ) -> dict[str, dict]:
        deadline = self.deadline(timeout or self.args.timeout)
        last: dict[str, dict] = {}
        while time.monotonic() < deadline:
            for client in self.clients.values():
                client.assert_alive()
            last = self.states()
            if len(last) == 2 and all(last.values()) and predicate(last):
                return last
            time.sleep(0.05)
        atomic_json(self.run_dir / "timeout-state.json", last)
        detail = f"; {diagnostic(last)}" if diagnostic else ""
        raise HarnessFailure(
            f"timeout waiting for {label}{detail}; last states saved to timeout-state.json"
        )

    def command(self, role: str, action: str, payload: dict | None = None) -> dict:
        client = self.clients[role]
        self.seq[role] += 1
        seq = self.seq[role]
        atomic_json(client.command_path, {"seq": seq, "action": action, "args": payload or {}})
        ack = self.wait_value(
            f"{role} ack {seq} ({action})",
            lambda: (value if int((value := read_json(client.ack_path)).get("seq", 0)) == seq else None),
            timeout=self.args.timeout,
        )
        assert isinstance(ack, dict)
        if not ack.get("ok"):
            raise HarnessFailure(f"{role}: {action} rejected: {ack.get('error', 'unknown error')}")
        return ack

    def command_both(self, action: str) -> None:
        # Commands are independent and setup-only; game actions are always sent to the acting peer.
        self.command("host", action)
        self.command("guest", action)

    @staticmethod
    def _unit(states: dict[str, dict], role: str, unit: str) -> dict:
        return states.get(role, {}).get("units", {}).get(unit, {})

    def require_unit_value(
        self, states: dict[str, dict], unit: str, prop: str, expected: object
    ) -> bool:
        return all(self._unit(states, role, unit).get(prop) == expected for role in ("host", "guest"))

    def unit_diagnostic(
        self, states: dict[str, dict], unit: str, prop: str, expected: object
    ) -> str:
        for role in ("host", "guest"):
            actual = self._unit(states, role, unit).get(prop, "<missing>")
            if actual != expected:
                return f"{role} unit {unit} property {prop}: expected {expected!r}, got {actual!r}"
        return f"unit {unit} property {prop} reached {expected!r}; another condition did not converge"

    def checkpoint(self, name: str, states: dict[str, dict] | None = None) -> None:
        states = self.stable_states(states)
        host_core = {key: states["host"].get(key) for key in ("round", "units")}
        guest_core = {key: states["guest"].get(key) for key in ("round", "units")}
        if host_core != guest_core:
            detail = first_difference(host_core, guest_core)
            raise HarnessFailure(f"{name}: state divergence, {detail}")
        record = {"name": name, "host": states["host"], "guest": states["guest"]}
        self.checkpoints.append(record)
        atomic_json(self.run_dir / f"{len(self.checkpoints):02d}-{name}.json", record)
        print(f"[mp2] PASS {name}")

    def stable_states(
        self, initial: dict[str, dict] | None = None, stable_for: float = 0.35, timeout: float = 5.0
    ) -> dict[str, dict]:
        """Wait until complete snapshots stop changing after their action predicate passed."""
        previous = initial or self.states()
        stable_since = time.monotonic()
        deadline = self.deadline(timeout)
        while time.monotonic() < deadline:
            for client in self.clients.values():
                client.assert_alive()
            current = self.states()
            if current != previous:
                previous = current
                stable_since = time.monotonic()
            elif time.monotonic() - stable_since >= stable_for:
                return current
            time.sleep(0.05)
        raise HarnessFailure("snapshots did not become quiescent within 5s")

    def scenario(self) -> None:
        self.scenario_deadline = time.monotonic() + self.args.timeout
        self.command_both("setup")
        states = self.wait_condition(
            "fixture on both peers", lambda s: all(v.get("fixture_ready") for v in s.values())
        )
        self.checkpoint("fixture", states)

        self.command("host", "place_spell")
        states = self.wait_condition(
            "spell token and modifier on both peers",
            lambda s: self.require_unit_value(s, "mp2_spell", "spell_records", 1)
            and all("Harness Round Buff" in self._unit(s, r, "mp2_spell").get("markers", [[]])[0]
                    for r in ("host", "guest")),
        )
        self.checkpoint("spell-placed", states)

        self.command("host", "advance_round")
        states = self.wait_condition(
            "round-duration spell expired on both peers",
            lambda s: all(v.get("round") == 2 for v in s.values())
            and self.require_unit_value(s, "mp2_spell", "spell_records", 0)
            and all("Harness Round Buff" not in self._unit(s, r, "mp2_spell").get("markers", [[]])[0]
                    for r in ("host", "guest")),
            diagnostic=lambda s: self.unit_diagnostic(s, "mp2_spell", "spell_records", 0),
        )
        self.checkpoint("spell-expired", states)

        self.command("host", "set_fatigue")
        states = self.wait_condition(
            "fatigue set on both peers",
            lambda s: self.require_unit_value(s, "mp2_fatigue", "fatigued", True),
        )
        self.checkpoint("fatigue-set", states)

        self.command("host", "advance_round")
        states = self.wait_condition(
            "fatigue cleared on both peers",
            lambda s: all(v.get("round") == 3 for v in s.values())
            and self.require_unit_value(s, "mp2_fatigue", "fatigued", False),
            diagnostic=lambda s: self.unit_diagnostic(s, "mp2_fatigue", "fatigued", False),
        )
        self.checkpoint("fatigue-cleared", states)

        self.command_both("enable_growth")
        states = self.wait_condition(
            "growth carrier enabled on both peers",
            lambda s: self.require_unit_value(s, "mp2_growth", "in_reserve", False)
            and self.require_unit_value(s, "mp2_growth", "growth", 0),
        )
        self.checkpoint("growth-enabled", states)

        for expected_round, expected_growth in ((4, 1), (5, 2)):
            self.command("host", "advance_round")
            states = self.wait_condition(
                f"growth {expected_growth} on both peers",
                lambda s, rnd=expected_round, growth=expected_growth: (
                    all(v.get("round") == rnd for v in s.values())
                    and self.require_unit_value(s, "mp2_growth", "growth", growth)
                ),
                diagnostic=lambda s, growth=expected_growth: self.unit_diagnostic(
                    s, "mp2_growth", "growth", growth
                ),
            )
            self.checkpoint(f"growth-{expected_growth}", states)

        self.command("host", "hover_los")
        self.command("guest", "hover_los")
        states = self.wait_condition(
            "LOS line and label visible on both peers",
            lambda s: all(v.get("los", {}).get("visible") and v.get("los", {}).get("label_visible")
                          and "/1 sight" in v.get("los", {}).get("text", "") for v in s.values()),
        )
        self.checkpoint("los-human-target", states)

        if self.args.include_transport:
            self.command("host", "embark")
            states = self.wait_condition(
                "embark activation synchronized",
                lambda s: self.require_unit_value(s, "mp2_cargo", "transport", "mp2_transport")
                and self.require_unit_value(s, "mp2_cargo", "activated", True),
            )
            self.checkpoint("transport-embarked", states)
            self.command("host", "disembark")
            states = self.wait_condition(
                "second transport move refused",
                lambda s: self.require_unit_value(s, "mp2_cargo", "transport", "mp2_transport")
                and self.require_unit_value(s, "mp2_cargo", "activated", True),
            )
            self.checkpoint("transport-second-move-refused", states)

        atomic_json(self.run_dir / "snapshots.json", self.checkpoints)

    def stop(self) -> None:
        for role in ("host", "guest"):
            if role in self.clients and self.clients[role].proc.poll() is None:
                try:
                    self.seq[role] += 1
                    atomic_json(
                        self.clients[role].command_path,
                        {"seq": self.seq[role], "action": "quit", "args": {}},
                    )
                except OSError:
                    pass
        for client in self.clients.values():
            try:
                client.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                kill_group(client.proc)
            client.close_log()
            fatal = client.fatal_log_line()
            if fatal and self.shutdown_failure is None:
                self.shutdown_failure = f"{client.role}: script error in log: {fatal}"
        kill_group(self.relay)
        if self.relay_log:
            self.relay_log.close()
        for directory in self.xdg_dirs:
            shutil.rmtree(directory, ignore_errors=True)


def first_difference(left: object, right: object, path: str = "state") -> str:
    if type(left) is not type(right):
        return f"{path}: host={left!r}, guest={right!r}"
    if isinstance(left, dict):
        for key in sorted(set(left) | set(right)):
            if key not in left or key not in right:
                return f"{path}.{key}: host={left.get(key)!r}, guest={right.get(key)!r}"
            if left[key] != right[key]:
                return first_difference(left[key], right[key], f"{path}.{key}")
    elif isinstance(left, list):
        for index, (lvalue, rvalue) in enumerate(zip(left, right)):
            if lvalue != rvalue:
                return first_difference(lvalue, rvalue, f"{path}[{index}]")
        if len(left) != len(right):
            return f"{path}.length: host={len(left)}, guest={len(right)}"
    return f"{path}: host={left!r}, guest={right!r}"


def deterministic_view(checkpoints: list[dict]) -> list[dict]:
    """Remove the relay's deliberately random room code, retaining all test state and logs."""
    value = json.loads(json.dumps(checkpoints))
    for checkpoint in value:
        for role in ("host", "guest"):
            room = checkpoint[role].get("room", "")
            displayed = f"{room[:3]}-{room[3:]}" if len(room) == 6 else room
            if room:
                checkpoint[role]["battle_log_tail"] = [
                    line.replace(displayed, "<room>").replace(room, "<room>")
                    for line in checkpoint[role].get("battle_log_tail", [])
                ]
            checkpoint[role]["room"] = "<room>"
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_CMD", "godot"))
    parser.add_argument("--relay-python", default=sys.executable)
    parser.add_argument("--run-dir", required=True, help="Directory for logs and snapshots.")
    parser.add_argument("--repeat", type=int, default=3, help="Runs to compare (default: 3).")
    parser.add_argument("--seed", type=int, default=240904)
    parser.add_argument("--timeout", type=float, default=120.0, help="Per-scenario timeout.")
    parser.add_argument("--memory-timeout", type=float, default=120.0)
    parser.add_argument("--port", type=int, default=0, help="Relay port; 0 chooses a free port.")
    parser.add_argument(
        "--include-transport",
        action="store_true",
        help="Also run the PR #665 transport scenario (expected to fail before that branch).",
    )
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be at least 1")
    return args


def main() -> int:
    args = parse_args()
    root = Path(args.run_dir).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    reference: list[dict] | None = None
    try:
        for number in range(1, args.repeat + 1):
            run_dir = root / f"run-{number:02d}"
            run_dir.mkdir(parents=True, exist_ok=False)
            run = Run(args, run_dir)
            try:
                print(f"[mp2] run {number}/{args.repeat}: {run_dir}")
                run.start()
                run.scenario()
                view = deterministic_view(run.checkpoints)
                atomic_json(run_dir / "deterministic-snapshots.json", view)
                if reference is None:
                    reference = view
                elif view != reference:
                    detail = first_difference(reference, view, "snapshots")
                    raise HarnessFailure(f"run {number}: snapshots differ from run 1: {detail}")
            finally:
                run.stop()
            if run.shutdown_failure:
                raise HarnessFailure(run.shutdown_failure)
        elapsed = time.monotonic() - start
        atomic_json(root / "determinism.json", {
            "runs": args.repeat, "identical": True, "seed": args.seed,
            "elapsed_seconds": round(elapsed, 3), "snapshots": reference,
        })
        print(f"[mp2] RESULT PASS: {args.repeat} identical run(s), {elapsed:.1f}s")
        return 0
    except (HarnessFailure, OSError, subprocess.SubprocessError) as exc:
        elapsed = time.monotonic() - start
        atomic_json(root / "failure.json", {"error": str(exc), "elapsed_seconds": round(elapsed, 3)})
        print(f"[mp2] RESULT FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run deterministic multiplayer regression scenarios against two real Godot peers."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import select
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
STALL_RE = re.compile(r"\[Relay\] main loop stalled ([0-9.]+)\s*s")
# #675 item 4: the guest's headless scene load blocks its main loop 10.5-10.8 s on EVERY green
# run, so a 5 s hard limit would be permanently red. The assertion enforces the measured baseline
# with headroom instead: 15 s sits ~40% above the worst measured stall and at half the relay's
# 30 s peer timeout — the point where the warning itself says a drop becomes likely.
STALL_LIMIT_S = 15.0
MIN_AVAILABLE_MB = 3500
# Bug 4: one peer's live connection goes silent both ways this long (the live stalls were 13-28 s; a fresh
# socket worked at once). With a takeover relay the peer rejoins after its 10 s silence threshold, so a change
# made during the silence must reach both peers within FAST_LIMIT_S (threshold + a few seconds).
SILENCE_S = 20.0
FAST_LIMIT_S = 15.0
# Step 23: the host's link is cut for this long (the Windows test lost WLAN for ~10 s); the whole
# scenario must converge well inside the 120 s owner-request bound, so LINK_CUT_WAIT_S is the ceiling.
LINK_CUT_S = 10.0
LINK_CUT_WAIT_S = 40.0
## 29(b): how long the guest's link stays dead after the host is already back.
REJOIN_RACE_GUEST_DELAY_S = 12.0


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
    """#675 item 7: probe the relay with a well-formed HTTP GET, not a bare TCP
    connect. The websockets relay logs `ERROR opening handshake failed` for any
    connection that never sends HTTP bytes; a plain GET gets a clean HTTP error
    response (no error log) and tells us the listener is up just as well."""
    deadline = time.monotonic() + timeout
    probe = (
        b"GET / HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\n"
        b"User-Agent: mp-harness-port-probe\r\n"
        b"Connection: close\r\n"
        b"\r\n"
    )
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25) as sock:
                sock.sendall(probe)
                head = sock.recv(64)
            if head.startswith(b"HTTP/"):
                return
            # A listener that answers non-HTTP bytes is still a listener on the
            # port we own; treat it as up rather than spinning to the timeout.
            return
        except OSError:
            time.sleep(0.05)
    raise HarnessFailure(f"relay did not listen on 127.0.0.1:{port} within {timeout:.0f}s")


def worst_stall_s(lines: list[str]) -> float:
    """#675 item 4: the largest '[Relay] main loop stalled Ns' gap in a peer log (0.0 if none)."""
    worst = 0.0
    for line in lines:
        match = STALL_RE.search(line)
        if match:
            worst = max(worst, float(match.group(1)))
    return worst


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


class StallProxy:
    """A TCP proxy between one peer and the relay. freeze(s) stops the CURRENT connection in both directions
    for s seconds (bytes wait in the kernel buffers, as in a stalled Wi-Fi flow); a new connection flows.
    freeze(s, outage=True) also refuses new connections for s seconds (the whole link is down).
    cut(s) is the harder link cut the Windows host saw (WLAN off): every live pair is CLOSED at once and new
    connections are refused until restore(), so the client sees a closed socket, not a silent one."""

    def __init__(self, target_port: int):
        self.target_port = target_port
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(8)
        self.port = int(self.listener.getsockname()[1])
        self.links: list[dict] = []
        self.refuse_until = 0.0
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self) -> None:
        while True:
            try:
                client, _ = self.listener.accept()
                if time.monotonic() < self.refuse_until:
                    client.close()  # link down: the new socket fails at once
                    continue
                upstream = socket.create_connection(("127.0.0.1", self.target_port))
            except OSError:
                return
            link = {"frozen_until": 0.0, "socks": (client, upstream)}
            self.links.append(link)
            for src, dst in ((client, upstream), (upstream, client)):
                threading.Thread(target=self._pump, args=(link, src, dst), daemon=True).start()

    @staticmethod
    def _pump(link: dict, src: socket.socket, dst: socket.socket) -> None:
        try:
            while True:
                if src.fileno() < 0:
                    break  # cut(): another thread closed the pair
                if time.monotonic() < link["frozen_until"]:
                    time.sleep(0.02)
                    continue
                if not select.select([src], [], [], 0.05)[0]:
                    continue
                data = src.recv(65536)
                if not data:
                    break
                dst.sendall(data)
        except (OSError, ValueError):
            pass
        for sock in link["socks"]:
            try:
                sock.close()
            except OSError:
                pass

    def freeze(self, seconds: float, outage: bool = False) -> None:
        if not self.links:
            raise HarnessFailure("stall proxy: the peer has no connection to freeze")
        self.links[-1]["frozen_until"] = time.monotonic() + seconds
        if outage:
            self.refuse_until = time.monotonic() + seconds

    def cut(self, seconds: float) -> None:
        """Cut the link: close every live pair now, refuse new connections for s seconds."""
        self.refuse_until = time.monotonic() + seconds
        self._close_links()

    def restore(self) -> None:
        """Accept connections again (the cut window ends)."""
        self.refuse_until = 0.0

    def _close_links(self) -> None:
        links, self.links = self.links, []
        for link in links:
            for sock in link["socks"]:
                try:
                    sock.close()
                except OSError:
                    pass

    def close(self) -> None:
        self.listener.close()
        self._close_links()


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
        self.rules_online = False
        self.start_question = ""  # "yes" / "no": the host's rules-automation start question
        self.leave = ""  # "menu" = End Battle, "close" = the game window is closed
        self.silence = ""  # bug 4: "host" / "guest" = that peer's connection goes silent (stall proxy)
        self.outage = False  # bug 4: the whole link is down too (new connections fail during the silence)
        self.link_cut = False  # step 23: the host's link is cut and restored (proxy closes the sockets)
        self.rejoin_race = False  # 29(b): both links are cut at once, the host returns first
        self.guest_owed_cut = False  # #1882: the host waits on the guest, then cuts its own link
        self.guest_answers_during_cut = False  # #1882 part 2: the answer is given while the host is away
        self.proxy: StallProxy | None = None
        self.proxies: dict[str, StallProxy] = {}
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
        self.relay_url = relay_url
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
        proxied: tuple[str, ...] = ()
        if self.silence:
            proxied = (self.silence,)
        elif self.rejoin_race:
            proxied = ("host", "guest")  # one relay hiccup takes both links down
        elif self.link_cut or self.guest_owed_cut:
            proxied = ("host",)
        for role in proxied:
            self.proxies[role] = StallProxy(port)
        # The single proxied role's proxy (silence / link-cut); rejoin-race has two and uses
        # self.proxies directly.
        self.proxy = next(iter(self.proxies.values()), None)
        urls = {role: (f"ws://127.0.0.1:{self.proxies[role].port}" if role in self.proxies else relay_url)
                for role in ("host", "guest")}

        host = self._start_client("host", urls["host"])
        room = self.wait_value(
            "host room code",
            lambda: host.room_code,
            timeout=40,
            clients=(host,),
        )
        guest = self._start_client("guest", urls["guest"], str(room))
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
        xdg = self.run_dir / f".xdg-{role}-{len(self.xdg_dirs)}"
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
        if self.link_cut or self.rejoin_race or self.guest_owed_cut:
            cmd += ["--expect-link-cut"]
        if room:
            cmd += ["--code", room]
        if self.rules_online:
            cmd += ["--rules-online"]
        if self.leave:
            cmd += ["--leave"]
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

    def checkpoint(self, name: str, states: dict[str, dict] | None = None,
                   compare_units: bool = True) -> None:
        states = self.stable_states(states)
        keys = ("round", "units", "rules", "turn") if compare_units else ("round", "rules", "turn")
        host_core = {key: states["host"].get(key) for key in keys}
        guest_core = {key: states["guest"].get(key) for key in keys}
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
        if self.start_question:
            self._start_question_scenario()
            return
        if self.leave:
            self.leave_scenario() if self.leave == "menu" else self.close_scenario()
            return
        if self.silence:
            self.silence_scenario()
            return
        if self.link_cut:
            self.link_cut_scenario()
            return
        if self.rejoin_race:
            self.rejoin_race_scenario()
            return
        if self.guest_owed_cut:
            self.guest_owed_cut_scenario()
            return
        self.command_both("setup")
        states = self.wait_condition(
            "fixture on both peers", lambda s: all(v.get("fixture_ready") for v in s.values())
        )
        self.checkpoint("fixture", states)
        # Bug 5: one join = one handshake (the guest announced on connected_to_server AND room_joined,
        # and each pass pushed the full state and the biome again).
        passes = [line for line in self.clients["host"].lines if "passed handshake" in line]
        if len(passes) != 1:
            raise HarnessFailure(f"one join must be one handshake; the host logged {len(passes)}: {passes}")

        if self.rules_online:
            self._rules_online_scenario()
            atomic_json(self.run_dir / "snapshots.json", self.checkpoints)
            return

        # Combat effects in co-op: five cues from the resolving peer, drawn exactly once on each side.
        self.command("host", "vfx_burst")
        states = self.wait_condition(
            "five combat-effect cues drawn on both peers",
            lambda s: all(v.get("vfx_cues") == 5 for v in s.values()),
            diagnostic=lambda s: "vfx_cues: " + repr({r: s[r].get("vfx_cues") for r in s}),
        )
        self.command_both("snapshot")
        time.sleep(1.0)
        states = self.wait_condition(
            "still exactly five cues a second later (no duplicate, no echo)",
            lambda s: all(v.get("vfx_cues") == 5 for v in s.values()),
            diagnostic=lambda s: "vfx_cues: " + repr({r: s[r].get("vfx_cues") for r in s}),
        )
        self.checkpoint("vfx-cues-once", states)

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

        # #673 co-op: the AI-slot designation is synced, the defender's owner rolls its own
        # saves, and the faces travel back to the resolving peer.
        self.command("host", "designate_ai")
        states = self.wait_condition(
            "AI-slot designation synced to both peers",
            lambda s: all(v.get("ai_slots") == [3] for v in s.values()),
            diagnostic=lambda s: "ai_slots: " + repr({r: s[r].get("ai_slots") for r in s}),
        )
        self.checkpoint("ai-slot-synced", states)

        self.command("host", "remote_save_attack")
        states = self.wait_condition(
            "save prompt open on the defender's owner while the resolver waits",
            lambda s: s["guest"].get("save_prompt_visible") is True
            and "Waiting for MP2-guest — defense saves vs Harness Blade"
            in s["host"].get("battle_log_tail", []),
            diagnostic=lambda s: "guest_prompt=%r host_tail=%r" % (
                s["guest"].get("save_prompt_visible"), s["host"].get("battle_log_tail"),
            ),
        )
        self.checkpoint("remote-save-prompt", states)

        self.command("guest", "confirm_save")
        states = self.wait_condition(
            "save faces routed back to the resolving peer",
            lambda s: s["host"].get("remote_save_wounds", -1) >= 0
            and any(
                "rolled their defense saves vs Harness Blade" in line
                for line in s["host"].get("battle_log_tail", [])
            ),
            diagnostic=lambda s: "wounds=%r host_tail=%r" % (
                s["host"].get("remote_save_wounds"), s["host"].get("battle_log_tail"),
            ),
        )
        self.checkpoint("remote-saves-rolled", states)

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

    def leave_scenario(self) -> None:
        """Bugs 9+10: the host leaves to the menu (End Battle): the guest is told within 2 s, the host's
        relay peer is closed, a saved-game load works in the next scene, no peer count goes negative."""
        sent = time.time()
        self.command("host", "leave_to_menu")
        deadline = time.monotonic() + 5
        while not self.states()["guest"].get("host_left_at") and time.monotonic() < deadline:
            time.sleep(0.05)
        guest, left = self.states()["guest"], self.states()["host"].get("left_state", {})
        lag = (guest.get("host_left_at") or float("inf")) - sent
        # The guest goes too: a host relay peer that outlived the scene would hand the next scene's
        # NetworkManager a peer_disconnected it never saw connect ("remaining peers: -1").
        self.seq["guest"] += 1
        atomic_json(self.clients["guest"].command_path, {"seq": self.seq["guest"], "action": "quit"})
        self.clients["guest"].proc.wait(timeout=15)
        time.sleep(1.0)
        problems = [msg for bad, msg in (
            (not 0 < lag <= 2.0, f"guest notice after {lag:.2f}s (inf = never; limit 2 s)"),
            (left.get("relay_connected") or left.get("mp_peer_relay"), f"host relay peer survived: {left}"),
            (left.get("load_gate") != 7, f"load after leaving returned {left.get('load_gate')} (7 = allowed, 4 = host-only)"),
            (any("remaining peers: -" in line for c in self.clients.values() for line in c.lines),
             "a peer count went negative"),
        ) if bad]
        if problems:
            raise HarnessFailure("leave: " + "; ".join(problems))
        print(f"[mp2] PASS host-leaves-to-menu (guest notice after {lag:.2f}s)")

    def close_scenario(self) -> None:
        """The host closes the game window on the table: the guest is told within 2 s, as for End Battle."""
        sent = time.time()
        self.seq["host"] += 1
        atomic_json(self.clients["host"].command_path, {"seq": self.seq["host"], "action": "close_window"})
        self.clients["host"].proc.wait(timeout=20)
        deadline = time.monotonic() + 5
        while not self.states()["guest"].get("host_left_at") and time.monotonic() < deadline:
            time.sleep(0.05)
        lag = (self.states()["guest"].get("host_left_at") or float("inf")) - sent
        if not 0 < lag <= 2.0:
            raise HarnessFailure(f"close: guest notice after {lag:.2f}s (inf = never; limit 2 s)")
        print(f"[mp2] PASS host-closes-window (guest notice after {lag:.2f}s)")

    def silence_scenario(self) -> None:
        """Bug 4: one peer's live connection goes silent in both directions for SILENCE_S. On a relay that can
        take over a seat the peer rejoins early: a round advanced 1 s into the silence reaches both peers within
        FAST_LIMIT_S, with the same transport ids and seats, equal state, no extra peer and the hiccup notice.
        On an older relay the client keeps today's behaviour (it waits; nothing else may break).
        Outage: new connections fail too until the silence ends; an early rejoin must keep retrying and the
        session must survive no worse than today (round on both peers within SILENCE_S + 8 s).
        State after the rejoin's full re-sync = round, rules, turn and the table objects by network id on both
        peers. Not the guest's GameUnit list: the fixture's units are plain miniatures, which the state sync
        carries without their GameUnit link (_serialize_object writes game_unit_id only for opr_unit objects)."""
        role = self.silence
        name = f"silence-{role}" + ("-outage" if self.outage else "")
        self.command_both("setup")
        before = self.wait_condition(
            "fixture on both peers", lambda s: all(v.get("fixture_ready") for v in s.values())
        )
        self.checkpoint(f"{name}-fixture", before)
        expect = self.args.silence_expect
        if expect == "auto":
            expect = "fast" if before["host"].get("relay_takeover") else "fallback"
        ids = {r: before[r].get("peer_id") for r in ("host", "guest")}
        units = len(before["host"].get("units", {}))
        objects = before["host"].get("objects", [])
        print(f"[mp2] {name} for {SILENCE_S:.0f}s, expecting {expect} (ids {ids})")
        started = time.monotonic()
        assert self.proxy is not None
        self.proxy.freeze(SILENCE_S, outage=self.outage)
        time.sleep(1.0)
        self.command("host", "advance_round")
        self.wait_condition(
            "the round advanced during the silence reaches both peers",
            lambda s: all(v.get("round") == 2 and v.get("session_ready") for v in s.values()),
            timeout=SILENCE_S + 30.0,
            diagnostic=lambda s: "rounds: " + repr({r: s[r].get("round") for r in s}),
        )
        latency = time.monotonic() - started
        limit = SILENCE_S + 8.0 if self.outage else FAST_LIMIT_S
        lines = self.clients[role].lines
        early = [line for line in lines if "rejoining early" in line]
        print(f"[mp2] {name}: round on both peers after {latency:.1f}s; "
              + " | ".join(line for line in lines if "[Relay] link silent" in line or "early rejoin" in line))
        time.sleep(max(0.0, started + SILENCE_S + 5.0 - time.monotonic()))  # the old flow resumes meanwhile
        after = self.stable_states()
        seen = after[role].get("net_status_seen", [])
        hiccup = "Connection hiccup \u2014 reconnecting\u2026"
        problems = [msg for bad, msg in (
            ({r: after[r].get("peer_id") for r in ids} != ids, f"transport ids changed: {ids} -> "
             + repr({r: after[r].get("peer_id") for r in ids})),
            (after["host"].get("peers") != {"1": 1, "2": 2}, f"host seats: {after['host'].get('peers')}"),
            (any(after[r].get("slot") != (1 if r == "host" else 2) for r in ids), "a seat changed"),
            (len(after["host"].get("units", {})) != units, f"host unit count {units} -> "
             + str(len(after["host"].get("units", {})))),
            (any(after[r].get("objects") != objects for r in ids), f"table objects {objects} -> "
             + repr({r: after[r].get("objects") for r in ids})),
            (any(after["host"].get(k) != after["guest"].get(k) for k in ("round", "rules", "turn")),
             "round/rules/turn differ: " + repr({r: [after[r].get(k) for k in ("round", "rules", "turn")]
                                                 for r in ids})),
            (expect == "fast" and latency > limit, f"round reached both peers after {latency:.1f}s "
             f"(limit {limit:.0f}s)"),
            (expect == "fast" and not early, "no early rejoin logged"),
            (expect == "fast" and "Reconnected" not in seen[seen.index(hiccup) + 1:] if hiccup in seen
             else expect == "fast", f"no hiccup notice followed by Reconnected: {seen}"),
            (expect == "fallback" and bool(early), "an early rejoin on a relay without takeover"),
        ) if bad]
        if problems:
            raise HarnessFailure(f"{name} ({expect}): " + "; ".join(problems))
        atomic_json(self.run_dir / f"{name}-after.json", {"name": f"{name}-after", **after})
        print(f"[mp2] PASS {name} ({expect}): round on both peers after {latency:.1f}s, ids {ids} kept")

    def link_cut_scenario(self) -> None:
        """Step 23 / test 5 on the laptop: the host's link is cut for LINK_CUT_S (the Windows host's
        WLAN off), then restored. Proven here, on the production code path: the host comes back with
        the SAME transport id (the early rejoin retries a dead socket, #1866), and the owner roll the
        guest is waiting for ends well before the 120 s bound (the peer_disconnected release, #1867)."""
        self.command_both("setup")
        states = self.wait_condition(
            "fixture on both peers", lambda s: all(v.get("fixture_ready") for v in s.values())
        )
        self.checkpoint("link-cut-fixture", states)
        # #1873: the room's agreed level must survive the cut, not just "a request".
        self.command_both("set_automatic")
        states = self.wait_condition(
            "both peers AUTOMATIC before the cut",
            lambda s: all(v.get("rules") == 1 for v in s.values()),
            diagnostic=lambda s: "rules: " + repr({r: s[r].get("rules") for r in s}),
        )
        self.command("host", "place_spell")
        states = self.wait_condition(
            "spell token on both peers before the cut",
            lambda s: self.require_unit_value(s, "mp2_spell", "spell_records", 1),
        )
        self.checkpoint("link-cut-spell-placed", states)
        ids = {role: states[role].get("peer_id") for role in ("host", "guest")}
        core = {role: {key: states[role].get(key) for key in ("room", "round", "turn")}
                for role in ("host", "guest")}
        print(f"[mp2] link-cut: ids {ids}, core {core}")
        # The guest resolves an attack on a HOST unit, so the save prompt and the pending owner
        # request sit on the host; cutting the host's link is the side that owes the answer.
        self.command("guest", "remote_save_attack")
        states = self.wait_condition(
            "the host owes the owner roll",
            lambda s: s["host"].get("save_prompt_visible") is True
            and s["guest"].get("remote_save_wounds", -1) == -1,
            diagnostic=lambda s: "host prompt=%r guest wounds=%r" % (
                s["host"].get("save_prompt_visible"), s["guest"].get("remote_save_wounds")),
        )
        self.checkpoint("link-cut-pending", states)
        assert self.proxy is not None
        started = time.monotonic()
        self.proxy.cut(LINK_CUT_S)
        print(f"[mp2] link-cut: host link cut for {LINK_CUT_S:.0f}s")
        time.sleep(LINK_CUT_S)
        self.proxy.restore()
        states = self.wait_condition(
            "the host rejoined with the owner prompt still open",
            lambda s: ("relay_reconnected" in [e.get("e") for e in s["host"].get("link_events", [])]
                       or "host_rejoined" in [e.get("e") for e in s["host"].get("link_events", [])])
            and s["host"].get("session_ready") and s["guest"].get("session_ready")
            and s["host"].get("save_prompt_visible") is True
            and s["guest"].get("remote_save_wounds", -1) == -1,
            timeout=LINK_CUT_WAIT_S,
            diagnostic=lambda s: "host events=%r prompt=%r guest wounds=%r ready=%r" % (
                [e.get("e") for e in s["host"].get("link_events", [])],
                s["host"].get("save_prompt_visible"),
                s["guest"].get("remote_save_wounds"),
                {r: s[r].get("session_ready") for r in ("host", "guest")}),
        )
        # The owner is BACK, so the request must NOT have been dropped: the host still owes the
        # roll and answers it now (test 5: "the roll was not made afterwards"). A release without
        # an answer is only right when the owner is gone for good (_on_relay_reconnect_failed),
        # covered by e2e_owner_roll_seam_test.
        self.command("host", "confirm_save")
        states = self.wait_condition(
            "the host's faces reach the waiting guest after the rejoin",
            lambda s: s["guest"].get("remote_save_wounds", -1) >= 0
            and not s["guest"].get("failed") and not s["host"].get("failed"),
            timeout=LINK_CUT_WAIT_S,
            diagnostic=lambda s: "guest wounds=%r failed=%r" % (
                s["guest"].get("remote_save_wounds"), s["guest"].get("failed")),
        )
        elapsed = time.monotonic() - started
        time.sleep(1.0)
        after = self.stable_states()
        events = {role: [e.get("e") for e in after[role].get("link_events", [])]
                  for role in ("host", "guest")}
        problems = [msg for bad, msg in (
            ("relay_reconnecting" not in events["host"], f"no rejoin start on the host: {events['host']}"),
            (any(after[r].get("rules") != 1 for r in ids),
             "the agreed rules level was lost: " + repr({r: after[r].get("rules") for r in ids})),
            ({r: after[r].get("peer_id") for r in ids} != ids,
             f"transport ids changed: {ids} -> " + repr({r: after[r].get("peer_id") for r in ids})),
            (after["host"].get("slot") != 1 or after["guest"].get("slot") != 2, "a seat changed"),
            ({r: {k: after[r].get(k) for k in ("round", "turn")} for r in ids}
             != {r: {k: core[r][k] for k in ("round", "turn")} for r in ids},
             "round/turn changed: " + repr({r: (after[r].get("round"), after[r].get("turn"))
                                           for r in ids})),
            (any(after[r].get("room") != core[r]["room"] for r in ids),
             "a room changed: " + repr({r: after[r].get("room") for r in ids})),
            (after["guest"].get("failed") or "internet_disconnected" in events["guest"],
             f"the guest lost the session: {events['guest']}"),
            (elapsed >= LINK_CUT_WAIT_S,
             f"the request took {elapsed:.1f}s (limit {LINK_CUT_WAIT_S:.0f}s)"),
        ) if bad]
        if problems:
            raise HarnessFailure("link-cut: " + "; ".join(problems))
        # Not the unit map: the fixture's plain miniatures lose their GameUnit link on the rejoin's
        # full-state rebuild (slot-3 AI unit absent on the guest) — a harness seam, logged in the PR.
        self.checkpoint("after_link_cut", after, compare_units=False)
        print(f"[mp2] PASS link-cut: host back with id {ids['host']}, the cut request was answered "
              f"after {elapsed:.1f}s, events {events['host']}")

    def guest_owed_cut_scenario(self) -> None:
        """#1882: the HOST waits on the GUEST (interference for a cast) and then the HOST's link is
        cut for LINK_CUT_S. The relay re-adds peer 2 with a reused-id flush when the host rejoins;
        that flush used to release the pending request (a rejoin read as a leave). With the fix the
        request survives, the guest's answer still lands, and a seated guest is never auto-rolled."""
        self.command_both("setup")
        states = self.wait_condition(
            "fixture on both peers", lambda s: all(v.get("fixture_ready") for v in s.values())
        )
        self.command_both("set_automatic")
        states = self.wait_condition(
            "both peers AUTOMATIC before the ask",
            lambda s: all(v.get("rules") == 1 for v in s.values()),
            diagnostic=lambda s: "rules: " + repr({r: s[r].get("rules") for r in s}),
        )
        self.checkpoint("guest-owed-fixture", states)
        self.command("host", "remote_interference")
        states = self.wait_condition(
            "the guest is asked to interfere",
            lambda s: s["guest"].get("interference_open") is True,
            diagnostic=lambda s: "guest card=%r host log tail=%r" % (
                s["guest"].get("interference_open"), self.clients["host"].lines[-3:]),
        )
        self.checkpoint("guest-owed-pending", states, compare_units=False)
        assert self.proxy is not None
        started = time.monotonic()
        self.proxy.cut(LINK_CUT_S)
        print(f"[mp2] guest-owed-cut: host link cut for {LINK_CUT_S:.0f}s with the ask in flight")
        if self.guest_answers_during_cut:
            # #1882 part 2: the guest answers while the host's socket is gone - the relay drops the
            # reply frame on the floor. The host must re-send the request after its rejoin and take
            # the guest's stored answer, not wait out the 120 s owner bound.
            time.sleep(1.0)
            self.command("guest", "answer_interference")
            self.wait_condition(
                "the guest answered during the host outage",
                lambda s: s["guest"].get("interference_open") is False,
                timeout=10.0,
                diagnostic=lambda s: "guest card=%r" % s["guest"].get("interference_open"),
            )
            print("[mp2] guest-owed-cut: the guest answered during the host outage")
            time.sleep(max(0.0, LINK_CUT_S - 1.0))
        else:
            time.sleep(LINK_CUT_S)
        self.proxy.restore()
        self.wait_condition(
            "the host rejoined",
            lambda s: "host_rejoined" in [e.get("e") for e in s["host"].get("link_events", [])]
            and s["host"].get("session_ready"),
            timeout=LINK_CUT_WAIT_S,
            diagnostic=lambda s: "host events=%r ready=%r" % (
                [e.get("e") for e in s["host"].get("link_events", [])],
                s["host"].get("session_ready")),
        )
        if not self.guest_answers_during_cut:
            self.command("guest", "answer_interference")
        states = self.wait_condition(
            "the host took the guest's stored answer after the rejoin" if self.guest_answers_during_cut
            else "the host took the guest's interference",
            lambda s: s["host"].get("interference_spent") == 1,
            timeout=LINK_CUT_WAIT_S,
            diagnostic=lambda s: "spent=%r host log tail=%r" % (
                s["host"].get("interference_spent"), self.clients["host"].lines[-5:]),
        )
        elapsed = time.monotonic() - started
        time.sleep(1.0)
        after = self.stable_states()
        # The reply value is the whole proof: 1 = the guest's real token arrived after the rejoin;
        # the release/timeout paths return 0 ("no answer"), the fallback never asks at all.
        problems = [msg for bad, msg in (
            (after["guest"].get("slot") != 2, "the guest lost its seat: %r"
             % after["guest"].get("slot")),
            (after["guest"].get("interference_open") is True, "the guest's card stayed open"),
            (after["host"].get("interference_spent") != 1, "the answer did not reach the cast: %r"
             % after["host"].get("interference_spent")),
            (elapsed >= LINK_CUT_WAIT_S, f"the ask took {elapsed:.1f}s (limit {LINK_CUT_WAIT_S:.0f}s)"),
        ) if bad]
        if problems:
            raise HarnessFailure("guest-owed-cut: " + "; ".join(problems))
        self.checkpoint("after_guest_owed_cut", after, compare_units=False)
        print(f"[mp2] PASS guest-owed-cut: the guest's interference survived the host rejoin "
              f"(spent 1) after {elapsed:.1f}s")

    def rejoin_race_scenario(self) -> None:
        """29(b): BOTH links die in the same relay hiccup, the host comes back first and the guest is
        still mid-rejoin — the live order behind "Peer 2 failed version handshake (no announce in
        8s) — kicking". The guest must end seated on slot 2 with the agreed rules level; the host
        must not log a kick. The guest's proxy stays closed for REJOIN_RACE_GUEST_DELAY_S after the
        host is back, so the host really does wait for a peer that cannot announce yet."""
        self.command_both("setup")
        states = self.wait_condition(
            "fixture on both peers", lambda s: all(v.get("fixture_ready") for v in s.values())
        )
        self.command_both("set_automatic")
        states = self.wait_condition(
            "both peers AUTOMATIC before the cut",
            lambda s: all(v.get("rules") == 1 for v in s.values()),
            diagnostic=lambda s: "rules: " + repr({r: s[r].get("rules") for r in s}),
        )
        self.checkpoint("rejoin-race-ready", states)
        ids = {role: states[role].get("peer_id") for role in ("host", "guest")}
        started = time.monotonic()
        for role in ("host", "guest"):
            self.proxies[role].cut(LINK_CUT_S)
        print(f"[mp2] rejoin-race: both links cut for {LINK_CUT_S:.0f}s")
        time.sleep(LINK_CUT_S)
        # The host returns first; the guest's link stays dead, as in the live run.
        self.proxies["host"].restore()
        self.wait_condition(
            "the host rejoined",
            lambda s: "host_rejoined" in [e.get("e") for e in s["host"].get("link_events", [])]
            and s["host"].get("session_ready"),
            timeout=LINK_CUT_WAIT_S,
            diagnostic=lambda s: "host events=%r ready=%r failed=%r" % (
                [e.get("e") for e in s["host"].get("link_events", [])],
                s["host"].get("session_ready"), s["host"].get("failed")),
        )
        time.sleep(REJOIN_RACE_GUEST_DELAY_S)
        self.proxies["guest"].restore()
        states = self.wait_condition(
            "both peers seated after the race",
            lambda s: s["guest"].get("session_ready") and s["guest"].get("slot") == 2
            and s["host"].get("session_ready") and s["host"].get("slot") == 1,
            timeout=LINK_CUT_WAIT_S,
            diagnostic=lambda s: "guest ready=%r slot=%r events=%r host slot=%r" % (
                s["guest"].get("session_ready"), s["guest"].get("slot"),
                [e.get("e") for e in s["guest"].get("link_events", [])],
                s["host"].get("slot")),
        )
        elapsed = time.monotonic() - started
        time.sleep(1.0)
        after = self.stable_states()
        kicked = [line for line in self.clients["host"].lines if "failed version handshake" in line]
        events = {role: [e.get("e") for e in after[role].get("link_events", [])]
                  for role in ("host", "guest")}
        problems = [msg for bad, msg in (
            (bool(kicked), f"the host kicked the rejoining guest: {kicked[:1]}"),
            (after["guest"].get("slot") != 2, "the guest lost its seat: slot %r"
             % after["guest"].get("slot")),
            ({r: after[r].get("peer_id") for r in ids} != ids,
             "a transport id changed: " + repr({r: after[r].get("peer_id") for r in ids})),
            (any(after[r].get("rules") != 1 for r in ids),
             "the agreed rules level was lost: " + repr({r: after[r].get("rules") for r in ids})),
            (after["host"].get("failed") or after["guest"].get("failed"), "a peer is failed"),
            (elapsed >= LINK_CUT_WAIT_S, f"the race took {elapsed:.1f}s (limit {LINK_CUT_WAIT_S:.0f}s)"),
        ) if bad]
        if problems:
            raise HarnessFailure("rejoin-race: " + "; ".join(problems))
        self.checkpoint("after_rejoin_race", after, compare_units=False)
        print(f"[mp2] PASS rejoin-race: guest seated on slot 2 after {elapsed:.1f}s, "
              f"events host {events['host']} guest {events['guest']}")

    def _start_question_scenario(self) -> None:
        """Bug 6c: the host is asked ONCE whether to play with rules automation when the second player
        sits down. Yes -> the guest gets the confirm card -> both Automatic; Not now -> both Manual and
        no card on the guest; a guest rejoin never asks again."""
        yes = self.start_question == "yes"
        self.wait_condition(
            "the host is asked, the guest is not",
            lambda s: s["host"].get("start_question_visible") and not s["guest"].get("start_question_visible"),
            diagnostic=lambda s: "host asked: " + repr(s["host"].get("start_question_count")),
        )
        self.command("host", "answer_start_question", {"yes": yes})
        if yes:
            self.wait_condition(
                "the guest sees the confirm card",
                lambda s: s["guest"].get("rules_card_visible") and not s["host"].get("start_question_visible"),
            )
            self.command("guest", "answer_rules_card", {"yes": True})
            self.wait_condition(
                "both sides Automatic",
                lambda s: all(v.get("rules") == 1 for v in s.values()),
                diagnostic=lambda s: "rules: " + repr({r: s[r].get("rules") for r in s}),
            )
        else:
            time.sleep(2.0)
            states = self.states()
            if states["guest"].get("rules_card_visible") or any(v.get("rules") != 0 for v in states.values()):
                raise HarnessFailure("Not now must leave both Manual with no card on the guest: " + repr(
                    {r: (v.get("rules"), v.get("rules_card_visible")) for r, v in states.items()}))
        # The guest leaves and comes back: same room, no second question.
        room = self.states()["host"]["room"]
        self.command("guest", "close_window")
        old = self.clients["guest"]
        old.proc.wait(timeout=15)
        for suffix in (".state.json", ".ack.json", ".command.json"):
            (self.run_dir / f"guest{suffix}").unlink(missing_ok=True)
        old.close_log()
        self.seq["guest"] = 0
        self._start_client("guest", self.relay_url, str(room))
        self.wait_condition(
            "the guest is back at the table",
            lambda s: s["guest"].get("session_ready") and s["host"].get("occupied_slots") == [1, 2],
        )
        time.sleep(3.0)
        states = self.states()
        if states["host"].get("start_question_count") != 1 or states["host"].get("start_question_visible"):
            raise HarnessFailure("a rejoin asked again: count=%r" % states["host"].get("start_question_count"))
        if yes:
            states = self.wait_condition(
                "the agreed Automatic level survives the rejoin on both sides",
                lambda s: all(v.get("rules") == 1 for v in s.values()),
                timeout=15,
                diagnostic=lambda s: "rules: " + repr({r: s[r].get("rules") for r in s}),
            )
        print(f"[mp2] PASS start-question-{self.start_question} (asked once, rejoin silent)")

    def _rules_online_scenario(self) -> None:
        """Plan 3.6: the agreed Automatic online room. A full exchange with enforced alternation —
        out-of-turn refusal, hand-over, TAIL and one automatic round end — peer-state equality after
        every step. Two units a side at first: P1 x3, P2 x1, so P1 keeps activating once P2 is spent
        (TAIL) and the round closes on the host."""
        self.command_both("set_automatic")
        states = self.wait_condition(
            "agreed Automatic room on both peers, P1 opens",
            lambda s: all(v.get("rules") == 1 and v.get("turn") == 1 for v in s.values()),
            diagnostic=lambda s: "rules/turn: " + repr(
                {r: (s[r].get("rules"), s[r].get("turn")) for r in s}
            ),
        )
        self.checkpoint("rules-online-automatic", states)

        self.command("host", "activate", {"unit": "mp2_p1a", "slot": 1})
        states = self.wait_condition(
            "the token handed to P2 on both peers",
            lambda s: all(v.get("turn") == 2 for v in s.values())
            and all("P2 to activate" in v.get("battle_log_tail", []) for v in s.values()),
            diagnostic=lambda s: "turn: " + repr({r: s[r].get("turn") for r in s}),
        )
        self.checkpoint("rules-online-handover", states)

        self.command("host", "activate", {"unit": "mp2_p1b", "slot": 1})
        states = self.wait_condition(
            "P1 refused off turn, nothing changed",
            lambda s: s["host"].get("last_refusal") == "It is P2's turn"
            and s["host"].get("turn") == 2
            and self._unit(s, "host", "mp2_p1b").get("activated") is False,
            diagnostic=lambda s: "host refusal=%r turn=%r p1b=%r" % (
                s["host"].get("last_refusal"), s["host"].get("turn"),
                self._unit(s, "host", "mp2_p1b").get("activated"),
            ),
        )
        self.checkpoint("rules-online-out-of-turn-refused", states)

        self.command("guest", "activate", {"unit": "mp2_p2a", "slot": 2})
        states = self.wait_condition(
            "the guest's activation fact hand the token back to P1",
            lambda s: all(v.get("turn") == 1 for v in s.values())
            and all("P1 to activate" in v.get("battle_log_tail", []) for v in s.values()),
            diagnostic=lambda s: "turn: " + repr({r: s[r].get("turn") for r in s}),
        )
        self.checkpoint("rules-online-handover-back", states)

        self.command("host", "activate", {"unit": "mp2_p1b", "slot": 1})
        states = self.wait_condition(
            "P2 spent: P1 keeps activating (TAIL)",
            lambda s: all(v.get("turn") == 1 for v in s.values())
            and all("P2 has no units left \u2014 P1 keeps activating" in v.get("battle_log_tail", [])
                    for v in s.values()),
            diagnostic=lambda s: "turn: " + repr({r: s[r].get("turn") for r in s}),
        )
        self.checkpoint("rules-online-tail", states)

        self.command("host", "activate", {"unit": "mp2_p1c", "slot": 1})
        states = self.wait_condition(
            "one automatic round end, opener P2, on both peers",
            lambda s: all(v.get("round") == 2 for v in s.values())
            and all(v.get("turn") == 2 for v in s.values()),
            diagnostic=lambda s: "round/turn: " + repr(
                {r: (s[r].get("round"), s[r].get("turn")) for r in s}
            ),
        )
        self.checkpoint("rules-online-round-end", states)

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
            stall = worst_stall_s(client.lines)
            if stall > STALL_LIMIT_S and self.shutdown_failure is None:
                self.shutdown_failure = (
                    f"{client.role}: main-loop stall {stall:.1f}s exceeds the "
                    f"{STALL_LIMIT_S:.0f}s baseline (relay drops peers near 30s)"
                )
        if self.proxy is not None:
            self.proxy.close()
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
            checkpoint[role].pop("net_status_seen", None)  # timing-dependent connect texts
            checkpoint[role].pop("objects", None)  # bug 4 silence scenario only
            checkpoint[role].pop("link_events", None)  # step 23: wall-clock rejoin events
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
    parser.add_argument(
        "--include-rules-online",
        action="store_true",
        help="Also run the plan 3.6 rules-online alternation gate (agreed Automatic room).",
    )
    parser.add_argument(
        "--start-question",
        action="store_true",
        help="Run only the bug 6c scenarios (host start question: yes, no; guest rejoin).",
    )
    parser.add_argument(
        "--silence-only",
        action="store_true",
        help="Run only the bug 4 silence scenarios (host, guest).",
    )
    parser.add_argument(
        "--include-link-cut",
        action="store_true",
        help="Also run step 23: the host's link is cut for LINK_CUT_S and restored (merge proof for #1866/#1867).",
    )
    parser.add_argument(
        "--link-cut-only",
        action="store_true",
        help="Run only step 23 (the host's link cut); used for the RED/GREEN proof.",
    )
    parser.add_argument(
        "--guest-owed-cut",
        action="store_true",
        help="Run only #1882: the host waits on the guest's interference, then the host's link is cut.",
    )
    parser.add_argument(
        "--guest-answers-during-cut",
        action="store_true",
        help="#1882 part 2: the guest answers while the host is cut; after the rejoin the host must "
             "take the guest's stored answer instead of waiting out the 120 s owner bound.",
    )
    parser.add_argument(
        "--rejoin-race",
        action="store_true",
        help="Run only 29(b): both links are cut at once, the host returns first, the guest must stay seated.",
    )
    parser.add_argument(
        "--silence-expect",
        choices=("auto", "fast", "fallback"),
        default="auto",
        help="auto = fast when the relay advertises seat takeover, else today's behaviour.",
    )
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be at least 1")
    if args.guest_answers_during_cut:
        args.guest_owed_cut = True
    return args


def main() -> int:
    args = parse_args()
    root = Path(args.run_dir).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    reference: list[dict] | None = None

    def run_once(run_dir: Path, rules_online: bool, ref: list[dict] | None, leave: str = "",
                 silence: str = "", outage: bool = False, link_cut: bool = False,
                 rejoin_race: bool = False, guest_owed_cut: bool = False,
                 guest_answers_during_cut: bool = False) -> list[dict]:
        run_dir.mkdir(parents=True, exist_ok=False)
        run = Run(args, run_dir)
        run.rules_online = rules_online
        run.leave = leave
        run.silence = silence
        run.outage = outage
        run.link_cut = link_cut
        run.rejoin_race = rejoin_race
        run.guest_owed_cut = guest_owed_cut
        run.guest_answers_during_cut = guest_answers_during_cut
        try:
            print(f"[mp2] run {run_dir.name}: {run_dir}")
            run.start()
            run.scenario()
            view = deterministic_view(run.checkpoints)
            atomic_json(run_dir / "deterministic-snapshots.json", view)
            if ref is None:
                ref = view
            elif view != ref:
                detail = first_difference(ref, view, "snapshots")
                raise HarnessFailure(f"{run_dir.name}: snapshots differ from the first run: {detail}")
        finally:
            run.stop()
        if run.shutdown_failure:
            raise HarnessFailure(run.shutdown_failure)
        return ref if ref is not None else view

    try:
        if args.link_cut_only:
            run_once(root / "link-cut-01", False, None, link_cut=True)
            print("[mp2] RESULT PASS: link cut")
            return 0
        if args.rejoin_race:
            run_once(root / "rejoin-race-01", False, None, rejoin_race=True)
            print("[mp2] RESULT PASS: rejoin race")
            return 0
        if args.guest_owed_cut and not (args.include_rules_online or args.include_link_cut):
            run_once(root / "guest-owed-cut-01", False, None, guest_owed_cut=True,
                     guest_answers_during_cut=args.guest_answers_during_cut)
            print("[mp2] RESULT PASS: guest-owed cut")
            return 0
        if args.start_question:
            for answer in ("yes", "no"):
                run = Run(args, root / f"start-question-{answer}")
                run.run_dir.mkdir(parents=True, exist_ok=False)
                run.start_question = answer
                try:
                    run.start()
                    run.scenario()
                finally:
                    run.stop()
            print("[mp2] RESULT PASS: start question")
            return 0
        if args.silence_only:
            for role in ("host", "guest"):
                run_once(root / f"silence-{role}", False, None, silence=role)
            run_once(root / "silence-host-outage", False, None, silence="host", outage=True)
            print("[mp2] RESULT PASS: silence")
            return 0
        for number in range(1, args.repeat + 1):
            reference = run_once(root / f"run-{number:02d}", False, reference)
        online_reference: list[dict] | None = None
        if args.include_rules_online:
            for number in range(1, args.repeat + 1):
                online_reference = run_once(root / f"rules-online-{number:02d}", True, online_reference)
        run_once(root / "leave-01", False, None, leave="menu")
        run_once(root / "close-01", False, None, leave="close")
        for role in ("host", "guest"):
            run_once(root / f"silence-{role}", False, None, silence=role)
        run_once(root / "silence-host-outage", False, None, silence="host", outage=True)
        if args.include_link_cut:
            run_once(root / "link-cut-01", False, None, link_cut=True)
        if args.guest_owed_cut:
            # #1882 part 2: wall-clock timing, so it stays out of the snapshot comparison above.
            run_once(root / "guest-owed-cut-01", False, None, guest_owed_cut=True,
                     guest_answers_during_cut=args.guest_answers_during_cut)
        elapsed = time.monotonic() - start
        atomic_json(root / "determinism.json", {
            "runs": args.repeat, "identical": True, "seed": args.seed,
            "rules_online": bool(args.include_rules_online),
            "link_cut": bool(args.include_link_cut),
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

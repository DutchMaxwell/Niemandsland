import copy
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path
import unittest
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_two_instance as driver  # noqa: E402


class DriverHelpersTest(unittest.TestCase):
    def test_first_difference_names_nested_property(self):
        left = {"units": {"u1": {"fatigued": False}}}
        right = {"units": {"u1": {"fatigued": True}}}

        self.assertEqual(
            driver.first_difference(left, right),
            "state.units.u1.fatigued: host=False, guest=True",
        )

    def test_deterministic_view_only_replaces_room_code(self):
        raw = [{
            "name": "fixture",
            "host": {"room": "ABC234", "round": 1, "battle_log_tail": ["Room code: ABC-234"]},
            "guest": {"room": "ABC234", "round": 1, "battle_log_tail": ["Room code: ABC-234"]},
        }]
        untouched = copy.deepcopy(raw)

        view = driver.deterministic_view(raw)

        self.assertEqual(view[0]["host"]["room"], "<room>")
        self.assertEqual(view[0]["guest"]["room"], "<room>")
        self.assertEqual(view[0]["host"]["round"], 1)
        self.assertEqual(view[0]["host"]["battle_log_tail"], ["Room code: <room>"])
        self.assertEqual(raw, untouched)

    def test_core_loaded_needs_the_mark_and_no_missing_mark(self):
        self.assertTrue(driver.core_loaded(["x", "core: NmlCore loaded", "y"]))
        self.assertFalse(driver.core_loaded(["x", "y"]))
        self.assertFalse(driver.core_loaded(["core: NmlCore NOT loaded - the decision tree plays; reinstall the game"]))
        self.assertFalse(driver.core_loaded(["core: NmlCore loaded", "core: NmlCore NOT loaded - again"]))

    def test_free_port_returns_a_bindable_local_port(self):
        port = driver.free_port()
        self.assertGreater(port, 0)
        self.assertLessEqual(port, 65535)

    def test_script_error_detector_covers_english_and_german_logs(self):
        self.assertIsNotNone(driver.SCRIPT_ERROR_RE.search("SCRIPT ERROR: invalid call"))
        self.assertIsNotNone(driver.SCRIPT_ERROR_RE.search("SKRIPTFEHLER: ungultiger Aufruf"))

    def test_worst_stall_reads_the_relay_warning_and_enforces_the_baseline(self):
        # #675 item 4: the measured guest baseline (10.5-10.8 s every green run) must stay GREEN
        # under STALL_LIMIT_S; a bigger gap, and a log without any stall line, behave sanely.
        self.assertEqual(driver.worst_stall_s(["MP2: guest joined room ABC234"]), 0.0)
        lines = [
            "Godot Engine v4.6.stable.official - https://godotengine.org",
            "WARNING: [Relay] main loop stalled 10.8s \u2014 heartbeats delayed (can trigger a relay timeout)",
            "WARNING: [Relay] main loop stalled 3.2s \u2014 heartbeats delayed (can trigger a relay timeout)",
        ]
        self.assertEqual(driver.worst_stall_s(lines), 10.8)
        self.assertLessEqual(driver.worst_stall_s(lines), driver.STALL_LIMIT_S)
        self.assertGreater(
            driver.worst_stall_s(["WARNING: [Relay] main loop stalled 15.4s \u2014 heartbeats delayed"]),
            driver.STALL_LIMIT_S,
        )


def echo_server() -> tuple[socket.socket, int]:
    """A local echo target for the proxy tests (each accepted connection is echoed and closed)."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("127.0.0.1", 0))
    server.listen(8)

    def accept_loop() -> None:
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return

            def pump(client: socket.socket = conn) -> None:
                try:
                    while True:
                        data = client.recv(1024)
                        if not data:
                            return
                        client.sendall(data)
                except OSError:
                    pass
                finally:
                    client.close()

            threading.Thread(target=pump, daemon=True).start()

    threading.Thread(target=accept_loop, daemon=True).start()
    return server, int(server.getsockname()[1])


class StallProxyCutTest(unittest.TestCase):
    """Step 23: cut() closes the live pair and refuses new ones; restore() accepts again."""

    def test_cut_closes_the_live_pair_and_restore_accepts_again(self):
        server, target = echo_server()
        proxy = driver.StallProxy(target)
        try:
            client = socket.create_connection(("127.0.0.1", proxy.port), timeout=2)
            client.sendall(b"ping")
            self.assertEqual(client.recv(4), b"ping")

            proxy.cut(0.3)
            try:
                self.assertEqual(client.recv(1), b"")  # the proxy closed the pair
            except ConnectionResetError:
                pass
            client.close()

            refused = socket.create_connection(("127.0.0.1", proxy.port), timeout=1)
            refused.settimeout(1.0)
            try:
                self.assertEqual(refused.recv(1), b"")  # accepted, then closed at once
            except (ConnectionResetError, socket.timeout):
                pass
            refused.close()

            proxy.restore()
            again = socket.create_connection(("127.0.0.1", proxy.port), timeout=2)
            again.settimeout(2.0)
            again.sendall(b"pong")
            self.assertEqual(again.recv(4), b"pong")
            again.close()
        finally:
            proxy.close()
            server.close()

    def test_freeze_still_flows_after_the_window(self):
        server, target = echo_server()
        proxy = driver.StallProxy(target)
        try:
            client = socket.create_connection(("127.0.0.1", proxy.port), timeout=2)
            client.sendall(b"ping")
            self.assertEqual(client.recv(4), b"ping")
            proxy.freeze(0.2)
            client.settimeout(2.0)
            client.sendall(b"held")
            self.assertEqual(client.recv(4), b"held")
            client.close()
        finally:
            proxy.close()
            server.close()


class FakeProc:
    def wait(self, timeout: float | None = None) -> int:
        return 0


class FakeClient:
    """A peer whose state file shows `states[0]` until the harness first sleeps, then `states[1]`:
    the ack was seen, the state file has not landed yet (or is mid-replace and reads as {})."""

    def __init__(self, tmp: Path, role: str, before: dict, after: dict, on_sleep: list) -> None:
        self.role = role
        self.command_path = tmp / f"{role}.command.json"
        self.proc = FakeProc()
        self.lines: list[str] = []
        self._before, self._after, self._on_sleep = before, after, on_sleep

    def state(self) -> dict:
        return self._after if self._on_sleep else self._before

    def assert_alive(self) -> None:
        return None


class LeaveStateRaceTest(unittest.TestCase):
    """The host acks leave_to_menu BEFORE it writes the state file that carries left_state, and that file is
    replaced by remove + rename every 100 ms: a one-shot read right after the ack saw {} or a stale state
    ("leave: load after leaving returned None", PR 2763, and the guest twin "guest notice after inf s")."""

    GOOD = {"left": True, "load_gate": 7, "relay_connected": False, "mp_peer_relay": False}

    def make_run(self, tmp: Path, host_before: dict, host_after: dict, guest: list[dict]):
        argv = ["run_two_instance.py", "--run-dir", str(tmp)]
        with mock.patch.object(sys, "argv", argv):
            run = driver.Run(driver.parse_args(), tmp)
        slept: list[bool] = []
        replies = iter(guest)
        host = FakeClient(tmp, "host", host_before, host_after, slept)
        guest_client = FakeClient(tmp, "guest", {}, {}, slept)
        guest_client.state = lambda: next(replies, {})  # type: ignore[method-assign]
        run.clients = {"host": host, "guest": guest_client}  # type: ignore[dict-item]
        run.command = lambda *a, **k: {"ok": True}  # type: ignore[method-assign]
        run.scenario_deadline = None
        return run, slept

    def run_scenario(self, scenario: str, host_before: dict, host_after: dict, guest: list[dict]) -> None:
        with tempfile.TemporaryDirectory() as raw:
            run, slept = self.make_run(Path(raw), host_before, host_after, guest)

            def fake_sleep(_seconds: float) -> None:
                slept.append(True)

            with mock.patch.object(driver.time, "sleep", fake_sleep):
                getattr(run, scenario)()

    def test_leave_waits_for_the_state_that_follows_the_ack(self):
        noticed = [{"host_left_at": time.time() + 0.1}] * 50
        for label, before in (("state file missing", {}), ("stale state", {"left_state": {}})):
            with self.subTest(label):
                self.run_scenario("leave_scenario", before, {"left_state": self.GOOD}, list(noticed))

    def test_leave_still_fails_on_a_wrong_load_gate(self):
        # The wait must not turn the check into a pass: the answer that arrives is still judged.
        bad = dict(self.GOOD, load_gate=4)
        with self.assertRaises(driver.HarnessFailure) as caught:
            self.run_scenario("leave_scenario", {}, {"left_state": bad}, [{"host_left_at": time.time() + 0.1}] * 50)
        self.assertIn("load after leaving returned 4", str(caught.exception))

    def test_guest_notice_is_not_lost_to_a_second_read_of_a_missing_file(self):
        # Once the guest's state shows host_left_at, a later read that finds the file mid-replace ({}) must
        # not turn the notice into "inf" (never): the value that ended the wait is the one used.
        noticed = [{"host_left_at": time.time() + 0.1}, {}, {}]
        good = {"left_state": self.GOOD}
        self.run_scenario("leave_scenario", good, good, list(noticed))
        self.run_scenario("close_scenario", {}, {}, list(noticed))

    def test_a_guest_that_is_never_told_still_fails(self):
        with self.assertRaises(driver.HarnessFailure) as caught:
            with mock.patch.object(driver.time, "monotonic", side_effect=[0.0, 0.0, 6.0, 6.0, 6.0]):
                self.run_scenario("close_scenario", {}, {}, [{}])
        self.assertIn("guest notice after infs", str(caught.exception))


class LinkCutFlagTest(unittest.TestCase):
    def test_include_link_cut_parses(self):
        argv = ["run_two_instance.py", "--run-dir", "/tmp/mp2", "--include-link-cut"]
        with mock.patch.object(sys, "argv", argv):
            args = driver.parse_args()
        self.assertTrue(args.include_link_cut)

    def test_include_link_cut_defaults_off(self):
        argv = ["run_two_instance.py", "--run-dir", "/tmp/mp2"]
        with mock.patch.object(sys, "argv", argv):
            args = driver.parse_args()
        self.assertFalse(args.include_link_cut)


class GuestAnswersDuringCutFlagTest(unittest.TestCase):
    def test_flag_implies_the_guest_owed_scenario(self):
        argv = ["run_two_instance.py", "--run-dir", "/tmp/mp2", "--guest-answers-during-cut"]
        with mock.patch.object(sys, "argv", argv):
            args = driver.parse_args()
        self.assertTrue(args.guest_answers_during_cut)
        self.assertTrue(args.guest_owed_cut)

    def test_flag_defaults_off(self):
        argv = ["run_two_instance.py", "--run-dir", "/tmp/mp2"]
        with mock.patch.object(sys, "argv", argv):
            args = driver.parse_args()
        self.assertFalse(args.guest_answers_during_cut)
        self.assertFalse(args.guest_owed_cut)


if __name__ == "__main__":
    unittest.main()

import copy
import sys
from pathlib import Path
import unittest


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


if __name__ == "__main__":
    unittest.main()

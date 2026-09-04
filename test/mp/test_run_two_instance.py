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


if __name__ == "__main__":
    unittest.main()

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]


@unittest.skipUnless(shutil.which('blender'), 'Blender is not installed')
class TailFloorTest(unittest.TestCase):
    """A tail that rests on the floor must not dip through it while the hips sway (RED: it did, by 6 mm in the probe rig)."""

    def test_tail_resting_on_the_floor_stays_on_it_during_the_sway(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / 'result.json'
            subprocess.run(['blender', '-b', '--factory-startup', '--python-exit-code', '1', '-P', str(ROOT / 'test/idle_tail_floor_probe.py'),
                            '--', str(ROOT / 'tools/idle'), str(out)], check=True, capture_output=True, timeout=300)
            result = json.loads(out.read_text())
        self.assertLess(result['rigid_sway']['min'], -1e-3)  # the old behaviour really goes below the ground (guards the probe itself)
        self.assertGreater(result['floor_follow']['min'], -5e-4)
        self.assertLess(result['floor_follow']['max'], 5e-4)


if __name__ == '__main__':
    unittest.main()

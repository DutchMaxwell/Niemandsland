import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]


@unittest.skipUnless(shutil.which('blender'), 'Blender is not installed')
class PetFloorTest(unittest.TestCase):
    """The rigged pet rat rests on the floor: reduction must not push its feet through it, and breathing, sniffing and tail sway must not
    move it off the floor, also when the owner armature is tilted (the keep_rig armatures carry a rig alignment of about 15 degrees)."""

    def test_pet_feet_stay_on_the_floor_through_reduction_and_the_sway(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / 'result.json'
            subprocess.run(['blender', '-b', '--factory-startup', '--python-exit-code', '1', '-P', str(ROOT / 'test/idle_pet_floor_probe.py'),
                            '--', str(ROOT / 'tools/idle'), str(out)], check=True, capture_output=True, timeout=300)
            result = json.loads(out.read_text())
        self.assertEqual(len(result['bones']), 6)
        self.assertAlmostEqual(result['placed'], 0.0, delta=2e-4)
        self.assertGreater(result['min'], -5e-4)
        self.assertLess(result['max'], 5e-4)


if __name__ == '__main__':
    unittest.main()

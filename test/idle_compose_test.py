import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]


@unittest.skipUnless(shutil.which('blender'), 'Blender is not installed')
class ComposedPartsTest(unittest.TestCase):
    """Throne forms keep their rigid composed parts (throne, bearers) in the idle payload: the idle mesh replaces the whole static model, so a part
    that is not placed here disappears in game. add_statics must put every part where compose_static puts it: scale, then rotation, then position."""

    def test_composed_parts_land_at_their_composed_bounds(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / 'result.json'
            subprocess.run(['blender', '-b', '--factory-startup', '--python-exit-code', '1', '-P', str(ROOT / 'test/idle_compose_probe.py'),
                            '--', str(ROOT / 'tools/idle'), str(out)], check=True, capture_output=True, timeout=300)
            result = json.loads(out.read_text())
        self.assertEqual(result['meshes'], 2)
        throne, bearer = result['rows']
        for row in (throne, bearer):
            self.assertFalse(row['parent'])
            self.assertTrue(row['name'].startswith('Static'))
        # 1 x 2 x 1 box, bottom on z = 0, scaled by 4 and lifted by 2: x +-2, y +-4, z 2..6
        for got, want in zip(throne['lo'] + throne['hi'], [-2, -4, 2, 2, 4, 6]):
            self.assertAlmostEqual(got, want, delta=1e-4)
        # turned 90 degrees about z (x and y swap), at (1, 1, 0.5): x 0..2, y 0.5..1.5, z 0.5..1.5
        for got, want in zip(bearer['lo'] + bearer['hi'], [0, 0.5, 0.5, 2, 1.5, 1.5]):
            self.assertAlmostEqual(got, want, delta=1e-4)


if __name__ == '__main__':
    unittest.main()

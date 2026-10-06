import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('preserve_pose', Path(__file__).parents[1] / 'tools/idle/preserve_pose.py')
pose = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pose)


def write_glb(path, doc, data):
    raw = json.dumps(doc).encode()
    raw += b' ' * (-len(raw) % 4)
    path.write_bytes(struct.pack('<4sIIII', b'glTF', 2, 28 + len(raw) + len(data), len(raw), 0x4E4F534A) + raw + struct.pack('<II', len(data), 0x004E4942) + data)


class PosePreservationTest(unittest.TestCase):
    def test_only_mesh_accessors_change_skeleton_and_animation_are_retained(self):
        original = {'asset': {'version': '2.0'}, 'nodes': [{'name': 'body', 'mesh': 0}, {'name': 'Hand', 'translation': [1, 2, 3]}],
                    'skins': [{'joints': [1], 'inverseBindMatrices': 0}], 'animations': [{'name': 'original-idle'}],
                    'meshes': [{'primitives': [{'indices': 0, 'attributes': {'POSITION': 0, 'JOINTS_0': 0}, 'material': 0}]}],
                    'materials': [{'name': 'body-paint'}], 'buffers': [{'byteLength': 4}],
                    'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': 4}], 'accessors': [{'bufferView': 0}]}
        changed = copy.deepcopy(original)
        changed['nodes'][1]['translation'] = [99, 99, 99]
        changed['animations'] = [{'name': 'wrong-weapon-motion'}]
        with tempfile.TemporaryDirectory() as directory:
            src, dest = Path(directory) / 'source.glb', Path(directory) / 'reduced.glb'
            write_glb(src, original, b'ORIG')
            write_glb(dest, changed, b'MESH')
            pose.preserve(src, dest)
            result, binary = pose.read(dest)
            for key in ['nodes', 'skins', 'animations', 'materials']:
                self.assertEqual(result[key], original[key])
            self.assertEqual(binary, b'ORIGMESH')
            self.assertEqual(result['meshes'][0]['primitives'][0]['attributes']['POSITION'], 1)
            self.assertEqual(result['bufferViews'][1]['byteOffset'], 4)
            self.assertEqual(result['accessors'][1]['bufferView'], 1)


if __name__ == '__main__':
    unittest.main()

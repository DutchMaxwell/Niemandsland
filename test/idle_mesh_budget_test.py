import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('mesh_budget', Path(__file__).parents[1] / 'tools/idle/mesh_budget.py')
budget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(budget)


class ShippedBudgetTest(unittest.TestCase):
    def test_counts_serialized_vertices_and_rejects_oversized_mesh(self):
        gltf = {'nodes': [{'name': 'body', 'mesh': 0}], 'meshes': [{'primitives': [
            {'attributes': {'POSITION': 0}, 'indices': 1}]}], 'accessors': [{'count': 24}, {'count': 36}]}
        data = json.dumps(gltf).encode()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mesh.glb'
            path.write_bytes(struct.pack('<4sIIII', b'glTF', 2, 20 + len(data), len(data), 0x4E4F534A) + data)
            self.assertEqual(budget.counts(path), {'body': {'vertices': 24, 'triangles': 12}})
            budget.validate(path, {'body': {'vertices': 24, 'triangles': 12}})
            with self.assertRaises(AssertionError):
                budget.validate(path, {'body': {'vertices': 23, 'triangles': 12}})
            with self.assertRaises(AssertionError):
                budget.validate(path, {'body': {'vertices': 24, 'triangles': 11}})


if __name__ == '__main__':
    unittest.main()

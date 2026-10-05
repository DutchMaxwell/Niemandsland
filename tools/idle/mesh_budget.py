"""Read triangle and serialized vertex budgets directly from shipped GLBs."""
import json
import struct


def counts(path):
    with path.open('rb') as stream:
        assert stream.read(4) == b'glTF', path
        stream.seek(12)
        length, kind = struct.unpack('<II', stream.read(8))
        assert kind == 0x4E4F534A, path
        gltf = json.loads(stream.read(length))
    result = {}
    for node in gltf['nodes']:
        if 'mesh' not in node:
            continue
        primitives = gltf['meshes'][node['mesh']]['primitives']
        result[node['name']] = {
            'vertices': sum(gltf['accessors'][p['attributes']['POSITION']]['count'] for p in primitives),
            'triangles': sum(gltf['accessors'][p['indices']]['count'] // 3 for p in primitives)}
    return result


def validate(path, budget):
    actual = counts(path)
    for metric in ['vertices', 'triangles']:
        assert sum(v[metric] for v in actual.values()) <= sum(v[metric] for v in budget.values()), (path, metric, actual, budget)
    return actual

"""Replace only mesh buffers; retain original skins, animation and attachment nodes."""
import copy
import json
import struct


def read(path):
    with open(path, 'rb') as stream:
        stream.seek(12)
        size, kind = struct.unpack('<II', stream.read(8))
        assert kind == 0x4E4F534A
        document = json.loads(stream.read(size))
        size, kind = struct.unpack('<II', stream.read(8))
        assert kind == 0x004E4942
        return document, stream.read(size)


def preserve(source, reduced):
    original, binary = read(source)
    mesh_doc, mesh_binary = read(reduced)
    assert [[original['nodes'][i]['name'] for i in s['joints']] for s in original['skins']] == [[mesh_doc['nodes'][i]['name'] for i in s['joints']] for s in mesh_doc['skins']]
    offset = len(binary)
    view_offset, accessor_offset = len(original['bufferViews']), len(original['accessors'])
    for view in mesh_doc['bufferViews']:
        view['byteOffset'] = view.get('byteOffset', 0) + offset
    for accessor in mesh_doc['accessors']:
        assert 'sparse' not in accessor
        if 'bufferView' in accessor:
            accessor['bufferView'] += view_offset
    original['bufferViews'].extend(mesh_doc['bufferViews'])
    original['accessors'].extend(mesh_doc['accessors'])
    materials = {m['name']: i for i, m in enumerate(original['materials'])}
    meshes = {n['name']: mesh_doc['meshes'][n['mesh']] for n in mesh_doc['nodes'] if 'mesh' in n}
    for node in original['nodes']:
        if 'mesh' not in node:
            continue
        mesh = copy.deepcopy(meshes[node['name']])
        for primitive in mesh['primitives']:
            primitive['indices'] += accessor_offset
            primitive['attributes'] = {key: value + accessor_offset for key, value in primitive['attributes'].items()}
            primitive['material'] = materials[mesh_doc['materials'][primitive['material']]['name']]
        original['meshes'][node['mesh']] = mesh
    binary += mesh_binary
    original['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(original, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    with open(reduced, 'wb') as stream:
        stream.write(struct.pack('<4sIIII', b'glTF', 2, 28 + len(encoded) + len(binary), len(encoded), 0x4E4F534A))
        stream.write(encoded)
        stream.write(struct.pack('<II', len(binary), 0x004E4942))
        stream.write(binary)

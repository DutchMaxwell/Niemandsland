"""Build the proven five-bone weighted Warrior tail chain."""
import bpy, math, heapq
from mathutils import Vector
from mathutils.kdtree import KDTree

def add_tail(arm, body, prefix):
    P = prefix
    view = bpy.context.view_layer
    # tail chain along the generated tail
    tail_mats = [i for i, m in enumerate(body.data.materials) if "tail" in m.name.lower()]
    tail = sorted({vi for p in body.data.polygons if p.material_index in tail_mats for vi in p.vertices})
    tail_bones = []
    if tail:
        to_arm = arm.matrix_world.inverted() @ body.matrix_world
        rest = {i: to_arm @ body.data.vertices[i].co for i in tail}
        tail_set = set(tail)
        other = KDTree(len(body.data.vertices))
        for v in body.data.vertices:
            if v.index not in tail_set:
                other.insert(to_arm @ v.co, v.index)
        other.balance()
        root = [i for i in tail if other.find(rest[i])[2] < 0.004]
        kd = KDTree(len(tail))
        for k, i in enumerate(tail):
            kd.insert(rest[i], k)
        kd.balance()
        dist = {i: math.inf for i in tail}
        heap = []
        for i in root:
            dist[i] = 0.0
            heapq.heappush(heap, (0.0, i))
        while heap:
            d, i = heapq.heappop(heap)
            if d > dist[i]:
                continue
            for co, k, dd in kd.find_n(rest[i], 10):
                j = tail[k]
                if d + dd < dist[j]:
                    dist[j] = d + dd
                    heapq.heappush(heap, (d + dd, j))
        S = max(d for d in dist.values() if d < math.inf)
        NB = 5
        cents = []
        for b in range(NB + 1):
            lo, hi = (b - 0.5) / NB * S, (b + 0.5) / NB * S
            pts = [rest[i] for i in tail if lo <= dist[i] < hi] or [rest[i] for i in tail if abs(dist[i] - b / NB * S) < S * 0.08]
            cents.append(sum(pts, Vector()) / len(pts))
        view.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        parent = arm.data.edit_bones[P + "Hips"]
        for b in range(NB):
            eb = arm.data.edit_bones.new(f"Tail{b}")
            eb.head, eb.tail, eb.parent, eb.use_connect = cents[b], cents[b + 1], parent, b > 0
            parent = eb
            tail_bones.append(eb.name)
        bpy.ops.object.mode_set(mode="OBJECT")
        hips_vg = body.vertex_groups[P + "Hips"]
        groups = [body.vertex_groups.new(name=n) for n in tail_bones]
        for i in tail:
            x = dist[i] / S * NB if dist[i] < math.inf else 0.0
            ws = [max(0.0, 1.0 - abs(x - (b + 0.5))) for b in range(NB)]
            wh = max(0.0, 1.0 - x / 0.6)
            tot = sum(ws) + wh or 1.0
            hips_vg.add([i], wh / tot, "REPLACE")
            for b in range(NB):
                if ws[b] > 0:
                    groups[b].add([i], ws[b] / tot, "REPLACE")
    return tail_bones, len(tail)

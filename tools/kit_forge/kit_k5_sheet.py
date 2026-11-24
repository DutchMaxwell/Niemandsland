# kit_k5_sheet.py - the K5 rows and assembly of the review sheet (preview only).
import math, random
from mathutils import Matrix
from kit_sheet import place, frame, disc, faces_of, run
from kit_k4_sheet import ground

LIT = ["dr_litter_straw", "dr_litter_leaves", "dr_litter_shards", "dr_litter_rags", "dr_litter_mud", "dr_litter_planks_flat", "dr_litter_staves_flat",
       "dr_litter_slates_fallen"]


def scene(objs, coll, X):
    """A street (cobbles) under a ruin tier foot with dense flat litter (denser at the wall foot; rotated, scaled 0.75-1.2),
    and a ruin yard (earth) with the wall stubs, rubble, beam and every junk prop. Bulky pieces stand ONLY in the yard."""
    r = random.Random(7)
    ground(coll, X - 1, -5, X + 13, 6, "cobbles", 0.0)
    f = faces_of(X, 6, X + 12, 9)
    run(objs, coll, f, "front", ["dr_ruin_face_foot_a", "dr_ruin_face_foot_b", "dr_ruin_face_doorway", "dr_ruin_face_foot_a"])
    for k in range(46):
        y = 5.6 - abs(r.gauss(0, 3.2))   # drifted against the wall foot
        if y < -4.2:
            continue
        x = X + r.uniform(0.3, 11.7)
        if math.hypot(x - (X + 3.0), y + 1.5) < 0.9 or math.hypot(x - (X + 8.0), y - 2.0) < 1.0:
            continue   # (the discs)
        s = r.uniform(0.75, 1.2)
        m = Matrix.Translation((x, y, 0.003)) @ Matrix.Rotation(r.uniform(0, 6.28), 4, "Z") @ Matrix.Diagonal((s, s, 1.0, 1.0))
        place(objs, r.choice(LIT), m, coll)
    disc(coll, X + 3.0, -1.5); disc(coll, X + 8.0, 2.0, 0.63)
    Y = X + 15
    ground(coll, Y, -3, Y + 12, 6, "earth", 0.0)
    T = lambda x, y, a=0.0: Matrix.Translation((Y + x, y, 0)) @ Matrix.Rotation(math.radians(a), 4, "Z")
    place(objs, "dr_yard_wallstub_a", T(4.5, 4.5), coll); place(objs, "dr_yard_wallstub_b", T(10.5, 1.5, 90), coll)
    place(objs, "dr_yard_rubble_a", T(7.6, 4.2, 30), coll); place(objs, "dr_yard_beam", T(8.0, 1.0, -15), coll)
    place(objs, "dr_junk_barrels", T(1.3, 3.6), coll); place(objs, "dr_junk_crates", T(1.5, 1.2, 20), coll)
    place(objs, "dr_junk_cart_wheel", T(4.6, 3.75), coll); place(objs, "dr_junk_planks", T(4.4, 0.9, 40), coll)
    place(objs, "dr_junk_sacks", T(3.0, 2.6, -30), coll); place(objs, "dr_junk_rubble", T(6.6, -1.3, 10), coll)
    for k in range(14):
        m = Matrix.Translation((Y + r.uniform(0.5, 11.5), r.uniform(-2.5, 5.5), 0.003)) @ Matrix.Rotation(r.uniform(0, 6.28), 4, "Z")
        place(objs, r.choice(LIT), m, coll)
    disc(coll, Y + 2.6, -1.6); disc(coll, Y + 9.8, -1.8, 0.63); disc(coll, Y + 6.2, 2.4)


ROWS = {"K5": [
    ("bulky junk (terrain cells / solid footprints only): barrels, crates, cart wheel, plank heap, sacks, rubble - 25 mm and 32 mm discs",
     ["dr_junk_barrels", "dr_junk_crates", "dr_junk_cart_wheel", "dr_junk_planks", "dr_junk_sacks", "dr_junk_rubble"], 1.3, True),
    ("flat litter 1 (<= 0.06 in high, <= 100 triangles): straw, leaves, shards, rags", LIT[:4], 1.0, True),
    ("flat litter 2: muck + mortar crumbs, broken boards, staves, fallen slates", LIT[4:], 1.0, True),
    ("yard pieces (ruin yards): wall stubs a / b, fallen-wall rubble, charred beams", ["dr_yard_wallstub_a", "dr_yard_wallstub_b", "dr_yard_rubble_a", "dr_yard_beam"], 1.4, True)]}
ASSEMBLY = {"K5": (scene, "K5 by the grammar: a cobbled street under a ruin tier with flat litter only (46 clusters, drifted to the wall foot) and a ruin yard on earth with every bulky piece",
                   [("street: flat litter only", (6, -5.6, 0)), ("ruin yard: stubs, rubble, beams, junk", (21, -3.6, 0))])}

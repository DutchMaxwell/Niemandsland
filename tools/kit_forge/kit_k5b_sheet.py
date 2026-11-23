# kit_k5b_sheet.py - the K5b rows and scene (preview only). The vegetation is shown with a PREVIEW of the material the
# game still lacks: vertex colour x albedo scale (x 1.6 as the kit's other previews), two-sided; cards with the atlas + alpha.
import bpy, os, math, random
from mathutils import Matrix
from kit_sheet import place, frame, disc, faces_of, run, top_plane
from kit_k4_sheet import ground
import kit_k5b

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CARD_DIR = os.environ.get("NML_KIT_GRASS_DIR", os.path.join(REPO, "build", "kit_forge", "grass_medium_01"))


def pv_veg():
    m = bpy.data.materials.get("pv_veg")
    if m:
        return m
    m = bpy.data.materials.new("pv_veg"); m.use_nodes = True
    nt = m.node_tree; bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Color"
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
    k = 2.0 * kit_k5b.ALBEDO_SCALE * 1.6
    nt.links.new(vc.outputs["Color"], mul.inputs[6]); mul.inputs[7].default_value = (k, k, k, 1.0)
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"]); bsdf.inputs["Roughness"].default_value = 0.9
    return m


def pv_card():
    m = bpy.data.materials.get("pv_card")
    if m:
        return m
    m = bpy.data.materials.new("pv_card"); m.use_nodes = True
    nt = m.node_tree; bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    d = nt.nodes.new("ShaderNodeTexImage"); d.image = bpy.data.images.load(os.path.join(CARD_DIR, "grass_medium_01_diff_1k.png"), check_existing=True)
    a = nt.nodes.new("ShaderNodeTexImage"); a.image = bpy.data.images.load(os.path.join(CARD_DIR, "grass_medium_01_alpha_1k.png"), check_existing=True)
    a.image.colorspace_settings.name = "Non-Color"
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
    k = 0.15 * 1.6
    nt.links.new(d.outputs["Color"], mul.inputs[6]); mul.inputs[7].default_value = (k, k, k, 1.0)
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    th = nt.nodes.new("ShaderNodeMath"); th.operation = "GREATER_THAN"; th.inputs[1].default_value = 0.4
    nt.links.new(a.outputs["Color"], th.inputs[0]); nt.links.new(th.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


VEG = [n for n, _ in kit_k5b.builders()]
PV_OVERRIDE = {n: (pv_card if ("_card_" in n or n == "dr_veg_plot_a") else pv_veg) for n in VEG}
LIT = ["dr_litter_straw", "dr_litter_leaves", "dr_litter_shards", "dr_litter_rags", "dr_litter_mud", "dr_litter_planks_flat", "dr_litter_staves_flat",
       "dr_litter_slates_fallen"]
DRIFT = ["dr_litter_drift_a", "dr_litter_drift_b", "dr_litter_drift_c"]


def scene(objs, coll, X):
    """A street under a ruin tier: FEW large drifts lying along the wall foot and across the lane mouth, single clusters
    overlapping their ends (same kinds together), moss and growth in the wall's angle, a puddle with a grown rim."""
    r = random.Random(11)
    ground(coll, X - 1, -5, X + 13, 6, "cobbles", 0.0)
    f = faces_of(X, 6, X + 12, 9)
    run(objs, coll, f, "front", ["dr_ruin_face_foot_a", "dr_ruin_face_foot_b", "dr_ruin_face_doorway", "dr_ruin_face_foot_a"])
    for k, m in enumerate(["dr_veg_foot_run_a", "dr_veg_foot_run_b", "dr_veg_foot_run_a", "dr_veg_foot_run_b"]):
        place(objs, m, frame((X + 3 * k, 6, 0), (1, 0, 0), (0, -1, 0)), coll)
    T = lambda x, y, a=0.0, s=1.0: Matrix.Translation((X + x, y, 0.003)) @ Matrix.Rotation(math.radians(a), 4, "Z") @ Matrix.Diagonal((s, s, 1.0, 1.0))
    drifts = [("dr_litter_drift_b", 2.2, 5.1, 4), ("dr_litter_drift_a", 6.0, 4.9, -6), ("dr_litter_drift_c", 9.8, 5.0, 8), ("dr_litter_drift_a", 3.5, 2.6, 28),
              ("dr_litter_drift_c", 8.2, 0.6, -35), ("dr_litter_drift_b", 10.6, 3.0, 70)]
    for m, x, y, a in drifts:
        place(objs, m, T(x, y, a, r.uniform(0.9, 1.15)), coll)
    kin = {"dr_litter_drift_a": ["dr_litter_straw", "dr_litter_mud", "dr_litter_planks_flat"], "dr_litter_drift_b": ["dr_litter_slates_fallen", "dr_litter_leaves", "dr_litter_mud"],
           "dr_litter_drift_c": ["dr_litter_rags", "dr_litter_shards", "dr_litter_staves_flat"]}
    for m, x, y, a in drifts:   # the drift's own kinds overlap its ends and trail off down-wind
        for j in range(3):
            d = r.choice((-1, 1)) * r.uniform(1.0, 1.9)
            place(objs, r.choice(kin[m]), T(x + d * math.cos(math.radians(a)) + r.uniform(-0.3, 0.3), y + d * math.sin(math.radians(a)) + r.uniform(-0.4, 0.4),
                                            r.uniform(0, 360), r.uniform(0.75, 1.1)), coll)
    top_plane(coll, X + 4.9, -2.9, X + 6.3, -1.7, 0.004, "ct_glass_dark")   # a puddle (a stand-in for the game's water)
    place(objs, "dr_veg_rim_a", Matrix.Translation((X + 5.6, -2.3, 0)), coll)
    for (x, y, m) in ((1.0, 1.0, "dr_veg_card_a"), (1.4, 0.7, "dr_veg_card_c"), (11.3, -1.5, "dr_veg_card_b"), (0.6, -2.5, "dr_veg_grass_tussock"), (11.0, -3.6, "dr_veg_moss_mat")):
        place(objs, m, Matrix.Translation((X + x, y, 0)), coll)
    disc(coll, X + 2.6, -1.4); disc(coll, X + 8.4, -2.4, 0.63); disc(coll, X + 6.4, 3.0)
    Y = X + 15   # two plot cells with the v6 growth
    for k, m in enumerate(("dr_veg_plot_a", "dr_veg_plot_b")):
        ground(coll, Y + 3.4 * k, 0, Y + 3.4 * k + 3, 3, "plot", 0.004)
        place(objs, m, frame((Y + 3.4 * k, 0, 0), (1, 0, 0), (0, -1, 0)), coll)
        place(objs, "dr_plot_fence_run", frame((Y + 3.4 * k, 0, 0), (1, 0, 0), (0, -1, 0)), coll)
    disc(coll, Y + 1.5, -1.0); disc(coll, Y + 4.9, -1.0, 0.63)


ROWS = {"K5b": [
    ("v6 vegetation, modelled: grass tuft / tussock / stubble / trodden, nettle, dead stalks - PREVIEW material (the game has none yet)",
     ["dr_veg_grass_tuft", "dr_veg_grass_tussock", "dr_veg_grass_stubble", "dr_veg_grass_trodden", "dr_veg_nettle", "dr_veg_dead_stalks"], 2.0, True),
    ("v6 card tufts a / b / c (5 crossed quads, grass_medium_01 billboards, alpha) and moss cushion / strip / cluster / mat (<= 0.02 in)",
     ["dr_veg_card_a", "dr_veg_card_b", "dr_veg_card_c", "dr_veg_moss_cushion", "dr_veg_moss_strip", "dr_veg_moss_cluster", "dr_veg_moss_mat"], 2.0, True),
    ("compositions: plot cell a / b (replace dr_plot_weeds_a / b), wall-foot run a (flat moss) / b (soft growth to 0.3 in), puddle rim",
     ["dr_veg_plot_a", "dr_veg_plot_b", "dr_veg_foot_run_a", "dr_veg_foot_run_b", "dr_veg_rim_a"], 1.2, True),
    ("litter at the 100-triangle cap, 1: straw, leaves, shards, rags (rust-red toned down)", LIT[:4], 1.0, True),
    ("litter at the 100-triangle cap, 2: muck + mortar, boards, staves + hoop, slates", LIT[4:], 1.0, True),
    ("NEW larger drifts (3.2 x 1.5 in, <= 300 triangles): a stable sweepings, b under a broken eave, c household refuse", DRIFT, 1.2, True)]}
ASSEMBLY = {"K5b": (scene, "street + wall foot: six drifts with their own kinds trailing off, moss / growth in the wall's angle, a puddle rim, card tufts; right: two plot cells with the v6 growth",
                    [("street: drifts overlap and trail (no stamps)", (6, -5.6, 0)), ("plot cells: dr_veg_plot_a / b + fence", (18, -2.2, 0))])}

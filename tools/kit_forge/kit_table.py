# kit_table.py - the module table of the ruin-town dressing kit and the manifest writer. Pure Python (no bpy):
# dress_kit.py imports it, and `python3 tools/kit_forge/dress_kit.py --manifest-only [<kit dir>]` writes the nominal
# manifest without Blender.
#
# Conventions (all numbers in INCHES):
# - Module local axes (glTF / Godot): +X along the face, +Y up, +Z out of the face. Origin = the left foot of the mounting
#   plane. Geometry behind the plane (z < 0) is inside the mass; z > 0 stands proud.
# - aabb_in = [[x0, y0, z0], [x1, y1, z1]] in those axes.
# - mount_in = the nominal height of the module's origin above the standing surface the face rises from (0 for a foot
#   band or a house panel, 2.5 for a gable / roof / chimney on the house body, 3.0 for an upper tier band). The proud
#   bands are measured at mount_in + local y: flat = up to FLAT 0.08, low = up to CLEAR 2.0, high = above.
# - proud_in = {flat, low, high}: the largest +z of any vertex in that band (0.0 when the band is empty).
# - openings = [[x0, x1, z0, z1]]: x along the face, z0 / z1 = HEIGHTS (local y) of an opening; nothing of ct_timber /
#   ct_stone crosses it except parts the forge declares as fill (glazing bars, door leaf).
# - shadow = 1-3 hull boxes [[lo], [hi]] (same axes) for the shadow proxy.
# - tri_cap = the contract's cap for the family; tris = the measured count (stubs: the cap, a worst case for budgets).
import json, os

FLAT, CLEAR = 0.08, 2.0
BODY, RISE, CELL = 2.5, 2.0, 3.0
OVERHANG = 0.3

CAPS = {"plain_face": 120, "feature_face": 350, "house_panel": 350, "gable": 300, "roof_s3": 700, "roof_s6": 1000,
        "verge": 250, "chimney": 120, "merlon_run": 150, "quoin": 60, "ladder": 120, "prop": 400, "litter": 100, "litter_drift": 300, "veg": 120, "veg_cell": 400,
        
        "fountain": 1500, "tower_cap": 600}

# Shared materials: textured sets (uv "world" = projected from board space by the shader, "mesh" = TEXCOORD_0 in inches
# divided by tile_in) and plain colours. tone / joint / anti_tile / macro = the game's dressing shader tone, joint and
# breakup tables; joint = [ao_lo, ao_hi, colour, base].
MATERIALS = {
    "ct_stone": {"set": "coursed_stone", "tile_in": 3.0, "course_in": 0.5, "stone_in": 0.6, "uv": "world", "tone": [0.42, 0.45, 0.52], "anti_tile": 0.0,
                 "macro": 0.9, "joint": [0.3, 0.62, [0.07, 0.08, 0.04], 0.18]},
    # The fine-stone material (smaller stones on the houses; ruins keep ct_stone, the town wall ct_stone_big):
    # the same set at tile 2.25 (course 0.375, stone 0.45). NOTE: 2.25 does not divide the 2.5 in body or the 3.0 in panel
    # (6.67 courses / stones): the house panels end in a part course of 0.25 in under the eaves and a part stone at one end.
    "ct_stone_fine": {"set": "coursed_stone", "tile_in": 2.25, "course_in": 0.375, "stone_in": 0.45, "uv": "world", "tone": [0.42, 0.45, 0.52], "anti_tile": 0.0,
                      "macro": 0.9, "joint": [0.3, 0.62, [0.07, 0.08, 0.04], 0.18]},
    "ct_stone_big": {"set": "coursed_stone", "tile_in": 3.6, "course_in": 0.6, "stone_in": 0.72, "uv": "world", "tone": [0.4, 0.43, 0.5], "anti_tile": 0.0,
                     "macro": 0.9, "joint": [0.3, 0.62, [0.07, 0.08, 0.04], 0.2]},
    "ct_plaster": {"set": "plaster", "tile_in": 6.0, "course_in": None, "stone_in": None, "uv": "world", "tone": [0.68, 0.62, 0.52], "anti_tile": 0.0,
                   "macro": 0.7, "joint": [0.9, 0.965, [0.16, 0.14, 0.11], 0.5]},
    "ct_timber": {"set": "timber", "tile_in": 3.25, "course_in": 0.3611, "stone_in": 1.625, "uv": "mesh", "tone": [0.7, 0.66, 0.62], "anti_tile": 0.0,
                  "macro": 0.35, "joint": [0.4, 0.7, [0.03, 0.025, 0.02], 0.3]},
    "ct_roof": {"set": "roof_tiles", "tile_in": 3.375, "course_in": 0.3068, "stone_in": 0.1875, "uv": "mesh", "tone": [0.42, 0.42, 0.44], "anti_tile": 0.0,
                "macro": 0.5, "joint": [0.45, 0.62, [0.07, 0.08, 0.04], 0.2]},
    "ct_flags": {"set": "flags", "tile_in": 1.8, "course_in": 1.8, "stone_in": 0.45, "uv": "world", "tone": [0.45, 0.45, 0.47], "anti_tile": 0.0,
                 "macro": 0.5, "joint": [0.75, 0.93, [0.1, 0.09, 0.06], 0.5]},
    "ct_iron": {"colour": [0.035, 0.033, 0.03], "roughness": 0.55, "metallic": 0.7},
    "ct_clay": {"colour": [0.28, 0.12, 0.07], "roughness": 0.85, "metallic": 0.0},
    "ct_glass_lit": {"colour": [0.9, 0.6, 0.3], "roughness": 0.4, "metallic": 0.0, "emission": [1.0, 0.62, 0.3],
                     "emission_energy": 2.0},
    "ct_glass_dark": {"colour": [0.02, 0.022, 0.025], "roughness": 0.25, "metallic": 0.0},
    "ct_matte": {"colour": [1.0, 1.0, 1.0], "roughness": 0.92, "metallic": 0.0},
    # The vegetation material: its shader is the game's vegetation shader.
    # A card module names `variant: card` (atlas + alpha scissor, shader veg_card); the others are modelled blades (veg_solid).
    "ct_veg": {"colour": [0.14, 0.14, 0.14], "roughness": 0.9, "metallic": 0.0, "shader": "veg_solid", "albedo_scale": 0.14, "cull": "disabled",
               "undo_backface_normal_flip": True, "wrap": 0.4, "backlight": 0.7, "cast_shadow": False,
               "card": {"set": "grass_cards", "alpha_scissor": 0.4, "tone": [0.15, 0.15, 0.15]},
               "variants": {"card": {"shader": "veg_card"}}},   # (the card variant selects the atlas + alpha-scissor shader)
}

# What the ground / tops shader reads (tones from the game's ground shader; cobbles 1.9 in = setts ~0.24 in).
GROUND = {
    "cobbles": {"set": "cobbles", "tile_in": 1.9, "tone": [0.36, 0.37, 0.4]},
    "earth": {"set": "earth", "tile_in": 8.0, "tone": [0.36, 0.33, 0.3]},
    "mud": {"set": "mud", "tile_in": 2.2, "tone": [0.36, 0.33, 0.3], "mirror": True, "height_in": 0.06},   # height-mapped mud
    "yard_flags": {"set": "flags", "tile_in": 1.8, "tone": [0.45, 0.45, 0.47]},
    "deck_flags": {"set": "flags", "tile_in": 1.8, "tone": [0.45, 0.45, 0.47]},
    "deck_boards": {"set": "timber", "tile_in": 3.25, "tone": [0.7, 0.66, 0.62]},
    "walk_flags": {"set": "flags", "tile_in": 1.8, "tone": [0.42, 0.42, 0.45]},
    "rubble": {"set": "coursed_stone", "tile_in": 3.0, "tone": [0.34, 0.35, 0.38]},
    "plot": {"set": "earth", "tile_in": 8.0, "tone": [0.3, 0.31, 0.24]},
}

# Coursed sets are sampled ONCE (anti_tile 0, no blend of shifted copies); course_in = the vertical course / row period,
# stone_in = the period along the course (counted on the 1k source by FFT of the AO + eye).
# Module heights (2.5, 3.0) and lengths (3.0) are whole multiples; ct_stone_big is at 6.0 and ct_roof at 3.375 so that
# holds (big: 3 courses per 3 in band; roof: 16 slates per 3 in segment, 11 rows per tile). ct_flags is irregular
# crazy paving: course_in = the tile (offsets in whole tiles), stone_in = the mean flag. Plaster: uncoursed (blend allowed).
# ct_stone (ruin / house) stays at tile 3.0 (course 0.5, the texture's small stones already ~0.3 in; a 1.5 tile put them
# at ~0.15 in, under the readability floor); ct_stone_big tile 3.6 (course 0.6, 5 per 3 in band, stone 0.72).
# Stone joints stay soft (a harder joint reads as crackle): joint base 0.28 -> 0.18 (big 0.32 -> 0.2), lo 0.35 -> 0.3.
# Cobbles and flags carry a HEIGHT map (lib/manifest.json sets.<name>.height; Poly Haven displacement, CC0).
SETS = {
    "coursed_stone": {"source": "https://polyhaven.com/a/medieval_blocks_05", "licence": "CC0-1.0"},
    "plaster": {"source": "https://polyhaven.com/a/painted_plaster_wall", "licence": "CC0-1.0"},
    "timber": {"source": "https://polyhaven.com/a/weathered_planks", "licence": "CC0-1.0"},
    "earth": {"source": "https://polyhaven.com/a/forest_ground_04", "licence": "CC0-1.0"},
    "cobbles": {"source": "https://polyhaven.com/a/cobblestone_floor_08", "licence": "CC0-1.0",
                "height": {"url": "9dcb9f766d3e287cd1e7513750c0e2383eb585f5ccbf747cd5e237ae2a38ceea.ctex", "size": 162062,
                           "source": "https://polyhaven.com/a/cobblestone_floor_08 (displacement, 512 px, 8-bit)", "licence": "CC0-1.0"}},
    "flags": {"source": "https://polyhaven.com/a/monastery_stone_floor", "licence": "CC0-1.0",
              "height": {"url": "e92215e1703c5db0b14d34760575b89cb1ea6c68bab3a3d0da3ef65436f679c8.ctex", "size": 135352,
                         "source": "https://polyhaven.com/a/monastery_stone_floor (displacement, 512 px, 8-bit)", "licence": "CC0-1.0"}},
    "roof_tiles": {"source": "https://polyhaven.com/a/grey_roof_tiles_02", "licence": "CC0-1.0"},
    "grass_cards": {"source": "https://polyhaven.com/a/grass_medium_01", "licence": "CC0-1.0",
                    "albedo": {'url': '46ccd9cc35a9c1d45a315e8ae0af50a462e929c23c9d7ba50f5843e5f8bf139c.ctex', 'sha256': '46ccd9cc35a9c1d45a315e8ae0af50a462e929c23c9d7ba50f5843e5f8bf139c', 'size': 349604}, "dry": {'url': '36017a3588c943b0cdbc31a75bda339c9097b3e69c8db36a617ee12793eb966f.ctex', 'sha256': '36017a3588c943b0cdbc31a75bda339c9097b3e69c8db36a617ee12793eb966f', 'size': 349604}, "normal": {'url': 'ef1180224dd2a366a8dacbd5b164f39f12277a59bef57cce45fe7d18ce2b28d2.ctex', 'sha256': 'ef1180224dd2a366a8dacbd5b164f39f12277a59bef57cce45fe7d18ce2b28d2', 'size': 349604},
                    "rects_px_1024": [[190, 765, 322, 140], [590, 770, 250, 115], [25, 890, 175, 122], [250, 900, 260, 112], [585, 885, 200, 127]]},
    # The mud set carries a full set + height map (it needs real relief)
    "mud": {"source": "https://polyhaven.com/a/brown_mud_03", "licence": "CC0-1.0",
            "height": {"url": "b2f01ef2484409769b1dea84c957c4d47542c2dc1eef2b3a8511f3976f6d0ef7.ctex", "size": 156764,
                       "source": "https://polyhaven.com/a/brown_mud_03 (displacement, 512 px, 8-bit)", "licence": "CC0-1.0"}},
}


def _m(batch, family, cap, role, ln, h, mats, aabb, proud, mount=0.0, openings=None, shadow=None, tags=None):
    return {"batch": batch, "family": family, "tri_cap": CAPS[cap], "role": role, "len_in": ln, "height_in": h,
            "mount_in": mount, "tris": CAPS[cap], "materials": mats, "aabb_in": aabb,
            "proud_in": {"flat": proud[0], "low": proud[1], "high": proud[2]}, "openings": openings or [],
            "shadow": shadow or [[[aabb[0][0] + 0.05, aabb[0][1], aabb[0][2] + 0.05], [aabb[1][0] - 0.05, aabb[1][1] - 0.05, min(aabb[1][2], 0.0)]]],
            "tags": tags or [], "stub": True}


def _face(batch, family, cap, role, mats, h=CELL, depth=0.4, proud=(0.0, 0.08, 0.08), mount=0.0, openings=None, tags=None, ln=CELL):
    return _m(batch, family, cap, role, ln, h, mats, [[0.0, 0.0, -depth], [ln, h, max(proud)]], proud, mount, openings,
              tags=tags)


def table():
    T = {}
    # ---------------- K1 HOUSE (25)
    tb = ["ct_stone", "ct_plaster", "ct_timber"]
    pan = (0.22, 0.12, 0.08)   # flat: the door step / plinth foot; low: sill board, shutters; high: top plate
    for role in ("plain_a", "plain_b", "window", "window_lit", "door", "blank"):
        mats = tb + (["ct_glass_lit"] if role == "window_lit" else ["ct_glass_dark"] if role in ("window", "door", "plain_b") else [])
        op = [[0.95, 2.05, 1.12, 1.88]] if role.startswith("window") else [[1.1, 1.85, 0.0, 1.72]] if role == "door" else []
        T["dr_house_tb_" + role] = _face("K1", "house_panel", "house_panel", role, mats, BODY, 0.3, pan, 0.0, op,
                                         ["single_band", "tiles", "timber_frame"])
    T["dr_house_tb_post"] = _m("K1", "quoin", "quoin", "corner", 0.22, BODY, ["ct_timber", "ct_stone"],
                               [[-0.11, 0.0, -0.11], [0.11, BODY, 0.11]], (0.11, 0.08, 0.08), tags=["centred_on_corner"])
    for sp in (3, 6):
        for v in ("", "_b"):
            T[f"dr_gable_tb_s{sp}{v}"] = _m("K1", "gable", "gable", "gable", float(sp), RISE, ["ct_plaster", "ct_timber", "ct_glass_dark"],
                                           [[-0.15, -0.12, -0.3], [sp + 0.15, RISE, 0.32]], (0.0, 0.0, 0.32), mount=BODY,
                                           tags=["jetty_0.12", "span_%d" % sp])
    for role in ("plain_a", "plain_b", "window", "door"):
        mats = ["ct_stone"] + (["ct_glass_dark", "ct_timber"] if role in ("window", "door") else [])
        op = [[1.0, 2.0, 1.0, 1.95]] if role == "window" else [[1.1, 1.9, 0.0, 1.75]] if role == "door" else []
        T["dr_house_st_" + role] = _face("K1", "house_panel", "house_panel", role, mats, BODY, 0.4, (0.22, 0.06, 0.08), 0.0, op,
                                         ["single_band", "tiles", "stone"])
    T["dr_house_st_quoin"] = _m("K1", "quoin", "quoin", "corner", 0.5, BODY, ["ct_stone"],
                                [[-0.06, 0.0, -0.5], [0.5, BODY, 0.06]], (0.06, 0.06, 0.06), tags=["on_corner"])
    for sp in (3, 6):
        T[f"dr_gable_st_s{sp}"] = _m("K1", "gable", "gable", "gable", float(sp), RISE, ["ct_stone"],
                                     [[0.0, 0.0, -0.4], [float(sp), RISE, 0.06]], (0.0, 0.0, 0.06), mount=BODY, tags=["span_%d" % sp])
        for role in ("mid_a", "mid_b", "verge"):
            ln = OVERHANG if role == "verge" else CELL
            T[f"dr_roof_s{sp}_{role}"] = _m("K1", "roof", "verge" if role == "verge" else f"roof_s{sp}", role, ln, RISE,
                                           ["ct_roof", "ct_timber"], [[0.0, -0.25, -sp - OVERHANG], [ln, RISE, OVERHANG]],
                                           (0.0, 0.0, OVERHANG), mount=BODY,
                                           shadow=[[[0.0, 0.0, -sp], [ln, RISE * 0.5, 0.0]], [[0.0, RISE * 0.5, -sp * 0.75], [ln, RISE, -sp * 0.25]]],
                                           tags=["span_%d" % sp, "symmetric_about_ridge"] + ([] if role == "verge" else ["tiles"]))
    T["dr_chimney_a"] = _m("K1", "chimney", "chimney", "chimney", 0.62, RISE + 0.9, ["ct_stone", "ct_clay"],
                           [[-0.31, 0.0, -0.31], [0.31, RISE + 0.9, 0.31]], (0.0, 0.0, 0.0), mount=BODY, tags=["centred"])
    # ---------------- K2 TIERS (17)
    st = ["ct_stone"]
    T["dr_ruin_face_foot_a"] = _face("K2", "ruin_face", "plain_face", "foot", st, proud=(0.12, 0.08, 0.08), tags=["foot", "tiles"])
    T["dr_ruin_face_foot_b"] = _face("K2", "ruin_face", "plain_face", "foot", st, proud=(0.12, 0.08, 0.08), tags=["foot", "tiles"])
    for v in ("a", "b", "c"):
        T["dr_ruin_face_plain_" + v] = _face("K2", "ruin_face", "feature_face", "plain", st, mount=CELL, tags=["upper_band", "tiles"])   # (arch / buttress / lost facing: feature cap)
    T["dr_ruin_face_window"] = _face("K2", "ruin_face", "feature_face", "window", st + ["ct_glass_dark"], mount=CELL,
                                     openings=[[1.05, 1.95, 0.9, 2.2]], tags=["upper_band", "tiles"])
    T["dr_ruin_face_doorway"] = _face("K2", "ruin_face", "feature_face", "doorway", st + ["ct_glass_dark"],
                                      openings=[[1.0, 2.0, 0.0, 2.1]], tags=["foot", "tiles", "closed_by_rubble"])
    T["dr_ruin_quoin"] = _m("K2", "quoin", "quoin", "corner", 0.5, CELL, st, [[-0.06, 0.0, -0.5], [0.5, CELL, 0.06]], (0.06, 0.06, 0.06),
                            tags=["on_corner"])
    for v in ("a", "b", "c"):
        T["dr_parapet_stub_" + v] = _m("K2", "parapet", "merlon_run", "parapet", CELL, 0.7, st, [[0.0, 0.0, -0.4], [CELL, 0.7, 0.0]],
                                       (0.0, 0.0, 0.0), mount=CELL, tags=["top_edge", "R4_strip"])
    for sp in (3, 6):
        T[f"dr_ruin_gable_s{sp}"] = _m("K2", "ruin_gable", "gable", "gable", float(sp), 2.6, st, [[0.0, 0.0, -0.3], [float(sp), 2.6, 0.0]],
                                       (0.0, 0.0, 0.0), mount=CELL, tags=["end_face", "R4_gable"])
    for v in ("a", "b"):
        T["dr_deck_edge_" + v] = _m("K2", "deck_edge", "plain_face", "deck_edge", CELL, 0.3, ["ct_timber"],
                                    [[0.0, -0.3, -0.3], [CELL, 0.0, 0.2]], (0.0, 0.0, 0.2), mount=CELL, tags=["top_edge", "tiles"])
    T["dr_ladder_3in"] = _m("K2", "ladder", "ladder", "ladder", 1.0, CELL, ["ct_timber"], [[-0.5, 0.0, 0.0], [0.5, CELL, 0.3]],
                            (0.3, 0.3, 0.3), tags=["ladder", "R1_exception"])
    T["dr_ladder_top"] = _m("K2", "ladder", "ladder", "ladder_top", 1.0, CELL + 0.5, ["ct_timber"],
                            [[-0.5, 0.0, -0.3], [0.5, CELL + 0.5, 0.3]], (0.3, 0.3, 0.3), tags=["ladder", "R1_exception"])
    # ---------------- K3 WALL + TOWER (17)
    sb = ["ct_stone_big"]
    T["dr_twall_foot"] = _face("K3", "twall_face", "plain_face", "foot", sb, proud=(0.0, 0.0, 0.0), tags=["foot", "batter_inside", "tiles"])
    for v in ("face_a", "face_b"):
        T["dr_twall_" + v] = _face("K3", "twall_face", "plain_face", "plain", sb, proud=(0.0, 0.06, 0.06), mount=CELL, tags=["upper_band", "tiles"])
    T["dr_twall_slit"] = _face("K3", "twall_face", "feature_face", "slit", sb + ["ct_glass_dark"], proud=(0.0, 0.06, 0.06), mount=CELL,
                               openings=[[1.35, 1.65, 0.8, 2.4]], tags=["upper_band", "tiles"])
    T["dr_twall_corbel"] = _face("K3", "twall_face", "feature_face", "corbel", sb, proud=(0.0, 0.06, 0.35), mount=CELL,
                                 tags=["upper_band", "string_course", "tiles"])
    T["dr_twall_ragged"] = _face("K3", "twall_face", "feature_face", "ragged", sb, proud=(0.0, 0.0, 0.0), mount=CELL,
                                 tags=["upper_band", "faces_breach", "tiles"])
    T["dr_twall_quoin"] = _m("K3", "quoin", "quoin", "corner", 0.6, CELL, sb, [[-0.06, 0.0, -0.6], [0.6, CELL, 0.06]], (0.06, 0.06, 0.06),
                             tags=["on_corner"])
    for v in ("a", "b", "broken"):
        T["dr_merlon_run_" + v] = _m("K3", "merlon_run", "merlon_run", "merlons", CELL, 0.7, sb, [[0.0, 0.0, -0.4], [CELL, 0.7, 0.0]],
                                     (0.0, 0.0, 0.0), mount=6.0, tags=["top_edge", "R4_strip"])
    T["dr_tower_foot"] = _face("K3", "tower_face", "plain_face", "foot", sb, proud=(0.0, 0.0, 0.0), tags=["foot", "tiles"])
    for v in ("face_a", "face_b"):
        T["dr_tower_" + v] = _face("K3", "tower_face", "plain_face", "plain", sb, proud=(0.0, 0.06, 0.06), mount=CELL, tags=["upper_band", "tiles"])
    T["dr_tower_slit"] = _face("K3", "tower_face", "feature_face", "slit", sb + ["ct_glass_dark"], proud=(0.0, 0.06, 0.06), mount=CELL,
                               openings=[[1.35, 1.65, 0.8, 2.4]], tags=["upper_band", "tiles"])
    T["dr_tower_quoin"] = _m("K3", "quoin", "quoin", "corner", 0.6, CELL, sb, [[-0.06, 0.0, -0.6], [0.6, CELL, 0.06]], (0.06, 0.06, 0.06),
                             tags=["on_corner"])
    for v in ("slate", "burnt"):
        mats = ["ct_roof", "ct_timber"] if v == "slate" else ["ct_timber", "ct_glass_dark", "ct_stone_big"]
        T["dr_tower_cap_" + v] = _m("K3", "tower_cap", "tower_cap", "cap", 6.0, 3.0 if v == "slate" else 2.0, mats,
                                    [[0.0, -3.0 if v == "slate" else -2.0, -6.0 - OVERHANG], [6.0, 0.0, OVERHANG]],
                                    (0.0, 0.0, OVERHANG), mount=12.0,
                                    tags=["never_above_12in", "R6_cap"] + (["is_top_band"] if v == "slate" else ["inside_top_band"]))
    # ---------------- K4 LAMPS, LANDMARKS, PLOTS (9)
    T["dr_lamp_post"] = _m("K4", "prop", "prop", "lamp", 0.2, 2.9, ["ct_iron", "ct_glass_lit", "ct_stone"],
                           [[-0.1, 0.0, -0.1], [0.1, 2.9, 0.1]], (0.1, 0.1, 0.1), tags=["centred", "cell_corner", "R1_exception"])
    T["dr_lamp_bracket"] = _m("K4", "prop", "prop", "lamp", 0.4, 0.8, ["ct_iron", "ct_glass_lit"], [[-0.2, -0.6, 0.0], [0.2, 0.2, 0.35]],
                              (0.0, 0.0, 0.35), mount=CLEAR + 0.6, tags=["wall_mounted", "above_clear"])
    T["dr_fountain"] = _m("K4", "landmark", "fountain", "fountain", CELL, BODY, ["ct_stone", "ct_glass_dark"],
                          [[-1.5, 0.0, -1.5], [1.5, BODY, 1.5]], (0.0, 0.0, 0.0), tags=["centred", "inside_solid_footprint"])
    T["dr_statue_plinth"] = _m("K4", "landmark", "prop", "plinth", CELL, BODY, ["ct_stone"], [[-1.5, 0.0, -1.5], [1.5, BODY, 1.5]],
                               (0.0, 0.0, 0.0), tags=["centred", "inside_solid_footprint", "no_figure"])
    T["dr_pool_kerb"] = _m("K4", "landmark", "plain_face", "kerb", CELL, FLAT, ["ct_stone"], [[0.0, 0.0, -0.3], [CELL, FLAT, 0.0]],
                           (0.0, 0.0, 0.0), tags=["flat", "class_edge"])
    for v, h in (("weeds_a", 0.4), ("weeds_b", 0.4), ("fence_run", 1.0), ("deadbush", 1.5)):
        T["dr_plot_" + v] = _m("K4", "plot", "prop", "plot", CELL, h, ["ct_timber", "ct_matte"], [[0.0, 0.0, -CELL], [CELL, h, 0.0]],
                               (0.0, 0.0, 0.0), tags=["terrain_cell", "bulky_ok"])
    # ---------------- K5 REFUSE (18)
    for v, ln, h in (("barrels", 1.4, 0.7), ("crates", 1.6, 0.9), ("cart_wheel", 1.0, 1.0), ("planks", 1.4, 0.3), ("sacks", 1.0, 0.4),
                     ("rubble", 1.6, 0.5)):
        T["dr_junk_" + v] = _m("K5", "junk", "prop", "junk", ln, h, ["ct_timber", "ct_iron", "ct_stone"],
                               [[-ln / 2, 0.0, -ln / 2], [ln / 2, h, ln / 2]], (0.0, 0.0, 0.0), tags=["centred", "bulky", "terrain_or_solid_only"])
    for v in ("straw", "leaves", "shards", "rags", "mud", "planks_flat", "staves_flat", "slates_fallen"):
        T["dr_litter_" + v] = _m("K5", "litter", "litter", "litter", 2.0, 0.03, ["ct_matte", "ct_clay"], [[-1.0, 0.0, -1.0], [1.0, 0.03, 1.0]],
                                 (0.0, 0.0, 0.0), shadow=[], tags=["centred", "flat"])
    for v, ln, h in (("wallstub_a", CELL, 1.2), ("wallstub_b", CELL, 0.8), ("rubble_a", 2.0, 0.6), ("beam", 2.4, 0.3)):
        T["dr_yard_" + v] = _m("K5", "yard", "prop", "yard", ln, h, ["ct_stone", "ct_timber"], [[-ln / 2, 0.0, -ln / 2], [ln / 2, h, ln / 2]],
                               (0.0, 0.0, 0.0), tags=["centred", "bulky", "terrain_or_solid_only"])
    # ---------------- K5b VEGETATION + LARGER LITTER DRIFTS
    vt = ["centred", "veg", "soft_veg", "no_collider", "no_shadow"]
    for v in ("grass_tuft", "grass_tussock", "grass_stubble", "grass_trodden", "card_a", "card_b", "card_c", "moss_cushion", "moss_strip",
              "moss_cluster", "moss_mat", "nettle", "dead_stalks"):
        T["dr_veg_" + v] = _m("K5b", "veg", "veg", "veg", 0.5, 0.4, ["ct_veg"], [[-0.3, 0.0, -0.3], [0.3, 0.4, 0.3]], (0.0, 0.0, 0.0), shadow=[], tags=vt)
    for v in ("plot_a", "plot_b"):
        T["dr_veg_" + v] = _m("K5b", "veg", "veg_cell", "plot", CELL, 0.4, ["ct_matte"], [[0.0, 0.0, -CELL], [CELL, 0.4, 0.0]], (0.0, 0.0, 0.0), shadow=[],
                              tags=["terrain_cell", "bulky_ok", "veg", "soft_veg", "no_collider", "no_shadow"])
    for v in ("foot_run_a", "foot_run_b"):
        T["dr_veg_" + v] = _m("K5b", "veg", "veg_cell", "wall_foot", CELL, 0.4, ["ct_matte"], [[0.0, 0.0, 0.0], [CELL, 0.4, 0.5]], (0.5, 0.5, 0.0), shadow=[],
                              tags=["veg", "soft_veg", "wall_foot", "no_collider", "no_shadow"])
    T["dr_veg_rim_a"] = _m("K5b", "veg", "veg_cell", "puddle_rim", 1.6, 0.4, ["ct_matte"], [[-0.8, 0.0, -0.8], [0.8, 0.4, 0.8]], (0.0, 0.0, 0.0), shadow=[],
                           tags=["centred", "veg", "soft_veg", "puddle_rim", "no_collider", "no_shadow"])
    for v in ("a", "b", "c"):
        T["dr_litter_drift_" + v] = _m("K5b", "litter", "litter_drift", "litter", 3.2, 0.06, ["ct_matte"], [[-1.6, 0.0, -0.8], [1.6, 0.06, 0.8]], (0.0, 0.0, 0.0),
                                       shadow=[], tags=["centred", "flat", "drift"])
    # ---------------- K6 (7)
    for sp in (3, 6):
        for role in ("broken", "rafters", "hip"):
            T[f"dr_roof_s{sp}_{role}"] = _m("K6", "roof", f"roof_s{sp}", role, CELL, RISE, ["ct_roof", "ct_timber"],
                                           [[0.0, -0.25, -sp - OVERHANG], [CELL, RISE, OVERHANG]], (0.0, 0.0, OVERHANG), mount=BODY,
                                           tags=["span_%d" % sp, "symmetric_about_ridge"])
    T["dr_chimney_b"] = _m("K6", "chimney", "chimney", "chimney", 0.62, RISE + 0.9, ["ct_stone", "ct_clay"],
                           [[-0.31, 0.0, -0.31], [0.31, RISE + 0.9, 0.31]], (0.0, 0.0, 0.0), mount=BODY, tags=["centred"])
    return T


def manifest(modules):
    return {"version": 1, "units": "inches in this file; GLB geometry in metres, glTF +Y up",
            "axes": "+X along the face, +Y up, +Z out of the face; origin = left foot of the mounting plane",
            "bands": {"flat": FLAT, "clear": CLEAR},
            "licence": {"meshes": "CC-BY-SA-4.0", "author": "own work, generated by script (forge/dress_kit.py)"},
            "materials": MATERIALS, "ground": GROUND, "sets": SETS, "modules": modules}


def write(path, modules):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(manifest(modules), f, indent=1, sort_keys=True)
    os.replace(tmp, path)

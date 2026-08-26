extends SceneTree
## NML-1073 M1-0 — proves BattleSim.state_to_plain() is COMPLETE: rebuilds a
## state Dictionary from N recorded nodes.jsonl lines using ONLY the plain
## JSON (positions back to Vector3; each unit's "unit" is a STAND-IN GameUnit
## built solely from the header line's "profiles" table — no live GameUnit is
## ever touched, exactly the position a Rust port is in), replays
## resolve()+score() and diffs the result against the recorded state_after/score.
##
## GAP (documented, not silently patched over): the plain form carries the
## "los" matrix (sees()) but not the state-level "los_blocked" terrain
## Callable (_los_clear) — nodes whose shoot/charge leg needed centre-line
## terrain blocking will show a resolve() mismatch here; that capture is
## M1-2/M1-3 scope. score() has no such dependency of its own, but the
## RECORDED score may have used either the cheap leaf (score(next, player))
## or the rich leaf (score(next, player, reply_threat(next, player))) — the
## 5-field JSONL contract does not carry which, so this tool tries both and
## reports the closer one; "neither within tolerance" is a real mismatch.
##
## Usage: godot --headless -s res://tools/node_recheck.gd -- dir=<NML_NODE_DUMP dir> n=50
##   acts=<acts.jsonl>   stamp the terrain from the SAME game's act corpus header
##                       (closes the resolve-side cover gap described below)
## (line 1 of nodes.jsonl is the {"profiles": ...} header, not counted in n)

const EPS := 1e-6

func _init() -> void:
	var dir := OS.get_environment("NML_NODE_DUMP")
	var acts := ""
	var n := 50
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		if kv[0] == "dir":
			dir = kv[1]
		elif kv[0] == "n":
			n = int(kv[1])
		elif kv[0] == "acts":
			acts = kv[1]
	var f := FileAccess.open(dir.path_join("nodes.jsonl"), FileAccess.READ)
	if f == null:
		printerr("[RECHECK] cannot open ", dir.path_join("nodes.jsonl"))
		quit(1)
		return
	var header: Variant = JSON.parse_string(f.get_line())
	var profiles: Dictionary = (header as Dictionary)["profiles"]
	# NML-1073 M2-0c: nodes.jsonl carries no terrain, so resolve()'s cover probe
	# (battle_sim.gd:616 — the mover's in_cover follows it) had nothing to ask
	# and every move/rush node showed an in_cover-only resolve mismatch. The ACT
	# recorder already captures the board (acts.jsonl header "terrain"); point
	# this at the acts.jsonl of the SAME game and the gap closes. Without it the
	# tool keeps its documented pre-M2-0c behaviour.
	var terrain_cb := Callable()
	if acts != "":
		var af := FileAccess.open(acts, FileAccess.READ)
		if af == null:
			printerr("[RECHECK] cannot open ", acts)
			quit(1)
			return
		var ah: Dictionary = JSON.parse_string(af.get_line())
		if ah.get("terrain") != null:
			terrain_cb = terrain_at_from_plain(ah["terrain"] as Dictionary)
	var checked := 0
	var resolve_exact := 0
	var max_score_diff := 0.0
	var matches := {"cheap": 0, "rich": 0, "neither": 0}
	var mismatches: Array = []
	while checked < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var rec: Variant = JSON.parse_string(line)
		if not (rec is Dictionary):
			continue
		checked += 1
		var player := int(rec["player"])
		var before := _rebuild_state(rec["state_before"], profiles)
		if terrain_cb.is_valid():
			before["terrain_at"] = terrain_cb
		var next: Dictionary = BattleSim.resolve(before, _rebuild_action(rec["action"]))
		var recorded := float(rec["score"])
		var d_cheap := absf(AiMissionEval.score(next, player) - recorded)
		var d_rich := absf(AiMissionEval.score(next, player,
			BattleSim.reply_threat(next, player)) - recorded)
		max_score_diff = maxf(max_score_diff, minf(d_cheap, d_rich))
		if d_cheap <= EPS and d_cheap <= d_rich:
			matches["cheap"] += 1
		elif d_rich <= EPS:
			matches["rich"] += 1
		else:
			matches["neither"] += 1
			mismatches.append({"node": checked, "kind": "score", "recorded": recorded,
				"cheap_diff": d_cheap, "rich_diff": d_rich})
		# M1-2 added "los_pairs" to the recorded form; a REBUILT state carries no
		# los_blocked Callable, so state_to_plain never writes it and the size
		# check below would fail every node. Drop the recorded side's copy.
		(rec["state_after"] as Dictionary).erase("los_pairs")
		if _plain_eq(BattleSim.state_to_plain(next, false), rec["state_after"]):
			resolve_exact += 1
		else:
			mismatches.append({"node": checked, "kind": "resolve",
				"action_kind": int((rec["action"] as Dictionary).get("kind", -1))})
	print("[RECHECK] nodes=%d resolve_exact=%d/%d max_score_diff=%.12f score_matches=%s" \
		% [checked, resolve_exact, checked, max_score_diff, str(matches)])
	for m in mismatches:
		print("[RECHECK] MISMATCH ", m)
	quit(0)


static func _rebuild_state(plain: Dictionary, profiles: Dictionary) -> Dictionary:
	var state := {"round": int(plain["round"]), "rounds_total": int(plain["rounds_total"]),
		"scoring": str(plain["scoring"])}
	for k in ["vp", "vp_flavour", "vp_memo", "markers_meta", "destroy_seq"]:
		if plain.has(k):
			state[k] = plain[k]
	var objectives: Array = []
	for o in (plain.get("objectives", []) as Array):
		objectives.append({"pos": _vec3((o as Dictionary)["pos"]), "owner": (o as Dictionary)["owner"]})
	state["objectives"] = objectives
	var units := {}
	var plain_units: Dictionary = plain["units"]
	# NML-1073 M3-0c: reinsert in the RECORDED order (state_to_plain's
	# "unit_order") when the corpus carries it. `plain_units` itself iterates
	# key-sorted (it round-tripped through JSON.stringify(sort_keys=true)), but
	# the root search (ai_planner.gd "for key in state[\"units\"]") walks
	# insertion order — rebuilding sorted silently hands it a DIFFERENT unit
	# order than the one that produced the recorded pick. Absent key
	# (pre-M3-0c corpus) falls back to `plain_units`'s own order, i.e. today's
	# (sorted) behaviour — unchanged.
	var order: Array = plain.get("unit_order", plain_units.keys())
	for uid in order:
		var su: Dictionary = (plain_units[uid] as Dictionary).duplicate(true)
		su["unit"] = _stand_in_unit(profiles[uid], su)
		su["positions"] = _vec3s(su.get("positions", []))
		units[uid] = su
	state["units"] = units
	return state


static func _rebuild_action(a: Dictionary) -> Dictionary:
	var out := a.duplicate()
	if out.has("dest"):
		out["dest"] = _vec3(out["dest"])
	return out


## A stand-in GameUnit built ONLY from the recorded profile — the completeness
## proof: if resolve()/score() run correctly off this, the profile lost nothing
## the closures needed. Reuses the real GameUnit/ModelInstance/OPRUnit classes
## (not hand-mocked accessors) so RulesRegistry/AiEv/AiShooting need no changes.
static func _stand_in_unit(p_static: Dictionary, dyn: Dictionary = {}) -> GameUnit:
	# NML-1073 M2-5b: the header profile is the DEPLOYMENT reading; the act line
	# carries the fields a live game rewrites (BattleSim.unit_profile_dyn, stamped
	# by AiActRecorder._stamp_gate_reads under "prof"). The per-act reading WINS —
	# without it a stand-in for a unit whose attached hero has fallen still
	# inherits the dead hero's rules. An act with no "prof" (the node corpus, a
	# pre-M2-5b act corpus) leaves the header reading in place, i.e. the old
	# behaviour.
	var p := p_static.duplicate(true)
	p.merge(dyn.get("prof", {}) as Dictionary, true)
	var u := GameUnit.new()
	u.unit_id = str(p.get("unit_id", ""))
	u.unit_properties = {"name": p.get("name", ""), "quality": int(p.get("quality", 0)),
		"defense": int(p.get("defense", 0)), "special_rules": p.get("special_rules", []),
		"game_system": str(p.get("game_system", "")), "faction_folder": str(p.get("faction_folder", "")),
		"size": int(p.get("model_count", 0))}
	for wm in (p.get("wounds_max", []) as Array):
		var m := ModelInstance.new()
		m.wounds_max = int(wm)
		u.models.append(m)
	# NML-1073 M2-0c finding: AiPlanner._round_start_refresh (:485) refills the
	# imagined round's spell tokens from the GameUnit FIELD casts_per_round —
	# not from the Caster(X) rule. The stand-in left it at 0, so every rollout
	# that crossed a round boundary ran its casters dry and the horizon leaf
	# priced a magic-less enemy. The profile's caster_value is the same source
	# the live field is built from (game_unit.gd:420/430).
	u.casts_per_round = int(p.get("caster_value", 0))
	var weapons: Array = p.get("weapons", [])
	if not weapons.is_empty():
		u.source_type = "opr"
		var ou := OPRApiClient.OPRUnit.new()
		for w in weapons:
			var ow := OPRApiClient.OPRWeapon.new()
			ow.name = str((w as Dictionary).get("name", ""))
			ow.range_value = int((w as Dictionary).get("range", 0))
			ow.attacks = int((w as Dictionary).get("attacks", 0))
			ow.count = int((w as Dictionary).get("count", 1))
			for r in ((w as Dictionary).get("rules", []) as Array):
				ow.special_rules.append(str(r))
			ou.weapons.append(ow)
		u.source_data = ou
	# NML-1073 M2-0c finding: RulesRegistry.unit_rules_of_primitive (item_grants)
	# and AiEv.rule_on_all_models (attached_heroes) are LIVE reads _unit_profile
	# already flattens (item_grants/attached_hero_rules) but this stand-in never
	# wired back — a unit with a granted rule (e.g. an aura item) replayed with
	# NONE of its item/hero rules, diverging exactly where that rule mattered.
	u.unit_properties["item_grants"] = {"_": p.get("item_grants", [])}
	var heroes: Array = []
	for hero_rules in (p.get("attached_hero_rules", []) as Array):
		var h := GameUnit.new()
		h.unit_properties = {"special_rules": hero_rules}
		var hm := ModelInstance.new()
		h.models.append(hm)
		heroes.append(h)
	u.unit_properties["attached_heroes"] = heroes
	# NML-1073 M2-0c finding: SoloController.sim_move_bands is a LIVE read on
	# eight sim/eval sites (AiMissionEval._presence :602 prices every objective
	# with it) and it is DYNAMIC — move_bands_for_props (movement_range_
	# controller.gd:80) derives the bands from unit_properties["rule_descriptions"],
	# a dict that grows in play when an attached aura hero's texts join the host
	# (a "Slow" text then costs -2"/-4" although the unit never carries the rule).
	# The stand-in owns no such texts, so it answered the pre-merge bands and the
	# whole eval drifted. state_to_plain now records the CURRENT bands per unit;
	# calibrate the stand-in onto them through spell_move_mod, the numeric band
	# delta move_bands_for_props already adds verbatim (:173). No recorded bands
	# (pre-M2-0c corpus) = the profile's snapshot, i.e. the old behaviour.
	var want: Dictionary = dyn.get("bands", p.get("move_bands", {}))
	if not want.is_empty():
		var nat: Dictionary = SoloController.sim_move_bands(u)
		var d_adv := int(roundf(float(want.get("advance", 0.0)) - float(nat.get("advance", 0.0))))
		var d_rush := int(roundf(float(want.get("rush", 0.0)) - float(nat.get("rush", 0.0))))
		if d_adv != 0 or d_rush != 0:
			u.unit_properties["spell_move_mod"] = {"advance": d_adv, "rush": d_rush}
	# NML-1073 M2-0d: the other two LIVE per-unit reads the ROOT search makes —
	# ai_planner.gd:975 adds SoloController.max_activation_advance_bonus_in to the
	# advance band for candidates_wide's reach gate, and AiShooting/the reach gates
	# read SoloController.shooting_range_bonus. Both are recorded per ACTIVATION
	# (M2-5b: BattleSim.unit_profile_dyn, merged into `p` at the top of this
	# function); answer them from the corpus here.
	# shooting_range_bonus (:4966) has an ADDITIVE seam — unit_properties
	# "spell_range_mod" is summed in verbatim — so it calibrates exactly, the same
	# trick spell_move_mod plays for the bands above.
	# max_activation_advance_bonus_in (:5070) has NONE: it is a pure walk over
	# Bounding/Quick/Teleport in RulesRegistry, which the stand-in already drives
	# from the profile's special_rules + item_grants + game_system + faction_folder.
	# So it is CHECKED, not stamped — a divergence is a real corpus gap and says so
	# out loud instead of replaying a silently wrong band (0.0 everywhere in the
	# arena corpus, so this never fires there).
	if p.has("shooting_range_bonus"):
		var nat_range := SoloController.shooting_range_bonus(u)
		if int(p["shooting_range_bonus"]) != nat_range:
			u.unit_properties["spell_range_mod"] = int(u.unit_properties.get("spell_range_mod", 0)) \
				+ int(p["shooting_range_bonus"]) - nat_range
	if p.has("max_activation_advance_bonus_in"):
		var nat_adv := SoloController.max_activation_advance_bonus_in(u)
		if absf(float(p["max_activation_advance_bonus_in"]) - nat_adv) > EPS:
			push_warning("[RECHECK] %s: max_activation_advance_bonus_in recorded=%f stand-in=%f" \
				% [str(p.get("unit_id", "")), float(p["max_activation_advance_bonus_in"]), nat_adv])
	return u


## Port of terrain_overlay.gd get_terrain_at_world_position + world_to_cell
## (scripts/terrain_overlay.gd:1090-1116) over the recorded cells/sandbox/
## cell_params — no live TerrainOverlay node.
static func terrain_at_from_plain(terrain: Dictionary) -> Callable:
	var cells := {}
	for c in (terrain["cells"] as Array):
		cells[Vector2i(int(c[0]), int(c[1]))] = int(c[2])
	var sandbox: Array = terrain["sandbox"]
	var cp: Dictionary = terrain["cell_params"]
	var tsize: Array = cp["table_size_feet"]
	var width_in := float(tsize[0]) * 12.0
	var height_in := float(tsize[1]) * 12.0
	var grid_in := float(cp["grid_size_inches"])
	var cell_m := grid_in * float(cp["inches_to_meters"])
	var rot_rad := deg_to_rad(float(cp["grid_rotation_degrees"]))
	var grid_size := int(ceil(sqrt(width_in * width_in + height_in * height_in) / grid_in))
	if grid_size % 2 != 0:
		grid_size += 1
	return func(world_pos: Vector3) -> int:
		var rx := world_pos.x * cos(-rot_rad) - world_pos.z * sin(-rot_rad)
		var rz := world_pos.x * sin(-rot_rad) + world_pos.z * cos(-rot_rad)
		var cell := Vector2i(int(floor(rx / cell_m + grid_size / 2.0)), int(floor(rz / cell_m + grid_size / 2.0)))
		var t := int(cells.get(cell, 0))
		if t != 0:
			return t
		var p := Vector2(world_pos.x, world_pos.z)
		for s in sandbox:
			var sd: Dictionary = s
			var c: Array = sd["c"]
			var he: Array = sd["he"]
			if TerrainRules.point_in_obb(p, Vector2(c[0], c[1]), Vector2(he[0], he[1]), float(sd["yaw"])):
				return int(sd["type"])
		return 0


## NML-1073 M3-0d: the state-level `los_blocked` seam (battle_sim.gd:792
## `_los_clear`, ai_planner.gd:829 safe-line probe) rebuilt from the recorded
## terrain instead of from the recorded ANSWERS. The corpus records only the
## ROOT centre-pair grid ("los_pairs"), but the search asks this seam about
## MOVED unit centres — every RUSH/ADVANCE candidate is scored on a state whose
## mover has left its root centre — and about arbitrary safe-line points. No
## root grid can answer those, so a nearest-centre snap silently returned the
## mover's OLD line of fire. Terrain cells are STATIC for a whole game, so the
## once-written header IS the complete input: this is the same function
## core_selfplay stamps (tools/core_selfplay.gd:675), fed the recorded cells.
## Only the school 3" grid produces "los_pairs" today; act_recheck diffs this
## rebuild against the recorded LIVE grid before the search uses it, so a board
## whose seam is NOT this function fails loudly instead of drifting.
static func los_blocked_from_plain(terrain: Dictionary) -> Callable:
	var cells := {}
	for c in (terrain["cells"] as Array):
		cells[Vector2i(int(c[0]), int(c[1]))] = int(c[2])
	var cp: Dictionary = terrain["cell_params"]
	var tsize: Array = cp["table_size_feet"]
	var width_in := float(tsize[0]) * 12.0
	var height_in := float(tsize[1]) * 12.0
	var grid_in := float(cp["grid_size_inches"])
	# The SAME grid convention terrain_at_from_plain uses above, i.e.
	# map_layout.gd _calculate_grid_dimensions(): table diagonal / grid inches,
	# rounded UP to even. SchoolTerrain.generate stores exactly this as "n".
	var grid_size := int(ceil(sqrt(width_in * width_in + height_in * height_in) / grid_in))
	if grid_size % 2 != 0:
		grid_size += 1
	var world := {"cells": cells, "n": grid_size}
	return func(a: Vector3, b: Vector3) -> bool:
		return SchoolTerrain.los_blocked(world, a, b)


static func _vec3(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _vec3s(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(_vec3(v))
	return out


## Recursive deep-equal, float/int compared with EPS tolerance (state_after
## from JSON already round-tripped through string formatting once).
static func _plain_eq(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= EPS
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _plain_eq(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _plain_eq(a[i], b[i]):
				return false
		return true
	return a == b

class_name AiActRecorder
extends RefCounted
## NML-1073 M2-0a: env NML_ACT_DUMP=<dir> appends every ACTIVATION the
## planner picked to <dir>/acts.jsonl — the per-activation counterpart to
## ai_planner.gd's NML_NODE_DUMP (per-node) recorder; same style (FileAccess
## stream opened once and kept open, JSON lines via JSON.stringify with
## sort_keys, env cap NML_ACT_DUMP_MAX). Unset (default) never touches disk:
## SoloController._planner_pick_unit calls begin()/finish() unconditionally,
## but begin() returns {} on the very first (cheap, cached) env check and
## finish() no-ops on an empty pending dict — byte-identical game either way.
## Line 1 is {"kind":"header", "profiles": {...}, "terrain": {...}|null,
## "knobs": {...}} — the STATIC per-unit/board/search data, written ONCE;
## every activation after it is a {"kind":"act", ...} line with the FULL
## input the search read plus the "pick" it returned.


static var _stream: FileAccess = null
static var _checked := false
static var _header_written := false
static var _max := 5000
static var _count := 0


static func _dump_stream() -> FileAccess:
	if not _checked:
		_checked = true
		var dir := OS.get_environment("NML_ACT_DUMP")
		if dir != "" and DirAccess.dir_exists_absolute(dir):
			_stream = FileAccess.open(dir.path_join("acts.jsonl"), FileAccess.WRITE)
			var cap := OS.get_environment("NML_ACT_DUMP_MAX")
			if cap != "":
				_max = maxi(int(cap), 0)
	return _stream


## NML-1073 M2-0b: true once NML_ACT_DUMP is set (the same cached check
## begin()/finish() use) — AiPlanner reads this to guard ALL search-trace
## bookkeeping so the search stays byte-identical AND allocation-free when
## the seam is off.
static func active() -> bool:
	return _dump_stream() != null


## Pre-pick capture (INPUT): call right after the un-activated-pool loop and
## BEFORE doctrine_pick/plan_with_rollout. Returns {} when the env seam is off
## or the line cap is already hit — the caller's finish() then no-ops too.
static func begin(state: Dictionary, me: int, pool: Array, terrain_cb: Callable) -> Dictionary:
	var f := _dump_stream()
	if f == null or _count >= _max:
		return {}
	if not _header_written:
		_header_written = true
		f.store_line(JSON.stringify(_header_line(state, terrain_cb), "", true, true))
		f.flush()   # a same-process reader (the unit test) must see the header without a close()
	var pool_keys: Array = []
	for k in state["units"]:
		if pool.has((state["units"][k] as Dictionary)["unit"]):
			pool_keys.append(str(k))
	var plain: Dictionary = BattleSim.state_to_plain(state, false)
	_stamp_gate_reads(state, plain)
	return {"kind": "act", "round": int(state["round"]), "player": me,
		"statics": {"opener_seat": AiPlanner.opener_seat, "playout_search": AiPlanner.playout_search,
			"fit_mode": AiMissionEval.fit_mode, "playout_net": AiPlanner.playout_net},
		"state": plain,
		"charge_illegal": _charge_illegal_matrix(state),
		"charge_illegal_grid": _charge_illegal_grid(state), "pool": pool_keys}


## Post-pick write (OUTPUT): call once the final pick (doctrine_pick or
## plan_with_rollout) is settled. `pending` is begin()'s return value — {}
## (env off / cap hit) is a silent no-op.
static func finish(pending: Dictionary, pick: Dictionary) -> void:
	if pending.is_empty() or _stream == null or _count >= _max:
		return
	pending["pick"] = _flatten_vec3(pick)
	# NML-1073 M2-0b: plan_with_rollout's search-trace bookkeeping — read once,
	# then reset so the NEXT activation (or a doctrine_pick that never calls
	# plan_with_rollout) never carries this one's stale trace forward.
	pending["trace"] = AiPlanner.trace
	AiPlanner.trace = {}
	_stream.store_line(JSON.stringify(pending, "", true, true))
	_stream.flush()   # a same-process reader (the unit test) must see the line without a close()
	_count += 1


## 0a finding: pick.action.dest (and runner_up.action.dest) is a raw Vector3 —
## JSON.stringify would write that as its native "(x, y, z)" STRING, not a
## parsable number array, unlike every other Vector3 this recorder writes via
## BattleSim._plain_vec3 (the SAME per-vector helper, applied recursively here
## since a Vector3 can surface anywhere under `pick`).
static func _flatten_vec3(v: Variant) -> Variant:
	if v is Vector3:
		return BattleSim._plain_vec3(v)
	if v is Dictionary:
		var out := {}
		for k in (v as Dictionary):
			out[k] = _flatten_vec3((v as Dictionary)[k])
		return out
	if v is Array:
		var out: Array = []
		for e in (v as Array):
			out.append(_flatten_vec3(e))
		return out
	return v


static func _header_line(state: Dictionary, terrain_cb: Callable) -> Dictionary:
	var profiles := {}
	for key in state["units"]:
		var u: GameUnit = (state["units"][key] as Dictionary)["unit"]
		var prof := BattleSim._unit_profile(u)
		prof["shooting_range_bonus"] = SoloController.shooting_range_bonus(u)
		prof["max_activation_advance_bonus_in"] = SoloController.max_activation_advance_bonus_in(u)
		profiles[str(key)] = prof
	return {"kind": "header", "profiles": profiles, "terrain": _terrain_line(terrain_cb),
		"knobs": {"top_k": AiPlanner.top_k_default(), "horizon": AiPlanner.horizon(),
			"tail_cap_p1": AiPlanner._tail_cap_for(1), "tail_cap_p2": AiPlanner._tail_cap_for(2),
			"imagined_round_end": AiPlanner.imagined_round_end_enabled(),
			"depth_discount": AiPlanner.depth_discount(), "seat_mode": AiPlanner.seat_mode(),
			"playout_margin": AiPlanner.close_margin(), "playout_rich": AiPlanner.playout_rich(),
			"seam_cast": BattleSim.cast_phase_enabled(), "seam_spacing": BattleSim.spacing_enabled()}}


## Reaches the live TerrainOverlay the same way SoloController's terrain_type_at
## Callable does: main.gd binds a lambda over its `terrain_overlay` member, so
## the Callable's bound object (get_object()) IS the main node. null when there
## is no overlay wired (headless tests, no terrain_type_at seam).
static func _terrain_line(terrain_cb: Callable) -> Variant:
	if not terrain_cb.is_valid():
		return null
	var owner_obj: Object = terrain_cb.get_object()
	if owner_obj == null or not ("terrain_overlay" in owner_obj):
		return null
	var ov = owner_obj.get("terrain_overlay")
	if ov == null:
		return null
	var cells: Array = []
	for k in (ov.grid_cells as Dictionary):
		var c := k as Vector2i
		cells.append([c.x, c.y, int(ov.grid_cells[k])])
	var sandbox: Array = []
	for s in ov._sandbox_shapes():
		var sd := s as Dictionary
		var c: Vector2 = sd["c"]
		var he: Vector2 = sd["he"]
		sandbox.append({"c": [c.x, c.y], "he": [he.x, he.y],
			"yaw": float(sd["yaw"]), "type": int(sd["type"])})
	return {"cells": cells, "sandbox": sandbox,
		"cell_params": {"table_size_feet": [ov.table_size_feet.x, ov.table_size_feet.y],
			"grid_rotation_degrees": float(ov.grid_rotation_degrees),
			"grid_size_inches": ov.GRID_SIZE_INCHES, "inches_to_meters": ov.INCHES_TO_METERS}}


## charge_illegal(attacker, victim, gap_in, attacker_centre, victim_centre) for
## every ordered pair of distinct alive units on opposite sides — the exact
## call shape AiPlanner._best_charge uses (ai_planner.gd ~:1190-1200). {} when
## the state carries no charge_illegal seam (lab fixtures, old snapshots).
static func _charge_illegal_matrix(state: Dictionary) -> Dictionary:
	var out := {}
	var cb: Callable = state.get("charge_illegal", Callable())
	if not cb.is_valid():
		return out
	for ak in state["units"]:
		var asu: Dictionary = state["units"][ak]
		if int(asu["alive"]) <= 0:
			continue
		for vk in state["units"]:
			if vk == ak:
				continue
			var vsu: Dictionary = state["units"][vk]
			if int(vsu["alive"]) <= 0 or int(vsu["player"]) == int(asu["player"]):
				continue
			var gap := maxf(BattleSim.dist_in(asu["positions"], vsu["positions"]) - BattleSim.CONTACT_IN, 0.0)
			out["%s|%s" % [str(ak), str(vk)]] = bool(cb.call(asu["unit"], vsu["unit"], gap,
				AiPlanner._centre(asu), AiPlanner._centre(vsu)))
	return out


## NML-1073 M2-0d: the per-unit LIVE reads SoloController.charge_candidate_illegal makes
## (solo_controller.gd:1434-1447) that state_to_plain does not already carry, written into the
## PLAIN unit dicts so BattleSim.charge_illegal_plain can answer the gate for an ARBITRARY
## imagined gap — the root pair matrix below can only answer the root one.
##   charge_probe_r      _move_base_radius_m(_moving_models(u)) (:4735/:4915). NOT state["radii"]:
##                       capture (:1176) writes the unit's OWN alive models, the gate measures
##                       unit + attached heroes and floors at DEFAULT_BASE_RADIUS_M.
##   charge_no_difficult has_special_rule("Strider"/"Flying") — the p.13 difficult exemption.
##   shroud              [penalty_in, floor_in] of melee_shroud_charge_in (:5150); absent when
##                       the victim carries no rule of the Melee-Shrouding family.
## Per ACT, not in the once-written header: all three drift in a live game (models die, an
## attached hero joins or falls), and the gate reads them fresh on every activation.
static func _stamp_gate_reads(state: Dictionary, plain: Dictionary) -> void:
	var units: Dictionary = plain["units"]
	for key in state["units"]:
		var pu: Dictionary = units.get(str(key), {})
		if pu.is_empty():
			continue
		var u: GameUnit = (state["units"][key] as Dictionary)["unit"]
		pu["charge_probe_r"] = _move_base_radius_of(u)
		pu["charge_no_difficult"] = u.has_special_rule("Strider") or u.has_special_rule("Flying")
		var sh := _melee_shroud_params(u)
		if not sh.is_empty():
			pu["shroud"] = sh


## SoloController._move_base_radius_m(_moving_models(u)) (:4735 over :4915) mirrored statically:
## alive models INCLUDING attached heroes, node-filtered exactly as _moving_models filters them,
## floored at the shared SeparationChecker default.
static func _move_base_radius_of(u: GameUnit) -> float:
	var r := SeparationChecker.DEFAULT_BASE_RADIUS_M
	var raw: Array = u.get_alive_models_with_attached() if u.has_method("get_alive_models_with_attached") \
		else u.get_alive_models()
	for m in raw:
		var node := (m as ModelInstance).node
		if node != null and is_instance_valid(node):
			r = maxf(r, SoloController.model_base_radius_m(m as ModelInstance))
	return r


## The [penalty_in, floor_in] SoloController.melee_shroud_charge_in (:5150) would apply against
## `target`, resolved in the SAME order: the named rule first, then the DATA aliases of the
## Melee-/Ranged-Shrouding primitives. [] = no rule of the family fires (reach = the raw band).
static func _melee_shroud_params(target: GameUnit) -> Array:
	if target == null:
		return []
	if AiEv.rule_on_all_models(target, "Melee Shrouding"):
		return [float(RulesRegistry.unit_param(target, "Melee Shrouding", "move_penalty_in",
				AiCombatMath.SHROUD_CHARGE_PENALTY_IN)),
			float(RulesRegistry.unit_param(target, "Melee Shrouding", "floor_in",
				AiCombatMath.SHROUD_FLOOR_IN))]
	for prim in ["Melee Shrouding", "Ranged Shrouding"]:
		for e in RulesRegistry.unit_rules_of_primitive(target, prim):
			var ed := e as Dictionary
			var n := str(ed["name"])
			if n == "Melee Shrouding" or n == "Ranged Shrouding" or not AiEv.rule_on_all_models(target, n):
				continue
			var sp: Dictionary = ed.get("params", {})
			var pen := float(sp.get("move_penalty_in", sp.get("melee_move_penalty_in", 0.0)))
			if pen <= 0.0:
				continue
			return [pen, float(sp.get("melee_floor_in", sp.get("floor_in", AiCombatMath.SHROUD_FLOOR_IN)))]
	return []


## NML-1073 M2-0d ORACLE: the LIVE gate's answer for every ordered opposite-side pair over a
## GAP GRID — 0", 0.5", … 14" — called exactly the way AiPlanner._best_charge calls it (same
## argument shape, the pair's own root centres as from/to). The pair matrix above records one
## point of this curve; the grid records the whole thing, so a replay's PURE gate can be diffed
## against the live one at every gap the rollouts actually ask about. ~84 pairs x 29 per act.
const GATE_GRID_STEPS := 29
const GATE_GRID_STEP_IN := 0.5


static func _charge_illegal_grid(state: Dictionary) -> Dictionary:
	var out := {}
	var cb: Callable = state.get("charge_illegal", Callable())
	if not cb.is_valid():
		return out
	for ak in state["units"]:
		var asu: Dictionary = state["units"][ak]
		if int(asu["alive"]) <= 0:
			continue
		var ca := AiPlanner._centre(asu)
		for vk in state["units"]:
			if vk == ak:
				continue
			var vsu: Dictionary = state["units"][vk]
			if int(vsu["alive"]) <= 0 or int(vsu["player"]) == int(asu["player"]):
				continue
			var cv := AiPlanner._centre(vsu)
			var row: Array = []
			for i in range(GATE_GRID_STEPS):
				row.append(bool(cb.call(asu["unit"], vsu["unit"],
					float(i) * GATE_GRID_STEP_IN, ca, cv)))
			out["%s|%s" % [str(ak), str(vk)]] = row
	return out

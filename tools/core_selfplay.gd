extends SceneTree
## CORE self-play runner (NML-995 core track, S1): full AI-vs-AI matches on
## the BattleSim substrate WITHOUT the game engine — no main.tscn, no models,
## no renderer. One process amortises its ~2s boot over thousands of games,
## replacing minutes-per-game Godot matches for TRAINING DATA generation.
##
## HONESTY GATE (documented, enforced by the roadmap): core results feed
## TRAINING only until the S3 parity ladder proves rule-equivalence against
## engine replays. The ladder A/B stays on the real engine until then.
##
## v0 scope: BattleSim rules (morale, fatigue, fractional wounds, spells EV)
## with STOCHASTIC ROUNDING of expected wounds (mean-preserving; real per-die
## sampling is S4); simple line deployment (no terrain); planner picks per
## activation for BOTH sides via AiPlanner.plan_with_rollout on the live
## core state; official alternation incl. the finished-first round opener.
##
## Run: godot --headless -s res://tools/core_selfplay.gd -- \
##        army1=<json> army2=<json> seed=1 games=100 out=<dir>

const IN2M := 0.0254
const TABLE_W_IN := 72.0
const TABLE_D_IN := 48.0
const ROUNDS := 4
## v4 encoder rows: reference distance for the precomputed shooting EV and
## the declared-rule flag order (columns 14-19).
const EV_REF_DIST_IN := 12.0
const FLAG_RULES: Array[String] = ["Fearless", "Ambush", "Flying", "Stealth", "Furious", "Regeneration"]
## v5: EVERY declared rule reaches the corpus via the committed, append-only
## vocabulary (unit slots 0-99, weapon slots 100-199). Rows append sparse
## pairs [n, slot, value, ...] after column 19 — implemented rules also feed
## the EVs, unimplemented ones at least become learnable signals. A rule the
## vocab does not know is logged LOUDLY and stamped into the result JSON
## (slot assignment happens centrally at collect time, never per box — two
## boxes must not invent diverging slots).
const RULE_VOCAB_PATH := "res://data/encoder_rule_vocab_v1.json"
static var _vocab_unit: Dictionary = {}
static var _vocab_weapon: Dictionary = {}
static var _vocab_loaded := false
static var unknown_rules: Dictionary = {}


static func _load_vocab() -> void:
	if _vocab_loaded:
		return
	_vocab_loaded = true
	var txt := FileAccess.get_file_as_string(RULE_VOCAB_PATH)
	var data: Variant = JSON.parse_string(txt)
	if data is Dictionary:
		var ul: Array = data.get("unit", [])
		for i in ul.size():
			_vocab_unit[str(ul[i])] = i
		var wl: Array = data.get("weapon", [])
		for i in wl.size():
			_vocab_weapon[str(wl[i])] = 100 + i
	else:
		push_warning("core_selfplay: rule vocab unreadable at %s" % RULE_VOCAB_PATH)


## "Tough(3)" / {name:"Tough", rating:3} -> ["Tough", 3]
static func _parse_rule(r: Variant) -> Array:
	if r is Dictionary:
		return [str(r.get("name", "")).strip_edges(), int(r.get("rating", 0))]
	var s := str(r).strip_edges()
	var m := RegEx.create_from_string("^(.*?)\\s*\\((\\d+)\\)\\s*$").search(s)
	if m != null:
		return [m.get_string(1), int(m.get_string(2))]
	return [s, 0]


static func _rule_pairs(gu: Variant, od: OPRApiClient.OPRUnit) -> Array:
	_load_vocab()
	var vals := {}
	for r in gu.get_special_rules():
		var pr := _parse_rule(r)
		if pr[0] == "":
			continue
		if _vocab_unit.has(pr[0]):
			var slot: int = _vocab_unit[pr[0]]
			vals[slot] = maxi(int(vals.get(slot, 0)), int(pr[1]) if pr[1] > 0 else 1)
		elif not unknown_rules.has(pr[0]):
			unknown_rules[pr[0]] = true
			push_warning("core_selfplay: UNKNOWN unit rule '%s' — not in vocab, stamped into result" % pr[0])
	for w in od.weapons:
		for r in w.special_rules:
			var pr := _parse_rule(r)
			if pr[0] == "":
				continue
			if _vocab_weapon.has(pr[0]):
				var slot: int = _vocab_weapon[pr[0]]
				vals[slot] = maxi(int(vals.get(slot, 0)), maxi(int(pr[1]), 1))
			elif not unknown_rules.has(pr[0]):
				unknown_rules[pr[0]] = true
				push_warning("core_selfplay: UNKNOWN weapon rule '%s' — not in vocab, stamped into result" % pr[0])
	var out: Array = []
	var slots := vals.keys()
	slots.sort()
	for s in slots:
		out.append(int(s))
		out.append(int(vals[s]))
	return out

var _army1 := ""
var _army2 := ""
var _seed := 1
var _games := 1
var _out := ""


func _initialize() -> void:
	_parse_args()
	# Script-mode quirk: during _initialize the root window is NOT yet inside
	# the tree, so add_child'ed nodes never enter it and every Node3D position
	# write fails SILENTLY (all units sat at the origin — the S3 gate's whole
	# "melee ball" cluster). Start on the first process frame instead.
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	var t0 := Time.get_ticks_msec()
	var played := 0
	for g in range(_games):
		_play_one(_seed + g)
		played += 1
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	printerr("[CORE] %d games in %.1fs (%.2f games/s)" % [played, dt, played / maxf(dt, 0.001)])
	quit(0)


## One full match: build fresh units, deploy on facing lines, alternate
## activations under the official rules, seize at round ends, score markers.
func _play_one(game_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var units1 := _units_from_list(_army1, 1)
	var units2 := _units_from_list(_army2, 2)
	if units1.is_empty() or units2.is_empty():
		printerr("[CORE] FATAL: empty army (%s / %s)" % [_army1, _army2])
		quit(1)
		return
	var objectives := [Vector3(-16.0 * IN2M, 0, 0), Vector3.ZERO, Vector3(16.0 * IN2M, 0, 0)]
	var patches := _gen_terrain(rng)   # S3: symmetric cover islands
	_deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, rng, patches)
	_deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, rng, patches)
	var state := _capture(units1 + units2, objectives, patches)
	var owners := [0, 0, 0]
	var opener := 1 if rng.randi_range(1, 6) >= rng.randi_range(1, 6) else 2
	var positions_log: Array = []
	for round_no in range(1, ROUNDS + 1):
		state["round"] = round_no
		for k in state["units"]:
			var su: Dictionary = state["units"][k]
			su["activated"] = false
			su["fatigued"] = false
		opener = _play_round(state, opener, rng, positions_log, round_no, game_seed)
		state = _last_state   # adopt the played round (resolve works on clones)
		_seize(state, objectives, owners)
	_write_result(game_seed, owners, positions_log)


## Alternate single activations (official one-for-one; a dry side passes the
## tail to the other). Returns the NEXT round's opener (finished-first rule:
## the side that did NOT take the last activation opens).
func _play_round(state: Dictionary, opener: int, rng: RandomNumberGenerator,
		positions_log: Array, round_no: int, game_seed: int) -> int:
	var turn := opener
	var last_side := 0
	var guard: int = (state["units"] as Dictionary).size() * 2 + 4
	while guard > 0:
		guard -= 1
		var pick := _pick_for(state, turn)
		if pick.is_empty():
			var other := 2 if turn == 1 else 1
			pick = _pick_for(state, other)
			if pick.is_empty():
				break
			turn = other
		var row := {"side": turn, "round": round_no,
			"seq": positions_log.size(),
			"value": float((pick.get("expectation", {}) as Dictionary).get("before", -1.0)),
			"features": AiMissionEval.features(state, turn, BattleSim.reply_threat(state, turn), true),
			"board": _board_rows(state)}
		# E0b (controller-proxy pairs for E2): resolve the CHOSEN and the
		# REJECTED candidate on clones and log both end boards. A log-only
		# rng keeps the game's dice stream untouched (determinism per seed).
		var ru: Dictionary = pick.get("runner_up", {})
		if not ru.is_empty() and ru.has("action"):
			var lrng := RandomNumberGenerator.new()
			lrng.seed = game_seed * 100000 + positions_log.size()
			var b_ch := _board_rows(BattleSim.resolve_stochastic(state, pick["action"], lrng))
			lrng.seed = game_seed * 100000 + positions_log.size() + 50000
			row["pair"] = {"chosen": b_ch,
				"runner": _board_rows(BattleSim.resolve_stochastic(state, ru["action"], lrng))}
		positions_log.append(row)
		state = BattleSim.resolve_stochastic(state, pick["action"], rng)
		last_side = turn
		turn = 2 if turn == 1 else 1
	# writeback: resolve clones — copy the final round state over the caller's
	_last_state = state
	return (2 if last_side == 1 else 1) if last_side != 0 else opener


var _last_state: Dictionary = {}


## E0/E1b/v3 (encoder corpus): raw board state per logged pick. Unit rows are
## [player, x_in, z_in, alive, wounds_left, shaken, fatigued, activated,
##  range_max_in, attacks_total, quality, defense] per LIVING unit (centre in
## table inches; stat line from the OPRUnit source, zeros when unreadable —
## v3: a point on a table says nothing about WHAT it can do, and the day's
## measurements showed input information, not capacity, is the bottleneck).
## Every mission objective adds [3, x_in, z_in, owner, 0,0,0,0, 0,0,0,0] —
## marker 3 in the player slot, owner (0 neutral / 1 / 2) in the alive slot.
## Always on — a silent opt-in knob is how phantoms start.
static func _board_rows(state: Dictionary) -> Array:
	var rows: Array = []
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["alive"]) <= 0:
			continue
		var c := Vector3.ZERO
		for p in su["positions"]:
			c += p as Vector3
		c /= float((su["positions"] as Array).size())
		var wl := 0
		for w in su["wounds"]:
			wl += int(w)
		var rmax := 0
		var atk := 0
		var q := 0
		var d := 0
		var sev := 0.0
		var mev := 0.0
		var flags := [0, 0, 0, 0, 0, 0]
		var gu: Variant = su.get("unit")
		if gu != null and gu.get("source_data") is OPRApiClient.OPRUnit:
			var od: OPRApiClient.OPRUnit = gu.source_data
			q = od.quality
			d = od.defense
			for w in od.weapons:
				rmax = maxi(rmax, w.range_value)
				atk += w.attacks * maxi(w.count, 1)
			# v4: the RULEBOOK, pre-digested — expected wounds vs the neutral
			# reference target via the exact, parity-tested combat math (AP,
			# Deadly, Blast etc. are priced in), plus the loudest unit rules
			# as declared flags. The net gets rule CONSEQUENCES, not prose.
			var att: Dictionary = AiEv.ctx_for(gu)
			sev = snappedf(AiEv.shoot_ev(AiShooting.profiles_in_range(od.weapons, EV_REF_DIST_IN),
				att, AiEv.NEUTRAL_DEFENDER.duplicate(), EV_REF_DIST_IN), 0.01)
			mev = snappedf(AiEv.melee_ev(AiShooting.melee_profiles(od.weapons),
				att, AiEv.NEUTRAL_DEFENDER.duplicate(), true), 0.01)
			for i in FLAG_RULES.size():
				if gu.has_special_rule(FLAG_RULES[i]):
					flags[i] = 1
		var pairs: Array = []
		if gu != null and gu.get("source_data") is OPRApiClient.OPRUnit:
			pairs = _rule_pairs(gu, gu.source_data)
		var row: Array = [int(su["player"]), snappedf(c.x / IN2M, 0.1),
			snappedf(c.z / IN2M, 0.1), int(su["alive"]), wl,
			1 if bool(su.get("shaken", false)) else 0,
			1 if bool(su.get("fatigued", false)) else 0,
			1 if bool(su.get("activated", false)) else 0,
			rmax, atk, q, d, sev, mev,
			flags[0], flags[1], flags[2], flags[3], flags[4], flags[5],
			pairs.size() / 2]
		row.append_array(pairs)
		rows.append(row)
	for o in state.get("objectives", []):
		var op: Vector3 = (o as Dictionary)["pos"]
		rows.append([3, snappedf(op.x / IN2M, 0.1), snappedf(op.z / IN2M, 0.1),
			int((o as Dictionary).get("owner", 0)),
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	return rows


func _pick_for(state: Dictionary, player: int) -> Dictionary:
	var has_pool := false
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["player"]) == player and not bool(su["activated"]) and int(su["alive"]) > 0:
			has_pool = true
			break
	if not has_pool:
		return {}
	# S2: NML_CORE_ACTOR=policy plays the cheap greedy policy instead of the
	# full planner — volume data generation (states + outcomes) at a fraction
	# of the cost; planner remains the default for quality data.
	if OS.get_environment("NML_CORE_ACTOR") == "policy":
		var a := AiPlanner._policy_step(state, player, true)
		return {} if a.is_empty() else {"used": true, "action": a}
	var pick := AiPlanner.plan_with_rollout(state, player)
	return pick if bool(pick.get("used", false)) else {}


## Round-end seize (persistence rule): majority of non-shaken alive units
## within 3" wins the marker; both near => neutral; nobody near keeps owner.
func _seize(state: Dictionary, objectives: Array, owners: Array) -> void:
	state = _last_state if not _last_state.is_empty() else state
	for i in range(objectives.size()):
		var near1 := 0
		var near2 := 0
		for k in state["units"]:
			var su: Dictionary = state["units"][k]
			if int(su["alive"]) <= 0 or bool(su.get("shaken", false)):
				continue
			for p in su["positions"]:
				if ((p as Vector3) - (objectives[i] as Vector3)).length() <= 3.0 * IN2M:
					if int(su["player"]) == 1:
						near1 += 1
					else:
						near2 += 1
					break
		if near1 > near2:
			owners[i] = 1
		elif near2 > near1:
			owners[i] = 2
		elif near1 > 0:
			owners[i] = 0
		# S3 fix: write ownership back into the STATE — features/eval read the
		# objectives' owner field, which otherwise stays 0 all game (S3-light
		# found obj_owned_* frozen at zero in every core position).
		if i < (state["objectives"] as Array).size():
			((state["objectives"] as Array)[i] as Dictionary)["owner"] = owners[i]


## Lightweight GameUnits from an Army-Forge list JSON — the test-fixture
## recipe (unit_properties + OPRUnit weapons + positionless models), no 3D.
func _units_from_list(path: String, player: int) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return []
	var out: Array = []
	var uidx := 0
	# Engine unit accounting (verified on round-1 snapshots): COMBINED pairs
	# (combined:true + joinToUnit) merge into ONE unit with pooled models and
	# weapons; attached HEROES (combined:false + joinToUnit) stay separate.
	var raw: Array = (data as Dictionary).get("units", [])
	var by_sel := {}
	for u in raw:
		var ud := u as Dictionary
		if ud.get("joinToUnit") and bool(ud.get("combined", false)):
			continue   # folded into its partner in the second pass
		var gu := GameUnit.new()
		gu.unit_id = "p%d_%d_%s" % [player, uidx, str(ud.get("id", uidx))]
		uidx += 1
		var rules: Array = []
		for r in ud.get("rules", []):
			var rn := str((r as Dictionary).get("label", (r as Dictionary).get("name", "")))
			if rn != "":
				rules.append(rn)
		gu.unit_properties = {"player_id": player, "name": str(ud.get("name", "Unit")),
			"quality": int(ud.get("quality", 4)), "defense": int(ud.get("defense", 4)),
			"special_rules": rules}
		gu.source_type = "opr"
		gu.source_data = OPRApiClient.OPRUnit.new()
		_append_selection(gu, ud)
		by_sel[str(ud.get("selectionId", ""))] = gu
		out.append(gu)
	for u in raw:
		var ud := u as Dictionary
		if not (ud.get("joinToUnit") and bool(ud.get("combined", false))):
			continue
		var host: GameUnit = by_sel.get(str(ud["joinToUnit"]), null)
		if host != null:
			_append_selection(host, ud)
		else:
			printerr("[CORE] WARN: combined partner %s not found" % str(ud["joinToUnit"]))
	return out


## Adds one selection's models (with their Tough pools) and weapons to a unit —
## used for the base selection and again for its combined partner.
func _append_selection(gu: GameUnit, ud: Dictionary) -> void:
	for w in ud.get("weapons", []):
		var wd := w as Dictionary
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str(wd.get("name", "W"))
		ow.range_value = int(wd.get("range", 0))
		ow.attacks = int(wd.get("attacks", 1))
		ow.count = maxi(int(wd.get("count", 1)), 1)
		for wr in wd.get("specialRules", []):
			var wl := str((wr as Dictionary).get("label", (wr as Dictionary).get("name", "")))
			if wl != "":
				ow.special_rules.append(wl)
		(gu.source_data as OPRApiClient.OPRUnit).weapons.append(ow)
	var tough := 1
	for r in ud.get("rules", []):
		var rl := str((r as Dictionary).get("label", (r as Dictionary).get("name", "")))
		if rl.begins_with("Tough("):
			tough = maxi(int(rl.trim_prefix("Tough(").trim_suffix(")")), 1)
	for _m in range(int(ud.get("size", 1))):
		var mi := ModelInstance.new()
		mi.is_alive = true
		mi.wounds_current = tough
		mi.wounds_max = tough
		mi.unit = gu
		var n := Node3D.new()
		root.add_child(n)
		mi.node = n
		gu.models.append(mi)


## S3: 12"-deep ZONE deployment — units spread across width AND depth (the
## naive single line doubled charge-exposure density vs engine positions).
func _deploy_zone(units: Array, z0_in: float, depth_in: float, rng: RandomNumberGenerator,
		patches: Array = []) -> void:
	var n := units.size()
	for i in range(n):
		var gu: GameUnit = units[i]
		var x0 := (-TABLE_W_IN / 2.0 + 8.0) + (TABLE_W_IN - 16.0) * (float(i) + 0.5) / float(n)
		# Plain random spot in the zone slot: measured per-round engine profile
		# (round-1 cover 0.31 of ~4.4 units) matches the islands' natural overlap
		# with the zone — active cover-seeking overshot it 5x.
		var best_x := x0 + rng.randf_range(-3.0, 3.0)
		var best_z := z0_in + rng.randf_range(1.0, depth_in - 3.0)
		for m in range(gu.models.size()):
			(gu.models[m] as ModelInstance).node.global_position = Vector3(
				(best_x + float(m % 5)) * IN2M, 0.0, (best_z + float(m / 5)) * IN2M)


## S3: point-symmetric cover islands (forest-class), radius 4", mirrored so
## neither side owns better ground. Returned as [{pos: Vector3, r: float}].
func _gen_terrain(rng: RandomNumberGenerator) -> Array:
	var patches: Array = []
	for _i in range(3):
		var x := rng.randf_range(-TABLE_W_IN / 2.0 + 8.0, TABLE_W_IN / 2.0 - 8.0)
		var z := rng.randf_range(1.0, TABLE_D_IN / 2.0 - 2.0)
		var r := rng.randf_range(4.0, 5.0)
		patches.append({"pos": Vector3(x * IN2M, 0, z * IN2M), "r": r * IN2M})
		patches.append({"pos": Vector3(-x * IN2M, 0, -z * IN2M), "r": r * IN2M})
	return patches


static func _terrain_type_at(patches: Array, pos: Vector3) -> int:
	for pt in patches:
		var d: Dictionary = pt
		var p: Vector3 = d["pos"]
		if Vector2(pos.x - p.x, pos.z - p.z).length() <= float(d["r"]):
			return TerrainRules.TerrainType.FOREST
	return TerrainRules.TerrainType.NONE


func _capture(all_units: Array, objectives: Array, patches: Array) -> Dictionary:
	var army := OPRArmyManager.new()
	root.add_child(army)
	var gu := {}
	for u in all_units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	var objs := objectives.duplicate()
	var terrain_at := func(pos: Vector3) -> int: return _terrain_type_at(patches, pos)
	var cover_of := func(u: GameUnit) -> bool:
		var c := Vector3.ZERO
		var alive := 0
		for m in u.models:
			var mi := m as ModelInstance
			if mi != null and mi.is_alive and mi.node != null:
				c += mi.node.global_position
				alive += 1
		if alive == 0:
			return false
		return TerrainRules.gives_cover(_terrain_type_at(patches, c / alive))
	# Dynamic LOS: forests block sight THROUGH them (2" line samples); a unit
	# standing inside forest can still shoot out / be shot (it has cover).
	var los_blocked := func(a: Vector3, b: Vector3) -> bool:
		if _terrain_type_at(patches, a) != TerrainRules.TerrainType.NONE \
				or _terrain_type_at(patches, b) != TerrainRules.TerrainType.NONE:
			return false
		var steps := int(ceilf((b - a).length() / (2.0 * IN2M)))
		for i in range(1, steps):
			if _terrain_type_at(patches, a.lerp(b, float(i) / steps)) \
					== TerrainRules.TerrainType.FOREST:
				return true
		return false
	var st := BattleSim.capture(army, func() -> Array: return objs,
		func(_i: int) -> int: return 0, 1, ROUNDS, cover_of, Callable(), terrain_at)
	st["los_blocked"] = los_blocked
	return st


func _write_result(game_seed: int, owners: Array, positions_log: Array) -> void:
	var p1 := 0
	var p2 := 0
	for o in owners:
		if int(o) == 1:
			p1 += 1
		elif int(o) == 2:
			p2 += 1
	var winner := "draw"
	if p1 != p2:
		winner = "p1" if p1 > p2 else "p2"
	var result := {"schema": 1, "board_schema": 5, "rule_vocab": "v1",
		"unknown_rules": unknown_rules.keys(),
		"tool": "core_selfplay", "seed": game_seed,
		"dice_seed": game_seed, "grades": {"p1": "planner_core", "p2": "planner_core"},
		"mission": {"family": "face_off", "name": "duel", "rounds": ROUNDS,
			"deployment": "zone12", "symmetric": true, "objective_count": 3, "packs": []},
		"armies": {"p1": _army1, "p2": _army2}, "opener": 0,
		"objectives": {"p1": p1, "p2": p2, "neutral": owners.size() - p1 - p2},
		"winner": winner, "planner_positions": positions_log, "planner_calib": []}
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
		var f := FileAccess.open(_out.path_join("core_s%d.json" % game_seed), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(result))
			f.close()
	printerr("[CORE] RESULT seed=%d P1=%d P2=%d -> %s" % [game_seed, p1, p2, winner])


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"army1": _army1 = kv[1]
			"army2": _army2 = kv[1]
			"seed": _seed = int(kv[1])
			"games": _games = int(kv[1])
			"out": _out = kv[1]

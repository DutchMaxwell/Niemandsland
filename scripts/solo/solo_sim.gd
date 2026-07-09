class_name SoloSim
extends RefCounted
## Headless AI-vs-AI game simulator (goal 003 — self-play). Plays a whole game with NO UI: no dice tray,
## no prompts, no camera — dice come from a SEEDED RNG and every combat/decision uses the SAME pure
## modules the real game uses (AiArchetype, AiDecision, AiShooting, AiCombatMath). That shared logic IS
## the correctness link to the real game.
##
## Board: 2D 4×4 ft table, 12" deployment zones, two mission objectives, and optional terrain (a grid of
## typed 3" cells — the SAME model as the game's terrain_overlay.gd; see TerrainRules). Rules verified
## against the official GF Advanced Rules v3.5.1 rulebook (2026-07-08):
##  • Actions (p.7): Hold (no move, may shoot) / Advance (6", may shoot) / Rush (12", no shoot) /
##    Charge (12" into melee).
##  • Shooting (p.8) & Melee (p.9): sum attacks of models in range → roll to hit at Quality → defender
##    rolls to block at Defense → unblocked = wounds. Melee: defender may strike back; the loser (more
##    wounds taken) tests morale (p.10). Fatigue (p.9): after its first melee in a round a unit hits only
##    on unmodified 6s in melee.
##  • Shaken (p.10): a Shaken unit stays IDLE when activated (recovering at the end of that activation);
##    it may strike back COUNTING AS FATIGUED, ALWAYS fails morale tests, and can't seize or contest
##    objectives. (No stat penalty — an earlier web-sourced "-1 Q/D, half move" reading was wrong.)
##  • Morale (p.10): test at the end of an activation where wounds leave a unit at ≤ half; the melee loser
##    tests. Fail + ≤ half size → Rout (destroyed), else Shaken. There is NO end-of-round army morale.
##  • Mission (p.6): seize a marker at the END OF EACH ROUND with a unit within 3" and no enemy within 3";
##    a seized marker STAYS seized when the unit leaves; both sides within 3" → neutral. After 4 rounds
##    the player controlling most markers wins (you never win purely by wiping the enemy).
##  • Terrain (p.11-12, TerrainRules — shared with terrain_overlay.gd): a shot needs clear LOS (Ruins/
##    Forest/Container block it); a unit with the majority of its models in Cover (Ruins/Forest) is +1
##    Defense vs shooting; Difficult (Forest) halves a move crossing it; Dangerous rolls one die per model
##    crossing it (a 1 = one wound). Passing no terrain (default) = open field, every rule inert.
##
## A unit is a plain Dictionary (see make_unit). Deterministic: same seed → same game.

const BOARD_IN := 48.0
const DEPLOY_IN := 12.0
const CONTACT_IN := 2.0
const OBJECTIVE_CONTROL_IN := 3.0
const DEFAULT_ROUNDS := 4
const MODEL_HEIGHT := 1   # every sim model is ground infantry (Height 1); tall/vehicle heights are a follow-up


static func default_objectives() -> Array:
	return [Vector2(BOARD_IN / 3.0, BOARD_IN / 2.0), Vector2(BOARD_IN * 2.0 / 3.0, BOARD_IN / 2.0)]


## A seeded, reflection-symmetric (across the board mid-line, y = 24") terrain layout on the 3" grid — the
## exact grid_cells model terrain_overlay.gd uses. Symmetry keeps the mirror-match fairness oracle intact
## (both deployment zones get equivalent cover) and matches how balanced OPR tables are laid out. Blobs sit
## in the bottom half and are mirrored to the top; the mid-line row (where the objectives sit) stays clear.
static func default_terrain(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cells := {}
	var n: int = int(BOARD_IN / TerrainRules.CELL_IN)   # 16 cells per axis
	var pieces := [
		{"type": TerrainRules.TerrainType.FOREST, "w": 2, "h": 2},
		{"type": TerrainRules.TerrainType.RUINS, "w": 2, "h": 2},
		{"type": TerrainRules.TerrainType.CONTAINER, "w": 1, "h": 2},
		{"type": TerrainRules.TerrainType.DANGEROUS, "w": 2, "h": 1},
	]
	for piece in pieces:
		var pw: int = int(piece["w"])
		var ph: int = int(piece["h"])
		var cx: int = rng.randi_range(1, n - pw - 1)
		var cy: int = rng.randi_range(1, n / 2 - ph - 1)   # bottom half only (mid-line stays clear)
		for dx in range(pw):
			for dy in range(ph):
				var c := Vector2i(cx + dx, cy + dy)
				cells[c] = int(piece["type"])
				cells[Vector2i(c.x, n - 1 - c.y)] = int(piece["type"])   # mirror across the mid-line
	return cells


## Terrain grid as JSON-friendly [cx, cy, type] triples for the replay viewer (cell = 3", board = 48").
static func _terrain_cells_json(terrain: Dictionary) -> Array:
	var out: Array = []
	for c in terrain:
		out.append([(c as Vector2i).x, (c as Vector2i).y, int(terrain[c])])
	return out


static func make_unit(name: String, player: int, quality: int, defense: int, models: int, weapons: Array,
		tough: int = 1, rules: Array = [], advance_in: float = 6.0, rush_in: float = 12.0) -> Dictionary:
	return {
		"name": name, "player": player, "quality": quality, "defense": defense,
		"tough": maxi(tough, 1), "max_models": models, "wounds_pool": 0,
		"weapons": weapons, "rules": rules,
		"pos": Vector2.ZERO,       # formation centre (for the high-level decision/movement)
		"model_pos": [],           # per-model positions (set at deploy) — the unit moves as a formation
		"advance_in": advance_in, "rush_in": rush_in,
		"activated": false, "shaken": false, "fatigued": false,
	}


static func units_from_opr_json(data: Dictionary, player: int) -> Array:
	# Parse every raw unit into a temp record keyed by its selectionId.
	var parsed: Dictionary = {}
	var order: Array = []
	for u in data.get("units", []):
		var unit := u as Dictionary
		var sel := str(unit.get("selectionId", str(order.size())))
		var rule_names: Array = []
		var tough := 1
		for r in unit.get("rules", []):
			var rn := str((r as Dictionary).get("name", ""))
			rule_names.append(rn)
			if rn == "Tough":
				tough = maxi(int((r as Dictionary).get("rating", 1)), 1)
		var weapons: Array = []
		for w in unit.get("loadout", []):
			var wd := w as Dictionary
			if not wd.has("attacks"):
				continue
			var ap := 0
			for sr in wd.get("specialRules", []):
				if str((sr as Dictionary).get("name", "")) == "AP":
					ap = int((sr as Dictionary).get("rating", 0))
			weapons.append({
				"name": str(wd.get("name", "Weapon")),
				"range_value": int(wd.get("range", 0)),
				"attacks": int(wd.get("attacks", 1)),
				"count": maxi(int(wd.get("count", 1)), 1),
				"special_rules": (["AP(%d)" % ap] if ap > 0 else []),
			})
		parsed[sel] = {
			"name": str(unit.get("name", "Unit")), "quality": int(unit.get("quality", 4)),
			"defense": int(unit.get("defense", 4)), "size": maxi(int(unit.get("size", 1)), 1),
			"weapons": weapons, "tough": tough, "rules": rule_names,
			"join_to": str(unit.get("joinToUnit", "")), "merged": false,
		}
		order.append(sel)
	# Merge joiners (combined-unit halves + joined heroes) INTO their target: models + weapons add up, so
	# a combined pair (2×5) becomes one unit of 10 — matching how the game imports them.
	for sel in order:
		var p: Dictionary = parsed[sel]
		var jt: String = p["join_to"]
		if jt != "" and parsed.has(jt):
			var tgt: Dictionary = parsed[jt]
			tgt["size"] = int(tgt["size"]) + int(p["size"])
			tgt["weapons"] = (tgt["weapons"] as Array) + (p["weapons"] as Array)
			tgt["tough"] = maxi(int(tgt["tough"]), int(p["tough"]))
			p["merged"] = true
	var out: Array = []
	for sel in order:
		var p: Dictionary = parsed[sel]
		if bool(p["merged"]):
			continue
		out.append(make_unit(str(p["name"]), player, int(p["quality"]), int(p["defense"]),
			int(p["size"]), _merge_weapon_types(p["weapons"]), int(p["tough"]), p["rules"]))
	return out


## OPR shooting (rulebook p.8 "Multiple Weapon Types" / "Determine Attacks"): weapons of the SAME type
## are one group and roll together at one target. Combine identical profiles (name + range + AP) by
## summing their model counts, so e.g. two Heavy Machineguns become one 2×-count group rolled at once,
## instead of two separate rolls (maintainer finding). Different types stay separate.
static func _merge_weapon_types(weapons: Array) -> Array:
	var groups: Dictionary = {}
	var order: Array = []
	for w in weapons:
		var wd := w as Dictionary
		var key := "%s|%d|%d|%s" % [str(wd["name"]), int(wd["range_value"]), int(wd["attacks"]), str(wd["special_rules"])]
		if groups.has(key):
			groups[key]["count"] = int(groups[key]["count"]) + int(wd["count"])
		else:
			groups[key] = wd.duplicate(true)
			order.append(key)
	var out: Array = []
	for k in order:
		out.append(groups[k])
	return out


static func alive_models(u: Dictionary) -> int:
	return maxi(0, int(u["max_models"]) - int(u["wounds_pool"]) / int(u["tough"]))


static func is_alive(u: Dictionary) -> bool:
	return alive_models(u) > 0


static func simulate_game(army_a: Array, army_b: Array, seed_value: int, max_rounds: int = DEFAULT_ROUNDS,
		log_lines: Array = [], objectives: Array = [], trace: Array = [], terrain: Dictionary = {}) -> Dictionary:
	var objs: Array = objectives if not objectives.is_empty() else default_objectives()
	var obj_owner: Array = []
	for _o in objs:
		obj_owner.append(-1)   # -1 = neutral / unseized
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var units: Array = []
	for u in army_a:
		units.append((u as Dictionary).duplicate(true))
	for u in army_b:
		units.append((u as Dictionary).duplicate(true))
	for i in range(units.size()):
		units[i]["_id"] = i   # stable id for the visual trace
	_deploy(units)
	if trace != null:
		trace.append({"type": "deploy", "board": _snapshot(units, obj_owner)})
	var a_start := _side_models(units, 0)
	var b_start := _side_models(units, 1)
	var activations := 0
	var end_reason := "round_limit"
	var round_no := 0
	for r in range(1, max_rounds + 1):
		round_no = r
		for u in units:
			u["activated"] = false
		log_lines.append("── Round %d ──" % r)
		# OPR: the deployment roll-off winner goes first on round 1, then the player who finished first
		# activates first each round. We roll off each round (a fixed first player was a systematic bias
		# the mirror test caught).
		var side := rng.randi_range(0, 1)
		while _has_unactivated(units, 0) or _has_unactivated(units, 1):
			if _has_unactivated(units, side):
				var actor: Variant = _next_unactivated(units, side)
				if actor != null:
					activations += 1
					_activate(actor, units, rng, log_lines, r, obj_owner, objs, trace, terrain)
			side = 1 - side
		# End of round: fatigue clears; then objectives are (re)seized.
		for u in units:
			u["fatigued"] = false
		_seize_objectives(units, objs, obj_owner, log_lines)
		if trace != null:
			trace.append({"type": "seize", "round": r, "board": _snapshot(units, obj_owner)})
		if _side_models(units, 0) == 0 or _side_models(units, 1) == 0:
			end_reason = "wipe"
			break
	var a_alive := _side_models(units, 0)
	var b_alive := _side_models(units, 1)
	var a_obj := obj_owner.count(0)
	var b_obj := obj_owner.count(1)
	# Mission decides the winner (you never win purely by wiping); surviving models as the tiebreak.
	var winner := -1
	if a_obj != b_obj:
		winner = 0 if a_obj > b_obj else 1
	elif a_alive != b_alive:
		winner = 0 if a_alive > b_alive else 1
	return {
		"winner": winner, "rounds": round_no, "end_reason": end_reason,
		"a_alive": a_alive, "b_alive": b_alive, "a_start": a_start, "b_start": b_start,
		"a_losses": a_start - a_alive, "b_losses": b_start - b_alive, "activations": activations,
		"a_objectives": a_obj, "b_objectives": b_obj, "terrain": _terrain_cells_json(terrain),
	}


static func _deploy(units: Array) -> void:
	for player in [0, 1]:
		var side: Array = []
		for u in units:
			if u["player"] == player:
				side.append(u)
		var z: float = DEPLOY_IN * 0.5 if player == 0 else (BOARD_IN - DEPLOY_IN * 0.5)
		for i in range(side.size()):
			var x: float = BOARD_IN * float(i + 1) / float(side.size() + 1)
			side[i]["pos"] = Vector2(x, z)
			side[i]["model_pos"] = _formation(Vector2(x, z), alive_models(side[i]))


## Lay out `n` individual models in a compact grid around `centre` (~1.5" spacing) — the unit's starting
## formation. Each model has its own position from here on; the unit moves as a rigid formation.
static func _formation(centre: Vector2, n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var cols: int = int(ceil(sqrt(float(n))))
	var sp := 1.5
	var w: float = float(cols - 1) * sp
	for k in range(n):
		var col: int = k % cols
		var row: int = k / cols
		out.append(Vector2(centre.x + float(col) * sp - w / 2.0, centre.y + float(row) * sp - w / 2.0))
	return out


# === Activation (mirrors SoloController._act on the 2D board) ===

static func _activate(unit: Dictionary, units: Array, rng: RandomNumberGenerator, log_lines: Array,
		round_no: int = 0, obj_owner: Array = [], objectives: Array = [], trace: Array = [],
		terrain: Dictionary = {}) -> void:
	unit["activated"] = true
	var rolls: Array = []   # dice detail recorded for the visual trace
	# OPR (p.10): a Shaken unit spends its activation idle, which clears Shaken at the end of it.
	if unit["shaken"]:
		unit["shaken"] = false
		log_lines.append("%s spends its activation idle — recovers from Shaken" % unit["name"])
		_trace_activation(trace, unit, round_no, "IDLE (recover Shaken)", null, 0.0, rolls, units, obj_owner)
		return
	var target: Variant = _pick_target(unit, units, INF)   # nearest, PREFERRING not-yet-activated (p.2)
	if target == null:
		return
	var upos: Vector2 = unit["pos"]
	var tpos: Vector2 = target["pos"]
	var weapons: Array = unit["weapons"]
	var archetype: int = AiArchetype.classify(weapons)
	var shoot_range: int = AiArchetype.max_range_inches(weapons)
	var advance: float = float(unit["advance_in"])
	var rush: float = float(unit["rush_in"])
	var enemy_dist: float = upos.distance_to(tpos)
	# Nearest objective NOT under this side's control (persistent owner). The official trees pivot on it.
	var side: int = int(unit["player"])
	var obj_pos: Vector2 = Vector2.INF
	var obj_dist: float = INF
	for oi in range(objectives.size()):
		if oi < obj_owner.size() and int(obj_owner[oi]) == side:
			continue   # already ours → controlled
		var d: float = upos.distance_to(objectives[oi])
		if d < obj_dist:
			obj_dist = d
			obj_pos = objectives[oi]
	var has_obj: bool = obj_pos != Vector2.INF
	# Enemies "in the way" to the objective: within 6" of the unit→objective path (p.58).
	var in_way: bool = false
	if has_obj:
		for e in units:
			if e["player"] != side and is_alive(e) and _seg_dist(upos, obj_pos, e["pos"]) <= 6.0:
				in_way = true
				break
	var ctx := {
		"arch": archetype, "objective": has_obj, "in_way": in_way,
		"obj_in_advance": obj_dist <= advance + OBJECTIVE_CONTROL_IN,
		"obj_in_rush": obj_dist <= rush + OBJECTIVE_CONTROL_IN,
		"enemy_in_charge": enemy_dist <= rush,
		"shoot_after_advance": shoot_range > 0 and (enemy_dist - advance) <= float(shoot_range),
	}
	var dec: Dictionary = AiDecision.decide_solo(ctx)
	var action: int = int(dec["action"])
	var to_obj: bool = int(dec["toward"]) == AiDecision.Toward.OBJECTIVE and has_obj
	var goal: Vector2 = obj_pos if to_obj else tpos
	var goal_dist: float = upos.distance_to(goal)
	var gdir: Vector2 = (goal - upos).normalized() if goal_dist > 0.0001 else Vector2.ZERO
	var edir: Vector2 = (tpos - upos).normalized() if enemy_dist > 0.0001 else Vector2.ZERO
	match action:
		AiDecision.Action.RUSH:
			# STOP AT the objective, never march past it (p.58: seize within 3", "as close as possible").
			# The maintainer's finding: units overshot the marker and abandoned it.
			_terrain_move(unit, gdir * (minf(rush, goal_dist) if to_obj else rush), terrain, rng, log_lines, rolls)
		AiDecision.Action.CHARGE:
			_terrain_move(unit, edir * minf(rush, maxf(enemy_dist - CONTACT_IN, 0.0)), terrain, rng, log_lines, rolls)
		AiDecision.Action.ADVANCE:
			if to_obj:
				# stop on the objective, don't overshoot
				_terrain_move(unit, gdir * minf(advance, goal_dist), terrain, rng, log_lines, rolls)
			else:
				# "Advancing" rule (p.58): a shooter advancing on the enemy stays as FAR as possible while
				# still in range — step back to the range edge if already inside it, else close to get in
				# range. It never flees off-board and always shoots (no kiting).
				if enemy_dist <= float(shoot_range):
					_terrain_move(unit, -edir * minf(advance, float(shoot_range) - enemy_dist), terrain, rng, log_lines, rolls)
				else:
					_terrain_move(unit, edir * advance, terrain, rng, log_lines, rolls)
		_:
			pass   # HOLD
	var dist: float = (unit["pos"] as Vector2).distance_to(tpos)
	var label: String = _decision_label(action, to_obj, bool(dec["shoot"]))
	# Resolve combat against the priority target (p.2 "prioritise units that haven't activated yet"):
	# melee hits whoever we charged; shooting re-picks the nearest un-activated enemy that is IN RANGE.
	var combat_target: Variant = target
	if action == AiDecision.Action.CHARGE and dist <= CONTACT_IN + 0.001:
		_resolve_melee(unit, target, rng, log_lines, rolls)
	elif bool(dec["shoot"]) and shoot_range > 0:
		# Valid shooting target = nearest un-activated enemy IN RANGE and with clear LOS (terrain blocks it).
		var st: Variant = _pick_target(unit, units, float(shoot_range), terrain, true)
		if st != null:
			combat_target = st
			_resolve_shooting(unit, st, (unit["pos"] as Vector2).distance_to(st["pos"]), rng, log_lines, rolls, terrain)
	var why := {"arch": ["MELEE", "SHOOTING", "HYBRID"][archetype], "range": shoot_range,
		"objective": has_obj, "obj_dist": (snappedf(obj_dist, 0.1) if has_obj else -1.0),
		"toward": ("objective" if to_obj else "enemy"), "in_way": in_way, "dist0": snappedf(enemy_dist, 0.1),
		"target_fresh": (combat_target != null and not bool(combat_target["activated"]))}
	log_lines.append("%s: %s (%.0f\" to %s)" % [unit["name"], label, enemy_dist, target["name"]])
	_trace_activation(trace, unit, round_no, label, combat_target, dist, rolls, units, obj_owner, why)


## Human-readable decision label for the log + replay.
static func _decision_label(action: int, to_obj: bool, shoot: bool) -> String:
	var t: String = " (objective)" if to_obj else " (enemy)"
	match action:
		AiDecision.Action.CHARGE:
			return "charges"
		AiDecision.Action.RUSH:
			return "rushes" + t
		AiDecision.Action.ADVANCE:
			return ("advances+shoots" if shoot else "advances") + t
		_:
			return "holds"


## Distance from point p to the segment a→b (for the "enemies in the way" 6" path check).
static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# === Combat resolution (uses AiShooting + AiCombatMath, dice from the seeded RNG) ===

static func _resolve_shooting(attacker: Dictionary, target: Dictionary, dist: float,
		rng: RandomNumberGenerator, log_lines: Array, rolls: Array = [], terrain: Dictionary = {}) -> void:
	var profiles: Array = AiShooting.profiles_in_range(attacker["weapons"], dist)
	if profiles.is_empty():
		return
	var alive_before := alive_models(target)
	var quality: int = int(attacker["quality"])
	var defense: int = int(target["defense"])
	# Cover (p.11): a target with the majority of its models in cover gets +1 to block rolls — modelled as a
	# better (lower) save target, floored at 2+ (a 1 always fails). Applies to shooting only.
	var in_cover: bool = not terrain.is_empty() and TerrainRules.majority_in_cover(target["model_pos"], terrain)
	if in_cover:
		defense = maxi(2, defense - 1)
		log_lines.append("%s is in cover (+1 Defense)" % target["name"])
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, _effective_attacks(attacker, int(profile["attacks"])))
		var hits := AiCombatMath.count_hits(faces, quality)
		var save_faces: Array = [] if hits <= 0 else _roll(rng, hits)
		var w: int = 0 if hits <= 0 else AiCombatMath.wounds(hits, save_faces, defense, int(profile["ap"]))
		total += w
		_trace_roll(rolls, "shoot", attacker["name"], target["name"], str(profile["name"]),
			faces, quality, hits, save_faces, defense + int(profile["ap"]), w, in_cover)
	if total > 0:
		_apply_wounds(target, total)
		log_lines.append("%s shoots %s → %d wound(s)" % [attacker["name"], target["name"], total])
	# General morale (p.10): a unit left at half or less by the wounds it just took must test.
	if AiCombatMath.should_test_shooting_morale(alive_before, alive_models(target), int(target["max_models"])):
		_morale(target, rng, log_lines, rolls)


static func _resolve_melee(attacker: Dictionary, target: Dictionary, rng: RandomNumberGenerator,
		log_lines: Array, rolls: Array = []) -> void:
	var dealt := _strike(attacker, target, rng, log_lines, rolls, "charge")
	if dealt > 0:
		_apply_wounds(target, dealt)
	# The defender MAY strike back (Shaken units strike back as fatigued — handled in _strike).
	var struck_back := 0
	if is_alive(target):
		struck_back = _strike(target, attacker, rng, log_lines, rolls, "strike back")
		if struck_back > 0:
			_apply_wounds(attacker, struck_back)
	attacker["fatigued"] = true
	target["fatigued"] = true
	log_lines.append("%s charges %s → %d dealt, %d back" % [attacker["name"], target["name"], dealt, struck_back])
	# Melee morale (p.10): only the loser (more wounds taken) tests.
	if dealt > struck_back and is_alive(target):
		_morale(target, rng, log_lines, rolls)
	elif struck_back > dealt and is_alive(attacker):
		_morale(attacker, rng, log_lines, rolls)


## One striker's melee output. Fatigued OR Shaken → hits only on unmodified 6s; else its Quality.
static func _strike(striker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator,
		_log_lines: Array = [], rolls: Array = [], kind: String = "melee") -> int:
	var profiles: Array = AiShooting.melee_profiles(striker["weapons"])
	var to_hit: int = 6 if (bool(striker["fatigued"]) or bool(striker["shaken"])) else int(striker["quality"])
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, _effective_attacks(striker, int(profile["attacks"])))
		var hits := AiCombatMath.count_hits(faces, to_hit)
		var save_faces: Array = [] if hits <= 0 else _roll(rng, hits)
		var w: int = 0 if hits <= 0 else AiCombatMath.wounds(hits, save_faces, int(defender["defense"]), int(profile["ap"]))
		total += w
		_trace_roll(rolls, kind, striker["name"], defender["name"], str(profile["name"]),
			faces, to_hit, hits, save_faces, int(defender["defense"]) + int(profile["ap"]), w)
	return total


## OPR morale (p.10): roll 1 die vs Quality (a Shaken unit ALWAYS fails). Fail + ≤ half size → Rout
## (destroyed), else the unit becomes Shaken.
static func _morale(unit: Dictionary, rng: RandomNumberGenerator, log_lines: Array, rolls: Array = []) -> void:
	var passed := false
	var face: int = -1
	if not bool(unit["shaken"]):
		face = int(_roll(rng, 1)[0])
		passed = DiceRules.is_success(face, int(unit["quality"]), 0)
	if passed:
		log_lines.append("%s passes morale" % unit["name"])
		_trace_morale(rolls, unit["name"], face, int(unit["quality"]), "pass")
		return
	if AiCombatMath.at_or_below_half(alive_models(unit), int(unit["max_models"])):
		unit["wounds_pool"] = int(unit["max_models"]) * int(unit["tough"])   # wiped
		log_lines.append("%s ROUTS (destroyed)" % unit["name"])
		_trace_morale(rolls, unit["name"], face, int(unit["quality"]), "rout")
	else:
		unit["shaken"] = true
		_trace_morale(rolls, unit["name"], face, int(unit["quality"]), "shaken")
		log_lines.append("%s is Shaken" % unit["name"])


## Seize objectives at round end (p.6): a marker is taken by the side with a non-Shaken unit within 3"
## and no enemy within 3". A seized marker STAYS with its owner if nobody is near; both sides near → it
## goes neutral. Shaken units can neither seize NOR contest. Mutates obj_owner in place.
static func _seize_objectives(units: Array, objectives: Array, obj_owner: Array, log_lines: Array) -> void:
	for i in range(objectives.size()):
		var near0 := false
		var near1 := false
		for u in units:
			if not is_alive(u) or bool(u["shaken"]):
				continue   # Shaken units can't seize or contest
			# A SINGLE model within 3" holds the objective (per-model now, not the formation centre).
			var holds := false
			for m in u["model_pos"]:
				if (m as Vector2).distance_to(objectives[i]) <= OBJECTIVE_CONTROL_IN:
					holds = true
					break
			if holds:
				if u["player"] == 0:
					near0 = true
				else:
					near1 = true
		if near0 and near1:
			if obj_owner[i] != -1:
				log_lines.append("Objective %d contested → neutral" % i)
			obj_owner[i] = -1
		elif near0 and obj_owner[i] != 0:
			obj_owner[i] = 0
			log_lines.append("Objective %d seized by Army 0" % i)
		elif near1 and obj_owner[i] != 1:
			obj_owner[i] = 1
			log_lines.append("Objective %d seized by Army 1" % i)
		# nobody near → owner unchanged (persistent)


## OPR "Determine Attacks": only the weapons of models that are still ALIVE count. Our weapon `count` is
## the starting model count, so scale a group's attacks by the surviving fraction — otherwise dead models
## keep attacking (maintainer found this in melee). Rounds to the nearest whole die.
static func _effective_attacks(unit: Dictionary, base_attacks: int) -> int:
	var mx: int = int(unit["max_models"])
	if mx <= 0:
		return base_attacks
	return maxi(0, int(round(float(base_attacks) * float(alive_models(unit)) / float(mx))))


static func _apply_wounds(unit: Dictionary, w: int) -> void:
	unit["wounds_pool"] = int(unit["wounds_pool"]) + maxi(w, 0)
	# Remove dead models from the formation, back rank first (defender-optimal, matches the game).
	var mp: Array = unit["model_pos"]
	while mp.size() > alive_models(unit):
		mp.pop_back()


# === Helpers ===

static func _roll(rng: RandomNumberGenerator, n: int) -> Array:
	var faces: Array = []
	for i in range(maxi(n, 0)):
		faces.append(rng.randi_range(1, 6))
	return faces


static func _move(unit: Dictionary, delta: Vector2) -> void:
	var old: Vector2 = unit["pos"]
	var np := Vector2(clampf(old.x + delta.x, 0.0, BOARD_IN), clampf(old.y + delta.y, 0.0, BOARD_IN))
	var applied: Vector2 = np - old   # the centre is board-clamped; shift the whole formation by the same
	unit["pos"] = np
	var mp: Array = unit["model_pos"]
	for k in range(mp.size()):
		mp[k] = (mp[k] as Vector2) + applied


## Terrain-aware movement: Difficult terrain (p.11) crossed by the path halves the move; then the rigid
## formation translates (board-clamped in _move); then each model that crossed Dangerous terrain (p.12)
## tests. Empty terrain (open field) → a plain _move.
static func _terrain_move(unit: Dictionary, delta: Vector2, terrain: Dictionary,
		rng: RandomNumberGenerator, log_lines: Array, rolls: Array = []) -> void:
	if terrain.is_empty() or delta == Vector2.ZERO:
		_move(unit, delta)
		return
	var start: Vector2 = unit["pos"]
	var mv := delta
	if TerrainRules.path_crosses(terrain, start, start + mv, TerrainRules.PathCheck.DIFFICULT):
		mv *= 0.5   # Difficult: halve a move that passes through it (a shorter step, may fall short of the goal)
		log_lines.append("%s slowed by difficult terrain (half move)" % unit["name"])
	_move(unit, mv)
	_dangerous_test(unit, (unit["pos"] as Vector2) - start, terrain, rng, log_lines, rolls)


## Dangerous terrain (p.12): each ALIVE model whose own path crossed a Dangerous cell rolls one die; a 1 is
## one wound to the unit. Models share the applied delta (rigid formation), so a model's segment is
## (current - applied) -> current. Wounds that drop the unit to <= half trigger a morale test.
static func _dangerous_test(unit: Dictionary, applied: Vector2, terrain: Dictionary,
		rng: RandomNumberGenerator, log_lines: Array, rolls: Array = []) -> void:
	if applied == Vector2.ZERO:
		return
	var before := alive_models(unit)
	var wounds := 0
	for m in unit["model_pos"]:
		var post: Vector2 = m
		if TerrainRules.path_crosses(terrain, post - applied, post, TerrainRules.PathCheck.DANGEROUS):
			var face: int = rng.randi_range(1, 6)
			var hurt: bool = face == 1
			if hurt:
				wounds += 1
			_trace_terrain(rolls, str(unit["name"]), face, hurt)
	if wounds > 0:
		_apply_wounds(unit, wounds)
		log_lines.append("%s takes %d wound(s) from dangerous terrain" % [unit["name"], wounds])
		if AiCombatMath.should_test_shooting_morale(before, alive_models(unit), int(unit["max_models"])):
			_morale(unit, rng, log_lines, rolls)


## Target selection (Solo & Co-Op rules p.2): the NEAREST valid enemy, but ALWAYS prioritising units that
## haven't activated this round — it only falls back to the nearest already-activated enemy when no
## un-activated one is reachable. `max_range` limits to reachable/in-range targets (INF = any). null if
## there is no valid target.
static func _pick_target(unit: Dictionary, units: Array, max_range: float,
		terrain: Dictionary = {}, require_los: bool = false) -> Variant:
	var side: int = int(unit["player"])
	var up: Vector2 = unit["pos"]
	var best_any: Variant = null
	var best_any_d: float = INF
	var best_fresh: Variant = null      # nearest NOT-yet-activated
	var best_fresh_d: float = INF
	for e in units:
		if e["player"] == side or not is_alive(e):
			continue
		var d: float = up.distance_to(e["pos"])
		if d > max_range:
			continue
		if require_los and not terrain.is_empty() \
				and not TerrainRules.has_line_of_sight(terrain, up, e["pos"], MODEL_HEIGHT, MODEL_HEIGHT):
			continue   # a shot needs clear line of sight (Ruins/Forest/Container block it)
		if d < best_any_d:
			best_any_d = d
			best_any = e
		if not bool(e["activated"]) and d < best_fresh_d:
			best_fresh_d = d
			best_fresh = e
	return best_fresh if best_fresh != null else best_any


static func _side_models(units: Array, player: int) -> int:
	var n := 0
	for u in units:
		if u["player"] == player:
			n += alive_models(u)
	return n


static func _has_unactivated(units: Array, player: int) -> bool:
	for u in units:
		if u["player"] == player and is_alive(u) and not bool(u["activated"]):
			return true
	return false


static func _next_unactivated(units: Array, player: int) -> Variant:
	for u in units:
		if u["player"] == player and is_alive(u) and not bool(u["activated"]):
			return u
	return null


# === Visual trace (pure observation — records what happened for the HTML replay viewer) ===

## Roster of static per-unit facts the viewer needs once (id aligns with the snapshot arrays).
static func roster(army_a: Array, army_b: Array) -> Array:
	var out: Array = []
	var idx := 0
	for src in [army_a, army_b]:
		for u in src:
			var unit := u as Dictionary
			out.append({
				"id": idx, "name": str(unit["name"]), "player": int(unit["player"]),
				"max_models": int(unit["max_models"]), "quality": int(unit["quality"]),
				"defense": int(unit["defense"]), "tough": int(unit["tough"]),
			})
			idx += 1
	return out


## A complete board state after a step (arrays indexed by unit id) — makes the viewer trivial.
static func _snapshot(units: Array, obj_owner: Array) -> Dictionary:
	var pos: Array = []
	var models: Array = []
	var alive: Array = []
	var shaken: Array = []
	for u in units:
		var p: Vector2 = u["pos"]
		pos.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		var mps: Array = []
		for m in u["model_pos"]:
			mps.append([snappedf((m as Vector2).x, 0.1), snappedf((m as Vector2).y, 0.1)])
		models.append(mps)   # individual model positions for the review
		alive.append(alive_models(u))
		shaken.append(bool(u["shaken"]))
	return {"pos": pos, "models": models, "alive": alive, "shaken": shaken, "owners": obj_owner.duplicate()}


static func _trace_roll(rolls: Array, kind: String, actor: String, target: String, weapon: String,
		hit_faces: Array, hit_target: int, hits: int, save_faces: Array, save_target: int, wounds: int,
		cover: bool = false) -> void:
	if rolls == null:
		return
	rolls.append({
		"kind": kind, "actor": actor, "target": target, "weapon": weapon,
		"hit_faces": hit_faces.duplicate(), "hit_target": hit_target, "hits": hits,
		"save_faces": save_faces.duplicate(), "save_target": save_target, "wounds": wounds, "cover": cover,
	})


static func _trace_morale(rolls: Array, unit: String, face: int, quality: int, result: String) -> void:
	if rolls == null:
		return
	rolls.append({"kind": "morale", "actor": unit, "face": face, "quality": quality, "result": result})


static func _trace_terrain(rolls: Array, unit: String, face: int, wounded: bool) -> void:
	if rolls == null:
		return
	rolls.append({"kind": "dangerous", "actor": unit, "face": face, "wound": wounded})


static func _trace_activation(trace: Array, unit: Dictionary, round_no: int, action: String,
		target: Variant, dist: float, rolls: Array, units: Array, obj_owner: Array, why: Dictionary = {}) -> void:
	if trace == null:
		return
	trace.append({
		"type": "activation", "round": round_no, "unit_id": int(unit.get("_id", -1)), "unit": str(unit["name"]),
		"player": int(unit["player"]), "action": action,
		"target": (str(target["name"]) if target != null else ""),
		"target_id": (int(target.get("_id", -1)) if target != null else -1),
		"dist": snappedf(dist, 0.1), "rolls": rolls, "why": why,
		"board": _snapshot(units, obj_owner),
	})

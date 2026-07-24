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
##    Charge (12" into melee). Movement (p.7): a non-charge move keeps every model over 1" from models of
##    ANY other unit (friendly or enemy) — the rigid formation stops clear instead of intermingling; only a
##    Charge may close inside that 1".
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
const SPACING_IN := 1.0   # OPR (p.7): non-charging models must stay over 1" from any OTHER unit's models
const MELEE_REACH_IN := 2.0   # OPR melee (p.9 "Who Can Strike"): only models within 2" of an enemy model strike
const OBJECTIVE_CONTROL_IN := 3.0
const DEFAULT_ROUNDS := 4
const MODEL_HEIGHT := 1   # every sim model is ground infantry (Height 1); tall/vehicle heights are a follow-up

## Substrings of special-rule names the COMBAT MATH actually models. Any rule a unit carries that matches
## none of these is logged once per game (unknown-rule visibility) — see docs/SOLO_AI_RULES_COVERAGE.md.
## "Medical Training" is the Battle Brothers medic item, which grants Regeneration Aura (modelled below).
const KNOWN_RULES: Array = ["AP", "Tough", "Regeneration", "Deadly", "Takedown", "Relentless", "Medical Training"]


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


## A reflection-symmetric (across the mid-line, y = 24") layer of thin IMPASSABLE wall segments — the sim's
## mirror of terrain_overlay's wall layer (`_last_wall_segments`), separate from the 3" terrain grid. Each
## segment is an [a, b] pair in inches. A short barrier sits just short of every objective (and its mirror),
## so a unit marching onto the marker must steer AROUND the wall's open ends — the individual-model movement
## the MovementPlanner adds. Symmetric both axes → the mirror-match fairness oracle stays balanced. Empty by
## default in the fairness oracle; used by the trace + tests to exercise wall avoidance.
static func default_walls(_seed_value: int = 0) -> Array:
	var mid: float = BOARD_IN / 2.0
	var out: Array = []
	for ox in [BOARD_IN / 3.0, BOARD_IN * 2.0 / 3.0]:   # one barrier per objective (x = 16", 32")
		var off := 4.0     # barrier sits 4" short of the marker on the approaching side
		var half := 3.0    # half-width of the barrier (6" wide — narrower than a marching frontage)
		out.append([Vector2(ox - half, mid - off), Vector2(ox + half, mid - off)])   # south of the marker
		out.append([Vector2(ox - half, mid + off), Vector2(ox + half, mid + off)])   # mirror, north of it
	return out


## Wall segments as JSON-friendly [[ax, ay], [bx, by]] pairs for the replay viewer.
static func _walls_json(walls: Array) -> Array:
	var out: Array = []
	for w in walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		out.append([[snappedf(a.x, 0.1), snappedf(a.y, 0.1)], [snappedf(b.x, 0.1), snappedf(b.y, 0.1)]])
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
		# Full special-rule footprint: unit rules + upgrade/item gains + weapon rules. Needed for
		# Regeneration/Hero detection and the unknown-rule log (AF nests granted rules under items).
		var rule_names: Array = _collect_rules(unit)
		var tough := 1
		for r in unit.get("rules", []):
			if str((r as Dictionary).get("name", "")) == "Tough":
				tough = maxi(int((r as Dictionary).get("rating", 1)), 1)
		var weapons: Array = []
		for w in unit.get("loadout", []):
			var wd := w as Dictionary
			if not wd.has("attacks"):
				continue
			weapons.append({
				"name": str(wd.get("name", "Weapon")),
				"range_value": int(wd.get("range", 0)),
				"attacks": int(wd.get("attacks", 1)),
				"count": maxi(int(wd.get("count", 1)), 1),
				"special_rules": _weapon_rule_strings(wd.get("specialRules", [])),
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
			tgt["rules"] = _union_rules(tgt["rules"], p["rules"])   # a joined medic/hero brings its rules along
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


## Translate a weapon's raw AF specialRules into the modelled rule strings the combat/targeting layers read:
## AP(X), Deadly(X), Takedown, Relentless. Other weapon rules are intentionally dropped from the combat
## profile (and surface via the unknown-rule log instead of silently changing math).
static func _weapon_rule_strings(special_rules: Variant) -> Array:
	var out: Array = []
	if not (special_rules is Array):
		return out
	for sr in special_rules:
		if not (sr is Dictionary):
			continue
		var name := str((sr as Dictionary).get("name", ""))
		var rating := int((sr as Dictionary).get("rating", 0))
		match name:
			"AP":
				if rating > 0:
					out.append("AP(%d)" % rating)
			"Deadly":
				out.append("Deadly(%d)" % maxi(rating, 1))
			"Takedown":
				out.append("Takedown")
			"Relentless":
				out.append("Relentless")
			_:
				pass   # not modelled — flagged by the unknown-rule log
	return out


## Every special-rule NAME a unit effectively carries: its own rules, the rules granted by its selected
## upgrades and loadout items (AF nests these under `content`), and its weapons' special rules. Used for
## Regeneration/Hero detection and the unknown-rule visibility log — never for the combat profile itself.
static func _collect_rules(unit: Dictionary) -> Array:
	var names: Dictionary = {}
	_gather_rule_names(unit.get("rules", []), names)
	for up in unit.get("selectedUpgrades", []):
		if up is Dictionary:
			_gather_rule_names(((up as Dictionary).get("option", {}) as Dictionary).get("gains", []), names)
	for w in unit.get("loadout", []):
		if not (w is Dictionary):
			continue
		var wd := w as Dictionary
		if str(wd.get("type", "")) == "ArmyBookItem":
			_gather_rule_names(wd.get("content", []), names)   # rules the item grants (skip the item name)
		_gather_rule_names(wd.get("specialRules", []), names)
	return names.keys()


## Recursively collect rule names from a list of AF rule/item nodes into `names` (nodes may nest `content`).
## Only RULE nodes contribute their name; ArmyBookItem nodes (weapons/gear like "Plasma Rifle") are
## containers — their name is skipped and only the rules they grant (their `content`) are collected.
static func _gather_rule_names(list: Variant, names: Dictionary) -> void:
	if not (list is Array):
		return
	for e in list:
		if not (e is Dictionary):
			continue
		var node := e as Dictionary
		# Only rule nodes contribute a name; weapons (ArmyBookWeapon / anything with attacks) and item
		# containers (ArmyBookItem) do not — we still recurse their granted rules.
		var node_type := str(node.get("type", ""))
		var is_container: bool = node.has("attacks") or node_type == "ArmyBookWeapon" or node_type == "ArmyBookItem"
		if not is_container:
			var nm := str(node.get("name", ""))
			if nm != "":
				names[nm] = true
		_gather_rule_names(node.get("content", []), names)


static func _union_rules(a: Variant, b: Variant) -> Array:
	var names: Dictionary = {}
	for r in (a if a is Array else []):
		names[str(r)] = true
	for r in (b if b is Array else []):
		names[str(r)] = true
	return names.keys()


## True if `rule_name` matches any rule the combat math models (substring test — "Regeneration Aura"
## matches "Regeneration"). Everything else is logged once per game.
static func _is_modeled_rule(rule_name: String) -> bool:
	for known in KNOWN_RULES:
		if rule_name.contains(str(known)):
			return true
	return false


## Case-sensitive substring test over a unit's collected rule names (e.g. "Regeneration", "Hero").
static func _unit_has_rule(u: Dictionary, needle: String) -> bool:
	for r in u.get("rules", []):
		if str(r).contains(needle):
			return true
	return false


## Medic behaviour: the Battle Brothers "Medical Training" item grants Regeneration Aura (GF Advanced Rules
## v3.5.1, p.13): each wound a unit with Regeneration takes is ignored on a 5+. Detected by substring so
## "Regeneration" and "Regeneration Aura" both count.
static func _has_regeneration(u: Dictionary) -> bool:
	return _unit_has_rule(u, "Regeneration")


static func _is_hero(u: Dictionary) -> bool:
	return _unit_has_rule(u, "Hero")


## Once per game, log every special rule present on any unit that the combat math does not model, so field
## tests and the review app SHOW the gaps instead of hiding them (M2/M3 backlog driver). Deduped by name.
static func _log_unmodeled_rules(units: Array, log_lines: Array) -> void:
	if log_lines == null:
		return
	var seen: Dictionary = {}
	for u in units:
		for r in u.get("rules", []):
			var name := str(r)
			if name == "" or seen.has(name) or _is_modeled_rule(name):
				continue
			seen[name] = true
			log_lines.append("⚠ unmodeled special rule: %s — not in the combat math (see docs/SOLO_AI_RULES_COVERAGE.md)" % name)


static func alive_models(u: Dictionary) -> int:
	return maxi(0, int(u["max_models"]) - int(u["wounds_pool"]) / int(u["tough"]))


static func is_alive(u: Dictionary) -> bool:
	return alive_models(u) > 0


static func simulate_game(army_a: Array, army_b: Array, seed_value: int, max_rounds: int = DEFAULT_ROUNDS,
		log_lines: Array = [], objectives: Array = [], trace: Array = [], terrain: Dictionary = {},
		walls: Array = []) -> Dictionary:
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
	_log_unmodeled_rules(units, log_lines)   # loud visibility of any special rule the combat math ignores
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
					_activate(actor, units, rng, log_lines, r, obj_owner, objs, trace, terrain, walls)
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
		"walls": _walls_json(walls),
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
		terrain: Dictionary = {}, walls: Array = []) -> void:
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
	var do_shoot: bool = bool(dec["shoot"])
	# Relentless overlay (Solo & Co-Op Rules v3.5.0, p.2): a unit with a Relentless weapon in range of
	# enemies always uses Hold and shoot instead of manoeuvring. (Indirect/Artillery share this pattern —
	# tracked as follow-ups in docs/SOLO_AI_RULES_COVERAGE.md.)
	if _forces_hold_and_shoot(unit, shoot_range > 0 and enemy_dist <= float(shoot_range)):
		action = AiDecision.Action.HOLD
		do_shoot = true
	var to_obj: bool = int(dec["toward"]) == AiDecision.Toward.OBJECTIVE and has_obj
	var goal: Vector2 = obj_pos if to_obj else tpos
	var goal_dist: float = upos.distance_to(goal)
	var gdir: Vector2 = (goal - upos).normalized() if goal_dist > 0.0001 else Vector2.ZERO
	var edir: Vector2 = (tpos - upos).normalized() if enemy_dist > 0.0001 else Vector2.ZERO
	match action:
		AiDecision.Action.RUSH:
			# STOP AT the objective, never march past it (p.58: seize within 3", "as close as possible").
			# The maintainer's finding: units overshot the marker and abandoned it.
			_terrain_move(unit, gdir * (minf(rush, goal_dist) if to_obj else rush), terrain, rng, log_lines, rolls, units, false, walls)
		AiDecision.Action.CHARGE:
			# Charge is the ONE action exempt from the 1" spacing rule — it closes to base contact.
			_terrain_move(unit, edir * minf(rush, maxf(enemy_dist - CONTACT_IN, 0.0)), terrain, rng, log_lines, rolls, units, true, walls)
		AiDecision.Action.ADVANCE:
			if to_obj:
				# stop on the objective, don't overshoot
				_terrain_move(unit, gdir * minf(advance, goal_dist), terrain, rng, log_lines, rolls, units, false, walls)
			else:
				# "Advancing" rule (p.58): a shooter advancing on the enemy stays as FAR as possible while
				# still in range — step back to the range edge if already inside it, else close to get in
				# range. It never flees off-board and always shoots (no kiting).
				if enemy_dist <= float(shoot_range):
					_terrain_move(unit, -edir * minf(advance, float(shoot_range) - enemy_dist), terrain, rng, log_lines, rolls, units, false, walls)
				else:
					_terrain_move(unit, edir * advance, terrain, rng, log_lines, rolls, units, false, walls)
		_:
			pass   # HOLD
	var dist: float = (unit["pos"] as Vector2).distance_to(tpos)
	var label: String = _decision_label(action, to_obj, do_shoot)
	# Resolve combat (p.2 "prioritise units that haven't activated yet"): melee hits whoever we charged;
	# shooting SPLITS each weapon type onto its own overlay-chosen target (AP→best Defense, Deadly→Tough,
	# Takedown→hero) and rolls each group, per OPR split-fire (p.8).
	var combat_target: Variant = target
	if action == AiDecision.Action.CHARGE and dist <= CONTACT_IN + 0.001:
		_resolve_melee(unit, target, rng, log_lines, rolls)
	elif do_shoot and shoot_range > 0:
		var st: Variant = _resolve_shooting_split(unit, units, rng, log_lines, rolls, terrain)
		if st != null:
			combat_target = st
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
			return "holds+shoots" if shoot else "holds"


## Distance from point p to the segment a→b (for the "enemies in the way" 6" path check).
static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# === Combat resolution (uses AiShooting + AiCombatMath, dice from the seeded RNG) ===

## SPLIT-FIRE shooting (OPR p.8 "you may split a unit's attacks by weapon type"): each ranged weapon TYPE
## independently picks its best target under its own targeting overlay (AiTargeting: AP→best Defense,
## Deadly→single-model Tough, Takedown→hero, else nearest not-activated in the open), then every weapon
## aimed at the same target is rolled as one volley. Returns the PRIMARY target (first group) for the trace
## headline, or null if nothing can fire.
static func _resolve_shooting_split(attacker: Dictionary, units: Array, rng: RandomNumberGenerator,
		log_lines: Array, rolls: Array = [], terrain: Dictionary = {}) -> Variant:
	var groups: Dictionary = {}   # target _id -> {"target": unit, "profiles": Array}
	var order: Array = []
	for w in attacker["weapons"]:
		var reach: int = int((w as Dictionary).get("range_value", 0))
		if reach <= 0:
			continue   # melee weapon
		var prof: Array = AiShooting.profiles_in_range([w], float(reach))
		if prof.is_empty():
			continue
		var overlay: int = AiTargeting.weapon_overlay((w as Dictionary).get("special_rules", []))
		var tgt: Variant = _pick_overlay_target(attacker, units, float(reach), terrain, overlay)
		if tgt == null:
			continue
		var id: int = int((tgt as Dictionary).get("_id", -1))
		if not groups.has(id):
			groups[id] = {"target": tgt, "profiles": []}
			order.append(id)
		(groups[id]["profiles"] as Array).append(prof[0])
	var primary: Variant = null
	for id in order:
		var g: Dictionary = groups[id]
		var tgt: Dictionary = g["target"]
		if primary == null:
			primary = tgt
		var d: float = (attacker["pos"] as Vector2).distance_to(tgt["pos"])
		_resolve_volley(attacker, tgt, g["profiles"], d, rng, log_lines, rolls, terrain)
	return primary


## Resolve ONE volley: the given ranged `profiles` (already grouped on `target`) fired at range `dist`.
## Handles cover, Relentless (>9" extra hits on 6s), Deadly (wound multiply, Tough-capped), Regeneration
## (the target's medic ignores wounds on a 5+), and the post-volley morale test.
static func _resolve_volley(attacker: Dictionary, target: Dictionary, profiles: Array, dist: float,
		rng: RandomNumberGenerator, log_lines: Array, rolls: Array = [], terrain: Dictionary = {}) -> void:
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
		if bool(profile.get("relentless", false)):
			hits += AiCombatMath.relentless_bonus_hits(faces, dist)   # >9": each unmodified 6 adds a hit
		var save_faces: Array = [] if hits <= 0 else _roll(rng, hits)
		var w: int = 0 if hits <= 0 else AiCombatMath.wounds(hits, save_faces, defense, int(profile["ap"]))
		var deadly: int = int(profile.get("deadly", 0))
		if w > 0 and deadly > 0:
			w *= AiCombatMath.deadly_multiplier(deadly, int(target["tough"]))
		total += w
		_trace_roll(rolls, "shoot", attacker["name"], target["name"], str(profile["name"]),
			faces, quality, hits, save_faces, defense + int(profile["ap"]), w, in_cover)
	total = _apply_regeneration(target, total, rng, log_lines, rolls)   # medic negates some wounds first
	if total > 0:
		_apply_wounds(target, total)
		log_lines.append("%s shoots %s → %d wound(s)" % [attacker["name"], target["name"], total])
	# General morale (p.10): a unit left at half or less by the wounds it just took must test.
	if AiCombatMath.should_test_shooting_morale(alive_before, alive_models(target), int(target["max_models"])):
		_morale(target, rng, log_lines, rolls)


## Back-compat single-target shooting (all in-range profiles at one target) — used by focused tests and any
## caller that already chose a target. Split-fire (above) is the activation path.
static func _resolve_shooting(attacker: Dictionary, target: Dictionary, dist: float,
		rng: RandomNumberGenerator, log_lines: Array, rolls: Array = [], terrain: Dictionary = {}) -> void:
	_resolve_volley(attacker, target, AiShooting.profiles_in_range(attacker["weapons"], dist),
		dist, rng, log_lines, rolls, terrain)


## Whether a unit is forced to Hold-and-shoot this activation: it has a Relentless ranged weapon and an
## enemy is in range (Solo & Co-Op Rules v3.5.0, p.2). Indirect/Artillery share this overlay but also carry
## damage/deployment facets not yet modelled — see the coverage doc — so only Relentless triggers it here.
static func _forces_hold_and_shoot(unit: Dictionary, enemy_in_range: bool) -> bool:
	if not enemy_in_range:
		return false
	for w in unit["weapons"]:
		if int((w as Dictionary).get("range_value", 0)) <= 0:
			continue
		for r in (w as Dictionary).get("special_rules", []):
			if str(r).begins_with("Relentless"):
				return true
	return false


## Pick a shooting target under a weapon's overlay: gather every valid enemy (alive, in range, clear LOS),
## build a descriptor for each, and let AiTargeting rank them. null if none is valid.
static func _pick_overlay_target(unit: Dictionary, units: Array, max_range: float, terrain: Dictionary,
		overlay: int) -> Variant:
	var side: int = int(unit["player"])
	var up: Vector2 = unit["pos"]
	var cands: Array = []
	var refs: Array = []
	for e in units:
		if e["player"] == side or not is_alive(e):
			continue
		var d: float = up.distance_to(e["pos"])
		if d > max_range:
			continue
		if not terrain.is_empty() \
				and not TerrainRules.has_line_of_sight(terrain, up, e["pos"], MODEL_HEIGHT, MODEL_HEIGHT):
			continue
		cands.append(_target_descriptor(e, d, terrain))
		refs.append(e)
	var idx: int = AiTargeting.best_index(cands, overlay)
	return refs[idx] if idx >= 0 else null


## Descriptor of a candidate target for AiTargeting (see its best_index docs). "has_upgrade"/"upgrade_cost"
## are absent from the point-sim (no per-unit upgrade cost) so Takedown only honours 'heroes first'.
static func _target_descriptor(e: Dictionary, dist: float, terrain: Dictionary) -> Dictionary:
	return {
		"dist": dist,
		"activated": bool(e["activated"]),
		"in_cover": not terrain.is_empty() and TerrainRules.majority_in_cover(e["model_pos"], terrain),
		"defense": int(e["defense"]),
		"is_hero": _is_hero(e),
		"has_upgrade": false,
		"upgrade_cost": 0,
		"single_tough": int(e["max_models"]) == 1 and int(e["tough"]) > 1,
		"has_tough": int(e["tough"]) > 1,
		"remaining_tough": int(e["max_models"]) * int(e["tough"]) - int(e["wounds_pool"]),
	}


## Regeneration / Medic (GF Advanced Rules v3.5.1, p.13): a unit that has the rule rolls one die per wound
## it would take; each 5+ ignores that wound. Returns the wounds that actually land. Records a "regen" trace
## roll per die so the review app shows the medic working. Units without the rule take full wounds.
static func _apply_regeneration(unit: Dictionary, wounds: int, rng: RandomNumberGenerator,
		log_lines: Array, rolls: Array = []) -> int:
	if wounds <= 0 or not _has_regeneration(unit):
		return maxi(wounds, 0)
	var ignored := 0
	for _i in range(wounds):
		var face: int = rng.randi_range(1, 6)
		var saved: bool = face >= 5
		if saved:
			ignored += 1
		_trace_regen(rolls, str(unit["name"]), face, saved)
	if ignored > 0:
		log_lines.append("%s regenerates %d wound(s) (medic)" % [unit["name"], ignored])
	return wounds - ignored


static func _resolve_melee(attacker: Dictionary, target: Dictionary, rng: RandomNumberGenerator,
		log_lines: Array, rolls: Array = []) -> void:
	# Wounds CAUSED (post-save) decide who won the melee (p.10); Regeneration only reduces what actually
	# lands, so we compare caused wounds but apply the post-regeneration amount.
	var dealt := _strike(attacker, target, rng, log_lines, rolls, "charge")
	var dealt_applied := _apply_regeneration(target, dealt, rng, log_lines, rolls)
	if dealt_applied > 0:
		_apply_wounds(target, dealt_applied)
	# The defender MAY strike back (Shaken units strike back as fatigued — handled in _strike).
	var struck_back := 0
	if is_alive(target):
		struck_back = _strike(target, attacker, rng, log_lines, rolls, "strike back")
		var back_applied := _apply_regeneration(attacker, struck_back, rng, log_lines, rolls)
		if back_applied > 0:
			_apply_wounds(attacker, back_applied)
	attacker["fatigued"] = true
	target["fatigued"] = true
	log_lines.append("%s charges %s → %d dealt, %d back" % [attacker["name"], target["name"], dealt, struck_back])
	# Melee morale (p.10): only the loser (more wounds taken) tests.
	if dealt > struck_back and is_alive(target):
		_morale(target, rng, log_lines, rolls)
	elif struck_back > dealt and is_alive(attacker):
		_morale(attacker, rng, log_lines, rolls)


## One striker's melee output. Fatigued OR Shaken → hits only on unmodified 6s; else its Quality. Only the
## models WITHIN 2" of an enemy model strike (p.9 "Who Can Strike"), so each weapon's attacks scale by the
## in-reach model count, not the whole unit. Deadly multiplies unsaved wounds (Tough-capped).
static func _strike(striker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator,
		_log_lines: Array = [], rolls: Array = [], kind: String = "melee") -> int:
	var profiles: Array = AiShooting.melee_profiles(striker["weapons"])
	var to_hit: int = 6 if (bool(striker["fatigued"]) or bool(striker["shaken"])) else int(striker["quality"])
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, _effective_melee_attacks(striker, defender, int(profile["attacks"])))
		var hits := AiCombatMath.count_hits(faces, to_hit)
		var save_faces: Array = [] if hits <= 0 else _roll(rng, hits)
		var w: int = 0 if hits <= 0 else AiCombatMath.wounds(hits, save_faces, int(defender["defense"]), int(profile["ap"]))
		var deadly: int = int(profile.get("deadly", 0))
		if w > 0 and deadly > 0:
			w *= AiCombatMath.deadly_multiplier(deadly, int(defender["tough"]))
		total += w
		_trace_roll(rolls, kind, striker["name"], defender["name"], str(profile["name"]),
			faces, to_hit, hits, save_faces, int(defender["defense"]) + int(profile["ap"]), w)
	return total


## OPR "Who Can Strike" (p.9): a striker's models count toward its melee attacks only if they are within 2"
## of an enemy model. Sim models are points, so the base-contact centre distance (CONTACT_IN) is folded into
## the 2" reach — the same base allowance the movement/coherency layers use — giving a centre-to-centre reach
## of CONTACT_IN + MELEE_REACH_IN. Falls back to the whole living unit when either side's model positions are
## unset (e.g. a focused unit test that doesn't place models).
static func _striking_models(striker: Dictionary, defender: Dictionary) -> int:
	var sm: Array = striker["model_pos"]
	var dm: Array = defender["model_pos"]
	if sm.is_empty() or dm.is_empty():
		return alive_models(striker)
	var reach2: float = (CONTACT_IN + MELEE_REACH_IN) * (CONTACT_IN + MELEE_REACH_IN)
	var n := 0
	for m in sm:
		for e in dm:
			if (m as Vector2).distance_squared_to(e as Vector2) <= reach2:
				n += 1
				break
	return mini(n, alive_models(striker))


## Melee attacks after the 2" strike rule: scale a weapon group's attacks by the fraction of the unit's
## models actually in reach of the enemy (vs the alive-fraction scaling shooting uses). Rounds to whole dice.
static func _effective_melee_attacks(striker: Dictionary, defender: Dictionary, base_attacks: int) -> int:
	var mx: int = int(striker["max_models"])
	if mx <= 0:
		return base_attacks
	return maxi(0, int(round(float(base_attacks) * float(_striking_models(striker, defender)) / float(mx))))


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
	# OPR casualty removal (p.9): the controlling player removes its own dead, and a player pulls them from
	# the REAR — keeping the front rank (objective-holders, models in the fight) in place. "Rear" is the side
	# toward this unit's OWN deployment edge (player 0 → y = 0, player 1 → y = BOARD_IN), so removal is
	# mirror-symmetric between the two sides. (A plain pop_back removed the highest-index — geometrically the
	# northern-most — model for BOTH players: that strips player 0's enemy-facing FRONT rank but player 1's
	# rear, a mirror asymmetry that handed player 1 a systematic objective-control edge once 1" spacing made
	# objective grip position-sensitive — the mirror-oracle skew.)
	var mp: Array = unit["model_pos"]
	var owns_low_edge: bool = int(unit["player"]) == 0
	while mp.size() > alive_models(unit):
		var rear_idx: int = 0
		var rear_y: float = (mp[0] as Vector2).y
		for k in range(1, mp.size()):
			var y: float = (mp[k] as Vector2).y
			if (owns_low_edge and y < rear_y) or (not owns_low_edge and y > rear_y):
				rear_y = y
				rear_idx = k
		mp.remove_at(rear_idx)


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


## Terrain- and spacing-aware movement. First the 1" spacing clamp (p.7) shortens a non-charge move so the
## rigid formation stops clear of other units; then Difficult terrain (p.11) crossed by the path halves it;
## then the formation translates (board-clamped in _move); then each model that crossed Dangerous terrain
## (p.12) tests. `units` (all units) drives spacing; a Charge passes allow_contact=true to skip it and close
## to base contact. Empty terrain + empty units (open field, no neighbours) → a plain _move.
static func _terrain_move(unit: Dictionary, delta: Vector2, terrain: Dictionary,
		rng: RandomNumberGenerator, log_lines: Array, rolls: Array = [],
		units: Array = [], allow_contact: bool = false, walls: Array = []) -> void:
	var mv := delta
	# 1" spacing (p.7): a non-charge move stops over 1" clear of any other unit — no walking through/into them.
	if not allow_contact and not units.is_empty() and mv != Vector2.ZERO:
		var reqd: float = mv.length()
		var allowed: float = _spacing_limit(unit, mv / reqd, reqd, units)
		if allowed < reqd - 0.001:
			mv = (mv / reqd) * allowed
			log_lines.append("%s stops clear of another unit (1\" spacing)" % unit["name"])
	if (terrain.is_empty() and walls.is_empty()) or mv == Vector2.ZERO:
		_planner_move(unit, mv, terrain, walls, allow_contact, log_lines)
		return
	var start: Vector2 = unit["pos"]
	if TerrainRules.path_crosses(terrain, start, start + mv, TerrainRules.PathCheck.DIFFICULT):
		mv *= 0.5   # Difficult: halve a move that passes through it (a shorter step, may fall short of the goal)
		log_lines.append("%s slowed by difficult terrain (half move)" % unit["name"])
	_planner_move(unit, mv, terrain, walls, allow_contact, log_lines)
	_dangerous_test(unit, (unit["pos"] as Vector2) - start, terrain, rng, log_lines, rolls)


## Apply the (spacing/Difficult-clamped) translation `mv` to the unit's individual models. With no wall in the
## path this is the exact rigid slide (fast path, identical to the pre-planner _move — so open-field play and
## the mirror oracle are unchanged); when a wall blocks it, MovementPlanner steers each model around it while
## keeping the unit in coherency (A* rescue if boxed in), and the formation centre follows the models.
static func _planner_move(unit: Dictionary, mv: Vector2, terrain: Dictionary, walls: Array,
		allow_contact: bool, log_lines: Array = []) -> void:
	if mv == Vector2.ZERO:
		return
	if walls.is_empty() or not MovementPlanner.rigid_blocked(unit["model_pos"], mv, walls):
		_move(unit, mv)
		return
	var planned: Array = MovementPlanner.plan_unit_step(unit["model_pos"], mv, walls, terrain, allow_contact, BOARD_IN)
	var mp: Array = unit["model_pos"]
	var old_c: Vector2 = _model_centroid(mp)
	var new_c := Vector2.ZERO
	for k in range(mini(planned.size(), mp.size())):
		var p: Vector2 = planned[k]
		var cp := Vector2(clampf(p.x, 0.0, BOARD_IN), clampf(p.y, 0.0, BOARD_IN))
		mp[k] = cp
		new_c += cp
	if not planned.is_empty():
		new_c /= float(planned.size())
		unit["pos"] = (unit["pos"] as Vector2) + (new_c - old_c)   # centre follows the models' mean shift
	if log_lines != null:
		log_lines.append("%s steers its models around a wall" % unit["name"])


## Mean of a set of model positions (Vector2) — the formation's current centroid.
static func _model_centroid(model_pos: Array) -> Vector2:
	if model_pos.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for m in model_pos:
		s += m as Vector2
	return s / float(model_pos.size())


## OPR General Movement (GF v3.5.1 p.7): "Models may never be within 1” of models from other units [...]
## unless they are taking a Charge action." Clamps a non-charge translation so the rigid formation stops at
## the separation threshold. Returns the greatest distance (≤ `dist`) the unit may travel along unit-vector
## `dir`. `sep` is the min centre-to-centre gap: base contact (CONTACT_IN) plus the rule's 1". A pair already
## inside `sep` (e.g. post-melee contact) doesn't restrict — only genuinely separated units are kept apart,
## which is exactly the intermingling the maintainer flagged. Applies to friendly AND enemy units alike.
static func _spacing_limit(unit: Dictionary, dir: Vector2, dist: float, units: Array,
		sep: float = CONTACT_IN + SPACING_IN) -> float:
	var my_models: Array = unit["model_pos"]
	if my_models.is_empty() or dir == Vector2.ZERO or dist <= 0.0:
		return dist
	var sep2: float = sep * sep
	var reach: float = dist + sep + 24.0   # coarse prune: units farther than this can't be reached this move
	var origin: Vector2 = unit["pos"]
	var limit: float = dist
	for other in units:
		if is_same(other, unit) or not is_alive(other):
			continue
		if origin.distance_to(other["pos"]) > reach:
			continue
		for o in other["model_pos"]:
			var op: Vector2 = o
			for m in my_models:
				var rel: Vector2 = (m as Vector2) - op
				var c: float = rel.length_squared() - sep2
				if c <= 0.0:
					continue   # already within sep (contact/exception) → this pair doesn't clamp
				var b: float = rel.dot(dir)
				if b >= 0.0:
					continue   # moving away or parallel → never enters the sep disk
				var disc: float = b * b - c
				if disc < 0.0:
					continue   # closest approach still outside sep → never enters
				limit = minf(limit, maxf(-b - sqrt(disc), 0.0))   # stop where centre distance first hits sep
	return limit


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


static func _trace_regen(rolls: Array, unit: String, face: int, saved: bool) -> void:
	if rolls == null:
		return
	rolls.append({"kind": "regen", "actor": unit, "face": face, "saved": saved})


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

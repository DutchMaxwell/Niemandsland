extends SceneTree
## Solo-AI FIELD TEST (goal 003 P3) — drives the REAL in-game SoloController on a REAL OPR army, headless.
## It builds two armies of REAL GameUnits (from an Army-Forge list JSON), wires the REAL SoloController with
## REAL objective / terrain / wall providers, then runs the AI side (as F11 does) for several rounds and
## prints a battle-log-style trace: archetype, the official decide_solo action + destination (objective vs
## enemy), the terrain-aware move, Dangerous-terrain tests, and the combat the AI declares (split-fire target
## selection via AiTargeting, dead-model-scaled attacks, Deadly / Cover, resolved on a SEEDED RNG — the
## in-game path resolves the identical modules on the visual dice tray with the human rolling saves, which is
## interactive and cannot run headless).
##
## Run: godot --headless -s res://tools/solo_field_test.gd -- <army_list.json> [seed]

const IN2M := 0.0254
const ARCH_NAMES: Array[String] = ["MELEE", "SHOOTING", "HYBRID"]
const OVERLAY_NAMES: Array[String] = ["", "AP→", "Deadly→", "Takedown→"]


func _init() -> void:
	# Defer until the SceneTree root is in-tree so Node3D global transforms are valid.
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var list_path := args[0] if args.size() > 0 else ""
	var seed_value := int(args[1]) if args.size() > 1 else 4242
	if list_path == "" or not FileAccess.file_exists(list_path):
		print("FIELD_TEST ERROR: pass an army list JSON path (copied into the worktree).")
		quit(1)
		return
	var mode := str(args[2]) if args.size() > 2 else "objectives"
	var close := mode == "melee"
	var autogame := mode == "autogame"
	var data: Dictionary = JSON.parse_string(FileAccess.open(list_path, FileAccess.READ).get_as_text())
	var specs := _parse_units(data)
	print("=== SOLO-AI FIELD TEST — %s (%d units/side, seed %d, mode=%s) ===" % [str(data.get("name", "army")), specs.size(), seed_value, mode])

	# Build both armies of REAL GameUnits + a real OPRArmyManager. Close mode deploys the lines within charge
	# range and drops objectives so the melee-capable units charge (exercises the 2" strike-reach scaling).
	var edge := 0.16 if close else 0.45
	var army: OPRArmyManager = OPRArmyManager.new()
	army.current_round = 1
	var human := _build_side(specs, 1, -edge)   # player 1 on the -Z edge
	var ai := _build_side(specs, 2, edge)        # player 2 (the AI) on the +Z edge
	var all_units: Array = human + ai
	for u in all_units:
		army.game_units[(u as GameUnit).unit_id] = u

	# Wire the REAL SoloController with REAL providers (objectives / terrain / walls).
	var solo: SoloController = SoloController.new()
	root.add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo._rng.seed = seed_value   # seed the D6-section unit pick so a trace is reproducible per seed
	var objectives: Array = [] if close else [Vector3(-0.2, 0.0, 0.0), Vector3(0.2, 0.0, 0.0)]
	var owners: Array = []
	for _o in objectives:
		owners.append(0)
	solo.objectives_provider = func() -> Array: return objectives
	solo.objective_owner_of = func(i: int) -> int: return int(owners[i]) if i < owners.size() else 0
	solo.terrain_type_at = Callable(self, "_terrain_at")
	solo.los_checker = func(_a: Vector3, _b: Vector3) -> bool: return true
	# One midfield wall so a loose unit's straight rush is blocked → MovementPlanner steers around it.
	var walls: Array = [[Vector2(-0.12, 0.16), Vector2(0.12, 0.16)]]
	solo.walls_provider = func() -> Array: return walls

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	if autogame:
		_run_autogame(solo, army, human, ai, objectives, owners, rng)
		return

	for round_no in range(1, 4):
		army.current_round = round_no
		print("\n----- ROUND %d — AI (player 2) activates its whole side (F11) -----" % round_no)
		var acted := 0
		while true:
			var unit: GameUnit = solo.activate_next_ai_unit()
			if unit == null:
				break
			acted += 1
			_print_activation(solo, unit, rng)
		if acted == 0:
			print("  (no eligible AI units — army spent)")
		# Reset activations for the next round (the real game does this on advance_round).
		for u in all_units:
			(u as GameUnit).is_activated = false

	print("\n=== FIELD TEST COMPLETE — objectives held by AI: %d/%d ===" % [_ai_held(ai, human, objectives), objectives.size()])
	quit(0)


# ===================================================================================================
# AUTOGAME (goal 003 P2): a COMPLETE 4-round match — the human side is simulated by scripted
# activations (each human unit walks toward its nearest objective, mirroring a simple player), the AI
# answers each with ONE activation (the in-game alternation contract), Shaken units idle-recover, the
# exhausted side lets the other finish, objectives seize/contest at round end via the SAME pure
# SoloController.seize_objectives main.gd runs, and the match is scored after round 4.
# ===================================================================================================

const AUTOGAME_ROUNDS := 4   # == main.gd SOLO_GAME_ROUNDS (OPR standard match length)


func _run_autogame(solo: SoloController, army: OPRArmyManager, human: Array, ai: Array,
		objectives: Array, owners: Array, rng: RandomNumberGenerator) -> void:
	for round_no in range(1, AUTOGAME_ROUNDS + 1):
		army.current_round = round_no
		var ai_opens: bool = round_no % 2 == 0   # OPR: the opening side alternates (AI opens even rounds)
		print("\n===== ROUND %d (%s opens) =====" % [round_no, "AI" if ai_opens else "You"])
		if ai_opens:
			_autogame_ai_step(solo, rng)
		var guard := 0
		while guard < 64:
			guard += 1
			var h := _autogame_human_step(solo, army, objectives)
			var a := _autogame_ai_step(solo, rng)
			if h == null and a == null:
				break   # both sides exhausted — the round is over
		# Round end: the SAME pure seize main.gd runs, against the real model positions.
		var infos: Array = []
		for u in (human + ai):
			var gu := u as GameUnit
			if gu.get_alive_count() <= 0:
				continue
			infos.append({"player": int(gu.unit_properties.get("player_id", 0)),
				"shaken": gu.is_shaken, "positions": solo.alive_positions(gu)})
		var res: Dictionary = SoloController.seize_objectives(infos, objectives, owners)
		for i in range((res["owners"] as Array).size()):
			owners[i] = (res["owners"] as Array)[i]
		for c in res.get("changes", []):
			var idx: int = int((c as Dictionary)["index"])
			var owner: int = int((c as Dictionary)["owner"])
			print("  ► Objective %d %s" % [idx + 1,
				("contested — goes neutral" if owner == 0 else "seized by P%d" % owner)])
		# Fatigue clears at round end (OPR); activations reset for the new round.
		for u in (human + ai):
			(u as GameUnit).is_activated = false
			(u as GameUnit).is_fatigued = false
	# Scoring (== main.gd _solo_show_game_summary): objectives held per side decide the winner.
	var ai_held := 0
	var human_held := 0
	var neutral := 0
	for o in owners:
		match int(o):
			0: neutral += 1
			2: ai_held += 1
			_: human_held += 1
	var verdict := "You win" if human_held > ai_held else ("The AI wins" if ai_held > human_held else "Draw")
	print("\n=== GAME OVER — %d rounds played ===" % AUTOGAME_ROUNDS)
	print("Objectives — you: %d · AI: %d · neutral: %d" % [human_held, ai_held, neutral])
	print(verdict)
	quit(0)


## One scripted HUMAN activation: the next eligible human unit advances 6" toward its nearest objective
## (a simple stand-in player). Shaken human units idle-recover. Returns the unit or null when exhausted.
func _autogame_human_step(solo: SoloController, army: OPRArmyManager, objectives: Array) -> GameUnit:
	var eligible: Array = solo.eligible_units_for(solo.human_slot)
	if eligible.is_empty():
		return null
	var unit := eligible[0] as GameUnit
	unit.activate(army.current_round)
	if unit.is_shaken:
		unit.is_shaken = false
		print("  • [You] %s idles — recovers from Shaken" % unit.get_name())
		return unit
	var centre := solo.unit_centre(unit)
	var goal := centre
	var best := INF
	for o in objectives:
		var d := MoveIntent.distance_inches(centre, o)
		if d < best:
			best = d
			goal = o
	var delta := MoveIntent.plan_unit_move(solo.alive_positions(unit), goal, 6.0)
	for m in unit.get_alive_models():
		var node: Node3D = (m as ModelInstance).node
		if node != null:
			node.global_position += delta
	var c2 := solo.unit_centre(unit)
	print("  • [You] %s advances toward the objective — now at (%.2f, %.2f)" % [unit.get_name(), c2.x, c2.z])
	return unit


## One AI activation via the real controller (alternation answer), traced. Null when the AI is exhausted.
func _autogame_ai_step(solo: SoloController, rng: RandomNumberGenerator) -> GameUnit:
	var unit: GameUnit = solo.activate_next_ai_unit()
	if unit == null:
		return null
	if bool(solo.last_report.get("idle_shaken", false)):
		unit.is_shaken = false   # main clears this via the radial seam; the harness clears it directly
		print("  • [AI]  %s idles — recovers from Shaken" % unit.get_name())
		return unit
	_print_activation(solo, unit, rng)
	return unit


# ===================================================================================================
# Trace of one AI activation: the decision, the move, Dangerous tests, and the declared combat.
# ===================================================================================================

func _print_activation(solo: SoloController, unit: GameUnit, rng: RandomNumberGenerator) -> void:
	var report: Dictionary = solo.last_report
	var target: GameUnit = report.get("target")
	var weapons := _weapons_of(unit)
	var arch := ARCH_NAMES[AiArchetype.classify(weapons)]
	var action := AiDecision.action_name(int(report.get("action", 0)))
	var toward := "objective" if int(report.get("toward", 0)) == AiDecision.Toward.OBJECTIVE else "enemy"
	var c := solo.unit_centre(unit)
	print("  • %s [%s] %s (→ %s)  %d/%d models  at (%.2f, %.2f)" % [
		unit.get_name(), arch, action, toward, unit.get_alive_count(), unit.models.size(), c.x, c.z])
	var dang := int(report.get("dangerous_models", 0))
	if dang > 0:
		var wounds := 0
		for _i in range(dang):
			if rng.randi_range(1, 6) == 1:
				wounds += 1
		print("      dangerous terrain: %d model(s) test → %d wound(s)" % [dang, wounds])
		if wounds > 0:
			_apply_wounds(unit, wounds)
	if bool(report.get("can_shoot", false)) and target != null:
		_resolve_shooting(solo, unit, rng)
	elif int(report.get("action", 0)) == AiDecision.Action.CHARGE and target != null:
		var dist := MoveIntent.distance_inches(solo.unit_centre(unit), solo.unit_centre(target))
		if dist <= 2.5:
			_resolve_melee(solo, unit, target, rng)
		else:
			print("      charge falls short (%.1f\")" % dist)


## AI SPLIT-FIRE shooting via the SAME modules main.gd wires: each ranged weapon type picks its target under
## its AiTargeting overlay, attacks scale by living models (SoloController.effective_attacks), Deadly/AP/Cover
## apply (AiCombatMath / TerrainRules), dice on the seeded RNG.
func _resolve_shooting(solo: SoloController, attacker: GameUnit, rng: RandomNumberGenerator) -> void:
	var groups: Dictionary = {}
	var order: Array = []
	for w in _weapons_of(attacker):
		var reach: int = int(w.range_value)
		if reach <= 0:
			continue
		var prof_list: Array = AiShooting.profiles_in_range([w], float(reach))
		if prof_list.is_empty():
			continue
		var overlay: int = AiTargeting.weapon_overlay(w.special_rules)
		var tgt := _pick_overlay_target(solo, attacker, overlay, float(reach))
		if tgt == null:
			continue
		if not groups.has(tgt.unit_id):
			groups[tgt.unit_id] = {"target": tgt, "profiles": []}
			order.append(tgt.unit_id)
		(groups[tgt.unit_id]["profiles"] as Array).append(prof_list[0])
	for id in order:
		var g := groups[id] as Dictionary
		var target := g["target"] as GameUnit
		var defense: int = target.get_defense()
		var dist := MoveIntent.distance_inches(solo.unit_centre(attacker), solo.unit_centre(target))
		var total := 0
		for p in g["profiles"]:
			var profile := p as Dictionary
			var base_attacks: int = int(profile.get("attacks", 0))
			var eff: int = SoloController.effective_attacks(base_attacks, attacker.get_alive_count(), attacker.models.size())
			if eff <= 0:
				continue
			var faces := _roll(rng, eff)
			var hits := AiCombatMath.count_hits(faces, attacker.get_quality())
			if bool(profile.get("relentless", false)):
				hits += AiCombatMath.relentless_bonus_hits(faces, dist)
			var save_faces := _roll(rng, hits) if hits > 0 else []
			var w := AiCombatMath.wounds(hits, save_faces, defense, int(profile.get("ap", 0))) if hits > 0 else 0
			if w > 0 and int(profile.get("deadly", 0)) > 0:
				w *= AiCombatMath.deadly_multiplier(int(profile.get("deadly", 0)), _tough_of(target))
			var scale_note := "" if eff == base_attacks else " [scaled %d→%d, dead models don't fire]" % [base_attacks, eff]
			var overlay_name := OVERLAY_NAMES[AiTargeting.weapon_overlay((profile.get("rules", []) as Array))]
			print("      shoots %s (%s%s) → %dA%s: %d hit(s), %d wound(s)" % [
				str(profile.get("name", "?")), overlay_name, target.get_name(), eff, scale_note, hits, w])
			total += w
		if total > 0:
			_apply_wounds(target, total)
			print("      → %s takes %d wound(s) (now %d/%d)" % [target.get_name(), total, target.get_alive_count(), target.models.size()])


## AI melee: only models within 2" strike (SoloController.striking_models scales attacks), Deadly applies.
func _resolve_melee(solo: SoloController, attacker: GameUnit, target: GameUnit, rng: RandomNumberGenerator) -> void:
	var striker_pos := solo.alive_positions(attacker)
	var enemy_pos := solo.alive_positions(target)
	var striking := SoloController.striking_models(striker_pos, enemy_pos)
	var total := 0
	for w in _weapons_of(attacker):
		if int(w.range_value) > 0:
			continue
		var prof_list: Array = AiShooting.melee_profiles([w])
		if prof_list.is_empty():
			continue
		var profile := prof_list[0] as Dictionary
		var eff: int = SoloController.effective_attacks(int(profile.get("attacks", 0)), striking, attacker.models.size())
		if eff <= 0:
			continue
		var faces := _roll(rng, eff)
		var hits := AiCombatMath.count_hits(faces, attacker.get_quality())
		var save_faces := _roll(rng, hits) if hits > 0 else []
		var wnd := AiCombatMath.wounds(hits, save_faces, target.get_defense(), int(profile.get("ap", 0))) if hits > 0 else 0
		total += wnd
	print("      charges %s in melee — %d/%d models strike (2\" reach) → %d wound(s)" % [
		target.get_name(), striking, attacker.get_alive_count(), total])
	if total > 0:
		_apply_wounds(target, total)
		print("      → %s takes %d wound(s) (now %d/%d)" % [target.get_name(), total, target.get_alive_count(), target.models.size()])


## Target selection for a weapon overlay — the same AiTargeting ranking main.gd's _solo_pick_overlay_target uses.
func _pick_overlay_target(solo: SoloController, attacker: GameUnit, overlay: int, max_range: float) -> GameUnit:
	var from := solo.unit_centre(attacker)
	var cands: Array = []
	var refs: Array = []
	for h in solo.army_manager.get_game_units_for_player(1):
		var hu := h as GameUnit
		if hu == null or hu.is_destroyed():
			continue
		var dist := MoveIntent.distance_inches(from, solo.unit_centre(hu))
		if dist > max_range:
			continue
		var tough := _tough_of(hu)
		cands.append({
			"dist": dist, "activated": hu.is_activated, "in_cover": _majority_in_cover(hu),
			"defense": hu.get_defense(), "is_hero": hu.is_hero(), "has_upgrade": false, "upgrade_cost": 0,
			"single_tough": hu.models.size() == 1 and tough > 1, "has_tough": tough > 1,
			"remaining_tough": hu.get_alive_count() * tough})
		refs.append(hu)
	var idx := AiTargeting.best_index(cands, overlay)
	return refs[idx] if idx >= 0 else null


# ===================================================================================================
# Army building (REAL GameUnits from the Army-Forge list) + helpers.
# ===================================================================================================

func _parse_units(data: Dictionary) -> Array:
	var parsed: Dictionary = {}
	var order: Array = []
	for u in data.get("units", []):
		var unit := u as Dictionary
		var sel := str(unit.get("selectionId", str(order.size())))
		var rule_names: Array = []
		for r in unit.get("rules", []):
			rule_names.append(str((r as Dictionary).get("name", "")))
		var weapons: Array = []
		for w in unit.get("loadout", []):
			var wd := w as Dictionary
			if not wd.has("attacks"):
				continue
			weapons.append({"name": str(wd.get("name", "Weapon")), "range": int(wd.get("range", 0)),
				"attacks": int(wd.get("attacks", 1)), "count": maxi(int(wd.get("count", 1)), 1),
				"rules": _rule_strings(wd.get("specialRules", []))})
		parsed[sel] = {"name": str(unit.get("name", "Unit")), "quality": int(unit.get("quality", 4)),
			"defense": int(unit.get("defense", 4)), "size": maxi(int(unit.get("size", 1)), 1),
			"weapons": weapons, "rules": rule_names, "join_to": str(unit.get("joinToUnit", "")), "merged": false}
		order.append(sel)
	for sel in order:
		var p: Dictionary = parsed[sel]
		var jt: String = p["join_to"]
		if jt != "" and parsed.has(jt):
			var tgt: Dictionary = parsed[jt]
			tgt["size"] = int(tgt["size"]) + int(p["size"])
			tgt["weapons"] = (tgt["weapons"] as Array) + (p["weapons"] as Array)
			p["merged"] = true
	var out: Array = []
	for sel in order:
		var p: Dictionary = parsed[sel]
		if not bool(p["merged"]):
			out.append(p)
	return out


func _rule_strings(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		var rd := r as Dictionary
		var nm := str(rd.get("name", ""))
		if rd.has("rating") and int(rd.get("rating", 0)) != 0:
			nm += "(%d)" % int(rd["rating"])
		out.append(nm)
	return out


func _build_side(specs: Array, player: int, z_edge: float) -> Array:
	var out: Array = []
	for i in range(specs.size()):
		var spec := specs[i] as Dictionary
		var unit := GameUnit.new()
		unit.unit_id = "p%d_%s" % [player, str(spec["name"]).replace(" ", "_") + str(i)]
		unit.unit_properties = {"player_id": player, "name": str(spec["name"]),
			"quality": int(spec["quality"]), "defense": int(spec["defense"]), "special_rules": spec["rules"]}
		# Real OPRUnit source_data so _unit_weapons() reads OPRWeapon objects (the in-game path).
		var opr := OPRApiClient.OPRUnit.new()
		opr.name = str(spec["name"])
		opr.quality = int(spec["quality"])
		opr.defense = int(spec["defense"])
		opr.size = int(spec["size"])
		var wl: Array[OPRApiClient.OPRWeapon] = []
		for wspec in spec["weapons"]:
			var wd := wspec as Dictionary
			var wpn := OPRApiClient.OPRWeapon.new()
			wpn.name = str(wd["name"])
			wpn.range_value = int(wd["range"])
			wpn.attacks = int(wd["attacks"])
			wpn.count = int(wd["count"])
			var sr: Array[String] = []
			for s in wd["rules"]:
				sr.append(str(s))
			wpn.special_rules = sr
			wl.append(wpn)
		opr.weapons = wl
		unit.source_type = "opr"
		unit.source_data = opr
		# Place `size` models in a 5-wide grid on this side's edge.
		var n: int = int(spec["size"])
		var base_x := -0.35 + float(i % 2) * 0.35   # two columns of units per side
		var base_z := z_edge - float(i / 2) * 0.08 * signf(z_edge)
		for m in range(n):
			var mi := ModelInstance.new()
			mi.is_alive = true
			var node := Node3D.new()
			root.add_child(node)
			node.global_position = Vector3(base_x + float(m % 5) * 0.03, 0.0, base_z + float(m / 5) * 0.03)
			mi.node = node
			unit.models.append(mi)
		out.append(unit)
	return out


func _weapons_of(unit: GameUnit) -> Array:
	if unit.source_type == "opr" and unit.source_data is OPRApiClient.OPRUnit:
		return (unit.source_data as OPRApiClient.OPRUnit).weapons
	return []


func _tough_of(unit: GameUnit) -> int:
	for r in unit.get_special_rules():
		var s := str(r).strip_edges()
		if s.begins_with("Tough(") and s.ends_with(")"):
			return maxi(int(s.substr(6, s.length() - 7).replace("+", "")), 1)
	return 1


func _majority_in_cover(unit: GameUnit) -> bool:
	var models := unit.get_alive_models()
	if models.is_empty():
		return false
	var n := 0
	for m in models:
		var node: Node3D = (m as ModelInstance).node
		if node != null and TerrainRules.gives_cover(_terrain_at(node.global_position)):
			n += 1
	return n * 2 > models.size()


## Apply whole-model wounds back-rank-first (a simple stand-in for the game's pooled/loose wound flows).
func _apply_wounds(unit: GameUnit, wounds: int) -> void:
	var left := wounds
	for i in range(unit.models.size() - 1, -1, -1):
		if left <= 0:
			break
		var m := unit.models[i] as ModelInstance
		if m != null and m.is_alive:
			m.is_alive = false
			left -= 1


func _roll(rng: RandomNumberGenerator, n: int) -> Array:
	var faces: Array = []
	for _i in range(maxi(n, 0)):
		faces.append(rng.randi_range(1, 6))
	return faces


func _ai_held(ai: Array, human: Array, objectives: Array) -> int:
	var held := 0
	for o in objectives:
		var na := _within(ai, o)
		var nh := _within(human, o)
		if na > nh:
			held += 1
	return held


func _within(units: Array, o: Vector3) -> int:
	var n := 0
	for u in units:
		for m in (u as GameUnit).get_alive_models():
			var node: Node3D = (m as ModelInstance).node
			if node != null and MoveIntent.distance_inches(node.global_position, o) <= 3.0:
				n += 1
				break
	return n


# Terrain: a Forest patch (Difficult + Cover, left-centre) and a Dangerous strip (right-centre), in metres.
func _terrain_at(p: Vector3) -> int:
	if p.x >= -0.28 and p.x <= -0.12 and absf(p.z) <= 0.12:
		return TerrainRules.TerrainType.FOREST
	if p.x >= 0.12 and p.x <= 0.30 and absf(p.z) <= 0.12:
		return TerrainRules.TerrainType.DANGEROUS
	return TerrainRules.TerrainType.NONE

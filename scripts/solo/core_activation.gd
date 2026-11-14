class_name CoreActivation
extends RefCounted
## One-core P3 step 19: the table's skeleton for core-resolved activations. INERT: nothing calls this until
## NML_ONE_CORE_ACTIVATION=1 (default OFF), and every later door asks one of the three predicates first.

static var _env := -1


## The flag, read once (the BattleSim.core_enabled pattern).
static func enabled() -> bool:
	if _env < 0:
		_env = 1 if OS.get_environment("NML_ONE_CORE_ACTIVATION") == "1" else 0
	return _env == 1


## The engine resolves at this table: an AI seat, or an agreed Automatic online room. Hotseat and Manual rooms: false.
static func applies(main) -> bool:
	return enabled() and ClassDB.class_exists("NmlCore") \
		and (not main.solo_ai_slots.is_empty() or main._online_turn_room())


## No unit rule, no attachment, no weapon rule: the volley the core resolves exactly as the table does.
static func is_plain(gu: GameUnit) -> bool:
	if not (gu.unit_properties.get("special_rules", []) as Array).is_empty() \
			or gu.has_attached_heroes() or gu.is_attached() or not gu.source_data is OPRApiClient.OPRUnit:
		return false
	for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
		if not w.special_rules.is_empty():
			return false
	return true


## (1) A human unit of this table's player while the game is PLAYING: it gets the explicit activation (O14 (1b)).
static func is_lifecycle_unit(main, gu: GameUnit) -> bool:
	return gu != null and applies(main) and not main._solo_is_ai_unit(gu) and main._solo_i_own_unit(gu) \
		and main.opr_army_manager.game_phase == OPRArmyManager.GamePhase.PLAYING


## (2) A lifecycle unit whose shot, End and digest resolve in the core.
static func is_core_unit(main, gu: GameUnit) -> bool:
	return is_lifecycle_unit(main, gu) and is_plain(gu)


## (3) Equal to (2) for now; step 82 widens it by movement rule.
static func on_move_path(main, gu: GameUnit) -> bool:
	return is_core_unit(main, gu)


## A core handle for the board as it stands (BattleSim.capture, plain form, gate reads); 0 on failure. The first
## capture of a game sends the game header, exactly as the AI's `_core_plan` does (one header per game, shared with it),
## so every step runs at the game's rules epoch, not at epoch 0.
static func capture(main) -> int:
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	if core == null:
		return 0
	var round_no: int = main.opr_army_manager.current_round
	var state := BattleSim.capture(main.opr_army_manager, sc.objectives_provider, sc.objective_owner_of, round_no,
		maxi(sc.game_rounds, round_no), sc.majority_in_cover, sc._has_los, sc.terrain_type_at, int(sc.ai_slot))
	if not sc._core_header_done:
		var head := AiActRecorder._header_line(state, sc.terrain_type_at)
		if not bool(core.set_game_header(head)):
			return 0
		sc._core_header_done = true
		sc._core_terrain_sig = hash(head["terrain"])
		sc._core_statics_builds = int(core.statics_builds())   # the header's build is #1, as in _core_plan
	else:
		sc._core_refresh_terrain()
	var plain := BattleSim.state_to_plain(state)
	AiActRecorder._stamp_gate_reads(state, plain)
	return int(core.capture_plain(plain))


## Calls per activation before the driver gives up (a plain volley asks three to four times).
const MAX_STEPS := 64


## One activation through the core: ask, print the lines not printed yet, land, throw on the owner's tray, ask again.
## `transcript` gains one faces entry per throw; `on_throw(kind, index)` runs before each throw (a test seam).
## `beat(event, answer, faces)` (step 42b, the table's presentation) is awaited before each throw ("throw"), after it
## ("thrown", with its faces) and at the last answer (its step name).
## Returns the core's last answer plus "steps" (calls), "core_us" (their total time) and "max_us" (the slowest).
## A `done` answer's state handle is released once the table landed it (R4); `keep_handle` hands it to the caller instead,
## who releases it.
static func drive(main, h: int, unit: GameUnit, transcript: Array, ai: bool,
		on_throw: Callable = Callable(), keep_handle := false, beat: Callable = Callable()) -> Dictionary:
	var core: Object = (main.solo_controller as SoloController)._core_node_ready()
	var enforce: bool = main.object_manager._strict_movement_enforced()
	var printed := 0
	var start_models := _start_models(main)
	var landed := {}
	var core_us := 0
	var max_us := 0
	var r: Dictionary = {}
	for step in MAX_STEPS:
		var t0 := Time.get_ticks_usec()
		r = core.step_activation(h, unit.unit_id, transcript, enforce)
		var us := Time.get_ticks_usec() - t0
		core_us += us
		max_us = maxi(max_us, us)
		var lines: Array = r.get("lines", [])
		for i in range(printed, lines.size()):
			var line: Dictionary = lines[i]
			main._log_rule_event(int(line["category"]), str(line["text"]), ai, str(line["detail"]))
		printed = maxi(printed, lines.size())
		await land_step(main, unit, r.get("landings", []), start_models, landed)
		if str(r["step"]) == "done":
			await land_delta(main, r.get("delta", []), start_models, landed)
			if not keep_handle:
				core.release(int(r.get("handle", 0)))
				r.erase("handle")
		if str(r["step"]) != "need_roll":
			if beat.is_valid():
				await beat.call(str(r["step"]), r, [])
			r.merge({"steps": step + 1, "core_us": core_us, "max_us": max_us}, true)
			return r
		var owner := str(r["owner"])
		var roller := _roller_of(main, unit, transcript, owner, str(r.get("owner_key", "")))
		var label: String = "AI (%s)" % owner if main._solo_is_ai_unit(roller) else main._roller_label(roller)
		if on_throw.is_valid():
			on_throw.call(str(r["kind"]), int(r["index"]))
		if beat.is_valid():
			await beat.call("throw", r, [])
		if str(r["kind"]) == "defense" and roller != unit and not main._solo_is_ai_unit(roller) \
				and main._solo_i_own_unit(roller):   # step 42 (O21): a local defender sees its saves coming, as on the table
			await main._solo_ask_saves(unit, roller, _shot_weapon(unit, lines), int(r["faces"]), int(r["target"]), 0)
		var faces: Array = await main._owner_roll(roller, int(r["faces"]), int(r["target"]), str(r["kind"]), "",
			{"label": label, "what": "%s dice" % r["kind"]})
		transcript.append({"t": "faces", "faces": faces})
		if beat.is_valid():
			await beat.call("thrown", r, faces)
	push_error("CoreActivation.drive: %s still needs dice after %d steps" % [unit.get_name(), MAX_STEPS])
	r.merge({"steps": MAX_STEPS, "core_us": core_us, "max_us": max_us}, true)
	return r


## Step 42 (O21): the weapon named by the core's last shot line ("<shooter> fires <weapon> at <target> — <n> hits",
## dice.rs) among `unit`'s own weapons, for the save card; "" when no line names one.
static func _shot_weapon(unit: GameUnit, lines: Array) -> String:
	var src := unit.source_data as OPRApiClient.OPRUnit
	for i in range(lines.size() - 1, -1, -1):
		for w in src.weapons if src != null else []:
			if str((lines[i] as Dictionary)["text"]).contains(" fires %s at " % w.name):
				return w.name
	return ""


## Step 43: the AI volleys the core resolved and the ones it refused (the AI smoke resets and reads them).
static var ai_runs := 0
static var ai_refusals := 0


## Step 42: the AI's volley through the core - Hold or Advance, the unit and its one target (the table's own pick) plain,
## no Dangerous test this activation (the table rolled it already; the core would roll it again). `h` is the board
## before the move (the AI body captured it and releases it). True = the core resolved the volley. A refusal is a
## defect: reported, and the table shoots instead - unless a die was already thrown (never resolve a volley twice).
static func run_ai(main, unit: GameUnit, report: Dictionary, target: GameUnit, h: int, shots: Array = []) -> bool:
	var kind := int(report.get("action", -1))
	if h == 0 or not (kind in [AiDecision.Action.HOLD, AiDecision.Action.ADVANCE]) or not is_plain(unit) \
			or not is_plain(target) or int(report.get("dangerous_dice", report.get("dangerous_models", 0))) > 0:
		return false
	var at: Array = unit.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	# Step 42c: each model's walked route (the planner's, world XZ) rides along, so the core's move check measures the
	# route, not the chord (R3); a model that did not move sends none.
	var routes := {}
	for p in main.solo_controller.last_move_paths:
		routes[p["model"]] = (p["path"] as Array).map(func(v: Vector3) -> Vector2: return Vector2(v.x, v.z))
	var trails: Array = unit.get_alive_models().map(func(m: ModelInstance) -> Array: return routes.get(m, []))
	var t: Array = [{"t": "begin"}, {"t": "placed", "positions": at, "trails": trails},
		{"t": "intent", "kind": kind, "shoot": target.unit_id}]
	# Step 42b: the table's presentation of the volley (_present); its stage opens before the core's first line.
	var st := {"n": 0, "open": false, "result": false, "hits": 0, "landed": 0, "announce": [],
		"before": main._solo_combined_alive(target), "moved": bool(report.get("moved", false))}
	var beat := func(ev: String, a: Dictionary, faces: Array) -> void:
		await _present(main, unit, target, shots, st, ev, a, faces)
	if not shots.is_empty():
		main._solo_stage_begin("%s fires at %s" % [unit.get_name(), target.get_name()])
	var r: Dictionary = await drive(main, h, unit, t, true, Callable(), false, Callable() if shots.is_empty() else beat)
	if str(r["step"]) == "done":
		ai_runs += 1
		announce(main, unit, target)   # step 50/51: the table that ran the AI activation announces its digest check
		return true
	ai_refusals += 1
	push_error("CoreActivation.run_ai: %s - the core answered %s: %s" % [unit.get_name(), r["step"], r.get("reason", "")])
	return t.any(func(e: Dictionary) -> bool: return str(e["t"]) == "faces")


## Step 42b: the table's show around an AI volley (_solo_resolve_ai_volley's calls in its order) on the core's steps:
## at the first hit roll the announce (the core says its line), the fan and the Declaration beat; a tracer before each
## hit roll (`shots` in the table's order); a weapon's hit strip and beat after its saves, or at the next hit roll or
## the end if it missed; before the morale roll or at the end the outcome toast and the Result beat; the Morale beat.
## A refusal only closes.
static func _present(main, unit: GameUnit, target: GameUnit, shots: Array, st: Dictionary, ev: String, a: Dictionary,
		faces: Array) -> void:
	var kind := str(a.get("kind", ""))
	var n: int = st["n"]
	var prev := str((shots[clampi(n - 1, 0, shots.size() - 1)]["profile"] as Dictionary).get("name", "weapon"))
	if ev == "throw" and kind == "attack":
		if n == 0:
			st["announce"] = main._solo_show_attack_announce(unit, target, "fires at", false)
			main._solo_show_fan_for_unit(unit)
			await main._solo_stage_phase("Declaration", SoloController.Pace.ANNOUNCE)
		elif st["open"]:
			await main._solo_stage_phase(prev)
		var shot: Dictionary = shots[mini(n, shots.size() - 1)]
		var d: Dictionary = main._solo_shot_eligibility(shot["member"], shot["profile"], shot, target, false, st["moved"])
		var pairs: Array = d["pairs"]
		main._solo_record_shot(unit, shot["member"], target, shot["profile"], int(d["sighted"]), int(d["bearers"]),   # 42c
			int(shot["max"]), int((d["report"] as Dictionary)["attacks"]),
			int(SoloController.effective_shoot_reach_in(float(shot["reach"]), target)))
		main._vfx_volley(shot["member"], target, shot["profile"],
			pairs.slice(0, int(d["bearers"]) if int(d["bearers"]) >= 0 else pairs.size()), false)
		st.merge({"n": n + 1, "open": true}, true)
	elif ev == "thrown" and kind == "defense":
		var saves := AiCombatMath.count_blocks(faces, int(a["target"]), 0)
		st.merge({"hits": st["hits"] + faces.size(), "landed": st["landed"] + faces.size() - saves, "open": false}, true)
		main._vfx_hit_strip(target, faces.size(), saves)
		await main._solo_stage_phase(prev)
	elif ev == "done" or (ev == "throw" and kind == "morale"):
		if st["open"]:
			st["open"] = false
			await main._solo_stage_phase(prev)
		if not st["result"]:
			st["result"] = true
			main._solo_clear_announce(st["announce"])
			main._solo_clear_auto_fan()
			await main._solo_show_outcome(main._solo_volley_outcome(target, st["hits"], st["landed"],
				int(st["before"]) - main._solo_combined_alive(target)))
			await main._solo_stage_phase("Result")
		if ev == "done" and int(st["landed"]) > 0:
			await main._solo_stage_phase("Morale")
		if ev == "done":
			main._solo_stage_end()
	elif ev != "throw" and ev != "thrown":
		main._solo_clear_announce(st["announce"])
		main._solo_clear_auto_fan()
		main._solo_stage_end()


## Step 38b: the weapons of a human volley in the table's order (`_run_human_shooting`: the attack groups, each profile
## that fires), as `_present_human` shows them: {member, profile}.
static func _human_shots(main, unit: GameUnit, target: GameUnit) -> Array:
	var sc: SoloController = main.solo_controller
	var dist: float = sc.nearest_melee_gap_in(unit, target)
	if dist == INF:
		dist = MoveIntent.distance_inches(sc.unit_centre(unit), sc.unit_centre(target))
	var out: Array = []
	for g in main._solo_attack_groups(unit, dist, false, target):
		for p in (g as Dictionary).get("profiles", []):
			if int((p as Dictionary).get("attacks", 0)) > 0:
				out.append({"member": g["member"], "profile": main._solo_bridge_granted_flags(g["member"], p, target)})
	return out


## Step 38b: what `_run_human_shooting` shows around a volley, on the core's steps: the Declaration beat at the first hit
## roll; a tracer before each hit roll; a weapon's hit strip and beat after its saves, or at the next hit roll or the end
## if it missed; the Result beat before the morale roll or at the end; the Morale beat and the close. The table's human
## volley shows no announce card and no outcome toast (those are the AI's), so neither does this. A refusal only closes.
static func _present_human(main, unit: GameUnit, target: GameUnit, shots: Array, st: Dictionary, ev: String, a: Dictionary,
		faces: Array) -> void:
	var kind := str(a.get("kind", ""))
	var n: int = st["n"]
	var prev := str((shots[clampi(n - 1, 0, shots.size() - 1)]["profile"] as Dictionary).get("name", "weapon"))
	if ev == "throw" and kind == "attack":
		if n == 0:
			await main._solo_stage_phase("Declaration")
		elif st["open"]:
			await main._solo_stage_phase(prev)
		var shot: Dictionary = shots[mini(n, shots.size() - 1)]
		var profile: Dictionary = shot["profile"]
		main._vfx_player_volley(shot["member"], target, profile, bool(profile.get("indirect", false))
			or SoloController.granted_indirect_of(unit) or main._solo_target_grants_indirect(target))
		st.merge({"n": n + 1, "open": true}, true)
	elif ev == "thrown" and kind == "defense":
		st["open"] = false
		main._vfx_hit_strip(target, faces.size(), AiCombatMath.count_blocks(faces, int(a["target"]), 0))
		await main._solo_stage_phase(prev)
	elif ev == "done" or (ev == "throw" and kind == "morale"):
		if st["open"]:
			st["open"] = false
			await main._solo_stage_phase(prev)
		if not st["result"]:
			st["result"] = true
			await main._solo_stage_phase("Result")
		if ev == "done":
			await main._solo_stage_phase("Morale")
			main._solo_stage_end()
	elif ev != "throw" and ev != "thrown":
		main._solo_stage_end()


## The unit a roll belongs to: the core names it by roster key (`owner_key`: two units may share a display name, and a
## unit may be renamed mid-game). Only when the core could not tell: the actor or the target of its shot by `owner`
## (the name), else the actor.
static func _roller_of(main, unit: GameUnit, transcript: Array, owner: String, owner_key: String = "") -> GameUnit:
	var keyed = main.opr_army_manager.game_units.get(owner_key)
	if keyed is GameUnit:
		return keyed
	if unit.get_name() == owner:
		return unit
	for e in transcript:
		if str((e as Dictionary).get("t", "")) == "intent":
			var foe = main.opr_army_manager.game_units.get(str((e as Dictionary).get("shoot", "")))
			if foe is GameUnit and (foe as GameUnit).get_name() == owner:
				return foe
	return unit


## Every living model on the table and its position at the activation start, in get_alive_models() order.
static func _start_models(main) -> Array:
	var out: Array = []
	for gu in main.opr_army_manager.game_units.values():
		for m in (gu as GameUnit).get_alive_models():
			if m.node != null and is_instance_valid(m.node):
				out.append({"model": m, "at": m.node.global_position})
	return out


## The start model of `gu` that stands at `at` on the table (XZ, within a millimetre); null when none does. The height is
## not compared: a placed position carries the drag's lift (the drop is checked before the models settle), the model's own
## node is back on the table.
static func _model_at(start_models: Array, gu: GameUnit, at: Vector3) -> ModelInstance:
	for e in start_models:
		var m: ModelInstance = e["model"]
		var p: Vector3 = e["at"]
		if m.unit == gu and Vector2(p.x, p.z).distance_to(Vector2(at.x, at.z)) < 0.001:
			return m
	return null


## Lands one step's landings on the table (O4 b): a wound shows at once on the wound marker, the dead leave right
## after the saves. Every need_roll repeats the earlier landings; `done` skips what this activation already landed.
static func land_step(main, _gu: GameUnit, landings: Array, start_models: Array, done: Dictionary) -> void:
	for entry in landings:
		var lgu: GameUnit = main.opr_army_manager.game_units.get(str(entry["unit"]))
		var died: Array[ModelInstance] = []
		for lm in entry["models"]:
			var m: ModelInstance = _model_at(start_models, lgu, lm["at"]) if lgu != null else null
			if m == null:
				push_error("CoreActivation.land_step: no model of %s at %s" % [entry["unit"], lm["at"]])
				continue
			if done.has(m):
				continue
			done[m] = true
			var before := m.wounds_current
			if bool(lm["dead"]):
				m.apply_damage(before)
				main._vfx_pip(ResultPips.Kind.KILL, m, 1)
				died.append(m)
			elif int(lm["wounds_left"]) < before:
				m.wounds_current = int(lm["wounds_left"])
				main._vfx_pip(ResultPips.Kind.WOUND, m, before - m.wounds_current)
				main.radial_menu_controller._update_wound_marker(m)
				if main.network_manager != null and main.network_manager.has_method("broadcast_model_wounds"):
					main.network_manager.broadcast_model_wounds(m)
		if not died.is_empty():
			main._core_said_losses = bool(entry.get("loss_line", false))   # step 27: the core said this loss line
			await main._solo_remove_dead_models(lgu, died, int(lgu.unit_properties.get("player_id", 1)))
			main._core_said_losses = false


## The activation's final delta (binding step 17): Shaken onto the table; a unit that moved AND lost models is
## accepted only when its losses already landed per step, else nothing lands and done["unknown"] is set.
static func land_delta(main, delta: Array, start_models: Array, done: Dictionary) -> void:
	for d in delta:
		var gu: GameUnit = main.opr_army_manager.game_units.get(str(d["unit"]))
		if gu == null:
			continue
		if bool(d["unknown"]):
			var start_alive := start_models.filter(func(e) -> bool: return (e["model"] as ModelInstance).unit == gu)
			var landed_dead := start_alive.filter(func(e) -> bool: return done.has(e["model"]) \
				and not (e["model"] as ModelInstance).is_alive)
			if landed_dead.size() != start_alive.size() - int(d["alive"]):
				push_error("CoreActivation.land_delta: %s moved and lost models the steps did not land" % gu.get_name())
				done["unknown"] = true
				return
		if bool(d["shaken"]) != gu.is_shaken:
			main.radial_menu_controller.card_toggle_shaken(gu)
			main._solo_mirror_shaken(gu)


## Step 28: the open activations, unit_id -> {handle, transcript, start_models, start_pos, start_rot, moved_round_before
## (absent when the unit had no stamp), dice, journal}. A session opens at the Start door (step 29) for EVERY lifecycle
## unit and closes at its End or Cancel (steps 35, 36).
static var _sessions: Dictionary = {}


## Opens `gu`'s session: a core capture of the board as it stands, plus the unit's start snapshot in get_alive_models()
## order - each model's position and facing exactly as ObjectManager._start_dragging stores them (before the lift).
## R6: a unit that already moved this round (an MP rejoin brings it back moved but not activated) starts where the move
## ledger says the round began for it (XZ; the height stays the model's own), so a new Start cannot launder that move.
## False, and nothing changes, when `gu` is not a lifecycle unit, already has a session, or the capture failed.
static func open_session(main, gu: GameUnit) -> bool:
	if not is_lifecycle_unit(main, gu) or _sessions.has(gu.unit_id):
		return false
	var h := capture(main)
	if h == 0:
		return false
	var round_no: int = main.opr_army_manager.current_round
	var starts: Dictionary = {}
	if int(gu.unit_properties.get("moved_round", -1)) == round_no and main.move_trails != null:
		starts = main.move_trails.ledger.round_starts_for_unit(gu.unit_id, round_no)
	var start_pos: Array[Vector3] = []
	var start_rot: Array[float] = []
	var start_own: Array = []   # step 32: the models start_pos / start_rot belong to, in the same order
	for m in gu.get_alive_models_with_attached():   # a joined hero moves with its host (step 30), so it starts with it
		if m.node != null and is_instance_valid(m.node):
			var p: Vector3 = m.node.global_position
			var was: Variant = starts.get(int(m.node.get_meta("network_id", 0)))
			start_pos.append(Vector3((was as Vector2).x, p.y, (was as Vector2).y) if was is Vector2 else p)
			start_rot.append(m.node.rotation.y)
			start_own.append(m)
	var s := {"handle": h, "transcript": [{"t": "begin"}], "start_models": _start_models(main), "start_pos": start_pos,
		"start_rot": start_rot, "start_own": start_own, "dice": false,
		"journal": _journal_records(main).merged({"props": _journal_props(main)}), "moved_before": {},
		"ledger_mark": main.move_trails.ledger.entries.size() if main.move_trails != null else 0}
	if gu.unit_properties.has("moved_round"):
		s["moved_round_before"] = gu.unit_properties["moved_round"]
	for u in [gu] + gu.get_attached_heroes():   # step 32: each moved_round before the Start (null = none), for the reset
		s["moved_before"][u.unit_id] = u.unit_properties.get("moved_round")
	_sessions[gu.unit_id] = s
	last_target = null   # step 50: a new activation never inherits the target of a cancelled one
	if on_move_path(main, gu):   # step 31 (O1/O2): every activation of a move-path unit starts on Advance
		main.object_manager.set_movement_cap(ObjectManager.MovementCap.ADVANCE)
	main._update_movement_cap_display()
	_refresh_card(main)
	return true


## The core's move bands of `gu` ({advance, rush, charge} inches, from its session's capture) when `gu` has a session
## and is on the move path; else {}: every other unit keeps the table's bands.
static func bands(main, gu: GameUnit) -> Dictionary:
	if gu == null or not _sessions.has(gu.unit_id) or not on_move_path(main, gu):
		return {}
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	var a: Dictionary = core.move_allowance(int(_sessions[gu.unit_id]["handle"]), gu.unit_id) if core != null else {}
	if a.is_empty():
		return {}
	return {"advance": a["advance"], "rush": a["rush"], "charge": a["charge"]}


## Whether `unit_id`'s activation is open (Started and not yet ended or cancelled).
static func session_open(unit_id: String) -> bool:
	return _sessions.has(unit_id)


## The name of ANOTHER unit whose session is open ("" when none; `except` null = any unit): check_begin's input.
static func open_unit_name(main, except: GameUnit) -> String:
	for id in _sessions:
		var gu = main.opr_army_manager.game_units.get(id)
		if gu is GameUnit and (except == null or id != except.unit_id):
			return (gu as GameUnit).get_name()
	return ""


## Releases the session's core handle and forgets the session; a unit without one is a no-op. `main` null (the scene is
## gone) only forgets it.
static func close_session(main, unit_id: String) -> void:
	if not _sessions.has(unit_id):
		return
	var sc: SoloController = main.solo_controller if main != null else null
	var core: Object = sc._core_node_ready() if sc != null else null
	if core != null:
		core.release(int(_sessions[unit_id]["handle"]))
	_sessions.erase(unit_id)
	if main != null:
		main._refresh_movement_cap_row()   # step 31: an ended unit shows Off again
	_refresh_card(main)


## Step 35 (O9): the first die of a roll THIS table throws commits every open activation: from then on its Cancel is gone.
## Idempotent; the card follows (its Cancel button goes) only when a session was still cancellable.
static func note_die(main) -> void:
	var changed := false
	for id in _sessions:
		if not bool((_sessions[id] as Dictionary)["dice"]):
			(_sessions[id] as Dictionary)["dice"] = true
			changed = true
	if changed:
		_refresh_card(main)


## Step 36: the presented unit card follows the sessions (its End / Cancel buttons); a table without a dock (a scene being
## freed) has nothing to refresh.
static func _refresh_card(main) -> void:
	if main != null and main.unit_dock != null:
		main.unit_dock.refresh_presented()


## Step 36: round advance ends every activation, so every open session closes.
static func close_all(main) -> void:
	for id in _sessions.keys():
		close_session(main, id)


## Step 68 (O16): an effect that adds, removes or re-hosts a unit (the Reinforcement sacrifice, Disembark, Unload) commits THAT
## unit's open activation like a die: its Cancel is gone (the card follows), nothing is undone, `committed` keeps the first
## reason. Idempotent; a unit without a session is a no-op.
static func note_commit(main, gu: GameUnit, why: String) -> void:
	if gu == null or not _sessions.has(gu.unit_id):
		return
	var s: Dictionary = _sessions[gu.unit_id]
	var open: bool = not bool(s["dice"])
	s["dice"] = true
	if not s.has("committed"):
		s["committed"] = why
	if open:
		_refresh_card(main)


## Step 35: whether `unit_id`'s activation can still be cancelled: open, and no die thrown since the Start.
static func can_cancel(unit_id: String) -> bool:
	return _sessions.has(unit_id) and not bool((_sessions[unit_id] as Dictionary)["dice"])


## Step 35 (O9, O15 (3)): Cancel. The core says its sentence (its answer must be `cancelled`: a refusal is a defect, reported,
## and nothing is undone), then the table puts the unit back (step 32: positions, chalk, ledger, moved_round, take-backs,
## and for the other table the move, rotation and trails-undo frames), gives back what a one-time effect spent (step 37) and
## closes the session. The unit is NOT activated by a cancel: no unit_deactivated, no activation broadcast, no AI reply.
static func cancel(main, gu: GameUnit) -> void:
	if gu == null or not can_cancel(gu.unit_id):
		return
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	if core == null:
		push_error("cancel: no core for %s's open activation" % gu.get_name())
		return
	var s: Dictionary = _sessions[gu.unit_id]
	var r: Dictionary = core.step_activation(int(s["handle"]), gu.unit_id, (s["transcript"] as Array) + [{"t": "cancel"}],
		main.object_manager._strict_movement_enforced())
	if str(r.get("step", "")) != "cancelled":
		push_error("cancel: the core answered %s to the Cancel of %s" % [r, gu.get_name()])
		return
	for line in r.get("lines", []):
		main._log_rule_event(int(line["category"]), str(line["text"]), false, str(line["detail"]))
	reset_to_start(main, gu, "")
	undo_journal(main, gu)
	close_session(main, gu.unit_id)


## Step 34 (N2 b): the core re-checks a drop of `gu` (a move-path unit with an open session) - every alive model where it
## stands now, at the declared mode, Enforce Movement Limit as set. Ok: this placement replaces the session's one and the
## core's lines are written (with Enforce off, the escape hatch's overrun line); false. Refused: the reason is logged
## (it reaches the other table) and toasted; true - the caller snaps the drag back and broadcasts the restore.
## Two defects are reported with push_error and the drop STANDS unchecked (a refusal would trap the unit with no way to
## move it): a selector that is not Advance, Rush or Charge (declared_mode), and an open session without its core.
static func drop_refused(main, gu: GameUnit) -> bool:
	var mode := declared_mode(main)
	if mode == 0:
		return false   # declared_mode reported the defect
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	if core == null:
		push_error("drop_refused: no core for %s's open activation - the drop is not checked" % gu.get_name())
		return false
	var s: Dictionary = _sessions[gu.unit_id]
	var at: Array = gu.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	var trails := session_trails(main, gu, main.object_manager.drag_paths())   # step 66 (MOVE_GAPS 5)
	var r: Dictionary = core.check_move(int(s["handle"]), gu.unit_id,
		{"mode": mode, "positions": PackedVector3Array(at), "trails": trails}, main.object_manager._strict_movement_enforced())
	if not bool(r.get("ok", false)):
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(r.get("reason", "")))
		main._show_toast(str(r.get("reason", "")))
		return true
	s["transcript"] = (s["transcript"] as Array).filter(func(e: Dictionary) -> bool: return str(e["t"]) != "placed") \
		+ [{"t": "placed", "positions": at, "trails": trails}]
	for line in r.get("lines", []):
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(line["text"]), false, str(line["detail"]))
	return false


## Step 66 (MOVE_GAPS 5): per alive model of `gu` (get_alive_models() order) the path it walked this activation, as the
## core's drop check takes it: this unit's ledger entries since its session opened (drop order, each join point once) and
## then the drag in flight (`now`: model id -> path, ObjectManager.drag_paths(); a refused drop is never recorded). A model
## that did not walk, or whose path does not run unbroken from where the core captured it to where it stands (the ledger
## and the board disagree: a take-back, a move the ledger never saw), gets [] and is checked by its chord, as before.
static func session_trails(main, gu: GameUnit, now: Dictionary) -> Array:
	var s: Dictionary = _sessions[gu.unit_id]
	var entries: Array = main.move_trails.ledger.entries if main.move_trails != null else []
	var walked := {}   # model id -> its paths in drop order
	for i in range(mini(int(s["ledger_mark"]), entries.size()), entries.size()):
		if str(entries[i]["unit"]) == gu.unit_id:
			(walked.get_or_add(int(entries[i]["model"]), []) as Array).append(entries[i]["points"])
	var begun := {}   # model -> where the core captured it
	for e in s["start_models"]:
		begun[e["model"]] = Vector2((e["at"] as Vector3).x, (e["at"] as Vector3).z)
	var out: Array = []
	for m in gu.get_alive_models():
		var id := int(m.node.get_meta("network_id", 0))
		var paths: Array = walked.get(id, [])
		if now.has(id):
			paths.append(now[id])
		out.append(_unbroken(paths, begun.get(m, Vector2.INF), Vector2(m.node.global_position.x, m.node.global_position.z)))
	return out


## `paths` joined end to start (each join point once) when the first starts at `start`, each starts where the one before
## ended and the last ends at `end`, all within the core's 0.01" trail tolerance; else an empty path.
static func _unbroken(paths: Array, start: Vector2, end: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tol := 0.01 / ObjectManager.METERS_TO_INCHES
	for p: PackedVector2Array in paths:
		if p.size() < 2 or (out[out.size() - 1] if not out.is_empty() else start).distance_to(p[0]) > tol:
			return PackedVector2Array()
		out.append_array(p if out.is_empty() else p.slice(1))
	return out if not out.is_empty() and out[out.size() - 1].distance_to(end) <= tol else PackedVector2Array()


## Step 31: the declared movement mode for the core, read from the selector and never from distance: Advance 1, Rush 2,
## Charge 3 (the core's kinds, sim.rs). Anything else is a defect: reported, and 0 means no core call.
static func declared_mode(main) -> int:
	match int(main.object_manager._movement_cap):
		ObjectManager.MovementCap.ADVANCE:
			return 1
		ObjectManager.MovementCap.RUSH:
			return 2
		ObjectManager.MovementCap.CHARGE:
			return 3
	push_error("declared_mode: the movement selector is %d - not Advance, Rush or Charge" % int(main.object_manager._movement_cap))
	return 0


## Step 38 (O15 (1)): the human attack door. False = not taken, the old path runs: `attacker` is not a core unit, the
## target is not plain, the selector says Charge (a melee action) or is no declaration (declared_mode reports it). True =
## taken. No open activation: "Activate <Unit> first.", nothing rolls. Else the declared intent (the selector's mode,
## never the distance; the core turns it into Hold when nothing moved) and the shot go through the core with the
## session's transcript; the session's own transcript is not touched, so a refusal can be tried again. `done`: the steps
## have landed and `last_target` is noted for step 50; the session stays open until the door ENDS the activation (the
## toggle that completes a shot ends it only while the session is open - with none, "Activate" would start a new one),
## and the door closes it after. `refused` below the transcript's size (an order rule, the O3 Rush sentence): logged and
## toasted, nothing was shot, the session stays open (the caller returns then). `refused` at the transcript's size is the
## core's own defect: reported, nothing toasted, the session stays open.
static func human_shoot(main, attacker: GameUnit, target: GameUnit, on_throw: Callable = Callable()) -> bool:
	if not is_core_unit(main, attacker) or not is_plain(target) \
			or int(main.object_manager._movement_cap) == ObjectManager.MovementCap.CHARGE:
		return false
	if main.core_door_refused(attacker):
		return true
	var mode := declared_mode(main)
	var s: Dictionary = _sessions.get(attacker.unit_id, {})
	if mode == 0:
		return false   # declared_mode reported the defect
	if s.is_empty():
		push_error("human_shoot: %s has no session after the door let it through" % attacker.get_name())
		return true
	var t: Array = (s["transcript"] as Array).duplicate()
	t.append({"t": "intent", "kind": mode, "shoot": target.unit_id})
	# Step 38b: the table's presentation of a human volley (_present_human); its stage opens before the core's first line.
	var shots := _human_shots(main, attacker, target)
	var st := {"n": 0, "open": false, "result": false}
	var beat := func(ev: String, a: Dictionary, faces: Array) -> void:
		await _present_human(main, attacker, target, shots, st, ev, a, faces)
	if not shots.is_empty():
		main._solo_stage_begin("%s fires at %s" % [attacker.get_name(), target.get_name()])
	var r: Dictionary = await drive(main, int(s["handle"]), attacker, t, false, on_throw, false, Callable() if shots.is_empty() else beat)
	if str(r["step"]) == "done":
		last_target = target
	elif str(r["step"]) == "refused" and int(r["index"]) < t.size():
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(r["reason"]))
		main._show_toast(str(r["reason"]))
	else:
		push_error("human_shoot: the core answered %s for %s's shot" % [r, attacker.get_name()])
	return true


## Step 69: the units whose End is running through the core (unit_id -> true).
static var _ending: Dictionary = {}


## Step 69 (D3 yes): the card's End of a core unit's activation goes through the core first, so a move that ends without a
## shot tests Dangerous terrain along its walked path too (steps 59-61). The declared intent has no target (the core turns it
## into Hold when nothing moved); the session's transcript is not touched. False = not taken, the door ends the activation:
## not a core unit, no session, a shot already went through the core (its run held the move's tests), or no declaration
## (declared_mode reported it), or the selector says Charge (no charge is on the core's step path yet: it would refuse and
## trap the unit open); also `done`, whose throws have landed. True = the activation stays open: the core refused
## (the reason is logged and toasted, the player sees why), or answered otherwise (a defect, reported), or this End is
## already running (a second press while the dice roll).
static func end(main, gu: GameUnit, on_throw: Callable = Callable()) -> bool:
	if not is_core_unit(main, gu) or not _sessions.has(gu.unit_id) or last_target != null:
		return false
	if _ending.has(gu.unit_id):
		return true
	var mode := declared_mode(main)
	if mode == 0 or mode == 3:
		return false   # declared_mode reported the defect, or a Charge: the old door ends it
	var t: Array = (_sessions[gu.unit_id]["transcript"] as Array).duplicate()
	t.append({"t": "intent", "kind": mode, "shoot": ""})
	_ending[gu.unit_id] = true
	var r: Dictionary = await drive(main, int(_sessions[gu.unit_id]["handle"]), gu, t, false, on_throw)
	_ending.erase(gu.unit_id)
	if str(r["step"]) == "done":
		return false
	if str(r["step"]) == "refused" and int(r["index"]) < t.size():
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(r["reason"]))
		main._show_toast(str(r["reason"]))
	else:
		push_error("end: the core answered %s for the End of %s" % [r, gu.get_name()])
	return true


## One-core P3 step 32 (the snap-back answer): `gu` back where its open activation started. Every model that is still
## alive goes to the session's start position and facing through the existing take-back, built once per drop of this
## round in the unit's ledger (drags and step 65a's formation drops alike; the models ride the first, so each moves and
## turns once on the wire) and run, never pushed: it broadcasts the move and the rotation, erases that drop's chalk and
## ledger entries and sends their undo. Then moved_round is what it was before the Start, no Ctrl+Z can take back a reset
## move, the transcript loses its placed inputs, and a non-empty `line` is ONE rule line (log + broadcast). The caller
## never runs it during a drag (O11 a); a unit without a session is a no-op.
static func reset_to_start(main, gu: GameUnit, line: String) -> void:
	if gu == null or not _sessions.has(gu.unit_id):
		return
	var s: Dictionary = _sessions[gu.unit_id]
	var nodes: Array[Node3D] = []
	var at: Array[Vector3] = []
	var rot: Array[float] = []
	for row in start_rows(gu):
		nodes.append(row[0])
		at.append(row[1])
		rot.append(row[2])
	var round_no: int = main.opr_army_manager.current_round
	var units: Array = [gu] + gu.get_attached_heroes()   # a joined hero's models record their drops under its own key
	var drops: Array = []   # [unit, drop id] of this round
	for u in units:
		for e in main.move_trails.ledger.entries_for_unit(u.unit_id):
			var d := [u, int(e.get("drop_id", -1))]
			if int(e.get("round", -1)) == round_no and not drops.has(d):
				drops.append(d)
	if drops.is_empty():
		drops.append([gu, -1])   # nothing in the ledger: the models still go back (no drop has id -1: ids are msec stamps)
	var peer: int = main.network_manager.get_my_peer_id() if main.network_manager != null else 0
	var none: Array[Node3D] = []
	for d in drops:
		var u: GameUnit = d[0]
		var owner := int(u.unit_properties.get("player_id", 0))
		UndoManager.MoveTakebackAction.new(nodes if d == drops[0] else none, at, rot, owner, u.unit_id, u.get_name(),
			int(d[1]), main.move_trails, main.network_manager, null, peer, null).undo()
	for u in units:   # the stamp the other table reads (Entrenched, Artillery) goes back through the sync seam
		main._sync_unit_property(u, "moved_round", (s["moved_before"] as Dictionary).get(u.unit_id))
		main.undo_manager.expire_move_takebacks(u.unit_id)
	s["transcript"] = (s["transcript"] as Array).filter(func(t: Dictionary) -> bool: return str(t.get("t", "")) != "placed")
	if not line.is_empty():
		main._log_rule_event(BattleLog.Category.MOVEMENT, line)


## Step 33: whether a model of `gu` moved this activation: more than the table's drop floor (0.1") from its start, or an
## entry of this round in the unit's ledger.
static func has_moved(main, gu: GameUnit) -> bool:
	var round_no: int = main.opr_army_manager.current_round
	for e in main.move_trails.ledger.entries_for_unit(gu.unit_id):
		if int(e.get("round", -1)) == round_no:
			return true
	for row in start_rows(gu):
		var p: Vector3 = (row[0] as Node3D).global_position
		if Vector2(p.x, p.z).distance_to(Vector2((row[1] as Vector3).x, (row[1] as Vector3).z)) * 39.3701 > 0.1:
			return true
	return false


## Step 32: the living models of `gu`'s activation (a joined hero's too) with where it started them,
## [[node, position, facing], ...]; `start_own` holds those models in the order of start_pos, set at the Start.
static func start_rows(gu: GameUnit) -> Array:
	var s: Dictionary = _sessions[gu.unit_id]
	var out: Array = []
	for i in (s["start_own"] as Array).size():
		var m: ModelInstance = s["start_own"][i]
		if m.is_alive and m.node != null and is_instance_valid(m.node):
			out.append([m.node, s["start_pos"][i], float(s["start_rot"][i])])
	return out


## Closes every open session, and the next capture sends the game header again (a loaded game's units are not the
## header's). The store is static, so the game's lifecycle calls this: main's `_exit_tree` (quit to menu, which a new game
## follows) and its save load.
static func reset_all(main) -> void:
	for id in _sessions.keys():
		close_session(main, id)
	_announced.clear()
	_ending.clear()   # step 69
	last_target = null
	_fixes_due.clear()
	_ended_round = -1   # step 52c
	_ended_rows.clear()
	if main != null and is_instance_valid(main.solo_controller):
		main.solo_controller._core_header_done = false
		if int(main._solo_core_ai_h) != 0:   # step 42c: the AI body's capture dies with the game too
			var core: Object = main.solo_controller._core_node_ready()
			if core != null:
				core.release(int(main._solo_core_ai_h))
		main._solo_core_ai_h = 0


## Step 37 (O9, O15 (4)): the unit properties a Cancel-reachable one-time spend writes, each with the rule its line names.
## The Speed Feat latches are SoloController.speed_feat_flag(<feat name>) of the two once-per-game Quick rules; the
## Utility Buff stamp and the Precision Tag latch are table-local; `tag_markers` sits on the TAGGED enemy and travels.
const JOURNAL_KEYS := {
	"speed_feat_used_speed_feat": "Speed Feat",
	"speed_feat_used_speed_feat_aura": "Speed Feat Aura",
	"utility_buff_round": "Utility Buff",
	"precision_tag_used": "Precision Tag",
	"tag_markers": "Precision Tag",
}
const _NET := preload("res://scripts/network_manager.gd")
## Step 67 (R8): the unit_properties keys the tripwire never reports, each with why. Every other key is a gameplay key.
const TRIPWIRE_SKIP := {
	"moved_round": "the reset (step 32) restores it",
	"bounding_roll": "kept for the round, journal-exempt (step 83, O17 (b))",
	"display_suffix": "UI only: the ' (2)' disambiguator of the card and the node names",
}
## Step 67: how many unit properties a Cancel found changed by a door the journal misses (tests and gates read it).
static var tripwire_hits := 0


## Step 37: JOURNAL_KEYS of EVERY game unit on the table (a spend can write on another unit), instance_id -> {key: value};
## a key the unit does not carry stays out of its row.
static func _journal_props(main) -> Dictionary:
	var out := {}
	for u in main.opr_army_manager.get_all_game_units():
		var row := {}
		for k in JOURNAL_KEYS:
			if u.unit_properties.has(k):
				row[k] = _copy(u.unit_properties[k])
		out[u.get_instance_id()] = row
	return out


## Step 67: every unit's spell records (a deep copy of main._solo_spell_mods; a unit without records stays out) and a
## deep copy of every unit's unit_properties (the tripwire's reference). Step 67b: every regiment block's width.
static func _journal_records(main) -> Dictionary:
	var mods := {}
	var all := {}
	for u in main.opr_army_manager.get_all_game_units():
		if main._solo_spell_mods.has(u.get_instance_id()):
			mods[u.get_instance_id()] = (main._solo_spell_mods[u.get_instance_id()] as Array).duplicate(true)
		all[u.get_instance_id()] = u.unit_properties.duplicate(true)
	var widths := {}
	for id in main.opr_army_manager.regiments:
		var reg: Regiment = main.opr_army_manager.regiments[id]
		if reg != null and reg.tray is RegimentTray and is_instance_valid(reg.tray):
			widths[id] = (reg.tray as RegimentTray).frontage
	return {"mods": mods, "all": all, "widths": widths}


## Step 37 (Cancel, step 35): every JOURNAL_KEYS value that changed on ANY unit since `gu`'s Start is put back (erased
## when the unit did not carry it) - a wire-listed key through main._sync_unit_property (it reaches the other table), a
## table-local one by a direct write, as its spender wrote it - and one "<Unit>: <Rule> is unspent again." line per rule
## names the ACTING unit. The Utility Buff stamp is written on every human unit that opens a Shoot or Fight pick, rule or
## not (main._solo_apply_utility_buffs), so it names its rule only when the unit or a joined hero carries one.
## Step 67: then every unit's spell records as they were (stamps, wire and the save mirror follow; one line per removed
## record name not named yet) and its granted-rule overlay, in place. Last the tripwire: any OTHER key that differs from
## the Start (TRIPWIRE_SKIP aside) is reported (push_error, tripwire_hits) and left as it is. Nothing without a session.
static func undo_journal(main, gu: GameUnit) -> void:
	if gu == null or not _sessions.has(gu.unit_id):
		return
	var props: Dictionary = (_sessions[gu.unit_id]["journal"] as Dictionary).get("props", {})
	var rules: Array = []
	for u in main.opr_army_manager.get_all_game_units():
		if not props.has(u.get_instance_id()):
			continue
		var was: Dictionary = props[u.get_instance_id()]
		for k in JOURNAL_KEYS:
			var had := was.has(k)
			if had == u.unit_properties.has(k) and (not had or u.unit_properties[k] == was[k]):
				continue
			if _NET.SYNCABLE_UNIT_PROPERTIES.has(k):
				main._sync_unit_property(u, k, _copy(was[k]) if had else null)
			elif had:
				u.unit_properties[k] = _copy(was[k])
			else:
				u.unit_properties.erase(k)
			if not rules.has(JOURNAL_KEYS[k]) and (k != "utility_buff_round" or _carries_buff(u)):
				rules.append(JOURNAL_KEYS[k])
	var mods: Dictionary = _sessions[gu.unit_id]["journal"].get("mods", {})
	var all: Dictionary = _sessions[gu.unit_id]["journal"].get("all", {})
	var units: Array = main.opr_army_manager.get_all_game_units().filter(func(u: GameUnit) -> bool:
		return all.has(u.get_instance_id()))
	var records_changed := false
	for u: GameUnit in units:
		var now: Array = main._solo_spell_mods.get(u.get_instance_id(), [])
		var was: Array = mods.get(u.get_instance_id(), [])
		if now != was:
			for rec in now:
				if not was.has(rec) and not rules.has(str(rec["spell"])):
					rules.append(str(rec["spell"]))
			if was.is_empty():
				main._solo_spell_mods.erase(u.get_instance_id())
			else:
				main._solo_spell_mods[u.get_instance_id()] = was.duplicate(true)
			main._solo_refresh_spell_stamps(u)
			main._broadcast_spell_mods(u)
			records_changed = true
		main.core_overlay_restore(u, all[u.get_instance_id()])   # the granted-rule overlay, in place (main.gd)
	if records_changed:
		main._solo_mirror_spell_state()   # the save mirror (spell_records) follows the records
	var widths: Dictionary = _sessions[gu.unit_id]["journal"].get("widths", {})
	for id in widths:   # step 67b: a re-rank is undone as its own undo does it (layout, Regiment, key, the wire)
		var reg: Regiment = main.opr_army_manager.regiments.get(id)
		if reg != null and is_instance_valid(reg.tray) and (reg.tray as RegimentTray).frontage != int(widths[id]):
			UndoManager.FrontageAction.new(reg.tray, reg.game_unit, int(widths[id]), (reg.tray as RegimentTray).frontage,
				main.network_manager).undo()
	if rules.has("Utility Buff") and _carries_buff(gu, rules):
		rules.erase("Utility Buff")   # one line per spend: the record's line names the buff that was spent
	for u: GameUnit in units:
		var at_start: Dictionary = all[u.get_instance_id()]
		var keys := at_start.duplicate()
		keys.merge(u.unit_properties)
		for k in keys:
			var n: Variant = u.unit_properties.get(k)
			if TRIPWIRE_SKIP.has(k) or (typeof(n) == typeof(at_start.get(k)) and n == at_start.get(k)):
				continue
			push_error("cancel: %s.%s changed by an unjournaled door" % [u.get_name(), k])
			tripwire_hits += 1
	for rule in rules:
		main._log_rule_event(BattleLog.Category.GENERAL, "%s: %s is unspent again." % [gu.get_name(), rule])


## Step 37: a journaled Array or Dictionary is its own deep copy, at the Start and at every restore, so an in-place
## change of the live value never reaches the journal (every JOURNAL_KEYS value is a bool or an int on main today).
static func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if v is Array or v is Dictionary else v


## Step 37: whether `u` or a hero joined to it carries a rule of the Utility Buff family (its stamp's line); step 67:
## with `named`, only a rule of one of those names (a record the Cancel removed names the buff that was spent).
static func _carries_buff(u: GameUnit, named: Array = []) -> bool:
	for m in [u] + u.get_attached_heroes():
		for e in RulesRegistry.unit_rules_of_primitive(m, "Utility Buff") if m is GameUnit else []:
			if named.is_empty() or named.has(str(e["name"])):
				return true
	return false


## Step 49 (N6 b): the units an activation touched - the actor and its joined chain (the host it joined, its attached
## heroes), then the target's chain; a null target = the actor side only. Each unit once.
static func touched_units(main, actor: GameUnit, target: GameUnit = null) -> Array:
	var out: Array = main._solo_joined_chain(actor)
	for gu in main._solo_joined_chain(target):
		if not out.has(gu):
			out.append(gu)
	return out


## Step 49 (N6 b): the RESULT of an activation on `units`, equal on both tables when they agree. Per unit (sorted by
## unit_id): id, Activated, Shaken, and per model (sorted by model_index): wounds, alive and - for a LIVING model only -
## its X and Z in whole millimetres (positions travel as exact floats). Not in it: the height (each table probes its own
## surface), the facing (it travels apart) and a dead model's parking slot (it travels with the wound frame).
static func rows(units: Array) -> Array:
	var by_id := units.duplicate()
	by_id.sort_custom(func(a: GameUnit, b: GameUnit) -> bool: return a.unit_id < b.unit_id)
	var out: Array = []
	for gu: GameUnit in by_id:
		var models: Array = gu.models.duplicate()
		models.sort_custom(func(a: ModelInstance, b: ModelInstance) -> bool: return a.model_index < b.model_index)
		var ms: Array = []
		for m: ModelInstance in models:
			var at: Variant = null
			if m.is_alive and m.node != null and is_instance_valid(m.node):
				at = [roundi(m.node.global_position.x * 1000.0), roundi(m.node.global_position.z * 1000.0)]
			ms.append([m.model_index, m.wounds_current, m.is_alive, at])
		out.append([gu.unit_id, gu.is_activated, gu.is_shaken, ms])
	return out


## Step 49 (N6 b): one hash of `rows(units)`.
static func digest(units: Array) -> String:
	return JSON.stringify(rows(units)).sha256_text()


## Step 50 (N6 b): the target of the shot of the activation that is ending - set by `human_shoot` (step 38), read and
## cleared by main's `core_activation_ended`, cleared at every Start and by `reset_all` too, so a cancelled or abandoned
## activation never hands its target on. Null = an End without an action (the actor side only).
static var last_target: GameUnit = null
## Step 50: unit_id -> the round in which THIS table ran and announced that unit's activation (step 52 reads it).
static var _announced: Dictionary = {}


## Step 50 (N6 b): after an activation of a core unit, or of a plain AI unit this table runs (step 42), in a room: one
## `activation_check` to every other table with the touched units, their digest and their rows (the rows let the
## receiver tell a sub-millimetre rounding split from a real difference, step 51). Nothing with the flag off, outside a
## room (solo, hotseat), in a Manual room, or for any other unit.
static func announce(main, actor: GameUnit, target: GameUnit = null) -> void:
	var nm = main.network_manager
	if actor == null or not applies(main) or nm == null or not nm.is_multiplayer_active():
		return
	if not is_core_unit(main, actor) and not (main._solo_is_ai_unit(actor) and is_plain(actor)):
		return
	var round_no: int = main.opr_army_manager.current_round
	var touched := touched_units(main, actor, target)
	var ids: Array = touched.map(func(gu: GameUnit) -> String: return gu.unit_id)
	_announced[actor.unit_id] = round_no
	nm.send_command("activation_check", {"unit": actor.unit_id, "units": ids, "round": round_no, "digest": digest(touched),
		"rows": rows(touched), "retry": 0}, 0)


## Step 51: the checks that matched this table (read by the gates).
static var checks_ok := 0


## Step 51 (N6 b): another table's `activation_check`. Ignored with the flag off (a mixed room keeps playing as it is) and
## for another round. When our rows of the named units equal theirs - the hash, or else the rows with every position
## within 1 mm (two tables a hair either side of a half millimetre round apart) - it is silent (`checks_ok`). Else one
## `activation_mismatch` with OUR rows goes back to the sender alone (the winner pushes only what differs, step 52); this
## table changes nothing (O13 (b): the table that ran the activation wins). A unit unknown here is a mismatch.
static func on_check(main, payload: Dictionary, from_peer: int) -> void:
	if not applies(main):
		return
	var round_no := int(payload.get("round", -1))
	var late: bool = round_no != int(main.opr_army_manager.current_round)
	if late and round_no != _ended_round:   # step 52c: never a silent drop
		checks_dropped += 1
		push_warning("CoreActivation.on_check: the check of %s for round %d came at round %d - not compared"
			% [payload.get("unit", ""), round_no, main.opr_army_manager.current_round])
		return
	var ids: Array = payload.get("units", [])
	var units: Array = []
	for id in ids:
		var gu: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(id))
		if gu != null:
			units.append(gu)
	var mine: Array = rows(units)
	if late:   # step 52c: this table ended round `round_no` before the check came - compare that round's result
		var by_id := ids.duplicate()
		by_id.sort()
		mine = by_id.map(func(id: Variant) -> Variant: return _ended_rows.get(str(id))).filter(func(r: Variant) -> bool:
			return r != null)
	var ours := JSON.stringify(mine).sha256_text()
	if mine.size() == ids.size() and (ours == str(payload.get("digest", "")) or rows_match(mine, payload.get("rows"))):
		checks_ok += 1
		return
	if int(payload.get("retry", 0)) >= 1:   # step 52: the re-check after a push still differs - one line, no notice
		var gu0: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(payload.get("unit", "")))
		main._log_rule_event(BattleLog.Category.GENERAL, "%s: the tables still disagree - nothing more was changed."
			% (gu0.get_name() if gu0 != null else str(payload.get("unit", ""))))
		return
	for id in ids:   # step 52: the Activated corrections this notice may bring back (sender, unit, round), each once
		_fixes_due["%d|%s|%d" % [from_peer, id, int(payload["round"])]] = true
	main.network_manager.send_command("activation_mismatch", {"unit": payload.get("unit", ""), "units": ids,
		"round": payload["round"], "theirs": payload.get("digest", ""), "ours": ours, "rows": mine,
		"retry": int(payload.get("retry", 0))}, from_peer)


## Step 51: two `rows` lists are the same result when everything but the positions is equal and each living model's X and
## Z differ by at most 1 mm.
static func rows_match(ours: Array, theirs: Variant) -> bool:
	if not theirs is Array or (theirs as Array).size() != ours.size():
		return false
	for i in ours.size():
		var a: Array = ours[i]
		var b: Variant = theirs[i]
		if not b is Array or (b as Array).size() != 4 or a.slice(0, 3) != (b as Array).slice(0, 3) \
				or not b[3] is Array or (b[3] as Array).size() != (a[3] as Array).size():
			return false
		for j in (a[3] as Array).size():
			if not same_model(a[3][j], b[3][j]):
				return false
	return true


## Step 51: two model rows agree - index, wounds and alive equal, and a living model's X and Z within 1 mm.
static func same_model(a: Array, b: Variant) -> bool:
	return b is Array and (b as Array).size() == 4 and a.slice(0, 3) == (b as Array).slice(0, 3) and near(a[3], b[3])


## Step 51: two positions in whole millimetres within 1 mm per axis; both null (dead) agree too.
static func near(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return b is Array and (b as Array).size() == 2 and absi(int(a[0]) - int(b[0])) <= 1 and absi(int(a[1]) - int(b[1])) <= 1


## Step 52 (O13 (b)): whether THIS table's state wins a mismatch on `unit_id`'s activation of round `round_no` - true iff
## this table ran and announced it (only a unit's owner moves it or rolls for it; an out-of-turn activation is undone
## before any check goes out).
static func wins(_main, unit_id: String, round_no: int) -> bool:
	return int(_announced.get(unit_id, -1)) == round_no


## Step 52 (O10, O13 (b)): another table reported a mismatch on an activation THIS table ran, with its rows. Push exactly
## what differs through today's paths - a wound frame per model whose wounds or life differ, one move and one rotation
## batch of the living models more than 1 mm off, the Shaken marker when it differs, and the activation flag as a
## correction (never the activation fact, which the room's turn gate would take for a new activation) - then the
## O15 (5) line and ONE re-check (retry 1) to the reporter. A table that does not win does nothing: it waits for the push.
static func on_mismatch(main, payload: Dictionary, from_peer: int) -> void:
	var actor: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(payload.get("unit", "")))
	if not applies(main) or actor == null or int(payload.get("retry", 0)) != 0 \
			or not wins(main, actor.unit_id, int(payload.get("round", -1))):
		return
	var nm = main.network_manager
	var theirs := {}
	for r in (payload.get("rows") if payload.get("rows") is Array else []):
		if r is Array and (r as Array).size() == 4:
			theirs[str(r[0])] = r
	var units: Array = []
	var moves: Array = []
	var turns: Array = []
	for id in payload.get("units", []):
		var gu: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(id))
		if gu == null:
			continue
		units.append(gu)
		var their: Array = theirs.get(gu.unit_id, [gu.unit_id, null, null, []])
		for mr: Array in rows([gu])[0][3]:
			var m: ModelInstance = gu.get_model(int(mr[0]))
			var tr := _model_row(their[3], int(mr[0]))
			if tr.is_empty() or mr.slice(1, 3) != tr.slice(1, 3):
				nm.broadcast_model_wounds(m)
			if mr[3] != null and not near(mr[3], null if tr.is_empty() else tr[3]) and m.node.has_meta("network_id"):
				moves.append_array([int(m.node.get_meta("network_id")), m.node.global_position.x,
					m.node.global_position.y, m.node.global_position.z])
				turns.append_array([int(m.node.get_meta("network_id")), m.node.rotation.y])
		if their[2] != gu.is_shaken:
			nm.broadcast_unit_marker(gu, "ShakenMarker", gu.is_shaken)
		if their[1] != gu.is_activated:
			nm.send_command("correct_unit_activated", {"unit": gu.unit_id, "activated": gu.is_activated,
				"activation_round": gu.activation_round, "round": int(payload["round"])}, from_peer)
	if not moves.is_empty():
		nm.broadcast_move_batch(moves)
		nm.broadcast_rotation_batch(turns)
	var slot: int = int(actor.unit_properties.get("player_id", 1))
	var peer: int = main._solo_peer_for_slot(slot)
	var who: String = main._peer_display_name(peer) if peer != 0 and nm.player_names.has(peer) else main._solo_player_label(slot)
	main._log_rule_event(BattleLog.Category.GENERAL,
		"%s: the tables disagreed after its activation - the state of %s was applied." % [actor.get_name(), who])
	nm.send_command("activation_check", {"unit": actor.unit_id, "units": units.map(func(gu: GameUnit) -> String:
		return gu.unit_id), "round": int(main.opr_army_manager.current_round), "digest": digest(units),
		"rows": rows(units), "retry": 1}, from_peer)


## Step 52: the row of model `index` in a reported list of model rows, or [] when the reporter has none.
static func _model_row(models: Variant, index: int) -> Array:
	for x in (models if models is Array else []):
		if x is Array and (x as Array).size() == 4 and int(x[0]) == index:
			return x
	return []


## Step 52: the Activated corrections this table asked for, "<peer>|<unit_id>|<round>" -> true, consumed on use.
static var _fixes_due: Dictionary = {}


## Step 52 (O10): the winner's activation flag of one unit, applied as a CORRECTION - set directly, the turn token
## untouched, no activation line, nothing re-broadcast; never counted as a new activation. Only one this table asked for:
## from the peer it sent the mismatch to, for a unit of that mismatch, in its round, once.
static func on_correct_activated(main, payload: Dictionary, from_peer: int) -> void:
	var gu: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(payload.get("unit", "")))
	var key := "%d|%s|%d" % [from_peer, payload.get("unit", ""), int(payload.get("round", -1))]
	if not applies(main) or gu == null or not _fixes_due.erase(key):
		return
	gu.is_activated = bool(payload.get("activated", gu.is_activated))
	gu.activation_round = int(payload.get("activation_round", gu.activation_round))
	main.radial_menu_controller._update_activated_markers(gu)


## Step 52c: every unit's rows as round `_ended_round` ended - taken by `OPRArmyManager.advance_round` before it refreshes
## the units - so the check of a round's LAST activation, whose activation fact ends the round on the receiving table
## before the check is handled, is still compared against that round's result. Only where checks run (flag on, a room
## where the engine resolves, a live session): solo and hotseat pay nothing.
static var _ended_round := -1
static var _ended_rows: Dictionary = {}
## Step 52c: the checks this table could not compare (another round than the current or the one that just ended).
static var checks_dropped := 0


static func note_round_end(army) -> void:
	var main: Node = army.get_node_or_null("/root/Main") if enabled() and army is Node else null
	if main == null or not applies(main) or main.network_manager == null or not main.network_manager.is_multiplayer_active():
		return
	_ended_round = int(army.current_round)
	_ended_rows.clear()
	for gu in army.game_units.values():
		_ended_rows[(gu as GameUnit).unit_id] = rows([gu])[0]

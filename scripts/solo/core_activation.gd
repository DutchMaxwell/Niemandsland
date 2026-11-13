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
		if not bool(core.set_game_header(AiActRecorder._header_line(state, sc.terrain_type_at))):
			return 0
		sc._core_header_done = true
		sc._core_statics_builds = int(core.statics_builds())   # the header's build is #1, as in _core_plan
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
	var t: Array = [{"t": "begin"}, {"t": "placed", "positions": at}, {"t": "intent", "kind": kind, "shoot": target.unit_id}]
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


## The start model of `gu` whose captured position equals `at` exactly; null when none does.
static func _model_at(start_models: Array, gu: GameUnit, at: Vector3) -> ModelInstance:
	for e in start_models:
		var m: ModelInstance = e["model"]
		if m.unit == gu and e["at"] == at:
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
	for m in gu.get_alive_models():
		if m.node != null and is_instance_valid(m.node):
			var p: Vector3 = m.node.global_position
			var was: Variant = starts.get(int(m.node.get_meta("network_id", 0)))
			start_pos.append(Vector3((was as Vector2).x, p.y, (was as Vector2).y) if was is Vector2 else p)
			start_rot.append(m.node.rotation.y)
	var s := {"handle": h, "transcript": [{"t": "begin"}], "start_models": _start_models(main), "start_pos": start_pos,
		"start_rot": start_rot, "dice": false, "journal": {"props": _journal_props(main)}}
	if gu.unit_properties.has("moved_round"):
		s["moved_round_before"] = gu.unit_properties["moved_round"]
	_sessions[gu.unit_id] = s
	last_target = null   # step 50: a new activation never inherits the target of a cancelled one
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


## Closes every open session, and the next capture sends the game header again (a loaded game's units are not the
## header's). The store is static, so the game's lifecycle calls this: main's `_exit_tree` (quit to menu, which a new game
## follows) and its save load.
static func reset_all(main) -> void:
	for id in _sessions.keys():
		close_session(main, id)
	_announced.clear()
	last_target = null
	if main != null and is_instance_valid(main.solo_controller):
		main.solo_controller._core_header_done = false


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


## Step 37 (Cancel, step 35): every JOURNAL_KEYS value that changed on ANY unit since `gu`'s Start is put back (erased
## when the unit did not carry it) - a wire-listed key through main._sync_unit_property (it reaches the other table), a
## table-local one by a direct write, as its spender wrote it - and one "<Unit>: <Rule> is unspent again." line per rule
## names the ACTING unit. The Utility Buff stamp is written on every human unit that opens a Shoot or Fight pick, rule or
## not (main._solo_apply_utility_buffs), so it names its rule only when the unit or a joined hero carries one.
## Nothing without a session.
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
	for rule in rules:
		main._log_rule_event(BattleLog.Category.GENERAL, "%s: %s is unspent again." % [gu.get_name(), rule])


## Step 37: a journaled Array or Dictionary is its own deep copy, at the Start and at every restore, so an in-place
## change of the live value never reaches the journal (every JOURNAL_KEYS value is a bool or an int on main today).
static func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if v is Array or v is Dictionary else v


## Step 37: whether `u` or a hero joined to it carries a rule of the Utility Buff family (its stamp's line).
static func _carries_buff(u: GameUnit) -> bool:
	for m in [u] + u.get_attached_heroes():
		if m is GameUnit and not RulesRegistry.unit_rules_of_primitive(m, "Utility Buff").is_empty():
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
	if not applies(main) or int(payload.get("round", -1)) != int(main.opr_army_manager.current_round):
		return
	var ids: Array = payload.get("units", [])
	var units: Array = []
	for id in ids:
		var gu: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(id))
		if gu != null:
			units.append(gu)
	var ours := digest(units)
	if units.size() == ids.size() and (ours == str(payload.get("digest", "")) or rows_match(rows(units), payload.get("rows"))):
		checks_ok += 1
		return
	if int(payload.get("retry", 0)) >= 1:   # step 52: the re-check after a push still differs - one line, no notice
		var gu0: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(payload.get("unit", "")))
		main._log_rule_event(BattleLog.Category.GENERAL, "%s: the tables still disagree - nothing more was changed."
			% (gu0.get_name() if gu0 != null else str(payload.get("unit", ""))))
		return
	main.network_manager.send_command("activation_mismatch", {"unit": payload.get("unit", ""), "units": ids,
		"round": payload["round"], "theirs": payload.get("digest", ""), "ours": ours, "rows": rows(units),
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
				"activation_round": gu.activation_round}, from_peer)
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


## Step 52 (O10): the winner's activation flag of one unit, applied as a CORRECTION - set directly, the turn token
## untouched, no activation line, nothing re-broadcast; never counted as a new activation.
static func on_correct_activated(main, payload: Dictionary) -> void:
	var gu: GameUnit = main.opr_army_manager.get_game_unit_by_id(str(payload.get("unit", "")))
	if not applies(main) or gu == null:
		return
	gu.is_activated = bool(payload.get("activated", gu.is_activated))
	gu.activation_round = int(payload.get("activation_round", gu.activation_round))
	main.radial_menu_controller._update_activated_markers(gu)

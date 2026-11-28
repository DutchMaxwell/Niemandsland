class_name CoreActivation
extends RefCounted
## One-core P3 step 19: the table's skeleton for core-resolved activations. Every door asks one of the three
## predicates first. Since the 0.3.16 release the flag is ON by default; NML_ONE_CORE_ACTIVATION=0 (or "off") is the
## kill switch that restores the old table path.

static var _env := -1


## The flag, read once (the BattleSim.spacing_enabled pattern): ON unless the kill switch says "0" or "off".
static func enabled() -> bool:
	if _env < 0:
		var raw := OS.get_environment("NML_ONE_CORE_ACTIVATION").to_lower()
		_env = 0 if (raw == "0" or raw == "off") else 1
	return _env == 1


## M-3 (maintainer 16.11.): the rules core (NmlCore) is MANDATORY for engine play. Solo (an AI seat) and Automatic are
## OFFERED only while it is loaded; a build without it plays Manual. Every door that offers either asks this (`applies`
## below asks the class table itself). Test seam: -1 asks ClassDB, 0 / 1 stands in for an absent / loaded core.
static var offer_override := -1


static func engine_offered() -> bool:
	if offer_override >= 0:
		return offer_override == 1
	return ClassDB.class_exists("NmlCore")


## P4.D-43c: the hotseat switch, read once (the master flag's pattern). ON by default; `NML_ONE_CORE_HOTSEAT=0` (or
## "off") is the way back: a local Automatic table with no AI seat then resolves its two human sides through the core
## like a solo or an agreed online room. Manual rooms never enter the core door.
static var _hotseat_env := -1


static func hotseat_enabled() -> bool:
	if _hotseat_env < 0:
		var raw := OS.get_environment("NML_ONE_CORE_HOTSEAT").to_lower()
		_hotseat_env = 0 if (raw == "0" or raw == "off") else 1
	return _hotseat_env == 1


## P4.D-43c: a local hotseat Automatic table (two human sides, no AI seat, no peer).
static func hotseat_room(main) -> bool:
	return hotseat_enabled() and main._solo_hotseat_automatic()


## The engine resolves at this table: an AI seat, an agreed Automatic online room, or (P4.D-43c, behind its switch) a
## local hotseat Automatic table. Manual rooms: false.
static func applies(main) -> bool:
	return enabled() and ClassDB.class_exists("NmlCore") \
		and (not main.solo_ai_slots.is_empty() or main._online_turn_room() or hotseat_room(main))


## P4.0-6: the per-choice switch. A choice id's prefix (`takedown_model:<shooter>:<target>`) names its
## switch: ON only for `NML_ONE_CORE_CHOICE_<PREFIX>` = "1"/"on", so the core's automatic pick resolves exactly as before
## unless it is turned on. P4.D-27: the kinds in CHOICE_DEFAULT_ON start ON instead - `NML_ONE_CORE_CHOICE_WOUND_ALLOC=0`
## (or "off") is the way back until the switch and the #172 guard are deleted. Tests set the entry per kind. CC-14a: `interference`
## (a foe's token spend against an AI cast, `interference:<seq>:<caster>:<slot>`) starts OFF like the Takedown pick.
const CHOICE_KINDS := ["takedown_model", "wound_alloc", "interference", "strike_back"]
const CHOICE_DEFAULT_ON := ["wound_alloc", "strike_back", "versatile_mode", "spot_markers", "blast_split", "push", "push_to"]
static var _choice_on: Dictionary = {}


static func choice_enabled(id: String) -> bool:
	var kind := id.get_slice(":", 0)
	if not _choice_on.has(kind):
		var raw := OS.get_environment("NML_ONE_CORE_CHOICE_%s" % kind.to_upper()).to_lower()
		_choice_on[kind] = (raw != "0" and raw != "off") if CHOICE_DEFAULT_ON.has(kind) else (raw == "1" or raw == "on")
	return bool(_choice_on[kind])


static func any_choice_enabled() -> bool:
	for kind in CHOICE_KINDS:
		if choice_enabled(str(kind)):
			return true
	return false


## The volley the core resolves exactly as the table does: `CoreSlice` takes the unit (today: no unit rule, no attachment,
## no weapon rule, an OPR profile - the slice's groups widen it).
static func is_plain(gu: GameUnit) -> bool:
	return CoreSlice.takes(gu)


## P4.D-13b: the TARGET half of `is_plain`. The core takes a target's profile from unit_properties
## (`BattleSim._unit_profile`), so a target needs no OPR profile: a loaded save from before the profile was saved is shot
## like any other unit. What it needs is a statline the core can hand a save to.
static func is_plain_target(gu: GameUnit) -> bool:
	return has_statline(gu) and CoreSlice.takes(gu, true)


## C-19: `is_plain` / `is_plain_target` for the HUMAN door (a human unit's lifecycle, move path and shot): the slice the human
## door reads (`CoreSlice.human_path`, H-30: the live deny slice, the AI door's own). The AI door asks the two above.
static func is_plain_human(gu: GameUnit) -> bool:
	return CoreSlice.takes_human(gu)


static func is_plain_target_human(gu: GameUnit) -> bool:
	return has_statline(gu) and CoreSlice.takes_human(gu, true)


## Quality and defense both in 2..6 (the rules' range). A hand-written foreign save may carry none: get_quality() and
## get_defense() then answer 0, and there is nothing to hand the core.
static func has_statline(gu: GameUnit) -> bool:
	return gu.get_quality() in range(2, 7) and gu.get_defense() in range(2, 7)


## P4.D-13c: a unit with no statline cannot be shot at a core table. True = the shot must not happen; ONE battle-log line
## says why. False when the core door is not on (kill switch, hotseat with its switch off): the table shoots as it always did.
static func refuses_statlineless(main, attacker: GameUnit, target: GameUnit) -> bool:
	if not applies(main) or has_statline(target):
		return false
	main._log_rule_event(BattleLog.Category.COMBAT, "%s cannot shoot %s: it has no Quality or Defense (a hand-written save), so it is not a valid target" % [
		attacker.get_name(), target.get_name()], main._solo_is_ai_unit(attacker))
	return true


## (1) A human unit of this table's player while the game is PLAYING: it gets the explicit activation (O14 (1b)).
static func is_lifecycle_unit(main, gu: GameUnit) -> bool:
	return gu != null and applies(main) and not main._solo_is_ai_unit(gu) and main._solo_i_own_unit(gu) \
		and main.opr_army_manager.game_phase == OPRArmyManager.GamePhase.PLAYING


## (2) A lifecycle unit whose shot, End and digest resolve in the core. PLAN_FIRST_DELETION step 21: a Hit & Run bearer is taken - its
## intent says `no_step` (step 20), so the core takes no step and keeps the round's use open for the player's drag (fab_a6_test).
## A Crossing Attack carrier is one too: the core rolls the mandatory attack from the trails the session holds (the table never
## rolled it for a player's unit).
static func is_core_unit(main, gu: GameUnit) -> bool:
	return is_lifecycle_unit(main, gu) and is_plain_human(gu)


## (3) Equal to (2) for now; step 82 widens it by movement rule.
static func on_move_path(main, gu: GameUnit) -> bool:
	return is_core_unit(main, gu)


## A core handle for the board as it stands (BattleSim.capture, plain form, gate reads); 0 on failure. `ai`: the AI activation's board, whose table once-records
## the landing compares against later (`land_late_once_records`). The first
## capture of a game sends the game header, exactly as the AI's `_core_plan` does (one header per game, shared with it),
## so every step runs at the game's rules epoch, not at epoch 0.
static func capture(main, ai := false, at_start: GameUnit = null) -> int:
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
	if at_start != null:
		_put_on_start_spots(main, plain, at_start)
	AiActRecorder._stamp_gate_reads(state, plain)
	_stamp_spent_ignore_feats(state, plain)
	_stamp_step_ledger(state, plain, sc)
	var h := int(core.capture_plain(plain))
	if ai:   # the AI activation's own board (main's activation start): the shadow's capture of the same moment must not replace it
		_once_seen = {"h": h, "mods": _once_sigs(main)}   # what the core's board holds of the table's once-records (`land_late_once_records`)
	return h


## C-10: the table's round stamps and latches `_ledger_of` does not carry, the table property each is read from (the State name where
## it differs). `_ledger_of` is a recorded corpus format and the AI search's input, so it stays byte-identical; the door's capture sends
## these under each unit's `step_ledger` and Second Wind's army cap of the round under `second_wind`, for THIS capture only.
const STEP_STAMPS := {"reckless_rolled_round": "reckless_rolled_round", "reckless_ap_round": "reckless_ap_round",
	"reckless_backfire_round": "reckless_backfire_round", "retreating_strike_round": "retreating_strike_round",
	"mind_control_moved_round": "mind_control_moved_round", "growth_strike_round": "regenerative_strength_round",
	"piercing_spot_round": "piercing_spot_round"}


## The step ledger of one unit: the stamps above (absent = never stamped), the latched Versatile pick as the round and the int mode the
## core keeps (1 = +1 to hit, 2 = AP(+1)). {} for a unit with none.
static func step_ledger_of(gu: GameUnit) -> Dictionary:
	var out := {}
	for key in STEP_STAMPS:
		if int(gu.unit_properties.get(STEP_STAMPS[key], -1)) != -1:
			out[key] = int(gu.unit_properties[STEP_STAMPS[key]])
	var pick: Dictionary = gu.unit_properties.get("versatile_pick", {})
	if int(gu.unit_properties.get("versatile_pick_round", -1)) != -1 and (int(pick.get("ap", 0)) > 0 or int(pick.get("hit_mod", 0)) > 0):
		out["versatile_pick_round"] = int(gu.unit_properties["versatile_pick_round"])
		out["versatile_pick_mode"] = 2 if int(pick.get("ap", 0)) > 0 else 1
	return out


static func _stamp_step_ledger(state: Dictionary, plain: Dictionary, sc: SoloController) -> void:
	for key in state["units"]:
		var sl := step_ledger_of((state["units"][key] as Dictionary)["unit"])
		if not sl.is_empty() and plain["units"].has(str(key)):
			plain["units"][str(key)]["step_ledger"] = sl
	var round_no := sc._second_wind_round_no()
	plain["second_wind"] = {"round": round_no, "uses": int(sc._second_wind_round_uses.get(str(round_no), 0))}


## P4.D-38a: the once-per-game ignore feat (the Protection Feat family) a table roll spent closes the core's latch: its name
## joins the unit's `feats_used` in THIS capture (the recorder's ledger, a recorded corpus format, is not touched).
static func _stamp_spent_ignore_feats(state: Dictionary, plain: Dictionary) -> void:
	for key in state["units"]:
		var u: GameUnit = (state["units"][key] as Dictionary)["unit"]
		var spent: Array = ignore_feats_of(u).filter(func(n: String) -> bool: return bool(u.unit_properties.get(_ignore_flag(n), false)))
		if not spent.is_empty():
			var ledger: Dictionary = plain["units"][str(key)]["ledger"]
			ledger["feats_used"] = (ledger.get("feats_used", []) as Array) + spent


## The once-per-game ignore rules `gu` carries (Regeneration-primitive entries with `uses_per_game`) and the flag that closes one
## (main.gd `_solo_ignore_feat_flag`).
static func ignore_feats_of(gu: GameUnit) -> Array:
	var out: Array = []
	for e in RulesRegistry.unit_rules_of_primitive(gu, "Regeneration"):
		if int(((e as Dictionary).get("params", {}) as Dictionary).get("uses_per_game", 0)) > 0:
			out.append(str((e as Dictionary)["name"]))
	return out


## P4.D-38a follow-up: the once-per-game SHOT feats `gu` carries, the two families main.gd `_solo_spend_shot_feats` spends (a Shot
## Modifier or Piercing Assault entry with `uses_per_game`), and the flag that closes one (`SoloController.shot_feat_flag`).
static func shot_feats_of(gu: GameUnit) -> Array:
	var out: Array = []
	for primitive in ["Shot Modifier", "Piercing Assault"]:
		for e in RulesRegistry.unit_rules_of_primitive(gu, primitive):
			if int(((e as Dictionary).get("params", {}) as Dictionary).get("uses_per_game", 0)) > 0:
				out.append(str((e as Dictionary)["name"]))
	return out


## The once-per-game Takedown bonus attacks `gu` carries (Takedown-primitive entries with `uses_per_game`), by their raw names.
static func takedown_feats_of(gu: GameUnit) -> Array:
	var out: Array = []
	for e in RulesRegistry.unit_rules_of_primitive(gu, "Takedown"):
		if int(((e as Dictionary).get("params", {}) as Dictionary).get("uses_per_game", 0)) > 0:
			out.append(str((e as Dictionary)["name"]))
	return out


static func _ignore_flag(rule_name: String) -> String:
	return "ignore_feat_used_%s" % rule_name.to_snake_case()


## Calls per activation before the driver gives up (a plain volley asks three to four times).
const MAX_STEPS := 64

## The movement selector's values and the metre-inch factor, mirrored from ObjectManager (MovementCap, METERS_TO_INCHES)
## on purpose: naming the ObjectManager class here made every `-s` tool that reaches this file (arena_match,
## core_dormant_check) compile object_manager.gd and its scene-side chain before the autoloads exist, which died with
## "Identifier not found: GraphicsSettings". test/one_core/core_activation_object_manager_parity_test.gd pins the match.
const CAP_ADVANCE := 1
const CAP_RUSH := 2
const CAP_CHARGE := 3
const METERS_TO_INCHES := 39.3701


## P4.0-6: the choices the step API may open for this activation, as their stable ids ([] = none). Only a choice whose
## switch is ON is built. The Takedown pick only when the table can see what the core's `takedown_choice` sees (a Takedown
## shooting profile on the actor, 2+ living models on the shot's target): that probe can never ask for a choice the core
## would not open. P4.D-23: the wound allocation of the volley's one group (`wound_alloc:<shooter>:<target>:0`; split
## groups join it with their own index) is probed unseen - the core opens it only where a group's landing has a real
## choice, and a probe nothing reached asks nothing. An empty answer means "no probe", i.e. the automatic pick.
static func pending_choices(main, unit: GameUnit, transcript: Array) -> Array:
	var ids: Array = interference_probes(transcript)
	if not any_choice_enabled():
		return ids
	for i in range(transcript.size() - 1, -1, -1):
		var e: Dictionary = transcript[i]
		if str(e.get("t", "")) == "choice":
			return ids   # already asked in this transcript: never a second probe
		if str(e.get("t", "")) != "intent":
			continue
		# Plan E-25: a charge at a human-owned defender probes its strike-back (`strike_back:<charger>:<defender>`): the core asks
		# where the table's `_solo_confirm_strike_back` would, the owner's answer follows; an AI defender always strikes back.
		var charged = main.opr_army_manager.game_units.get(str(e.get("charge", "")))
		if charged is GameUnit:
			if choice_enabled("strike_back") and not main._solo_is_ai_unit(charged):
				ids.append("strike_back:%s:%s" % [unit.unit_id, (charged as GameUnit).unit_id])
			return ids + _push_probes(main, unit)
		var target = main.opr_army_manager.game_units.get(str(e.get("shoot", "")))
		if not target is GameUnit:
			return ids
		if choice_enabled("takedown_model") and (target as GameUnit).get_alive_models().size() >= 2 and _takedown_weapon(unit):
			ids.append("takedown_model:%s:%s" % [unit.unit_id, (target as GameUnit).unit_id])
		if choice_enabled("wound_alloc"):
			ids.append("wound_alloc:%s:%s:0" % [unit.unit_id, (target as GameUnit).unit_id])
		# Step 29c (D-29-R1): a human-owned skirmish target's owner places the even Blast split's remainder; the core asks
		# only where a remainder has a choice, so the probe is unseen like the wound allocation's.
		if choice_enabled("blast_split") and CoherencyChecker.is_skirmish_system(target) and not main._solo_is_ai_unit(target):
			ids.append("blast_split:%s:%s" % [unit.unit_id, (target as GameUnit).unit_id])
		# Step 22b (OD-2: a player's pick is asked through the core): a human Versatile Attack shooter picks the mode (22a).
		if choice_enabled("versatile_mode") and not main._solo_is_ai_unit(unit) \
				and not RulesRegistry.unit_rules_of_primitive(unit, "Versatile Attack").is_empty():
			ids.append("versatile_mode:%s" % unit.unit_id)
		# A human attacker picks how many Precision Spotter markers to remove from the target (the core asks where the volley
		# spends them; no answer takes them all, as the AI does).
		if choice_enabled("spot_markers") and not main._solo_is_ai_unit(unit) \
				and int((target as GameUnit).unit_properties.get("spot_markers", 0)) > 0:
			ids.append("spot_markers:%s:%s" % [unit.unit_id, (target as GameUnit).unit_id])
		return ids + _push_probes(main, unit)
	return ids


## CC-14a: the interference choices the transcript's OPEN casts may ask, probed unseen like the wound allocation: one
## `interference:<seq>:<caster>:<slot>` per pool slot that holds a token. An open cast whose pools hold none still needs ONE entry
## (the core's static check wants a choice for every open cast; nothing reaches it, the core says "no caster ... no interference"),
## so its first pool's id covers it. [] with the switch OFF (the core then refuses an open cast and the table keeps it). Pure.
static func interference_probes(transcript: Array) -> Array:
	var ids: Array = []
	if not choice_enabled("interference"):
		return ids
	for e in transcript:
		var c: Dictionary = e
		if str(c.get("t", "")) != "cast" or not bool(c.get("open", false)):
			continue
		var pools: Array = c.get("pools", [])
		var stem := "interference:%d:%s:" % [int(c["seq"]), str(c["caster"])]
		var from := ids.size()
		for p in pools:
			if ((p as Array)[1] as Array).any(func(pay: Variant) -> bool: return int((pay as Array)[1]) > 0):
				ids.append(stem + str(int((p as Array)[0])))
		if ids.size() == from:
			ids.append(stem + str(int((pools[0] as Array)[0]) if not pools.is_empty() else 0))
	return ids


## Whether `unit` carries a Takedown shooting profile — the core's `ShootProfile.takedown` is stamped from
## the same weapon entries (`weapon_has(w, "Takedown")`).
static func _takedown_weapon(unit: GameUnit) -> bool:
	var src := unit.source_data as OPRApiClient.OPRUnit
	for w in src.weapons if src != null else []:
		for r in (w as OPRApiClient.OPRWeapon).special_rules:
			if GameUnit.rule_name_matches(str(r), "Takedown"):
				return true
	return false


## Step 29e-1 (D-29-R2): a human skirmish attacker may push any enemy unit its attack shakes - probed unseen per enemy unit
## (the core asks only where a push holds): `push:<attacker>:<unit>` and its spot `push_to:<attacker>:<unit>`.
static func _push_probes(main, unit: GameUnit) -> Array:
	var ids: Array = []
	if main._solo_is_ai_unit(unit) or not CoherencyChecker.is_skirmish_system(unit) or not choice_enabled("push"):
		return ids
	var side := int(unit.unit_properties.get("player_id", 0))
	for u in main.opr_army_manager.game_units.values():
		var gu := u as GameUnit
		if gu.get_alive_count() > 0 and int(gu.unit_properties.get("player_id", 0)) != side:
			ids.append_array(["push:%s:%s" % [unit.unit_id, gu.unit_id], "push_to:%s:%s" % [unit.unit_id, gu.unit_id]])
	return ids


## Step 29e-1 (D-29 Q2): the attacker's push spot - every living model of `target` wears a ring 2 in past its base; the
## attacker drags one, and the drop is the answer `<slot>:<x>,<y>,<z>` (the model goes back to its spot: the core moves it
## when it takes the push). Esc skips ("skip"). The drag is the table's own; nothing takes the mouse.
static var push_pick: Dictionary = {}


static func pick_push_spot(main, target: GameUnit) -> String:
	if target == null:
		return "skip"
	push_pick = {"target": target, "out": [], "rings": []}
	for m in target.get_alive_models():
		var ring: MeshInstance3D = main._solo_spawn_picked_ring((m as ModelInstance).node.global_position)
		var r := SoloController.model_base_radius_m(m) + 2.0 * 0.0254
		(ring.mesh as TorusMesh).inner_radius = r - 0.003
		(ring.mesh as TorusMesh).outer_radius = r + 0.003
		(push_pick["rings"] as Array).append(ring)
	main._log_rule_event(BattleLog.Category.MOVEMENT, "Push: drag one of %s's models up to 2 in - Esc skips" % target.get_name())
	var out: Array = push_pick["out"]
	while out.is_empty() and is_instance_valid(main) and main.is_inside_tree() and not push_pick.is_empty():
		await main.get_tree().process_frame
	for ring in push_pick.get("rings", []):
		if is_instance_valid(ring):
			(ring as Node).queue_free()
	push_pick = {}
	return str(out[0]) if not out.is_empty() else "skip"


## A table drop while the push spot is asked: a model of the target is the answer (true, the drop is taken and the model
## restored); anything else is an ordinary drop (false).
static func take_push_drop(main, mv: Dictionary) -> bool:
	if push_pick.is_empty():
		return false
	var node := mv.get("node") as Node3D
	var gu := UnitUtils.get_game_unit(node)
	if gu == null or gu != push_pick["target"]:
		return false
	var m: ModelInstance = gu.get_model_for_node(node)
	var slot := gu.get_alive_models().find(m)
	if slot < 0:
		return false
	var p := node.global_position
	main.solo_controller._apply_model_positions([m], [mv.get("from_raw", p)])
	(push_pick["out"] as Array).append("%d:%f,%f,%f" % [slot, p.x, p.y, p.z])
	return true


## Esc while the push spot is asked: no push (true = the key is taken).
static func skip_push_pick() -> bool:
	if push_pick.is_empty():
		return false
	(push_pick["out"] as Array).append("skip")
	return true


## Step 22b: what the owner's Versatile prompt shows - the weapon and the mode the AI's own EV would pick (the recommended button), as the
## table's `_solo_prompt_versatile` did; {} for any other choice.
static func _versatile_context(main, unit: GameUnit, transcript: Array, id: String) -> Dictionary:
	if not id.begins_with("versatile_mode:"):
		return {}
	var src := unit.source_data as OPRApiClient.OPRUnit
	var w: OPRApiClient.OPRWeapon = src.weapons[0] if src != null and not src.weapons.is_empty() else null
	var target = main.opr_army_manager.game_units.get(str((transcript.filter(func(e: Dictionary) -> bool: return str(e.get("t", "")) == "intent").back() as Dictionary).get("shoot", "")))
	var defense := int((target as GameUnit).get_defense()) if target is GameUnit else 4
	return {"weapon": w.name if w != null else "Weapon",
		"recommended": AiEv.versatile_best_mode(unit.get_quality(), defense, 0, false)}


## The sentence the fallback line and the owner's request use for a choice id.
static func choice_purpose(id: String, transcript: Array = []) -> String:
	match id.get_slice(":", 0):
		"takedown_model":
			return "Takedown model pick"
		"wound_alloc":
			return "wound allocation"
		"strike_back":
			return "strike-back choice"
		"versatile_mode":
			return "Versatile Attack mode"
		"spot_markers":
			return "Precision Spotter markers"
		"blast_split":
			return "Blast split"
		"push":
			return "push"
		"push_to":
			return "push spot"
		"interference":
			return _cast_spell_of(transcript, id.get_slice(":", 2)) if not transcript.is_empty() else "interference"   # the table's request names the spell
	return "choice"


## The saves a defense batch failed: a 6 always saves, a 1 never, anything else needs `target`+ (the core's rule). Only the
## wound prompt's count - the core's own pool is what lands, and a wrong count never changes it.
static func failed_saves(faces: Array, target: int) -> int:
	return faces.filter(func(f: Variant) -> bool: return int(f) < 6 and (int(f) == 1 or int(f) < target)).size()


## Whether an owner's answer fits the choice the core opened: one of its options, or - the wound allocation - a list of
## them (`slot:1,slot:1,slot:0`, a slot may repeat). The one test both the owner's reply and the driver go through.
static func answer_fits(id: String, options: Array, option: String) -> bool:
	if option.is_empty():
		return false
	if id.get_slice(":", 0) in ["push_to", "push_replace"]:
		return true   # a free answer (a spot); the core referees it and refuses with the reason
	if id.get_slice(":", 0) != "wound_alloc":
		return options.has(option)
	for slot in option.split(","):
		if not options.has(slot):
			return false
	return true


## One activation through the core: ask, print the lines not printed yet, land, throw on the owner's tray, ask again.
## `transcript` gains one faces entry per throw; `on_throw(kind, index)` runs before each throw (a test seam).
## `beat(event, answer, faces)` (step 42b, the table's presentation) is awaited before each throw ("throw"), after it
## ("thrown", with its faces) and at the last answer (its step name).
## Returns the core's last answer plus "steps" (calls), "core_us" (their total time) and "max_us" (the slowest).
## A `done` answer's state handle is released once the table landed it (R4); `keep_handle` hands it to the caller instead,
## who releases it.
## P4.0-6: a choice whose switch is ON is probed once; a `need_choice` answer asks its OWNER (local, or over the
## owner-request path), and only an answer the core offered is appended; no answer leaves the core's automatic pick.
## CC-12: `cx` (`cast_context`) is the activation's planned casts: the core's cast legs are thrown on the tray under the
## table's own kind, leg and purpose (`CAST_KINDS`), the cast presentation follows the core's lines and dice, a hit buff /
## debuff lands on the table as the cast resolves, and the cast leg's `pre` block is written when the casts are over. Empty = no casts.
static func drive(main, h: int, unit: GameUnit, transcript: Array, ai: bool,
		on_throw: Callable = Callable(), keep_handle := false, beat: Callable = Callable(), cx := {}) -> Dictionary:
	var core: Object = (main.solo_controller as SoloController)._core_node_ready()
	var enforce: bool = main.object_manager._strict_movement_enforced()
	var printed := 0
	var start_models := _start_models(main)
	var landed := {}
	if not cx.is_empty():
		landed["cx"] = cx   # `_land_spell_buffs` reads the planned casts from here
	var core_us := 0
	var max_us := 0
	var r: Dictionary = {}
	var probes := pending_choices(main, unit, transcript)
	var unsaved := {}   # P4.D-24: the saves each defender failed (by key) in this call's throws - the wound prompt's count
	for step in MAX_STEPS:
		var inputs := transcript
		if not probes.is_empty():
			inputs = transcript.duplicate()
			for id in probes:
				inputs.append({"t": "choice", "id": id, "option": ""})
		var t0 := Time.get_ticks_usec()
		r = core.step_activation(h, unit.unit_id, inputs, enforce)
		var us := Time.get_ticks_usec() - t0
		core_us += us
		max_us = maxi(max_us, us)
		var lines: Array = r.get("lines", [])
		for i in range(printed, lines.size()):
			var line: Dictionary = lines[i]
			if not cx.is_empty():
				await _cast_line(main, unit, cx, line)
			# P4.D-48: a melee line carries "{cite}" where the table cites its rules book (the core holds no book version).
			main._log_rule_event(int(line["category"]), str(line["text"]).replace("{cite}",
				OPRApiClient.rules_cite(RulesRegistry.system_of_unit(unit))), ai, str(line["detail"]))
			_note_start_twice(main, unit, str(line["text"]))
		printed = maxi(printed, lines.size())
		await land_step(main, unit, r.get("landings", []), start_models, landed)
		if not cx.is_empty() and bool(cx["pre_due"]):
			_cast_leg_end(main, cx)
		# Step 29e-1: a push spot the core refuses is said once and asked again (the dice are in the transcript, nothing rerolls).
		if str(r["step"]) == "refused" and int(r["index"]) < transcript.size():
			var bad: Dictionary = transcript[int(r["index"])]
			if str(bad.get("t", "")) == "choice" and str(bad.get("id", "")).get_slice(":", 0) in ["push_to", "push_replace"]:
				main._log_rule_event(BattleLog.Category.MOVEMENT, str(r["reason"]), ai)
				main._show_toast(str(r["reason"]))
				transcript.remove_at(int(r["index"]))
				probes.append(str(bad["id"]))
				continue
		if str(r["step"]) == "need_choice":
			var options: Array = r.get("options", [])
			# The choice's owner is a roster KEY (the Takedown shooter, the wounded target): never the shooter by default.
			var owner := _roller_of(main, unit, transcript, str(r["owner"]), str(r["owner"]))
			var wounds := int(unsaved.get(str(r["owner"]), 0)) + int(unsaved.get("", 0))
			var id := str(r["id"])
			var interference := id.begins_with("interference:")
			if interference and not cx.is_empty():
				await _cast_throw(main, cx)   # CC-14a: the table shows the cast (markers, seal, "Cast" card) BEFORE the foe is asked
			var option: String = await main._owner_choice(owner, id, options, choice_purpose(id, transcript), wounds,
				_interference_context(main, cx) if interference else _versatile_context(main, unit, transcript, id))
			probes.erase(id)   # asked once: the answer follows, or the core's automatic pick stands
			if answer_fits(id, options, option):
				transcript.append({"t": "choice", "id": id, "option": option})
				if interference:
					_land_interference(main, cx, transcript, id, int(option))
			elif interference:
				transcript.append({"t": "choice", "id": id, "option": "0"})   # O3: no answer is no interference; the core's static check wants the entry
			continue
		if str(r["step"]) == "done":
			if not ai and _sessions.has(unit.unit_id) and landed.get("moved_self") != null \
					and lines.any(func(l: Dictionary) -> bool: return str(l.get("rule", "")) == "fall") \
					and fall_replace_needed(main, unit, landed["moved_self"]):
				_sessions[unit.unit_id]["fall_replace"] = landed["moved_self"]
				_sessions[unit.unit_id]["fall_ring"] = _fall_ring(main, landed["moved_self"])
				_refresh_card(main)   # the card shows "Place for me"
			elif ai and landed.get("moved_self") != null \
					and lines.any(func(l: Dictionary) -> bool: return str(l.get("rule", "")) == "fall"):
				regroup(main, unit, landed["moved_self"])   # 27c-3 (D-27c Q3): an AI unit always takes the core placer
			if not cx.is_empty():
				await _cast_finish(main, cx)
			await land_delta(main, _tokens_the_core_changed(core, h, r.get("delta", [])), start_models, landed,
				new_breaks(core, h, r.get("illegal", [])))
			if not keep_handle:
				core.release(int(r.get("handle", 0)))
				r.erase("handle")
		if str(r["step"]) != "need_roll":
			if not cx.is_empty():
				await _cast_finish(main, cx)
				_cast_leg_end(main, cx)
			if beat.is_valid():
				await beat.call(str(r["step"]), r, [])
			r.merge({"steps": step + 1, "core_us": core_us, "max_us": max_us}, true)
			return r
		var owner := str(r["owner"])
		var kind := str(r["kind"])
		var roller := _roller_of(main, unit, transcript, owner, str(r.get("owner_key", "")))
		var label: String = "AI (%s)" % _shown_owner(roller, owner) if main._solo_is_ai_unit(roller) else main._roller_label(roller)
		# CC-12b/12c: a cast leg is the tray's own kind with the table's leg and purpose; any other roll after the cast leg
		# (Dangerous came before it) closes the casts first - their effects have landed and the `pre` block is written.
		var mapped: Array = CAST_KINDS.get(kind, [])
		var tray_kind := kind if mapped.is_empty() else str(mapped[0])
		var purpose := ""
		if kind == "cast":
			purpose = "Casting %s (%d+)" % [_cast_spell_of(transcript, str(r.get("owner_key", ""))), int(r["target"])]
		if not cx.is_empty() and mapped.is_empty() and kind != "dangerous":
			await _cast_finish(main, cx)
			_cast_leg_end(main, cx)
		if on_throw.is_valid():
			on_throw.call(kind, int(r["index"]))
		if beat.is_valid() and mapped.is_empty():
			await beat.call("throw", r, [])
		if kind == "cast" and not cx.is_empty():
			await _cast_throw(main, cx)
		if str(r["kind"]) == "defense" and roller != unit and not main._solo_is_ai_unit(roller) \
				and main._solo_i_own_unit(roller):   # step 42 (O21): a local defender sees its saves coming, as on the table
			await main._solo_ask_saves(unit, roller, _shot_weapon(unit, lines), int(r["faces"]), int(r["target"]), 0)
		var leg_before: String = main._solo_leg
		if not mapped.is_empty():
			main._solo_leg = str(mapped[1])   # AI-G4 H1a: dice.jsonl's `leg` of the roll
		var faces: Array = await main._owner_roll(roller, int(r["faces"]), int(r["target"]), tray_kind, purpose,
			{"label": label, "what": purpose if not purpose.is_empty() else "%s dice" % kind})
		main._solo_leg = leg_before
		transcript.append({"t": "faces", "faces": faces})
		if kind == "defense" or kind == "spell_defense":
			var defender := str(r.get("owner_key", ""))
			unsaved[defender] = int(unsaved.get(defender, 0)) + failed_saves(faces, int(r["target"]))
		if kind == "cast" and not cx.is_empty():
			_cast_thrown(main, cx, r, faces)
		elif kind == "spell_defense" and not cx.is_empty() and not (cx["cur"] as Dictionary).is_empty():
			var seen: Dictionary = (cx["cur"] as Dictionary)["hits"]   # one save die per spell hit: the outcome toast's hit count
			seen[str(r.get("owner_key", ""))] = int(seen.get(str(r.get("owner_key", "")), 0)) + faces.size()
		if beat.is_valid() and mapped.is_empty():
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


## CC-12b/12c: the core's cast legs as the door names them on the tray: [tray kind, leg]. `cast` is the die (tray kind attack,
## leg cast); every `spell_*` leg is a plain kind with leg spell (the table's own tags, main.gd `_solo_resolve_one_cast`).
## The shadow reads the same map (`CoreShadow.CAST_KINDS`).
const CAST_KINDS := {"cast": ["attack", "cast"], "spell_attack": ["attack", "spell"],
	"spell_defense": ["defense", "spell"], "spell_morale": ["morale", "spell"],
	"spell_fearless": ["fearless", "spell"], "spell_no_retreat": ["no_retreat", "spell"]}


## CC-12b: the spell of `owner_key`'s cast in the transcript (a caster casts once per activation), "?" when none.
static func _cast_spell_of(transcript: Array, owner_key: String) -> String:
	for e in transcript:
		if str((e as Dictionary).get("t", "")) == "cast" and str(e["caster"]) == owner_key:
			return str(e["spell"])
	return "?"


## CC-12: the cast side of one core-driven activation: the planned casts (`report["casts"]`, plan order), the presentation's
## cursor (`next` planned cast, `cur` the cast on the stage), which casts landed their effect on the table, the board's flags
## from before the activation's Dangerous test (the `pre` diff's start) and `volley`, called once the casts are over (the
## volley's stage opens then: the table's casts run in their own stages before it).
static func cast_context(main, report: Dictionary, volley: Callable = Callable()) -> Dictionary:
	var before: Dictionary = main._solo_act_flags if not main._solo_act_flags.is_empty() else main._solo_unit_flags()
	return {"report": report, "casts": report.get("casts", []), "next": 0, "cur": {}, "began": false, "ended": false, "landed": {},
		"before": before, "volley": volley, "volley_open": false, "pre_due": false}


## CC-12b: the cast presentation, driven by the core's lines, each looked at before it is printed. The first line tagged `cast` /
## `spell` opens the cast's stage (the table: `_solo_stage_begin` first); the next cast's first `cast` line closes the one on the
## stage; the volley's own announce ("<unit> fires at ...") ends the cast leg (the spell's saves, wounds and morale lines carry the
## shared machinery's tags - `save`, `shoot`, `morale` - so the tag alone cannot say where the leg ends). The cards close where
## the table's do: the cast die's line closes "Cast roll", the spell's own lines "Effect".
static func _cast_line(main, unit: GameUnit, cx: Dictionary, line: Dictionary) -> void:
	if bool(cx["ended"]):
		return
	var rule := str(line["rule"])
	var text := str(line["text"])
	if bool(cx["began"]) and text.begins_with("%s fires" % unit.get_name()):
		await _cast_finish(main, cx)
		main._solo_flush_volley_note(cx["report"])   # the table's order: casts, the volley's note, then its first line
		_cast_open_volley(cx)
		cx["pre_due"] = true   # the casts' casualties of this very step land after its lines: `drive` writes the `pre` block then
		return
	var is_result := text.contains(": cast roll ")   # the die's own line (rule `cast`) belongs to the cast on the stage
	var cur: Dictionary = cx["cur"]
	if not cur.is_empty() and bool(cur.get("result", false)) and not bool(cur.get("roll_card", false)):
		cur["roll_card"] = true
		await main._solo_stage_phase("Cast roll")
	if rule != "cast" and rule != "spell":
		if not cur.is_empty():
			var wound := CAST_WOUND_LINE.search(text)   # the spell damage's landed wounds, for the outcome toast
			if wound != null:
				(cur["wounds"] as Dictionary)[wound.get_string(1)] = int(wound.get_string(2))
		return   # an effect line of the cast on the stage: it joins that card
	if not cur.is_empty() and rule == "cast" and not is_result and (bool(cur.get("rolled", false)) or bool(cur.get("fizzle", false))):
		await _cast_finish(main, cx)
		cur = {}
	if cur.is_empty():
		var casts: Array = cx["casts"]
		var idx := int(cx["next"])
		while idx < casts.size() and ((casts[idx] as Dictionary).get("caster") == null \
				or ((casts[idx] as Dictionary)["caster"] as GameUnit).get_alive_count() == 0):
			idx += 1   # a caster that is gone before its turn casts silently nothing (the table skips it)
		if idx >= casts.size():
			return
		cx["next"] = idx + 1
		cx["began"] = true
		cur = {"idx": idx, "announce": [], "seal": 0, "rolled": false, "success": false, "hits": {}, "wounds": {}, "before": {}}
		cx["cur"] = cur
		var c: Dictionary = casts[idx]
		main._solo_stage_begin("%s casts %s" % [(c["caster"] as GameUnit).get_name(), str(c.get("name", "?"))])
	if is_result:
		cur["result"] = true
	elif text.contains(" fizzles ") and text.contains("no target remains"):
		cur["fizzle"] = true


## The core's "<target> takes N wound(s) (a/b)" line of a spell's damage.
static var CAST_WOUND_LINE := RegEx.create_from_string("^(.+) takes (\\d+) wounds? \\(")


## The planned cast on the stage: its cast dict, its caster, the targets that still stand.
static func _cast_of(cx: Dictionary) -> Dictionary:
	var cur: Dictionary = cx["cur"]
	return (cx["casts"] as Array)[int(cur["idx"])] if not cur.is_empty() else {}


static func _cast_targets(c: Dictionary) -> Array:
	return (c.get("targets", []) as Array).filter(func(t: Variant) -> bool: return t is GameUnit and not (t as GameUnit).is_destroyed())


## CC-12b: before the cast die is thrown (the table: announce markers, the seal, the "needs" line, then the "Cast" card).
## CC-14a: once per cast - a foe's interference choice shows it first (the table asks the foe after the card), the die finds it done.
static func _cast_throw(main, cx: Dictionary) -> void:
	var c := _cast_of(cx)
	var targets := _cast_targets(c)
	if c.is_empty() or targets.is_empty() or bool((cx["cur"] as Dictionary).get("thrown", false)):
		return
	var cur: Dictionary = cx["cur"]
	cur["thrown"] = true
	for t in targets:
		(cur["before"] as Dictionary)[(t as GameUnit).unit_id] = main._solo_combined_alive(t)
	var name := str(c.get("name", "?"))
	var entry: Dictionary = c.get("spell", {})
	cur["announce"] = main._solo_show_attack_announce(c.get("caster_unit", c["caster"]), targets[0], "casts %s at" % name, false)
	cur["seal"] = main._vfx_seal_begin(c["caster"], entry, entry.get("effect", {}), name)
	await main._solo_stage_phase("Cast", SoloController.Pace.ANNOUNCE)


## CC-14b: what the foe's dialog shows about the cast on the stage: caster, spell, targets, the base target after the casting net
## (conduit mod included, as the table's `_solo_resolve_one_cast` clamps it) and the boost. {} when no cast is on the stage.
static func _interference_context(main, cx: Dictionary) -> Dictionary:
	var c := _cast_of(cx)
	if c.is_empty():
		return {}
	var caster: GameUnit = c["caster"]
	var base := int(c.get("base_target", 4))   # the planner always sets it; 4 is the book's base cast target
	var net := int(SoloController.caster_casting_net(caster, int(main.solo_controller.caster_conduit(caster).get("mod", 0)))["net"])
	return {"caster": caster.get_name(), "spell": str(c.get("name", "?")), "targets": main._solo_cast_target_label(_cast_targets(c)),
		"base": clampi(base - net, 2, 6) if net != 0 else base, "boost": int(c.get("boost", 0))}


## CC-14a: a foe's interference answer `n` for choice `id`: the tokens leave the pool's units the way the core takes them and the table
## did (in the pool's list order, nearest first = the planner's `_draw_aura_tokens`), every machine hears of it, and the seal dims.
## Done at the answer, so the core's end counts (`land_delta`'s casts check) agree with the table's.
static func _land_interference(main, cx: Dictionary, transcript: Array, id: String, n: int) -> void:
	var cast := {}
	for e in transcript:
		if str((e as Dictionary).get("t", "")) == "cast" and int(e["seq"]) == int(id.get_slice(":", 1)):
			cast = e
	var left := n
	for p in cast.get("pools", []):
		if int((p as Array)[0]) != int(id.get_slice(":", 3)):
			continue
		for pay in (p as Array)[1]:
			var gu = main.opr_army_manager.game_units.get(str((pay as Array)[0]))
			var take := mini(int((pay as Array)[1]), left)
			if gu is GameUnit and take > 0:
				(gu as GameUnit).spend_caster_points(take)
				if main.network_manager != null and main.network_manager.has_method("broadcast_unit_casts"):
					main.network_manager.broadcast_unit_casts(gu)
				left -= take
	var cur: Dictionary = cx.get("cur", {})
	if n > 0 and not cur.is_empty() and int(cur.get("seal", 0)) > 0:
		main._vfx_emit({"k": "seal_dim", "sid": int(cur["seal"])})


## CC-12b: after the cast die: the core's own target number reads the face as the table does; the seal ends with the outcome.
static func _cast_thrown(main, cx: Dictionary, r: Dictionary, faces: Array) -> void:
	var cur: Dictionary = cx["cur"]
	if cur.is_empty():
		return
	cur["rolled"] = true
	var success := not faces.is_empty() and DiceRules.is_success(int(faces[0]), int(r["target"]), 0)
	cur["success"] = success
	var c := _cast_of(cx)
	if int(cur["seal"]) > 0:
		main._vfx_emit({"k": "seal_end", "sid": int(cur["seal"]), "o": int(SpellSeal.Outcome.SUCCESS if success else SpellSeal.Outcome.FAIL),
			"tg": _cast_targets(c).map(main._vfx_unit_eye).filter(func(e: Vector3) -> bool: return e != Vector3.INF) if success else [],
			"dmg": str(((c.get("spell", {}) as Dictionary).get("effect", {}) as Dictionary).get("kind", "")) == "damage"})


## CC-12b: the cast on the stage is over: its "Cast roll" card, the effect (a hit buff / debuff lands on the table now,
## `land_cast_effect`: the table's own lines and token) and its "Effect" card, then the outcome toast and the stage's end.
## A fizzle closes after its "Cast" card, as the table's does.
static func _cast_finish(main, cx: Dictionary) -> void:
	var cur: Dictionary = cx["cur"]
	if cur.is_empty():
		return
	cx["cur"] = {}
	var c: Dictionary = (cx["casts"] as Array)[int(cur["idx"])]
	var name := str(c.get("name", "?"))
	var caster: GameUnit = c["caster"]
	if bool(cur.get("fizzle", false)):
		await main._solo_stage_phase("Cast")
		main._solo_stage_end()
		return
	var effect: Dictionary = (c.get("spell", {}) as Dictionary).get("effect", {})
	var success := bool(cur["success"])
	if not bool(cur.get("roll_card", false)):
		await main._solo_stage_phase("Cast roll")
	if not success:
		main._solo_clear_announce(cur["announce"])
		await main._solo_show_outcome("%s fails to cast %s" % [caster.get_name(), name])
		main._solo_stage_end()
		return
	if str(effect.get("kind", "")) != "damage":
		land_cast_effect(main, cx, int(cur["idx"]))
	else:
		for t in c.get("targets", []):   # the table's toast after each target's damage (`_solo_resolve_spell_damage`)
			var hits := int((cur["hits"] as Dictionary).get((t as GameUnit).unit_id, 0))
			if hits <= 0:
				continue
			var landed := int((cur["wounds"] as Dictionary).get((t as GameUnit).get_name(), 0))
			var lost: int = int((cur["before"] as Dictionary).get((t as GameUnit).unit_id, 0)) - main._solo_combined_alive(t)
			await main._solo_show_outcome("%s: %d hit%s → %d wound%s land — %s loses %d model%s" % [
				name, hits, ("" if hits == 1 else "s"), landed, ("" if landed == 1 else "s"), (t as GameUnit).get_name(), lost,
				("" if lost == 1 else "s")])
	await main._solo_stage_phase("Effect")
	main._solo_clear_announce(cur["announce"])
	await main._solo_show_outcome("%s resolves %s" % [caster.get_name(), name])
	main._solo_stage_end()


## CC-12a: a hit buff / debuff / other non-damage cast takes effect on the table, once: the table's own announce line,
## its spell record and token on every standing target (`_solo_announce_spell_effect`, `_solo_place_spell_tokens`) - the table
## rebuilds the effect from ITS spell entry, the core only said it landed. The cast presentation lands it as the cast resolves
## (before the volley's first die, as the table's order); `_land_spell_buffs` lands what the delta names and nothing did yet.
static func land_cast_effect(main, cx: Dictionary, idx: int) -> void:
	var landed: Dictionary = cx["landed"]
	if landed.has(idx):
		return
	landed[idx] = true
	var c: Dictionary = (cx["casts"] as Array)[idx]
	var targets := _cast_targets(c)
	if targets.is_empty():
		return
	var caster: GameUnit = c["caster"]
	var name := str(c.get("name", "?"))
	var effect: Dictionary = (c.get("spell", {}) as Dictionary).get("effect", {})
	main._solo_announce_spell_effect(caster, name, effect, targets)
	var placed := effect.duplicate()
	var once: bool = main._solo_spell_lasts_once(caster, name, effect)
	placed["once"] = once
	placed["duration"] = "once" if once else "round"
	main._solo_place_spell_tokens(name, targets, placed)


## CC-12b: the volley's stage opens once the cast leg is over (the table's casts run in their own stages before it), BEFORE the
## volley's first line is printed. Once per activation.
static func _cast_open_volley(cx: Dictionary) -> void:
	if bool(cx["volley_open"]):
		return
	cx["volley_open"] = true
	if (cx["volley"] as Callable).is_valid():
		(cx["volley"] as Callable).call()


## CC-12a/12c: the cast leg is over and its casualties have landed (the next roll is the volley's, or the core is done): the
## caster discs show the spent tokens, and the leg's `pre` block is written - the units the casts changed, so the replay gates
## start the core from the state the volley started from (the table's `_solo_resolve_ai_casts` tail). Once per activation.
## A Shaken a spell's morale test left lands with the delta, after a volley's `pre`: the block misses it (known gap).
static func _cast_leg_end(main, cx: Dictionary) -> void:
	if bool(cx["ended"]):
		return
	cx["ended"] = true
	cx["pre_due"] = false
	main._solo_refresh_caster_markers()
	var before: Dictionary = main._solo_act_flags if not main._solo_act_flags.is_empty() else cx["before"]
	main._solo_act_flags = {}
	main._solo_record_pre_leg(before)
	_cast_open_volley(cx)


## Step 43: the AI volleys the core resolved and the ones it refused (the AI smoke resets and reads them).
static var ai_runs := 0


## G1' gate `start_twice` (D-PAR3): the core rolled a Reanimation pool for a unit the table already reanimated this round
## (`reanimated_round`, main.gd `_solo_try_reanimation`). Counted in the census as legacy["start"]["twice"].
static func _note_start_twice(main, unit: GameUnit, text: String) -> void:
	if text.begins_with("Reanimation: ") and text.contains(" rolls ") \
			and int(unit.unit_properties.get("reanimated_round", -1)) == int(main.opr_army_manager.current_round):
		var d: Dictionary = legacy.get("start", {})
		d["twice"] = int(d.get("twice", 0)) + 1
		legacy["start"] = d
## Test seam (D-PAR3 15a): false leaves `paid{start}` out of the AI transcript - the control that shows the double pool roll it prevents.
static var start_paid_input := true
static var ai_refusals := 0

## The success target the tray stamps on a Dangerous test's roll (`sim.rs` DANGEROUS_TARGET): a 1 wounds, never a 6.
const DANGEROUS_TARGET := 6


## P4.D-19: the core and the table disagree about the Dangerous test of an activation the core took (the table's report
## names dice the core did not roll): a defect, counted here and reported. The test is not repaired after the fact.
static var dangerous_mismatches := 0


static func _dangerous_mismatch(unit: GameUnit, dice: int, why: String) -> void:
	dangerous_mismatches += 1
	push_error("CoreActivation.run_ai: %s - the table reported a Dangerous test of %d dice, the core did not roll it: %s" % [
		unit.get_name(), dice, why])


## P4.D-37: the activation_level group (core_slice_allow.json): a unit whose rules fire when it moves through an enemy
## (a Strafing weapon, Crossing Attack). The core's activation resolves them from the trails it is handed, in its
## pre-attack slots. Both doors take both: a player's bearer strikes with the activation's Fire / End (`_solo_human_strafing`
## leaves a Strafing strike to the core; the table never rolled Crossing Attack for a player's unit).
const MOVE_THROUGH := ["Strafing", "Crossing Attack"]


static func moves_through(gu: GameUnit) -> bool:
	return CoreSlice.carries(gu, MOVE_THROUGH)


## The actions the AI door takes: a Hold or an Advance; a Rush only for a unit that moves through (it cannot shoot, but its
## move-through attacks fire after the move) or that CASTS this activation (`casting`: a rushed caster may still cast, the core
## resolves the move's Dangerous test and the casts; measured 20.11.: 23 of the 25 casting activations the door was never asked about
## in a 10-game soak were Rushes).
static func takes_action(unit: GameUnit, kind: int, casting := false) -> bool:
	return kind in [AiDecision.Action.HOLD, AiDecision.Action.ADVANCE] \
		or (kind == AiDecision.Action.RUSH and (casting or moves_through(unit)))


## P4.D-19: does the AI body hand this activation to the core? A board was captured for it before its move, the tray
## exists, the action is one the door takes (`takes_action`), and the unit is plain. True = the activation's Dangerous test
## and the end morale from its wounds are the core's: the body rolls neither (see `run_ai`'s `owns_dangerous`).
## C-19 (deny mode): an activation that casts (`report["casts"]`) is NOT taken. `run_ai` refuses it anyway (the "cast" clause), but
## by then the body had deferred the Dangerous test and resolved the casts first: cast -> Dangerous, where the table pays Dangerous
## -> cast (a caster the test kills must not cast). The whole activation stays on the table, in the table's own order; a caster
## with nothing to cast this activation is still taken. CC-13a: with the cast switch ON (`cast_door_enabled`) a casting activation
## IS taken when no member of its chain carries a table-only pre-attack beat (`cast_chain_clear`); the body then probes the casts
## (`probe_casts`) before it pays or resolves anything.
## D-PAR3 15b: a capture taken after the table moved `gu` puts it and its joined heroes back on each model's route start
## (`last_move_paths`), so the transcript's placement replays the move through the core's move check. A model without a
## route stays. Stamps and latches stay the table's (fd_paid_brief.md (iii)).
static func _put_on_start_spots(main, plain: Dictionary, gu: GameUnit) -> void:
	var start := {}
	for p in main.solo_controller.last_move_paths:
		if not ((p as Dictionary)["path"] as Array).is_empty():
			start[p["model"]] = (p["path"] as Array)[0]
	for u in [gu] + gu.get_attached_heroes():
		var key := str((u as GameUnit).unit_id)
		if not (plain["units"] as Dictionary).has(key):
			continue
		var at: Array = []
		for m in (u as GameUnit).models:
			if m.is_alive and m.node != null:
				at.append(start.get(m, m.node.global_position))
		plain["units"][key]["positions"] = BattleSim._plain_vec3s(at)


## D-PAR3 15b: a Surprise Attack bearer's burst fires after the capture (main.gd's activation body): the table pays the whole
## pre-volley part and the volley goes through the recapture (`recapture_due`).
static func _surprise_chain(unit: GameUnit) -> bool:
	return ([unit] + unit.get_attached_heroes()).any(func(u) -> bool: return u is GameUnit and (u as GameUnit).has_special_rule("Surprise Attack"))


## D-PAR3 15b: the table paid the activation's start, Dangerous test, casts and beats (`takes_ai_activation` said no) and the
## volley may still be the core's: the body recaptures the board right before it.
static func recapture_due(main, unit: GameUnit, report: Dictionary, target: GameUnit) -> bool:
	return target != null and bool(report.get("table_paid", false)) and main._solo_core_ai_h != 0 and is_plain(unit)


static func takes_ai_activation(main, unit: GameUnit, report: Dictionary) -> bool:
	var casts: Array = report.get("casts", [])
	var takes: bool = main._solo_core_ai_h != 0 and main.dice_roller_control != null and is_plain(unit) \
		and takes_action(unit, int(report.get("action", -1)), not casts.is_empty()) \
		and (casts.is_empty() or (cast_door_enabled() and cast_chain_clear(unit))) and not _surprise_chain(unit)
	if takes and moves_through(unit) and not main.solo_controller.last_move_paths.is_empty() \
			and not crossed_plain(main, unit, chords_of(main.solo_controller.last_move_paths)):
		report["through_refused"] = true   # P4.D-37c: the decision is made once, here; `run_ai` honours it after the table struck
		return false
	return takes


## The planner's walked paths ({"model", "path"}) as the core's strike legs: one start-to-end leg per model that moved.
static func chords_of(paths: Array) -> Array:
	return paths.filter(func(p: Dictionary) -> bool: return (p["path"] as Array).size() >= 2).map(
		func(p: Dictionary) -> Array: return [(p["path"] as Array)[0], (p["path"] as Array)[-1]])


## P4.D-37c: every enemy the core's strike legs (`chords`: one start-to-end leg per model) cross is a plain target. The core strikes
## what those legs cross with the rules it ports; the slice vouches only for units it lists, so any other crossed enemy
## (even one the strike would not pick) leaves the strike to the table, as before.
static func crossed_plain(main, gu: GameUnit, chords: Array, human := false) -> bool:
	for e in main.opr_army_manager.get_game_units_for_player(main.solo_controller.enemy_slot_of(gu)):
		var eu := e as GameUnit
		if eu == null or eu.get_alive_count() <= 0 or SoloController.unit_in_reserve(eu) or eu.is_attached():
			continue
		if SoloController.trails_cross_unit_bases(chords, eu.models) and not (is_plain_target_human(eu) if human else is_plain_target(eu)):
			return false
	return true


## P4.D-37c: a drop of this human unit handed its strike to the table (a crossed enemy is not a plain target): the activation's
## Fire and End are the table's too, so the strike is not made twice.
static func table_struck(gu: GameUnit) -> bool:
	return bool((_sessions.get(gu.unit_id, {}) as Dictionary).get("table_strike", false))


## P4.D-3 census: volleys the TABLE resolved instead of the core, door -> reason -> count ("_all" = the door's table
## calls). Counting only: no RNG, no log line, nothing the game reads.
static var legacy := {}
## The same volleys by their whole reason SET (door -> "reason|reason" sorted -> volleys): what allowing groups would unlock.
static var legacy_sets := {}


## Why the core door refuses this shooter (and target): "no_core", "attached", "non_opr", "unit_rule:<name>",
## "weapon_rule:<name>" for the shooter; the target's carry a "target_" prefix ("target_rule:<name>" = its unit rules).
static func why_not(main, unit: GameUnit, target: GameUnit, human := false) -> Array:
	var out: Array = [] if applies(main) else ["no_core"]
	out.append_array((CoreSlice.refusals_human(unit) if human else CoreSlice.refusals(unit)) if unit != null else [])
	for r in ((CoreSlice.refusals_human(target, true) if human else CoreSlice.refusals(target, true)) if target != null else []):
		out.append("target_rule:" + r.trim_prefix("unit_rule:") if r.begins_with("unit_rule:") else "target_" + r)
	return out


## One table volley, counted once per reason. `extra` = comma-joined door facts ("split", "no_handle").
static func note_legacy(main, door: String, unit: GameUnit, targets: Array, extra: String = "") -> void:
	var human := door.begins_with("human")   # C-19: the human doors count under the slice the human door reads
	var why: Array = why_not(main, unit, null, human)
	for t in targets:
		for r in why_not(main, null, t as GameUnit, human) + CoreSlice.pair_refusals(unit, t as GameUnit):
			if not why.has(r):
				why.append(r)
	why.append_array(Array(extra.split(",", false)))
	var d: Dictionary = legacy.get(door, {})
	d["_all"] = int(d.get("_all", 0)) + 1
	var seen := {}
	for r in (why if not why.is_empty() else ["other"]):
		if not seen.has(r):
			seen[r] = true
			d[r] = int(d.get(r, 0)) + 1
	legacy[door] = d
	var reasons: Array = seen.keys()
	reasons.sort()
	var key := "|".join(PackedStringArray(reasons))
	var sets: Dictionary = legacy_sets.get(door, {})
	sets[key] = int(sets.get(key, 0)) + 1
	legacy_sets[door] = sets


## NML_TABLE_CENSUS=<path>: a both-AI game writes the census when it ends (the core's own AI volleys ride along).
static func dump_legacy() -> void:
	var path := OS.get_environment("NML_TABLE_CENSUS")
	var f := FileAccess.open(path, FileAccess.WRITE) if path != "" else null
	if f != null:
		var out := {"legacy": legacy, "legacy_sets": legacy_sets, "core_ai_runs": ai_runs, "core_ai_refusals": ai_refusals, "land_illegal": land_illegal,
			"cast_door": {"seen": cast_seen, "taken": cast_taken, "fallbacks": cast_fallbacks, "probe_refusals": cast_probe_refusals,
			"reasons": cast_probe_reasons.slice(0, 40), "not_asked": cast_not_asked}}
		if not CoreShadow.records.is_empty():
			out["shadow"] = CoreShadow.records   # C-4: the shadow run's volleys (NML_CORE_SHADOW=1)
		if not CoreShadow.melee_records.is_empty():
			out["shadow_melee"] = CoreShadow.melee_records   # plan E: the AI charges (NML_CORE_SHADOW_MELEE=1)
		f.store_string(JSON.stringify(out))


## Step 42: the AI's volley through the core - Hold or Advance (P4.D-37: a Rush too, for a unit that moves through), the unit and its one target (the table's own pick) plain,
## no Dangerous test this activation (the table rolled it already; the core would roll it again). `h` is the board
## before the move (the AI body captured it and releases it). True = the core resolved the volley. A refusal is a
## defect: reported, and the table shoots instead - unless a die was already thrown (never resolve a volley twice).
## P4.D-18: `owns_dangerous` = the caller rolled no Dangerous test and leaves it to the core (the activation's test and
## the end-of-activation morale from its wounds ride this call). Only then may `target` be null (a unit that cannot shoot
## or has no target: the activation has no shot). Default false = the table's own roll stays authoritative: a report that
## names Dangerous dice is refused, as before.
## P4.D-14: `rest` = split fire's further groups ({target, shots}, the table's order); `target` and `shots` are the first. The core
## fires them from the aim (`split_aim`) and the table stages each group as its own volley. A group that is not plain, or an aim the
## core would pool, keeps the whole activation on the table (false before any die).
static func run_ai(main, unit: GameUnit, report: Dictionary, target: GameUnit, h: int, shots: Array = [],
		owns_dangerous := false, rest: Array = []) -> bool:
	if bool(report.get("through_refused", false)):
		return false   # P4.D-37c: the body left the strike to the table (a crossed enemy is not a plain target)
	var kind := int(report.get("action", -1))
	var reported := int(report.get("dangerous_dice", report.get("dangerous_models", 0)))
	var paid := bool(report.get("core_paid", false))   # D-PAR3 15b: recaptured after the table's start, test, casts and beats
	var table_rolled := not owns_dangerous and reported > 0 and not paid
	var parts: Array = [{"target": target, "shots": shots}] + rest
	var aim := split_aim(parts)
	# A unit that cast this activation: the table resolved the casts after the capture (`_solo_resolve_ai_casts`), so the
	# board `h` holds no spell effect - the volley stays on the table (the shadow's "cast" reason names it). CC-12: unless the
	# caller marked the report `cast_door` (the cast door took the activation; CC-13a sets it, nothing does today): then the core
	# resolves the planned casts from this capture and the table does not.
	var cast := not (report.get("casts", []) as Array).is_empty()
	var cast_taken := cast and bool(report.get("cast_door", false))
	if h == 0 or not takes_action(unit, kind, cast_taken) or not is_plain(unit) or table_rolled or (cast and not cast_taken and not paid) or _aim_ambiguous(aim) \
			or (target == null and not owns_dangerous) or (target != null and not is_plain_target(target)) \
			or rest.any(func(p: Dictionary) -> bool: return not is_plain_target(p["target"])) \
			or parts.any(func(p: Dictionary) -> bool: return not CoreSlice.pair_refusals(unit, p["target"]).is_empty()):
		return false
	# #172 interim: the core lands its own casualty order, so a human owner who has a wound-allocation choice (a Tough
	# model, or mixed loadouts among the alive models) would never be asked. That volley stays on the table, which
	# prompts. The real wound count is unknown before the roll: one wound keeps the Tough and loadout checks. With the
	# wound_alloc switch ON (P4.D-26) the core asks the allocation as a NeedChoice and the owner's prompt answers it, so the
	# guard applies only with the switch OFF; the guard and the switch go together (P4.D-27).
	var chooser: Array = [] if choice_enabled("wound_alloc") else parts.filter(
		func(p: Dictionary) -> bool: return p["target"] != null and main._solo_wound_choice_matters(p["target"], 1))
	if not chooser.is_empty():
		main._log_rule_event(BattleLog.Category.COMBAT, "%s: %s's owner chooses the casualties - the table resolves this volley" % [
			unit.get_name(), chooser[0]["target"].get_name()], true)
		return false
	var t: Array = ai_transcript(main, unit, report, target, aim)
	if cast_taken:
		t.append_array(cast_inputs(report))   # CC-12: the planned casts, after the intent and before the first faces
	# Step 42b: the table's presentation of the volley (_present); its stage opens before the core's first line.
	# P4.D-19: the core prints no sentence for the Dangerous test (its first throw): the table's own two stand in for it, in
	# the table's words and places - the test line before the roll, the wound line right after it - and the staged volley
	# does not take that throw for its first hit roll. `reported` is the table's dice count; a first throw of another
	# size or target means the core did not roll the test the table reported (a defect, reported; it then shows as a hit roll).
	var dice := reported if owns_dangerous else 0
	var st := {"n": 0, "open": false, "result": false, "hits": 0, "landed": 0, "announce": [], "first": dice > 0, "test": false,
		"before": main._solo_combined_alive(target) if target != null else 0, "moved": bool(report.get("moved", false))}
	var shows := target != null and not shots.is_empty()   # a shotless activation has no volley to stage
	var sts: Array = [st]   # split fire: one stage state per group (the first is `st`, which also holds the Dangerous test's)
	for p in rest:
		sts.append(st.merged({"n": 0, "open": false, "result": false, "hits": 0, "landed": 0, "announce": [], "first": false, "test": false,
			"before": main._solo_combined_alive(p["target"])}, true))
	var at := [0]   # the group being shown
	var beat := func(ev: String, a: Dictionary, faces: Array) -> void:
		if ev == "throw" and st["first"]:
			st["first"] = false
			st["test"] = int(a["count"]) == dice and int(a["target"]) == DANGEROUS_TARGET
			if st["test"]:
				main._solo_log_dangerous_test(unit, dice)
			else:
				_dangerous_mismatch(unit, dice, "its first throw is %s dice at %s+" % [a["count"], a["target"]])
		if st["test"] and (ev == "throw" or ev == "thrown"):
			if ev == "thrown":
				st["test"] = false
				var wounds := faces.filter(func(f: Variant) -> bool: return int(f) == 1).size()
				if wounds > 0:
					main._solo_log_dangerous_wounds(unit, wounds)
			return
		if shows:
			var g: Dictionary = parts[at[0]]
			var cur: Dictionary = sts[at[0]]
			if ev == "throw" and str(a.get("kind", "")) == "attack" and at[0] < parts.size() - 1 and cur.has("rolling") \
					and int(cur["n"]) >= (cur["rolling"] as Array).size():
				await _present(main, unit, g["target"], g["shots"], cur, "done", {}, [])   # the group's last weapon fired: close its stage
				at[0] += 1
				g = parts[at[0]]
				cur = sts[at[0]]
				main._solo_stage_begin("%s fires at %s" % [unit.get_name(), g["target"].get_name()])
			await _present(main, unit, g["target"], g["shots"], cur, ev, a, faces)
	# CC-12b: with casts the volley's stage opens when the cast leg is over (`cast_context`'s `volley`): the casts run in their own stages.
	var open_volley := func() -> void:
		if shows:
			main._solo_stage_begin("%s fires at %s" % [unit.get_name(), target.get_name()])
	var cx := cast_context(main, report, open_volley) if cast_taken else {}
	if cx.is_empty():
		open_volley.call()
	_beat_actor = unit if report.has("core_beats") else null   # H-8: the beats guard handed this unit's beats to the core
	var r: Dictionary = await drive(main, h, unit, t, true, Callable(), false, beat if shows or dice > 0 else Callable(), cx)
	_beat_actor = null
	if str(r["step"]) == "done":
		if st["first"] and dice > 0:
			_dangerous_mismatch(unit, dice, "it threw no die")
		ai_runs += 1
		if shows:   # an exchange was fought (the table's `_solo_consume_once_mods` follows a volley, never a bare Dangerous test or cast)
			land_late_once_records(main, h, unit, parts.map(func(p: Dictionary) -> GameUnit: return p["target"]),
				(cx.get("casts", []) as Array).map(func(c: Dictionary) -> String: return str(c.get("name", ""))))
		announce(main, unit, target, cast_touched(report) if cast_taken else [])   # step 50/51 (+ CC-13c: the casts' targets and payers): the table that ran the AI activation announces its digest check
		return true
	ai_refusals += 1
	push_error("CoreActivation.run_ai: %s - the core answered %s: %s" % [unit.get_name(), r["step"], r.get("reason", "")])
	return t.any(func(e: Dictionary) -> bool: return str(e["t"]) == "faces")


## P4.D-48: the AI charges the core resolved through the charge door (the AI smoke and the door test read them).
static var ai_charges := 0
## True while the charge door drives: the core moves both units before it wounds them, so a landing names its model by slot
## (the table's start positions are the planner's, not the core's), and the fatigue the fight writes is the core's own.
static var _charge_landing := false
## H-8 (Plan H): the unit whose pre-attack beats the core resolves in this call (the beats guard, `report["core_beats"]`); null else.
static var _beat_actor: GameUnit = null


## P4.D-48: does the charge door take this AI charge? A board captured before the move, the tray, a CHARGE at a target, both
## units taken by the melee slice (`CoreSlice.MELEE_PATH`: no rule at all to start), a target with a statline, no Dangerous
## test the table rolled and no cast (the board holds neither). A human defender's strike-back is its owner's choice: the
## core asks it (Plan E-24) and `drive` answers it through `_solo_confirm_strike_back` (E-25).
## WIP switch, default OFF (`NML_ONE_CORE_CHARGE=1` turns it on): the core's tray melee does not yet say the table's
## melee lines nor land its strike losses per step (measured, test/one_core/core_charge_door_test.gd), so no game takes it.
static var _charge_env := -1


static func charge_door_enabled() -> bool:
	if _charge_env < 0:
		var raw := OS.get_environment("NML_ONE_CORE_CHARGE").to_lower()
		_charge_env = 1 if (raw == "1" or raw == "on") else 0
	return _charge_env == 1


## Lead decision (#3025): a melee winner of 10+ models consolidates differently on the table (0 models moved) and in the core
## (2; both legal, the core is the reference). Until the table follows, a unit of that size on either side stays on the table.
const MELEE_MAX_MODELS := 10


static func takes_ai_charge(main, unit: GameUnit, report: Dictionary) -> bool:
	return charge_door_enabled() and main._solo_core_ai_h != 0 and main.dice_roller_control != null \
		and charge_refusals(main, unit, report).is_empty()


## Plan E (melee shadow): why the charge door's slice refuses this AI charge, by reason ([] = it takes it); the door's own
## predicate apart from the switch, the board and the tray. Read before the table fights (the sizes are the start's).
## `deny` reads `CoreSlice.MELEE_DENY_PATH` instead of the live allow file (shadow deny view only; the door leaves it false).
static func charge_refusals(main, unit: GameUnit, report: Dictionary, deny := false) -> Array:
	var target = report.get("target")
	if unit == null or not target is GameUnit or int(report.get("action", -1)) != AiDecision.Action.CHARGE:
		return ["no_charge"]
	var out: Array = CoreSlice.melee_refusals(unit, false, deny) + CoreSlice.melee_refusals(target, true, deny).map(func(r): return "target_" + r)
	if main._solo_combined_alive(unit) >= MELEE_MAX_MODELS or main._solo_combined_alive(target) >= MELEE_MAX_MODELS:
		out.append("size")
	if not has_statline(target):
		out.append("no_statline")
	if int(report.get("dangerous_dice", report.get("dangerous_models", 0))) != 0:
		out.append("dangerous")
	if not (report.get("casts", []) as Array).is_empty():
		out.append("cast")
	# The core's melee transcript is the rules-3.6 one (its result line and the sides' tallies read `EPOCH_73_V36`, the table's older line says
	# "dealt" where the core says "took"): a charge under an older stamp (a replay, a pinned test) stays on the table, as a pre-83 lone hero does for a volley.
	if AiActRecorder.rules_epoch < AiActRecorder.EPOCH_73_V36:
		out.append("old_epoch")
	return out


## P4.D-48: the AI charge through the core's step path (`_run_ai_melee` hands over). The core lands the charge with its own
## `charge_move` from the board before the move (authoritative, lead decision: the planner's drop is not sent), then
## the snap, the pile-in, the strikes, the melee result, the loser's morale and the consolidation, and writes their lines;
## the delta lands Shaken, Fatigue and every moved model's end position. The target's pre-melee wounds (`target_wounds_start`)
## are the core's own read of the same board. True = the core resolved it (or a refusal after a die: never twice).
static func run_ai_charge(main, unit: GameUnit, report: Dictionary) -> bool:
	var target: GameUnit = report["target"]
	# No placement: the core's charge move is the landing (lead decision), so the planner's drop is neither checked nor used
	# (its routes may end where a later separation nudge moved a model, which the core's trail check refuses).
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": int(report.get("action", -1)), "charge": target.unit_id}]
	var wounds := [main._solo_unit_wounds_now(unit), main._solo_unit_wounds_now(target), main._solo_combined_alive(target)]
	main._solo_stage_begin("%s charges %s" % [unit.get_name(), target.get_name()])
	_charge_landing = true
	var r: Dictionary = await drive(main, main._solo_core_ai_h, unit, t, true)
	_charge_landing = false
	if str(r["step"]) == "done":
		ai_charges += 1
		var lost: int = wounds[2] - main._solo_combined_alive(target)
		await main._solo_show_outcome("Melee: %s deals %d — takes %d back — %s loses %d model%s" % [unit.get_name(),
			wounds[1] - main._solo_unit_wounds_now(target), wounds[0] - main._solo_unit_wounds_now(unit), target.get_name(),
			lost, "" if lost == 1 else "s"])
		main._solo_stage_end()
		announce(main, unit, target)
		return true
	main._solo_stage_end()
	ai_refusals += 1
	push_error("CoreActivation.run_ai_charge: %s - the core answered %s: %s" % [unit.get_name(), r["step"], r.get("reason", "")])
	return t.any(func(e: Dictionary) -> bool: return str(e["t"]) == "faces")


## C-2: the AI activation's transcript before its first die: begin, the models where they stand now (with the routes they
## walked) and the intent (`target` null = no shot). `split` (an array of {member, weapon, target}, P4.D-14) is split fire's
## aim; empty = none, the intent then carries no "split" key. Shared by `run_ai` and the shadow replay (C-4).
static func ai_transcript(main, unit: GameUnit, report: Dictionary, target: GameUnit, split: Array = []) -> Array:
	# S1: the joined heroes' models follow the host's (get_alive_models_with_attached), so the core moves them with the unit
	# as the table does; a hero left at its start would be out of range of the volley it fires in.
	var chain: Array = unit.get_alive_models_with_attached()
	var at: Array = chain.map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	# Step 42c: each model's walked route (the planner's, world XZ) rides along, so the core's move check measures the
	# route, not the chord (R3); a model that did not move sends none.
	var routes := {}
	for p in main.solo_controller.last_move_paths:
		var route: Array = (p["path"] as Array).map(func(v: Vector3) -> Vector2: return Vector2(v.x, v.z))
		# The glide rests on the placement the gate left (`end`), which the retraced route may fall up to 0.0005 m short of: the core's move
		# check wants the route to end where the model stands (0.01 in), so the hop to the placement rides along.
		var end: Variant = (p as Dictionary).get("end")
		if end is Vector3 and route.size() >= 2 and Vector2((end as Vector3).x, (end as Vector3).z).distance_to(route.back()) > 0.000001:
			route.append(Vector2((end as Vector3).x, (end as Vector3).z))
		routes[p["model"]] = route
	var trails: Array = chain.map(func(m: ModelInstance) -> Array: return routes.get(m, []))
	var intent := {"t": "intent", "kind": int(report.get("action", -1))}
	if target != null:
		intent["shoot"] = target.unit_id
	if not split.is_empty():
		intent["split"] = split
	# D-PAR3 15a: every AI board is captured after the table's activation start (`begin_activation`): the core skips its own.
	var paid := bool(report.get("core_paid", false))   # D-PAR3 15b: the table paid the test, casts and beats too
	return [{"t": "begin"}] + ([{"t": "paid", "start": true, "dangerous": paid, "beats": paid}] if start_paid_input else []) \
		+ [{"t": "placed", "positions": at, "trails": trails}, intent]


## CC-13a: the switch `NML_ONE_CORE_CAST` (default OFF; "1" / "on" turns it on): the core resolves a casting AI activation's casts
## in its one call (Dangerous, casts, volley) instead of the table's `_solo_resolve_ai_casts`. Nothing is player-visible with it OFF.
static var _cast_env := -1


static func cast_door_enabled() -> bool:
	if _cast_env < 0:
		var raw := OS.get_environment("NML_ONE_CORE_CAST").to_lower()
		_cast_env = 1 if (raw == "1" or raw == "on") else 0
	return _cast_env == 1


## CC-13a: the rule primitives of the table's pre-attack beats that run in the cast slot's neighbourhood with NO core guard yet
## (main.gd after the casts: Mend, Breath Attack, the Utility Buff family, Mind Control, Piercing Tag, Precision, Reckless
## Piercing, Storm Attack, Teleport): a unit carrying one stays on the table until the "beats guard" lane lands (the core, which
## takes the whole activation, would resolve the beat a second time).
const CAST_BEAT_PRIMITIVES := ["Mend", "Breath Attack", "Utility Buff", "Mind Control", "Piercing Tag", "Precision Tag",
	"Precision Target", "Precision Spotter", "Reckless Piercing", "Storm Attack", "Teleport"]


## CC-13a: the cast predicate: no member of the unit's chain (the unit and its joined heroes) carries a `CAST_BEAT_PRIMITIVES` rule.
static func cast_chain_clear(unit: GameUnit) -> bool:
	if CoreSlice.carries(unit, CAST_BEAT_PRIMITIVES):
		return false
	for hero in unit.get_attached_heroes():
		if hero != null and CoreSlice.carries(hero, CAST_BEAT_PRIMITIVES):
			return false
	return true


## CC-13a: the casts a probe refused (named reasons, before any die) and how many: what the AI smoke reads.
static var cast_probe_refusals := 0
static var cast_probe_reasons: Array = []
## CC-15 prep: the cast door's census for the soak (`dump_legacy`, key "cast_door"): casting activations that reached the body's cast
## slot (`cast_seen`), the probe's takes (`cast_taken`), and the marked ones whose core call could not run, so the table cast after all
## (`cast_fallbacks`, the late-lines case: the volley's own pre-lines print before the table's casts).
static var cast_seen := 0
static var cast_taken := 0
static var cast_fallbacks := 0
## CC-15 prep: why a casting activation was not even asked of the door, reason -> count (`note_cast_not_asked`).
static var cast_not_asked: Dictionary = {}


## CC-15 prep: the first reason `takes_ai_activation` (in its own order) said no to a casting activation: the switch is off, no board,
## no dice roller, a unit the slice refuses (its first refusal named), an action the door does not take, a table-only pre-attack beat
## on the chain (`cast_chain_clear`), else the move-through refusal.
static func note_cast_not_asked(main, unit: GameUnit, report: Dictionary) -> void:
	var why := "through_refused"
	if not cast_door_enabled():
		why = "switch_off"
	elif main._solo_core_ai_h == 0:
		why = "no_handle"
	elif main.dice_roller_control == null:
		why = "no_dice_roller"
	elif not is_plain(unit):
		why = "unit:%s" % str((CoreSlice.refusals(unit) + ["?"])[0])
	elif not takes_action(unit, int(report.get("action", -1))):
		why = "action:%d" % int(report.get("action", -1))
	elif not cast_chain_clear(unit):
		why = "beat_primitive"
	cast_not_asked[why] = int(cast_not_asked.get(why, 0)) + 1


## CC-13a: the dry probe at the body's cast slot: the activation's placement, intent and cast inputs, no faces. The core checks every
## planned cast (keys, spell, kind, target rule, interference choice) BEFORE it rolls anything, so a refusal costs no die and the
## table then pays the Dangerous test and resolves the casts in its own order; anything else (the first die asked, a choice,
## done) is a taken activation. A `done` answer holds a board: released here.
static func probe_casts(main, unit: GameUnit, report: Dictionary) -> bool:
	var h: int = main._solo_core_ai_h
	if h == 0:
		return false
	var core: Object = (main.solo_controller as SoloController)._core_node_ready()
	var t: Array = ai_transcript(main, unit, report, null) + cast_inputs(report)
	var probes := interference_probes(t)
	if not probes.is_empty() and main._solo_ai_cast_foes().size() > 1:   # CC-14a: the planner's pools carry ONE human slot, the table asks every one
		return _probe_refused("an open cast with more than one human foe slot (the pools carry one)")
	for id in probes:
		t.append({"t": "choice", "id": id, "option": ""})
	var r: Dictionary = core.step_activation(h, unit.unit_id, t, main.object_manager._strict_movement_enforced())
	if r.has("handle"):
		core.release(int(r["handle"]))
	return str(r["step"]) != "refused" or _probe_refused(str(r.get("reason", "")))


static func _probe_refused(why: String) -> bool:
	cast_probe_refusals += 1
	cast_probe_reasons.append(why)
	return false


## CC-10b: the planner's cast dicts (`report["casts"]`, plan order) as the core's `Input::Cast` entries: one per planned
## cast, `seq` 0-based, every unit named by its roster key (`unit_id`), payers as `[[key, tokens]..]` in spend order and
## the pools per foe slot. Pure. Nothing sends this array to the core yet (CC-13).
static func cast_inputs(report: Dictionary) -> Array:
	var out: Array = []
	for c in report.get("casts", []):
		var cast := c as Dictionary
		var caster: GameUnit = cast.get("caster")
		if caster == null:
			continue
		var targets: Array = []
		for t in cast.get("targets", []):
			if t is GameUnit:
				targets.append((t as GameUnit).unit_id)
		var conduit: GameUnit = cast.get("conduit")
		var shaken: Array = []
		for sh in cast.get("conduit_shaken", []):
			var su: GameUnit = (sh as Dictionary).get("unit")
			if su != null:
				shaken.append(su.unit_id)
		var pools: Array = []
		for p in cast.get("pools", []):
			var row: Array = p as Array
			pools.append([int(row[0]), _cast_payers(row[1])])
		var effect: Dictionary = (cast.get("spell", {}) as Dictionary).get("effect", {})
		out.append({"t": "cast", "seq": out.size(), "caster": caster.unit_id,
			"spell": str(cast.get("name", "")), "targets": targets,
			"base": int(cast.get("base_target", 0)),
			"threshold": int(cast.get("threshold", 0)),
			"boost": int(cast.get("boost", 0)), "boost_sources": _cast_payers(cast.get("boost_sources", [])),
			"interference": int(cast.get("interference", 0)),
			"interference_sources": _cast_payers(cast.get("interference_sources", [])),
			"conduit": (conduit.unit_id if conduit != null else ""), "conduit_shaken": shaken,
			"pools": pools, "once": bool(effect.get("once", str(effect.get("duration", "")) == "once")),
			"open": bool(cast.get("interference_open", false))})
	return out


## One payer list of a cast as the core reads it: `[[unit key, tokens]..]` in spend order.
static func _cast_payers(srcs: Array) -> Array:
	var rows: Array = []
	for s in srcs:
		var sd := s as Dictionary
		var su: GameUnit = sd.get("unit")
		if su != null:
			rows.append([su.unit_id, int(sd.get("tokens", 0))])
	return rows


## P4.D-14: split fire's aim of `parts` (the volley's groups, {target, shots}): one {member, weapon, target} per shot in the table's
## group order; [] for one group. The member is the unit NAME (`sim.rs split_plan` finds it by name), the target its roster key.
static func split_aim(parts: Array) -> Array:
	var aim: Array = []
	for p in parts if parts.size() > 1 else []:
		for shot in p["shots"]:
			aim.append({"member": (shot["member"] as GameUnit).get_name(), "weapon": str(shot["profile"].get("name", "")), "target": (p["target"] as GameUnit).unit_id})
	return aim


## An aim that names one (member, weapon) for two targets: the core fires that weapon once and pools the rest (`split_weapon_reaimed`).
static func _aim_ambiguous(aim: Array) -> bool:
	var seen := {}
	for e in aim:
		var key := "%s|%s" % [e["member"], e["weapon"]]
		if seen.get(key, e["target"]) != e["target"]:
			return true
		seen[key] = e["target"]
	return false


## Step 42c-2: the table's shot rows of one AI volley (`_solo_resolve_ai_volley` writes one per shot, in `shots` order,
## before it skips a weapon with no attacks), and the shots that roll (attacks > 0, same order: the order of the core's
## hit rolls; all of them when none rolls, so the show only closes). A silent weapon has no hit roll to hang its row on,
## so `_present` writes them all at the first hit roll, or at the end when none rolls.
static func _record_shots(main, unit: GameUnit, target: GameUnit, shots: Array, moved: bool) -> Array:
	var rolling: Array = []
	for shot in shots:
		var d: Dictionary = main._solo_shot_eligibility(shot["member"], shot["profile"], shot, target, false, moved)
		var attacks := int((d["report"] as Dictionary)["attacks"])
		main._solo_record_shot(unit, shot["member"], target, shot["profile"], int(d["sighted"]), int(d["bearers"]),
			int(shot["max"]), attacks, int(SoloController.effective_shoot_reach_in(float(shot["reach"]), target)))
		if attacks > 0:
			rolling.append(shot)
	return rolling if not rolling.is_empty() else shots


## P4.D-30b1: the Piercing Tag pool of the target. The core spent its own copy (and applied the +AP), so the table's
## pool never moved and the spend line was never written. The table's own spend, once per volley, at the volley's first
## hit roll (a refusal never gets here, so the table's volley after it cannot spend twice): the pool, the sync and the line.
## The AP it returns is not used: the core's volley carries it.
static func _spend_tag(main, target: GameUnit) -> void:
	main._solo_spend_piercing_tag(target)


## Step 42b: the table's show around an AI volley (_solo_resolve_ai_volley's calls in its order) on the core's steps:
## at the first hit roll the announce (the core says its line), the fan and the Declaration beat; a tracer before each
## hit roll (`shots`: the shots that roll, in the table's order); a weapon's hit strip and beat after its saves, or at
## the next hit roll or the end if it missed; before the morale roll or at the end the outcome toast and the Result beat;
## the Morale beat. A refusal only closes.
static func _present(main, unit: GameUnit, target: GameUnit, shots: Array, st: Dictionary, ev: String, a: Dictionary,
		faces: Array) -> void:
	var kind := str(a.get("kind", ""))
	# Step 42c-2: the rows at the first hit roll, or at the end; never at a refusal (the table then writes them).
	if not st.has("rolling") and (ev == "done" or (ev == "throw" and kind == "attack")):
		_spend_tag(main, target)
		st["rolling"] = _record_shots(main, unit, target, shots, st["moved"])
	shots = st.get("rolling", shots)
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
		# The table's own reading (`_solo_resolve_ai_volley`): Indirect fire, own or granted, tests no sight line, so its cue
		# draws no chalk tracer (deletion blocker before PLAN_FIRST_DELETION step 35).
		var granted: bool = SoloController.granted_indirect_of(unit)
		var d: Dictionary = main._solo_shot_eligibility(shot["member"], shot["profile"], shot, target, granted, st["moved"])
		var pairs: Array = d["pairs"]
		main._vfx_volley(shot["member"], target, shot["profile"],
			pairs.slice(0, int(d["bearers"]) if int(d["bearers"]) >= 0 else pairs.size()),
			bool((shot["profile"] as Dictionary).get("indirect", false)) or granted)
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
			await main._solo_show_outcome(CoreActivation.volley_outcome(target, st["hits"], st["landed"],
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


## P4.D-41: the outcome sentence the AI volley toast shows, moved verbatim out of the table so the core door owns it.
## DN-2: the table's wrapper is gone; the AI volley resolver asks this sentence itself.
static func volley_outcome(target: GameUnit, hits: int, wounds: int, lost: int) -> String:
	return "%s: %d hit%s → %d wound%s land — %s loses %d model%s" % [target.get_name(), hits, ("" if hits == 1 else "s"),
		wounds, ("" if wounds == 1 else "s"), target.get_name(), lost, ("" if lost == 1 else "s")]


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
	if not st.has("tagged") and (ev == "done" or (ev == "throw" and kind == "attack")):
		st["tagged"] = true
		_spend_tag(main, target)
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


## The unit name a roll's label shows: a lone hero (its host has no model left) rolls for its host in the table's log, which was
## aimed at the host ("AI (Cultists) defends"); every other roller shows the owner the core named.
static func _shown_owner(roller: GameUnit, owner: String) -> String:
	var host = roller.get_attached_to()
	return (host as GameUnit).get_name() if host is GameUnit and (host as GameUnit).get_alive_count() <= 0 else owner


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


## P4.0-1: `gu`'s start models in capture order. The core names a model by its slot, the index it had in its unit's list of
## living models when the board was captured (BattleSim.capture: get_alive_models() order, the order `_start_models` keeps).
static func _models_by_slot(start_models: Array, gu: GameUnit) -> Array:
	return start_models.filter(func(e: Dictionary) -> bool: return (e["model"] as ModelInstance).unit == gu) \
		.map(func(e: Dictionary) -> ModelInstance: return e["model"])


## Lands one step's landings on the table (O4 b): a wound shows at once on the wound marker, the dead leave right
## after the saves. Every need_roll repeats the earlier landings (the list only ever grows at its end); `done` skips what
## this activation already landed.
## P4.0-2: what is remembered is the landing, `(event index, unit, slot)` -> the model it landed on, not the model: a model
## wounded by one landing and wounded or killed by a later one takes both.
## P4.0-1: each landed model also carries the core's `(unit, slot)`. For now the position still decides which model it is
## (the 1 mm XZ match, as before: a table that lost a model after the capture shifts its slot list, the position stays
## right); the slot is the cross-check, and a landing whose slot names another model is a push_error, never silent.
static func land_step(main, active: GameUnit, landings: Array, start_models: Array, done: Dictionary) -> void:
	for event in landings.size():
		var entry: Dictionary = landings[event]
		var lgu: GameUnit = main.opr_army_manager.game_units.get(str(entry["unit"]))
		var by_slot: Array = _models_by_slot(start_models, lgu) if lgu != null else []
		if lgu != null and not (entry.get("moved_to", []) as Array).is_empty():
			var key := "%d:%s:move" % [event, entry["unit"]]
			if lgu == active and not done.has(key):   # 27c: the active unit's own move is a fall's - the model the core moved
				done["moved_self"] = _moved_model(start_models, lgu, entry["moved_to"])
			_land_push(main, lgu, entry["moved_to"], start_models, done, key)
			continue
		var died: Array[ModelInstance] = []
		for lm in entry["models"]:
			var m: ModelInstance = _model_at(start_models, lgu, lm["at"]) if lgu != null else null
			if _charge_landing and int(lm["slot"]) >= 0 and int(lm["slot"]) < by_slot.size():
				m = by_slot[int(lm["slot"])]   # P4.D-48: the core moved the model first; its slot names it
			if m == null:
				push_error("CoreActivation.land_step: no model of %s at %s" % [entry["unit"], lm["at"]])
				continue
			var slot := int(lm["slot"])
			var landed_key := "%d:%s:%d" % [event, entry["unit"], slot]
			if done.has(landed_key):
				continue
			if (by_slot[slot] if slot >= 0 and slot < by_slot.size() else null) != m:
				push_error("CoreActivation.land_step: slot %d of %s is not the model at %s" % [slot, entry["unit"], lm["at"]])
			done[landed_key] = m
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
			elif int(lm["wounds_left"]) > before:
				# H-5a (Plan H): more wounds left than the model holds = the core healed it (Mend, `sim.rs` `tray_mend`, which
				# also said the table's line); the table's own writers, as `_solo_apply_mend`.
				m.heal(int(lm["wounds_left"]) - before)
				main.radial_menu_controller._update_wound_marker(m)
				if main.network_manager != null and main.network_manager.has_method("broadcast_model_wounds"):
					main.network_manager.broadcast_model_wounds(m)
		if not died.is_empty():
			main._core_said_losses = bool(entry.get("loss_line", false))   # step 27: the core said this loss line
			await main._solo_remove_dead_models(lgu, died, int(lgu.unit_properties.get("player_id", 1)))
			main._core_said_losses = false


## H-8 (Plan H): a pre-attack beat's push (Mind Control) as its own step event: the unit's living models, in capture slot order,
## move to the core's positions with the table's own writer (`_apply_model_positions`), and their start entries follow them, so
## a later landing of the same activation (the volley's, `at` = the pushed position) finds them. Landed once (`done`).
static func _land_push(main, gu: GameUnit, to: Array, start_models: Array, done: Dictionary, key: String) -> void:
	if done.has(key):
		return
	done[key] = null
	var alive: Array = _models_by_slot(start_models, gu).filter(func(m: ModelInstance) -> bool: return m.is_alive)
	if alive.size() != to.size():
		push_error("CoreActivation.land_step: %s was pushed with %d models in the core, the table holds %d" % [gu.get_name(), to.size(), alive.size()])
		return
	main.solo_controller._apply_model_positions(alive, to)
	for e in start_models:
		var i := alive.find(e["model"])
		if i >= 0:
			e["at"] = to[i]


## The activation's final delta (binding step 17): Shaken onto the table; a unit that moved AND lost models is
## accepted only when its losses already landed per step, else nothing lands and done["unknown"] is set.
## `illegal` = the breaks the activation created (`new_breaks`, PLAN_FIRST_DELETION 3c): a unit named there is not moved.
static func land_delta(main, delta: Array, start_models: Array, done: Dictionary, illegal: Array = []) -> void:
	for d in delta:
		var gu: GameUnit = main.opr_army_manager.game_units.get(str(d["unit"]))
		if gu == null:
			continue
		if bool(d["unknown"]):
			var start_alive := start_models.filter(func(e) -> bool: return (e["model"] as ModelInstance).unit == gu)
			var landed := done.values()   # P4.0-2: the models some landing of this activation touched
			var landed_dead := start_alive.filter(func(e) -> bool: return landed.has(e["model"]) \
				and not (e["model"] as ModelInstance).is_alive)
			if landed_dead.size() != start_alive.size() - int(d["alive"]):
				push_error("CoreActivation.land_delta: %s moved and lost models the steps did not land" % gu.get_name())
				done["unknown"] = true
				return
		if bool(d["shaken"]) != gu.is_shaken:
			main.radial_menu_controller.card_toggle_shaken(gu)
			main._solo_mirror_shaken(gu)
		_land_positions(main, gu, d, start_models, illegal)
		_land_ledger(main, gu, d)
		_land_versatile_mode(main, gu, d)   # before the stamps: it reads the table's own `versatile_pick_round`
		_land_stamps(main, gu, d)
		_land_pools(main, gu, d)
		_land_piercing(main, gu, d)
		_land_surprise(main, gu, d)
		_land_feats(main, gu, d)
		_land_once_latches(main, gu, d)
		_land_growth(main, gu, d)
		_land_buffs(main, gu, d)
		_land_spell_buffs(main, gu, d, done)
		_land_marks_left(main, gu, d)


## HR-POS: the unit's surviving model positions after the activation (the delta's `positions`, capture slot order with the
## dead left out, world metres), present when the unit moved. A unit that lost models in the same activation (a Hazardous
## self-wound in the volley) and then stepped carries its survivors: they map onto the start models still alive, in order
## (the per-step landings already removed the same dead). The core's own steps move models the table never placed (the Hit & Run
## sidestep after a volley, `sim.rs` `tray_hit_and_run`, whose line the core already logged): each model that does not stand
## where the core left it (XZ, within `LAND_EPSILON_M`) is put there with the table's own writer (`_apply_model_positions`:
## MP move batch, surface height). A model the table already placed there (a walked move) is no news.
## meleefix: the landing tolerance of `_land_positions`, 0.01 mm: above the float32 noise of a spot both sides computed (the walked move
## agrees with the core to ~3e-6 m), below anything a rule measures.
const LAND_EPSILON_M := 0.00001

## DOOR-LAND-NO-LEGALITY (PLAN_FIRST_DELETION 3c): a unit the core's checker names in `illegal` (overlap, forbidden ground,
## off the board, coherency, an enemy within 1") is not moved: it stays where the table holds it, one line says why, and
## `land_illegal` counts it (the census). The volley's results and the step's stamps land as before. The ruling refuses an illegal
## OPTIONAL step; the charge door's moves (the charge, the 1" separation) are not optional: they land and only the counter shows them.
static var land_illegal := 0


## Lead ruling 3c: a step is judged by the breaks IT creates. `after` = the done step's `illegal` list (3b: the checker on the
## end board of every unit the call moved); a break the board before the activation (handle `h`) already had for the same
## unit, model and kind (overlap: and the same other base; coherency: per unit, i.e. "no worse") is not the step's.
static func new_breaks(core: Object, h: int, after: Array) -> Array:
	if after.is_empty():
		return after
	var units := PackedStringArray()
	for e in after:
		if not units.has(str(e["unit"])):
			units.append(str(e["unit"]))
	var had := {}
	for e in core.check_rest(h, units).get("illegal", []):
		had[_break_key(e)] = true
	return after.filter(func(e: Dictionary) -> bool: return not had.has(_break_key(e)))


static func _break_key(e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	if kind == "coherency":
		return "%s|coherency" % str(e["unit"])
	var other := "%s.%s" % [str(e.get("other", "")), str(e.get("other_model", ""))] if kind == "overlap" else ""
	return "%s|%s|%s|%s" % [str(e["unit"]), str(e.get("model", "")), kind, other]

static func _land_positions(main, gu: GameUnit, d: Dictionary, start_models: Array, illegal: Array = []) -> void:
	var at: Array = d.get("positions", [])
	if at.is_empty():
		return
	var alive: Array = _models_by_slot(start_models, gu).filter(func(m: ModelInstance) -> bool: return m.is_alive)
	if alive.size() != at.size():
		push_error("CoreActivation.land_delta: %s moved %d models in the core, the table holds %d" % [gu.get_name(), at.size(), alive.size()])
		return
	var models: Array = []
	var to: Array = []
	for i in at.size():
		var m: ModelInstance = alive[i]
		var p: Vector3 = at[i]
		if m.node == null or not is_instance_valid(m.node):
			continue
		var now: Vector3 = m.node.global_position
		# Any core end spot above float noise is landed: a 1 in separation can end a model 0.36 mm from the spot the board holds (its landing
		# spot), and the old 0.0005 m dead zone left it 0.014 in off the core's end state. A spot the table already walked to is skipped, so
		# an equal move still sends no MP batch.
		if Vector2(now.x, now.z).distance_to(Vector2(p.x, p.z)) < LAND_EPSILON_M:
			continue
		models.append(m)
		to.append(p)
	if models.is_empty():
		return
	var why := PackedStringArray()
	for e in illegal:
		if str(e.get("unit", "")) == str(d["unit"]) and not why.has(str(e.get("kind", ""))):
			why.append(str(e.get("kind", "")))
	if why.is_empty() or _charge_landing:
		main.solo_controller._apply_model_positions(models, to)
	land_illegal += 0 if why.is_empty() else 1
	if not why.is_empty() and not _charge_landing:
		main._log_rule_event(BattleLog.Category.MOVEMENT, "%s stays where it is - the step would not be legal (%s)" % [
			gu.get_name(), ", ".join(why)], main._solo_is_ai_unit(gu))
	# The landed step IS the table's Hit & Run step (the table's tail never runs it on this path), so the two stamps that step
	# writes on the table (`hit_and_run_move`: `hit_and_run_round` and, since #3002, `moved_round`) are written here with
	# the same writers; `_land_stamps` then finds the table agreeing instead of reporting a split.
	var stamps: Dictionary = d.get("stamps", {})
	var round_no := int(main.solo_controller._current_round())
	if int(stamps.get("hit_and_run_round", -1)) == round_no:
		gu.unit_properties["hit_and_run_round"] = round_no
		if int(stamps.get("moved_round", -1)) == round_no:
			main.solo_controller._sync_unit_latch(gu, "moved_round", round_no)


## C-11: the rule name of each Precision latch and the table flag that closes it.
const PRECISION_FLAGS := {"Precision Tag": "precision_tag_used", "Precision Target": "precision_target_used"}


## C-11: the once-per-game name lists the core SPENT in this activation (the delta's `limited_used`, `storm_used`, `precision_used`:
## the names `State` gained, inventory class (a)). The table's own writer for each ran only on the table path, so on this one the
## core's after is the first writer: the weapon through `mark_limited_used` (the controller's record, the MP latch and the
## decision record), the other two through their `unit_properties` flag (MP-synced). A name the table already holds is no news.
static func _land_once_latches(main, gu: GameUnit, d: Dictionary) -> void:
	for name in d.get("limited_used", []):
		if not (gu.unit_properties.get("limited_used", []) as Array).has(str(name)):
			main.solo_controller.mark_limited_used(gu, {"name": str(name)})
	for name in d.get("storm_used", []):
		var flag := "storm_used_%s" % str(name).to_snake_case()
		if not bool(gu.unit_properties.get(flag, false)):
			main._sync_unit_property(gu, flag, true)
	for name in d.get("precision_used", []):
		if not PRECISION_FLAGS.has(str(name)):
			push_error("CoreActivation.land_delta: %s spent the precision rule %s, which no table flag closes yet" % [gu.get_name(), name])
		elif not bool(gu.unit_properties.get(PRECISION_FLAGS[str(name)], false)):
			main._sync_unit_property(gu, PRECISION_FLAGS[str(name)], true)


## C-13: the unit's Growth Markers count after the activation (the delta's `growth_markers`). `State` keeps ONE counter per unit, the
## table one property per rule (`growth_<rule>`, what `_ledger_of` sums): the table's writers (`_solo_growth_on_kill`, the ignore-wound
## bank) did not run on a path the core resolved, so the core's count lands on the unit's rule. A unit with no such rule or with two
## cannot be attributed: reported, nothing written. A count the table already holds is no news.
static func _land_growth(main, gu: GameUnit, d: Dictionary) -> void:
	var keys: Array = RulesRegistry.unit_rules_of_primitive(gu, "Growth Markers").map(
		func(e: Variant) -> String: return "growth_%s" % str((e as Dictionary)["name"]).to_snake_case())
	var held := 0
	for k in keys:
		held += int(gu.unit_properties.get(k, 0))
	var count := int(d.get("growth_markers", 0))
	if count == held:
		return
	if keys.size() != 1:
		push_error("CoreActivation.land_delta: %s holds %d Growth markers in the core (table %d) but carries %d Growth Markers rules" % [
			gu.get_name(), count, held, keys.size()])
		return
	main._sync_unit_property(gu, keys[0], count)


## C-15: the once buffs the core SPENT in this activation (the delta's `buffs_spent`: per record its name and scope; the core's own
## morale / hit / defense / grant spends, Great Banner and Regeneration grant rules included). The core is the authority: each named
## once-record of the table (same spell, scope, duration "once") is spent with the table's own spend (`_solo_spend_records`: its record,
## token, log line, wire message); a record the table no longer holds is no news. This replaces the table's own spend after a volley
## and after the morale die (P4.0-4b / -4c), which picked the records by role and knew no grant. From epoch 81 the core keeps a
## once morale buff through a Shaken unit's auto-failed test, as the table does (#2804).
static func _land_buffs(main, gu: GameUnit, d: Dictionary) -> void:
	# One spend for the whole delta: records of the same spell stacked on the unit (a cast that was not used up in an earlier round) are
	# all spent by the core's exchange; the table says that once (`_solo_spend_records` dedupes the sentence), not once per record.
	var spend: Array = []
	var pool: Array = (main._solo_spell_mods.get(gu.get_instance_id(), []) as Array).duplicate()
	for e in d.get("buffs_spent", []):
		var hit: Array = pool.filter(func(rd: Variant) -> bool: return str((rd as Dictionary).get("spell", "")) == str(e[0]) \
			and str((rd as Dictionary).get("scope", "")) == str(e[1]) and str((rd as Dictionary).get("duration", "")) == "once")
		if not hit.is_empty():
			spend.append(hit[0])
			pool.erase(hit[0])   # equal records are interchangeable: the next entry takes the next one
	main._solo_spend_records(gu, spend)


## Landing lane (PLAN H): the once-records the TABLE placed between the capture and the core's call are not on the board the core
## captured: the table's pre-attack beat block (a Furious Buff on a friend, a Shred / Slayer / Indirect / Quick Shot / Increased Shooting
## Range Mark on the foe) runs first, the core resolves its own copy of the beat and spends it, and the delta cannot name the table's record
## (`buffs_spent` diffs against the capture's ledger). Without this the record stays stale and the table's `"X" on U is consumed` line is
## never said. WORKS ONLY on records the capture did not hold (`_once_seen`, by signature), so the core stays the authority on every
## record it knew (`_land_buffs`), and spends them with the table's own exchange spend (`_solo_spend_once_mods`: its roles, scope, log line,
## wire message). Test seam: false = the old behaviour.
static var land_late_once := true
## The once-records the table held when handle `h` was captured: {"h": h, "mods": {unit instance id: [record signature, ...]}}.
static var _once_seen := {"h": 0, "mods": {}}


## A once-record's identity for the capture compare: its fields without the Regeneration grant's `used` flag, which flips with the exchange.
static func _rec_sig(rd: Dictionary) -> String:
	var c := rd.duplicate()
	c.erase("used")
	return JSON.stringify(c, "", true)


static func _once_sigs(main) -> Dictionary:
	var out := {}
	for key in main._solo_spell_mods:
		var sigs: Array = []
		for rd in main._solo_spell_mods[key]:
			if str((rd as Dictionary).get("duration", "")) == "once":
				sigs.append(_rec_sig(rd))
		if not sigs.is_empty():
			out[key] = sigs
	return out


## After a core-resolved exchange of `attacker` at `targets` (the capture is handle `h`): spend the table's once-records this exchange
## would spend (the attacker chain's own / grant / range, the defenders' vs_target / defense / grants) that the capture did not hold.
## `skip` names records a cast placed (the cast lane's `buffs_gained` / `buffs_spent` own them).
static func land_late_once_records(main, h: int, attacker: GameUnit, targets: Array, skip: Array = []) -> void:
	if not land_late_once or h == 0 or int(_once_seen["h"]) != h:
		return
	var sides: Array = [[attacker, ["attacker_own", "grant", "range"]]]
	for t in targets:
		sides.append([t, ["vs_target", "defense", "grant", "grant_vs"]])
	for side in sides:
		var unit := side[0] as GameUnit
		if unit == null:
			continue
		for u in [unit, unit.get_attached_to() if unit.has_method("get_attached_to") else null]:
			var uu := u as GameUnit
			if uu == null:
				continue
			var known: Array = ((_once_seen["mods"] as Dictionary).get(uu.get_instance_id(), []) as Array).duplicate()
			var late: Array = []
			for rd in main._solo_spell_mods.get(uu.get_instance_id(), []):
				if str((rd as Dictionary).get("duration", "")) != "once":
					continue
				var at := known.find(_rec_sig(rd))
				if at >= 0:
					known.remove_at(at)
				elif not skip.has(str((rd as Dictionary).get("spell", ""))):
					late.append(rd)
			if not late.is_empty():
				main._solo_spend_once_mods(uu, side[1], false, "", unit == attacker, late)


## Landing lane (PLAN H, `EPOCH_94_PARITY_BATCH`): the melee-scoped Marks (Rapid Charge, Piercing Fighting) a core volley placed on the marked unit and left
## standing (the delta's `marks_left`: record name, scope, granted rule). After a volley the table keeps such a record for a later charger (`_solo_apply_vs_marks` records
## it on the target and the volley's spend skips a melee-scoped record); the door never ran that seam, so the record is landed here, with the table's own writer and
## silently (the core already said the pick and the `... is ACTIVE` line). A record the table holds already (its own pre-attack beat placed it) is no news: only the
## difference in count lands.
static func _land_marks_left(main, gu: GameUnit, d: Dictionary) -> void:
	var left := {}   # "name|scope" -> [count, grant]
	for e in d.get("marks_left", []):
		var key := "%s|%s" % [e[0], e[1]]
		left[key] = [int((left.get(key, [0, ""]) as Array)[0]) + 1, str(e[2])]
	for key in left:
		var parts: PackedStringArray = str(key).split("|")
		var held: int = (main._solo_spell_mods.get(gu.get_instance_id(), []) as Array).filter(func(rd: Variant) -> bool:
			return str((rd as Dictionary).get("spell", "")) == parts[0] and str((rd as Dictionary).get("scope", "")) == parts[1] \
				and str((rd as Dictionary).get("duration", "")) == "once").size()
		for _i in int(left[key][0]) - held:
			main._solo_record_spell_mod(gu, parts[0], {"grants_rule": left[key][1], "scope": parts[1], "beneficiary": "attackers",
				"duration": "once", "no_live_grant": true, "quiet": true})


## CC-12a (CC-8c's `buffs_gained`): the buff / debuff effects this activation's casts landed on the unit and left standing
## (spell names, placement order). The planned cast with that name and this unit among its targets lands from the table's own
## spell entry (`land_cast_effect`), unless the cast presentation landed it already (no news). A name no planned cast explains is a
## core/table split: reported, nothing written. A record placed and spent in the same activation is not named (it is in
## `buffs_spent`; the table placed it at the cast and `_land_buffs` spends it).
static func _land_spell_buffs(main, gu: GameUnit, d: Dictionary, done: Dictionary) -> void:
	var cx: Dictionary = done.get("cx", {})
	for name in d.get("buffs_gained", []):
		var idx := -1
		for i in (cx.get("casts", []) as Array).size():
			var c: Dictionary = cx["casts"][i]
			if str(c.get("name", "")) == str(name) and (c.get("targets", []) as Array).has(gu) \
					and (idx < 0 or not (cx["landed"] as Dictionary).has(i) and (cx["landed"] as Dictionary).has(idx)):
				idx = i
		if idx < 0:
			push_error("CoreActivation.land_delta: the core landed %s on %s, no planned cast explains it" % [name, gu.get_name()])
			continue
		land_cast_effect(main, cx, idx)


## P4.D-38a: the once-per-game feat latches the core SPENT in this activation (the delta's `feats_used`, inventory row of the
## same name). The core spent them in its own copy; the table's flag is what its own roll and the next capture read. Closed for
## the ignore feats (the Protection Feat family) and, the same follow-up, the once-per-game shot feats the table's own
## `_solo_spend_shot_feats` spends (main.gd), each with that writer's flag and sentence; any other name is a core/table split
## nobody mapped yet (reported).
static func _land_feats(main, gu: GameUnit, d: Dictionary) -> void:
	for name in d.get("feats_used", []):
		if ignore_feats_of(gu).has(str(name)):
			if bool(gu.unit_properties.get(_ignore_flag(str(name)), false)):
				continue
			main._sync_unit_property(gu, _ignore_flag(str(name)), true)
			main._log_rule_event(BattleLog.Category.COMBAT, "%s: %s spends its once-per-game ignore roll" % [name, gu.get_name()], true)
			continue
		if shot_feats_of(gu).has(str(name)):
			var flag := SoloController.shot_feat_flag(str(name))
			if bool(gu.unit_properties.get(flag, false)):
				continue
			main._sync_unit_property(gu, flag, true)
			main._log_rule_event(BattleLog.Category.COMBAT, "%s: %s spends its once-per-game feat on this attack" % [name, gu.get_name()], true)
			continue
		# Coverage ledger m2 (gf_811): the once-per-game Takedown bonus attack (Takedown Shot / Strike) closes the table's own latch
		# (main.gd `_solo_takedown_bonus_groups`, raw rule name); the core's volley already named the extra attack, so no second line.
		if takedown_feats_of(gu).has(str(name)):
			main._sync_unit_property(gu, "takedown_bonus_used_%s" % str(name), true)
			continue
		push_error("CoreActivation.land_delta: %s spent the feat %s, which no table flag closes yet" % [gu.get_name(), name])


## P4.0-4g: the latched Versatile pick the delta now carries (inventory class (a)). The table holds it as the
## Dictionary `versatile_pick` (`{"hit_mod": int, "ap": int}`), the shape the old path's own writer stores, so the
## core's int mode maps onto it. A difference is a core/table split (reported); mode 0 means "no pick", nothing lands.
static func _land_versatile_mode(main, gu: GameUnit, d: Dictionary) -> void:
	var mode := int(d.get("versatile_pick_mode", 0))
	if mode == 0:
		return
	var vm := {"hit_mod": 1, "ap": 0} if mode == 1 else {"hit_mod": 0, "ap": 1}
	var was: Dictionary = gu.unit_properties.get("versatile_pick", {})
	if was == vm:
		return
	# The table's latch counts only in the round it was written (`_solo_versatile_latch_read`): a core-resolved volley never ran the table's
	# pick, so an empty or older latch is no table pick to differ from - the core is the first writer this round.
	if int(gu.unit_properties.get("versatile_pick_round", -1)) == int(main.opr_army_manager.current_round):
		stamp_splits += 1
		push_error("CoreActivation.land_delta: %s.versatile_pick differs (table %s, core %s)" % [gu.get_name(), str(was), str(vm)])
	main._sync_unit_property(gu, "versatile_pick", vm)


## P4.0-4e: the `State` field names whose table property is spelled differently (every other stamp is 1:1).
const STAMP_KEYS := {"spot_round": "spotted_round", "growth_strike_round": "regenerative_strength_round"}


## HR-POS: how many stamp differences `_land_stamps` reported (a test reads it; each is also a push_error).
static var stamp_splits := 0


## P4.0-4e: the per-unit once-per-round stamps the delta now carries (inventory class (a)). The table's own writer
## owns each on this path, so a difference is a core/table split (reported) and the core's value lands, as `shaken` does.
static func _land_stamps(main, gu: GameUnit, d: Dictionary) -> void:
	for key in d.get("stamps", {}):
		var prop := str(STAMP_KEYS.get(key, key))
		var value := int(d["stamps"][key])
		var was := int(gu.unit_properties.get(prop, -1))
		if value == was:
			continue
		# On a core-resolved charge, the table never ran `_solo_melee_strike_phase`, so the core is the first writer
		# of melee-only once-per-round stamps (`growth_strike_round` -> `regenerative_strength_round`).
		var first_pick: bool = key == "versatile_pick_round" and value == int(main.opr_army_manager.current_round) and was < value   # the core latched this round, the table did not (see `_land_versatile_mode`)
		# H-8: likewise the core is the first writer of the push stamp when the beats guard held Mind Control.
		if not (_charge_landing and key == "growth_strike_round") and not first_pick and not (_beat_actor != null and key == "mind_control_moved_round"):
			stamp_splits += 1
			push_error("CoreActivation.land_delta: %s.%s differs (table %d, core %d)" % [gu.get_name(), prop, was, value])
		main._sync_unit_property(gu, prop, value)


## P4.0-4f: the marker pools the delta now carries (inventory class (a)). Every name is the table's own property
## name and an absent pool reads 0, so a difference is a core/table split (reported) and the core's count lands.
static func _land_pools(main, gu: GameUnit, d: Dictionary) -> void:
	for key in d.get("pools", {}):
		var value := int(d["pools"][key])
		var was := int(gu.unit_properties.get(key, 0))
		if value == was:
			continue
		push_error("CoreActivation.land_delta: %s.%s differs (table %d, core %d)" % [gu.get_name(), key, was, value])
		main._sync_unit_property(gu, key, value)


## C-12: the two Piercing-Tag latches the delta now carries (inventory rows of the same names). The bearer's
## once-per-game `piercing_tag_used` is a bool on both sides; the target's standing pool the table keeps as the
## NAME that placed it (`piercing_tag_source`): only "Piercing Target" stands, so the core's bool maps onto that
## name. A difference is a core/table split (reported) and the core's value lands, as the pools do.
static func _land_piercing(main, gu: GameUnit, d: Dictionary) -> void:
	var used := bool(d.get("piercing_tag_used", false))
	var was_used := bool(gu.unit_properties.get("piercing_tag_used", false))
	if used != was_used:
		push_error("CoreActivation.land_delta: %s.piercing_tag_used differs (table %s, core %s)" % [gu.get_name(), was_used, used])
		main._sync_unit_property(gu, "piercing_tag_used", used)
	var standing := bool(d.get("piercing_tag_persistent", false))
	var source := str(gu.unit_properties.get("piercing_tag_source", ""))
	if standing == (source == "Piercing Target"):
		return
	var core_source := "Piercing Target" if standing else ""
	push_error("CoreActivation.land_delta: %s.piercing_tag_source differs (table %s, core %s)" % [gu.get_name(), source, core_source])
	main._sync_unit_property(gu, "piercing_tag_source", core_source)


## D19 (a): the unit's once-per-game Surprise Attack latch after the activation (the delta's `surprise_attack_used`). The core
## fires the burst at the activation trigger from its own copy (`sim.rs`, `tray_surprise_attack`), so on this path it is the
## first writer for a bearer the table's beat did not reach. It lands with the writer that beat uses (`_sync_unit_property`,
## MP-synced), which stamps BEFORE the candidate search: a bearer with no target in range burns the latch too. Monotone, like
## the table's own latch: a `false` row never re-opens a once-per-game burst the table already spent.
static func _land_surprise(main, gu: GameUnit, d: Dictionary) -> void:
	if not bool(d.get("surprise_attack_used", false)) or bool(gu.unit_properties.get("surprise_attack_used", false)):
		return
	main._sync_unit_property(gu, "surprise_attack_used", true)


## The delta's rows without a spell-token count the core did not change. The table owns the tokens: a human cast pays
## them on the table after the activation's capture (the Start comes first), so the core's row still carries the
## captured count, and landing it handed a paid cast's tokens back at the End (cast or failed alike). A count the core
## changed itself (its own casts) still lands. The rows are copied, never edited: the caller's answer stays as given.
static func _tokens_the_core_changed(core: Object, h: int, delta: Array) -> Array:
	var before: Dictionary = core.plain_of(h).get("units", {}) if h != 0 else {}
	var out: Array = []
	for d in delta:
		var row: Dictionary = d
		var was: Variant = (before.get(str(row.get("unit", "")), {}) as Dictionary).get("casts")
		if row.has("casts") and was != null and int(was) == int(row["casts"]):
			row = row.duplicate()
			row.erase("casts")
		out.append(row)
	return out


## P4.0-4d: the table-owned per-activation ledger the delta now carries (inventory class (a)): the fatigue flag and the
## unspent spell tokens. A plain activation changes neither and the table's own writer owns both, so a difference is a
## core/table split (reported); the core's value lands either way, as `shaken` does.
static func _land_ledger(main, gu: GameUnit, d: Dictionary) -> void:
	if d.has("fatigued") and bool(d["fatigued"]) != gu.is_fatigued:
		# P4.D-48: the fight's fatigue is the core's outcome, not a split; H-8: so is the fatigue a held beat (Fatigue Debuff) put on
		# another unit than the actor.
		if not _charge_landing and not (_beat_actor != null and gu != _beat_actor and bool(d["fatigued"])):
			push_error("CoreActivation.land_delta: %s fatigue differs (table %s, core %s)" % [
				gu.get_name(), gu.is_fatigued, bool(d["fatigued"])])
		if main.radial_menu_controller != null:
			main.radial_menu_controller.card_toggle_fatigued(gu)
	if d.has("casts") and int(d["casts"]) != gu.casts_current:
		push_error("CoreActivation.land_delta: %s casts differ (table %d, core %d)" % [
			gu.get_name(), gu.casts_current, int(d["casts"])])
		gu.set_caster_points(int(d["casts"]))
		if main.network_manager != null and main.network_manager.has_method("broadcast_unit_casts"):
			main.network_manager.broadcast_unit_casts(gu)


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
		"start_rot": start_rot, "start_own": start_own, "dice": false, "cast": false,
		"journal": _journal_records(main).merged({"props": _journal_props(main)}), "moved_before": {},
		"ledger_mark": main.move_trails.ledger.entries.size() if main.move_trails != null else 0}
	if gu.unit_properties.has("moved_round"):
		s["moved_round_before"] = gu.unit_properties["moved_round"]
	for u in [gu] + gu.get_attached_heroes():   # step 32: each moved_round before the Start (null = none), for the reset
		s["moved_before"][u.unit_id] = u.unit_properties.get("moved_round")
	_sessions[gu.unit_id] = s
	if main.save_manager != null:
		main.save_manager.note_activation_start(gu.get_name())   # P4.0-7 (D5): what a mid-step save stores
	last_target = null   # step 50: a new activation never inherits the target of a cancelled one
	# Step 31 (O1/O2): every activation of a move-path unit starts on Advance - unless the player pressed Rush or Charge
	# for this very unit before its Start: that press is the declaration, and resetting it refused a Rush drag at 6".
	var picked: bool = str(main.get("_movement_cap_picked_for")) == gu.unit_id \
		and int(main.object_manager._movement_cap) in [CAP_RUSH, CAP_CHARGE]
	if on_move_path(main, gu) and not picked:
		main.object_manager.set_movement_cap(CAP_ADVANCE)
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
	var pm: Dictionary = (_sessions[gu.unit_id] as Dictionary).get("post_melee", {})
	if not pm.is_empty():   # the move after a melee drags on its own allowance (begin_post_melee_move)
		return {"advance": int(pm["in"]), "rush": int(pm["in"]), "charge": int(pm["in"])}
	var a: Dictionary = core.move_allowance(int(_sessions[gu.unit_id]["handle"]), gu.unit_id) if core != null else {}
	if a.is_empty():
		return {}
	return {"advance": a["advance"], "rush": a["rush"], "charge": a["charge"]}


## Ticket 12 (DRAG-BAND-DIFFICULT): does the core's drop check hold `gu`'s move to the 6" Difficult cap, for the walked
## trails (`now`: the drag in flight, ObjectManager.drag_paths(); a model in it stands at its path's end, every other one
## where it stands now)? The core's own test
## (`move_difficult`), so the drag band and the drop's refusal never disagree. -1 = not on the core move path: the caller's
## own check applies; 0 / 1 = the core's answer.
static func drag_difficult(main, gu: GameUnit, now: Dictionary) -> int:
	if gu == null or not _sessions.has(gu.unit_id) or not on_move_path(main, gu):
		return -1
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	if core == null:
		return -1
	var at: Array = gu.get_alive_models().map(func(m: ModelInstance) -> Vector3:
		var p: Variant = now.get(int(m.node.get_meta("network_id", 0)))
		return Vector3(p[-1].x, 0.0, p[-1].y) if p != null else main.object_manager.resting_position(m.node))
	var r: Dictionary = core.move_difficult(int(_sessions[gu.unit_id]["handle"]), gu.unit_id,
		{"positions": PackedVector3Array(at), "trails": session_trails(main, gu, now)})
	if not bool(r.get("ok", false)):
		push_error("drag_difficult: the core answered %s for %s" % [r, gu.get_name()])
		return -1
	return 1 if bool(r["difficult"]) else 0


## Whether `unit_id`'s activation is open (Started and not yet ended or cancelled).
static func session_open(unit_id: String) -> bool:
	return _sessions.has(unit_id)


## Plan step 27-pre P3: whether the core listed a jump for `unit_id`'s current placement - it sees that ledge and rolls the
## jump when the activation resolves (`place` records it from the drop check's "jump" lines).
static func core_sees_jump(unit_id: String) -> bool:
	return _sessions.has(unit_id) and bool((_sessions[unit_id] as Dictionary).get("core_jump", false))


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
	_free_fall_ring(_sessions[unit_id])
	_sessions.erase(unit_id)
	if main != null and str(main.get("_movement_cap_picked_for")) == unit_id:
		main.set("_movement_cap_picked_for", "")   # a mode pressed in this activation is not the next one's declaration
	if main != null and main.save_manager != null:
		main.save_manager.note_activation_end()   # P4.0-7 (D5): an ended activation saves as the table stands
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
	var pm: Dictionary = (_sessions.get(gu.unit_id, {}) as Dictionary).get("post_melee", {})
	if not pm.is_empty():
		return _post_melee_refused(main, gu, pm)
	var mode := declared_mode(main)
	if mode == 0:
		return false   # declared_mode reported the defect
	var r := place(main, gu, mode, main.object_manager.drag_paths())
	if r.is_empty() or bool(r.get("ok", false)):
		return false
	main._log_rule_event(BattleLog.Category.MOVEMENT, str(r.get("reason", "")))
	main._show_toast(str(r.get("reason", "")))
	return true


## The move after a melee (Consolidation Moves, GF / AoF Advanced Rules v3.5.1): when neither unit was destroyed the
## charger moves back 1", when the enemy was destroyed the survivor may move up to 3". It is a movement of its own, so the
## charge's distance does not count against it: from here on the drops of `gu`'s open activation are checked against
## `allowance_in` from where its models stand now, and its drag band is that allowance. `label` names it in the refusal.
## A unit without an open activation (a defender) has nothing to check: a no-op.
static func begin_post_melee_move(main, gu: GameUnit, allowance_in: float, label: String) -> void:
	if gu == null or not _sessions.has(gu.unit_id):
		return
	var from := {}   # model id -> where it stood when the melee ended (XZ)
	for m in gu.get_alive_models():
		from[int(m.node.get_meta("network_id", 0))] = Vector2(m.node.global_position.x, m.node.global_position.z)
	_sessions[gu.unit_id]["post_melee"] = {"in": allowance_in, "label": label, "from": from,
		"mark": main.move_trails.ledger.entries.size() if main.move_trails != null else 0}


## The drop check of a post-melee move (`begin_post_melee_move`): each model's walk since the melee ended (its drops in the
## ledger plus the drag in flight; a model with no recorded walk counts its straight distance) against the allowance. Over
## it: the line is logged; with Enforce Movement Limit on it is toasted and the drop refused (true), off it stands.
static func _post_melee_refused(main, gu: GameUnit, pm: Dictionary) -> bool:
	var length_in := func(p: PackedVector2Array) -> float:
		var d := 0.0
		for i in range(1, p.size()):
			d += p[i - 1].distance_to(p[i])
		return d * METERS_TO_INCHES
	var walked := {}   # model id -> inches walked since the melee ended
	var entries: Array = main.move_trails.ledger.entries if main.move_trails != null else []
	for i in range(mini(int(pm["mark"]), entries.size()), entries.size()):
		if str(entries[i]["unit"]) == gu.unit_id:
			var id := int(entries[i]["model"])
			walked[id] = float(walked.get(id, 0.0)) + float(length_in.call(entries[i]["points"]))
	var now: Dictionary = main.object_manager.drag_paths()
	var x := 0.0
	for m in gu.get_alive_models():
		var id := int(m.node.get_meta("network_id", 0))
		var w: float = float(walked.get(id, 0.0)) + (float(length_in.call(now[id])) if now.has(id) else 0.0)
		if w == 0.0 and (pm["from"] as Dictionary).has(id):
			w = (pm["from"][id] as Vector2).distance_to(Vector2(m.node.global_position.x, m.node.global_position.z)) * METERS_TO_INCHES
		x = maxf(x, w)
	var y := float(pm["in"])
	if x <= y + 0.01:
		return false
	var text := "%s: a model moved %.1f\" - the %s allowance is %.1f\"." % [gu.get_name(), x, str(pm["label"]), y]
	main._log_rule_event(BattleLog.Category.MOVEMENT, text)
	if not main.object_manager._strict_movement_enforced():
		return false   # the escape hatch: the overrun is named, the drop stands
	main._show_toast(text)
	return true


## The core's drop check of `gu`'s placement (an open session): every alive model where it stands now, at `mode`, with the walked
## trails (`now`: the drag in flight, ObjectManager.drag_paths()). The core's answer: ok = the placement replaces the
## session's one and its lines are written; not ok = nothing changes (the caller says why). {} = no core: reported, unchecked.
static func place(main, gu: GameUnit, mode: int, now: Dictionary) -> Dictionary:
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	if core == null:
		push_error("drop_refused: no core for %s's open activation - the drop is not checked" % gu.get_name())
		return {}
	var s: Dictionary = _sessions[gu.unit_id]
	var at: Array = gu.get_alive_models().map(func(m: ModelInstance) -> Vector3: return main.object_manager.resting_position(m.node))   # step 69b: no drag lift
	var trails := session_trails(main, gu, now)   # step 66 (MOVE_GAPS 5)
	var r: Dictionary = core.check_move(int(s["handle"]), gu.unit_id,
		{"mode": mode, "positions": PackedVector3Array(at), "trails": trails}, main.object_manager._strict_movement_enforced())
	if not bool(r.get("ok", false)):
		return r
	s["transcript"] = (s["transcript"] as Array).filter(func(e: Dictionary) -> bool: return str(e["t"]) != "placed") \
		+ [{"t": "placed", "positions": at, "trails": trails}]
	# Plan step 27-pre P3: the core listed a jump for this placement, so it rolls it when the activation resolves
	s["core_jump"] = (r.get("lines", []) as Array).any(func(l: Dictionary) -> bool: return str(l.get("rule", "")) == "jump")
	if CoreSlice.carries(gu, ["Strafing"]) and not table_struck(gu):   # P4.D-37c: sticky for the activation (one strike, one resolver)
		var from: Dictionary = {}
		for e in s["start_models"]:
			from[e["model"]] = e["at"]
		var alive: Array = gu.get_alive_models()
		s["table_strike"] = not crossed_plain(main, gu, range(at.size()).map(func(i: int) -> Array: return [from.get(alive[i], at[i]), at[i]]), true)
	for line in r.get("lines", []):
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(line["text"]), false, str(line["detail"]))
	return r


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
		var end: Vector2 = (now[id] as PackedVector2Array)[-1] if now.has(id) else Vector2(m.node.global_position.x, m.node.global_position.z)
		out.append(_unbroken(paths, begun.get(m, Vector2.INF), end))   # a drag path ends where its model stands (ticket 12: or will)
	return out


## `paths` joined end to start (each join point once) when the first starts at `start`, each starts where the one before
## ended and the last ends at `end`, all within the core's 0.01" trail tolerance; else an empty path.
static func _unbroken(paths: Array, start: Vector2, end: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tol := 0.01 / METERS_TO_INCHES
	for p: PackedVector2Array in paths:
		if p.size() < 2 or (out[out.size() - 1] if not out.is_empty() else start).distance_to(p[0]) > tol:
			return PackedVector2Array()
		out.append_array(p if out.is_empty() else p.slice(1))
	return out if not out.is_empty() and out[out.size() - 1].distance_to(end) <= tol else PackedVector2Array()


## Step 31: the declared movement mode for the core, read from the selector and never from distance: Advance 1, Rush 2,
## Charge 3 (the core's kinds, sim.rs). Anything else is a defect: reported, and 0 means no core call.
static func declared_mode(main) -> int:
	match int(main.object_manager._movement_cap):
		CAP_ADVANCE:
			return 1
		CAP_RUSH:
			return 2
		CAP_CHARGE:
			return 3
	push_error("declared_mode: the movement selector is %d - not Advance, Rush or Charge" % int(main.object_manager._movement_cap))
	return 0


## Why the core refused the last Auto shot's placement ("" = it did not, or the reason is the door's own).
static var auto_refused := ""


## True when this activation already resolved a spell: the core's capture is from the Start, before the table's cast,
## so its board holds no spell effect: the door refuses the volley and the player rolls it freely.
static func cast_this_activation(gu: GameUnit) -> bool:
	return gu != null and bool((_sessions.get(gu.unit_id, {}) as Dictionary).get("cast", false))


## Records that `gu`'s activation resolved a spell; called by the human cast path once the spell is over. A unit
## without an open session has nothing to mark.
static func note_cast(gu: GameUnit) -> void:
	if gu != null and _sessions.has(gu.unit_id):
		(_sessions[gu.unit_id] as Dictionary)["cast"] = true


## One line that names why a volley of this activation is a free roll after a cast; true = the door refuses it.
static func refuses_after_cast(main, attacker: GameUnit) -> bool:
	if not cast_this_activation(attacker):
		return false
	main._log_rule_event(BattleLog.Category.COMBAT,
		"%s already cast a spell this activation - its volley is a free roll (cast_this_activation)" % attacker.get_name())
	return true


## Step 38 (O15 (1)): the human attack door. False = not taken, the old path runs: `attacker` is not a core unit, the
## target is not plain (`is_plain_target`) or the table already struck. True =
## taken. No open activation: "Activate <Unit> first.", nothing rolls. A Charge selector (a melee action) and no
## declaration (declared_mode still reports the defect) are refused: one toast says why, nothing was shot, the session
## stays open (the caller returns). Else the declared intent (the selector's mode,
## never the distance; the core turns it into Hold when nothing moved) and the shot go through the core with the
## session's transcript; the session's own transcript is not touched, so a refusal can be tried again. `done`: the steps
## have landed and `last_target` is noted for step 50; the session stays open until the door ENDS the activation (the
## toggle that completes a shot ends it only while the session is open - with none, "Activate" would start a new one),
## and the door closes it after. `refused` below the transcript's size (an order rule, the O3 Rush sentence): logged and
## toasted, nothing was shot, the session stays open (the caller returns then). `refused` at the transcript's size is the
## core's own defect: reported, nothing toasted, the session stays open. `auto` (the Auto verbs' shot after the
## engine's own move): the unit's end positions reach the core first through `place`, the same check a dropped drag gets,
## and the transcript says the engine paid the move's Dangerous test; a placement or a shot the core refuses is not taken,
## its reason in `auto_refused` (the caller's free roll names it). P4.D-13c: a target with no statline is no valid
## target: one line, nothing shot, the session stays open (the caller returns).
static func human_shoot(main, attacker: GameUnit, target: GameUnit, on_throw: Callable = Callable(), auto := false) -> bool:
	auto_refused = ""
	if refuses_statlineless(main, attacker, target):
		return true   # nothing was shot: `last_target` is not the target, the caller returns and the activation stays open
	if not is_core_unit(main, attacker) or not is_plain_target_human(target) or table_struck(attacker):
		return false
	if refuses_after_cast(main, attacker):
		return false
	if main.core_door_refused(attacker):
		return true
	if int(main.object_manager._movement_cap) == CAP_CHARGE:
		main._show_toast("Charge is a melee action - pick Advance or Hold to shoot.")
		return true   # nothing was shot: the caller returns and the activation stays open
	var mode := declared_mode(main)
	var s: Dictionary = _sessions.get(attacker.unit_id, {})
	if mode == 0:
		main._show_toast("Pick a movement mode before shooting.")
		return true   # declared_mode reported the defect; nothing was shot, the caller returns
	if s.is_empty():
		push_error("human_shoot: %s has no session after the door let it through" % attacker.get_name())
		return true
	if auto:
		var p := place(main, attacker, mode, {})
		if not bool(p.get("ok", false)) or table_struck(attacker):
			auto_refused = str(p.get("reason", "")) if not p.is_empty() and not bool(p.get("ok", false)) else ""
			return false   # the core cannot take the Auto move: the caller's free roll says why
	var t: Array = (s["transcript"] as Array).duplicate()
	if auto:   # the engine rolled the Auto move's Dangerous test (`_run_player_intent`), so the core does not roll it again
		t.insert(1, {"t": "paid", "start": false, "dangerous": true, "beats": false})
	t.append({"t": "intent", "kind": mode, "shoot": target.unit_id, "no_step": true})   # step 21: the player drags a Hit & Run step
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
	elif str(r["step"]) == "refused" and int(r["index"]) < t.size() and auto:
		auto_refused = str(r["reason"])   # the engine already ran the Auto verb, so its refused shot is the free roll, never a stuck activation
		return false
	elif str(r["step"]) == "refused" and int(r["index"]) < t.size():
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(r["reason"]))
		main._show_toast(str(r["reason"]))
	else:
		push_error("human_shoot: the core answered %s for %s's shot" % [r, attacker.get_name()])
	return true


## P4.D-43a: the human's declared split through the core. `b_names` = the weapons the player sent at `target_b`; the
## table's `_run_human_attack_split` fires the rest at `target_a`. False = not taken, the table resolves the split (an
## aim the core would pool, a target whose owner has a wound-allocation choice, or BOTH groups with nothing to fire). One
## group with nothing to fire is no split: the other group fires alone through `human_shoot` at its target and its answer
## is this door's. True =
## the core took it: `last_target` is `target_a` when the split resolved (a refusal leaves it null and the session open,
## the caller returns). The caller does the table's side effects (the declared line, `shot_round`,
## `human_attack_resolved`, `_solo_complete_human_attack`) and closes the session.
static func human_shoot_split(main, attacker: GameUnit, target_a: GameUnit, target_b: GameUnit, b_names: Array) -> bool:
	if not is_core_unit(main, attacker) or not is_plain_target_human(target_a) or not is_plain_target_human(target_b) \
			or int(main.object_manager._movement_cap) == CAP_CHARGE or table_struck(attacker):
		return false
	if refuses_after_cast(main, attacker):
		return false
	if main.core_door_refused(attacker):
		return true
	var mode := declared_mode(main)
	var s: Dictionary = _sessions.get(attacker.unit_id, {})
	if mode == 0:
		return false
	if s.is_empty():
		push_error("human_shoot_split: %s has no session after the door let it through" % attacker.get_name())
		return true
	var parts: Array = [
		{"target": target_a, "shots": _human_shots(main, attacker, target_a).filter(
			func(sh: Dictionary) -> bool: return not b_names.has(str((sh["profile"] as Dictionary).get("name", ""))))},
		{"target": target_b, "shots": _human_shots(main, attacker, target_b).filter(
			func(sh: Dictionary) -> bool: return b_names.has(str((sh["profile"] as Dictionary).get("name", ""))))}]
	if (parts[0]["shots"] as Array).is_empty() and (parts[1]["shots"] as Array).is_empty():
		return false   # both groups have nothing to fire: the table's own "no volley" line
	if (parts[0]["shots"] as Array).is_empty() or (parts[1]["shots"] as Array).is_empty():
		var alone: Dictionary = parts[1] if (parts[0]["shots"] as Array).is_empty() else parts[0]
		return await human_shoot(main, attacker, alone["target"] as GameUnit)
	var aim := split_aim(parts)
	if aim.is_empty() or _aim_ambiguous(aim):
		return false
	var chooser: Array = [] if choice_enabled("wound_alloc") else parts.filter(
		func(p: Dictionary) -> bool: return main._solo_wound_choice_matters(p["target"], 1))
	if not chooser.is_empty():
		main._log_rule_event(BattleLog.Category.COMBAT, "%s: %s's owner chooses the casualties - the table resolves this split" % [
			attacker.get_name(), chooser[0]["target"].get_name()], true)
		return false
	var t: Array = (s["transcript"] as Array).duplicate()
	t.append({"t": "intent", "kind": mode, "shoot": target_a.unit_id, "split": aim, "no_step": true})
	var sts: Array = parts.map(func(p: Dictionary) -> Dictionary: return {"n": 0, "open": false, "result": false})
	var at := [0]
	var beat := func(ev: String, a: Dictionary, faces: Array) -> void:
		var g: Dictionary = parts[at[0]]
		var cur: Dictionary = sts[at[0]]
		if ev == "throw" and str(a.get("kind", "")) == "attack" and at[0] < parts.size() - 1 \
				and int(cur["n"]) >= (g["shots"] as Array).size():
			await _present_human(main, attacker, g["target"], g["shots"], cur, "done", {}, [])
			at[0] += 1
			g = parts[at[0]]
			cur = sts[at[0]]
			main._solo_stage_begin("%s fires at %s" % [attacker.get_name(), g["target"].get_name()])
		await _present_human(main, attacker, g["target"], g["shots"], cur, ev, a, faces)
	main._solo_stage_begin("%s fires at %s" % [attacker.get_name(), target_a.get_name()])
	var r: Dictionary = await drive(main, int(s["handle"]), attacker, t, false, Callable(), false, beat)
	if str(r["step"]) == "done":
		last_target = target_a
	elif str(r["step"]) == "refused" and int(r["index"]) < t.size():
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(r["reason"]))
		main._show_toast(str(r["reason"]))
	else:
		push_error("human_shoot_split: the core answered %s for %s's split" % [r, attacker.get_name()])
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
	if gu != null and _sessions.has(gu.unit_id) and (_sessions[gu.unit_id] as Dictionary).has("fall_replace"):
		return fall_lock(main, gu)
	if not is_core_unit(main, gu) or not _sessions.has(gu.unit_id) or last_target != null or table_struck(gu):
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
		return _sessions.has(gu.unit_id) and (_sessions[gu.unit_id] as Dictionary).has("fall_replace") and fall_lock(main, gu)
	if str(r["step"]) == "refused" and int(r["index"]) < t.size():
		main._log_rule_event(BattleLog.Category.MOVEMENT, str(r["reason"]))
		main._show_toast(str(r["reason"]))
	else:
		push_error("end: the core answered %s for the End of %s" % [r, gu.get_name()])
	return true


## Plan step 27c-2a (D-27c Q2): while a model of `gu` that fell stands more than 1 in from the others, End is locked with one
## line (true); once it does not, the state lifts and End ends the activation (false). The core's step is over - its jump was
## rolled once, in the End or the shot that made the model fall: nothing here drives it again.
static func fall_lock(main, gu: GameUnit) -> bool:
	var fell: ModelInstance = _sessions[gu.unit_id]["fall_replace"]
	if fall_replace_needed(main, gu, fell):
		var line := "Place the other models within 1 in of %s's model that fell" % gu.get_name()
		main._log_rule_event(BattleLog.Category.MOVEMENT, line)
		main._show_toast(line)
		return true
	(_sessions[gu.unit_id] as Dictionary).erase("fall_replace")
	return false   # the End goes on: the activation's close_session takes the ring off


## Plan step 27c-2b (D-27c Q1): the 1 in ring round the model that fell, drawn as the picked-target ring (solid, no pulse:
## its edge is the measure) sized to the model's base + 1 in; the owner drags the others into it, no modal.
static func _fall_ring(main, fell: ModelInstance) -> MeshInstance3D:
	var ring: MeshInstance3D = main._solo_spawn_picked_ring(fell.node.global_position)
	var r := SoloController.model_base_radius_m(fell) + 0.0254
	(ring.mesh as TorusMesh).inner_radius = r - 0.003
	(ring.mesh as TorusMesh).outer_radius = r + 0.003
	return ring


static func _free_fall_ring(s: Dictionary) -> void:
	var ring: Variant = s.get("fall_ring")
	if is_instance_valid(ring) and ring is Node:   # validity first: `is` on a freed instance raises
		(ring as Node).queue_free()
	s.erase("fall_ring")


## Plan step 27c-3 (D-27c Q2/Q3): the core's 1 in placer ("Place for me", ruling D14) for `gu` round its model `fell`, on the
## board as it stands: the positions land as a move (broadcast, as a push's) and the core's line is logged. False when the
## core had no answer; a placement nobody needed moves nothing and says nothing.
static func regroup(main, gu: GameUnit, fell: ModelInstance) -> bool:
	var alive := gu.get_alive_models()
	var slot := alive.find(fell)
	var h := capture(main) if slot >= 0 else 0
	if h == 0:
		return false
	var core: Object = (main.solo_controller as SoloController)._core_node_ready()
	var r: Dictionary = core.regroup_around(h, gu.unit_id, slot)
	core.release(h)
	if not bool(r.get("ok", false)):
		push_error("regroup: the core refused %s: %s" % [gu.get_name(), r.get("reason", "")])
		return false
	main.solo_controller._apply_model_positions(alive, r["positions"])
	if not str(r["line"]).is_empty():
		main._log_rule_event(BattleLog.Category.MOVEMENT, "%s: %s" % [gu.get_name(), r["line"]], main._solo_is_ai_unit(gu))
	return true


## The "Place for me" button of `gu`'s fall lock: the core places the others; the lock lifts at the next End.
static func place_for_me(main, gu: GameUnit) -> void:
	if fall_pending(gu.unit_id):
		regroup(main, gu, _sessions[gu.unit_id]["fall_replace"])
		_refresh_card(main)


## Does `unit_id`'s open activation wait for the others to stand within 1 in of a model that fell (27c-2a)? Only the table
## that runs the activation holds a session, so only the owner sees the lock and the button.
static func fall_pending(unit_id: String) -> bool:
	return _sessions.has(unit_id) and (_sessions[unit_id] as Dictionary).has("fall_replace")


## Does a model of `gu` stand more than 1 in from its model `fell`, on the board as it stands now (a fresh capture: the
## player re-places after the step)? The core measures (`NmlCore.fall_replace_needed`); false when `fell` died.
static func fall_replace_needed(main, gu: GameUnit, fell: ModelInstance) -> bool:
	var slot := gu.get_alive_models().find(fell)
	var h := capture(main) if slot >= 0 else 0
	if h == 0:
		return false
	var core: Object = (main.solo_controller as SoloController)._core_node_ready()
	var needed := bool(core.fall_replace_needed(h, gu.unit_id, slot))
	core.release(h)
	return needed


## The model of `gu` whose position the core's `to` moves (XZ, more than a millimetre), or null.
static func _moved_model(start_models: Array, gu: GameUnit, to: Array) -> ModelInstance:
	var rows: Array = start_models.filter(func(e: Dictionary) -> bool:
		return (e["model"] as ModelInstance).unit == gu and (e["model"] as ModelInstance).is_alive)
	for i in mini(rows.size(), to.size()):
		var at: Vector3 = rows[i]["at"]
		if Vector2(at.x - (to[i] as Vector3).x, at.z - (to[i] as Vector3).z).length() > 0.001:
			return rows[i]["model"]
	return null


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
	if main != null and main.save_manager != null:
		main.save_manager.note_activation_end()   # P4.0-7 (D5): a reset (a load) ends the activation on the save side too
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
		CoreShadow.release(main)   # C-3


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
## heroes), then the target's chain; a null target = the actor side only. Each unit once. CC-13c: `extra` = further units the
## activation touched (`cast_touched`), each with its own joined chain, after the target's.
static func touched_units(main, actor: GameUnit, target: GameUnit = null, extra: Array = []) -> Array:
	var out: Array = main._solo_joined_chain(actor)
	for gu in main._solo_joined_chain(target):
		if not out.has(gu):
			out.append(gu)
	for x in extra:
		for gu in main._solo_joined_chain(x as GameUnit):
			if not out.has(gu):
				out.append(gu)
	return out


## CC-13c: the units the core-resolved casts of a report touched beyond the actor's chain and the volley's target: every cast's
## targets (a spell's wounds, a buff's record land there) and the units that paid its boost / interference tokens (their counts
## moved), each once, in plan order. [] for a report without casts. Pure.
static func cast_touched(report: Dictionary) -> Array:
	var out: Array = []
	for c in report.get("casts", []):
		var cast := c as Dictionary
		var units: Array = (cast.get("targets", []) as Array).duplicate()
		for key in ["boost_sources", "interference_sources"]:
			for src in cast.get(key, []):
				units.append((src as Dictionary).get("unit"))
		for u in units:
			if u is GameUnit and not out.has(u):
				out.append(u)
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
static func announce(main, actor: GameUnit, target: GameUnit = null, extra: Array = []) -> void:
	var nm = main.network_manager
	if actor == null or not applies(main) or nm == null or not nm.is_multiplayer_active():
		return
	if not is_core_unit(main, actor) and not (main._solo_is_ai_unit(actor) and is_plain(actor)):
		return
	var round_no: int = main.opr_army_manager.current_round
	var touched := touched_units(main, actor, target, extra)
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

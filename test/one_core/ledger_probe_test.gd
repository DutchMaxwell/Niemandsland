extends GdUnitTestSuite
## One core C-9 (shadow-run prelude): does the LIVE `CoreActivation.capture` hand the table's between-activation ledger to the
## core, and does the core's AFTER come back? The inventory (docs/one_core/STATE_DELTA_INVENTORY.md) says "the live capture never
## sends the ledger"; the capture has sent it since its first version (`AiActRecorder._stamp_gate_reads` writes `ledger` into every
## unit), so the real questions are which fields the core then READS and which of its changes the delta CARRIES.
##
## Method (no landing in the IN and chain cases, so the core's answer is the whole result): one table property is flipped between
## two fresh live captures of the same board, one core volley each (fixed faces: every throw 6, every save 1), and the throws the
## core asks for are compared. A chain runs a second volley on the state the first one left (what the core remembers) against a
## second volley on a fresh capture (what the table would send next: its own, unchanged, property). The landing cases run
## `land_delta` (the real path) on the real delta and read the table's property afterwards.
## Real: the main scene, NmlCore, `CoreActivation.capture` / `land_delta`. Constructed: OPR units (ParityTable), properties written
## by hand. Every case prints one `LEDGER_PROBE` line (the table of the 22 fields is in the PR body).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
## The delta row of a unit, key for key (sorted): what the core hands back. A key added there is a field the landing must map.
const DELTA_KEYS := ["alive", "casts", "fatigued", "feats_used", "moved", "piercing_tag_persistent", "piercing_tag_used", "pools",
	"removed", "shaken", "stamps", "unit", "unknown", "versatile_pick_mode"]
## The round stamps the capture does NOT send (`_ledger_of` has no key for them), with the table property each is landed under.
const UNSENT_STAMPS := {"reckless_rolled_round": "reckless_rolled_round", "reckless_ap_round": "reckless_ap_round",
	"reckless_backfire_round": "reckless_backfire_round", "versatile_pick_round": "versatile_pick_round",
	"retreating_strike_round": "retreating_strike_round", "mind_control_moved_round": "mind_control_moved_round",
	"growth_strike_round": "regenerative_strength_round", "piercing_spot_round": "piercing_spot_round"}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true
	_main._solo_auto_saves = true
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## "Att" (10 rifles, player 2) and "Def" (`foe_models` models 12" away, player 1); the overrides change the units' side dicts.
func _pair(att_over := {}, foe_over := {}, foe_models := 20) -> Array:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0}).merged(att_over, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": foe_models, "x_in": 12.0}).merged(foe_over, true), {})
	return [att, foe]


func _add_weapon(gu: GameUnit, wname: String, count: int, rules: Array) -> void:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = 24
	w.attacks = 1
	w.count = count
	w.special_rules.assign(rules)
	(gu.source_data as OPRApiClient.OPRUnit).weapons.append(w)


## One core volley of `att` at `foe` on a fresh live capture (or on `handle`, a state an earlier volley left): the throws it asked
## ("kind xCount @target"), its log lines, its delta, and the state it left (`handle`, released by `_end`).
func _volley(att: GameUnit, foe: GameUnit, handle := 0) -> Dictionary:
	var core: Object = _main.solo_controller._core_node_ready()
	var h := handle if handle != 0 else CoreActivation.capture(_main)
	assert_int(h).override_failure_message("the live capture failed").is_not_equal(0)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
	var asks: Array = []
	var r: Dictionary = {}
	for _i in 64:
		r = core.step_activation(h, att.unit_id, t, false)
		if str(r["step"]) != "need_roll":
			break
		asks.append("%s x%d @%d" % [r["kind"], int(r["faces"]), int(r["target"])])
		var faces: Array = []
		for _k in int(r["faces"]):
			faces.append(1 if str(r["kind"]) == "defense" else 6)
		t.append({"t": "faces", "faces": faces})
	if handle == 0:
		core.release(h)
	return {"step": str(r["step"]), "reason": str(r.get("reason", "")), "asks": asks, "delta": r.get("delta", []), "handle": int(r.get("handle", 0))}


func _end(volleys: Array) -> void:
	var core: Object = _main.solo_controller._core_node_ready()
	for v in volleys:
		if int((v as Dictionary)["handle"]) != 0:
			core.release(int((v as Dictionary)["handle"]))


func _row(v: Dictionary, gu: GameUnit) -> Dictionary:
	for e in v["delta"]:
		if str(e["unit"]) == gu.unit_id:
			return e
	return {}


## The reading of a volley a case compares, as text: a throw, the number of throws, whether a weapon / the storm was thrown, the
## unit's latched Versatile mode, or one marker pool in the unit's delta row.
func _read(v: Dictionary, what: String, gu: GameUnit = null) -> String:
	match what:
		"hit": return str(v["asks"][0])
		"save": return str(v["asks"][1])
		"thrown": return str(v["asks"].size())
		"pod": return str((v["asks"] as Array).has("attack x3 @4"))
		"storm": return str((v["asks"] as Array).has("attack x3 @2"))
		"mode": return str(_row(v, gu).get("versatile_pick_mode", "no row"))
	return str(_row(v, gu).get("pools", {}).get(what, "no row"))


## A table property flipped between two fresh captures: `off` is the reading before, `on` the reading after `arm` ran.
func _flip(field: String, units: Array, arm: Callable, what: String, off: String, on: String, row_unit := 1) -> void:
	var first := await _volley(units[0], units[1])
	arm.call(units[0], units[1])
	var second := await _volley(units[0], units[1])
	_end([first, second])
	var was := _read(first, what, units[row_unit])
	var now := _read(second, what, units[row_unit])
	print("LEDGER_PROBE in %s: %s -> %s" % [field, was, now])
	assert_str(was).override_failure_message("%s: before the property is set" % field).is_equal(off)
	assert_str(now).override_failure_message("%s: after the property is set" % field).is_equal(on)


func test_in_the_spell_buff_ledger_is_sent() -> void:
	await _flip("buffs", _pair(), func(att: GameUnit, _f: GameUnit) -> void:
		_main._solo_record_spell_mod(att, "Fury", {"modifier": {"hit_mod": 1}, "scope": "shooting", "duration": "round"})
		_main._solo_mirror_spell_state(), "hit", "attack x10 @4", "attack x10 @3")


func test_in_a_spent_limited_weapon_is_sent() -> void:
	var u := _pair()
	_add_weapon(u[0], "Pod", 3, ["Limited"])
	await _flip("limited_used", u, func(att: GameUnit, _f: GameUnit) -> void: att.unit_properties["limited_used"] = ["Pod"],
		"thrown", "5", "3")


func test_in_a_spent_feat_is_sent() -> void:
	var aof := {"game_system": "aof", "faction_folder": "ghostly_undead"}
	await _flip("feats_used", _pair(aof.merged({"rules": ["Precision Feat"]}), aof), func(att: GameUnit, _f: GameUnit) -> void:
		att.unit_properties[SoloController.shot_feat_flag("Precision Feat")] = true, "hit", "attack x10 @3", "attack x10 @4")


func test_in_a_spent_precision_tag_is_sent() -> void:
	await _flip("precision_used", _pair({"faction_folder": "jackals", "rules": ["Precision Tag"]}), func(att: GameUnit, _f: GameUnit) -> void:
		att.unit_properties["precision_tag_used"] = true, "hit", "attack x10 @3", "attack x10 @4")


func test_in_a_spent_storm_attack_is_sent() -> void:
	await _flip("storm_used", _pair({"faction_folder": "daemons_of_change", "rules": ["Storm of Change"]}), func(att: GameUnit, _f: GameUnit) -> void:
		att.unit_properties["storm_used_storm_of_change"] = true, "storm", "true", "false")


## Each pool on the target is +1 to hit for its attackers (Piercing Tag markers are +AP: the save target moves instead).
func test_in_the_marker_pools_on_the_target_are_sent() -> void:
	for pool in ["spot_markers", "tag_markers", "vengeance_markers"]:
		var u := _pair()
		await _flip(pool, u, func(_a: GameUnit, foe: GameUnit) -> void: foe.unit_properties[pool] = 1, "hit", "attack x10 @4", "attack x10 @3")
	await _flip("piercing_tag_markers", _pair(), func(_a: GameUnit, foe: GameUnit) -> void:
		foe.unit_properties["piercing_tag_markers"] = 2
		foe.unit_properties["piercing_tag_source"] = "", "save", "defense x10 @4", "defense x10 @5")


## `piercing_tag_persistent` has no key of its own: the fold derives it from the NAME that placed the pool.
func test_in_the_piercing_target_name_makes_the_pool_stand() -> void:
	var u := _pair()
	u[1].unit_properties["piercing_tag_markers"] = 2
	await _flip("piercing_tag_persistent", u, func(_a: GameUnit, foe: GameUnit) -> void: foe.unit_properties["piercing_tag_source"] = "Piercing Target",
		"piercing_tag_markers", "1", "2")


func test_in_growth_markers_are_sent() -> void:
	await _flip("growth_markers", _pair({"faction_folder": "infected_colonies", "rules": ["Precision Growth"]}), func(att: GameUnit, _f: GameUnit) -> void:
		att.unit_properties["growth_precision_growth"] = 2, "hit", "attack x10 @4", "attack x10 @3")


## NOT sent: the table's latched Versatile pick (and its round). The core picks again (mode 2 = AP(+1)) whatever the table latched.
func test_in_the_versatile_pick_is_not_sent() -> void:
	await _flip("versatile_pick_mode", _pair({"faction_folder": "battle_brothers", "rules": ["Versatile Attack"]}), func(att: GameUnit, _f: GameUnit) -> void:
		att.unit_properties["versatile_pick_round"] = 1
		att.unit_properties["versatile_pick"] = {"hit_mod": 1, "ap": 0}, "mode", "2", "2", 0)


## C-12: `piercing_tag_used` rides the ledger (the second_wind_used shape). A Piercing Tag bearer whose table latch
## is closed places nothing: the core's save target stays the profile's own (it placed the tag again before the fix).
func test_in_the_piercing_tag_latch_is_sent() -> void:
	await _flip("piercing_tag_used", _pair({"faction_folder": "alien_hives", "rules": ["Piercing Tag(1)"]}), func(att: GameUnit, _f: GameUnit) -> void:
		att.unit_properties["piercing_tag_used"] = true, "save", "defense x10 @5", "defense x10 @4")


## Two volleys on ONE core state (the second on the handle the first left, at `second`: the same target unless a case needs a live one)
## against the same second volley on a fresh capture (what the table sends next). The core's change is never written back to the
## table's property: the delta rows carry exactly `DELTA_KEYS`, none of them the field.
func _chain(field: String, units: Array, what: String, first_r: String, core_r: String, fresh_r: String, second: GameUnit = null) -> void:
	var foe2: GameUnit = second if second != null else units[1]
	var first := await _volley(units[0], units[1])
	var core_second := await _volley(units[0], foe2, int(first["handle"]))
	var fresh_second := await _volley(units[0], foe2)
	_end([first, core_second, fresh_second])
	print("LEDGER_PROBE out %s: first %s, core second %s, fresh second %s" % [field, _read(first, what), _read(core_second, what), _read(fresh_second, what)])
	assert_str(_read(first, what)).override_failure_message("%s: first volley" % field).is_equal(first_r)
	assert_str(_read(core_second, what)).override_failure_message("%s: the core remembers its own change" % field).is_equal(core_r)
	assert_str(_read(fresh_second, what)).override_failure_message("%s: the table sends its unchanged property" % field).is_equal(fresh_r)
	assert_array(first["delta"]).is_not_empty()
	for row in first["delta"]:
		var keys: Array = (row as Dictionary).keys()
		keys.sort()
		assert_array(keys).override_failure_message("the delta row's keys: %s" % [keys]).is_equal(DELTA_KEYS)


func test_out_limited_is_lost() -> void:
	var u := _pair()
	_add_weapon(u[0], "Pod", 3, ["Limited"])
	await _chain("limited_used", u, "pod", "true", "false", "true")


func test_out_storm_is_lost() -> void:
	await _chain("storm_used", _pair({"faction_folder": "daemons_of_change", "rules": ["Storm of Change"]}), "storm", "true", "false", "true")


func test_out_precision_used_is_lost() -> void:
	await _chain("precision_used", _pair({"faction_folder": "jackals", "rules": ["Precision Tag"]}), "hit", "attack x10 @3", "attack x10 @4", "attack x10 @3")


## The core spends its own copy of a once buff; the table repeats the spend itself (`spend_once_after_volley`), nothing comes back.
func test_out_a_once_buff_is_lost() -> void:
	var u := _pair()
	_main._solo_record_spell_mod(u[0], "Fury", {"modifier": {"hit_mod": 1}, "scope": "shooting", "duration": "once"})
	_main._solo_mirror_spell_state()
	await _chain("buffs", u, "hit", "attack x10 @3", "attack x10 @4", "attack x10 @3")


## Growth gained by a kill: the core's second volley reads the marker its own first volley gained, the table never hears of it.
func test_out_growth_is_lost() -> void:
	var u := _pair({"faction_folder": "dwarf_guilds", "rules": ["Precision Frenzy"]}, {}, 5)   # the first target dies: that is the kill
	var next := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def2", "models": 40, "x_in": 16.0}), {})
	await _chain("growth_markers", u, "hit", "attack x10 @4", "attack x10 @3", "attack x10 @4", next)


## Carried by NAME, landed for the Protection Feat family only: any other feat is reported and its table flag stays open.
func test_out_a_spent_feat_is_carried_but_not_landed() -> void:
	var aof := {"game_system": "aof", "faction_folder": "ghostly_undead"}
	var u := _pair(aof.merged({"rules": ["Precision Feat"]}), aof)
	var first := await _volley(u[0], u[1])
	_end([first])
	assert_array(_row(first, u[0]).get("feats_used", [])).override_failure_message("the delta names the spent feat").is_equal(["Precision Feat"])
	await assert_error(func() -> void: CoreActivation.land_delta(_main, first["delta"], [], {})) \
		.is_push_error("CoreActivation.land_delta: %s spent the feat Precision Feat, which no table flag closes yet" % u[0].get_name())
	assert_bool(u[0].unit_properties.has(SoloController.shot_feat_flag("Precision Feat"))).is_false()


## Carried and landed: a marker pool. A split is reported (the table's own spend did not run here) and the core's count lands.
func _lands(units: Array, setup: Callable, who: int, pool: String, table_was: int, core_says: int) -> void:
	setup.call(units[0], units[1])
	var v := await _volley(units[0], units[1])
	_end([v])
	print("LEDGER_PROBE out %s: table %d, core %d" % [pool, table_was, core_says])
	assert_int(int(_row(v, units[who]).get("pools", {}).get(pool, -1))).override_failure_message("the delta's %s" % pool).is_equal(core_says)
	await assert_error(func() -> void: CoreActivation.land_delta(_main, v["delta"], [], {})).is_push_error(
		"CoreActivation.land_delta: %s.%s differs (table %d, core %d)" % [units[who].get_name(), pool, table_was, core_says])
	assert_int(int(units[who].unit_properties.get(pool, 0))).override_failure_message("%s landed" % pool).is_equal(core_says)


func test_out_the_marker_pools_land() -> void:
	await _lands(_pair({}, {}, 5), func(_a: GameUnit, foe: GameUnit) -> void: foe.unit_properties["spot_markers"] = 1, 1, "spot_markers", 1, 0)
	await _lands(_pair({}, {}, 5), func(_a: GameUnit, foe: GameUnit) -> void: foe.unit_properties["tag_markers"] = 1, 1, "tag_markers", 1, 0)
	await _lands(_pair({}, {}, 5), func(_a: GameUnit, foe: GameUnit) -> void:
		foe.unit_properties["piercing_tag_markers"] = 2
		foe.unit_properties["piercing_tag_source"] = "", 1, "piercing_tag_markers", 2, 1)
	# A Vengeance bearer the volley destroys banks its markers on the destroyer (5 models, one marker each).
	await _lands(_pair({}, {"faction_folder": "eternal_dynasty", "rules": ["Vengeance"]}, 5), func(_a: GameUnit, _f: GameUnit) -> void: pass,
		0, "vengeance_markers", 0, 5)


## C-12: carried and landed: the bearer's once-per-game latch. The core's placement closed its own copy; the table's
## flag is what its next placement reads, so the delta closes it (a split is reported: the table's own placement did
## not run here). The target's pool is pre-set to what the core's placement + spend leaves, so the latch is the only
## difference this landing reports. RED: drop `piercing_tag_used` from the delta -> the flag stays open.
func test_out_the_piercing_tag_latch_lands() -> void:
	var u := _pair({"faction_folder": "alien_hives", "rules": ["Piercing Tag(1)"]})
	u[1].unit_properties["piercing_tag_markers"] = 1
	u[1].unit_properties["piercing_tag_source"] = ""
	var v := await _volley(u[0], u[1])
	_end([v])
	print("LEDGER_PROBE out piercing_tag_used: table false, core %s" % _row(v, u[0]).get("piercing_tag_used", "no row"))
	assert_bool(bool(_row(v, u[0]).get("piercing_tag_used", false))).override_failure_message("the delta carries the latch").is_true()
	await assert_error(func() -> void: CoreActivation.land_delta(_main, v["delta"], [], {})).is_push_error(
		"CoreActivation.land_delta: %s.piercing_tag_used differs (table false, core true)" % u[0].get_name())
	assert_bool(bool(u[0].unit_properties.get("piercing_tag_used", false))).override_failure_message("the latch landed").is_true()
	assert_int(int(u[1].unit_properties.get("piercing_tag_markers", 0))).override_failure_message("the pool the core left lands equal").is_equal(1)


## C-12: carried and landed: the standing pool's source. A core "Piercing Target" placement sets the core's persistent
## flag; the table keeps the NAME that placed it, so the landing writes "Piercing Target" — the next table volley reads
## a standing pool, not a spend-whole one. The placed pool and the bearer's latch land with it (their splits are
## reported too: the table's own placement did not run here). RED: drop `piercing_tag_persistent` from the delta ->
## the source stays empty and the pool would spend.
func test_out_the_piercing_target_source_lands() -> void:
	var u := _pair({"faction_folder": "alien_hives", "rules": ["Piercing Target"]})
	var v := await _volley(u[0], u[1])
	_end([v])
	print("LEDGER_PROBE out piercing_tag_persistent: table , core %s" % _row(v, u[1]).get("piercing_tag_persistent", "no row"))
	assert_bool(bool(_row(v, u[1]).get("piercing_tag_persistent", false))).override_failure_message("the delta carries the standing flag").is_true()
	assert_int(int(_row(v, u[1]).get("pools", {}).get("piercing_tag_markers", -1))).override_failure_message("the placed token").is_equal(1)
	await assert_error(func() -> void: CoreActivation.land_delta(_main, v["delta"], [], {})).is_push_error(
		"CoreActivation.land_delta: %s.piercing_tag_source differs (table , core Piercing Target)" % u[1].get_name())
	assert_str(str(u[1].unit_properties.get("piercing_tag_source", ""))).override_failure_message("the source landed").is_equal("Piercing Target")
	assert_int(int(u[1].unit_properties.get("piercing_tag_markers", 0))).override_failure_message("the pool landed").is_equal(1)
	assert_bool(bool(u[0].unit_properties.get("piercing_tag_used", false))).override_failure_message("the bearer's latch landed too").is_true()


## Carried but NOT sent: the core's own pick lands over the table's different latch (reported as a split).
func test_out_a_versatile_pick_lands_over_the_tables_latch() -> void:
	var u := _pair({"faction_folder": "battle_brothers", "rules": ["Versatile Attack"]})
	u[0].unit_properties["versatile_pick_round"] = 1
	u[0].unit_properties["versatile_pick"] = {"hit_mod": 1, "ap": 0}
	var v := await _volley(u[0], u[1])
	_end([v])
	await assert_error(func() -> void: CoreActivation.land_delta(_main, v["delta"], [], {})).is_push_error(
		"CoreActivation.land_delta: %s.versatile_pick differs (table %s, core %s)" % [u[0].get_name(), str({"hit_mod": 1, "ap": 0}), str({"hit_mod": 0, "ap": 1})])
	assert_dict(u[0].unit_properties["versatile_pick"]).is_equal({"hit_mod": 0, "ap": 1})


## The trap: a round stamp the capture does not send comes back as the core's fresh -1 and is landed over the table's real stamp as soon
## as the unit has a delta row (here: the wounded target). A stamp the capture DOES send (`vs_mark_round`) comes back equal.
func test_the_unsent_round_stamps_are_overwritten_with_minus_one() -> void:
	var u := _pair()
	u[1].unit_properties["vs_mark_round"] = 1
	var v := await _volley(u[0], u[1])
	_end([v])
	await assert_error(func() -> void: CoreActivation.land_delta(_main, v["delta"], [], {})).is_success()
	assert_int(int(u[1].unit_properties["vs_mark_round"])).override_failure_message("a sent stamp survives the landing").is_equal(1)
	for key in UNSENT_STAMPS:
		var prop: String = UNSENT_STAMPS[key]
		u[1].unit_properties[prop] = 1
		await assert_error(func() -> void: CoreActivation.land_delta(_main, v["delta"], [], {})).is_push_error(
			"CoreActivation.land_delta: %s.%s differs (table 1, core -1)" % [u[1].get_name(), prop])
		assert_int(int(u[1].unit_properties[prop])).override_failure_message("%s was overwritten" % prop).is_equal(-1)


## Wire only: ledger keys of fields a shoot volley cannot exercise, and properties that have no key at all.
func test_the_wire_keys_of_the_fields_a_volley_does_not_exercise() -> void:
	var wired := {"second_wind_used": ["second_wind_used", true], "surprise_attack_used": ["surprise_attack_used", true],
		"reinforcement_spent": ["reinforcement_used", true], SoloController.DELAYED_ACTION_STAMP: ["delayed_action_round", 3],
		"activated_via_coordinate": ["activated_via_coordinate", true], "piercing_tag_used": ["piercing_tag_used", true]}
	for prop in wired:
		var gu := GameUnit.new()
		gu.unit_properties[prop] = (wired[prop] as Array)[1]
		assert_dict(AiActRecorder._ledger_of(gu)).override_failure_message("%s -> ledger key" % prop).is_equal({wired[prop][0]: wired[prop][1]})
	var tp := GameUnit.new()
	tp.unit_properties["teleport_used_this_activation"] = true
	assert_bool(AiActRecorder._ledger_of(tp).has("teleport")).is_true()
	for prop in ["versatile_pick", "versatile_pick_round", "reckless_rolled_round", "reckless_ap_round", "reckless_backfire_round",
			"retreating_strike_round", "mind_control_moved_round", "regenerative_strength_round", "piercing_spot_round"]:
		var gu := GameUnit.new()
		gu.unit_properties[prop] = 1
		assert_dict(AiActRecorder._ledger_of(gu)).override_failure_message("%s has no ledger key" % prop).is_empty()


## Surprise: a Precision Spotter's placement die has no roll record, so the step API REFUSES the whole activation: the spotter's markers
## cannot come out of a core volley at all until that is fixed. This case turns red with the fix: update it then.
func test_a_precision_spotter_volley_is_refused_by_the_step_api() -> void:
	var u := _pair({"faction_folder": "dao_union", "rules": ["Precision Spotter"]})
	var v := await _volley(u[0], u[1])
	_end([v])
	assert_str(v["step"]).override_failure_message("answer: %s" % [v]).is_equal("refused")
	assert_str(v["reason"]).contains("without a roll record")

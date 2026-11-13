extends GdUnitTestSuite
## E2E - MP (online co-op, #673): the AI's once-per-game DOOR latches have to reach the other table.
##
## THE DEFECT. In an online co-op room two humans face one AI seat and the AI's activation resolves on
## whichever machine's activation it answered. The once-per-game latches the activation doors write
## (Piercing Tag, Precision Tag, Precision Target, Surprise Attack, Storm Attack, the Takedown bonus)
## were plain `unit_properties[...] = true` writes, so the machine that answers the AI's NEXT activation
## still saw the rule as unspent and fired it a second time.
##
## The suite drives the REAL main.tscn doors and records what main hands to NetworkManager (the FakeNet
## seam of e2e_mp_hidden_counters_test.gd), then replays those exact arguments into the REAL receiver on a
## "second machine" whose copy of the unit starts without the latch, and runs the same door again.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## The REAL NetworkManager with its transport swapped out (the WireNet of e2e_one_core_ai_body_test.gd): every
## frame this machine would send is recorded, and the real allow-list gate of broadcast_unit_property applies.
class WireNet extends "res://scripts/network_manager.gd":
	var active: bool = true
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		wire.append({"t": type, "p": payload, "to": target_peer})
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1   # the machine of human slot 1 answers the AI: a Storm hits a slot-1 unit, whose save rolls locally

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: WireNet
var _real_net: Node
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true   # no dialogs, no physics tray, no floating text in a headless sweep
	_real_net = _main.network_manager   # kept for the receive-side proof (its handler is call_remote)
	_fake = auto_free(WireNet.new())
	_main.network_manager = _fake
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI's bearer (player 2) of `rule` in the given gf faction.
func _bearer(unit_name: String, rule: String, faction: String, pos: Vector3 = Vector3.ZERO) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, unit_name, [pos]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = [rule]
	return u


## A human unit in reach; `models` 2 makes it the tougher pick when two are in reach.
func _foe(unit_name: String, pos: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.02 * INCH * i, 0, 0))
	return _reg(E2EBoot.make_unit(_main, 1, unit_name, positions))


## The unit-property frames this machine sent, in order: {unit, key, value}.
func _frames() -> Array:
	var out: Array = []
	for w in _fake.wire:
		var p: Dictionary = (w as Dictionary)["p"] as Dictionary
		if str(p.get("m", "")) != "sync_unit_property":
			continue
		var a: Array = p["a"]
		out.append({"unit": str(a[0]), "key": str(a[1]), "value": a[2]})
	return out


func _values(key: String) -> Array:
	var out: Array = []
	for e in _frames():
		if str((e as Dictionary)["key"]) == key:
			out.append((e as Dictionary)["value"])
	return out


## Read defensively: with no frame at all every assertion must still FAIL cleanly - an out-of-bounds
## index takes gdUnit's -d run into the debugger and the whole headless process down.
func _first_unit(key: String) -> String:
	for e in _frames():
		if str((e as Dictionary)["key"]) == key:
			return str((e as Dictionary)["unit"])
	return "<no message>"


## The second machine: it never saw the activation, so its copy of the unit starts without the latch;
## it then receives exactly the frames this machine sent for `key`, through the REAL receiver.
func _replay_on_the_other_table(unit: GameUnit, key: String) -> void:
	unit.unit_properties.erase(key)
	for e in _frames():
		var d := e as Dictionary
		if str(d["key"]) == key:
			_real_net.sync_unit_property(str(d["unit"]), key, d["value"])


func _log_count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


# === 1. Piercing Tag / Precision Tag / Precision Target ==========================================

func test_piercing_tag_latch_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var tagger := _bearer("Marksman", "Piercing Tag(2)", "alien_hives")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0))
	await _main._solo_apply_piercing_tag(tagger)
	assert_array(_values("piercing_tag_used")) \
		.override_failure_message("the once-per-game latch never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_str(_first_unit("piercing_tag_used")).is_equal(tagger.unit_id)

	_replay_on_the_other_table(tagger, "piercing_tag_used")
	var before := int(alpha.unit_properties.get("piercing_tag_markers", 0))
	await _main._solo_apply_piercing_tag(tagger)
	assert_int(int(alpha.unit_properties.get("piercing_tag_markers", 0))) \
		.override_failure_message("the other table placed the once-per-game Piercing Tag a second time") \
		.is_equal(before)


func test_precision_tag_latch_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var tagger := _bearer("Marksman", "Precision Tag(2)", "jackals")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0))
	await _main._solo_apply_precision_tag(tagger)
	assert_array(_values("precision_tag_used")) \
		.override_failure_message("the once-per-game latch never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_str(_first_unit("precision_tag_used")).is_equal(tagger.unit_id)

	_replay_on_the_other_table(tagger, "precision_tag_used")
	var before := int(alpha.unit_properties.get("tag_markers", 0))
	await _main._solo_apply_precision_tag(tagger)
	assert_int(int(alpha.unit_properties.get("tag_markers", 0))) \
		.override_failure_message("the other table placed the once-per-game Precision Tag a second time") \
		.is_equal(before)


func test_precision_target_latch_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var tagger := _bearer("Marksman", "Precision Target", "blessed_sisters")
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0))
	_main._solo_apply_precision_target(tagger)
	assert_array(_values("precision_target_used")) \
		.override_failure_message("the once-per-game latch never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_str(_first_unit("precision_target_used")).is_equal(tagger.unit_id)

	_replay_on_the_other_table(tagger, "precision_target_used")
	var before := _log_count("Precision Target:")
	_main._solo_apply_precision_target(tagger)
	assert_int(_log_count("Precision Target:")) \
		.override_failure_message("the other table placed the once-per-game Precision Target a second time (alpha: %s)" % str(alpha.unit_properties)) \
		.is_equal(before)


# === 2. Surprise Attack / Storm Attack / Takedown bonus =========================================

func test_surprise_attack_latch_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var bearer := _bearer("Skulker", "Surprise Attack", "jackals")
	_foe("Target", Vector3(40.0 * INCH, 0, 0), 1)   # far outside the 6" range: the latch burns anyway
	await _main._solo_apply_surprise_attack(bearer)
	assert_array(_values("surprise_attack_used")) \
		.override_failure_message("the first-activation latch never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_str(_first_unit("surprise_attack_used")).is_equal(bearer.unit_id)

	_replay_on_the_other_table(bearer, "surprise_attack_used")
	assert_bool(_main.solo_controller.surprise_attack_bearer_ready(bearer)) \
		.override_failure_message("the other table still reads the bearer as READY to burst a second time") \
		.is_false()


func test_storm_attack_latch_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	# Both seats are AI here only so the storm's hits do not stop on a human's save prompt (a headless run has no
	# clicker): the latch under test is the bearer's, whoever the target is.
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	# The faction the existing hotseat storm suite uses: the rule lives only in the daemon sections of the map.
	var stormer := _bearer("Stormer", "Storm of War", "daemons_of_war")
	stormer.unit_properties.erase("game_system")
	_foe("Foe", Vector3(6.0 * INCH, 0, 0), 3)
	await _main._solo_apply_storm_attack(stormer)
	assert_array(_values("storm_used_storm_of_war")) \
		.override_failure_message("the once-per-game latch never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_str(_first_unit("storm_used_storm_of_war")).is_equal(stormer.unit_id)
	assert_int(_log_count("unleashes the storm")).override_failure_message("fixture check: the storm fired once").is_equal(1)

	_replay_on_the_other_table(stormer, "storm_used_storm_of_war")
	await _main._solo_apply_storm_attack(stormer)
	assert_int(_log_count("unleashes the storm")) \
		.override_failure_message("the other table unleashed the once-per-game storm a second time") \
		.is_equal(1)


func test_takedown_bonus_latch_rides_the_wire_and_holds_on_the_other_table(timeout := 120000) -> void:
	var bearer := _bearer("Sergeant", "Takedown Strike", "alien_hives")
	assert_int(_main._solo_takedown_bonus_groups(bearer, true).size()) \
		.override_failure_message("fixture check: the first melee grants the extra attack") \
		.is_equal(1)
	assert_array(_values("takedown_bonus_used_Takedown Strike")) \
		.override_failure_message("the once-per-game latch never reached the wire (frames: %s)" % str(_frames())) \
		.is_equal([true])
	assert_str(_first_unit("takedown_bonus_used_Takedown Strike")).is_equal(bearer.unit_id)

	_replay_on_the_other_table(bearer, "takedown_bonus_used_Takedown Strike")
	assert_array(_main._solo_takedown_bonus_groups(bearer, true)) \
		.override_failure_message("the other table granted the once-per-game extra attack a second time") \
		.is_empty()


# === 3. Counter-proofs ===========================================================================

## Offline the whole thing must stay silent and still latch.
func test_a_solo_game_latches_without_a_frame(timeout := 120000) -> void:
	_fake.active = false
	var tagger := _bearer("Marksman", "Piercing Tag(2)", "alien_hives")
	_foe("Alpha", Vector3(10.0 * INCH, 0, 0))
	var bearer := _bearer("Sergeant", "Takedown Strike", "alien_hives")

	await _main._solo_apply_piercing_tag(tagger)
	_main._solo_takedown_bonus_groups(bearer, true)

	assert_bool(bool(tagger.unit_properties.get("piercing_tag_used", false))).is_true()
	assert_bool(bool(bearer.unit_properties.get("takedown_bonus_used_Takedown Strike", false))).is_true()
	assert_array(_frames()) \
		.override_failure_message("an offline game broadcast hidden state") \
		.is_empty()


## The allow-list is still a boundary: the latch keys and their two name prefixes are listed, nothing else.
func test_the_receiver_takes_the_latch_keys_and_still_refuses_other_keys(timeout := 120000) -> void:
	var alpha := _foe("Alpha", Vector3(10.0 * INCH, 0, 0), 1)

	_real_net.sync_unit_property(alpha.unit_id, "player_id", 2)
	_real_net.sync_unit_property(alpha.unit_id, "storm_usedX", true)
	_real_net.sync_unit_property(alpha.unit_id, "takedown_bonus", true)
	assert_int(int(alpha.unit_properties.get("player_id", 0))).is_equal(1)
	assert_bool(alpha.unit_properties.has("storm_usedX")).is_false()
	assert_bool(alpha.unit_properties.has("takedown_bonus")).is_false()

	for key in ["piercing_tag_used", "precision_tag_used", "precision_target_used", "surprise_attack_used",
			"storm_used_storm_of_war", "takedown_bonus_used_Takedown Strike"]:
		_real_net.sync_unit_property(alpha.unit_id, key, true)
		assert_bool(bool(alpha.unit_properties.get(key, false))).override_failure_message(key).is_true()

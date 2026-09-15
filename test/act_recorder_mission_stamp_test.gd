extends GdUnitTestSuite
## Wave 6 — the act-recorder header carries WHICH mission the game played.
##
## D-MISSIONS (maintainer 15.09.): the recorder never stamped the mission, so
## no gate, corpus census or replay could tell a Domination game from a Duel
## one. The stamp rides the header line (`_header_line`) as a FORMAT addition
## — precedent: the `books` key, written unconditionally, read optionally —
## and the Rust twin reads it via `nml_core::ActHeader::mission_id`
## (core/nml-core/src/acts.rs), answering "duel" for every header written
## before the key existed.
##
## The id's sources, in order: the table's setter (AiActRecorder.set_mission,
## armed by main.gd's _solo_apply_mission_if_chosen), the arena selector's env
## door (`NML_MISSION`, tools/arena_match.gd), the catalog default "duel" —
## every stamp validated against the same catalog the selector validates
## against (MissionCatalog.mission_ids). before_test/after_test close the
## recorder so each test starts from fresh statics (the same fresh-file
## contract a game end gives the real recorder).

const IN2M := 0.0254


func before_test() -> void:
	# close() resets the recorder's cached statics — INCLUDING the mission id
	# (fresh-file contract) — so a test arms only what it asserts.
	AiActRecorder.close()
	OS.set_environment("NML_MISSION", "")


func after_test() -> void:
	AiActRecorder.close()
	OS.set_environment("NML_MISSION", "")


func _armed(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _state() -> Dictionary:
	var a := _armed(1, [Vector3.ZERO], "A")
	var b := _armed(2, [Vector3(6.0 * IN2M, 0, 0)], "B")
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"A": a, "B": b}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 3)
	state["charge_illegal"] = func(_at: GameUnit, _vt: GameUnit, _gap: float,
		_ca: Vector3, _cb: Vector3) -> bool: return false
	return state


## The table path: main.gd arms the setter from the selector's choice; the
## stamp carries id + the catalog's family and scoring — the same fields the
## core's Mission struct (acts.rs) reads back.
func test_the_table_choice_stamps_the_header() -> void:
	# Dynamic dispatch keeps this file PARSING pre-fix: a direct AiActRecorder.set_mission()
	# reference is a parse-time error (static analysis on the class), which would mask the
	# behavioral reds this suite exists to prove. has_method() records a clean assertion
	# failure instead — the same seam pattern solo_arena_test uses for rule_text_refused.
	var rec: Object = load("res://scripts/solo/act_recorder.gd")
	assert_bool(rec.has_method("set_mission")).override_failure_message(
		"AiActRecorder.set_mission() not implemented yet (pre-fix RED)").is_true()
	if not rec.has_method("set_mission"):
		return
	rec.call("set_mission", "Domination")   # the setter lower-cases, like the arena door
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("domination")
	assert_str(str(m.get("family", ""))).override_failure_message("header stamp 'family'").is_equal("progressive")
	assert_str(str(m.get("scoring", ""))).override_failure_message("header stamp 'scoring'").is_equal("round_vp")


## No mission chosen stamps the catalog default EXPLICITLY — the key is never
## omitted, because an absent key would mean "predates the stamp" to every
## reader (the same reading `ActHeader::mission_id` gives old recordings).
func test_an_unchosen_mission_stamps_the_catalog_default() -> void:
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("duel")
	assert_str(str(m.get("family", ""))).override_failure_message("header stamp 'family'").is_equal("face_off")
	assert_str(str(m.get("scoring", ""))).override_failure_message("header stamp 'scoring'").is_equal("end")


## The env door: when the table chose nothing, the recorder reads the same
## NML_MISSION the arena selector writes (strip + lower), so a headless arena
## game and a table game stamp identically.
func test_the_env_door_fills_in_when_the_table_chose_nothing() -> void:
	OS.set_environment("NML_MISSION", "Domination")
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("domination")
	assert_str(str(m.get("family", ""))).override_failure_message("header stamp 'family'").is_equal("progressive")
	assert_str(str(m.get("scoring", ""))).override_failure_message("header stamp 'scoring'").is_equal("round_vp")


## An unknown id cannot reach the recorder through the arena (it FATALs
## there), so the fallback is belt-and-braces — but it must fall to the same
## default, never to an empty string or a dropped key.
func test_an_unknown_env_id_falls_back_to_duel() -> void:
	OS.set_environment("NML_MISSION", "not_a_mission")
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("duel")
	assert_str(str(m.get("family", ""))).override_failure_message("header stamp 'family'").is_equal("face_off")
	assert_str(str(m.get("scoring", ""))).override_failure_message("header stamp 'scoring'").is_equal("end")

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
## The id's source is the arena selector's env door (`NML_MISSION`,
## tools/arena_match.gd), validated against the same catalog the selector
## validates against (MissionCatalog.mission_ids). The recorder cannot read
## main.gd's `_solo_mission_id` (stay-out file), so a mission chosen through
## the table UI still stamps the catalog default "duel" — flagged in the PR,
## not silently lost: "duel" is what those games were before this key.

const IN2M := 0.0254


func after_test() -> void:
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


## The env door: the arena selector writes its catalog-validated choice here,
## the recorder mirrors it into the header — id plus the catalog's family and
## scoring, the same fields `tools/arena_match.gd`'s own `_mission_stamp`
## builds for the battle log.
func test_the_header_stamps_the_env_chosen_mission() -> void:
	OS.set_environment("NML_MISSION", "Domination")   # the arena lower-cases; so do we
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("domination")
	assert_str(str(m.get("family", ""))).override_failure_message("header stamp 'family'").is_equal("progressive")
	assert_str(str(m.get("scoring", ""))).override_failure_message("header stamp 'scoring'").is_equal("round_vp")


## No mission chosen stamps the catalog default EXPLICITLY — the key is never
## omitted, because an absent key would mean "predates the stamp" to every
## reader (the same reading `ActHeader::mission_id` gives old recordings).
func test_an_unchosen_mission_stamps_the_catalog_default() -> void:
	OS.set_environment("NML_MISSION", "")
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("duel")
	assert_str(str(m.get("family", ""))).override_failure_message("header stamp 'family'").is_equal("face_off")
	assert_str(str(m.get("scoring", ""))).override_failure_message("header stamp 'scoring'").is_equal("end")


## An unknown id cannot reach the recorder through the arena (it FATALs
## there), so the fallback is belt-and-braces — but it must fall to the same
## default, never to an empty string or a dropped key.
func test_an_unknown_env_id_falls_back_to_duel() -> void:
	OS.set_environment("NML_MISSION", "not_a_mission")
	var m: Dictionary = AiActRecorder._header_line(_state(), Callable()).get("mission", {})
	assert_str(str(m.get("id", ""))).override_failure_message("header stamp 'id'").is_equal("duel")

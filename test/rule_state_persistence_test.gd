extends GdUnitTestSuite
## NML-949/950 — rule state that outlives the objects that compute it. Five once-per-game /
## per-round values lived only in RAM: a load, an MP rejoin, or a plain SoloController rebuild
## (an AI-slot change, or a human taking over an AI slot) handed them back at their class
## defaults, re-arming spent weapons and mis-capping per-round rules.
##
## RED TODAY BY DESIGN: every assertion below compiles against the CURRENT API (no
## `army_manager.rule_state`, no typed fix-only call) and fails on a real assertion, never a
## crash — the fix has not been written yet.


func _mgr() -> OPRArmyManager:
	var mgr := OPRArmyManager.new()
	add_child(mgr)
	return auto_free(mgr)


func _save_mgr() -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)
	return auto_free(sm)


func _controller(mgr: OPRArmyManager) -> SoloController:
	var sc := SoloController.new()
	add_child(sc)
	sc.setup(mgr, null, null, 1, 2)   # human=1, ai=2 — mirrors solo_controller_test.gd exactly
	# Round awareness exactly as main.gd:2110 wires it. Without this `_current_round()` answers 0
	# for every round, every per-round counter collapses onto one key, and a per-round test would be
	# measuring nothing — the fixture has to be as round-aware as the real game.
	sc.round_provider = func() -> int:
		return int(mgr.current_round) if mgr != null else 0
	return auto_free(sc)


## A minimal GameUnit, registered on `mgr` under player `pid`. One live model at the origin, a
## real Node3D so unit_centre()/nearest_human_unit() reads (Second Wind's EV probe) don't fault.
func _unit(mgr: OPRArmyManager, pid: int, unit_name: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "%s_%d" % [unit_name, pid]
	u.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3.ZERO
	m.node = n
	u.models.append(m)
	if mgr != null:
		mgr.game_units[u.unit_id] = u
	return u


# === A1 — the save carries a rule_state key at all =============================================

func test_game_state_carries_the_rule_bookkeeping() -> void:
	var sm := _save_mgr()
	sm.army_manager = _mgr()
	var state := sm._serialize_game_state()
	assert_bool(state.has("rule_state")) \
		.override_failure_message("NML-949 — the match-level rule bookkeeping is not in the save at all; every once-per-game counter resets on load.") \
		.is_true()


# === A2 — Limited across a REAL save/load ========================================================

func test_limited_weapon_stays_spent_across_a_save() -> void:
	var mgr := _mgr()
	var sc := _controller(mgr)
	var u := _unit(mgr, 2, "Rocketeer")
	var prof := {"name": "Rocket", "limited": true}

	sc.mark_limited_used(u, prof)
	assert_bool(sc.is_limited_used(u, prof)).is_true()   # sanity: spent on the live controller

	# REAL reload of the unit: to_dict -> JSON -> from_dict (a save is a JSON file), THEN the same
	# post-load hook every real load runs (save_manager.gd:386/main.gd:12405) — to_dict() always
	# stamps unit_properties["attached_to"] = "" when absent, and only this hook resolves that
	# back to null; skipping it leaves every reloaded unit reading as "attached" to the eligibility
	# gates that check is_attached(), which is not the real reload's behaviour.
	var wire: Dictionary = JSON.parse_string(JSON.stringify(u.to_dict()))
	var u2 := GameUnit.from_dict(wire)
	mgr.game_units[u2.unit_id] = u2
	var sm := _save_mgr()
	sm.army_manager = mgr
	sm._restore_hero_attachments_after_load()

	# Fresh controller on the same mgr — both the reload AND the controller-rebuild case at once
	# (a new controller starts with an empty session cache, exactly like an AI-slot change).
	var sc2 := _controller(mgr)
	assert_bool(sc2.is_limited_used(u2, prof)) \
		.override_failure_message("Limited (core v3.5.1) is once per GAME — after a save/load the spent weapon fires again.") \
		.is_true()


# === A3 — Limited across a controller rebuild, NO serialization at all =========================

func test_limited_stays_spent_across_a_controller_rebuild() -> void:
	var mgr := _mgr()
	var sc := _controller(mgr)
	var u := _unit(mgr, 2, "Rocketeer")
	var prof := {"name": "Rocket", "limited": true}

	sc.mark_limited_used(u, prof)
	assert_bool(sc.is_limited_used(u, prof)).is_true()   # sanity

	# Same live GameUnit, no save/load — only the AI-slot-change / human-takes-the-slot trigger
	# (main.gd :2026-2028 and :11310-11319 both queue_free() the controller).
	var sc2 := _controller(mgr)
	assert_bool(sc2.is_limited_used(u, prof)) \
		.override_failure_message("the controller is rebuilt on an AI-slot change — the spent Limited weapon came back without any save involved.") \
		.is_true()


# === A4 — Second Wind's per-round army cap across a REAL reload ================================

## TWO carriers, so the cap is ceil(2/3) = 1: after one Second Wind the round is full while the
## SECOND carrier has still never used its own. That separation is the whole point — the per-unit
## second_wind_used flag already persists correctly, so only the missing round COUNTER can be what
## lets a second Second Wind through.
##
## Deliberately only the match state is round-tripped, not the units: rebuilding the GameUnits would
## let an unrelated fixture slip (an empty roster makes second_wind_candidate() return null for the
## wrong reason, and the test would pass while the bug is still there — that is exactly what the
## first draft of this test did).
func _second_wind_pair(mgr: OPRArmyManager) -> Array:
	var out: Array = []
	for i in range(2):
		var c := _unit(mgr, 2, "Carrier%d" % i)
		c.unit_properties["special_rules"] = ["Martial Prowess"]
		c.unit_properties["faction_folder"] = "dark_elf_raiders"
		c.is_activated = true   # eligible: already activated once this round
		out.append(c)
	return out


func test_a_second_wind_stays_spent_for_the_round_after_a_reload() -> void:
	var mgr := _mgr()
	var carriers := _second_wind_pair(mgr)
	var sm := _save_mgr()
	sm.army_manager = mgr
	var sc := _controller(mgr)

	var cand := sc.second_wind_candidate()
	assert_object(cand) \
		.override_failure_message("fixture: no Second Wind candidate before spending — the eligibility gates in second_wind_candidate() were not met") \
		.is_not_null()
	sc.spend_second_wind(cand)
	(cand as GameUnit).is_activated = true   # spend_second_wind clears it; it is still on the table
	assert_object(sc.second_wind_candidate()) \
		.override_failure_message("fixture: with 2 carriers the cap is 1, so the round must be full after one Second Wind") \
		.is_null()

	# The reload: the match state through save_manager's own serializer/deserializer and a genuine
	# JSON pass (a save IS a JSON file, and JSON has no integer dictionary keys).
	sm._deserialize_game_state(JSON.parse_string(JSON.stringify(sm._serialize_game_state())))

	# Guard against the false pass: the untouched second carrier must still be a live, eligible
	# carrier, so a null verdict below can ONLY come from the restored counter.
	var other := carriers[1] as GameUnit
	assert_bool(other.is_activated).is_true()
	assert_bool(bool(other.unit_properties.get("second_wind_used", false))).is_false()
	assert_int(mgr.get_game_units_for_player(2).size()) \
		.override_failure_message("fixture: the AI roster went missing, so any null verdict below would be meaningless") \
		.is_equal(2)

	var sc2 := _controller(mgr)
	assert_object(sc2.second_wind_candidate()) \
		.override_failure_message("the Second Wind army cap is one third of the carriers PER ROUND — after a reload the counter reads zero and the round grants more Second Winds than it may.") \
		.is_null()


func test_the_second_wind_cap_reopens_on_the_next_round() -> void:
	# The counter is per ROUND, not per game — and this is also the JSON-key proof: a counter keyed
	# by an integer round number comes back from JSON keyed by a string and would never be found.
	var mgr := _mgr()
	var carriers := _second_wind_pair(mgr)
	var sm := _save_mgr()
	sm.army_manager = mgr
	var sc := _controller(mgr)
	sc.spend_second_wind(sc.second_wind_candidate())
	(carriers[0] as GameUnit).is_activated = true

	sm._deserialize_game_state(JSON.parse_string(JSON.stringify(sm._serialize_game_state())))
	mgr.set_current_round(2)

	var sc2 := _controller(mgr)
	assert_object(sc2.second_wind_candidate()) \
		.override_failure_message("the cap binds per ROUND — round 2 owes its own Second Wind, but the restored counter is still blocking it.") \
		.is_not_null()


# === A5 — Re-Deployment across a controller rebuild =============================================

func test_redeploy_stays_done_across_a_controller_rebuild() -> void:
	var mgr := _mgr()
	var sc := _controller(mgr)
	sc._redeploy_done = true

	var sc2 := _controller(mgr)
	assert_bool(sc2._redeploy_done) \
		.override_failure_message("Re-Deployment is once per GAME; a rebuilt controller offers it again. Today only a foreign game_phase gate hides this — loosen that gate and it is exploitable (NML-950).") \
		.is_true()


func test_a_fresh_table_owes_every_once_per_game_rule_again() -> void:
	# clear_all() is the new-table reset. The store must be cleared with the armies, or the next
	# game would start with the last game's Re-Deployment already spent.
	var mgr := _mgr()
	var sc := _controller(mgr)
	sc._redeploy_done = true
	mgr.clear_all()
	var sc2 := _controller(mgr)
	assert_bool(sc2._redeploy_done) \
		.override_failure_message("a fresh table must owe Re-Deployment again — the match rule store was not cleared with the armies.") \
		.is_false()


# === Backwards compatibility: saves written before this change ================================

func test_an_older_save_without_the_store_loads_as_all_fresh() -> void:
	# Pre-NML-949 saves carry no rule_state. An empty store IS the old behaviour, which is why this
	# addition owes no SaveMigrations step — assert that, so nobody "fixes" it with a version bump.
	var sm := _save_mgr()
	var mgr := _mgr()
	sm.army_manager = mgr
	sm._deserialize_game_state({"current_round": 3, "game_phase": OPRArmyManager.GamePhase.PLAYING})
	assert_int(mgr.current_round).is_equal(3)
	var sc := _controller(mgr)
	assert_bool(sc._redeploy_done) \
		.override_failure_message("an old save must load as all-fresh, not crash and not carry stale state") \
		.is_false()

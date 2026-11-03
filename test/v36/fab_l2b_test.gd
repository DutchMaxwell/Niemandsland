extends GdUnitTestSuite
## Rules 3.6 log wave, row AIG-G2-L2b: the shooting-range reach the TABLE applies must name the BOOK entry
## that granted it. Two book spellings reach via the Royal Legion primitive:
##   * the self entry "Increased Shooting Range" (gf alien_hives), and
##   * the aura "Increased Shooting Range Aura" — either its own Royal Legion entry (aof) or an Aura Channel
##     whose granted base is the self entry (gf alien_hives, expanded at import onto the unit).
## Today the table's reach line names only the expanded base, so an aura reads as a self grant and the
## harvest cannot tell the two books apart.
## Log-only: the reach, the weapons that fire and every number stay exactly as on main. Controls first.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const IN2M := 0.0254
## Both fixture units sit on the default base (VolumetricLos.DEFAULT_BASE_RADIUS_M = 0.016 m); every range
## gate measures base-EDGE to base-edge (B11), so a centre offset carries both radii on top.
const EDGE_SLACK_IN := 2.0 * 0.016 / IN2M

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


## A player unit whose OPR source carries one ranged weapon — the shape _solo_all_weapons and
## _solo_attack_groups read.
func _armed(pid: int, unit_name: String, positions: Array, system: String, faction: String,
		rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["quality"] = 4
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## X offset (metres) that puts a single-model unit at `gap_in` base-edge-to-base-edge from origin.
func _x_for_gap(gap_in: float) -> float:
	return (gap_in + EDGE_SLACK_IN) * IN2M


## The profile names the human volley rolls dice for against `target`.
func _volley_weapons(attacker: GameUnit, target: GameUnit) -> Array:
	var dist: float = _main.solo_controller.nearest_melee_gap_in(attacker, target)
	var out: Array = []
	for grp in _main._solo_attack_groups(attacker, dist, false, target):
		for p in (grp as Dictionary).get("profiles", []):
			out.append(str((p as Dictionary).get("name", "")))
	return out


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


# ===== controls (all green on main) =====

func test_control_a_plain_rifle_carries_no_bonus_and_logs_nothing() -> void:
	var gunner := _armed(1, "Riflemen", [Vector3.ZERO], "gf", "alien_hives", [])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], "gf", "alien_hives", [])
	assert_int(SoloController.shooting_range_bonus(gunner)).is_equal(0)
	assert_array(_volley_weapons(gunner, grunts)) \
		.override_failure_message("fixture broken: a plain 24\" rifle must not reach 26\"").not_contains(["Rifle"])
	_main._solo_log_range_bonus(gunner, grunts)
	assert_str(_log_text()).not_contains("shooting range —")


func test_control_the_self_entry_still_names_itself() -> void:
	var gunner := _armed(1, "Hive Guard", [Vector3.ZERO], "gf", "alien_hives",
		["Increased Shooting Range"])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], "gf", "alien_hives", [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("fixture broken: the self entry must resolve to +6\"").is_equal(6)
	assert_array(_volley_weapons(gunner, grunts)).contains(["Rifle"])
	_main._solo_log_range_bonus(gunner, grunts)
	assert_str(_log_text()) \
		.override_failure_message("the self grant keeps its own book name (log: %s)" % _log_text().strip_edges()) \
		.contains("Increased Shooting Range +6\" shooting range")


func test_control_an_aura_that_is_its_own_royal_legion_entry_names_the_aura() -> void:
	var gunner := _armed(1, "Dwarf Gunners", [Vector3.ZERO], "aof", "havoc_dwarves",
		["Increased Shooting Range Aura"])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], "aof", "havoc_dwarves", [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("fixture broken: the aof aura entry must resolve to +6\"").is_equal(6)
	assert_array(_volley_weapons(gunner, grunts)).contains(["Rifle"])
	_main._solo_log_range_bonus(gunner, grunts)
	assert_str(_log_text()) \
		.override_failure_message("the aof aura entry already names itself; must stay (log: %s)" % _log_text().strip_edges()) \
		.contains("Increased Shooting Range Aura +6\" shooting range")


# ===== the named line (RED on main: the aura reads as the expanded base) =====

func test_an_aura_channel_names_the_aura_not_its_expanded_base() -> void:
	# gf alien_hives: "Increased Shooting Range Aura" is an Aura Channel whose granted base is the self
	# entry, which the import writes onto the unit (both names carried). The reach came from the aura,
	# so the line must name the aura.
	var gunner := _armed(1, "Bio-Tech Master", [Vector3.ZERO], "gf", "alien_hives",
		["Increased Shooting Range Aura", "Increased Shooting Range"])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], "gf", "alien_hives", [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("fixture broken: the expanded aura must still resolve to +6\"").is_equal(6)
	assert_array(_volley_weapons(gunner, grunts)) \
		.override_failure_message("fixture broken: the +6\" must lift the 24\" rifle to 26\"").contains(["Rifle"])
	_main._solo_log_range_bonus(gunner, grunts)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: the aura granted the reach, the line must name it (log: %s)" % text.strip_edges()) \
		.contains("Increased Shooting Range Aura +6\" shooting range")


func test_below_epoch_73_the_aura_line_keeps_its_old_text() -> void:
	# The book-name fix belongs to epoch 73. At 72 the table must print the old expanded-base text,
	# byte for byte, so a playtest table cannot silently change its wording.
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var gunner := _armed(1, "Bio-Tech Master", [Vector3.ZERO], "gf", "alien_hives",
		["Increased Shooting Range Aura", "Increased Shooting Range"])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], "gf", "alien_hives", [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("fixture broken: the expanded aura must still resolve to +6\"").is_equal(6)
	_main._solo_log_range_bonus(gunner, grunts)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("epoch 72 keeps the old line (log: %s)" % text.strip_edges()) \
		.contains("Bio-Tech Master: Increased Shooting Range +6\" shooting range — Rifle reaches Grunts past its printed range")
	assert_str(text).not_contains("Increased Shooting Range Aura")

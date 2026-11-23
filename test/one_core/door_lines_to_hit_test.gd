extends GdUnitTestSuite
## One core, door lines (lane dlines train 4, DS-GHITN): the core door writes the table's "To-hit vs <U>: <note> → hits on N+" line
## (Artillery shooter/target, Stealth, Stealth aliases, Evasive + stand-down, Aircraft, Shot Modifier entries, Instinctive, multi-fragment
## order and net-0 logging) and the three Takedown lines (pick, context embedding the to-hit note, wounded/killed, without "takes N wounds").
## Each case runs SEEDS (12) seeded volleys on the door and pins the lines (`door_lines.gd`). RED on main's library;
## GREEN after that train.
## Real: the main scene, NmlCore, the importer's own unit builder. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_to_hit_dice"
## Per label: the door's count of `<prefix>` lines that contain the case's needle (all `<prefix>` lines when it has none), per seed.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_LINES := {
	"artillery shooter >12": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"artillery shooter <=12": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"artillery shooter <=9": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"artillery target >12": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"artillery target <=12": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"artillery target moved": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"stealth >9": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"stealth <=9": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"screened >9": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"entrenched >12": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"evasive": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"evasive stand-down": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"aircraft": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"good shot": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"bad shot": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"buccaneer >9": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"buccaneer <=9": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"targeting visor": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"mobile artillery": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"instinctive": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"net-zero order": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"plain control": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"takedown troopers": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
	"takedown no takes-line": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"takedown tough": [2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1],
	"takedown with note (to-hit)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"takedown with note (ctx)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
	"takedown when shooting": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(uname: String, size: int, rules: Array, weapon_rules: Array, faction := "battle_brothers", system := "gf", guns := 6) -> Dictionary:
	var e := DoorLines.entry(uname, size, rules, weapon_rules, faction, guns)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


## One case: the door alone runs SEEDS volleys and writes the pinned count of `<prefix>` lines that contain `needle`
## (every `<prefix>` line when the case has none) per seed.
func _door_says(label: String, shooter: Dictionary, target: Dictionary, prefix: String, opts := {}, needle := "") -> void:
	var want: Array = WANT_LINES.get(label, [])
	var got: Array = []
	for s in SEEDS:
		var v: Dictionary = await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE), opts)
		var hits: Array = DoorLines.named(v["lines"], prefix)
		if needle != "":
			hits = hits.filter(func(l: String) -> bool: return l.contains(needle))
		got.append(hits.size())
	print("DOOR_LINES %s %s" % [label, JSON.stringify(got)])
	assert_array(got).override_failure_message("%s: the door's %s lines per seed %s, want %s" % [label, prefix, JSON.stringify(got), JSON.stringify(want)]).is_equal(want)


func _plain_shooter(faction := "battle_brothers", system := "gf") -> Dictionary:
	return _unit("Gunners", 6, [], [], faction, system, 6)


func _plain_target(size := 10, rules := [], faction := "battle_brothers", system := "gf") -> Dictionary:
	return _unit("Targets", size, rules, [], faction, system, 0)


func test_artillery_shooter_and_target_write_their_to_hit_notes() -> void:
	var art_s := _unit("Gunners", 6, ["Artillery"], [], "battle_brothers", "gf", 6)
	var art_t := _plain_target(10, ["Artillery"])
	await _door_says("artillery shooter >12", art_s, _plain_target(), "To-hit vs", {"distance_in": 18.0}, "Artillery +1 (Held, target over 12\")")
	await _door_says("artillery shooter <=12", art_s, _plain_target(), "To-hit vs", {"distance_in": 11.0}, "Artillery: no +1 (target within 12\")")
	await _door_says("artillery shooter <=9", art_s, _plain_target(), "To-hit vs", {"distance_in": 6.0}, "Artillery: no +1 (target within 9\")")
	await _door_says("artillery target >12", _plain_shooter(), art_t, "To-hit vs", {"distance_in": 18.0}, "Artillery target -1 over 12\" (unmoved)")
	await _door_says("artillery target <=12", _plain_shooter(), art_t, "To-hit vs", {"distance_in": 11.0}, "Artillery target: no -1 (within 12\")")
	await _door_says("artillery target moved", _plain_shooter(), art_t, "To-hit vs", {"distance_in": 18.0, "ledger": {"tgt": {"moved_round": 1}}}, "Artillery target: no -1 (moved this round)")


func test_stealth_and_its_aliases_write_their_to_hit_notes() -> void:
	await _door_says("stealth >9", _plain_shooter(), _plain_target(10, ["Stealth"]), "To-hit vs", {"distance_in": 18.0}, "Stealth -1")
	await _door_says("stealth <=9", _plain_shooter(), _plain_target(10, ["Stealth"]), "To-hit vs", {"distance_in": 6.0}, "Stealth: no -1 (within 9\")")
	await _door_says("screened >9", _plain_shooter("saurians", "aof"), _plain_target(10, ["Screened"], "ghostly_undead", "aof"), "To-hit vs", {"distance_in": 18.0}, "Screened -1 over 9\"")
	await _door_says("entrenched >12", _plain_shooter(), _plain_target(10, ["Entrenched"], "human_defense_force", "gf"), "To-hit vs", {"distance_in": 18.0}, "Entrenched -1 over 12\"")


func test_evasive_the_stand_down_and_aircraft_write_their_to_hit_notes() -> void:
	await _door_says("evasive", _plain_shooter(), _plain_target(10, ["Evasive"]), "To-hit vs", {"distance_in": 14.0}, "Evasive -1")
	await _door_says("evasive stand-down", _plain_shooter("saurians", "aof"),
		_plain_target(10, ["Empyrean Spirit", "Enhanced Empyrean Spirit"], "ghostly_undead", "aof"),
		"To-hit vs", {"distance_in": 14.0}, "Enhanced Empyrean Spirit: -1 to hit (base Evasive stood down)")
	await _door_says("aircraft", _plain_shooter(), _plain_target(1, ["Aircraft", "Tough(6)"]), "To-hit vs", {"distance_in": 10.0}, "Aircraft -1")


func test_shot_modifiers_and_instinctive_write_their_to_hit_notes() -> void:
	await _door_says("good shot", _unit("Gunners", 6, ["Good Shot"], [], "saurians", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", {"distance_in": 14.0}, "Good Shot +1")
	await _door_says("bad shot", _unit("Gunners", 6, ["Bad Shot"], [], "orc_marauders", "gf", 6), _plain_target(), "To-hit vs", {"distance_in": 14.0}, "Bad Shot -1")
	await _door_says("buccaneer >9", _unit("Gunners", 6, ["Buccaneer"], [], "sky_city_dwarves", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", {"distance_in": 14.0}, "Buccaneer +1")
	await _door_says("buccaneer <=9", _unit("Gunners", 6, ["Buccaneer"], [], "sky_city_dwarves", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", {"distance_in": 6.0})
	await _door_says("targeting visor", _unit("Gunners", 6, ["Targeting Visor"], [], "dao_union", "gf", 6), _plain_target(), "To-hit vs", {"distance_in": 14.0}, "Targeting Visor +1")
	await _door_says("mobile artillery", _unit("Gunners", 6, ["Mobile Artillery"], [], "human_defense_force", "gf", 6), _plain_target(), "To-hit vs", {"distance_in": 14.0}, "Mobile Artillery +1")
	await _door_says("instinctive", _unit("Gunners", 6, ["Instinctive"], [], "goblins", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", {"distance_in": 14.0}, "Instinctive +1 (closest target)")


func test_multi_fragment_order_and_zero_net_still_log_the_to_hit_note() -> void:
	# Artillery +1 + Good Shot +1 vs Stealth -1 + Evasive -1 -> net 0, still logged in exact table order.
	var att := _unit("Gunners", 6, ["Artillery", "Good Shot"], [], "saurians", "aof", 6)
	var tgt := _plain_target(10, ["Stealth", "Evasive"], "saurians", "aof")
	await _door_says("net-zero order", att, tgt, "To-hit vs", {"distance_in": 18.0},
		"Artillery +1 (Held, target over 12\"), Stealth -1, Evasive -1, Good Shot +1 → hits on 4+")
	await _door_says("plain control", _plain_shooter(), _plain_target(), "To-hit vs", {"distance_in": 14.0})


func test_takedown_writes_its_three_lines_and_embeds_the_to_hit_note() -> void:
	var sniper := _unit("Snipers", 3, [], ["Takedown", "AP(1)"], "battle_brothers", "gf", 3)
	await _door_says("takedown troopers", sniper, _plain_target(10), "Takedown", {"distance_in": 14.0}, "unit of [1]: hits on 4+, no cover of its own, saves on 4+")
	await _door_says("takedown no takes-line", sniper, _plain_target(10), "Targets takes", {"distance_in": 14.0})
	await _door_says("takedown tough", sniper, _plain_target(3, ["Tough(3)"]), "Takedown", {"distance_in": 14.0}, "Tough(3) model")
	var boosted := _unit("Snipers", 3, ["Good Shot"], ["Takedown"], "saurians", "aof", 3)
	var stealth_tgt := _plain_target(10, ["Stealth"], "saurians", "aof")
	await _door_says("takedown with note (to-hit)", boosted, stealth_tgt, "To-hit vs", {"distance_in": 14.0}, "Stealth -1, Good Shot +1")
	await _door_says("takedown with note (ctx)", boosted, stealth_tgt, "Takedown", {"distance_in": 14.0}, "hits on 4+, Stealth -1, Good Shot +1, no cover of its own, saves on 4+")
	var unit_td := _unit("Snipers", 3, ["Takedown when Shooting"], [], "saurians", "aof", 3)
	await _door_says("takedown when shooting", unit_td, _plain_target(10, [], "saurians", "aof"), "Takedown", {"distance_in": 14.0}, "Takedown when Shooting (Gun): targets the trooper")

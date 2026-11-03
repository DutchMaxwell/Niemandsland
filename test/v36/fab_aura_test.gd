extends GdUnitTestSuite
## AIG-G2 (0.3.15): the import-time aura expansion grants every aura's base rule to the whole unit,
## but the table never wrote a battle-log line for the grant. At battle start the game must log ONE
## line per granted aura effect, naming the aura and the bearer; every other log line stays
## byte-identical. The battle is built through the real offline importer, the real joined-hero pass,
## the real aura expansion and the real game-phase seam (OPRArmyManager.start_game), not a hand-built
## field: the ratmen list carries two aura bearers (one of them with two auras) and the custodian
## list the third, one per book.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RATMEN := "res://test/fixtures/card_list_aof_ratmen_1500.json"
const CUSTODIAN := "res://test/fixtures/card_list_gf_custodian_brothers_1000.json"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	_main.opr_army_manager.current_round = 1
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_main.solo_ai_slots = {2: true}   # no AI handoff and no hotseat inventory lines at the flip


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The ratmen export with Getrie's second aura: the same book's "God-Mother's Blight" item (its
## Brother Hepalit already carries it) selected onto the Tinkering Inventor. One bearer, two auras,
## both resolved from the real mechanics map.
func _ratmen_with_two_auras() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RATMEN))
	var blight: Dictionary = {}
	var getrie: Dictionary = {}
	for u: Dictionary in data.get("units", []):
		if str(u.get("name", "")) == "Brother Hepalit":
			for it: Dictionary in u.get("items", []):
				if str(it.get("name", "")) == "God-Mother's Blight":
					blight = it
		elif str(u.get("name", "")) == "Getrie Veikasip":
			getrie = u
	if not blight.is_empty() and not getrie.is_empty():
		getrie["items"] = (getrie.get("items", []) as Array) + [blight]
		getrie["loadout"] = (getrie.get("loadout", []) as Array) + [blight]
	return data


## Import one real list through the production path and register its GameUnits on the table.
func _import(path: String, data: Dictionary, pid: int) -> void:
	var client := OPRApiClient.new()
	var army := client.build_army_offline(data)
	army.player_id = pid
	var by_unit := {}
	for unit: OPRApiClient.OPRUnit in army.units:
		var nodes: Array[Node3D] = []
		for i in range(maxi(unit.size, 1)):
			var n := Node3D.new()
			_main.object_manager.add_child(n)
			nodes.append(n)
		var gu := EquipmentDistributor.create_from_opr_unit(unit, nodes, pid)
		gu.unit_properties["faction_folder"] = army.faction_folder
		by_unit[unit] = gu
	OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
	OPRArmyManager.expand_auras_of(army.units, by_unit)
	_main.opr_army_manager.armies[pid] = army
	for unit: OPRApiClient.OPRUnit in army.units:
		var gu: GameUnit = by_unit[unit]
		_main.opr_army_manager.unit_to_game_unit[unit] = gu
		_main.opr_army_manager.game_units[gu.unit_id] = gu
	client.free()


func _build_battle() -> void:
	_import(RATMEN, _ratmen_with_two_auras(), 1)
	_import(CUSTODIAN, JSON.parse_string(FileAccess.get_file_as_string(CUSTODIAN)), 2)


func _start() -> void:
	_main.opr_army_manager.start_game()
	await E2EBoot.settle(get_tree())


func _texts() -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		out.append(str((e as Dictionary)["text"]))
	return out


## Aura grant lines are the only ones that name an aura ("<Aura>: <bearer> grants <effect> to ...").
func _aura_lines() -> Array:
	var out: Array = []
	for t: String in _texts():
		if t.contains(" Aura: ") and t.contains(" grants "):
			out.append(t)
	return out


func _non_aura_lines() -> Array:
	var out: Array = []
	for t: String in _texts():
		if not (t.contains(" Aura: ") and t.contains(" grants ")):
			out.append(t)
	return out


func test_battle_start_logs_one_line_per_granted_aura_effect() -> void:
	_build_battle()
	await _start()
	var want: Array = [
		"Increased Shooting Range Aura: Getrie Veikasip grants Increased Shooting Range to Monks",
		"Bane in Melee Aura: Getrie Veikasip grants Bane in Melee to Monks",
		"Bane in Melee Aura: Brother Hepalit grants Bane in Melee to Snipers",
		"Steadfast Aura: Custodian Brothers grants Steadfast to Custodian Brothers",
	]
	assert_array(_aura_lines()).override_failure_message(
		"one line per granted aura effect, in deployment order (log: %s)" % str(_texts())) \
		.contains_exactly(want)


func test_battle_start_leaves_every_other_log_line_untouched() -> void:
	_build_battle()
	await _start()
	assert_array(_non_aura_lines()).override_failure_message(
		"the aura lines must not replace or reorder the existing log (log: %s)" % str(_texts())) \
		.contains_exactly(["Battle started"])
	assert_int(_aura_lines().size()).override_failure_message(
		"exactly one line per granted aura effect — no duplicate for the two-aura bearer").is_equal(4)
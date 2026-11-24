extends GdUnitTestSuite
## Rules 3.6 Unstable terrain: a model that moves over 6" into or through a ruin takes the Dangerous test. A live game
## logged "takes one Dangerous terrain test" for a unit that had only rushed through a ruin - no Dangerous terrain on
## the table near it - so the log must name the cause. These cases pin both causes on the same 12" line move: a ruin
## band names Unstable ruins in the test line (and in the AI's sidestep note), a Dangerous band keeps today's line.
## Real: SoloController._execute_move, main._solo_log_dangerous_test, BattleLog. Constructed: the painted band.

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _solo: SoloController
var _main: Node
var _epoch0: int
var _rect := Rect2()   # inches: x0, z0, w, h
var _type := TerrainRules.TerrainType.RUINS


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_93_DANGER_RULES_RIDER   # Unstable (73) and the AI sidestep (93) both live
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	_solo.terrain_type_at = func(p: Vector3) -> int:
		return _type if _rect.has_point(Vector2(p.x / IN2M, p.z / IN2M)) else TerrainRules.TerrainType.NONE
	_main = auto_free(load("res://scripts/main.gd").new())
	_main.battle_log = auto_free(BattleLog.new())
	_main.solo_controller = _solo


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	_solo._player_move = false


## Five one-wound models in a row (1.5" apart, 32 mm bases) at z 0 move 12" toward (0, 14"); answers the model count
## that takes the Dangerous test. `player` = a player's order (never re-aimed around the band).
func _line_move(tag: String, type: int, patch: Rect2, player: bool) -> GameUnit:
	_type = type
	_rect = patch
	_solo.board_clamp_notes = []
	_solo._player_move = player
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = tag
	u.unit_properties = {"player_id": 2, "special_rules": [], "name": tag, "quality": 4, "defense": 4}
	for i in range(5):
		var m := ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.wounds_max = 1
		m.wounds_current = 1
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3((float(i) - 2.0) * 1.5 * IN2M, 0, 0)
		u.models.append(m)
	_mgr.game_units[tag] = u
	u.set_meta("dang", _solo._execute_move(u, Vector3(0, 0, 14.0 * IN2M), 12.0, false))
	_mgr.game_units.erase(tag)
	return u


## The battle-log lines the test writer prints for `u` with the move's dice.
func _logged(u: GameUnit) -> Array:
	_main._solo_log_dangerous_test(u, _solo.last_dangerous_dice)
	return (_main.battle_log.entries() as Array).map(func(e: Dictionary) -> String: return str(e["text"]))


func test_a_rush_through_a_ruin_names_unstable_ruins_in_the_test_line() -> void:
	# A band of ruin across the whole board between 4" and 8": no way around it, the 12" move crosses it.
	var u := _line_move("Beasts", TerrainRules.TerrainType.RUINS, Rect2(-60.0, 4.0, 120.0, 4.0), true)
	assert_int(int(u.get_meta("dang"))).override_failure_message("the 12-inch move through the ruin takes the test").is_greater(0)
	var lines := _logged(u)
	assert_str(str(lines[-1])).override_failure_message("the line names the Unstable cause: %s" % [lines]) \
		.is_equal("Beasts moved over 6\" through Unstable ruins: one Dangerous terrain test for the whole unit (5 dice)")
	# The cause is read once: a later test of the same unit (a transport wreck, say) is a plain Dangerous test again.
	assert_str(str(_logged(u)[-1])).is_equal("Beasts takes one Dangerous terrain test for the whole unit (%d dice)" % _solo.last_dangerous_dice)


func test_a_crossing_of_dangerous_terrain_keeps_the_dangerous_line() -> void:
	var u := _line_move("Grunts", TerrainRules.TerrainType.DANGEROUS, Rect2(-60.0, 4.0, 120.0, 4.0), true)
	assert_int(int(u.get_meta("dang"))).is_greater(0)
	var lines := _logged(u)
	assert_str(str(lines[-1])).is_equal("Grunts takes one Dangerous terrain test for the whole unit (5 dice)")
	assert_str(str(lines)).not_contains("Unstable")


func test_the_ai_sidestep_names_what_it_skirted() -> void:
	# A small patch mid-route the AI line can skirt (the #3090 sidestep geometry).
	var patch := Rect2(2.5, 4.0, 3.0, 4.0)
	_line_move("Ruin", TerrainRules.TerrainType.RUINS, patch, false)
	assert_str(str(_solo.board_clamp_notes)).contains("Ruin sidesteps Unstable ruins (")
	_line_move("Field", TerrainRules.TerrainType.DANGEROUS, patch, false)
	assert_str(str(_solo.board_clamp_notes)).contains("Field sidesteps Dangerous ground (")

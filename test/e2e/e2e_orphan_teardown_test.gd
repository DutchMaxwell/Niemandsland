extends GdUnitTestSuite
## E2E — the wandering "13 orphans" CI report, pinned deterministically.
##
## WHAT HAPPENED. A solo activation does not end when the resolver a test awaits returns: the
## round/turn bookkeeping runs on trailing continuations. One of them clears the shooter's activation,
## and radial_menu_controller._update_token() takes the ACTIVATED status token down with
## `remove_child()` + `queue_free()`. From remove_child on, that subtree is DETACHED — and gdUnit's
## orphan monitor counts exactly the nodes outside the tree. It is 13 nodes: marker root + Border +
## Disc + LetterLabel + one Label3D per character of "ACTIVATED". No other token reaches 13 (CASTS 9,
## WOUNDS/SHAKEN 10, FATIGUED 12), which is why the report was always that same number.
##
## WHY IT WANDERED. gdUnit snapshots orphans right after the test BODY (GC_ORPHANS_CHECK.TEST_CASE),
## before after_test, and pumps no frame there. The continuation lands in that narrow window — but
## only when the volley's REAL dice wipe the targets, so the same suite reported 13 or 0 from run to
## run, and the report moved between e2e_cast_split_ux_test and e2e_split_fire_test.
##
## HOW THIS SUITE PINS IT. The volley below is stacked to be LETHAL (quality 2 shooter, 12 attacks per
## weapon, defense 6 targets), so both target units die every run and the takedown always fires — no
## dice luck involved. E2EBoot.settle() then lets the game go quiet before the body returns. Drop that
## call and this suite reports the 13 orphans again and the after_test assertion fails; that red was
## run, not assumed.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

## Marker root + Border + Disc + LetterLabel + one arc character per letter of "ACTIVATED".
const ACTIVATED_TOKEN_NODES := 4 + 9

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _orphans_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_orphans_before = get_tree().root.get_orphan_node_ids()


func after_test() -> void:
	# Asserted BEFORE the teardown sweep, and deliberately not left to gdUnit: its orphan report is a
	# warning that only surfaces as a non-zero exit code, while this must fail loudly and by name.
	assert_int(_new_orphans()) \
		.override_failure_message("a finished activation left its status token detached — that is the CI orphan report") \
		.is_equal(0)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Orphan nodes that appeared during this test (the boot's own are filtered out) — the same measure
## gdUnit's orphan monitor reports.
func _new_orphans() -> int:
	var n := 0
	for id in get_tree().root.get_orphan_node_ids():
		if not _orphans_before.has(id):
			n += 1
	return n


## A unit whose weapons cannot miss much and whose armour cannot save much — the point is a
## guaranteed wipe, not a realistic profile.
func _armed(pid: int, unit_name: String, pos: Vector3, weapon_names: Array, quality: int, defense: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = quality
	u.unit_properties["defense"] = defense
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wn in weapon_names:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wn)
		w.range_value = 24
		w.attacks = 12
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_a_finished_activation_leaves_no_detached_status_token(timeout := 240000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle", "Cannon"], 2, 4)
	var foe_a := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [], 4, 6)
	var foe_b := _armed(2, "FoeB", Vector3(0, 0, 8.0 * INCH), [], 4, 6)

	await _main._run_human_attack_split(shooter, foe_a, foe_b, ["Cannon"])

	# The fixture only pins the flake while it really does wipe the table — a volley that stopped
	# killing would make this suite pass for the wrong reason.
	assert_int(foe_a.get_alive_count() + foe_b.get_alive_count()) \
		.override_failure_message("the fixture must stay lethal, otherwise the takedown never fires") \
		.is_equal(0)
	assert_bool(shooter.is_activated) \
		.override_failure_message("the activation must complete — it is what puts the token on the table") \
		.is_true()

	# THE FIX UNDER TEST. Without this the trailing round bookkeeping detaches the ACTIVATED token
	# after the body has returned but before gdUnit reads, and all 13 nodes are counted.
	await E2EBoot.settle(get_tree())


func test_the_activated_token_really_is_thirteen_nodes() -> void:
	# Guards the number the whole diagnosis rests on: if the disc ever grows a node or the label is
	# renamed, this says so instead of letting a future "13 orphans" hunt start from a stale premise.
	var unit := E2EBoot.make_unit(_main, 1, "Grunts", [Vector3.ZERO])
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	unit.activate(1)
	_main.radial_menu_controller._update_activated_markers(unit)
	var marker: Node = (unit.models[0].node as Node3D).get_node_or_null("ActivatedMarker")
	assert_object(marker) \
		.override_failure_message("activating a unit must put its ACTIVATED token on the table") \
		.is_not_null()
	assert_int(_count_subtree(marker)) \
		.override_failure_message("the ACTIVATED token's node count is the CI orphan count") \
		.is_equal(ACTIVATED_TOKEN_NODES)


func _count_subtree(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_subtree(c)
	return n

extends RefCounted
## Shared plumbing for the END-TO-END suites in test/e2e/.
##
## WHY THIS LAYER EXISTS. The rest of test/ is unit level: no suite loads scripts/main.gd, so four
## defects that lived in main.gd's own flow reached the maintainer while the suite reported 1694 green
## — the deployment gate could be walked around, menu clicks fell through to the battlefield, the log
## export was truncated, and an AI path label was positioned before it entered the tree. The suites in
## this directory boot the REAL scenes/main.tscn, let its real _ready() run, and drive the real
## functions, so that class of defect fails in CI instead of in the maintainer's hands.
##
## This file is NOT a test suite (gdUnit only collects *_test.gd) — it is the helper the suites share.

## The real game scene. Its root node is named "Main", so once it is mounted it lives at /root/Main and
## every hardcoded absolute path in main.gd / object_manager.gd resolves exactly as in play.
const MAIN_SCENE := "res://scenes/main.tscn"

## main.gd:737 reads this ProjectSetting in _ready(). Set, it skips the interactive table-size chooser
## (an EXCLUSIVE modal that would await a click no headless test can make) and the cinematic intro, and
## call_deferred("_on_intro_finished") instead. Must be set BEFORE the scene is instantiated.
## Same seam the shipped test/mp/mp_harness.gd and tools/tutorial_smoke.gd already use.
static func arm_harness_mode() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)


## Snapshot of /root's children, taken BEFORE a boot.
## main.gd mounts two Windows on the TREE ROOT rather than on itself — lighting_panel (main.gd:534) and
## opr_import_dialog (main.gd:583) — and the scene runner's teardown only frees its own scene, so both
## outlive the test. gdUnit's orphan detector does not see root-mounted children, so this leak is
## silent: measured 1505 -> 1689 nodes over two boots while gdUnit still reported "0 orphans".
static func root_children(tree: SceneTree) -> Array:
	if tree == null or tree.root == null:
		return []
	return tree.root.get_children()


## Free everything main.gd parked on /root during a boot. Call from after_test() with the snapshot
## taken in before_test().
static func free_stray_root_nodes(tree: SceneTree, before: Array) -> void:
	if tree == null or tree.root == null:
		return
	for child in tree.root.get_children():
		if before.has(child):
			continue
		if not is_instance_valid(child):
			continue
		tree.root.remove_child(child)
		child.free()


## Push a real mouse button event through the viewport's full input pipeline (_input -> GUI ->
## _unhandled_input), the way the engine does in play.
##
## TWO TRAPS, both measured on Godot 4.6.2 headless:
##  1. gdUnit's own simulate_mouse_button_pressed() does NOT work headless. It routes through
##     Input.parse_input_event + flush_buffered_events, which the headless DisplayServer drops, and its
##     fallback only calls _gui_input/_unhandled_input on the SCENE ROOT — so it never presses a Button.
##     Viewport.push_input() has no DisplayServer involvement and works.
##  2. COORDINATE SPACES. Headless the window is 1280x720 while stretch/mode=canvas_items targets
##     1920x1080, so the viewport carries a 0.667 scale. Control.get_global_rect() and
##     Camera3D.unproject_position() speak CANVAS coordinates; push_input() expects SCREEN coordinates
##     and divides them back out. Skip the conversion and every click lands 1.5x off — on a NEIGHBOURING
##     widget, while the test still "passes".
static func click_canvas(vp: Viewport, canvas_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = vp.get_screen_transform() * canvas_pos
	ev.global_position = ev.position
	vp.push_input(ev)


## Push a mouse MOTION event, same coordinate rules as click_canvas().
static func motion_canvas(vp: Viewport, canvas_pos: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = vp.get_screen_transform() * canvas_pos
	ev.global_position = ev.position
	ev.relative = relative
	vp.push_input(ev)


## A GameUnit with `count` live models parked at `positions`, owned by `pid`. The model nodes are
## parented under `host` so they are real tree nodes with real global transforms — which is what
## main.gd's table-rect test reads.
static func make_unit(host: Node, pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "e2e_p%d_%s" % [pid, unit_name]
	u.unit_properties = {
		"player_id": pid,
		"name": unit_name,
		"quality": 4,
		"defense": 4,
		"network_id": u.unit_id,
	}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		n.name = "%s_m%d" % [unit_name, u.models.size()]
		host.add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## Move every model of `u` to `pos` (models are spread on a small line so they stay distinguishable).
static func place_unit_at(u: GameUnit, pos: Vector3) -> void:
	var i := 0
	for m in u.models:
		var mi := m as ModelInstance
		if mi == null or mi.node == null or not is_instance_valid(mi.node):
			continue
		mi.node.global_position = pos + Vector3(0.03 * i, 0.0, 0.0)
		i += 1

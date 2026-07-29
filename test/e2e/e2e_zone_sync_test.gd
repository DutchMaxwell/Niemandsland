extends GdUnitTestSuite
## E2E — #194/#195: deployment zones in multiplayer. #195: when both peers ticked "Show
## Deployment Zones", the zones flashed permanently — every inbound settings message
## mirrored the checkbox via `button_pressed =`, which RE-EMITS `toggled`, whose handler
## broadcast right back: a ping-pong loop between the peers. #194: the guest's tick was a
## silent no-op — visibility only flips EXISTING meshes, and the guest often never received
## the zone geometry (a guest's own Map-Tool emission could even wipe the host's).
##
## Fix under test, on the real main.tscn: visibility + colour-flip are strictly LOCAL view
## preferences (no broadcast, no receive); programmatic checkbox writes use
## set_pressed_no_signal; zone GEOMETRY (deployment_type) stays synced host→guest only.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


## Stands in for NetworkManager at main's seam: "multiplayer is live" + records every
## outbound table-settings broadcast — the ping-pong detector.
class FakeNet extends Node:
	var is_host: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func broadcast_table_settings(s: Dictionary) -> void:
		sent.append(s)
	func slot_has_human_peer(_slot: int) -> bool:
		return false

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _sent_keys() -> Array:
	var keys: Array = []
	for s in _fake.sent:
		keys.append_array((s as Dictionary).keys())
	return keys


func test_inbound_zone_message_never_broadcasts_back(timeout := 120000) -> void:
	# The #195 loop: receiving the zone type mirrored the checkbox WITH signal — the
	# toggled handler then broadcast "deployment_visible" straight back to the sender.
	_main._on_remote_table_settings_changed({"deployment_type": 1})
	await _runner.simulate_frames(2)
	assert_array(_sent_keys()) \
		.override_failure_message("#195 — an INBOUND zone message produced an outbound broadcast (%s): this is the ping-pong that made both peers' zones flash permanently" % str(_sent_keys())) \
		.is_empty()
	# The mirror itself must still happen (box reads ON) and the geometry must exist.
	assert_bool(_main.deployment_zone_check.button_pressed).is_true()
	assert_bool((_main.terrain_overlay.deployment_zone_meshes as Array).is_empty()) \
		.override_failure_message("#194 — receiving the zone type built no meshes: the guest's 'Show Deployment Zones' tick stays a silent no-op") \
		.is_false()


func test_visibility_toggle_is_strictly_local(timeout := 120000) -> void:
	_main._on_deployment_zones_visibility_toggled(true)
	_main._on_deployment_flip_toggled(true)
	assert_array(_sent_keys()) \
		.override_failure_message("#194/#195 — a per-player VIEW preference was broadcast (%s); visibility and colour flip must stay local" % str(_sent_keys())) \
		.is_empty()


func test_zone_geometry_is_host_authoritative(timeout := 120000) -> void:
	# A guest's Map Tool emits deployment_type_changed from non-user paths too (load/sync);
	# its push used to wipe the host's zone meshes mid-game ("kept going throughout").
	_fake.is_host = false
	_main._on_deployment_type_changed(1)
	assert_array(_sent_keys()) \
		.override_failure_message("#194 — a GUEST broadcast deployment_type: a guest opening its Map Tool wipes the host's zones") \
		.is_empty()
	# The host still syncs geometry to its guests.
	_fake.is_host = true
	_main._on_deployment_type_changed(1)
	assert_array(_sent_keys()).contains(["deployment_type"])

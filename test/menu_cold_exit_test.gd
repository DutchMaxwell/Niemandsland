extends GdUnitTestSuite
## Cold-cache menu exit (PR 1). The start menu's diorama builds its miniatures over awaited frames and, on a
## cold model cache, awaited downloads. A player who presses Create meanwhile takes the menu out of the tree
## while that build is suspended; every resumed step must stop quietly. Before this fix each clean-profile
## start logged "Parameter data.tree is null" + 3 SCRIPT ERRORs (asset_download_manager ensure_batch_parallel,
## menu_battlefield _build_units and build: get_tree() on a node that had left the tree).

const Battlefield := preload("res://scripts/menu_battlefield.gd")

var _server: TCPServer = null


func after_test() -> void:
	if _server != null:
		_server.stop()
		_server = null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _batch_into(m: AssetDownloadManager, entries: Array, state: Dictionary) -> void:
	await m.ensure_batch_parallel(entries, 1, 0)
	state["done"] = true


## The download manager a menu model library owns: its batch is pending on a server that accepts and never
## answers (a slow first download), then the menu leaves the tree. The batch must give up quietly.
func test_download_batch_gives_up_when_its_owner_leaves_the_tree() -> void:
	_server = TCPServer.new()
	var port := 20000 + randi() % 20000
	assert_int(_server.listen(port, "127.0.0.1")).is_equal(OK)
	var m := AssetDownloadManager.new()
	m.cache_dir = "user://menu_cold_exit_test_cache"
	add_child(m)
	var state := {}
	var entry := {"url": "http://127.0.0.1:%d/slow.glb" % port, "sha256": "menu_cold_exit_probe",
		"path": m.cache_path("menu_cold_exit_probe")}
	_batch_into(m, [entry], state)
	await _frames(5)
	assert_bool(state.has("done")).override_failure_message("the download was not pending — the test proves nothing").is_false()
	remove_child(m)   # the menu scene leaves the tree; the scene change frees it only later
	await _frames(10)
	assert_bool(state.has("done")) \
		.override_failure_message("the batch kept waiting on a manager that left the tree").is_true()
	m.free()


## Holder + the nodes build() reparents into the diorama (environment, sun, camera).
func _battlefield() -> Array:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	holder.add_child(env)
	var sun := DirectionalLight3D.new()
	holder.add_child(sun)
	var lens := Camera3D.new()
	holder.add_child(lens)
	var light: Node = auto_free(Node.new())
	var field: Node3D = Battlefield.new()
	holder.add_child(field)
	return [holder, field, env, sun, light, lens]


## The menu leaves right after the terrain, before any miniature: nothing more is built.
func test_menu_left_before_the_miniatures_builds_nothing_more() -> void:
	var parts := _battlefield()
	var holder: Node3D = parts[0]
	var field: Node3D = parts[1]
	var labels: Array = []
	field.progress.connect(func(label: String, _ratio: float) -> void: labels.append(label))
	field.build("urban_ruins", parts[2], parts[3], parts[4], parts[5])   # runs to its first await
	holder.remove_child(field)
	await _frames(10)
	assert_bool(labels.has("Preparing miniatures")) \
		.override_failure_message("the diorama kept building after the menu left the tree").is_false()
	field.free()


## The menu leaves while the miniatures are being placed (the first model stands): no further model.
func test_menu_left_mid_miniatures_places_no_further_model(timeout := 120000) -> void:
	var parts := _battlefield()
	var holder: Node3D = parts[0]
	var field: Node3D = parts[1]
	field.build("urban_ruins", parts[2], parts[3], parts[4], parts[5])
	var deadline := Time.get_ticks_msec() + 90000
	while field.model_count < 1 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(field.model_count).override_failure_message("no miniature was placed (model cache/download) — the test proves nothing").is_equal(1)
	holder.remove_child(field)
	await _frames(10)
	assert_int(field.model_count) \
		.override_failure_message("the diorama placed more miniatures after the menu left the tree").is_equal(1)
	field.free()

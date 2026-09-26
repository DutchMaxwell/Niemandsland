extends Node
## SHIP PROBE (macOS core, 26.09.2026) — the proof that an EXPORTED build plays Erlkönig.
## Mounts the REAL scenes/main.tscn, applies the default NACHTMAHR grade exactly as a Solo game
## does (so main.gd prints its own "opponent: erlkoenig ..." line), then asks the shipped
## Rust core for one real activation pick on a two-unit board (the e2e_core_reload_test path),
## which runs the packed net through the extension. Prints ONE "NML_SHIP_PROBE {json}" marker.
##
## An export template does not honour `-s <script>` (measured 26.09. on the Linux export: no
## output, the menu just idles), so this runs as a SCENE passed as the start argument:
##   Niemandsland.app/Contents/MacOS/Niemandsland --headless res://tools/core_ship_probe.tscn
## Exit 0 = every leg true, 1 = a leg false, 2 = the watchdog tripped.

const MAIN_SCENE := "res://scenes/main.tscn"
const SETTLE_FRAMES := 8
const WATCHDOG_SECONDS := 240.0


func _ready() -> void:
	# main.gd reads this in _ready(): no table-size chooser, no intro (same seam as tutorial_smoke).
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		print("NML_SHIP_PROBE_TIMEOUT after %d s" % int(WATCHDOG_SECONDS))
		get_tree().quit(2))
	_drive.call_deferred()


func _drive() -> void:
	var tree := get_tree()
	# The scene's root is named "Main": mounted under /root it lives at /root/Main, where main.gd's
	# and object_manager.gd's absolute paths expect it (e2e_boot.gd MAIN_SCENE note).
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(main)
	for _i in SETTLE_FRAMES:
		await tree.process_frame

	var report := {
		"os": OS.get_name(),
		"arch": Engine.get_architecture_name(),
		"class_present": ClassDB.class_exists("NmlCore"),
		"core_enabled": BattleSim.core_enabled(),
	}
	# Same calls as the Solo panel path (e2e_core_reload_test._arm): prints "opponent: erlkoenig ..."
	# when the core is up and the packed brain was accepted, "opponent: tree — ..." otherwise.
	main.solo_ai_slots = {2: true}
	main._solo_difficulty_grades = {}
	main._ensure_solo_controller()
	main._solo_apply_difficulty()
	var sc: SoloController = main.solo_controller
	report["brain_sha"] = sc.shipped_brain_sha if sc != null else ""
	report["planner"] = sc != null and sc.difficulty_by_slot.has(2) and sc.difficulty_by_slot[2].planner

	var picked := false
	if sc != null and report["planner"]:
		for side in [1, 2]:
			var u := _make_unit(main, side, "probe_unit_%d" % side, Vector3(float(side - 1) * 0.75, 0, 0))
			main.opr_army_manager.game_units[u.unit_id] = u
		var pool: Array = []
		for gu in sc.army_manager.game_units.values():
			if int(gu.unit_properties.player_id) == 2:
				pool.append(gu)
		picked = sc._planner_pick_unit(pool) != null
	report["picked"] = picked
	report["core_calls"] = sc._core_calls if sc != null else 0
	report["declines"] = str(sc._core_declines) if sc != null else "no controller"
	var declines: String = report["declines"]
	var ok: bool = report["class_present"] and report["core_enabled"] and report["planner"] \
		and str(report["brain_sha"]) != "" and picked and int(report["core_calls"]) > 0 \
		and not declines.contains("rules registry") and not declines.contains("unreadable") \
		and not declines.contains("LeafValue")
	report["ok"] = ok
	print("NML_SHIP_PROBE " + JSON.stringify(report))
	tree.quit(0 if ok else 1)


## A one-model OPR unit on the main table (the shape e2e_boot.make_unit + e2e_core_reload_test build;
## test/ is not in the export, so the few lines are copied, not imported).
func _make_unit(host: Node, pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "probe_p%d_%s" % [pid, unit_name]
	u.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4, "network_id": u.unit_id}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n := Node3D.new()
	n.name = "%s_m0" % unit_name
	n.set_meta("game_unit", u)
	host.add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var weapon := OPRApiClient.OPRWeapon.new()
	weapon.name = "CCW"
	weapon.attacks = 1
	weapon.count = 1
	var data := OPRApiClient.OPRUnit.new()
	data.weapons.append(weapon)
	u.source_type = "opr"
	u.source_data = data
	m.wounds_current = 1
	return u

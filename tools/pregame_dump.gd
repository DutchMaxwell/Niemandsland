extends RefCounted
## NML-1152 step 1 — the pregame fixture builder (deployment-parity design §4.1). Rides the REAL
## arena_match harness (tools/arena_match.gd `dump=<dir>`): called after BOTH _deploy_side calls
## and the settle pass, BEFORE seed(_dice_seed) — repairs cross slots, so these positions are
## final. Writes ONE JSON per run; the caller quits without playing. Everything the twin must
## replay draw-for-draw: streams, roll-off attempts + winner, deploy order, per-side deploy seeds,
## physics-probe counts (§4.3), transport fills, and per-unit final board state (spot = the
## placement record's anchor, models = the settled node positions).
##
## Extraction rules (verified against solo_controller.gd):
##  * deploy records carry `unit_id` = the unit's deployment roster id (the `id` all_units
##    is indexed by — deterministic per list, solo_controller.gd:9095/:9160/:9166). `place`
##    and `pushed` key on "side|<unit_id>" — duplicate display NAMES cannot collide (found
##    live on the name-keyed v1 fixture: 4/200 sides, e.g. seed 56, shared one record).
##  * the LAST deploy record with x_m/z_m wins: the vanguard record (x_m/z_m, no section) is
##    emitted BEFORE the final placement record (section + x_m/z_m), so last-wins yields the
##    pushed spot WITH its section. Repair records carry no x_m/z_m and never override.
##  * `placement_order` per side = the FINAL placement records in arrival order — the main
##    queue then the scout queue, exactly the table's deploy sequence (solo_controller.gd:9038,
##    :9071-9083). Vanguard/repair records carry no `section` and are excluded.
##  * `records` arrive side-annotated (arena_match annotates at capture time — solo.ai_slot has
##    moved on by dump time).

const RESULT_SCHEMA := 1   # shared with arena_match.gd's result schema constant


static func write(out_dir: String, army1: String, army2: String, seed_v: int, dice_seed: int,
		layout_seed: int, symmetric: bool, opener: int, deploy_order: Array,
		knob_records: Array, records: Array, probe_hits: Dictionary, tray: Dictionary,
		army_manager: Node, solo: Node) -> void:
	var attempts: Array = []
	for r in knob_records:
		if str((r as Dictionary).get("kind", "")) == "roll_off":
			var dd: Dictionary = (r as Dictionary)["data"]
			attempts.append({"p1": int(dd.get("p1", 0)), "p2": int(dd.get("p2", 0))})
	var place := {}    # "side|<unit_id>" → last deploy record data with x_m/z_m (final anchor)
	var pushed := {}   # "side|<unit_id>" → saw the vanguard record
	var order := {}    # side(int) → [unit_id, ...] final placement records in arrival order
	var fills := {}    # side(int) → [{transport, cargo}]
	for r in records:
		var rec: Dictionary = r
		var d: Dictionary = rec.get("data", {})
		var side := int(rec.get("side", 0))
		var uname := str(rec.get("unit", ""))
		var key := "%d|%s" % [side, str(rec.get("unit_id", uname))]
		if str(rec.get("why", "")) == "vanguard forward placement":
			pushed[key] = true
		if d.has("x_m") and d.has("z_m"):
			place[key] = d
		if str(rec.get("kind", "")) == "deploy" and d.has("x_m") and d.has("section"):
			var oid: Array = order.get(side, [])
			oid.append(str(rec.get("unit_id", uname)))
			order[side] = oid
		if str(rec.get("why", "")) == "transport fill at deployment":
			var fl: Array = fills.get(side, [])
			fl.append({"transport": uname, "cargo": str(rec.get("chosen", "")).substr(6)})
			fills[side] = fl
	var sides := {}
	for slot in [1, 2]:
		var units: Array = []
		var reserved: Array = []
		var deploy_idx := 0   # the all_units roster id: alive, unattached, unridden (solo_controller.gd:8977-8983)
		for u in army_manager.get_game_units_for_player(slot):
			var gu := u as GameUnit
			if gu == null or int(gu.get_alive_count()) <= 0 or gu.is_attached() \
					or army_manager.transport_of(gu) != null:
				continue
			var uid := str(deploy_idx)
			deploy_idx += 1
			if bool(gu.unit_properties.get("ambush_reserve", false)):
				reserved.append(gu.get_name())
				continue
			var pos: Array = []
			var facing := 0.0
			for m in solo._deploy_models(gu):
				var node: Node3D = (m as ModelInstance).node
				if node == null or not is_instance_valid(node):
					continue
				if pos.is_empty():
					facing = snappedf(node.rotation.y, 0.0001)
				pos.append([snappedf(node.global_position.x, 0.0001), snappedf(node.global_position.z, 0.0001)])
			var pd: Dictionary = place.get("%d|%s" % [slot, uid], {})
			units.append({"key": uid, "name": gu.get_name(), "section": int(pd.get("section", -1)),
				"scout": SoloController.unit_has_scout(gu), "ambush": SoloController.unit_has_ambush(gu),
				"base_r_m": snappedf(solo._deploy_base_radius(solo._deploy_models(gu)), 0.0001),
				# NML-1152 step 6c — the TRUE per-unit base shape, the gate ORACLE
				# (equipment_distributor.gd:360-365 writes these; shape_for_model
				# separation_checker.gd:267-278 reads them). The twin derives its own
				# shape from the lists and the gate compares — never feeds it.
				"base_is_oval": bool(gu.unit_properties.get("base_is_oval", false)),
				"base_width_mm": int(gu.unit_properties.get("base_width_mm", SeparationChecker.DEFAULT_BASE_MM)),
				"base_depth_mm": int(gu.unit_properties.get("base_depth_mm", SeparationChecker.DEFAULT_BASE_MM)),
				"base_size_round": int(gu.unit_properties.get("base_size_round", SeparationChecker.DEFAULT_BASE_MM)),
				"footprint": v2list(solo._deploy_footprint_offsets(gu)),
				"spot": [snappedf(float(pd.get("x_m", 0.0)), 0.0001), snappedf(float(pd.get("z_m", 0.0)), 0.0001)],
				"vanguard_pushed": pushed.has("%d|%s" % [slot, uid]),
				"facing_rad": facing, "models": pos})
		sides[str(slot)] = {"seed_value": seed_v + int(slot),
			"probe_hits": int(probe_hits.get(slot, 0)),
			"fills": fills.get(slot, []), "reserved": reserved,
			"placement_order": order.get(slot, []),
			# NML-1152 step 6e — the PRE-GAME tray layout, INPUT (not an answer)
			"tray_models": tray.get(slot, []),
			"units": units}
	var gh: Array = []
	OS.execute("git", ["rev-parse", "HEAD"], gh)
	var dump := {"schema": RESULT_SCHEMA, "tool": "pregame_dump", "seed": seed_v,
		"dice_seed": dice_seed, "layout_seed": layout_seed,
		"git_head": str(gh[0]).strip_edges() if not gh.is_empty() else "",
		"armies": {"p1": army1, "p2": army2}, "symmetric": symmetric,
		"roll_off_attempts": attempts, "opener": opener, "deploy_order": deploy_order, "sides": sides}
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tag := "%s_vs_%s" % [(army1 as String).get_file().get_basename(), (army2 as String).get_file().get_basename()]
	var path := out_dir.path_join("pregame_%s_s%d.json" % [tag, seed_v])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[ARENA] FATAL: cannot write pregame dump: %s" % path)
		return
	f.store_string(JSON.stringify(dump, "  "))
	f.close()
	printerr("[ARENA] pregame dump: %s" % path)
	print("PREGAME_DUMP %d %s OK" % [seed_v, tag])


## NML-1152 step 6e — the PRE-GAME tray layout, captured BEFORE the first _deploy_side while both
## armies still stand on their side trays (opr_army_manager.gd:1182-1212 + the row packer). This is
## the geometry the table's _deploy_spot_free (solo_controller.gd:9350-9367) sees through BOTH
## finish repairs — every alive model's XZ (the dump's 1e-4 frame, same as unit spots) plus its
## model_base_radius_m bounding radius (:5202-5207). INPUT, not an answer; the twin drops a unit's
## row once its replay places that unit. Roster ids follow the write() walk (same filter, same
## order); a transport fill between snapshot and dump re-keys cargo ids — corpus-absent (0 fills).
static func tray_snapshot(army_manager: Node, solo: Node) -> Dictionary:
	var out := {}
	for slot in [1, 2]:
		var rows: Array = []
		var idx := 0
		for u in army_manager.get_game_units_for_player(slot):
			var gu := u as GameUnit
			if gu == null or int(gu.get_alive_count()) <= 0 or gu.is_attached() \
					or army_manager.transport_of(gu) != null:
				continue
			var pos: Array = []
			for m in solo._deploy_models(gu):
				var node: Node3D = (m as ModelInstance).node
				if node != null and is_instance_valid(node):
					pos.append([snappedf(node.global_position.x, 0.0001),
						snappedf(node.global_position.z, 0.0001),
						snappedf(SoloController.model_base_radius_m(m as ModelInstance), 0.0001)])
			rows.append({"key": str(idx), "name": gu.get_name(), "models": pos})
			idx += 1
		out[slot] = rows
	return out


## Vector2 offsets → JSON [[x, z], ...] at dump precision.
static func v2list(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append([snappedf((v as Vector2).x, 0.0001), snappedf((v as Vector2).y, 0.0001)])
	return out

extends SceneTree
## NML-1158b step 1 — the POLICY corpus writer (READ-ONLY replay dump, the
## act_recheck pattern): restores each act's recorded state + header knobs +
## pure charge gate, RE-DERIVES the search's own menu per unit (a corrupted
## state cannot pass: a mismatching act is flagged and emits NO vectors), then
## writes per candidate the AiClone.menu_tuples tuple + action_vec — the
## APPEND-ONLY layout (clone_train.py:60-64: kinds, plain, geo, cover, sight;
## slots may only ever be appended) — plus the recorded pick index and the
## recorded trace.scored / pool_idx / rs where the act carries them. The
## corpus is never written; the dump file is the only output.
##
## Usage: godot --headless -s res://tools/policy_dump.gd --
##   file=<acts.jsonl> out=<policy_dump.jsonl> [n=0=all] [offset=0]
##   --corrupt=state   RED proof: shift every unit 1 m — the act must be
##                     flagged and dumped empty, exit nonzero.

const NodeRecheck := preload("res://tools/node_recheck.gd")
const SCHEMA := "policy_dump/1"
const VEC_DIM := 5 + 5 + AiClone.GEO_DIM + 2   # kinds, plain, geo, cover, sight
const EPS := 1e-9

var _units_n := 0
var _cands_n := 0


func _init() -> void:
	var file_path := ""
	var out_path := ""
	var n := 0
	var offset := 0
	var corrupt := false
	for a in OS.get_cmdline_user_args():
		if a == "--corrupt=state":
			corrupt = true
			continue
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"file": file_path = kv[1]
				"out": out_path = kv[1]
				"n": n = int(kv[1])
				"offset": offset = int(kv[1])
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		printerr("[POLICY_DUMP] cannot open ", file_path)
		quit(1)
		return
	var header: Dictionary = JSON.parse_string(f.get_line())
	var profiles: Dictionary = header["profiles"]
	var terrain: Variant = header.get("terrain")
	if terrain != null:
		header["terrain_at"] = NodeRecheck.terrain_at_from_plain(terrain as Dictionary)
		# M3-0d: the TERRAIN rebuild is the los source (act_recheck proved it
		# reproduces the recorded live grid); menu_tuples wants "clear", the
		# seam answers "blocked" — one negation, stamped once.
		header["los_blocked"] = NodeRecheck.los_blocked_from_plain(terrain as Dictionary)
	var fresh := not FileAccess.file_exists(out_path)
	var out := FileAccess.open(out_path, FileAccess.WRITE if fresh else FileAccess.READ_WRITE)
	if out == null:
		printerr("[POLICY_DUMP] cannot write ", out_path)
		quit(1)
		return
	if fresh:   # schema version lives in the header; appended rows share it
		out.store_line(JSON.stringify({"kind": "header", "schema": SCHEMA, "act_dim": VEC_DIM,
			"geo_dim": AiClone.GEO_DIM, "vec_layout": "kinds:5,plain:5,geo:8,cover:1,sight:2"}))
	else:
		out.seek_end()
	var knobs: Dictionary = header.get("knobs", {})
	# The only statics the MENU surface reads (candidates/charge gate/engage
	# fold) — the dump re-derives menus, never runs the rollout.
	BattleSim.engage_fold_vintage = 0 if bool(knobs.get("engage_fold", false)) else 1
	BattleSim.hero_fold = bool(knobs.get("hero_attach", false))
	var game := file_path.get_base_dir().get_file()
	var checked := 0
	var skipped := 0
	var flagged := 0
	while (n == 0 or checked < n) and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		if skipped < offset:
			skipped += 1
			continue
		checked += 1
		var act: Dictionary = JSON.parse_string(line)
		var flags := _dump_act(act, header, profiles, out, game, offset + checked,
			corrupt and checked == 1)
		flagged += 1 if not flags.is_empty() else 0
		for fl in flags:
			printerr("[POLICY_DUMP] FLAG act %d: %s" % [offset + checked, str(fl)])
	print("POLICY_DUMP file=%s acts=%d units=%d cands=%d flagged=%d schema=%s out=%s"
		% [game, checked, _units_n, _cands_n, flagged, SCHEMA, out_path])
	if out != null:
		out.flush()
		out.close()
	quit(0 if flagged == 0 else 1)


## One act: rebuild -> stamp -> verify menus -> emit one row per unit menu.
func _dump_act(act: Dictionary, header: Dictionary, profiles: Dictionary,
		out: FileAccess, game: String, act_no: int, corrupt: bool) -> Array:
	var state: Dictionary = NodeRecheck._rebuild_state(act["state"], profiles)
	if corrupt:   # RED: shift EVERY unit 1 m — each acting unit's own centre
		for k in state["units"]:   # feeds its advance/patient/charge geometry
			(state["units"][k] as Dictionary)["positions"][0] = \
				((state["units"][k] as Dictionary)["positions"][0] as Vector3) + Vector3(1.0, 0.0, 0.0)
	var plain_state: Dictionary = act["state"]
	var key_of := {}
	for k in state["units"]:
		key_of[(state["units"][k]["unit"] as GameUnit).get_instance_id()] = str(k)
	if bool(act.get("charge_gate", true)):
		state["charge_illegal"] = func(atk: GameUnit, vic: GameUnit, gap: float,
				ca: Vector3, cv: Vector3) -> bool:
			return BattleSim.charge_illegal_plain(plain_state, header,
				str(key_of.get(atk.get_instance_id(), "")), str(key_of.get(vic.get_instance_id(), "")),
				gap, ca, cv)
	if header.has("terrain_at"):
		state["terrain_at"] = header["terrain_at"]
	var trace: Dictionary = act.get("trace", {})
	var menus: Dictionary = trace.get("menus", {})
	var flags: Array = []
	var activatable := {}
	for k in state["units"]:
		if AiPlanner._can_activate(state["units"][k], int(act["player"])):
			activatable[str(k)] = true
	if activatable.size() != menus.size():
		flags.append("menu.units recorded=%d activatable=%d" % [menus.size(), activatable.size()])
	var board: Array = []
	var first_of := {}
	var score_of := {}
	var pool_pos := {}
	var rs_of := {}
	if flags.is_empty():
		board = BattleSim.board_rows(state)
		var first := 1 << 30
		for s in (trace.get("scored", []) as Array):
			first_of[str(s["unit"])] = mini(int(first_of.get(str(s["unit"]), first)), int(s["idx"]))
			score_of[int(s["idx"])] = float(s["score"])
		for i in range((trace.get("pool_idx", []) as Array).size()):
			pool_pos[int((trace["pool_idx"] as Array)[i])] = i
		for r in (trace.get("rs", []) as Array):
			rs_of[int(r["idx"])] = float(r["rs"])
	var pick: Dictionary = act.get("pick", {})
	var pick_action: Dictionary = (pick.get("action", {}) as Dictionary) \
		if bool(pick.get("used", false)) else {}
	var lb: Callable = header.get("los_blocked", Callable())
	var los_at: Callable = (func(pa: Vector3, pb: Vector3) -> bool: return not lb.call(pa, pb)) \
		if lb.is_valid() else Callable()
	var rows: Array = []
	for k in menus:
		var cands: Array = menus[k]
		if not activatable.has(str(k)):
			flags.append("menu.unit_not_activatable:" + str(k))
			continue
		if flags.is_empty():
			# plan_with_rollout:147-148: a SHAKEN unit's menu is the bare hold —
			# candidates() itself never sees the shaken branch.
			var live: Array = [{"unit": str(k), "kind": AiDecision.Action.HOLD}] \
				if bool((state["units"][k] as Dictionary).get("shaken", false)) \
				else AiPlanner.candidates(state, str(k))
			if live.size() != cands.size():
				flags.append("menu.size:%s recorded=%d got=%d" % [str(k), cands.size(), live.size()])
			else:
				for i in range(cands.size()):
					if not _same_action(cands[i], live[i]):
						flags.append("menu.cand:%s[%d]" % [str(k), i])
						break
		var pick_i := -1
		if str(pick.get("unit_key", "")) == str(k):
			for i in range(cands.size()):
				if _same_action(pick_action, cands[i]):
					pick_i = i
					break
			if pick_i < 0:
				flags.append("pick.not_in_menu:" + str(k))
		if flags.is_empty():
			var flat: Array = []
			for c in cands:
				var cd: Dictionary = (c as Dictionary).duplicate()
				if cd.has("dest"):
					cd["dest"] = _dest3(cd["dest"])
				flat.append(cd)
			var tuples: Array = AiClone.menu_tuples(state, str(k), flat,
				header.get("terrain_at", Callable()), los_at)
			var cands_out: Array = []
			var first := int(first_of.get(str(k), -1))
			for i in range(tuples.size()):
				var t: Dictionary = tuples[i]
				var gi := first + i
				var src: Variant = (cands[i] as Dictionary).get("dest")
				cands_out.append({"i": i, "kind": int(t["kind"]),
					"dest": [float(t["dest_x"]), float(t["dest_z"])],
					"src_dest": src, "vec": AiClone.action_vec(t, board, int(act["player"]), 2),
					"scored": score_of.get(gi), "pool_pos": pool_pos.get(gi), "rs": rs_of.get(gi)})
			rows.append({"kind": "menu_row", "game": game, "act_no": act_no,
				"round": int(act["round"]), "side": int(act["player"]), "unit": str(k),
				"board": board, "pick_idx": pick_i, "cands": cands_out})
	if flags.is_empty():
		for r in rows:
			out.store_line(JSON.stringify(r, "", true, true))
		_units_n += rows.size()
		for r in rows:
			_cands_n += (r["cands"] as Array).size()
	return flags


static func _same_action(a: Variant, b: Variant) -> bool:
	var ad: Dictionary = a
	var bd: Dictionary = b
	if int(ad.get("kind", -1)) != int(bd.get("kind", -1)) \
			or bool(ad.get("patient", false)) != bool(bd.get("patient", false)) \
			or str(ad.get("wave", "")) != str(bd.get("wave", "")) \
			or str(ad.get("charge", "")) != str(bd.get("charge", "")) \
			or str(ad.get("shoot", "")) != str(bd.get("shoot", "")):
		return false
	var da: Variant = _dest3(ad.get("dest")) if ad.has("dest") else null
	var db: Variant = _dest3(bd.get("dest")) if bd.has("dest") else null
	if (da == null) != (db == null):
		return false
	return da == null or ((da as Vector3) - (db as Vector3)).length() <= EPS


static func _dest3(d: Variant) -> Variant:
	if d is Vector3:
		return d
	if d is Array and (d as Array).size() == 3:
		return Vector3(float(d[0]), float(d[1]), float(d[2]))
	return null

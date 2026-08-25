extends SceneTree
## NML-1073 M1-0 — proves BattleSim.state_to_plain() is COMPLETE: rebuilds a
## state Dictionary from N recorded nodes.jsonl lines using ONLY the plain
## JSON (positions back to Vector3; each unit's "unit" is a STAND-IN GameUnit
## built solely from the header line's "profiles" table — no live GameUnit is
## ever touched, exactly the position a Rust port is in), replays
## resolve()+score() and diffs the result against the recorded state_after/score.
##
## GAP (documented, not silently patched over): the plain form carries the
## "los" matrix (sees()) but not the state-level "los_blocked" terrain
## Callable (_los_clear) — nodes whose shoot/charge leg needed centre-line
## terrain blocking will show a resolve() mismatch here; that capture is
## M1-2/M1-3 scope. score() has no such dependency of its own, but the
## RECORDED score may have used either the cheap leaf (score(next, player))
## or the rich leaf (score(next, player, reply_threat(next, player))) — the
## 5-field JSONL contract does not carry which, so this tool tries both and
## reports the closer one; "neither within tolerance" is a real mismatch.
##
## Usage: godot --headless -s res://tools/node_recheck.gd -- dir=<NML_NODE_DUMP dir> n=50
## (line 1 of nodes.jsonl is the {"profiles": ...} header, not counted in n)

const EPS := 1e-6

func _init() -> void:
	var dir := OS.get_environment("NML_NODE_DUMP")
	var n := 50
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		if kv[0] == "dir":
			dir = kv[1]
		elif kv[0] == "n":
			n = int(kv[1])
	var f := FileAccess.open(dir.path_join("nodes.jsonl"), FileAccess.READ)
	if f == null:
		printerr("[RECHECK] cannot open ", dir.path_join("nodes.jsonl"))
		quit(1)
		return
	var header: Variant = JSON.parse_string(f.get_line())
	var profiles: Dictionary = (header as Dictionary)["profiles"]
	var checked := 0
	var resolve_exact := 0
	var max_score_diff := 0.0
	var matches := {"cheap": 0, "rich": 0, "neither": 0}
	var mismatches: Array = []
	while checked < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var rec: Variant = JSON.parse_string(line)
		if not (rec is Dictionary):
			continue
		checked += 1
		var player := int(rec["player"])
		var before := _rebuild_state(rec["state_before"], profiles)
		var next: Dictionary = BattleSim.resolve(before, _rebuild_action(rec["action"]))
		var recorded := float(rec["score"])
		var d_cheap := absf(AiMissionEval.score(next, player) - recorded)
		var d_rich := absf(AiMissionEval.score(next, player,
			BattleSim.reply_threat(next, player)) - recorded)
		max_score_diff = maxf(max_score_diff, minf(d_cheap, d_rich))
		if d_cheap <= EPS and d_cheap <= d_rich:
			matches["cheap"] += 1
		elif d_rich <= EPS:
			matches["rich"] += 1
		else:
			matches["neither"] += 1
			mismatches.append({"node": checked, "kind": "score", "recorded": recorded,
				"cheap_diff": d_cheap, "rich_diff": d_rich})
		if _plain_eq(BattleSim.state_to_plain(next, false), rec["state_after"]):
			resolve_exact += 1
		else:
			mismatches.append({"node": checked, "kind": "resolve",
				"action_kind": int((rec["action"] as Dictionary).get("kind", -1))})
	print("[RECHECK] nodes=%d resolve_exact=%d/%d max_score_diff=%.12f score_matches=%s" \
		% [checked, resolve_exact, checked, max_score_diff, str(matches)])
	for m in mismatches:
		print("[RECHECK] MISMATCH ", m)
	quit(0)


static func _rebuild_state(plain: Dictionary, profiles: Dictionary) -> Dictionary:
	var state := {"round": int(plain["round"]), "rounds_total": int(plain["rounds_total"]),
		"scoring": str(plain["scoring"])}
	for k in ["vp", "vp_flavour", "vp_memo", "markers_meta", "destroy_seq"]:
		if plain.has(k):
			state[k] = plain[k]
	var objectives: Array = []
	for o in (plain.get("objectives", []) as Array):
		objectives.append({"pos": _vec3((o as Dictionary)["pos"]), "owner": (o as Dictionary)["owner"]})
	state["objectives"] = objectives
	var units := {}
	var plain_units: Dictionary = plain["units"]
	for uid in plain_units:
		var su: Dictionary = (plain_units[uid] as Dictionary).duplicate(true)
		su["unit"] = _stand_in_unit(profiles[uid])
		su["positions"] = _vec3s(su.get("positions", []))
		units[uid] = su
	state["units"] = units
	return state


static func _rebuild_action(a: Dictionary) -> Dictionary:
	var out := a.duplicate()
	if out.has("dest"):
		out["dest"] = _vec3(out["dest"])
	return out


## A stand-in GameUnit built ONLY from the recorded profile — the completeness
## proof: if resolve()/score() run correctly off this, the profile lost nothing
## the closures needed. Reuses the real GameUnit/ModelInstance/OPRUnit classes
## (not hand-mocked accessors) so RulesRegistry/AiEv/AiShooting need no changes.
static func _stand_in_unit(p: Dictionary) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = str(p.get("unit_id", ""))
	u.unit_properties = {"name": p.get("name", ""), "quality": int(p.get("quality", 0)),
		"defense": int(p.get("defense", 0)), "special_rules": p.get("special_rules", []),
		"game_system": str(p.get("game_system", "")), "faction_folder": str(p.get("faction_folder", "")),
		"size": int(p.get("model_count", 0))}
	for wm in (p.get("wounds_max", []) as Array):
		var m := ModelInstance.new()
		m.wounds_max = int(wm)
		u.models.append(m)
	var weapons: Array = p.get("weapons", [])
	if not weapons.is_empty():
		u.source_type = "opr"
		var ou := OPRApiClient.OPRUnit.new()
		for w in weapons:
			var ow := OPRApiClient.OPRWeapon.new()
			ow.name = str((w as Dictionary).get("name", ""))
			ow.range_value = int((w as Dictionary).get("range", 0))
			ow.attacks = int((w as Dictionary).get("attacks", 0))
			ow.count = int((w as Dictionary).get("count", 1))
			for r in ((w as Dictionary).get("rules", []) as Array):
				ow.special_rules.append(str(r))
			ou.weapons.append(ow)
		u.source_data = ou
	return u


static func _vec3(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _vec3s(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(_vec3(v))
	return out


## Recursive deep-equal, float/int compared with EPS tolerance (state_after
## from JSON already round-tripped through string formatting once).
static func _plain_eq(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= EPS
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _plain_eq(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _plain_eq(a[i], b[i]):
				return false
		return true
	return a == b

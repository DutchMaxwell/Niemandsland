class_name CoreShadow
extends RefCounted
## C-3 (shadow run): env NML_CORE_SHADOW=1 (test soaks only, default OFF). The core keeps a board for EVERY OPR AI
## activation, not only for a plain one, and an in-memory tap holds the table's tray rolls of that activation, so the
## same volley can be replayed through the core and compared (C-4). Counting only: the table resolves as always, the
## capture draws no die and writes no line. Flag off: no capture, no tap entry - byte-identical play.

static var _env := -1
## The table's tray rolls since this activation's shadow capture, in order: {kind, count, target, faces, owner, leg}.
static var tap: Array = []
## True while a shadow board is open (the tray's tap appends only then).
static var tapping := false
## C-4: one record per compared AI activation, {equal, first_diff, labels, unported}; the census writes them ("shadow").
static var records: Array = []
## C-4: begin + placed of this activation, taken after its move and before its first table die (the Dangerous test can
## remove a model; the core rolls that test itself from the same placement and routes).
static var placed: Array = []
## The first difference in words (which roll, which unit), for the report's diagnosis; set by `compare`/`_state_diff`.
static var _detail := {}
## The replay gates' reading (tools/parity/parity_compare.py): these kinds fold to "attack", a defense target clamps to 2..6.
const FOLD := ["morale", "fearless", "no_retreat", "regeneration", "ravage", "battleborn", "dangerous"]


## The flag, read once: ON only for "1" / "on".
static func enabled() -> bool:
	if _env < 0:
		var raw := OS.get_environment("NML_CORE_SHADOW").to_lower()
		_env = 1 if (raw == "1" or raw == "on") else 0
	return _env == 1


## The shadow board of the AI activation about to start (`peek`, before its move): a core handle, 0 with the flag off,
## no core at this table or a non-OPR unit. Opens the tap on a handle, empties it either way.
static func capture(main, peek: GameUnit) -> int:
	tap.clear()
	tapping = false
	if not enabled() or peek == null or not CoreActivation.applies(main) or not peek.source_data is OPRApiClient.OPRUnit:
		return 0
	var h := CoreActivation.capture(main)
	tapping = h != 0
	return h


## One table tray roll, kept while a shadow board is open (main.gd's `_solo_tray_roll` calls it with `faces` known).
static func note_roll(kind: String, count: int, target: int, faces: Array, owner: String, leg: String) -> void:
	if tapping:
		tap.append({"kind": kind, "count": count, "target": target, "faces": faces.duplicate(), "owner": owner, "leg": leg})


## C-4: the activation's placement for the replay (main.gd's AI body calls it after the move, before any die).
static func note_placed(main, unit: GameUnit, report: Dictionary) -> void:
	if int(main._solo_core_shadow_h) != 0:
		placed = CoreActivation.ai_transcript(main, unit, report, null).slice(0, 2)


## C-4: after the table resolved this AI activation's volley(s) at `order` (`groups`: target id -> {target, shots}),
## replay the activation in the core on the shadow board with the table's own faces (the cast and spell legs left out,
## as the replay gates do), then compare the roll stream by gate reading and each unit's end state (alive, the living
## models' wounds as a multiset, shaken, fatigued). No landing, no line, no die: the core's answer is only read.
static func compare(main, unit: GameUnit, report: Dictionary, groups: Dictionary, order: Array) -> void:
	if int(main._solo_core_shadow_h) == 0 or order.is_empty():
		return
	var core: Object = main.solo_controller._core_node_ready()
	var split: Array = []
	if order.size() > 1:
		for id in order:
			for shot in groups[id]["shots"]:
				split.append({"member": (shot["member"] as GameUnit).get_name(), "weapon": str(shot["profile"].get("name", "")), "target": id})
	var t := CoreActivation.ai_transcript(main, unit, report, groups[order[0]]["target"], split)
	if not placed.is_empty():
		t = placed + t.slice(2)
	var rolls: Array = tap.filter(func(r: Dictionary) -> bool: return not ["cast", "spell"].has(str(r["leg"])))
	var enforce: bool = main.object_manager._strict_movement_enforced()
	var r: Dictionary = core.step_activation(int(main._solo_core_shadow_h), unit.unit_id, t, enforce)
	var diff := ""
	var i := 0
	_detail = {}
	# The table signs a roll with the UNIT's label even when its joined hero holds the models (a lone hero saves "as the
	# hero" but the tray still reads "AI (<unit>)"); the core names the hero. One unit, one roller: a hero's name also
	# matches its host's.
	var host_of := {}
	for gu in [unit] + order.map(func(id) -> GameUnit: return groups[id]["target"]):
		for hero in (gu as GameUnit).get_attached_heroes():
			host_of[(hero as GameUnit).get_name()] = (gu as GameUnit).get_name()
	while str(r["step"]) == "need_roll" and diff == "":
		if i >= rolls.size():
			diff = "core_rolls_more"
			_detail = {"core": gate_key(r, false)}
		elif not same_roll(gate_key(r, false), gate_key(rolls[i], true), host_of) or (rolls[i]["faces"] as Array).size() != int(r["faces"]):
			diff = "rolls"
			_detail = {"core": gate_key(r, false), "table": _raw(rolls[i])}
		else:
			t.append({"t": "faces", "faces": rolls[i]["faces"]})
			i += 1
			r = core.step_activation(int(main._solo_core_shadow_h), unit.unit_id, t, enforce)
	if diff == "" and str(r["step"]) != "done":
		diff = str(r["step"])   # refused / need_choice / open: the core does not finish the table's activation
		_detail = {"reason": str(r.get("reason", r.get("id", "")))}
	elif diff == "" and i < rolls.size():
		diff = "table_rolled_more"
		_detail = {"table": rolls.slice(i, i + 4).map(_raw)}
	if r.has("handle"):
		diff = diff if diff != "" else _state_diff(main, core.plain_of(int(r["handle"])))
		core.release(int(r["handle"]))
	var labels: Array = CoreActivation.why_not(main, unit, null)
	for id in order:
		for w in CoreActivation.why_not(main, null, groups[id]["target"]):
			if not labels.has(w):
				labels.append(w)
	if order.size() > 1:
		labels.append("split")
	# C-18: what the deny-mode slice (NML_CORE_SLICE=deny) would refuse here: [] = the core door would take this volley.
	var deny: Array = CoreSlice.refusals_in(CoreSlice.DENY_PATH, unit)
	for id in order:
		deny.append_array(CoreSlice.refusals_in(CoreSlice.DENY_PATH, groups[id]["target"], true).map(func(x): return "target_" + x))
	if order.size() > 1:
		deny.append("split")   # the door keeps a split volley on the table (`order.size() == 1`)
	records.append({"deny": deny, "equal": diff == "", "first_diff": diff, "labels": labels, "unported": r.get("unported", []),
		"detail": _detail, "shooter": unit.get_name(), "targets": order.map(func(id) -> String: return groups[id]["target"].get_name())})


## Two gate keys are one roll: equal, or equal but for a core owner that is a joined hero of the table's owner.
static func same_roll(core_key: Array, table_key: Array, host_of: Dictionary) -> bool:
	return core_key == table_key or (core_key.slice(0, 3) == table_key.slice(0, 3) and host_of.get(core_key[3], "") == table_key[3])


## A roll by the replay gates' reading: (kind, count, target, owner); the table's owner "AI (<name>)" reads "<name>".
static func gate_key(r: Dictionary, table: bool) -> Array:
	var kind := "attack" if FOLD.has(str(r["kind"])) else str(r["kind"])
	var target := clampi(int(r["target"]), 2, 6) if kind == "defense" else int(r["target"])
	var owner := str(r["owner"])
	if table and owner.begins_with("AI (") and owner.ends_with(")"):
		owner = owner.substr(4, owner.length() - 5)
	return [kind, int(r["count"]), target, owner]


## The first unit field where the core's end state differs from the table's board now: "" = equal, else "<field>".
static func _state_diff(main, core_plain: Dictionary) -> String:
	var table: Dictionary = BattleSim.capture(main.opr_army_manager)   # the four fields need no objective, cover or LOS read
	var core_units: Dictionary = core_plain.get("units", {})
	var none := {"alive": 0, "wounds": []}
	for uid in core_units.keys() + (table["units"] as Dictionary).keys():
		var a: Dictionary = table["units"].get(uid, none)
		var b: Dictionary = core_units.get(uid, none)
		for k in ["alive", "wounds", "shaken", "fatigued"]:
			var core_v: Variant = _field(b, k)
			# The core shakes the host only; landing its delta mirrors that onto the joined hero (`land_delta` ->
			# `_solo_mirror_shaken`, as the table's own morale does), so a hero reads its host's core Shaken here.
			var host := str(a.get("attached_to", ""))
			if k == "shaken" and host != "" and core_units.has(host):
				core_v = maxi(int(core_v), _field(core_units[host], k))
			if _field(a, k) != core_v:
				_detail = {"unit": str(uid), "table": _field(a, k), "core": core_v}
				return k
	return ""


## A table roll as the record shows it: its own kind (unfolded), count, target, owner and leg.
static func _raw(r: Dictionary) -> Array:
	return [str(r["kind"]), int(r["count"]), int(r["target"]), str(r["owner"]), str(r["leg"])]


## One compared field: ints, and the living models' wounds as a sorted multiset (which of equal models fell is a tie).
static func _field(u: Dictionary, k: String) -> Variant:
	if k == "wounds":
		var w: Array = (u.get(k, []) as Array).map(func(x: Variant) -> int: return int(x))
		w.sort()
		return w
	return int(u.get(k, 0))


## Closes the activation's shadow board (every exit of the AI body, and a game reset): the handle is released, the tap
## emptied.
static func release(main) -> void:
	if int(main._solo_core_shadow_h) != 0 and is_instance_valid(main.solo_controller):
		var core: Object = main.solo_controller._core_node_ready()
		if core != null:
			core.release(int(main._solo_core_shadow_h))
	main._solo_core_shadow_h = 0
	placed = []
	tap.clear()
	tapping = false

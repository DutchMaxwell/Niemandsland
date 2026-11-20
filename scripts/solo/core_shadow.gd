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
## C-19 s2: the volley's compare, held until the activation's last table die (`flush`). The core's one call also rolls
## the end-of-activation morale from Dangerous wounds, which the table throws only after the volley code returned
## (main.gd's AI body); comparing at the volley's end read that die as "core_rolls_more". [unit, report, groups, order].
static var _held: Array = []
## The replay gates' reading (tools/parity/parity_compare.py): these kinds fold to "attack", a defense target clamps to 2..6.
const FOLD := ["morale", "fearless", "no_retreat", "regeneration", "ravage", "battleborn", "dangerous"]
## CC-10c: the core's cast legs as the door names them on the tray: [kind, leg] (`CoreActivation.CAST_KINDS`, one map for both).
const CAST_KINDS := CoreActivation.CAST_KINDS
## CC-10c: env NML_CORE_SHADOW_CAST=1|on (soaks only, default OFF). The replay carries the activation's cast inputs and
## keeps the tap's cast/spell legs, so the core's cast slot is compared too - a cast-only activation included.
static var _cast_env := -1
## CC-10c: the cast-only activation waiting for the body's `flush` (no volley holds a compare): [unit, report].
static var _cast_pending: Array = []
## CC-10d: env NML_CORE_SHADOW_PLANT = cast_boost | cast_payer | cast_buff (default ""), a deliberate fault for the soak's
## detector check: cast_boost moves every cast die's target, cast_payer the caster's spend, cast_buff drops a landed buff.
static var _plant := ""
static var _plant_read := false
## CC-10d: the table's token names per unit BEFORE this activation's casts, and the buffs the core's own cast lines place
## (per unit key, unique names in sorted order) - the two halves of the "buffs" reading.
static var _buffs_before: Dictionary = {}
static var _core_buffs: Dictionary = {}
## Gate 10 (game 12): the units already wiped when this activation's board was captured. A joined hero whose host
## was gone before the activation fights on alone (p.14) and owns its Shaken; a stale host flag is not mirrored.
static var _wiped_at_capture: Dictionary = {}


## EPOCH_94_PARITY_BATCH: env NML_CORE_SHADOW_SLOTS=1|on (soaks only, default OFF) compares WHICH models survived, below the
## epoch too: the core's old f64 casualty order parts mirror models of a symmetric formation the other way than the table, so a
## compare below 94 reads "positions" on such boards (a soak that wants the prevalence of that gap turns it on). From epoch 94 the
## compare is always on: the epoch claims the table's order.
static var _slots_env := -1


static func slots_enabled() -> bool:
	if _slots_env < 0:
		var raw := OS.get_environment("NML_CORE_SHADOW_SLOTS").to_lower()
		_slots_env = 1 if (raw == "1" or raw == "on") else 0
	return _slots_env == 1 or AiActRecorder.rules_epoch >= AiActRecorder.EPOCH_94_PARITY_BATCH


## The flag, read once: ON only for "1" / "on".
static func enabled() -> bool:
	if _env < 0:
		var raw := OS.get_environment("NML_CORE_SHADOW").to_lower()
		_env = 1 if (raw == "1" or raw == "on") else 0
	return _env == 1


## CC-10c: the cast switch, read once: ON only for "1" / "on".
static func cast_enabled() -> bool:
	if _cast_env < 0:
		var raw := OS.get_environment("NML_CORE_SHADOW_CAST").to_lower()
		_cast_env = 1 if (raw == "1" or raw == "on") else 0
	return _cast_env == 1


## The shadow board of the AI activation about to start (`peek`, before its move): a core handle, 0 with the flag off,
## no core at this table or a non-OPR unit. Opens the tap on a handle, empties it either way.
static func capture(main, peek: GameUnit) -> int:
	tap.clear()
	tapping = false
	if not (enabled() or melee_enabled() or cast_enabled()) or peek == null or not CoreActivation.applies(main) or not peek.source_data is OPRApiClient.OPRUnit:
		return 0
	var h := CoreActivation.capture(main)
	tapping = h != 0
	note_wiped(main.opr_army_manager)
	return h


## The units with no living model at this activation's capture (`_wiped_at_capture`, read by `_state_diff`).
static func note_wiped(army: OPRArmyManager) -> void:
	_wiped_at_capture = {}
	for gu in army.get_all_game_units():
		if gu is GameUnit and (gu as GameUnit).get_alive_count() <= 0:
			_wiped_at_capture[(gu as GameUnit).unit_id] = true


## One table tray roll, kept while a shadow board is open (main.gd's `_solo_tray_roll` calls it with `faces` known).
static func note_roll(kind: String, count: int, target: int, faces: Array, owner: String, leg: String) -> void:
	if tapping:
		tap.append({"kind": kind, "count": count, "target": target, "faces": faces.duplicate(), "owner": owner, "leg": leg})


## C-4: the activation's placement for the replay (main.gd's AI body calls it after the move, before any die).
static func note_placed(main, unit: GameUnit, report: Dictionary) -> void:
	if int(main._solo_core_shadow_h) != 0:
		placed = CoreActivation.ai_transcript(main, unit, report, null).slice(0, 2)
		# CC-10c: a cast-only activation waits for the body's `flush` (no volley code holds a compare then).
		if cast_enabled():
			_buffs_before = _token_names(main)   # CC-10d: the board at the activation's start, cast or no cast
			if not (report.get("casts", []) as Array).is_empty():
				_cast_pending = [unit, report]


## C-19 s2: the volley code's hand-off: the compare waits for `flush` (the AI body, after its end-of-activation morale).
static func hold(main, unit: GameUnit, report: Dictionary, groups: Dictionary, order: Array) -> void:
	if (enabled() or cast_enabled()) and int(main._solo_core_shadow_h) != 0 and not order.is_empty():
		_held = [unit, report, groups, order]


## C-19 s2: the held compare, now that the table has thrown every die of the activation it shares with the core's one
## call (the AI body calls it before Ambush re-deployment and Coordinate, and its wrapper on every early exit). CC-10c: a
## cast-only activation (no volley held a compare) is replayed here, with no aim and no targets.
static func flush(main) -> void:
	if _held.is_empty():
		if not _cast_pending.is_empty() and int(main._solo_core_shadow_h) != 0:
			var p: Array = _cast_pending
			_cast_pending = []
			compare(main, p[0], p[1], {}, [])
		return
	var h: Array = _held
	_held = []
	_cast_pending = []   # the held compare carries this activation's casts: no second, cast-only compare of the same tap
	compare(main, h[0], h[1], h[2], h[3])


## C-4: after the table resolved this AI activation's volley(s) at `order` (`groups`: target id -> {target, shots}),
## replay the activation in the core on the shadow board with the table's own faces (the cast and spell legs left out,
## as the replay gates do), then compare the roll stream by gate reading and each unit's end state (alive, the living
## models' wounds as a multiset, shaken, fatigued). No landing, no line, no die: the core's answer is only read.
## CC-10c: with NML_CORE_SHADOW_CAST=1 the cast inputs ride after the intent, the cast/spell legs stay in the stream, and
## an empty `order` (a cast-only activation) is a compare of the casts alone.
static func compare(main, unit: GameUnit, report: Dictionary, groups: Dictionary, order: Array) -> void:
	if int(main._solo_core_shadow_h) == 0 or (order.is_empty() and not cast_enabled()):
		return
	var core: Object = main.solo_controller._core_node_ready()
	var split: Array = CoreActivation.split_aim(order.map(func(id) -> Dictionary: return groups[id]))   # the door's own aim
	var target: GameUnit = groups[order[0]]["target"] if not order.is_empty() else null
	var t := CoreActivation.ai_transcript(main, unit, report, target, split)
	if not placed.is_empty():
		t = placed + t.slice(2)
	var damage: Array = _damage_spells(report)
	var keys_of: Dictionary = {}
	if cast_enabled():
		t.append_array(CoreActivation.cast_inputs(report))
		_plant_casts(t)
		keys_of = _keys_of(main)
		_core_buffs = {}
	var rolls: Array = tap if cast_enabled() else tap.filter(func(r: Dictionary) -> bool: return not ["cast", "spell"].has(str(r["leg"])))
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
		elif not same_roll(gate_key(r, false), gate_key(rolls[i], true), host_of) or (rolls[i]["faces"] as Array).size() != int(r["faces"]) \
				or not _leg_ok(r, rolls[i]):
			diff = "rolls"
			_detail = {"core": gate_key(r, false), "table": _raw(rolls[i])}
		else:
			if cast_enabled():
				_note_core_cast(r, rolls[i]["faces"], damage, keys_of)
			t.append({"t": "faces", "faces": rolls[i]["faces"]})
			i += 1
			r = core.step_activation(int(main._solo_core_shadow_h), unit.unit_id, t, enforce)
	if diff == "" and str(r["step"]) != "done":
		diff = str(r["step"])   # refused / need_choice / open: the core does not finish the table's activation
		_detail = {"reason": str(r.get("reason", r.get("id", "")))}
	elif diff == "" and i < rolls.size():
		diff = "table_rolled_more"
		_detail = {"table": rolls.slice(i, i + 4).map(_raw)}
	if cast_enabled():
		_spend_core_buffs(r.get("delta", []))
		if plant_name() == "cast_buff":
			_drop_one_buff()
	if r.has("handle"):
		var plain: Dictionary = core.plain_of(int(r["handle"]))
		diff = diff if diff != "" else _state_diff(main, plain, _core_buffs)
		if diff == "" and slots_enabled():
			diff = _positions_diff(main, plain)   # WHICH models stand, not only how many (the casualty order)
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
		deny.append_array(CoreSlice.pair_refusals_in(CoreSlice.DENY_PATH, unit, groups[id]["target"]))
	if not (report.get("casts", []) as Array).is_empty() and not cast_enabled():
		deny.append("cast")   # the door keeps a volley after this activation's casts on the table (`run_ai`)
	records.append({"deny": deny, "equal": diff == "", "first_diff": diff, "labels": labels, "unported": r.get("unported", []),
		"detail": _detail, "shooter": unit.get_name(), "targets": order.map(func(id) -> String: return groups[id]["target"].get_name())})


## Two gate keys are one roll: equal, or equal but for a core owner that is a joined hero of the table's owner.
static func same_roll(core_key: Array, table_key: Array, host_of: Dictionary) -> bool:
	return core_key == table_key or (core_key.slice(0, 3) == table_key.slice(0, 3) and host_of.get(core_key[3], "") == table_key[3])


## A roll by the replay gates' reading: (kind, count, target, owner); the table's owner "AI (<name>)" reads "<name>".
## CC-10c: the core's cast legs read as the tray's own kind (the door's map, `CAST_KINDS`).
static func gate_key(r: Dictionary, table: bool) -> Array:
	var kind := str(r["kind"])
	if not table and CAST_KINDS.has(kind):
		kind = str((CAST_KINDS[kind] as Array)[0])
	kind = "attack" if FOLD.has(kind) else kind
	var target := clampi(int(r["target"]), 2, 6) if kind == "defense" else int(r["target"])
	var owner := str(r["owner"])
	if table and owner.begins_with("AI (") and owner.ends_with(")"):
		owner = owner.substr(4, owner.length() - 5)
	return [kind, int(r["count"]), target, owner]


## CC-10c: the table's leg of a core cast leg ("cast" / "spell"); a plain kind reads "" and any table leg fits it (the
## table tags a plain volley "main").
static func _leg_ok(core_roll: Dictionary, table_roll: Dictionary) -> bool:
	var leg := str((CAST_KINDS.get(str(core_roll["kind"]), ["", ""]) as Array)[1])
	return leg.is_empty() or leg == str(table_roll["leg"])


## The first unit field where the core's end state differs from the table's board now: "" = equal, else "<field>".
## CC-10d: the caster's unspent tokens (`casts`) and, from `core_buffs`, the spell tokens each unit gained.
static func _state_diff(main, core_plain: Dictionary, core_buffs: Variant = null) -> String:
	var table: Dictionary = BattleSim.capture(main.opr_army_manager)   # the four fields need no objective, cover or LOS read
	var core_units: Dictionary = core_plain.get("units", {})
	var none := {"alive": 0, "wounds": []}
	for uid in core_units.keys() + (table["units"] as Dictionary).keys():
		var a: Dictionary = table["units"].get(uid, none)
		var b: Dictionary = core_units.get(uid, none)
		for k in ["alive", "wounds", "shaken", "fatigued"] + (["casts"] if cast_enabled() else []):
			var core_v: Variant = _field(b, k)
			# The core shakes the host only; landing its delta mirrors that onto the joined hero (`land_delta` ->
			# `_solo_mirror_shaken`, as the table's own morale does), so a hero reads its host's core Shaken here.
			var host := str(a.get("attached_to", ""))
			if k == "shaken" and host != "" and core_units.has(host) and not _wiped_at_capture.has(host):
				core_v = maxi(int(core_v), _field(core_units[host], k))
			if _field(a, k) != core_v:
				_detail = {"unit": str(uid), "table": _field(a, k), "core": core_v}
				return k
	if cast_enabled() and core_buffs is Dictionary:
		return _buffs_diff(main, core_buffs)
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



## CC-10d: the buff names each unit GAINED this activation (the table's own token list, before vs now) against the tokens
## the core's cast lines place: a token on the wrong unit, a missing one or a surplus one is a difference.
static func _buffs_diff(main, core_buffs: Dictionary) -> String:
	var now := _token_names(main)
	var uids: Array = now.keys() + core_buffs.keys()
	uids.sort()
	for uid in uids:
		var had: Array = _buffs_before.get(uid, [])
		var a: Array = (now.get(uid, []) as Array).filter(func(n: Variant) -> bool: return not had.has(n))
		# A re-cast of a token the unit still held places no second name on the table's list: not a gain on either side.
		var b: Array = (core_buffs.get(uid, []) as Array).filter(func(n: Variant) -> bool: return not had.has(n))
		b.sort()
		if a != b:
			_detail = {"unit": str(uid), "table": a, "core": b}
			return "buffs"
	return ""


## CC-10d: the table's live spell tokens per unit key, unique names in sorted order (the buff names a unit carries).
static func _token_names(main) -> Dictionary:
	var out := {}
	for e in main._solo_spell_tokens_active:
		var ed := e as Dictionary
		var gu: GameUnit = ed.get("unit")
		if gu == null or not is_instance_valid(gu):
			continue
		var names: Array = out.get(gu.unit_id, [])
		var tok := str(ed.get("token", ""))
		if not tok.is_empty() and not names.has(tok):
			names.append(tok)
			names.sort()
			out[gu.unit_id] = names
	return out


## CC-10d: the names of the activation's damage spells (a damage cast lands no token; every other effect places one).
static func _damage_spells(report: Dictionary) -> Array:
	var out: Array = []
	for c in report.get("casts", []):
		var eff: Dictionary = ((c as Dictionary).get("spell", {}) as Dictionary).get("effect", {})
		if str(eff.get("kind", "")) == "damage":
			out.append(str((c as Dictionary).get("name", "")))
	return out


## CC-10d: unit NAME -> roster key, the reading the core's cast lines allow (they name units, not keys).
static func _keys_of(main) -> Dictionary:
	var out := {}
	for uid in main.opr_army_manager.game_units:
		out[(main.opr_army_manager.game_units[uid] as GameUnit).get_name()] = str(uid)
	return out


## CC-10d: the core's own cast line as [spell, [target names]]: "<caster> casts <spell> at <targets> — needs <n>+ (...)";
## the announce line has no " — needs " and is skipped. [] when this step said no such line.
static func _cast_line(lines: Array) -> Array:
	for i in range(lines.size() - 1, -1, -1):
		var text := str((lines[i] as Dictionary).get("text", ""))
		if not text.contains(" — needs ") or not text.contains(" casts "):
			continue
		var after := text.substr(text.find(" casts ") + 7)
		if not after.contains(" at "):
			continue
		var rest := after.substr(after.find(" at ") + 4)
		return [after.substr(0, after.find(" at ")), rest.substr(0, rest.find(" — needs ")).split(", ", false)]
	return []


## CC-10d: a core cast die the table passed: a hit places the spell's token on every standing target its own line names.
static func _note_core_cast(r: Dictionary, faces: Array, damage: Array, keys_of: Dictionary) -> void:
	if str(r["kind"]) != "cast" or not faces.any(func(f: Variant) -> bool: return int(f) >= int(r["target"])):
		return
	var hit := _cast_line(r.get("lines", []))
	if hit.is_empty() or damage.has(str(hit[0])):
		return
	for target in hit[1]:
		var key := str(keys_of.get(str(target), ""))
		if key.is_empty():
			continue
		var names: Array = _core_buffs.get(key, [])
		if not names.has(str(hit[0])):
			names.append(str(hit[0]))
			names.sort()
			_core_buffs[key] = names


## CC-10d: a once token the core's OWN delta reports spent (e.g. placed and spent by the same activation's volley) is not
## a token the table holds now either - the table's own list already shows the spend.
static func _spend_core_buffs(delta: Array) -> void:
	for d in delta:
		var row := d as Dictionary
		var names: Array = _core_buffs.get(str(row.get("unit", "")), [])
		for pair in row.get("buffs_spent", []):
			names.erase(str((pair as Array)[0]))
		if names.is_empty():
			_core_buffs.erase(str(row.get("unit", "")))


## CC-10d: the soak's planted faults on the SENT cast inputs (default: none).
static func _plant_casts(t: Array) -> void:
	var plant := plant_name()
	var dice: Array = tap.filter(func(r: Dictionary) -> bool: return str(r["leg"]) == "cast")
	var k := -1
	for e in t:
		var c := e as Dictionary
		if str(c.get("t", "")) != "cast":
			continue
		k += 1
		if plant == "cast_boost":
			# The die's target moves by one and the payers stay as the table paid them: an unpaid extra boost is refused by
			# the core's own payer check before any die (never a `rolls` reading). Away from the clamp at 6+ / 2+: up while
			# the table's die needs less than 6, else down; the table's own die (the tap's k-th cast leg) is the reference.
			var needs := clampi(int(c.get("base", 0)) - int(c.get("boost", 0)) + int(c.get("interference", 0)), 2, 6)
			if k < dice.size():
				needs = int((dice[k] as Dictionary)["target"])
			c["base"] = int(c.get("base", 0)) + (1 if needs < 6 else -1)
		elif plant == "cast_payer":
			c["threshold"] = maxi(int(c.get("threshold", 0)) - 1, 0)


## CC-10d: NML_CORE_SHADOW_PLANT, read once; "" = none.
static func plant_name() -> String:
	if not _plant_read:
		_plant = OS.get_environment("NML_CORE_SHADOW_PLANT").to_lower()
		_plant_read = true
	return _plant


## CC-10d: the `cast_buff` plant: drop one buff the core's lines placed (a core that stayed silent about a token).
static func _drop_one_buff() -> void:
	for uid in _core_buffs:
		var names: Array = _core_buffs[uid]
		if not names.is_empty():
			names.pop_back()
			if names.is_empty():
				_core_buffs.erase(uid)
			return


## Closes the activation's shadow board (every exit of the AI body, and a game reset): the handle is released, the tap
## emptied.
static func release(main) -> void:
	if int(main._solo_core_shadow_h) != 0 and is_instance_valid(main.solo_controller):
		var core: Object = main.solo_controller._core_node_ready()
		if core != null:
			core.release(int(main._solo_core_shadow_h))
	main._solo_core_shadow_h = 0
	melee_end(main)
	_melee = {}
	_core_rolls = []
	_held = []
	placed = []
	_cast_pending = []
	_buffs_before = {}
	_core_buffs = {}
	tap.clear()
	tapping = false


## Plan E (melee shadow, P4.D-48): env NML_CORE_SHADOW_MELEE=1|on|deny (soaks only, default OFF). With the charge door off
## the table fights every AI charge; for each one the active view's slice WOULD take (`1`/`on`: live allow file; `deny`:
## the melee deny file) the shadow board replays it through the core's step path with the table's own faces and compares
## rolls, end state, positions (XZ, within 0.01") and lines. Counting only; the charge door is untouched.
static var _melee_env := -1   # -1 unread, 0 off, 1 allow view (1/on), 2 deny view (deny)
## One record per AI charge seen: {charger, target, taken, why, deny, rules, equal, first_diff, detail, core_rolls}.
static var melee_records: Array = []
## The charge in flight: {why, deny, charger, target, rules, lines}; {} = none. `_line_fn` taps the battle log while the table fights it.
static var _melee: Dictionary = {}
static var _line_fn: Callable
## Full core `need_roll` stream emitted during the last `_melee_diff` replay, in order (up through any diverging roll).
static var _core_rolls: Array = []


static func _read_melee_env() -> int:
	if _melee_env < 0:
		var raw := OS.get_environment("NML_CORE_SHADOW_MELEE").to_lower()
		_melee_env = 2 if raw == "deny" else (1 if raw in ["1", "on"] else 0)
	return _melee_env


static func melee_enabled() -> bool:
	return _read_melee_env() > 0


static func melee_deny_view() -> bool:
	return _read_melee_env() == 2


## Rule labels carried by `gu` (unit rules, weapon rules, joined heroes' rules), base names deduplicated in order.
static func _rule_labels(gu: GameUnit) -> Array:
	var out: Array = []
	if gu == null:
		return out
	var add := func(r: Variant) -> void:
		var l := CoreSlice.rule_label(r)
		if l != "" and not out.has(l):
			out.append(l)
	for r in gu.get_special_rules():
		add.call(r)
	if gu.source_data is OPRApiClient.OPRUnit:
		for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
			for r in w.special_rules:
				add.call(r)
	for hero in gu.get_attached_heroes():
		for l in _rule_labels(hero as GameUnit):
			if not out.has(l):
				out.append(l)
	return out


## One core `need_roll` step as the melee shadow record keeps it: unfolded kind, count, target, owner, expected face count.
static func _core_roll(r: Dictionary) -> Dictionary:
	return {"kind": str(r["kind"]), "count": int(r["count"]), "target": int(r["target"]), "owner": str(r["owner"]), "faces": int(r["faces"])}


## Before the table fights the charge: the slice's reading (start sizes), both names/rules, and the battle-log tap.
static func melee_begin(main, unit: GameUnit, report: Dictionary) -> void:
	melee_end(main)
	if not melee_enabled() or int(main._solo_core_shadow_h) == 0:
		return
	var target: GameUnit = report.get("target") as GameUnit
	var deny: Array = CoreActivation.charge_refusals(main, unit, report, true)
	var why: Array = deny.duplicate() if melee_deny_view() else CoreActivation.charge_refusals(main, unit, report, false)
	_melee = {"why": why, "deny": deny, "charger": unit.get_name() if unit != null else "", "target": target.get_name() if target != null else "",
		"rules": {"charger": _rule_labels(unit), "target": _rule_labels(target)}, "lines": []}
	var lines: Array = _melee["lines"]
	_line_fn = func(e: Dictionary) -> void: lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(_line_fn)


## The tap closes (every exit, `release`).
static func melee_end(main) -> void:
	if _line_fn.is_valid() and main.battle_log != null and main.battle_log.entry_added.is_connected(_line_fn):
		main.battle_log.entry_added.disconnect(_line_fn)
	_line_fn = Callable()


## After the table fought the charge: one record; a charge the active view takes is replayed and compared.
static func melee_compare(main, unit: GameUnit, report: Dictionary) -> void:
	if _melee.is_empty():
		return
	melee_end(main)
	var m := _melee
	_melee = {}
	var rec := {"charger": m["charger"], "target": m["target"], "taken": (m["why"] as Array).is_empty(),
		"why": m["why"], "deny": m["deny"], "rules": m["rules"], "equal": false, "first_diff": "", "detail": {}, "core_rolls": []}
	if rec["taken"]:
		rec["first_diff"] = _melee_diff(main, unit, report, m["lines"])
		rec["equal"] = rec["first_diff"] == ""
		rec["detail"] = _detail
		rec["core_rolls"] = _core_rolls
	melee_records.append(rec)


static func _melee_diff(main, unit: GameUnit, report: Dictionary, table_lines: Array) -> String:
	var core: Object = main.solo_controller._core_node_ready()
	var h := int(main._solo_core_shadow_h)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.CHARGE, "charge": (report["target"] as GameUnit).unit_id}]
	var rolls: Array = tap.filter(func(r: Dictionary) -> bool: return not ["cast", "spell"].has(str(r["leg"])))
	var r: Dictionary = core.step_activation(h, unit.unit_id, t, false)
	_detail = {}
	_core_rolls = []
	var i := 0
	while str(r["step"]) == "need_roll":
		_core_rolls.append(_core_roll(r))
		if i >= rolls.size() or not same_roll(gate_key(r, false), gate_key(rolls[i], true), {}) or (rolls[i]["faces"] as Array).size() != int(r["faces"]):
			_detail = {"core": gate_key(r, false), "table": _raw(rolls[i]) if i < rolls.size() else []}
			return "rolls"
		t.append({"t": "faces", "faces": rolls[i]["faces"]})
		i += 1
		r = core.step_activation(h, unit.unit_id, t, false)
	if str(r["step"]) != "done":
		_detail = {"reason": str(r.get("reason", r.get("id", "")))}
		return str(r["step"])
	if i < rolls.size():
		_detail = {"table": rolls.slice(i, i + 4).map(_raw)}
		return "table_rolled_more"
	var plain: Dictionary = core.plain_of(int(r["handle"]))
	core.release(int(r["handle"]))
	var diff := _state_diff(main, plain)
	if diff == "":
		diff = _positions_diff(main, plain)
	if diff == "":
		var cite := OPRApiClient.rules_cite(RulesRegistry.system_of_unit(unit))
		var core_lines: Array = (r.get("lines", []) as Array).map(func(l: Dictionary) -> String:
			return "%s|%s" % [BattleLog.Category.keys()[int(l["category"])], str(l["text"]).replace("{cite}", cite)])
		var said: Array = table_lines.filter(func(l: String) -> bool: return not l.contains(" → "))   # the tray's roll lines are the table's
		if said != core_lines:
			_detail = {"table": said, "core": core_lines}
			diff = "lines"
	return diff


## The first unit whose living models stand elsewhere in the core (XZ, sorted, 0.01"): "" = none, else "positions". Models of
## one unit are told apart by where they stand, so this is the reading of WHICH models survived (counts and wounds are `_state_diff`'s).
static func _positions_diff(main, core_plain: Dictionary) -> String:
	var table: Dictionary = BattleSim.capture(main.opr_army_manager)
	for uid in table["units"]:
		var xz := func(ps: Array) -> Array:
			var out: Array = ps.map(func(p: Variant) -> Vector2: return Vector2(p[0], p[2]) / 0.0254)   # Vector3 (table) or [x, y, z] (core)
			out.sort()
			return out
		var a: Array = xz.call(table["units"][uid].get("positions", []))
		var b: Array = xz.call((core_plain.get("units", {}) as Dictionary).get(uid, {}).get("positions", []))
		if a.size() != b.size() or range(a.size()).any(func(i: int) -> bool: return (a[i] as Vector2).distance_to(b[i]) > 0.01):
			_detail = {"unit": str(uid), "table": a, "core": b}
			return "positions"
	return ""

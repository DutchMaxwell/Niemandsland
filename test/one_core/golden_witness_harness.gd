extends RefCounted
## P4.0-10 — golden witness for the table's combat families on the OLD table path.
##
## WHY THIS EXISTS. The plan deletes table code family by family (decision D1: no field window, golden fixtures
## before each deletion). This harness captures what the table does TODAY for a small scenario grid — the volley
## family (plain, AP, Blast, cover, Deadly), the melee family (plain, AP, Impact, Furious, Counter) and the morale
## family (pass, Shaken, Rout, a spent once-buff) — and stores the final unit state plus every battle-log line the
## exchange wrote, together with the provenance that makes the recording meaningful (rules epoch, git sha, registry
## sha256). `compare()` runs the same grid again and names every difference, so a deletion that changes the table's
## result before its replacement is in place turns the companion suite red.
##
## It runs the TABLE path only: the caller clears NML_ONE_CORE_ACTIVATION, and nothing here opens a core session;
## the volley goes through main._solo_resolve_ai_volley, the melee through main._run_ai_melee and the morale test
## through main._solo_morale_test exactly as the game drives them. No gameplay code is touched — this file and its
## CLI/ suite are test/tool code.
##
## The grid is deliberately small and seeded: 4-5 scenarios x 4 seeds per family. Determinism comes from
## main.seed_tray_rng() (the same seam the parity gate uses) and from `_solo_batch` (instant dice, zero pacing holds).

const ParityTable := preload("res://test/parity/parity_table.gd")
const ParityMelee := preload("res://test/parity/parity_table_melee.gd")

## v1 fixtures (the three P4.0-10 families) carry counts and sums only; v2 adds the per-model identity ("slots") and
## the tray RNG state after the exchange. The comparator reads either schema and compares a v2 key only when the
## fixture has it, so a v1 fixture stays valid; a fresh capture always writes v2.
const SCHEMA_V1 := "nml-golden-witness-v1"
const SCHEMA := "nml-golden-witness-v2"
const SCHEMAS := [SCHEMA_V1, SCHEMA]
## The runner a scenario without a "runner" key uses: one AI volley through main._solo_resolve_ai_volley.
const RUNNER_AI_VOLLEY := "ai_volley"
const FAMILY := "shooting_volley"
const FIXTURE_PATH := "res://test/fixtures/one_core/golden_shoot_volley.json"
const MELEE_FAMILY := "melee"
const MELEE_FIXTURE_PATH := "res://test/fixtures/one_core/golden_melee.json"
const MORALE_FAMILY := "morale"
const MORALE_FIXTURE_PATH := "res://test/fixtures/one_core/golden_morale.json"
## Four seeds per scenario: in the volley grid they cover a morale failure (0), a save-less volley (17), the
## singular forms (49) and a volley with no hit (225); the melee grid records whatever they roll.
const SEEDS: Array[int] = [0, 17, 49, 225]
## The registry system every scenario below imports under; its mechanics map hash is part of the provenance.
const REGISTRY_SYSTEM := "gf"
## Cover is painted as a (2*COVER_CELLS+1)^2 block of forest cells around the defender's centre.
const COVER_CELLS := 2

const ATTACKER := {"player": 1, "name": "Att", "models": 10, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const DEFENDER := {"player": 2, "name": "Def", "models": 10, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}

## The melee grid keeps the parity gate's board: the attacker stands at its post-move position (base contact,
## 6.74" against 8.0"), the defender spreads 1.3" so no centroid ties; both units strike with one attack per model.
const MELEE_ATTACKER := {"key": "att", "player": 1, "name": "Att", "models": 10, "quality": 4, "defense": 4,
	"tough": 1, "x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const MELEE_DEFENDER := {"key": "def", "player": 2, "name": "Def", "models": 8, "quality": 4, "defense": 4,
	"tough": 1, "x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BLADE := {"name": "Blade", "range_in": 0, "attacks": 1, "count": 10, "rules": []}
const DEF_BLADE := {"name": "Blade", "range_in": 0, "attacks": 1, "count": 8, "rules": []}
const CHARGE := {"dest_x_in": 6.74}

## The morale grid: one AI-owned unit (player 2, so no save prompt), 10 models, no weapon needed.
const MORALE_UNIT := {"player": 2, "name": "Mor", "models": 10, "quality": 2, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}


## The shooting grid: five shapes. `cover` paints forest under the defender (z_step 0.1" keeps the ten models
## inside the painted block); `weapon.rules` are the table's own weapon-rule names.
static func scenarios() -> Array:
	return [
		{"name": "plain", "note": "no weapon rule, no cover", "weapon": RIFLE,
			"attacker": ATTACKER, "defender": DEFENDER},
		{"name": "ap", "note": "AP(1) worsens the defender's save from 4+ to 5+", "weapon": _weapon(["AP(1)"]),
			"attacker": ATTACKER, "defender": DEFENDER},
		{"name": "blast", "note": "Blast(3) scales every hit by the defender's model count", "weapon": _weapon(["Blast(3)"]),
			"attacker": ATTACKER, "defender": DEFENDER},
		{"name": "cover", "note": "majority of the defender fully inside forest: +1 Defense",
			"weapon": RIFLE, "attacker": ATTACKER,
			"defender": _with(DEFENDER, {"z_step_in": 0.1}), "cover": true},
		{"name": "deadly", "note": "Deadly(3) vs Tough(3): each unsaved wound kills one model",
			"weapon": _weapon(["Deadly(3)"]), "attacker": ATTACKER,
			"defender": _with(DEFENDER, {"tough": 3})},
		{"name": "ap_marked_target", "note": "AP(1) vs a defender with 2 Piercing Tag markers: one token spent, +1 AP (P4.D-30)",
			"weapon": _weapon(["AP(1)"]), "attacker": ATTACKER,
			"defender": _with(DEFENDER, {"ledger": {"piercing_tag_markers": 2, "piercing_tag_source": ""}})},
	]


## The melee grid: the same charge, five shapes of the charge/strike/strike-back/morale path.
static func melee_scenarios() -> Array:
	return [
		{"name": "plain", "note": "no rule: both sides strike with one attack per model",
			"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE,
			"weapon": BLADE, "defender_weapon": DEF_BLADE},
		{"name": "ap", "note": "AP(1) on the attacker's blade worsens the defender's save",
			"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE,
			"weapon": _with(BLADE, {"rules": ["AP(1)"]}), "defender_weapon": DEF_BLADE},
		{"name": "impact", "note": "Impact(1) auto-hits before the strikes (rules 3.6 slot)",
			"attacker": _with(MELEE_ATTACKER, {"rules": ["Impact(1)"]}), "defender": MELEE_DEFENDER,
			"charge": CHARGE, "weapon": BLADE, "defender_weapon": DEF_BLADE},
		{"name": "furious", "note": "Furious: each unmodified 6 in melee adds a hit on the charge",
			"attacker": _with(MELEE_ATTACKER, {"rules": ["Furious"]}), "defender": MELEE_DEFENDER,
			"charge": CHARGE, "weapon": BLADE, "defender_weapon": DEF_BLADE},
		{"name": "counter", "note": "Counter on the defender's blade strikes first when charged",
			"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE,
			"weapon": BLADE, "defender_weapon": _with(DEF_BLADE, {"rules": ["Counter"]})},
	]


## The morale grid: the four outcomes the plan names (pass, Shaken, Rout, a spent once-buff) through the table's
## real _solo_morale_test. `dead` marks models lost before the test (the at-or-below-half gate); `once_mod` places
## a one-use morale-buff record on the unit.
static func morale_scenarios() -> Array:
	return [
		{"name": "pass", "note": "full strength, Q2+: every seed rolls the pass",
			"unit": _with(MORALE_UNIT, {"quality": 2}), "melee": false, "seeds": [0, 17, 34, 36]},
		{"name": "shake", "note": "full strength, Q6+: every seed fails and turns the unit Shaken",
			"unit": _with(MORALE_UNIT, {"quality": 6}), "melee": false, "seeds": [8, 17, 49, 225]},
		{"name": "rout", "note": "4 of 10 models left and a melee test: every seed fails and Routs",
			"unit": _with(MORALE_UNIT, {"quality": 6}), "melee": true, "dead": 6, "seeds": [8, 17, 49, 225]},
		{"name": "once", "note": "a one-use +1 morale buff turns a 4 into a pass and is then spent",
			"unit": _with(MORALE_UNIT, {"quality": 5}), "melee": false, "once_mod": "Great Banner",
			"seeds": [1, 4, 13, 20]},
	]


static func _weapon(rules: Array) -> Dictionary:
	return _with(RIFLE, {"rules": rules})


static func _with(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	return out.merged(patch, true)


## Puts a freshly booted main.tscn into the state the grid needs and proves the OLD table path is active: the
## kill switch was set by the caller (env) but CoreActivation caches its decision once, so the cache is dropped
## here. False = the one-core flag is on; the caller must not record anything then.
static func configure(main: Node) -> bool:
	CoreActivation._env = -1
	if CoreActivation.enabled():
		return false
	main.solo_ai_slots = {2: true}
	main._ensure_solo_controller()
	main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	main.opr_army_manager.current_round = 1
	main._solo_batch = true
	return true


## Runs one family's whole grid on `main` (already booted, PLAYING, solo_controller ready) and returns the fixture
## shape. Await it: every exchange awaits the table's own presentation seams.
static func capture(main: Node, family: String = FAMILY) -> Dictionary:
	if family == MELEE_FAMILY:
		return await capture_melee(main)
	if family == MORALE_FAMILY:
		return await capture_morale(main)
	var out := {"schema": SCHEMA, "family": FAMILY, "provenance": provenance(), "cases": []}
	for sc in scenarios():
		for seed in SEEDS:
			out["cases"].append(await _run_case(main, sc, seed))
	return out


static func capture_melee(main: Node) -> Dictionary:
	var fast: bool = main.get("_solo_fast")
	var slots: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
	main.set("_solo_fast", true)   # the parity gate's fast-forward: no glide tweens
	# Both seats AI, like the parity gate: a human seat would wait for a save click on the strike-back.
	main.solo_ai_slots = {1: true, 2: true}
	var out := {"schema": SCHEMA, "family": MELEE_FAMILY, "provenance": provenance(), "cases": []}
	for sc in melee_scenarios():
		for seed in SEEDS:
			out["cases"].append(await _run_melee_case(main, sc, seed))
	main.solo_ai_slots = slots
	main.set("_solo_fast", fast)
	return out


static func capture_morale(main: Node) -> Dictionary:
	var out := {"schema": SCHEMA, "family": MORALE_FAMILY, "provenance": provenance(), "cases": []}
	for sc in morale_scenarios():
		for seed in sc["seeds"]:
			out["cases"].append(await _run_morale_case(main, sc, int(seed)))
	return out


## What a later reader needs to know this recording is still comparable: the rules epoch moves the table's
## behaviour, the registry hash moves its data, and the git sha says which tree produced it.
static func provenance() -> Dictionary:
	var sha := ""
	var lines: Array = []
	if OS.execute("git", ["rev-parse", "HEAD"], lines, true) == 0 and not lines.is_empty():
		sha = str(lines[0]).strip_edges()
	var reg := RulesRegistry.registry_state(REGISTRY_SYSTEM)
	return {"epoch": AiActRecorder.rules_epoch, "git_sha": sha, "registry_system": REGISTRY_SYSTEM,
		"registry_sha256": str(reg.get("sha256", ""))}


## One scenario x seed: build the two neutral units, optionally paint cover, seed the real tray, run one AI volley
## through main._solo_resolve_ai_volley, and record what it did. The units are removed again so the next case
## starts from the same table.
static func _run_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var runner := str(sc.get("runner", RUNNER_AI_VOLLEY))
	match runner:
		RUNNER_AI_VOLLEY:
			return await _run_ai_volley_case(main, sc, seed)
	return {"scenario": str(sc["name"]), "seed": seed, "error": "unknown runner %s" % runner}


static func _run_ai_volley_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var weapon: Dictionary = (sc["weapon"] as Dictionary).duplicate(true)
	var att := ParityTable._make_unit(main, sc["attacker"], weapon)
	var dfn := ParityTable._make_unit(main, sc["defender"], {})
	var painted := {}
	if bool(sc.get("cover", false)):
		painted = _paint_cover(main, dfn)
		if not main._solo_majority_in_cover(dfn):
			_unpaint_cover(main, painted)
			_free_units(main, [att, dfn])
			return {"scenario": str(sc["name"]), "seed": seed, "error": "the cover setup is not cover"}
	main.seed_tray_rng(seed)
	var dist_in := float((sc["defender"] as Dictionary)["x_in"]) - float((sc["attacker"] as Dictionary)["x_in"])
	var wobj: OPRApiClient.OPRWeapon = (att.source_data as OPRApiClient.OPRUnit).weapons[0]
	var plist: Array = AiShooting.profiles_in_range([wobj], dist_in)
	for p in plist:
		main._solo_stamp_unit_shred(p, att, int(weapon["range_in"]))
	var shots: Array = []
	for p in AiEv.stamp_sergeant(plist, att):
		shots.append({"member": att, "quality": int((sc["attacker"] as Dictionary)["quality"]),
			"alive": att.get_alive_count(), "max": att.models.size(), "reach": float(weapon["range_in"]),
			"profile": p})
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	await main._solo_resolve_ai_volley(att, dfn, shots)
	main.battle_log.entry_added.disconnect(tap)
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, dfn]), "rng": _rng_state(main)}
	_unpaint_cover(main, painted)
	_free_units(main, [att, dfn])
	await main.get_tree().process_frame
	return rec


## One melee scenario x seed: build the two units in base contact (the parity gate's own board and per-model
## loadout), seed the real tray, run the table's real charge/strike/strike-back/morale resolver, and record it.
static func _run_melee_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var pair: Array = ParityMelee._units(main, sc, {})
	var att := pair[0] as GameUnit
	var dfn := pair[1] as GameUnit
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	await main._run_ai_melee({"unit": att, "target": dfn, "charge_from_in": ParityMelee._charge_from_in(sc)})
	main.battle_log.entry_added.disconnect(tap)
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, dfn]), "rng": _rng_state(main)}
	_free_units(main, [att, dfn])
	await main.get_tree().process_frame
	return rec


## One morale scenario x seed on one AI-owned unit: optionally lose models and/or place the one-use buff, seed the
## real tray, run the table's real morale test, and record the outcome lines and the unit's final state.
static func _run_morale_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var unit := ParityTable._make_unit(main, sc["unit"], {})
	_kill_models(unit, int(sc.get("dead", 0)))
	var spell := str(sc.get("once_mod", ""))
	if spell != "":
		main._solo_spell_mods[unit.get_instance_id()] = [{"spell": spell, "morale_mod": 1, "duration": "once"}]
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	await main._solo_morale_test(unit, "AI (%s)" % unit.get_name(), bool(sc.get("melee", false)), "")
	main.battle_log.entry_added.disconnect(tap)
	main._solo_spell_mods.erase(unit.get_instance_id())
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([unit]), "rng": _rng_state(main)}
	_free_units(main, [unit])
	await main.get_tree().process_frame
	return rec


## Marks `n` models of the unit dead (from the back); the model count on the unit stays the starting size, which is
## what the at-or-below-half gate reads.
static func _kill_models(unit: GameUnit, n: int) -> void:
	for i in range(n):
		if i < unit.models.size():
			(unit.models[unit.models.size() - 1 - i] as ModelInstance).is_alive = false


## What "final state" means for the witness: models left, wounds left on them, whether the unit is Shaken, and (v2)
## which model slot is alive with how many wounds left, so "which models died" is part of the record.
static func _final(units: Array) -> Array:
	var out: Array = []
	for u in units:
		var gu := u as GameUnit
		var wounds := 0
		var slots: Array = []
		for i in gu.models.size():
			var m := gu.models[i] as ModelInstance
			wounds += int(m.wounds_current)
			slots.append([i, m.is_alive, int(m.wounds_current)])
		out.append({"unit": gu.get_name(), "alive": gu.get_alive_count(), "wounds": wounds,
			"shaken": gu.is_shaken, "slots": slots})
	return out


## The tray RNG state after the exchange, as a string: it is a 64-bit value and JSON numbers are doubles.
static func _rng_state(main: Node) -> String:
	return str((main._tray_rng as RandomNumberGenerator).state)


## Paints a forest block around the defender and returns the touched cells as cell -> {had, value} (0 is a valid
## terrain value, so `had` decides whether the restore erases or writes back).
static func _paint_cover(main: Node, unit: GameUnit) -> Dictionary:
	var saved := {}
	var alive: Array = unit.get_alive_models()
	if alive.is_empty() or main.terrain_overlay == null:
		return saved
	var centre := Vector3.ZERO
	for m in alive:
		centre += (m as ModelInstance).node.global_position
	centre /= float(alive.size())
	var o: Node3D = main.terrain_overlay
	var cell: Vector2i = o.world_to_cell(centre)
	for dx in range(-COVER_CELLS, COVER_CELLS + 1):
		for dz in range(-COVER_CELLS, COVER_CELLS + 1):
			var key := cell + Vector2i(dx, dz)
			saved[key] = {"had": o.grid_cells.has(key), "value": int(o.grid_cells.get(key, 0))}
			o.grid_cells[key] = o.TerrainType.FOREST
	return saved


static func _unpaint_cover(main: Node, saved: Dictionary) -> void:
	if saved.is_empty() or main.terrain_overlay == null:
		return
	var o: Node3D = main.terrain_overlay
	for key in saved:
		var row: Dictionary = saved[key]
		if bool(row["had"]):
			o.grid_cells[key] = int(row["value"])
		else:
			o.grid_cells.erase(key)


static func _free_units(main: Node, units: Array) -> void:
	for u in units:
		main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()


## The committed fixture of one family (the shooting family stays the default for the older callers).
static func fixture_path(family: String = FAMILY) -> String:
	if family == MELEE_FAMILY:
		return MELEE_FIXTURE_PATH
	if family == MORALE_FAMILY:
		return MORALE_FIXTURE_PATH
	return FIXTURE_PATH


## The fixture on disk ({} when it is missing — the caller reports that as a difference).
static func load_fixture(path: String = FIXTURE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func save_fixture(fixture: Dictionary, path: String = FIXTURE_PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(fixture, " ", true, true) + "\n")
	f.close()
	return OK


## Every difference between the committed fixture and a fresh run, as human-readable lines (empty = green).
## Provenance is compared on what changes behaviour — the rules epoch and the registry data hash — plus the schema;
## the git sha is NOT a difference: a fixture is always committed by the commit AFTER the one that produced it. The
## caller prints the recorded sha as context (see describe_provenance()).
static func compare(expected: Dictionary, got: Dictionary) -> Array:
	var problems: Array = []
	if not SCHEMAS.has(str(expected.get("schema", ""))):
		problems.append("fixture: schema %s, want one of %s" % [str(expected.get("schema", "<none>")), str(SCHEMAS)])
	if str(expected.get("family", "")) != str(got.get("family", "")):
		problems.append("fixture: family %s, want %s" % [
			str(expected.get("family", "<none>")), str(got.get("family", "<none>"))])
	var ep: Dictionary = expected.get("provenance", {})
	var gp: Dictionary = got.get("provenance", {})
	if int(ep.get("epoch", -1)) != int(gp.get("epoch", -1)):
		problems.append("provenance: epoch %d in the fixture, %d now" % [
			int(ep.get("epoch", -1)), int(gp.get("epoch", -1))])
	if str(ep.get("registry_sha256", "")) != str(gp.get("registry_sha256", "")):
		problems.append("provenance: registry %s sha256 %s in the fixture, %s now" % [
			REGISTRY_SYSTEM, str(ep.get("registry_sha256", "")), str(gp.get("registry_sha256", ""))])
	var want := {}
	for c in expected.get("cases", []):
		want[_key(c)] = c
	var seen := {}
	for c in got.get("cases", []):
		var k := _key(c)
		seen[k] = true
		if not want.has(k):
			problems.append("%s: not in the fixture" % k)
			continue
		problems.append_array(_compare_case(k, want[k] as Dictionary, c as Dictionary))
	for k in want:
		if not seen.has(k):
			problems.append("%s: in the fixture but not in the run" % k)
	return problems


static func describe_provenance(fixture: Dictionary, run: Dictionary) -> String:
	var fp: Dictionary = fixture.get("provenance", {})
	var rp: Dictionary = run.get("provenance", {})
	return "epoch %s/%s, git sha %s/%s, registry %s sha256 %s/%s (fixture/run)" % [
		str(fp.get("epoch", "?")), str(rp.get("epoch", "?")),
		str(fp.get("git_sha", "?")), str(rp.get("git_sha", "?")),
		REGISTRY_SYSTEM, str(fp.get("registry_sha256", "?")), str(rp.get("registry_sha256", "?"))]


static func _compare_case(key: String, want: Dictionary, got: Dictionary) -> Array:
	var problems: Array = []
	if got.has("error") or want.has("error"):
		if str(got.get("error", "")) != str(want.get("error", "")):
			problems.append("%s: error %s, fixture %s" % [key, str(got.get("error", "<none>")), str(want.get("error", "<none>"))])
		return problems
	var wf := _final_rows(want.get("final", []))
	var gf := _final_rows(got.get("final", []))
	if wf != gf:
		problems.append("%s: final state %s, fixture %s" % [key, JSON.stringify(gf), JSON.stringify(wf)])
	# v2 keys: compared only when the fixture has them (a v1 fixture has neither).
	var ws := _slot_rows(want.get("final", []))
	if not ws.is_empty() and ws != _slot_rows(got.get("final", [])):
		problems.append("%s: model slots %s, fixture %s" % [
			key, JSON.stringify(_slot_rows(got.get("final", []))), JSON.stringify(ws)])
	if want.has("rng") and str(want["rng"]) != str(got.get("rng", "<none>")):
		problems.append("%s: tray rng state %s, fixture %s" % [key, str(got.get("rng", "<none>")), str(want["rng"])])
	var wl: Array = want.get("lines", [])
	var gl: Array = got.get("lines", [])
	for i in range(maxi(wl.size(), gl.size())):
		var w := str(wl[i]) if i < wl.size() else "<missing>"
		var g := str(gl[i]) if i < gl.size() else "<missing>"
		if w != g:
			problems.append("%s: line %d is %s, fixture %s" % [key, i, JSON.stringify(g), JSON.stringify(w)])
	return problems


## JSON turns every number into a float on the way back in, so both sides are normalised to the same ints/bools
## before they are compared.
static func _final_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var row := r as Dictionary
		out.append({"unit": str(row.get("unit", "")), "alive": int(row.get("alive", 0)),
			"wounds": int(row.get("wounds", 0)), "shaken": bool(row.get("shaken", false))})
	return out


## Per unit, the normalised [slot, alive, wounds] triples; [] when a row has no "slots" key (a v1 fixture).
static func _slot_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var row := r as Dictionary
		if not row.has("slots"):
			return []
		var triples: Array = []
		for t in row["slots"]:
			triples.append([int(t[0]), bool(t[1]), int(t[2])])
		out.append(triples)
	return out


static func _key(c: Dictionary) -> String:
	return "%s:%d" % [str(c.get("scenario", "?")), int(c.get("seed", -1))]

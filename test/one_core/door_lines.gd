extends RefCounted
## One core, door lines (lane dlines, 19.11.): the battle-log lines of a volley, per rule, on the table (the AI body) and on the core
## door (live capture + step driver), compared. The harness is `roster_sweep.gd`: `volley` hands back the lines each half wrote
## ("<CATEGORY>|<text>", in log order). Only the lines that name the rule are compared, so a rule that has its line on the door is
## not held up by another one that has not. A hard project rule: every applied rule writes a line, on either path.

const RosterSweep := preload("res://test/one_core/roster_sweep.gd")


## A list entry in the harness's shape: one OPR unit of `size` models, its rules, and `guns` weapons that carry `weapon_rules`.
static func entry(uname: String, size: int, rules: Array, weapon_rules: Array, faction := "battle_brothers", guns := 1) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = 4
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	if guns > 0:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Gun"
		w.range_value = 24
		w.attacks = 2
		w.count = guns
		w.special_rules.assign(weapon_rules)
		ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": "gf"}


## The COMBAT lines of `lines` that start with `prefix` (a rule's name), in order.
static func named(lines: Array, prefix: String) -> Array:
	return lines.filter(func(l: String) -> bool: return l.begins_with("COMBAT|" + prefix))


## `seeds` volleys of `shooter` at `target` on both halves; `opts` as `RosterSweep.volley`'s (a planted ledger fact). Returns
## {"fired": seeds where the table said a line of the rule, "bad": one text per seed where the two halves' lines of the rule differ,
## "state_bad": seeds where the end states differ (wounds, losses)}.
## "with_text": the seeds where a compared table line contains `needle` (a line of the rule that only some volleys write).
## The caller has armed the harness (`RosterSweep.arm`).
static func compare(main: Node, shooter: Dictionary, target: Dictionary, prefix: String, seeds: int, dump_dir: String, opts := {}, needle := "") -> Dictionary:
	var fired := 0
	var with_text := 0
	var state_bad := 0   # seeds whose end state (wounds, losses) differs: a line test over a pair whose dice differ proves nothing
	var bad: Array = []
	for s in seeds:
		var table := await RosterSweep.volley(main, shooter, target, s, false, dump_dir, opts)
		var core := await RosterSweep.volley(main, shooter, target, s, true, dump_dir, opts)
		var t := named(table["lines"], prefix)
		var c := named(core["lines"], prefix)
		fired += 1 if not t.is_empty() else 0
		with_text += 1 if needle != "" and t.any(func(l: String) -> bool: return l.contains(needle)) else 0
		if RosterSweep.first_state_diff(table["state"], core["state"]) != "":
			state_bad += 1
		if t != c:
			bad.append("seed %d: table %s | door %s" % [s, JSON.stringify(t), JSON.stringify(c)])
	return {"fired": fired, "with_text": with_text, "bad": bad, "state_bad": state_bad}

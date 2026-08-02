extends RefCounted
## Off-board audit — the measurement seam for issue #215 (AI paths that leave the table).
##
## Both AI harnesses (tools/solo_selfplay.gd, tools/arena_match.gd) run this over the REAL model
## positions after a unit settled and emit ONE parseable battle-log line per offending unit. The
## line is the machine-readable contract consumed by tools/tactic_audit.py (detector d9), so the
## A/B measurement track can put a number on the defect instead of arguing about it:
## a leg that plans off-board scores d9 > 0, a fixed leg scores exactly 0.
##
## MEASUREMENT ONLY — nothing here changes a decision, a position or a rule. It is a tools/ script
## by design: the game never loads it, so a real match is untouched.
##
## Centre-based by intent: a base may legitimately hang over the table edge (models are placed by
## their centre, and SoloController._clamp_to_bounds clamps CENTRES to half-extent minus a margin).
## A model CENTRE past the half-extent is what "the planner routed off the table" means, and it is
## exactly what the scalar board_in folding produced on a rectangular table.

const IN2M: float = 0.0254
const FEET_TO_M: float = 0.3048
## Float-noise tolerance. The controller parks clamped models a hair INSIDE the edge
## (BOUNDS_MARGIN_M), so a legitimate edge model never reaches the half-extent — anything past it
## by more than this is a genuine off-board centre.
const OFFBOARD_EPS_IN: float = 0.05


## Table half-extents in metres, read from the live table node (feet). Mirrors
## SoloController._table_half_extents, including its 4x4 ft fallback when no table is present.
static func half_extents_m(table: Node) -> Vector2:
	var feet := Vector2(4, 4)
	if table != null and "table_size" in table:
		feet = table.table_size
	return feet * FEET_TO_M * 0.5


## How far one model centre sits OUTSIDE the table, in inches (<= 0 means inside). Worst single axis:
## the scalar-board defect over-permits ONE axis, so per-axis is the honest measure — a diagonal corner
## exit still reports its larger side. Pure: this is the whole detection rule, unit-testable on its own.
static func overhang_in(p: Vector3, half_m: Vector2) -> float:
	return maxf(absf(p.x) - half_m.x, absf(p.z) - half_m.y) / IN2M


## Off-board tally for one unit's alive models: how many model centres sit outside the table and by
## how much (inches, per axis, whichever is worse). Returns {"count": int, "max_overhang_in": float}.
static func check_unit(table: Node, unit) -> Dictionary:
	var out := {"count": 0, "max_overhang_in": 0.0}
	if unit == null or table == null or unit.get_alive_count() <= 0:
		return out
	var half := half_extents_m(table)
	for m in unit.get_alive_models():
		var mi := m as ModelInstance
		if mi == null or mi.node == null or not is_instance_valid(mi.node):
			continue
		var p: Vector3 = (mi.node as Node3D).global_position
		var over_in := overhang_in(p, half)
		if over_in > OFFBOARD_EPS_IN:
			out["count"] = int(out["count"]) + 1
			out["max_overhang_in"] = maxf(float(out["max_overhang_in"]), over_in)
	return out


## The ONE parseable line. Keep this format stable — tools/tactic_audit.py (d9) parses it:
##   AUDIT off-board: <unit> — <n> model(s), max overhang <x.x>" (<phase>)
static func line(unit_name: String, count: int, max_overhang_in: float, phase: String) -> String:
	return "AUDIT off-board: %s — %d model(s), max overhang %.2f\" (%s)" % [
		unit_name, count, max_overhang_in, phase]


## Audit one settled unit and, on a violation, write the parseable line to the battle log (both
## harnesses capture that stream). Returns the tally so a caller can also record it its own way.
static func audit_and_log(table: Node, battle_log: Node, unit, phase: String) -> Dictionary:
	var tally := check_unit(table, unit)
	if int(tally["count"]) > 0 and battle_log != null:
		battle_log.log_event(BattleLog.Category.GENERAL,
			line(str(unit.get_name()), int(tally["count"]), float(tally["max_overhang_in"]), phase), true)
	return tally

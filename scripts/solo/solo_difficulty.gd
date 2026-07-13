class_name SoloDifficulty
extends RefCounted
## Solo-AI ARENA — graded DIFFICULTY as POLICY KNOBS on the SAME deterministic engine (docs/SOLO_AI_PLAN.md
## "AI learning plan"). A difficulty NEVER changes what is LEGAL: every grade plays 100% by the rules. The
## knobs only shape the AI's CLEVERNESS in the discretionary zones the official rules leave open — the
## "genuine tie" targeting/EV points (the hybrid policy) and the objective-vs-fight emphasis. So a lower
## grade is a WEAKER opponent, never an illegal one.
##
## The four knobs (all in [0,1] unless noted):
##   • ev_noise           — deliberate suboptimality: among GENUINELY TIED candidates (same official key,
##                          where the rules would "roll a die"), the AI takes the 2nd/3rd-best EV option
##                          with this seeded probability. 0 = always the best EV (the sharpest play).
##   • rule_exploitation  — whether the AI presses OPTIONAL rule advantages: at ≥ EXPLOIT_THRESHOLD it
##                          refines a genuine target tie by the weapon overlay (Deadly → single-Tough/Tough,
##                          AP → highest Defense, Takedown → heroes — Solo & Co-Op v3.5.0 p.2). Below it the
##                          AI skips that optimisation (e.g. does NOT steer Deadly onto Tough). `spend_boosts`
##                          mirrors the same gate for a future boost-token subsystem (none in this build yet).
##   • mission_focus      — the weight between OBJECTIVE play and FIGHTING: at lower focus the unit ignores an
##                          uncontrolled objective (and just fights the enemy — always legal) with probability
##                          1 − mission_focus. 1.0 = always pursue the objective (the official tree's default).
##   • coordination       — focus-fire vs spread: among tied targets, high coordination concentrates on the
##                          best-EV target (focus fire); below COORD_THRESHOLD the AI spreads onto a different
##                          tied target instead. 1.0 = full focus fire.
##   • lookahead (bool)   — the ceiling flag (Albtraum): full EV lookahead / boost spending headroom. A design
##                          marker surfaced in the decision record; the deterministic engine is shared, so it
##                          currently equals Kriegsherr play plus the boost gate — the hook for future depth.
##
## DETERMINISM: every seeded draw is a PURE hash of explicit integer seed parts (base seed, side, activation
## index, unit-name hash, a per-knob salt) — NO shared RNG state, NO Math.random-style nondeterminism. Same
## seed + same preset ⇒ identical "mistakes". The mirror-fairness SIM never constructs a SoloDifficulty, so
## it stays byte-identical (the opts-pattern discipline: knobs live game-side only).

# ===== Constants =====

enum Grade { REKRUT, VETERAN, KRIEGSHERR, ALBTRAUM }

## rule_exploitation at or above this presses optional advantages (overlay targeting, boosts).
const EXPLOIT_THRESHOLD := 1.0

## coordination below this spreads fire instead of concentrating it.
const COORD_THRESHOLD := 0.5

## Per-knob salts so the two independent draws inside ONE activation (objective skip, target noise) never
## correlate — same activation index, different salt ⇒ independent deterministic draws.
const SALT_TARGET := 101
const SALT_OBJECTIVE := 202

## FNV-1a 64-bit mixing constants — a self-contained deterministic hash (no reliance on engine hash()).
const _FNV_OFFSET := 1469598103934665603
const _FNV_PRIME := 1099511628211
const _POS_MASK := 0x7FFFFFFFFFFFFFFF
const _UNIT_RESOLUTION := 1000000

## The named presets (the graded arena ladder). Each is {ev_noise, rule_exploitation, mission_focus,
## coordination, lookahead}. Rekrut = high noise / no exploitation / low focus / no coordination; Veteran =
## mild noise, partial smarts; Kriegsherr = no noise, full exploitation, full focus & coordination (the
## sharp deterministic ceiling); Albtraum = Kriegsherr + the lookahead/boost ceiling flag.
const PRESETS := {
	"rekrut": {"grade": Grade.REKRUT, "ev_noise": 0.40, "rule_exploitation": 0.0, "mission_focus": 0.35, "coordination": 0.0, "lookahead": false},
	"veteran": {"grade": Grade.VETERAN, "ev_noise": 0.15, "rule_exploitation": 0.5, "mission_focus": 0.70, "coordination": 0.60, "lookahead": false},
	"kriegsherr": {"grade": Grade.KRIEGSHERR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "lookahead": false},
	"albtraum": {"grade": Grade.ALBTRAUM, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "lookahead": true},
}

# ===== State =====

var grade: int = Grade.KRIEGSHERR
var grade_name: String = "kriegsherr"
var ev_noise: float = 0.0
var rule_exploitation: float = 1.0
var mission_focus: float = 1.0
var coordination: float = 1.0
var lookahead: bool = false

## The game-level base seed folded into every deterministic draw (reproducibility across a rating run).
var base_seed: int = 0


# ===== Construction =====

## Build a difficulty from a preset NAME (case-insensitive; unknown → Kriegsherr, the safe ceiling). The
## base seed is folded into every seeded draw so a whole game replays identically.
static func for_grade(name: String, p_base_seed: int = 0) -> SoloDifficulty:
	var key := name.strip_edges().to_lower()
	var preset: Dictionary = PRESETS.get(key, PRESETS["kriegsherr"])
	var d := SoloDifficulty.new()
	d.grade = int(preset["grade"])
	d.grade_name = key if PRESETS.has(key) else "kriegsherr"
	d.ev_noise = float(preset["ev_noise"])
	d.rule_exploitation = float(preset["rule_exploitation"])
	d.mission_focus = float(preset["mission_focus"])
	d.coordination = float(preset["coordination"])
	d.lookahead = bool(preset["lookahead"])
	d.base_seed = p_base_seed
	return d


## The ordered grade names (weakest → strongest) — the arena ladder, for UI / tooling / test shape.
static func grade_names() -> Array:
	return ["rekrut", "veteran", "kriegsherr", "albtraum"]


## A flat view of this preset's knobs (for the decision record and tests).
func to_dict() -> Dictionary:
	return {"grade": grade_name, "ev_noise": ev_noise, "rule_exploitation": rule_exploitation,
		"mission_focus": mission_focus, "coordination": coordination, "lookahead": lookahead}


# ===== Deterministic draws (pure — the whole point of "reproducible mistakes") =====

## FNV-1a over a list of ints → a non-negative 63-bit hash. Overflow wraps (Godot int64 two's-complement),
## which is exactly what a mixing hash wants; the mask keeps it non-negative for the modulo below.
static func _mix(parts: Array) -> int:
	var h := _FNV_OFFSET
	for p in parts:
		h = (h ^ int(p)) * _FNV_PRIME
	return h & _POS_MASK


## A deterministic float in [0,1) from integer seed parts — no RNG object, no shared state.
func _unit01(parts: Array, salt: int) -> float:
	var full: Array = [base_seed, salt] + parts
	return float(_mix(full) % _UNIT_RESOLUTION) / float(_UNIT_RESOLUTION)


# ===== Knob predicates the decision layer consults =====

## Whether this grade presses optional rule advantages (overlay targeting, boost spending).
func exploits_rules() -> bool:
	return rule_exploitation >= EXPLOIT_THRESHOLD


## Whether this grade would spend boost tokens if a boost subsystem existed (future hook — same gate as
## rule exploitation; there is no boost subsystem in this build, so this only feeds the decision record).
func spend_boosts() -> bool:
	return exploits_rules()


## Whether this grade FOCUS-FIRES (concentrates on the best target) or SPREADS across tied targets.
func focus_fires() -> bool:
	return coordination >= COORD_THRESHOLD


## Deterministically decide whether an activation IGNORES its uncontrolled objective and just fights (a
## legal choice; the tree normally prefers the objective). True with probability 1 − mission_focus. At
## mission_focus == 1.0 this is always false (byte-identical to the official tree).
func skips_objective(seed_parts: Array) -> bool:
	if mission_focus >= 1.0:
		return false
	return _unit01(seed_parts, SALT_OBJECTIVE) < (1.0 - mission_focus)


## Pick an index into a best-first ranked list of `n` tied candidates, applying ev_noise: with probability
## ev_noise the AI DEVIATES to the 2nd (or, half of those times, the 3rd) best; otherwise it takes the best
## (index 0). Deterministic and reproducible. n ≤ 1 or ev_noise == 0 ⇒ 0 (the sharpest play).
func noisy_pick(n: int, seed_parts: Array) -> int:
	if n <= 1 or ev_noise <= 0.0:
		return 0
	var r := _unit01(seed_parts, SALT_TARGET)
	if r >= ev_noise:
		return 0
	# Deviate: pick the 2nd-best; on the deeper half of the deviation band drop to the 3rd (when it exists).
	if n >= 3 and r < ev_noise * 0.5:
		return 2
	return 1

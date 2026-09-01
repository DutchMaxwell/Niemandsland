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
##   • persistence        — plan-persistence / role discipline (AI plausibility Stage 4). How strongly the
##                          commander's STANDING ORDERS survive across activations and rounds, re-validated
##                          rather than re-derived (Killzone continue/abort): a shooter HOLDS its firing
##                          position instead of being dragged off a clean shot, a melee unit keeps closing on
##                          ONE enemy across rounds. FULL (≥ PERSIST_FULL, kriegsherr/albtraum) holds a clean
##                          shot whenever the marker is not seizable THIS move; BASIC (≥ PERSIST_THRESHOLD,
##                          veteran) holds only when the marker is out of even a Rush; NONE (rekrut) never —
##                          units act locally/short-sighted (their characteristic idle-prone weakness).
##   • lookahead (bool)   — the ceiling flag (Albtraum): full EV lookahead / boost spending headroom. A design
##                          marker surfaced in the decision record; the deterministic engine is shared, so it
##                          currently equals Kriegsherr play plus the boost gate — the hook for future depth.
##   • placement (word)   — NML-1140 step 8: the objective-placement rung (doctrine ladder):
##                          "rulebook" (random-legal draw; low grades), "style" (argmax + fairness
##                          guard; middle), "search" (max^N mini-game; NACHTMAHR). Only NACHTMAHR
##                          presets exist, so every preset carries "search"; rulebook/style are
##                          parked machinery like the persistence tiers. See resolve_placement.
##
## DETERMINISM: every seeded draw is a PURE hash of explicit integer seed parts (base seed, side, activation
## index, unit-name hash, a per-knob salt) — NO shared RNG state, NO Math.random-style nondeterminism. Same
## seed + same preset ⇒ identical "mistakes". The mirror-fairness SIM never constructs a SoloDifficulty, so
## it stays byte-identical (the opts-pattern discipline: knobs live game-side only).

# ===== Constants =====

enum Grade { REKRUT, VETERAN, KRIEGSHERR, ALBTRAUM, NACHTMAHR }

## rule_exploitation at or above this presses optional advantages (overlay targeting, boosts).
const EXPLOIT_THRESHOLD := 1.0

## coordination below this spreads fire instead of concentrating it.
const COORD_THRESHOLD := 0.5

## persistence at/above this holds standing orders at all (BASIC discipline); at/above PERSIST_FULL the
## discipline is FULL (a clean shot is held whenever the marker is not seizable this move). Below it the
## grade keeps no standing orders — units re-decide locally each activation (rekrut's short-sighted play).
const PERSIST_THRESHOLD := 0.5
const PERSIST_FULL := 1.0

## Per-knob salts so the two independent draws inside ONE activation (objective skip, target noise) never
## correlate — same activation index, different salt ⇒ independent deterministic draws.
const SALT_TARGET := 101
const SALT_OBJECTIVE := 202

## FNV-1a 64-bit mixing constants — a self-contained deterministic hash (no reliance on engine hash()).
const _FNV_OFFSET := 1469598103934665603
const _FNV_PRIME := 1099511628211
const _POS_MASK := 0x7FFFFFFFFFFFFFFF
const _UNIT_RESOLUTION := 1000000

## ONE grade (maintainer 2026-07-22: "du kannst alle anderen Schwierigkeitsgrade entfernen. ich
## will nur nachtmahr und den mega stark. dümmer bauen wir später neu wenn wir mal eine starke KI
## haben."): NACHTMAHR — every strength knob at its ceiling. The knob MACHINERY (noise bands,
## persistence tiers, mission-focus draws) stays fully functional and unit-tested, so rebuilding
## weaker personas later is a matter of adding presets, not code.
const PRESETS := {
	"nachtmahr": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "placement": "search"},
	# NML-1073 M5 (working name, never exposed): the SHIPPED nachtmahr grade plus the
	# hero_fold knob. ALBTRAUM lookahead uses BattleSim too, so the knob touches the shipped
	# tree grade, not just the planner — this pairs it for a tree-vs-tree A/B before any
	# default flip.
	"nachtmahr_herofold": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "hero_fold": true, "placement": "search"},
	# PLANNER_V0 (NML-995, plan D6): NACHTMAHR knobs plus the 1-ply mission planner overlay in
	# SoloController._solve_planner. WORKING name for the arena A/B — no interactive exposure
	# before the measurement gate (>=55% vs the tree), and never a display name.
	# NML-1073 M5 (maintainer 27.08., "an der Realität halten"): the table-fidelity knobs
	# (pool1_rollout, hero_fold) are DEFAULT ON here — not worse on 298 pairs (four-arm A/B),
	# ~+14% table time. The four A/B arm presets below (planner_v0_pool1/_herofold/_both) keep
	# their own explicit combinations for future A/Bs and are untouched by this flip.
	"planner_v0": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "pool1_rollout": true, "hero_fold": true},
	# NML-1073 M2-4 (working name, never exposed): planner_v0 with the PLAYOUT
	# ARBITRATION armed and the hand eval kept — the recording arm the Rust port
	# is gated against. planner_v2 cannot serve: its `eval_fit` is a different
	# value function, which the port declines rather than approximates.
	# NML-1073 M5: table-fidelity knobs default on, same as planner_v0 (see above).
	"planner_v0s": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "playout_search": true, "pool1_rollout": true, "hero_fold": true},
	# E4 (eval-tuning wave): planner_v0 with the FITTED eval as the leaf — the
	# arena A/B pair for "did the data-derived value function beat the hand one".
	# NML-1073 M5: table-fidelity knobs default on, same as planner_v0 (see above).
	"planner_v1": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "eval_fit": true, "pool1_rollout": true, "hero_fold": true},
	# NML-1073 M5 BUG-3 (working name, never exposed): planner_v0 with the JOINED-HERO FOLD
	# armed in the imagination. One arm of the four-arm A/B the maintainer gated the promotion
	# on — nothing here becomes a default before that measurement.
	"planner_v0_herofold": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "hero_fold": true},
	# NML-1073 M5, the other two A/B arms. `planner_v0_pool1` is planner_v0 with the ONE-UNIT
	# POOL routed through the rollout (#410); `planner_v0_both` arms that AND the joined-hero
	# fold. With planner_v0 (neither) and planner_v0_herofold above, the four arms of the A/B
	# the maintainer gated the promotion on are all selectable PER SEAT.
	"planner_v0_pool1": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "pool1_rollout": true},
	"planner_v0_both": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "pool1_rollout": true, "hero_fold": true},
	# NML-1073 M5: table-fidelity knobs default on, same as planner_v0 (see above).
	"planner_v2": {"grade": Grade.NACHTMAHR, "ev_noise": 0.0, "rule_exploitation": 1.0, "mission_focus": 1.0, "coordination": 1.0, "persistence": 1.0, "lookahead": true, "avoid_overkill": true, "endgame_convergence": true, "planner": true, "placement": "search", "eval_fit": true, "playout_search": true, "pool1_rollout": true, "hero_fold": true},
}

## Legacy grade names (old harness scripts, saved arena invocations, docs) all resolve to
## NACHTMAHR via for_grade's fallback — nothing breaks, everything plays at the ceiling.
const LEGACY_GRADE_ALIASES := ["rekrut", "veteran", "kriegsherr", "albtraum", "albtraum_v1"]

# ===== State =====

var grade: int = Grade.NACHTMAHR
var grade_name: String = "kriegsherr"
var ev_noise: float = 0.0
var rule_exploitation: float = 1.0
var mission_focus: float = 1.0
var coordination: float = 1.0
var persistence: float = 1.0
var lookahead: bool = false
var avoid_overkill: bool = false   # albtraum v2: focus fire caps at the target's wound pool (claims ledger)
var endgame_convergence: bool = false   # albtraum v2: last-two-rounds marker runs + one-runner-per-marker spread
var planner: bool = false   # PLANNER_V0: route activations through the 1-ply mission planner overlay
var eval_fit: bool = false  # E4: planner leaves score with the FITTED eval (planner_v1)
var playout_search: bool = false  # S-wave: close top-2 arbitrated by full playouts (planner_v2)
## NML-1073 M5 (EXPERIMENT, default false): route a side's LAST un-activated unit through the
## rollout pick instead of _select_ai_unit's one-unit shortcut. env NML_POOL1_ROLLOUT=1 sets the
## same bit process-wide. Off = the shipped behaviour, byte-identical.
var pool1_rollout: bool = false
## NML-1073 M5 BUG-3 (EXPERIMENT, default false): the planner's IMAGINATION folds a JOINED
## HERO into its host — no activation of its own, the way SoloController.can_activate
## (solo_controller.gd:405-419) already refuses it on the real table. env NML_HERO_FOLD=1 sets
## the same bit process-wide. Off = the shipped behaviour, byte-identical.
var hero_fold: bool = false
## NML-1140 step 8: the placement rung this preset places objectives by (rulebook|style|search),
## resolved per game by resolve_placement — env override first, else the strongest seat's preset.
var placement: String = "rulebook"

## The game-level base seed folded into every deterministic draw (reproducibility across a rating run).
var base_seed: int = 0


# ===== Construction =====

## Build a difficulty from a preset NAME (case-insensitive). There is exactly ONE grade: every
## name — current, legacy or unknown — resolves to NACHTMAHR. The base seed is folded into every
## seeded draw so a whole game replays identically.
static func for_grade(name: String, p_base_seed: int = 0) -> SoloDifficulty:
	var key := name.strip_edges().to_lower()
	if not PRESETS.has(key):
		key = "nachtmahr"
	var preset: Dictionary = PRESETS[key]
	var d := SoloDifficulty.new()
	d.grade = int(preset["grade"])
	d.grade_name = key
	d.ev_noise = float(preset["ev_noise"])
	d.rule_exploitation = float(preset["rule_exploitation"])
	d.mission_focus = float(preset["mission_focus"])
	d.coordination = float(preset["coordination"])
	d.persistence = float(preset.get("persistence", 1.0))
	d.lookahead = bool(preset["lookahead"])
	d.avoid_overkill = bool(preset.get("avoid_overkill", false))
	d.endgame_convergence = bool(preset.get("endgame_convergence", false))
	d.planner = bool(preset.get("planner", false))
	d.eval_fit = bool(preset.get("eval_fit", false))
	d.playout_search = bool(preset.get("playout_search", false))
	d.pool1_rollout = bool(preset.get("pool1_rollout", false))
	d.hero_fold = bool(preset.get("hero_fold", false))
	d.placement = str(preset.get("placement", "rulebook"))
	d.base_seed = p_base_seed
	return d


## The available grade names — exactly one: NACHTMAHR (weaker personas return as presets later).
static func grade_names() -> Array:
	return ["nachtmahr"]


## NML-1140 step 8: THE one placement resolver — all three harnesses take their
## generate() rung from here and nowhere else. Env NML_OBJECTIVE_DOCTRINE
## (rulebook|style|search) beats the preset — the arena/test control (an explicit
## "rulebook" pins the random-legal draw back over a search preset, the A/B's control
## arm). Unset, the STRONGEST seat's preset decides (the layout is ONE shared game
## input, design 5; unknown grade names fall back to nachtmahr like for_grade).
## Unknown env words and an armed style/search without NML_OBJECTIVES=rulebook print
## one loud FATAL and return "?" — the harness quits on "?" (the label-bug class;
## a typo must never silently record a mislabeled corpus).
static func resolve_placement(p1_grade := "", p2_grade := "", objectives_mode := "") -> String:
	var m := OS.get_environment("NML_OBJECTIVE_DOCTRINE").strip_edges().to_lower()
	if m != "":
		if m != "rulebook" and m != "style" and m != "search":
			printerr("[OBJECTIVES] FATAL: unknown NML_OBJECTIVE_DOCTRINE '%s' (rulebook|style|search; unset = the preset decides) — refusing a mislabeled run" % m)
			return "?"
		if m != "rulebook" and objectives_mode != "rulebook":
			printerr("[OBJECTIVES] FATAL: NML_OBJECTIVE_DOCTRINE=%s requires NML_OBJECTIVES=rulebook — refusing an armed-but-inert run" % m)
			return "?"
		return m
	var s1 := p1_grade.strip_edges().to_lower()
	var s2 := p2_grade.strip_edges().to_lower()
	if not PRESETS.has(s1):
		s1 = "nachtmahr"
	if not PRESETS.has(s2):
		s2 = "nachtmahr"
	if int(PRESETS[s2]["grade"]) > int(PRESETS[s1]["grade"]):
		s1 = s2
	return str(PRESETS[s1].get("placement", "rulebook"))


## A flat view of this preset's knobs (for the decision record and tests).
func to_dict() -> Dictionary:
	return {"grade": grade_name, "ev_noise": ev_noise, "rule_exploitation": rule_exploitation,
		"mission_focus": mission_focus, "coordination": coordination, "persistence": persistence,
		"lookahead": lookahead, "avoid_overkill": avoid_overkill, "endgame_convergence": endgame_convergence,
		"planner": planner, "eval_fit": eval_fit, "placement": placement}


## Whether this grade plays the ENDGAME MARKER MATH (albtraum v2): from the second-to-last round a
## unit whose fight is marginal starts the trip to a reachable unheld marker, and the runner ledger
## spreads simultaneous trips across DIFFERENT markers (mirror draws: 3 of 5 markers ended neutral).
func converges_endgame() -> bool:
	return endgame_convergence


## Whether this grade routes focus fire around already-doomed targets (albtraum v2 claims ledger):
## expected damage committed by EARLIER activations this round counts against a target's wound pool,
## and a volley is scored only for the wounds the pool can still absorb — no stacking three units
## onto a target the first one already kills on expectation.
func avoids_overkill() -> bool:
	return avoid_overkill


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


## Plan-persistence / role-discipline TIER for the commander's standing orders (AI plausibility Stage 4):
##   2 = FULL    (kriegsherr/albtraum) — hold a clean shot whenever the marker is not seizable this move;
##   1 = BASIC   (veteran)             — hold a clean shot only when the marker is out of even a Rush;
##   0 = NONE    (rekrut)              — no standing orders; the unit re-decides locally each activation.
func persistence_tier() -> int:
	if persistence >= PERSIST_FULL:
		return 2
	if persistence >= PERSIST_THRESHOLD:
		return 1
	return 0


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

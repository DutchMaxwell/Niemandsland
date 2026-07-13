class_name AiEv
extends RefCounted
## Solo-AI capstone — the EXPECTED-VALUE metric that fills exactly the decision points the official OPR
## Solo & Co-Op rules leave undefined, computed from the SAME rule-aware AiCombatMath helpers the dice
## resolution uses (one math, no second truth). Pure + deterministic: probabilities, never dice — same
## inputs, same decision (the deterministic-tree philosophy, docs/SOLO_AI_PLAN.md "hybrid policy").
##
## HARD BOUNDARY (docs/SOLO_AI_PLAN.md): EV never overrides an official tree branch or targeting key.
## It only fills:
##   • the "better than" of the archetype classification (Solo & Co-Op v3.5.0 p.1 "Unit Types":
##     SHOOTING = "ranged better than melee", HYBRID = "melee better than ranged" — metric undefined);
##   • ranking among GENUINELY TIED candidates, where the official rules say "roll a die" — the shipped
##     hybrid policy replaces that die with a utility score.
##
## Rule flow-through: because every probability is derived from the wave-1..3 helpers, AP / Reliable /
## Blast / Deadly / Rending / Bane / Relentless / Surge / Furious / Thrust / Impact / Counter / Fear-less
## risk / Stealth / Evasive / Shielded / Cover / Regeneration all shape the scores automatically —
## Deadly naturally prefers Tough targets, Blast prefers big units, a Stealth target beyond 9" devalues.
##
## Unit context dictionary (unit_ctx / build via ctx_for): quality:int, defense:int, tough:int,
## models:int, artillery:bool, furious:bool, fearless:bool, impact:int, stealth:bool, evasive:bool,
## shielded:bool, in_cover:bool, counter_models:int, regeneration:bool. Missing keys default neutral.

# ===== Constants =====

## Probability of one specific face on a d6 — the "unmodified 6" chance behind the per-6 bonus-hit rules
## (Relentless / Surge / Furious: +1 hit per unmodified 6 → expected +attacks/6).
const SIX_P := 1.0 / 6.0

## The neutral reference defender for the archetype "better than" comparison (Solo & Co-Op v3.5.0 p.1
## leaves the metric undefined): Defense 4+, 5 models, Tough 1, no special rules — a documented
## convention, not an official value.
const NEUTRAL_DEFENDER := {"defense": 4, "tough": 1, "models": 5}

## Regeneration ignore target (GF/AoF Advanced Rules v3.5.1: each wound ignored on a 5+) — expected
## pass-through factor is 1 − P(5+) = 2/3.
const REGENERATION_TARGET := 5

## Self-Repair ignore target (wave-4 army-book rule, Robot Legions — official Army Forge text: each wound
## ignored on a 6+) — expected pass-through factor 1 − P(6+) = 5/6. All models must carry the rule.
const SELF_REPAIR_TARGET := 6


# ===== Context builders (GameUnit → EV context; the readers main.gd's resolution delegates to) =====

## Whether ALL models of a unit carry `rule` — the trigger form of Stealth / Evasive / Shielded ("units
## where all models have this rule"): the unit-level rule covers its own models (Army Forge semantics),
## and every attached hero must carry it too (a joined hero is a model of the unit — GF v3.5.1 "Hero").
static func rule_on_all_models(unit: GameUnit, rule: String) -> bool:
	if unit == null or not unit.has_special_rule(rule):
		return false
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			var hero := h as GameUnit
			if hero != null and hero.get_alive_count() > 0 and not hero.has_special_rule(rule):
				return false
	return true


## Rating X of a unit-level "Name(X)" special rule (0 if absent) — type-safe against label-only shapes
## (the wave-1 _rule_to_string lesson).
static func unit_rating(unit: GameUnit, rule_name: String) -> int:
	if unit == null:
		return 0
	var prefix := rule_name + "("
	for r in unit.get_special_rules():
		var s := str(r).strip_edges()
		if s.begins_with(prefix) and s.ends_with(")"):
			return maxi(int(s.substr(prefix.length(), s.length() - prefix.length() - 1).replace("+", "")), 0)
	return 0


## Build the EV context for a live unit. `in_cover` / `counter_models` come from the caller's terrain /
## weapon knowledge (cover is a terrain read, counter models a weapon walk — injected, not divined).
## Wave 5: `defense` is the Armor(X)-adjusted value ("counts as having Defense X+", best-of — the same
## AiCombatMath.armored_defense the dice path uses) and `morale_bonus` carries Banner's +1 (both gated
## by the system-scoped RulesRegistry, so a rule only fires where its book fields it).
static func ctx_for(unit: GameUnit, in_cover: bool = false, counter_models: int = 0) -> Dictionary:
	if unit == null:
		return NEUTRAL_DEFENDER.duplicate()
	return {
		"quality": unit.get_quality(),
		"defense": AiCombatMath.armored_defense(unit.get_defense(),
			unit_rating(unit, "Armor") if RulesRegistry.unit_rule_active(unit, "Armor") else 0),
		"morale_bonus": int(RulesRegistry.unit_param(unit, "Banner", "morale_bonus", AiCombatMath.BANNER_MORALE_BONUS)) \
			if RulesRegistry.unit_rule_active(unit, "Banner") else 0,
		"tough": maxi(unit_rating(unit, "Tough"), 1),
		"models": maxi(unit.get_alive_count(), 1),
		"artillery": unit.has_special_rule("Artillery"),
		"furious": unit.has_special_rule("Furious"),
		"fearless": unit.has_special_rule("Fearless"),
		"impact": unit_rating(unit, "Impact"),
		"stealth": rule_on_all_models(unit, "Stealth"),
		"evasive": rule_on_all_models(unit, "Evasive"),
		"shielded": rule_on_all_models(unit, "Shielded"),
		"in_cover": in_cover,
		"counter_models": counter_models,
		"regeneration": _regen_target(unit) > 0,
		"regen_target": _regen_target(unit),
	}


## The Regeneration-family wound-ignore roll target for a unit (0 = none): Regeneration / Medical Training
## → 5+ (any bearing model), else Self-Repair (wave-4 army-book, all models) → 6+. Mirrors main's
## _solo_regen_target so the EV metric and the dice resolution ignore wounds at the SAME rate — wave 5:
## both read the target from the RulesRegistry mechanics map (constants as byte-identical fallback).
static func _regen_target(unit: GameUnit) -> int:
	if unit.has_special_rule("Regeneration") or unit.has_special_rule("Medical Training"):
		return int(RulesRegistry.unit_param(unit, "Regeneration", "ignore_target", REGENERATION_TARGET))
	if rule_on_all_models(unit, "Self-Repair"):
		return int(RulesRegistry.unit_param(unit, "Self-Repair", "ignore_target", SELF_REPAIR_TARGET))
	return 0


## Stamp the Sergeant facet onto a unit's weapon profiles (wave 5, model-level rule): the FIRST profile
## with attacks gets "sergeant_attacks" = the bearer's own attack share (total attacks / alive models,
## min 1) — the pooled resolution's documented approximation of "when THIS model attacks". Gated by the
## system-scoped RulesRegistry so the rule only fires where the unit's book fields it. Returns the same
## array (profiles mutated in place — callers build them fresh per activation). Shared by the dice path
## and the EV metric (one stamping, one truth).
static func stamp_sergeant(profiles: Array, unit: GameUnit) -> Array:
	if unit == null or not RulesRegistry.unit_rule_active(unit, "Sergeant"):
		return profiles
	var alive: int = maxi(unit.get_alive_count(), 1)
	for p in profiles:
		var profile := p as Dictionary
		var attacks := int(profile.get("attacks", 0))
		if attacks <= 0:
			continue
		profile["sergeant_attacks"] = maxi(1, roundi(float(attacks) / float(alive)))
		break
	return profiles


# ===== Core expected value (one weapon profile) =====

## Expected wounds ONE weapon profile (AiShooting profile dict) deals to `def_ctx`, mirroring the real
## resolution step for step — to-hit modifiers, per-6 bonus hits, Blast, the Rending AP(+4) sub-batch,
## Bane save re-rolls, Deadly's Tough cap and the defender's Regeneration all use the same AiCombatMath
## rules as the dice path. `dist_in` gates the over-9" rules (ranged); melee is profile range 0.
static func profile_ev(profile: Dictionary, att: Dictionary, def_ctx: Dictionary, dist_in: float, charging: bool) -> float:
	var attacks := float(maxi(int(profile.get("attacks", 0)), 0))
	if attacks <= 0.0:
		return 0.0
	var melee: bool = int(profile.get("range", 0)) <= 0
	var quality := int(att.get("quality", 4))
	# — To-hit target: the same composition as _solo_melee_strike_phase / the shooting volleys —
	var target: int
	if melee:
		target = AiCombatMath.thrust_to_hit(quality, charging and bool(profile.get("thrust", false)))
		target = AiCombatMath.modified_hit_target(target, AiCombatMath.melee_hit_modifier(bool(def_ctx.get("evasive", false))))
	else:
		target = AiCombatMath.reliable_quality(quality, bool(profile.get("reliable", false)))
		target = AiCombatMath.modified_hit_target(target, AiCombatMath.shooting_hit_modifier(dist_in,
			bool(att.get("artillery", false)), bool(def_ctx.get("stealth", false)),
			bool(def_ctx.get("artillery", false)), bool(def_ctx.get("evasive", false))))
	var hits := attacks * AiCombatMath.success_chance(target)
	# — Per-unmodified-6 bonus hits (expected +attacks/6 each; "only the original hit counts as a 6") —
	if not melee and bool(profile.get("relentless", false)) and dist_in > AiCombatMath.LONG_RANGE_IN:
		hits += attacks * SIX_P
	if bool(profile.get("surge", false)):
		hits += attacks * SIX_P
	if melee and charging and (bool(profile.get("furious", false)) or bool(att.get("furious", false))):
		hits += attacks * SIX_P
	# — Sergeant (wave 5, model-level: the bearer's unmodified 6s deal +1 hit). The stamping caller
	#   (stamp_sergeant) marks ONE profile with the bearer's own attack share; expectation = share/6,
	#   the exact expected count of the bearer's 6s (mirrors the dice path's capped bonus) —
	var sergeant_attacks := float(mini(int(profile.get("sergeant_attacks", 0)), int(attacks)))
	if sergeant_attacks > 0.0:
		hits += sergeant_attacks * SIX_P
	# — Rending / Destructive (wave 4): the expected unmodified-6 hits save at AP(+4); NOT Blast-multiplied
	#   (matches the resolution's rending_ap_hits cap convention). Same AP(+4) math for both rules —
	var six_hits: float = attacks * SIX_P if (bool(profile.get("rending", false)) or bool(profile.get("destructive", false))) else 0.0
	# — Blast (GF v3.5.1: each hit ×min(X, models in target), after other rules) —
	var blast := int(profile.get("blast", 0))
	if blast > 1:
		hits *= float(clampi(blast, 1, maxi(int(def_ctx.get("models", 1)), 1)))
	six_hits = minf(six_hits, hits)
	# — Saves: Shielded then Cover (shooting only; Blast AND Indirect ignore cover — wave 5 — not
	#   Shielded) then AP —
	var defense := AiCombatMath.shielded_defense(int(def_ctx.get("defense", 4)), bool(def_ctx.get("shielded", false)))
	if not melee and blast <= 1 and not bool(profile.get("indirect", false)):
		defense = AiCombatMath.covered_defense(defense, bool(def_ctx.get("in_cover", false)))
	var ap := int(profile.get("ap", 0))
	var bane := bool(profile.get("bane", false))
	var unsaved := (hits - six_hits) * (1.0 - block_chance(defense, ap, bane)) \
		+ six_hits * (1.0 - block_chance(defense, ap + AiCombatMath.RENDING_AP_BONUS, bane))
	# — Deadly (Tough-capped multiply) —
	var deadly := int(profile.get("deadly", 0))
	if deadly > 0:
		unsaved *= float(AiCombatMath.deadly_multiplier(deadly, maxi(int(def_ctx.get("tough", 1)), 1)))
	# — Shred (wave 5): every save die (one per hit) that lands a natural 1 deals +1 wound — expected
	#   +hits/6, NOT Deadly-multiplied (mirrors the dice path's save-step reading) —
	if bool(profile.get("shred", false)):
		unsaved += hits * SIX_P
	# — Regeneration family (5+ Regeneration / 6+ Self-Repair ignores; only Bane/Rending bypass it — the
	#   _solo_ignores_regen rule. Destructive does NOT bypass, so its wounds are reduced here too) —
	if bool(def_ctx.get("regeneration", false)) and not (bane or bool(profile.get("rending", false))):
		unsaved *= 1.0 - AiCombatMath.success_chance(int(def_ctx.get("regen_target", REGENERATION_TARGET)))
	return unsaved


## Block probability of one save die at Defense + AP; with the striker's Bane the defender's unmodified
## 6s are re-rolled once (GF/AoF v3.5.1 p.13): P = P(2..5 block) + P(6) × P(re-roll blocks).
static func block_chance(defense: int, ap: int, bane: bool) -> float:
	var p := AiCombatMath.success_chance(AiCombatMath.save_target(defense, ap))
	if bane:
		p = (p - SIX_P) + SIX_P * p
	return clampf(p, 0.0, 1.0)


# ===== Side totals =====

## Expected wounds of a unit's SHOOTING at `dist_in`: every ranged profile that reaches (AiShooting
## profiles carry their range) fires per the split-fire grouping — totals are additive.
static func shoot_ev(profiles: Array, att: Dictionary, def_ctx: Dictionary, dist_in: float) -> float:
	var total := 0.0
	for p in profiles:
		var profile := p as Dictionary
		if int(profile.get("range", 0)) >= int(ceil(dist_in)) and int(profile.get("range", 0)) > 0:
			total += profile_ev(profile, att, def_ctx, dist_in, false)
	return total


## Expected wounds of a unit's MELEE strikes (all melee profiles; `charging` enables Furious/Thrust),
## plus the charge's Impact hits when charging.
static func melee_ev(profiles: Array, att: Dictionary, def_ctx: Dictionary, charging: bool) -> float:
	var total := 0.0
	for p in profiles:
		var profile := p as Dictionary
		if int(profile.get("range", 0)) <= 0:
			total += profile_ev(profile, att, def_ctx, 0.0, charging)
	if charging:
		total += impact_ev(att, def_ctx)
	return total


## Expected Impact wounds of a charge (GF/AoF v3.5.1 p.13): X dice per charging model minus the
## defender's Counter models (impact_total_dice), hit on 2+, saved at the Shielded-adjusted Defense
## (no AP — Impact is not a weapon), Regeneration applies (no bypass).
static func impact_ev(att: Dictionary, def_ctx: Dictionary) -> float:
	var dice := AiCombatMath.impact_total_dice(int(att.get("impact", 0)), int(att.get("models", 0)),
		int(def_ctx.get("counter_models", 0)))
	if dice <= 0:
		return 0.0
	var hits := float(dice) * AiCombatMath.success_chance(AiCombatMath.IMPACT_HIT_TARGET)
	var defense := AiCombatMath.shielded_defense(int(def_ctx.get("defense", 4)), bool(def_ctx.get("shielded", false)))
	var wounds := hits * (1.0 - block_chance(defense, 0, false))
	if bool(def_ctx.get("regeneration", false)):
		wounds *= 1.0 - AiCombatMath.success_chance(int(def_ctx.get("regen_target", REGENERATION_TARGET)))
	return wounds


## The charge matchup score for a TIE-BREAK between equally-valid charge targets: expected wounds we
## deal (Furious/Thrust/Impact in, scaled down by the defender's Counter strike-first — its expected
## counter wounds thin our attackers before we swing) minus the wounds their strike-back deals,
## risk-weighted: OUR Fearless halves the weight of wounds taken (its 4+ re-roll halves the chance a
## failed morale sticks — GF/AoF v3.5.1 p.13; an advisory heuristic, tie-breaks only).
static func charge_score(our_profiles: Array, us: Dictionary, their_profiles: Array, them: Dictionary) -> float:
	var dealt := melee_ev(our_profiles, us, them, true)
	# Counter strikes first (p.13): first-order attacker attrition = counter wounds / our wound pool.
	var counter_first := 0.0
	for p in their_profiles:
		var profile := p as Dictionary
		if int(profile.get("range", 0)) <= 0 and bool(profile.get("counter", false)):
			counter_first += profile_ev(profile, them, us, 0.0, false)
	var pool := maxf(1.0, float(int(us.get("models", 1))) * float(maxi(int(us.get("tough", 1)), 1)))
	dealt *= clampf(1.0 - counter_first / pool, 0.0, 1.0)
	var taken := melee_ev(their_profiles, them, us, false)
	var risk_weight: float = 0.5 if bool(us.get("fearless", false)) else 1.0
	# Banner (wave 5): +1 to morale test rolls shaves 1/6 off the chance a failed test sticks, so the
	# wounds-taken weight relaxes by morale_bonus/6 — an advisory heuristic, tie-breaks only (the same
	# discipline as the Fearless half-weight above).
	risk_weight *= maxf(0.0, 1.0 - float(int(us.get("morale_bonus", 0))) * SIX_P)
	return dealt - taken * risk_weight


# ===== The archetype "better than" (Solo & Co-Op v3.5.0 p.1 "Unit Types") =====

## Classify a unit for the REAL game: MELEE = no ranged weapons; otherwise HYBRID when the unit's melee
## is "better than" its ranged, else SHOOTING — the PDF leaves "better than" undefined, and this fills
## it with total expected wounds vs the NEUTRAL_DEFENDER: each ranged profile at its own max range, the
## melee side as a charge (Furious/Thrust/Impact included via `unit_ctx`). A tie goes to SHOOTING (reach
## also has value — the same tie rule as AiArchetype.classify). The SIM keeps the frozen
## AiArchetype.classify heuristic (its fairness oracle stays byte-identical); this metric is the real
## game's, per the planner-opts opt-in discipline.
static func classify(weapons: Array, unit_ctx: Dictionary) -> int:
	var ranged: Array = AiShooting.profiles_in_range(weapons, 0.0)
	var melee: Array = AiShooting.melee_profiles(weapons)
	if ranged.is_empty():
		return AiArchetype.Type.MELEE
	if melee.is_empty():
		return AiArchetype.Type.SHOOTING
	var ranged_total := 0.0
	for p in ranged:
		var profile := p as Dictionary
		ranged_total += profile_ev(profile, unit_ctx, NEUTRAL_DEFENDER, float(int(profile.get("range", 0))), false)
	var melee_total := melee_ev(melee, unit_ctx, NEUTRAL_DEFENDER, true)
	return AiArchetype.Type.HYBRID if melee_total > ranged_total else AiArchetype.Type.SHOOTING

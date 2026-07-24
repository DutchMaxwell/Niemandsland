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

## Measurement seam (like SoloController._solo_batch): the arena sets this false (NML_VERSATILE=0) to run
## the rule-OFF leg of a paired A/B. Default true — the shipped game always models Versatile Attack.
static var versatile_enabled := true

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
## Aura expansion (army-book "X Aura" — official text: "This model and its unit get X"): the base rules
## that a set of unit members (the unit + its attached Heroes) grant to the WHOLE unit via any "* Aura"
## they carry. The base keeps any qualifier ("Bane in Melee Aura" -> "Bane in Melee"). Pure; used by the
## import-time expander so every downstream rule check then sees the granted rule unit-wide.
static func aura_granted_rules(members: Array) -> Array:
	var granted: Array = []
	for m in members:
		var gu := m as GameUnit
		if gu == null:
			continue
		for r in gu.get_special_rules():
			var s := str(r).strip_edges()
			if s.ends_with(" Aura"):
				var base := s.trim_suffix(" Aura").strip_edges()
				if not base.is_empty() and not granted.has(base):
					granted.append(base)
	return granted


static func rule_on_all_models(unit: GameUnit, rule: String) -> bool:
	if unit == null or not unit.has_special_rule(rule):
		return false
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			var hero := h as GameUnit
			if hero != null and hero.get_alive_count() > 0 and not hero.has_special_rule(rule):
				return false
	return true


## EXACT unit-rule check — has_special_rule matches by PREFIX, so "Unpredictable" would false-positive
## on an "Unpredictable Fighter" unit (the Ferocious-vs-"Ferocious Boost" lesson). Rating stripped.
static func has_exact_rule(unit: GameUnit, rule: String) -> bool:
	if unit == null:
		return false
	for r in unit.get_special_rules():
		var name: String = (str((r as Dictionary).get("name", "")) if r is Dictionary else str(r))
		if name.strip_edges().get_slice("(", 0).strip_edges() == rule:
			return true
	return false


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
		"heavy_impact": unit_rating(unit, "Heavy Impact"),
		"ravage": unit_rating(unit, "Ravage"),
		"stealth": rule_on_all_models(unit, "Stealth"),
		"evasive": rule_on_all_models(unit, "Evasive"),
		"melee_evasion": rule_on_all_models(unit, "Melee Evasion"),
		"fortified": rule_on_all_models(unit, "Fortified"),
		# Guarded OR Versatile Defense's consistently-played def-half (both: +1 Def when shot/charged
		# from over 9" — one EV flag, one dice-path arithmetic).
		"guarded": rule_on_all_models(unit, "Guarded") or rule_on_all_models(unit, "Versatile Defense"),
		"ranged_shrouding": rule_on_all_models(unit, "Ranged Shrouding"),
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
	if unit == null:
		return profiles
	# Versatile Attack (army-book, unit-level): flag every profile so the >9" AP(+1)/+1-to-hit mode
	# choice reaches BOTH the EV metric and the dice path (one stamping, one truth — like Sergeant
	# below). Unit-level approximation, mirroring Royal Legion: applied unit-wide when the unit carries
	# the rule. Shooting facet only for now (the melee/charge >9" facet is a tracked follow-up).
	if versatile_enabled and (unit.has_special_rule("Versatile Attack")
			or not RulesRegistry.unit_rules_of_primitive(unit, "Versatile Attack").is_empty()):
		# Coverage wave: DATA aliases (Watchborn — same over-9\" AP(+1)/+1-to-hit pick) stamp the
		# same facet; the shooting half fires here, the charge half stays the tracked follow-up.
		for vp in profiles:
			(vp as Dictionary)["versatile_attack"] = true
	# Ferocious (unit rule: "when attacking, unmodified 6s deal 1 extra hit") = every weapon the unit
	# uses gets Surge. Stamp the surge facet the EV metric and the dice path already read. Exact match so
	# "Ferocious Boost" (a different rule) does not trigger it.
	for r in unit.get_special_rules():
		if str(r).strip_edges() == "Ferocious":
			for fp in profiles:
				(fp as Dictionary)["surge"] = true
			break
	# Coverage wave (2026-07-23): Surge-family DATA aliases via the generic primitive layer —
	# Devout (exact), Point-Blank Surge (within 12\"), Bloodborn/Clan Warrior/Primal (extra ATTACK
	# on 6s, rolled not auto-hit), Predator Fighter (melee-only extra attack), Devout Boost
	# (upgrade: successful 5s count too when engaging over 9\").
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Surge"):
		var ed := e as Dictionary
		var n := str(ed["name"])
		if n == "Surge" or n == "Ferocious":
			continue
		var sp: Dictionary = ed.get("params", {})
		if not str(sp.get("upgrades", "")).is_empty():
			continue   # upgrade entries (Devout Boost) ride the base facet below, never stamp alone
		for fp in profiles:
			var fpd := fp as Dictionary
			if bool(sp.get("melee_only", false)) and int(fpd.get("range", 0)) > 0:
				continue
			if bool(sp.get("extra_attack", false)):
				fpd["surge_attack"] = true
				fpd["surge_attack_rule"] = n
			else:
				fpd["surge"] = true
				if float(sp.get("within_in", 0.0)) > 0.0:
					fpd["surge_within_in"] = float(sp.get("within_in", 0.0))
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Surge"):
		var ed := e as Dictionary
		var sp: Dictionary = ed.get("params", {})
		var base_rule := str(sp.get("upgrades", ""))
		if base_rule.is_empty() or not has_exact_rule(unit, base_rule):
			continue
		for fp in profiles:
			var fpd := fp as Dictionary
			if bool(sp.get("extra_attack", false)) and bool(fpd.get("surge_attack", false)):
				fpd["surge_attack_low"] = int(sp.get("surge_low", 5))   # Primal Boost: 5-6 spawn attacks
			elif bool(fpd.get("surge", false)):
				fpd["surge_low"] = int(sp.get("surge_low", 5))
				fpd["surge_over_in"] = float(sp.get("over_in", 9.0))
	# Coverage wave (resolver audit): unit-level RENDING aliases ("Rending in Melee" / "when
	# Shooting" — granted or direct): stamp the rending facet onto the gated profile set.
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Rending"):
		var edr := e as Dictionary
		if str(edr["name"]) == "Rending":
			continue
		var spr: Dictionary = edr.get("params", {})
		for fp in profiles:
			var fpd := fp as Dictionary
			if bool(spr.get("melee_only", false)) and int(fpd.get("range", 0)) > 0:
				continue
			if bool(spr.get("shooting_only", false)) and int(fpd.get("range", 0)) <= 0:
				continue
			fpd["rending"] = true
	# Coverage wave: cover-ignore facet (unit-level "Ignores Cover when shooting" and kin — the
	# Indirect primitive's cover_only alias form): ranged profiles save against uncovered Defense.
	for e in RulesRegistry.unit_rules_of_primitive(unit, "Indirect"):
		var edx := e as Dictionary
		var spx: Dictionary = edx.get("params", {})
		if str(edx["name"]) != "Indirect" and bool(spx.get("cover_only", false)) and bool(spx.get("ignores_cover", false)):
			for fp in profiles:
				var fpd := fp as Dictionary
				if int(fpd.get("range", 0)) > 0:
					fpd["ignores_cover"] = true
	if not RulesRegistry.unit_rule_active(unit, "Sergeant"):
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


## Stamp each profile with its target-property conditional-AP specs (Shatter/Tear/Melee Slayer/
## Disintegrate) so profile_ev can value the extra AP against tough/armoured targets. Registry-driven +
## system-scoped via `unit`; profiles without such a weapon rule are left untouched (no cond_ap key).
static func stamp_conditional_ap(profiles: Array, unit: GameUnit) -> Array:
	if unit == null:
		return profiles
	var system := RulesRegistry.system_of_unit(unit)
	var faction := RulesRegistry.faction_of_unit(unit)
	# MODEL-level family members (Slayer / Piercing Hunter: "when this model shoots…") sit on the
	# UNIT — collect them once, stamp them onto every profile (deduped against weapon rules by name).
	var unit_specs: Array = []   # [{n: base name, p: params}]
	for r in unit.get_special_rules():
		var base := RulesRegistry.base_rule_name(str((r as Dictionary).get("name", "")) if r is Dictionary else str(r))
		var params: Dictionary = RulesRegistry.lookup(system, faction, base).get("params", {})
		if params.has("condition"):
			unit_specs.append({"n": base, "p": params})
	for p in profiles:
		var profile := p as Dictionary
		var specs: Array = []
		var seen: Dictionary = {}
		for r in profile.get("rules", []):
			var base := RulesRegistry.base_rule_name(str(r))
			var params: Dictionary = RulesRegistry.lookup(system, faction, base).get("params", {})
			if params.has("condition"):
				specs.append(params)
				seen[base] = true
			# Crack: on-6-to-hit AP bonus (per-die), stamped for profile_ev's six-hits sub-batch.
			if int(params.get("on6_ap", 0)) > 0:
				profile["on6_ap"] = int(params["on6_ap"])
		for us in unit_specs:
			if not seen.has((us as Dictionary)["n"]):
				specs.append((us as Dictionary)["p"])
		if not specs.is_empty():
			profile["cond_ap"] = specs
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
	# Wave 6: a spell buff/debuff's ±N to hit rolls (AiSpell P3 seam) folds into the SAME net-modifier
	# composition as the rule modifiers — 0 when absent, so the pre-spell EV is byte-identical.
	var spell_mod := int(att.get("spell_hit_mod", 0))
	# — To-hit target: the same composition as _solo_melee_strike_phase / the shooting volleys —
	var target: int
	if melee:
		target = AiCombatMath.thrust_to_hit(quality, charging and bool(profile.get("thrust", false)))
		target = AiCombatMath.modified_hit_target(target,
			AiCombatMath.melee_hit_modifier(bool(def_ctx.get("evasive", false)),
				bool(def_ctx.get("melee_evasion", false))) + spell_mod)
	else:
		target = AiCombatMath.reliable_quality(quality, bool(profile.get("reliable", false)))
		target = AiCombatMath.modified_hit_target(target, AiCombatMath.shooting_hit_modifier(dist_in,
			bool(att.get("artillery", false)), bool(def_ctx.get("stealth", false)),
			bool(def_ctx.get("artillery", false)), bool(def_ctx.get("evasive", false))) + spell_mod)
	# — Versatile Attack (army-book): over 9" (shooting), pick the EV-better of +1 to hit or AP(+1) via the
	#   SAME chooser the dice path calls. hit_mod improves the to-hit here; the ap bonus folds in below —
	var versatile := {}
	if bool(profile.get("versatile_attack", false)) and dist_in > AiCombatMath.LONG_RANGE_IN and (not melee or charging):
		# Chooser inputs MUST match the dice path's (xhigh review find): main passes the SHIELDED defense
		# (not covered) — pass the same basis here, or a Shielded target could flip the plan/dice mode choice.
		var choose_def := AiCombatMath.shielded_defense(int(def_ctx.get("defense", 4)), bool(def_ctx.get("shielded", false)))
		versatile = versatile_best_mode(target, choose_def, int(profile.get("ap", 0)), bool(profile.get("bane", false)))
		target = AiCombatMath.modified_hit_target(target, int(versatile.get("hit_mod", 0)))
	# Precise (army-book weapon rule): flat +1 to hit when attacking, any range (melee or shooting).
	if bool(profile.get("precise", false)):
		target = AiCombatMath.modified_hit_target(target, 1)
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
	# — On-6 AP (wave 4 Rending/Destructive at the fixed +4; wave-5 army-book Crack at a stamped per-weapon
	#   bonus): the expected unmodified-6 hits save at AP(+on6_ap); NOT Blast-multiplied (matches the
	#   resolution's rending_ap_hits cap convention). Fallback keeps Rending/Destructive byte-identical.
	var on6_ap := int(profile.get("on6_ap", 0))
	if on6_ap == 0 and (bool(profile.get("rending", false)) or bool(profile.get("destructive", false))):
		on6_ap = AiCombatMath.RENDING_AP_BONUS
	var six_hits: float = attacks * SIX_P if on6_ap > 0 else 0.0
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
	# Guarded (quick-win batch: "+1 to defense rolls" when shot or charged from over 9" away) — the
	# SHOOTING side gates on the volley distance here; the charge side lives only in the dice
	# resolution, because melee EV always values at dist 0 (the Versatile Attack precedent).
	if not melee:
		defense = AiCombatMath.guarded_defense(defense,
			bool(def_ctx.get("guarded", false)) and dist_in > AiCombatMath.LONG_RANGE_IN)
	var ap := int(profile.get("ap", 0)) + int(versatile.get("ap", 0))   # Versatile Attack AP(+1) mode
	# Target-property conditional AP (Shatter/Tear/Melee Slayer/Disintegrate): value the extra AP this
	# weapon gets against THIS target, so the AI's targeting matches the dice resolution. One truth with
	# main._solo_conditional_ap (both read the same registry params via AiCombatMath.conditional_ap_bonus).
	for cap in profile.get("cond_ap", []):
		ap += AiCombatMath.conditional_ap_bonus(cap as Dictionary, maxi(int(def_ctx.get("tough", 1)), 1),
			int(def_ctx.get("defense", 4)), bool(def_ctx.get("charging", false)), dist_in, melee)
	var bane := bool(profile.get("bane", false))
	# Fortified (defender): each incoming hit's FINAL AP counts as -1 (min 0) — applied per sub-batch.
	var fort := bool(def_ctx.get("fortified", false))
	var unsaved := (hits - six_hits) * (1.0 - block_chance(defense, AiCombatMath.fortified_ap(ap, fort), bane)) \
		+ six_hits * (1.0 - block_chance(defense, AiCombatMath.fortified_ap(ap + on6_ap, fort), bane))
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


## Versatile Attack (army-book): over 9" the unit picks ONE effect for the activation — AP(+1) OR +1 to
## hit. This is the pure, EV-optimal chooser: given the composed to-hit target, the target's Defense, the
## profile AP and Bane, it returns which mode yields more unsaved wounds per attack. BOTH the EV metric
## (profile_ev) and the dice resolution (main._solo_shoot) call it with the SAME inputs, so the plan and
## the roll always pick the same mode — no over/under-prediction. Returns {"hit_mod": 0|1, "ap": 0|1}.
static func versatile_best_mode(hit_target: int, defense: int, ap: int, bane: bool) -> Dictionary:
	var ev_hit := AiCombatMath.success_chance(AiCombatMath.modified_hit_target(hit_target, 1)) \
		* (1.0 - block_chance(defense, ap, bane))               # +1 to hit
	var ev_ap := AiCombatMath.success_chance(hit_target) \
		* (1.0 - block_chance(defense, ap + 1, bane))           # AP(+1)
	if ev_ap >= ev_hit:
		return {"hit_mod": 0, "ap": 1}
	return {"hit_mod": 1, "ap": 0}


# ===== Side totals =====

## Expected wounds of a unit's SHOOTING at `dist_in`: every ranged profile that reaches (AiShooting
## profiles carry their range) fires per the split-fire grouping — totals are additive.
static func shoot_ev(profiles: Array, att: Dictionary, def_ctx: Dictionary, dist_in: float) -> float:
	var total := 0.0
	var shrouded: bool = bool(def_ctx.get("ranged_shrouding", false))
	for p in profiles:
		var profile := p as Dictionary
		# Ranged Shrouding on the DEFENDER shortens every profile's working range (-6" min 6") before
		# the in-range gate — so the AI never counts EV a shrouded target's denial would deny.
		var reach: float = AiCombatMath.shrouded_reach(float(profile.get("range", 0)),
			AiCombatMath.SHROUD_RANGE_PENALTY_IN, AiCombatMath.SHROUD_FLOOR_IN) if shrouded \
			else float(profile.get("range", 0))
		if reach >= ceilf(dist_in) and int(profile.get("range", 0)) > 0:
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
	total += ravage_ev(att, def_ctx)   # every melee turn, not just charges ("turn to attack in melee")
	return total


## Expected Ravage(X) wounds of a melee turn (army-book rule): X dice per alive bearer model, each 6+
## one DIRECT wound — no hit roll, no save; only Regeneration thins it (no bypass clause).
static func ravage_ev(att: Dictionary, def_ctx: Dictionary) -> float:
	var dice := int(att.get("ravage", 0)) * maxi(int(att.get("models", 0)), 0)
	if dice <= 0:
		return 0.0
	var wounds := float(dice) * AiCombatMath.success_chance(AiCombatMath.RAVAGE_WOUND_TARGET)
	if bool(def_ctx.get("regeneration", false)):
		wounds *= 1.0 - AiCombatMath.success_chance(int(def_ctx.get("regen_target", REGENERATION_TARGET)))
	return wounds


## Expected Impact wounds of a charge (GF/AoF v3.5.1 p.13): X dice per charging model minus the
## defender's Counter models (impact_total_dice), hit on 2+, saved at the Shielded-adjusted Defense
## (no AP — Impact is not a weapon), Regeneration applies (no bypass).
static func impact_ev(att: Dictionary, def_ctx: Dictionary) -> float:
	# Heavy Impact rides as a SECOND pool whose hits save at AP(1); Counter's denial strips the heavy
	# dice first (defender-optimal — mirrors the dice path).
	var models := maxi(int(att.get("models", 0)), 0)
	var counter := int(def_ctx.get("counter_models", 0))
	var heavy_raw := int(att.get("heavy_impact", 0)) * models
	var heavy_cut := mini(counter, heavy_raw)
	var heavy_dice := heavy_raw - heavy_cut
	var dice := AiCombatMath.impact_total_dice(int(att.get("impact", 0)), models, counter - heavy_cut)
	if dice + heavy_dice <= 0:
		return 0.0
	var p_hit := AiCombatMath.success_chance(AiCombatMath.IMPACT_HIT_TARGET)
	var defense := AiCombatMath.shielded_defense(int(def_ctx.get("defense", 4)), bool(def_ctx.get("shielded", false)))
	var wounds := float(dice) * p_hit * (1.0 - block_chance(defense, 0, false)) \
		+ float(heavy_dice) * p_hit * (1.0 - block_chance(defense, 1, false))
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

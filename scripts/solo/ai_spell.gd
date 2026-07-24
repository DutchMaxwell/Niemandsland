class_name AiSpell
extends RefCounted
## Solo-AI wave 6 — pure Caster(X)/spell math. Deterministic, headless-testable; no dice are rolled
## here and no game state is touched (the AiEv discipline: probabilities in, numbers out).
##
## The rule (GF/AoF/AoFS/AoFR/GFF Advanced Rules v3.5.1, "Caster(X)", byte-identical across all five
## systems): X spell tokens per round (cap 6, accumulating, also off-table); before attacking, spend
## tokens equal to a spell's value to try casting it (one try per spell); roll one die, on 4+ the
## effect resolves on a target in line of sight; models with tokens within 18" line of sight of the
## caster's unit may spend tokens at the same time for +1 (friendly) / -1 (enemy) per token.
##
## The official Solo & Co-Op v3.5.0 AI procedure ("Caster"): cast after moving (before attacking),
## selecting a random spell by rolling D3+X (X = caster level); if the spell has no valid target or
## costs more tokens than held, cycle through the list until a valid spell is found, else don't cast.
## official_pick_order() reproduces exactly that cycle; the EV helpers below fill ONLY what the
## procedure leaves open (which target, how many boost/interference tokens — the AiEv charter).
##
## THREE new primitives (the wave-6 design):
##   P1 cast_success_chance — token/boost/interference → cast probability,
##   P2 spell_damage_ev     — expected wounds of a FIXED-hit-count damage spell (no to-hit roll;
##                            Shielded and Cover do NOT apply against spell hits),
##   P3 spell_modifier_delta — the EV delta a buff/debuff modifier or rule grant is worth.

# ===== Constants (each cites its rule source) =====

## The base cast roll target (v3.5.1 Caster(X): "Roll one die, on 4+ resolve the effect").
## Data-driven at the call sites via RulesRegistry ("Caster".cast_target); this is the fallback seam.
const CAST_BASE_TARGET: int = 4

## The boost/interference aura range in inches (v3.5.1: "Models within 18\" in line of sight of the
## caster's unit may spend any number of spell tokens ... to give the caster +1/-1 to the roll per
## token"). Fallback for RulesRegistry "Caster".aura_in.
const AURA_RANGE_IN: float = 18.0

## Marginal expected wounds a boost/interference token must buy before the deterministic token
## economy spends it — the opportunity-cost floor of the wave-6 heuristic (a documented convention,
## not a rule value: a token held is a future cast's currency).
const TOKEN_VALUE_EPS: float = 0.05

## Probability of one specific d6 face (the on-6 facet expectation, mirrors AiEv.SIX_P).
const SIX_P := 1.0 / 6.0


# ===== P1 — cast probability =====

## The cast roll target after boost/interference (v3.5.1: +1 per friendly token, -1 per enemy token,
## on a 4+ base). Bounded to [2, 6]: a natural 1 always fails and a natural 6 always succeeds
## (core p.1 "Modifiers"), so no amount of tokens makes a cast certain or hopeless.
static func cast_target(boost_tokens: int, interference_tokens: int, base_target: int = CAST_BASE_TARGET) -> int:
	return clampi(base_target - maxi(boost_tokens, 0) + maxi(interference_tokens, 0),
		AiCombatMath.BEST_HIT_TARGET, AiCombatMath.UNMODIFIED_SIX)


## P1: probability the cast roll succeeds given the tokens spent on both sides. Base 4+ = 0.5;
## +1 boost → 3+ = 2/3; -1 interference → 5+ = 1/3; clamp-bounded to [1/6, 5/6].
static func cast_success_chance(boost_tokens: int, interference_tokens: int, base_target: int = CAST_BASE_TARGET) -> float:
	return AiCombatMath.success_chance(cast_target(boost_tokens, interference_tokens, base_target))


# ===== Spell damage facets (the weapon-rule tokens of the committed spell maps) =====

## Parse a spell's weapon-rule token list (["AP(1)", "Blast(3)", "Bane", …] — the committed
## spells_mechanics_<system>.json encoding) into the facet knobs P2 consumes. Unknown tokens are
## ignored (conservative: the spell still deals its base hits, the exotic facet adds nothing).
##   ap / blast / deadly     — rated facets (AiShooting rating convention);
##   bane                    — defender re-rolls unmodified Defense 6s (Lacerate is the AoF sibling
##                             with the same re-roll text; both also bypass Regeneration);
##   shred                   — +1 wound per unmodified Defense 1;
##   surge                   — +1 hit per 6 on the spell's trigger roll ("Roll as many dice as hits");
##   on6_ap                  — AP(+X) upgrade on trigger-roll 6s (Crack +2 / Destructive +4);
##   ignores_regen           — Bane / Lacerate / Disintegrate wounds bypass Regeneration;
##   ap_vs_tough3/9, ap_vs_def3 — the conditional AP facets (Shatter / Tear / Disintegrate), resolved
##                             against the actual defender by effective_ap().
static func spell_facets(weapon_rules: Array) -> Dictionary:
	var f := {"ap": 0, "blast": 0, "deadly": 0, "bane": false, "shred": false, "surge": false,
		"on6_ap": 0, "ignores_regen": false, "ap_vs_tough3": 0, "ap_vs_tough9": 0, "ap_vs_def3": 0}
	for r in weapon_rules:
		var s := str(r).strip_edges()
		var base := s.get_slice("(", 0).strip_edges()
		match base:
			"AP":
				f["ap"] = maxi(int(f["ap"]), _rating(s))
			"Blast":
				f["blast"] = _rating(s)
			"Deadly":
				f["deadly"] = _rating(s)
			"Bane", "Lacerate":
				f["bane"] = true
				f["ignores_regen"] = true
			"Shred":
				f["shred"] = true
			"Surge":
				f["surge"] = true
			"Crack":
				f["on6_ap"] = maxi(int(f["on6_ap"]), 2)
			"Destructive":
				f["on6_ap"] = maxi(int(f["on6_ap"]), AiCombatMath.RENDING_AP_BONUS)
			"Hazardous":
				# "Gets AP(4), but this model's unit takes one wound on unmodified rolls of 1" — the
				# AP facet lands here; the self-wound side is the caller's trigger-roll business.
				f["ap"] = maxi(int(f["ap"]), 4)
			"Disintegrate":
				f["ignores_regen"] = true
				f["ap_vs_def3"] = 2
			"Shatter":
				f["ap_vs_tough3"] = 2
			"Tear":
				f["ap_vs_tough9"] = 4
			_:
				pass   # unknown facet: conservative no-op (base hits still count)
	return f


static func _rating(rule: String) -> int:
	var open := rule.find("(")
	var close := rule.find(")")
	if open < 0 or close <= open:
		return 0
	return maxi(int(rule.substr(open + 1, close - open - 1).replace("+", "")), 0)


## The effective AP of a spell against a CONCRETE defender: the flat AP plus the conditional facets
## (Shatter: +2 vs majority Tough(3)+; Tear: +4 vs Tough(9)+; Disintegrate: +2 vs Defense 2-3+),
## each per its official army-book condition.
static func effective_ap(facets: Dictionary, def_ctx: Dictionary) -> int:
	var ap := int(facets.get("ap", 0))
	var tough := maxi(int(def_ctx.get("tough", 1)), 1)
	if int(facets.get("ap_vs_tough3", 0)) > 0 and tough >= 3:
		ap += int(facets["ap_vs_tough3"])
	if int(facets.get("ap_vs_tough9", 0)) > 0 and tough >= 9:
		ap += int(facets["ap_vs_tough9"])
	if int(facets.get("ap_vs_def3", 0)) > 0 and int(def_ctx.get("defense", 4)) <= 3:
		ap += int(facets["ap_vs_def3"])
	return ap


# ===== P2 — damage-spell expected wounds =====

## P2: expected wounds of a damage spell against `def_ctx` (an AiEv.ctx_for context). Spells deal a
## FIXED hit count — there is no to-hit roll, so the attacks × P(hit) step of profile_ev does not
## exist here. Two hard save-side deviations from shooting (the wave-6 design §3.1):
##   • Shielded does NOT apply ("+1 to defense rolls against hits that are not from spells" —
##     army-book rule text, quoted at AiCombatMath.SHIELDED_DEFENSE_BONUS), and
##   • Cover does NOT apply (GF v3.5.1 p.11 grants it "against shooting"; a spell is not shooting).
## So the save rolls against the RAW (Armor-adjusted) Defense of the context. Everything after the
## hit count reuses the shooting math: Blast ×min(X, models), the on-6 trigger-roll facets as an
## expected AP-upgraded sub-batch (the spell text adds "Roll as many dice as hits …"), Bane re-rolls
## via AiEv.block_chance, Deadly's Tough cap, Shred's +hits/6, and the Regeneration family.
static func spell_damage_ev(hits: int, def_ctx: Dictionary, facets: Dictionary = {}) -> float:
	if hits <= 0:
		return 0.0
	var h := float(hits)
	# Trigger-roll facets (one die per base hit): Surge adds a hit per 6; Crack/Destructive upgrade
	# the AP of the 6s' hits. Expectation: hits/6 each.
	if bool(facets.get("surge", false)):
		h += float(hits) * SIX_P
	var six_hits: float = float(hits) * SIX_P if int(facets.get("on6_ap", 0)) > 0 else 0.0
	# Blast (GF v3.5.1: each hit ×min(X, models), "after resolving other special rules").
	var blast := int(facets.get("blast", 0))
	if blast > 1:
		h *= float(clampi(blast, 1, maxi(int(def_ctx.get("models", 1)), 1)))
	six_hits = minf(six_hits, h)
	# Saves at the RAW Defense — no Shielded, no Cover (see above).
	var defense := int(def_ctx.get("defense", 4))
	var bane := bool(facets.get("bane", false))
	var ap := effective_ap(facets, def_ctx)
	var unsaved := (h - six_hits) * (1.0 - AiEv.block_chance(defense, ap, bane)) \
		+ six_hits * (1.0 - AiEv.block_chance(defense, ap + int(facets.get("on6_ap", 0)), bane))
	# Deadly (Tough-capped multiply — one model takes them all, so Tough bounds it).
	var deadly := int(facets.get("deadly", 0))
	if deadly > 0:
		unsaved *= float(AiCombatMath.deadly_multiplier(deadly, maxi(int(def_ctx.get("tough", 1)), 1)))
	# Shred: +1 wound per unmodified Defense 1 among the save dice (one per hit) — expected +h/6.
	if bool(facets.get("shred", false)):
		unsaved += h * SIX_P
	# Regeneration family, unless the facets bypass it (Bane / Lacerate / Disintegrate).
	if bool(def_ctx.get("regeneration", false)) and not (bane or bool(facets.get("ignores_regen", false))):
		unsaved *= 1.0 - AiCombatMath.success_chance(int(def_ctx.get("regen_target", AiEv.REGENERATION_TARGET)))
	return unsaved


# ===== P3 — buff/debuff EV delta =====

## P3: the expected-wounds DELTA a spell modifier/grant is worth on one side's attack: EV(with the
## effect) − EV(without), over the SAME AiEv chain the targeting/decision layer already uses. The
## parametrised buff/debuff building block of the wave-6 design:
##   effect.modifier.hit_mod  — ±N to hit rolls (folds into the profile_ev to-hit composition via
##                              the att ctx "spell_hit_mod" seam),
##   effect.modifier.def_mod  — ±N to defense rolls (a save target N better/worse, clamped [2,6]),
##   effect.grants_rule       — Bane / Shred (the EV-visible profile facets; scope-gated),
##   anything else            — 0.0 (movement/range/morale/casting modifiers carry no EV in this
##                              chain yet — the honest wave-6 boundary, logged as such).
## `ranged` picks the shoot_ev (at dist_in) vs melee_ev (charging) side; a scoped effect that does
## not apply to that side ("in melee" vs a shooting evaluation) is worth 0 by definition.
static func spell_modifier_delta(profiles: Array, att: Dictionary, def_ctx: Dictionary,
		effect: Dictionary, ranged: bool, dist_in: float, charging: bool = false) -> float:
	if profiles.is_empty():
		return 0.0
	var scope := str(effect.get("scope", ""))
	if (scope == "melee" and ranged) or (scope == "shooting" and not ranged) \
			or (scope == "charging" and not charging):
		return 0.0
	var att2 := att.duplicate()
	var def2 := def_ctx.duplicate()
	var profiles2: Array = profiles
	var modifier: Dictionary = effect.get("modifier", {})
	var grant := str(effect.get("grants_rule", ""))
	var changed := false
	if modifier.has("hit_mod"):
		att2["spell_hit_mod"] = int(att.get("spell_hit_mod", 0)) + int(modifier["hit_mod"])
		changed = true
	if modifier.has("def_mod"):
		# +1 to defense rolls = a save target one BETTER (lower), the shielded_defense arithmetic;
		# negative = worse. Clamped to [2,6] (natural 1 fails, natural 6 blocks).
		def2["defense"] = clampi(int(def_ctx.get("defense", 4)) - int(modifier["def_mod"]),
			AiCombatMath.BEST_HIT_TARGET, AiCombatMath.UNMODIFIED_SIX)
		changed = true
	if grant.begins_with("Bane") or grant == "Shred":
		var flag := "bane" if grant.begins_with("Bane") else "shred"
		profiles2 = []
		for p in profiles:
			var copy := (p as Dictionary).duplicate()
			copy[flag] = true
			profiles2.append(copy)
		changed = true
	if not changed:
		return 0.0
	return _side_ev(profiles2, att2, def2, ranged, dist_in, charging) \
		- _side_ev(profiles, att, def_ctx, ranged, dist_in, charging)


static func _side_ev(profiles: Array, att: Dictionary, def_ctx: Dictionary, ranged: bool,
		dist_in: float, charging: bool) -> float:
	if ranged:
		return AiEv.shoot_ev(profiles, att, def_ctx, dist_in)
	return AiEv.melee_ev(profiles, att, def_ctx, charging)


# ===== The official Solo v3.5.0 spell pick =====

## The exact official selection cycle: the D3+X roll indexes the faction's BOOK-ORDERED spell list
## (1-based, wrapped), and the AI then cycles forward through the list until a valid spell is found.
## Returns the 0-based candidate order to probe; empty for an empty list. Deterministic given the
## rolled D3 (the caller rolls it — seeded RNG in self-play, so a match replays identically).
static func official_pick_order(list_size: int, d3: int, caster_x: int) -> Array:
	if list_size <= 0:
		return []
	var start: int = (clampi(d3, 1, 3) + maxi(caster_x, 0) - 1) % list_size
	var order: Array = []
	for i in range(list_size):
		order.append((start + i) % list_size)
	return order


# ===== Token economy (deterministic heuristics — the officially-open boost/interference choice) =====

## Boost tokens worth spending on a cast worth `effect_value` expected wounds, with `available`
## helper tokens in 18" LoS: spend while the NEXT token's marginal EV — [P(boost+1) − P(boost)] ×
## effect_value — exceeds the opportunity-cost floor (TOKEN_VALUE_EPS per token, the documented
## wave-6 convention). The [2,6] clamp naturally stops the spend once the roll can't improve.
static func plan_boost(effect_value: float, available: int, interference_tokens: int = 0,
		base_target: int = CAST_BASE_TARGET, min_gain: float = TOKEN_VALUE_EPS) -> int:
	var boost := 0
	while boost < available:
		var gain := (cast_success_chance(boost + 1, interference_tokens, base_target)
			- cast_success_chance(boost, interference_tokens, base_target)) * maxf(effect_value, 0.0)
		if gain <= min_gain:
			break
		boost += 1
	return boost


## F4/NML-006 — pure once-mod filtering for the DICE path (mirrors the exporter's encoding, tested):
## records = [{spell, hit_mod, def_mod, casting_mod, morale_mod, range_in, advance_in, rush_in,
## grants_rule, scope, beneficiary, duration}]. role selects the reading:
##   "attacker_own" : the token BEARER attacks — its own hit_mod (beneficiary != "attackers")
##   "vs_target"    : units attacking the BEARER — hit_mod with beneficiary == "attackers"
##   "defense"      : the bearer defends — def_mod (no attackers-def encoding exists in the data)
##   "casting"      : the bearer casts — casting_mod ("-3 to casting rolls" shifts the roll target)
##   "morale"       : the bearer takes a morale test — morale_mod
##   "range"        : the bearer shoots — range_in (shooting-scoped in the data; call with melee=false)
##   "speed"        : the bearer moves — advance_in/rush_in (feeds the props stamp, NML-006)
##   "grant"        : records granting a special rule (grants_rule non-empty; the overlay reader)
## melee filters scope ("melee"/"shooting"/"attacking"/""); "charging" is never applied here (v1).
static func mods_for(records: Array, role: String, melee: bool) -> Array:
	var out: Array = []
	for r in records:
		var rd := r as Dictionary
		var scope := str(rd.get("scope", ""))
		if scope == "charging" or (scope == "melee" and not melee) or (scope == "shooting" and melee):
			continue
		var attackers := str(rd.get("beneficiary", "")) == "attackers"
		match role:
			"attacker_own":
				if not attackers and int(rd.get("hit_mod", 0)) != 0:
					out.append(rd)
			"vs_target":
				if attackers and int(rd.get("hit_mod", 0)) != 0:
					out.append(rd)
			"defense":
				if not attackers and int(rd.get("def_mod", 0)) != 0:
					out.append(rd)
			"casting":
				if int(rd.get("casting_mod", 0)) != 0:
					out.append(rd)
			"morale":
				if int(rd.get("morale_mod", 0)) != 0:
					out.append(rd)
			"range":
				if int(rd.get("range_in", 0)) != 0:
					out.append(rd)
			"speed":
				if int(rd.get("advance_in", 0)) != 0 or int(rd.get("rush_in", 0)) != 0:
					out.append(rd)
			"grant":
				if not str(rd.get("grants_rule", "")).is_empty():
					out.append(rd)
	return out


## Interference tokens the OTHER side should spend against an announced cast worth `effect_value`
## to it (the same marginal calculus, mirrored: spend while the P-reduction per token times the
## effect's value exceeds the floor). `boost` is the caster side's already-committed boost.
static func plan_interference(effect_value: float, available: int, boost: int = 0,
		base_target: int = CAST_BASE_TARGET, min_gain: float = TOKEN_VALUE_EPS) -> int:
	var inter := 0
	while inter < available:
		var gain := (cast_success_chance(boost, inter, base_target)
			- cast_success_chance(boost, inter + 1, base_target)) * maxf(effect_value, 0.0)
		if gain <= min_gain:
			break
		inter += 1
	return inter

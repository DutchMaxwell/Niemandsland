#!/usr/bin/env python3
"""Export DERIVED, text-free special-rule mechanics maps for the solo AI.

Reads the maintainer's LOCAL rules registry (one JSON per (game system, faction)
book plus a per-system core file — see docs/RULES_REGISTRY.md in the registry
package) and emits one committed mechanics map per game system:

    assets/solo/rules_mechanics_<system>.json

The maps carry ONLY our own mechanic encoding — rule NAMES, the primitive that
automates each rule, and our numeric parameter knobs (verified against the
official rulebook PDFs). **No official rule text, description, or citation body
is ever copied into the output** (the registry data is OPR's IP and stays
local); a hygiene guard below refuses to write otherwise.

Lookup contract (mirrored by scripts/solo/rules_registry.gd): a rule is ALWAYS
resolved by (game_system, faction, name) with a fallback to
(game_system, "common", name) — never by name alone across systems, because
154 of 383 cross-system rule names diverge (skirmish/variant rewrites).

Usage:
    python3 tools/rules_mechanics_export.py                 # default registry path
    python3 tools/rules_mechanics_export.py --registry PATH # explicit registry
    python3 tools/rules_mechanics_export.py --check         # verify outputs are current
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

SYSTEMS = ["gf", "gff", "aof", "aofs", "aofr"]

# Keys that may appear in an emitted rule entry. Anything else is a bug (and a
# potential text leak), so the hygiene guard hard-fails on it.
ALLOWED_ENTRY_KEYS = {"primitive", "params", "rated", "book_version"}

# Registry keys whose VALUES must never reach the output (rule bodies / notes).
FORBIDDEN_SOURCE_KEYS = {"official_text", "text", "description", "reason", "note", "citation", "_license", "_note"}

# Longest legitimate short-slug param value ("shooting_melee" etc.). A hygiene
# ceiling — real rule texts are sentences and blow way past this.
MAX_PARAM_STRING = 24

# --- Our own primitive parameter encoding (NOT rule text) -------------------
# One block per primitive: the numeric/boolean knobs the game-side helpers
# consume. Values verified against the official GF/AoF Advanced Rules v3.5.1
# rulebook PDFs (and, for army-book rules, the fielded army data); they mirror
# the constants the wave-1..4 primitives shipped with (AiCombatMath).
PRIMITIVE_PARAMS = {
    "AP": {"rating": "X"},
    "Tough": {"rating": "X"},
    "Deadly": {"rating": "X", "tough_capped": True},
    "Blast": {"rating": "X", "ignores_cover": True},
    "Impact": {"rating": "X", "hit_target": 2},
    "Fear": {"rating": "X"},
    "Relentless": {"bonus_hits_per_six": 1, "over_in": 9.0},
    "Surge": {"bonus_hits_per_six": 1},
    "Furious": {"bonus_hits_per_six": 1, "charge_only": True},
    "Rending": {"ap_bonus": 4, "bypass_regen": True},
    "Bane": {"reroll_save_sixes": True, "bypass_regen": True},
    "Lacerate": {"bypass_regen": True},
    "Thrust": {"hit_bonus": 1, "ap_bonus": 1, "charge_only": True},
    "Reliable": {"quality": 2},
    "Fearless": {"recover_target": 4},
    "Stealth": {"hit_penalty": 1, "over_in": 9.0},
    "Evasive": {"hit_penalty": 1},
    "Shielded": {"defense_bonus": 1},
    "Artillery": {"shooter_hit_bonus": 1, "target_hit_penalty": 2, "over_in": 9.0, "hold_only": True},
    "Immobile": {"hold_only": True},
    "Regeneration": {"ignore_target": 5},
    "Self-Repair": {"ignore_target": 6, "all_models": True},
    # Resistance (AoF/GF army-book rule — official Army Forge text: "When a unit where all
    # models have this rule takes wounds, roll one die for each. On a 6+ it is ignored. If the
    # wounds were from a spell, then they are ignored on a 2+ instead."): the Regeneration family
    # with a second, far more generous threshold against spell wounds.
    "Resistance": {"ignore_target": 6, "ignore_target_spell": 2, "all_models": True},
    "Counter": {"strikes_first": True, "impact_reduction_per_model": 1},
    "Fast": {"advance_mod": 2, "rush_mod": 4},
    "Slow": {"advance_mod": -2, "rush_mod": -4},
    # Rapid Rush (army-book rule): "+6\" when using Rush actions" — Rush/Charge band only.
    "Rapid Rush": {"rush_mod": 6},
    "Battleborn": {"recover_target": 4},
    # Steadfast (quick-win batch): official text byte-identical to Battleborn — the round-start
    # Shaken recovery on a 4+ (shared _solo_battleborn_recovery seam, registry-tuned target).
    "Steadfast": {"recover_target": 4},
    # No Retreat (quick-win batch): a failed morale test causing Shaken/Rout counts as passed;
    # then one die per wound-to-fully-destroy, each 1-3 = one self-wound that bypasses regen.
    "No Retreat": {"self_wound_max": 3, "bypass_regen": True},
    # Guarded (quick-win batch): shot or charged from over 9" away -> +1 to defense rolls.
    "Guarded": {"defense_bonus": 1, "over_in": 9.0},
    # Shrouding family (denial primitives): enemies trying to shoot (-6" range) or charge
    # (-3" movement) get their reach reduced, never below the 6" floor. The "X Aura" forms are
    # expanded at import (aura wave), so only the base rules carry the mechanics.
    "Ranged Shrouding": {"range_penalty_in": 6.0, "floor_in": 6.0},
    "Melee Shrouding": {"move_penalty_in": 3.0, "floor_in": 6.0},
    # Data-lag closures (code shipped in earlier waves, the maps only now say so):
    # Versatile Attack: over-9" shoot/charge, pick AP(+1) or +1-to-hit (EV chooser for the AI,
    # the Bug-13 dialog for the human). Infiltrate: counts as Ambush, 3" arrival radius (Bug 26).
    "Versatile Attack": {"ap_bonus": 1, "hit_bonus": 1, "over_in": 9.0, "pick_one": True},
    "Infiltrate": {"counts_as": "Ambush", "min_enemy_dist_in": 3.0},
    # Grill round 2, cut A (2026-07-18): Unpredictable = the generic "when attacking" form of the
    # wave-4 melee-only Unpredictable Fighter (one die: 1-3 -> AP(+1), 4-6 -> +1 to hit).
    "Unpredictable": {"ap_bonus": 1, "hit_bonus": 1, "low_roll_max": 3},
    # Ravage(X): on the bearer's melee turn, X dice per alive model — each 6+ one DIRECT wound
    # (no hit roll, no save; Regeneration applies, no ignore clause).
    "Ravage": {"rating": "X", "wound_target": 6, "no_save": True},
    # Quick Shot: "may shoot after using Rush actions" — the move-and-shoot band becomes Rush.
    "Quick Shot": {"shoot_after_rush": True},
    # Mend: once per activation, before attacking — heal D3 wounds on a friendly Tough model in 3".
    "Mend": {"heal_d3": True, "range_in": 3.0, "requires_tough": True},
    # Breath Attack: once per activation, before attacking — 2+ for 1 hit Blast(3)/AP(1) at 6"/LOS.
    "Breath Attack": {"trigger_target": 2, "range_in": 6.0, "blast": 3, "ap": 1},
    # Repel Ambushers (cut B): enemy Ambushers must arrive over 12" from this unit.
    "Repel Ambushers": {"min_dist_in": 12.0},
    # Movement trio (cut C, EV-scored via the position machinery — grill decision):
    # Bounding: on activation, place all bearers within D3+1" (valued as a move-band bonus).
    "Bounding": {"place_d3_plus": 1},
    # Teleport: before attacking, place within 3" (Advance/Charge) or 6" (Rush).
    "Teleport": {"advance_bonus_in": 3.0, "rush_bonus_in": 6.0},
    # Hit & Run: once per round, up to 3" after shooting or being in melee.
    "Hit & Run": {"move_in": 3.0, "per_round": True},
    # Wahl-effect wave: Versatile Reach picks +4" shooting range OR +2" charge per activation
    # (AI: charge mode exactly when it unlocks the target's charge). Versatile Defense picks
    # +1 defense OR -1 enemy to-hit vs over-9" attacks; the automation consistently plays the
    # defense half (Guarded machinery; the hit half is a future EV switch — default_mode is data).
    "Versatile Reach": {"range_bonus_in": 4.0, "charge_bonus_in": 2.0, "pick_one": True},
    "Versatile Defense": {"defense_bonus": 1, "hit_penalty": 1, "over_in": 9.0, "default_mode": "def"},
    # Vanguard: after deploying, place the model within 9" — pushed toward the enemy side.
    "Vanguard": {"place_in": 9.0},
    # Move-mod band (autonomous wave 2026-07-19): name fallbacks in MovementRangeController,
    # descriptions parse them anyway — data closes the coverage honestly.
    "Quick": {"advance_mod": 2, "rush_mod": 2},
    "Rapid Advance": {"advance_mod": 4},
    "Swift": {"negates": "Slow"},
    # Unpredictable Shooter: the shooting-only half of the Unpredictable attack die.
    "Unpredictable Shooter": {"ap_bonus": 1, "hit_bonus": 1, "low_roll_max": 3},
    # --- Coverage wave 2026-07-23 (100%-Abdeckung): new primitives ---
    # Shot Modifier: flat attacker-side to-hit modifier when shooting (Good/Bad Shot), optional
    # over-9" gate (Targeting Visor) or terrain condition (Grounded Precision, all attacks).
    "Shot Modifier": {"hit_bonus": 1},
    # Second Wind (Inquisitorial Agent / Martial Prowess): once per game a full-carrier unit
    # activates a SECOND time in a round (fatigue cleared); army cap 1/3 of carriers per round.
    "Second Wind": {"uses_per_game": 1, "army_cap_fraction": 3},
    # Utility Buff: once per activation, before attacking — apply a once-mod (hit/casting/morale/
    # rule grant) to a target in range, or re-position a friendly Artillery model.
    "Utility Buff": {"range_in": 12.0, "once": True},
    # Mind Control: forced morale test on an enemy in 18"/LOS; failure -> up to 6" straight move.
    "Mind Control": {"range_in": 18.0, "move_in": 6.0, "needs_los": True},
    # Growth Markers: marker accrual (per_round or on_kill) with per-marker/per-two effects.
    "Growth Markers": {"max_markers": 4},
    # Piercing Tag: once per game, X markers on an enemy 24"/LOS; attackers spend for +AP.
    "Piercing Tag": {"rating": "X", "range_in": 24.0, "needs_los": True, "uses_per_game": 1},
    # Crossing Attack(X): move-through pick, X dice at 6+ -> direct wounds (no save).
    "Crossing Attack": {"rating": "X", "wound_target": 6},
    # Spell Conduit: friendly casters within range get +1 casting (position proxy approximated).
    "Spell Conduit": {"range_in": 12.0, "casting_mod": 1},
    # Transport(X): S1 mechanics shipped (capacity, embark/exit 6", destruction spill).
    "Transport": {"rating": "X"},
    # Storm Attack (chaos "Storm of X" family): once per game, before attacking — 3 dice, each 2+
    # one enemy unit within 12" takes 3 hits carrying the facet (surge/shred/bane/ap1).
    "Storm Attack": {"dice": 3, "trigger_target": 2, "range_in": 12.0, "hits": 3, "uses_per_game": 1},
    # Hit & Run halves: 3" step after shooting only / after melee only.
    "Hit & Run Shooter": {"move_in": 3.0, "per_round": True, "after": "shoot"},
    "Hit & Run Fighter": {"move_in": 3.0, "per_round": True, "after": "melee"},
    # Conditional-AP additions: Piercing Hunter (range-gated, no target property) and Slayer
    # (target Tough>=3 AND [over-9" shot OR charge] — the situational gate on top).
    "Piercing Hunter": {"ap_bonus": 1, "condition": "ranged_over", "over_in": 9.0},
    "Slayer": {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3,
               "gate": "ranged_over_or_charge", "over_in": 9.0},
    # Heavy Impact(X): a second impact pool whose hits carry AP(1).
    "Heavy Impact": {"rating": "X", "ap": 1, "counts_as": "Impact"},
    "Retaliate": {"rating": "X", "hits_per_wound": "X"},
    "Re-Deployment": {"max_units": 2},
    "Strafing": {"move_through_attack": True, "weapon_only": True},
    "Destructive": {"ap_bonus": 4, "bypass_regen": False},
    "Royal Legion": {"range_bonus_in": 4, "charge_mod": 2},
    # --- Wave 5 ---
    "Shred": {"extra_wound_per_save_one": 1},
    "Indirect": {"moved_hit_penalty": 1, "ignores_cover": True, "ignores_los": True, "hold_and_shoot": True},
    "Limited": {"uses_per_game": 1},
    "Banner": {"morale_bonus": 1, "scope": "unit"},
    "Musician": {"move_bonus_in": 1, "scope": "unit"},
    "Sergeant": {"bonus_hits_per_six": 1, "model_level": True},
    "Armor": {"rating": "X", "defense_value": "X", "best_of": True},
    # --- Wave-5 conditional-AP family (2026-07-18, grill "primitive families first") ---
    # Target-property AP rules: each its own primitive NAME but ALL read by the one generic
    # AiCombatMath.conditional_ap_bonus helper via {ap_bonus, condition, threshold, charge_only}.
    # condition: "vs_tough_ge" (target mostly Tough>=threshold) / "vs_armor" (target save<=threshold).
    "Shatter": {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3},
    "Tear": {"ap_bonus": 4, "condition": "vs_tough_ge", "threshold": 9},
    "Melee Slayer": {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3, "charge_only": True},
    "Disintegrate": {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3, "bypass_regen": True},
    # Piercing Assault (GF/AoF): "AP(+1) when charging" — the same conditional-AP reader, condition
    # "on_charge" (charge-gated, no target property). A reuse case, no new game code.
    "Piercing Assault": {"ap_bonus": 1, "condition": "on_charge"},
    # Crack (GF/AoF): "on unmodified 6 to hit, those hits get AP(+2)" — the Rending/Destructive on-6
    # machinery, but a per-weapon bonus (+2) instead of the fixed +4, and NO Regeneration bypass.
    "Crack": {"on6_ap": 2},
    # Melee Evasion: the melee-only Evasive ("-1 to hit rolls in melee when attacking this unit"). Same
    # hit_penalty as Evasive, but the shooting hit modifier ignores it (melee_only).
    "Melee Evasion": {"hit_penalty": 1, "melee_only": True},
    # Precise (army-book weapon rule): "+1 to hit when attacking" — a flat attacker-side to-hit bonus,
    # applied in one EV choke point (profile_ev) and one resolution choke point (_solo_hits).
    "Precise": {"hit_bonus": 1},
    # Fortified (defender): incoming hits count as AP(-1), to a min. of AP(0). Applied per-hit to the
    # final AP (AiCombatMath.fortified_ap) in profile_ev + _solo_save_batch.
    "Fortified": {"incoming_ap_reduction": 1},
    # --- Wave 6 (spellcasting) --- Caster(X) token economy, verified byte-identical
    # across all five systems in the official v3.5.1 rulebooks; held as per-system
    # DATA regardless, so a future skirmish errata stays a data change.
    "Caster": {"rating": "X", "token_cap": 6, "cast_target": 4, "aura_in": 18.0,
               "boost_per_token": 1},
    # --- AI plausibility wave 1 --- Aircraft (GF Advanced Rules v3.5.1 only — none of
    # AoF/AoFS/AoFR/GFF v3.5.1 field the rule, see SYSTEM_SCOPED_PRIMITIVES): mandatory
    # straight-line Advance-only move (+30" to the total move, at least 30" — the model may
    # not use a table edge to move less), ignores units/terrain while moving and stopping,
    # cannot seize or contest objectives, cannot be charged, and units targeting it get
    # -12" to their range. solo_move_in is the AI-section simplification (always 30").
    "Aircraft": {"advance_only": True, "straight_move": True, "move_add_in": 30.0,
                 "min_move_in": 30.0, "solo_move_in": 30.0, "cannot_seize": True,
                 "cannot_be_charged": True, "target_range_penalty_in": 12.0,
                 "ignores_obstacles": True},
}

# Per-(system, rule) parameter overrides — the SYSTEM-SCOPED divergences.
# GFF and AoFS (the skirmish-scale games) rewrite Banner/Musician to a
# "bearer + up to 3 friendly units picked before the game" scope; the full
# games grant the bearer's own unit. The picked-units facet is data here so
# the loader can surface it; the solo automation applies the bearer scope and
# flags the pick as manual (see docs/SOLO_AI_RULES_COVERAGE.md).
SYSTEM_PARAM_OVERRIDES = {
    ("gff", "Banner"): {"morale_bonus": 1, "scope": "picked", "picked_units": 3},
    ("aofs", "Banner"): {"morale_bonus": 1, "scope": "picked", "picked_units": 3},
    ("gff", "Musician"): {"move_bonus_in": 1, "scope": "picked", "picked_units": 3},
    ("aofs", "Musician"): {"move_bonus_in": 1, "scope": "picked", "picked_units": 3},
}

# Wave-5 rule -> primitive mapping. The registry still marks these rules
# unautomated (its mechanic proposals mirror the PREVIOUS wave's game
# vocabulary); this table is the bridging seam until the registry sync tool
# re-runs with the wave-5 vocabulary. Names must match registry rule names.
WAVE5_PRIMITIVES = {
    "Shred": "Shred",
    "Indirect": "Indirect",
    "Limited": "Limited",
    "Banner": "Banner",
    "Musician": "Musician",
    "Sergeant": "Sergeant",
    "Armor": "Armor",
    # Wave-5 coverage push (2026-07-17): Resistance -> Regeneration-family primitive with a
    # spell-wound threshold. First of the "primitive families first" batch (grill decision).
    "Resistance": "Resistance",
    # Wave-5 conditional-AP family (2026-07-18): target-property AP rules (see PRIMITIVE_PARAMS).
    "Shatter": "Shatter",
    "Tear": "Tear",
    "Melee Slayer": "Melee Slayer",
    "Disintegrate": "Disintegrate",
    "Piercing Assault": "Piercing Assault",
    "Crack": "Crack",
    "Melee Evasion": "Melee Evasion",
    "Precise": "Precise",
    # Ferocious (unit rule) = Surge on every weapon the unit uses (stamped in AiEv.stamp_sergeant).
    "Ferocious": "Surge",
    "Fortified": "Fortified",
    # Quick-win batch (2026-07-18): Rapid Rush = the Fast-family movement modifier (Rush only;
    # bands via MovementRangeController description parser + name fallback).
    "Rapid Rush": "Rapid Rush",
    "Steadfast": "Steadfast",
    "No Retreat": "No Retreat",
    "Guarded": "Guarded",
    "Ranged Shrouding": "Ranged Shrouding",
    "Melee Shrouding": "Melee Shrouding",
    "Versatile Attack": "Versatile Attack",
    "Infiltrate": "Infiltrate",
    "Unpredictable": "Unpredictable",
    "Ravage": "Ravage",
    "Quick Shot": "Quick Shot",
    "Mend": "Mend",
    "Breath Attack": "Breath Attack",
    "Repel Ambushers": "Repel Ambushers",
    "Bounding": "Bounding",
    "Teleport": "Teleport",
    "Hit & Run": "Hit & Run",
    "Versatile Reach": "Versatile Reach",
    "Versatile Defense": "Versatile Defense",
    "Vanguard": "Vanguard",
    "Quick": "Quick",
    "Rapid Advance": "Rapid Advance",
    "Swift": "Swift",
    "Unpredictable Shooter": "Unpredictable Shooter",
    "Hit & Run Shooter": "Hit & Run Shooter",
    "Hit & Run Fighter": "Hit & Run Fighter",
    "Piercing Hunter": "Piercing Hunter",
    "Slayer": "Slayer",
    "Heavy Impact": "Heavy Impact",
    # Wave 6: Caster(X) — automated by the spellcasting subsystem (AiSpell +
    # the spells_mechanics_<system>.json maps emitted by spells_mechanics_export.py).
    "Caster": "Caster",
    # Wave 7 (2026-07-22): Retaliate(X) — official text "When this model takes wounds in melee,
    # the attacker takes X hits per wound taken." Reactive melee damage, resolved through the
    # shared save batch after each strike phase.
    "Retaliate": "Retaliate",
    # Wave 7: Re-Deployment — official text "After all other units are deployed ... you may
    # remove up to two friendly units from the table and deploy them again." Solo automation:
    # at the game-start transition the AI re-places up to two carriers with CURRENT knowledge.
    "Re-Deployment": "Re-Deployment",
    # Wave 7: Strafing (weapon rule) — move-through attack, weapon excluded from normal volleys;
    # profile flag parsed from the weapon's own specialRules (AiShooting), trigger in main.
    "Strafing": "Strafing",
    # AI plausibility wave 1: Aircraft (system-scoped below — GF only).
    "Aircraft": "Aircraft",
}

# Primitives that only exist in SOME systems' books: the bridging table above is
# name-keyed across systems, but a rule name in the shared Army Forge common set can
# be absent from a system's printed rulebook. Only the listed systems get the
# primitive; everywhere else the entry stays unautomated (primitive null), so the
# runtime gate (RulesRegistry.unit_rule_active) never fires cross-system.
SYSTEM_SCOPED_PRIMITIVES = {
    # Verified against the v3.5.1 Advanced Rules PDFs: the Aircraft special rule is
    # printed in GF only (no hit in AoF / AoFS / AoFR / GFF v3.5.1).
    "Aircraft": {"gf"},
}

# Rules the solo layer models although NO army-book lists them as a book rule:
# game-state tokens ("Fatigue" is a condition, not a book entry) and rules only
# granted by items ("Medical Training"). Kept so the derived modeled set stays
# a superset of the runtime vocabulary.
ENGINE_MODELED_TOKENS = ["Fatigue", "Medical Training",
                         # Coverage wave: item-granted WEAPONS that surface as rule tokens in
                         # bundled lists (they import as weapons; no separate rule mechanic).
                         "Drone Laser Gun", "Bash"]
ENGINE_DECISION_TOKENS = []

# Wave-5 primitives that steer decisions/EV (all of them do: hold overlay,
# movement bonus, morale-risk EV, targeting EV, profile choice).
WAVE5_DECISION_TOKENS = sorted(set(WAVE5_PRIMITIVES.values()))


def default_registry_path() -> str:
    # Never a hardcoded user directory — resolved from $HOME at runtime.
    return os.path.join(os.path.expanduser("~"), "openTTS-rules", "rules")


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def params_for(system: str, name: str, primitive: str, mech_params: dict | None = None) -> dict:
    override = SYSTEM_PARAM_OVERRIDES.get((system, name))
    if override is not None:
        return dict(override)
    # Coverage wave (2026-07-23): a registry entry's OWN mechanic params take precedence — the
    # alias families (Plaguebound -> Regeneration at 6+, Lustbound -> Royal Legion 4\"/2\", ...)
    # carry per-rule numbers the primitive defaults must not overwrite.
    if mech_params:
        return dict(mech_params)
    return dict(PRIMITIVE_PARAMS.get(primitive, {}))


def entry_for(system: str, rule: dict, book_version: str) -> dict:
    """One text-free mechanics entry for a registry rule."""
    name = rule["name"]
    mech = rule.get("mechanic") or {}
    primitive = mech.get("primitive") or WAVE5_PRIMITIVES.get(name)
    # Coverage wave: a "planned" entry documents the intended mechanic but has NO resolver yet —
    # it must NOT emit as automated (the manual notice stays visible until the resolver ships).
    if rule.get("status") == "planned":
        primitive = None
    allowed_systems = SYSTEM_SCOPED_PRIMITIVES.get(name)
    if allowed_systems is not None and system not in allowed_systems:
        primitive = None
    out = {
        "primitive": primitive,
        "rated": bool(rule.get("rated", False)),
        "book_version": book_version,
    }
    if primitive:
        params = params_for(system, name, primitive, mech.get("params"))
        if params:
            out["params"] = params
    return out


def hygiene_check(system_map: dict) -> None:
    """Refuse to emit anything that smells like copied rule text."""
    def check_entry(name: str, entry: dict) -> None:
        extra = set(entry.keys()) - ALLOWED_ENTRY_KEYS
        if extra:
            raise SystemExit("HYGIENE: entry %r has forbidden keys %s" % (name, sorted(extra)))
        for key, value in (entry.get("params") or {}).items():
            if isinstance(value, str) and (len(value) > MAX_PARAM_STRING or ". " in value):
                raise SystemExit("HYGIENE: param %s of %r looks like text: %r" % (key, name, value))

    for name, entry in system_map["common"].items():
        check_entry(name, entry)
    for faction, rules in system_map["factions"].items():
        for name, entry in rules.items():
            check_entry("%s/%s" % (faction, name), entry)
    blob = json.dumps(system_map, ensure_ascii=False)
    for needle in FORBIDDEN_SOURCE_KEYS:
        if '"%s"' % needle in blob:
            raise SystemExit("HYGIENE: forbidden key %r leaked into the output" % needle)


def build_system_map(registry: str, system: str) -> dict:
    sys_dir = os.path.join(registry, system)
    core_files = sorted(glob.glob(os.path.join(sys_dir, "core_*.json")))
    faction_files = sorted(
        f for f in glob.glob(os.path.join(sys_dir, "*.json")) if f not in core_files
    )
    if not core_files or not faction_files:
        raise SystemExit("registry incomplete for system %r under %s" % (system, sys_dir))

    common: dict = {}
    core_version = ""
    core_keyword_names: set = set()
    for cf in core_files:
        core = load_json(cf)
        core_version = str(core.get("version", ""))
        for rule in core.get("rules", []):
            common[rule["name"]] = entry_for(system, rule, core_version)
            # Coverage wave: keyword/grant statuses in the CORE file emit as covered too.
            if rule.get("status") in ("keyword", "aura-grant"):
                core_keyword_names.add(rule["name"])

    factions: dict = {}
    modeled: set = set(core_keyword_names)
    decision: set = set()
    for ff in faction_files:
        book = load_json(ff)
        slug = book.get("faction", os.path.splitext(os.path.basename(ff))[0])
        book_version = str(book.get("book_version", ""))
        fmap: dict = {}
        for rule in book.get("rules", []):
            entry = entry_for(system, rule, book_version)
            # Coverage wave: KEYWORD rules (army-building only, no table mechanic) and pure
            # AURA-GRANT carriers (the import's grant expansion handles them) are COVERED — the
            # runtime's not-automated notice must not flag them as manual work.
            if rule.get("status") in ("keyword", "aura-grant"):
                modeled.add(rule["name"])
            if entry["primitive"]:
                # BOTH the primitive and the rule NAME: the runtime's not-automated notice matches
                # unit rule names against this set, so an aliased rule (Ferocious -> Surge) must
                # appear under its own name too (sim-wave finding: the notice still printed).
                modeled.add(entry["primitive"])
                modeled.add(rule["name"])
                if rule.get("decision_relevant") or entry["primitive"] in WAVE5_DECISION_TOKENS:
                    decision.add(entry["primitive"])
            if rule.get("is_core"):
                # Core rules resolve via the common fallback — no duplicate.
                # But a core rule missing from the core file still needs a slot.
                if rule["name"] not in common:
                    common[rule["name"]] = entry_for(system, rule, core_version or book_version)
                # Coverage wave: keyword/grant status of a core-listed rule must still emit as
                # covered (the faction-loop clause above never reaches core-only entries).
                if rule.get("status") in ("keyword", "aura-grant"):
                    modeled.add(rule["name"])
                continue
            fmap[rule["name"]] = entry
        if fmap:
            factions[slug] = fmap

    for name, entry in common.items():
        if entry["primitive"]:
            modeled.add(entry["primitive"])
            modeled.add(name)
    for name, entry in common.items():
        if entry["primitive"] in WAVE5_DECISION_TOKENS:
            decision.add(entry["primitive"])

    system_map = {
        "_meta": {
            "system": system,
            "core_version": core_version,
            "faction_books": len(faction_files),
            "generator": "tools/rules_mechanics_export.py",
            "contract": "lookup (system, faction, name) -> fallback (system, common, name); never name-only across systems",
            "content": "derived mechanics only - rule names + our own primitive/param encoding; no rule texts",
        },
        "modeled": sorted(modeled | set(ENGINE_MODELED_TOKENS)),
        "decision": sorted(decision | set(ENGINE_DECISION_TOKENS)),
        "common": dict(sorted(common.items())),
        "factions": dict(sorted((k, dict(sorted(v.items()))) for k, v in factions.items())),
    }
    hygiene_check(system_map)
    return system_map


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default=default_registry_path(),
                        help="path to the local rules registry (default: ~/openTTS-rules/rules)")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "solo"),
                        help="output directory (default: <repo>/assets/solo)")
    parser.add_argument("--check", action="store_true",
                        help="verify the committed maps match the registry (no writes)")
    args = parser.parse_args()

    if not os.path.isdir(args.registry):
        print("registry not found: %s (this generator needs the maintainer's local registry)" % args.registry)
        return 2

    os.makedirs(args.out, exist_ok=True)
    stale = []
    for system in SYSTEMS:
        system_map = build_system_map(args.registry, system)
        out_path = os.path.join(args.out, "rules_mechanics_%s.json" % system)
        payload = json.dumps(system_map, indent=1, ensure_ascii=False, sort_keys=False) + "\n"
        if args.check:
            current = ""
            if os.path.exists(out_path):
                with open(out_path, "r", encoding="utf-8") as f:
                    current = f.read()
            if current != payload:
                stale.append(out_path)
            continue
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(payload)
        n_faction_rules = sum(len(v) for v in system_map["factions"].values())
        print("%s: common=%d faction_rules=%d (books=%d) modeled_tokens=%d decision_tokens=%d -> %s" % (
            system, len(system_map["common"]), n_faction_rules,
            system_map["_meta"]["faction_books"], len(system_map["modeled"]),
            len(system_map["decision"]), os.path.relpath(out_path)))

    if args.check:
        if stale:
            print("STALE mechanics maps (re-run tools/rules_mechanics_export.py):")
            for p in stale:
                print("  " + p)
            return 1
        print("mechanics maps are current")
    return 0


if __name__ == "__main__":
    sys.exit(main())

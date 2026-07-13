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
    "Counter": {"strikes_first": True, "impact_reduction_per_model": 1},
    "Fast": {"advance_mod": 2, "rush_mod": 4},
    "Slow": {"advance_mod": -2, "rush_mod": -4},
    "Battleborn": {"recover_target": 4},
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
    # --- Wave 6 (spellcasting) --- Caster(X) token economy, verified byte-identical
    # across all five systems in the official v3.5.1 rulebooks; held as per-system
    # DATA regardless, so a future skirmish errata stays a data change.
    "Caster": {"rating": "X", "token_cap": 6, "cast_target": 4, "aura_in": 18.0,
               "boost_per_token": 1},
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
    # Wave 6: Caster(X) — automated by the spellcasting subsystem (AiSpell +
    # the spells_mechanics_<system>.json maps emitted by spells_mechanics_export.py).
    "Caster": "Caster",
}

# Rules the solo layer models although NO army-book lists them as a book rule:
# game-state tokens ("Fatigue" is a condition, not a book entry) and rules only
# granted by items ("Medical Training"). Kept so the derived modeled set stays
# a superset of the runtime vocabulary.
ENGINE_MODELED_TOKENS = ["Fatigue", "Medical Training"]
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


def params_for(system: str, name: str, primitive: str) -> dict:
    override = SYSTEM_PARAM_OVERRIDES.get((system, name))
    if override is not None:
        return dict(override)
    return dict(PRIMITIVE_PARAMS.get(primitive, {}))


def entry_for(system: str, rule: dict, book_version: str) -> dict:
    """One text-free mechanics entry for a registry rule."""
    name = rule["name"]
    mech = rule.get("mechanic") or {}
    primitive = mech.get("primitive") or WAVE5_PRIMITIVES.get(name)
    out = {
        "primitive": primitive,
        "rated": bool(rule.get("rated", False)),
        "book_version": book_version,
    }
    if primitive:
        params = params_for(system, name, primitive)
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
    for cf in core_files:
        core = load_json(cf)
        core_version = str(core.get("version", ""))
        for rule in core.get("rules", []):
            common[rule["name"]] = entry_for(system, rule, core_version)

    factions: dict = {}
    modeled: set = set()
    decision: set = set()
    for ff in faction_files:
        book = load_json(ff)
        slug = book.get("faction", os.path.splitext(os.path.basename(ff))[0])
        book_version = str(book.get("book_version", ""))
        fmap: dict = {}
        for rule in book.get("rules", []):
            entry = entry_for(system, rule, book_version)
            if entry["primitive"]:
                modeled.add(entry["primitive"])
                if rule.get("decision_relevant") or entry["primitive"] in WAVE5_DECISION_TOKENS:
                    decision.add(entry["primitive"])
            if rule.get("is_core"):
                # Core rules resolve via the common fallback — no duplicate.
                # But a core rule missing from the core file still needs a slot.
                if rule["name"] not in common:
                    common[rule["name"]] = entry_for(system, rule, core_version or book_version)
                continue
            fmap[rule["name"]] = entry
        if fmap:
            factions[slug] = fmap

    for entry in common.values():
        if entry["primitive"]:
            modeled.add(entry["primitive"])
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

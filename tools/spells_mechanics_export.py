#!/usr/bin/env python3
"""Export DERIVED, text-free faction SPELL mechanics maps for the solo AI.

Sibling of tools/rules_mechanics_export.py, for the Caster(X) subsystem: reads
the maintainer's LOCAL rules registry (for the (system, faction, book_uid)
inventory) plus the registry sync tool's on-disk Army Forge cache (the fetched
army-book JSONs, which carry each faction's spell list per game system) and
emits one committed spell map per game system:

    assets/solo/spells_mechanics_<system>.json

The maps carry ONLY our own mechanic encoding — spell NAMES, thresholds,
numeric target/range parameters, weapon-rule tokens ("AP(1)", "Blast(3)") and
the primitive that automates each spell. **No official spell text is ever
copied into the output** (the effect prose is OPR's IP and stays local); a
hygiene guard below refuses to write otherwise.

SYSTEM SCOPING (the same HARD invariant as the rules maps): a faction's spell
list can DIVERGE between game systems — measured on the current cache, 77 of
82 books published for 2+ systems have parameter-divergent spell lists (same
names, different target counts / hits / ranges). Only the per-system effect
TEXT carries that divergence (the API's structured `generation` block is a
shared template), so this generator parses each system's own text through a
strict grammar at GENERATION time; anything the grammar cannot fully parse is
emitted as status "unmodeled" (name + threshold only — the AI then never
pretends to automate it).

Usage:
    python3 tools/spells_mechanics_export.py                 # default paths
    python3 tools/spells_mechanics_export.py --registry PATH --cache PATH
    python3 tools/spells_mechanics_export.py --check         # verify outputs
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

SYSTEMS = ["gf", "gff", "aof", "aofs", "aofr"]

# ---------------------------------------------------------------------------
# The strict effect-text grammar. Every OPR faction spell (1356 across the five
# systems at the time of writing) opens with a "Pick ..." assignment clause;
# the effect clause then falls into one of a small set of shapes. The grammar
# is deliberately narrow: a spell that does not match COMPLETELY becomes
# "unmodeled" (conservative fallback), never a guess.
# ---------------------------------------------------------------------------

ASSIGN_RE = re.compile(
    r'^Pick\s+(one|up to two|up to three|up to four|up to six)\s+(friendly|enemy)\s+'
    r'(unit|units|model|models)\s+within\s+(\d+)[”"]', re.IGNORECASE)

DAMAGE_RE = re.compile(r'\btakes?\s+(\d+)\s+hits?\b(?:\s+with\s+([^.]+?))?(?:\s+each)?(?:\.|$)')

# "which gets/get <Rule Name> (in melee|when shooting|when attacking|when
# charging)? (against)? once (next time the effect would apply)"
GRANT_RE = re.compile(
    r'\bwhich\s+(?:friendly\s+units\s+)?gets?\s+'
    r'([A-Z][A-Za-z0-9\'’ &-]*?)'
    r'(?:\s+(in melee|when shooting|when attacking|when charging))?'
    r'(?:\s+against)?\s+once\b')

MODIFIER_RE = re.compile(
    r'\bwhich\s+(?:friendly\s+units\s+)?gets?\s+'
    r'([+-]\d+)\s+to\s+(hit|defense|morale test|casting)\s+rolls\b'
    r'(?:\s+(in melee|when shooting|when attacking|when charging))?'
    r'(?:\s+against)?\s+once\b')

RANGE_MOD_RE = re.compile(
    r'\bwhich\s+(?:friendly\s+units\s+)?gets?\s+([+-]\d+)[”"]\s+range\s+when\s+shooting\b')

SPEED_MOD_RE = re.compile(
    r'\bwhich\s+moves?\s+([+-]\d+)[”"]\s+when\s+using\s+Advance\s+actions\s+'
    r'and\s+([+-]\d+)[”"]\s+when\s+using\s+Rush/Charge\s+actions\b')

COUNTS = {"one": 1, "up to two": 2, "up to three": 3, "up to four": 4, "up to six": 6}
SCOPES = {"in melee": "melee", "when shooting": "shooting",
          "when attacking": "attacking", "when charging": "charging"}
MOD_KEYS = {"hit": "hit_mod", "defense": "def_mod",
            "morale test": "morale_mod", "casting": "casting_mod"}

# Weapon-rule token: "AP(1)", "Blast(3)", "Deadly(3)", "Bane", "Shred", ... —
# names + optional numeric rating only (our own token vocabulary; the rules
# maps commit the same category of names).
WEAPON_RULE_RE = re.compile(r"^[A-Z][A-Za-z'’ -]{0,30}(\(\+?\d+\))?$")

# Grant names the solo EV layer can actually value (profile facets exist for
# them). Everything else is still castable data, but its EV contribution is 0.
EV_GRANTS = {"Bane", "Bane in Melee", "Bane when Shooting", "Shred"}

# --- hygiene ---------------------------------------------------------------

ALLOWED_SPELL_KEYS = {"name", "threshold", "range_in", "target", "effect", "mechanic", "status"}
ALLOWED_TARGET_KEYS = {"side", "count", "kind"}
ALLOWED_EFFECT_KEYS = {"kind", "hits", "weapon_rules", "grants_rule", "scope",
                       "duration", "modifier", "beneficiary"}
ALLOWED_MODIFIER_KEYS = {"hit_mod", "def_mod", "morale_mod", "casting_mod",
                         "advance_in", "rush_in", "range_in"}
ALLOWED_MECHANIC_KEYS = {"primitive", "params"}
FORBIDDEN_SOURCE_KEYS = {"official_effect", "effect_text", "description", "citation",
                         "text", "note", "reason", "effectSkirmish", "_license", "_note"}
MAX_NAME = 40          # spell / rule NAMES (not prose)
MAX_PARAM_STRING = 24  # short slugs only


def default_registry_path() -> str:
    # Never a hardcoded user directory — resolved from $HOME at runtime.
    return os.path.join(os.path.expanduser("~"), "openTTS-rules", "rules")


def default_cache_path(registry: str) -> str:
    # The rules_registry_sync.py fetch cache sits next to the registry.
    return os.path.normpath(os.path.join(registry, os.pardir, "tools", ".rules_cache"))


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_weapon_rules(clause: str) -> list | None:
    """'AP(1) and Destructive' / 'AP(2), Bane and Shred' -> token list, or
    None when any fragment is not a clean weapon-rule token."""
    out = []
    for frag in re.split(r",\s*|\s+and\s+", clause.strip()):
        frag = frag.strip().rstrip(".")
        if not frag:
            continue
        if not WEAPON_RULE_RE.match(frag):
            return None
        out.append(frag)
    return out


def classify(text: str) -> dict | None:
    """Parse ONE spell effect text through the strict grammar. Returns
    {range_in, target{side,count,kind}, effect{...}} or None (unmodeled)."""
    m = ASSIGN_RE.match(text.strip())
    if not m:
        return None
    count = COUNTS[m.group(1).lower()]
    side = m.group(2).lower()
    kind_word = m.group(3).lower().rstrip("s")
    range_in = int(m.group(4))
    target = {"side": side, "count": count, "kind": kind_word}
    rest = text[m.end():]

    dm = DAMAGE_RE.search(rest)
    if dm:
        rules: list = []
        if dm.group(2):
            parsed = parse_weapon_rules(dm.group(2))
            if parsed is None:
                return None  # a facet we cannot tokenise -> unmodeled
            rules = parsed
        effect = {"kind": "damage", "hits": int(dm.group(1)), "weapon_rules": rules}
        return {"range_in": range_in, "target": target, "effect": effect}

    mm = MODIFIER_RE.search(rest)
    if mm:
        modifier = {MOD_KEYS[mm.group(2)]: int(mm.group(1))}
        effect = {"kind": ("buff" if side == "friendly" else "debuff"),
                  "modifier": modifier, "duration": "once"}
        if mm.group(3):
            effect["scope"] = SCOPES[mm.group(3)]
        if side == "enemy":
            # "friendly units get +1 ... against" = our attackers benefit;
            # plain "which gets -1 ..." = the enemy itself is degraded.
            effect["beneficiary"] = "attackers" if "friendly units" in mm.group(0) else "target"
        return {"range_in": range_in, "target": target, "effect": effect}

    rm = RANGE_MOD_RE.search(rest)
    if rm:
        effect = {"kind": ("buff" if side == "friendly" else "debuff"),
                  "modifier": {"range_in": int(rm.group(1))},
                  "scope": "shooting", "duration": "once"}
        if side == "enemy":
            effect["beneficiary"] = "attackers"
        return {"range_in": range_in, "target": target, "effect": effect}

    sm = SPEED_MOD_RE.search(rest)
    if sm:
        effect = {"kind": ("buff" if side == "friendly" else "debuff"),
                  "modifier": {"advance_in": int(sm.group(1)), "rush_in": int(sm.group(2))},
                  "duration": "once"}
        return {"range_in": range_in, "target": target, "effect": effect}

    gm = GRANT_RE.search(rest)
    if gm:
        rule_name = gm.group(1).strip()
        if len(rule_name) > MAX_NAME:
            return None
        effect = {"kind": ("buff" if side == "friendly" else "debuff"),
                  "grants_rule": rule_name, "duration": "once"}
        if gm.group(2):
            effect["scope"] = SCOPES[gm.group(2)]
        if side == "enemy":
            effect["beneficiary"] = "attackers"
        return {"range_in": range_in, "target": target, "effect": effect}

    # The assignment clause parsed but the effect clause matched no shape
    # (terrain state, forced morale, ...): the AI can still cast it LEGALLY
    # (side/count/range are known) and announce it — the effect stays manual.
    return {"range_in": range_in, "target": target, "effect": {"kind": "utility"}}


def mechanic_for(effect: dict) -> dict | None:
    """Our automating primitive for a parsed effect (None -> the spell is data
    the AI can SEE but not value/resolve -> unmodeled)."""
    if effect["kind"] == "damage":
        return {"primitive": "spell_damage_ev",
                "params": {"hits": effect["hits"]}}
    modifier = effect.get("modifier")
    if modifier:
        # casting/morale/range/speed modifiers carry no EV in wave 5 — they
        # stay "modeled" only where the EV chain can price them (hit/def).
        if "hit_mod" in modifier or "def_mod" in modifier:
            return {"primitive": "spell_modifier_delta", "params": dict(modifier)}
        return None
    grant = effect.get("grants_rule", "")
    if grant in EV_GRANTS:
        return {"primitive": "spell_modifier_delta",
                "params": {"grants_rule": grant}}
    return None


def spell_entry(sp: dict) -> dict:
    """One text-free spell entry. Status ladder:
      modeled   — the mechanics fully price/resolve it (damage; hit/def
                  modifiers; the EV-visible rule grants),
      castable  — target side/count/range parsed, so the AI can cast it
                  LEGALLY per the official procedure and announce it, but the
                  effect is applied manually (EV contribution 0),
      unmodeled — the grammar could not even parse the assignment clause; the
                  AI never selects it."""
    name = str(sp.get("name", "")).strip()
    entry = {"name": name, "threshold": int(sp.get("threshold", 0))}
    parsed = classify(str(sp.get("effect", "")))
    if parsed is None:
        entry["status"] = "unmodeled"
        return entry
    entry["range_in"] = parsed["range_in"]
    entry["target"] = parsed["target"]
    entry["effect"] = parsed["effect"]
    mech = mechanic_for(parsed["effect"])
    if mech is None:
        entry["status"] = "castable"
    else:
        entry["mechanic"] = mech
        entry["status"] = "modeled"
    return entry


# --- hygiene guard ----------------------------------------------------------

def _check_string(context: str, value: str, limit: int) -> None:
    if len(value) > limit or ". " in value or value.endswith("."):
        raise SystemExit("HYGIENE: %s looks like prose: %r" % (context, value))


def hygiene_check(system_map: dict) -> None:
    """Refuse to emit anything that smells like copied spell text."""
    for faction, fmap in system_map["factions"].items():
        for sp in fmap["spells"]:
            ctx = "%s/%s" % (faction, sp.get("name", "?"))
            extra = set(sp.keys()) - ALLOWED_SPELL_KEYS
            if extra:
                raise SystemExit("HYGIENE: spell %s has forbidden keys %s" % (ctx, sorted(extra)))
            _check_string(ctx + ".name", str(sp.get("name", "")), MAX_NAME)
            if set((sp.get("target") or {}).keys()) - ALLOWED_TARGET_KEYS:
                raise SystemExit("HYGIENE: %s target keys" % ctx)
            effect = sp.get("effect") or {}
            if set(effect.keys()) - ALLOWED_EFFECT_KEYS:
                raise SystemExit("HYGIENE: %s effect keys %s" % (ctx, sorted(set(effect.keys()) - ALLOWED_EFFECT_KEYS)))
            if set((effect.get("modifier") or {}).keys()) - ALLOWED_MODIFIER_KEYS:
                raise SystemExit("HYGIENE: %s modifier keys" % ctx)
            for wr in effect.get("weapon_rules", []):
                if not WEAPON_RULE_RE.match(str(wr)):
                    raise SystemExit("HYGIENE: %s weapon rule %r" % (ctx, wr))
            _check_string(ctx + ".grants_rule", str(effect.get("grants_rule", "")), MAX_NAME)
            for key in ("kind", "scope", "duration", "beneficiary"):
                _check_string(ctx + "." + key, str(effect.get(key, "")), MAX_PARAM_STRING)
            mech = sp.get("mechanic")
            if mech is not None:
                if set(mech.keys()) - ALLOWED_MECHANIC_KEYS:
                    raise SystemExit("HYGIENE: %s mechanic keys" % ctx)
                for k, v in (mech.get("params") or {}).items():
                    if isinstance(v, str):
                        _check_string("%s.params.%s" % (ctx, k), v, MAX_NAME)
    blob = json.dumps(system_map, ensure_ascii=False)
    for needle in FORBIDDEN_SOURCE_KEYS:
        if '"%s"' % needle in blob:
            raise SystemExit("HYGIENE: forbidden key %r leaked into the output" % needle)


# --- per-system build --------------------------------------------------------

def build_system_map(registry: str, cache: str, system: str) -> tuple[dict, dict]:
    sys_dir = os.path.join(registry, system)
    faction_files = sorted(
        f for f in glob.glob(os.path.join(sys_dir, "*.json"))
        if not os.path.basename(f).startswith("core_"))
    if not faction_files:
        raise SystemExit("registry incomplete for system %r under %s" % (system, sys_dir))

    factions: dict = {}
    stats = {"factions": 0, "spells": 0, "modeled": 0, "castable": 0, "unmodeled": 0, "missing_books": 0}
    for ff in faction_files:
        reg = load_json(ff)
        slug = reg.get("faction", os.path.splitext(os.path.basename(ff))[0])
        uid = str(reg.get("book_uid", ""))
        gs_id = int(reg.get("game_system_id", 0))
        cache_file = os.path.join(cache, "book-%s-gs%d.json" % (uid, gs_id))
        if not uid or not os.path.exists(cache_file):
            stats["missing_books"] += 1
            continue
        book = load_json(cache_file)
        spells = book.get("spells") or []
        if not spells:
            continue
        entries = []
        for sp in spells:  # BOOK ORDER — the official D3+X index cycles this list
            entry = spell_entry(sp)
            entries.append(entry)
            stats["spells"] += 1
            stats[entry["status"]] += 1
        factions[slug] = {"book_uid": uid,
                          "book_version": str(reg.get("book_version", "")),
                          "spells": entries}
        stats["factions"] += 1

    system_map = {
        "_meta": {
            "system": system,
            "generator": "tools/spells_mechanics_export.py",
            "contract": "spells resolve by (system, faction); lists are BOOK-ORDERED (the official solo D3+X pick indexes them); never share lists across systems",
            "content": "derived mechanics only - spell names, thresholds and our own numeric target/effect encoding; no spell texts",
        },
        "factions": dict(sorted(factions.items())),
    }
    hygiene_check(system_map)
    return system_map, stats


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default=default_registry_path(),
                        help="path to the local rules registry (default: ~/openTTS-rules/rules)")
    parser.add_argument("--cache", default=None,
                        help="path to the registry sync tool's army-book fetch cache "
                             "(default: <registry>/../tools/.rules_cache)")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "solo"),
                        help="output directory (default: <repo>/assets/solo)")
    parser.add_argument("--check", action="store_true",
                        help="verify the committed maps match the sources (no writes)")
    args = parser.parse_args()
    cache = args.cache or default_cache_path(args.registry)

    if not os.path.isdir(args.registry):
        print("registry not found: %s (this generator needs the maintainer's local registry)" % args.registry)
        return 2
    if not os.path.isdir(cache):
        print("army-book cache not found: %s (run the registry sync tool first)" % cache)
        return 2

    os.makedirs(args.out, exist_ok=True)
    stale = []
    for system in SYSTEMS:
        system_map, stats = build_system_map(args.registry, cache, system)
        out_path = os.path.join(args.out, "spells_mechanics_%s.json" % system)
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
        print("%s: factions=%d spells=%d modeled=%d castable=%d unmodeled=%d missing_books=%d -> %s" % (
            system, stats["factions"], stats["spells"], stats["modeled"], stats["castable"],
            stats["unmodeled"], stats["missing_books"], os.path.relpath(out_path)))

    if args.check:
        if stale:
            print("STALE spell maps (re-run tools/spells_mechanics_export.py):")
            for p in stale:
                print("  " + p)
            return 1
        print("spell maps are current")
    return 0


if __name__ == "__main__":
    sys.exit(main())

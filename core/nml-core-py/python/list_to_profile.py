"""Army-Forge list -> BattleSim unit profile, in pure Python (NML-1073 M3-3).

Ports three GDScript functions field for field:

  tools/core_selfplay.gd:_units_from_list / _append_selection (the
      Godot-free army loader every M3 corpus is built from — combined-unit
      folding, upgrade-label rule grants, per-model Tough/wounds_max)

  scripts/solo/battle_sim.gd:_unit_profile (the STATIC per-unit profile dict
      AiActRecorder stamps once per game onto the act corpus header's
      "profiles" line)

  scripts/opr_api_client.gd:_rule_to_string (NML-1073 M3-3b: a weapon-level
      specialRules entry, e.g. {"name": "AP", "rating": 1}, carries no
      "label" — only "rating" — so core_selfplay.gd's plain label/name
      fallback used to drop it to a bare "AP", zeroing AP/Blast/Deadly for
      every weapon in the trainer. core_selfplay.gd now calls this shared,
      arena-tested formatter for weapon rules specifically; unit-level
      "rules" and upgrade-label grants keep the plain label/name fallback,
      since those dicts already carry a pre-formatted "label" — see
      _rule_label below)

This reproduces exactly what THAT loader produces today, not the full
Army-Forge import path (opr_api_client.gd), which resolves base-size
recommendations, free-text rule descriptions and live hero attachment that
core_selfplay's lightweight loader never touches. Three consequences, all
confirmed against the M3-0 oracle corpus (8 games, 101 units, 0 mismatches
before this port existed to gate on the corpus for real):

  * base_radius WAS always 32 mm (0.016 m). NML-1097 reads the list's own
    "bases" field through opr_api_client.gd's parser instead: the ARENA's act
    headers, recorded off these very lists, carry the real radii, and 131 of
    qbf_ref's 148 roster units are not 32 mm. This is the first field where
    this loader deliberately follows the TABLE and no longer reproduces
    tools/core_selfplay.gd, which still has the bug — see tools/loader_gate.py.
    NML-1097b ports `_apply_tough_base_fallback` (opr_api_client.gd:609-633)
    too: the keyword+Tough ladder that sizes a unit Army Forge gave no usable
    base for (`bases:{round:"none"}`, common for vehicles) — see `_base_of`.
  * item_grants was ALWAYS empty, and with it every rule an item grants was
    missing from special_rules. NML-1098 ports the table's own loadout pass
    (opr_api_client.gd:_parse_tts_unit :738-813): a non-weapon loadout entry
    puts its NAME on the rule line and its content's rules under item_grants,
    which is what RulesRegistry.unit_rules_of_primitive reads. This is the
    second field where this loader follows the TABLE rather than
    tools/core_selfplay.gd, which still parses rule names out of upgrade LABEL
    text and never sees the item name — see tools/loader_gate.py.
    NOT ported, because it is provably inert here: `_apply_selected_upgrade_rules`
    (:826-869), the `option.gains` pass. All 6741 selectedUpgrades across both
    AI list pools carry an EMPTY `gains`, so it contributes nothing; the label
    text those lists do carry is not a rule source on the table.
    An item's rules then feed the AURA pass (opr_army_manager.gd:_expand_auras):
    "Furious Aura" on a hero grants "Furious" to its whole unit, which is the
    single biggest rule source these lists have. attached_hero_rules stays the
    caller's (selfplay.play_game) job (NML-1081) and picks all of this up.
  * move_bands runs the NAME-based Fast/Slow/Rapid Rush/Quick/Rapid Advance
    fallback AND, since NML-1108, movement_range_controller.gd's REGISTRY
    pass (:164-188): a rule whose mechanics entry resolves to one of those
    primitives without sharing the name — Highborn/Scurry/Agile -> Quick,
    Royal Legion's charge half, an "X Aura" -> Fast — applies its own params
    to whichever band the name pass left uncovered. The map is read from the
    very asset the table reads (assets/solo/rules_mechanics_<system>.json),
    keyed (game_system, faction_folder, name) like RulesRegistry.lookup.
    Still NOT ported: the DESCRIPTION pass, which needs `rule_descriptions`
    — free rule text the arena fetches from the army-book API and the
    bundled AI lists do not carry. Where a book states a movement modifier
    ONLY in prose and the registry entry does not (yet) encode it as
    advance_mod/rush_mod, the trainer cannot see it — see tools/loader_gate.py.
    NML-1121 closed this gap for AoF Ghostly Undead / Shadow Stalkers'
    "Ethereal" (advance_mod/rush_mod -6/-6, primitive "Teleport"): the data
    now carries what the prose said, so the registry pass alone reaches it.

Two more fields — shooting_range_bonus and max_activation_advance_bonus_in —
are stamped here too. Current main's `_unit_profile` (battle_sim.gd:1573) no
longer carries them (M2-5b moved them into the per-ACTIVATION dynamic
profile, unit_profile_dyn); the 4 pre-M2-5b games in the M3-0 oracle corpus
were recorded before that split and still carry them in their header. Both
read SoloController.shooting_range_bonus / max_activation_advance_bonus_in,
which fire only for RulesRegistry-driven rules (Royal Legion, Bounding,
the Teleport family) — absent from all 8 oracle games, which is why they
stayed hardcoded 0/0.0 until NML-1108. They are now computed off the same
registry map, so an AoF list's 27 Royal Legion units read 4 and its 5
Bounding units read 4.0 instead of nothing.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any

# separation_checker.gd / opr_army_manager.gd constants (base-radius fallback)
DEFAULT_BASE_MM = 32
MM_TO_METERS = 0.001
# opr_api_client.gd:650-657 — every parsed base dimension is clamped here.
BASE_MM_MIN = 20
BASE_MM_MAX = 150

#: NML-1097 — replay switch, NOT a game knob. `tools/core_selfplay.gd` reads no
#: base at all, so every model in a corpus THAT harness recorded sits on the
#: 32 mm fallback with no Tough scaling. The seed-for-seed gates against those
#: corpora (test_selfplay / test_sidecars) set this so they keep measuring the
#: search loop instead of this fix; `tools/loader_gate.py` measures this fix.
LEGACY_CORE_SELFPLAY = False

# movement_range_controller.gd constants (name-based move-band fallback)
OPR_ADVANCE_INCHES = 6
OPR_RUSH_CHARGE_INCHES = 12
FAST_ADVANCE_BONUS = 2
FAST_RUSH_BONUS = 4
RAPID_RUSH_BONUS = 6
QUICK_BONUS = 2
RAPID_ADVANCE_BONUS = 4

# rules_registry.gd:SYSTEMS / DEFAULT_SYSTEM / MAP_PATH_TEMPLATE — the mechanics
# maps the TABLE reads, loaded straight out of the checkout they are committed in.
REGISTRY_SYSTEMS = ("gf", "gff", "aof", "aofs", "aofr")
REGISTRY_DEFAULT_SYSTEM = "gf"
REGISTRY_DIR = Path(__file__).resolve().parents[3] / "assets" / "solo"
_REGISTRY_CACHE: dict[str, dict] = {}

#: movement_range_controller.gd:179 — the ONLY primitives the move-band registry
#: pass honours. A rule aliased to anything else (Wild Veil -> Ranged Shrouding)
#: leaves the bands alone, on the table and here. NML-1121: "Teleport" joined this
#: list for Ethereal's own advance_mod/rush_mod (-6/-6); the real "Teleport" rule
#: carries no such keys (its advance_bonus_in/rush_bonus_in are read elsewhere, by
#: _max_activation_advance_bonus_in below), so it is unaffected by riding this pass.
MOVE_PRIMITIVES = ("Fast", "Slow", "Quick", "Rapid Advance", "Rapid Rush", "Royal Legion", "Teleport")
#: solo_controller.gd:5435 — the byte-identical fallback when the map is absent.
ROYAL_LEGION_RANGE_BONUS_IN = 4
#: solo_controller.gd:5563 — the Teleport family's default placement distance.
TELEPORT_ADVANCE_BONUS_IN = 3.0


def _rule_label(r: dict) -> str:
    """A rule/specialRule entry's display name — battle_sim / core_selfplay
    read "label" first, "name" as the fallback, empty string last. Used for
    UNIT-level "rules" and upgrade-label grants only; those dicts already
    carry a pre-formatted "label" (e.g. Tough's is "Tough(3)"). Weapon-level
    specialRules entries go through _rule_to_string below instead — see its
    docstring for why."""
    return str(r.get("label", r.get("name", "")))


def _format_rating(value: Any) -> str:
    """opr_api_client.gd:_format_rating — strips a whole float's decimal
    point (1.0 -> "1"); any other type (int, str, a fractional float, ...)
    formats via plain str()."""
    if isinstance(value, float):
        if value == int(value):
            return str(int(value))
        return str(value)
    return str(value)


def _rule_to_string(rule: dict) -> str:
    """opr_api_client.gd:_rule_to_string — the single source of truth (also
    used by the arena import path) for turning an Army-Forge rule dict into
    its display string. A weapon-level specialRules entry (e.g.
    {"name": "AP", "rating": 1}) carries no "label", only "rating" — the
    plain label/name fallback (_rule_label above) silently dropped it to a
    bare "AP", zeroing every rated weapon rule (NML-1073 M3-3b). Ported
    field for field: a present "rating" always wins (formatted via
    _format_rating, so a string rating like "+3" passes through as-is, e.g.
    "Deadly(+3)"); absent a rating, a "label" already shaped "Name(X)" is
    kept whole; otherwise it's the bare name, else the bare label."""
    rule_name = str(rule.get("name", ""))
    rating = rule.get("rating", None)
    if rating is not None and str(rating) != "":
        return "%s(%s)" % (rule_name, _format_rating(rating))
    label = str(rule.get("label", ""))
    if rule_name and label.startswith(rule_name + "(") and label.endswith(")"):
        return label
    return rule_name if rule_name else label


#: NML-1098 — replay switch, NOT a game knob. True makes this loader reproduce
#: `tools/core_selfplay.gd` again: rule names parsed out of upgrade LABEL text,
#: no loadout pass, no item names, no item grants and no aura expansion. Every
#: corpus THAT harness recorded was played under it, so the seed-for-seed gates
#: against those corpora (test_selfplay / test_sidecars) set it and keep
#: measuring the search loop; `tools/loader_gate.py` measures this fix.
LEGACY_CORE_SELFPLAY = False


def _is_weapon_profile_token(token: str) -> bool:
    """core_selfplay.gd:_is_weapon_profile_token — a weapon PROFILE token
    always declares attacks ("A2") and/or a range ("24\"" / "Range...")."""
    return re.search(r'^A\d+$|\d"$|^Range\b', token) is not None


def _rules_in_upgrade_label(label: str) -> list[str]:
    """core_selfplay.gd:_rules_in_upgrade_label — the rule names an upgrade
    OPTION's label grants, e.g. "Archivist (Caster(2))" -> ["Caster(2)"].
    Split at TOP-LEVEL commas so "Caster(1)"'s own parens stay intact; a
    weapon-swap label (any split token looks like a weapon profile) grants
    nothing here. LEGACY ONLY: the table reads the resolved `loadout` and
    `option.gains` instead, and never the label text."""
    open_i = label.find("(")
    close_i = label.rfind(")")
    if open_i < 0 or close_i <= open_i:
        return []
    inner = label[open_i + 1 : close_i]
    out: list[str] = []
    depth = 0
    start = 0
    for i, c in enumerate(inner):
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == "," and depth == 0:
            piece = inner[start:i].strip()
            if piece:
                out.append(piece)
            start = i + 1
    last = inner[start:].strip()
    if last:
        out.append(last)
    for token in out:
        if _is_weapon_profile_token(token):
            return []
    return out


def _item_count(value: Any, default: int) -> int:
    """`_safe_int(item["count"], unit.size)` (opr_api_client.gd:260) for the
    numeric shape a loadout count actually has: None or anything unparsable
    answers the unit size, an int passes through, a float truncates.
    `_safe_int`'s "60x35" branch is base-size only and unreachable from here."""
    if value is None or isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value):
        return int(value)
    return default


def _granted_rules_of_item(item: dict[str, Any]) -> list[str]:
    """opr_api_client.gd:_granted_rules_of_item — the rules a non-weapon
    loadout entry grants, from its "specialRules" then its "content", deduped
    in that order. An ArmyBookWeapon inside the content is a weapon profile and
    never a rule (a Weapon Team's autocannon), so it is skipped here."""
    out: list[str] = []
    raw: list = []
    for key in ("specialRules", "content"):
        value = item.get(key)
        if isinstance(value, list):
            raw.extend(value)
    for entry in raw:
        if isinstance(entry, str):
            granted = entry
        elif isinstance(entry, dict):
            if entry.get("type", "") == "ArmyBookWeapon":
                continue
            granted = _rule_to_string(entry)
        else:
            continue
        if granted and granted not in out:
            out.append(granted)
    return out


def _granted_weapon_names_of_item(item: dict[str, Any]) -> list[str]:
    """opr_api_client.gd:_granted_weapons_of_item — the names of the WEAPONS an
    item's content carries. The table appends them to the unit's weapons and
    erases each from the rule line ("they're weapons now, not profile-less
    rules", :775-781); this loader takes weapons off the list's own `weapons`
    field, so only the erase matters here."""
    out: list[str] = []
    content = item.get("content")
    if not isinstance(content, list):
        return out
    for entry in content:
        if not isinstance(entry, dict) or entry.get("type", "") != "ArmyBookWeapon":
            continue
        if int(entry.get("attacks") or 0) > 0:
            out.append(str(entry.get("name", entry.get("label", "Unknown"))).strip())
    return out


def _selection_rules(ud: dict[str, Any]) -> tuple[list[str], dict[str, list[str]]]:
    """opr_api_client.gd:_parse_tts_unit's rule assembly for ONE selection ->
    `(special_rules, item_grants)`, in the table's own order: the "rules" field
    first, then each non-weapon LOADOUT entry — its own name onto the rule line,
    then the rules it grants.

    Two carve-outs are the table's, ported verbatim. An item only a SUBSET of
    the models carry (`count < size`) is per-model equipment: its NAME stays off
    the unit rule line, and a Tough(X) it grants must not buff the whole squad
    (:803-813). And an item that grants a WEAPON has that weapon's name erased
    from the rule line again (:775-781)."""
    size = int(ud.get("size", 1))
    rules: list[str] = []
    for r in ud.get("rules", []):
        rl = _rule_label(r)
        if rl:
            rules.append(rl)
    grants: dict[str, list[str]] = {}
    if LEGACY_CORE_SELFPLAY:
        for su in ud.get("selectedUpgrades", []):
            option = su.get("option", {})
            for rl in _rules_in_upgrade_label(str(option.get("label", ""))):
                if rl not in rules:
                    rules.append(rl)
        return rules, grants
    for item in ud.get("loadout", []) or []:
        if isinstance(item, str):
            if item and item not in rules:
                rules.append(item)
            continue
        if not isinstance(item, dict) or int(item.get("attacks") or 0) > 0:
            continue  # a weapon profile — it rides in `weapons`, not on the rule line
        name = str(item.get("name", item.get("label", "")))
        per_model = size > 1 and 0 < _item_count(item.get("count", size), size) < size
        granted = _granted_rules_of_item(item)
        if name and granted:
            grants[name] = granted
        for wname in _granted_weapon_names_of_item(item):
            if wname in rules:
                rules.remove(wname)  # Array.erase: the FIRST occurrence only
        if not per_model and name and name not in rules:
            rules.append(name)
        for g in granted:
            if per_model and g.startswith("Tough("):
                continue
            if g not in rules:
                rules.append(g)
    return rules, grants


def _aura_granted_rules(members: list[dict[str, Any]]) -> list[str]:
    """ai_ev.gd:aura_granted_rules — the base rules a set of unit members (the
    unit plus its attached heroes) grants to the WHOLE unit through any "X Aura"
    they carry. The base keeps any qualifier: "Bane in Melee Aura" grants
    "Bane in Melee"."""
    granted: list[str] = []
    for m in members:
        for r in m["special_rules"]:
            rule = str(r).strip()
            if rule.endswith(" Aura"):
                base = rule[: -len(" Aura")].strip()
                if base and base not in granted:
                    granted.append(base)
    return granted


def _expand_auras(units: list[dict[str, Any]]) -> None:
    """opr_army_manager.gd:_expand_auras (:2112-2147), run once per ARMY right
    after the joined heroes are attached (:385-389).

    For every unit, every "X Aura" carried by the unit OR by one of its attached
    heroes grants X to the unit AND to each of those heroes — the official text
    is "this model and its unit get X", and the heroes need it too or
    `AiEv.rule_on_all_models`'s "all models" quantifier would withhold it.
    Purely additive and deduped; a base rule nothing models is simply inert.

    The attachment is `_attach_joined_heroes` (:2150-2164): index the army by
    selection id, then every unit whose `join_to_unit` names another one joins
    it. Combined halves are already folded away, so what is left joining is a
    Hero."""
    if LEGACY_CORE_SELFPLAY:
        return
    by_sel: dict[str, dict[str, Any]] = {}
    for u in units:
        if u["selection_id"]:
            by_sel[u["selection_id"]] = u
    heroes: dict[str, list[dict[str, Any]]] = {u["unit_id"]: [] for u in units}
    for u in units:
        host = by_sel.get(u["join_to_unit"])
        if host is not None and host["unit_id"] != u["unit_id"]:
            heroes[host["unit_id"]].append(u)
    for u in units:
        members = [u] + heroes[u["unit_id"]]
        granted = _aura_granted_rules(members)
        for m in members:
            for g in granted:
                if g not in m["special_rules"]:
                    m["special_rules"].append(g)


def _flatten_grants(grants: dict[str, list[str]]) -> list[str]:
    """battle_sim.gd:_granted_rules — `item_grants.values()` flattened in
    insertion order, the order rules_registry.gd:167 walks them."""
    return [g for granted_list in grants.values() for g in granted_list]


def _weapon_rating(rules: list[str], rule_name: str) -> int:
    """ai_shooting.gd:_rating_of — rating X of a weapon's "Name(X)" special
    rule, 0 if absent. NOT clamped to >= 0 (contrast _unit_rating below)."""
    prefix = rule_name + "("
    for r in rules:
        s = str(r).strip()
        if s.startswith(prefix) and s.endswith(")"):
            return int(s[len(prefix) : -1].replace("+", ""))
    return 0


def _unit_rating(special_rules: list[str], rule_name: str) -> int:
    """ai_ev.gd:unit_rating — rating X of a unit-level "Name(X)" special
    rule, 0 if absent, clamped to >= 0."""
    prefix = rule_name + "("
    for r in special_rules:
        s = str(r).strip()
        if s.startswith(prefix) and s.endswith(")"):
            return max(int(s[len(prefix) : -1].replace("+", "")), 0)
    return 0


def _rule_base_name(rule: str) -> str:
    """movement_range_controller.gd:_rule_base_name — "Swift(3)" -> "Swift"."""
    return rule.split("(")[0].strip()


def _registry_map(system: str) -> dict:
    """rules_registry.gd:normalize_system + map_for — a system's parsed
    mechanics map, cached; {} when the asset is missing, which degrades every
    reader below to its pre-NML-1108 fallback exactly as the table does."""
    s = str(system).strip().lower()
    if s not in REGISTRY_SYSTEMS:
        s = REGISTRY_DEFAULT_SYSTEM
    if s not in _REGISTRY_CACHE:
        try:
            with open(REGISTRY_DIR / ("rules_mechanics_%s.json" % s), encoding="utf-8") as f:
                parsed = json.load(f)
        except (OSError, ValueError):
            parsed = {}
        _REGISTRY_CACHE[s] = parsed if isinstance(parsed, dict) else {}
    return _REGISTRY_CACHE[s]


def _registry_entry(system: str, faction: str, rule_name: str) -> dict:
    """rules_registry.gd:lookup — the faction's own entry first, then the
    system's "common" one. ALWAYS keyed (system, faction, name), never by name
    alone: 154 of 383 rule names mean different things across game systems."""
    m = _registry_map(system)
    if not m:
        return {}
    factions = m.get("factions", {})
    if faction and faction != "common" and rule_name in factions.get(faction, {}):
        return factions[faction][rule_name]
    return m.get("common", {}).get(rule_name, {})


def _registry_primitive(entry: dict) -> str:
    """rules_registry.gd:has_primitive — an entry's automating primitive, ""
    for the explicit `"primitive": null` an UNautomated rule carries."""
    p = entry.get("primitive")
    return p if isinstance(p, str) else ""


def _has_special_rule(special_rules: list[str], name: str) -> bool:
    """game_unit.gd:has_special_rule via rule_name_matches (NML-1112) — the
    exact name or its parametrised form ("Tough(3)" answers "Tough"), never a
    bare prefix ("Fast" must not answer for "Fast Aura")."""
    for r in special_rules:
        t = str(r).strip()
        if t == name or (t.startswith(name) and t[len(name):].strip().startswith("(")):
            return True
    return False


def _rule_active(special_rules: list[str], system: str, faction: str, name: str) -> bool:
    """rules_registry.gd:unit_rule_active — the unit carries the rule AND its
    book fields it for this system; a MISSING map falls back to the plain
    rule check, so a checkout without assets keeps the old behaviour."""
    if not _has_special_rule(special_rules, name):
        return False
    if not _registry_map(system):
        return True
    return bool(_registry_primitive(_registry_entry(system, faction, name)))


def _rules_of_primitive(
    special_rules: list[str], grants: list[str], system: str, faction: str, primitive: str
) -> list[tuple[str, dict]]:
    """rules_registry.gd:unit_rules_of_primitive — (name, params) of every
    EFFECTIVE rule aliased to `primitive`: direct special_rules first, then
    item_grants, each base name counted once in first-seen order."""
    out: list[tuple[str, dict]] = []
    seen: set[str] = set()
    for raw in list(special_rules) + list(grants):
        n = _rule_base_name(str(raw))
        if not n or n in seen:
            continue
        seen.add(n)
        entry = _registry_entry(system, faction, n)
        if _registry_primitive(entry) == primitive:
            out.append((n, entry.get("params", {})))
    return out


def _bounding_dice_count(params: dict) -> int:
    """solo_controller.gd:bounding_dice_count — how many dice the placement
    rolls: an explicit `dice_count`, else the head of a `place_die` like
    "2D3", else one."""
    if "dice_count" in params:
        return max(int(params["dice_count"]), 1)
    pd = str(params.get("place_die", "")).lower()
    if "d" in pd:
        head = pd.split("d", 1)[0].strip()
        if _is_valid_int(head):
            return max(int(head), 1)
    return 1


def _move_bands(
    special_rules: list[str], game_system: str = "", faction: str = ""
) -> dict[str, float]:
    """movement_range_controller.gd:move_bands_for_props — the NAME pass
    (:125-163) plus, since NML-1108, the REGISTRY pass (:164-188). The
    DESCRIPTION pass (:108-115) stays out: it reads `rule_descriptions`, free
    rule text the arena fetches from the army-book API and these lists lack.

    Order matters and is the table's: a band the name pass already filled is
    NOT topped up by the registry, so Fast + Highborn is 10"/18" and not
    12"/22", while an "X Aura" the aura expansion turned into a second, bare
    "X" DOES stack — the table counts both too (its description pass reads the
    aura's own text). A once-per-game feat (`uses_per_game`) never rides the
    permanent bands."""
    advance = OPR_ADVANCE_INCHES
    rush = OPR_RUSH_CHARGE_INCHES
    counted: dict[str, dict[str, bool]] = {}
    for r in special_rules:
        base = _rule_base_name(str(r))
        done = counted.get(base, {"advance": False, "rush": False})
        if done["advance"] and done["rush"]:
            continue
        if base == "Fast":
            if not done["advance"]:
                advance += FAST_ADVANCE_BONUS
            if not done["rush"]:
                rush += FAST_RUSH_BONUS
            counted[base] = {"advance": True, "rush": True}
        elif base == "Slow":
            if not done["advance"]:
                advance -= FAST_ADVANCE_BONUS
            if not done["rush"]:
                rush -= FAST_RUSH_BONUS
            counted[base] = {"advance": True, "rush": True}
        elif base == "Rapid Rush":
            if not done["rush"]:
                rush += RAPID_RUSH_BONUS
            counted[base] = {"advance": True, "rush": True}
        elif base == "Quick":
            if not done["advance"]:
                advance += QUICK_BONUS
            if not done["rush"]:
                rush += QUICK_BONUS
            counted[base] = {"advance": True, "rush": True}
        elif base == "Rapid Advance":
            if not done["advance"]:
                advance += RAPID_ADVANCE_BONUS
            counted[base] = {"advance": True, "rush": True}
    if not LEGACY_CORE_SELFPLAY:
        for r in special_rules:
            base = _rule_base_name(str(r))
            done = counted.get(base, {"advance": False, "rush": False})
            if done["advance"] and done["rush"]:
                continue
            entry = _registry_entry(game_system, faction, base)
            if _registry_primitive(entry) not in MOVE_PRIMITIVES:
                continue
            rp = entry.get("params", {})
            if int(rp.get("uses_per_game", 0)) > 0:
                continue
            if not done["advance"]:
                advance += int(rp.get("advance_mod", 0))
            if not done["rush"]:
                rush += int(rp.get("rush_mod", rp.get("charge_mod", 0)))
            counted[base] = {"advance": True, "rush": True}
    return {"advance": float(max(0, advance)), "rush": float(max(0, rush))}


def _shooting_range_bonus(
    special_rules: list[str], grants: list[str], game_system: str, faction: str
) -> int:
    """solo_controller.gd:shooting_range_bonus — Royal Legion's +4" range (the
    inches are registry DATA, the constant is the byte-identical fallback), or
    the largest `range_bonus_in` any DATA alias of that primitive carries. The
    table also adds `unit_properties["spell_range_mod"]`, a live solo-layer
    stamp that is 0 at deployment — the instant the act header is written."""
    if _has_special_rule(special_rules, "Royal Legion"):
        params = _registry_entry(game_system, faction, "Royal Legion").get("params", {})
        return int(params.get("range_bonus_in", ROYAL_LEGION_RANGE_BONUS_IN))
    best = 0
    for _n, params in _rules_of_primitive(
        special_rules, grants, game_system, faction, "Royal Legion"
    ):
        best = max(best, int(params.get("range_bonus_in", 0)))
    return best


def _max_activation_advance_bonus_in(
    special_rules: list[str], grants: list[str], game_system: str, faction: str
) -> float:
    """solo_controller.gd:max_activation_advance_bonus_in — the LARGEST extra
    Advance inches one activation can put on TOP of the bands, worst-roll on
    purpose (a reach gate that over-offers only over-offers): Bounding's
    placement (3" per die plus the flat), a once-per-game Quick feat, and the
    Teleport family's own `advance_bonus_in`."""
    bonus = 0.0
    if _rule_active(special_rules, game_system, faction, "Bounding"):
        params = _registry_entry(game_system, faction, "Bounding").get("params", {})
        bonus += _bounding_dice_count(params) * 3.0 + float(params.get("place_d3_plus", 1))
    else:
        best = 0.0
        for _n, params in _rules_of_primitive(
            special_rules, grants, game_system, faction, "Bounding"
        ):
            best = max(
                best, _bounding_dice_count(params) * 3.0 + float(params.get("place_d3_plus", 0))
            )
        bonus += best
    for _n, params in _rules_of_primitive(special_rules, grants, game_system, faction, "Quick"):
        if int(params.get("uses_per_game", 0)) > 0:
            bonus += max(0.0, float(params.get("advance_mod", 2)))
    tele = "Teleport" if _rule_active(special_rules, game_system, faction, "Teleport") else ""
    if not tele:
        for n, _params in _rules_of_primitive(
            special_rules, grants, game_system, faction, "Teleport"
        ):
            if n != "Teleport":
                tele = n
                break
    if tele:
        params = _registry_entry(game_system, faction, tele).get("params", {})
        bonus += max(0.0, float(params.get("advance_bonus_in", TELEPORT_ADVANCE_BONUS_IN)))
    return bonus


def _is_valid_int(s: str) -> bool:
    """GDScript `String.is_valid_int()` — an optional sign, then digits only."""
    return re.fullmatch(r"[+-]?\d+", s) is not None


def _is_valid_float(s: str) -> bool:
    """GDScript `String.is_valid_float()`."""
    return re.fullmatch(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?", s) is not None


def _is_usable_base_value(value: Any) -> bool:
    """opr_api_client.gd:_is_usable_base_value — Army Forge answers
    `bases:{round:"none"}` for a model it has no recommendation for, so a
    non-empty dict is not proof of a real one."""
    if isinstance(value, bool):
        return False
    if isinstance(value, (int, float)):
        return value > 0
    if isinstance(value, str):
        s = value.strip().lower()
        if s in ("", "none", "null", "0"):
            return False
        return "x" in s or _is_valid_int(s) or _is_valid_float(s)
    return False


def _parse_base_size(value: Any, default: int = DEFAULT_BASE_MM) -> tuple[bool, int, int]:
    """opr_api_client.gd:_parse_base_size — `(is_oval, width_mm, depth_mm)`.
    A round base answers `(False, size, size)`; an oval "105x70" answers
    `(True, 70, 105)` — width is the SHORT axis (perpendicular to facing),
    depth the LONG one, whichever order Army Forge wrote them in."""
    if value is None or isinstance(value, bool):
        return (False, default, default)
    if isinstance(value, int):
        return (False, value, value)
    if isinstance(value, float):
        return (False, int(value), int(value))
    if isinstance(value, str):
        if "x" in value:
            parts = value.split("x")
            if len(parts) >= 2:
                first = int(parts[0]) if _is_valid_int(parts[0]) else default
                second = int(parts[1]) if _is_valid_int(parts[1]) else default
                return (True, min(first, second), max(first, second))
        if _is_valid_int(value):
            return (False, int(value), int(value))
        if _is_valid_float(value):
            return (False, int(float(value)), int(float(value)))
    return (False, default, default)


def _clamp_mm(mm: int) -> int:
    return max(BASE_MM_MIN, min(BASE_MM_MAX, mm))


#: opr_api_client.gd:531-534 — keyword heuristics for classifying a bracketless big
#: single model when Army Forge gave no usable base. VEHICLE_KEYWORDS is checked
#: FIRST (NML-993): vehicle-heavy names ("APC", "tank", ...) win over walker-shaped
#: words ("Knight Brothers APC" is a transport, not a knight-walker).
VEHICLE_KEYWORDS = ("apc", "tank", "transport", "carrier", "hover", "chariot", "buggy")
WALKER_KEYWORDS = (
    "walker", "mech", "dreadnought", "sentinel", "war-suit", "warsuit", "exo", "knight", "suit",
)
ARTILLERY_KEYWORDS = (
    "artillery", "cannon", "mortar", "howitzer", "battery", "ballista", "catapult", "bombard",
)
MONSTER_KEYWORDS = (
    "dragon", "beast", "monster", "wyrm", "behemoth", "daemon", "demon", "hive", "kraken",
    "hydra", "giant", "ogre", "troll",
)


def _tough_from_rules(rules: list[str]) -> int:
    """opr_api_client.gd:_tough_from_rules — Tough(x) off a special_rules array (0 if none)."""
    for r in rules:
        s = str(r)
        if s.startswith("Tough(") and s.endswith(")") and _is_valid_int(s[len("Tough(") : -1]):
            return int(s[len("Tough(") : -1])
    return 0


def _classify_big_model(name: str, size: int, tough: int) -> str:
    """opr_api_client.gd:_classify_big_model — walker / vehicle / artillery / monster, or ""
    for infantry/cavalry/hero (sized by the round Tough ladder instead). Multi-model units are
    never a vehicle; a keyword-less single model is only a vehicle once Tough >= 6."""
    if size > 1:
        return ""
    n = name.lower()
    for kw in VEHICLE_KEYWORDS:
        if kw in n:
            return "vehicle"
    for kw in WALKER_KEYWORDS:
        if kw in n:
            return "walker"
    for kw in ARTILLERY_KEYWORDS:
        if kw in n:
            return "artillery"
    for kw in MONSTER_KEYWORDS:
        if kw in n:
            return "monster"
    return "vehicle" if tough >= 6 else ""


def _walker_base_mm(tough: int) -> int:
    """opr_api_client.gd:_walker_base_mm — ROUND base (mm) by Tough."""
    if tough >= 18:
        return 120
    if tough >= 15:
        return 100
    if tough >= 12:
        return 80
    if tough >= 9:
        return 60
    if tough >= 6:
        return 50
    return 40


def _vehicle_base_mm(tough: int) -> tuple[int, int]:
    """opr_api_client.gd:_vehicle_base_mm — OVAL base (width_mm, depth_mm) by Tough."""
    if tough >= 18:
        return (105, 170)
    if tough >= 15:
        return (92, 150)
    if tough >= 12:
        return (92, 120)
    if tough >= 9:
        return (70, 105)
    if tough >= 6:
        return (52, 90)
    return (42, 75)


def _artillery_base_mm(tough: int) -> tuple[int, int]:
    """opr_api_client.gd:_artillery_base_mm — OVAL base (width_mm, depth_mm) by Tough."""
    if tough >= 9:
        return (52, 90)
    if tough >= 6:
        return (42, 75)
    return (35, 60)


def _base_of(ud: dict[str, Any], game_system: str, rules: list[str]) -> dict[str, Any]:
    """opr_api_client.gd:_apply_base_recommendation over ONE list selection ->
    the three properties `SeparationChecker.shape_for_model` reads off
    `unit_properties` (`base_is_oval` / `base_width_mm` / `base_depth_mm`).

    PRECEDENCE RULE, verbatim from the table: an explicit Army-Forge
    recommendation always WINS; without a usable one, `_apply_tough_base_fallback`
    (opr_api_client.gd:609-633) sizes the unit from its TYPE (keyword + Tough) —
    see `_classify_big_model` and friends above. Its "never shrink below the
    existing base" guard is not reproduced: every ladder mm here (>= 35) already
    exceeds `OPRUnit`'s 32 mm round default, the only base this fallback ever
    starts from, so the guard can never actually block anything. `aofr` reads the
    SQUARE recommendation first; its shape is still `shape_for_model`'s round
    branch, off the longer edge.

    NML-1152 step 6c — the MOUNT link (opr_api_client.gd:994-1008): the item
    loop runs AFTER the AF parse (:930) and BEFORE the Tough fallback (:1040);
    a single-model unit's mount/vehicle upgrade carrying a usable
    `bases.round` REPLACES the unit base (last item wins, no clamp on this
    path — the table assigns the parsed ints directly)."""
    bases = ud.get("bases") or {}
    if not isinstance(bases, dict):
        bases = {}
    # The OPRUnit fields exist either way (opr_api_client.gd:269-270 defaults);
    # the chain mutates them in the table's own order: AF parse (:930) →
    # mount items (:994-1008) → Tough fallback (:1040, grow-only).
    base: dict[str, Any] = {"is_oval": False, "width_mm": DEFAULT_BASE_MM, "depth_mm": DEFAULT_BASE_MM}
    had_recommendation = False
    if game_system == "aofr" and _is_usable_base_value(bases.get("square", "")):
        _, w, d = _parse_base_size(bases.get("square", ""), 25)
        base = {"is_oval": False, "width_mm": _clamp_mm(w), "depth_mm": _clamp_mm(d)}
        had_recommendation = True
    elif _is_usable_base_value(bases.get("round", "")):
        is_oval, w, d = _parse_base_size(bases.get("round", ""), DEFAULT_BASE_MM)
        base = {"is_oval": is_oval, "width_mm": _clamp_mm(w), "depth_mm": _clamp_mm(d)}
        had_recommendation = True
    if int(ud.get("size", 1)) <= 1:
        for item in ud.get("loadout", []) or []:
            if not isinstance(item, dict) or int(item.get("attacks") or 0) > 0:
                continue
            item_bases = item.get("bases")
            if isinstance(item_bases, dict) and _is_usable_base_value(item_bases.get("round", "")):
                m_oval, m_w, m_d = _parse_base_size(item_bases.get("round", ""), DEFAULT_BASE_MM)
                base = {"is_oval": bool(m_oval), "width_mm": int(m_w), "depth_mm": int(m_d)}
    if not had_recommendation:
        base = _tough_fallback_base(base, str(ud.get("name", "")), int(ud.get("size", 1)), rules)
    return base


def _tough_fallback_base(base: dict[str, Any], name: str, size: int, rules: list[str]) -> dict[str, Any]:
    """`_apply_tough_base_fallback` (opr_api_client.gd:833-850) with its
    `_set_round_base` / `_set_oval_base` (:887-906) grow-only guards — a mount
    base already REPLACED above is never shrunk. The guard IS reachable here
    (unlike on a fresh 32 mm default): a mount can be smaller than the ladder."""
    tough = _tough_from_rules(rules)
    if tough < 3:
        return base  # normal infantry / heroes — keep the base (:835-836)
    long_mm = max(base["width_mm"], base["depth_mm"])
    verdict = _classify_big_model(name, size, tough)
    if verdict in ("vehicle", "artillery"):
        w, d = _vehicle_base_mm(tough) if verdict == "vehicle" else _artillery_base_mm(tough)
        if max(w, d) <= long_mm:
            return base  # _set_oval_base :900-901
        return {"is_oval": True, "width_mm": w, "depth_mm": d}
    mm = _walker_base_mm(tough) if verdict in ("walker", "monster") else _base_size_from_tough(tough)
    if mm <= long_mm:
        return base  # _set_round_base :888-889
    return {"is_oval": False, "width_mm": mm, "depth_mm": mm}


def _base_size_from_tough(tough: int) -> int:
    """opr_api_client.gd:_base_size_from_tough — the base long edge (mm) a
    model's Tough alone justifies. 0 = normal infantry, keep the unit base."""
    if tough >= 18:
        return 150  # Titans
    if tough >= 12:
        return 120  # Large monsters / giants / large vehicles
    if tough >= 9:
        return 80
    if tough >= 6:
        return 60  # Monsters / vehicles
    if tough >= 3:
        return 40  # Large infantry / cavalry
    return 0


def _base_radius_m(base: dict[str, Any], model_tough: int = 1) -> float:
    """`SoloController.model_base_radius_m` (solo_controller.gd:5187-5191) =
    `SeparationChecker.shape_for_model(...).bounding_radius()` for the unit's
    FIRST model — exactly the scalar an act header carries as `base_radius`.

    A Tough model's base grows to `OPRArmyManager.model_base_long_mm`
    (opr_army_manager.gd:1470) — unit base vs Tough-justified base, whichever is
    longer — as a SCALE, so an oval keeps its proportions. Round: the scaled
    radius. Oval: the circumscribed radius of the scaled half-axes
    (separation_checker.gd:253-278, :137-140)."""
    long_mm = max(base["width_mm"], base["depth_mm"])
    scale = float(max(long_mm, _base_size_from_tough(model_tough))) / float(max(1, long_mm))
    if base["is_oval"]:
        semi_x = (base["width_mm"] / 2.0) * MM_TO_METERS * scale
        semi_z = (base["depth_mm"] / 2.0) * MM_TO_METERS * scale
        return math.sqrt(semi_x * semi_x + semi_z * semi_z)
    return (long_mm / 2.0) * MM_TO_METERS * scale


#: NML-1073 M5 D5-4b — the base SHAPES an act-header profile may name.
#: `"rect"` is READ and never written: `SeparationChecker.shape_for_model`
#: (separation_checker.gd:253-278) has no RECT branch, so a `base_is_square`
#: unit gets a ROUND shape off `base_size_round` and the recorder says round.
BASE_SHAPES = ("round", "oval", "rect")


def base_shape_of(profile: dict[str, Any]) -> tuple[str, int | None, int | None]:
    """The base SHAPE of one act-header profile: `(base_shape, w_mm, d_mm)`.

    WHY IT IS NOT `base_radius`. That scalar is `BaseShape.bounding_radius()`,
    the CIRCUMSCRIBING circle of the unit's first model, while the table's own
    contact measure `SeparationChecker._edge_distance_meters`
    (separation_checker.gd:290) walks the exact SUPPORT EXTENT of an oval. A
    reader with the radius alone therefore mis-measures every oval base —
    vehicles, cavalry, monsters — and no amount of Rust can fix it, because the
    corpus did not carry the shape. `BattleSim._unit_profile` records these
    three keys from D5-4b on; this is the reader for them.

    A header recorded BEFORE D5-4b carries none of the three. That is answered
    `("round", None, None)`: round is what every consumer already assumes, and
    the two `None`s say the axes are unknown rather than 32 mm. An unknown
    `base_shape` RAISES — reading a geometry this port cannot draw as if it
    were a circle is the silent skip, not the safe default.

    The mm are the unit's UNSCALED list reading. The per-MODEL Tough scale is
    already in `state["radii"]`, so each model's semi-axes come back as
    `radius * (axis_mm / max(w_mm, d_mm))`.
    """
    shape = str(profile.get("base_shape") or "round")
    if shape not in BASE_SHAPES:
        raise ValueError("unknown base_shape %r — expected one of %s"
                         % (shape, ", ".join(BASE_SHAPES)))
    w, d = profile.get("base_w_mm"), profile.get("base_d_mm")
    return shape, (None if w is None else int(w)), (None if d is None else int(d))


def _caster_value(special_rules: list[str], alive_count: int) -> int:
    """game_unit.gd:get_caster_value — Caster(X) rating, else Caster Group's
    alive-model count, else Spell Accumulator(X), else 0."""
    for r in special_rules:
        s = str(r)
        if s.startswith("Caster("):
            start = s.find("(") + 1
            end = s.find(")")
            if start > 0 and end > start:
                return int(s[start:end])
    if any(str(r).startswith("Caster Group") for r in special_rules):
        return max(alive_count, 0)
    for r in special_rules:
        s = str(r)
        if s.startswith("Spell Accumulator("):
            start = s.find("(") + 1
            end = s.find(")")
            if start > 0 and end > start:
                return int(s[start:end])
    return 0


def _faction_from_path(path: str | Path) -> str:
    """core_selfplay.gd:_units_from_list — the faction is the list
    FILENAME up to its last underscore ("robot_legions_1000" ->
    "robot_legions"; a name with no underscore stays whole)."""
    stem = Path(path).stem
    us = stem.rfind("_")
    return stem[:us] if us > 0 else stem


#: NML-1152 step 6c — the bundled model manifest's `base_mm` specs
#: (model_library.gd:127-134), keyed `faction/normalized unit name`
#: (make_key :100-109). Loaded once; a missing/malformed file means no
#: overrides (default-preserving, like the loader's bundled fallback).
_MANIFEST_BASES: dict[str, dict[str, Any]] | None = None


def _manifest_base_overrides() -> dict[str, dict[str, Any]]:
    global _MANIFEST_BASES
    if _MANIFEST_BASES is None:
        out: dict[str, dict[str, Any]] = {}
        p = Path(__file__).resolve().parents[2] / "assets" / "model_manifest.json"
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
        for key, entry in (data.get("models") or {}).items():
            if isinstance(entry, dict) and isinstance(entry.get("base_mm"), dict):
                out[str(key)] = entry["base_mm"]
        _MANIFEST_BASES = out
    return _MANIFEST_BASES


def _normalize_unit(s: str) -> str:
    """model_library.gd:_normalize_unit — lowercase, -/_ folded to spaces,
    space repeats collapsed; both sides of the manifest lookup."""
    t = s.strip().lower().replace("-", " ").replace("_", " ")
    while "  " in t:
        t = t.replace("  ", " ")
    return t


def _apply_manifest_base_overrides(built: list[dict[str, Any]], faction: str) -> None:
    """opr_army_manager.gd:_apply_manifest_base_overrides (:2565-2589) — runs at
    SPAWN on the table, i.e. post-fold, per unit NAME. Precedence
    MANIFEST > AF base > Tough-derived: a present override REPLACES the parsed
    base with no grow guard (the parse has already resolved the lower links).
    The table's `base_is_square` branch (:2574-2581) is aofr-only; the corpus
    game system is `gf`, so the round branch here carries the whole law."""
    overrides = _manifest_base_overrides()
    if not overrides:
        return
    prefix = faction.strip().lower() + "/"
    for u in built:
        spec = overrides.get(prefix + _normalize_unit(str(u["name"])))
        if not spec:
            continue
        if _is_usable_base_value(spec.get("round", "")):
            m_oval, m_w, m_d = _parse_base_size(spec.get("round", ""), DEFAULT_BASE_MM)
            u["base"] = {"is_oval": bool(m_oval), "width_mm": int(m_w), "depth_mm": int(m_d)}


def deploy_base_groups(
    data: dict[str, Any], faction: str, player: int
) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    """NML-1152 step 6c — the twin's production base-shape derivation for the
    deployment law: `(units, heroes_of)`. `units` are `_units_from_list`'s
    internal units (combined folded, non-combined attached heroes kept as
    their own entries) with the manifest override applied; `heroes_of` maps a
    host's selectionId -> its attached heroes in list order. The host's
    DEPLOYMENT models are its own plus each attached hero's
    (solo_controller.gd:_deploy_models :10239-10245) — the fold the settle's
    per-model shapes and `_deploy_base_radius` (:10263-10267) read. Per-unit
    shape inputs: `u["base"]` + `u["model_tough"]`."""
    built = _units_from_list(data, player)
    _apply_manifest_base_overrides(built, faction)
    heroes_of: dict[str, list[dict[str, Any]]] = {}
    for u in built:
        if u["join_to_unit"]:
            heroes_of.setdefault(u["join_to_unit"], []).append(u)
    return built, heroes_of


# ------------------------------------------------------- arena deploy roster ---
# NML-1152 step 8 — the UnitSpec roster the arena deployment branch feeds
# `nml_core.deploy_side`. The twin derives everything from the LIST (the 6c
# doctrine: the dump's shape fields are the gate's oracle only).

# solo_controller.gd:10228-10229 — the compact deployment grid the footprint
# offsets build (the model POSITIONS themselves are `_place_unit_at`'s fixed
# grid, ported Rust-side in `place_unit_models`).
DEPLOY_SPACING_M = 0.04
DEPLOY_COLS = 5
# coherency_checker.gd:13/:18 — the span cap the grid shrinks under. The
# skirmish 6" cap is corpus-absent like the Rust port's (a skirmish corpus
# must extend this law, not silently reuse the 9" one).
DEPLOY_MAX_CHAIN_IN = 9.0
# separation_checker.gd — the DEFAULT_BASE_RADIUS_M `_deploy_base_radius`
# starts from (:10261).
DEPLOY_DEFAULT_BASE_R_M = 0.016


def _rule_matches(candidate: str, rule: str) -> bool:
    """game_unit.gd:rule_name_matches :254-258 — the exact name, or the name
    followed by a parenthesised qualifier ("Tough(3)"); a bare prefix is NOT a
    match ("Fearless" is not "Fear", "Ambush Beacon" is not "Ambush")."""
    s = str(candidate).strip()
    return s == rule or (s.startswith(rule) and s[len(rule):].strip().startswith("("))


def _base_rule(candidate: str) -> str:
    """RulesRegistry.base_rule_name :128-129 — the name without its params."""
    return str(candidate).strip().split("(", 1)[0].strip()


def _deploy_flags(u: dict[str, Any]) -> dict[str, bool]:
    """The four deployment classifications over one internal unit.

    solo_controller.gd:9009-9015 + :10165-10191: Scout = the special rule or an
    item-granted "Scout" (B12); Ambush = Ambush/Infiltrate/Rapid Ambush by base
    name, special rules or grants (the counts_as ALIAS branch of
    `unit_has_ambush` needs the live RulesRegistry and has no list-side
    reading); Strider/Flying ignore terrain (:9109, special rules only, no
    grants); Vanguard = the rule or a grant (the table ANDs `unit_rule_active`
    with the faction book map, which a list cannot see)."""
    rules = [str(r) for r in u["special_rules"]]
    grants = [str(g) for g in u["item_grants"]]
    ambush_rules = ("Ambush", "Infiltrate", "Rapid Ambush")
    return {
        "scout": any(_rule_matches(r, "Scout") for r in rules)
        or any(_base_rule(g) == "Scout" for g in grants),
        "ambush": any(_base_rule(r) in ambush_rules for r in rules)
        or any(_base_rule(g) in ambush_rules for g in grants),
        "ignores_terrain": any(
            _rule_matches(r, "Strider") or _rule_matches(r, "Flying") for r in rules
        ),
        "vanguard": any(_rule_matches(r, "Vanguard") for r in rules)
        or any(_base_rule(g) == "Vanguard" for g in grants),
    }


def _deploy_footprint_offsets(shapes: list[dict[str, Any]]) -> list[list[float]]:
    """solo_controller.gd:_deploy_footprint_offsets :10273-10307 over the
    folded shape groups — the model-local XZ offsets (metres, relative to the
    drop anchor) the drop WILL build, so the footprint check tests where each
    model actually lands. Squarest grid + base-aware spacing + span cap."""
    n = sum(int(g["n"]) for g in shapes)
    if n == 0:
        return []
    base_r = max(
        [DEPLOY_DEFAULT_BASE_R_M]
        + [
            _base_radius_m(
                {"is_oval": g["is_oval"], "width_mm": g["w_mm"], "depth_mm": g["d_mm"]},
                int(g["tough"]),
            )
            for g in shapes
        ]
    )
    spacing = max(DEPLOY_SPACING_M, 2.0 * base_r + 0.006)
    cols = min(n, DEPLOY_COLS) if n <= 2 * DEPLOY_COLS else math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)
    span_cap = (DEPLOY_MAX_CHAIN_IN - 0.5) * 0.0254
    grid_diag = math.sqrt((cols - 1) ** 2 + (rows - 1) ** 2)
    if grid_diag > 0.001 and grid_diag * spacing + 2.0 * base_r > span_cap:
        spacing = max(2.0 * base_r + 0.002, (span_cap - 2.0 * base_r) / grid_diag)
    return [
        [
            (float(i % cols) - float(cols - 1) * 0.5) * spacing,
            (float(i // cols) - float(rows - 1) * 0.5) * spacing,
        ]
        for i in range(n)
    ]


def deploy_unit_specs(
    data: dict[str, Any], faction: str, player: int
) -> tuple[list[dict[str, Any]], dict[str, tuple[str, int, int]]]:
    """NML-1152 step 8 — the arena deployment roster for one list:
    `(specs, hero_fold)`.

    `specs` are UnitSpec dicts in host-creation order, one per unit EXCLUDING
    its attached heroes — `_deploy_models` (:10238-10245) deploys the host's
    models PLUS each attached hero's, so a hero folds into its host's group
    (model_shapes: host first, heroes in list order — the settle reads them in
    exactly that order). A hero whose joinToUnit names no selection stays its
    own row, the same guard `derive_attachment` applies. `hero_fold` maps a
    folded hero's unit_id -> `(host_key, offset, count)`: the hero's models are
    that slice of the host's settled group.

    NOT ported (corpus-absent, named loudly): regiments deploy from their tray
    (`_is_regiment` -> empty offsets) and a dangling hero-of-hero chain."""
    built, heroes_of = deploy_base_groups(data, faction, player)
    by_sel = {u["selection_id"]: u for u in built if u["selection_id"]}
    specs: list[dict[str, Any]] = []
    hero_fold: dict[str, tuple[str, int, int]] = {}
    for u in built:
        if u["join_to_unit"] and u["join_to_unit"] in by_sel:
            continue
        group = [u] + (heroes_of.get(u["selection_id"], []) if u["selection_id"] else [])
        shapes: list[dict[str, Any]] = []
        model_count = 0
        for m in group:
            toughs = [int(t) for t in m["model_tough"]]
            if toughs and any(t != toughs[0] for t in toughs):
                raise ValueError("per-model Tough not uniform in %s" % m["name"])
            shapes.append(
                {
                    "is_oval": bool(m["base"]["is_oval"]),
                    "w_mm": int(m["base"]["width_mm"]),
                    "d_mm": int(m["base"]["depth_mm"]),
                    "tough": toughs[0] if toughs else 1,
                    "n": len(toughs),
                }
            )
            model_count += len(toughs)
        flags = _deploy_flags(u)
        specs.append(
            {
                "key": u["unit_id"],
                "model_count": model_count,
                # The ladder reads `deploy_base_radius_of` (the shapes) — this
                # scalar stays the act-header-style cross-check artifact (6c).
                "base_r_m": _base_radius_m(
                    u["base"], int(u["model_tough"][0]) if u["model_tough"] else 1
                ),
                "footprint": _deploy_footprint_offsets(shapes),
                "scout": flags["scout"],
                "ambush": flags["ambush"],
                "ignores_terrain": flags["ignores_terrain"],
                "vanguard": flags["vanguard"],
                "transport_capacity": 0,
                "facing_rad": 0.0,
                "model_shapes": shapes,
            }
        )
        offset = model_count - sum(int(g["n"]) for g in shapes[1:])
        for h in group[1:]:
            count = len(h["model_tough"])
            hero_fold[h["unit_id"]] = (u["unit_id"], offset, count)
            offset += count
    return specs, hero_fold


def _units_from_list(
    data: dict[str, Any], player: int
) -> list[dict[str, Any]]:
    """core_selfplay.gd:_units_from_list + _append_selection — two passes
    over data["units"]: pass 1 builds one internal unit per selection that
    is NOT a combined-in partner; pass 2 folds each combined partner
    (joinToUnit + combined:true) into its host by selectionId. Returns the
    internal (pre-profile) unit dicts in host-creation order."""
    raw: list[dict] = data.get("units", [])
    game_system = str(data.get("gameSystem", "gf"))
    units: dict[str, dict] = {}
    by_sel: dict[str, dict] = {}
    order: list[str] = []
    uidx = 0

    def append_selection(u: dict, ud: dict) -> None:
        """The selection's WEAPONS and per-model Tough. Its rules and item
        grants come from `_selection_rules` at the call site, because the
        table's combined-unit merge folds those two with different rules
        (dedup / first-item-wins) than the pooling done here."""
        for w in ud.get("weapons", []):
            wrules: list[str] = []
            for wr in w.get("specialRules", []):
                wl = _rule_to_string(wr)
                if wl:
                    wrules.append(wl)
            u["weapons"].append(
                {
                    "name": str(w.get("name", "W")),
                    "range": int(w.get("range", 0)),
                    "attacks": int(w.get("attacks", 1)),
                    "count": max(int(w.get("count", 1)), 1),
                    "rules": wrules,
                }
            )
        tough = 1
        for r in ud.get("rules", []):
            rl = _rule_label(r)
            if rl.startswith("Tough("):
                tough = max(int(rl[len("Tough(") : -1]), 1)
        for _ in range(int(ud.get("size", 1))):
            u["model_tough"].append(tough)

    for ud in raw:
        if ud.get("joinToUnit") and bool(ud.get("combined", False)):
            continue  # folded into its partner in the second pass
        rules, grants = _selection_rules(ud)
        unit_id = "p%d_%d_%s" % (player, uidx, str(ud.get("id", uidx)))
        uidx += 1
        u = {
            "unit_id": unit_id,
            "name": str(ud.get("name", "Unit")),
            "quality": int(ud.get("quality", 4)),
            "defense": int(ud.get("defense", 4)),
            # NML-1073 D4: the two list fields `_unit_profile` does NOT carry —
            # see `selections_from_army_forge_json`. `joinToUnit` is JSON null on
            # a selection that joins nothing, so `or ""` and not `get(.., "")`.
            "selection_id": str(ud.get("selectionId", "")),
            "join_to_unit": str(ud.get("joinToUnit") or ""),
            "special_rules": rules,
            "item_grants": grants,
            "weapons": [],
            "model_tough": [],
            # NML-1097 / NML-1097b: the HOST selection's base. A combined-in partner
            # folds its models in and its own `bases` is dropped — `_merge_combined_units`
            # (opr_api_client.gd:1378-1411) keeps the anchor half's base. `rules` is
            # this selection's already-assembled special_rules (base rules + loadout
            # grants) — the Tough(x) fallback classifier reads the same set
            # `_apply_tough_base_fallback` does on the table (`unit.special_rules`).
            "base": _base_of(ud, game_system, rules),
        }
        append_selection(u, ud)
        by_sel[str(ud.get("selectionId", ""))] = u
        units[unit_id] = u
        order.append(unit_id)

    for ud in raw:
        if not (ud.get("joinToUnit") and bool(ud.get("combined", False))):
            continue
        host = by_sel.get(str(ud["joinToUnit"]))
        if host is not None:
            append_selection(host, ud)
            # `_merge_combined_units` (opr_api_client.gd:1400-1407): the partner
            # half's rule lines are appended to the anchor if absent, and an
            # item name the anchor already grants under is NOT overwritten.
            prules, pgrants = _selection_rules(ud)
            for r in prules:
                if r not in host["special_rules"]:
                    host["special_rules"].append(r)
            for item_name, granted in pgrants.items():
                host["item_grants"].setdefault(item_name, granted)
        # else: dropped, mirroring core_selfplay.gd's printerr-only WARN

    return [units[k] for k in order]


def _unit_profile(u: dict[str, Any], faction: str, game_system: str) -> dict[str, Any]:
    """battle_sim.gd:_unit_profile off one internal unit dict."""
    special_rules: list[str] = u["special_rules"]
    grants: list[str] = _flatten_grants(u["item_grants"])
    model_count = len(u["model_tough"])
    weapons = [
        {
            "name": w["name"],
            "range": w["range"],
            "attacks": w["attacks"],
            "count": w["count"],
            "ap": _weapon_rating(w["rules"], "AP"),
            "rules": w["rules"],
        }
        for w in u["weapons"]
    ]
    return {
        "unit_id": u["unit_id"],
        "name": u["name"],
        "quality": u["quality"],
        "defense": u["defense"],
        "tough": max(_unit_rating(special_rules, "Tough"), 1),
        "wounds_max": list(u["model_tough"]),
        "model_count": model_count,
        "weapons": weapons,
        "special_rules": special_rules,
        "caster_value": _caster_value(special_rules, model_count),
        "move_bands": _move_bands(special_rules, game_system, faction),
        "base_radius": (DEFAULT_BASE_MM / 2.0) * MM_TO_METERS
        if LEGACY_CORE_SELFPLAY
        else _base_radius_m(u["base"], u["model_tough"][0] if u["model_tough"] else 1),
        "game_system": game_system,
        "faction_folder": faction,
        "item_grants": grants,
        "attached_hero_rules": [],
        # unit_profile_dyn fields — see module docstring ("Two more fields").
        # LEGACY_CORE_SELFPLAY replays the pre-NML-1108 hardcoded reading, the
        # one every corpus tools/core_selfplay.gd recorded was played under.
        "shooting_range_bonus": 0
        if LEGACY_CORE_SELFPLAY
        else _shooting_range_bonus(special_rules, grants, game_system, faction),
        "max_activation_advance_bonus_in": 0.0
        if LEGACY_CORE_SELFPLAY
        else _max_activation_advance_bonus_in(special_rules, grants, game_system, faction),
    }


def profiles_from_army_forge_json(
    data: dict[str, Any], faction: str, player: int
) -> dict[str, dict[str, Any]]:
    """The testable core: an already-parsed Army-Forge list dict + the
    faction name a real list's FILENAME would have supplied -> one profile
    dict per unit key, keyed exactly like battle_sim.gd's header (unit_id).
    """
    game_system = str(data.get("gameSystem", "gf"))
    built = _units_from_list(data, player)
    # NML-1152 step 6c — the manifest base override rides the table's spawn
    # order (opr_army_manager.gd:296): after the parse, before any shape read
    # (`base_radius` below). Inert while the bundled manifest carries no
    # `base_mm` entries; digest-neutral by construction then.
    _apply_manifest_base_overrides(built, faction)
    _expand_auras(built)
    return {u["unit_id"]: _unit_profile(u, faction, game_system) for u in built}


def selections_from_army_forge_json(
    data: dict[str, Any], player: int
) -> dict[str, tuple[str, str]]:
    """The `(selection_id, join_to_unit)` pair per unit key — what
    `battle_sim.gd:1352-1369` reads off each `GameUnit`'s
    `OPRApiClient.OPRUnit` source_data to derive hero attachment (NML-1081).

    They come back HERE instead of riding the profile because an act corpus
    header's `profiles` dict is compared field for field (M3-3), and a new key
    would be a new field. Keys and order are `profiles_from_army_forge_json`'s;
    a combined-in partner is folded into its host and has no key of its own,
    exactly as `OPRArmyManager` gives it no `GameUnit`."""
    return {
        u["unit_id"]: (u["selection_id"], u["join_to_unit"])
        for u in _units_from_list(data, player)
    }


def profiles_from_list(path: str | Path, player: int) -> dict[str, dict[str, Any]]:
    """The M3-3 gate entry point: an Army-Forge list JSON FILE + its player
    seat (1 or 2, matching core_selfplay.gd's army1/army2) -> one profile
    dict per unit key. `profiles_from_list(p1) | profiles_from_list(p2)`
    reproduces an act-corpus header's "profiles" dict field for field."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return profiles_from_army_forge_json(data, _faction_from_path(path), player)

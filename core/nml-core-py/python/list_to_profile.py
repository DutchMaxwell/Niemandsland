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
  * move_bands only ever needs the NAME-based Fast/Slow/Rapid Rush/Quick/
    Rapid Advance fallback (movement_range_controller.gd's description pass
    and RulesRegistry data-alias pass both read unit_properties keys this
    loader never sets — "rule_descriptions" / registry lookups keyed by
    game_system+faction_folder). Empirically 0 of 101 corpus units need the
    registry pass; a future faction whose special rules ARE registry
    aliases (Scurry, Highborn, ...) would need that pass ported too.

Two more fields — shooting_range_bonus and max_activation_advance_bonus_in —
are stamped here too, always 0 / 0.0. Current main's `_unit_profile`
(battle_sim.gd:1573) no longer carries them (M2-5b moved them into the
per-ACTIVATION dynamic profile, unit_profile_dyn); the 4 pre-M2-5b games in
the M3-0 oracle corpus were recorded before that split and still carry them
in their header. Both read SoloController.shooting_range_bonus/
max_activation_advance_bonus_in, which only fire for RulesRegistry-driven
rules (Royal Legion, Bounding) absent from every one of the 44 special rules
across all 8 oracle games — so 0/0.0 is exactly what a full port would
compute here too, not a shortcut that happens to pass.
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


def _move_bands(special_rules: list[str]) -> dict[str, float]:
    """movement_range_controller.gd:move_bands_for_props, restricted to the
    NAME-based fallback pass (see module docstring for why the description
    and registry passes are always no-ops for this loader's units)."""
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
    return {"advance": float(max(0, advance)), "rush": float(max(0, rush))}


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
    branch, off the longer edge."""
    bases = ud.get("bases") or {}
    if not isinstance(bases, dict):
        bases = {}
    if game_system == "aofr" and _is_usable_base_value(bases.get("square", "")):
        _, w, d = _parse_base_size(bases.get("square", ""), 25)
        return {"is_oval": False, "width_mm": _clamp_mm(w), "depth_mm": _clamp_mm(d)}
    if _is_usable_base_value(bases.get("round", "")):
        is_oval, w, d = _parse_base_size(bases.get("round", ""), DEFAULT_BASE_MM)
        return {"is_oval": is_oval, "width_mm": _clamp_mm(w), "depth_mm": _clamp_mm(d)}
    tough = _tough_from_rules(rules)
    if tough < 3:
        return {"is_oval": False, "width_mm": DEFAULT_BASE_MM, "depth_mm": DEFAULT_BASE_MM}
    verdict = _classify_big_model(str(ud.get("name", "")), int(ud.get("size", 1)), tough)
    if verdict == "vehicle":
        w, d = _vehicle_base_mm(tough)
        return {"is_oval": True, "width_mm": _clamp_mm(w), "depth_mm": _clamp_mm(d)}
    if verdict == "artillery":
        w, d = _artillery_base_mm(tough)
        return {"is_oval": True, "width_mm": _clamp_mm(w), "depth_mm": _clamp_mm(d)}
    if verdict in ("walker", "monster"):
        mm = _clamp_mm(_walker_base_mm(tough))
        return {"is_oval": False, "width_mm": mm, "depth_mm": mm}
    mm = _clamp_mm(_base_size_from_tough(tough))  # large infantry / cavalry
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
        "move_bands": _move_bands(special_rules),
        "base_radius": (DEFAULT_BASE_MM / 2.0) * MM_TO_METERS
        if LEGACY_CORE_SELFPLAY
        else _base_radius_m(u["base"], u["model_tough"][0] if u["model_tough"] else 1),
        "game_system": game_system,
        "faction_folder": faction,
        "item_grants": _flatten_grants(u["item_grants"]),
        "attached_hero_rules": [],
        # legacy fields — see module docstring ("Two more fields")
        "shooting_range_bonus": 0,
        "max_activation_advance_bonus_in": 0.0,
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

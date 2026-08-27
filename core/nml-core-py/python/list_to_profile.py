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

  * base_radius is ALWAYS 32 mm (0.016 m) — the loader never copies the
    list's own "bases" field onto unit_properties, so SeparationChecker's
    shape builder always falls through to its DEFAULT_BASE_MM. This is a
    property of TODAY'S trainer, not a game rule; NML-1073 M3-8+ may need a
    real base-size reader once the trainer's units carry positions/spacing.
  * item_grants and attached_hero_rules are ALWAYS empty — item-granted
    rules and live hero attachment are both import-path/MP-only features
    this loader never wires (NML-1081).
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
import re
from pathlib import Path
from typing import Any

# separation_checker.gd / opr_army_manager.gd constants (base-radius fallback)
DEFAULT_BASE_MM = 32
MM_TO_METERS = 0.001

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


def _is_weapon_profile_token(token: str) -> bool:
    """core_selfplay.gd:_is_weapon_profile_token — a weapon PROFILE token
    always declares attacks ("A2") and/or a range ("24\"" / "Range...")."""
    return re.search(r'^A\d+$|\d"$|^Range\b', token) is not None


def _rules_in_upgrade_label(label: str) -> list[str]:
    """core_selfplay.gd:_rules_in_upgrade_label — the rule names an upgrade
    OPTION's label grants, e.g. "Archivist (Caster(2))" -> ["Caster(2)"].
    Split at TOP-LEVEL commas so "Caster(1)"'s own parens stay intact; a
    weapon-swap label (any split token looks like a weapon profile) grants
    nothing here."""
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


def _base_radius_m(base_mm: int = DEFAULT_BASE_MM) -> float:
    """separation_checker.gd:shape_for_model, the round-base branch with
    model_tough == 1 (this loader never enlarges a model's base): radius =
    (base_mm / 2) in metres, no Tough up-scaling. `base_mm` is a parameter
    (not baked in) so the M3-3 red proof can flip it to prove the gate."""
    return (base_mm / 2.0) * MM_TO_METERS


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
    units: dict[str, dict] = {}
    by_sel: dict[str, dict] = {}
    order: list[str] = []
    uidx = 0

    def append_selection(u: dict, ud: dict) -> None:
        rules: list[str] = u["special_rules"]
        for su in ud.get("selectedUpgrades", []):
            option = su.get("option", {})
            for rl in _rules_in_upgrade_label(str(option.get("label", ""))):
                if rl not in rules:
                    rules.append(rl)
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
        rules: list[str] = []
        for r in ud.get("rules", []):
            rn = _rule_label(r)
            if rn:
                rules.append(rn)
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
            "weapons": [],
            "model_tough": [],
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
        "base_radius": _base_radius_m(),
        "game_system": game_system,
        "faction_folder": faction,
        "item_grants": [],
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

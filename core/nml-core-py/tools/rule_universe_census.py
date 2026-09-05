"""Rule universe census (PLAN A1, 2026-08-31): every army-book rule name vs
every layer that must know it.

Walks the private army-book snapshot (`--books <dir>` with `gf/` and `aof/`
subdirectories; never committed, never embedded) and cross-references each
distinct rule name against the four layers that must know it:

  1. registry  - the table registry's data (scripts/solo/rules_registry.gd):
                 the system's assets/solo/rules_mechanics_<system>.json, over
                 the common block plus every faction block. Reports the entry's
                 `primitive`; an entry with `"primitive": null` is registered
                 but unautomated (UNMAPPED-registered - rules_registry.gd:
                 has_primitive is false for it); no entry at all = UNMAPPED.
  2. mechanics - does any entry for the name exist in that map at all?
  3. core      - the fast core (core/nml-core/src/*.rs; rules.rs itself is the
                 lookup/parser twin and carries no resolver arms):
                   PORTED  - the name's own token is in non-test code (always
                             trusted), OR its primitive's token is AND (for a
                             primitive listed in CONSUMED_PARAM_KEYS) the
                             entry's own params include a consumed role. A
                             primitive not in that table is trusted whole;
                   STAMPED - the primitive token is there (the class is
                             recognised) but this entry's params map to none
                             of its consumed roles - stamped, read by nobody
                             (PR #489's finding: a shared primitive's token
                             alone over-credits every name under it);
                   PARTIAL - no arm, but the effect reaches the core only
                             through a precomputed channel: the loader's
                             MOVE_PRIMITIVES move-band pass (list_to_profile.py)
                             or the conditional-AP pass (an entry param
                             `condition`/`on6_ap`);
                   MISSING - no evidence (noted when Rust docs name it).

     A port PR for a shared "class" primitive (one resolver arm, params vary
     per entry) MUST add its consumed param keys to CONSUMED_PARAM_KEYS below
     - a live rule GRANT's name does not need hand-listing, it is read off
     the `*::granted(state, i, "X")` call sites (consumed_grant_names).
     Skipping this reopens #489's bug for the next primitive.
  4. encoder   - a slot in data/encoder_rule_vocab_v1.json (v5, unit band or
                 weapon band).

PRIVATE-SAFE: the books are read at runtime from wherever `--books` points;
nothing about their content is baked into this file. Outputs carry rule names
and faction names only - safe to run against the private snapshot.

RED knob `--hide <primitive>`: every name aliased to that primitive loses its
primitive-derived port evidence; the core-ported covered count must drop by
exactly the names that were ported through it. One line proves the counter is
live.

Exit code is 0 whenever the census ran (this is an instrument, not a gate);
usage errors exit 2.
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SYSTEMS = ("gf", "aof")

STATUS_RANK = {"PORTED": 3, "STAMPED": 2, "PARTIAL": 1, "MISSING": 0, "N/A": -1}

# Names that are census hygiene, not porting targets (SPEC_block_C_next_
# 2026-09-02.md's "Census hygiene, not ports" bullet). A MISSING verdict on
# these reads as "still to port", which is false for both: Unique is
# list-building only (rules_registry.gd never reads it at runtime, so no
# resolver arm will ever exist for it); Swift's whole effect (params:
# {"negates": "Slow"}) is already baked into the move value the loader
# computes per-unit BEFORE the core ever runs (list_to_profile.py's
# move-band pass resolves Fast/Slow/Quick/... and their negations into one
# static `mv` field - Swift is consumed there, not at runtime, so it is not
# itself a MOVE_PRIMITIVES entry and would never earn PARTIAL either).
# Rank -1 so real evidence elsewhere always outranks N/A if this table and
# reality ever disagree.
NA_NAMES: dict[str, str] = {
    "Unique": "list-building only, no in-game effect (not a porting target)",
    "Swift": "already folded into the loader's move-band pass"
             " (negates Slow before the core ever runs)",
}

# Primitive -> the registry param keys a resolver on this core actually
# reads for it (see the module docstring). Absent = trusted whole.
CONSUMED_PARAM_KEYS: dict[str, frozenset[str]] = {
    # mods.rs/sim.rs (#489): dice.rs sums hit_mod into to-hit (shoot+melee);
    # sim.rs sums morale_mod. casting_mod/def_mod/ap_mod/move_mod/
    # range_bonus_in are recorded, read by nothing on this core.
    # Closure audit (rules-wave3-utilbuff4, 2026-09-05) of the 16 names the
    # #694 follow-up measured STAMPED: nothing added, deliberately. The
    # grant-only entries' records land in the ledger (sim.rs::record_buff)
    # but their nine granted names (Dangerous/Difficult Terrain, Slow, Fast,
    # Swift, Entrenched, Rapid Advance, Rapid Rush, Rapid Charge) are read at
    # NO granted()/granted_vs() call site; casting_mod is recorded but
    # Role::Casting (mods.rs) is never summed; defense_mod/def_mod, ap_mod,
    # move_mod and range_bonus_in are not modeled on unit.rs's UtilityBuff,
    # so record_buff drops the all-zero row. The pick gates (range_in/
    # target/needs_los/max_targets/once/beneficiary) are read only to shape
    # the pick, never the effect - listing one would flip all 16 while their
    # effects stay unread, the exact #489 shape this table exists to prevent.
    "Utility Buff": frozenset({"hit_mod", "morale_mod"}),
    # Block B6: unit.rs::stamp reads `extra_attack` to route a Surge entry
    # into `surge_attack`/`surge_attack_low` (dice.rs::surge_attack_hits, both
    # resolve functions). melee_only/shooting_only are the alias loop's own
    # facet gate; the epoch-3 surge-gates port reads the plain auto-hit form's
    # `within_in` (Point-Blank Surge, ai_ev.gd:228-231) and the Boosts'
    # `over_in` (Devout/Ferocious/Lucky Boost, ai_ev.gd:243-244 -> dice.rs's
    # epoch-gated surge block). `surge_low` is deliberately NOT listed: the
    # resolver reads it only off `upgrades`-carrying entries, and the one
    # upgrades-less carrier that prints it (Great Sergeant) is dead data in
    # the TABLE's own stamp loop — listing it would over-credit that name's
    # printed 5-6 form, the exact #489 shape. The bonus_hits_per_six-only
    # names (Brutal, Devout, Lucky, Surge Mark, Surge when Shooting, Great
    # Sergeant) stay UNREAD as params — the table reads no param of theirs, so
    # neither does the twin — but the surge2 wave (2026-09-04) ports each BY
    # NAME: unit.rs::build_for's epoch-4 named arm (rule_on(rules_epoch, 4),
    # the literal) re-states the plain auto-hit facet the generic walk gives
    # them, so the names reach the core through their own tokens. Without this
    # entry "Surge" was TRUSTED WHOLE — PR #489's bug, reopened here until now.
    "Surge": frozenset({"extra_attack", "melee_only", "shooting_only", "within_in", "over_in"}),
    # Block B7: `unit::growth_of` stamps `UnitStatic.growth` off every "Growth
    # Markers" entry the unit carries, and `sim::growth_bonus_of` folds the
    # AP/hit facets into the tray (main.gd:4287/:5675-5680). The
    # rules-wave3-growthmark epoch-6 wave consumes the rest: the marker-gain
    # triggers (`per_round`/`on_kill` were already read by
    # `sim::growth_round_start`/`growth_on_kill`, `max_markers` caps them) and
    # the four new facets — Defensive Frenzy/Growth's `defense_per_marker`/
    # `defense_per_two` (sim::growth_defense_of -> dice.rs save target),
    # Fortified Growth's `enemy_ap_per_two` (defender-side AP cut) and
    # Regenerative Strength's `on_ignore_wound`/`attacks_per_marker`
    # (sim::growth_on_ignore_wound / melee_parts). `min_ap`/`all_models`/
    # `scope` stay unread on this core (the floor is the hard 0 every entry
    # prints; the whole-unit gates are implicit in the marker fold), so a
    # floor-only entry would still ride STAMPED.
    "Growth Markers": frozenset({"ap_per_marker", "ap_per_two", "hit_per_marker", "hit_per_two",
        "per_round", "max_markers", "on_kill",
        "defense_per_marker", "defense_per_two", "enemy_ap_per_two",
        "on_ignore_wound", "attacks_per_marker"}),
    # Block B13: unit.rs::retaliate_hits_per_wound reads `hits_per_wound` into
    # Ctx.retaliate_hits_per_wound (sim.rs::strike_phase lash-back). "rating"
    # stays unread on this core (the shipped "X" string falls back to the
    # rating itself).
    "Retaliate": frozenset({"hits_per_wound"}),
    # Block B12: unit.rs::unpredictable_shooting_params (via ctx_for) + dice.rs
    # ::resolve_volley_with_tray read the shooting volley die's three params.
    "Unpredictable Shooter": frozenset({"ap_bonus", "hit_bonus", "low_roll_max"}),
    # Block B10: unit.rs::regen_targets reads `ignore_target` (and the spell
    # twin `ignore_target_spell`) off the whole-unit "Resistance" entry into
    # Ctx.regen_target / Ctx.regen_target_spell — consumed by
    # dice.rs::regen_batch, combat.rs's unsaved folds and spell.rs's
    # spell-wound leg; `all_models` is the whole-unit gate itself.
    "Resistance": frozenset({"ignore_target", "ignore_target_spell", "all_models"}),
    # Block B9: deployment.rs::deploy_side reads the registry's `place_in`
    # (UnitSpec.place_in_m via list_to_profile.py:_deploy_flags — the table's
    # `unit_param(unit, "Vanguard", "place_in", 9.0)`, solo_controller.gd:9627)
    # as the Vanguard push band (vanguard_push, the 100/75/50/25 % ladder).
    # Every Vanguard-primitive entry (Vanguard, Fanatic, Drakesworn) carries
    # place_in; without this entry the primitive was TRUSTED WHOLE, so all
    # three names rode the bare 'vanguard' field token — PR #489's
    # over-credit shape, reopened by the #481 parity wave until now.
    "Vanguard": frozenset({"place_in"}),
    # NML-1152 B14 step 1: unit.rs::UnitStatic.bounding reads the named
    # "Bounding" entry's own `place_d3_plus` (the DATA-alias family stays
    # table-only, ported instead through the RECORDED `Action::traced` draw).
    "Bounding": frozenset({"place_d3_plus"}),
    # Block B11: unit.rs::UnitStatic.quick_shot_active reads `shoot_after_rush` as a whole-unit gate for sim.rs's RUSH+shoot predicate.
    "Quick Shot": frozenset({"shoot_after_rush"}),
    # Ambush arrival S6: the twin's arrive_one leg reads `min_enemy_dist_in`
    # (unit.rs:1553-1556 -> deployment.rs::arrive_one's own_ring_m), so the
    # primitive is no longer trusted whole. Without this entry Surprise Attack
    # (same primitive; its GF/AoF params carry no consumed key - the registry
    # itself marks its arrival_strike "planned") rode the bare 'infiltrate'
    # token to PORTED - the #489 over-credit shape, declined by the spec (§6).
    "Infiltrate": frozenset({"min_enemy_dist_in"}),
    # Rung C data port (AUDIT_armybook_flanks_2026-09-02.md): unit.rs's
    # `stealth_alias_of` is a genuine per-entry DATA-ALIAS loop (scans every
    # carried rule, keeps the best `hit_penalty` off any OTHER entry whose own
    # primitive is "Stealth") — the same shape as Infiltrate/Bounding above,
    # just never given a CONSUMED_PARAM_KEYS row before this port. Screened is
    # its first alias to actually exist in the registry.
    "Stealth": frozenset({"hit_penalty"}),
    # Rung C data port: unit.rs's `banner_bonus_of` is the same kind of
    # generic DATA-ALIAS loop for `morale_bonus`, feeding `CaptureReads` —
    # Courageous is its first alias.
    "Banner": frozenset({"morale_bonus"}),
    # Wave 3 "Boost Aura" family (rules-wave3-aura3): unit.rs::aura_grant_pairs
    # reads `grants` off every "X Boost Aura" entry (epoch-6 gated) and hands
    # the base rule to the unit directly; the import expansion stays, the
    # fallback. `scope` documents the reach; only `grants` is consumed.
    "Aura": frozenset({"grants"}),
    # Regeneration-family DATA-ALIAS wave (2026-09-03, rules-wave-regen):
    # unit.rs::regen_targets folds every carried entry whose primitive is
    # "Regeneration" into Ctx.regen_target / Ctx.regen_target_spell — the
    # table's own coverage wave (main.gd:6637-6652,
    # RulesRegistry.unit_rules_of_primitive(target, "Regeneration")). Reads
    # `ignore_target` / `ignore_target_spell` off the entry and `all_models`
    # as the whole-unit gate; `upgrades` / `uses_per_game` /
    # `terrain_within_in` / `spell_only` are unread — the table's alias
    # layer reads none of them either. Whole-by `rules_epoch >= 3`
    # (acts::CURRENT_RULES_EPOCH). Without this row the primitive is trusted
    # whole for the twelve names under it — the #489 over-credit shape.
    "Regeneration": frozenset({"ignore_target", "ignore_target_spell", "all_models"}),
    # Bane family port (rules-wave-bane, 2026-09-03): unit.rs
    # ::stamp_unit_strikers' epoch-gated ladder mirrors main.gd's
    # `_solo_striker_has_bane` — the Bane-prefixed names by scope suffix, and
    # the DATA-ALIAS wave (Bestial, Mischievous, Scrapper — non-"Bane",
    # non-"Aura") gated on the entry's own `reroll_save_sixes`. The Boost
    # variants' 5-6 extension (reroll_save_low/reroll_save_from, over_in) is
    # read by nobody on this core — those entries stay STAMPED.
    "Bane": frozenset({"reroll_save_sixes"}),
    # Shred-family wave: unit.rs::stamp's Shred data-alias arm (the table's
    # main.gd:3001/:4355 `unit_rule_active(member, "Shred") or
    # _solo_shred_facet_applies`) reads the scope pair per profile via
    # facet_applies — that is what separates the scoped halves ("Shred in
    # Melee"/"when Shooting") from the ungated aliases. The base wound
    # amount IS consumed as of the shred3 wave (2026-09-05): unit.rs
    # ::build_for's epoch-6 arm (`rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`,
    # frozen) reads `extra_wound_per_save_one` off the entry — facet-scoped
    # onto every shred_alias profile — and dice.rs::save_batch multiplies
    # the per-face amount by it, so Warbound/Infected/Destroyer leave the
    # STAMPED verdict their hard-coded +1 earned under the wave-1 alias.
    # The Boost entries' widened save-fail
    # window IS consumed as of the shred2 wave (2026-09-04): unit.rs::stamp's
    # upgrades arm (6b) reads `save_fail_max` / `extra_wound_save_low` (one
    # meaning, two key spellings) plus `over_in` off the entry, gating on the
    # model also carrying the `upgrades` base rule, and dice.rs's volley
    # consumes the window behind `rule_on(rules_epoch, 4)` past the entry's
    # own `over_in` distance (melee never widens — no pre-charge gap).
    "Shred": frozenset({"melee_only", "shooting_only", "save_fail_max", "extra_wound_save_low", "over_in", "extra_wound_per_save_one"}),
    # Lacerate-family wave (rules-wave2-lacerate2, 2026-09-04): unit.rs
    # ::stamp_unit_strikers' epoch-4 arm mirrors main.gd:6990-7001's unit-level
    # coverage wave — every carried Lacerate-primitive entry whose params carry
    # `bypass_regen` stamps the profile bane flag, facet-scoped by melee_only/
    # shooting_only ("Ignores Regeneration" ungated, "… in Melee" melee-only).
    # The plain "Lacerate" name keeps its own-token PORTED through the
    # weapon-level literal read (unit.rs::base_profile) regardless of params.
    "Lacerate": frozenset({"bypass_regen", "melee_only", "shooting_only"}),
    # Ambush family (rules-wave2-ambush, 2026-09-04): unit.rs
    # ::ambush_family_of reads each name at its OWN literal, gated
    # `rule_on(rules_epoch, 4)` — "Ambushing Piercing Shot"'s counts_as (+
    # its name-literal arrival-round AP(+1), consumed by dice.rs's volley
    # fold via sim::ctx_live), "Ambush Beacon"'s beacon_in and "Rapid
    # Ambush"'s arrive_from_round (both consumed by the core-py
    # arrival_reads export), "Ambush Re-Deployment"'s re_reserve/
    # uses_per_game (stamped; the once-per-game withdraw beat is a future
    # port). Without this row the primitive is trusted whole for every name
    # under it — the #489 over-credit shape.
    "Ambush": frozenset({"counts_as", "beacon_in", "arrive_from_round", "re_reserve", "uses_per_game"}),
    # Ranged-Shrouding family wave (rules-wave3-rangeshroud, 2026-09-05):
    # unit.rs::ranged_shroud_params (epoch-6 arm) reads the carried entry's
    # own `range_penalty_in`/`floor_in` off the literal name AND every alias
    # whose primitive is "Ranged Shrouding" (Darkborn, Shadowborn, Wild Veil
    # and their Boosts), mirroring SoloController.ranged_shroud_reach_in's
    # coverage wave (solo_controller.gd:5651-5660). The melee half of the
    # composite aliases was already consumed pre-wave by unit.rs
    # ::melee_shroud_params' own alias walk (`move_penalty_in` on the
    # Melee-Shrouding primitive, `melee_move_penalty_in`/`melee_floor_in` on
    # the composite Ranged-Shrouding entries, `floor_in` as the fallback
    # floor). Without this row the primitive is trusted whole for every name
    # under it — the #489 over-credit shape.
    "Ranged Shrouding": frozenset(
        {"range_penalty_in", "floor_in", "move_penalty_in", "melee_move_penalty_in", "melee_floor_in"}
    ),
    # Piercing Hunter family wave (rules-wave3-piercehunt, 2026-09-05): the
    # three ported names (Piercing Hunter, Havocbound, Piercing Shooter) ride
    # their OWN tokens — unit.rs::build_for's epoch-6 named arm (frozen
    # EPOCH_6_TABLE_RULES) states each spelling literally and the dice folds
    # log the named forms. Deliberately NO CONSUMED_PARAM_KEYS row here: the
    # conditional-AP class's params are uniform across every entry
    # (ap_bonus/condition on all of them), so a row would over-credit the two
    # UNPORTED members (Point-Blank Piercing needs a `within_in` cap the
    # CondAp spec does not carry; Havocbound Boost needs an always-on leg +
    # the `upgrades` coupling the stamp pass does not read) — the #489
    # over-credit shape, declined.
    # Royal Legion family (rules-wave3-royallegion, 2026-09-05): unit.rs
    # ::royal_legion_family_of folds every carried Royal Legion-primitive
    # entry's two live halves — `range_bonus_in` (the _shooting_range_bonus
    # alias-max) and `charge_mod` (the move-band pass's flat rush fold,
    # MOVE_PRIMITIVES carrying "Royal Legion") — and the primitive-NULL
    # "Lustbound Boost Aura" rides its base through the raw-name expansion
    # arm. `upgrades` stays unread: neither twin's band or range pass reads
    # it either (the move_rule_mods precedent).
    "Royal Legion": frozenset({"range_bonus_in", "charge_mod"}),
}


def base_rule_name(rule: str) -> str:
    """rules_registry.gd:base_rule_name - "Tough(3)" -> "Tough" (also strips
    the " (spell)" grant mark: everything before the first paren, trimmed)."""
    return rule.strip().split("(")[0].strip()


def snake_variants(name: str) -> set[str]:
    """Token forms a Rust arm could use for `name`: "Hit & Run" ->
    {"hit_and_run", "hitrun"}; "Counter-Attack" -> {"counter_attack",
    "counterattack"}; single words stay single words."""
    s = name.lower()
    s = re.sub(r"\s*&\s*", " and ", s)
    parts = [p for p in re.split(r"[^a-z0-9]+", s) if p]
    if not parts:
        return set()
    return {"_".join(parts), "".join(parts)}


# ------------------------------------------------------------------ books


# AUDIT_armybook_flanks_2026-09-02.md sec.3 (C-1): a book carries rule
# occurrences under both keys - `specialRules` on units/weapons/upgrades,
# and `rules` for the shared `_common.json` core-rulebook glossary (Limited,
# Reliable, Banner, Transport, ... - ten names that live ONLY there). Walk
# both so the universe covers every layer the books actually use.
RULE_LIST_KEYS = ("specialRules", "rules")


def walk_rule_names(node, out: list) -> None:
    """Every `specialRules` or `rules` array anywhere in the JSON - units,
    weapons, upgrades, the shared `_common.json` glossary, wherever they
    nest - contributes one sighting per entry."""
    if isinstance(node, dict):
        for key in RULE_LIST_KEYS:
            rules = node.get(key)
            if isinstance(rules, list):
                for entry in rules:
                    if isinstance(entry, dict):
                        name = base_rule_name(str(entry.get("name", "")))
                        if name:
                            out.append(name)
        for value in node.values():
            walk_rule_names(value, out)
    elif isinstance(node, list):
        for item in node:
            walk_rule_names(item, out)


def load_books(books_dir: Path) -> list[dict]:
    """Each book: {faction, system, names[]}. A `_common`-style shared file
    (no `specialRules`) now contributes its `rules[]` core glossary instead
    of nothing."""
    books = []
    for system in SYSTEMS:
        for path in sorted((books_dir / system).glob("*.json")):
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError) as exc:
                print(f"warning: unreadable book {path.name}: {exc}", file=sys.stderr)
                continue
            names: list = []
            walk_rule_names(data, names)
            books.append(
                {
                    "faction": str(data.get("name") or path.stem),
                    "system": str(data.get("gameSystem") or system),
                    "names": names,
                }
            )
    return books


# ------------------------------------------------------------------ registry


def load_mechanics(repo: Path, system: str) -> dict:
    """name -> {primitives: set, entry: bool, cond_ap: bool} over the common
    block plus every faction block of rules_mechanics_<system>.json (an absent
    file is the registry's empty map: data refines, never breaks)."""
    path = Path(repo) / "assets" / "solo" / f"rules_mechanics_{system}.json"
    info: dict = {}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return info
    blocks = [data.get("common") or {}]
    blocks += list((data.get("factions") or {}).values())
    for block in blocks:
        if not isinstance(block, dict):
            continue
        for name, entry in block.items():
            slot = info.setdefault(
                name, {"primitives": set(), "entry": False, "cond_ap": False,
                       "param_keys": set(), "vs_target": False, "grants_rule_values": set()}
            )
            slot["entry"] = True
            primitive = entry.get("primitive") if isinstance(entry, dict) else None
            if isinstance(primitive, str) and primitive:
                slot["primitives"].add(primitive)
            params = entry.get("params") if isinstance(entry, dict) else None
            if isinstance(params, dict) and ("condition" in params or "on6_ap" in params):
                slot["cond_ap"] = True
            if isinstance(params, dict):
                slot["param_keys"].update(params.keys())
                if params.get("vs_target"):
                    slot["vs_target"] = True
                grant = params.get("grants_rule")
                if isinstance(grant, str) and grant:
                    slot["grants_rule_values"].add(grant)
    return info


def load_vocab(repo: Path) -> dict:
    path = Path(repo) / "data" / "encoder_rule_vocab_v1.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {"unit": set(), "weapon": set()}
    return {
        "unit": set(data.get("unit") or []),
        "weapon": set(data.get("weapon") or []),
    }


def move_primitives(repo: Path) -> set:
    """The loader's move-band pass primitives, parsed from
    list_to_profile.py:MOVE_PRIMITIVES - never hard-coded here."""
    path = Path(repo) / "core" / "nml-core-py" / "python" / "list_to_profile.py"
    try:
        text = path.read_text()
    except OSError:
        return set()
    m = re.search(r"MOVE_PRIMITIVES\s*=\s*\(([^)]*)\)", text, re.S)
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))


GRANTED_CALL_RE = re.compile(r'granted\([^()\n]*"([^"\n]+)"[^()\n]*\)')


def consumed_grant_names(repo: Path) -> set[str]:
    """Every literal rule name a `*::granted(state, i, "X")` call checks in
    core/nml-core/src (rules.rs excluded) - read off the Rust source, never
    hand-listed."""
    names: set[str] = set()
    src = Path(repo) / "core" / "nml-core" / "src"
    for path in sorted(src.rglob("*.rs")):
        if path.name == "rules.rs":
            continue
        try:
            text = path.read_text()
        except OSError:
            continue
        names.update(base_rule_name(m) for m in GRANTED_CALL_RE.findall(text))
    return names


# ------------------------------------------------------------------ rust scan

CFG_TEST_RE = re.compile(r"#\s*\[\s*cfg\s*\(\s*test")
RAW_STR_RE = re.compile(r'r(#*)"')


def scan_rust_file(path: Path) -> tuple[dict, list]:
    """One .rs file -> ({token: (relpath, line)}, [comment texts]).

    Tokens are the lowercased identifiers of non-comment, non-test code plus
    the snake forms of its string literals: a resolver arm shows up as the
    primitive's name (a rules_of_primitive call site), a field, or a literal.
    #[cfg(test)] regions are skipped - a test literal is not a resolver arm.
    Raw strings, // and (nested) /* */ comments are handled; single quotes
    (lifetimes, char literals) stay code, which can add a stray 1-char token
    at worst - no rule name is 1 char."""
    tokens: dict = {}
    comments: list = []
    try:
        text = path.read_text()
    except OSError:
        return tokens, comments
    rel = path.relative_to(path.parents[3]).as_posix()

    i, n = 0, len(text)
    line = 1
    depth = 0
    skip_depth: int | None = None
    buf: list = []

    def flush(end_line: int) -> None:
        if buf:
            tokens.setdefault("".join(buf).lower(), (rel, end_line))
            buf.clear()

    def record_literal(literal: str, at_line: int) -> None:
        for variant in snake_variants(literal):
            tokens.setdefault(variant, (rel, at_line))

    while i < n:
        c = text[i]
        if c == "\n":
            flush(line)
            line += 1
            i += 1
            continue
        if skip_depth is None:
            if c == "#":
                m = CFG_TEST_RE.match(text, i)
                if m:
                    flush(line)
                    skip_depth = depth
                    i = m.end()
                    continue
            if c.isalpha() or c == "_" or (buf and c.isdigit()):
                buf.append(c)
                i += 1
                continue
            flush(line)
            if c == '"':
                j = i + 1
                while j < n and text[j] != '"':
                    if text[j] == "\\":
                        j += 1
                    elif text[j] == "\n":
                        line += 1
                    j += 1
                record_literal(text[i + 1 : min(j, n)], line)
                i = j + 1
                continue
            if c == "r":
                m = RAW_STR_RE.match(text, i)
                if m:
                    closer = '"' + m.group(1)
                    end = text.find(closer, m.end())
                    literal = text[m.end() : end if end >= 0 else n]
                    record_literal(literal, line)
                    line += literal.count("\n")
                    i = (end + len(closer)) if end >= 0 else n
                    continue
            if c == "/" and i + 1 < n and text[i + 1] == "/":
                j = text.find("\n", i)
                comments.append((rel, line, text[i : j if j >= 0 else n]))
                i = j if j >= 0 else n
                continue
            if c == "/" and i + 1 < n and text[i + 1] == "*":
                nest, j = 0, i
                while j < n:
                    if text.startswith("/*", j):
                        nest += 1
                        j += 2
                    elif text.startswith("*/", j):
                        nest -= 1
                        j += 2
                        if nest == 0:
                            break
                    else:
                        if text[j] == "\n":
                            line += 1
                        j += 1
                comments.append((rel, line, text[i:j]))
                i = j
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
            continue
        # inside a #[cfg(test)] region: parse structure, record nothing
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = j if j >= 0 else n
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            nest, j = 0, i
            while j < n:
                if text.startswith("/*", j):
                    nest += 1
                    j += 2
                elif text.startswith("*/", j):
                    nest -= 1
                    j += 2
                    if nest == 0:
                        break
                else:
                    if text[j] == "\n":
                        line += 1
                    j += 1
            i = j
            continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                elif text[j] == "\n":
                    line += 1
                j += 1
            i = j + 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth <= skip_depth:
                skip_depth = None
        i += 1
    flush(line)
    return tokens, comments


def scan_rust(repo: Path) -> tuple[dict, list]:
    """All of core/nml-core/src except rules.rs - the lookup/parser twin has no
    resolver arms, only the data-driven lookup every arm shares."""
    tokens: dict = {}
    comments: list = []
    src = Path(repo) / "core" / "nml-core" / "src"
    for path in sorted(src.rglob("*.rs")):
        if path.name == "rules.rs":
            continue
        t, c = scan_rust_file(path)
        for k, v in t.items():
            tokens.setdefault(k, v)
        comments.extend(c)
    return tokens, comments


def comment_index(comments: list) -> str:
    """One lowercase string of all Rust comments with (file:line) markers, so
    a doc-mention lookup is one substring search per rule name."""
    parts = []
    for rel, _line, ctext in comments:
        parts.append(ctext.replace("\x00", "").lower())
        parts.append(f"\x00{rel}:{_line}\n")
    return "".join(parts)


def mention_of(name: str, joined: str) -> str | None:
    idx = joined.find(name.lower())
    if idx < 0:
        return None
    end = joined.find("\x00", idx)
    if end < 0:
        return None
    nl = joined.find("\n", end)
    return joined[end + 1 : nl if nl >= 0 else len(joined)]


def is_consumed(primitive: str, name: str, mech: dict, consumed_grants: set) -> bool:
    """Does THIS entry's own param evidence map to a role a resolver reads?
    `primitive` is a CONSUMED_PARAM_KEYS key by construction here (see
    core_status_for's prim_hit) - an untracked primitive is no longer
    trusted whole (AUDIT_armybook_flanks_2026-09-02.md sec.8's spot-check:
    Sturdy Boost/Shielded, Ignores Regeneration/Lacerate, Vale
    Oath/Battleborn and Ambushing Piercing Shot/Ambush all rode a bare
    literal-gate or an unrelated string/field reuse to PORTED)."""
    roles = CONSUMED_PARAM_KEYS.get(primitive)
    if roles is None:
        return False
    if roles & mech.get("param_keys", set()):
        return True
    if mech.get("vs_target"):
        implied = name[: -len(" Mark")] if name.endswith(" Mark") else name
        if base_rule_name(implied) in consumed_grants:
            return True
    return any(base_rule_name(g) in consumed_grants for g in mech.get("grants_rule_values", set()))


def core_status_for(name: str, mech: dict, tokens: dict, bands: set, hide: str | None,
                     consumed_grants: set):
    """(status, note) for one (name, system)."""
    if name in NA_NAMES:
        return "N/A", NA_NAMES[name]
    prims = set(mech.get("primitives", set()))
    variants = snake_variants(name)
    if hide and hide in prims:
        prims.discard(hide)
        variants -= snake_variants(hide)
    name_hit = None
    for v in sorted(variants):
        if v in tokens:
            name_hit = (v, tokens[v])
            break
    # C-2 (AUDIT_armybook_flanks_2026-09-02.md sec.8): a primitive-token
    # match is only real alias evidence for a vetted CONSUMED_PARAM_KEYS
    # class - an untracked primitive's token is, as often as not, an
    # exact-literal gate or an unrelated string/field on that SAME-NAMED
    # rule, which no alias can ever reach (Shielded/Battleborn/Lacerate/
    # Ambush - none are CONSUMED_PARAM_KEYS classes).
    prim_hit = None
    for p in sorted(prims & CONSUMED_PARAM_KEYS.keys()):
        for v in sorted(snake_variants(p)):
            if v in tokens:
                prim_hit = (p, v, tokens[v])
                break
        if prim_hit:
            break
    if name_hit or prim_hit:
        if name_hit:
            v, where = name_hit
            return "PORTED", f"name token '{v}' at {where[0]}:{where[1]}"
        p, v, where = prim_hit
        note = f"primitive '{p}' token '{v}' at {where[0]}:{where[1]}"
        if is_consumed(p, name, mech, consumed_grants):
            return "PORTED", note
        return "STAMPED", note + " (recognised; no resolver reads a consumed param on this entry)"
    notes = []
    if prims & bands:
        notes.append("move-band pass only")
    if mech.get("cond_ap"):
        notes.append("conditional-AP pass (EV path) only")
    if notes:
        return "PARTIAL", " + ".join(notes)
    return "MISSING", ""


def build_universe(books: list[dict]) -> dict:
    universe: dict = {}
    for book in books:
        s = book["system"]
        if s not in SYSTEMS:
            continue
        for name in book["names"]:
            u = universe.setdefault(
                name,
                {"systems": set(), "occ": 0, "occ_by_system": {}, "factions_by_system": {}},
            )
            u["systems"].add(s)
            u["occ"] += 1
            u["occ_by_system"][s] = u["occ_by_system"].get(s, 0) + 1
            u["factions_by_system"].setdefault(s, set()).add(book["faction"])
    return universe


def build_rows(universe, mechanics, tokens, bands, vocab, mentions, hide=None,
                consumed_grants: set | None = None) -> dict:
    rows = {}
    AURA_SUFFIX = " Aura"

    def one_system(name, s, u):
        mech = mechanics[s].get(
            name, {"primitives": set(), "entry": False, "cond_ap": False}
        )
        status, note = core_status_for(name, mech, tokens, bands, hide, consumed_grants or set())
        if status == "MISSING":
            where = mention_of(name, mentions)
            if where:
                note = (note + "; " if note else "") + f"named in Rust docs ({where})"
        # the HIDDEN copy, not the raw map: the label must reflect the RED
        # knob's discard, or the "X Aura" pass-2 below still sees a mapped
        # entry and inherits its base's status instead of the UNMAPPED cap.
        label_prims = set(mech["primitives"])
        if hide and hide in label_prims:
            label_prims.discard(hide)
        primitives = sorted(label_prims)
        primitive_label = (
            "|".join(primitives)
            if primitives
            else ("UNMAPPED-registered" if mech["entry"] else "UNMAPPED")
        )
        band = (
            "unit" if name in vocab["unit"]
            else ("weapon" if name in vocab["weapon"] else "")
        )
        return {
            "primitive": primitive_label,
            "mechanics_entry": mech["entry"],
            "cond_ap_param": mech["cond_ap"],
            "core": status,
            "core_note": note,
            "aura_live": False,
            "encoder_slot": bool(band),
            "encoder_band": band,
        }

    # Pass 1: every non-aura name. Pass 2: "X Aura" names - the import expands
    # them to X on both sides (opr_army_manager.gd:_expand_auras and the
    # loader's twin), so their core status is X's; their own mechanics entry
    # stays primitive-null BY DESIGN (that is why the label keeps the aura
    # pointer). Aura rule: an UNMAPPED-registered aura has no primitive and
    # therefore no params anyone reads, so the base's token alone caps it at
    # STAMPED - never PORTED by token sharing - unless its OWN full-name
    # token (snake variants of the aura name) is non-test core evidence.
    # An aura whose base is not itself a book rule stays as judged.
    for name, u in universe.items():
        if name.endswith(AURA_SUFFIX):
            continue
        rows[name] = {
            "systems": sorted(u["systems"]),
            "occ": u["occ"],
            "occ_by_system": dict(u["occ_by_system"]),
            "factions_by_system": {s: sorted(f) for s, f in u["factions_by_system"].items()},
            "per_system": {s: one_system(name, s, u) for s in sorted(u["systems"])},
        }
    for name, u in universe.items():
        if not name.endswith(AURA_SUFFIX):
            continue
        base = name[: -len(AURA_SUFFIX)]
        per_system = {}
        for s in sorted(u["systems"]):
            ps = one_system(name, s, u)
            base_row = rows.get(base)
            if base_row is not None and s in base_row["per_system"]:
                base_ps = base_row["per_system"][s]
                unmapped_reg = ps["primitive"] == "UNMAPPED-registered"
                if unmapped_reg and ps["core"] == "PORTED":
                    # own full-name token in non-test core: the one way an
                    # UNMAPPED-registered name may read PORTED
                    ps["core_note"] = (
                        f"aura of '{base}' (expanded at import): {ps['core_note']}"
                    )
                elif unmapped_reg and base_ps["core"] == "PORTED":
                    # PORTED means CONSUMED: this entry has no primitive, so
                    # no params anyone reads - the base's token is not its own.
                    # The name is still LIVE through the import expansion
                    # (opr_army_manager.gd:2117 / list_to_profile.py:350), so
                    # it is flagged on its own line, never folded into
                    # core-ported (the #489/#517 invariant stays untouched).
                    ps["core"] = "STAMPED"
                    ps["aura_live"] = True
                    ps["core_note"] = (
                        f"aura of '{base}' (expanded at import): base is PORTED"
                        f" ({base_ps['core_note']}) but this entry is"
                        f" UNMAPPED-registered - no params anyone reads"
                        f" (aura rule: capped at STAMPED; LIVE via the import"
                        f" expansion — opr_army_manager.gd:2117 /"
                        f" list_to_profile.py:350)"
                    )
                else:
                    ps["core"] = base_ps["core"]
                    ps["core_note"] = (
                        f"aura of '{base}' (expanded at import): {base_ps['core_note']}"
                    )
            elif base in universe:
                ps["core_note"] = (
                    f"aura of '{base}' (expanded at import); base not a book rule"
                    f" in this system"
                )
            per_system[s] = ps
        rows[name] = {
            "systems": sorted(u["systems"]),
            "occ": u["occ"],
            "occ_by_system": dict(u["occ_by_system"]),
            "factions_by_system": {s: sorted(f) for s, f in u["factions_by_system"].items()},
            "per_system": per_system,
        }
    return rows


def parse_audit(path: Path | None) -> dict:
    """The known MISSING rows of plans/RULES_AUDIT_2026-08-31.md: the GF sec.3
    table rows and the AoF sec.4 hard-zero primitive list. Lenient - a file
    that does not parse yields empty lists, never a crash."""
    out = {"gf": [], "aof": []}
    if path is None:
        return out
    try:
        text = path.read_text()
    except OSError:
        return out
    for m in re.finditer(r"^\|\s*\d+\s*\|\s*\*\*(.+?)\*\*", text, re.M):
        name = re.sub(r"\s*\(.*$", "", m.group(1)).strip()
        if name and name not in out["gf"]:
            out["gf"].append(name)
    lines = text.splitlines()
    for idx, ln in enumerate(lines):
        if "**Hard zero" in ln:
            for follow in lines[idx + 1 : idx + 4]:
                if follow.startswith(("- ", "|", "#")) or not follow.strip():
                    continue
                for piece in follow.split(","):
                    name = piece.strip().rstrip(".").strip()
                    if name and not name.startswith("*") and name not in out["aof"]:
                        out["aof"].append(name)
                break
            break
    return out


def best_core(row: dict) -> str:
    return max(
        (ps["core"] for ps in row["per_system"].values()),
        key=lambda st: STATUS_RANK[st],
    )


def summarize(rows: dict) -> dict:
    def count(pred) -> int:
        return sum(1 for r in rows.values() if pred(r))

    summary = {
        "total": len(rows),
        "registry_primitive": count(
            lambda r: any(
                not ps["primitive"].startswith("UNMAPPED")
                for ps in r["per_system"].values()
            )
        ),
        "mechanics_entry": count(
            lambda r: any(ps["mechanics_entry"] for ps in r["per_system"].values())
        ),
        "core_ported": count(lambda r: best_core(r) == "PORTED"),
        "core_stamped": count(lambda r: best_core(r) == "STAMPED"),
        "core_partial": count(lambda r: best_core(r) == "PARTIAL"),
        "core_missing": count(lambda r: best_core(r) == "MISSING"),
        # census hygiene (NA_NAMES): not a porting target, so not counted in
        # any ported/unported bucket above and excluded from the denominator
        # summary_lines prints for them (core_ported_denominator below).
        "core_na": count(lambda r: best_core(r) == "N/A"),
        "aura_live": count(
            lambda r: any(ps["aura_live"] for ps in r["per_system"].values())
        ),
        "encoder_slot": count(
            lambda r: any(ps["encoder_slot"] for ps in r["per_system"].values())
        ),
        "all_layers": count(
            lambda r: all(
                not ps["primitive"].startswith("UNMAPPED")
                and ps["mechanics_entry"]
                and ps["core"] == "PORTED"
                and ps["encoder_slot"]
                for ps in r["per_system"].values()
            )
        ),
    }
    # The ported/unported ratio's own denominator: total minus the N/A
    # (census-hygiene) names, so 212/442 with 2 N/A names reads 212/440,
    # never 212/442 - a stale denominator would silently count Unique and
    # Swift as still-unported.
    summary["core_ported_denominator"] = summary["total"] - summary["core_na"]
    by_system = {}
    for s in SYSTEMS:
        sub = [(n, r) for n, r in rows.items() if s in r["per_system"]]
        by_system[s] = {
            "names": len(sub),
            "registry_primitive": sum(
                1 for _n, r in sub if not r["per_system"][s]["primitive"].startswith("UNMAPPED")
            ),
            "mechanics_entry": sum(1 for _n, r in sub if r["per_system"][s]["mechanics_entry"]),
            "core_ported": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "PORTED"),
            "core_stamped": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "STAMPED"),
            "core_partial": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "PARTIAL"),
            "core_missing": sum(1 for _n, r in sub if r["per_system"][s]["core"] == "MISSING"),
            "encoder_slot": sum(1 for _n, r in sub if r["per_system"][s]["encoder_slot"]),
        }
    summary["by_system"] = by_system
    return summary


def ranked_lists(rows: dict) -> dict:
    """Core-MISSING and core-PARTIAL names per system, ranked by occurrences
    in that system (the BLOCK B port order)."""
    out = {}
    for s in SYSTEMS:
        buckets = {"MISSING": [], "PARTIAL": []}
        for name, r in rows.items():
            ps = r["per_system"].get(s)
            if ps is None or ps["core"] not in buckets:
                continue
            buckets[ps["core"]].append(
                {
                    "name": name,
                    "occ": r["occ_by_system"].get(s, 0),
                    "primitive": ps["primitive"],
                    "mechanics_entry": ps["mechanics_entry"],
                    "encoder_slot": ps["encoder_slot"],
                    "factions": len(r["factions_by_system"].get(s, [])),
                    "note": ps["core_note"],
                }
            )
        for bucket in buckets.values():
            bucket.sort(key=lambda e: (-e["occ"], e["name"]))
        out[s] = buckets
    return out


def compute_offenders(books: list[dict], rows: dict) -> list:
    """Factions ranked by unported occurrences (core != PORTED), worst rules
    attached - the BLOCK B per-faction port list."""
    out = []
    for book in books:
        if book["system"] not in SYSTEMS:
            continue
        per_name: dict = {}
        for name in book["names"]:
            per_name[name] = per_name.get(name, 0) + 1
        unported = []
        for name, occ in per_name.items():
            row = rows.get(name)
            if row is None:
                continue
            st = row["per_system"].get(book["system"], {}).get("core", "MISSING")
            if st not in ("PORTED", "N/A"):
                unported.append({"name": name, "core": st, "occ": occ})
        unported.sort(key=lambda e: (-e["occ"], e["name"]))
        out.append(
            {
                "faction": book["faction"],
                "system": book["system"],
                "occ_total": sum(per_name.values()),
                "occ_unported": sum(u["occ"] for u in unported),
                "worst": unported[:5],
            }
        )
    out.sort(key=lambda f: (-f["occ_unported"], f["faction"]))
    return out


def reconcile_audit(audit: dict, rows: dict, tokens: dict) -> list:
    """Each audit row -> the census's own finding for the names (or primitives)
    it names. CONFIRMED = census agrees MISSING; CHANGED = ported on this tree;
    mechanic rows have no book rule name and are judged by core token evidence."""
    findings = []
    for system in ("gf", "aof"):
        for row_name in audit.get(system, []):
            alias = row_name.split("/")[0].strip()
            finding = {
                "system": system,
                "audit_row": row_name,
                "audit_claim": "MISSING",
                "matches": [],
                "core_token": [],
                "verdict": "",
            }
            names = set()
            for n in rows:
                if n.lower() == row_name.lower() or n.lower() == alias.lower():
                    names.add(n)
                for ps in rows[n]["per_system"].values():
                    if alias.lower() in [p.lower() for p in ps["primitive"].split("|")]:
                        names.add(n)
            for n in sorted(names):
                r = rows[n]
                for s in sorted(r["per_system"]):
                    ps = r["per_system"][s]
                    if (
                        n.lower() == row_name.lower()
                        or n.lower() == alias.lower()
                        or alias.lower() in [p.lower() for p in ps["primitive"].split("|")]
                    ):
                        finding["matches"].append(
                            {"name": n, "system": s, "occ": r["occ_by_system"].get(s, 0), "core": ps["core"]}
                        )
            for v in sorted(snake_variants(row_name)):
                if v in tokens:
                    w = tokens[v]
                    finding["core_token"].append(f"{v} at {w[0]}:{w[1]}")
            if not finding["core_token"]:
                # mechanic-row fallback: the row's leading word may still name
                # real core code ("split fire" -> the split_plan arm, NML-1150)
                first = re.split(r"[^a-z0-9]+", alias.lower())[0]
                if first and first in tokens and len(first) > 3:
                    w = tokens[first]
                    finding["core_token"].append(f"first-word '{first}' at {w[0]}:{w[1]}")
            statuses = {m["core"] for m in finding["matches"]}
            if "PORTED" in statuses:
                finding["verdict"] = "CHANGED - ported on this tree"
            elif "PARTIAL" in statuses:
                finding["verdict"] = "PARTIAL on this tree"
            elif statuses:
                finding["verdict"] = "CONFIRMED missing"
            elif finding["core_token"]:
                finding["verdict"] = "mechanic row - no book rule name; core token present"
            else:
                finding["verdict"] = "mechanic row - no book rule name, no core token"
            findings.append(finding)
    return findings


# ------------------------------------------------------------------ outputs


def git_head(repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10, check=False,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def census(books_dir: Path, repo: Path, hide: str | None = None,
           audit_path: Path | None = None) -> dict:
    books = load_books(books_dir)
    if not books:
        raise SystemExit(f"no books found under {books_dir}/gf|aof")
    mechanics = {s: load_mechanics(repo, s) for s in SYSTEMS}
    tokens, comments = scan_rust(repo)
    mentions = comment_index(comments)
    bands = move_primitives(repo)
    vocab = load_vocab(repo)
    consumed_grants = consumed_grant_names(repo)
    universe = build_universe(books)
    rows = build_rows(universe, mechanics, tokens, bands, vocab, mentions,
                       consumed_grants=consumed_grants)
    summary = summarize(rows)
    result = {
        "meta": {
            "generated": datetime.datetime.now().isoformat(timespec="seconds"),
            "repo": str(repo),
            "head": git_head(repo),
            "books": len(books),
            "books_by_system": {
                s: sum(1 for b in books if b["system"] == s) for s in SYSTEMS
            },
            "books_dir": str(books_dir),
            "hide": hide,
            "audit": str(audit_path) if audit_path else "",
            "tool": "core/nml-core-py/tools/rule_universe_census.py",
            "method": {
                "walk": "specialRules[].name and rules[].name over every book JSON, recursive; base = name before '('",
                "core_ported": "name token, or a CONSUMED_PARAM_KEYS-consumed primitive-param, in non-test core/nml-core/src code beyond rules.rs",
                "core_stamped": "primitive token present but this entry's params map to no CONSUMED_PARAM_KEYS role - recognised, not read",
                "core_partial": "move-band pass primitive (list_to_profile.py:MOVE_PRIMITIVES) or conditional-AP entry param",
                "core_missing": "no token evidence; 'named in Rust docs' when a comment mentions it",
            },
        },
        "summary": summary,
        "rows": rows,
        "ranked": ranked_lists(rows),
        "offenders": compute_offenders(books, rows),
        "audit_rows": parse_audit(audit_path),
        "audit_reconciliation": reconcile_audit(parse_audit(audit_path), rows, tokens),
        "red": None,
    }
    if hide:
        before = summary["core_ported"]
        rows_hidden = build_rows(universe, mechanics, tokens, bands, vocab, mentions, hide,
                                  consumed_grants)
        after = summarize(rows_hidden)["core_ported"]
        direct = {
            n for n, r in rows.items()
            if any(
                hide.lower() in [p.lower() for p in ps["primitive"].split("|")]
                for ps in r["per_system"].values()
            )
        }
        # "X Aura" names ride their base through the import-time expansion, so
        # hiding a primitive drops them too when the base is aliased.
        aliased = set(direct)
        for n in rows:
            if n.endswith(" Aura") and n[:-5] in direct and n[:-5] in universe:
                aliased.add(n)
        ported_aliased = sum(1 for n in aliased if best_core(rows[n]) == "PORTED")
        result["red"] = {
            "primitive": hide,
            "before": before,
            "after": after,
            "drop": before - after,
            "aliased": len(aliased),
            "ported_aliased": ported_aliased,
            "ok": (before - after) == ported_aliased,
            "aliased_names": sorted(aliased),
        }
    return result


def summary_lines(res: dict) -> list[str]:
    s = res["summary"]
    t = s["total"]
    pd = s["core_ported_denominator"]
    consumed, stamped = s["core_ported"], s["core_stamped"]
    lines = [
        f"RULES-COVERAGE registry-primitive : {s['registry_primitive']}/{t}",
        f"RULES-COVERAGE mechanics-entry    : {s['mechanics_entry']}/{t}",
        f"RULES-COVERAGE core-ported        : {consumed}/{pd}"
        f"  (STAMPED: {stamped}, PARTIAL: {s['core_partial']}, MISSING: {s['core_missing']},"
        f" N/A: {s['core_na']} excluded from {pd})",
        f"RULES-COVERAGE consumed vs stamped: consumed {consumed}/{pd}"
        f" · stamped-only {stamped} · missing {pd - consumed - stamped}",
        f"RULES-COVERAGE encoder-slot       : {s['encoder_slot']}/{t}",
        f"RULES-COVERAGE all-layers         : {s['all_layers']}/{t}",
        f"RULES-COVERAGE aura-granted       : {s['aura_live']}/{t}"
        f"  (base PORTED, live through the import expansion;"
        f" NOT counted as core-ported)",
    ]
    for system in SYSTEMS:
        b = s["by_system"][system]
        n = b["names"]
        lines.append(
            f"RULES-COVERAGE {system} : names {n} - registry {b['registry_primitive']}/{n},"
            f" mechanics {b['mechanics_entry']}/{n}, core {b['core_ported']}/{n},"
            f" encoder {b['encoder_slot']}/{n}"
        )
    if res.get("red"):
        r = res["red"]
        lines.append(
            f"RED --hide {r['primitive']}: core-ported {r['before']} -> {r['after']}"
            f" (drop {r['drop']}); {r['primitive']} aliases: {r['aliased']}"
            f" (ported before: {r['ported_aliased']})"
            f" -> drops exactly its rules: {'OK' if r['ok'] else 'VIOLATION'}"
        )
    return lines


def _cell(value: str) -> str:
    return str(value).replace("|", "/")


def markdown_report(res: dict) -> str:
    s = res["summary"]
    t = s["total"]
    meta = res["meta"]
    out = [
        "# RULE COVERAGE 2026-08-31 - the rule universe vs every layer (PLAN A1)",
        "",
        f"Generated {meta['generated']} from {meta['repo']} @ {meta['head']};"
        f" {meta['books']} books ({meta['books_by_system'].get('gf', 0)} GF,"
        f" {meta['books_by_system'].get('aof', 0)} AoF) at `{meta['books_dir']}`"
        " (private snapshot, read at runtime only).",
        "",
        "## Summary",
        "",
        "```",
    ]
    out += summary_lines(res)
    out += ["```", "", "Board row RULES-COVERAGE = the core-ported line.", ""]

    out += [
        "## Method",
        "",
        "- Walk: every `specialRules[].name` or `rules[].name` in each book"
        " JSON (recursive, so units/weapons/upgrades and the shared"
        " `_common.json` core-rulebook glossary all count); base name ="
        " text before the first `(` (the registry's own `base_rule_name`).",
        "- Registry/mechanics: the system's `rules_mechanics_<system>.json`,"
        " common + faction blocks. `primitive: null` = registered but"
        " unautomated (UNMAPPED-registered).",
        f"- Core PORTED: name token, or a `CONSUMED_PARAM_KEYS`-consumed"
        f" registry-primitive param, in non-test `core/nml-core/src` code."
        f" STAMPED: the primitive token is there, but this entry's own"
        f" params map to no consumed role. PARTIAL: only the loader's"
        f" move-band pass (`MOVE_PRIMITIVES`) or the conditional-AP entry"
        f" param reaches the core. MISSING: nothing.",
        "- Aura rule: an \"X Aura\" rides its base's import-time expansion,"
        " but an UNMAPPED-registered aura (primitive null) has no params"
        " anyone reads, so the base's token alone leaves it capped at"
        " STAMPED - never PORTED by token sharing - unless the aura's own"
        " full-name token (snake variants of the aura name) is core"
        " evidence.",
        "- Aura-granted: an \"X Aura\" reads \"this model and its unit get"
        " X\"; both the table (opr_army_manager.gd:394) and the loader"
        " (list_to_profile.py:1367) expand it to X at import, so an aura"
        " whose base is PORTED is live even though its own entry consumes"
        " nothing - counted on the separate aura-granted line, never folded"
        " into core-ported.",
        "- Encoder: a slot in `data/encoder_rule_vocab_v1.json` (unit or weapon band).",
        f"- N/A: census hygiene, not a porting target ({', '.join(sorted(NA_NAMES))}) -"
        f" excluded from the core-ported ratio's denominator, never counted"
        f" MISSING or as a faction offender.",
        "",
    ]

    if res.get("red"):
        r = res["red"]
        out += [
            "## RED proof",
            "",
            f"`--hide {r['primitive']}` forces every alias of the known-ported"
            f" primitive **{r['primitive']}** to lose its primitive-derived port"
            f" evidence. Core-ported covered count: {r['before']} -> {r['after']}"
            f" (drop {r['drop']}); the primitive aliases {r['aliased']} rule"
            f" names, {r['ported_aliased']} of them were PORTED before."
            f" **Drops exactly its rules: {'OK' if r['ok'] else 'VIOLATION'}**"
            f" - the covered count is live, not decorative.",
            "",
        ]

    for system in SYSTEMS:
        rows = res["ranked"][system]["MISSING"]
        out += [
            f"## Core-MISSING - {system.upper()}, ranked by occurrences ({len(rows)} names)",
            "",
            "| # | rule | occ | registry primitive | mechanics | encoder | factions |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for i, e in enumerate(rows, 1):
            out.append(
                f"| {i} | {e['name']} | {e['occ']} | {_cell(e['primitive'])} |"
                f" {'yes' if e['mechanics_entry'] else 'no'} |"
                f" {'yes' if e['encoder_slot'] else 'no'} | {e['factions']} |"
            )
        out.append("")

    partial = sorted(
        (e for system in SYSTEMS for e in res["ranked"][system]["PARTIAL"]),
        key=lambda e: -e["occ"],
    )
    out += [
        f"## PARTIAL - reaches the core only through a precomputed channel ({len(partial)} names)",
        "",
        "| # | rule | system | occ | registry primitive | via | encoder |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for i, e in enumerate(partial[:40], 1):
        system = "gf" if e in res["ranked"]["gf"]["PARTIAL"] else "aof"
        out.append(
            f"| {i} | {e['name']} | {system} | {e['occ']} | {_cell(e['primitive'])} |"
            f" {_cell(e['note'])} | {'yes' if e['encoder_slot'] else 'no'} |"
        )
    out.append("")

    offenders = res["offenders"]
    out += [
        "## Worst factions by unported occurrences",
        "",
        "| # | faction | system | unported occ / total | worst rules (occ) |",
        "| --- | --- | --- | --- | --- |",
    ]
    for i, f in enumerate(offenders[:15], 1):
        worst = ", ".join(f"{w['name']} ({w['occ']})" for w in f["worst"][:4])
        out.append(
            f"| {i} | {f['faction']} | {f['system']} |"
            f" {f['occ_unported']}/{f['occ_total']} | {worst} |"
        )
    out.append("")

    out += [
        "## Reconciliation vs plans/RULES_AUDIT_2026-08-31.md",
        "",
        "| audit row | system | audit claim | census finding | verdict |",
        "| --- | --- | --- | --- | --- |",
    ]
    for f in res["audit_reconciliation"]:
        if f["matches"]:
            finding = "; ".join(
                f"{m['name']} [{m['system']} x{m['occ']}]: {m['core']}"
                for m in f["matches"][:4]
            )
        elif f["core_token"]:
            finding = "; ".join(f["core_token"][:2])
        else:
            finding = "-"
        out.append(
            f"| {f['audit_row']} | {f['system']} | {f['audit_claim']} |"
            f" {_cell(finding)} | {f['verdict']} |"
        )
    out.append("")

    out += [
        f"## Full matrix ({t} names)",
        "",
        "| rule | systems | occ | registry primitive | mechanics | core | encoder |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name in sorted(res["rows"]):
        r = res["rows"][name]
        per = r["per_system"]
        prim_vals = {ps["primitive"] for ps in per.values()}
        primitive = next(iter(prim_vals)) if len(prim_vals) == 1 else (
            " / ".join(f"{s}: {ps['primitive']}" for s, ps in sorted(per.items()))
        )
        core_vals = {ps["core"] for ps in per.values()}
        core = next(iter(core_vals)) if len(core_vals) == 1 else (
            " / ".join(f"{ps['core']}({s})" for s, ps in sorted(per.items()))
        )
        mech = "yes" if any(ps["mechanics_entry"] for ps in per.values()) else "no"
        enc = "yes" if any(ps["encoder_slot"] for ps in per.values()) else "no"
        out.append(
            f"| {name} | {'+'.join(r['systems'])} | {r['occ']} |"
            f" {_cell(primitive)} | {mech} | {core} | {enc} |"
        )
    out.append("")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Rule universe census (PLAN A1): army-book rule names vs"
        " registry, fast core and encoder vocab."
    )
    ap.add_argument("--books", required=True,
                    help="directory with gf/ and aof/ book JSONs (private; read-only)")
    ap.add_argument("--repo", default=str(REPO),
                    help="openTTS checkout providing assets/, data/, core/ (default: this repo)")
    ap.add_argument("--hide", default=None, metavar="PRIMITIVE",
                    help="RED knob: treat this known ported primitive as missing")
    ap.add_argument("--audit", default=None,
                    help="path to RULES_AUDIT_2026-08-31.md for the reconciliation section")
    ap.add_argument("--out-json", default=None, help="write the full census JSON here")
    ap.add_argument("--out-md", default=None, help="write the markdown report here")
    args = ap.parse_args(argv)
    try:
        res = census(
            Path(args.books), Path(args.repo), args.hide,
            Path(args.audit) if args.audit else None,
        )
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return 2
    for line in summary_lines(res):
        print(line)
    if args.out_json:
        out = Path(args.out_json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(res, indent=1) + "\n")
    if args.out_md:
        out = Path(args.out_md)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(markdown_report(res))
    return 0


if __name__ == "__main__":
    sys.exit(main())

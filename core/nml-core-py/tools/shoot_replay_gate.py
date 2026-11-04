"""GATE D1-B4 (NML-1073) — the TABLE's SHOOTING dice, act by act, roll by roll.

WHAT IS BEING GATED. `tools/arena_match.gd` plays on the real table and every
combat die leaves `_solo_tray_roll` (main.gd:7126-7180); D1-B1 taps that into
`dice.jsonl`, one line per roll with the activation ordinal on it. The fast
trainer had no damage dice at all — `sim.rs` filled an expected-value pool. B4
gives it the tray: `dice::resolve_shooting_with_tray` draws the hit dice, the
save batch, Bane's re-roll and the pooled Regeneration roll in the table's own
order, and the wounds then land through the trainer's OWN casualty machinery.

THE THREE CHECKS, on every act whose recorded pick is HOLD/ADVANCE with a shoot
target:

  STREAM — the tray is seeded with the game's `dice_seed` and BURNED forward to
  where this activation started (the sum of `maxi(1, count)` over every earlier
  recorded roll — main.gd:7152-7159's zero-die rule included). The resolver's
  rolls are then compared to the recorded ones tuple by tuple:
  (roll_kind, count, target, faces), EXACT. Faces can only agree if the draw
  ORDER and every die COUNT agree, which is why this one check carries the port.

  HITS — hits/blocks recomputed from the RECORDED faces at the RECORDED target
  (`DiceRules.count_successes`, dice_rules.gd:55-71) against the same numbers
  off the resolver's own roll. Redundant while STREAM is green, and the first
  thing left standing when it is not.

  NEXT STATE — the defender's `alive` and total wounds after the replayed
  activation against the recorded plain state of the NEXT act. Reported as
  measured, not asserted: the table can run further activations between two
  planner picks (a dry side hands the tail to the other), and those land on the
  same defender.

VERDICTS per act. `want` is EVERY roll the table drew under this activation
ordinal, never a prefix — truncating it would hide the case where the table drew
MORE than the port did:

  `full_equal`   — same number of rolls, every roll identical. THIS is the gate's
                   number, and the tool exits 1 while any act misses it (pass
                   `--report-only` to survey instead of gate).
  `prefix_equal` — the overlap held but the lengths differ. It splits into
                   `table_longer` (the table drew rolls the port did not — often
                   a LATER activation sharing the ordinal, because `move_act_seq`
                   bumps once per planner pick and a dry side hands the tail to
                   the other; benign but unproven) and `port_longer` (the port
                   drew rolls the table never did — never benign).
  `both_silent` / `table_silent` / `port_silent` — one side or both drew nothing.
                   These are classified and CLOSED; they never fall through into
                   the length or shape counters.
  `shape` / `faces` — a roll parted inside the overlap. `faces` after `shape`
                   held would mean the tray twin itself is wrong.

THE TWO REDS, and they are not equals:

  `--red-misseed` is the LOAD-BEARING one. It seeds the tray with `dice_seed + 1`
  and changes nothing else: every die count and every target still comes out of
  the same recorded state, so the shapes line up, the comparison REACHES the
  faces, and every act that rolls must part there. A green here would mean the
  faces are not actually being compared. The bar is stated in dice, not in acts:
  an activation of one or two dice CAN agree on a wrong seed by chance (1/6,
  1/36) and two of the 670 do, so the red holds when no act that staked MORE
  than two dice survived — and the surviving sizes are printed, not hidden.

  `--mode off` reruns the same acts down the expected-value path. It draws no
  dice at all, so it proves the REPORTING CHANNEL — that an absent stream is
  noticed — and nothing whatever about whether the faces are right.

    PYTHONPATH=<module> python core/nml-core-py/tools/shoot_replay_gate.py \\
        --ref ~/selfplay_out/qbd_ref --limit 3
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402

#: `AiPlanner` action kinds that shoot (`BattleSim.HOLD` / `.ADVANCE`).
SHOOTING_KINDS = (0, 1)

#: NML-1104: the RECORDED corpus's `roll_kind` now names the rule behind seven
#: special-rule dice that used to be lumped under the blanket "attack" —
#: morale, Fearless's recovery die, No Retreat, Regeneration, Ravage,
#: Battleborn, dangerous terrain (main.gd's `_solo_tray_roll` call sites).
#: `nml_core`'s own rolls (`core/nml-core/src/dice.rs`) still stamp all of
#: them "attack" — it has no matching split. Every reader here that compares
#: a recorded roll against the port's OWN roll positionally, `roll_kind`
#: included, folds the recorded side back through `combat_kind()` first, so
#: "kind" still means the same two-value thing on both sides of the compare.
_COMBAT_KIND = {
    "morale": "attack", "fearless": "attack", "no_retreat": "attack",
    "regeneration": "attack", "ravage": "attack", "battleborn": "attack",
    "dangerous": "attack",
}


def combat_kind(roll_kind: str) -> str:
    """`roll_kind` folded to the port's two-value scheme ("attack"/"defense")
    — see `_COMBAT_KIND`. A no-op for every kind the port already knows."""
    return _COMBAT_KIND.get(roll_kind, roll_kind)


def successes(faces, target: int) -> int:
    """`DiceRules.count_successes(faces, target, 0)` dice_rules.gd:55-71 — a 6
    always succeeds, a 1 always fails, everything else needs `>= target`."""
    if target <= 0:
        return 0
    return sum(1 for f in faces if f >= 6 or (f > 1 and f >= target))


def compared_target(kind: str, target: int) -> int:
    """The `target` a roll is COMPARED at (AI-G4F1, DIAG-PARITY D-A). A DEFENSE
    target reads clamped to 2..6: the core clamps the summed save target once
    (dice.rs `save_target(..).clamp(2, 6)`, `EPOCH_68_MODIFIER_SUM`), the table
    hands the tray the raw `base_defense + ap` (main.gd `_solo_tray_roll`). A 6
    always saves and a 1 always fails (`successes()`), so a 10+ blocks exactly
    the faces a 6+ does. Attack targets stay raw. Reports print the raw pair."""
    return min(max(target, 2), 6) if kind == "defense" else target


def parted_field(g: tuple, w: tuple) -> str | None:
    """The first of kind / count / target where the port's roll `g` and the
    recorded roll `w` part, the target read through `compared_target()`; None
    when they agree. Shared by both replay gates."""
    if g[0] != w[0]:
        return "kind"
    if g[1] != w[1]:
        return "count"
    if compared_target(g[0], g[2]) != compared_target(w[0], w[2]):
        return "target"
    return None


def read_game(d: Path) -> tuple[dict, list[dict], list[dict], int]:
    """(header, act lines, dice lines, dice_seed) of one recorded arena game.

    THE ACTIVATION ORDINAL, and it is the whole of this function. `dice.jsonl`
    stamps every roll with `solo_controller.move_act_seq()`, which bumps once per
    ACTIVATION — and an activation the planner did not pick (a dry side handing
    its tail to the other) writes a `kind:"auto"` line that bumps it too. Those
    lines carry their own `act`, and it equals their position in the INTERLEAVED
    act|auto stream: 1428 of 1428 auto lines in `~/selfplay_out/qbe_ref` do.

    Only the planner-picked `kind:"act"` lines can be replayed, so each one is
    stamped here with its interleaved position. Numbering the act lines among
    THEMSELVES — what this reader did before — slides every ordinal after the
    first auto activation, and from there on the tool compares each act against
    another activation's rolls. On `qbe_ref` that is not a rounding error: the
    same gate scores 15/669 acts FULL-equal counting act lines alone and 100/669
    counting interleaved positions, with `table_silent` falling 359 -> 91.
    """
    acts = [json.loads(x) for x in (d / "acts.jsonl").read_text().splitlines() if x.strip()]
    head = acts[0]
    lines = []
    for i, a in enumerate((x for x in acts[1:] if x.get("kind") in ("act", "auto")), 1):
        if a.get("kind") == "act":
            lines.append(dict(a, act=i))
    dice = [json.loads(x) for x in (d / "dice.jsonl").read_text().splitlines() if x.strip()]
    arena = next(d.glob("arena_*.json"))
    return head, lines, dice, int(json.loads(arena.read_text())["dice_seed"])


def burn_prefix(dice: list[dict]) -> list[int]:
    """Draws standing BEFORE each recorded roll. `maxi(1, count)`, so a zero-die
    roll costs one draw all the same (main.gd:7152-7159) — get this wrong and
    every face from that point on is off by one."""
    out, n = [], 0
    for r in dice:
        out.append(n)
        n += max(1, int(r["count"]))
    out.append(n)
    return out


def first_at_or_after(dice: list[dict], act: int) -> int:
    """Index of the first roll drawn at or after activation `act` — where the
    stream stood when that activation began, whether or not it rolled."""
    for i, r in enumerate(dice):
        if int(r["act"]) >= act:
            return i
    return len(dice)


def detach(plain: dict) -> dict:
    """`--hero-attach off` on a RECORDED state. The corpus is a table game, so
    every host already carries its `attached` heroes and every hero its
    `attached_to` — which is `hero_attach="table"`, and there is nothing to
    switch on. This strips the two fields instead, so the same acts replay the
    way a `hero_attach="off"` corpus would: the D1-B4b volley then finds no
    member but the host, exactly as `selfplay.play_game(hero_attach="off")`
    leaves it. It is the BEFORE half of the B4b measurement, in one tool."""
    out = dict(plain)
    units = {}
    for k, u in plain["units"].items():
        u = dict(u, attached=[], attached_to="")
        # `attached_hero_rules` (state.rs:71/:173) is the ONE profile field that
        # follows from attachment, and it rides the act's own `prof` block. Left
        # standing, a fallen-hero-less "off" control would still let the hero's
        # rules vote in `AiEv.rule_on_all_models` (ai_ev.gd:79-83) — the control
        # would not be a control.
        if isinstance(u.get("prof"), dict):
            u["prof"] = dict(u["prof"], attached_hero_rules=[])
        units[k] = u
    out["units"] = units
    return out


def detach_header(head: dict) -> dict:
    """The header's half of `--hero-attach off`: an act with no `prof` block
    falls back to the HEADER profile, so the same field has to go there too."""
    profiles = {k: dict(p, attached_hero_rules=[]) for k, p in head["profiles"].items()}
    return dict(head, profiles=profiles)


def defender_state(plain: dict, key: str) -> tuple[int, int]:
    """(alive, total wounds left) of one unit in a plain state."""
    u = plain["units"].get(key)
    if u is None:
        return (-1, -1)
    return (int(u["alive"]), int(sum(u["wounds"])))


def lone_hero_names(plain: dict, profiles: dict) -> dict[str, str]:
    """A LONE attached hero's NAME -> its HOST's name (G4-H6): the table signs
    the save with the host's label (G4-T2), the core with the hero's own. A
    lone hero's `attached_to` host has no living models; the hero still has."""
    units, out = plain.get("units") or {}, {}
    for key, u in units.items():
        host = u.get("attached_to")
        hu = units.get(host) if host else None
        if not hu or int(u.get("alive", 0)) <= 0 or int(hu.get("alive", 0)) > 0:
            continue
        hero = str((profiles.get(key) or {}).get("name", ""))
        hname = str((profiles.get(host) or {}).get("name", ""))
        if hero and hname:
            out[hero] = hname
    return out


def signer_ok(roller: str, table_label: str, lone: dict[str, str]) -> bool:
    """The table's label for the port's roller: the roller's own name, or - for a LONE hero (`lone_hero_names`) - its
    host's. Only ever a relaxation: a label that matched before still matches, so a lone hero that rolls under its own
    name (its own attack, a strike) cannot turn into a new `owner` failure."""
    return table_label in ("AI (%s)" % roller, "AI (%s)" % lone.get(roller, roller))


def shots_of(d: Path) -> dict[int, list[dict]]:
    """The table's own per-shot record — sidecar `shots.jsonl` (NML_SHOT_DUMP,
    written inside the per-shot loop of `_solo_resolve_ai_volley`, so per
    activation ordinal the lines stand in the table's resolve order): member,
    weapon, and the TARGET NAME that shot fired at. NML-1150's aiming oracle:
    acts.jsonl carries one `shoot` key and cannot hold per-weapon aims."""
    f = d / "shots.jsonl"
    if not f.exists():
        return {}
    out: dict[int, list[dict]] = {}
    for line in f.read_text().splitlines():
        if line.strip():
            s = json.loads(line)
            out.setdefault(int(s["act"]), []).append(s)
    return out


def _stale(units: dict, key: str) -> bool:
    """No living model on the unit AND none on a joined hero attached to it.
    A host wiped out under a still-standing hero is a legal shot (G4-H4)."""
    u = units.get(key, {})
    if int(u.get("alive", -1)) > 0:
        return False
    return not any(int(units.get(str(h), {}).get("alive", -1)) > 0
                   for h in (u.get("attached", []) or []))
#: AI-G4 H1b (lead ruling O3): the legs of an activation the core never rolls. The table rolls the cast die and
#: the spell's own saves and morale inside the act; the core prices a cast as an expectation (sim.rs `cast_phase`),
#: so the gate CUTS them. `dangerous` stays the core's. A roll without a `leg` (a recording from before H1a) is `main`.
CUT_LEGS = ("cast", "spell")


def read_pre(d: Path) -> dict[int, dict]:
    """{activation ordinal: {unit id: {alive, shaken}}} from the `kind:"pre"` lines of acts.jsonl (H1a, epoch 73+)."""
    out: dict[int, dict] = {}
    for x in (d / "acts.jsonl").read_text().splitlines():
        if '"pre"' in x:
            r = json.loads(x)
            if r.get("kind") == "pre":
                out[int(r["act"])] = r["units"]
    return out


def read_verbs(d: Path) -> dict[int, int]:
    """{activation ordinal: executed verb} from the `kind:"verb"` lines of acts.jsonl (F-HOLD-ADV, epoch 73+): the table's
    own gates turned the planner's pick into this verb (a planned Hold walked into range as an Advance), so the replay
    plays it. A recording from before the row has no such line and replays the pick."""
    out: dict[int, int] = {}
    for x in (d / "acts.jsonl").read_text().splitlines():
        if '"verb"' in x:
            r = json.loads(x)
            if r.get("kind") == "verb":
                out[int(r["act"])] = int(r["verb"])
    return out


#: `TerrainRules.gives_cover`: ruins and forest. `BASE_RIM_SAMPLES` of terrain_rules.gd.
COVER_TYPES, RIM_SAMPLES = (1, 2), 8


def majority_in_cover(u: dict, board, built: int) -> bool:
    """`_solo_majority_in_cover` on a unit's standing models: more than half of them FULLY inside cover terrain (centre
    + rim), a unit built with one model by its centre alone."""
    n = 0
    for p, r in zip(u["positions"], u["radii"]):
        r = float(r) if built > 1 else 0.0
        ring = [[p[0] + math.cos(math.tau * i / RIM_SAMPLES) * r, 0.0, p[2] + math.sin(math.tau * i / RIM_SAMPLES) * r]
                for i in range(RIM_SAMPLES)] if r > 0 else []
        n += all(board.type_at(q) in COVER_TYPES for q in [p, *ring])
    return n * 2 > len(u["positions"])


def patch_pre(plain: dict, units: dict, board=None) -> dict:
    """`plain` after the cast leg: every unit in `units` cut down to its recorded alive count (models dropped from the
    end of each per-model list) and carrying its recorded Shaken flag. With a `board` (F-PRE-COVER) a unit the leg cut
    down gets its `in_cover` read again from the survivors, as the table does per save moment."""
    out = dict(plain, units=dict(plain["units"]))
    for uid, rec in units.items():
        if uid not in out["units"]:
            continue
        u = dict(out["units"][uid], shaken=bool(rec["shaken"]))
        a0, a = int(u["alive"]), int(rec["alive"])
        if a < a0:
            for f in ("wounds", "radii", "positions", "kits"):
                if isinstance(u.get(f), list) and len(u[f]) == a0:
                    u[f] = u[f][:a]
            u["alive"] = a
            if board is not None and u.get("positions"):
                u["in_cover"] = majority_in_cover(u, board, a0)
        out["units"][uid] = u
    return out


def cut_pre_legs(rolls: list[dict], plain: dict, pre: dict | None, burn: bool = True,
                 patch: bool = True, board=None) -> tuple[list[dict], int, dict]:
    """(the act's rolls without the cast/spell legs, draws to burn off the tray for them, `plain` after the leg).
    Only a cast leg that LEADS the act is cut, and a leading dangerous test is cut with it (G4-H8: the table's order is
    dangerous test -> cast; both are burned as ONE prefix and the caller switches the core's own test off, see
    `cut_dangerous`). Any other roll in front of the cast would make the core draw between two stretches of one
    resolve, and a tray cannot be burned mid-resolve - such an act is left as recorded, and so is a dangerous test with
    no cast behind it (the core's own). `burn` / `patch` False are the two RED mutants (`--red-pre noburn|nopatch`)."""
    lead = 0
    while lead < len(rolls) and rolls[lead].get("leg") in CUT_LEGS + ("dangerous",):
        lead += 1
    casts = sum(r.get("leg") in CUT_LEGS for r in rolls)
    if casts == 0 or casts != sum(r.get("leg") in CUT_LEGS for r in rolls[:lead]):
        return rolls, 0, plain
    draws = sum(max(1, int(r["count"])) for r in rolls[:lead]) if burn else 0
    return rolls[lead:], draws, patch_pre(plain, pre or {}, board) if patch else plain


def cut_dangerous(rolls: list[dict], kept: list[dict]) -> bool:
    """True when `cut_pre_legs` took the table's dangerous test along with the cast leg (G4-H8): the tray has spent its
    dice, so the core must not roll a test of its own for this act (header knob `dangerous` off, then restored)."""
    return any(r.get("leg") == "dangerous" for r in rolls[:len(rolls) - len(kept)])


def lone_hero_of(units: dict, key: str) -> str:
    """AI-G4 F-AIM (epoch 73+): the table fires "at" a dead host while its joined hero stands - the hero is the unit
    now. `key` itself unless it has no living model and exactly one living attached hero; then that hero's key."""
    u = units.get(key, {})
    if int(u.get("alive", -1)) != 0:
        return key
    live = [str(h) for h in (u.get("attached", []) or []) if int(units.get(str(h), {}).get("alive", -1)) > 0]
    return live[0] if len(live) == 1 else key


def split_aim(head: dict, rec: list[dict], shoot_key: str, units: dict) -> tuple[list[dict] | None, str, int]:
    """The `split` aim for one act, or `(None, why, 0)` to stay pooled. A
    non-empty `target_id` that the header profiles carry is the unit key itself
    (G4-H4) and wins outright — two units can share a display NAME. Without
    one, the sidecar's target NAME becomes a unit key through the header
    profiles; a name sitting on more than one key is ambiguous and its entries
    are dropped (the count rides back as the third slot), never guessed. An aim
    whose entries all point at the recorded `shoot` key is the pre-1150 path and
    injects nothing. An aim naming a unit that is DEAD in the replayed state is
    a stale ordinal (the sidecar shares dice.jsonl's move_act_seq, which a dry
    side can hand to a later activation) — the whole aim is untrustworthy and
    injects nothing; a dead HOST with a living joined hero is still a legal
    shot (G4-H4)."""
    profiles = head["profiles"]
    name_keys: dict[str, list[str]] = {}
    for k, p in profiles.items():
        name_keys.setdefault(str(p.get("name", "")), []).append(k)
    aim, amb = [], 0
    for s in rec:
        tid = str(s.get("target_id", "") or "")
        keys = [tid] if tid and tid in profiles else name_keys.get(str(s.get("target", "")), [])
        if len(keys) == 1:
            aim.append({"member": str(s["member"]), "weapon": str(s["weapon"]),
                        "target": keys[0]})
        else:
            amb += 1
    if not aim:
        return None, "uncovered", amb
    if int((head.get("knobs") or {}).get("rules_epoch", 0)) >= 73:
        aim = [dict(a, target=lone_hero_of(units, a["target"])) for a in aim]
    if any(_stale(units, a["target"]) for a in aim):
        return None, "stale", amb
    if all(a["target"] == shoot_key for a in aim):
        return None, "aligned", amb
    return aim, ("reaim" if len({a["target"] for a in aim}) == 1 else "multi"), amb


#: PR #448's (NML-1103) merge commit — the fix that made conditional AP
#: (Shatter/Tear/Disintegrate/Melee Slayer/Piercing Assault/Piercing Hunter)
#: count the way the table resolves it. `vintage_knobs` asks git whether this
#: is an ancestor of a corpus's recorded commit pin, when one is available.
_COND_AP_FIX_COMMIT = "c94f825"


def vintage_knobs(header: dict, repo: str | Path | None = None) -> dict[str, bool]:
    """NML-1130 — the `{"engage_fold": bool, "cond_ap": bool}` this corpus was
    RECORDED under, read off its act header. Every gate's `--engage-fold
    auto` / `--cond-ap auto` (the default) resolves to this per game, so a gate
    replays a corpus against the KNOBS IT WAS RECORDED WITH instead of
    whatever the twin defaults to today.

    `engage_fold` (PR #446, D5-4 — the attached-hero fold of the engage test):
    `header["knobs"]["engage_fold"]` if the corpus stamps it; absent means the
    corpus predates the knob itself, so the table it was recorded on had no
    fold at all — OFF.

    `cond_ap` — True means "count conditional AP the corrected way", i.e.
    `LEGACY_NO_COND_AP` OFF. No corpus format field carries this yet (a
    companion PR, NML-1129, is to stamp `knobs.cond_ap` going forward; read
    here if present). Failing that, this looks for a recorded commit pin
    (`commit` / `base_commit` / `sha` / `base`, header-level or inside
    `knobs`) and asks git whether `_COND_AP_FIX_COMMIT` (#448) is an ancestor
    of it — recorded after the fix -> ON, before -> legacy OFF.

    FALLBACK, and it is a real gap, not a nicety: neither `qbf_ref` nor
    `qbg_ref` carries a commit pin — the farm scripts only ECHO their
    PIN_COMMIT into the CALLER's own up-log, never into the corpus itself —
    so this defaults `cond_ap` ON (today's silent reading) rather than the
    naive "absent -> legacy OFF" one. `qbg_ref` was recorded AFTER #448
    without a stamp, and the naive reading costs it 141 acts (NML-1128).
    `qbf_ref` PREDATES #448 without a pin either, and needs `--cond-ap off`
    explicit — this fallback cannot tell the two corpora apart."""
    knobs = header.get("knobs") or {}
    engage_fold = bool(knobs["engage_fold"]) if "engage_fold" in knobs else False

    if "cond_ap" in knobs:
        return {"engage_fold": engage_fold, "cond_ap": bool(knobs["cond_ap"])}

    commit = (header.get("commit") or header.get("base_commit") or header.get("sha")
              or header.get("base") or knobs.get("commit") or knobs.get("base_commit"))
    cond_ap = None
    if commit and repo:
        try:
            r = subprocess.run(
                ["git", "-C", str(repo), "merge-base", "--is-ancestor",
                 _COND_AP_FIX_COMMIT, str(commit)],
                capture_output=True, timeout=10, check=False)
            if r.returncode in (0, 1):
                cond_ap = r.returncode == 0
        except (OSError, subprocess.SubprocessError):
            cond_ap = None
    if cond_ap is None:
        cond_ap = True  # FALLBACK — see docstring
    return {"engage_fold": engage_fold, "cond_ap": cond_ap}


def resolve_vintage_flag(flag: str, header: dict, repo: str, key: str) -> bool:
    """One of `--engage-fold`/`--cond-ap`'s `auto`/`on`/`off` resolved for one
    game's header. `key` is `"engage_fold"` or `"cond_ap"`."""
    if flag == "on":
        return True
    if flag == "off":
        return False
    return vintage_knobs(header, repo)[key]


def vintage_report_line(seen: set[tuple[bool, bool]]) -> str:
    """One-line summary of the resolved `(engage_fold, cond_ap)` pairs a run
    saw across its games, for the report header line NML-1130 requires."""
    if len(seen) == 1:
        eng, cap = next(iter(seen))
        return "engage_fold=%s cond_ap=%s" % (eng, cap)
    return "engage_fold/cond_ap MIXED: %s" % ", ".join(
        "(engage_fold=%s cond_ap=%s)" % kv for kv in sorted(seen))


def run(ref: Path, repo: str, mode: str, limit: int, verbose: int, report_only: bool,
        hero_attach: str = "table", sighting: str = "unit",
        engage_fold: str = "auto", cond_ap: str = "auto", inject: bool = True, red_pre: str = "",
        movement: bool = False, red_move_rigid: bool = False) -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    tally = {k: 0 for k in
             ("acts", "prefix_equal", "full_equal", "table_longer", "port_longer",
              "both_silent", "table_silent", "port_silent", "shape", "faces",
              "declined", "rolls_equal", "rolls", "hits_equal", "hits", "next_checked",
              "next_equal", "equal_over_2", "equal_dice_max", "split_fire",
              "full_equal_owner", "clean_acts", "clean_full_equal", "clean_both_silent",
              "split_injected", "split_reaim", "split_multi", "split_aligned",
              "split_uncovered", "split_stale", "split_ambig", "split_full_equal", "pre_cut", "pre_uncut", "verbs")}
    unported: dict[str, int] = {}
    reasons: dict[str, int] = {}
    # D6a-B5: the SAME classifier over the acts the table did NOT split-fire on.
    # `first field to part` is first-past-the-post, so an act the port cannot
    # possibly match (the table aimed a weapon somewhere else) lands in whatever
    # field parts first and buries the class this rung is about.
    reasons_clean: dict[str, int] = {}
    firsts: list[str] = []
    vintage_seen: set[tuple[bool, bool]] = set()
    t0 = time.perf_counter()

    walls_seen: set[str] = set()
    if movement:
        from melee_replay_gate import header_walls_m  # lazy: melee_replay_gate imports this module at load time
    for d in games:
        head, lines, dice, seed = read_game(d)
        burn = burn_prefix(dice)
        shots = shots_of(d)
        pres = read_pre(d)
        verbs = read_verbs(d)
        core = nml_core.load(repo)
        if hero_attach == "off":
            head = detach_header(head)
        # NML-1130: replay this game with the ENGAGE FOLD and the CONDITIONAL
        # AP reading it was recorded under, not today's twin defaults — see
        # `vintage_knobs`.
        eff_engage_fold = resolve_vintage_flag(engage_fold, head, repo, "engage_fold")
        eff_cond_ap = resolve_vintage_flag(cond_ap, head, repo, "cond_ap")
        vintage_seen.add((eff_engage_fold, eff_cond_ap))
        nml_core.set_legacy_no_cond_ap(not eff_cond_ap)
        # `hero_attach` is also a SEAM (`Seams::hero_attach`, io.rs): with it on,
        # a host's activation marks its heroes activated and drags their models
        # along. Neither touches this tool's verdict — it replays one recorded
        # act at a time and compares the DEFENDER — but a control that only half
        # flips the knob is not a control.
        # AI-G4 H2 (--movement): the shooter's Advance moves per model through the movement port (header knob
        # movement=table) on the board's walls, read the way the melee gate reads them. --red-move-rigid hands
        # the same walls over with the knob OFF: the rigid landing is back. Without the flag nothing is set.
        walls, wall_src = header_walls_m(d, head) if movement else ([], "")
        walls_seen.add(wall_src)
        terrain = dict(head.get("terrain") or {}, walls=walls) if movement and head.get("terrain") else head.get("terrain")
        move_knob = {"movement": not red_move_rigid} if movement else {}
        board = nml_core.board(head["terrain"]) if head.get("terrain") else None  # F-PRE-COVER: cover of survivors
        header = {"profiles": head["profiles"], "terrain": terrain,
                  "knobs": dict(head.get("knobs", {}), **move_knob,
                                hero_attach=hero_attach == "table",
                                engage_fold=eff_engage_fold,
                                # NML-1073 M5 D6a-B4. `"unit"` is the
                                # default and the BEFORE half of the
                                # sighting measurement; `"model"` gives
                                # the volley the table's own die count,
                                # which lands in the `count` bucket of
                                # "first field to part".
                                sighting=sighting)}
        core.set_header(header)
        for pos, act in enumerate(lines):
            # The INTERLEAVED ordinal `read_game` stamped, never the
            # act line's position among its own kind.
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) not in SHOOTING_KINDS or not action.get("shoot"):
                continue
            if k in verbs:   # F-HOLD-ADV: the verb the table ran, not the one it planned
                if verbs[k] not in SHOOTING_KINDS:
                    continue   # it ran a move that cannot shoot: there is no volley to replay
                action = dict(action, kind=verbs[k])
                tally["verbs"] += 1
            tally["acts"] += 1
            # NML-1150: SPLIT FIRE's aim — where the table really pointed each
            # weapon (shots.jsonl). Injected into the action as `split`; the
            # core then resolves one tray volley per target group, in the
            # table's group order. Only the AIM comes from the record — every
            # count and face stays port-computed.
            aim, aim_kind, amb = (None, "", 0)
            if inject:
                aim, aim_kind, amb = split_aim(head, shots.get(k, []), action["shoot"],
                                               act["state"]["units"])
            if aim is not None:
                tally["split_injected"] += 1
                tally["split_" + aim_kind] += 1
                tally["split_ambig"] += bool(amb)
                action = dict(action, split=aim)
            elif aim_kind in ("uncovered", "stale"):
                # no usable aim: the sidecar has no lines here, every entry sat
                # on an ambiguous name, or the ordinal is stale (a named target
                # is dead) — the act stays on the pooled path
                tally["split_" + aim_kind] += 1
            i0 = first_at_or_after(dice, k)
            plain = act["state"] if hero_attach == "table" else detach(act["state"])
            # AI-G4 H1b: the cast/spell legs are cut, their dice burned, the state patched from the `pre` line.
            rolls_k = [r for r in dice[i0:] if int(r["act"]) == k]
            rolls_cut, pre_burn, plain = cut_pre_legs(rolls_k, plain, pres.get(k), red_pre != "noburn",
                                                      red_pre != "nopatch", board)
            tally["pre_cut"] += len(rolls_cut) < len(rolls_k)
            tally["pre_uncut"] += len(rolls_cut) == len(rolls_k) and any(r.get("leg") in CUT_LEGS for r in rolls_k)
            state = core.state_of(plain)
            # G4-H6: a LONE joined hero's roll compares as its host's label.
            lone = lone_hero_names(plain, head["profiles"])
            # `--red-misseed` moves the tray one seed over. Every count and
            # every target still comes out of the same state, so the SHAPE holds
            # and the comparison reaches the faces — which is exactly what has
            # to go red, and what `--mode off` (no dice at all) cannot prove.
            tray = nml_core.Tray(seed + 1 if mode == "misseed" else seed)
            if burn[i0] + pre_burn:
                tray.roll(burn[i0] + pre_burn)
            dang_off = cut_dangerous(rolls_k, rolls_cut)
            if dang_off:  # G4-H8: the cut took the table's dangerous test; the core rolls none for this one act
                core.set_header(dict(header, knobs=dict(header["knobs"], dangerous=False)))
            try:
                if mode in ("table", "misseed"):
                    nxt, report = core.resolve_with_tray(state, action, nml_core.Rng(0), tray)
                else:
                    nxt = core.resolve_stochastic_rng(state, action, nml_core.Rng(0))
                    report = {"rolls": [], "unported": []}
            except Exception as exc:  # a declined activation is not a dice verdict
                tally["declined"] += 1
                if len(firsts) < max(3, verbose):
                    firsts.append("%s act %d — DECLINED: %s" % (d.name, k, exc))
                continue
            finally:
                if dang_off:
                    core.set_header(header)
            for name in report["unported"]:
                unported[name] = unported.get(name, 0) + 1
            # SPLIT FIRE, measured rather than assumed: the table signs each save
            # batch with the DEFENDER (main.gd:6448), so a defense roll under
            # this ordinal whose owner is not the recorded `shoot` target means
            # the table aimed a shot somewhere this port cannot follow
            # (`_solo_pick_overlay_target` :2996-3005).
            tgt_owner = "AI (%s)" % head["profiles"][action["shoot"]]["name"] \
                if action["shoot"] in head["profiles"] else None
            split = bool(tgt_owner and any(r["roll_kind"] == "defense" and r["owner"] != tgt_owner
                                           for r in rolls_cut))
            tally["split_fire"] += split

            # `owner` rides along as the FIFTH slot and is deliberately NOT
            # compared: D1-B4b stamps it so a divergence can say WHO rolled
            # (main.gd:7173 — the firing member, so an attached hero signs its
            # own dice), not so the verdict changes shape.
            got = [(r["kind"], r["count"], r["target"], r["faces"], r["owner"])
                   for r in report["rolls"]]
            # EVERY roll the table drew under this activation ordinal, NOT a
            # prefix: truncating to `len(got)` would hide "the table drew more
            # than the port did", which is the whole `table_longer` bucket.
            # `roll_kind` goes through `combat_kind()` (NML-1104) so a
            # Regeneration/morale roll inside this window still reads "attack"
            # against the port's own still-blanket kind.
            want = [(combat_kind(r["roll_kind"]), r["count"], r["target"], r["faces"], r["owner"])
                    for r in rolls_cut]
            if not split:
                tally["clean_acts"] += 1
            if not got and not want:
                tally["both_silent"] += 1
                tally["clean_both_silent"] += not split
                continue
            if got and not want:
                tally["table_silent"] += 1
                if len(firsts) < max(3, verbose):
                    firsts.append("%s act %d [table_silent] %s — the port drew %d roll(s), "
                                  "the table none" % (d.name, k, action["shoot"][-6:], len(got)))
                continue
            if want and not got:
                tally["port_silent"] += 1
                if len(firsts) < max(3, verbose):
                    firsts.append("%s act %d [port_silent] %s — the table drew %d roll(s), "
                                  "the port none" % (d.name, k, action["shoot"][-6:], len(want)))
                continue

            verdict = "equal"
            why = ""
            tally["rolls"] += max(len(got), len(want))
            for i, (g, w) in enumerate(zip(got, want)):
                field = parted_field(g, w)
                if field:
                    # WHICH field parted first is the whole diagnosis: `count`
                    # is the attack-scaling class (the table scales by SIGHTED
                    # models, main.gd:4109, this port by `alive`), `target` the
                    # to-hit / AP class, `kind` a draw-order class.
                    reasons[field] = reasons.get(field, 0) + 1
                    if not split:
                        reasons_clean[field] = reasons_clean.get(field, 0) + 1
                    verdict, why = ("shape",
                                    "roll %d %s: %s(%d dice, %d+, %s) vs table %s(%d dice, %d+, %s)"
                                    % (i + 1, field, g[0], g[1], g[2], "AI (%s)" % g[4],
                                       w[0], w[1], w[2], w[4]))
                    break
                if g[3] != w[3]:
                    verdict, why = "faces", "roll %d %s: %s vs table %s" % (i + 1, g[0], g[3], w[3])
                    reasons["faces"] = reasons.get("faces", 0) + 1
                    break
                tally["rolls_equal"] += 1
                tally["hits"] += 1
                if successes(g[3], g[2]) == successes(w[3], w[2]):
                    tally["hits_equal"] += 1
            if verdict != "equal":
                tally[verdict] += 1
                if why and len(firsts) < 3:
                    firsts.append("%s act %d [%s] %s — %s"
                                  % (d.name, k, verdict, action["shoot"][-6:], why))
            else:
                # The overlap held. PREFIX-equal is that much; FULL-equal also
                # needs the two lists to be the same length. They part when the
                # table ran further activations under this same ordinal
                # (`table_longer`, benign but unproven) or when the port drew
                # rolls the table never did (`port_longer`, never benign).
                tally["prefix_equal"] += 1
                # How many dice this act actually staked on the comparison. A
                # 2-die act agreeing by CHANCE is a 1-in-36 event, so it says
                # nothing; the misseed red below is measured on the acts that
                # staked more than that.
                staked = sum(g[1] for g in got)
                tally["equal_dice_max"] = max(tally["equal_dice_max"], staked)
                if staked > 2:
                    tally["equal_over_2"] += 1
                # D1-B4b — THE SECOND BAR: WHO rolled. The port emits the bare
                # unit name; `dice.jsonl` wraps it the way `_solo_owner_label`
                # does (main.gd:7039-7040), and in a trainer corpus every unit
                # is an AI unit. Compared APART from the four-field verdict so
                # the numbers above stay the ones every earlier run measured —
                # and compared at all because it is what turns "the attached
                # hero fires its OWN shots" from a claim into a verdict: a host
                # rolling the hero's dice matches on count, target and faces and
                # can only part HERE.
                owners_ok = all(signer_ok(g[4], w[4], lone) for g, w in zip(got, want))
                if not owners_ok:
                    reasons["owner"] = reasons.get("owner", 0) + 1
                    if len(firsts) < max(3, verbose):
                        bad = next((i for i, (g, w) in enumerate(zip(got, want))
                                    if not signer_ok(g[4], w[4], lone)), 0)
                        firsts.append("%s act %d [owner] %s — roll %d: AI (%s) vs table %s"
                                      % (d.name, k, action["shoot"][-6:], bad + 1,
                                         got[bad][4], want[bad][4]))
                if len(got) == len(want):
                    tally["full_equal"] += 1
                    tally["clean_full_equal"] += not split
                    tally["split_full_equal"] += aim is not None
                    if owners_ok:
                        tally["full_equal_owner"] += 1
                elif len(want) > len(got):
                    tally["table_longer"] += 1
                    reasons["length"] = reasons.get("length", 0) + 1
                else:
                    tally["port_longer"] += 1
                    reasons["length"] = reasons.get("length", 0) + 1
                    if len(firsts) < max(3, verbose):
                        firsts.append("%s act %d [port_longer] %s — %d rolls vs the table's %d"
                                      % (d.name, k, action["shoot"][-6:], len(got), len(want)))
                # The NEXT replayable act, which is a position in `lines`
                # and no longer the same number as the ordinal.
                if pos + 1 < len(lines):
                    tally["next_checked"] += 1
                    if defender_state(nxt.plain(), action["shoot"]) == defender_state(
                            lines[pos + 1]["state"], action["shoot"]):
                        tally["next_equal"] += 1


    label = {"table": "GATE D1-B4",
             "off": "RED D1-B4 --mode off (dice=expected)",
             "misseed": "RED D1-B4 --red-misseed (tray on dice_seed+1)"}[mode]
    if movement:
        label += " + movement=table" + (" [RED: rigid]" if red_move_rigid else "")
    print()
    print("%s over %d games, %d shooting acts, hero_attach=%s, sighting=%s, %s (%.1fs)" % (
        label, len(games), tally["acts"], hero_attach, sighting,
        vintage_report_line(vintage_seen), time.perf_counter() - t0))
    print("  EQUAL : %d/%d acts FULL-equal (same roll count, every roll identical)"
          % (tally["full_equal"], tally["acts"]))
    print("  OWNER : %d/%d acts FULL-equal AND every roll signed by the same unit "
          "(the strict bar; %d act(s) match the dice but not the roller)"
          % (tally["full_equal_owner"], tally["acts"],
             tally["full_equal"] - tally["full_equal_owner"]))
    print("  BOTH-SILENT: %d/%d acts where neither side drew a die (counted as equal)"
          % (tally["both_silent"], tally["acts"]))
    print("        : %d/%d acts PREFIX-equal (the overlap held; %d table_longer, %d port_longer)"
          % (tally["prefix_equal"], tally["acts"], tally["table_longer"], tally["port_longer"]))
    print("  rolls : %d of %d compared rolls equal" % (tally["rolls_equal"], tally["rolls"]))
    print("  hits  : %d/%d rolls score the same hits/blocks off the recorded faces"
          % (tally["hits_equal"], tally["hits"]))
    print("  next  : %d/%d equal defender (alive, wounds) at the next act (prefix-equal acts)"
          % (tally["next_equal"], tally["next_checked"]))
    print("  split : %d both silent, %d table silent, %d port silent, %d shape, %d faces, %d declined"
          % (tally["both_silent"], tally["table_silent"], tally["port_silent"],
             tally["shape"], tally["faces"], tally["declined"]))
    print("  aim   : %d/%d acts injected with the sidecar's per-weapon aim "
          "(%d single re-aim, %d multi-target, %d aligned, %d uncovered, %d with a dropped "
          "ambiguous entry); %d of those FULL-equal"
          % (tally["split_injected"], tally["acts"], tally["split_reaim"],
             tally["split_multi"], tally["split_aligned"], tally["split_uncovered"],
             tally["split_ambig"], tally["split_full_equal"]))
    print("  first field to part: %s" % (
        ", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    print("  pre   : %d acts with the table's cast/spell leg cut%s; %d left uncut (a roll in front of the leg)"
          % (tally["pre_cut"], " [RED: %s]" % red_pre if red_pre else "", tally["pre_uncut"]))
    print("  verbs : %d acts replayed with the verb the table executed (F-HOLD-ADV)" % tally["verbs"])
    print("  split-fire: %d/%d acts where the table saved dice under a unit that is NOT "
          "the recorded shoot target" % (tally["split_fire"], tally["acts"]))
    # The same two numbers over the acts split fire did NOT touch — the only
    # population where a FULL-equal verdict was reachable before NML-1150.
    print("  no-split : %d/%d of those acts FULL-equal (+%d both silent); first field to part "
          "there: %s" % (tally["clean_full_equal"], tally["clean_acts"], tally["clean_both_silent"],
                         ", ".join("%s=%d" % kv for kv in sorted(reasons_clean.items())) or "none"))
    if movement:
        print("  walls : %s" % "; ".join(sorted(walls_seen)))
    print("  unported branches touched: %s" % (
        ", ".join("%s=%d" % kv for kv in sorted(unported.items())) or "none"))
    for f in firsts:
        print("  first : %s" % f)

    if mode == "off":
        # The reporting channel only: with no dice drawn there is nothing to
        # compare, so this proves the tool NOTICES an absent stream — not that
        # the stream is right. `--red-misseed` is the load-bearing one.
        ok = tally["prefix_equal"] == 0 and tally["acts"] > 0
        print("  RED (reporting channel) %s"
              % ("held — no tray, no equal act" if ok else "FAILED — the EV path matched"))
        return 0 if ok else 1
    if mode == "misseed":
        # LOAD-BEARING: the shapes still line up, so the comparison must reach
        # the faces and fail there. A green here would mean the faces are not
        # actually being compared.
        # A wrong seed must redden every act that staked more than a coin-flip's
        # worth of dice. Acts of 1-2 dice CAN agree by chance (1/6, 1/36) and two
        # of them do over 670 acts — counting those as a red failure would be
        # arithmetic denial, so the bar is `equal_over_2 == 0` and the surviving
        # sizes are printed rather than hidden.
        ok = tally["faces"] > 0 and tally["equal_over_2"] == 0
        print("  RED (load-bearing) %s"
              % ("held — %d acts reached the faces and parted; the %d that did not staked "
                 "at most %d dice (chance, 1-in-6^n)"
                 % (tally["faces"], tally["prefix_equal"], tally["equal_dice_max"])
                 if ok else
                 "FAILED — %d act(s) of more than 2 dice survived a wrong-seeded tray"
                 % tally["equal_over_2"]))
        return 0 if ok else 1

    # The GATE is the strict bar: same dice AND the same unit rolling them.
    # Both sides drawing NOTHING is agreement, not a missing verdict.
    ok = (tally["acts"] > 0
          and tally["full_equal_owner"] + tally["both_silent"] == tally["acts"])
    # AI-G4 F-PRINT: the printed number leaves the both-silent acts out, like the pass formula does.
    short = tally["acts"] - tally["full_equal_owner"] - tally["both_silent"]
    if report_only:
        print("  REPORT ONLY — %d/%d acts short of full equality, exit 0 by request"
              % (short, tally["acts"]))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — %d of %d shooting acts are not FULL-equal (see the buckets above)"
                    % (short, tally["acts"])))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--mode", choices=("table", "off", "misseed"), default="table",
                    help="'table' is the gate; 'off' reruns the acts down the expected-value "
                         "path, which proves the REPORTING CHANNEL only (no dice are drawn, so "
                         "nothing about the faces is tested); 'misseed' is the load-bearing red")
    ap.add_argument("--red-misseed", action="store_true",
                    help="RED PROOF: seed the tray with dice_seed+1. Every count and target is "
                         "unchanged, so the shapes hold and the FACES must part on every act "
                         "that rolls")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when acts are short of full equality (this tool is a GATE "
                         "by default and exits 1)")
    ap.add_argument("--hero-attach", choices=("table", "off"), default="table",
                    help="'table' replays the recorded attachment, which is what the corpus "
                         "carries and what D1-B4b reads; 'off' strips `attached`/`attached_to` "
                         "from every replayed state, reproducing a hero_attach='off' corpus — "
                         "the BEFORE half of the B4b measurement")
    ap.add_argument("--sighting", choices=("unit", "model"), default="unit",
                    help="'unit' is today's die count (every ALIVE model of the unit fires) and "
                         "the BEFORE half of D6a; 'model' counts the models with range AND line "
                         "of sight, per weapon, the way the table does")
    ap.add_argument("--movement", action="store_true",
                    help="AI-G4 H2: replay with the header knob movement=table - the shooter's Advance moves per "
                         "model through the M4 movement port on the board's walls (the melee gate's switch), "
                         "instead of the core translating the unit rigidly")
    ap.add_argument("--red-move-rigid", action="store_true",
                    help="RED PROOF for --movement: the same walls are handed over but the header knob stays "
                         "OFF, so the rigid landing is back and the acts the port closed part again")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--verbose", type=int, default=0, help="print every diverging act")
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: the header knob engage_fold (PR #446). 'auto' (default) "
                         "reads the corpus's OWN vintage (vintage_knobs) — absent means the "
                         "corpus predates the knob, so OFF; 'on'/'off' force it")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: conditional AP (PR #448/NML-1103), i.e. LEGACY_NO_COND_AP "
                         "inverted. 'auto' (default) reads the corpus's OWN vintage; 'on'/'off' "
                         "force it")
    ap.add_argument("--inject", choices=("on", "off"), default="on",
                    help="NML-1150: inject the sidecar shots.jsonl per-weapon aim as the "
                         "action's `split` (the core then resolves one tray volley per target "
                         "group, in the table's order). 'off' is the BEFORE control on the same "
                         "binary — every act stays pooled on the recorded shoot key")
    ap.add_argument("--red-pre", choices=("noburn", "nopatch"), default="",
                    help="AI-G4 H1b RED PROOF for the cast/spell cut: 'noburn' cuts the rolls but leaves their dice "
                         "on the tray (the faces must part), 'nopatch' keeps the pre-spell state (the count must part)")
    a = ap.parse_args(argv)
    mode = "misseed" if a.red_misseed else a.mode
    return run(Path(a.ref).expanduser(), a.repo, mode, a.limit, a.verbose, a.report_only,
               a.hero_attach, a.sighting, a.engage_fold, a.cond_ap, a.inject == "on", a.red_pre,
               a.movement or a.red_move_rigid, a.red_move_rigid)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

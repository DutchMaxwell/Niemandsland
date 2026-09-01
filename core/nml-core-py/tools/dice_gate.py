"""GATE D1-B6 (NML-1073 M5) — THE dice gate: one tool, three checks, three reds.

D1 built its ladder gate by gate: `dice_stream_gate.py` (B6a) proves the tray
twin replays a recorded stream, `shoot_replay_gate.py` (B4) replays shooting
activations, `melee_replay_gate.py` (B5b) replays charges. Each answers its own
question and prints its own table. B6 is the rung that asks all three questions
in ONE pass over the corpus, so a single run says whether the port's dice are
the table's dice — and so the three answers cannot drift apart between tools.

Nothing here re-implements those gates: the act positioning (`read_game`,
`burn_prefix`, `first_at_or_after`), the success formula (`successes`), the
next-state reader (`defender_state`), the trailing-morale split
(`trailing_morale`), the whole stream walk (`walk_game`), and SPLIT FIRE's own
aim builder (`shots_of`, `split_aim`) are IMPORTED. This file owns the join and
the reporting, nothing else.

THE THREE CHECKS

  A STREAM (per GAME) — seed a fresh `nml_core.Tray` with the game's own
    `dice_seed` and walk `dice.jsonl` in file order, comparing the faces the
    twin returns to the faces the table recorded, EXACT, `maxi(1, count)`
    included. This is the check that catches a MISSED tray consumer: one draw
    the port does not make and every face after it is wrong.

  B TALLY (per ACTIVATION) — `(hits, blocks, unsaved)` for the activation,
    computed the same way on both sides: `successes` over the "attack" rolls,
    `successes` over the "defense" rolls, and their difference floored at zero.
    Computed from the RECORDED faces and from the port's OWN rolls, compared
    EXACT. Where A is about the generator, B is about what the resolver DID
    with it.

  C NEXT (per ACTIVATION) — `alive` and total wounds of BOTH combatants after
    the replayed activation against the recorded plain state of the next
    replayable act. Both, because a melee is the one activation where the
    acting unit bleeds too. Reported as measured: the table can run further
    activations between two planner picks, and those land on the same units.

    C POS (per ACTIVATION, `--no-pos` to skip) — C's blind spot: `alive` and
    wounds say nothing about WHERE a unit stands, so a movement-only rule
    (#485, Hit & Run #493) ports wrong and C NEXT never falls. Compares the
    same two combatants' `positions` (state.rs `plain_of`, meters) reduced
    to a centroid, in inches, against `--pos-tol` (default 0.5"). #493 found
    this by hand (17% of Harassing acts within 0.5"); this makes it a check.

THE VERDICT VOCABULARY is the B4/B5 gates' own, per activation, and the eight
buckets SUM to the class's activation count — a row that does not add up is a
gate hiding something:

  `full_equal`   same number of rolls, every roll identical (kind, count,
                 target, faces, roller).
  `shape`        a roll parted inside the overlap on kind/count/target/roller.
  `faces`        the shape held and the FACES parted — with A green that can
                 only mean the port drew at a different point in the stream.
  `length`       the overlap held, the lists differ in length (the table ran a
                 further activation under the same ordinal, or the port drew
                 rolls the table never did).
  `table_silent` the port rolled, the table did not. On CHARGE acts this is
                 mostly a charge-LANDING divergence (D5), not a dice one.
  `port_silent`  the table rolled, the port did not. Never benign.
  `both_silent`  neither rolled.
  `declined`     the port refused the recorded action; not a dice verdict.

CLASSES: `shooting` (HOLD/ADVANCE with a shoot target), `melee` (CHARGE with a
target), and `morale` — the trailing morale block of EITHER, counted only on the
activations where at least one side drew one, which is why its denominator is
smaller than the other two. A morale roll is stamped `roll_kind` "attack" like
every other die and can only be told apart by WHERE it sits: last. (NML-1104
split the RECORDED corpus's `roll_kind` by rule for seven special-rule dice —
morale, Fearless, No Retreat, Regeneration, Ravage, Battleborn, dangerous
terrain; `shoot_replay_gate.combat_kind()` folds those back to "attack" when
this file's `want` tuples are built, so the port's still-blanket "attack"
(`core/nml-core/src/dice.rs`) keeps comparing like for like.)

THE THREE REDS, and the point of each is that it reddens ONE check and leaves
the other two standing. All three run the green arm in the SAME pass, so the
proof is on one screen and needs no second run:

  `--red-extra-draw`  burns one tray draw before the stream walk. Check A must
                      fall to 0 of N — every game desynced on its first roll.
                      B and C never touch that tray (each activation seeds its
                      own), so they must print their green numbers.
  `--red-formula`     scores the TABLE's recorded faces one pip off — a face
                      equal to the target stops counting, where
                      `DiceRules.count_successes` (dice_rules.gd:55-71) says
                      `>=`. Only check B reads that formula, so only B may fall
                      — and it must, or the tally is not being compared at all.
  `--red-one-wound`   moves the PORT's wound total by ONE before check C
                      compares it — the smallest change the check has to be
                      able to see. Only check C reads that state, so only C may
                      fall — 271 -> 1 on the corpus. That surviving 1 is not a
                      survivor: the arms are counted independently, and it is an
                      activation the GREEN arm already scored unequal, where the
                      port's wound total happens to sit exactly one BELOW the
                      table's for both combatants. No activation can be equal in
                      both arms; that is arithmetic, not evidence.
                      A SHIFT to the next act's state was the first red tried
                      here and was dropped: the shifted state often coincides,
                      so it reddened 271 -> 256 on the corpus and nothing at all
                      on the two bundled games. A red that only sometimes
                      reddens is not a red.

    PYTHONPATH=<module> python core/nml-core-py/tools/dice_gate.py \\
        --ref ~/selfplay_out/qbe_ref --out /tmp/dice_gate.json
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
from dice_stream_gate import walk_game  # noqa: E402
from melee_replay_gate import CHARGE_KIND, trailing_morale  # noqa: E402
from shoot_replay_gate import (  # noqa: E402
    SHOOTING_KINDS, burn_prefix, combat_kind, defender_state, first_at_or_after, read_game,
    resolve_vintage_flag, shots_of, split_aim, successes, vintage_report_line,
)

CLASSES = ("shooting", "melee", "morale")
BUCKETS = ("full_equal", "shape", "faces", "length", "table_silent", "port_silent",
           "both_silent", "declined")


def successes_red(faces, target: int) -> int:
    """`--red-formula`: `successes` with a one-character off-by-one — a face
    EQUAL to the target stops counting, where `DiceRules.count_successes`
    (dice_rules.gd:55-71) says `>=`. The natural-6 rule is left standing, so a
    6 still succeeds and the break is exactly the threshold. Applied to the
    TABLE's side of check B only: applying it to both would cancel and prove
    nothing."""
    if target <= 0:
        return 0
    return sum(1 for f in faces if f >= 6 or (f > 1 and f > target))


def tallies(rolls, red: bool = False) -> tuple[int, int, int]:
    """(hits, blocks, unsaved) of one activation's rolls — check B's number.
    "attack" rolls score hits, "defense" rolls score blocks, and what is left
    over is what actually wounded."""
    score = successes_red if red else successes
    hits = sum(score(r[3], r[2]) for r in rolls if r[0] == "attack")
    blocks = sum(score(r[3], r[2]) for r in rolls if r[0] == "defense")
    return hits, blocks, max(0, hits - blocks)


def both_equal(nx: dict, other: dict, keys, bump: int = 0) -> bool:
    """Check C's comparison: `alive` and total wounds of BOTH combatants.
    `bump` is `--red-one-wound` — it moves the PORT's wound total by one, which
    is the smallest difference this check must never miss."""
    for k in keys:
        alive, wounds = defender_state(nx, k)
        if (alive, wounds + bump) != defender_state(other, k):
            return False
    return True


#: meters per inch (rows.rs's own fixture: `0.254` == `10.0"`) — `positions`
#: (state.rs `plain_of`) is written in meters, `--pos-tol` is read in inches.
INCH_M = 0.0254

#: check C POS's own bucket order, mirroring `BUCKETS`'s "sum to the count".
POS_BUCKETS = ("pos_equal", "pos_moved_1in", "pos_moved_3in", "pos_moved_far", "pos_unknown")


def unit_centroid(plain: dict, key: str) -> tuple[float, float, float] | None:
    """Mean of one unit's alive-model positions, or `None` — no such unit, or
    an empty `positions` list (wiped out; the array tracks `alive`, never a
    dead model's stale spot)."""
    ps = (plain.get("units", {}).get(key) or {}).get("positions") or []
    if not ps:
        return None
    n = len(ps)
    return (sum(p[0] for p in ps) / n, sum(p[1] for p in ps) / n, sum(p[2] for p in ps) / n)


def pos_gap_in(nx: dict, other: dict, key: str) -> float | None:
    """Centroid distance, port vs. the table's next-act snapshot, in inches.
    `None` — `pos_unknown` — when either side has no position at all, never
    a gap of zero."""
    a, b = unit_centroid(nx, key), unit_centroid(other, key)
    if a is None or b is None:
        return None
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5 / INCH_M


def pos_verdict(nx: dict, other: dict, keys, tol_in: float) -> tuple[str, float | None]:
    """Check C POS's bucket for one activation: the WORST gap across `keys`
    (the combatants `both_equal` compares) against `tol_in`. Any key
    `pos_unknown` makes the whole activation `pos_unknown` — never a fail."""
    gaps = [pos_gap_in(nx, other, k) for k in keys]
    if any(g is None for g in gaps):
        return "pos_unknown", None
    gap = max(gaps)
    if gap <= tol_in:
        return "pos_equal", gap
    if gap <= 1.0:
        return "pos_moved_1in", gap
    if gap <= 3.0:
        return "pos_moved_3in", gap
    return "pos_moved_far", gap


def classify(got: list, want: list) -> str:
    """One activation's verdict in the B4/B5 vocabulary. `want` is EVERY roll
    the table drew under this ordinal, never a prefix."""
    if not got and not want:
        return "both_silent"
    if not want:
        return "table_silent"
    if not got:
        return "port_silent"
    for g, w in zip(got, want):
        if g[:3] != w[:3] or g[4] != w[4]:
            return "shape"
        if g[3] != w[3]:
            return "faces"
    return "full_equal" if len(got) == len(want) else "length"


def bearer_names(profile: dict) -> set[str]:
    """Every rule base name the unit or one of its attached heroes carries in
    the header profiles. The import folds item-granted rules into
    `special_rules` (opr_api_client.gd:261-263), so the flat lists are the
    whole check — the same read `RulesRegistry.unit_rule_active` makes."""
    out = set()
    for r in profile.get("special_rules", []):
        out.add(str(r).split("(")[0].strip())
    for row in profile.get("attached_hero_rules", []):
        for g in row:
            out.add(str(g).split("(")[0].strip())
    return out


#: `--only-rule`'s own one-die "attack" shape, `(count, target)`: Mend's D3
#: `_solo_tray_roll(1, 1, ...)` (main.gd:5244) and BLOCK B3's Breath Attack
#: trigger `_solo_tray_roll(1, trigger, ...)` (main.gd:5307-5308, trigger ==
#: `BREATH_TRIGGER` == 2, sim.rs). Unlisted rules fall back to Mend's shape,
#: the only one this gate knew before block B3.
#:
#: BLOCK B4 (Shot Modifier: Good Shot / Bad Shot / Targeting Visor) does not
#: fit this shape at all — it is not a separate die, it is a TARGET shift on
#: the bearer's own already-existing to-hit roll (`_solo_hit_mod_info`
#: main.gd:5681-5701), so its `count` is the weapon's attack count (rarely 1)
#: and its `target` is Quality +-1 (not a fixed number). `None` marks that:
#: "any 'attack' roll of a bearer counts as the rule's own slot", the only
#: definition that makes sense for a modifier instead of a draw.
#:
#: BLOCK B6 (the extra-ATTACK-DIE Surge siblings — Bloodborn / Clan Warrior /
#: Primal / Predator / Royal Warrior / Crazed / Psychotic) is a FOURTH shape:
#: it IS a separate die (unlike B4), but neither its count (one per unmodified
#: 6/5) nor its target (the bearer's own ordinary to-hit target) is fixed —
#: so `(count, target)` cannot name it either. Its shape is POSITIONAL
#: instead: `EXTRA_ATTACK_DIE` marks the roll that immediately follows
#: ANOTHER "attack" roll at the SAME target (main.gd:4417-4432 draws it right
#: after the primary hit die, nothing else rolls between them).
EXTRA_ATTACK_DIE = object()
#: BLOCK B7 (Growth Markers): the SAME target-shift shape as B4 — Piercing
#: Growth's AP delta and Precision Frenzy's hit delta each move an EXISTING
#: attack roll's target, not a die of their own.
RULE_ROLL_SHAPE: dict[str, tuple[int, int] | None | object] = {
    "Mend": (1, 1), "Breath Attack": (1, 2),
    "Good Shot": None, "Bad Shot": None, "Targeting Visor": None,
    "Piercing Growth": None, "Precision Frenzy": None,
    "Bloodborn": EXTRA_ATTACK_DIE, "Clan Warrior": EXTRA_ATTACK_DIE,
    "Primal": EXTRA_ATTACK_DIE, "Predator": EXTRA_ATTACK_DIE,
    "Predator Fighter": EXTRA_ATTACK_DIE, "Predator Shooter": EXTRA_ATTACK_DIE,
    "Royal Warrior": EXTRA_ATTACK_DIE, "Crazed": EXTRA_ATTACK_DIE,
    "Psychotic": EXTRA_ATTACK_DIE,
}

#: Unlike B4's family (shooting only), Piercing Growth's AP facet reaches
#: melee too — `_solo_attack_groups` adds it to `prof["ap"]` regardless of
#: which the caller built profiles for (main.gd:4287). The one name the
#: shooting-only `None`-shape guard below must let a CHARGE act through for.
NONE_SHAPE_MELEE_OK = frozenset({"Piercing Growth"})

#: BLOCK B2b (the Utility-Buff family) is a THIRD shape, and it is NOT
#: `RULE_ROLL_SHAPE`'s `None`: those rules draw no die of their own at all —
#: the buff is a RECORD that a LATER roll reads (`_solo_record_spell_mod`
#: main.gd:3649 read back at `_solo_hit_mod_info` :5703 / the morale sum
#: :8288). B4's `None` says "the roll exists, its shape is just not fixed";
#: this says "there is no roll to find". An act is selected by BEARER alone
#: and the rule-slot sub-check has nothing to count.
#: BLOCK B5 (Hit & Run): the same "no roll at all" shape as B2b — the free
#: move is dice-free start to finish (`tray_hit_and_run`, sim.rs). The literal
#: primitive name plus its two ported data aliases, so `--only-rule` selects a
#: bearer act whichever of the three names the unit's own header carries.
#: BLOCK B8 (Second Wind): pure activation/fatigue bookkeeping
#: (`second_wind_candidate`/`spend_second_wind`, sim.rs) — no roll of its own.
#: The primitive name plus its only two literal carriers in the registry.
DICE_FREE_RULES = frozenset({
    "Precision Attacks Buff", "Precision Fighter Buff", "Precision Shooter Buff",
    "Morale Debuff", "Casting Buff", "Primal Boost Buff", "Unstoppable Mark",
    "Hit & Run", "Guerrilla", "Harassing",
    "Second Wind", "Inquisitorial Agent", "Martial Prowess",
})


def is_rule_roll(r: dict, only_rule: str, prev: dict | None = None) -> bool:
    """A count-1 "attack" roll at the rule's own target — OR, for a `None`
    shape (block B4's target-shift family), any "attack" roll at all — OR, for
    `EXTRA_ATTACK_DIE` (block B6), an "attack" roll immediately following
    ANOTHER "attack" roll (`prev`, the roll at `block[i-1]`, `None` for `r`
    itself being the block's first roll) at the SAME target. Bearer-gated at
    the call site (`only_rule not in bearer_names(prof)`), so a count-1
    target-2+ ordinary to-hit die never gets mistaken for the rule's own draw
    unless the SAME unit also happens to carry the rule — and for a `None`
    shape, EVERY attack roll of a bearer's own shooting act counts, coarser
    than the other rules' by design (see `RULE_ROLL_SHAPE`). A rule in
    `DICE_FREE_RULES` has no roll of its own at all and never matches."""
    if only_rule in DICE_FREE_RULES:
        return False   # block B2b: there is no roll of its own to find
    if r.get("roll_kind") != "attack":
        return False
    shape = RULE_ROLL_SHAPE.get(only_rule, (1, 1))
    if shape is EXTRA_ATTACK_DIE:
        return prev is not None and prev.get("roll_kind") == "attack" and r.get("target") == prev.get("target")
    if shape is None:
        return True
    count, target = shape
    return int(r.get("count", 0)) == count and int(r.get("target", 0)) == target


def inject_split_aim(head: dict, shots: list[dict], action: dict, units: dict) -> tuple[dict, bool]:
    """NML-1150, the gap PR #488 could only bucket, now filled: `split_aim`
    (`shoot_replay_gate.py`, imported not copied) folds the sidecar's
    per-weapon target names onto this act's own `action`. An act that already
    carries `action.split`, or one `split_aim` cannot cover (no shots.jsonl
    line under this ordinal, every entry ambiguous or stale, or every shot
    already agrees with the recorded `shoot` key — nothing to inject), comes
    back UNCHANGED — `split_unrecorded` below then judges it on the raw dice
    shape, exactly as it did before this existed."""
    if action.get("split"):
        return action, False
    aim, _, _ = split_aim(head, shots, action["shoot"], units)
    if aim is None:
        return action, False
    return dict(action, split=aim), True


def split_unrecorded(cls: str, block: list[dict], action: dict) -> bool:
    """NML-1150 GAP: a shooting act's recorded dice carry MORE THAN ONE raw
    "attack"-shaped roll (`is_rule_roll`'s own shape read — `roll_kind ==
    "attack"`, distinct from "defense" and the seven named special-rule
    kinds) under one ordinal: the table split the volley across targets, but
    the act itself carries no `action.split` (0 of ~1800 shooting acts on
    every corpus checked so far predate the field). The twin (`sim.rs` shoot
    branch, `plan.as_deref().unwrap_or(&pooled)`) still pools every shot at
    the ONE recorded target, so B and C can never agree there — bucketed as
    confounded, the same reason `--only-rule` already skips B/C for a shape-
    confounded act. An act that DOES carry `action.split` is untouched."""
    return (cls == "shooting" and not action.get("split")
            and sum(1 for r in block if r.get("roll_kind") == "attack") > 1)


def run(ref: Path, repo: str, limit: int, out: str, red: str, report_only: bool,
        no_dangerous: bool = False, engage_fold: str = "auto", cond_ap: str = "auto",
        only_rule: str = "", pos_tol: float = 0.5, no_pos: bool = False,
        movement: str = "rigid") -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    grid = {c: dict.fromkeys(BUCKETS + ("acts",), 0) for c in CLASSES}
    chk = dict.fromkeys(("stream_ok", "rolls", "tally", "tally_equal", "tally_red",
                         "next", "next_equal", "next_red", "mend_rolls", "mend_rolls_equal",
                         "mend_rolls_clean", "mend_rolls_clean_equal", "confounded",
                         "split_unrecorded", "split_aimed", "pos", "ledger_acts") + POS_BUCKETS, 0)
    if only_rule:
        grid["mend"] = dict.fromkeys(BUCKETS + ("acts",), 0)
    first = {"stream": "", "tally": "", "next": ""}
    pos_gaps: list[float] = []  # every KNOWN gap (inches), for the median line
    vintage_seen: set[tuple[bool, bool]] = set()
    t0 = time.perf_counter()

    for d in games:
        walked = walk_game(d, red == "extra-draw")
        chk["rolls"] += walked.rolls
        if walked.mismatch is None:
            chk["stream_ok"] += 1
        elif not first["stream"]:
            first["stream"] = "%s line %d: %s" % (d.name, walked.mismatch[0], walked.mismatch[3])

        head, lines, dice, seed = read_game(d)
        burn = burn_prefix(dice)
        shots = shots_of(d)
        core = nml_core.load(repo)
        # NML-1130: replay with the ENGAGE FOLD and the CONDITIONAL AP reading
        # this corpus was recorded under, not today's twin defaults.
        eff_engage_fold = resolve_vintage_flag(engage_fold, head, repo, "engage_fold")
        eff_cond_ap = resolve_vintage_flag(cond_ap, head, repo, "cond_ap")
        vintage_seen.add((eff_engage_fold, eff_cond_ap))
        nml_core.set_legacy_no_cond_ap(not eff_cond_ap)
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       dangerous=not no_dangerous,
                                       engage_fold=eff_engage_fold, sighting="model",
                                       movement=(movement == "table"))})
        for pos, act in enumerate(lines):
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            kind = int(action.get("kind", -1))
            i0 = first_at_or_after(dice, k)
            if kind in SHOOTING_KINDS and action.get("shoot"):
                cls, foe = "shooting", action["shoot"]
            elif kind == CHARGE_KIND and action.get("charge"):
                cls, foe = "melee", action["charge"]
            elif only_rule and RULE_ROLL_SHAPE.get(only_rule, (1, 1)) not in (None, EXTRA_ATTACK_DIE):
                # --only-rule: the rule fires BEFORE attacking (main.gd:1056-1058),
                # on ADVANCE/RUSH activations just as well — a Mend act with no
                # shoot/charge target is still a replayable act, judged as its
                # own class. A `None`-shape rule (block B4's Shot Modifier
                # family — a to-hit TARGET shift, not a standalone pre-attack
                # die) never applies off a shooting act, so it never takes this
                # branch: `combat_kind()` folds a trailing morale roll's
                # `roll_kind` back to "attack" too, and without a real shoot
                # act to anchor on, a `None` shape would misread that morale
                # die as the rule's own slot. `EXTRA_ATTACK_DIE` (block B6)
                # never fires off a bare move/cast act either — always
                # attached to a shoot or charge — so it stays out too.
                cls, foe = "mend", None
            else:
                continue
            block = [r for r in dice[i0:] if int(r["act"]) == k]
            if only_rule:
                # A `None`-shape rule (block B4) never reaches melee (main.gd:
                # 5627-5636's all_attacks/melee_only/when:charge gate keeps it
                # out) — a CHARGE act's own strikes are ALSO roll_kind
                # "attack", so without this the coarse "any attack roll"
                # match would mistake a Good-Shot-bearer's charge for the
                # rule's own slot.
                if RULE_ROLL_SHAPE.get(only_rule, (1, 1)) is None and cls != "shooting" \
                        and not (cls == "melee" and only_rule in NONE_SHAPE_MELEE_OK):
                    continue
                unit_key = (act.get("pick") or {}).get("unit_key") or action.get("unit")
                prof = head["profiles"].get(unit_key) or {}
                dice_free = only_rule in DICE_FREE_RULES
                if only_rule not in bearer_names(prof) or not (dice_free or any(
                        is_rule_roll(block[i], only_rule, block[i - 1] if i else None)
                        for i in range(len(block)))):
                    continue
            if cls == "shooting":
                # NML-1150: aim from shots.jsonl BEFORE the confound check
                # below, so an act this can aim never falls into the
                # split_unrecorded fallback at all.
                action, aimed = inject_split_aim(head, shots.get(k, []), action,
                                                  act["state"]["units"])
                chk["split_aimed"] += aimed
            grid[cls]["acts"] += 1
            # NML-1152 step 10: does THIS act's state_before carry NON-EMPTY
            # ledger content (act_recorder.gd's `_ledger_of`) for at least one
            # unit — `{}` (recorded, nothing to say) and a missing key (a
            # corpus predating this schema) both read False here alike.
            if any(u.get("ledger") for u in act["state"]["units"].values()):
                chk["ledger_acts"] += 1
            split_confound = split_unrecorded(cls, block, action)
            chk["split_unrecorded"] += split_confound
            tray = nml_core.Tray(seed)
            if burn[i0]:
                tray.roll(burn[i0])
            try:
                nxt, report = core.resolve_with_tray(
                    core.state_of(act["state"]), action, nml_core.Rng(0), tray)
            except Exception:  # a declined activation is not a dice verdict
                grid[cls]["declined"] += 1
                continue
            got = [(r["kind"], r["count"], r["target"], r["faces"], "AI (%s)" % r["owner"])
                   for r in report["rolls"]]
            # `roll_kind` -> `combat_kind()` (NML-1104): the RECORDED corpus
            # names the rule behind seven special-rule dice the port still
            # lumps under "attack" — see this file's docstring, CLASSES.
            want = [(combat_kind(r["roll_kind"]), r["count"], r["target"], r["faces"], r["owner"])
                    for r in dice[i0:] if int(r["act"]) == k]
            grid[cls][classify(got, want)] += 1
            # THE RULE'S OWN SUB-CHECK (--only-rule): every recorded roll of the
            # rule's shape must reappear at the SAME SLOT of the port's draw
            # order with the same face — the draw happened, where it belongs.
            if only_rule:
                clean = len(got) == len(want)
                shape = RULE_ROLL_SHAPE.get(only_rule, (1, 1))
                for i, w in enumerate(want):
                    if shape is EXTRA_ATTACK_DIE:
                        rule_shaped = i > 0 and want[i - 1][0] == "attack" and w[2] == want[i - 1][2]
                    else:
                        rule_shaped = shape is None or (w[1], w[2]) == shape
                    if w[0] == "attack" and rule_shaped:
                        chk["mend_rolls"] += 1
                        hit = i < len(got) and got[i] == w
                        chk["mend_rolls_equal"] += hit
                        if clean:
                            chk["mend_rolls_clean"] += 1
                            chk["mend_rolls_clean_equal"] += hit
            gm, wm = trailing_morale(got), trailing_morale(want)
            if gm or wm:
                grid["morale"]["acts"] += 1
                grid["morale"][classify(gm, wm)] += 1

            # CHECK B — only where both sides rolled: an activation the table
            # never fought has no tally to be compared against. Under
            # --only-rule also only where the port reproduced the act's whole
            # shape: an act the table resolved BEYOND its recorded pick (the
            # known length confound) has a tally that measures that gap, not
            # the rule — counted as confounded instead. `split_confound` is the
            # same skip for the split-unrecorded signature above, regardless of
            # --only-rule.
            if got and want and (not only_rule or len(got) == len(want)) and not split_confound:
                chk["tally"] += 1
                green = tallies(got) == tallies(want)
                chk["tally_equal"] += green
                if red == "formula":
                    chk["tally_red"] += tallies(got) == tallies(want, True)
                elif not green and not first["tally"]:
                    first["tally"] = "%s act %d [%s] port %s vs table %s" % (
                        d.name, k, cls, tallies(got), tallies(want))
            elif only_rule and got != want:
                chk["confounded"] += 1
            # CHECK C — both combatants, against the NEXT replayable act. Under
            # --only-rule it runs only where the act's SHAPE held: a confounded
            # act's state divergence is the confound's, not the rule's (the
            # confound is counted above). `split_confound` skips it here too.
            if (not only_rule or len(got) == len(want)) and pos + 1 < len(lines) \
                    and not split_confound:
                chk["next"] += 1
                nx = nxt.plain()
                keys = (action["unit"], foe)
                nxt_state = lines[pos + 1]["state"]
                if only_rule:
                    # The rule's patient is usually a THIRD friendly unit (the
                    # bearer's own host, a joined hero, a neighbour) — check C
                    # must see the whole friendly side on rule acts, or the
                    # heal it is supposed to police is invisible to it.
                    actor = nxt_state["units"].get(action["unit"]) or {}
                    side = actor.get("player")
                    if side is not None:
                        keys = tuple(kk for kk, uu in sorted(nxt_state["units"].items())
                                     if uu.get("player") == side)
                green = both_equal(nx, nxt_state, keys)
                chk["next_equal"] += green
                if red == "one-wound":
                    chk["next_red"] += both_equal(nx, nxt_state, keys, bump=1)
                elif not green and not first["next"]:
                    first["next"] = "%s act %d [%s] %s vs %s" % (
                        d.name, k, cls, keys[0][-6:], keys[1][-6:])
                # CHECK C POS — same combatants, added not replacing: a pure
                # movement rule (#485, #493) leaves `next_equal` untouched, so
                # this is the only thing in the pass that can catch it.
                if not no_pos:
                    chk["pos"] += 1
                    bucket, gap = pos_verdict(nx, nxt_state, keys, pos_tol)
                    chk[bucket] += 1
                    if gap is not None:
                        pos_gaps.append(gap)

    acts = sum(grid[c]["acts"] for c in grid)
    print()
    print("GATE D1-B6 over %d games, %d activations, movement=%s, %s%s%s (%.1fs)"
          % (len(games), acts, movement, vintage_report_line(vintage_seen),
             "" if not red else " — RED --red-%s" % red,
             " — RED --red-no-dangerous (the p.12 test switched OFF)" if no_dangerous else "",
             time.perf_counter() - t0))
    print("  A STREAM: %d/%d games replay the recorded tray exactly (%d rolls)"
          % (chk["stream_ok"], len(games), chk["rolls"]))
    print("  B TALLY : %d/%d activations score the table's (hits, blocks, unsaved)"
          % (chk["tally_equal"], chk["tally"]))
    print("  C NEXT  : %d/%d activations leave BOTH combatants where the next act found them"
          % (chk["next_equal"], chk["next"]))
    pos_median = 0.0
    if pos_gaps:
        s, n = sorted(pos_gaps), len(pos_gaps)
        pos_median = s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
    if not no_pos:
        print("  C POS   : %d/%d activations with both combatants within %g\" of the table "
              "(median gap %s\")"
              % (chk["pos_equal"], chk["pos"], pos_tol,
                 ("%.3f" % pos_median) if pos_gaps else "n/a"))
    print("  AIM     : %d/%d shooting acts split-aimed from shots.jsonl (%d unaimed -> "
          "split_unrecorded)"
          % (chk["split_aimed"], grid["shooting"]["acts"], chk["split_unrecorded"]))
    print("  SPLIT   : %d/%d shooting acts split-unrecorded (corpus predates action.split) "
          "— B/C skipped"
          % (chk["split_unrecorded"], grid["shooting"]["acts"]))
    print("  LEDGER  : %d/%d acts with recorded ledgers" % (chk["ledger_acts"], acts))
    if only_rule:
        print("  rule %s: %d/%d rule-shaped rolls replay at their own slot "
              "(%d/%d on the %d shape-clean acts), %d acts shape-confounded "
              "(tally and C skipped there)"
              % (only_rule, chk["mend_rolls_equal"], chk["mend_rolls"],
                 chk["mend_rolls_clean_equal"], chk["mend_rolls_clean"],
                 chk["mend_rolls_clean"], chk["confounded"]))
    cols = ("acts",) + BUCKETS
    fmt = "  %-9s" + "%14s" * len(cols)
    grid_classes = tuple(grid)
    tot = {b: sum(grid[c][b] for c in grid_classes) for b in cols}
    print(fmt % (("class",) + cols))
    for c in grid_classes + ("TOTAL",):
        g = tot if c == "TOTAL" else grid[c]
        print(fmt % ((c,) + tuple(g[b] for b in cols)))
    for name, text in first.items():
        if text:
            print("  first %s divergence: %s" % (name, text))

    summary = {"tool": "dice_gate", "gate": "D1-B6", "ref": str(ref), "games": len(games),
               "red": red or "none", "no_dangerous": no_dangerous, "only_rule": only_rule,
               "checks": chk, "classes": grid, "totals": tot, "pos_tol": pos_tol,
               "pos_median": round(pos_median, 3) if pos_gaps else None,
               "first": first, "seconds": round(time.perf_counter() - t0, 1)}
    if out:
        Path(out).expanduser().write_text(json.dumps(summary, indent=1, sort_keys=True))
        print("  summary -> %s" % out)

    if red:
        # Each red moves ITS OWN check and leaves the other two standing at the
        # GREEN numbers this same pass computed and printed above.
        seen = {"extra-draw": ("A", len(games), chk["stream_ok"]),
                "formula": ("B", chk["tally_equal"], chk["tally_red"]),
                "one-wound": ("C", chk["next_equal"], chk["next_red"])}[red]
        # An extra draw shifts EVERY stream, so its bar is ZERO. The other two
        # are stated as "fewer": `--red-formula` leaves the activations that
        # scored nothing on both sides, and `--red-one-wound` can pick up an
        # activation the green arm had already scored unequal (the arms are
        # counted apart). Neither of those two may disturb check A.
        ok = (seen[2] == 0) if red == "extra-draw" else \
            (seen[2] < seen[1] and chk["stream_ok"] == len(games))
        print("  RED --red-%s %s — check %s fell %d -> %d, the other two above are this same "
              "pass's GREEN numbers" % ((red, "held" if ok else "FAILED") + seen))
        return 0 if ok else 1

    # The bar D1 set for itself: stream exact on every game, every activation's
    # tally exact. `full_equal` and check C are REPORTED, not gated — the melee
    # rung's own log names charge landing (D5) and per-model sighting (D6a) as
    # what still holds them down. Under --only-rule the bar is the RULE's:
    # every rule-shaped roll at its slot, the friendly side where the next act
    # found it, and every unconfounded activation's tally exact.
    if only_rule:
        ok = chk["stream_ok"] == len(games) and 0 < chk["mend_rolls_clean"] \
            and chk["mend_rolls_clean_equal"] == chk["mend_rolls_clean"] \
            and chk["tally_equal"] == chk["tally"] \
            and chk["next_equal"] == chk["next"]
    else:
        ok = chk["stream_ok"] == len(games) and chk["tally"] > 0 \
            and chk["tally_equal"] == chk["tally"]
    if report_only:
        print("  REPORT ONLY — %d/%d activations short of an equal tally, exit 0 by request"
              % (chk["tally"] - chk["tally_equal"], chk["tally"]))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — A %d/%d games, B %d/%d activations"
                    % (chk["stream_ok"], len(games), chk["tally_equal"], chk["tally"])))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--out", default="", help="write the summary JSON here")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when the checks are short (this tool is a GATE by "
                         "default and exits 1)")
    for knob, helptext in (
            ("extra-draw", "RED for check A: burn one tray draw before the stream walk"),
            ("formula", "RED for check B: score the table's faces one pip off (> instead of >=)"),
            ("one-wound", "RED for check C: move the port's wound total by one")):
        ap.add_argument("--red-" + knob, action="store_true", help=helptext)
    ap.add_argument("--red-no-dangerous", action="store_true",
                    help="RED for D1-B8: switch the p.12 DANGEROUS-terrain test back OFF "
                         "(header knob dangerous=false). Orthogonal to the three checks above "
                         "— every number must fall back to the pre-D1-B8 baseline")
    ap.add_argument("--only-rule", default="",
                    help="restrict the classified activations to the RULE's own acts: "
                         "an acting unit (or attached hero) bearing the rule whose "
                         "recorded dice block carries the rule's die shape — block B "
                         "parity runs read their rule here")
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: the header knob engage_fold (PR #446). 'auto' (default) "
                         "reads the corpus's OWN vintage (vintage_knobs) — absent means the "
                         "corpus predates the knob, so OFF; 'on'/'off' force it")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: conditional AP (PR #448/NML-1103), i.e. LEGACY_NO_COND_AP "
                         "inverted. 'auto' (default) reads the corpus's OWN vintage; 'on'/'off' "
                         "force it")
    ap.add_argument("--pos-tol", type=float, default=0.5,
                    help="check C POS: inches of centroid gap that still counts pos_equal "
                         "(default 0.5\")")
    ap.add_argument("--no-pos", action="store_true",
                    help="skip check C POS (the position add-on to check C)")
    ap.add_argument("--movement", choices=("rigid", "table"), default="rigid",
                    help="NML-1152 S0: header knob movement. 'rigid' (default) reproduces "
                         "every published number byte-for-byte; 'table' routes CHARGE through "
                         "the M4 movement port (mv::step::charge_move) instead of one rigid "
                         "translation of the whole unit — slower, moves check C POS and "
                         "C NEXT up")
    a = ap.parse_args(argv)
    reds = [k for k in ("extra-draw", "formula", "one-wound")
            if getattr(a, "red_" + k.replace("-", "_"))]
    if len(reds) > 1:
        ap.error("one red knob at a time — each has to redden its own check alone")
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.out, reds[0] if reds else "",
               a.report_only, a.red_no_dangerous, a.engage_fold, a.cond_ap, a.only_rule,
               a.pos_tol, a.no_pos, a.movement)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

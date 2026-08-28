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
(`trailing_morale`) and the whole stream walk (`walk_game`) are IMPORTED. This
file owns the join and the reporting, nothing else.

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
    resolve_vintage_flag, successes, vintage_report_line,
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


def run(ref: Path, repo: str, limit: int, out: str, red: str, report_only: bool,
        no_dangerous: bool = False, engage_fold: str = "auto", cond_ap: str = "auto") -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    grid = {c: dict.fromkeys(BUCKETS + ("acts",), 0) for c in CLASSES}
    chk = dict.fromkeys(("stream_ok", "rolls", "tally", "tally_equal", "tally_red",
                         "next", "next_equal", "next_red"), 0)
    first = {"stream": "", "tally": "", "next": ""}
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
                                       engage_fold=eff_engage_fold)})
        for pos, act in enumerate(lines):
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            kind = int(action.get("kind", -1))
            if kind in SHOOTING_KINDS and action.get("shoot"):
                cls, foe = "shooting", action["shoot"]
            elif kind == CHARGE_KIND and action.get("charge"):
                cls, foe = "melee", action["charge"]
            else:
                continue
            grid[cls]["acts"] += 1
            i0 = first_at_or_after(dice, k)
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
            gm, wm = trailing_morale(got), trailing_morale(want)
            if gm or wm:
                grid["morale"]["acts"] += 1
                grid["morale"][classify(gm, wm)] += 1

            # CHECK B — only where both sides rolled: an activation the table
            # never fought has no tally to be compared against.
            if got and want:
                chk["tally"] += 1
                green = tallies(got) == tallies(want)
                chk["tally_equal"] += green
                if red == "formula":
                    chk["tally_red"] += tallies(got) == tallies(want, True)
                elif not green and not first["tally"]:
                    first["tally"] = "%s act %d [%s] port %s vs table %s" % (
                        d.name, k, cls, tallies(got), tallies(want))
            # CHECK C — both combatants, against the NEXT replayable act.
            if pos + 1 < len(lines):
                chk["next"] += 1
                nx, keys = nxt.plain(), (action["unit"], foe)
                nxt_state = lines[pos + 1]["state"]
                green = both_equal(nx, nxt_state, keys)
                chk["next_equal"] += green
                if red == "one-wound":
                    chk["next_red"] += both_equal(nx, nxt_state, keys, bump=1)
                elif not green and not first["next"]:
                    first["next"] = "%s act %d [%s] %s vs %s" % (
                        d.name, k, cls, keys[0][-6:], keys[1][-6:])

    acts = sum(grid[c]["acts"] for c in ("shooting", "melee"))
    print()
    print("GATE D1-B6 over %d games, %d activations, %s%s%s (%.1fs)"
          % (len(games), acts, vintage_report_line(vintage_seen),
             "" if not red else " — RED --red-%s" % red,
             " — RED --red-no-dangerous (the p.12 test switched OFF)" if no_dangerous else "",
             time.perf_counter() - t0))
    print("  A STREAM: %d/%d games replay the recorded tray exactly (%d rolls)"
          % (chk["stream_ok"], len(games), chk["rolls"]))
    print("  B TALLY : %d/%d activations score the table's (hits, blocks, unsaved)"
          % (chk["tally_equal"], chk["tally"]))
    print("  C NEXT  : %d/%d activations leave BOTH combatants where the next act found them"
          % (chk["next_equal"], chk["next"]))
    cols = ("acts",) + BUCKETS
    fmt = "  %-9s" + "%14s" * len(cols)
    tot = {b: sum(grid[c][b] for c in CLASSES) for b in cols}
    print(fmt % (("class",) + cols))
    for c in CLASSES + ("TOTAL",):
        g = tot if c == "TOTAL" else grid[c]
        print(fmt % ((c,) + tuple(g[b] for b in cols)))
    for name, text in first.items():
        if text:
            print("  first %s divergence: %s" % (name, text))

    summary = {"tool": "dice_gate", "gate": "D1-B6", "ref": str(ref), "games": len(games),
               "red": red or "none", "no_dangerous": no_dangerous, "checks": chk, "classes": grid, "totals": tot,
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
    # what still holds them down.
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
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: the header knob engage_fold (PR #446). 'auto' (default) "
                         "reads the corpus's OWN vintage (vintage_knobs) — absent means the "
                         "corpus predates the knob, so OFF; 'on'/'off' force it")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: conditional AP (PR #448/NML-1103), i.e. LEGACY_NO_COND_AP "
                         "inverted. 'auto' (default) reads the corpus's OWN vintage; 'on'/'off' "
                         "force it")
    a = ap.parse_args(argv)
    reds = [k for k in ("extra-draw", "formula", "one-wound")
            if getattr(a, "red_" + k.replace("-", "_"))]
    if len(reds) > 1:
        ap.error("one red knob at a time — each has to redden its own check alone")
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.out, reds[0] if reds else "",
               a.report_only, a.red_no_dangerous, a.engage_fold, a.cond_ap)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

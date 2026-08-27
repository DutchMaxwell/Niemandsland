"""GATE D1-B6a (NML-1073) — the recorded TRAY STREAM replays exactly on the
Rust twin, act by act, roll by roll, against the arena reference corpus.

WHAT IS BEING GATED. `tools/arena_match.gd` plays every combat die through
`_solo_tray_roll` on its own `_tray_rng`, seeded from `_dice_seed` after
deployment (main.gd:7120-7159, arena_match.gd:478). `AiActRecorder` writes that
stream, one JSON line per draw, to `dice.jsonl` — `count`, the `faces` that came
back, `roll_kind` ("attack"/"defense"), the owner/target unit keys, and `seq`/
`act` for ordering. `nml_core.Tray` (NML-1073 M5 D1-B3, dice.rs) is the pure
port of that same generator and the same `maxi(1, count)` rule: a recorded
`count: 0` line still carries exactly one face, because the table burns a draw
for a zero-die roll and reads it as nothing.

THE CHECK, on every game dir under `--ref`: read the one `arena_*.json`'s
`dice_seed` (checked against the seed embedded in the dir's own `..._s<seed>`
suffix — the two must agree, or the corpus is mislabeled, not merely a dice
mismatch), seed a fresh `nml_core.Tray(dice_seed)`, then walk `dice.jsonl` in
file order calling `tray.roll(count)` and comparing the returned faces to the
recorded `faces` EXACTLY. Two corpus-integrity invariants ride along for free
on the same walk: `seq` must climb by exactly 1 from its first value, and `act`
must never fall. Any of the three failing means the recording and the twin
have parted company, and it is reported the same way.

WHAT THIS IS NOT. The dice STREAM matching does not mean a REPLAYED game
matches — that needs the twin to also consume the tray at every site the table
does (D1-B4/B5), and this gate does not drive a game at all. It only proves the
generator and the `maxi(1, count)` rule are byte-identical to what was
recorded, on the real corpus, roll for roll.

RED PROOF: `--red-extra-draw` burns one tray draw before the walk begins. That
shifts the whole stream by one face, so the FIRST roll of every game must
mismatch — the same "if this changed nothing, the tool caught nothing"
convention `tools/charge_gate.py` uses for `--mode off`.

    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/dice_stream_gate.py \\
        --ref ~/selfplay_out/qbd_ref
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import nml_core  # noqa: E402

#: The seed a game dir's own name carries — `<pairing>_s<seed>` — checked
#: against the arena json's `dice_seed` so a mislabeled dir cannot masquerade
#: as a clean replay.
_DIR_SEED = re.compile(r"_s(\d+)$")


class DiceStreamError(ValueError):
    """A corpus problem the walk refuses to paper over: a missing or
    duplicate `arena_*.json`, or a `dice_seed` that disagrees with the seed
    embedded in the dir name."""


def dice_seed_of(gamedir: Path) -> int:
    """The one `arena_*.json`'s `dice_seed` for `gamedir`, verified against
    the seed embedded in the dir name. Raises `DiceStreamError` rather than
    silently trusting either field alone."""
    arenas = sorted(gamedir.glob("arena_*.json"))
    if len(arenas) != 1:
        raise DiceStreamError(
            "%s: expected exactly one arena_*.json, found %d"
            % (gamedir.name, len(arenas))
        )
    doc = json.loads(arenas[0].read_text(encoding="utf-8"))
    dice_seed = doc.get("dice_seed")
    m = _DIR_SEED.search(gamedir.name)
    if dice_seed is None or m is None or int(dice_seed) != int(m.group(1)):
        raise DiceStreamError(
            "%s: arena dice_seed %r != dir-name seed %r"
            % (gamedir.name, dice_seed, m and m.group(1))
        )
    return int(dice_seed)


def dice_lines(path: Path):
    """`dice.jsonl` records in FILE order, blank lines skipped."""
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


class GameResult:
    """One game's walk: the roll/kind tallies (always collected, even on a
    mismatch, since they describe the recording and not the replay), and the
    first mismatch as `(line_no, seq, roll_kind, detail)` or `None`."""

    __slots__ = ("name", "rolls", "kinds", "mismatch")

    def __init__(self, name: str):
        self.name = name
        self.rolls = 0
        self.kinds: collections.Counter[str] = collections.Counter()
        self.mismatch: tuple[int, int, str, str] | None = None


def walk_game(gamedir: Path, red_extra_draw: bool = False) -> GameResult:
    """Seed the twin tray from `gamedir`'s own `dice_seed` and replay
    `dice.jsonl` against it. `red_extra_draw` burns one tray draw first — the
    RED PROOF: it shifts the whole stream, so the FIRST roll must mismatch."""
    result = GameResult(gamedir.name)
    tray = nml_core.Tray(dice_seed_of(gamedir))
    if red_extra_draw:
        tray.roll(1)  # burn one draw — every later face is now off by one
    seq_prev = None
    act_prev = None
    for ln, rec in enumerate(dice_lines(gamedir / "dice.jsonl"), 1):
        result.rolls += 1
        result.kinds[rec["roll_kind"]] += 1
        seq, act = rec["seq"], rec["act"]
        if result.mismatch is None:
            if seq_prev is not None and seq != seq_prev + 1:
                result.mismatch = (
                    ln, seq, rec["roll_kind"],
                    "seq %d does not follow %d" % (seq, seq_prev),
                )
            elif act_prev is not None and act < act_prev:
                result.mismatch = (
                    ln, seq, rec["roll_kind"],
                    "act %d < previous act %d" % (act, act_prev),
                )
        seq_prev, act_prev = seq, act
        faces = tray.roll(rec["count"])
        if result.mismatch is None and faces != rec["faces"]:
            result.mismatch = (
                ln, seq, rec["roll_kind"],
                "expected=%s recorded=%s" % (faces, rec["faces"]),
            )
    return result


def run(ref: Path, limit: int, red_extra_draw: bool) -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    ok = 0
    total_rolls = 0
    per_game_rolls: list[int] = []
    kinds: collections.Counter[str] = collections.Counter()
    first = ""
    for d in games:
        result = walk_game(d, red_extra_draw)
        total_rolls += result.rolls
        per_game_rolls.append(result.rolls)
        kinds.update(result.kinds)
        if result.mismatch is None:
            ok += 1
            continue
        ln, seq, roll_kind, detail = result.mismatch
        print("MISMATCH %s line=%d seq=%d roll_kind=%s %s"
              % (d.name, ln, seq, roll_kind, detail))
        if not first:
            first = "%s:%d" % (d.name, ln)

    mismatched = len(games) - ok
    print()
    print("DICE_STREAM games=%d ok=%d rolls=%d mismatched_games=%d first=%s"
          % (len(games), ok, total_rolls, mismatched, first or "none"))
    if per_game_rolls:
        print("  rolls per game: min=%d median=%s max=%d"
              % (min(per_game_rolls), statistics.median(per_game_rolls), max(per_game_rolls)))
    if kinds:
        print("  roll_kind: %s" % ", ".join("%s=%d" % kv for kv in kinds.most_common(8)))

    if red_extra_draw:
        ok_red = len(games) > 0 and mismatched == len(games)
        print("  RED %s" % ("held (the extra draw desynced every tray)"
                             if ok_red else "FAILED — nothing moved"))
        return 0 if ok_red else 1
    return 0 if mismatched == 0 else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument(
        "--red-extra-draw", action="store_true",
        help="RED PROOF: burn one tray draw before the walk; every game must mismatch",
    )
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.limit, a.red_extra_draw)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

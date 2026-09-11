"""Extract the ONE committed fixture for #857's charge-landing pin.

Source record (READ-ONLY, on the box's gate bundle):

    ~/selfplay_out/qbg_ref_e8/
        blood_brothers_2000_vs_change_disciples_2000_s31/acts.jsonl

Act 46 (interleaved activation ordinal, `read_game`'s numbering) is the worst
`both_silent` charge of the epoch-8 reference: unit
`1788940198.45508_3222013045` ("Change Brothers") declares a charge on
`1788940196.17461_443796625` ("Blood Assault Brothers"), the recording ends the
charger SHORT of the target, and the port lands on a different vector. See
`analysis/BOTH_SILENT_857_2026-09-10.md` §6 and
`analysis/CHARGE_LANDING_E8_2026-09-09.md` §4.

The fixture carries the pre-act state, the picked action, the header the game
was recorded under, the tray's burn prefix at that act and the RECORDED
next-act centroid of charger and target — everything the replay needs, nothing
the box does not have. Rebuild with:

    python3 core/nml-core-py/tools/charge_landing_pin_fixture.py \
        --corpus ~/selfplay_out/qbg_ref_e8 \
        --out core/nml-core-py/tests/python/fixtures/charge_landing_pin/act46.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import shoot_replay_gate as srg

GAME = "blood_brothers_2000_vs_change_disciples_2000_s31"
ACT = 46
IN2M = 0.0254


def _centroid_in(positions) -> list[float]:
    n = len(positions)
    return [round(sum(p[0] for p in positions) / n / IN2M, 4),
            round(sum(p[2] for p in positions) / n / IN2M, 4)]


def _interleaved_state(game_dir: Path, ordinal: int) -> dict:
    """The pre-act state of activation `ordinal` (1-based, act|auto interleaved
    — the same numbering `read_game` stamps)."""
    raw = [json.loads(x) for x in (game_dir / "acts.jsonl").read_text().splitlines()
           if x.strip()]
    lines = [a for a in raw[1:] if a.get("kind") in ("act", "auto")]
    return lines[ordinal - 1]["state"]


def _record_path_in(game_dir: Path) -> str:
    """`~/`-relative on purpose: the repo must not carry a home directory."""
    try:
        rel = game_dir.resolve().relative_to(Path.home().resolve())
        return "~/" + rel.as_posix() + "/acts.jsonl"
    except ValueError:
        return "<corpus>/" + GAME + "/acts.jsonl"


def build(game_dir: Path) -> dict:
    head, lines, dice, seed = srg.read_game(game_dir)
    act_line = next(a for a in lines if int(a["act"]) == ACT)
    action = act_line["pick"]["action"]
    charger, target = action["unit"], action["charge"]

    burn = srg.burn_prefix(dice)
    i0 = srg.first_at_or_after(dice, ACT)
    pre = _interleaved_state(game_dir, ACT)
    post = _interleaved_state(game_dir, ACT + 1)

    return {
        "schema": 1,
        "source": {
            "game": GAME,
            "act": ACT,
            "record_path": _record_path_in(game_dir),
            "dice_seed": seed,
            "charger": charger,
            "target": target,
        },
        "note": (
            "e8 corpus f2935a61; `tray_seed` is the record's own dice_seed. The "
            "brief said seed 27; the arena record carries %d, and act 46 draws "
            "ZERO dice (both_silent), so either seed lands the same centroid."
            % seed),
        "header": {"profiles": head["profiles"], "terrain": head.get("terrain"),
                   "knobs": head.get("knobs")},
        "action": action,
        "state": pre,
        "tray_seed": seed,
        "burn_draws": burn[i0],
        "expected_next_centroid_in": _centroid_in(post["units"][charger]["positions"]),
        "target_next_centroid_in": _centroid_in(post["units"][target]["positions"]),
        "tolerance_in": 0.5,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus", default="~/selfplay_out/qbg_ref_e8")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    game_dir = Path(args.corpus).expanduser() / GAME
    fix = build(game_dir)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(fix, separators=(",", ":")) + "\n")
    print("wrote %s (%d bytes)" % (out, out.stat().st_size))
    print("expected next centroid (x,z) in:", fix["expected_next_centroid_in"],
          "target:", fix["target_next_centroid_in"], "burn:", fix["burn_draws"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""RED pin for the epoch-8 charge landing (#857) — the port's `charge_move`
against the ONE recorded `both_silent` charge it misses worst.

SOURCE RECORD (READ-ONLY, gate bundle, rebuilt by
`core/nml-core-py/tools/charge_landing_pin_fixture.py`):

    ~/selfplay_out/qbg_ref_e8/
        blood_brothers_2000_vs_change_disciples_2000_s31/acts.jsonl
    act 46 (interleaved activation ordinal), e8 bundle recorded at sha f2935a61.

WHAT IS PINNED. Act 46 is the canonical signature from
`analysis/BOTH_SILENT_857_2026-09-10.md` §6 / `analysis/CHARGE_LANDING_E8_
2026-09-09.md` §4: unit `1788940198.45508_3222013045` ("Change Brothers")
declares a charge on `1788940196.17461_443796625` ("Blood Assault Brothers"),
the recording ends the charger at (19.4, 9.5)" while the target never moves
(foe centroid delta 0.00"), and the port lands on a DIFFERENT vector entirely.
The recorded act is `both_silent` — no die is thrown — so the landing is the
charge-move executor's own output, reached through `mv::step::MoveRules::
charge_move` (`sim.rs:4858`; `movement=table` forces `charge_landing`,
`sim.rs:4909-4911`), NOT the rigid band clamp (`:4993`) and NOT the engage fold
(`fold` only touches the engage `side()` lists, exonerated 09.09.).

THE ASSERTION is the charger's next-act centroid, within 0.5" of the recorded
(19.4, 9.5)". On current main it is RED; the failure prints the measured and
the recorded centroid side by side. This is a RED pin like #863 — no fix in
this run.

The e8 header knobs (`engage_fold: true, cond_ap: true, rules_epoch: 8,
rule_vocab_version: 7`) are replayed as recorded, plus the movement and
charge-landing seams the brief names. `cond_ap` reaches the resolve through
`set_legacy_no_cond_ap(False)` (the shipped reading the e8 gate used), and the
header's own `cond_ap` key is inert in `acts::Knobs`.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURE = (Path(__file__).resolve().parent / "fixtures" / "charge_landing_pin"
           / "act46.json")


def _centroid_in(positions) -> tuple[float, float]:
    n = len(positions)
    return (sum(p[0] for p in positions) / n / 0.0254,
            sum(p[2] for p in positions) / n / 0.0254)


def test_857_the_port_lands_the_e8_charge_where_the_recording_landed():
    import nml_core

    fix = json.loads(FIXTURE.read_text())
    head, source = fix["header"], fix["source"]
    nml_core.set_legacy_no_cond_ap(False)
    core = nml_core.load(str(REPO))
    core.set_header({
        "profiles": head["profiles"],
        "terrain": head.get("terrain"),
        "knobs": dict(head.get("knobs") or {}, hero_attach=True,
                      charge_landing=True, movement=True, engage_fold=True),
    })

    tray = nml_core.Tray(fix["tray_seed"])
    if fix["burn_draws"]:
        tray.roll(fix["burn_draws"])
    nxt, report = core.resolve_with_tray(
        core.state_of(fix["state"]), fix["action"], nml_core.Rng(0), tray)

    charger = source["charger"]
    units = nxt.plain()["units"]
    got = _centroid_in(units[charger]["positions"])
    want = tuple(fix["expected_next_centroid_in"])
    delta = math.dist(got, want)

    print("charge-landing pin: measured %s in | recorded %s in | delta %.3f in "
          "| rolls=%r" % (tuple(round(v, 4) for v in got),
                          tuple(round(v, 4) for v in want), delta,
                          report["rolls"]))
    assert delta <= fix["tolerance_in"], (
        "charge landing diverged from the e8 recording: measured %s in vs "
        "recorded %s in (delta %.3f in > %.2f in); the port's `charge_move` "
        "lands on a different vector than the table did"
        % (tuple(round(v, 4) for v in got), tuple(round(v, 4) for v in want),
           delta, fix["tolerance_in"]))

    # The recorded act is `both_silent`: the same branch must consume no die.
    # Kept AFTER the landing pin so a wrong-reason roll divergence cannot mask
    # the centroid this fixture exists for.
    assert report["rolls"] == [], (
        "the recorded act 46 is `both_silent` but the port drew %r"
        % report["rolls"])

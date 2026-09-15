"""Wave 4 vocab c (PR #1008) — the three NEW token columns re-derive from the
act record itself.

`tokens::build` splices the unit feature vector out to 91 wide:

  * t[88]/t[89] — the unit-level terrain debuffs (`grants_rule` "Difficult
    Terrain" / "Dangerous Terrain", STANDALONE_SWEEP_A_2026-09-14), gated on
    `EPOCH_27_TERRAIN_DEBUFF`;
  * t[90] — the Vengeance marker pool ON the unit's joined-chain host,
    capped at 3 and scaled by it.

The exhaustive, hand-computed arithmetic proof lives in Rust
(`core/nml-core/src/tokens.rs`'s `terrain_debuff_and_vengeance_columns`).
This file carries the two things only the Python seam can prove, over the
`acts_25.jsonl` corpus `test_policy_tokens.py` already marshals:

  * a PRE-LEDGER act (the corpus has no `ledger` key on ANY unit) exports
    0.0 in all three columns — the byte-identity an old replay must keep;
  * a CURRENT-FORMAT act whose `ledger` carries the grants and the marker
    pool exports EXACTLY the values a reader re-derives from that same
    ledger dict — the expected numbers are computed from the record, never
    from a constant — and land on exactly one row (the injected unit is
    chosen with no chain neighbours, so the joined-chain walk cannot leak
    the grant onto another row).
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"

W = 91
DIFFICULT, DANGEROUS = 88, 89
VENGEANCE = 90


def _read_acts(name: str):
    lines = [json.loads(l) for l in open(FIXTURES / name, encoding="utf-8")]
    return lines[0], lines[1:]


def _current_header(header):
    """The acts_25 corpus predates `knobs.rules_epoch`, so its replay default
    reads LOW and the terrain-debuff gate stays closed — the recorded
    behaviour. Both halves of this file run under the CURRENT epoch instead
    (a live corpus carries its own stamp), so the pre-ledger zeros prove the
    ABSENT LEDGER alone, not the epoch default. The epoch comes from
    `BUILD_INFO` — the build's own `CURRENT_RULES_EPOCH` — never a constant."""
    header = copy.deepcopy(header)
    header.setdefault("knobs", {})["rules_epoch"] = nml_core.BUILD_INFO["rules_epoch"]
    return header


def _first_menu_export(core, header, acts):
    """The smoke loop's first usable act: `plan_with_rollout(cands=True)` for
    the menu, then `policy_tokens` off the same state."""
    core.set_header(header)
    for act in acts:
        rec = act["trace"].get("arbitration")
        sig = rec["sig"] if rec else None
        state = core.state_of(act["state"])
        got = core.plan_with_rollout(state, act["player"], act["statics"], sig, cands=True)
        if not got["used"]:
            continue
        tr = got["trace"]
        best_idx = tr["scored"][tr["best_idx"]]["idx"]
        toks = core.policy_tokens(state, act["player"], tr["cands"], best_idx)
        return act, state, toks
    raise AssertionError("the corpus declined everywhere — the gate proves nothing")


def _nonzero_rows(toks, col):
    return [k for k, row in enumerate(toks["units"])
            if toks["units_mask"][k] and abs(row[col]) > 1e-9]


def test_pre_ledger_corpus_exports_zero_in_the_three_new_columns():
    """acts_25.jsonl predates the per-unit `ledger` key on every unit — the
    pre-existing default (`io.rs`: absent ledger folds to nothing). All three
    new columns must read 0.0 on every masked-in row, exactly as the corpus
    was recorded."""
    header, acts = _read_acts("acts_25.jsonl")
    assert not any("ledger" in (u or {}) for act in acts
                   for u in act["state"]["units"].values()), "corpus is no longer pre-ledger"
    core = nml_core.load(str(REPO))
    _, _, toks = _first_menu_export(core, _current_header(header), acts)
    assert len(toks["units"][0]) == W
    for col in (DIFFICULT, DANGEROUS, VENGEANCE):
        assert not _nonzero_rows(toks, col), (
            "column %d is non-zero on a pre-ledger act" % col)


def test_new_columns_re_derive_from_the_acts_own_ledger():
    """The current-format half: inject a ledger onto one chain-free unit and
    re-derive the three columns from THAT dict — grants → 1.0, the marker
    pool → min(n, 3)/3 — and require the export to answer the same numbers on
    exactly one row (zero everywhere else on live rows)."""
    header, acts = _read_acts("acts_25.jsonl")
    units = next(a["state"]["units"] for a in acts)
    unit_key = next(k for k, u in units.items()
                    if isinstance(u, dict) and u.get("alive")
                    and not u.get("attached") and not u.get("attached_to"))
    ledger = {"buffs": [{"grants_rule": "Difficult Terrain"},
                        {"grants_rule": "Dangerous Terrain"}],
              "vengeance_markers": 2}
    want = [1.0, 1.0, min(ledger["vengeance_markers"], 3) / 3.0]

    injected = copy.deepcopy(acts[0])
    injected["state"]["units"][unit_key]["ledger"] = ledger
    core = nml_core.load(str(REPO))
    _, _, toks = _first_menu_export(core, _current_header(header), [injected])

    rows = [k for k, row in enumerate(toks["units"])
            if toks["units_mask"][k] and abs(row[DIFFICULT] - want[0]) < 1e-9]
    assert len(rows) == 1, "the grant leaked onto %d rows, not one" % len(rows)
    row = toks["units"][rows[0]]
    assert abs(row[DANGEROUS] - want[1]) < 1e-9
    assert abs(row[VENGEANCE] - want[2]) < 1e-6, "vengeance %r, want %r" % (row[VENGEANCE], want[2])
    for col in (DIFFICULT, DANGEROUS, VENGEANCE):
        for k, mask in enumerate(toks["units_mask"]):
            if mask and k != rows[0]:
                assert abs(toks["units"][k][col]) < 1e-9, (
                    "row %d column %d should be 0" % (k, col))

"""NML-1158b step 1 — the policy_dump.jsonl schema gate.

tools/policy_dump.gd is the policy wave's corpus writer: per recorded act and
unit menu it emits the AiClone feature vectors (append-only layout) plus the
recorded pick index. The design (POLICY_NET_DESIGN_2026-09-01 step 1) pins
two checks on real qbg_ref acts, and this gate adds the schema invariants
every later reader (policy_rows.py, step 2) leans on:

  * the header carries the schema stamp and the append-only vec width;
  * every candidate vec has exactly that width, on every row;
  * the dumped candidate count equals trace.menus' size for that unit;
  * the recorded pick's vec is among the dumped vecs — matched by kind+dest
    (act_recorder action shape, ai_planner.gd:623-625), its one-hot kind slot
    and snapped destination identify it inside the row's own vecs.

Skips when this machine has no dump artifact or corpus (CI has neither).
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

DUMP = Path(os.environ.get("NML_POLICY_DUMP",
                           os.path.expanduser("~/nml-mission/policy_out/policy_dump.jsonl")))
CORPUS = Path(os.environ.get("NML_POLICY_CORPUS",
                             os.path.expanduser("~/selfplay_out/qbg_ref")))
IN2M = 0.0254  # BattleSim.IN2M — plain-state positions are meters, menu_tuples divides by it for game-inches
DEST_TOL = 0.06  # the 0.1-inch snap in menu_tuples (±0.05) + float slack
DEST_X_SCALE = 36.0  # AiClone.DEST_X_SCALE / DEST_Z_SCALE — vec slots are table fractions
DEST_Z_SCALE = 24.0


def _header_and_rows() -> tuple[dict, list[dict]]:
    lines = [ln for ln in DUMP.read_text().splitlines() if ln.strip()]
    header = json.loads(lines[0])
    return header, [json.loads(ln) for ln in lines[1:]]


@pytest.mark.skipif(not DUMP.exists(), reason="no policy_dump.jsonl artifact on this machine")
def test_header_schema() -> None:
    header, rows = _header_and_rows()
    assert header["kind"] == "header" and header["schema"] == "policy_dump/1"
    assert header["vec_layout"] == "kinds:5,plain:5,geo:8,cover:1,sight:2"
    assert header["act_dim"] == 20 and header["geo_dim"] == 8
    assert rows, "a dump with a header must carry rows"
    for row in rows:
        assert row["kind"] == "menu_row" and isinstance(row["cands"], list) and row["cands"]
        for cand in row["cands"]:
            assert len(cand["vec"]) == header["act_dim"]
        assert -1 <= row["pick_idx"] < len(row["cands"])


@pytest.mark.skipif(not (DUMP.exists() and CORPUS.is_dir()),
                    reason="no dump artifact or qbg_ref corpus on this machine")
def test_candidate_count_matches_recorded_menus() -> None:
    _, rows = _header_and_rows()
    menus: dict[tuple[str, int, str], int] = {}
    for game in sorted({r["game"] for r in rows}):
        acts = (CORPUS / game / "acts.jsonl").read_text().splitlines()
        for no, ln in enumerate(acts[1:], 1):
            if ln.strip():
                for unit, cands in json.loads(ln).get("trace", {}).get("menus", {}).items():
                    menus[(game, no, unit)] = len(cands)
    assert rows
    for row in rows:
        key = (row["game"], row["act_no"], row["unit"])
        assert key in menus, f"dumped row {key} has no recorded menu"
        assert len(row["cands"]) == menus[key], f"candidate count drift at {key}"


@pytest.mark.skipif(not DUMP.exists(), reason="no policy_dump.jsonl artifact on this machine")
def test_pick_vec_is_one_of_the_dumped_vecs() -> None:
    _, rows = _header_and_rows()
    picked = [r for r in rows if r["pick_idx"] >= 0]
    assert picked, "no row with a recorded pick — the dump cannot serve step 2"
    for row in picked:
        cand = row["cands"][row["pick_idx"]]
        vec = cand["vec"]
        assert sum(1.0 for v in vec[:5] if abs(v - 1.0) < 1e-9) == 1.0
        assert abs(vec[cand["kind"]] - 1.0) < 1e-9, "kind slot must be the one-hot"
        dest_m = cand["src_dest"]
        if dest_m is not None:
            assert abs(vec[5] * DEST_X_SCALE - dest_m[0] / IN2M) <= DEST_TOL
            assert abs(vec[6] * DEST_Z_SCALE - dest_m[2] / IN2M) <= DEST_TOL

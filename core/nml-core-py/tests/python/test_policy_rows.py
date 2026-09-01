"""NML-1158b step 2 — the policy_rows join on a 2-act synthetic game.

One synthetic game, two acts (side 1 then side 2), result won by p1.
The winner lever (clone_train.py:113-115) must pay winner rows 1.0 and
loser rows --winner-weight. RED PROOF: NML_TEST_WINNER=p2 swaps the
winner — every weight flips and these asserts fail — then restore.
Fully synthetic: runs on CI, no dump artifact or corpus needed.
"""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import policy_rows  # noqa: E402

WW = "0.5"
WINNER = os.environ.get("NML_TEST_WINNER", "p1")   # RED: set to p2, expect failure


def _fixture(tmp_path):
    c = lambda i, rs: {"i": i, "kind": 1, "rs": rs, "vec": [0.0] * 20}
    rows = [{"kind": "header", "schema": "policy_dump/1", "act_dim": 20},
            {"kind": "menu_row", "game": "g", "act_no": 1, "unit": "u1", "side": 1,
             "board": [[1, 0.0, 0.0]], "pick_idx": 0, "cands": [c(0, 0.4), c(1, 0.2), c(2, None)]},
            {"kind": "menu_row", "game": "g", "act_no": 2, "unit": "u2", "side": 2,
             "board": [[2, 0.0, 0.0]], "pick_idx": 1, "cands": [c(0, 0.1), c(1, 0.3), c(2, 0.5)]}]
    d = tmp_path / "dump.jsonl"
    d.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    (tmp_path / "g").mkdir()
    json.dump({"winner": WINNER, "objectives": {"vp1": 1, "vp2": 0}, "rounds_played": 4},
              open(tmp_path / "g" / "arena_x.json", "w"))
    return d, tmp_path / "rows.jsonl"


def test_two_act_join_and_winner_lever(tmp_path):
    d, out = _fixture(tmp_path)
    policy_rows.main(["--dump", str(d), "--corpus", str(tmp_path), "--out", str(out),
                      "--winner-weight", WW])
    hdr, *rows = [json.loads(ln) for ln in out.read_text().splitlines() if ln.strip()]
    assert hdr["schema"] == "policy_rows/1" and hdr["rows"] == 2 and hdr["dropped"] == 0
    r1, r2 = rows
    assert WINNER == "p1" and r1["winner"] == "p1" and r1["vp"] == [1, 0]
    assert r1["pick_rs"] == 0.4 and r1["menu_mean_rs"] == pytest.approx(0.3)
    assert r2["pick_rs"] == 0.3 and r2["menu_mean_rs"] == pytest.approx(0.3)
    assert r1["weight"] == 1.0 and r2["weight"] == 0.5    # the lever, per side


def test_red_pick_index_refused(tmp_path):
    d, out = _fixture(tmp_path)
    with pytest.raises(SystemExit):
        policy_rows.main(["--dump", str(d), "--corpus", str(tmp_path), "--out", str(out),
                          "--winner-weight", WW, "--red"])

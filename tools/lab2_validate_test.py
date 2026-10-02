"""lab2_validate: one fixture per row problem the prereg's section 6 names (missing row, duplicate/conflicting row,
wrong seat/net/hash/epoch, illegal action, unsupported path), plus the pilot's row checks (unknown row, tree stamp
iff tree arm, non-finite timing, dirty build). Every problem fails validation and withholds every PASS flag."""
import importlib.util
import math
import os

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


val = _load("lab2_validate")
SHA = {"prereg_sha256": "p" * 64, "model_sha256": "m" * 64, "wheel_sha256": "w" * 64, "rules_epoch": 68}
HEADERS = {"I": {"1": "i", "2": "i"}, "L": {"1": "l", "2": "i"}}


def _row(rid, arm="L", y=1):
    tree = {"completed": 8, "deadline_hit": False, "batches": 1, "frontier": 8, "terminal": 0}
    dec = [{"seq": 0, "side": 1, "arm": arm, "allocated_us": 900, "elapsed_us": 850, "overshoot_us": 0,
            "tree": tree if arm in val.TREE_ARMS else None, "deadline": None, "search": None, "net_calls": 1},
           {"seq": 1, "side": 2, "arm": "I", "allocated_us": None, "elapsed_us": 400, "overshoot_us": None,
            "tree": None, "deadline": None, "search": None, "net_calls": 1}]
    return {"schema": val.SCHEMA, "prereg_sha256": SHA["prereg_sha256"], "row_id": rid, "arm": arm, "seat": 1,
            "build": {"commit": "c", "dirty": False, "rules_epoch": 68, "wheel_sha256": SHA["wheel_sha256"]},
            "model_sha256": SHA["model_sha256"], "header_sha256": HEADERS[arm], "decisions": dec,
            "net": {"1": {"calls": 3, "leaves": 9}, "2": {"calls": 2, "leaves": 5}}, "y": y, "winner": "p1",
            "valid": True, "reason": None, "wall_s": 1.5, "rss_hwm_mib": 300, "done": True}


def _set():
    manifest = {"rows": {"b1_L": {"arm": "L", "seat": 1}, "b1_I": {"arm": "I", "seat": 1}}, "headers": HEADERS, **SHA}
    return [_row("b1_L"), _row("b1_I", arm="I", y=0.5)], manifest


def test_a_clean_set_passes_and_keeps_its_flags():
    ok, probs = val.validate(*_set())
    assert ok and probs == [] and val.pass_flags(ok, {"A_T": True, "net": False}) == {"A_T": True, "net": False}



def test_in_memory_rows_with_int_seat_keys_validate_like_their_json():
    rows, manifest = _set()
    for row in rows:
        row["net"] = {int(s): v for s, v in row["net"].items()}
        row["header_sha256"] = {int(s): h for s, h in row["header_sha256"].items()}
    assert val.validate(rows, manifest) == (True, [])

MUTATIONS = {
    "missing_id": lambda rows: rows.pop(),
    "unknown_id": lambda rows: rows.append(_row("ghost")),
    "duplicate_id": lambda rows: rows.append(dict(rows[0], wall_s=9.0)),
    "conflicting_duplicate": lambda rows: rows.append(dict(rows[0], y=0, winner="p2")),
    "wrong_seat": lambda rows: rows[0].update(seat=2),
    "net_inactive": lambda rows: rows[0]["net"].update({"2": {"calls": 0, "leaves": 0}}),
    "wrong_model_sha256": lambda rows: rows[0].update(model_sha256="x" * 64),
    "wrong_header_sha256": lambda rows: rows[0].update(header_sha256=HEADERS["I"]),
    "wrong_rules_epoch": lambda rows: rows[0]["build"].update(rules_epoch=67),
    "dirty_build": lambda rows: rows[0]["build"].update(dirty=True),
    "tree_stamp": lambda rows: rows[1]["decisions"][0].update(tree={"completed": 1}),
    "non_finite": lambda rows: rows[0]["decisions"][0].update(elapsed_us=math.nan),
}


@pytest.mark.parametrize("problem", sorted(MUTATIONS))
def test_each_problem_fails_validation_and_withholds_every_flag(problem):
    rows, manifest = _set()
    MUTATIONS[problem](rows)
    ok, probs = val.validate(rows, manifest)
    assert not ok and problem in {p["problem"] for p in probs}, probs
    assert val.pass_flags(ok, {"A_T": True, "B_LI": True}) == {"A_T": False, "B_LI": False}


@pytest.mark.parametrize("reason", ["illegal", "unported:deadly", "overflow", "unsupported"])
def test_an_injected_failure_report_fails_validation_instead_of_scoring(reason):
    rows, manifest = _set()
    rows[0].update(valid=False, reason=reason, y=None)
    ok, probs = val.validate(rows, manifest)
    assert not ok and {"row_id": "b1_L", "problem": "invalid", "detail": reason} in probs


"""Pure-python tests of parity_compare.py (no nml_core, no Godot)."""
import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).with_name("parity_compare.py")


def rec(seed, faces=(5, 2), owner="Att", alive=4):
    roll = {"kind": "attack", "count": 2, "target": 4, "faces": list(faces), "owner": owner}
    return {"seed": seed, "epoch": 73, "def_alive": alive, "rolls": [roll]}


def run(tmp_path, table, core, exceptions=()):
    paths = {}
    for name, rows in (("t.jsonl", table), ("c.jsonl", core)):
        paths[name] = tmp_path / name
        paths[name].write_text("".join(json.dumps(r) + "\n" for r in rows))
    exc, out = tmp_path / "e.json", tmp_path / "r.json"
    exc.write_text(json.dumps(list(exceptions)))
    p = subprocess.run([sys.executable, str(SCRIPT), "--table", str(paths["t.jsonl"]), "--core",
                        str(paths["c.jsonl"]), "--scenario", "s", "--exceptions", str(exc), "--out", str(out)],
                       capture_output=True, text=True)
    return p.returncode, json.loads(out.read_text())


def entry(since="2026-11-11"):
    return {"id": "X1", "scenario": "s", "lane": "shoot", "since": since, "reason": "r", "pr": 0, "owner_lane": "l"}


def test_equal_traces_pass_even_with_wrapped_roller(tmp_path):
    rc, res = run(tmp_path, [rec(0, owner="AI (Att)")], [rec(0)])
    assert rc == 0 and res["identical"] == 1


def test_planted_face_difference_fails(tmp_path):
    rc, res = run(tmp_path, [rec(0), rec(1)], [rec(0), rec(1, faces=(5, 3))])
    assert rc == 1 and res["mismatching_seeds"] == [1]


def test_stale_exception_fails(tmp_path):
    rc, res = run(tmp_path, [rec(0)], [rec(0)], [entry()])
    assert rc == 1 and "stale" in res["problems"][0]


def test_future_dated_exception_fails(tmp_path):
    rc, res = run(tmp_path, [rec(0)], [rec(0, faces=(1, 1))], [entry(since="2026-11-12")])
    assert rc == 1 and any("after the baseline" in p for p in res["problems"])

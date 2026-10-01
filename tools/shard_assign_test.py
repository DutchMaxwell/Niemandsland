import json
import os
import statistics
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import shard_assign  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_lpt_max_shard_is_within_15_percent_of_the_mean():
    os.chdir(ROOT)
    suites = shard_assign.suites_on_disk()
    weights = json.load(open(shard_assign.WEIGHTS))
    _, load = shard_assign.assign(suites, weights, 10)
    assert max(load) <= 1.15 * statistics.mean(load), load


def test_unknown_suites_get_the_median_weight_and_are_still_assigned_once():
    weights = {"a": 10.0, "b": 2.0, "c": 4.0}
    shards, _ = shard_assign.assign(["a", "b", "c", "new"], weights, 2)
    flat = sorted(s for sh in shards for s in sh)
    assert flat == ["a", "b", "c", "new"]
    # median of known = 4.0: "new" weighs 4.0, lands next to "b" (a alone = 10)
    assert "new" in next(sh for sh in shards if "b" in sh)


def test_check_fails_when_a_suite_falls_outside_every_shard(monkeypatch):
    os.chdir(ROOT)
    real = shard_assign.assign

    def lossy(suites, weights, shards):
        out, load = real(suites, weights, shards)
        out[0] = out[0][1:]  # silently drop one suite
        return out, load

    monkeypatch.setattr(shard_assign, "assign", lossy)
    monkeypatch.setattr(sys, "argv", ["shard_assign.py", "--shards", "10", "--check"])
    assert shard_assign.main() == 1


def test_check_passes_on_the_real_tree():
    os.chdir(ROOT)
    r = subprocess.run([sys.executable, "tools/shard_assign.py", "--shards", "10", "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout

#!/usr/bin/env python3
"""Tests for tools/lab2_pool.py: real spawn-mode worker processes on a toy cluster function (no data needed).
Run: python3 -m pytest -q tools/lab2_pool_test.py"""
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import lab2_pool as pool  # noqa: E402


def init(out_dir):
    return {"out_dir": out_dir}


def work(ctx, cid, payload):
    """A toy cluster: every unit of the cluster writes one row file, deterministic except wall_s / rss."""
    for unit in payload:
        row = {"row_id": "%s_%s" % (cid, unit), "y": len(cid) * 10 + unit, "pid": os.getpid(), "wall_s": 0.1 * unit,
               "rss_hwm_mib": pool.vmhwm_mib()}
        json.dump(row, open(os.path.join(ctx["out_dir"], row["row_id"] + ".json"), "w"), sort_keys=True)
    return {"units": list(payload)}


CLUSTERS = {"posA": [0, 1, 2], "posBB": [0, 1, 2], "posC": [0, 1, 2], "posDDD": [0, 1, 2]}


def rows(directory):
    out = {}
    for name in sorted(os.listdir(directory)):
        r = json.load(open(os.path.join(directory, name)))
        out[name] = r
    return out


def test_two_workers_write_the_same_rows_as_one_and_a_cluster_never_spans_workers(tmp_path):
    one, two = tmp_path / "one", tmp_path / "two"
    one.mkdir(), two.mkdir()
    r1 = pool.run_clusters(CLUSTERS, 1, init, work, (str(one),), key="k")
    r2 = pool.run_clusters(CLUSTERS, 2, init, work, (str(two),), key="k")
    assert [r["id"] for r in r1] == [r["id"] for r in r2] == pool.schedule_order(list(CLUSTERS), "k")
    strip = lambda d: {n: {k: v for k, v in r.items() if k not in ("wall_s", "rss_hwm_mib", "pid")} for n, r in d.items()}
    assert strip(rows(str(one))) == strip(rows(str(two))) and len(rows(str(two))) == 12   # byte-identical but wall/RSS/pid
    for cid in CLUSTERS:  # every row file of a cluster was written by ONE process
        assert len({r["pid"] for n, r in rows(str(two)).items() if n.startswith(cid + "_")}) == 1
    assert len({r["pid"] for r in r2}) <= 2 and os.getpid() not in {r["pid"] for r in r2}   # real worker processes
    peaks, total = pool.worker_hwms(r2)
    assert total == sum(peaks.values()) and all(v > 0 for v in peaks.values())


def test_scheduler_order_is_the_sha256_order_and_independent_of_listing_order():
    ids = ["b", "a", "c", "d"]
    assert pool.schedule_order(ids, "k") == pool.schedule_order(ids[::-1], "k")
    import hashlib
    want = sorted(ids, key=lambda c: hashlib.sha256(("k:" + c).encode()).hexdigest())
    assert pool.schedule_order(ids, "k") == want


def test_p1_rule_on_synthetic_peaks(tmp_path):
    assert pool.p1_workers([300, 200])["workers"] == 4          # 4 x 300 = 1200 MiB <= 6 GiB
    assert pool.p1_workers([512])["workers"] == 4               # 4 x 512 = 2048 <= 6144, and 512 is allowed
    assert pool.p1_workers([513])["workers"] == 0               # above the 512 MiB per-worker cap: no allowed N
    f = tmp_path / "pilot.json"
    f.write_text(json.dumps({"worker_hwm_mib": {"1": 100.0, "2": 480.0}}))
    assert pool.main(["p1", "--rss", str(f)]) == 0
    f.write_text("[600]")
    assert pool.main(["p1", "--rss", str(f)]) == 1


def die_on_bb(ctx, cid, payload):
    """A worker killed outright mid-cluster, as an uncaught core panic does."""
    if cid == "posBB":
        os._exit(3)
    return work(ctx, cid, payload)


def test_a_dying_worker_fails_the_run_instead_of_hanging(tmp_path):
    import concurrent.futures
    import threading
    out = {}
    t = threading.Thread(target=lambda: out.update(r=_run_or_raise(tmp_path)), daemon=True)
    t.start()
    t.join(120)                                   # the old Pool waited forever for the lost cluster
    assert not t.is_alive(), "run_clusters hung on a dead worker"
    assert isinstance(out["r"], concurrent.futures.process.BrokenProcessPool)


def _run_or_raise(tmp_path):
    try:
        return pool.run_clusters(CLUSTERS, 2, init, die_on_bb, (str(tmp_path),))
    except Exception as e:  # noqa: BLE001 - the test reads the exception type
        return e

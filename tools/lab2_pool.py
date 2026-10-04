#!/usr/bin/env python3
"""Workers, scheduler and the P1 rule of the stage-0 lab driver (tree plan step 25).

`run_clusters` runs scheduling UNITS in sha256(scheduler key : unit id) order, one unit per task, one `init()` context
(core + net) per worker process (spawn mode); a unit never spans workers. The caller chooses the unit: since stage-0
amendment A4.1 the endings, the full games and the P9 rows schedule ONE row/game per unit (a complete cluster pinned
one worker to its heaviest position or block); the source keeps one slot per unit (its candidates run in order until
the first eligible). Every task reports its worker pid and VmHWM.
`p1_workers` is prereg P1 as amendment A4 widened it for the pilot's dedicated >= 32-vCPU box: the highest N in 1..24 with
N x max worker VmHWM <= 12 GiB (24 x 512 MiB) and max <= 512 MiB (was 1..4 and 6 GiB on the laptop).
Run:  python3 tools/lab2_pool.py p1 --rss worker_hwms.json
"""
import argparse
import hashlib
import json
import multiprocessing
import os
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lab2_rows import vmhwm_mib  # noqa: E402

CAP_MIB, PER_WORKER_MIB, MAX_WORKERS = 12 * 1024, 512, 24   # amendment A4 (was 6 GiB, 4 workers)
_CTX = {}


def schedule_order(cluster_ids, key):
    """Cluster ids in sha256(key : id) order: independent of the order they were listed in."""
    return sorted(cluster_ids, key=lambda c: hashlib.sha256(("%s:%s" % (key, c)).encode()).hexdigest())


def _init(init, args):
    _CTX["ctx"] = init(*args)


def _task(work, cid, payload):
    return {"id": cid, "pid": os.getpid(), "result": work(_CTX["ctx"], cid, payload), "hwm_mib": vmhwm_mib()}


def run_clusters(clusters, workers, init, work, init_args=(), key=""):
    """clusters {id: payload}; `init` / `work` are module-level callables (spawn pickles them by name). Returns
    the task reports in schedule order, whatever order the workers finished in."""
    order = schedule_order(list(clusters), key)
    if workers <= 1:
        _init(init, init_args)
        return [_task(work, cid, clusters[cid]) for cid in order]
    # an executor, not a Pool: a worker that dies (a core panic outside `guarded`) fails the run with
    # BrokenProcessPool, where a Pool replaces the worker and waits forever for the lost cluster
    with ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context("spawn"), initializer=_init,
                             initargs=(init, init_args)) as ex:
        pending = [ex.submit(_task, work, cid, clusters[cid]) for cid in order]
        return [p.result() for p in pending]


def worker_hwms(reports):
    """{pid: highest VmHWM that worker reported} and their sum (MiB)."""
    peak = {}
    for r in reports:
        peak[r["pid"]] = max(peak.get(r["pid"], 0.0), r["hwm_mib"])
    return peak, sum(peak.values())


def p1_workers(hwms):
    """Prereg P1 from the per-worker peaks of the pilot (MiB); 0 = a worker above 512 MiB, no allowed N."""
    top = max(hwms)
    n = max((n for n in range(1, MAX_WORKERS + 1) if n * top <= CAP_MIB), default=0) if top <= PER_WORKER_MIB else 0
    return {"workers": n, "max_worker_hwm_mib": top, "cap_mib": CAP_MIB, "per_worker_mib": PER_WORKER_MIB}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("p1")
    p.add_argument("--rss", required=True, help="JSON list of worker peaks (MiB) or a pilot.json with worker_hwm_mib")
    a = ap.parse_args(argv)
    data = json.load(open(a.rss))
    res = p1_workers(list(data["worker_hwm_mib"].values()) if isinstance(data, dict) else data)
    print("[p1] " + json.dumps(res, sort_keys=True))
    return 0 if res["workers"] else 1


if __name__ == "__main__":
    sys.exit(main())

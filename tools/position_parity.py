#!/usr/bin/env python3
"""Run Stage A parity and reject fixture, coverage, or endpoint regressions.

Build/install the GDExtension first. Initial baseline creation is explicit:
  python3 tools/position_parity.py --out /tmp/parity --runs 3 \
      --record-baseline 'Initial Stage A measurement'
Normal CI/development runs omit --record-baseline. No workflow file is edited.
"""

from __future__ import annotations
import argparse
from collections import Counter
import copy
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time

REPO = Path(__file__).resolve().parents[1]
FIXTURES = REPO / "test/fixtures/position_parity/cases.json"
BASELINE = REPO / "test/fixtures/position_parity/baseline.json"
EPS_IN = 1e-9
IN2M = 0.0254
REASONS = (
    "parse_error",
    "caught_panic",
    "charge_final_placement",
    "whole_unit_shorten",
    "base_shapes",
    "skirmish_chain",
    "charge_snap",
    "boxed_escape",
    "coherency_hold",
)
SCRIPT_ERROR = re.compile(
    r"SCRIPT ERROR|Parse Error|Parser Error|SCRIPT-FEHLER|Skriptfehler|Parser-Fehler|POSITION_PARITY_ERROR",
    re.I,
)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def fingerprint(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def stable_rows(report):
    rows = copy.deepcopy(report["rows"])
    for row in rows:
        row.pop("timing_us", None)
    return rows


def distance(a, b, scale=IN2M):
    if (
        len(a) != len(b)
        or len(a) not in (2, 3)
        or not all(type(x) in (int, float) and math.isfinite(x) for x in [*a, *b])
    ):
        raise ValueError("invalid/nonfinite coordinates")
    return math.dist(a, b) / scale


def tier(delta):
    return 0 if delta <= EPS_IN else (1 if delta <= 0.5 else 2)


def measure(fixtures, report):
    expected = {c["id"]: c for c in fixtures["cases"]}
    if len(expected) != len(fixtures["cases"]):
        raise ValueError("duplicate fixture IDs")
    observed = [r["id"] for r in report["rows"]]
    if len(observed) != len(set(observed)) or set(observed) != set(expected):
        raise ValueError("missing, duplicate, or unexpected report rows")
    by_reason = Counter({reason: 0 for reason in REASONS})
    stats = {
        "n": len(expected),
        "equal": 0,
        "within_0.5in": 0,
        "declined": 0,
        "models": {
            "n": 0,
            "equal": 0,
            "within_0.5in": 0,
            "beyond_0.5in": 0,
            "declined": 0,
        },
        "formation": {
            "n": 0,
            "equal": 0,
            "within_0.5in": 0,
            "declined": 0,
            "recorded_equal": 0,
        },
    }
    cases = {}
    for row in report["rows"]:
        f = expected[row["id"]]
        if (
            not row["table_end"]
            or len(row["table_end"]) != len(row["model_ids"])
            or len(set(row["model_ids"])) != len(row["model_ids"])
        ):
            raise ValueError(f'{row["id"]}: invalid table model identities')
        units = {u["id"]: u for u in f["units"]}
        actor = units[f["action"]["unit"]]
        moving_ids = [
            f"{key}:{i}"
            for key in [actor["id"], *actor["attached"]]
            for i in range(len(units[key]["positions"]))
        ]
        if row["model_ids"] != moving_ids:
            raise ValueError(f'{row["id"]}: fixture/table model identities differ')
        # Validate the oracle even if the Rust boundary fails.
        for point in row["table_end"]:
            if len(point) != 3:
                raise ValueError(f'{row["id"]}: expected world Vector3 coordinates')
            distance(point, point)
        if ("formation_call" in f) != ("formation" in row):
            raise ValueError(f'{row["id"]}: missing or unexpected formation comparison')
        reasons = []
        if not row["rust_ok"]:
            reason = row["boundary_reason"]
            if reason not in ("parse_error", "caught_panic"):
                raise ValueError(f'{row["id"]}: untyped boundary failure')
            reasons.append(reason)
        else:
            if row["rust_model_ids"] != row["model_ids"] or len(row["rust_end"]) != len(
                row["table_end"]
            ):
                raise ValueError(f'{row["id"]}: model identity/count mismatch')
            missing = set(row["table_stages"]) - set(row["rust_capabilities"])
            if "charge_final_placement" in missing:
                missing.discard("final_placement")
            if missing - set(REASONS):
                raise ValueError(f"unknown skipped stage: {missing-set(REASONS)}")
            reasons.extend(sorted(missing))
        if "formation" in row and not row["formation"]["ok"]:
            reason = row["formation"]["reason"]
            if reason not in ("parse_error", "caught_panic"):
                raise ValueError(f'{row["id"]}: untyped formation boundary failure')
            reasons.append(reason)
        reasons = sorted(set(reasons))
        deltas = (
            [distance(a, b) for a, b in zip(row["table_end"], row["rust_end"])]
            if row["rust_ok"]
            else []
        )
        ranks = [tier(x) for x in deltas]
        n = len(row["table_end"])
        stats["models"]["n"] += n
        if reasons:
            stats["declined"] += 1
            stats["models"]["declined"] += n
            by_reason.update(reasons)
        else:
            stats["equal"] += int(all(r == 0 for r in ranks))
            stats["within_0.5in"] += int(all(r <= 1 for r in ranks))
            stats["models"]["equal"] += sum(r == 0 for r in ranks)
            stats["models"]["within_0.5in"] += sum(r <= 1 for r in ranks)
            stats["models"]["beyond_0.5in"] += sum(r == 2 for r in ranks)
        cases[row["id"]] = {
            "reasons": reasons,
            "model_ids": row["model_ids"],
            "delta_in": deltas,
            "tiers": ranks,
            "all_models_within": not reasons and all(r <= 1 for r in ranks),
        }
        if "formation" in row:
            formation = row["formation"]
            group = stats["formation"]
            group["n"] += 1
            count = len(f["formation_call"]["model_pos"])
            if (
                not count
                or len(formation["table"]) != count
                or len(formation["recorded"]) != count
            ):
                raise ValueError("invalid formation reference count")
            for point in [*formation["table"], *formation["recorded"]]:
                distance(point, point, 1)
            if not formation["ok"]:
                group["declined"] += 1
            else:
                if len(formation["rust"]) != count:
                    raise ValueError("invalid formation output count")
                errors = [
                    distance(a, b, 1)
                    for a, b in zip(formation["table"], formation["rust"])
                ]
                historical = [
                    distance(a, b, 1)
                    for a, b in zip(formation["table"], formation["recorded"])
                ]
                group["equal"] += int(all(x <= EPS_IN for x in errors))
                group["within_0.5in"] += int(all(x <= 0.5 for x in errors))
                group["recorded_equal"] += int(
                    len(historical) == len(errors)
                    and all(x <= EPS_IN for x in historical)
                )
                cases[row["id"]]["formation_tiers"] = [tier(x) for x in errors]
    stats["by_reason"] = dict(sorted(by_reason.items()))
    return {"summary": stats, "cases": cases}


def summary_line(measured):
    s = measured["summary"]
    return (
        f'parity: n={s["n"]} equal={s["equal"]} within_0.5in={s["within_0.5in"]} '
        f'declined={s["declined"]} by_reason={canonical(s["by_reason"])}'
    )


def regressions(baseline, current, fixture_sha):
    errors = []
    if baseline["fixture_sha256"] != fixture_sha:
        return [
            "fixture digest changed: an explicit baseline update with a reason is required"
        ]
    old = baseline["measurement"]
    if old["cases"].keys() != current["cases"].keys():
        return ["baseline/report case IDs differ"]
    for key, now in current["cases"].items():
        before = old["cases"][key]
        if now["model_ids"] != before["model_ids"]:
            errors.append(f"{key}: model identities changed")
        if set(now["reasons"]) - set(before["reasons"]):
            errors.append(
                f'{key}: new decline {set(now["reasons"])-set(before["reasons"])}'
            )
        # Existing coverage gaps cannot hide an endpoint threshold regression.
        if before["tiers"] and (
            len(before["tiers"]) != len(now["tiers"])
            or any(a > b for a, b in zip(now["tiers"], before["tiers"]))
        ):
            errors.append(f"{key}: model endpoint bucket worsened")
        if not before["reasons"] and not now["reasons"]:
            if any(a > b + EPS_IN for a, b in zip(now["delta_in"], before["delta_in"])):
                errors.append(f"{key}: accepted model delta increased")
        if "formation_tiers" in before:
            if (
                "formation_tiers" not in now
                or len(now["formation_tiers"]) != len(before["formation_tiers"])
                or any(
                    a > b
                    for a, b in zip(now["formation_tiers"], before["formation_tiers"])
                )
            ):
                errors.append(f"{key}: formation regressed")
    for reason, count in current["summary"]["by_reason"].items():
        if count > old["summary"]["by_reason"].get(reason, 0):
            errors.append(f"{reason}: count increased")
    return errors


def available_mb():
    return next(
        int(line.split()[1]) // 1024
        for line in Path("/proc/meminfo").read_text().splitlines()
        if line.startswith("MemAvailable:")
    )


def busy_godot():
    busy = []
    for path in Path("/proc").glob("[0-9]*/comm"):
        try:
            if path.read_text().strip().lower().startswith("godot"):
                busy.append(path.parent.name)
        except OSError:
            pass
    return busy


def run_godot(args, raw, log):
    # Serializes this harness's runners. Also checks other sessions before start.
    with open("/tmp/nml-position-parity-godot.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        announced = 0.0
        while available_mb() < 3500 or busy_godot():
            if time.monotonic() - announced >= 30:
                print(
                    f"waiting: available_mb={available_mb()} Godot_PIDs={busy_godot()}",
                    flush=True,
                )
                announced = time.monotonic()
            time.sleep(0.1)
        env = {k: v for k, v in os.environ.items() if not k.startswith("NML_")}
        env.update(
            {
                "NML_CORE": "1",
                "NML_CORE_MOVE": "1",
                "NML_TRACE": "0",
                "GODOT_SILENCE_ROOT_WARNING": "1",
            }
        )
        cmd = [
            args.godot,
            "--headless",
            "--path",
            str(REPO),
            "-s",
            "res://tools/position_parity.gd",
            "--",
            f"fixtures={args.fixtures.resolve()}",
            f"out={raw.resolve()}",
        ]
        # An old successful report must not mask a launch that writes nothing.
        raw.write_text("")
        with log.open("w") as stream:
            result = subprocess.run(
                cmd,
                cwd=REPO,
                env=env,
                stdout=stream,
                stderr=subprocess.STDOUT,
                timeout=args.timeout,
            )
        content = log.read_text(errors="replace")
        if (
            result.returncode
            or SCRIPT_ERROR.search(content)
            or not raw.exists()
            or not raw.stat().st_size
        ):
            raise RuntimeError(f"Godot failed ({result.returncode}); see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, default=FIXTURES)
    parser.add_argument("--baseline", type=Path, default=BASELINE)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument("--record-baseline", metavar="REASON")
    parser.add_argument(
        "--check-report",
        type=Path,
        action="append",
        help="check a saved raw report without launching Godot; repeat for determinism",
    )
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    if args.check_report and len({p.resolve() for p in args.check_report}) != len(
        args.check_report
    ):
        parser.error("--check-report paths must be distinct")
    fixtures = json.loads(args.fixtures.read_text())
    games = {c["game"] for c in fixtures["cases"] if c["game"] is not None}
    if len(fixtures["cases"]) < 100 or len(games) < 20:
        raise ValueError("fixtures need >=100 positions from >=20 games")
    fixture_sha = hashlib.sha256(args.fixtures.read_bytes()).hexdigest()
    args.out.mkdir(parents=True, exist_ok=True)
    reports = []
    stable = []
    for i in range(len(args.check_report) if args.check_report else args.runs):
        raw = (
            args.check_report[i] if args.check_report else args.out / f"run-{i+1}.json"
        )
        if not args.check_report:
            run_godot(args, raw, args.out / f"run-{i+1}.log")
        report = json.loads(raw.read_text())
        reports.append(report)
        stable.append(stable_rows(report))
        measured = measure(fixtures, report)
        print(summary_line(measured), flush=True)
        if fingerprint(stable[-1]) != fingerprint(stable[0]):
            raise ValueError(f"run {i+1} is nondeterministic (timing excluded)")
    measured = measure(fixtures, reports[0])
    evidence = {
        "fixture_sha256": fixture_sha,
        "deterministic_runs": len(reports),
        "stable_sha256": fingerprint(stable[0]),
        "measurement": measured,
        "wall_time_us": [
            {
                "table": sum(r["timing_us"]["table"] for r in report["rows"]),
                "rust": sum(r["timing_us"]["rust"] for r in report["rows"]),
            }
            for report in reports
        ],
    }
    (args.out / "measurement.json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n"
    )
    if args.record_baseline:
        if not args.record_baseline.strip() or len(reports) < 3:
            raise ValueError("baseline requires a reason and >=3 identical runs")
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=REPO, text=True
        ).strip()
        baseline = {
            "schema": 1,
            "boundary": "stage_a",
            "source_revision": commit,
            "reason": args.record_baseline,
            "fixture_sha256": fixture_sha,
            "measurement": measured,
        }
        args.baseline.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n")
    else:
        failures = regressions(
            json.loads(args.baseline.read_text()), measured, fixture_sha
        )
        if failures:
            for error in failures:
                print("REGRESSION:", error)
            return 1
    print(
        f"determinism: runs={len(reports)} identical=true timing_excluded=true sha256={fingerprint(stable[0])}"
    )
    print("models: " + canonical(measured["summary"]["models"]))
    print("formation: " + canonical(measured["summary"]["formation"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

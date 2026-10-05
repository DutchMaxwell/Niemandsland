#!/usr/bin/env python3
"""The lab pilot's row validator: a score exists only for a row set that passes every check.

`validate(rows, manifest)` -> (ok, problems). A row follows the shared row schema ("stage0-row/1"); the manifest is
{"rows": {row_id: {"arm", "seat", "net_seats" (default both)}}, "prereg_sha256", "rules_epoch", "model_sha256",
"wheel_sha256", "headers": {arm: {seat: sha256}}}; a row entry's own "headers": {seat: sha256} overrides its arm's
(the candidate seat, the cell's allowance and the source game move a real row's map). Problems: an unknown, missing,
duplicate or conflicting row ID; a wrong seat/arm/net/hash/epoch or a dirty build; an invalid row (illegal action, unported / overflow / unsupported
path, net_inactive — it never reaches a score); a valid row without an outcome; a tree stamp on a non-tree decision
or none on a tree decision; a decision that never searched (zero_search: a deadline fallback of the core, or a tree
trace without one completed playout - the arm then played the preselection's top row, not itself); a non-finite
timing. `pass_flags` withholds every PASS flag unless validation passed.
"""
import json
import math

SCHEMA = "stage0-row/1"
TREE_ARMS = ("L", "T", "L_tray", "T_tray")
VOLATILE = ("wall_s", "rss_hwm_mib")  # provenance two writes of the same row may differ in
TIMINGS = ("allocated_us", "elapsed_us", "preselect_us", "overshoot_us")


def _canon(row):
    return json.dumps({k: v for k, v in row.items() if k not in VOLATILE}, sort_keys=True)


def _finite(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def _row_problems(row, want, m):
    """Every problem of one row against its manifest entry `want` and the run's expectations `m`."""
    out = [("schema", row.get("schema"))] if row.get("schema") != SCHEMA else []
    out += [("wrong_" + k, row.get(k)) for k in ("arm", "seat") if row.get(k) != want.get(k)]
    build = row.get("build") or {}
    for key, got in (("prereg_sha256", row.get("prereg_sha256")), ("model_sha256", row.get("model_sha256")),
                     ("wheel_sha256", build.get("wheel_sha256")), ("rules_epoch", build.get("rules_epoch"))):
        if got != m[key]:
            out.append(("wrong_" + key, got))
    if build.get("dirty") is not False:
        out.append(("dirty_build", build.get("dirty")))
    expect = want["headers"] if "headers" in want else m["headers"].get(row.get("arm"), {})
    heads = {str(s): h for s, h in expect.items()}
    if {str(s): h for s, h in (row.get("header_sha256") or {}).items()} != heads:
        out.append(("wrong_header_sha256", row.get("header_sha256")))
    net = row.get("net") or {}
    calls = {str(s): (v or {}).get("calls", 0) for s, v in net.items()}  # int seat keys in memory, str after JSON
    out += [("net_inactive", s) for s in want.get("net_seats", (1, 2)) if calls.get(str(s), 0) <= 0]
    if not row.get("valid"):
        out.append(("invalid", row.get("reason")))
    elif row.get("y") not in (0, 0.5, 1) or row.get("done") is not True:
        out.append(("no_outcome", row.get("y")))
    if not _finite(row.get("wall_s")):
        out.append(("non_finite", "wall_s"))
    for d in row.get("decisions") or ():
        if (d.get("tree") is not None) != (d.get("arm") in TREE_ARMS):
            out.append(("tree_stamp", d.get("seq")))
        for trace in (d.get("tree"), d.get("deadline")):
            if trace and (trace.get("fallback") or not trace.get("completed")):
                out.append(("zero_search", "%s@%s" % (trace.get("fallback") or "no_playout", d.get("seq"))))
        bad = [k for k in TIMINGS if not _finite(d.get(k)) and (k == "elapsed_us" or d.get(k) is not None)]
        out += [("non_finite", "%s@%s" % (k, d.get("seq"))) for k in bad]
    return out


def validate(rows, manifest):
    """(ok, problems), problems = [{row_id, problem, detail}] in a stable order; ok only when there are none."""
    found, seen = [], {}
    for row in rows:
        rid = row.get("row_id")
        if rid not in manifest["rows"]:
            found.append((rid, "unknown_id", None))
        elif rid in seen:
            found.append((rid, "duplicate_id" if _canon(seen[rid]) == _canon(row) else "conflicting_duplicate", None))
        else:
            seen[rid] = row
            found += [(rid, p, d) for p, d in _row_problems(row, manifest["rows"][rid], manifest)]
    found += [(rid, "missing_id", None) for rid in manifest["rows"] if rid not in seen]
    found.sort(key=lambda x: (str(x[0]), x[1], str(x[2])))
    return not found, [{"row_id": r, "problem": p, "detail": d} for r, p, d in found]


def pass_flags(ok, flags):
    """The gate booleans as computed, or every one withheld (False) when validation failed."""
    return {k: bool(v) and ok for k, v in flags.items()}

#!/usr/bin/env python3
"""Turn captured relay STATS log lines into a weekly, human-readable usage digest.

The relay emits one aggregate line per hour (and one at boot), e.g.

    2026-07-05 06:00:00,000 INFO STATS {"games_played": 30, "rooms_created": 45, "ts": "...", ...}

Those lines are pure aggregates — no IPs, no room codes, no player identities — so a captured Fly
log is safe to keep and to hand around. This tool reads such a capture, groups the samples by ISO
week and prints totals, peaks and week-over-week trends.

Usage:
  fly logs -a niemandsland-relay > relay.log        # or any file that contains the STATS lines
  python stats_digest.py relay.log

Only lines containing the "STATS " marker are considered; everything else is ignored, so a raw,
mixed log stream works as-is.
"""
import json
import sys
from collections import OrderedDict
from datetime import datetime

# Cumulative scalar counters -> reported as "new this week" deltas.
_DELTA_SCALARS = ("rooms_created", "games_played", "peer_connections", "server_starts")
# Histogram dicts -> reported as per-bucket deltas.
_DELTA_DICTS = ("join_failures", "room_lifetime_buckets", "peers_per_room")
# Cumulative maxima -> reported as the value at the end of the week.
_PEAKS = ("peak_concurrent_rooms", "peak_concurrent_peers")

_STATS_MARKER = "STATS "

_LIFETIME_LABELS = {
    "lt_10min": "<10m",
    "10_45min": "10-45m",
    "45_120min": "45-120m",
    "gt_120min": ">120m",
}


def iter_stats_records(lines):
    """Yield the parsed JSON object from every line that carries a 'STATS ' marker.

    Malformed lines (no marker, no JSON, bad JSON, or no usable timestamp) are skipped, so a raw
    mixed log stream is safe to feed in. A record needs a timestamp to be placed in a week; the
    per-line 'ts' is preferred, falling back to the snapshot's 'last_updated'.
    """
    for line in lines:
        marker = line.find(_STATS_MARKER)
        if marker == -1:
            continue
        brace = line.find("{", marker)
        if brace == -1:
            continue
        try:
            record = json.loads(line[brace:])
        except (ValueError, TypeError):
            continue
        if not isinstance(record, dict):
            continue
        ts = record.get("ts") or record.get("last_updated")
        if not ts:
            continue
        record["ts"] = ts
        yield record


def _parse_ts(ts):
    """Parse an ISO-8601 timestamp (the relay writes UTC with a +00:00 offset)."""
    return datetime.fromisoformat(ts)


def _week_label(ts):
    """ISO-week label like '2026-W27' for grouping."""
    iso = _parse_ts(ts).isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"


def _delta_dict(end, base, key):
    """Per-bucket positive deltas for a histogram field between two snapshots."""
    end_d = end.get(key, {}) or {}
    base_d = base.get(key, {}) or {}
    out = {}
    for bucket, value in end_d.items():
        diff = int(value) - int(base_d.get(bucket, 0))
        if diff:
            out[bucket] = diff
    return out


def _sum_dict(d):
    return sum(int(v) for v in d.values())


def _trend_arrow(current, previous):
    if previous is None:
        return " "
    if current > previous:
        return "^"
    if current < previous:
        return "v"
    return "="


def build_weeks(records):
    """Group records by ISO week (chronological), returning an OrderedDict label -> [records]."""
    weeks = OrderedDict()
    for rec in sorted(records, key=lambda r: r["ts"]):
        weeks.setdefault(_week_label(rec["ts"]), []).append(rec)
    return weeks


def render_digest(records, source=""):
    """Render the weekly digest text from an iterable of parsed STATS records."""
    records = [r for r in records]
    lines = ["Niemandsland relay - weekly usage digest"]
    if source:
        lines.append(f"Source: {source}")
    if not records:
        lines.append("No STATS records found.")
        return "\n".join(lines)

    ordered = sorted(records, key=lambda r: r["ts"])
    first, last = ordered[0], ordered[-1]
    lines.append(f"Samples: {len(ordered)}   Span: {first['ts']} -> {last['ts']}")
    lines.append("")

    weeks = build_weeks(records)
    baseline = first  # observation start: deltas are growth we actually witnessed
    prev_rooms_delta = None
    prev_games_delta = None
    for label, week_records in weeks.items():
        end = week_records[-1]
        rooms_d = int(end.get("rooms_created", 0)) - int(baseline.get("rooms_created", 0))
        games_d = int(end.get("games_played", 0)) - int(baseline.get("games_played", 0))
        peers_d = int(end.get("peer_connections", 0)) - int(baseline.get("peer_connections", 0))
        starts_d = int(end.get("server_starts", 0)) - int(baseline.get("server_starts", 0))

        lines.append(f"{label}  ({len(week_records)} sample(s))")
        lines.append(
            f"  rooms created      : +{rooms_d:<5d} (total {end.get('rooms_created', 0)})"
            f"  {_trend_arrow(rooms_d, prev_rooms_delta)}"
        )
        lines.append(
            f"  games played (>=2) : +{games_d:<5d} (total {end.get('games_played', 0)})"
            f"  {_trend_arrow(games_d, prev_games_delta)}"
        )
        lines.append(
            f"  peer connections   : +{peers_d:<5d} (total {end.get('peer_connections', 0)})"
        )
        if starts_d:
            lines.append(f"  server starts      : +{starts_d}")
        lines.append(
            f"  peak rooms / peers : {end.get('peak_concurrent_rooms', 0)}"
            f" / {end.get('peak_concurrent_peers', 0)}  (cumulative)"
        )

        jf = _delta_dict(end, baseline, "join_failures")
        if jf:
            detail = ", ".join(f"{k} {v}" for k, v in sorted(jf.items()))
            lines.append(f"  join failures      : {_sum_dict(jf)}  ({detail})")

        lt = _delta_dict(end, baseline, "room_lifetime_buckets")
        if lt:
            detail = ", ".join(
                f"{_LIFETIME_LABELS.get(k, k)} {lt[k]}" for k in _LIFETIME_LABELS if k in lt
            )
            lines.append(f"  room lifetimes     : {detail}")

        ppr = _delta_dict(end, baseline, "peers_per_room")
        if ppr:
            detail = ", ".join(f"{v}x{k}p" for k, v in sorted(ppr.items(), key=lambda kv: int(kv[0])))
            lines.append(f"  peers/room (peak)  : {detail}")

        lines.append("")
        baseline = end
        prev_rooms_delta = rooms_d
        prev_games_delta = games_d

    lines.append("Totals (latest snapshot)")
    lines.append(f"  first seen         : {last.get('first_seen') or 'n/a'}")
    lines.append(f"  server starts      : {last.get('server_starts', 0)}")
    lines.append(f"  rooms created      : {last.get('rooms_created', 0)}")
    lines.append(f"  games played (>=2) : {last.get('games_played', 0)}")
    lines.append(f"  peer connections   : {last.get('peer_connections', 0)}")
    lines.append(
        f"  peak rooms / peers : {last.get('peak_concurrent_rooms', 0)}"
        f" / {last.get('peak_concurrent_peers', 0)}"
    )
    jf_total = last.get("join_failures", {}) or {}
    if _sum_dict(jf_total):
        detail = ", ".join(f"{k} {v}" for k, v in sorted(jf_total.items()) if v)
        lines.append(f"  join failures      : {_sum_dict(jf_total)}  ({detail})")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: python {sys.argv[0]} <captured-log-file>")
        sys.exit(2)
    path = sys.argv[1]
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            records = list(iter_stats_records(f))
    except OSError as exc:
        print(f"Could not read {path}: {exc}")
        sys.exit(1)
    print(render_digest(records, source=path))


if __name__ == "__main__":
    main()

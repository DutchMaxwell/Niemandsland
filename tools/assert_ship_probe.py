#!/usr/bin/env python3
"""Reads the log of an exported build that ran tools/core_ship_probe.tscn and decides PASS/FAIL.

The macOS CI job (build.yml, export-macos) runs the EXPORTED .app headless with the probe as its
main scene and hands the log to this file. PASS needs all of:
  * the process exit code (when given) is 0,
  * one `NML_SHIP_PROBE {json}` marker whose legs are all true (class present, core enabled, the
    packed brain accepted, a real planner pick went through the core) and whose `os` / `arch` are
    the ones the caller expects — an x86_64 leg that silently ran the arm64 slice must not pass,
  * a `opponent: erlkoenig` line from main.gd and NO `opponent: tree` line,
  * none of the error markers the Linux export smoke step already treats as fatal.

Usage:  python3 tools/assert_ship_probe.py LOG --os macOS --arch arm64 [--exit-code N]
Exit 0 = PASS, 1 = FAIL (every reason is printed).
"""

import argparse
import json
import re
import sys

MARKER = "NML_SHIP_PROBE "
FATAL = re.compile(r"GDExtension|SCRIPT ERROR|Parse Error", re.IGNORECASE)
SHA = re.compile(r"^[0-9a-f]{64}$")


def check(text, want_os, want_arch, exit_code=None):
    """Returns the list of failure reasons; empty = PASS."""
    problems = []
    if exit_code is not None and exit_code != 0:
        problems.append(f"the probe exited with code {exit_code} (0 expected; 124/142 = watchdog or timeout)")
    lines = text.splitlines()
    reports = [ln[ln.index(MARKER) + len(MARKER):] for ln in lines if ln.startswith(MARKER)]
    if not reports:
        problems.append("no NML_SHIP_PROBE marker in the log — the probe scene never reached its end")
    else:
        try:
            report = json.loads(reports[-1])
        except ValueError as exc:
            report = {}
            problems.append(f"the NML_SHIP_PROBE marker is not JSON: {exc}")
        for key in ("class_present", "core_enabled", "planner", "picked", "ok"):
            if report and report.get(key) is not True:
                problems.append(f"probe leg {key} = {report.get(key)!r}, expected true")
        if report and int(report.get("core_calls", 0)) <= 0:
            problems.append("probe leg core_calls = 0 — no activation went through the Rust core")
        if report and not SHA.match(str(report.get("brain_sha", ""))):
            problems.append(f"probe brain_sha = {report.get('brain_sha')!r}, expected the packed net's sha256")
        if report and report.get("os") != want_os:
            problems.append(f"probe ran on os {report.get('os')!r}, expected {want_os!r}")
        if report and report.get("arch") != want_arch:
            problems.append(f"probe ran the {report.get('arch')!r} slice, expected {want_arch!r}")
    if not any(ln.startswith("opponent: erlkoenig") for ln in lines):
        problems.append("no `opponent: erlkoenig` line in the log")
    if any(ln.startswith("opponent: tree") for ln in lines):
        problems.append("the log says `opponent: tree` — NACHTMAHR fell back to the decision tree")
    for ln in lines:
        if FATAL.search(ln):
            problems.append(f"fatal marker in the log: {ln.strip()[:200]}")
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("log")
    ap.add_argument("--os", dest="want_os", required=True)
    ap.add_argument("--arch", dest="want_arch", required=True)
    ap.add_argument("--exit-code", type=int, default=None)
    args = ap.parse_args(argv)
    with open(args.log, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    problems = check(text, args.want_os, args.want_arch, args.exit_code)
    if problems:
        for p in problems:
            print(f"SHIP PROBE FAIL: {p}")
        return 1
    print(f"SHIP PROBE PASS: os={args.want_os} arch={args.want_arch} — NmlCore loaded, opponent: erlkoenig")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Diff two arena result directories file by file, key path by key path.

tools/arena_match.gd writes one arena_*.json per game. Retargeting the harness
(PLAN G steps 8/9) must not move a single number, so this tool pairs the files by
FILENAME and compares the parsed JSON exactly: same binary plus same seed means
bit-identical values, so there is no float tolerance here on purpose.

  arena_result_diff.py A_DIR B_DIR [--ignore KEY ...]

A difference is printed as `<file>: <key path>: <A value> -> <B value>`, at most
20 key paths per file. Key paths are dotted for dict keys and bracketed for list
indices (`p1.vp`, `board[3][0]`).

Exit codes:
  0  all pairs identical
  1  at least one pair differs
  2  nothing was compared: no arena_*.json pair at all, a file without a partner,
     or a directory that cannot be read. Never let a short run look equal.
"""

import argparse
import glob
import json
import os
import sys

CAP = 20
_MISSING = object()


def _fmt(value):
    return "<missing>" if value is _MISSING else json.dumps(
        value, sort_keys=True, default=str)


def _walk(a, b, path, ignore, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted(set(a) | set(b)):
            if key in ignore:
                continue
            step = "%s.%s" % (path, key) if path else str(key)
            if key not in a or key not in b:
                out.append((step, a.get(key, _MISSING), b.get(key, _MISSING)))
            else:
                _walk(a[key], b[key], step, ignore, out)
        return
    if isinstance(a, list) and isinstance(b, list):
        for i in range(max(len(a), len(b))):
            if i < len(a) and i < len(b):
                _walk(a[i], b[i], "%s[%d]" % (path, i), ignore, out)
            else:
                out.append(("%s[%d]" % (path, i), a[i] if i < len(a) else _MISSING,
                            b[i] if i < len(b) else _MISSING))
        return
    if type(a) is not type(b) or a != b:
        out.append((path, a, b))


def _names(directory):
    return sorted(os.path.basename(p)
                  for p in glob.glob(os.path.join(directory, "arena_*.json")))


def main(argv=None):
    ap = argparse.ArgumentParser(description="diff two arena result directories")
    ap.add_argument("a_dir")
    ap.add_argument("b_dir")
    ap.add_argument("--ignore", action="append", default=[], metavar="KEY", help="dict key to skip at any depth, e.g. profile")
    args = ap.parse_args(argv)
    ignore = set(args.ignore)

    for directory in (args.a_dir, args.b_dir):
        if not os.path.isdir(directory):
            print("not a directory: %s" % directory, file=sys.stderr)
            return 2

    names_a, names_b = _names(args.a_dir), _names(args.b_dir)
    pairs = sorted(set(names_a) & set(names_b))
    unpaired = sorted(set(names_a) ^ set(names_b))
    for name in unpaired:
        print("unpaired %s" % name, file=sys.stderr)
    if unpaired:
        return 2
    if not pairs:
        print("no arena_*.json pairs in %s and %s" % (args.a_dir, args.b_dir), file=sys.stderr)
        return 2

    differing = 0
    for name in pairs:
        try:
            with open(os.path.join(args.a_dir, name), encoding="utf-8") as fh:
                a = json.load(fh)
            with open(os.path.join(args.b_dir, name), encoding="utf-8") as fh:
                b = json.load(fh)
        except (OSError, ValueError) as err:
            print("%s: unreadable: %s" % (name, err), file=sys.stderr)
            differing += 1
            continue
        diffs = []
        _walk(a, b, "", ignore, diffs)
        if not diffs:
            continue
        differing += 1
        print("%s: %d differing key path(s)" % (name, len(diffs)))
        for path, left, right in diffs[:CAP]:
            print("  %s: %s -> %s" % (path or "<root>", _fmt(left), _fmt(right)))
        if len(diffs) > CAP:
            print("  ... %d more" % (len(diffs) - CAP))

    print("%d/%d pair(s) differ" % (differing, len(pairs)))
    return 1 if differing else 0


if __name__ == "__main__":
    sys.exit(main())

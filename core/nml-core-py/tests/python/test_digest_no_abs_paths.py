"""NML-1073 addendum (2026-09-05) -- the digest must never carry a filesystem
path. 11 pinned `result_digest` constants diverged between the laptop
(`/home/<user>/...`) and a build box (`/root/...`) because `armies`
held `str(list_p1)` / `str(list_p2)` -- the CALLER'S absolute army-list path,
not anything about the game. `armies` now holds the list BASENAME plus a
content hash (`armies_sha256`), so the digest sees WHICH lists played, never
WHERE they lived on disk.

This is the guard, not a description of the fix: it walks every string leaf
of the exact body `result_digest` hashes (the result dict minus
`DIGEST_EXCLUDED_FIELDS`) and refuses a path separator or this machine's own
home directory anywhere in it. No field in a real game result has ever needed
either -- unit/faction/rule names, mission strings, `armies` and
`armies_sha256` are all path-free by construction -- so this is a proof over
the LIVE body, not an assumption about which fields to check. A future field
that smuggles a machine path back into the digest (a board file, a log path,
another `str(some_path)`) fails HERE, on the machine that introduced it,
instead of on a different machine's CI run.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
FAST = {"top_k": 2, "horizon": 1}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _walk_strings(obj):
    """Every string leaf of a JSON-shaped value, dict keys included --
    `result_digest` hashes `json.dumps(body, sort_keys=True)`, so a path
    hiding in a KEY would be just as real a divergence as one in a value."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield k
            yield from _walk_strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk_strings(v)
    elif isinstance(obj, str):
        yield obj


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + the 1000pt lists")
def test_the_digested_body_carries_no_filesystem_path():
    """RED without the fix: `armies.p1` / `armies.p2` held `str(list_p1)` /
    `str(list_p2)`, e.g. `/home/<user>/nml-mission/farm/ai_lists/
    robot_legions_1000.json` -- both signals below (a separator, this
    machine's home dir) catch it. GREEN with the fix: `armies` holds only
    `robot_legions_1000.json` and `armies_sha256` a hex digest -- neither
    contains a slash, a backslash, or `$HOME`."""
    core = nml_core.load(str(REPO))
    result = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    body = {k: v for k, v in result.items() if k not in sp.DIGEST_EXCLUDED_FIELDS}
    home = str(Path.home())
    bad = sorted({
        s for s in _walk_strings(body)
        if "/" in s or "\\" in s or (home and home in s)
    })
    assert not bad, "digested body carries a filesystem path: %r" % bad[:5]

"""Tripwire for the #703 (Fortified) / #698 (Growth Markers) rebase resolution.

dice.rs::save_batch composes the two families' AP reductions as
`(eff_ap + def.growth_fortify_ap).max(0)`, where `eff_ap` (Fortified's own
Boost/alias reduction) is ALREADY floored at 0 before the add. That is
clamp-then-add, not add-then-clamp — the two orders agree only while
`growth_fortify_ap` (the registry's `enemy_ap_per_two` param, read off any
entry whose primitive is "Growth Markers") stays <= 0. A positive value
would make the two orders diverge by up to a full point of AP on every save
(worked case: ap=0, Fortified reduction 1, growth +2 gives 2 under
clamp-then-add but only 1 under add-then-clamp), silently, in data, with no
code review needed to introduce it.

This is not proven by the type system — `enemy_ap_per_two` is an ordinary
i64 registry param — so it is proven here instead: every shipped
`rules_mechanics_*.json` entry that carries the key must have a
non-positive value. The day someone ships a positive one, this fails and
points straight at this comment instead of quietly changing how hard units
are to wound.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
MECHANICS_DIR = REPO_ROOT / "assets" / "solo"


def _entries_carrying_enemy_ap_per_two(doc, path=""):
    """Yield (path, value) for every dict anywhere in `doc` (registry entries
    are `{"primitive": ..., "params": {"enemy_ap_per_two": ..., ...}}`) whose
    OWN keys include `enemy_ap_per_two` directly — i.e. the innermost
    `params` dict itself, visited once per registry entry."""
    if isinstance(doc, dict):
        if "enemy_ap_per_two" in doc:
            yield (path, doc["enemy_ap_per_two"])
        for key, value in doc.items():
            yield from _entries_carrying_enemy_ap_per_two(value, f"{path}/{key}")
    elif isinstance(doc, list):
        for i, value in enumerate(doc):
            yield from _entries_carrying_enemy_ap_per_two(value, f"{path}[{i}]")


def test_every_shipped_enemy_ap_per_two_is_non_positive():
    mechanics_files = sorted(MECHANICS_DIR.glob("rules_mechanics_*.json"))
    assert len(mechanics_files) >= 5, (
        f"expected at least the five game-system mechanics files, found {mechanics_files}"
    )
    offenders = []
    seen_any = False
    for f in mechanics_files:
        doc = json.loads(f.read_text())
        for path, value in _entries_carrying_enemy_ap_per_two(doc):
            seen_any = True
            if value > 0:
                offenders.append(f"{f.name}{path} = {value}")
    assert seen_any, (
        "no rules_mechanics_*.json entry carries enemy_ap_per_two any more — "
        "if the Fortified Growth rule was renamed/removed, the clamp-order "
        "risk this test guards may have moved with it; update or retire this "
        "test deliberately rather than let it go silently green on nothing."
    )
    assert not offenders, (
        "enemy_ap_per_two must never be positive — dice.rs::save_batch composes it as "
        "clamp-then-add (Fortified's eff_ap floors at 0 BEFORE growth_fortify_ap adds), "
        "which only agrees with add-then-clamp while this value is <= 0. Offenders: "
        + ", ".join(offenders)
    )

"""Tree search knob, plan step 7 — `trace.tree` rides ONLY a pick the tree made.

The NML-1147a stamp law on the binding's `pick_plain`: the default header
answers the pick object it always did (no `tree` key at all), and a header
with `search_mode: tree` stamps the search trace on every pick it answers.
The byte-identical half of the proof is the existing P1/P2 replay gates.
"""

from __future__ import annotations

import json
from pathlib import Path

import nml_core

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"


def test_trace_tree_rides_only_a_tree_pick():
    lines = (FIXTURES / "acts_25.jsonl").read_text().splitlines()
    header = json.loads(lines[0])
    acts = [json.loads(x) for x in lines[1:] if x.strip()]
    tree_header = json.loads(lines[0])
    tree_header.setdefault("knobs", {}).update(search_mode="tree", tree_budget=16)
    plain, tree = nml_core.load(str(REPO)), nml_core.load(str(REPO))
    plain.set_header(header)
    tree.set_header(tree_header)
    seen = 0
    for act in acts[:6]:
        a = plain.plan_with_rollout(plain.state_of(act["state"]), act["player"], act["statics"])
        b = tree.plan_with_rollout(tree.state_of(act["state"]), act["player"], act["statics"])
        assert a["used"] and b["used"], (a.get("unsupported"), b.get("unsupported"))
        assert "tree" not in a["trace"], "a default pick carries a tree trace"
        stamp = b["trace"]["tree"]
        assert stamp["completed"] >= 16 and stamp["deadline_hit"] is False
        assert [r[0] for r in stamp["root"]] == b["trace"]["pool_idx"]
        seen += 1
    assert seen == 6

"""A pull request gets its CI run whatever its base branch is: a PR stacked on its parent's branch is
already proven when the parent merges. Re-adding `branches:` to a pull_request
trigger turns this red."""
import os
import re

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _pull_request_block(name):
    wf = open(os.path.join(ROOT, ".github", "workflows", name), encoding="utf-8").read()
    m = re.search(r"^  pull_request:\n((?:    .*\n)*)", wf, re.M)
    assert m, f"{name}: no pull_request trigger"
    return m.group(1)


@pytest.mark.parametrize("name", ["build.yml", "mp-two-instance.yml"])
def test_pull_request_trigger_has_no_branch_filter(name):
    block = _pull_request_block(name)
    assert "types:" in block  # the block parsed is the real trigger, not an empty match
    bad = [l for l in block.splitlines() if re.match(r"\s*branches(-ignore)?\s*:", l)]
    assert not bad, f"{name}: pull_request must not filter on the base branch (stacked PRs need their run): {bad}"

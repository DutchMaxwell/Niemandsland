"""tools/ci/all_required.py: a skip is green only when the `changes` outputs explain it."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "ci"))
from all_required import verdict  # noqa: E402

JOBS = ["changes", "core-linux", "core-py-linux", "test", "shards-coverage", "relay-tests", "rust-gate"]


def _env(event="pull_request", ref="refs/pull/1/merge", ncore="true", rust="true", **res):
    needs = {j: {"result": res.get(j.replace("-", "_"), "success")} for j in JOBS}
    return {"NEEDS": json.dumps(needs), "EVENT": event, "REF": ref, "NOT_CORE_ONLY": ncore, "RUST_RELEVANT": rust}


S = "skipped"


def test_real_shapes_are_green():
    assert verdict(_env()) == 0  # full PR
    assert verdict(_env(ncore="false", rust="false", core_linux=S, core_py_linux=S, test=S, rust_gate=S)) == 0  # docs PR
    assert verdict(_env(rust="false", rust_gate=S)) == 0  # non-rust PR
    assert verdict(_env(event="push", ref="refs/heads/main", rust="false", rust_gate=S)) == 0  # main push


def test_skip_without_a_path_reason_is_red():
    assert verdict(_env(test=S)) == 1  # not_core_only=true: the suite had to run
    assert verdict(_env(event="push", ref="refs/heads/main", test=S)) == 1
    assert verdict(_env(rust="true", rust_gate=S)) == 1
    assert verdict(_env(event="push", ref="refs/tags/v1.0", rust="false", rust_gate=S)) == 1
    assert verdict(_env(ncore="false", rust="false", changes=S, core_linux=S, core_py_linux=S, test=S, rust_gate=S)) == 1
    assert verdict(_env(ncore="false", shards_coverage=S)) == 1
    assert verdict(_env(ncore="false", relay_tests=S)) == 1


def test_failure_or_cancel_is_red():
    assert verdict(_env(test="failure")) == 1
    assert verdict(_env(core_linux="cancelled")) == 1
    assert verdict(_env(test="cancelled")) == 1  # the one gdUnit job of a LOOK-only PR (ncore=true, test not skipped)


def test_failed_changes_cannot_pass_through_empty_outputs():
    # changes failed -> its outputs are empty (NOT_CORE_ONLY="" reads as fast lane): changes itself is red
    assert verdict(_env(ncore="", rust="", changes="failure", core_linux=S, core_py_linux=S, test=S, rust_gate=S)) == 1


def test_skip_table_mirrors_the_jobs_if_lines():
    import re
    wf = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".github/workflows/build.yml")).read()
    want = {
        "core-linux": "github.event_name != 'pull_request' || needs.changes.outputs.not_core_only == 'true'",
        "core-py-linux": "github.event_name != 'pull_request' || needs.changes.outputs.not_core_only == 'true'",
        "test": "github.event_name != 'pull_request' || needs.changes.outputs.not_core_only == 'true'",
        "rust-gate": "startsWith(github.ref, 'refs/tags/v') || (github.event_name == 'pull_request' && needs.changes.outputs.rust_relevant == 'true')",
    }
    for job, cond in want.items():
        m = re.search(rf"^  {job}:\n(?:    .*\n)*?    if: \$\{{\{{ (.*) \}}\}}$", wf, re.M)
        assert m and m.group(1) == cond, f"{job}: its if: changed - update SKIP_OK in tools/ci/all_required.py and this table"


def test_the_aggregate_needs_exactly_the_jobs_this_table_knows():
    import re
    wf = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".github/workflows/build.yml")).read()
    m = re.search(r"^  all-required:\n(?:    .*\n)*?    needs: \[(.*)\]$", wf, re.M)
    assert m and [j.strip() for j in m.group(1).split(",")] == JOBS, \
        "all-required needs changed: add the job to JOBS and, if it can skip, to SKIP_OK (the advisory MP workflow is not a need)"

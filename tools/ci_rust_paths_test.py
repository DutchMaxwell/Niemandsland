"""Guards the wiring that makes the Rust jobs part of the "All required checks" verdict.

build.yml's `changes.rust_relevant` filter (decides whether rust-gate runs on a PR) must list the same
paths as rust.yml's push `paths:` (the file's single source). rust.yml must not run on pull_request by
itself (that would run the Rust jobs twice), and rust-gate must be in all-required's `needs`.
Plain text parsing: the shards-coverage job installs pytest only, not PyYAML.
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(name):
    with open(os.path.join(ROOT, ".github", "workflows", name), encoding="utf-8") as f:
        return f.read()


def _bullets_after(text, header_pattern):
    """The quoted `- '...'` items directly under the first line matching header_pattern."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.match(header_pattern, line):
            items = []
            for nxt in lines[i + 1:]:
                m = re.match(r"\s*-\s*'([^']+)'\s*$", nxt)
                if not m:
                    break
                items.append(m.group(1))
            return items
    raise AssertionError("header not found: " + header_pattern)


def test_the_pr_filter_in_build_yml_equals_rust_yml_push_paths():
    rust = _bullets_after(_read("rust.yml"), r"^    paths:$")  # the only `paths:` left: under push
    build = _bullets_after(_read("build.yml"), r"^\s+rust_relevant:$")
    assert rust, "rust.yml push paths not found"
    assert sorted(rust) == sorted(build), (rust, build)


def test_rust_yml_has_no_pull_request_trigger_of_its_own():
    assert not re.search(r"^  pull_request:", _read("rust.yml"), re.M)


def test_all_required_waits_for_rust_gate():
    m = re.search(r"^  all-required:.*?^    needs: \[([^\]]*)\]", _read("build.yml"), re.M | re.S)
    assert m, "all-required needs not found"
    assert "rust-gate" in [n.strip() for n in m.group(1).split(",")]

"""tools/ci/run_shard_group.sh must never lose a slice's exit code (a red slice = a red job).

A fake `godot` on PATH stands in for gdUnit inside a scratch tree with six suites; it fails or dies
by signal for one chosen slice. The real shard_assign.py splits the suites.
"""

import os
import shutil
import stat
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAKE = """#!/usr/bin/env bash
i=$(sed -n 's/.*-rd reports\\/slice\\([0-9]*\\).*/\\1/p' <<< "$*")
echo "fake slice $i xdg=$XDG_DATA_HOME args=$*"
mkdir -p "$XDG_DATA_HOME/godot/app_userdata/Niemandsland/model_cache" && echo n > "$XDG_DATA_HOME/godot/app_userdata/Niemandsland/model_cache/new_$i"
[ "$i" = "${FAKE_FAIL:-x}" ] && exit 1
[ "$i" = "${FAKE_KILL:-x}" ] && kill -9 $$
exit 0
"""


def _run(tmp_path, args=("--shards", "6", "--first", "3", "--procs", "3"), suites=None, **env_extra):
    tree = tmp_path / "tree"
    (tree / "tools" / "ci").mkdir(parents=True)
    (tree / "test").mkdir()
    shutil.copy(os.path.join(ROOT, "tools", "shard_assign.py"), tree / "tools")
    shutil.copy(os.path.join(ROOT, "tools", "ci", "run_shard_group.sh"), tree / "tools" / "ci")
    for n in range(6):
        (tree / "test" / f"s{n}_test.gd").write_text("")
    (tree / "test" / "shard_weights.json").write_text("{}")
    bindir = tmp_path / "bin"
    bindir.mkdir()
    (bindir / "godot").write_text(FAKE)
    (bindir / "godot").chmod(0o755 | stat.S_IEXEC)
    home = tmp_path / "home"
    seed = home / ".local/share/godot/app_userdata/Niemandsland/model_cache"
    seed.mkdir(parents=True)
    (seed / "old_blob").write_text("o")
    env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}", HOME=str(home), RUNNER_TEMP=str(tmp_path / "rt"))
    env.update(env_extra)
    if suites is not None:
        (tree / "look_suites.txt").write_text(suites)
    p = subprocess.run(["bash", "tools/ci/run_shard_group.sh", *args], cwd=tree, env=env, capture_output=True, text=True)
    return p, tree, seed


def test_all_slices_green_exit_0_and_one_log_each(tmp_path):
    p, tree, seed = _run(tmp_path)
    assert p.returncode == 0, p.stdout + p.stderr
    for i in (3, 4, 5):
        log = (tree / f"gdunit_output_{i}.log").read_text()
        assert f"ud{i}" in log and f"-rd reports/slice{i}" in log
        assert (tmp_path / f"rt/ud{i}/godot/app_userdata/Niemandsland/model_cache/old_blob").exists()
        assert (seed / f"new_{i}").exists()  # new blobs copied back for the cache save
    assert not (tree / "gdunit_output_2.log").exists()


def test_last_slice_failing_fails_the_group(tmp_path):
    p, _, _ = _run(tmp_path, FAKE_FAIL="5")
    assert p.returncode == 1, p.stdout


def test_middle_slice_killed_by_signal_fails_the_group(tmp_path):
    p, _, _ = _run(tmp_path, FAKE_KILL="4")
    assert p.returncode == 1, p.stdout
    assert "slice 4 exited 137" in p.stdout


LOOK = ("--suite-file", "look_suites.txt")


def test_suite_file_runs_exactly_its_suites_in_one_process(tmp_path):
    p, tree, seed = _run(tmp_path, LOOK, suites="test/s1_test.gd\ntest/e2e/boot_test.gd\n")
    assert p.returncode == 0, p.stdout + p.stderr
    log = (tree / "gdunit_output_0.log").read_text()
    assert "-a res://test/s1_test.gd -a res://test/e2e/boot_test.gd" in log and "-rd reports/slice0" in log
    assert "test/s0_test.gd" not in log and not (tree / "gdunit_output_1.log").exists()  # no shard split
    assert (seed / "new_0").exists()


def test_suite_file_failing_or_empty_fails_the_job(tmp_path):
    assert _run(tmp_path / "a", LOOK, suites="test/s1_test.gd\n", FAKE_FAIL="0")[0].returncode == 1
    assert _run(tmp_path / "b", LOOK, suites="")[0].returncode == 1  # an empty list would run the whole tree: never

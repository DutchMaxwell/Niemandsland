import json
import os
import statistics
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import shard_assign  # noqa: E402
import shard_weights_from_logs as swl  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_lpt_max_shard_is_within_15_percent_of_the_mean():
    os.chdir(ROOT)
    suites = shard_assign.suites_on_disk()
    weights = json.load(open(shard_assign.WEIGHTS))
    _, load = shard_assign.assign(suites, weights, 10)
    assert max(load) <= 1.15 * statistics.mean(load), load


def test_unknown_suites_get_the_median_weight_and_are_still_assigned_once():
    weights = {"a": 10.0, "b": 2.0, "c": 4.0}
    shards, _ = shard_assign.assign(["a", "b", "c", "new"], weights, 2)
    flat = sorted(s for sh in shards for s in sh)
    assert flat == ["a", "b", "c", "new"]
    # median of known = 4.0: "new" weighs 4.0, lands next to "b" (a alone = 10)
    assert "new" in next(sh for sh in shards if "b" in sh)


def test_check_fails_when_a_suite_falls_outside_every_shard(monkeypatch):
    os.chdir(ROOT)
    real = shard_assign.assign

    def lossy(suites, weights, shards):
        out, load = real(suites, weights, shards)
        out[0] = out[0][1:]  # silently drop one suite
        return out, load

    monkeypatch.setattr(shard_assign, "assign", lossy)
    monkeypatch.setattr(sys, "argv", ["shard_assign.py", "--shards", "10", "--check"])
    assert shard_assign.main() == 1


def _fixture_tree(tmp_path, monkeypatch, suites, weights):
    """A tiny test/ tree: `suites` are the *_test.gd files on disk, `weights` the weights file."""
    (tmp_path / "test").mkdir()
    for s in suites:
        (tmp_path / "test" / s).write_text("")
    (tmp_path / "test" / "shard_weights.json").write_text(json.dumps(weights))
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(sys, "argv", ["shard_assign.py", "--shards", "2", "--check"])


def test_check_passes_and_names_the_median_when_a_suite_has_no_weight_line(tmp_path, monkeypatch, capsys):
    suites = ["a_test.gd", "b_test.gd", "c_test.gd", "new_test.gd"]
    weights = {"test/a_test.gd": 10.0, "test/b_test.gd": 2.0, "test/c_test.gd": 4.0}
    _fixture_tree(tmp_path, monkeypatch, suites, weights)
    assert shard_assign.main() == 0
    out = capsys.readouterr().out
    assert "1 unweighted suites at the median (4 s)" in out, out
    assert "exactly once" in out, out


def test_check_says_nothing_about_the_median_when_every_suite_has_a_line(tmp_path, monkeypatch, capsys):
    _fixture_tree(tmp_path, monkeypatch, ["a_test.gd"], {"test/a_test.gd": 3.0})
    assert shard_assign.main() == 0
    assert "unweighted" not in capsys.readouterr().out


def test_check_fails_when_a_weight_line_names_a_suite_that_was_deleted(tmp_path, monkeypatch, capsys):
    weights = {"test/a_test.gd": 3.0, "test/deleted_test.gd": 5.0}
    _fixture_tree(tmp_path, monkeypatch, ["a_test.gd"], weights)
    assert shard_assign.main() == 1
    out = capsys.readouterr().out
    assert "::error::" in out and "test/deleted_test.gd" in out, out


def test_index_mode_stdout_stays_a_bare_suite_list_when_a_suite_has_no_weight_line(tmp_path, monkeypatch, capsys):
    _fixture_tree(tmp_path, monkeypatch, ["a_test.gd", "new_test.gd"], {"test/a_test.gd": 3.0})
    monkeypatch.setattr(sys, "argv", ["shard_assign.py", "--shards", "1", "--index", "0"])
    assert shard_assign.main() == 0
    assert capsys.readouterr().out.split() == ["test/a_test.gd", "test/new_test.gd"]


def test_check_passes_on_the_real_tree():
    os.chdir(ROOT)
    r = subprocess.run([sys.executable, "tools/shard_assign.py", "--shards", "10", "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout


# --- tools/shard_weights_from_logs.py -------------------------------------------------------------

def _log(*stamps):
    """A shard log: ANSI-coloured `Run Test Suite` lines at the given (time, suite) pairs, plus a summary line."""
    rows = ["2026-11-18T20:45:00.5000000Z ##[group]Run gdUnit", "2026-11-18T20:45:01.0000000Z noise Overall Summary: x"]
    for t, s in stamps[:-1]:
        rows.append(f"2026-11-18T{t}Z \x1b[38;2;0;206;209mRun Test Suite: \x1b[0m\x1b[38;2;250;235;215mres://{s}\x1b[0m")
    rows.append(f"2026-11-18T{stamps[-1][0]}Z \x1b[38;2;30;144;255mOverall Summary:\x1b[0m 3 test cases")
    return "\n".join(rows)


def test_weights_from_a_three_suite_log_are_the_gaps_between_the_run_lines():
    log = _log(("20:45:10.0000000", "test/a_test.gd"), ("20:45:12.5000000", "test/b_test.gd"),
               ("20:46:12.5000000", "test/c_test.gd"), ("20:46:12.5500000", "end"))
    assert swl.median_weights([log]) == {"test/a_test.gd": 2.5, "test/b_test.gd": 60.0, "test/c_test.gd": 0.1}


def test_weights_from_two_runs_take_the_median_per_suite_and_render_the_existing_format():
    runs = [_log(("20:00:00.0000000", "test/a_test.gd"), ("20:00:10.0000000", "x")),
            _log(("20:00:00.0000000", "test/a_test.gd"), ("20:00:30.0000000", "x")),
            _log(("20:00:00.0000000", "test/a_test.gd"), ("20:00:14.0000000", "x"))]
    w = swl.median_weights(runs)
    assert w == {"test/a_test.gd": 14.0}
    assert swl.render({"test/b_test.gd": 2.0, **w}) == '{\n"test/a_test.gd": 14.0,\n"test/b_test.gd": 2.0\n}\n'


def test_a_log_without_an_overall_summary_skips_its_last_suite(tmp_path, monkeypatch, capsys):
    cut = "\n".join(_log(("20:00:00.0000000", "test/a_test.gd"), ("20:00:04.0000000", "test/b_test.gd"),
                         ("20:00:09.0000000", "end")).splitlines()[:-1])
    assert swl.median_weights([cut]) == {"test/a_test.gd": 4.0}
    # the CLI drops a suite that is not on disk (shard_assign.py --check would reject its line)
    (tmp_path / "test").mkdir()
    (tmp_path / "test" / "a_test.gd").write_text("")
    (tmp_path / "shard.log").write_text(_log(("20:00:00.0000000", "test/a_test.gd"), ("20:00:04.0000000", "test/gone_test.gd"),
                                             ("20:00:09.0000000", "end")))
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(sys, "argv", ["shard_weights_from_logs.py", "shard.log"])
    assert swl.main() == 0
    assert capsys.readouterr().out == '{\n"test/a_test.gd": 4.0\n}\n'

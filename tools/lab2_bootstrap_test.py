"""The bootstrap's exactness: order statistics, never interpolated quantiles; cells c1..c12 numerically; the drawn
index stream hashed, so the same hashed key reproduces it and another key does not."""
import importlib.util
import os

import pytest

np = pytest.importorskip("numpy")
_SPEC = importlib.util.spec_from_file_location(
    "lab2_tree_probe", os.path.join(os.path.dirname(os.path.abspath(__file__)), "lab2_tree_probe.py"))
lab = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(lab)


def test_bounds_are_order_statistics_where_interpolation_differs():
    draws = np.arange(1000.0)  # sorted; np.quantile would answer 4.995 and 994.005
    assert (lab.order_stat(draws, 0.005), lab.order_stat(draws, 0.995)) == (4.0, 994.0)
    assert (lab.order_stat(draws, 0.025), lab.order_stat(draws, 0.975)) == (24.0, 974.0)
    assert np.quantile(draws, 0.005) != lab.order_stat(draws, 0.005)


def test_cells_iterate_numerically():
    assert sorted(["c10", "c2", "c12", "c1"], key=lab.cell_key) == ["c1", "c2", "c10", "c12"]


def _gains(order):
    return {c: {"g%d" % j: {"A_T": (j + int(c[1:])) % 3 / 2} for j in range(3 + int(c[1:]) % 2)} for c in order}


def test_the_same_key_draws_the_same_index_stream_in_any_dict_order():
    a = lab.bootstrap_intervals(_gains(["c2", "c10", "c1"]), resamples=300, seed=7)
    b = lab.bootstrap_intervals(_gains(["c10", "c1", "c2"]), resamples=300, seed=7)
    c = lab.bootstrap_intervals(_gains(["c1", "c2", "c10"]), resamples=300, seed=8)
    assert a == b and a["A_T"]["index_sha256"] != c["A_T"]["index_sha256"]
    t = a["A_T"]
    assert t["lo"] <= t["lo95"] <= t["point"] <= t["hi95"] <= t["hi"]

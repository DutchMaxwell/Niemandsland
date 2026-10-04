#!/usr/bin/env python3
"""Tests for tools/lab2_source.py: real source games (1000 pt lists, bank, shipped net, top_k 2 / horizon 1).
Run on the laptop: ~/.cache/nml-stage0/venv/bin/python3 -m pytest -q tools/lab2_source_test.py
Skip with a named reason where nml_core, onnxruntime, the bank or the lists are absent (CI)."""
import importlib.util
import inspect
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(_HERE)
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(REPO, "core", "nml-core-py", "python"))
BANK = os.path.expanduser("~/selfplay_out/terrain_bank")
LISTS = os.path.expanduser("~/nml-mission/farm/ai_lists")
NEEDS = [m for m in ("nml_core", "onnxruntime") if importlib.util.find_spec(m) is None]
if not (os.path.isdir(BANK) and os.path.isdir(LISTS)):
    NEEDS.append("bank/lists")
pytestmark = pytest.mark.skipif(bool(NEEDS), reason="needs %s (laptop venv gate)" % ", ".join(NEEDS))
if not NEEDS:
    import nml_core
    import selfplay as sp
    import lab2_source as ls
    from lab2_net import ShippedNet

PLAY_KW = dict(top_k=2, horizon=1)


def row(cand, seed=29, mover=1):
    return dict(slot="s1", cell="c1", mission="domination", mover=str(mover), candidate=cand,
                list_p1="robot_legions_1000.json", list_p2="blessed_sisters_1000.json", terrain=str(seed),
                layout=str(seed + 1000), deploy=str(seed + 2000), play=str(seed + 3000), tray=str(seed + 4000),
                extra="x")


@pytest.fixture(scope="module")
def env():
    return nml_core.load(REPO), ShippedNet(REPO)


def run(env, rows, cap):
    core, net = env
    return ls.generate(sp, core, {"s1": rows}, REPO, BANK, LISTS, net, cap, PLAY_KW)


def test_second_candidate_is_taken_when_the_first_is_ineligible(env):
    positions, discarded, missing = run(env, [row("a", mover=3), row("b")], cap=20)
    assert missing == [] and [p["candidate"] for p in positions] == ["b"]
    assert [d["candidate"] for d in discarded] == ["a"] and discarded[0]["reason"] == "mover_mismatch"
    assert positions[0]["keys"] == {"extra": "x"} and positions[0]["mover"] == 1


def test_cap_one_with_an_ineligible_first_is_missing(env):
    positions, discarded, missing = run(env, [row("a", mover=3), row("b")], cap=1)
    assert positions == [] and missing == ["s1"] and len(discarded) == 1


def test_snapshot_round_trips_through_state_of(env):
    positions, _, _ = run(env, [row("b")], cap=1)
    snap = positions[0]
    state = env[0].state_of(snap["state"])
    assert state.plain() == snap["state"] and snap["state"]["round"] == snap["state"]["rounds_total"]
    assert all(2 <= len(state.pool(p, True)) <= 3 for p in (1, 2)) and len(snap["owners_before_round"]) > 0


def test_spy_reads_no_result_field():
    src = inspect.getsource(ls.Spy)
    for word in ("winner", "rounds_log", "verdict", "result", '"vp"', "expectation"):
        assert word not in src, word



def test_two_workers_write_the_same_positions_timing_and_transitions_as_one_process(tmp_path):
    import csv, json
    tsv = tmp_path / "s.tsv"
    with open(tsv, "w", newline="") as f:
        w = csv.DictWriter(f, list(row("a")), delimiter="\t")
        w.writeheader()
        w.writerow(dict(row("a"), slot="s1"))
        w.writerow(dict(row("b", seed=31, mover=2), slot="s2"))
    (tmp_path / "h.json").write_text(json.dumps({"knobs": {"top_k": 2, "horizon": 1}}))
    outs = {}
    for n in (1, 2):
        d = tmp_path / ("w%d" % n)
        d.mkdir()
        ls.main(["source", "--slots", str(tsv), "--bank", BANK, "--lists", LISTS, "--header", str(tmp_path / "h.json"),
                 "--out", str(d / "p.json"), "--timing-out", str(d / "t.json"), "--transitions-out", str(d / "x.json"),
                 "--workers", str(n)])
        p = json.loads((d / "p.json").read_text())
        outs[n] = (p["positions"], [(c["slot"], c["eligible"]) for c in p["candidates"]], (d / "t.json").read_text(),
                   (d / "x.json").read_text(), json.loads((d / "x.json.headers").read_text()))
    assert outs[1] == outs[2] and len(outs[1][0]) == 2


def test_cli_writes_positions_proof_and_exit_code(tmp_path):
    import csv, json
    tsv, header, out = tmp_path / "s.tsv", tmp_path / "h.json", tmp_path / "p.json"
    with open(tsv, "w", newline="") as f:
        w = csv.DictWriter(f, list(row("a")), delimiter="\t")
        w.writeheader(), w.writerow(row("a"))
    header.write_text(json.dumps({"knobs": {"top_k": 2, "horizon": 1, "menu_wide": "table"}}))
    argv = ["source", "--slots", str(tsv), "--bank", BANK, "--lists", LISTS, "--header", str(header), "--out", str(out),
            "--timing-out", str(tmp_path / "t.json"), "--transitions-out", str(tmp_path / "x.json")]
    assert ls.main(argv) == 0
    data = json.loads(out.read_text())
    assert len(data["positions"]) == 1 and data["ignored_header_knobs"] == ["menu_wide"]
    assert len(json.loads((tmp_path / "t.json").read_text())) == 12
    assert len(json.loads((tmp_path / "x.json").read_text())) == 9 and "s1:a" in json.loads((tmp_path / "x.json.headers").read_text())
    assert data["net"]["1"]["calls"] > 0 and data["net"]["2"]["calls"] > 0


GRADE = {"top_k": 2, "horizon": 1, "dice": "table", "hero_attach": "table", "seam_cast": True, "deployment": "arena"}


def test_knobs_play_the_source_games_at_the_shipped_grade_and_refuse_what_the_source_fixes(tmp_path):
    import csv, json
    tsv, header, knobs, out = (tmp_path / n for n in ("s.tsv", "h.json", "k.json", "p.json"))
    with open(tsv, "w", newline="") as f:
        w = csv.DictWriter(f, list(row("a")), delimiter="\t")
        w.writeheader(), w.writerow(row("a"))
    header.write_text(json.dumps({"knobs": {"top_k": 9, "horizon": 9}}))
    knobs.write_text(json.dumps(GRADE))
    argv = ["source", "--slots", str(tsv), "--bank", BANK, "--lists", LISTS, "--header", str(header),
            "--knobs", str(knobs), "--out", str(out), "--transitions-out", str(tmp_path / "x.json")]
    ls.main(argv)
    played = json.loads((tmp_path / "x.json.headers").read_text())["s1:a"]["knobs"]  # the header the game really set
    assert played["seam_cast"] is True and played["hero_attach"] is True and played["deployment"] == "arena"
    assert (played["top_k"], played["horizon"]) == (2, 1) and json.loads(out.read_text())["play_kwargs"] == GRADE
    knobs.write_text(json.dumps(dict(GRADE, mission="duel", dice="expected")))
    with pytest.raises(SystemExit, match="mission,dice"):
        ls.main(argv)


def test_timing_set_lists_games_and_activations_in_order(env):
    timing = ls.TimingSet(per_cell=1000)
    core, net = env
    slots = {"s1": [row("a", seed=29)], "s2": [dict(row("b", seed=31, mover=2), slot="s2")]}
    ls.generate(sp, core, slots, REPO, BANK, LISTS, net, 1, PLAY_KW, timing)
    sources = [r["source"] for r in timing.states]
    assert sorted(set(sources)) == ["s1:a", "s2:b"] and sources == sorted(sources)  # game 1 wholly before game 2
    for src in set(sources):
        seqs = [r["seq"] for r in timing.states if r["source"] == src]
        assert seqs == sorted(seqs) and len(set(seqs)) == len(seqs) and seqs[0] == 1
    assert all(core.state_of(r["state"]).pool(r["player"], True) for r in timing.states[:3])


def test_timing_set_keeps_twelve_and_a_short_cell_fails(env):
    timing = ls.TimingSet()
    core, net = env
    ls.generate(sp, core, {"s1": [row("a")]}, REPO, BANK, LISTS, net, 1, PLAY_KW, timing)
    assert timing.count == {"c1": 12} and [r["seq"] for r in timing.states] == list(range(1, 13))
    assert timing.short({"c1"}) == {} and timing.short({"c1", "c2"}) == {"c2": 0}
    assert ls.TimingSet(per_cell=13).short({"c1"}) == {"c1": 0}


def test_transitions_replay_and_the_reds_fail(env):
    import lab2_tree_probe as lab
    core, net = env
    trans = ls.TransitionSet(quota=lambda cell: 40)
    ls.generate(sp, core, {"s1": [row("a")]}, REPO, BANK, LISTS, net, 1, PLAY_KW, None, trans)
    recs = trans.records
    assert len(recs) == 40 and [r["seq"] for r in recs] == list(range(1, 41))
    assert list(trans.headers) == ["s1:a"]

    def fresh():  # a replay core needs its game's header, as `lab2_tree_probe` pilot will have to supply
        c = nml_core.load(REPO)
        c.set_header(trans.headers["s1:a"])
        return c
    results = [lab.replay_transition(nml_core, fresh(), r) for r in recs]
    assert all(r["ok"] for r in results), [r["checks"] for r in results if not r["ok"]][:1]
    red_rec = next(r for r in recs if r["after"].get("vp") is not None)
    die_rec = next(r for r in recs if any(x["faces"] for x in r["rolls"]))
    assert not lab.replay_transition(nml_core, fresh(), lab.red_vp(red_rec))["ok"]
    assert not lab.replay_transition(nml_core, fresh(), lab.red_die(die_rec))["ok"]


def test_default_quota_is_100_and_short_cells_are_named():
    assert sum(ls.default_quota("c%d" % n) for n in range(1, 13)) == 100
    assert [ls.default_quota(c) for c in ("c4", "c5", "c12")] == [9, 8, 8]
    t = ls.TransitionSet()
    for _ in range(9):
        t.add({"cell": "c1"})
    assert t.full("c1") and t.short({"c1", "c5"}) == {"c5": 0}


def test_attach_eval_takes_decimal_keys_and_refuses_a_missing_position(tmp_path):
    import csv
    tsv = tmp_path / "e.tsv"
    with open(tsv, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["cell", "source", "replicate", "purpose", "owner", "arm", "seed"])
        for r in range(8):
            w.writerow(["c1", "k1", r, "eval_general", "", "", 9_000_000_000_000_000_000 + r])
            w.writerow(["c1", "k1", r, "eval_tray", "", "", 5 + r])
            w.writerows(["c1", "k1", r, "search_general", o, arm, 100 * r + int(o)] for o in "12" for arm in ("L", "T", "L_tray", "T_tray"))
    pos = [{"slot": "s", "cell": "c1", "keys": {"source": "k1"}}]
    ls.attach_eval(pos, str(tsv))
    assert pos[0]["eval"][3] == {"general": "9000000000000000003", "tray": "8"} and len(pos[0]["eval"]) == 8
    assert pos[0]["search"]["T"][3] == {"1": "301", "2": "302"} and set(pos[0]["search"]) == {"L", "T", "L_tray", "T_tray"}
    with pytest.raises(SystemExit):
        ls.attach_eval([{"slot": "t", "cell": "c1", "keys": {"source": "k2"}}], str(tsv))


def test_ending_from_the_source_snapshot_reproduces_the_source_game(env):
    """Fidelity (hand planner on both sides so the I/I ending is the source game's own continuation)."""
    import lab2_tree_probe as lab
    core = env[0]
    r = row("a", seed=29)
    snap, _ = ls.play_candidate(sp, core, r, REPO, BANK, LISTS, None, PLAY_KW)
    full = sp.play_game(29, os.path.join(LISTS, r["list_p1"]), os.path.join(LISTS, r["list_p2"]), REPO, BANK, core,
                        record_final_state=True, **ls.source_kwargs(r, None, PLAY_KW))
    state, _, win = lab.finish_ending(nml_core, sp, {"inc": core, "cand": core}, snap, *restored(snap["streams"]))
    assert win == full["winner"] and sp.final_state_digest(state) == full["final_state_hash"]


def restored(st):
    rng, tray, n = nml_core.Rng(0), nml_core.Tray(st["dice_seed"]), st["faces_before"]
    rng.state = st["rng_state"]
    while n > 0:
        tray.roll(min(n, 4096))
        n -= min(n, 4096)
    assert tray.state == st["tray_state"]
    return rng, tray


def test_a_one_vp_corruption_of_the_snapshot_flips_the_verdict(env):
    """Seed 34 on domination ends 7:7 (a draw): +1 VP in the snapshot's own ledger must decide it."""
    import lab2_tree_probe as lab
    core = env[0]
    snap, _ = ls.play_candidate(sp, core, row("a", seed=34), REPO, BANK, LISTS, None, PLAY_KW)
    assert lab.finish_ending(nml_core, sp, {"inc": core, "cand": core}, snap, *restored(snap["streams"]))[2] == "draw"
    bad = dict(snap, state=dict(snap["state"], vp=[snap["state"]["vp"][0] + 1, snap["state"]["vp"][1]]))
    assert lab.finish_ending(nml_core, sp, {"inc": core, "cand": core}, bad, *restored(snap["streams"]))[2] == "p1"


class StubNet:
    """A net whose hooks answer 0.0 and never count: the `net_inactive` tripwire must catch it."""
    counts = {1: {"calls": 0, "leaves": 0}, 2: {"calls": 0, "leaves": 0}}

    def hook(self, side):
        return lambda leaves, _side=None: [0.0] * len(leaves)


def ending_env(env, seed=29):
    """(snapshot, cores factory) of one source game on the hand planner; the game header gives the arm cores."""
    core, trans = env[0], ls.TransitionSet(quota=lambda cell: 1)
    snap, _ = ls.play_candidate(sp, core, row("a", seed=seed), REPO, BANK, LISTS, None, PLAY_KW, None, trans)
    snap["search"] = {a: [{"1": str(1000 + r), "2": str(2000 + r)} for r in range(8)] for a in ("L", "T")}
    header = trans.headers["s1:a"]

    def cores(arm):
        cand = nml_core.load(REPO)
        extra = dict(lab_arm(arm), **({"deadline_us": 50000} if arm != "I" else {}))
        cand.set_header(dict(header, knobs=dict(header["knobs"], **extra)))
        return {"inc": core, "cand": cand}
    return snap, cores


def lab_arm(arm):
    import lab2_tree_probe as lab
    return lab.ARM_KNOBS[arm]


def test_a_never_called_net_makes_the_row_invalid(env):
    import lab2_tree_probe as lab
    snap, cores = ending_env(env)
    row_ = lab.run_ending(nml_core, sp, cores("I"), snap, *restored(snap["streams"]), "I", StubNet())
    assert row_["valid"] is False and row_["reason"] == "net_inactive"


def test_rows_are_byte_identical_and_the_real_net_is_active(env):
    import lab2_tree_probe as lab
    snap, cores = ending_env(env)
    net = env[1]
    out = [lab.run_ending(nml_core, sp, cores("T"), snap, *restored(snap["streams"]), "T", net,
                          lab.search_streams(nml_core, snap, "T", 0)) for _ in range(2)]
    assert lab.canon(out[0]) == lab.canon(out[1])
    assert out[0]["valid"] and out[0]["net_calls"][3 - snap["mover"]] > 0 and len(out[0]["search"]) >= 2


def test_t_decisions_receive_different_sigs(env):
    import lab2_tree_probe as lab
    snap, cores = ending_env(env)
    seen, real = [], sp._pick_for

    def spy(core, state, player, *args, **kwargs):
        if "sig" in kwargs:
            seen.append(kwargs["sig"])
        return real(core, state, player, *args, **kwargs)
    with sp.forced_picks(spy):
        row_ = lab.run_ending(nml_core, sp, cores("T"), snap, *restored(snap["streams"]), "T", None,
                              lab.search_streams(nml_core, snap, "T", 0))
    sigs = [d["sig"] for d in row_["search"]]  # landed picks; a dry side's pending sig is re-offered, never redrawn
    assert len(sigs) >= 2 and len(set(sigs)) == len(sigs) and set(sigs) <= set(seen)
    assert {d["seed"] for d in row_["search"]} == {int(snap["search"]["T"][0][str(snap["mover"])])}


CTX = {"prereg": "p" * 64, "build": {"commit": "abc", "dirty": False, "rules_epoch": 68, "wheel_sha256": "w"}}
PRINCIPLES_ROW = ("schema prereg_sha256 row_id split part cell source arm opponent seat replicate seeds build model_sha256 "
                  "header_sha256 net decisions y winner valid reason wall_s rss_hwm_mib done").split()
PRINCIPLES_DECISION = "seq side arm allocated_us elapsed_us preselect_us overshoot_us tree deadline search net_calls".split()


def test_play_row_runs_real_games_as_schema_rows(env):
    import lab2_tree_probe as lab
    b = {"block": "b0", "cell": "c1", "mission": "domination", "army1": os.path.join(LISTS, "robot_legions_1000.json"),
         "army2": os.path.join(LISTS, "blessed_sisters_1000.json"),
         "seeds": {"terrain": "29", "layout": "1029", "deploy": "2029", "play_general": ["3029", "3030"],
                   "tray": ["4029", "4030"], "search": {"d%dc%d" % (d, s): {"L": {"1": "501", "2": "502"}, "C": {"1": "601", "2": "602"}}
                                                        for d in (0, 1) for s in (1, 2)}}}
    for arm in ("I", "L", "C"):
        rec = lab.play_row(nml_core, sp, lab.game_rows([b], (arm,))[0], REPO, BANK, {}, env[1], 20000, CTX)
        assert list(rec) == PRINCIPLES_ROW and rec["valid"] and rec["winner"] in ("p1", "p2", "draw")
        assert all(list(d) == PRINCIPLES_DECISION for d in rec["decisions"]) and rec["decisions"]
        deep = [d for d in rec["decisions"] if d["arm"] != "I"]
        assert (arm == "I") == (not deep)
        # A3: every searching arm (L and C alike) runs its allowance after the root preselection and stamps its time
        assert all(isinstance(d["preselect_us"], int) and 0 < d["preselect_us"] <= d["elapsed_us"] for d in deep)
        assert all(d["preselect_us"] is None for d in rec["decisions"] if d["arm"] == "I")
        if arm == "L":
            assert all(d["tree"] and d["allocated_us"] == 20000 and d["search"] for d in deep)
            assert all(d["tree"] is None for d in rec["decisions"] if d["arm"] == "I")
        if arm == "C":
            assert all(d["deadline"] and d["tree"] is None and d["allocated_us"] == 20000 for d in deep)


def test_ending_rows_carry_tree_only_on_tree_decisions(env):
    import lab2_tree_probe as lab
    snap, cores = ending_env(env)
    snap["eval"] = [{"general": str(7000 + r), "tray": str(8000 + r)} for r in range(8)]
    snap["search"]["L"] = snap["search"]["T"]
    ctx = dict(CTX, hdr={"inc": "h0", "T": "h1", "I": "h0"})
    row_t = lab.ending_row(nml_core, sp, cores("T"), snap, "T", 0, env[1], ctx)
    row_i = lab.ending_row(nml_core, sp, cores("I"), snap, "I", 0, env[1], ctx)
    assert list(row_t) == PRINCIPLES_ROW and row_t["valid"] and row_t["row_id"].endswith("_T_r0")
    mine = [d for d in row_t["decisions"] if d["arm"] == "T"]
    assert mine and all(d["tree"] and d["search"] and d["allocated_us"] == 50000 for d in mine)
    assert all(d["tree"] is None for d in row_t["decisions"] if d["arm"] == "I")
    assert all(d["tree"] is None and d["allocated_us"] is None for d in row_i["decisions"])


def test_fullgames_on_two_workers_write_the_same_rows_as_one(env, tmp_path, monkeypatch):
    import json
    import lab2_tree_probe as lab
    monkeypatch.setattr(lab, "bootstrap_intervals", lambda *a, **k: {})  # arm I alone has no L/C contrasts to resample
    blocks = []
    for i, seed in enumerate(("29", "31")):
        blocks.append({"block": "b%d" % i, "cell": "c1", "mission": "domination",
                       "army1": os.path.join(LISTS, "robot_legions_1000.json"), "army2": os.path.join(LISTS, "blessed_sisters_1000.json"),
                       "seeds": {"terrain": seed, "layout": "10" + seed, "deploy": "20" + seed, "play_general": ["30" + seed, "31" + seed],
                                 "tray": ["40" + seed, "41" + seed], "search": {}}})
    for name, data in (("blocks", blocks), ("timing", {"c1": {"B_us": 20000}}), ("knobs", {"top_k": 2, "horizon": 1})):
        (tmp_path / (name + ".json")).write_text(json.dumps(data))
    pilot = tmp_path / "pilot.json"
    for workers in (1, 2):
        argv = ["fullgames", "--blocks", str(tmp_path / "blocks.json"), "--timing", str(tmp_path / "timing.json"),
                "--knobs", str(tmp_path / "knobs.json"), "--bank", BANK, "--out-dir", str(tmp_path / ("w%d" % workers)),
                "--prereg-sha256", "p" * 64, "--arms", "I", "--resamples", "50", "--out", str(tmp_path / ("o%d" % workers)),
                "--repo", REPO, "--workers", str(workers), "--scheduler-key", "7"]
        assert lab.main(argv + (["--pilot-json", str(pilot)] if workers == 2 else [])) == 0
    names = sorted(os.listdir(tmp_path / "w1"))
    assert names == sorted(os.listdir(tmp_path / "w2")) and len(names) == 8
    drop = ("wall_s", "rss_hwm_mib")
    strip = lambda r: {k: ([{kk: vv for kk, vv in d.items() if kk not in ("elapsed_us", "overshoot_us")} for d in v] if k == "decisions" else v)
                       for k, v in r.items() if k not in drop}
    for n in names:
        assert strip(json.load(open(tmp_path / "w1" / n))) == strip(json.load(open(tmp_path / "w2" / n))), n
    info = json.load(open(pilot))
    assert info["workers"] == 2 and abs(info["sum_hwm_mib"] - sum(info["worker_hwm_mib"].values())) < 1e-9

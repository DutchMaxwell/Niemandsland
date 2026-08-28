"""NML-1073 M5 D1-B4b RED-GREEN — a joined HERO has no activation of its own.

THE BUG THIS PINS. D1-B4b gave the tray resolver the host's attached heroes as
extra members of one volley (`main._run_ai_shooting` :2954-2958). On its own that
would have let a hero fire TWICE under `hero_attach="table"`: once inside its
host's volley, and once in the full activation the trainer's pool still handed
it, because the pool filtered on player/activated/alive only.

The table does not work that way. `SoloController.can_activate`
(solo_controller.gd:405-411) ends on `not u.is_attached()`, and the host's move
walks `get_alive_models_with_attached()` (`_moving_models` :5319-5321), so a
joined hero moves with the host and never takes a turn of its own.

THREE PROPERTIES, each with its RED half measured on the SAME state with the
attachment stripped — which is exactly what a `hero_attach="off"` corpus is:

  (1) the pool never offers a joined hero;
  (2) the host's activation marks its heroes activated too;
  (3) the hero's models take the host's displacement.

The fixture is the bundled `shoot_replay` game (a real table recording, so its
hosts really do carry heroes) — no new fixture, no corpus dependency.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import nml_core

REPO = str(Path(__file__).resolve().parents[4])
GAME = Path(__file__).resolve().parent / "fixtures" / "shoot_replay"


def _acts():
    lines = [json.loads(x) for x in (GAME / "acts.jsonl").read_text().splitlines() if x.strip()]
    return lines[0], [a for a in lines[1:] if a.get("kind") == "act"]


def _detached(plain: dict) -> dict:
    """The same state as a `hero_attach="off"` corpus carries it."""
    out = dict(plain)
    out["units"] = {k: dict(u, attached=[], attached_to="") for k, u in plain["units"].items()}
    return out


def _core(head, hero_attach: bool = True):
    """`hero_attach` is `Seams::hero_attach` (io.rs), the seam that folds a
    joined hero into its host. It is OFF by default in the crate because
    `BattleSim` — the parity authority for every planner gate — does not fold
    (ai_planner.gd:27/131/645 filters on player/activated/alive only,
    battle_sim.gd:699-700 moves the mover's own positions and nothing else), and
    a table RECORDING carries attachment on every host, so folding it in
    unconditionally would move the recorded rollout values and redden GATE G5.
    `selfplay.play_game(hero_attach="table")` turns it on."""
    core = nml_core.load(REPO)
    knobs = dict(head.get("knobs", {}), hero_attach=hero_attach)
    core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                     "knobs": knobs})
    return core


def _centre(plain: dict, key: str):
    ps = plain["units"][key]["positions"]
    n = len(ps)
    return tuple(sum(p[a] for p in ps) / n for a in range(3)) if n else None


def test_a_joined_hero_never_takes_an_activation_of_its_own():
    head, lines = _acts()
    core = _core(head)
    plain = lines[0]["state"]
    heroes = {k for k, u in plain["units"].items() if u.get("attached_to")}
    assert heroes, "the fixture no longer carries an attached hero"
    # MEASURED, and it is the table's own answer, not this port's: two of the
    # fixture's four heroes are ALREADY `activated` in the recorded state, next
    # to their un-activated hosts' peers — the table marks a joined hero
    # activated when its host goes, which is exactly what `sim.rs` now does.
    assert any(plain["units"][h]["activated"] for h in heroes)
    live = {h for h in heroes
            if not plain["units"][h]["activated"] and plain["units"][h]["alive"] > 0}
    assert live, "every fixture hero is already activated — nothing to filter"

    for player in (1, 2):
        offered = set(core.state_of(plain).pool(player))
        assert not (offered & heroes), "a joined hero was offered an activation"
    # RED: strip the attachment — a `hero_attach="off"` state — and every LIVE
    # hero comes straight back into its side's pool. So the filter is doing the
    # work, not the fixture.
    loose = set()
    for player in (1, 2):
        loose |= set(core.state_of(_detached(plain)).pool(player))
    assert live <= loose, "detaching changed nothing — the pool filter is untested"

    # And the count is the table's: one activation per HOST, never per model.
    hosts = [k for k, u in plain["units"].items()
             if u["alive"] > 0 and not u["activated"] and not u.get("attached_to")]
    got = sum(len(core.state_of(plain).pool(p)) for p in (1, 2))
    assert got == len(hosts), "activations must equal the host count: %d vs %d" % (
        got, len(hosts))


def test_the_host_activation_carries_its_heroes_along():
    """The host moves, the hero moves with it and spends the same activation.

    MEASURED FIRST, on the recording: by the time the table picks a host, that
    host's joined hero is ALREADY `activated` in the act's plain state — the
    table has never let it act on its own. A trainer state under
    `hero_attach="table"` does not look like that: `derive_attachment` fills
    `attached`/`attached_to` and nothing pre-marks the hero, so its flag comes
    up false at every round start (`rollout.rs:268`). That is the shape this
    test builds — one act of the recording with the hero's flag cleared — and
    it is the shape the double-fire bug lived in.
    """
    head, lines = _acts()
    core = _core(head)
    for act in lines:
        action = (act.get("pick") or {}).get("action") or {}
        unit = action.get("unit")
        plain = act["state"]
        if not unit or unit not in plain["units"] or not action.get("dest"):
            continue
        hero = next((h for h in (plain["units"][unit].get("attached") or [])
                     if plain["units"][h]["positions"]), None)
        if hero is None or not plain["units"][unit]["positions"]:
            continue
        # The trainer's shape: a joined hero that has NOT yet been marked.
        plain = dict(plain, units=dict(plain["units"],
                                       **{hero: dict(plain["units"][hero], activated=False)}))
        before_host, before_hero = _centre(plain, unit), _centre(plain, hero)
        nxt = core.resolve_stochastic_rng(core.state_of(plain), action, nml_core.Rng(0)).plain()
        moved = tuple(a - b for a, b in zip(_centre(nxt, unit), before_host))
        if max(abs(m) for m in moved) < 1e-9:
            continue  # the move clamped to nothing here; take the next act

        assert nxt["units"][hero]["activated"], "the host went, the hero stayed un-activated"
        hero_moved = tuple(a - b for a, b in zip(_centre(nxt, hero), before_hero))
        for a, b in zip(hero_moved, moved):
            assert abs(a - b) < 1e-9, "the hero did not take the host's displacement: %s vs %s" % (
                hero_moved, moved)

        # RED — the SAME state and the same act with the SEAM off, which is what
        # `hero_attach="off"` is. The hero is left standing on the board with
        # its activation still in hand: the pre-B4b behaviour, and exactly the
        # shape the double-fire bug lived in.
        off = _core(head, hero_attach=False)
        red = off.resolve_stochastic_rng(
            off.state_of(plain), action, nml_core.Rng(0)).plain()
        assert not red["units"][hero]["activated"], "the RED half already marks the hero"
        red_moved = tuple(a - b for a, b in zip(_centre(red, hero), before_hero))
        assert max(abs(m) for m in red_moved) < 1e-9, "the RED half already moves the hero"
        return
    raise AssertionError("no act in the fixture moves a host that carries a hero")


# ------------------------------------------- NML-1127: the JOIN is not the FOLD ---


def test_the_harness_pool_folds_a_joined_hero_only_under_the_seam():
    """RED-GREEN — `State.pool` must ask the fold seam, not assume it.

    `State.pool` used to call `can_activate(.., true)` unconditionally, on the
    argument that a corpus without the seam carries no attachment either. That
    was true until NML-1105 and is false since: `tools/core_selfplay.gd` now
    builds its units through the table's import path, so its states carry
    `attached_to` on every host while its pool (:431-436) is still the
    planner's own filter and never folds — a `hero_attach: false` header over
    a fully joined roster. Folding regardless costs one activation per joined
    hero, which is what read 0/20 on every M3 gate against that oracle.
    """
    head, lines = _acts()
    core = _core(head)
    plain = lines[0]["state"]
    live = {k for k, u in plain["units"].items()
            if u.get("attached_to") and not u["activated"] and u["alive"] > 0}
    assert live, "the fixture no longer carries a live joined hero"

    folded = set()
    loose = set()
    for player in (1, 2):
        folded |= set(core.state_of(plain).pool(player, True))
        loose |= set(core.state_of(plain).pool(player, False))
    assert not (folded & live), "the seam ON must keep a joined hero out of the pool"
    assert live <= loose, "the seam OFF must still hand a joined hero its own activation"
    # The DEFAULT is the fold — every caller written before NML-1127 gets what
    # it always got, which is what keeps the frozen corpora byte-identical.
    for player in (1, 2):
        assert core.state_of(plain).pool(player) == core.state_of(plain).pool(player, True)


def test_hero_attach_of_corpus_reads_the_join_and_the_fold_apart(tmp_path):
    """`selfplay.hero_attach_of_corpus` — the mode a recording actually played.

    The header's `hero_attach` key is the FOLD alone; the JOIN is only visible
    in the first act's state. All three modes are distinguishable, and a gate
    that reads them off the corpus cannot be pointed at the wrong one.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
    import selfplay as sp

    head, lines = _acts()
    plain = lines[0]["state"]
    assert any(u.get("attached_to") for u in plain["units"].values())

    def write(fold: bool, state: dict) -> Path:
        path = tmp_path / ("c_%s_%d.jsonl" % (fold, len(list(tmp_path.iterdir()))))
        path.write_text(
            json.dumps({"kind": "header", "knobs": dict(head.get("knobs", {}),
                                                        hero_attach=fold)})
            + "\n" + json.dumps({"kind": "act", "state": state}) + "\n"
        )
        return path

    assert sp.hero_attach_of_corpus(write(False, plain)) == "join"
    assert sp.hero_attach_of_corpus(write(True, plain)) == "table"
    assert sp.hero_attach_of_corpus(write(False, _detached(plain))) == "off"

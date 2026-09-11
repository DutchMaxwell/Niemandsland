#!/usr/bin/env python3
"""Regenerate test/fixtures/policy_twin/state_phi_twin.json — the ONE fixture
both policy twins assert against:

  * core/nml-core/src/policy.rs   state_phi (policy.rs:322), PolicyNet::logit (policy.rs:117)
  * scripts/solo/policy_order.gd  state_phi (policy_order.gd:76), logit (policy_order.gd:108)

The expected numbers are computed here from a direct transcription of the Rust
arithmetic (IEEE-754 f64, identical operation order), never by hand; the Rust
test core/nml-core/tests/state_phi_twin.rs re-verifies the pin against the real
Rust functions on the farm, the gdUnit test test/policy_order_twin_test.gd
verifies the GDScript twin against the same pin in CI.

Usage: python3 tools/policy_twin/gen_state_phi_twin.py
"""
import json, os, random

FIXED = 22  # PHI_FIXED: policy.rs:323 / policy_order.gd:18
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "test", "fixtures", "policy_twin", "state_phi_twin.json")


def state_phi(board, side, actor_row):
    pools = [0.0] * (3 * FIXED)
    n = [0.0, 0.0, 0.0]
    for r in board:
        c0 = int(r[0])
        p = 0 if c0 == 3 else (1 if c0 == side else 2)
        for j in range(min(FIXED, len(r))):
            pools[p * FIXED + j] += r[j]
        n[p] += 1.0
    phi = [pools[p * FIXED + j] / max(n[p], 1.0) for p in range(3) for j in range(FIXED)]
    total = float(max(len(board), 1))
    phi += [c / total for c in n]
    phi += [0.0] * FIXED  # actor block: every caller uses actor_row = -1
    phi += [1.0 if side == 1 else 0.0, 1.0 if side == 2 else 0.0]
    return phi


def logit(net, phi, vec):
    z = net["b2"]
    for j in range(len(net["b1"])):
        acc = net["b1"][j]
        for i, x in enumerate(phi + vec):
            acc += x * net["w1"][i][j]
        z += max(acc, 0.0) * net["w2"][j]
    return z


def col(rng):
    return round(rng.uniform(-0.5, 0.5), 4)


def main():
    rng = random.Random(1158)  # NML-1158b: the policy twin step
    r = lambda: col(rng)
    # marker c0=3, two own rows per side, one foe row per side, one row shorter
    # than FIXED, one game-state row c0=4 (pools as foe for both sides).
    synthetic = [
        [3] + [r() for _ in range(21)],                    # marker
        [1] + [r() for _ in range(21)],                    # own s1 / foe s2
        [1] + [r() for _ in range(21)],                    # own s1 / foe s2
        [2] + [r() for _ in range(21)],                    # foe s1 / own s2
        [1] + [r() for _ in range(4)],                     # own s1 / foe s2, 5 cols
        [4] + [r() for _ in range(21)],                    # game state, foe both
        [2] + [r() for _ in range(21)],                    # foe s1 / own s2
    ]
    state_dim, act_dim, hidden = 93, 20, 3
    net = {"schema": "policy_net/1", "state_dim": state_dim, "act_dim": act_dim,
           "hidden": hidden,
           "w1": [[r() for _ in range(hidden)] for _ in range(state_dim + act_dim)],
           "b1": [r() for _ in range(hidden)], "w2": [r() for _ in range(hidden)],
           "b2": r()}
    candidate = [r() for _ in range(act_dim)]
    boards = {"synthetic": synthetic, "empty": []}
    cases = []
    for name, board_key, side in (
        ("synthetic_side_1", "synthetic", 1), ("synthetic_side_2", "synthetic", 2),
        ("empty_side_1", "empty", 1), ("empty_side_2", "empty", 2),
    ):
        phi = state_phi(boards[board_key], side, -1)
        assert len(phi) == state_dim
        cases.append({"name": name, "board": board_key, "side": side,
                      "state_phi": phi, "logit": logit(net, phi, candidate)})
    fixture = {"meta": {"generated_by": "tools/policy_twin/gen_state_phi_twin.py",
                        "seed": 1158, "actor_row": -1,
                        "references": "core/nml-core/src/policy.rs:322, :117; "
                                      "scripts/solo/policy_order.gd:76, :108"},
               "net": net, "candidate": candidate, "boards": boards, "cases": cases}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(fixture, f, indent=2)
        f.write("\n")
    print("wrote %s (%d cases)" % (OUT, len(cases)))


if __name__ == "__main__":
    main()

//! The NML-1073 M2-1 gates, pinned on the recorded ACT corpus.
//!
//! `acts_25.jsonl` is one whole `tools/arena_match.gd` game recorded with
//! `NML_ACT_DUMP` (M2-0a), 23 activations under an `NML_ACT_DUMP_MAX=25` cap:
//! robot_legions_1000 vs blessed_sisters_1000, seed 27, dice seed 27, both
//! sides `planner_v0`, `NML_SIM_SPACING=0 NML_SIM_CAST=0`, 4 rounds, 13 units,
//! a 3-marker `duel` mission on a 6x4 board with 107 painted terrain cells and
//! no sandbox pieces. Each line carries the FULL search input (`state`, incl.
//! the M2-0c/M2-0d per-unit gate reads), the live charge gate's answers
//! (`charge_illegal`, `charge_illegal_grid`) and the search trace, of which
//! `trace.menus` is this milestone's oracle.
//!
//! IT HAS BEEN RE-RECORDED TWICE, and both times for the same reason: a corpus
//! that describes a planner which no longer exists is not an oracle, it is a
//! fossil. M2-1 re-recorded it because the handed M2-0d capture still used the
//! pre-NML-1073-S1b charge gap. M2-1b (this step) re-recorded it because
//! NML-1073 S1d changed the RULE underneath it — `BattleSim.resolve`'s melee
//! trigger became `SoloController.MELEE_ENGAGE_IN` (1") and BOTH planner menu
//! sites now hand the charge gate the RAW base-edge gap instead of
//! `edge_gap_in - CHARGE_CONTACT_MARGIN_IN`. Against the pre-S1d corpus this
//! crate scored G3 238/287, G4 15/25 and G5 7/15; the game itself also plays
//! out differently, because charges that used to fall short now connect (23
//! activations instead of 25, 10 CHARGE candidates instead of 13).
//!
//! The corpus replays 23/23 through `act_recheck` at this HEAD (CHARGE_GATE
//! 50808/50808, CHARGE_MATRIX 1752/1752), which is what makes it an oracle at
//! all.
//!
//! GATE G1 — the CHARGE GATE: `gate::charge_illegal` reproduces the recorded
//! `charge_illegal_grid` for every ordered opposite-side pair at every gap of
//! the 0"..14" half-inch grid, plus the root `charge_illegal` matrix.
//!
//! GATE G2 — the MENU: for every (act, pool unit), `menu::candidates` equals the
//! recorded menu — same length, same kind order, `dest` equal to the last bit
//! (the recorded value is an f32 written at full precision, so the bar is
//! EXACT, not 1e-9), same shoot/charge keys, same patient/wave flags.

use std::collections::BTreeMap;

use nml_core::acts::{GATE_GRID_STEPS, GATE_GRID_STEP_IN};
use nml_core::menu::{candidates_tuned, Candidate, Tuning};
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, gate, load_acts, Act, ActCorpus, State};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// The `dest` bar. The recorder writes `BattleSim._plain_vec3` at full
/// precision, so every recorded component IS an f32 value and the port's f32
/// arithmetic has to land on it bit for bit.
const DEST_EPS: f64 = 1e-9;

fn corpus() -> ActCorpus {
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

/// Roster index of a recorded unit key.
fn idx(state: &State, key: &str) -> usize {
    *state.roster.index.get(key).unwrap_or_else(|| panic!("unknown unit key {key}"))
}

/// Every gap the recorder probed: 0", 0.5", ... 14" (act_recorder.gd:239-240).
fn grid_gaps() -> Vec<f64> {
    (0..GATE_GRID_STEPS).map(|i| i as f64 * GATE_GRID_STEP_IN).collect()
}

/// G1 over one act; returns (checks, mismatches). `honour_no_difficult` is true
/// for the gate itself and false for the red proof.
fn gate_pass(act: &Act, terrain: &nml_core::Terrain, honour_no_difficult: bool) -> (usize, usize) {
    let (mut n, mut bad) = (0usize, 0usize);
    let gaps = grid_gaps();
    // BTreeMap so a failure reports the same pair first on every run.
    let rows: BTreeMap<&String, &Vec<bool>> = act.charge_illegal_grid.iter().collect();
    for (pair, want) in rows {
        let (ak, vk) = pair.split_once('|').expect("pair key is attacker|victim");
        let (ai, vi) = (idx(&act.state, ak), idx(&act.state, vk));
        assert_eq!(want.len(), GATE_GRID_STEPS, "{pair}: recorded row is not the 29-step grid");
        for (g, &w) in gaps.iter().zip(want) {
            let got = gate::charge_illegal_tuned(
                &act.state,
                terrain,
                ai,
                vi,
                *g,
                None,
                None,
                honour_no_difficult,
            );
            n += 1;
            if got != w {
                bad += 1;
            }
        }
    }
    (n, bad)
}

#[test]
fn g1_the_pure_charge_gate_reproduces_the_recorded_gap_grid() {
    let c = corpus();
    assert_eq!(c.acts.len(), 23, "the fixture is the whole 23-activation recording");
    let (mut n, mut bad) = (0usize, 0usize);
    for act in &c.acts {
        let (an, ab) = gate_pass(act, &c.terrain, true);
        n += an;
        bad += ab;
    }
    println!("G1 charge gate: {}/{} grid answers reproduced", n - bad, n);
    assert_eq!(n, 50_808, "the grid size itself is part of the contract");
    assert_eq!(bad, 0, "{bad} of {n} grid answers differ from the live gate");
}

#[test]
fn g1b_the_pure_charge_gate_reproduces_the_root_pair_matrix() {
    let c = corpus();
    let (mut n, mut bad) = (0usize, 0usize);
    for act in &c.acts {
        let rows: BTreeMap<&String, &bool> = act.charge_illegal.iter().collect();
        for (pair, &want) in rows {
            let (ak, vk) = pair.split_once('|').expect("pair key is attacker|victim");
            let (ai, vi) = (idx(&act.state, ak), idx(&act.state, vk));
            // `AiActRecorder._charge_illegal_matrix` (act_recorder.gd:225-227):
            // the ROOT gap is the model-to-model distance minus CONTACT_IN,
            // floored at 0 — not the edge gap `_best_charge` uses.
            let gap = (nml_core::geom::dist_in(
                &act.state.positions[ai],
                &act.state.positions[vi],
            ) - nml_core::CONTACT_IN)
                .max(0.0);
            let got = gate::charge_illegal(&act.state, &c.terrain, ai, vi, gap, None, None);
            n += 1;
            if got != want {
                bad += 1;
            }
        }
    }
    println!("G1b charge gate root matrix: {}/{} reproduced", n - bad, n);
    assert_eq!(bad, 0, "{bad} of {n} root answers differ from the live gate");
}

/// Field-by-field candidate equality, in the order a mismatch report wants it.
fn same(got: &Candidate, want: &Candidate) -> Result<(), String> {
    if got.kind != want.kind {
        return Err(format!("kind {} != {}", got.kind, want.kind));
    }
    if got.unit != want.unit {
        return Err(format!("unit {} != {}", got.unit, want.unit));
    }
    match (&got.dest, &want.dest) {
        (None, None) => {}
        (Some(a), Some(b)) => {
            for k in 0..3 {
                if (a[k] - b[k]).abs() > DEST_EPS {
                    return Err(format!("dest {a:?} != {b:?}"));
                }
            }
        }
        _ => return Err(format!("dest {:?} != {:?}", got.dest, want.dest)),
    }
    if got.shoot != want.shoot {
        return Err(format!("shoot {:?} != {:?}", got.shoot, want.shoot));
    }
    if got.charge != want.charge {
        return Err(format!("charge {:?} != {:?}", got.charge, want.charge));
    }
    if got.patient != want.patient {
        return Err(format!("patient {} != {}", got.patient, want.patient));
    }
    if got.wave != want.wave {
        return Err(format!("wave {:?} != {:?}", got.wave, want.wave));
    }
    Ok(())
}

/// The G2 sweep, factored out so the red proof can count mismatches instead of
/// asserting on the first one. Returns (menus, candidates, mismatches, per-kind
/// counts, the first failure's message).
struct MenuReport {
    menus: usize,
    cands: usize,
    bad: usize,
    kinds: [usize; 4],
    first: Option<String>,
}

fn menu_sweep(c: &ActCorpus, tuning: Tuning) -> MenuReport {
    let statics = build_act_statics(c, REPO);
    let mut r = MenuReport { menus: 0, cands: 0, bad: 0, kinds: [0; 4], first: None };
    let mut sc = Scratch::default();
    for (ai, act) in c.acts.iter().enumerate() {
        // Pool order, not hash order: the report must be stable run to run.
        for key in &act.pool {
            let want = match act.menus.get(key) {
                Some(m) => m,
                None => panic!("act {ai}: pool unit {key} has no recorded menu"),
            };
            let got = candidates_tuned(
                &act.state,
                &c.terrain,
                &statics,
                idx(&act.state, key),
                &mut sc,
                tuning,
            );
            r.menus += 1;
            for cand in want {
                if (0..4).contains(&cand.kind) {
                    r.kinds[cand.kind as usize] += 1;
                }
            }
            if got.len() != want.len() {
                r.bad += want.len().max(got.len());
                r.cands += want.len();
                r.first.get_or_insert(format!(
                    "act {ai} unit {key}: menu length {} != recorded {}",
                    got.len(),
                    want.len()
                ));
                continue;
            }
            r.cands += want.len();
            for (i, (g, w)) in got.iter().zip(want).enumerate() {
                if let Err(why) = same(g, w) {
                    r.bad += 1;
                    r.first.get_or_insert(format!("act {ai} unit {key} candidate {i}: {why}"));
                }
            }
        }
    }
    r
}

#[test]
fn g2_the_rust_menu_equals_every_recorded_menu() {
    let c = corpus();
    let r = menu_sweep(&c, Tuning::default());
    println!(
        "G2 menu parity: {}/{} candidates over {} menus in {} acts \
         (HOLD {}, ADVANCE {}, RUSH {}, CHARGE {})",
        r.cands - r.bad,
        r.cands,
        r.menus,
        c.acts.len(),
        r.kinds[0],
        r.kinds[1],
        r.kinds[2],
        r.kinds[3]
    );
    assert_eq!(r.menus, 73, "one menu per pool unit per act");
    assert_eq!(r.cands, 529, "the recorded candidate count is part of the contract");
    assert_eq!(r.kinds, [103, 197, 219, 10], "per-kind composition of the oracle");
    assert_eq!(r.bad, 0, "{} mismatches; first: {}", r.bad, r.first.unwrap_or_default());
}

/// RED PROOF 1 — the D22 cover bonus is load-bearing, and the whole measured
/// curve is printed rather than one point of it, because the obvious probe
/// (6.0" -> 5.0") moves NOTHING and that is a fact about the rule, not a hole in
/// the gate: the safe frontier is the last 8 half-inch steps, so it spans 3.5",
/// and any bonus above that already outbids every rival point on it. The bonus
/// is saturated at 6". It starts biting at 3.0" and the curve on this corpus is
///
///   6.0 -> 0    5.0 -> 0    3.0 -> 2    1.0 -> 11    0.0 -> 11
///
/// so the branch is proven live, and the number the game ships is proven to sit
/// on a plateau rather than on a cliff.
#[test]
fn the_cover_bonus_is_load_bearing() {
    let c = corpus();
    let mut moved = 0usize;
    for bonus in [5.0f64, 3.0, 1.0, 0.0] {
        let bent = Tuning { cover_bonus_in: bonus, ..Tuning::default() };
        let r = menu_sweep(&c, bent);
        println!("RED cover bonus 6.0 -> {bonus}: {} of {} candidates differ", r.bad, r.cands);
        moved = moved.max(r.bad);
    }
    assert!(moved > 0, "no cover bonus at all moved a candidate — the branch is dead here");
}

/// RED PROOF 2 — the p.13 Strider/Flying exemption is load-bearing. Disable it
/// and the charge gate starts capping charges the live one waves through, so G1
/// stops reproducing the recorded grid.
#[test]
fn the_strider_exemption_is_load_bearing() {
    let c = corpus();
    let (mut n, mut bad) = (0usize, 0usize);
    for act in &c.acts {
        let (an, ab) = gate_pass(act, &c.terrain, false);
        n += an;
        bad += ab;
    }
    println!("RED Strider/Flying exemption off: {bad} of {n} grid answers differ");
    assert!(bad > 0, "the difficult-terrain exemption changed nothing — G1 cannot fail");
}

/// A menu is only worth as much as its ability to FAIL. The recorded oracle
/// carries no `shroud` and no Immobile/Artillery unit, so neither the shroud
/// reach nor `forces_hold` is exercised by G1/G2 — stated, not hidden.
#[test]
fn the_oracle_names_what_it_does_not_cover() {
    let c = corpus();
    let shrouded = c.acts.iter().flat_map(|a| a.state.shroud.iter()).filter(|s| s.is_some()).count();
    let carriers = c
        .profiles
        .list
        .iter()
        .filter(|p| nml_core::menu::forces_hold(&p.special_rules))
        .count();
    println!("uncovered by this fixture: shrouded victims {shrouded}, hold-only units {carriers}");
    assert_eq!(shrouded, 0);
    assert_eq!(carriers, 0);
}

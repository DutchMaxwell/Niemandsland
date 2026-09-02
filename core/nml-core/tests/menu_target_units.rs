//! NML-1157 — GATE for `Tuning::target_units`, the MENU's reading of a JOINED
//! UNIT, pinned on the same recorded act corpus GATE G2 uses.
//!
//! THE RULE. GF Advanced Rules v3.5.1 p.14 (Hero): "when a Hero joins a unit,
//! they count as part of that unit". The shipped table has never let one be
//! named on its own — `solo_controller.gd:1197` skips attached heroes when it
//! builds the AI's target list ("a joined hero is PART of its host unit — you
//! target the unit, never the hero alone"), and `main.gd:8452`/`:9166` resolve
//! every combat intent and every click on a hero to its host. This crate
//! already applies the identical guard in `tray_breath_attack` (`sim.rs:411`)
//! and Hit & Run (`sim.rs:890`). `menu::enemy_keys` did not.
//!
//! THE SECOND HALF. `best_charge` emits exactly ONE target, the argmax of
//! `charge_score` = dealt − taken, which has no distance term — so a lone hero,
//! the smallest strike-back on the board, wins the slot and the unit standing
//! an inch away is never offered. Measured on `~/selfplay_out/gen0_teacher`
//! (796 replayed activations): 544 of 787 charge offers name a joined hero, 51
//! name the nearest enemy, and 134 of the 144 activations with an enemy inside
//! 2" are offered a charge at somebody else.
//!
//! THE RED is the first test: with the knob OFF the menu still names joined
//! heroes, and it must, because that is what every recorded corpus carries.
//! Deleting the knob's default would turn that test red, which is the point.

use std::collections::BTreeSet;

use nml_core::menu::{candidates_tuned, Tuning};
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, gate, load_acts, ActCorpus, State};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// `AiDecision.Action` ai_decision.gd:16.
const CHARGE: i64 = 3;

fn corpus() -> ActCorpus {
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn idx(state: &State, key: &str) -> usize {
    *state.roster.index.get(key).unwrap_or_else(|| panic!("unknown unit key {key}"))
}

/// A unit key that is a JOINED HERO right now: attached, with a host that still
/// has living models (p.14's "fights on alone" leaves an orphaned hero a target).
fn joined_hero(state: &State, key: &str) -> bool {
    match state.attached_to[idx(state, key)] {
        Some(h) => state.alive[h] > 0,
        None => false,
    }
}

/// (menus, candidates, candidates naming a joined hero, menus carrying two
/// CHARGE candidates at different targets) over the whole corpus.
fn sweep(c: &ActCorpus, tuning: Tuning) -> (usize, usize, usize, usize) {
    let statics = build_act_statics(c, REPO);
    let mut sc = Scratch::default();
    let (mut menus, mut cands, mut snipes, mut twin) = (0, 0, 0, 0);
    for act in &c.acts {
        for key in &act.pool {
            let got =
                candidates_tuned(&act.state, &c.terrain, &statics, idx(&act.state, key), &mut sc, tuning);
            menus += 1;
            cands += got.len();
            let mut charges: BTreeSet<&str> = BTreeSet::new();
            for cand in &got {
                for t in [cand.shoot.as_deref(), cand.charge.as_deref()].into_iter().flatten() {
                    if joined_hero(&act.state, t) {
                        snipes += 1;
                    }
                }
                if cand.kind == CHARGE {
                    if let Some(t) = cand.charge.as_deref() {
                        charges.insert(t);
                    }
                }
            }
            if charges.len() > 1 {
                twin += 1;
            }
        }
    }
    (menus, cands, snipes, twin)
}

#[test]
fn red_the_default_menu_still_names_joined_heroes() {
    let c = corpus();
    let (menus, cands, snipes, twin) = sweep(&c, Tuning::default());
    println!("OFF: {menus} menus, {cands} candidates, {snipes} name a joined hero, {twin} twin charges");
    assert!(menus > 0, "the fixture must offer menus at all");
    assert!(
        snipes > 0,
        "the RED: with the knob OFF the menu names joined heroes — that is the corpus's own \
         behaviour and it must not change, or every recorded menu moves"
    );
    assert_eq!(twin, 0, "the OFF menu carries at most one CHARGE candidate per unit");
}

#[test]
fn green_target_units_never_names_a_joined_hero() {
    let c = corpus();
    let tuning = Tuning { target_units: true, ..Tuning::default() };
    let (menus, cands, snipes, _) = sweep(&c, tuning);
    println!("ON: {menus} menus, {cands} candidates, {snipes} name a joined hero");
    assert_eq!(
        snipes, 0,
        "GF v3.5.1 p.14: a joined Hero is part of its host, so no menu candidate may name it \
         while the host still has living models"
    );
}

#[test]
fn green_target_units_offers_the_charge_the_unit_can_reach() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    // The TRAINER's own tuning: `charge_gate: false` is what
    // `tools/core_selfplay.gd` and `selfplay.py --charge-gate off` play, and it
    // is the configuration in which `best_charge` names an out-of-band target —
    // 26 of the 36 declared charges in the batch-2 corpus, median 20.7" on a
    // 12" band. With the gate ON the two picks coincide on this fixture, which
    // is worth stating on its own: the second candidate is free wherever the
    // menu was already honest.
    let gated = Tuning { target_units: true, ..Tuning::default() };
    assert_eq!(sweep(&c, gated).3, 0, "with the charge gate ON the two picks agree on this corpus");
    let tuning = Tuning { target_units: true, charge_gate: false, ..Tuning::default() };
    let mut sc = Scratch::default();
    let (mut twin, mut checked) = (0usize, 0usize);
    for act in &c.acts {
        for key in &act.pool {
            let ai = idx(&act.state, key);
            let got = candidates_tuned(&act.state, &c.terrain, &statics, ai, &mut sc, tuning);
            let charges: Vec<&str> =
                got.iter().filter(|x| x.kind == CHARGE).filter_map(|x| x.charge.as_deref()).collect();
            if charges.len() < 2 {
                continue;
            }
            twin += 1;
            assert_eq!(charges.len(), 2, "at most two charge candidates: best-scoring and nearest");
            assert_ne!(charges[0], charges[1], "a menu never carries the same charge twice");
            // The SECOND one is the reachable one: the gate accepts it at its
            // own base-edge gap, which is what `nearest_chargeable` promises.
            let vi = idx(&act.state, charges[1]);
            let gap = nml_core::geom::edge_gap_in(
                &act.state.positions[ai],
                &act.state.radii[ai],
                &act.state.positions[vi],
                &act.state.radii[vi],
                nml_core::DEFAULT_BASE_RADIUS_M,
            )
            .max(0.0);
            assert!(
                !gate::charge_illegal(&act.state, &c.terrain, ai, vi, gap, None, None),
                "act unit {key}: the reachable candidate {} sits at {gap:.2}\" and the gate refuses it",
                charges[1]
            );
            checked += 1;
        }
    }
    println!("ON: {twin} menus carry a second, reachable CHARGE candidate ({checked} gate-checked)");
    assert!(
        twin > 0,
        "the fix's whole point: at least one unit in the corpus is offered the charge it can \
         reach beside the one it scores best"
    );
}

#[test]
fn the_knob_off_menu_is_the_recorded_menu() {
    // The "no corpus moves" claim, stated where the knob lives rather than only
    // in GATE G2: OFF must reproduce the recorded menu LENGTH for every pool
    // unit of every act. G2 (`tests/menu.rs`) still owns the field-by-field bar.
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let mut n = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        for key in &act.pool {
            let want = act.menus.get(key).unwrap_or_else(|| panic!("act {ai}: no menu for {key}"));
            let got = candidates_tuned(
                &act.state,
                &c.terrain,
                &statics,
                idx(&act.state, key),
                &mut sc,
                Tuning::default(),
            );
            assert_eq!(got.len(), want.len(), "act {ai} unit {key}: the OFF menu moved");
            n += 1;
        }
    }
    println!("OFF: {n} recorded menus reproduced");
}

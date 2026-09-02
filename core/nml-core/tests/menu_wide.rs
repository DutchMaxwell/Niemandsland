//! W1 (AUDIT_rulebook_flanks_2026-09-02, top-1; DEFECT_LEDGER row 23) — GATE for
//! `Tuning::wide_shoot`, the ADVANCE+shoot leg of the TABLE's own teacher menu.
//!
//! THE DEFECT. `menu::candidates` has exactly one shoot site and it hangs on
//! HOLD, so the search can only fire by STANDING STILL. The engine has never
//! had that limit: `sim::resolve` fires a volley for `HOLD` **and** `ADVANCE`
//! (`sim.rs:3102`). The GDScript teacher grew the missing leg on 16.08. and
//! says why in its own comment (`ai_planner.gd:1145-1153`): "a shoot target
//! only ever hung on HOLD, so the learned policy could fire only by standing
//! still. It stood still in 3.5% of activations and rushed in 85%, and
//! clone-vs-clone games ended with a median 62 survivors against tree-vs-tree's
//! 54 — it moved and stopped fighting." That leg was never ported.
//!
//! THE RED is the first test: with the knob OFF no menu in the recorded corpus
//! carries a moving shot, and it must stay that way, because that is what every
//! recorded corpus replays. The GREEN is a state built to have the shot only
//! AFTER the move: out of every barrel's reach from where the unit stands, in
//! reach once it has closed its 6" advance. OFF offers it nothing to fire at;
//! "table" offers ADVANCE+shoot, and the search takes it.

use nml_core::geom;
use nml_core::menu::{candidates_tuned, Tuning};
use nml_core::plan::plan_with_rollout;
use nml_core::sim::{Scratch, ADVANCE};
use nml_core::{build_act_statics, load_acts, ActCorpus, State};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// `BattleSim.IN2M` — the sim's one inch.
const IN2M: f64 = nml_core::IN2M;

fn corpus() -> ActCorpus {
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

/// The longest ranged barrel this unit's PROFILES carry — the same `range`
/// field `sim::profiles_of` gates a volley on.
fn barrel_in(us: &nml_core::unit::UnitStatic) -> f64 {
    us.shoot.iter().map(|p| p.range as f64).fold(0.0, f64::max)
}

fn idx(state: &State, key: &str) -> usize {
    *state.roster.index.get(key).unwrap_or_else(|| panic!("unknown unit key {key}"))
}

/// Move every model of unit `e` by one rigid translation, so its formation, its
/// radii and its wounds stay exactly what the recording captured.
fn shift(state: &mut State, e: usize, d: [f64; 3]) {
    for p in state.positions[e].iter_mut() {
        for k in 0..3 {
            p[k] += d[k];
        }
    }
}

/// Put unit `e` at `want_in` inches from unit `i`, measured the way the menu
/// measures (`geom::dist_in`, nearest model to nearest model). Straight out
/// along +X and then corrected: the distance is monotone in the offset once the
/// two footprints are apart, so a couple of Newton steps land on it exactly.
fn place_at(state: &mut State, i: usize, e: usize, want_in: f64) {
    let ci = geom::centre(&state.positions[i]);
    let ce = geom::centre(&state.positions[e]);
    let mut t = want_in;
    for _ in 0..8 {
        let ce_now = geom::centre(&state.positions[e]);
        let target = [
            (ci[0] as f64) + t * IN2M - ce_now[0] as f64,
            (ci[1] as f64) - ce_now[1] as f64,
            (ci[2] as f64) - ce_now[2] as f64,
        ];
        shift(state, e, target);
        let got = geom::dist_in(&state.positions[i], &state.positions[e]);
        if (got - want_in).abs() < 1e-6 {
            return;
        }
        t += want_in - got;
    }
    let _ = ce;
    let got = geom::dist_in(&state.positions[i], &state.positions[e]);
    assert!((got - want_in).abs() < 0.05, "could not place at {want_in}\"; got {got:.3}\"");
}

/// The board this rung is about: ONE shooter of the acting player, ONE living
/// enemy, standing 3" past the shooter's longest barrel. Returns (state,
/// shooter index, victim index, the shooter's advance band).
fn out_of_reach_board(c: &ActCorpus) -> (State, usize, usize, f64) {
    let statics = build_act_statics(c, REPO);
    for act in &c.acts {
        for key in &act.pool {
            let i = idx(&act.state, key);
            let us = &statics[act.state.roster.profile[i]];
            let band = act.state.bands[i].advance;
            let reach = barrel_in(us);
            // The gap has to be one the ADVANCE can close and the standing unit
            // cannot: reach < gap <= reach + band, with room either side.
            if us.shoot.is_empty() || reach <= band + 2.0 {
                continue;
            }
            let mut st = act.state.clone();
            let me = st.player[i];
            let mut victim = None;
            for e in 0..st.units() {
                if st.player[e] == me {
                    // one pool unit, so the pick is about THIS unit's menu
                    st.activated[e] = e != i;
                    continue;
                }
                if st.alive[e] <= 0 {
                    continue;
                }
                // The victim has to be one the SHOOTER can see: `sees` reads
                // the recorded per-unit row, which no translation rewrites, and
                // the moving-shot leg asks it exactly as the HOLD leg does.
                if victim.is_none() && st.sees(i, act.state.key(e)) {
                    victim = Some(e);
                    // A single surviving model: the shot is plainly worth
                    // taking and the strike back is not what decides it.
                    st.alive[e] = 1;
                    place_at(&mut st, i, e, reach + 3.0);
                    continue;
                }
                // Everybody else off to the far edge, out of every menu.
                shift(&mut st, e, [500.0 * IN2M, 0.0, 0.0]);
            }
            if let Some(e) = victim {
                // The shot has to be worth something once the move has been
                // made, or the board proves nothing. Asked with the crate's own
                // EV, not with the function under test.
                let mut sc = Scratch::default();
                let d = (geom::dist_in(&st.positions[i], &st.positions[e]) - band).max(0.0);
                let us = &statics[st.roster.profile[i]];
                nml_core::sim::profiles_of(us, st.alive[i], d, &mut sc);
                let att = nml_core::sim::ctx_of(us, &st, i);
                let def = nml_core::sim::ctx_of(&statics[st.roster.profile[e]], &st, e);
                let ev = nml_core::combat::shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d);
                if ev > 0.0 {
                    return (st, i, e, band);
                }
            }
        }
    }
    panic!("no act in the fixture carries a shooter with a barrel longer than its advance band");
}

/// RED — with the knob OFF, no menu in the recorded corpus offers a MOVING
/// shot. Every shoot target hangs on HOLD, which is the defect and, until the
/// knob is turned on, also the contract: the recorded corpora replay on it.
#[test]
fn red_the_default_menu_never_offers_a_moving_shot() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let (mut menus, mut holds, mut moving) = (0usize, 0usize, 0usize);
    for act in &c.acts {
        for key in &act.pool {
            let got = candidates_tuned(
                &act.state,
                &c.terrain,
                &statics,
                idx(&act.state, key),
                &mut sc,
                Tuning::default(),
            );
            menus += 1;
            for cd in &got {
                if cd.shoot.is_some() {
                    if cd.kind == ADVANCE {
                        moving += 1;
                    } else {
                        holds += 1;
                    }
                }
            }
            // The "no corpus moves" half, stated where the knob lives.
            let want = act.menus.get(key).unwrap_or_else(|| panic!("no recorded menu for {key}"));
            assert_eq!(got.len(), want.len(), "unit {key}: the OFF menu moved");
        }
    }
    println!("OFF: {menus} menus, {holds} shots on HOLD, {moving} shots on the move");
    assert!(holds > 0, "the corpus has to offer shots at all for this to say anything");
    assert_eq!(moving, 0, "the RED: today's menu can only fire by standing still");
}

/// GREEN, the menu half — a shot that exists only AFTER the advance. OFF the
/// unit is offered nothing to fire at; under `wide_shoot` it is offered exactly
/// one ADVANCE at the victim's centre, carrying the shot.
#[test]
fn green_menu_wide_offers_the_shot_the_advance_opens() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let (st, i, e, band) = out_of_reach_board(&c);
    let gap = geom::dist_in(&st.positions[i], &st.positions[e]);
    let reach = barrel_in(&statics[st.roster.profile[i]]);
    println!(
        "board: {} at {gap:.2}\" from {}, barrel {reach:.0}\", advance band {band:.0}\"",
        st.key(i),
        st.key(e)
    );
    assert!(gap > reach, "the premise: standing still, the barrel does not reach");
    assert!(gap - band <= reach, "the premise: after the advance it does");

    let mut sc = Scratch::default();
    let off = candidates_tuned(&st, &c.terrain, &statics, i, &mut sc, Tuning::default());
    assert!(
        off.iter().all(|cd| cd.shoot.is_none()),
        "OFF: standing still there is nothing in reach, so the menu carries no shot at all"
    );

    let on = candidates_tuned(
        &st,
        &c.terrain,
        &statics,
        i,
        &mut sc,
        Tuning { wide_shoot: true, ..Tuning::default() },
    );
    let shots: Vec<_> = on.iter().filter(|cd| cd.shoot.is_some()).collect();
    println!("OFF: {} candidates, ON: {} candidates, {} of them shoot", off.len(), on.len(), shots.len());
    assert_eq!(shots.len(), 1, "one living enemy in reach after the move = one moving shot");
    assert_eq!(shots[0].kind, ADVANCE, "the leg is ADVANCE, the only move that keeps the shot");
    assert_eq!(shots[0].shoot.as_deref(), Some(st.key(e)));
    let want = geom::to_f64(geom::centre(&st.positions[e]));
    assert_eq!(shots[0].dest, Some(want), "the destination is the TARGET's centre (ai_planner.gd:1156)");
    assert_eq!(on.len(), off.len() + 1, "the ON menu only GROWS, and only at the tail");
    for (k, cd) in off.iter().enumerate() {
        assert_eq!(cd.kind, on[k].kind, "candidate {k} kept its index");
        assert_eq!(cd.dest, on[k].dest, "candidate {k} kept its index");
    }
}

/// GREEN, the search half — the point of the rung. Given the same board, the
/// OFF search has nothing to fire and stands still or walks away; the ON search
/// picks the advance that opens the shot.
#[test]
fn green_the_search_takes_the_moving_shot() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let (st, i, e, _) = out_of_reach_board(&c);
    let act = &c.acts[0];
    let mut knobs = c.knobs;

    knobs.menu_wide = false;
    let off = plan_with_rollout(&st, &c.terrain, &statics, &knobs, &act.statics, st.player[i])
        .unwrap_or_else(|u| panic!("OFF search declined: {u:?}"));
    knobs.menu_wide = true;
    let on = plan_with_rollout(&st, &c.terrain, &statics, &knobs, &act.statics, st.player[i])
        .unwrap_or_else(|u| panic!("ON search declined: {u:?}"));
    for (n, u, k, sc) in on.scored.iter().take(12) {
        println!("  ON scored idx {n} {u} kind {k} -> {sc:.6}");
    }
    println!(
        "OFF picked kind {} shoot {:?} (after {:.4}); ON picked kind {} shoot {:?} (after {:.4})",
        off.action.kind, off.action.shoot, off.expectation_after,
        on.action.kind, on.action.shoot, on.expectation_after
    );
    assert_eq!(off.unit_key, st.key(i));
    assert!(off.action.shoot.is_none(), "OFF: there is no shot in this menu to pick");
    assert_eq!(on.unit_key, st.key(i));
    assert_eq!(on.action.kind, ADVANCE, "ON: the search moves");
    assert_eq!(
        on.action.shoot.as_deref(),
        Some(st.key(e)),
        "ON: and it fires while it moves — the whole rung"
    );
    assert!(
        on.expectation_after > off.expectation_after,
        "the moving shot has to be worth more than standing still, or the pick was luck"
    );
}

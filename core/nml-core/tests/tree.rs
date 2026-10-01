//! Tree step 3 — the activation walk. `tree::advance` must walk the SAME
//! alternation the one-ply rollout walks (rollout.rs `rollout_traced`): the
//! Delayed Action pass, the dry-side hand-off, and at "both dry" the booked
//! round end, then either the game end or the next round's start beats.
//!
//! The proof re-drives every rollout by hand: `policy_step` picks for both
//! sides exactly as the rollout does, `advance` walks, and every round-end
//! snapshot must equal `rollout_traced`'s boundary byte for byte (the `State`
//! `Debug` print carries every field, floats at round-trip precision), with
//! the same `Stop`. Tail caps are zeroed: the tree never applies them.

use nml_core::menu::Candidate;
use nml_core::plan::{seams_of, tuning_of};
use nml_core::playout::{other_player, Policy};
use nml_core::rollout::{Rollout, Stop};
use nml_core::sim::{reach_index_for_state, Scratch};
use nml_core::tree::{advance, Step};
use nml_core::{act_statics, load_acts, State};

const ACTS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const WIDE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// The rollout, re-driven through `advance`: the horizon is the driver's cut,
/// not the walk's, exactly as `rounds_left` is checked before the game end.
fn walk(roll: &Rollout, st: &State, first: &Candidate, me: i64, horizon: usize,
        sc: &mut Scratch) -> (Vec<State>, Stop) {
    let mut cur = roll.policy.resolve(st, first).unwrap();
    roll.coordinate_hand_off(&mut cur, first, me, sc).unwrap();
    let (mut ends, mut turn) = (Vec::new(), other_player(st, me));
    loop {
        let step = advance(roll, &mut cur, turn, Some(&mut ends));
        if ends.len() >= horizon {
            ends.truncate(horizon);
            return (ends, Stop::Horizon);
        }
        let Step::Mover(t) = step else { return (ends, Stop::GameEnd) };
        let a = roll.policy.policy_step(&cur, t, t == me, sc).unwrap()
            .unwrap_or_else(|| panic!("advance named player {t}, the policy finds them dry"));
        cur = roll.policy.resolve(&cur, &a).unwrap();
        roll.coordinate_hand_off(&mut cur, &a, me, sc).unwrap();
        turn = other_player(&cur, t);
    }
}

/// What one sweep saw: rollouts, round crossings, game ends, rollouts with a
/// Delayed Action pass stamped at any round end, and the first mismatch.
struct Seen { n: usize, crossed: usize, game_end: usize, passed: usize, bad: Option<String> }

/// Every policy candidate of every pool unit of every act, as an opener.
/// `carriers` doctors every profile into a Delayed Action carrier, so the
/// pass (epoch >= 7) fires on a corpus that recorded none.
fn sweep(path: &str, carriers: bool) -> Seen {
    let c = load_acts(path).unwrap_or_else(|e| panic!("{e}"));
    let per_act = act_statics(&c, REPO);
    let mut knobs = c.knobs;
    (knobs.tail_cap_p1, knobs.tail_cap_p2) = (0, 0);
    let seams = seams_of(&knobs);
    let mut sc = Scratch::default();
    let mut seen = Seen { n: 0, crossed: 0, game_end: 0, passed: 0, bad: None };
    for (ai, act) in c.acts.iter().enumerate() {
        let mut statics = (*per_act[ai]).clone();
        statics.iter_mut().for_each(|u| u.delayed_action_active |= carriers);
        let reach = if seams.path { reach_index_for_state(&act.state, &c.terrain) } else { None };
        let mut p = Policy::new(&statics, &c.terrain, seams);
        (p.tuning, p.reach) = (tuning_of(&knobs), reach.as_ref());
        let roll = Rollout::new(p, knobs);
        let horizon = roll.horizon() as usize;
        for key in &act.pool {
            let i = act.state.roster.index[key.as_str()];
            for cand in p.policy_candidates(&act.state, i, &mut sc) {
                let (want, ws) = roll.rollout_traced(&act.state, &cand, act.player, -1, &mut sc).unwrap();
                let (got, gs) = walk(&roll, &act.state, &cand, act.player, horizon, &mut sc);
                seen.n += 1;
                seen.crossed += usize::from(want.len() > 1);
                seen.game_end += usize::from(ws == Stop::GameEnd);
                seen.passed += usize::from(want.iter().any(|e| e.delayed_action_round.contains(&e.round)));
                let same = ws == gs && want.len() == got.len()
                    && want.iter().zip(&got).all(|(a, b)| format!("{a:?}") == format!("{b:?}"));
                if !same && seen.bad.is_none() {
                    seen.bad = Some(format!("act {ai} {key} {}: {ws:?}/{} vs walk {gs:?}/{}",
                                            cand.kind, want.len(), got.len()));
                }
            }
        }
    }
    seen
}

#[test]
fn advance_replays_every_rollout_boundary_on_both_fixtures() {
    for (path, carriers) in [(ACTS, false), (WIDE, false), (WIDE, true)] {
        let s = sweep(path, carriers);
        println!("tree walk {} carriers={carriers}: {} rollouts, {} crossed a round, {} game ends, \
                  {} with a Delayed Action pass", path.rsplit('/').next().unwrap(),
                 s.n, s.crossed, s.game_end, s.passed);
        assert!(s.n >= 80 && s.crossed > 0 && s.game_end > 0,
                "the sweep must cross a round and reach the game end: {}/{}/{}", s.n, s.crossed, s.game_end);
        assert!(!carriers || s.passed > 0, "the doctored carriers never passed: the pass is untested");
        assert_eq!(s.bad, None, "the walk left the rollout's alternation");
    }
}

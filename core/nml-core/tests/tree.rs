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
use nml_core::tree::{advance, leaf_value, menu, playout, referee, Node, Step};
use nml_core::{act_statics, full_playout_bent, load_acts, ActCorpus, ArbBend, GodotRng, State, TreeLeaf,
               UnitStatic};

const ACTS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const WIDE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// Act `ai`'s search config (the corpus knobs, tail caps zeroed: the tree
/// never applies them) over `statics`, handed to `f`.
fn with_roll<R>(c: &ActCorpus, ai: usize, statics: &[UnitStatic], f: impl FnOnce(&Rollout) -> R) -> R {
    let mut knobs = c.knobs;
    (knobs.tail_cap_p1, knobs.tail_cap_p2) = (0, 0);
    let seams = seams_of(&knobs);
    let reach = if seams.path { reach_index_for_state(&c.acts[ai].state, &c.terrain) } else { None };
    let mut p = Policy::new(statics, &c.terrain, seams);
    (p.tuning, p.reach) = (tuning_of(&knobs), reach.as_ref());
    f(&Rollout::new(p, knobs))
}

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
    let mut sc = Scratch::default();
    let mut seen = Seen { n: 0, crossed: 0, game_end: 0, passed: 0, bad: None };
    for (ai, act) in c.acts.iter().enumerate() {
        let mut statics = (*per_act[ai]).clone();
        statics.iter_mut().for_each(|u| u.delayed_action_active |= carriers);
        with_roll(&c, ai, &statics, |roll| for key in &act.pool {
            let i = act.state.roster.index[key.as_str()];
            let horizon = roll.horizon() as usize;
            for cand in roll.policy.policy_candidates(&act.state, i, &mut sc) {
                let (want, ws) = roll.rollout_traced(&act.state, &cand, act.player, -1, &mut sc).unwrap();
                let (got, gs) = walk(roll, &act.state, &cand, act.player, horizon, &mut sc);
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
        });
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

fn load(path: &str) -> ActCorpus {
    load_acts(path).unwrap_or_else(|e| panic!("{e}"))
}

/// The referee's verdict string as a value for `player`.
fn verdict(winner: &str, player: i64) -> f64 {
    match (winner, player) {
        ("draw", _) => 0.5,
        ("p1", 1) | ("p2", 2) => 1.0,
        _ => 0.0,
    }
}

/// Step 4 — a frontier that is not a game end takes the one-ply's own leaf.
/// On every one-boundary pool rollout of acts_25 (the final-round acts) the
/// Blend leaf on that boundary IS the recorded `rs` (G3's bar), an armed hook
/// value enters exactly as `blend_score_leaf` takes it, and the same state as
/// a reached game end is the referee's in both modes.
#[test]
fn the_blend_leaf_is_the_one_ply_value_and_a_game_end_the_referee() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let (mut n, mut sc, mut rng) = (0usize, Scratch::default(), GodotRng::new(0));
    for (ai, act) in c.acts.iter().enumerate() {
        let (p, seat) = (act.player, act.statics.opener_seat);
        with_roll(&c, ai, &per_act[ai], |roll| for rv in &act.rs {
            let rows = menu(roll, &act.state, p, &mut sc);
            let (ends, _) = roll.rollout_traced(&act.state, &rows[rv.idx as usize], p, -1, &mut sc).unwrap();
            if ends.len() != 1 {
                continue;
            }
            let open = Node::new(ends[0].clone(), Step::Mover(p), p);
            let mut leaf = |node: &Node, mode, vals: &[f64], w| {
                leaf_value(roll, node, mode, p, seat, vals, w, &mut rng, &mut sc).unwrap()
            };
            let hand = leaf(&open, TreeLeaf::Blend, &[], 0.0);
            assert!((hand - rv.rs).abs() <= 1e-9, "act {ai} idx {}: {hand} vs recorded {}", rv.idx, rv.rs);
            let armed = leaf(&open, TreeLeaf::Blend, &[0.25], 0.5);
            let want = roll.blend_score_leaf(&ends, p, seat, &[0.25], 0.5);
            assert!((armed - want).abs() <= 1e-12 && armed != hand, "act {ai}: armed leaf {armed} vs {want}");
            let end = Node::new(ends[0].clone(), Step::Terminal, p);
            let r = referee(&ends[0], p);
            assert!([0.0, 0.5, 1.0].contains(&r), "referee {r}");
            assert_eq!((leaf(&end, TreeLeaf::Blend, &[], 0.0), leaf(&end, TreeLeaf::Terminal, &[], 0.0)), (r, r));
            n += 1;
        });
    }
    println!("blend leaf: {n} one-boundary pool rollouts equal their recorded rs");
    assert!(n > 0, "no one-boundary rollout: the check is vacuous");
}

/// Step 4 — one activation from the end (every unit but one activated, that
/// one SHAKEN so its only legal row is the recovery hold), the Terminal leaf
/// is `full_playout`'s verdict for the same stream seed, with its dice off:
/// both run the EV transition the tree uses.
#[test]
fn the_terminal_leaf_one_activation_from_the_end_is_the_playout_verdict() {
    let mut seen = [0usize; 3];
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        let mut sc = Scratch::default();
        for (ai, act) in c.acts.iter().enumerate().filter(|(_, a)| a.state.round >= a.state.rounds_total) {
            let p = act.player;
            with_roll(&c, ai, &per_act[ai], |roll| for key in &act.pool {
                let u = act.state.roster.index[key.as_str()];
                let mut st = act.state.clone();
                st.activated.iter_mut().enumerate().for_each(|(i, a)| *a |= i != u);
                st.shaken[u] = true;
                assert_eq!(advance(roll, &mut st.clone(), p, None), Step::Mover(p));
                let node = Node::new(st.clone(), Step::Mover(p), p);
                for seed in 0..2 {
                    let got = leaf_value(roll, &node, TreeLeaf::Terminal, p, false, &[], 0.0,
                                         &mut GodotRng::new(seed), &mut sc).unwrap();
                    let bend = ArbBend { stochastic_wounds: false, ..ArbBend::default() };
                    let r = full_playout_bent(roll, &st, &Candidate::hold(key), p, &mut GodotRng::new(seed),
                                              bend, &mut sc).unwrap();
                    assert_eq!(got, verdict(r.winner, p), "act {ai} {key} seed {seed}: {r:?}");
                    seen[(got * 2.0) as usize] += 1;
                }
            });
        }
    }
    println!("terminal leaf vs full_playout: loss/draw/win = {seen:?}");
    assert!(seen.iter().sum::<usize>() > 0, "no final-round act: the check is vacuous");
}

/// Step 4 — a uniform playout from every act's own state reaches the game end
/// with a referee value and never spends more than the arbitration tail's
/// backstop, `units * 2 + 4` activations, in one round.
#[test]
fn a_terminal_playout_stays_inside_the_arbitration_guard() {
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        let (mut n, mut worst, mut sc) = (0usize, 0usize, Scratch::default());
        for (ai, act) in c.acts.iter().enumerate() {
            let cap = act.state.units() * 2 + 4;
            let (v, most) = with_roll(&c, ai, &per_act[ai], |roll| {
                playout(roll, &act.state, act.player, act.player, &mut GodotRng::new(ai as i64), &mut sc).unwrap()
            });
            assert!([0.0, 0.5, 1.0].contains(&v) && most <= cap, "act {ai}: value {v}, {most} > {cap} steps");
            (n, worst) = (n + 1, worst.max(most));
        }
        println!("{}: {n} uniform playouts to the end, at most {worst} activations in one round",
                 path.rsplit('/').next().unwrap());
    }
}

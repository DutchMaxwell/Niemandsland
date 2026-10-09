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

use std::collections::BTreeMap;

use nml_core::menu::Candidate;
use nml_core::plan::{seams_of, tuning_of};
use nml_core::playout::{other_player, Policy};
use nml_core::rollout::{Rollout, Stop};
use nml_core::sim::{reach_index_for_state, Scratch, Unsupported};
use nml_core::score::score_with;
use nml_core::sim::reply_threat;
use nml_core::tree::{
    advance, expand, leaf_value, menu, own_children, playout, ranked, referee, root_children, run, select, select_own,
    transition, Child, Node, Step, TreeCfg, TreeTrace,
};
use nml_core::{act_statics, full_playout_bent, load_acts, plan_with_rollout, read_act_header, read_acts, Search, SearchMode, ActCorpus, ArbBend, GodotRng, State, TreeDice,
               TreeLeaf, UnitStatic};

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
                leaf_value(roll, node, mode, p, seat, vals, w, &mut rng, None, &mut sc).unwrap()
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

/// aifix E1 — GF v3.5.1 p.7: the side that finished activating first opens the
/// next round. Every unit already activated, the first side asked is dry first,
/// so it opens again whatever the head counts (the old rule: fewer alive units,
/// a tie always to player 1).
#[test]
fn the_side_that_ran_dry_first_opens_the_next_round() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let (mut checked, mut p2_opens) = (0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate().filter(|(_, a)| a.state.round < a.state.rounds_total) {
        let mut knobs = c.knobs;
        (knobs.tail_cap_p1, knobs.tail_cap_p2, knobs.opener_by_finish) = (0, 0, true);
        let seams = seams_of(&knobs);
        let mut pol = Policy::new(&per_act[ai], &c.terrain, seams);
        pol.tuning = tuning_of(&knobs);
        let roll = &Rollout::new(pol, knobs);
        for first in [1, 2] {
            let mut st = act.state.clone();
            st.activated.iter_mut().for_each(|a| *a = true);
            assert_eq!(advance(roll, &mut st, first, None), Step::Mover(first), "act {ai} first-dry {first}");
            checked += 1;
            p2_opens += (first == 2) as usize;
        }
    }
    assert!(checked >= 20 && p2_opens >= 10, "{checked} {p2_opens}");
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
                                         &mut GodotRng::new(seed), None, &mut sc).unwrap();
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
                playout(roll, &act.state, act.player, act.player, &mut GodotRng::new(ai as i64), None, &mut sc).unwrap()
            });
            assert!([0.0, 0.5, 1.0].contains(&v) && most <= cap, "act {ai}: value {v}, {most} > {cap} steps");
            (n, worst) = (n + 1, worst.max(most));
        }
        println!("{}: {n} uniform playouts to the end, at most {worst} activations in one round",
                 path.rsplit('/').next().unwrap());
    }
}

/// Every field of a state, floats at round-trip precision.
fn canon(states: &[State]) -> Vec<String> {
    states.iter().map(|s| format!("{s:?}")).collect()
}

/// Step 5 — chance edges, over every menu row of every act of both fixtures:
/// `Ev` is `Policy::resolve` bit for bit; `Tray` draws `samples` states, the
/// same stream base twice is byte-identical, another base moves some edge,
/// the samples of one edge differ among themselves somewhere, and an
/// activation the tray path flags unported declines by name (here
/// `surge_gates` / `dangerous_rigid_end_only`; the fixtures' Deadly(3) weapons
/// land per model from `EPOCH_14_DEADLY_LANDING` and no longer decline, stage-0
/// P9); `Tray` with no base declines.
#[test]
fn chance_edges_are_reproducible_and_decline_unported() {
    let (mut n, mut moved, mut spread, mut declined) = (0usize, 0usize, 0usize, BTreeMap::new());
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        let mut sc = Scratch::default();
        for (ai, act) in c.acts.iter().enumerate() {
            let base = 740_000_000 + 1_000 * ai as i64;
            with_roll(&c, ai, &per_act[ai], |roll| for cand in menu(roll, &act.state, act.player, &mut sc) {
                let edge = |dice, b| transition(roll, &act.state, &cand, dice, 4, b);
                let want = roll.policy.resolve(&act.state, &cand).unwrap();
                assert!(canon(&edge(TreeDice::Ev, None).unwrap()) == canon(&[want]), "act {ai}: Ev is not resolve");
                match edge(TreeDice::Tray, Some(base)) {
                    Err(Unsupported::TreeUnported(what)) => *declined.entry(what).or_insert(0usize) += 1,
                    Err(e) => panic!("act {ai} {}: {e:?}", cand.kind),
                    Ok(a) => {
                        let (a, b) = (canon(&a), canon(&edge(TreeDice::Tray, Some(base)).unwrap()));
                        // Another base may roll into an unported branch itself (a branch
                        // flags only when its dice reach it): that counts as moved too.
                        let other = edge(TreeDice::Tray, Some(base + 7)).map(|v| canon(&v)).ok();
                        assert!(a.len() == 4 && a == b, "act {ai}: the same base drew different samples");
                        moved += usize::from(other.as_ref() != Some(&a));
                        spread += usize::from(a.iter().any(|s| s != &a[0]));
                        n += 1;
                    }
                }
            });
            let none = with_roll(&c, ai, &per_act[ai], |roll| {
                let rows = menu(roll, &act.state, act.player, &mut sc);
                transition(roll, &act.state, &rows[0], TreeDice::Tray, 4, None)
            });
            assert_eq!(none.map(|v| v.len()), Err(Unsupported::TreeDiceSeed), "act {ai}: Tray with no base");
        }
    }
    println!("chance edges: {n} tray edges reproduced, {moved} moved by another base, \
              {spread} spread within one edge; declined {declined:?}");
    assert!(n > 0 && moved > 0 && spread > 0, "the tray draws are inert");
    assert!(!declined.is_empty() && !declined.contains_key("deadly"), "decline by name, never Deadly: {declined:?}");
}

/// Step 14 — the true-tray Terminal playout: with a stream base every step
/// rolls the tray, so the same base twice is the identical value, another
/// base moves some value on the fixtures, and a still-unported branch declines
/// by name — Deadly no longer does (per-model landing from `EPOCH_14_DEADLY_LANDING`)
/// (`None`, the EV playout, is pinned by `a_terminal_playout_stays_inside_the_arbitration_guard`).
#[test]
fn tray_playouts_roll_the_leaf_stream_and_decline_unported() {
    let (mut n, mut moved, mut declined) = (0usize, 0usize, BTreeMap::new());
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        let mut sc = Scratch::default();
        for (ai, act) in c.acts.iter().enumerate() {
            let base = 740_000_000 + 1_000 * ai as i64;
            with_roll(&c, ai, &per_act[ai], |roll| {
                let mut play = |b: i64| {
                    playout(roll, &act.state, act.player, act.player, &mut GodotRng::new(ai as i64), Some(b), &mut sc)
                        .map(|r| r.0.to_bits())
                };
                match play(base) {
                    Err(Unsupported::TreeUnported(what)) => *declined.entry(what).or_insert(0usize) += 1,
                    Err(e) => panic!("act {ai}: {e:?}"),
                    Ok(v) => {
                        assert_eq!(play(base), Ok(v), "act {ai}: the same base rolled a different playout");
                        moved += usize::from(play(base + 7) != Ok(v));
                        n += 1;
                    }
                }
            });
        }
    }
    println!("tray playouts: {n} reproduced, {moved} moved by another base; declined {declined:?}");
    assert!(n > 0 && moved > 0, "the tray playouts are inert: {n}/{moved}");
    assert!(!declined.is_empty() && !declined.contains_key("deadly"), "decline by name, never Deadly: {declined:?}");
}

/// Step 6a — the ROOT's children are the one-ply's own prefilter rows in its
/// order, pool first: on every answered act of acts_25 `ranked` carries the
/// one-ply trace's scores bit for bit in its ranked order, and
/// `root_children` is `pool_idx`, then the rest of that order.
#[test]
fn root_children_follow_the_one_ply_order() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let (mut n, mut sc) = (0usize, Scratch::default());
    for (ai, act) in c.acts.iter().enumerate() {
        let Ok(pick) = plan_with_rollout(&act.state, &c.terrain, &per_act[ai], &c.knobs, &act.statics, act.player)
        else { continue };
        with_roll(&c, ai, &per_act[ai], |roll| {
            let (rows, order) = ranked(roll, &act.state, act.player, &mut sc).unwrap();
            let got: Vec<(i64, u64)> = order.iter().map(|&i| (i as i64, rows[i].score.to_bits())).collect();
            let want: Vec<(i64, u64)> = pick.scored.iter().map(|s| (s.0, s.3.to_bits())).collect();
            assert_eq!(got, want, "act {ai}: the ranked rows are not the one-ply's");
            let kids: Vec<usize> = root_children(&rows, &order, &pick.pool_idx).iter().map(|k| k.idx).collect();
            let mut want = pick.pool_idx.clone();
            want.extend(pick.scored.iter().map(|s| s.0 as usize).filter(|i| !pick.pool_idx.contains(i)));
            assert_eq!(kids, want, "act {ai}: root order");
        });
        n += 1;
    }
    println!("root children: {n} of {} acts in the one-ply's order", c.acts.len());
    assert!(n >= 20, "only {n} acts answered");
}

/// Step 6a — a deeper node generates its children on its first expansion,
/// ordered by the prefilter's 1-ply rule for ITS mover (checked by an
/// independent sort: score desc, build index asc), and widens by `k` in that
/// order, never touching an opened child again.
#[test]
fn deeper_children_follow_an_independent_rank_and_widen() {
    let (mut n, mut sc) = (0usize, Scratch::default());
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let p = act.player;
            with_roll(&c, ai, &per_act[ai], |roll| {
                let (rows, order) = ranked(roll, &act.state, p, &mut sc).unwrap();
                let mut root = Node::new(act.state.clone(), Step::Mover(p), p);
                root.children = root_children(&rows, &order, &[]);
                assert_eq!(expand(roll, &mut root, 2, TreeDice::Ev, 1, None, p, &mut sc).unwrap(), 2);
                assert!(root.next_child == 2 && root.children[2].nodes.is_empty(), "act {ai}: root widening");
                let kid = &mut root.children[0].nodes[0];
                if kid.terminal.is_some() {
                    return;
                }
                let (m, st) = (kid.mover, kid.state.clone());
                expand(roll, kid, 3, TreeDice::Ev, 1, None, p, &mut sc).unwrap();
                let statics = roll.policy.statics;
                let mut want: Vec<(usize, f64)> = menu(roll, &st, m, &mut sc).iter().enumerate().map(|(i, cand)| {
                    let next = roll.policy.resolve(&st, cand).unwrap();
                    (i, score_with(&next, statics, m, &reply_threat(statics, &next, m), None))
                }).collect();
                want.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap().then(a.0.cmp(&b.0)));
                let got: Vec<usize> = kid.children.iter().map(|k| k.idx).collect();
                assert_eq!(got, want.iter().map(|w| w.0).collect::<Vec<_>>(), "act {ai}: deeper order");
                let open = kid.next_child;
                expand(roll, kid, 3, TreeDice::Ev, 1, None, p, &mut sc).unwrap();
                let lens: Vec<usize> = kid.children.iter().map(|k| k.nodes.len()).collect();
                let bar = (open + 3).min(lens.len());
                assert!(open == 3.min(lens.len()) && kid.next_child == bar, "act {ai}: widening {open}/{}", kid.next_child);
                assert!(lens[..bar].iter().all(|&l| l == 1) && lens[bar..].iter().all(|&l| l == 0), "act {ai}: {lens:?}");
                n += 1;
            });
        }
    }
    println!("deeper children: {n} depth-1 nodes in the independent order");
    assert!(n >= 20, "only {n} deeper nodes checked");
}

/// A tree search over `st` for `p`: root children in the hand order
/// (`ranked`, no pool), the given leaf mode, budget and batch, EV edges.
fn search(roll: &Rollout, st: &State, p: i64, leaf: TreeLeaf, budget: usize, batch: usize,
          sc: &mut Scratch) -> (usize, TreeTrace, Vec<usize>) {
    search_widen(roll, st, p, leaf, budget, batch, 0.0, sc)
}

/// `search` at a widening rate (0.0 = open every child first).
#[allow(clippy::too_many_arguments)]
fn search_widen(roll: &Rollout, st: &State, p: i64, leaf: TreeLeaf, budget: usize, batch: usize, widen: f64,
                sc: &mut Scratch) -> (usize, TreeTrace, Vec<usize>) {
    let (rows, order) = ranked(roll, st, p, sc).unwrap();
    let mut root = Node::new(st.clone(), Step::Mover(p), p);
    root.children = root_children(&rows, &order, &[]);
    let cfg = TreeCfg { leaf, dice: TreeDice::Ev, samples: 1, batch, budget, wall_ms: 0, deadline: None, widen, puct: 0.0, player: p,
                        opener_seat: false, sig: None, hook: None, w: 0.0 };
    let (best, trace) = run(roll, &cfg, &mut root, &mut GodotRng::new(7), sc).unwrap();
    (best, trace, order)
}

/// Every final-round act's state cut down to ONE activation left in the
/// game — pool unit `u` — so every root child ends the game in one step.
fn last_activations(c: &ActCorpus) -> Vec<(usize, State)> {
    let mut out = Vec::new();
    for (ai, act) in c.acts.iter().enumerate().filter(|(_, a)| a.state.round >= a.state.rounds_total) {
        for key in &act.pool {
            let u = act.state.roster.index[key.as_str()];
            let mut st = act.state.clone();
            st.activated.iter_mut().enumerate().for_each(|(i, a)| *a |= i != u);
            out.push((ai, st));
        }
    }
    out
}

/// Step 6b — budget 1 opens exactly the hand's top row and picks it.
#[test]
fn budget_one_picks_the_hands_top_row() {
    let mut sc = Scratch::default();
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let (best, trace, order) = with_roll(&c, ai, &per_act[ai], |roll| {
                search(roll, &act.state, act.player, TreeLeaf::Blend, 1, 8, &mut sc)
            });
            assert!(best == 0 && trace.completed == 1 && trace.root.len() == 1 && trace.root[0].0 == order[0],
                    "act {ai}: {best} {trace:?}");
        }
    }
}

/// Step 6b — one activation from the end every root child is a game end; at
/// a budget past the root width the pick is the argmax of `full_playout`'s
/// verdict (dice off) over the root rows, first in order on ties, computed
/// here without the tree. Batch 1 and batch 8 below the width visit the
/// same root children.
#[test]
fn last_activation_picks_the_referee_argmax_at_any_batch() {
    let (mut n, mut varied, mut sc) = (0usize, 0usize, Scratch::default());
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, st) in last_activations(&c) {
            let p = c.acts[ai].player;
            with_roll(&c, ai, &per_act[ai], |roll| {
                let (rows, order) = ranked(roll, &st, p, &mut sc).unwrap();
                let bend = ArbBend { stochastic_wounds: false, ..ArbBend::default() };
                let want: Vec<f64> = order.iter().map(|&i| {
                    let r = full_playout_bent(roll, &st, &rows[i].cand, p, &mut GodotRng::new(0), bend, &mut sc);
                    verdict(r.unwrap().winner, p)
                }).collect();
                let top = want.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
                let first = want.iter().position(|&v| v == top).unwrap();
                varied += usize::from(first > 0);
                let (best, trace, _) = search(roll, &st, p, TreeLeaf::Terminal, want.len() + 3, 8, &mut sc);
                let means: Vec<f64> = trace.root.iter().map(|r| r.2).collect();
                assert_eq!((best, means), (first, want.clone()), "act {ai}: pick vs the referee argmax");
                let k = (want.len() - 1).min(6);
                let seen = |t: TreeTrace| t.root.iter().map(|r| r.0).collect::<Vec<_>>();
                let one = seen(search(roll, &st, p, TreeLeaf::Blend, k, 1, &mut sc).1);
                assert_eq!(one, seen(search(roll, &st, p, TreeLeaf::Blend, k, 8, &mut sc).1), "act {ai}: batch");
                n += 1;
            });
        }
    }
    println!("last activation: {n} synthetic states pick the referee argmax ({varied} past the hand's \
              top row), batch 1 = batch 8");
    assert!(n > 0 && varied > 0, "no synthetic state whose argmax leaves the top row: {n}/{varied}");
}

/// The trace counters on the depth-1 synthetic states: within the root width
/// every leaf is a game end or a frontier state, they sum to `completed`, and
/// the batches are the budget cut into `batch`-sized slices.
#[test]
fn the_trace_counts_batches_frontier_and_terminal() {
    let (mut n, mut ends, mut sc) = (0usize, 0usize, Scratch::default());
    let c = load(WIDE);
    let per_act = act_statics(&c, REPO);
    for (ai, st) in last_activations(&c) {
        let p = c.acts[ai].player;
        with_roll(&c, ai, &per_act[ai], |roll| {
            let (budget, batch) = (menu(roll, &st, p, &mut sc).len().min(7), 3);
            let t = search(roll, &st, p, TreeLeaf::Blend, budget, batch, &mut sc).1;
            assert_eq!((t.frontier + t.terminal, t.completed), (budget, budget), "act {ai}: {t:?}");
            assert_eq!(t.batches, budget.div_ceil(batch), "act {ai}: {t:?}");
            (n, ends) = (n + 1, ends + t.terminal);
        });
    }
    assert!(n > 0 && ends > 0, "no depth-1 state counted a game end: {n}/{ends}");
}

/// Step 6b — past the root width the search descends (deeper expansions),
/// and the same act twice gives the identical pick and trace in both modes.
#[test]
fn the_same_search_twice_is_identical() {
    let (mut deep, mut sc) = (0usize, Scratch::default());
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    for (ai, act) in c.acts.iter().enumerate() {
        with_roll(&c, ai, &per_act[ai], |roll| for leaf in [TreeLeaf::Blend, TreeLeaf::Terminal] {
            let width = menu(roll, &act.state, act.player, &mut sc).len();
            let a = search(roll, &act.state, act.player, leaf, width + 12, 4, &mut sc);
            let b = search(roll, &act.state, act.player, leaf, width + 12, 4, &mut sc);
            assert!(a.0 == b.0 && a.1 == b.1, "act {ai} {leaf:?}: {:?} vs {:?}", a.1, b.1);
            assert!(a.1.completed >= width + 12, "act {ai}: {} of {}", a.1.completed, width + 12);
            deep += usize::from(a.1.root.iter().any(|r| r.1 > 1));
        });
    }
    println!("repeatability: {deep} searches descended below the root");
    assert!(deep > 0, "no search descended: depth is untested");
}

/// Step 6b — UCT takes the MOVER's side: over the same three children at
/// equal visits the searcher's node picks the highest mean, the opponent's
/// node the lowest.
#[test]
fn select_takes_the_movers_side() {
    let c = load(ACTS);
    let st = &c.acts[0].state;
    let mut node = Node::new(st.clone(), Step::Mover(1), 1);
    node.n = 6;
    for (i, mean) in [0.5, 0.9, 0.1].into_iter().enumerate() {
        let mut leaf = Node::new(st.clone(), Step::Mover(2), 1);
        (leaf.n, leaf.w) = (2, 2.0 * mean);
        node.children.push(Child { idx: i, cand: Candidate::hold(st.key(0)), nodes: vec![leaf], prior: None, own: None });
    }
    node.next_child = 3;
    assert_eq!(select(&node, 1), 1, "the searcher's own node takes the argmax");
    node.mover = 2;
    assert_eq!(select(&node, 1), 2, "the opponent's node takes the argmin");
}

/// Step 7 — the knob wired into `Search::run`. Absent, no pick carries a tree
/// trace (the byte-identical proof is the EXISTING gates: G3/G4/G5, parity,
/// playout_rush_k, menu_advance_k). At `search_mode: tree`, budget 64, every
/// pick of acts_25 carries the trace, `rs` is its root statistics, and at
/// least one act picks differently; an arbitration act declines by name.
#[test]
fn the_tree_knob_parts_the_pick_and_stamps_it() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let mut knobs = c.knobs;
    (knobs.search_mode, knobs.tree_budget) = (SearchMode::Tree, 64);
    let (mut n, mut moved) = (0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let pick = |k| plan_with_rollout(&act.state, &c.terrain, &per_act[ai], k, &act.statics, act.player).unwrap();
        let (one, tree) = (pick(&c.knobs), pick(&knobs));
        assert!(one.tree.is_none(), "act {ai}: a default pick carries a tree trace");
        let t = tree.tree.as_ref().unwrap_or_else(|| panic!("act {ai}: the tree pick carries no trace"));
        assert_eq!(tree.rs, t.root.iter().map(|r| (r.0 as i64, r.2)).collect::<Vec<_>>(), "act {ai}: rs");
        assert!(t.completed >= 64 && !t.deadline_hit, "act {ai}: {} leaves", t.completed);
        moved += usize::from(tree.unit_key != one.unit_key || format!("{:?}", tree.action) != format!("{:?}", one.action));
        n += 1;
    }
    let mut arb = c.acts[0].statics.clone();
    arb.playout_search = true;
    let a = &c.acts[0];
    let err = plan_with_rollout(&a.state, &c.terrain, &per_act[0], &knobs, &arb, a.player).unwrap_err();
    assert_eq!(err, Unsupported::TreeOutOfScope("playout_search"));
    println!("tree knob: {n} acts stamped, {moved} picked differently at budget 64");
    assert!(n == c.acts.len() && moved >= 1, "{n} acts, {moved} moved");
}

/// Step 8 — the wall clock is a SAFETY fallback, never the budget. At 1 ms on
/// acts_wide_25 the search stops between batches with `deadline_hit`, fewer
/// leaves than the budget and a pick among the opened root rows; replaying
/// with `PlanBend.tree_budget = completed` (wall off) reproduces the pick and
/// the root statistics byte for byte; wall 0 spends the whole budget.
#[test]
fn the_deadline_stops_early_and_the_stamped_count_replays() {
    let c = load(WIDE);
    let per_act = act_statics(&c, REPO);
    let mut knobs = c.knobs;
    (knobs.search_mode, knobs.tree_budget, knobs.tree_wall_ms) = (SearchMode::Tree, 128, 1);
    let (mut hit, mut sc) = (0usize, Scratch::default());
    for (ai, act) in c.acts.iter().enumerate() {
        let seams = seams_of(&knobs);
        let reach = if seams.path { reach_index_for_state(&act.state, &c.terrain) } else { None };
        let mut p = Policy::new(&per_act[ai], &c.terrain, seams);
        (p.tuning, p.reach) = (tuning_of(&knobs), reach.as_ref());
        let roll = Rollout::new(p, knobs);
        let cut = Search::new(roll, &act.statics).run(&act.state, act.player, &mut sc, None).unwrap();
        let t = cut.tree.clone().unwrap();
        assert!(t.deadline_hit && t.completed > 0 && t.completed < 128, "act {ai}: {t:?}");
        assert!(cut.pool_idx.contains(&(cut.scored[cut.best_idx as usize].0 as usize)), "act {ai}: pick off the root");
        let mut replay = Search::new(roll, &act.statics);
        replay.bend.tree_budget = Some(t.completed as i64);
        let again = replay.run(&act.state, act.player, &mut sc, None).unwrap();
        let ta = again.tree.clone().unwrap();
        assert!(!ta.deadline_hit && (ta.completed, &ta.root) == (t.completed, &t.root), "act {ai}: {ta:?} vs {t:?}");
        assert_eq!(format!("{:?}", again.action), format!("{:?}", cut.action), "act {ai}: replayed pick");
        let off = Rollout::new(p, nml_core::Knobs { tree_wall_ms: 0, ..knobs });
        let full = Search::new(off, &act.statics).run(&act.state, act.player, &mut sc, None).unwrap();
        let tf = full.tree.unwrap();
        assert!(!tf.deadline_hit && tf.completed >= 128, "act {ai}: wall 0 {tf:?}");
        hit += 1;
    }
    println!("deadline: {hit} acts cut at 1 ms and replayed from their stamped count");
    assert_eq!(hit, c.acts.len());
}

/// Step 8 — a corpus row carries the stamped count back: `trace.tree.completed`
/// reads into `Act::tree_completed`; a row without the key reads `None`.
#[test]
fn a_recorded_tree_count_reads_back() {
    let text = std::fs::read_to_string(ACTS).unwrap();
    let lines: Vec<&str> = text.lines().take(2).collect();
    let mut row: serde_json::Value = serde_json::from_str(lines[1]).unwrap();
    row["trace"]["tree"] = serde_json::json!({"completed": 17, "deadline_hit": true, "root": []});
    let read = |t: String| read_acts(std::io::Cursor::new(t.into_bytes()), "test").unwrap().acts[0].tree_completed;
    let stamped = read(format!("{}\n{}\n", lines[0], row));
    assert_eq!((stamped, read(format!("{}\n{}\n", lines[0], lines[1]))), (Some(17), None));
}

/// Step 6c — the widening-rate knob. At its default (0.0) every child of a node
/// opens before the search descends (the 6b tests run there): past the root
/// width all root children are open. At 0.5 a node keeps at most
/// ceil(n ^ 0.5) children open, so the root opens far fewer and the search
/// goes deeper at the same budget. A negative rate is refused in the header.
#[test]
fn the_widening_rate_caps_open_children() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let (mut narrowed, mut sc) = (0usize, Scratch::default());
    for (ai, act) in c.acts.iter().enumerate() {
        with_roll(&c, ai, &per_act[ai], |roll| {
            let width = menu(roll, &act.state, act.player, &mut sc).len();
            let run_at = |w, sc: &mut Scratch| search_widen(roll, &act.state, act.player, TreeLeaf::Blend, width + 12, 4, w, sc).1;
            let (full, cut) = (run_at(0.0, &mut sc), run_at(0.5, &mut sc));
            assert_eq!(full.root.len(), width, "act {ai}: the default opens every root child");
            let cap = (cut.completed as f64).sqrt().ceil() as usize;
            assert!(cut.root.len() <= cap && cut.completed >= width + 12, "act {ai}: {} open, cap {cap}", cut.root.len());
            narrowed += usize::from(cut.root.len() < width);
        });
    }
    println!("widening 0.5: {narrowed} of {} roots kept fewer children open", c.acts.len());
    assert!(narrowed > 0, "the widening rate changed nothing");
    let head = r#"{"kind":"header","profiles":{},"knobs":{"tree_widen":-0.5}}"#;
    assert!(read_act_header(head).is_err_and(|e| e.contains("tree_widen")), "a negative rate must be refused");
}

/// aifix D5 — knob `no_end_threat`: a boundary at `round == rounds_total` is
/// priced with no reply volley, so its blend equals the score at NO_INCOMING;
/// with the knob off the same boundary is still discounted by the volley.
#[test]
fn the_game_end_boundary_carries_no_reply_threat() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let (mut differs, mut checked) = (0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let mut end = act.state.clone();
        end.round = end.rounds_total;
        let p = act.player;
        let price = |on: bool| {
            let mut knobs = c.knobs;
            knobs.no_end_threat = on;
            let mut pol = Policy::new(&per_act[ai], &c.terrain, seams_of(&knobs));
            pol.tuning = tuning_of(&knobs);
            let roll = Rollout::new(pol, knobs);
            let got = roll.blend_score(std::slice::from_ref(&end), p, false);
            (got, score_with(&end, &per_act[ai], p, nml_core::NO_INCOMING, roll.policy.fit))
        };
        let (on, want) = price(true);
        assert_eq!(on, want, "act {ai}");
        differs += (price(false).0 != want) as usize;
        checked += 1;
    }
    assert!(checked >= 20 && differs >= 1, "{checked} {differs}");
}

/// NachtmahrZero E1 — PUCT at the root. With every mean tied, a prior steers the selection to its heaviest child
/// (UCT, blind to priors, keeps the first); `puct` 0 or no priors is UCT to the bit; the softmax is a distribution.
#[test]
fn puct_follows_the_prior_where_uct_is_blind() {
    use nml_core::tree::{select_puct, softmax_prior};
    let c = load(ACTS);
    let st = &c.acts[0].state;
    let mut node = Node::new(st.clone(), Step::Mover(1), 1);
    node.n = 6;
    for (i, p) in [0.1, 0.7, 0.2].into_iter().enumerate() {
        let mut leaf = Node::new(st.clone(), Step::Mover(2), 1);
        (leaf.n, leaf.w) = (2, 1.0);
        node.children.push(Child { idx: i, cand: Candidate::hold(st.key(0)), nodes: vec![leaf], prior: Some(p), own: None });
    }
    node.next_child = 3;
    assert_eq!(select(&node, 1), 0, "UCT with tied means keeps the first child");
    assert_eq!(select_puct(&node, 1, 1.0), 1, "PUCT goes to the prior's favourite");
    assert_eq!(select_puct(&node, 1, 0.0), 0, "c = 0 removes the prior term");
    let pri = softmax_prior(&[0.0, 2.0, 1.0]);
    assert!((pri.iter().sum::<f64>() - 1.0).abs() < 1e-12 && pri[1] > pri[2] && pri[2] > pri[0]);
}

/// E1 through `Search::run`: `tree_puct` 0 with logits is byte-identical to no logits (the OFF proof); with `tree_puct`
/// on and logits that load one row, that row's root visits rise over the UCT run on most acts; no logits = UCT.
#[test]
fn tree_puct_off_is_identical_and_on_moves_the_visits_to_the_prior() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let mut off = c.knobs;
    (off.search_mode, off.tree_budget) = (SearchMode::Tree, 96);
    let mut on = off;
    on.tree_puct = 4.0;
    let (mut raised, mut n) = (0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let run = |k: &nml_core::acts::Knobs, lg: Option<&[f32]>| {
            let seams = seams_of(k);
            let reach = if seams.path { reach_index_for_state(&act.state, &c.terrain) } else { None };
            let mut p = Policy::new(&per_act[ai], &c.terrain, seams);
            (p.tuning, p.reach) = (tuning_of(k), reach.as_ref());
            let roll = Rollout::new(p, *k);
            let mut search = Search::new(roll, &act.statics);
            search.cand_logits = lg;
            search.run(&act.state, act.player, &mut Scratch::default(), None).unwrap()
        };
        let base = run(&off, None);
        let rows = base.cands.len();
        let fav = rows - 1; // the hand's LAST row: the prior must pull it up against the hand order
        let mut lg = vec![0.0f32; rows];
        lg[fav] = 8.0;
        let plain = run(&off, Some(&lg));
        assert_eq!(format!("{:?}", plain.tree.as_ref().unwrap().root), format!("{:?}", base.tree.as_ref().unwrap().root),
                   "act {ai}: tree_puct 0 with logits must equal no logits");
        assert_eq!(format!("{:?}", run(&on, None).tree.as_ref().unwrap().root), format!("{:?}", base.tree.as_ref().unwrap().root),
                   "act {ai}: tree_puct on without logits must equal UCT");
        let visits = |p: &nml_core::Pick| p.tree.as_ref().unwrap().root.iter().find(|r| r.0 == fav).map_or(0, |r| r.1);
        n += 1;
        raised += usize::from(visits(&run(&on, Some(&lg))) > visits(&base));
    }
    assert!(raised * 10 >= n * 8, "the prior raised the favoured row's visits on only {raised} of {n} acts");
}

// ------------- the one-ply's opponent-model knobs in the tree (loop re-run prerequisite) ---

/// `with_roll` over the given knobs instead of the corpus's (tail caps zeroed the same way).
fn with_knobs<R>(c: &ActCorpus, ai: usize, statics: &[UnitStatic], k: &nml_core::Knobs,
                 f: impl FnOnce(&Rollout) -> R) -> R {
    let mut knobs = *k;
    (knobs.tail_cap_p1, knobs.tail_cap_p2) = (0, 0);
    let seams = seams_of(&knobs);
    let reach = if seams.path { reach_index_for_state(&c.acts[ai].state, &c.terrain) } else { None };
    let mut p = Policy::new(statics, &c.terrain, seams);
    (p.tuning, p.reach) = (tuning_of(&knobs), reach.as_ref());
    f(&Rollout::new(p, knobs))
}

/// The one-ply's opponent-model knobs as the recorder's presets set them (selfplay.py `leaf_opener`,
/// `reply_net_cap3_restricted`), one family or both.
fn opponent_model(k: &nml_core::Knobs, leaf_opener: bool, reply_net: bool) -> nml_core::Knobs {
    let mut k = *k;
    k.leaf_opener_only = leaf_opener;
    if reply_net {
        k.reply_by_net = true;
        (k.reply_top_k, k.reply_horizon, k.reply_pool_cap, k.reply_menu_restricted) = (3, 1, 3, true);
    }
    k
}

/// The arms every check below runs: (name, `leaf_opener_only`, the `reply_by_net` family).
const ARMS: [(&str, bool, bool); 3] =
    [("leaf_opener", true, false), ("reply_net_cap3_restricted", false, true), ("both", true, true)];

/// Map step 1 — the tree prices NO rollout, so `leaf_opener_only` has nothing to cut there. On both fixtures every
/// root edge's leaf is the edge's own activation (the EV resolve, its Coordinate hand-off, `advance` to the next
/// decision: rule bookkeeping, no move chosen) priced by the Blend leaf of that ONE state (the referee at a game
/// end), knob OFF and ON alike. Negative control: the one-ply's scripted-tail value of the same edge differs from
/// the tree's leaf, so a tree whose leaves played that tail would fail the equality. Reported: the root edges where
/// the one-ply's `leaf_opener_only` leaf is the very state the tree prices, and the Coordinate hand-offs (the
/// scripted brain's one reach into the tree).
#[test]
fn opponent_model_tree_leaf_is_the_edges_own_activation() {
    let mut sc = Scratch::default();
    let (mut edges, mut tail_differs, mut same_leaf, mut coord) = (0usize, 0usize, 0usize, 0usize);
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let (p, seat) = (act.player, act.statics.opener_seat);
            for on in [false, true] {
                with_knobs(&c, ai, &per_act[ai], &opponent_model(&c.knobs, on, false), |roll| {
                    let (rows, order) = ranked(roll, &act.state, p, &mut sc).unwrap();
                    let mut root = Node::new(act.state.clone(), Step::Mover(p), p);
                    root.children = root_children(&rows, &order, &[]);
                    let width = root.children.len();
                    let cfg = TreeCfg { leaf: TreeLeaf::Blend, dice: TreeDice::Ev, samples: 1, batch: 8, budget: width,
                                        wall_ms: 0, deadline: None, widen: 0.0, puct: 0.0, player: p, opener_seat: seat,
                                        sig: None, hook: None, w: 0.0 };
                    let t = run(roll, &cfg, &mut root, &mut GodotRng::new(7), &mut sc).unwrap().1;
                    assert_eq!((t.completed, root.next_child), (width, width), "act {ai}: one leaf per root edge");
                    for ch in &root.children {
                        let leaf = &ch.nodes[0];
                        let mut cur = roll.policy.resolve(&act.state, &ch.cand).unwrap();
                        let fired = roll.coordinate_hand_off(&mut cur, &ch.cand, p, &mut sc).unwrap();
                        let turn = other_player(&cur, p);
                        let step = advance(roll, &mut cur, turn, None);
                        assert_eq!(format!("{:?}", leaf.state), format!("{cur:?}"),
                                   "act {ai} idx {}: the leaf is not the edge's own activation", ch.idx);
                        let want = match step {
                            Step::Terminal => referee(&cur, p),
                            Step::Mover(_) => roll.blend_score_leaf(std::slice::from_ref(&cur), p, seat, &[], 0.0),
                        };
                        assert_eq!((leaf.n, leaf.w.to_bits()), (1, want.to_bits()),
                                   "act {ai} idx {} leaf_opener_only={on}: not the Blend leaf of that state", ch.idx);
                        let (ends, stop) = roll.rollout_traced(&act.state, &ch.cand, p, -1, &mut sc).unwrap();
                        if on {
                            assert_eq!((ends.len(), stop), (1, Stop::TailCap), "act {ai}: the one-ply knob is not live");
                            same_leaf += usize::from(format!("{:?}", ends[0]) == format!("{cur:?}"));
                        } else {
                            tail_differs += usize::from(roll.blend_score(&ends, p, seat).to_bits() != leaf.w.to_bits());
                            (edges, coord) = (edges + 1, coord + usize::from(fired));
                        }
                    }
                });
            }
        }
    }
    println!("tree leaf: {edges} root edges priced at their own activation, knob OFF and ON; the scripted-tail value \
              differs on {tail_differs}; the one-ply's leaf_opener_only leaf is the tree's very state on {same_leaf}; \
              Coordinate fired on {coord}");
    assert!(edges > 0 && tail_differs > 0, "no edge where a scripted tail would show: the equality proves nothing");
}

/// A seat-aware counting leaf hook (`tests/plan.rs` `SeatLog`, with a state-dependent answer so the net leaf moves
/// the search): every call is logged as `(side, opener_seat, leaves)`; a leaf answers 0.01 x (the side's models
/// alive minus the other side's).
struct HookLog {
    root_seat: bool,
    calls: std::cell::RefCell<Vec<(i64, bool, usize)>>,
}

impl HookLog {
    fn log(&self, leaves: &[&State], side: i64, opener_seat: bool) -> Vec<f64> {
        self.calls.borrow_mut().push((side, opener_seat, leaves.len()));
        let lead = |s: &State| (0..s.units()).map(|i| if s.player[i] == side { s.alive[i] } else { -s.alive[i] }).sum::<i64>();
        leaves.iter().map(|&s| 0.01 * lead(s) as f64).collect()
    }
}

impl nml_core::plan::LeafValue for HookLog {
    fn value(&self, leaves: &[&State], side: i64) -> Result<Vec<f64>, Unsupported> {
        Ok(self.log(leaves, side, self.root_seat))
    }

    fn value_for_seat(&self, leaves: &[&State], side: i64, opener_seat: bool) -> Result<Vec<f64>, Unsupported> {
        Ok(self.log(leaves, side, opener_seat))
    }
}

/// A tree pick's deterministic part: the pick, the counts and every root child (idx, visits, mean); the
/// wall-clock stamps left out.
fn tree_stats(p: &nml_core::Pick) -> String {
    let t = p.tree.as_ref().expect("a tree pick carries its trace");
    format!("{} {:?} {} {} {} {} {} {:?}", p.unit_key, p.action, t.completed, t.batches, t.frontier, t.terminal,
            t.deadline_hit, t.root)
}

/// Map step 2 — the tree runs no rollout, so the `reply_by_net` family has no reply to hand the nested search: an
/// opponent node of the tree searches its full menu itself. Through `Search::run` (the tree knob, budget 64, the net
/// leaf live at w 1) every arm ON gives OFF's pick, root statistics and hook calls to the bit, and every hook call
/// comes from the searcher's own seat — no nested search. Negative control: the same act through the ONE-PLY with the
/// same hook and the family ON logs calls from the opponent's seat, so the log sees a nested search where one runs.
#[test]
fn opponent_model_reply_family_runs_no_nested_search_in_the_tree() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let mut tree = c.knobs;
    (tree.search_mode, tree.tree_budget, tree.tree_wall_ms, tree.deadline_us) = (SearchMode::Tree, 64, 0, 0);
    let (mut acts, mut tree_calls, mut nested) = (0usize, 0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let (p, seat) = (act.player, act.statics.opener_seat);
        let pick = |k: &nml_core::Knobs| {
            let log = HookLog { root_seat: seat, calls: Default::default() };
            let got = with_knobs(&c, ai, &per_act[ai], k, |roll| {
                let mut s = Search::new(*roll, &act.statics);
                s.leaf_value = Some(&log as &dyn nml_core::plan::LeafValue);
                s.leaf_value_w = 1.0;
                s.run(&act.state, p, &mut Scratch::default(), None)
            });
            (got, log.calls.into_inner())
        };
        let (off, off_calls) = pick(&tree);
        let off = off.unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        for (name, lo, rn) in ARMS {
            let (on, on_calls) = pick(&opponent_model(&tree, lo, rn));
            let on = on.unwrap_or_else(|e| panic!("act {ai} {name}: {e:?}"));
            assert_eq!(tree_stats(&on), tree_stats(&off), "act {ai} {name}: the tree's pick or root statistics moved");
            assert_eq!(on_calls, off_calls, "act {ai} {name}: the tree's hook calls moved");
        }
        assert!(!off_calls.is_empty() && off_calls.iter().all(|&(side, s, _)| (side, s) == (p, seat)),
                "act {ai}: a tree hook call from another seat: {off_calls:?}");
        tree_calls += off_calls.len();
        let (one, one_ply) = pick(&opponent_model(&c.knobs, false, true));
        if one.is_ok() {
            nested += one_ply.iter().filter(|&&(side, _, _)| side != p).count();
        }
        acts += 1;
    }
    println!("reply_by_net family in the tree: {acts} acts, {tree_calls} tree hook calls, every one from the searcher's \
              seat in every arm; the one-ply with the family ON logged {nested} nested calls from the opponent's seat");
    assert!(acts == c.acts.len() && tree_calls > 0, "{acts} acts, {tree_calls} calls");
    assert!(nested > 0, "the one-ply ran no nested reply search: the log cannot see one, the tree check proves nothing");
}

/// IDENTITY — the opponent-model knobs are inert in the tree: at a budget past the root width (the search descends
/// into the opponent's nodes) every arm ON gives the all-OFF pick and root statistics (idx, visits, mean, counts) to
/// the bit, the Blend leaf on both fixtures and the Terminal leaf on acts_25. No executable line of the tree changes
/// in this PR, so all-OFF is today's tree by construction.
#[test]
fn opponent_model_knobs_leave_the_tree_bit_identical() {
    let mut sc = Scratch::default();
    let (mut n, mut deep) = (0usize, 0usize);
    for (path, leaves) in [(ACTS, &[TreeLeaf::Blend, TreeLeaf::Terminal][..]), (WIDE, &[TreeLeaf::Blend][..])] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            for &leaf in leaves {
                let mut tree = |k: &nml_core::Knobs| with_knobs(&c, ai, &per_act[ai], k, |roll| {
                    let width = menu(roll, &act.state, act.player, &mut sc).len();
                    let (best, t, _) = search(roll, &act.state, act.player, leaf, width + 16, 4, &mut sc);
                    (format!("{best} {t:?}"), t.root.iter().any(|r| r.1 > 1))
                });
                let (off, descended) = tree(&c.knobs);
                for (name, lo, rn) in ARMS {
                    assert_eq!(tree(&opponent_model(&c.knobs, lo, rn)).0, off, "act {ai} {leaf:?} {name}: the tree moved");
                }
                (n, deep) = (n + 1, deep + usize::from(descended));
            }
        }
    }
    println!("tree identity: {n} searches x {} arms bit-identical to all knobs OFF, {deep} descended below the root",
             ARMS.len());
    assert!(n > 0 && deep > 0, "{n} searches, {deep} descended: the opponent's nodes are untested");
}

/// The recorder's tree arm with both opponent-model presets on (`--arm L` + `leaf_opener` +
/// `reply_net_cap3_restricted`) is one header the parser takes as written.
#[test]
fn opponent_model_tree_header_parses_as_written() {
    let head = r#"{"kind":"header","profiles":{},"knobs":{"search_mode":"tree","tree_leaf":"blend","tree_budget":128,
        "leaf_opener_only":true,"reply_by_net":true,"reply_top_k":3,"reply_horizon":1,"reply_pool_cap":3,
        "reply_menu_restricted":true}}"#;
    let k = read_act_header(head).unwrap_or_else(|e| panic!("{e}")).knobs;
    assert_eq!((k.search_mode, k.tree_leaf, k.tree_budget), (SearchMode::Tree, TreeLeaf::Blend, 128));
    assert!(k.leaf_opener_only && k.reply_by_net && k.reply_menu_restricted);
    assert_eq!((k.reply_top_k, k.reply_horizon, k.reply_pool_cap), (3, 1, 3));
}


// ------------- tree_opponent_own_leaf: the opponent's node in ITS OWN frame (D7) ---

/// `search` with a leaf hook `hook` at weight `w` asked from the searcher's seat `seat`; hands back the tree too.
#[allow(clippy::too_many_arguments)]
fn search_hooked(roll: &Rollout, st: &State, p: i64, leaf: TreeLeaf, budget: usize, batch: usize,
                 hook: Option<&dyn nml_core::plan::LeafValue>, w: f64, seat: bool, sc: &mut Scratch)
                 -> (usize, TreeTrace, Node) {
    let (rows, order) = ranked(roll, st, p, sc).unwrap();
    let mut root = Node::new(st.clone(), Step::Mover(p), p);
    root.children = root_children(&rows, &order, &[]);
    let cfg = TreeCfg { leaf, dice: TreeDice::Ev, samples: 1, batch, budget, wall_ms: 0, deadline: None, widen: 0.0,
                        puct: 0.0, player: p, opener_seat: seat, sig: None, hook, w };
    let (best, trace) = run(roll, &cfg, &mut root, &mut GodotRng::new(7), sc).unwrap();
    (best, trace, root)
}

/// FNV-1a 64 over the lines, each closed by a newline: one number for a whole fixture sweep.
fn digest(lines: &[String]) -> u64 {
    let mut h = 0xcbf2_9ce4_8422_2325u64;
    for b in lines.iter().flat_map(|l| l.bytes().chain(std::iter::once(b'\n'))) {
        h = (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3);
    }
    h
}

/// The OFF sweep: #1720's 59 searches past the root width (Blend on both fixtures, Terminal on acts_25; budget the
/// width plus 16, batch 4), each without a hook and (Blend) with `HookLog` at w 1, plus the 23 acts of acts_25 through
/// `Search::run` (tree, budget 64, `HookLog` at w 1). One line per search: the pick, the counts, every root child
/// (idx, visits, mean) and every hook call (side, seat, leaves).
fn off_sweep(k: impl Fn(&nml_core::Knobs) -> nml_core::Knobs) -> (Vec<String>, usize) {
    let (mut lines, mut searches, mut sc) = (Vec::new(), 0usize, Scratch::default());
    let line = |t: &TreeTrace| format!("{} {} {} {} {} {:?}", t.completed, t.batches, t.frontier, t.terminal,
                                       t.deadline_hit, t.root);
    for (path, leaves) in [(ACTS, &[TreeLeaf::Blend, TreeLeaf::Terminal][..]), (WIDE, &[TreeLeaf::Blend][..])] {
        let c = load(path);
        let (per_act, tag) = (act_statics(&c, REPO), path.rsplit('/').next().unwrap());
        for (ai, act) in c.acts.iter().enumerate() {
            let (p, seat) = (act.player, act.statics.opener_seat);
            for &leaf in leaves {
                with_knobs(&c, ai, &per_act[ai], &k(&c.knobs), |roll| {
                    let width = menu(roll, &act.state, p, &mut sc).len();
                    let (best, t, _) = search_hooked(roll, &act.state, p, leaf, width + 16, 4, None, 0.0, seat, &mut sc);
                    lines.push(format!("{tag} {ai} {leaf:?} bare {best} {}", line(&t)));
                    searches += 1;
                    if leaf == TreeLeaf::Blend {
                        let log = HookLog { root_seat: seat, calls: Default::default() };
                        let (best, t, _) = search_hooked(roll, &act.state, p, leaf, width + 16, 4,
                                                         Some(&log as &dyn nml_core::plan::LeafValue), 1.0, seat, &mut sc);
                        lines.push(format!("{tag} {ai} {leaf:?} hook {best} {} {:?}", line(&t), log.calls.into_inner()));
                    }
                });
            }
        }
    }
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    let mut tree = k(&c.knobs);
    (tree.search_mode, tree.tree_budget, tree.tree_wall_ms, tree.deadline_us) = (SearchMode::Tree, 64, 0, 0);
    for (ai, act) in c.acts.iter().enumerate() {
        let log = HookLog { root_seat: act.statics.opener_seat, calls: Default::default() };
        let got = with_knobs(&c, ai, &per_act[ai], &tree, |roll| {
            let mut s = Search::new(*roll, &act.statics);
            s.leaf_value = Some(&log as &dyn nml_core::plan::LeafValue);
            s.leaf_value_w = 1.0;
            s.run(&act.state, act.player, &mut Scratch::default(), None).unwrap()
        });
        lines.push(format!("run {ai} {} {:?}", tree_stats(&got), log.calls.into_inner()));
    }
    (lines, searches)
}

/// The OFF sweep's digest on main ead23782 (before `tree_opponent_own_leaf` existed), recorded on the box.
const MAIN_OFF_DIGEST: u64 = 0xd7f9_79ff_69a7_cb5e;

/// IDENTITY — `tree_opponent_own_leaf` OFF is main's tree to the bit: #1720's 59-search fixture (bare and hooked) and
/// the 23 `Search::run` tree picks give main's picks, counts, root statistics and hook calls, as one digest recorded
/// on main before the knob existed.
#[test]
fn tree_opponent_own_leaf_off_is_mains_tree_to_the_bit() {
    let (lines, searches) = off_sweep(|k| *k);
    let explicit = off_sweep(|k| own_knobs(k, false)).0;
    assert!(lines == explicit, "the knob written OFF is not the default");
    assert!(!load(ACTS).knobs.tree_opponent_own_leaf && !load(WIDE).knobs.tree_opponent_own_leaf, "the fixtures carry the knob");
    let got = digest(&lines);
    println!("tree_opponent_own_leaf OFF: {searches} searches + {} lines, digest {got:#018x}", lines.len());
    assert_eq!(searches, 59, "the #1720 fixture is 59 searches");
    assert_eq!(got, MAIN_OFF_DIGEST, "OFF moved the tree off main: digest {got:#018x}");
}

/// The knobs with `tree_opponent_own_leaf` set to `on`.
fn own_knobs(k: &nml_core::Knobs, on: bool) -> nml_core::Knobs {
    nml_core::Knobs { tree_opponent_own_leaf: on, ..*k }
}

/// Every node of the tree under `n`, `n` included.
fn each_node<'a>(n: &'a Node, f: &mut impl FnMut(&'a Node)) {
    f(n);
    for c in &n.children {
        for x in &c.nodes {
            each_node(x, f);
        }
    }
}

/// (child, sample) steps of a path, or (searcher-frame argmin, own-frame argmax) pairs.
type Pairs = Vec<(usize, usize)>;

/// The descent `run` takes from `root` next at the widening rate `widen` (no priors): at every node with all its
/// allowed children open the child `select` picks — `select_own` at an opponent node when `own` — and its least-visited
/// sample. Returns the path as (child, sample) and, per opponent node on it, (the searcher-frame argmin, the own-frame
/// argmax).
fn next_descent(root: &Node, p: i64, own: bool, widen: f64) -> (Pairs, Pairs) {
    let cap = |x: &Node| if widen > 0.0 { f64::from(x.n.max(1)).powf(widen).ceil() as usize } else { usize::MAX };
    let (mut node, mut path, mut opp) = (root, Vec::new(), Vec::new());
    while node.terminal.is_none() && !node.children.is_empty() && node.next_child >= node.children.len().min(cap(node)) {
        let (paranoid, mine) = (select(node, p), select_own(node));
        let c = if own && node.mover != p { mine } else { paranoid };
        if node.mover != p {
            opp.push((paranoid, mine));
        }
        let s = (0..node.children[c].nodes.len()).min_by_key(|&s| node.children[c].nodes[s].n).unwrap_or(0);
        path.push((c, s));
        node = &node.children[c].nodes[s];
    }
    (path, opp)
}

/// The nodes along `path` from `root`, `root` first.
fn nodes_on<'a>(root: &'a Node, path: &[(usize, usize)]) -> Vec<&'a Node> {
    let mut out = vec![root];
    for &(c, s) in path {
        let last = out[out.len() - 1];
        out.push(&last.children[c].nodes[s]);
    }
    out
}

/// D7 at one node: over the same three children the searcher's argmin and the opponent's own argmax differ (the leaf is
/// not zero-sum: own != 1 - mean); `select` takes the first, `select_own` the second, and both keep the first on ties.
#[test]
fn select_own_takes_the_opponents_own_argmax() {
    let c = load(ACTS);
    let st = &c.acts[0].state;
    let mut node = Node::new(st.clone(), Step::Mover(2), 1);
    node.n = 6;
    for (i, (mean, own)) in [(0.5, 0.3), (0.9, 0.1), (0.1, 0.2)].into_iter().enumerate() {
        let mut leaf = Node::new(st.clone(), Step::Mover(1), 1);
        (leaf.n, leaf.w, leaf.wo) = (2, 2.0 * mean, 2.0 * own);
        node.children.push(Child { idx: i, cand: Candidate::hold(st.key(0)), nodes: vec![leaf], prior: None, own: None });
    }
    node.next_child = 3;
    assert_eq!((select(&node, 1), select_own(&node)), (2, 0), "paranoid argmin vs own argmax");
    node.children.iter_mut().for_each(|k| k.nodes[0].wo = 1.0);
    assert_eq!(select_own(&node), 0, "ties keep the first child");
}

/// (b) ON, the search follows the opponent's OWN frame at its nodes. On both fixtures (Blend leaf, `HookLog` at w 1,
/// budget 4 x the root width + 32, batch 8, widening 0.5 so the search selects at the opponent's nodes; at 0.0 and
/// this budget it reaches few of them fully opened) a search runs; the next descent is predicted from the tree (`select_own`
/// at every opponent node, `select` elsewhere); one more leaf runs on the same tree, and every node on the predicted
/// path gained it. Both frames sit on the tree: every visited child of an opponent node on the path carries its own
/// value (`wo`: the referee for the opponent per visit at a game end, a priced leaf sum otherwise) beside the
/// searcher's. On some opponent node the own argmax is not the searcher's argmin, so there the search went the own
/// way. OFF, the prediction with `select` everywhere holds and no node carries an own mean (the control).
#[test]
fn tree_opponent_own_leaf_selects_the_opponents_own_argmax() {
    let (mut checked, mut split, mut nodes, mut sc) = (0usize, 0usize, 0usize, Scratch::default());
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let (p, seat) = (act.player, act.statics.opener_seat);
            for on in [false, true] {
                with_knobs(&c, ai, &per_act[ai], &own_knobs(&c.knobs, on), |roll| {
                    let width = menu(roll, &act.state, p, &mut sc).len();
                    let log = HookLog { root_seat: seat, calls: Default::default() };
                    let hook = Some(&log as &dyn nml_core::plan::LeafValue);
                    let (rows, order) = ranked(roll, &act.state, p, &mut sc).unwrap();
                    let mut root = Node::new(act.state.clone(), Step::Mover(p), p);
                    root.children = root_children(&rows, &order, &[]);
                    let mut cfg = TreeCfg { leaf: TreeLeaf::Blend, dice: TreeDice::Ev, samples: 1, batch: 8,
                                            budget: 4 * width + 32, wall_ms: 0, deadline: None, widen: 0.5, puct: 0.0,
                                            player: p, opener_seat: seat, sig: None, hook, w: 1.0 };
                    run(roll, &cfg, &mut root, &mut GodotRng::new(7), &mut sc).unwrap();
                    let mut own_any = false;
                    each_node(&root, &mut |x| own_any |= x.wo != 0.0);
                    assert!(on || !own_any, "act {ai}: OFF carries own means");
                    let (path, opp) = next_descent(&root, p, on, cfg.widen);
                    if opp.is_empty() {
                        return;
                    }
                    for x in nodes_on(&root, &path).into_iter().filter(|x| x.terminal.is_none() && x.mover != p) {
                        // Both frames: every visited child carries its own value, the referee for the opponent per
                        // visit at a game end, a priced (non-zero) leaf sum otherwise.
                        for y in x.children[..x.next_child].iter().flat_map(|k| &k.nodes).filter(|y| y.n > 0) {
                            let ok = match y.terminal {
                                Some(_) => y.wo == f64::from(y.n) * referee(&y.state, x.mover),
                                None => y.wo != 0.0,
                            };
                            assert!(!on || ok, "act {ai}: a child of an opponent node lacks its own value: n {} w {} wo {}",
                                    y.n, y.w, y.wo);
                        }
                        nodes += usize::from(on);
                    }
                    let before: Vec<u32> = nodes_on(&root, &path).iter().map(|x| x.n).collect();
                    cfg.budget = 1;
                    let t = run(roll, &cfg, &mut root, &mut GodotRng::new(7), &mut sc).unwrap().1;
                    let after: Vec<u32> = nodes_on(&root, &path).iter().map(|x| x.n).collect();
                    let gained = t.completed as u32;
                    assert!(gained > 0 && before.iter().zip(&after).all(|(b, a)| a - b == gained),
                            "act {ai} on={on}: the search left the predicted path, visits {before:?} -> {after:?} (+{gained})");
                    if on {
                        checked += 1;
                        split += opp.iter().filter(|(a, b)| a != b).count();
                    }
                });
            }
        }
    }
    println!("tree_opponent_own_leaf select: {checked} ON descents through {nodes} opponent nodes followed the own \
              argmax; {split} of them where it is not the searcher's argmin");
    assert!(checked >= 20 && split > 0, "{checked} descents, {split} where the frames differ: the choice is untested");
}

/// ON, an opponent node's children come in the order of ITS OWN leaf. For the node below each act's root child 0, when
/// it is the opponent's, `own_children` (`HookLog` at w 1) is checked by hand: every `ranked` row through its EV edge
/// (resolve, the Coordinate hand-off, `advance`), priced by `blend_score_leaf` for the opponent with the flipped seat
/// token and the hook's value asked from that seat (the referee for the opponent at a game end), best first, `ranked`'s
/// order on ties, and the hook asked once for the whole menu. Through `run` ON every opponent node built carries own
/// values in that order; OFF none carries one. On some node the own order is not `ranked`'s.
#[test]
fn tree_opponent_own_leaf_orders_the_opponents_children_by_its_own_leaf() {
    let (mut checked, mut reordered, mut built, mut sc) = (0usize, 0usize, 0usize, Scratch::default());
    for path in [ACTS, WIDE] {
        let c = load(path);
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let (p, seat) = (act.player, act.statics.opener_seat);
            let log = HookLog { root_seat: seat, calls: Default::default() };
            let hook = Some(&log as &dyn nml_core::plan::LeafValue);
            with_knobs(&c, ai, &per_act[ai], &own_knobs(&c.knobs, true), |roll| {
                let (rows, order) = ranked(roll, &act.state, p, &mut sc).unwrap();
                let mut root = Node::new(act.state.clone(), Step::Mover(p), p);
                root.children = root_children(&rows, &order, &[]);
                expand(roll, &mut root, 1, TreeDice::Ev, 1, None, p, &mut sc).unwrap();
                let x = &root.children[0].nodes[0];
                if x.terminal.is_some() || x.mover == p {
                    return;
                }
                let opp = x.mover;
                let before = log.calls.borrow().len();
                let (kids, asked) = own_children(roll, x, p, !seat, hook, 1.0, &mut sc).unwrap();
                let (krows, korder) = ranked(roll, &x.state, opp, &mut sc).unwrap();
                let mut want: Vec<(usize, f64)> = korder.iter().map(|&i| {
                    let mut cur = roll.policy.resolve(&x.state, &krows[i].cand).unwrap();
                    roll.coordinate_hand_off(&mut cur, &krows[i].cand, p, &mut sc).unwrap();
                    let turn = other_player(&cur, opp);
                    let v = match advance(roll, &mut cur, turn, None) {
                        Step::Terminal => referee(&cur, opp),
                        Step::Mover(_) => {
                            let hv = HookLog { root_seat: seat, calls: Default::default() }.log(&[&cur], opp, !seat);
                            roll.blend_score_leaf(std::slice::from_ref(&cur), opp, !seat, &hv, 1.0)
                        }
                    };
                    (i, v)
                }).collect();
                want.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
                let got: Vec<(usize, u64)> = kids.iter().map(|k| (k.idx, k.own.unwrap().to_bits())).collect();
                assert_eq!(got, want.iter().map(|w| (w.0, w.1.to_bits())).collect::<Vec<_>>(), "act {ai}: own order");
                let calls = log.calls.borrow()[before..].to_vec();
                assert!(calls.len() <= 1 && calls.iter().all(|&(side, s, n)| side == opp && s == !seat && n == asked),
                        "act {ai}: own_children asked {calls:?}");
                reordered += usize::from(kids.iter().map(|k| k.idx).ne(korder.iter().copied()));
                checked += 1;
            });
            for on in [false, true] {
                with_knobs(&c, ai, &per_act[ai], &own_knobs(&c.knobs, on), |roll| {
                    let width = menu(roll, &act.state, p, &mut sc).len();
                    let root = search_hooked(roll, &act.state, p, TreeLeaf::Blend, 2 * width + 16, 8, hook, 1.0, seat, &mut sc).2;
                    each_node(&root, &mut |x| {
                        if x.terminal.is_none() && x.mover != p && !x.children.is_empty() {
                            let owns: Vec<Option<f64>> = x.children.iter().map(|k| k.own).collect();
                            if on {
                                assert!(owns.iter().all(|o| o.is_some()) && owns.windows(2).all(|w| w[0] >= w[1]),
                                        "act {ai}: an opponent node not in its own order: {owns:?}");
                                built += 1;
                            } else {
                                assert!(owns.iter().all(|o| o.is_none()), "act {ai}: OFF carries own values");
                            }
                        }
                    });
                });
            }
        }
    }
    println!("tree_opponent_own_leaf order: {checked} opponent nodes in the hand-checked own order, {reordered} of them \
              off ranked's; {built} opponent nodes built ON, every one in its own order");
    assert!(checked >= 10 && reordered > 0 && built > 0, "{checked} {reordered} {built}");
}

/// (c) The cost and the seat. Through `Search::run` (tree, budget 64 and 128, `HookLog` at w 1) on acts_25: OFF asks
/// the hook from the searcher's seat only; ON adds calls from the opponent's seat (side and `opener_seat` flipped),
/// none from a third, and the trace's `own_leaves` counts exactly their leaves. Reported: calls and leaves ON / OFF.
#[test]
fn tree_opponent_own_leaf_asks_the_opponents_seat_only_when_on() {
    let c = load(ACTS);
    let per_act = act_statics(&c, REPO);
    for budget in [64, 128] {
        let mut tree = c.knobs;
        (tree.search_mode, tree.tree_budget, tree.tree_wall_ms, tree.deadline_us) = (SearchMode::Tree, budget, 0, 0);
        let (mut calls, mut leaves, mut opp_calls, mut moved) = ([0usize; 2], [0usize; 2], [0usize; 2], 0usize);
        for (ai, act) in c.acts.iter().enumerate() {
            let (p, seat) = (act.player, act.statics.opener_seat);
            let mut picks = Vec::new();
            for (i, on) in [false, true].into_iter().enumerate() {
                let log = HookLog { root_seat: seat, calls: Default::default() };
                let got = with_knobs(&c, ai, &per_act[ai], &own_knobs(&tree, on), |roll| {
                    let mut s = Search::new(*roll, &act.statics);
                    s.leaf_value = Some(&log as &dyn nml_core::plan::LeafValue);
                    s.leaf_value_w = 1.0;
                    s.run(&act.state, p, &mut Scratch::default(), None).unwrap()
                });
                let log = log.calls.into_inner();
                let theirs: Vec<&(i64, bool, usize)> = log.iter().filter(|&&(side, s, _)| (side, s) != (p, seat)).collect();
                assert!(theirs.iter().all(|&&(side, s, _)| side != p && s != seat), "act {ai}: a call from a third seat: {log:?}");
                let own = got.tree.as_ref().unwrap().own_leaves;
                assert_eq!(own, theirs.iter().map(|x| x.2).sum::<usize>(), "act {ai} on={on}: own_leaves");
                assert!(on || theirs.is_empty(), "act {ai}: OFF asked the opponent's seat: {theirs:?}");
                calls[i] += log.len();
                leaves[i] += log.iter().map(|x| x.2).sum::<usize>();
                opp_calls[i] += theirs.len();
                picks.push(format!("{} {:?}", got.unit_key, got.action));
            }
            moved += usize::from(picks[0] != picks[1]);
        }
        println!("tree_opponent_own_leaf cost at budget {budget}: hook calls OFF {} ON {} (x{:.2}), leaves OFF {} ON {} \
                  (x{:.2}); ON calls from the opponent's seat {}; picks moved {moved}/{}", calls[0], calls[1],
                 calls[1] as f64 / calls[0] as f64, leaves[0], leaves[1], leaves[1] as f64 / leaves[0] as f64,
                 opp_calls[1], c.acts.len());
        assert!(opp_calls[0] == 0 && opp_calls[1] > 0, "opponent-seat calls OFF {} ON {}", opp_calls[0], opp_calls[1]);
    }
}

/// The knob parses from a header and defaults off.
#[test]
fn tree_opponent_own_leaf_parses_and_defaults_off() {
    let head = r#"{"kind":"header","profiles":{},"knobs":{"search_mode":"tree","tree_opponent_own_leaf":true}}"#;
    assert!(read_act_header(head).unwrap_or_else(|e| panic!("{e}")).knobs.tree_opponent_own_leaf);
    let bare = r#"{"kind":"header","profiles":{},"knobs":{"search_mode":"tree"}}"#;
    assert!(!read_act_header(bare).unwrap().knobs.tree_opponent_own_leaf);
}

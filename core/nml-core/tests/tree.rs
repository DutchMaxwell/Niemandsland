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
    advance, expand, leaf_value, menu, playout, ranked, referee, root_children, run, select, transition, Child,
    Node, Step, TreeCfg, TreeTrace,
};
use nml_core::{act_statics, full_playout_bent, load_acts, plan_with_rollout, ActCorpus, ArbBend, GodotRng, State, TreeDice,
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

/// Every field of a state, floats at round-trip precision.
fn canon(states: &[State]) -> Vec<String> {
    states.iter().map(|s| format!("{s:?}")).collect()
}

/// Step 5 — chance edges, over every menu row of every act of both fixtures:
/// `Ev` is `Policy::resolve` bit for bit; `Tray` draws `samples` states, the
/// same stream base twice is byte-identical, another base moves some edge,
/// the samples of one edge differ among themselves somewhere, and an
/// activation the tray path flags unported declines by name (the fixtures
/// carry Deadly(3) weapons); `Tray` with no base declines.
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
                        // Another base may roll into an unported branch itself (a Deadly
                        // weapon flags only when it lands): that counts as moved too.
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
    assert!(declined.contains_key("deadly"), "no Deadly activation declined");
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
    let (rows, order) = ranked(roll, st, p, sc).unwrap();
    let mut root = Node::new(st.clone(), Step::Mover(p), p);
    root.children = root_children(&rows, &order, &[]);
    let cfg = TreeCfg { leaf, dice: TreeDice::Ev, samples: 1, batch, budget, player: p, opener_seat: false,
                        sig: None, hook: None, w: 0.0 };
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
        node.children.push(Child { idx: i, cand: Candidate::hold(st.key(0)), nodes: vec![leaf] });
    }
    assert_eq!(select(&node, 1), 1, "the searcher's own node takes the argmax");
    node.mover = 2;
    assert_eq!(select(&node, 1), 2, "the opponent's node takes the argmin");
}

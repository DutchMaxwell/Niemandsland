//! B15b — the opponent child-order shuffle (`tree_opp_shuffle`): at an OPPONENT
//! node the first batch permutes the candidate order before the take-first-`k`,
//! same width, so a different subset of the reply set opens first. `0` (default)
//! = off, byte-identical; any other value is the shuffle seed.
//!
//! RED (before the knob): there is no way to permute the order, so a config
//! cannot make the same-width first batch pick a different reply.
//! GREEN: on some fixture the same budget, same completed count, picks a
//! different reply under a shuffle seed than under off, and the seed is
//! deterministic (the control arm's CRN).

use nml_core::plan::{seams_of, tuning_of};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::{reach_index_for_state, Scratch};
use nml_core::tree::{ranked, root_children, run, Node, Step, TreeCfg, TreeTrace};
use nml_core::{act_statics, load_acts, ActCorpus, GodotRng, State, TreeDice, TreeLeaf, UnitStatic};

const ACTS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const WIDE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const BATCH: usize = 8;
const BUDGET: usize = 40;
const SEED: i64 = 12345;

/// The corpus knobs with the tail caps zeroed (the tree never applies them).
fn with_roll<R>(c: &ActCorpus, ai: usize, statics: &[UnitStatic], f: impl FnOnce(&Rollout) -> R) -> R {
    let mut knobs = c.knobs;
    (knobs.tail_cap_p1, knobs.tail_cap_p2) = (0, 0);
    let seams = seams_of(&knobs);
    let reach = if seams.path { reach_index_for_state(&c.acts[ai].state, &c.terrain) } else { None };
    let mut p = Policy::new(statics, &c.terrain, seams);
    (p.tuning, p.reach) = (tuning_of(&knobs), reach.as_ref());
    f(&Rollout::new(p, knobs))
}

/// A tree search at `BUDGET`/`BATCH`, `tree_opp_shuffle` = `shuffle`.
fn run_shuffle(roll: &Rollout, st: &State, p: i64, shuffle: i64, sc: &mut Scratch) -> (usize, TreeTrace) {
    let (rows, order) = ranked(roll, st, p, sc).unwrap();
    let mut root = Node::new(st.clone(), Step::Mover(p), p);
    root.children = root_children(&rows, &order, &[]);
    let cfg = TreeCfg { leaf: TreeLeaf::Blend, dice: TreeDice::Ev, samples: 1, batch: BATCH, opp_batch: 0, opp_shuffle: shuffle,
                        budget: BUDGET, wall_ms: 0, deadline: None, widen: 0.0, puct: 0.0, player: p,
                        opener_seat: false, sig: None, hook: None, w: 0.0 };
    let (best, trace) = run(roll, &cfg, &mut root, &mut GodotRng::new(7), sc).unwrap();
    (best, trace)
}

#[test]
fn tree_opp_shuffle_permutes_the_first_batch_at_the_same_width() {
    let (mut sc, mut flips) = (Scratch::default(), 0usize);
    for path in [ACTS, WIDE] {
        let c = load_acts(path).unwrap_or_else(|e| panic!("{e}"));
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let p = act.player;
            with_roll(&c, ai, &per_act[ai], |roll| {
                let (off, toff) = run_shuffle(roll, &act.state, p, 0, &mut sc);
                let (off2, _) = run_shuffle(roll, &act.state, p, 0, &mut sc);
                let (on, ton) = run_shuffle(roll, &act.state, p, SEED, &mut sc);
                let (on2, _) = run_shuffle(roll, &act.state, p, SEED, &mut sc);
                assert_eq!(off, off2, "{path} act {ai}: off is not deterministic");
                assert_eq!(on, on2, "{path} act {ai}: a shuffle seed is not deterministic");
                // Same width: the shuffle reorders, it never changes how many leaves open.
                assert_eq!(toff.completed, ton.completed, "{path} act {ai}: shuffle changed the width");
                if off != on {
                    flips += 1;
                }
            });
        }
    }
    assert!(flips > 0, "no fixture let the shuffled order pick a different reply at the same width");
}

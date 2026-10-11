//! B15 — the opponent wide-first batch (`tree_opp_batch`): at an OPPONENT node
//! the FIRST expansion batch opens up to `tree_opp_batch` children instead of
//! `tree_batch`, so the reply set is opened wide before the search descends
//! below it. 0 (default) = off, `tree_batch` everywhere.
//!
//! RED (before the knob): the widest first batch any opponent node opens at
//! budget 64 is `tree_batch` (8); a config cannot ask for 24.
//! GREEN: on some fixture one opponent node opens >= 24 rows in its first batch
//! while the search reaches the same budget in fewer batches, and a config whose
//! `tree_opp_batch` equals `tree_batch` is byte-identical to off (0).

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
const OPP_BATCH: usize = 24;
const BUDGET: usize = 64;

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

/// A tree search at a fixed budget and `batch`, `tree_opp_batch` = `opp_batch`.
fn run_opp(roll: &Rollout, st: &State, p: i64, opp_batch: usize, sc: &mut Scratch) -> (usize, TreeTrace, Node) {
    let (rows, order) = ranked(roll, st, p, sc).unwrap();
    let mut root = Node::new(st.clone(), Step::Mover(p), p);
    root.children = root_children(&rows, &order, &[]);
    let cfg = TreeCfg { leaf: TreeLeaf::Blend, dice: TreeDice::Ev, samples: 1, batch: BATCH, opp_batch, opp_shuffle: 0, budget: BUDGET,
                        wall_ms: 0, deadline: None, widen: 0.0, puct: 0.0, player: p,
                        opener_seat: false, sig: None, hook: None, w: 0.0 };
    let (best, trace) = run(roll, &cfg, &mut root, &mut GodotRng::new(7), sc).unwrap();
    (best, trace, root)
}

/// Every opponent node of the tree under `n`.
fn opp_nodes<'a>(n: &'a Node, p: i64, out: &mut Vec<&'a Node>) {
    if n.terminal.is_none() && n.mover != p {
        out.push(n);
    }
    for c in &n.children {
        for x in &c.nodes {
            opp_nodes(x, p, out);
        }
    }
}

/// The widest first batch any opponent node opened: the largest `next_child`
/// over the opponent nodes of a finished search.
fn widest_opp_batch(root: &Node, p: i64) -> usize {
    let mut ns = Vec::new();
    opp_nodes(root, p, &mut ns);
    ns.iter().map(|x| x.next_child).max().unwrap_or(0)
}

#[test]
fn tree_opp_batch_opens_the_reply_set_wide_on_the_first_batch() {
    let (mut sc, mut widened) = (Scratch::default(), 0usize);
    for path in [ACTS, WIDE] {
        let c = load_acts(path).unwrap_or_else(|e| panic!("{e}"));
        let per_act = act_statics(&c, REPO);
        for (ai, act) in c.acts.iter().enumerate() {
            let p = act.player;
            with_roll(&c, ai, &per_act[ai], |roll| {
                let (_, off, root_off) = run_opp(roll, &act.state, p, 0, &mut sc);
                let (_, narrow, _) = run_opp(roll, &act.state, p, BATCH, &mut sc);
                let (_, on, root_on) = run_opp(roll, &act.state, p, OPP_BATCH, &mut sc);
                // Identity: `opp_batch` 0 and `batch` are the same narrow search.
                assert_eq!(off, narrow, "{path} act {ai}: tree_opp_batch 0 parted from batch");
                let off_max = widest_opp_batch(&root_off, p);
                let on_max = widest_opp_batch(&root_on, p);
                assert!(off_max <= BATCH, "{path} act {ai}: off opened an opponent node wider than batch ({off_max})");
                if on_max >= OPP_BATCH {
                    assert!(on.batches < off.batches,
                        "{path} act {ai}: a wide first batch did not cut the batch count ({on:?} vs {off:?})");
                    widened += 1;
                }
            });
        }
    }
    assert!(widened > 0, "no fixture opened an opponent node's first batch to tree_opp_batch");
}

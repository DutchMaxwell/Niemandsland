//! The TREE operator — a recursive search over one activation, behind the
//! default-off tree search knob. This file is its skeleton: the node model
//! and the activation walk; leaves, chance edges, expansion and selection
//! land on top of it.

use crate::menu::Candidate;
use crate::playout::other_player;
use crate::rollout::{
    cross_round, delayed_action_passer, imagined_round_end, reinforcement_round_start,
    spawn_round_start, Rollout,
};
use crate::state::State;

/// One decision node: `mover` picks among `children`, opened in order
/// (`next_child` is the first unopened one). `n` visits and `w` summed
/// value in the searcher's frame; `terminal` holds the referee's value when
/// the node is a reached game end.
pub struct Node {
    pub state: State,
    pub mover: i64,
    pub children: Vec<Child>,
    pub next_child: usize,
    pub n: u32,
    pub w: f64,
    pub terminal: Option<f64>,
}

/// One edge out of a decision node; `node` is built when the edge is opened.
pub struct Child {
    pub cand: Candidate,
    pub node: Option<Box<Node>>,
}

/// What the walk found: the side that moves next, or the game's end.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    Mover(i64),
    Terminal,
}

/// `rollout_traced`'s alternation (rollout.rs:378-411) from `turn` on, up to
/// the next decision: the Delayed Action pass, the dry-side hand-off, and at
/// "both dry" the booked round end, then the game end or the next round's
/// start beats. The caller resolves the mover's pick, applies
/// `Rollout::coordinate_hand_off` (rollout.rs:419-423) and passes the turn
/// on with `other_player` — the rollout's own order.
///
/// Two deliberate departures, both outside the rule path: no tail cap and no
/// horizon (the tree walks to the real game end), and no guard (every round
/// crossing moves `round` towards `rounds_total`). "Dry" is "no unit may
/// activate", where the rollout asks `policy_step`; the two differ only on a
/// menu whose every score is NaN or -inf. `ends` collects each round-end
/// snapshot, as `rollout_traced` does.
pub fn advance(roll: &Rollout, cur: &mut State, mut turn: i64,
               mut ends: Option<&mut Vec<State>>) -> Step {
    let (statics, terrain, seams) = (roll.policy.statics, roll.policy.terrain, roll.policy.seams);
    let can_move = |st: &State, p: i64| (0..st.units()).any(|i| st.can_activate(i, p, seams.hero_attach));
    loop {
        if let Some(pi) = delayed_action_passer(statics, cur, turn, seams) {
            cur.delayed_action_round[pi] = cur.round;
            turn = other_player(cur, turn);
            continue;
        }
        if can_move(cur, turn) {
            return Step::Mover(turn);
        }
        turn = other_player(cur, turn);
        if can_move(cur, turn) {
            return Step::Mover(turn);
        }
        if roll.knobs.imagined_round_end {
            imagined_round_end(cur);
        }
        if let Some(e) = ends.as_deref_mut() {
            e.push(cur.clone());
        }
        if cur.round >= cur.rounds_total {
            return Step::Terminal;
        }
        turn = cross_round(statics, cur);
        reinforcement_round_start(statics, terrain, seams, cur);
        spawn_round_start(statics, terrain, seams, cur);
    }
}

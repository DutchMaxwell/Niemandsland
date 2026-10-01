//! The TREE operator — a recursive search over one activation, behind the
//! default-off tree search knob. This file is its skeleton: the node model
//! and the activation walk; leaves, chance edges, expansion and selection
//! land on top of it.

use serde_json::Value;

use crate::acts::{TreeDice, TreeLeaf};
use crate::arbitration::adjudicate_end;
use crate::dice::Tray;
use crate::menu::{candidates_tuned, Candidate};
use crate::mission::vp_of;
use crate::plan::{rank, ScoredRow};
use crate::playout::other_player;
use crate::rng::GodotRng;
use crate::score::score_with;
use crate::rollout::{
    cross_round, delayed_action_passer, imagined_round_end, reinforcement_round_start,
    spawn_round_start, Rollout,
};
use crate::sim::{reply_threat, resolve_stochastic_tray_on_board, Scratch, Unsupported};
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

/// One edge out of a decision node: `idx` is the row's build index in the
/// node's menu, `nodes` one per chance sample (one under EV), empty until
/// the edge is opened.
pub struct Child {
    pub idx: usize,
    pub cand: Candidate,
    pub nodes: Vec<Node>,
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

impl Node {
    /// A node where `advance` stopped with `step`; a reached game end is
    /// priced ONCE, here, by the referee for the searching `player`.
    pub fn new(state: State, step: Step, player: i64) -> Node {
        let (mover, terminal) = match step {
            Step::Mover(m) => (m, None),
            Step::Terminal => (0, Some(referee(&state, player))),
        };
        Node { state, mover, children: Vec::new(), next_child: 0, n: 0, w: 0.0, terminal }
    }
}

/// `player`'s legal rows, flat: every unit that may activate in capture
/// order, its menu in build order — the prefilter's rule (plan.rs
/// `prefilter`), a SHAKEN unit offering its recovery hold only.
pub fn menu(roll: &Rollout, state: &State, player: i64, sc: &mut Scratch) -> Vec<Candidate> {
    let p = &roll.policy;
    let mut out = Vec::new();
    for i in (0..state.units()).filter(|&i| state.can_activate(i, player, p.seams.hero_attach)) {
        if state.shaken[i] {
            out.push(Candidate::hold(state.key(i)));
        } else {
            out.extend(candidates_tuned(state, p.terrain, p.statics, i, sc, p.tuning));
        }
    }
    out
}

/// The referee at a reached game end (`adjudicate_end`, the `full_playout`
/// verdict) for `player`: win 1, draw 0.5, loss 0. It reads the marker
/// owners and the VP ledger the walk's last round end booked into the state.
pub fn referee(state: &State, player: i64) -> f64 {
    let owners: Vec<i64> = state.objectives.iter().map(|o| o.owner).collect();
    let flavour = state.vp_flavour.as_deref().cloned().unwrap_or(Value::Null);
    let r = adjudicate_end(&state.scoring, &owners, vp_of(state.vp.as_deref()), &flavour, state, state.round);
    match (r.winner, player) {
        ("draw", _) => 0.5,
        ("p1", 1) | ("p2", 2) => 1.0,
        _ => 0.0,
    }
}

/// One uniform-random playout from `state` (`mover` to act) to the game end,
/// priced by the referee for `player`: every activation draws one of the
/// mover's flat `menu` rows uniformly off `rng` (never the greedy tail) and
/// resolves it with the EV transition. Also returns the most activations any
/// one round took; past the arbitration tail's backstop (`units * 2 + 4`,
/// arbitration.rs `playout_round_tail`) the state is priced as it stands.
pub fn playout(roll: &Rollout, state: &State, mover: i64, player: i64, rng: &mut GodotRng,
               sc: &mut Scratch) -> Result<(f64, usize), Unsupported> {
    let (mut cur, mut turn) = (state.clone(), mover);
    let (cap, mut round, mut steps, mut most) = (state.units() * 2 + 4, state.round, 0usize, 0usize);
    while let Step::Mover(t) = advance(roll, &mut cur, turn, None) {
        if cur.round != round {
            (round, steps) = (cur.round, 0);
        }
        steps += 1;
        most = most.max(steps);
        if steps > cap {
            break;
        }
        let rows = menu(roll, &cur, t, sc);
        let a = &rows[rng.randi_range(0, rows.len() as i64 - 1) as usize];
        cur = roll.policy.resolve(&cur, a)?;
        roll.coordinate_hand_off(&mut cur, a, player, sc)?;
        turn = other_player(&cur, t);
    }
    Ok((referee(&cur, player), most))
}

/// A frontier node's value for the searching `player`. A reached game end is
/// the referee's in both modes. Otherwise `Blend` is the one-ply's own leaf,
/// `blend_score_leaf` over this one state (`vals`: its hook value from the
/// caller's one batch per expansion, empty = the hand leaf untouched), and
/// `Terminal` is one uniform playout to the end.
#[allow(clippy::too_many_arguments)]
pub fn leaf_value(roll: &Rollout, node: &Node, mode: TreeLeaf, player: i64, opener_seat: bool,
                  vals: &[f64], w: f64, rng: &mut GodotRng, sc: &mut Scratch) -> Result<f64, Unsupported> {
    if let Some(v) = node.terminal {
        return Ok(v);
    }
    match mode {
        TreeLeaf::Blend => Ok(roll.blend_score_leaf(std::slice::from_ref(&node.state), player, opener_seat, vals, w)),
        TreeLeaf::Terminal => Ok(playout(roll, &node.state, node.mover, player, rng, sc)?.0),
    }
}

/// Sample `k` of a chance edge draws `Rng(base + k)` and `Tray(base + k +
/// TRAY_OFFSET)` — the S2 continuation layout.
pub const TRAY_OFFSET: i64 = 50_000;

/// A chance edge: the states `cand` leads to from `state`. `Ev` is ONE
/// state, the EV transition (`Policy::resolve`) bit for bit. `Tray` is
/// `samples` states through the TRUE tray path
/// (`resolve_stochastic_tray_on_board`, never the remainder coin of
/// `resolve_stochastic_on_board_reach`). `base` is the NODE's stream, not the
/// edge's, so sibling edges roll the same dice (common random numbers). A
/// sample the tray path flags `unported` declines by the flag's name, and
/// `Tray` without a stream seed declines rather than invent one.
pub fn transition(roll: &Rollout, state: &State, cand: &Candidate, dice: TreeDice, samples: usize,
                  base: Option<i64>) -> Result<Vec<State>, Unsupported> {
    if dice == TreeDice::Ev {
        return Ok(vec![roll.policy.resolve(state, cand)?]);
    }
    let base = base.ok_or(Unsupported::TreeDiceSeed)?;
    let (p, action) = (&roll.policy, cand.action());
    (0..samples as i64)
        .map(|k| {
            let mut rng = GodotRng::new(base.wrapping_add(k));
            let mut tray = Tray::seeded(base.wrapping_add(k + TRAY_OFFSET));
            let (next, shot) =
                resolve_stochastic_tray_on_board(p.statics, state, &action, p.terrain, p.seams, &mut rng, &mut tray)?;
            match shot.unported.first() {
                Some(&what) => Err(Unsupported::TreeUnported(what)),
                None => Ok(next),
            }
        })
        .collect()
}

/// `player`'s rows at `state`, each resolved once (EV) and scored by the
/// prefilter's own 1-ply rule (plan.rs `prefilter`: `score_with` with the
/// reply threat, for the side that acts), with `rank`'s order: score desc,
/// build index on ties.
pub fn ranked(roll: &Rollout, state: &State, player: i64, sc: &mut Scratch)
              -> Result<(Vec<ScoredRow>, Vec<usize>), Unsupported> {
    let (statics, fit) = (roll.policy.statics, roll.policy.fit);
    let mut rows = Vec::new();
    for cand in menu(roll, state, player, sc) {
        let next = roll.policy.resolve(state, &cand)?;
        let score = score_with(&next, statics, player, &reply_threat(statics, &next, player), fit);
        rows.push(ScoredRow { idx: rows.len(), unit_key: cand.unit.clone(), cand, score });
    }
    let order = rank(&rows, true);
    Ok((rows, order))
}

/// The ROOT's children: the one-ply's prefilter rows, its rolled `pool`
/// first in pool order, then the rest of its ranked `order`. The hand order
/// ORDERS, it never cuts: every row is a child.
pub fn root_children(rows: &[ScoredRow], order: &[usize], pool: &[usize]) -> Vec<Child> {
    let rest = order.iter().filter(|i| !pool.contains(i));
    pool.iter().chain(rest).map(|&i| Child { idx: i, cand: rows[i].cand.clone(), nodes: Vec::new() }).collect()
}

/// Opens up to `k` more of `node`'s children, in order (progressive
/// widening: an opened child is never touched again, none is removed); a
/// node below the root builds its children from `ranked` for its mover on
/// its first expansion. An opened child gets one node per `transition`
/// state: the Coordinate hand-off, then `advance` to the next decision, a
/// game end priced by the referee for `player`. Returns how many opened.
#[allow(clippy::too_many_arguments)]
pub fn expand(roll: &Rollout, node: &mut Node, k: usize, dice: TreeDice, samples: usize, base: Option<i64>,
              player: i64, sc: &mut Scratch) -> Result<usize, Unsupported> {
    if node.terminal.is_some() {
        return Ok(0);
    }
    if node.children.is_empty() {
        let (rows, order) = ranked(roll, &node.state, node.mover, sc)?;
        node.children = root_children(&rows, &order, &[]);
    }
    let (from, to) = (node.next_child, (node.next_child + k).min(node.children.len()));
    for c in from..to {
        let cand = node.children[c].cand.clone();
        for mut cur in transition(roll, &node.state, &cand, dice, samples, base)? {
            roll.coordinate_hand_off(&mut cur, &cand, player, sc)?;
            let turn = other_player(&cur, node.mover);
            let step = advance(roll, &mut cur, turn, None);
            node.children[c].nodes.push(Node::new(cur, step, player));
        }
    }
    node.next_child = to;
    Ok(to - from)
}

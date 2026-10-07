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
use crate::plan::{rank, LeafValue, ScoredRow};
use crate::playout::other_player;
use crate::rng::GodotRng;
use crate::score::score_with;
use crate::rollout::{
    cross_round, delayed_action_passer, imagined_round_end, reinforcement_round_start,
    spawn_round_start, Rollout,
};
use crate::sim::{reply_threat_opts, resolve_stochastic_tray_on_board, Scratch, Unsupported};
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
        let first_dry = roll.knobs.opener_by_finish.then(|| other_player(cur, turn));
        turn = cross_round(statics, cur, first_dry);
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
/// resolves it with the EV transition — or, with `tray_base`, through the TRUE
/// tray path off `Rng(tray_base)` / `Tray(tray_base + TRAY_OFFSET)`, an
/// unported branch declining by name. Also returns the most activations any
/// one round took; past the arbitration tail's backstop (`units * 2 + 4`,
/// arbitration.rs `playout_round_tail`) the state is priced as it stands.
pub fn playout(roll: &Rollout, state: &State, mover: i64, player: i64, rng: &mut GodotRng,
               tray_base: Option<i64>, sc: &mut Scratch) -> Result<(f64, usize), Unsupported> {
    let mut dice = tray_base.map(|b| (GodotRng::new(b), Tray::seeded(b.wrapping_add(TRAY_OFFSET))));
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
        cur = match dice.as_mut() {
            None => roll.policy.resolve(&cur, a)?,
            Some((r, t)) => {
                let p = &roll.policy;
                let (next, shot) = resolve_stochastic_tray_on_board(p.statics, &cur, &a.action(), p.terrain, p.seams, r, t)?;
                if let Some(&what) = shot.unported.first() {
                    return Err(Unsupported::TreeUnported(what));
                }
                next
            }
        };
        roll.coordinate_hand_off(&mut cur, a, player, sc)?;
        turn = other_player(&cur, t);
    }
    Ok((referee(&cur, player), most))
}

/// A frontier node's value for the searching `player`. A reached game end is
/// the referee's in both modes. Otherwise `Blend` is the one-ply's own leaf,
/// `blend_score_leaf` over this one state (`vals`: its hook value from the
/// caller's one batch per expansion, empty = the hand leaf untouched), and
/// `Terminal` is one uniform playout to the end (through the tray from
/// `tray_base`, the node's own stream base, under `TreeDice::Tray`).
#[allow(clippy::too_many_arguments)]
pub fn leaf_value(roll: &Rollout, node: &Node, mode: TreeLeaf, player: i64, opener_seat: bool,
                  vals: &[f64], w: f64, rng: &mut GodotRng, tray_base: Option<i64>, sc: &mut Scratch)
                  -> Result<f64, Unsupported> {
    if let Some(v) = node.terminal {
        return Ok(v);
    }
    match mode {
        TreeLeaf::Blend => Ok(roll.blend_score_leaf(std::slice::from_ref(&node.state), player, opener_seat, vals, w)),
        TreeLeaf::Terminal => Ok(playout(roll, &node.state, node.mover, player, rng, tray_base, sc)?.0),
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
        let score = score_with(&next, statics, player, &reply_threat_opts(statics, &next, player, roll.policy.seams.reply_opts()), fit);
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

/// UCT's exploration constant — the pilot's starting point (plan D-T2).
pub const UCT_C: f64 = 0.5;

/// One tree search's settings: the tree knobs resolved, plus the searcher.
#[derive(Clone, Copy)]
pub struct TreeCfg<'a> {
    pub leaf: TreeLeaf,
    pub dice: TreeDice,
    pub samples: usize,
    pub batch: usize,
    pub budget: usize,
    /// The wall-clock SAFETY fallback in ms (0 = off), checked between
    /// expansion batches; the budget stays the leaf count.
    pub wall_ms: u64,
    /// The `deadline_us` instant (None = off), checked before EVERY batch,
    /// the first included.
    pub deadline: Option<std::time::Instant>,
    /// The widening rate: 0.0 opens every child of a node before the search
    /// descends; > 0 keeps at most ceil(max(n, 1) ^ widen) of an n-visit
    /// node's children open.
    pub widen: f64,
    pub player: i64,
    pub opener_seat: bool,
    /// The chance streams' root seed (the playout signature); `None`
    /// declines under `Tray`.
    pub sig: Option<i64>,
    pub hook: Option<&'a dyn LeafValue>,
    pub w: f64,
}

/// Leaf evaluations completed, the wall-clock stamp, every opened root
/// child as (build idx, visits, mean), and the deadline fallback that
/// answered when no batch completed (`None` = the search picked).
#[derive(Debug, Clone, PartialEq)]
pub struct TreeTrace {
    pub completed: usize,
    pub deadline_hit: bool,
    pub root: Vec<(usize, u32, f64)>,
    pub fallback: Option<&'static str>,
    /// Search iterations that valued something: an expansion batch, or a game end revisited.
    pub batches: usize,
    /// Leaf evaluations of a non-terminal state; `frontier + terminal == completed`.
    pub frontier: usize,
    /// Leaf evaluations of a game end, priced by the referee.
    pub terminal: usize,
    /// Microseconds from the planner call to the pick (`Search::run`); 0 from a bare `run`.
    pub elapsed_us: u64,
    /// `deadline_after_preselect`: microseconds of the root preselection before the
    /// search clock started — `Some` ONLY when that knob is on (set by `Search::run`).
    pub preselect_us: Option<u64>,
}

/// A child's mean over its sample nodes (equally likely chance outcomes)
/// and its visits.
fn child_stat(c: &Child) -> (f64, u32) {
    let n = c.nodes.iter().map(|x| x.n).sum();
    let seen = c.nodes.iter().filter(|x| x.n > 0);
    (seen.clone().map(|x| x.w / x.n as f64).sum::<f64>() / seen.count().max(1) as f64, n)
}

/// UCT in the searcher's frame: the searcher's nodes take the argmax of
/// `mean + c * sqrt(ln N / n)`, the opponent's the argmin of `mean - ...`,
/// over the OPENED children; ties keep the first child in order.
pub fn select(node: &Node, player: i64) -> usize {
    let (sign, ln_n) = (if node.mover == player { 1.0 } else { -1.0 }, (node.n.max(1) as f64).ln());
    let mut best = (0, f64::NEG_INFINITY);
    for (i, c) in node.children[..node.next_child].iter().enumerate() {
        let (mean, n) = child_stat(c);
        let u = sign * mean + UCT_C * (ln_n / n.max(1) as f64).sqrt();
        if u > best.1 {
            best = (i, u);
        }
    }
    best.0
}

/// The stream base of a node's sample node `slot` (= child * samples + sample).
fn child_base(base: Option<i64>, slot: usize) -> Option<i64> {
    base.map(|b| b.wrapping_mul(1_000_003).wrapping_add((slot + 1) as i64))
}

/// The tree search from `root` (its children set, e.g. by `root_children`).
/// Each iteration selects by UCT from the root down to a node with unopened
/// children or a game end (sample nodes least-visited first), opens up to
/// `batch` children there, values the new leaves with ONE hook call, and
/// adds them to every node on the path. It stops once `budget` leaf
/// evaluations completed; a chance child's samples are never split, so the
/// last batch may overshoot by fewer than `samples`. Every child of a node
/// is opened before the search descends below it, unless `widen` caps the
/// open children (progressive widening). Streams: the root's base is `sig`, a sample node's base
/// derives from its parent's and its (child, sample) index (`child_base`). The
/// Terminal playouts resolve with EV under `Ev` and through the tray off the
/// leaf node's own stream base under `Tray`. The pick is the opened root
/// child with the highest mean, the first in order on ties.
pub fn run(roll: &Rollout, cfg: &TreeCfg, root: &mut Node, rng: &mut GodotRng, sc: &mut Scratch)
           -> Result<(usize, TreeTrace), Unsupported> {
    let per_child = if cfg.dice == TreeDice::Tray { cfg.samples } else { 1 };
    // Progressive widening: how many of a node's children may be open. Off
    // (0.0), every child opens before the search descends.
    let cap = |x: &Node| {
        if cfg.widen > 0.0 { f64::from(x.n.max(1)).powf(cfg.widen).ceil() as usize } else { usize::MAX }
    };
    let (start, mut completed, mut deadline_hit) = (std::time::Instant::now(), 0, false);
    let (mut batches, mut frontier, mut terminal) = (0, 0, 0);
    while completed < cfg.budget {
        if cfg.deadline.is_some_and(|d| std::time::Instant::now() >= d) {
            deadline_hit = true;
            break;
        }
        // The wall is a SAFETY fallback between batches, never the budget:
        // the first batch always completes, so there is a pick to stamp.
        if cfg.wall_ms > 0 && completed > 0 && start.elapsed().as_millis() >= u128::from(cfg.wall_ms) {
            deadline_hit = true;
            break;
        }
        let (mut node, mut path, mut base) = (&mut *root, Vec::new(), cfg.sig);
        while node.terminal.is_none() && !node.children.is_empty() && node.next_child >= node.children.len().min(cap(node)) {
            let c = select(node, cfg.player);
            let s = (0..node.children[c].nodes.len()).min_by_key(|&s| node.children[c].nodes[s].n).unwrap_or(0);
            base = child_base(base, c * per_child + s);
            path.push((c, s));
            node = &mut node.children[c].nodes[s];
        }
        let mut vals = Vec::new();
        if let Some(v) = node.terminal {
            vals.push(v);
            terminal += 1;
        } else {
            let from = node.next_child;
            let k = cfg.batch.min((cfg.budget - completed).div_ceil(per_child)).min(cap(node) - from);
            expand(roll, node, k, cfg.dice, cfg.samples, base, cfg.player, sc)?;
            let fresh = || node.children[from..node.next_child].iter().flat_map(|c| &c.nodes);
            let states: Vec<&State> = fresh().filter(|x| x.terminal.is_none()).map(|x| &x.state).collect();
            let hv = match cfg.hook.filter(|_| cfg.leaf == TreeLeaf::Blend && cfg.w != 0.0) {
                Some(h) => h.value(&states, cfg.player)?,
                None => Vec::new(),
            };
            if !hv.is_empty() && hv.len() != states.len() {
                return Err(Unsupported::LeafValue(hv.len(), states.len()));
            }
            let mut j = 0;
            for c in from..node.next_child {
                for (s, x) in node.children[c].nodes.iter_mut().enumerate() {
                    let own = if hv.is_empty() || x.terminal.is_some() { &[][..] } else { j += 1; &hv[j - 1..j] };
                    let tb = if cfg.dice == TreeDice::Tray { child_base(base, c * per_child + s) } else { None };
                    let v = leaf_value(roll, x, cfg.leaf, cfg.player, cfg.opener_seat, own, cfg.w, rng, tb, sc)?;
                    (x.n, x.w) = (1, v);
                    vals.push(v);
                    if x.terminal.is_some() { terminal += 1 } else { frontier += 1 }
                }
            }
        }
        if vals.is_empty() {
            break;
        }
        batches += 1;
        let (cnt, sum) = (vals.len() as u32, vals.iter().sum::<f64>());
        let mut cur = &mut *root;
        (cur.n, cur.w) = (cur.n + cnt, cur.w + sum);
        for &(c, s) in &path {
            cur = &mut cur.children[c].nodes[s];
            (cur.n, cur.w) = (cur.n + cnt, cur.w + sum);
        }
        completed += vals.len();
    }
    let (mut best, mut trace) = ((0, f64::NEG_INFINITY), Vec::new());
    for (i, c) in root.children[..root.next_child].iter().enumerate() {
        let (mean, n) = child_stat(c);
        trace.push((c.idx, n, mean));
        if n > 0 && mean > best.1 {
            best = (i, mean);
        }
    }
    Ok((best.0, TreeTrace { completed, deadline_hit, root: trace, fallback: None, batches, frontier, terminal, elapsed_us: 0,
                            preselect_us: None }))
}

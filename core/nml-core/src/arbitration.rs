//! The PLAYOUT ARBITRATION — `AiPlanner.full_playout` (ai_planner.gd:1338-1417),
//! `_playout_round_tail` (:1431-1449), `_playout_pick` (:1452-1458) and the
//! escalation loop inside `plan_with_rollout` (:231-265).
//!
//! What it is, in one line: when the 1-ply-plus-rollout blend cannot separate
//! the top two candidates, the planner stops JUDGING and PLAYS — it runs both
//! branches to the end of the game under the cheap policy, three times each,
//! and lets the marker delta decide. It escalates by two while the two branches
//! stay within `PLAYOUT_DECIDE_MARGIN` of each other, up to `PLAYOUT_CAP`.
//!
//! What makes this the hardest thing in the port to mirror: it is the ONLY
//! stochastic path in the search. Every playout activation goes through
//! `BattleSim.resolve_stochastic`, whose only difference from `resolve` is that
//! `_apply_expected_wounds` spends the sub-wound remainder on a `randf()` coin
//! flip instead of carrying it. So a single mis-ordered draw does not perturb a
//! number — it changes which models die, which changes the next pick, which
//! changes the rest of the game. `rng.rs` therefore had to be exact BEFORE any
//! of this could be checked at all.
//!
//! THE SIGNATURE IS AN INPUT, NOT A PORT. `_playout_sig` (:1305-1307) is
//! `hash("%d:%d:%s" % [round, player, str(BattleSim.board_rows(state))])` — a
//! Godot String hash over Godot's own float formatting of the whole board. That
//! is engine text formatting, not rules, and guessing it would put a silent
//! approximation underneath every seed. The recorder writes the value it used
//! into `trace.arbitration.sig`; this module takes it as an argument, and a
//! caller without one declines instead of inventing a stream.

use serde_json::Value;

use crate::menu::Candidate;
use crate::mission::{
    apply_destroy_step, playout_seize, sabotage_winner, vp_of, vp_score_end, vp_score_round,
};
use crate::rng::GodotRng;
use crate::rollout::{round_start_refresh, Rollout};
use crate::sim::{resolve_stochastic_on_board, Scratch, Unsupported};
use crate::state::State;

/// `AiPlanner.PLAYOUT_MAX_ROUNDS` ai_planner.gd:1310 — INSURANCE, not a rule:
/// a nonsense `rounds_total` must not hang the arena. Real missions run 4-6.
pub const PLAYOUT_MAX_ROUNDS: i64 = 12;
/// `AiPlanner.PLAYOUT_DECIDE_MARGIN` ai_planner.gd:87 — the mean marker delta
/// that settles a close call and stops the escalation.
pub const PLAYOUT_DECIDE_MARGIN: f64 = 0.5;
/// `AiPlanner.PLAYOUT_CAP` ai_planner.gd:88 — max playouts per branch.
pub const PLAYOUT_CAP: i64 = 7;

/// TEST SEAMS. Every shipping call uses `ArbBend::default()`, which is the
/// GDScript. Each field turns ONE load-bearing decision off so a red proof can
/// COUNT how many arbitrations it moves instead of asserting green and hoping.
#[derive(Debug, Clone, Copy)]
pub struct ArbBend {
    /// `AiPlanner.PLAYOUT_DECIDE_MARGIN`. Lowering it stops the escalation
    /// earlier and changes `n` — and, through the shorter sums, the verdict.
    pub decide_margin: f64,
    /// `false` resolves every playout activation with `BattleSim.resolve`'s
    /// CARRY rounding instead of `resolve_stochastic`'s coin flip: the dice are
    /// never drawn, so the two branches play the same deterministic game.
    pub stochastic_wounds: bool,
}

impl Default for ArbBend {
    fn default() -> Self {
        ArbBend { decide_margin: PLAYOUT_DECIDE_MARGIN, stochastic_wounds: true }
    }
}

/// `full_playout`'s return dictionary (ai_planner.gd:1412-1417), in the ARENA's
/// vocabulary so a played-out game and a real `tools/arena_match.gd` game are a
/// direct comparison.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlayoutResult {
    /// Mission-currency points — final markers, or the VP ledger under
    /// `round_vp`, or the 1/0 sabotage verdict. THIS is what the search reads.
    pub p1: i64,
    pub p2: i64,
    /// The full VP ledger including the book's end bonus.
    pub vp: [i64; 2],
    /// Final marker owners: (p1, p2, neutral).
    pub objectives: (i64, i64, i64),
    /// Living models per side at game end.
    pub survivors: [i64; 2],
    pub rounds_played: i64,
    pub winner: &'static str,
}

/// What the escalation loop decided — `trace.arbitration` (ai_planner.gd:263-264).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Arbitration {
    /// `done`: playouts run PER BRANCH (3, 5 or 7), not the total.
    pub n: i64,
    pub sum_b: f64,
    pub sum_r: f64,
    /// `sum_r > sum_b` — the runner-up took the pick.
    pub swapped: bool,
}

fn other(turn: i64) -> i64 {
    // ai_planner.gd:1444/1466 — the literal `2 if turn == 1 else 1`, NOT
    // `_other_player`: the tail alternates between the two SEAT IDS, and a seat
    // with no unit left on the board still gets its (empty) turn.
    if turn == 1 {
        2
    } else {
        1
    }
}

/// `AiPlanner._playout_pick` ai_planner.gd:1452-1458 — the next cheap-policy
/// move of `player`, or `None` when the side has no un-activated living unit.
///
/// The GDScript scans for the FIRST eligible unit and then hands the whole side
/// to `_policy_step`; the scan is a dry-side test, not a unit choice.
fn playout_pick(
    roll: &Rollout,
    state: &State,
    player: i64,
    sc: &mut Scratch,
) -> Result<Option<Candidate>, Unsupported> {
    for i in 0..state.units() {
        if state.player[i] == player && !state.activated[i] && state.alive[i] > 0 {
            // BOTH sides step with `playout_rich()` here — unlike `rollout.rs`,
            // which splits rich/cheap by seat (R9). Same brain for both branches
            // keeps the comparison fair (ai_planner.gd:72-74).
            return roll.policy.policy_step(state, player, roll.knobs.playout_rich, sc);
        }
    }
    Ok(None)
}

/// `AiPlanner._playout_round_tail` ai_planner.gd:1431-1449 — cheap-policy
/// alternation until the round runs dry. A dry side passes the tail to the
/// other. Returns the state and `last`, the seat that moved LAST (0 = nobody).
fn playout_round_tail(
    roll: &Rollout,
    mut state: State,
    mut turn: i64,
    rng: &mut GodotRng,
    bend: ArbBend,
    sc: &mut Scratch,
) -> Result<(State, i64), Unsupported> {
    let mut last = 0i64;
    // Evaluated ONCE, on the state the tail STARTS from (:1434).
    let mut guard = state.units() as i64 * 2 + 4;
    while guard > 0 {
        guard -= 1;
        let mut a = playout_pick(roll, &state, turn, sc)?;
        if a.is_none() {
            let o = other(turn);
            a = playout_pick(roll, &state, o, sc)?;
            if a.is_none() {
                break;
            }
            turn = o;
        }
        let a = a.expect("the dry branch breaks above");
        state = resolve_stochastic(roll, &state, &a, rng, bend)?;
        last = turn;
        turn = other(turn);
    }
    Ok((state, last))
}

fn resolve_stochastic(
    roll: &Rollout,
    state: &State,
    c: &Candidate,
    rng: &mut GodotRng,
    bend: ArbBend,
) -> Result<State, Unsupported> {
    if !bend.stochastic_wounds {
        return roll.policy.resolve(state, c); // RED PROOF ONLY — no draw at all
    }
    resolve_stochastic_on_board(
        roll.policy.statics,
        state,
        &c.action(),
        roll.policy.terrain,
        roll.policy.seams,
        rng,
    )
}

/// `AiPlanner.full_playout` ai_planner.gd:1338-1417 — play ONE branch to game
/// end under the cheap policy and report it in the arena's vocabulary.
///
/// Four parity traps live here:
///   * `owners` is built ONCE from `state0` and carried through every round; it
///     is NOT re-read from the state at each boundary (which is what
///     `rollout.rs::imagined_round_end` does for its single round);
///   * the next round's OPENER comes from `last` (the seat that moved last), not
///     from `cross_round`'s fewer-units rule — a playout never crosses a round
///     the way a rollout does;
///   * `rounds_total` is clamped by `round0 + PLAYOUT_MAX_ROUNDS - 1`, and
///     `rounds_played` is `maxi(rounds_total, round0)`, so a game already past
///     its last round still reports the round it stood in;
///   * `_round_start_refresh` runs on EVERY unit of both sides, with no opener
///     recomputation and no `reset_round_mods` — an imagined round inherits the
///     last one's spell modifiers, exactly as the shipped rollout does.
pub fn full_playout(
    roll: &Rollout,
    state0: &State,
    action: &Candidate,
    player: i64,
    rng: &mut GodotRng,
    sc: &mut Scratch,
) -> Result<PlayoutResult, Unsupported> {
    full_playout_bent(roll, state0, action, player, rng, ArbBend::default(), sc)
}

/// The same playout with the red-proof seams exposed.
#[allow(clippy::too_many_arguments)]
pub fn full_playout_bent(
    roll: &Rollout,
    state0: &State,
    action: &Candidate,
    player: i64,
    rng: &mut GodotRng,
    bend: ArbBend,
    sc: &mut Scratch,
) -> Result<PlayoutResult, Unsupported> {
    let mut owners: Vec<i64> = state0.objectives.iter().map(|o| o.owner).collect();
    let mut state = resolve_stochastic(roll, state0, action, rng, bend)?;
    let turn = other(player);
    // The playout continues the LIVE ledger: a playout that counts only
    // remaining-round VP can call an already-won game lost (NML-1010 W2).
    let mut vp = vp_of(state0.vp.as_deref());
    let flavour: Value = state0.vp_flavour.as_deref().cloned().unwrap_or(Value::Null);
    let mut memo = state0
        .vp_memo
        .as_deref()
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();

    let (s, last) = playout_round_tail(roll, state, turn, rng, bend, sc)?;
    state = s;
    let mut opener = if last != 0 { other(last) } else { turn };
    book_round_end(&mut state, &mut owners, &mut vp, &flavour, &mut memo);

    let round0 = state0.round;
    let rounds_total = state.rounds_total.min(round0 + PLAYOUT_MAX_ROUNDS - 1);
    for r in (round0 + 1)..=rounds_total {
        state.round = r;
        for k in 0..state.units() {
            round_start_refresh(roll.policy.statics, &mut state, k);
        }
        let (s, last) = playout_round_tail(roll, state, opener, rng, bend, sc)?;
        state = s;
        if last != 0 {
            opener = other(last);
        }
        book_round_end(&mut state, &mut owners, &mut vp, &flavour, &mut memo);
    }
    // Face-Off is END-scored per book: the ledger is always closed out, but
    // WHICH currency decides is the mission's business (:1394-1399).
    vp_score_end(&owners, &mut vp, &flavour);

    let (mut p1, mut p2) = (0i64, 0i64);
    for &o in &owners {
        if o == 1 {
            p1 += 1;
        } else if o == 2 {
            p2 += 1;
        }
    }
    let (mut alive1, mut alive2) = (0i64, 0i64);
    for k in 0..state.units() {
        if state.player[k] == 1 {
            alive1 += state.alive[k];
        } else if state.player[k] == 2 {
            alive2 += state.alive[k];
        }
    }
    let scoring: &str = &state0.scoring;
    let (mut pts1, mut pts2) = if scoring == "round_vp" { (vp[0], vp[1]) } else { (p1, p2) };
    if scoring == "sabotage" {
        // W3: the playout speaks sabotage's own goal — destroy theirs, keep yours.
        let sw = sabotage_winner(&state.markers_meta);
        pts1 = i64::from(sw == "p1");
        pts2 = i64::from(sw == "p2");
    }
    let winner = if pts1 != pts2 {
        if pts1 > pts2 {
            "p1"
        } else {
            "p2"
        }
    } else if owners.is_empty() && alive1 != alive2 {
        if alive1 > alive2 {
            "p1"
        } else {
            "p2"
        }
    } else {
        "draw"
    };
    Ok(PlayoutResult {
        p1: pts1,
        p2: pts2,
        vp,
        objectives: (p1, p2, owners.len() as i64 - p1 - p2),
        survivors: [alive1, alive2],
        rounds_played: rounds_total.max(round0),
        winner,
    })
}

/// The three calls every playout round end makes, in order (ai_planner.gd:
/// 1369-1372 and :1382-1385): seize from the final positions, the marker
/// destroy step, then the round's VP.
fn book_round_end(
    state: &mut State,
    owners: &mut [i64],
    vp: &mut [i64; 2],
    flavour: &Value,
    memo: &mut serde_json::Map<String, Value>,
) {
    playout_seize(state, owners);
    if !state.markers_meta.is_empty() {
        let mut markers = std::mem::take(&mut state.markers_meta);
        let mut seq = std::mem::take(&mut state.destroy_seq);
        apply_destroy_step(&mut markers, owners, &mut seq);
        state.markers_meta = markers;
        state.destroy_seq = seq;
    }
    // The GDScript's `vp`/`vp_memo` are LOCAL to `full_playout` and never written
    // back into the state, so nothing is stored on `state` here either.
    vp_score_round(owners, vp, flavour, memo, &state.markers_meta);
}

/// The escalation loop — ai_planner.gd:236-260. Three playouts per branch, then
/// +2 while the mean delta stays inside `PLAYOUT_DECIDE_MARGIN`, hard-capped at
/// `PLAYOUT_CAP`. The two branches get ADJACENT seeds off the same signature
/// (`sig*31 + i*2` and `+1`), so best and runner never share a dice stream.
///
/// `sum_b`/`sum_r` accumulate the SIGNED marker delta from `player`'s side:
/// `(p1 - p2) * (+1 for seat 1, -1 for seat 2)`.
pub fn arbitrate(
    roll: &Rollout,
    state: &State,
    best: &Candidate,
    runner: &Candidate,
    player: i64,
    sig: i64,
    sc: &mut Scratch,
) -> Result<Arbitration, Unsupported> {
    arbitrate_bent(roll, state, best, runner, player, sig, ArbBend::default(), sc)
}

/// The same escalation with the red-proof seams exposed.
#[allow(clippy::too_many_arguments)]
pub fn arbitrate_bent(
    roll: &Rollout,
    state: &State,
    best: &Candidate,
    runner: &Candidate,
    player: i64,
    sig: i64,
    bend: ArbBend,
    sc: &mut Scratch,
) -> Result<Arbitration, Unsupported> {
    let sign = if player == 1 { 1.0 } else { -1.0 };
    let mut n = 3i64;
    let mut sum_b = 0.0f64;
    let mut sum_r = 0.0f64;
    let mut done = 0i64;
    while n <= PLAYOUT_CAP {
        for i in done..n {
            let base = sig.wrapping_mul(31).wrapping_add(i.wrapping_mul(2));
            let mut rb = GodotRng::new(base);
            let pb = full_playout_bent(roll, state, best, player, &mut rb, bend, sc)?;
            sum_b += (pb.p1 - pb.p2) as f64 * sign;
            let mut rr = GodotRng::new(base.wrapping_add(1));
            let pr = full_playout_bent(roll, state, runner, player, &mut rr, bend, sc)?;
            sum_r += (pr.p1 - pr.p2) as f64 * sign;
        }
        done = n;
        if (sum_b - sum_r).abs() / (n as f64) >= bend.decide_margin {
            break;
        }
        n += 2;
    }
    Ok(Arbitration { n: done, sum_b, sum_r, swapped: sum_r > sum_b })
}

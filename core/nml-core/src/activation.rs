//! One-core P3: one activation as the ordered inputs the table sends, the
//! answers the core gives, the order rules on the inputs, and
//! `step_activation`, which resolves the activation through the step API.

use crate::acts::{rule_on, EPOCH_94_PARITY_BATCH};
use crate::dice::Tray;
use crate::gate::INCHES_TO_METERS;
use crate::io::{Action, Seams, SplitShot};
use crate::landing::Landing;
use crate::logline::{Category, LogLine};
use crate::mods::LiveMod;
use crate::mv::step::{leg_crosses, DIFFICULT_MOVE_CAP_IN};
use crate::mv::tier::{tier_crossings, TierKind};
use crate::rng::GodotRng;
use crate::sim::{band_parts, resolve_stochastic_tray_on_board, terrain_debuff_folds, Cover, ADVANCE, CHARGE, HOLD, REPOSITION, RUSH};
use crate::state::State;
use crate::step::{step_with, Step};
use crate::terrain::{is_difficult, Terrain};
use crate::unit::UnitStatic;

/// One thing the table tells the core during an activation, in order.
#[derive(Debug, Clone, PartialEq)]
pub enum Input {
    /// "Activate" on the unit's card starts the activation.
    Begin,
    /// The declared action (`sim::HOLD` ..); `shoot` is `Some` when it shoots. `split` is split fire's aim,
    /// per (member, weapon) the target key it fires at; `None` (or empty) = the one `shoot` target.
    /// `charge` is a `sim::CHARGE`'s target key (the core lands the charge with `charge_move`, then strikes).
    /// Step 20: `no_step` = the core takes no Hit & Run step after the attack (a human bearer's player drags it).
    Intent { kind: i64, shoot: Option<String>, split: Option<Vec<SplitShot>>, charge: Option<String>, no_step: bool },
    /// One thrown face group, in the order the core asked for them.
    Faces(Vec<u8>),
    /// The unit's model positions after a drag (`at`) and each model's walked path this
    /// activation (world XZ metres, in the order of `at`; empty = none).
    Placed { at: Vec<[f64; 3]>, trails: Vec<Vec<[f64; 2]>> },
    /// "Cancel", allowed until the first die of the activation.
    Cancel,
    /// P4.0-5: one answer to a `NeedChoice`, by the choice's stable `id` and an option id. An EMPTY
    /// `option` asks the core what it is waiting for: the next answer is `ActStep::NeedChoice`.
    /// A transcript without a `Choice` keeps the core's automatic pick (the default policy).
    Choice { id: String, option: String },
    /// CC-3: one planned cast, in plan order, after the `Intent` and before the first `Faces`. The core does not resolve it yet.
    Cast(CastInput),
    /// meleefix: one melee unit's consolidation inputs from the table's AI round planner (`ConsolidatePlan`); read from
    /// `EPOCH_96_PARITY_BATCH` on, ignored below it. Absent = the core's own goal.
    Consolidate(ConsolidatePlan),
    /// D-PAR3 14a: what the table already resolved this activation before it captured the core's board, so the core does
    /// not resolve it again: `start` = the activation-start triggers (Reanimation, Surprise Attack), `dangerous` = the move's
    /// Dangerous terrain test, `beats` = the pre-attack phase. Only directly after `Begin`.
    Paid { start: bool, dangerous: bool, beats: bool },
}

/// One push: the target unit's key, its model's slot (`state.positions` order) and where the attacker moves it. Step 29d
/// (D-29-R2): the attacker decides AFTER the dice, through the choices `push:<attacker>:<target>` (push | no) and
/// `push_to:<attacker>:<target>` (`<slot>:<x>,<y>,<z>`, world metres); a supplied `Tray::offer_push` is the same answer.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct PushInput { pub target: String, pub model: usize, pub to: [f64; 3] }

/// meleefix: what the table's goal for a melee winner's "may move up to 3 in" reads besides the board
/// (`SoloController.consolidate_after_melee_win` -> `_nearest_uncontrolled_objective`): whether the unit's side runs the
/// round planner (NML-210), the unit's task this round (`seize` with its marker index and lane spread, `fight`, or none) and
/// the greedy's inputs (the endgame spread switch and each objective's runner count, in objective order). The core reads the
/// board itself after the fight, so the goal is the table's for the state the winner really stands in.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ConsolidatePlan {
    pub unit: String,
    pub planner: bool,
    pub task: String,
    pub marker: i64,
    pub lane: bool,
    pub spread: bool,
    pub runners: Vec<i64>,
}

/// One planned cast: the planner's picks (spell, targets, boost and interference with their payers, the conduit, the
/// eligible interferers) and the table's readings (`base` = the caster's cast target, `once` = the book text's reading).
/// `seq` is the cast's 0-based ordinal in the activation (every choice id will carry it); the `*_sources` / `pools` lists
/// are `(unit key, tokens)` in spend order, `pools` per foe slot. `open`: the foe's owner may still interfere.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct CastInput {
    pub seq: i64,
    pub caster: String,
    pub spell: String,
    pub targets: Vec<String>,
    pub base: i64,
    pub threshold: i64,
    pub boost: i64,
    pub boost_sources: Vec<(String, i64)>,
    pub interference: i64,
    pub interference_sources: Vec<(String, i64)>,
    pub conduit: String,
    pub conduit_shaken: Vec<String>,
    pub pools: Vec<(i64, Vec<(String, i64)>)>,
    pub once: bool,
    pub open: bool,
}

/// The core's answer to the inputs so far. `Done` and `Cancelled` are the
/// two terminal states of an activation in the core.
#[derive(Debug)]
// One per step call, never stored in bulk: `State` by value (the plan's API) costs nothing here.
#[allow(clippy::large_enum_variant)]
pub enum ActStep {
    /// Roll `faces` dice and send them as the next `Faces`; `lines` and
    /// `landings` are only those before the starved draw. `owner` is the rolling unit's name (a label), `owner_key`
    /// its roster key (who rolls; "" when the core cannot tell, see `owner_key_of`).
    NeedRoll { index: usize, faces: usize, kind: &'static str, count: i64, target: i64, owner: String, owner_key: String, lines: Vec<LogLine>, landings: Vec<Landing> },
    /// The activation is open and waits for the next input.
    Open,
    /// P4.0-5 / CC-9a: the core needs one answer before it can resolve (`option: ""` asked). `id` and every
    /// option are stable ids (a target unit key and `slot:<n>` model slots, or `"0".."pool"` for interference),
    /// `owner` is the roster key of the unit whose side answers. `lines` and `landings` are only those before
    /// the choice point (cumulative, like `NeedRoll`). Answer with `Input::Choice { id, option }`.
    NeedChoice { id: String, options: Vec<String>, owner: String, lines: Vec<LogLine>, landings: Vec<Landing> },
    /// Input `index` breaks an order rule; `reason` is the sentence the player sees.
    Refused { index: usize, reason: String },
    /// The activation was cancelled before its first die; the state is untouched
    /// and the table puts the models back. `lines` is the one cancel sentence.
    Cancelled { lines: Vec<LogLine> },
    /// `unported`: the resolver's own `ShootResult.unported` marks (dice.rs `mark`), so a core that
    /// knows it diverged from the table says so; `[]` on a fully ported volley.
    Done { state: State, lines: Vec<LogLine>, landings: Vec<Landing>, unported: Vec<&'static str> },
}

/// The order rules, checked in their numbered order on each input; the error
/// is the first offending input's index and its sentence. `name` is the unit's.
pub fn order_check(name: &str, t: &[Input]) -> Result<(), (usize, String)> {
    let (mut declared, mut shot, mut rolled, mut over) = (false, false, false, false);
    let mut last_seq: Option<i64> = None;
    let mut consolidated: Vec<&str> = Vec::new();
    for (i, x) in t.iter().enumerate() {
        let why = match x {
            _ if i == 0 && *x != Input::Begin => Some("the activation was not started".to_string()),
            Input::Begin if i > 0 => Some("the activation is already started".to_string()),
            Input::Paid { .. } if i != 1 => Some("what the table paid is said right after the start".to_string()),
            _ if over => Some("the activation is over".to_string()),
            Input::Cancel if rolled => Some("cancel is not possible after the first die".to_string()),
            Input::Faces(_) if !declared => Some("faces before the action was declared".to_string()),
            Input::Choice { .. } if !declared => Some("the choice was answered before the action was declared".to_string()),
            Input::Cast(_) if !declared => Some("a cast before the action was declared".to_string()),
            Input::Cast(_) if rolled => Some("a cast after the first die".to_string()),
            // meleefix: the planner's consolidation inputs ride with the declared action, before the first die, once per unit, so a
            // growing transcript cannot change a goal between two steps.
            Input::Consolidate(_) if !declared => Some("consolidation inputs before the action was declared".to_string()),
            Input::Consolidate(_) if rolled => Some("consolidation inputs after the first die".to_string()),
            Input::Consolidate(c) if consolidated.contains(&c.unit.as_str()) => Some(format!("consolidation inputs for {} twice", c.unit)),
            Input::Cast(c) if c.seq < last_seq.map_or(0, |p| p + 1) => Some(format!("cast seq {} is too low: seq is 0 or more and higher than the cast before", c.seq)),
            Input::Intent { .. } if declared => Some("one action per activation".to_string()),
            Input::Placed { .. } if shot => Some(format!("{name} has already shot this round — it cannot move now")),
            Input::Intent { kind, .. } if *kind == REPOSITION => Some("not on the step path yet".to_string()),
            Input::Intent { kind, charge: None, .. } if *kind == CHARGE => Some("a charge names its target".to_string()),
            _ => None,
        };
        if let Some(reason) = why {
            return Err((i, reason));
        }
        match x {
            Input::Intent { shoot, .. } => (declared, shot) = (true, shoot.is_some()),
            Input::Faces(_) => rolled = true,
            Input::Cancel => over = true,
            Input::Cast(c) => last_seq = Some(c.seq),
            Input::Consolidate(c) => consolidated.push(c.unit.as_str()),
            _ => {}
        }
    }
    Ok(())
}

/// `begin_check`'s refusal: the player-facing `reason` and the battle-log `line` the door records.
#[derive(Debug, Clone, PartialEq)]
pub struct BeginRefused {
    pub reason: String,
    pub line: LogLine,
}

/// O5 + Firefight step 7: a unit may begin only when no other unit's activation is open (`Some(a)`)
/// and the table does not mix game systems (`systems`, normalised through `rules::book`).
/// Refusals carry both a player-facing reason and a `LogLine`.
pub fn begin_check(open_elsewhere: Option<&str>, systems: &[&str]) -> Result<(), BeginRefused> {
    if let Some(a) = open_elsewhere {
        let reason = format!("Finish {a}'s activation first.");
        let line = LogLine { rule: "begin_check", category: Category::General, side: 0, text: reason.clone(), detail: None };
        return Err(BeginRefused { reason, line });
    }
    let mut books: Vec<&'static str> = systems.iter().map(|s| crate::rules::book(s).system).collect();
    books.sort_unstable();
    books.dedup();
    if books.len() > 1 {
        let reason = if books.len() == 2 {
            format!("cannot start a game with lists of two game systems ({}, {})", books[0], books[1])
        } else {
            format!("cannot start a game with lists of {} game systems ({})", books.len(), books.join(", "))
        };
        let line = LogLine { rule: "mixed_systems", category: Category::General, side: 0, text: reason.clone(), detail: None };
        return Err(BeginRefused { reason, line });
    }
    Ok(())
}

/// The table's own drop floor in inches (`main.gd` `_on_units_dropped`, the
/// `<= 0.1` skip): a model that moved no more than this did not move.
pub const DROP_FLOOR_IN: f64 = 0.1;

/// Not moving is Hold: the core reads the declaration from the selector, never
/// from distance. ADVANCE or RUSH with no placement, or with every model within
/// `DROP_FLOOR_IN` (horizontal, the table's measure) of its start, is HOLD;
/// every other case is `declared`. A placement that does not match the unit's
/// models is not proven still, so it stays `declared` for the move check.
pub fn effective_kind(declared: i64, start: &[[f64; 3]], placed: Option<&[[f64; 3]]>) -> i64 {
    let still = |p: &[[f64; 3]]| p.len() == start.len() && p.iter().zip(start).all(|(a, b)| (a[0] - b[0]).hypot(a[2] - b[2]) / INCHES_TO_METERS <= DROP_FLOOR_IN);
    if (declared == ADVANCE || declared == RUSH) && placed.is_none_or(still) {
        HOLD
    } else {
        declared
    }
}

/// What a unit may move this activation per declared mode, in inches: the parts the real move
/// spends (`sim::band_parts`), one number for both. `widened_by` = the rules whose part is non-zero.
#[derive(Debug, Clone, PartialEq)]
pub struct Allowance { pub advance: f64, pub rush: f64, pub charge: f64, pub widened_by: Vec<String> }

/// The unit's `Allowance` at its activation start in `state`; Bounding is 0.0 here (gap G2).
pub fn allowance(statics: &[UnitStatic], state: &State, si: usize, seams: Seams, terrain: &Terrain) -> Allowance {
    let parts = [ADVANCE, RUSH, CHARGE].map(|k| band_parts(statics, state, state, si, k, None, 0.0, Cover::Board(terrain), seams, false));
    let grants: Vec<&str> = ["Fast", "Rapid Advance", "Rapid Rush", "Slow"].into_iter().filter(|g| crate::mods::granted(state, si, g)).collect();
    let names: [&[&str]; 8] = [&["Bounding"], &["Versatile Reach"], &["Grounded Speed"], &["Speed Feat"], &["Great Musician"], &grants, &["Rapid Charge"], &["Musician"]];
    // a Musician inch taken back with its bearer widens nothing, so only a given one is named
    let on = |i: usize| parts.iter().any(|p| {
        let v = [p.bounding, p.vr, p.gs, p.feat, p.buff, p.grant, p.rapid_mark, p.cmd][i];
        if i == 7 { v > 0.0 } else { v != 0.0 }
    });
    let widened_by = (0..8).filter(|&i| on(i)).flat_map(|i| names[i].iter().map(|n| n.to_string())).collect();
    Allowance { advance: parts[0].total(), rush: parts[1].total(), charge: parts[2].total(), widened_by }
}

/// One drop: the declared mode, each model's position (`state.positions` order) and each model's
/// walked path this activation (world XZ metres, same order; empty = none). Literals: `..Default::default()`.
#[derive(Debug, Clone, Default)]
pub struct Drop { pub mode: i64, pub placed: Vec<[f64; 3]>, pub trails: Vec<Vec<[f64; 2]>> }

/// `check_move`'s answer: accepted (with the overrun line when not enforced) or refused.
#[derive(Debug, Clone, PartialEq)]
pub enum Check { Ok { lines: Vec<LogLine> }, Refused { reason: String } }

/// The move check of one drop against the unit's start in `state`: (1) a declared mode, (2) one
/// position per model, (3) every model's walked path (its trail when it has 2+ points, which must
/// run from its start to its placed position within 0.01"; else the straight segment from start to end once the model
/// moved more than `DROP_FLOOR_IN`), plus every climb its legs pay, within the mode's allowance (+0.01" float noise), at
/// most 6" for every model once any model's path crosses Difficult terrain or the unit carries the Difficult debuff (not
/// for Flying or Strider). An
/// overrun is refused with the O3 sentence when `enforce`, else accepted with that sentence as one log line.
/// The model count of a placement that also moves the unit's joined heroes: the host's models, then each attached
/// hero's in `attached` order (the table's `get_alive_models_with_attached`).
pub fn placed_chain_len(state: &State, si: usize) -> usize {
    state.positions[si].len() + state.attached[si].iter().map(|&h| state.positions[h].len()).sum::<usize>()
}

/// Heightfield plan steps 13 / 13b: the inches a walked path (world XZ metres) drops down the cliffs of a tier board, or
/// `None` when it crosses a cliff it may not. A tier edge without a ladder is a sheer face: never climbed; a DROP of up to
/// 3 in is regular movement where the book prints drops (`drops`: gff / aofs, BG36 p.15) and counts its height (D4), every
/// other drop is refused. A leg through a grid vertex, where the segment test sees no edge, counts as the cliff it grazed
/// when the tier level changes on it with no ladder. A flat board has no edges and no levels: `Some(0.0)`. With `jumps`
/// (the skirmish Jumping rule) a drop over 3 in and up to 6 in is a jump: it is listed in the second field and its height
/// is not counted in the first.
///
/// Plan step 27-pre-R R2: `floor_y` (the walker's start height, world metres; `Some` from `PENDING_EPOCH_RUIN_LEDGES`) adds
/// the drops off a free ruin's floors (`Terrain::slab_drops`) to the same walk-ordered edges, so every band above applies.
fn cliff_drop_in(terrain: &Terrain, path: &[[f64; 2]], drops: bool, jumps: bool, floor_y: Option<f64>) -> Option<(f64, Vec<Jump>)> {
    let at = |p: [f64; 2]| [p[0] / terrain.in2m(), p[1] / terrain.in2m()];
    // Every cliff the path takes, in walking order.
    let mut ev: Vec<Edge> = Vec::new();
    let mut walked = 0.0;
    for w in path.windows(2) {
        let (a, b) = (at(w[0]), at(w[1]));
        let hits = tier_crossings(a, b, terrain.tier_edges());
        let cliffs: Vec<_> = hits.iter().filter(|c| c.kind == TierKind::Cliff).collect();
        let (la, lb) = (terrain.tier_in_at(a[0], a[1]), terrain.tier_in_at(b[0], b[1]));
        let grazed = cliffs.is_empty() && la != lb && !hits.iter().any(|c| c.kind == TierKind::Ladder);
        // (rise of the step, down?, where on the leg) per cliff the leg takes
        let steps: Vec<(f64, bool, f64)> = if grazed { vec![((la - lb).abs(), la > lb, 0.5)] } else { cliffs.iter().map(|c| (c.dy_in, c.down, c.t)).collect() };
        let (d, len) = ([w[1][0] - w[0][0], w[1][1] - w[0][1]], (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1]));
        for (dy, down, t) in steps {
            ev.push(Edge { s: walked + len * t, dy, down, at: [w[0][0] + d[0] * t, w[0][1] + d[1] * t], dir: [d[0] / len.max(1e-12), d[1] / len.max(1e-12)] });
        }
        walked += len;
    }
    if let Some(y) = floor_y {
        ev.extend(terrain.slab_drops(path, y).into_iter().map(|d| Edge { s: d.s, dy: d.dy_in, down: true, at: d.at, dir: d.dir }));
        ev.sort_by(|a, b| a.s.total_cmp(&b.s));
    }
    let (mut dropped, mut jumped) = (0.0, Vec::new());
    let mut k = 0;
    while k < ev.len() {
        let Edge { s, dy, down, at, dir } = ev[k];
        // A gap (3.6 skirmish p.15): down an edge and straight back up to the same height - a jump across, one die per inch of
        // width (1 in free); the gap's depth is never walked.
        if let (true, true, Some(&Edge { s: s2, dy: dy2, down: false, .. })) = (jumps, down, ev.get(k + 1)) {
            if (dy2 - dy).abs() < 1e-6 {
                if let crate::mv::jump::JumpKind::Jump { dice } = crate::mv::jump::gap_kind((s2 - s) / terrain.in2m()) {
                    jumped.push(Jump { dy, dice, gap_in: Some((s2 - s) / terrain.in2m()), at, dir });
                }
                k += 2;
                continue;
            }
        }
        // the plain-drop band read where the jump band is read (`mv::jump::drop_kind`, with its tolerance): a floor's
        // 3.00000014 in (float32 heights) is the 3 in drop it was built as, not a cliff (found by the R3 ruin e2e)
        if drops && down && matches!(crate::mv::jump::drop_kind(dy), crate::mv::jump::JumpKind::Free) {
            dropped += dy;
        } else if let (true, true, crate::mv::jump::JumpKind::Jump { dice }) = (jumps, down, crate::mv::jump::drop_kind(dy)) {
            jumped.push(Jump { dy, dice, gap_in: None, at, dir });
        } else {
            return None;
        }
        k += 1;
    }
    Some((dropped, jumped))
}

/// One cliff a walked path takes: metres walked to it, its rise (in), down?, where (world XZ) and the leg's direction.
#[derive(Debug, Clone, Copy)]
struct Edge { s: f64, dy: f64, down: bool, at: [f64; 2], dir: [f64; 2] }

/// One jump on a walked path: its height (in; a gap's depth), its dice before Strider, a gap's width (in), where the path
/// crosses the (first) edge and the path's direction there (world XZ).
#[derive(Debug, Clone, Copy)]
struct Jump { dy: f64, dice: u32, gap_in: Option<f64>, at: [f64; 2], dir: [f64; 2] }

/// Ruling D13: where model `m` of unit `si` lands when its jump at `j` fails - the first legal spot on its own path past the
/// edge, from where its base clears the edge out to 2 in from it: on the low side, not solid, overlapping no other model
/// (its unit's others where `placed` puts them, every other unit where it stands). `None`: no room, the jump is refused.
fn jump_foot(state: &State, si: usize, m: usize, terrain: &Terrain, placed: &[[f64; 3]], j: &Jump) -> Option<[f64; 3]> {
    let (r, i2m) = (state.radii[si][m], terrain.in2m());
    // the height the model drops from: the tier behind the edge, or - off a ruin's floor (27-pre-R), where the tier grid is
    // flat - the ground past the edge plus the drop; on a tier cliff both are the same height
    let past = terrain.tier_in_at(j.at[0] / i2m + j.dir[0] * 0.01, j.at[1] / i2m + j.dir[1] * 0.01);
    let high = terrain.tier_in_at(j.at[0] / i2m - j.dir[0] * 0.01, j.at[1] / i2m - j.dir[1] * 0.01).max(past + j.dy);
    let clear = |p: [f64; 2], q: [f64; 3], rq: f64| (p[0] - q[0]).hypot(p[1] - q[2]) >= r + rq - 1e-6;
    (0..=40).map(|k| r + 0.01 * i2m + k as f64 * 0.05 * i2m).take_while(|&d| d <= 2.0 * i2m + 1e-9).find_map(|d| {
        let p = [j.at[0] + j.dir[0] * d, j.at[1] + j.dir[1] * d];
        let low = terrain.tier_in_at(p[0] / i2m, p[1] / i2m);
        let free = !terrain.solid_at(p[0] / i2m, p[1] / i2m) && low < high - 0.01
            && placed.iter().enumerate().filter(|&(k, _)| k != m).all(|(k, q)| clear(p, *q, state.radii[si].get(k).copied().unwrap_or(r)))
            && (0..state.positions.len()).filter(|&u| u != si && state.alive[u] > 0)
                .all(|u| state.positions[u].iter().zip(state.radii[u].iter()).all(|(q, &rq)| clear(p, *q, rq)));
        free.then_some([p[0], low * i2m, p[1]])
    })
}

/// The dice one model rolls for its jumps: one per inch begun, halved rounding up with Strider.
fn jump_dice_for(state: &State, si: usize, jumps: &[Jump]) -> u32 {
    let strider = state.profile(si).special_rules.iter().any(|r| r == "Strider");
    jumps.iter().map(|j| crate::mv::jump::jump_dice(j.dice, false, strider)).sum()
}

/// Whether the skirmish Jumping rule holds for unit `si` at this epoch (the books that print drops).
/// Plan step 27-pre-R R2: the walker's height for the ruin-floor ledges (`cliff_drop_in`'s `floor_y`), from
/// `PENDING_EPOCH_RUIN_LEDGES` on; `None` below it, so a record before it replays without them.
fn ruin_floor_y(seams: Seams, at: &[f64; 3]) -> Option<f64> {
    rule_on(seams.rules_epoch, crate::acts::PENDING_EPOCH_RUIN_LEDGES).then_some(at[1])
}

fn jumps_on(state: &State, si: usize, seams: Seams) -> bool {
    state.book(si).vertical_moves && rule_on(seams.rules_epoch, crate::acts::EPOCH_100_SKIRMISH_JUMP)
}

/// The jumps a drop that `check_move` accepts asks of unit `si`: per host model (`state.positions` order) that jumps, its
/// dice, the inches it jumps down (a fall's height, step 17) and where it lands if it falls (`jump_foot`, ruling D13; the
/// first jump's foot). Flying never jumps; empty below the Jumping epoch and in every book without drops.
pub fn jump_dice_of(state: &State, si: usize, seams: Seams, terrain: &Terrain, drop: &Drop) -> Vec<(usize, u32, f64, [f64; 3])> {
    if !jumps_on(state, si, seams) || state.profile(si).special_rules.iter().any(|r| r == "Flying") {
        return Vec::new();
    }
    state.positions[si].iter().zip(&drop.placed).enumerate().filter_map(|(i, (a, b))| {
        let path = walked_path([a[0], a[2]], [b[0], b[2]], drop.trails.get(i).filter(|t| t.len() >= 2));
        let jumps = cliff_drop_in(terrain, &path, true, true, ruin_floor_y(seams, a))?.1;
        let dice = jump_dice_for(state, si, &jumps);
        let foot = jump_foot(state, si, i, terrain, &drop.placed, jumps.first()?)?;
        (dice > 0).then(|| (i, dice, jumps.iter().map(|j| j.dy).sum(), foot))
    }).collect()
}

/// L-RF1 (GF BG 3.6 p.11-12: a building is Impassable): does a walked path (world XZ metres) touch a solid tier cell? Sampled
/// every 0.1 in, so a leg through a house corner, where the cliff test sees no crossing, counts too. No solid cell: `false`.
fn enters_solid(terrain: &Terrain, path: &[[f64; 2]]) -> bool {
    let m = terrain.in2m();
    if !terrain.has_solid() || m <= 0.0 {
        return false; // a board without solid cells (and a bare `Terrain::default`, scale 0) has nothing to sample
    }
    path.windows(2).any(|w| {
        let d = [w[1][0] - w[0][0], w[1][1] - w[0][1]];
        let n = (d[0].hypot(d[1]) / m / 0.1).ceil().max(1.0) as usize;
        (0..=n).any(|k| { let f = k as f64 / n as f64; terrain.solid_at((w[0][0] + d[0] * f) / m, (w[0][1] + d[1] * f) / m) })
    })
}

/// A model's walked path for the move check (world XZ metres): its trail when it has 2+ points, else (R3: no chord bypass)
/// the straight segment [start, end] once it moved past the drop floor; a model that stayed has none.
fn walked_path(a: [f64; 2], b: [f64; 2], trail: Option<&Vec<[f64; 2]>>) -> Vec<[f64; 2]> {
    match trail {
        Some(t) => t.clone(),
        None if (a[0] - b[0]).hypot(a[1] - b[1]) / INCHES_TO_METERS > DROP_FLOOR_IN => vec![a, b],
        None => Vec::new(),
    }
}

/// GF p.11: Difficult terrain caps the WHOLE unit once any model's path crosses it (or the unit carries the Difficult
/// debuff); Flying and Strider ignore it (read as `mv::step` reads them). `paths` = per model, world XZ metres.
fn difficult_caps(statics: &[UnitStatic], state: &State, si: usize, terrain: &Terrain, paths: &[Vec<[f64; 2]>]) -> bool {
    let rules = &state.profile(si).special_rules;
    if rules.iter().any(|r| r == "Flying" || r == "Strider") {
        return false;
    }
    let crosses = |t: &Vec<[f64; 2]>, r: &f64| {
        let leg: Vec<[f32; 2]> = t.iter().map(|p| terrain.to_inch([p[0] as f32, 0.0, p[1] as f32])).collect();
        leg_crosses(&leg, *r, terrain, is_difficult)
    };
    paths.iter().zip(&state.radii[si]).any(|(t, r)| crosses(t, r)) || terrain_debuff_folds(statics, state, si).0
}

/// Does `check_move` hold this drop to the 6" Difficult cap? The same paths and the same test, read without the
/// refusals, so the table's drag band shrinks exactly where the drop check would cap it (a display question only).
pub fn drop_difficult(statics: &[UnitStatic], state: &State, si: usize, terrain: &Terrain, drop: &Drop) -> bool {
    let paths: Vec<Vec<[f64; 2]>> = state.positions[si].iter().zip(&drop.placed).enumerate()
        .map(|(i, (a, b))| walked_path([a[0], a[2]], [b[0], b[2]], drop.trails.get(i).filter(|t| t.len() >= 2)))
        .collect();
    difficult_caps(statics, state, si, terrain, &paths)
}

pub fn check_move(statics: &[UnitStatic], state: &State, si: usize, seams: Seams, terrain: &Terrain, drop: &Drop, enforce: bool) -> Check {
    let (mode, m) = match drop.mode {
        ADVANCE => ("Advance", 0),
        RUSH => ("Rush", 1),
        CHARGE => ("Charge", 2),
        _ => return Check::Refused { reason: "movement mode not declared".to_string() },
    };
    let start = &state.positions[si];
    // S1: the placement may carry the joined heroes' models after the host's (`placed_chain_len`); the allowance below
    // reads the host's models (the zip stops there), as the table measures the unit's own move.
    if drop.placed.len() != start.len() && drop.placed.len() != placed_chain_len(state, si) {
        return Check::Refused { reason: "placement does not match the unit's models".to_string() };
    }
    let inch = |p: [f64; 2], q: [f64; 2]| (p[0] - q[0]).hypot(p[1] - q[1]) / INCHES_TO_METERS;
    // The climbs the AI's move pays (GF p.11), in the trail's world frame: none for Flying or below epoch 74.
    let flying = state.profile(si).special_rules.iter().any(|r| r == "Flying");
    let ledges = crate::mv::step::world_ledges_of(terrain, flying, seams.rules_epoch);
    let (mut x, mut dropped) = (0.0f64, 0.0f64);
    let mut jump_lines: Vec<LogLine> = Vec::new();
    // Teleport / Ethereal (army book): once per activation, before attacking, the unit is PLACED within the rule's reach of
    // where it stands - a placement, not a walk. The table pays it before the core call (`teleport_used`), so a trail ends
    // where the walk ended and the hop on to the placed model is held to the reach, never to the move allowance.
    let hop_in = statics[state.roster.profile[si]].teleport.as_ref().filter(|_| state.teleport_used[si])
        .map(|s| crate::unit::teleport_cap_in(&s.name, drop.mode == RUSH));
    // Each model's path: its trail, else (R3: no chord bypass) the straight segment [start, end] once it moved past the
    // drop floor, so its climbs and its Difficult crossing count all the same; a model that stayed has none.
    let mut paths: Vec<Vec<[f64; 2]>> = Vec::with_capacity(start.len());
    for (i, (a, b)) in start.iter().zip(&drop.placed).enumerate() {
        let (a, b) = ([a[0], a[2]], [b[0], b[2]]);
        let trail = drop.trails.get(i).filter(|t| t.len() >= 2);
        if trail.is_some_and(|t| inch(t[0], a) > 0.01 || inch(t[t.len() - 1], b) > hop_in.unwrap_or(0.0) + 0.01) {
            return Check::Refused { reason: "trail does not match the placed model".to_string() };
        }
        let path = walked_path(a, b, trail);
        // L-RF1: nobody walks through or ends on a building (an intact house); Flying crosses it but may not end on it.
        let ends_inside = terrain.solid_at(b[0] / terrain.in2m(), b[1] / terrain.in2m());
        if ends_inside || (!flying && enters_solid(terrain, &path)) {
            return Check::Refused { reason: format!("{}: a building is impassable", statics[state.roster.profile[si]].name) };
        }
        // Heightfield plan steps 13 / 13b (`EPOCH_94_PARITY_BATCH`): the AI planner never walks a cliff, a placed move is stopped
        // the same way unless it is a drop the book allows, which pays its height. A Flying unit ignores the edges.
        let drop_in = match (rule_on(seams.rules_epoch, EPOCH_94_PARITY_BATCH) && !flying).then(|| cliff_drop_in(terrain, &path, state.book(si).vertical_moves, jumps_on(state, si, seams),
            ruin_floor_y(seams, &state.positions[si][i]))) {
            Some(None) => return Check::Refused { reason: format!("{}: cliff: no ladder here", statics[state.roster.profile[si]].name) },
            Some(Some((d, jumps))) => {
                // Jumping (3.6 skirmish p.15): one line per jumping model; the jump's height is not counted toward the move.
                let dice = jump_dice_for(state, si, &jumps);
                if dice > 0 && jump_foot(state, si, i, terrain, &drop.placed, &jumps[0]).is_none() {
                    return Check::Refused { reason: format!("{}: model {} has no room to land at the foot of the drop", statics[state.roster.profile[si]].name, i + 1) };
                }
                if dice > 0 {
                    jump_lines.push(LogLine { rule: "jump", category: Category::Movement, side: state.player[si], detail: None,
                        text: format!("{}: model {} jumps {} - {dice} dice at 2+, the jump does not count toward the move",
                            statics[state.roster.profile[si]].name, i + 1, jumps.iter().map(|j| match j.gap_in {
                                Some(w) => format!("a {w:.0} in gap"),
                                None => format!("down {:.0} in", j.dy),
                            }).collect::<Vec<_>>().join(" and ")) });
                }
                d
            }
            None => 0.0,
        };
        dropped = dropped.max(drop_in);
        x = x.max(drop_in + if path.is_empty() { inch(a, b) } else { crate::mv::step::trail_walk_in(&path, &ledges).0 });
        paths.push(path);
    }
    let difficult = difficult_caps(statics, state, si, terrain, &paths);
    let a = allowance(statics, state, si, seams, terrain);
    let full = [a.advance, a.rush, a.charge][m];
    let capped = difficult && full > DIFFICULT_MOVE_CAP_IN;
    let y = if capped { DIFFICULT_MOVE_CAP_IN } else { full };
    // Rules-must-log: the drop names itself once (the biggest of the unit's models).
    let drop_line = (dropped > 0.0).then(|| LogLine { rule: "drop", category: Category::Movement, side: state.player[si],
        text: format!("{}: Drop {dropped:.0} in - a drop is regular movement and counts its height", statics[state.roster.profile[si]].name), detail: None });
    if x <= y + 0.01 {
        return Check::Ok { lines: drop_line.into_iter().chain(jump_lines).collect() };
    }
    // The Difficult cap names itself: "the Rush allowance is 6.0"" alone read as a wrong Rush band to the player.
    let why = if capped { " in Difficult terrain" } else { "" };
    let text = format!("{}: a model moved {x:.1}\" - the {mode} allowance is {y:.1}\"{why}.", statics[state.roster.profile[si]].name);
    if enforce {
        return Check::Refused { reason: text };
    }
    let detail = if capped { Some("Difficult terrain".to_string()) } else { (!a.widened_by.is_empty()).then(|| a.widened_by.join(", ")) };
    Check::Ok { lines: drop_line.into_iter().chain(jump_lines).chain([LogLine { rule: "move_overrun", category: Category::Movement, side: state.player[si], text, detail }]).collect() }
}

/// P4.0-5: the one choice the step API offers so far — the Takedown model pick (`sim::takedown_pick`'s
/// automatic answer). `Some((id, options, owner))` when the activation shoots a Takedown weapon at a
/// target with 2+ living models: `id` = `takedown_model:<shooter key>:<target key>`, `options` = the
/// target's living capture slots as `slot:<n>`, `owner` = the shooter's roster key (its side answers,
/// as on the table). `None` otherwise, so every other transcript sees no choice at all.
fn takedown_choice(statics: &[UnitStatic], state: &State, si: usize, shoot: Option<&str>) -> Option<(String, Vec<String>, String)> {
    let target = shoot?;
    let ti = *state.roster.index.get(target)?;
    let living: Vec<usize> = (0..state.wounds[ti].len()).filter(|&i| state.wounds[ti][i] > 0).collect();
    if living.len() < 2 || !statics[state.roster.profile[si]].shoot.iter().any(|p| p.takedown) {
        return None;
    }
    let owner = state.roster.keys[si].clone();
    let id = format!("takedown_model:{owner}:{target}");
    Some((id, living.iter().map(|i| format!("slot:{i}")).collect(), owner))
}

/// CC-5a: the spell kinds the core will resolve (damage; buff and debuff as a modifier or a grant). CC-13f: `utility` too - the table
/// resolves a utility spell as announce + token + the book's manual note, nothing mechanical (every utility entry of the spell books
/// is `{"kind": "utility"}`, no modifier, no grant), which is exactly an effect-less buff here (`sim::tray_spell_effect`).
const CAST_KINDS: [&str; 4] = ["damage", "buff", "debuff", "utility"];

/// CC-5a/9c: why one planned cast cannot be taken, `None` when it can. The caster and every target are units of the roster, the caster
/// holds a spell of that EXACT name, the spell's kind is one the core resolves, and `open` (a foe's owner may still answer) requires
/// an interference probe or answer (`interference:<seq>:<caster>:<slot>`) in the transcript plus valid pool payers.
fn cast_break(statics: &[UnitStatic], state: &State, left: &mut [i64], c: &CastInput, t: &[Input]) -> Option<String> {
    let Some(&ci) = state.roster.index.get(c.caster.as_str()) else { return Some(format!("cast {}: {} is no unit of this game", c.seq, c.caster)) };
    let caster = &statics[state.roster.profile[ci]];
    let Some(spell) = caster.spells.iter().find(|s| s.name == c.spell) else { return Some(format!("cast {}: {} has no spell named {}", c.seq, caster.name, c.spell)) };
    if !CAST_KINDS.contains(&spell.effect_kind.as_str()) {
        return Some(format!("cast {}: the core does not resolve {} spells yet ({})", c.seq, spell.effect_kind, c.spell));
    }
    if c.targets.is_empty() && spell.target_count > 0 {
        return Some(format!("cast {}: {} has no targets", c.seq, c.spell));
    }
    if let Some(k) = c.targets.iter().find(|k| !state.roster.index.contains_key(k.as_str())) {
        return Some(format!("cast {}: {k} is no unit of this game (a target of {})", c.seq, c.spell));
    }
    if c.open {
        for (_, payers) in &c.pools {
            for (key, n) in payers {
                let Some(&i) = state.roster.index.get(key.as_str()) else {
                    return Some(format!("cast {}: {key} is no unit of this game (an interference pool for {})", c.seq, c.spell));
                };
                if *n < 0 {
                    return Some(format!("cast {}: {} has a negative interference pool ({n}) for {}", c.seq, statics[state.roster.profile[i]].name, c.spell));
                }
            }
        }
        let prefix = format!("{INTERFERENCE}{}:{}:", c.seq, c.caster);
        let needed: Vec<i64> = c.pools.iter().filter(|(_, p)| p.iter().any(|(_, n)| *n > 0)).map(|(s, _)| *s).collect();
        let covered = if needed.is_empty() {
            t.iter().any(|x| matches!(x, Input::Choice { id, .. } if id.starts_with(&prefix)))
        } else {
            needed.iter().all(|&slot| t.iter().any(|x| matches!(x, Input::Choice { id, .. } if *id == format!("{prefix}{slot}"))))
        };
        if !covered {
            return Some(format!("cast {}: a foe's answer to {} cannot be asked yet", c.seq, c.spell));
        }
    }
    if let Some(k) = (!c.conduit.is_empty()).then_some(&c.conduit).into_iter().chain(&c.conduit_shaken).find(|k| !state.roster.index.contains_key(k.as_str())) {
        return Some(format!("cast {}: {k} is no unit of this game (a conduit for {})", c.seq, c.spell));
    }
    // CC-5b: the tokens as the table paid them at plan time: the threshold from the caster, boost and interference from the listed
    // payers, each from what is left after the casts before it. The payers must give exactly the boost / interference named.
    for (what, want, payers) in [("boost", c.boost, &c.boost_sources), ("interference", c.interference, &c.interference_sources)] {
        let given = payers.iter().try_fold(0i64, |acc, p| acc.checked_add(p.1));
        if given != Some(want) {
            let got = given.map_or_else(|| "overflow".into(), |g| g.to_string());
            return Some(format!("cast {}: {} has {what} {want} but its payers give {got}", c.seq, c.spell));
        }
    }
    let pays = std::iter::once((c.caster.as_str(), c.threshold)).chain(c.boost_sources.iter().chain(&c.interference_sources).map(|(k, n)| (k.as_str(), *n)));
    for (key, n) in pays {
        let Some(&i) = state.roster.index.get(key) else { return Some(format!("cast {}: {key} is no unit of this game (a payer for {})", c.seq, c.spell)) };
        if n < 0 || left[i] < n {
            return Some(format!("cast {}: {} holds {} token(s) but {} asks {n} of it", c.seq, statics[state.roster.profile[i]].name, left[i], c.spell));
        }
        left[i] -= n;
    }
    if spell.effect_kind == "damage" {
        return damage_break(statics, state, c, spell).map(|why| format!("cast {}: {why}", c.seq)).or_else(|| earlier_record_break(statics, state, c, t));
    }
    None
}

/// CC-13e (hazard 2, seen at activation start): a damage cast whose standing target - or a unit joined to it - is a target of an EARLIER
/// cast of the same transcript whose spell places a record (a non-damage spell with a modifier or a grant). `sim::tray_cast` would refuse
/// it at resolution, after that earlier cast's die was thrown and the rest of the activation lost; here it is refused before any die, so
/// the table resolves all the casts in its own order. Conservative: the earlier cast may fail its die and place nothing.
fn earlier_record_break(statics: &[UnitStatic], state: &State, c: &CastInput, t: &[Input]) -> Option<String> {
    let places = |e: &CastInput| state.roster.index.get(e.caster.as_str()).is_some_and(|&ci| {
        statics[state.roster.profile[ci]].spells.iter().any(|s| s.name == e.spell && s.effect_kind != "damage" && !crate::sim::spell_effect_less(s))
    });
    let placed: Vec<(i64, usize)> = t.iter().filter_map(|x| if let Input::Cast(e) = x { Some(e) } else { None }).filter(|e| e.seq < c.seq && places(e))
        .flat_map(|e| e.targets.iter().filter_map(|k| state.roster.index.get(k.as_str()).map(|&u| (e.seq, u)))).collect();
    let spell = &c.spell;
    c.targets.iter().filter_map(|k| state.roster.index.get(k.as_str()).copied()).filter(|&u| state.alive[u] > 0).find_map(|u| {
        let chain = std::iter::once(u).chain(state.attached_to[u]).chain(state.attached[u].iter().copied());
        let (seq, _) = chain.filter_map(|m| placed.iter().find(|p| p.1 == m)).next()?;
        Some(format!("cast {}: {} meets {spell} after cast {seq} placed a record on it or its joined unit (the core does not say that for spell damage yet)", c.seq, statics[state.roster.profile[u]].name))
    })
}

/// CC-6a/8b: whether target `t` carries no rule or live record that moves its save or says a line the core lacks for
/// spell damage. Checked at activation start (`damage_break`) AND re-checked at cast resolution (`sim::tray_cast`, CC-6a
/// hazard 2) because an earlier cast in the same activation may place a record on `t` or its joined chain.
pub(crate) fn damage_target_plain(statics: &[UnitStatic], state: &State, t: usize) -> bool {
    let d = &statics[state.roster.profile[t]].ctx;
    let armor = state.profiles.list.get(state.roster.profile[t]).is_some_and(|p| crate::rules::has_special_rule(&p.special_rules, "Armor"));
    let chain_clear = std::iter::once(t).chain(state.attached_to[t]).chain(state.attached[t].iter().copied()).all(|u| state.buffs[u].is_empty());
    chain_clear && state.growth_markers[t] <= 0 && !(armor || d.shielded || d.guarded || d.fortified)
}

/// CC-6a/6b/7a/7b: why the core cannot resolve a damage spell's hits exactly yet, `None` when it can. Weapon rules: all ported
/// damage-spell facets (`AP`, `Deadly`, `Surge`, `Hazardous`, `Crack`, `Blast`, `Bane`, `Lacerate`, `Shred`, `Destructive`, `Fracture`,
/// `Puncture`, `Disintegrate`, `Shatter`, `Tear`, `Purge`, `Decimate`, `Obliterate`, `Reap`, `Fragment`; `Scourge` and unknown rules
/// stay refused). Target: no rule or record that moves its save or says a line the core lacks (a live modifier or grant on its chain,
/// growth markers, Shielded, Guarded, Fortified, Armor); Regeneration and its family are resolved at the spell threshold (CC-6b).
fn damage_break(statics: &[UnitStatic], state: &State, c: &CastInput, spell: &crate::rules::Spell) -> Option<String> {
    if let Some(rule) = spell.weapon_rules.iter().find(|r| r.split('(').next().is_none_or(|n| !matches!(
        n.trim(),
        "AP" | "Deadly" | "Surge" | "Hazardous" | "Crack" | "Blast" | "Bane" | "Lacerate" | "Shred"
            | "Destructive" | "Fracture" | "Puncture" | "Disintegrate" | "Shatter" | "Tear"
            | "Purge" | "Decimate" | "Obliterate" | "Reap" | "Fragment"
    ))) {
        return Some(format!("the core does not resolve the {rule} rule of {} yet", c.spell));
    }
    let t = c.targets.iter().filter_map(|k| state.roster.index.get(k.as_str()).copied()).find(|&t| !damage_target_plain(statics, state, t))?;
    Some(format!("{} meets {} with a rule the core does not say for spell damage yet", statics[state.roster.profile[t]].name, c.spell))
}

/// CC-5a: the first planned cast in the transcript that `cast_break` refuses, as (its input index, the sentence).
fn cast_check(statics: &[UnitStatic], state: &State, t: &[Input]) -> Option<(usize, String)> {
    let mut left = state.casts.clone();
    t.iter().enumerate().find_map(|(i, x)| if let Input::Cast(c) = x { cast_break(statics, state, &mut left, c, t).map(|why| (i, why)) } else { None })
}

/// P4.0-5: the ids of the Takedown model-pick choice (`takedown_model:<shooter>:<target>`) start with this.
const TAKEDOWN_MODEL: &str = "takedown_model:";
/// The ids of the wound-allocation choice (`wound_alloc:<shooter>:<target>:<group>`) start with this.
const WOUND_ALLOC: &str = "wound_alloc:";
/// CC-9b/9c: the ids of the cast-interference choice (`interference:<seq>:<caster>:<slot>`) start with this.
const INTERFERENCE: &str = "interference:";
/// The player's spot-marker offer (`spot_markers:<shooter>:<target>`, options "0".."N", the attacker's count of the target's Precision
/// Spotter markers to remove): an interference-shaped count choice; no answer takes all of them (the AI's rule).
const SPOT_MARKERS: &str = "spot_markers:";
/// E-24: the ids of the defender's strike-back choice (`strike_back:<charger>:<defender>`, options `strike` / `hold`) start with this.
const STRIKE_BACK: &str = "strike_back:";
/// Step 29b: the ids of the defender's Blast split choice (`blast_split:<shooter>:<target>`) start with this.
const BLAST_SPLIT: &str = "blast_split:";
/// Step 29d: the attacker's push (`push:<attacker>:<target>`, push | no) and its spot (`push_to:<attacker>:<target>`).
const PUSH: &str = "push:";
const PUSH_TO: &str = "push_to:";
/// Step 29d-2: the defender's own placement of the pushed unit's other models (`push_replace:<target>`).
const PUSH_REPLACE: &str = "push_replace:";
/// Step 22a (OD-2: a player's own pick is asked of the player): the ids of the Versatile mode choice
/// (`versatile_mode:<activating unit>`, options `ap` / `hit`) start with this. It rides the strike-back list (a two-way choice).
const VERSATILE_MODE: &str = "versatile_mode:";

/// One activation through the step API: the order rules, then the declared
/// action (not moving = Hold) on the supplied faces and the LAST placement (`check_move` first).
/// A new entry: the AI's resolver path is untouched. `NeedRoll.index` is the
/// roll's, not the transcript's; a refusal of the whole transcript is at `t.len()`.
pub fn step_activation(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, t: &[Input], enforce: bool) -> ActStep {
    let at = state.roster.index.get(unit).copied();
    let name = at.map_or(unit, |i| statics[state.roster.profile[i]].name.as_str());
    if let Err((index, reason)) = order_check(name, t) {
        return ActStep::Refused { index, reason };
    }
    // CC-5a: the static checks come first, each break with its own sentence at its cast's index, before any resolver: so before the
    // Dangerous die and before any token is spent.
    if let Some((index, reason)) = cast_check(statics, state, t) {
        return ActStep::Refused { index, reason };
    }
    // D-PAR3 14a/14b: `order_check` keeps a `Paid` at index 1; the start and the beats ride the tray, the Dangerous test the seams.
    let (paid_start, paid_dangerous, paid_beats) = match t.get(1) {
        Some(Input::Paid { start, dangerous, beats }) => (*start, *dangerous, *beats),
        _ => (false, false, false),
    };
    let casts: Vec<CastInput> = t.iter().filter_map(|x| if let Input::Cast(c) = x { Some(c.clone()) } else { None }).collect();
    if paid_beats && !casts.is_empty() {
        return ActStep::Refused { index: 1, reason: "the table paid the pre-attack phase, so it cast already: no cast input".to_string() };
    }
    let consolidate: Vec<ConsolidatePlan> = t.iter().filter_map(|x| if let Input::Consolidate(c) = x { Some(c.clone()) } else { None }).collect();
    // Before any resolver runs: no die is drawn and no state is resolved. A `Placed` in the
    // transcript is simply dropped (the table puts the models back).
    if t.last() == Some(&Input::Cancel) {
        let side = at.map_or(0, |i| state.player[i]);
        let text = format!("{name} cancelled its activation - back at its start.");
        return ActStep::Cancelled { lines: vec![LogLine { rule: "activation_cancel", category: Category::Movement, side, text, detail: None }] };
    }
    let declared = t.iter().enumerate().find_map(|(i, x)| match x {
        Input::Intent { kind, shoot, split, charge, no_step } => Some((i, *kind, shoot.clone(), split.clone(), charge.clone(), *no_step)),
        _ => None,
    });
    let Some((at_intent, declared, shoot, split, charge, no_step)) = declared else {
        return ActStep::Open;
    };
    let placed = t.iter().rev().find_map(|x| match x {
        Input::Placed { at, trails } => Some((at.clone(), trails.clone())),
        _ => None,
    });
    let start = at.map_or(&[][..], |i| state.positions[i].as_slice());
    let kind = effective_kind(declared, start, placed.as_ref().map(|(p, _)| p.as_slice()));
    if kind == RUSH && shoot.is_some() {
        return ActStep::Refused { index: at_intent, reason: format!("{name} rushed this activation - it cannot shoot.") };
    }
    // CC-9b: route every `Choice` by id prefix (`takedown_model:`, `wound_alloc:`, `interference:`); any other prefix is
    // refused with a sentence. Within each kind the last entry per id wins; without one the core's automatic pick stands.
    let mut takedown: Option<(usize, &str, &str)> = None;
    let mut wound: Vec<(usize, String, Option<Vec<usize>>)> = Vec::new();
    let mut interference: Vec<(usize, String, Option<i64>)> = Vec::new();
    let mut strike_back: Vec<(usize, String, Option<bool>)> = Vec::new();
    let mut blast: Vec<(usize, String, Option<Vec<String>>)> = Vec::new();
    let mut free: Vec<(usize, String, Option<String>)> = Vec::new();
    for (i, x) in t.iter().enumerate() {
        let Input::Choice { id, option } = x else { continue };
        if id.starts_with(TAKEDOWN_MODEL) {
            takedown = Some((i, id.as_str(), option.as_str()));
        } else if id.starts_with(WOUND_ALLOC) {
            let slots = option.split(',').map(|s| s.strip_prefix("slot:")?.parse::<usize>().ok()).collect::<Option<Vec<_>>>();
            if !option.is_empty() && slots.is_none() {
                return ActStep::Refused { index: i, reason: format!("{option} is not a slot list (slot:<n>,..) for {id}") };
            }
            wound.retain(|w| w.1 != *id);
            wound.push((i, id.clone(), slots.filter(|_| !option.is_empty())));
        } else if id.starts_with(INTERFERENCE) || id.starts_with(SPOT_MARKERS) {
            let count = if option.is_empty() {
                None
            } else {
                let plain = option.bytes().all(|b| b.is_ascii_digit()) && (option.len() == 1 || !option.starts_with('0'));
                let Some(n) = plain.then(|| option.parse::<i64>().ok()).flatten() else {
                    return ActStep::Refused { index: i, reason: format!("{option} is not a token count (0..N) for {id}") };
                };
                Some(n)
            };
            interference.retain(|w| w.1 != *id);
            interference.push((i, id.clone(), count));
        } else if id.starts_with(STRIKE_BACK) {
            let answer = match option.as_str() {
                "" => None,
                "strike" => Some(true),
                "hold" => Some(false),
                _ => return ActStep::Refused { index: i, reason: format!("{option} is not an option of {id} (options: strike, hold)") },
            };
            strike_back.retain(|w| w.1 != *id);
            strike_back.push((i, id.clone(), answer));
        } else if id.starts_with(PUSH) {
            let answer = match option.as_str() {
                "" => None,
                "push" => Some(true),
                "no" => Some(false),
                _ => return ActStep::Refused { index: i, reason: format!("{option} is not an option of {id} (options: push, no)") },
            };
            strike_back.retain(|w| w.1 != *id);
            strike_back.push((i, id.clone(), answer));
        } else if id.starts_with(PUSH_TO) || id.starts_with(PUSH_REPLACE) {
            free.retain(|w| w.1 != *id);
            free.push((i, id.clone(), (!option.is_empty()).then(|| option.clone())));
        } else if id.starts_with(BLAST_SPLIT) {
            blast.retain(|w| w.1 != *id);
            blast.push((i, id.clone(), (!option.is_empty()).then(|| option.split(',').map(String::from).collect())));
        } else if id.starts_with(VERSATILE_MODE) {
            if *id != format!("{VERSATILE_MODE}{unit}") {
                return ActStep::Refused { index: i, reason: format!("the open choice is {VERSATILE_MODE}{unit}, not {id}") };
            }
            let answer = match option.as_str() {
                "" => None,
                "ap" => Some(true),
                "hit" => Some(false),
                _ => return ActStep::Refused { index: i, reason: format!("{option} is not an option of {id} (options: ap, hit)") },
            };
            strike_back.retain(|w| w.1 != *id);
            strike_back.push((i, id.clone(), answer));
        } else {
            return ActStep::Refused {
                index: i,
                reason: format!("unknown choice kind {id} (expected {TAKEDOWN_MODEL}, {WOUND_ALLOC}, {INTERFERENCE}, {SPOT_MARKERS}, {STRIKE_BACK}, {BLAST_SPLIT}, {PUSH}, {PUSH_TO}, {PUSH_REPLACE} or {VERSATILE_MODE})"),
            };
        }
    }
    let mut seams = seams;
    seams.no_dangerous |= paid_dangerous; // D-PAR3 14b: the table rolled this move's test (its end morale is the table's too)
    if let Some((i, id, option)) = takedown {
        let Some((want, options, owner)) = at.and_then(|si| takedown_choice(statics, state, si, shoot.as_deref())) else {
            return ActStep::Refused { index: i, reason: format!("no choice is open in this activation (got {id})") };
        };
        if id != want {
            return ActStep::Refused { index: i, reason: format!("the open choice is {want}, not {id}") };
        }
        if option.is_empty() {
            return ActStep::NeedChoice { id: want, options, owner, lines: Vec::new(), landings: Vec::new() };
        }
        let Some(slot) = option.strip_prefix("slot:").and_then(|n| n.parse::<usize>().ok()).filter(|_| options.iter().any(|o| o == option)) else {
            return ActStep::Refused { index: i, reason: format!("{option} is not an option of {want} (options: {})", options.join(", ")) };
        };
        seams = Seams { takedown_pick: Some(slot), ..seams };
    }
    if let Some((i, id, _)) = interference.iter().find(|c| c.2.is_some() && casts.is_empty() && c.1.starts_with(INTERFERENCE)) {
        return ActStep::Refused { index: *i, reason: format!("no interference choice is open in this activation (got {id})") };
    }
    // A charge on the step path is the TABLE's charge (the move, the snap, the pile-in), whatever the header's
    // search knobs say: the ported movement is ON and the plain-only imagination OFF. Without it the resolver skips the move,
    // finds no contact and answers a fightless `Done` (measured at the Godot door: empty lines, empty delta).
    if kind == CHARGE {
        seams = Seams { movement: true, plain_only: false, charge_direct: true, ..seams };
    }
    // Not HOLD: a mode was declared and the last placement moved (or does not match the models).
    let mut moved = Vec::new();
    if let (true, Some((p, trails)), Some(pi), Some(si)) = (kind != HOLD, &placed, t.iter().rposition(|x| matches!(x, Input::Placed { .. })), at) {
        #[allow(clippy::needless_update)] // the plan's literal form: step 78 adds `from` to `Drop`
        let drop = Drop { mode: declared, placed: p.clone(), trails: trails.clone(), ..Default::default() };
        match check_move(statics, state, si, seams, terrain, &drop, enforce) {
            Check::Refused { reason } => return ActStep::Refused { index: pi, reason },
            Check::Ok { lines } => moved = lines,
        }
    }
    let action = Action { kind, unit: unit.to_string(), dest: None, shoot, charge, patient: false, split, traced: None, teleport: None };
    let faces: Vec<Vec<u8>> = t.iter().filter_map(|x| if let Input::Faces(f) = x { Some(f.clone()) } else { None }).collect();
    // The spike's non-tray seed: a plain activation never draws from it.
    let reached_wound = std::cell::RefCell::new(Vec::new());
    let reached_int = std::cell::RefCell::new(Vec::new());
    let reached_back = std::cell::RefCell::new(Vec::new());
    let reached_blast = std::cell::RefCell::new(Vec::new());
    let reached_free = std::cell::RefCell::new(Vec::new());
    let cast_refused = std::cell::RefCell::new(None);
    let run = |statics: &[UnitStatic]| {
        let resolve = |tray: &mut Tray| {
            if let Some((p, trails)) = placed.clone() {
                tray.place(p, trails);
            }
            tray.pay(paid_start, paid_beats);
            tray.hold_step(no_step);
            for (_, id, answer) in &wound {
                tray.offer_wound_alloc(id.clone(), answer.clone());
            }
            for (_, id, answer) in &interference {
                tray.offer_interference(id.clone(), *answer);
            }
            for (_, id, answer) in &strike_back {
                tray.offer_strike_back(id.clone(), *answer);
            }
            for (_, id, answer) in &blast {
                tray.offer_blast_split(id.clone(), answer.clone());
            }
            tray.offer_casts(casts.clone());
            for (_, id, answer) in &free {
                tray.offer_free(id.clone(), answer.clone());
            }
            tray.offer_consolidation(consolidate.clone());
            let out = resolve_stochastic_tray_on_board(statics, state, &action, terrain, seams, &mut GodotRng::new(0), tray);
            *reached_wound.borrow_mut() = tray.feed().map(|f| f.wound_choices.clone()).unwrap_or_default();
            *reached_int.borrow_mut() = tray.feed().map(|f| f.interference_choices.clone()).unwrap_or_default();
            *reached_back.borrow_mut() = tray.feed().map(|f| f.strike_back_choices.clone()).unwrap_or_default();
            *reached_blast.borrow_mut() = tray.feed().map(|f| f.blast_choices.clone()).unwrap_or_default();
            *reached_free.borrow_mut() = tray.feed().map(|f| f.free_choices.clone()).unwrap_or_default();
            *cast_refused.borrow_mut() = tray.feed().and_then(|f| f.cast_refused.clone());
            out
        };
        step_with(&faces, resolve, |r| r.as_ref().map_or(&[][..], |(_, s)| s.rolls.as_slice()))
    };
    let first = run(statics);
    // Every reached choice (interference and wound_alloc) in (draw, reach) order, before the first
    // starved roll and before any cast refusal that came after it: a bad option is refused, an unanswered ask is NeedChoice
    // with the lines and landings before that choice point. Unreached answered choices are refused on Done.
    let at_wound = |id: &str| wound.iter().find(|w| w.1 == id).map_or(0, |w| w.0);
    let at_int = |id: &str| interference.iter().find(|w| w.1 == id).map_or(0, |w| w.0);
    let wound_choices = reached_wound.take();
    let int_choices = reached_int.take();
    let back_choices = reached_back.take();
    let blast_choices = reached_blast.take();
    let free_choices = reached_free.take();
    enum Pending {
        Refuse(usize, String),
        Ask { id: String, options: Vec<String>, owner: String, lines: Vec<LogLine>, landings: Vec<Landing> },
    }
    let mut events: Vec<(usize, usize, Pending)> = Vec::new();
    for c in &int_choices {
        let Some((at, pool, owner)) = &c.reached else { continue };
        if let Some(n) = c.bad {
            events.push((*at, c.order, Pending::Refuse(at_int(&c.id), format!("{n} is not an option of {} (options: 0..={pool})", c.id))));
        } else if c.answer.is_none() {
            events.push((*at, c.order, Pending::Ask {
                id: c.id.clone(),
                options: (0..=*pool).map(|n| n.to_string()).collect(),
                owner: owner.clone(),
                lines: c.lines.clone(),
                landings: c.landings.clone(),
            }));
        }
    }
    for c in &wound_choices {
        let Some((at, options, owner)) = &c.reached else { continue };
        if let Some(s) = c.bad {
            events.push((*at, c.order, Pending::Refuse(at_wound(&c.id), format!("slot:{s} is not an option of {}", c.id))));
        } else if c.answer.is_none() {
            events.push((*at, c.order, Pending::Ask {
                id: c.id.clone(),
                options: options.iter().map(|s| format!("slot:{s}")).collect(),
                owner: owner.clone(),
                lines: c.lines.clone(),
                landings: c.landings.clone(),
            }));
        }
    }
    for c in back_choices.iter().filter(|c| c.answer.is_none()) {
        let Some((at, owner)) = &c.reached else { continue };
        let options = if c.id.starts_with(VERSATILE_MODE) {
            ["ap", "hit"]
        } else if c.id.starts_with(PUSH) {
            ["push", "no"]
        } else {
            ["strike", "hold"]
        }.map(String::from).to_vec();
        events.push((*at, c.order, Pending::Ask { id: c.id.clone(), options, owner: owner.clone(), lines: c.lines.clone(), landings: c.landings.clone() }));
    }
    // Step 29d: a free answer (`push_to:`) has no option list; a spot the core refuses is refused at its input with the reason.
    for c in &free_choices {
        let Some((at, owner)) = &c.reached else { continue };
        let index = free.iter().find(|w| w.1 == c.id).map_or(0, |w| w.0);
        if let Some(why) = &c.bad {
            events.push((*at, c.order, Pending::Refuse(index, why.clone())));
        } else if c.answer.is_none() {
            events.push((*at, c.order, Pending::Ask { id: c.id.clone(), options: Vec::new(), owner: owner.clone(), lines: c.lines.clone(), landings: c.landings.clone() }));
        }
    }
    for c in &blast_choices {
        let Some((at, options, owner)) = &c.reached else { continue };
        let index = blast.iter().find(|w| w.1 == c.id).map_or(0, |w| w.0);
        if c.bad {
            let got = c.answer.as_ref().map(|a| a.join(",")).unwrap_or_default();
            events.push((*at, c.order, Pending::Refuse(index, format!("{got} is not an option of {} (options: {})", c.id, options.join(" | ")))));
        } else if c.answer.is_none() {
            events.push((*at, c.order, Pending::Ask { id: c.id.clone(), options: options.clone(), owner: owner.clone(), lines: c.lines.clone(), landings: c.landings.clone() }));
        }
    }
    events.sort_by_key(|(at, order, _)| (*at, *order));
    for (at, _, ev) in events {
        if matches!(first, Step::NeedRoll { index, .. } if index < at) {
            continue;
        }
        if matches!(&*cast_refused.borrow(), Some((refused_at, _, _)) if *refused_at <= at) {
            break;
        }
        return match ev {
            Pending::Refuse(index, reason) => ActStep::Refused { index, reason },
            Pending::Ask { id, options, owner, lines, landings } => ActStep::NeedChoice { id, options, owner, lines: [moved, lines].concat(), landings },
        };
    }
    // CC-5c/8b: a cast refused during resolution (unhandled spell kind, or CC-6a hazard 2: an earlier cast in the same
    // activation placed a record on a damage spell's target) is refused at its own input unless an earlier roll starved.
    if let Some((at, seq, reason)) = cast_refused.take() {
        if !matches!(first, Step::NeedRoll { index, .. } if index < at) {
            let index = t.iter().position(|x| matches!(x, Input::Cast(c) if c.seq == seq)).unwrap_or(0);
            return ActStep::Refused { index, reason };
        }
    }
    if matches!(first, Step::Done(..)) {
        if let Some(c) = int_choices.iter().find(|c| c.reached.is_none() && c.answer.is_some()) {
            let kind = if c.id.starts_with(SPOT_MARKERS) { "spot-marker offer" } else { "interference choice" };
            return ActStep::Refused { index: at_int(&c.id), reason: format!("no {kind} is open in this activation (got {})", c.id) };
        }
        if let Some((i, id, _)) = strike_back.iter().find(|w| w.2.is_some() && back_choices.iter().any(|c| c.id == w.1 && c.reached.is_none())) {
            let kind = if id.starts_with(VERSATILE_MODE) { "Versatile mode" } else { "strike-back" };
            return ActStep::Refused { index: *i, reason: format!("no {kind} choice is open in this activation (got {id})") };
        }
        if let Some(c) = wound_choices.iter().find(|c| c.reached.is_none() && c.answer.is_some()) {
            return ActStep::Refused { index: at_wound(&c.id), reason: format!("no wound allocation is open in this activation (got {})", c.id) };
        }
    }
    match first {
        Step::NeedRoll { index, faces, kind, count, target, owner, owner_unit, lines, landings } => {
            let owner_key = owner_key_of(statics, state, &owner, owner_unit, |keyed| match run(keyed) {
                Step::NeedRoll { index: i, kind: k, count: c, target: g, owner, .. } if (i, k, c, g) == (index, kind, count, target) => Some(owner),
                _ => None,
            });
            ActStep::NeedRoll { index, faces, kind, count, target, owner, owner_key, lines: [moved, lines].concat(), landings }
        }
        Step::Refused { reason, .. } => ActStep::Refused { index: t.len(), reason },
        Step::Done(Ok((state, shot)), lines, landings) => ActStep::Done { state, lines: [moved, lines].concat(), landings, unported: shot.unported },
        Step::Done(Err(u), ..) => ActStep::Refused { index: t.len(), reason: format!("{u:?}") },
    }
}

/// The roster key of the unit whose name a roll's `owner` is: the unit the supplied tray stamped for this draw (4.0-9),
/// else the one unit carrying that name, else (two units share it, as in a mirror match) the owner of the same roll when
/// `replay` runs the activation again with every unit named by its own key. A name decides no rule on this path, so the
/// replay draws the same rolls; one that asks for a different roll, or a name no unit carries, gives "" (the core cannot
/// tell). Never by the roll's kind: a unit can owe a defence or morale die for its own move (Dangerous terrain).
fn owner_key_of(statics: &[UnitStatic], state: &State, owner: &str, owner_unit: Option<usize>, replay: impl FnOnce(&[UnitStatic]) -> Option<String>) -> String {
    if let Some(u) = owner_unit.filter(|&u| u < state.units() && statics[state.roster.profile[u]].name == owner) {
        return state.roster.keys[u].clone();
    }
    let named: Vec<usize> = (0..state.units()).filter(|&u| statics[state.roster.profile[u]].name == owner).collect();
    match named[..] {
        [] => String::new(),
        [u] => state.roster.keys[u].clone(),
        _ => {
            let mut keyed = statics.to_vec();
            for (u, key) in state.roster.keys.iter().enumerate() {
                keyed[state.roster.profile[u]].name = key.clone();
            }
            replay(&keyed).filter(|k| named.iter().any(|&u| state.roster.keys[u] == *k)).unwrap_or_default()
        }
    }
}

/// What one activation did to one unit: the table's final cross-check of the
/// per-step landings (which carry the per-model news). `shaken` and `alive`
/// are the unit's values AFTER; `unknown` marks a unit that both moved and
/// lost models (not reachable on the plain path; the driver refuses it).
#[derive(Debug, Clone, PartialEq)]
pub struct UnitDelta {
    pub key: String,
    /// Indices into `before.positions[u]` (capture order) of the models that are gone.
    pub removed: Vec<usize>,
    pub shaken: bool,
    pub alive: i64,
    pub moved: bool,
    pub unknown: bool,
    /// HR-POS: the unit's surviving model positions AFTER (world metres), in capture slot order with the dead left out
    /// (removal keeps the survivors' order), carried whenever the unit moved. The core's own steps (the Hit & Run
    /// sidestep after a volley) move models the table never placed; `land_delta` puts each surviving model there. A unit
    /// can lose models in the same activation and still step (Hazardous self-wounds land in the volley, `sim.rs`
    /// `land_hazardous_self`, before `tray_hit_and_run`): its survivors ride too. Empty when nothing moved.
    pub positions: Vec<[f64; 3]>,
    /// P4.0-4d: the table-owned per-activation ledger AFTER — the fatigue flag and the unspent spell
    /// tokens. A plain activation changes neither; carrying them makes a table/core split visible.
    pub fatigued: bool,
    pub casts: i64,
    /// P4.0-4e: the per-unit once-per-round stamps AFTER (inventory class (a)), keyed by the `State`
    /// field name; `land_delta` maps the two names the table spells differently.
    pub stamps: Vec<(&'static str, i64)>,
    /// P4.0-4f: the per-unit marker pools AFTER (inventory class (a)), keyed by the table's own
    /// property name (every name is 1:1; absent on the table reads 0).
    pub pools: Vec<(&'static str, i64)>,
    /// P4.0-4g: the latched Versatile pick AFTER (inventory class (a)): 0 = none, 1 = +1 to hit,
    /// 2 = AP(+1). `land_delta` maps it onto the table's `versatile_pick` Dictionary.
    pub versatile_pick_mode: i64,
    /// The once-per-game feat latches this activation SPENT (inventory class (a)): the names `State::feats_used`
    /// gained, in the order they were spent. `land_delta` closes the table's flag for each, so the next capture sends it back.
    pub feats_used: Vec<String>,
    /// C-11: the once-per-game name lists this activation SPENT (inventory class (a)), the `feats_used` shape: the names
    /// `State::limited_used` / `storm_used` / `precision_used` gained, in the order they were spent. `land_delta` closes the
    /// table's latch for each (the weapon through `mark_limited_used`, the other two through their flag).
    pub limited_used: Vec<String>,
    pub storm_used: Vec<String>,
    pub precision_used: Vec<String>,
    /// C-13: the unit's Growth Markers counter AFTER (inventory class (a), `State::growth_markers`). One counter per unit
    /// whatever rules it carries; `land_delta` writes it through the unit's Growth Markers rule.
    pub growth_markers: i64,
    /// C-12: the Piercing-Tag bearer's once-per-game placement latch AFTER (inventory row of the same name):
    /// the core's placement closed its own copy; `land_delta` closes the table's flag, so the next capture
    /// sends it back and neither side places the tag twice.
    pub piercing_tag_used: bool,
    /// C-12: whether the unit's Piercing-Tag pool STANDS after the activation (`State::piercing_tag_persistent`,
    /// the "Piercing Target" name). The table keeps the NAME that placed it (`piercing_tag_source`);
    /// `land_delta` maps the bool onto that name.
    pub piercing_tag_persistent: bool,
    /// D19 (a): the unit's once-per-game Surprise Attack latch AFTER (`State::surprise_attack_used`, the
    /// "first time this unit is activated" trigger). The core fires the burst from its own copy; `land_delta`
    /// closes the table's flag with the writer its own beat uses, so a replay neither bursts twice nor
    /// re-opens a burned latch.
    pub surprise_attack_used: bool,
    /// C-15: the once buffs this activation SPENT (inventory class (b)): per record its own name (the table's `spell`) and scope, in
    /// `before`'s order. The core spends in its own copy of the ledger; `land_delta` spends the matching table records. CAST-O7: then
    /// the once records this activation's own casts placed and its spends took (never in `before`), in placement order. Records the
    /// core ADDED any other way (a pre-attack placement) are not carried.
    pub buffs_spent: Vec<(String, String)>,
    /// CC-8c: the spell names of the buff / debuff effects this activation's casts landed on this unit and that it still holds at
    /// the end (the table's `_solo_place_spell_tokens` names), in placement order; a record placed and spent by the same
    /// activation is in `buffs_spent` only (no news for the table: it lands the effect itself and spends it). Report only:
    /// the door lands each name from its own spell entry (`CoreActivation._land_spell_buffs`), the core pushes nothing.
    pub buffs_gained: Vec<String>,
    /// Landing lane: the melee-scoped Marks (once, attackers-side, scope `melee`: Rapid Charge, Piercing Fighting, Precision Fighting) this unit holds at the end and
    /// did not hold at the start, as (record name, scope, granted rule). The table keeps such a record on the marked unit after a volley for a later charger; the door
    /// never ran the table's `_solo_apply_vs_marks`, so `land_delta` records them (silently: the core said the pick and the record's lines).
    pub marks_left: Vec<(String, String, String)>,
}

/// The once buffs of `before` that `after` no longer holds, as (record name, scope). Each record is first matched to an identical
/// one in `after`, so a buff the activation did not touch is never named. CAST-O7: then the once records this activation's casts
/// placed on unit `u` and its spends took (`State::cast_buffs`) - never in `before`, so the diff cannot see them - in placement
/// order. Records the core added any other way (a pre-attack mark) are still not carried.
fn spent_buffs(before: &[LiveMod], after: &State, u: usize) -> Vec<(String, String)> {
    let mut kept: Vec<&LiveMod> = after.buffs[u].iter().collect();
    let mut out = Vec::new();
    for b in before {
        match kept.iter().position(|a| *a == b) {
            Some(i) => {
                kept.remove(i);
            }
            None if b.once => out.push((b.name.to_string(), b.scope.to_string())),
            None => {}
        }
    }
    out.extend(cast_spent_of(after, u).map(|r| (r.name.to_string(), r.scope.to_string())));
    out
}

/// The melee-scoped once Marks `after` holds on unit `u` beyond `before`'s (matched one for one), in ledger order.
fn marks_left(before: &[LiveMod], after: &State, u: usize) -> Vec<(String, String, String)> {
    let mut known: Vec<&LiveMod> = before.iter().collect();
    let mut out = Vec::new();
    for r in after.buffs[u].iter().filter(|r| r.attackers && r.once && &*r.scope == "melee") {
        match known.iter().position(|b| *b == r) {
            Some(i) => {
                known.remove(i);
            }
            None => out.push((r.name.to_string(), r.scope.to_string(), r.grants_rule.to_string())),
        }
    }
    out
}

/// CAST-O7: the once records this activation's casts placed on unit `u` that its spends took.
fn cast_spent_of(after: &State, u: usize) -> impl Iterator<Item = &LiveMod> {
    after.cast_buffs.iter().filter(move |(cu, _, spent)| *cu == u && *spent).map(|(_, r, _)| r)
}

/// CC-8c: the effects this activation's casts landed on unit `u` and nothing spent, in placement order.
fn cast_gained_of(after: &State, u: usize) -> impl Iterator<Item = &LiveMod> {
    after.cast_buffs.iter().filter(move |(cu, _, spent)| *cu == u && !*spent).map(|(_, r, _)| r)
}

/// The names `after` holds that `before` did not, in `after`'s order.
fn gained(before: &[String], after: &[String]) -> Vec<String> {
    after.iter().filter(|n| !before.contains(n)).cloned().collect()
}

/// P4.0-4f: the marker pools the inventory marks table-owned, in `State` declaration order, AFTER.
fn pools_of(s: &State, u: usize) -> Vec<(&'static str, i64)> {
    vec![
        ("spot_markers", s.spot_markers[u]),
        ("tag_markers", s.tag_markers[u]),
        ("piercing_tag_markers", s.piercing_tag_markers[u]),
        ("vengeance_markers", s.vengeance_markers[u]),
    ]
}

/// P4.0-4e: every round stamp the inventory marks table-owned, in `State` declaration order, AFTER.
fn stamps_of(s: &State, u: usize) -> Vec<(&'static str, i64)> {
    vec![
        ("vs_mark_round", s.vs_mark_round[u]),
        ("hit_and_run_round", s.hit_and_run_round[u]),
        ("moved_round", s.moved_round[u]),
        ("reckless_rolled_round", s.reckless_rolled_round[u]),
        ("reckless_ap_round", s.reckless_ap_round[u]),
        ("reckless_backfire_round", s.reckless_backfire_round[u]),
        ("versatile_pick_round", s.versatile_pick_round[u]),
        ("retreating_strike_round", s.retreating_strike_round[u]),
        ("mind_control_moved_round", s.mind_control_moved_round[u]),
        ("growth_strike_round", s.growth_strike_round[u]),
        ("spot_round", s.spot_round[u]),
        ("piercing_spot_round", s.piercing_spot_round[u]),
    ]
}

/// Every unit whose alive, shaken, positions or moved_round changed. `removed`
/// holds the positions of `before` that no longer appear in `after`, by exact
/// f64 equality: removal shifts slots but never edits a survivor.
pub fn delta_of(before: &State, after: &State) -> Vec<UnitDelta> {
    let mut out = Vec::new();
    for (u, key) in before.roster.keys.iter().enumerate() {
        let (b, a) = (&before.positions[u], &after.positions[u]);
        let (mut removed, mut j) = (Vec::new(), 0);
        for (i, p) in b.iter().enumerate() {
            if a.get(j) == Some(p) {
                j += 1;
            } else {
                removed.push(i);
            }
        }
        // `a` is not `b` minus some entries: a survivor was edited, i.e. a model moved.
        let moved = j < a.len() || before.moved_round.get(u) != after.moved_round.get(u);
        let unknown = moved && a.len() < b.len();
        if j < a.len() || unknown {
            removed.clear();
        }
        let stamps_changed = stamps_of(before, u) != stamps_of(after, u);
        let pools_changed = pools_of(before, u) != pools_of(after, u);
        if b != a || before.alive[u] != after.alive[u] || before.shaken[u] != after.shaken[u] || moved
            || before.fatigued[u] != after.fatigued[u] || before.casts[u] != after.casts[u]
            || stamps_changed || pools_changed
            || before.versatile_pick_mode[u] != after.versatile_pick_mode[u]
            || before.feats_used[u] != after.feats_used[u]
            || before.limited_used[u] != after.limited_used[u]
            || before.storm_used[u] != after.storm_used[u]
            || before.precision_used[u] != after.precision_used[u]
            || before.growth_markers[u] != after.growth_markers[u]
            || before.piercing_tag_used[u] != after.piercing_tag_used[u]
            || before.piercing_tag_persistent[u] != after.piercing_tag_persistent[u]
            || before.surprise_attack_used[u] != after.surprise_attack_used[u]
            || before.buffs[u] != after.buffs[u]
            || cast_spent_of(after, u).next().is_some()
            || cast_gained_of(after, u).next().is_some()
        {
            out.push(UnitDelta {
                key: key.clone(),
                removed,
                shaken: after.shaken[u],
                alive: after.alive[u],
                moved,
                unknown,
                positions: if moved { a.clone() } else { Vec::new() },
                fatigued: after.fatigued[u],
                casts: after.casts[u],
                stamps: stamps_of(after, u),
                pools: pools_of(after, u),
                versatile_pick_mode: after.versatile_pick_mode[u],
                feats_used: gained(&before.feats_used[u], &after.feats_used[u]),
                limited_used: gained(&before.limited_used[u], &after.limited_used[u]),
                storm_used: gained(&before.storm_used[u], &after.storm_used[u]),
                precision_used: gained(&before.precision_used[u], &after.precision_used[u]),
                growth_markers: after.growth_markers[u],
                piercing_tag_used: after.piercing_tag_used[u],
                piercing_tag_persistent: after.piercing_tag_persistent[u],
                surprise_attack_used: after.surprise_attack_used[u],
                buffs_spent: spent_buffs(&before.buffs[u], after, u),
                buffs_gained: cast_gained_of(after, u).map(|r| r.name.to_string()).collect(),
                marks_left: marks_left(&before.buffs[u], after, u),
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use Input::{Begin, Cancel, Faces};

    /// A `Placed` without walked paths.
    fn placed(at: Vec<[f64; 3]>) -> Input {
        Input::Placed { at, trails: Vec::new() }
    }

    fn intent(kind: i64, shoot: Option<&str>) -> Input {
        Input::Intent { kind, shoot: shoot.map(String::from), split: None, charge: None, no_step: false }
    }

    /// A planned cast with the given `seq` and every other field at its default.
    fn cast(seq: i64) -> Input {
        Input::Cast(CastInput { seq, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], ..Default::default() })
    }

    fn refused(t: &[Input], index: usize, reason: &str) {
        assert_eq!(order_check("Squad", t), Err((index, reason.to_string())), "{t:?}");
    }

    #[test]
    fn rule1_the_first_input_must_be_begin() {
        refused(&[intent(ADVANCE, None)], 0, "the activation was not started");
    }

    #[test]
    fn rule2_a_second_begin_is_refused() {
        refused(&[Begin, placed(vec![]), Begin], 2, "the activation is already started");
    }

    #[test]
    fn rule3_nothing_after_a_cancel() {
        refused(&[Begin, Cancel, placed(vec![])], 2, "the activation is over");
    }

    #[test]
    fn rule4_cancel_only_until_the_first_die() {
        refused(&[Begin, intent(ADVANCE, None), Faces(vec![3]), Cancel], 3, "cancel is not possible after the first die");
    }

    #[test]
    fn rule5_faces_need_a_declared_action() {
        refused(&[Begin, placed(vec![]), Faces(vec![4])], 2, "faces before the action was declared");
    }

    #[test]
    fn rule6_one_action_per_activation() {
        refused(&[Begin, intent(HOLD, None), intent(ADVANCE, None)], 2, "one action per activation");
    }

    #[test]
    fn rule7_no_move_after_the_unit_shot() {
        let t = [Begin, intent(ADVANCE, Some("Rifles")), Faces(vec![5]), placed(vec![[0.0; 3]])];
        refused(&t, 3, "Squad has already shot this round — it cannot move now");
        assert_eq!(order_check("Squad", &[Begin, intent(ADVANCE, None), placed(vec![])]), Ok(()));
    }

    #[test]
    fn rule8_reposition_is_not_on_the_step_path_and_a_charge_names_its_target() {
        refused(&[Begin, placed(vec![]), intent(REPOSITION, None)], 2, "not on the step path yet");
        refused(&[Begin, intent(CHARGE, None)], 1, "a charge names its target");
        let charge = Input::Intent { kind: CHARGE, shoot: None, split: None, charge: Some("b".into()), no_step: false };
        assert_eq!(order_check("Squad", &[Begin, charge, Faces(vec![4])]), Ok(()));
    }

    /// CC-3: a cast sits after the declared action and before the first die; `seq` starts at 0 or more and rises.
    /// RED: the `Cast` arms removed from `order_check` -> every refusal below is `Ok`.
    #[test]
    fn rule9_a_cast_sits_after_the_intent_and_before_the_first_die_with_a_rising_seq() {
        let low = "is too low: seq is 0 or more and higher than the cast before";
        refused(&[Begin, cast(0)], 1, "a cast before the action was declared");
        refused(&[Begin, intent(HOLD, Some("b")), Faces(vec![3]), cast(0)], 3, "a cast after the first die");
        refused(&[Begin, intent(HOLD, Some("b")), cast(0), cast(0)], 3, &format!("cast seq 0 {low}"));
        refused(&[Begin, intent(HOLD, Some("b")), cast(1), cast(0)], 3, &format!("cast seq 0 {low}"));
        refused(&[Begin, intent(HOLD, Some("b")), cast(-1)], 2, &format!("cast seq -1 {low}"));
        refused(&[Begin, intent(HOLD, Some("b")), cast(0), Cancel, cast(1)], 4, "the activation is over");
        let ok = [Begin, placed(vec![]), intent(ADVANCE, None), cast(0), placed(vec![]), cast(1), cast(5), Faces(vec![4])];
        assert_eq!(order_check("Squad", &ok[..]), Ok(()));
    }

    #[test]
    fn moves_before_the_shooting_intent_are_fine() {
        let t = [Begin, placed(vec![[1.0, 0.0, 0.0]]), placed(vec![[2.0, 0.0, 0.0]]), intent(ADVANCE, Some("Rifles"))];
        assert_eq!(order_check("Squad", &t), Ok(()));
    }

    #[test]
    fn cancel_after_a_move_is_fine() {
        assert_eq!(order_check("Squad", &[Begin, placed(vec![[1.0, 0.0, 0.0]]), Cancel]), Ok(()));
    }

    #[test]
    fn begin_names_the_open_activation() {
        let err = begin_check(Some("A"), &[]).unwrap_err();
        assert_eq!(err.reason, "Finish A's activation first.");
        assert_eq!(err.line.rule, "begin_check");
        assert_eq!(err.line.text, err.reason);
        assert_eq!(begin_check(None, &[]), Ok(()));
    }

    /// Firefight step 7: `begin_check` refuses mixed game systems with reason + log line;
    /// same-system tables (including `gff` + `gff`) open.
    #[test]
    fn begin_refuses_mixed_systems_and_opens_same_system() {
        assert_eq!(begin_check(None, &["gff", "gff"]), Ok(()));
        assert_eq!(begin_check(None, &["gf", ""]), Ok(()));
        assert_eq!(begin_check(None, &["GF", "gf"]), Ok(()));
        let err = begin_check(None, &["gf", "gff"]).unwrap_err();
        assert!(err.reason.contains("lists of two game systems"), "reason: {}", err.reason);
        assert!(err.reason.contains("gf") && err.reason.contains("gff"), "reason: {}", err.reason);
        assert_eq!(err.line.rule, "mixed_systems");
        assert_eq!(err.line.category, Category::General);
        assert_eq!(err.line.text, err.reason);
        assert!(begin_check(None, &["aof", "gff"]).is_err());
    }

    /// Two models at the origin and 1 m east, the second one moved `dx` inches east and `dy` up.
    fn shifted(dx: f64, dy: f64) -> Vec<[f64; 3]> {
        vec![[0.0, 0.0, 0.0], [1.0 + dx * INCHES_TO_METERS, dy * INCHES_TO_METERS, 0.0]]
    }

    #[test]
    fn not_moving_is_hold() {
        let start = shifted(0.0, 0.0);
        assert_eq!(effective_kind(ADVANCE, &start, None), HOLD);
        assert_eq!(effective_kind(ADVANCE, &start, Some(&shifted(0.05, 0.0))), HOLD, "inside the 0.1\" floor");
        assert_eq!(effective_kind(ADVANCE, &start, Some(&shifted(0.0, 3.0))), HOLD, "height is not horizontal");
        assert_eq!(effective_kind(ADVANCE, &start, Some(&shifted(0.5, 0.0))), ADVANCE);
        assert_eq!(effective_kind(RUSH, &start, Some(&shifted(0.5, 0.0))), RUSH);
        assert_eq!(effective_kind(RUSH, &start, None), HOLD);
    }

    #[test]
    fn only_advance_and_rush_fall_back_to_hold() {
        let start = shifted(0.0, 0.0);
        assert_eq!(effective_kind(HOLD, &start, Some(&shifted(0.5, 0.0))), HOLD);
        assert_eq!(effective_kind(CHARGE, &start, None), CHARGE);
        assert_eq!(effective_kind(ADVANCE, &start, Some(&start[..1])), ADVANCE, "a short placement is not proven still");
    }

    // ---- step 11: a whole activation through the step API ----

    use crate::dice::Roll;
    use crate::sim::tests::volley_landings::volley_line;
    use crate::unit::ShootProfile;

    fn seams() -> Seams {
        Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() }
    }

    /// The step-1 driver loop: roll each `NeedRoll` from the seeded tray `seed`
    /// and append it; returns the last answer and the roll records it asked for.
    fn drive(statics: &[UnitStatic], st: &State, mut t: Vec<Input>, seed: i64) -> (ActStep, Vec<Roll>) {
        let (mut dice, mut rolls) = (Tray::seeded(seed), Vec::new());
        dice.set_zero_draws(true); // exactly the faces asked for: the feed already applied the epoch
        loop {
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { faces, kind, count, target, owner, .. } => {
                    let f = dice.roll(faces);
                    rolls.push(Roll { kind, count, target, faces: f.clone(), owner });
                    t.push(Faces(f));
                }
                other => return (other, rolls),
            }
        }
    }

    /// C-1: the step answer keeps the resolver's `unported` marks. A Strafing rifle in a normal volley
    /// (dice.rs `mark("strafing")`, the per-model split is not ported) answers `["strafing"]`, the
    /// plain rifle `[]` (RED: drop the field at the `Step::Done` arm and the Strafing side reads `[]`).
    #[test]
    fn a_done_step_answers_the_unported_marks() {
        let (st, mut statics) = volley_line();
        let marks = |statics: &[UnitStatic]| match drive(statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7).0 {
            ActStep::Done { unported, .. } => unported,
            other => panic!("{other:?}"),
        };
        assert_eq!(marks(&statics), Vec::<&str>::new());
        statics[0].shoot[0].strafing = true;
        assert_eq!(marks(&statics), vec!["strafing"]);
    }

    /// The stepped activation equals one straight seeded run, state and roll records alike; the
    /// straight run's non-tray stream differs (seed vs 0), so a draw from it would show here too.
    #[test]
    fn a_stepped_activation_equals_the_seeded_run() {
        let (st, statics) = volley_line();
        let (mut killed, mut shaken, mut morale) = (0, 0, 0);
        for seed in 0..200i64 {
            let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
            let (want, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, rolls) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            assert_eq!((&state.alive, &state.shaken), (&want.alive, &want.shaken), "seed {seed}");
            // The step asks for the morale die as "morale" (the table's kind); its record keeps the replay's "attack".
            morale += rolls.iter().filter(|r| r.kind == "morale").count();
            let fold = |r: Roll| Roll { kind: if r.kind == "morale" { "attack" } else { r.kind }, ..r };
            assert_eq!(rolls.into_iter().map(fold).collect::<Vec<_>>(), shot.rolls, "seed {seed}");
            assert_eq!(state, want, "seed {seed}");
            (killed, shaken) = (killed + (want.alive[2] < st.alive[2]) as i32, shaken + want.shaken[2] as i32);
        }
        assert!(killed > 0 && shaken > 0 && morale > 0, "fixture must kill, shake and test morale: {killed} {shaken} {morale}");
    }

    /// `volley_line` with split fire's second target: "bh" stands alone (not attached) 10" north of "a", which
    /// now carries a second weapon; the rifle's aim is "b", the pistol's is "bh".
    fn split_line() -> (State, Vec<UnitStatic>, Vec<SplitShot>) {
        let (mut st, mut statics) = volley_line();
        st.attached = std::rc::Rc::new(vec![Vec::new(); 4]);
        st.attached_to = std::rc::Rc::new(vec![None; 4]);
        st.positions[3] = vec![[0.0, 0.0, 10.0 * INCHES_TO_METERS]];
        statics[0].shoot.push(crate::unit::ShootProfile { name: "pistol".into(), attacks: 4, count: 1, range: 24, ..Default::default() });
        (statics[3].model_count, statics[3].wounds_max, statics[3].ctx.defense) = (1, vec![1], 4);
        let aim = |weapon: &str, target: &str| SplitShot { member: "a".into(), weapon: weapon.into(), target: target.into() };
        (st, statics, vec![aim("rifle", "b"), aim("pistol", "bh")])
    }

    /// S1 shadow soak (a joined hero's weapons missing from the core's volley): "a" (at 0") advances 4" with its joined
    /// hero "ah" (at 2", a 6" pistol) and shoots "b" (at 12"). The table moves the hero with the host, so it stands 5" from
    /// "b" and fires; a placement that carries the hero's model after the host's does the same in the core. A host-only
    /// placement leaves "ah" behind at 10" and its pistol silent (the soak's mismatch). RED: drop the hero half of the
    /// placement in `resolve_with` -> the chain placement's volley has no "ah" roll either.
    #[test]
    fn a_chain_placement_moves_the_joined_hero_and_its_weapon_fires() {
        let (mut st, mut statics) = volley_line();
        let p = st.profiles.list[0].clone();
        st.profiles = std::rc::Rc::new(crate::state::Profiles { list: vec![p; 4], index: Default::default() }); // one per roster slot
        statics[1].shoot = vec![ShootProfile { name: "pistol".into(), attacks: 1, count: 1, range: 6, ..Default::default() }];
        let seams = Seams { hero_attach: true, moved_shoot: true, ..seams() };
        let x = |v: f64| [v * INCHES_TO_METERS, 0.0, 0.0];
        let hero_rolls = |at: Vec<[f64; 3]>| {
            let mut t = vec![Begin, Input::Placed { at, trails: Vec::new() }, intent(ADVANCE, Some("b"))];
            let mut n = 0;
            loop {
                match step_activation(&statics, &st, "a", &Terrain::default(), seams, &t, true) {
                    ActStep::NeedRoll { faces, owner, .. } => {
                        n += (owner == "ah") as i32;
                        t.push(Faces(vec![6; faces]));
                    }
                    ActStep::Done { .. } => return n,
                    other => panic!("{other:?}"),
                }
            }
        };
        assert_eq!(hero_rolls(vec![x(4.0)]), 0, "host-only placement: the hero stays at 10\" and its pistol is out of range");
        assert_eq!(hero_rolls(vec![x(4.0), x(7.0)]), 1, "the chain placement moves the hero to 5\": its pistol fires");
    }

    /// Split fire on the step API: an intent that carries `split` equals one straight seeded run with the
    /// same `Action.split`, state, roll records and lines alike, over 200 seeds. RED: carry `split: None` into the
    /// action (both targets are then pooled on "b", "bh" is never fired at and the rolls differ).
    #[test]
    fn a_split_fire_intent_equals_the_seeded_run_with_the_same_aim() {
        let (st, statics, aim) = split_line();
        let (mut both, mut pooled_differs) = (0, 0);
        for seed in 0..200i64 {
            let split = |split: Option<Vec<SplitShot>>| Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split, traced: None, teleport: None };
            let (want, shot) = resolve_stochastic_tray_on_board(&statics, &st, &split(Some(aim.clone())), &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, rolls) = drive(&statics, &st, vec![Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: Some(aim.clone()), charge: None, no_step: false }], seed);
            let ActStep::Done { state, lines, .. } = got else { panic!("seed {seed}: {got:?}") };
            let fold = |r: Roll| Roll { kind: if r.kind == "morale" { "attack" } else { r.kind }, ..r };
            assert_eq!(rolls.into_iter().map(fold).collect::<Vec<_>>(), shot.rolls, "seed {seed}");
            assert_eq!(state, want, "seed {seed}");
            // The step's own lines name each aimed target's volley, in the aim's group order.
            let said: Vec<&str> = lines.iter().map(|l| l.text.as_str()).filter(|t| t.starts_with("a fires at ")).collect();
            assert_eq!(said, ["a fires at b", "a fires at bh"], "seed {seed}");
            // The aim bites: both targets lose something here, and the pooled run (no aim) is another run.
            both += (want.wounds[2] != st.wounds[2] && want.alive[3] < st.alive[3]) as i32;
            let pooled = resolve_stochastic_tray_on_board(&statics, &st, &split(None), &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap().0;
            pooled_differs += (pooled != want) as i32;
        }
        assert!(both > 0 && pooled_differs > 0, "fixture must hurt both targets and differ from the pooled run: {both} {pooled_differs}");
    }

    // ---- P4.0-5: NeedChoice in the step API ----

    /// `volley_line` with "a" carrying one Takedown sniper shot into "b" (two Tough(3) models).
    fn takedown_line() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = volley_line();
        statics[0].shoot = vec![ShootProfile { name: "sniper".into(), takedown: true, attacks: 1, count: 1, range: 24, ..Default::default() }];
        (st, statics)
    }

    /// The fixture's choice id: stable (the shooter's and the target's roster keys).
    const TAKEDOWN_ID: &str = "takedown_model:a:b";

    /// One choice point: without a `Choice` the automatic pick stands (the last living slot); with
    /// `Input::Choice` answered, the OTHER model takes the Takedown wound. RED: drop the answer ->
    /// both runs equal; accept any slot -> the default's model is named again.
    #[test]
    fn a_takedown_choice_answered_explicitly_differs_from_the_default() {
        let (st, statics) = takedown_line();
        for seed in 0..200i64 {
            let (auto, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let answer = [Begin, intent(HOLD, Some("b")), Input::Choice { id: TAKEDOWN_ID.into(), option: "slot:0".into() }];
            let (explicit, _) = drive(&statics, &st, answer.to_vec(), seed);
            let (ActStep::Done { state: a, .. }, ActStep::Done { state: e, .. }) = (&auto, &explicit) else { continue };
            if a.wounds[2] == e.wounds[2] {
                continue; // no Takedown group landed on this seed
            }
            assert_eq!(a.wounds[2], vec![3, 2], "seed {seed}: the automatic pick is the last living slot");
            assert_eq!(e.wounds[2], vec![2, 3], "seed {seed}: the answer names slot 0");
            assert_eq!(a.alive[2], e.alive[2], "seed {seed}: the group is nonlethal, only the pick differs");
            return;
        }
        panic!("no seed in 0..200 landed a Takedown group");
    }

    /// The empty option asks the open choice: stable id, every living slot as an option, the answering
    /// unit's key as `owner`.
    #[test]
    fn an_empty_option_asks_the_choice_with_its_stable_id_and_slots() {
        let (st, statics) = takedown_line();
        let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: TAKEDOWN_ID.into(), option: String::new() }];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::NeedChoice { id, options, owner, .. } => {
                assert_eq!((id.as_str(), owner.as_str()), (TAKEDOWN_ID, "a"));
                assert_eq!(options, vec!["slot:0".to_string(), "slot:1".to_string()]);
            }
            other => panic!("expected NeedChoice, got {other:?}"),
        }
    }

    /// A wrong id and a wrong option are refusals at the choice's input, never a silent acceptance
    /// (RED: drop the option check -> a bogus `slot:9` resolves as the automatic pick).
    #[test]
    fn a_wrong_choice_id_or_option_is_refused() {
        let (st, statics) = takedown_line();
        let ask = |id: &str, option: &str| {
            let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: id.into(), option: option.into() }];
            step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true)
        };
        match ask("takedown_model:a:zzz", "slot:0") {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains(TAKEDOWN_ID), "{reason}"),
            other => panic!("a wrong id must be refused, got {other:?}"),
        }
        match ask(TAKEDOWN_ID, "slot:9") {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains("slot:9"), "{reason}"),
            other => panic!("a wrong option must be refused, got {other:?}"),
        }
    }

    // ---- the wound-allocation choice ----

    use crate::state::Kit;
    const ALLOC_ID: &str = "wound_alloc:a:b:0";

    /// `volley_line` with "b" a mixed-kit unit: two Tough(3) models (6 wounds) carrying different weapons; "a" fires 4 shots.
    fn mixed_line() -> (State, Vec<UnitStatic>) {
        let (mut st, statics) = volley_line();
        let kit = |w: u16| Kit { weapons: vec![w], equipment: 0, wounds_max: 3 };
        st.kits = vec![Rc::new(Vec::new()), Rc::new(Vec::new()), Rc::new(vec![kit(1), kit(2)]), Rc::new(Vec::new())];
        (st, statics)
    }

    /// The activation to its next answer: 4 hits, every save fails (4 unsaved wounds on "b"), morale passes; `choice` is the
    /// option of the wound-allocation `Choice` sent first (`Some("")` = only asked, `None` = no choice in the transcript).
    fn alloc(st: &State, statics: &[UnitStatic], choice: Option<&str>) -> ActStep {
        let mut t = vec![Begin, intent(HOLD, Some("b"))];
        t.extend(choice.map(|o| Input::Choice { id: ALLOC_ID.into(), option: o.into() }));
        loop {
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { faces, kind, .. } => t.push(Faces(vec![if kind == "defense" { 1 } else { 6 }; faces])),
                other => return other,
            }
            assert!(t.len() < 12, "{t:?}");
        }
    }

    /// No `Choice` in the transcript is today's landing, mixed kits or not: the stepped activation equals the seeded run.
    #[test]
    fn without_a_wound_allocation_choice_the_landing_is_the_automatic_one() {
        let (st, statics) = mixed_line();
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
        for seed in 0..200i64 {
            let (want, _) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            assert_eq!(state, want, "seed {seed}");
        }
    }

    /// The ask is answered once the saves are in (the wounds are unknown before): `NeedChoice` with the stable id, the target's
    /// living slots and the target as owner; asked before the dice, the dice come first.
    #[test]
    fn a_wound_allocation_ask_opens_after_the_saves() {
        let (st, statics) = mixed_line();
        match alloc(&st, &statics, Some("")) {
            ActStep::NeedChoice { id, options, owner, .. } => {
                assert_eq!((id.as_str(), owner.as_str()), (ALLOC_ID, "b"));
                assert_eq!(options, vec!["slot:0".to_string(), "slot:1".to_string()]);
            }
            other => panic!("expected NeedChoice, got {other:?}"),
        }
        let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: ALLOC_ID.into(), option: String::new() }];
        let first = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true);
        assert!(matches!(first, ActStep::NeedRoll { index: 0, .. }), "{first:?}");
    }

    /// The answer lands on the named slots, in order, a slot repeating (one wound each); the automatic landing (no choice
    /// in the transcript, today's) leaves the OTHER model standing. RED: ignore the answer -> both runs equal.
    #[test]
    fn an_answered_wound_allocation_lands_on_the_named_slots() {
        let (st, statics) = mixed_line();
        let survivor = |step: ActStep| match step {
            ActStep::Done { state, lines, .. } => (state.positions[2].clone(), state.wounds[2].clone(), lines),
            other => panic!("expected Done, got {other:?}"),
        };
        let (auto_at, auto_wounds, _) = survivor(alloc(&st, &statics, None));
        assert_eq!((auto_at.len(), auto_wounds.iter().sum::<i64>()), (1, 2), "fixture: auto kills one model, wounds the other");
        // Three wounds kill one model, the fourth wounds the other: kill the one the automatic order spares.
        let against = if auto_at[0] == st.positions[2][0] { "slot:0,slot:0,slot:0,slot:1" } else { "slot:1,slot:1,slot:1,slot:0" };
        let (at, wounds, lines) = survivor(alloc(&st, &statics, Some(against)));
        assert_ne!(at, auto_at, "the answer, not the automatic order, decides who survives");
        assert_eq!((at.len(), wounds), (1, vec![2]));
        assert!(lines.iter().any(|l| l.rule == "wound_alloc" && l.text == "b: the owner allocates 4 wounds"), "{lines:?}");
    }

    /// A slot that is no option, and an answer that is no slot list, are refused at the choice's input (RED: accept any slot ->
    /// the bogus pick lands nothing and the activation is `Done`).
    #[test]
    fn a_bad_wound_allocation_answer_is_refused() {
        let (st, statics) = mixed_line();
        for (option, said) in [("slot:5", "slot:5 is not an option of wound_alloc:a:b:0"), ("slot:0,slot:7", "slot:7 is not an option"), ("b", "is not a slot list")] {
            match alloc(&st, &statics, Some(option)) {
                ActStep::Refused { index: 2, reason } => assert!(reason.contains(said), "{option}: {reason}"),
                other => panic!("{option}: expected a refusal, got {other:?}"),
            }
        }
    }

    /// The owner places a Deadly(2) volley's wounds too: a wound goes to the next pick and deals X there; a wound
    /// the auto pick FORCES onto the already-wounded Tough model takes no pick. Two unsaved wounds, pick slot 1: slot 1 takes
    /// 2 of its 3, then the forced second wound finishes it - slot 0 stands; the automatic landing spares the other model.
    /// With no pool wound the ask still opens. RED: land Deadly by the automatic pick -> both runs equal.
    #[test]
    fn a_deadly_volley_lands_on_the_owners_picks_and_forced_wounds_take_none() {
        let (mut st, mut statics) = mixed_line();
        // Deadly reads the dynamic `Profile` of every roster entry (the fixture has one).
        st.profiles = Rc::new(crate::state::Profiles { list: vec![st.profiles.list[0].clone(); 4], index: Default::default() });
        statics[0].shoot = vec![crate::unit::ShootProfile { name: "lance".into(), attacks: 2, count: 1, range: 24, deadly: 2, ..Default::default() }];
        let ask = alloc(&st, &statics, Some(""));
        assert!(matches!(ask, ActStep::NeedChoice { ref id, .. } if id == ALLOC_ID), "{ask:?}");
        let end = |choice: Option<&str>| match alloc(&st, &statics, choice) {
            ActStep::Done { state, lines, .. } => (state.positions[2].clone(), state.wounds[2].clone(), lines),
            other => panic!("expected Done, got {other:?}"),
        };
        let (auto_at, ..) = end(None);
        let (at, wounds, lines) = end(Some("slot:1,slot:0"));
        assert_eq!((at.clone(), wounds), (vec![st.positions[2][0]], vec![3]), "slot 1 died, slot 0 stands untouched");
        assert_eq!(auto_at, vec![st.positions[2][1]], "the automatic landing kills the lead, slot 0");
        assert!(lines.iter().any(|l| l.text == "b: the owner allocates 1 wound"), "the forced wound took no pick: {lines:?}");
    }

    /// A split volley has one choice per target group, the group's place in the plan in its id. Two mixed-kit
    /// targets, the rifle aimed at "b" (group 0) and the pistol at "bh" (group 1): each answer lands on its own target, and an
    /// answer under the wrong group index is no answer (RED: id every group `:0` -> the "bh" answer is never read).
    #[test]
    fn a_split_volley_has_one_choice_per_target_group() {
        let (mut st, mut statics) = mixed_line();
        let kit = |w: u16| Kit { weapons: vec![w], equipment: 0, wounds_max: 3 };
        st.attached = Rc::new(vec![Vec::new(); 4]);
        st.attached_to = Rc::new(vec![None; 4]);
        st.positions[3] = vec![[12.0 * INCHES_TO_METERS, 0.0, 10.0 * INCHES_TO_METERS], [12.0 * INCHES_TO_METERS, 0.0, 12.5 * INCHES_TO_METERS]];
        (st.wounds[3], st.alive[3], st.kits[3]) = (vec![3, 3], 2, Rc::new(vec![kit(1), kit(2)]));
        Rc::make_mut(&mut st.radii)[3] = vec![INCHES_TO_METERS; 2];
        statics[3] = UnitStatic { name: "bh".into(), ..statics[2].clone() };
        statics[0].shoot.push(ShootProfile { name: "pistol".into(), attacks: 4, count: 1, range: 24, ..Default::default() });
        let aim = |weapon: &str, target: &str| crate::io::SplitShot { member: "a".into(), weapon: weapon.into(), target: target.into() };
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: Some(vec![aim("rifle", "b"), aim("pistol", "bh")]), traced: None, teleport: None };
        // Every attack hits, every save fails, morale passes: run the activation to its end under the given answers.
        let run = |answers: &[(&str, &str)]| {
            let (mut faces, choices) = (Vec::<Vec<u8>>::new(), std::cell::RefCell::new(Vec::new()));
            loop {
                let resolve = |tray: &mut Tray| {
                    for (id, o) in answers {
                        tray.offer_wound_alloc((*id).into(), Some(o.split(',').map(|s| s[5..].parse().unwrap()).collect()));
                    }
                    let out = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams(), &mut GodotRng::new(0), tray);
                    *choices.borrow_mut() = tray.feed().unwrap().wound_choices.clone();
                    out
                };
                match step_with(&faces, resolve, |r| r.as_ref().map_or(&[][..], |(_, s)| s.rolls.as_slice())) {
                    Step::NeedRoll { faces: n, kind, .. } => faces.push(vec![if kind == "defense" { 1 } else { 6 }; n]),
                    Step::Done(Ok((state, _)), ..) => return (state, choices.take()),
                    other => panic!("{other:?}"),
                }
            }
        };
        // Both groups: three wounds kill slot 1, the fourth wounds slot 0 - slot 0 is the survivor, one wound down.
        let (id0, id1, against) = ("wound_alloc:a:b:0", "wound_alloc:a:bh:1", "slot:1,slot:1,slot:1,slot:0");
        let (end, seen) = run(&[(id0, against), (id1, against)]);
        for u in [2, 3] {
            assert_eq!((&end.positions[u], &end.wounds[u]), (&vec![st.positions[u][0]], &vec![2]), "unit {u}");
        }
        let reached: Vec<_> = seen.iter().filter_map(|c| c.reached.as_ref().map(|r| (c.id.as_str(), r.1.clone()))).collect();
        assert_eq!(reached, vec![(id0, vec![0, 1]), (id1, vec![0, 1])]);
        // The pistol's group is group 1: an answer under index 0 is never read, so "bh" lands automatically (slot 1 survives).
        let (end, seen) = run(&[(id0, against), ("wound_alloc:a:bh:0", against)]);
        assert_eq!(end.positions[3], vec![st.positions[3][1]]);
        assert!(seen[1].reached.is_none(), "{seen:?}");
    }

    /// An answer no landing asked for - the unit has no real choice here - is refused, not dropped (RED: ignore a stale answer ->
    /// `Done`).
    #[test]
    fn a_wound_allocation_answer_nobody_asked_for_is_refused() {
        let (mut st, statics) = mixed_line();
        let plain = Kit { weapons: vec![1], equipment: 0, wounds_max: 1 };
        st.kits[2] = Rc::new(vec![plain.clone(), plain]);
        match alloc(&st, &statics, Some("slot:0")) {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains("no wound allocation is open"), "{reason}"),
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    /// No choice where nothing is chosen: one kit and no Tough, or an answer that would wipe the unit. The ask finds nothing
    /// to open and the activation just ends.
    #[test]
    fn a_wound_allocation_ask_without_a_real_choice_just_resolves() {
        let (mut st, statics) = mixed_line();
        let plain = Kit { weapons: vec![1], equipment: 0, wounds_max: 1 };
        st.kits[2] = Rc::new(vec![plain.clone(), plain]);
        assert!(matches!(alloc(&st, &statics, Some("")), ActStep::Done { .. }), "one kit, no Tough");
        let (mut st, statics) = mixed_line();
        st.wounds[2] = vec![2, 2];
        assert!(matches!(alloc(&st, &statics, Some("")), ActStep::Done { .. }), "4 wounds kill both models: nothing to choose");
        let (st, statics) = mixed_line();
        let mut t = vec![Begin, intent(HOLD, Some("b")), Input::Choice { id: ALLOC_ID.into(), option: String::new() }];
        for faces in [vec![6; 4], vec![6; 4]] {
            t.push(Faces(faces)); // every attack hits, every save holds: no wound to allocate
        }
        let end = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true);
        assert!(matches!(end, ActStep::Done { .. }), "no unsaved wound, no choice: {end:?}");
    }

    /// O3: a unit that moved as a Rush cannot shoot (RED: drop the Rush check).
    #[test]
    fn a_rush_cannot_shoot() {        let (st, statics) = volley_line();
        let moved: Vec<[f64; 3]> = st.positions[0].iter().map(|p| [p[0] + 3.0 * INCHES_TO_METERS, p[1], p[2]]).collect();
        let t = [Begin, placed(moved), intent(RUSH, Some("b"))];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (2, "a rushed this activation - it cannot shoot.")),
            other => panic!("expected the O3 refusal, got {other:?}"),
        }
    }

    /// Not moving is Hold: a Rush with no placement resolves as the Hold run, die for die.
    #[test]
    fn a_rush_that_never_moved_is_the_hold_run() {
        let (st, statics) = volley_line();
        for seed in 0..20i64 {
            let (hold, hold_rolls) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let (rush, rush_rolls) = drive(&statics, &st, vec![Begin, intent(RUSH, Some("b"))], seed);
            let (ActStep::Done { state: h, .. }, ActStep::Done { state: r, .. }) = (&hold, &rush) else { panic!("seed {seed}: {hold:?} {rush:?}") };
            assert_eq!((h, &hold_rolls), (r, &rush_rolls), "seed {seed}");
        }
    }

    #[test]
    fn open_until_the_intent() {
        let (st, statics) = volley_line();
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        assert!(matches!(ask(&[Begin]), ActStep::Open));
        assert!(matches!(ask(&[intent(HOLD, None)]), ActStep::Refused { index: 0, .. }));
    }

    /// CC-3/CC-5c: a cast that SUCCEEDED has an effect the core does not resolve yet (a buff or debuff; a damage spell's hits are
    /// CC-5c/8b: a buff cast that succeeded now lands (CC-8b), so after its die the activation moves on to the volley
    /// (`NeedRoll` for the shot); a cancel before any die is the usual one; an order break still reads first.
    #[test]
    fn a_cast_that_succeeded_is_refused_at_its_index_until_the_core_resolves_effects() {
        let (st, statics) = caster_line(); // CC-5a: the cast must pass the static checks to get here
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        let start = [Begin, intent(HOLD, Some("b"))];
        let hit = [&start[..], &[Input::Cast(ward(0)), Faces(vec![6])]].concat();
        assert!(matches!(ask(&hit), ActStep::NeedRoll { kind: "attack", .. }), "CC-8b: buff resolves and moves on to the volley");
        let two = [&start[..], &[Input::Cast(bolt(0)), Input::Cast(ward(1)), Faces(vec![1]), Faces(vec![6])]].concat();
        assert!(matches!(ask(&two), ActStep::NeedRoll { kind: "attack", .. }), "CC-8b: second cast (buff) resolves too");
        assert!(matches!(ask(&[Begin, intent(HOLD, None), cast(0), Cancel]), ActStep::Cancelled { .. }), "no die yet: the usual cancel");
        assert!(matches!(ask(&[Begin, cast(0)]), ActStep::Refused { index: 1, reason } if reason == "a cast before the action was declared"));
        // the same transcript without the cast is untouched
        assert!(matches!(ask(&[Begin, intent(HOLD, Some("b"))]), ActStep::NeedRoll { .. }));
    }

    // ---- CC-5a: the static checks on a planned cast ----

    /// "a" holds a damage spell ("Bolt"), a kind the core does not know ("Mend All"), a buff ("Ward") and a utility spell ("Dread");
    /// everything else is `volley_line`'s.
    fn caster_line() -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = volley_line();
        let spell = |name: &str, kind: &str| crate::rules::Spell { name: name.into(), effect_kind: kind.into(), threshold: 1, target_count: 1, ..Default::default() };
        for u in [0, 1] {
            (statics[u].is_caster, statics[u].spells) = (true, vec![spell("Bolt", "damage"), spell("Mend All", "heal"), spell("Ward", "buff"), spell("Dread", "utility")]);
        }
        (st, statics)
    }

    fn bolt(seq: i64) -> CastInput {
        CastInput { seq, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], ..Default::default() }
    }

    /// The buff: its effect is CC-8b's, so a hit on its die is still refused.
    fn ward(seq: i64) -> CastInput {
        CastInput { spell: "Ward".into(), ..bolt(seq) }
    }

    /// CC-5a: a cast the core cannot take is refused with its OWN sentence at its input's index, and a bad cast behind a good
    /// one is still found (the checks run before the "not resolved yet" refusal). RED: a check removed -> the case reads the
    /// "casts are not resolved by the core yet" sentence instead; compared by exact name (`bolt` is not `Bolt`).
    #[test]
    fn a_cast_the_core_cannot_take_is_refused_with_its_own_sentence_at_its_index() {
        let (st, statics) = caster_line();
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        let start = [Begin, intent(HOLD, Some("b"))];
        for (c, why) in [
            (CastInput { caster: "zz".into(), ..bolt(0) }, "cast 0: zz is no unit of this game"),
            (CastInput { spell: "bolt".into(), ..bolt(0) }, "cast 0: a has no spell named bolt"),
            (CastInput { spell: "Mend All".into(), ..bolt(0) }, "cast 0: the core does not resolve heal spells yet (Mend All)"),
            (CastInput { targets: vec!["b".into(), "zz".into()], ..bolt(0) }, "cast 0: zz is no unit of this game (a target of Bolt)"),
            (CastInput { open: true, ..bolt(0) }, "cast 0: a foe's answer to Bolt cannot be asked yet"),
            (CastInput { targets: vec![], ..bolt(0) }, "cast 0: Bolt has no targets"),
            (CastInput { conduit: "zz".into(), ..bolt(0) }, "cast 0: zz is no unit of this game (a conduit for Bolt)"),
        ] {
            let ActStep::Refused { index, reason } = ask(&[&start[..], &[Input::Cast(c.clone())]].concat()) else { panic!("{c:?}") };
            assert_eq!((index, reason.as_str()), (2, why), "{c:?}");
        }
        // a valid cast asks its die (CC-5c); a bad one BEHIND it is found first, at its own index
        assert!(matches!(ask(&[&start[..], &[Input::Cast(bolt(0))]].concat()), ActStep::NeedRoll { kind: "cast", .. }));
        let t = [&start[..], &[Input::Cast(bolt(0)), Input::Cast(CastInput { spell: "Nope".into(), ..bolt(1) })]].concat();
        assert!(matches!(ask(&t), ActStep::Refused { index: 3, reason } if reason == "cast 1: a has no spell named Nope"));
    }

    /// The board of the casts that end before any die: "b" is wiped out (a fizzle for anyone casting at it), "ah" is down (a skip for
    /// its casts); "a" holds 3 tokens, "ah" 3, "bh" 1.
    fn wiped_line() -> (State, Vec<UnitStatic>) {
        let (mut st, statics) = caster_line();
        st.casts = vec![3, 3, 0, 1];
        for u in [1, 2] {
            (st.alive[u], st.positions[u], st.wounds[u]) = (0, Vec::new(), Vec::new());
        }
        (st, statics)
    }

    /// CC-5b: casts that end before any die are TAKEN, and their tokens are spent exactly as the lists say, in plan order: "a"
    /// pays threshold 1 for a cast at the wiped-out "b" (a fizzle, one line) with "ah" paying a boost of 1 and "bh" the interference
    /// of 1; then the downed "ah" "casts" (a silent skip) and still pays its threshold. RED: the boost payers ignored in the spend
    /// -> "ah" keeps a token it paid.
    #[test]
    fn a_cast_that_ends_before_any_die_is_taken_and_spends_its_tokens_exactly() {
        let (st, statics) = wiped_line();
        let fizzle = CastInput { threshold: 1, boost: 1, boost_sources: vec![("ah".into(), 1)], interference: 1, interference_sources: vec![("bh".into(), 1)], ..bolt(0) };
        let skip = CastInput { caster: "ah".into(), threshold: 1, ..bolt(1) };
        let t = [Begin, intent(HOLD, None), Input::Cast(fizzle), Input::Cast(skip)];
        let ActStep::Done { state, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) else { panic!("taken") };
        assert_eq!(state.casts, vec![2, 1, 0, 0], "a paid 1, ah 1 (boost) + 1 (its own threshold), bh 1");
        let said: Vec<_> = lines.iter().map(|l| (l.rule, l.side, l.text.as_str())).collect();
        assert_eq!(said, [("cast", 0, "a's Bolt fizzles — no target remains")], "the skip says nothing");
    }

    /// CC-5b: a cast the core cannot pay is refused at its input's index before any die, with the payer named: the caster short of its
    /// threshold, a payer short of its share, the SECOND cast short because the first took the tokens, an unknown payer, a payer
    /// list that does not add up to the boost / interference named, a negative spend.
    #[test]
    fn a_cast_the_core_cannot_pay_for_is_refused_at_its_index() {
        let (mut st, statics) = wiped_line();
        st.casts = vec![3, 1, 0, 1]; // "ah" holds ONE token
        let ask = |casts: Vec<CastInput>| {
            let t = [vec![Begin, intent(HOLD, None)], casts.into_iter().map(Input::Cast).collect()].concat();
            step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true)
        };
        let pay = |key: &str, n: i64| vec![(key.to_string(), n)];
        for (c, why) in [
            (CastInput { caster: "ah".into(), threshold: 2, ..bolt(0) }, "cast 0: ah holds 1 token(s) but Bolt asks 2 of it"),
            (CastInput { boost: 1, boost_sources: pay("b", 1), ..bolt(0) }, "cast 0: b holds 0 token(s) but Bolt asks 1 of it"),
            (CastInput { interference: 1, interference_sources: pay("zz", 1), ..bolt(0) }, "cast 0: zz is no unit of this game (a payer for Bolt)"),
            (CastInput { boost: 2, boost_sources: pay("ah", 1), ..bolt(0) }, "cast 0: Bolt has boost 2 but its payers give 1"),
            (CastInput { interference: 1, ..bolt(0) }, "cast 0: Bolt has interference 1 but its payers give 0"),
            (CastInput { threshold: -1, ..bolt(0) }, "cast 0: a holds 3 token(s) but Bolt asks -1 of it"),
        ] {
            let got = ask(vec![c.clone()]);
            let ActStep::Refused { index, reason } = got else { panic!("{c:?}: {got:?}") };
            assert_eq!((index, reason.as_str()), (2, why), "{c:?}");
        }
        // "ah" holds ONE token: the first cast takes it, the second finds it gone (refused at ITS index, 3)
        let (first, second) = (CastInput { caster: "ah".into(), threshold: 1, ..bolt(0) }, CastInput { caster: "ah".into(), threshold: 1, ..bolt(1) });
        assert!(matches!(ask(vec![first, second]), ActStep::Refused { index: 3, reason } if reason == "cast 1: ah holds 0 token(s) but Bolt asks 1 of it"));
    }

    /// The board of the cast die: "a" is the caster "Mystic" (4 tokens), "b" the target "Foe", "ah" a friendly unit "Hero" joined to "a".
    fn die_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = caster_line();
        (statics[0].name, statics[2].name, statics[1].name) = ("Mystic".into(), "Foe".into(), "Hero".into());
        st.casts = vec![4, 2, 0, 0];
        (st, statics)
    }

    /// Asks `t` through the core and answers each `NeedRoll` with the next of `faces`; the last answer and how many rolls were asked.
    fn answer_dice(statics: &[UnitStatic], st: &State, mut t: Vec<Input>, faces: &[u8]) -> (ActStep, usize) {
        let mut next = faces.iter();
        let mut asked = 0;
        loop {
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { .. } if next.len() > 0 => {
                    asked += 1;
                    t.push(Faces(vec![*next.next().unwrap()]));
                }
                other => return (other, asked),
            }
        }
    }

    /// CC-5c: the cast die and the lines up to it, byte for byte the table's (golden_cast_effects `buff_self` / `casting_once`).
    /// The die is kind "cast", count 1, the caster's; the activating unit's name is on the announce line, the caster's on the
    /// needs line (a joined hero casts: the activating "Mystic" announces, "Hero" needs). A failed die is taken: its result line, the tokens paid, the
    /// casting once-record spent; a success is refused. RED: boost / interference left out of the target, the base not moved by
    /// the net first, the once-record kept, the die's kind or owner changed.
    #[test]
    fn a_cast_asks_its_die_and_says_the_tables_lines_up_to_it() {
        let (mut st, statics) = die_line();
        let spell = |c: CastInput| [Begin, intent(HOLD, None), Input::Cast(CastInput { base: 4, threshold: c.threshold.max(1), ..c })];
        // a plain cast: asked first, the lines said before the starved draw are the announce and the needs line
        let ActStep::NeedRoll { index, faces, kind, count, target, owner, owner_key, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &spell(bolt(0)), true) else { panic!("asks the die") };
        let said = lines.iter().map(|l| (l.rule, l.side, l.text.as_str())).collect::<Vec<_>>();
        assert_eq!((index, faces, kind, count, target, owner.as_str(), owner_key.as_str()), (0, 1, "cast", 1, 4, "Mystic", "a"));
        assert_eq!(said, [("cast", 0, "Mystic casts Bolt at Foe"), ("cast", 0, "Mystic casts Bolt at Foe \u{2014} needs 4+ (1 token)")]);
        // a failed die is taken: the result line, the tokens paid, nothing else changes
        let (done, asked) = answer_dice(&statics, &st, spell(bolt(0)).to_vec(), &[1]);
        let ActStep::Done { state, lines, .. } = done else { panic!("a failed cast is taken: {done:?}") };
        assert_eq!(lines.last().map(|l| l.text.as_str()), Some("Bolt: cast roll 1 vs 4+ \u{2014} FAILED"));
        assert_eq!((state.casts.clone(), asked), (vec![3, 2, 0, 0], 1));
        // CC-8b: an effect-less buff resolves to Done; a damage spell without hits is taken too
        assert!(matches!(answer_dice(&statics, &st, spell(ward(0)).to_vec(), &[6]).0, ActStep::Done { .. }));
        assert!(matches!(answer_dice(&statics, &st, spell(bolt(0)).to_vec(), &[6]).0, ActStep::Done { .. }), "hits 0: nothing to save");
        // a joined hero casts: the activating unit's name announces, the hero's names the cast; boost and interference move the target 4 -> 3
        let hero = CastInput { caster: "ah".into(), boost: 2, boost_sources: vec![("ah".into(), 2)], interference: 1, interference_sources: vec![("bh".into(), 1)], threshold: 2, ..bolt(0) };
        st.casts = vec![4, 4, 0, 1];
        let ActStep::NeedRoll { target, owner, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &spell(hero), true) else { panic!("asks the die") };
        assert_eq!((target, owner.as_str()), (3, "Hero"));
        assert_eq!(lines.iter().map(|l| l.text.as_str()).collect::<Vec<_>>(), ["Mystic casts Bolt at Foe", "Hero casts Bolt at Foe \u{2014} needs 3+ (2 tokens, +2 boost, -1 interference)"]);
    }

    /// CC-5c: the lines before the cast die and the die's own shape equal CC-2's goldens (`golden_cast_effects.json`: `buff_self`,
    /// `boost_interference`, `casting_once`, recorded from the table with the core off), line for line: the core's lines are the
    /// golden's but for the tray's own "AI (...)" line and the result line (said after the die).
    #[test]
    fn the_lines_before_the_die_equal_the_cc2_goldens() {
        use crate::mods::LiveMod;
        let golden: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(format!("{}/../../test/fixtures/one_core/golden_cast_effects.json", env!("CARGO_MANIFEST_DIR"))).expect("the CC-2 golden")).unwrap();
        let focus = LiveMod { move_mod: 0, range_in: 0, hit_mod: 0, casting_mod: 1, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: true, name: Rc::from("Focus") };
        let me = |c: CastInput| CastInput { caster: "a".into(), spell: "Warding Chant".into(), targets: vec!["a".into()], base: 4, threshold: c.threshold.max(1), ..c };
        let mut seen = 0;
        for (scenario, cast, buffs, roll) in [
            ("buff_self", me(bolt(0)), vec![], "cast|attack|1x4+|AI (Mystic)|"),
            ("boost_interference", me(CastInput { threshold: 2, boost: 2, boost_sources: vec![("a".into(), 2)], interference: 1, interference_sources: vec![("bh".into(), 1)], ..bolt(0) }), vec![], "cast|attack|1x3+|AI (Mystic)|"),
            ("casting_once", me(bolt(0)), vec![focus], "cast|attack|1x3+|AI (Mystic)|"),
        ] {
            let case = golden["cases"].as_array().unwrap().iter().find(|c| c["scenario"] == scenario).unwrap();
            let (mut st, mut statics) = die_line();
            (statics[0].spells[0].name, statics[0].spells[0].effect_kind) = ("Warding Chant".into(), "buff".into()); // the golden's spell is a buff
            (statics[2].name, st.casts, st.buffs[0]) = ("Foe".into(), vec![6, 0, 0, 1], buffs);
            let t = [Begin, intent(HOLD, None), Input::Cast(cast)];
            let ActStep::NeedRoll { count, target, owner, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) else { panic!("{scenario}: asks the die") };
            let ours: Vec<String> = lines.iter().map(|l| format!("COMBAT|{}", l.text)).collect();
            let want: Vec<String> = case["lines"].as_array().unwrap().iter().map(|l| l.as_str().unwrap().to_string()).take_while(|l| !l.starts_with("COMBAT|AI (")).collect();
            assert_eq!(ours, want, "{scenario}");
            assert!(case["extra"]["rolls"][0].as_str().unwrap().starts_with(roll), "{scenario}: {:?}", case["extra"]["rolls"]);
            assert_eq!(format!("cast|attack|{count}x{target}+|AI ({owner})|"), roll, "{scenario}");
            seen += 1;
        }
        assert_eq!(seen, 3);
    }

    /// CC-5c: the casting net moves the BASE first and is clamped to 2..6, boost and interference move the clamped result (the
    /// table's double clamp: base 4, net +3, interference 2 is 4+, not the single clamp's 3+). The line names the notes in the
    /// table's order: the caster's records, then the Spell Amplifier; the once-record is spent by the roll even when it fails.
    #[test]
    fn the_casting_net_moves_the_base_and_the_once_record_is_spent_by_the_roll() {
        use crate::mods::LiveMod;
        let (mut st, mut statics) = die_line();
        statics[0].spell_amplifier_casting_mod = 2;
        let focus = LiveMod { move_mod: 0, range_in: 0, hit_mod: 0, casting_mod: 1, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: true, name: Rc::from("Focus") };
        st.buffs[0] = vec![focus];
        let cast = |c: CastInput| [Begin, intent(HOLD, None), Input::Cast(CastInput { base: 4, threshold: 1, ..c })];
        let ActStep::NeedRoll { target, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &cast(bolt(0)), true) else { panic!("asks the die") };
        assert_eq!(target, 2, "4 - 3 clamps to 2");
        assert_eq!(lines[0].text, "+3 to casting rolls (Focus +1, Spell Amplifier +2) \u{2014} Mystic casts on 2+ (base 4+)");
        let counter = CastInput { interference: 2, interference_sources: vec![("bh".into(), 2)], ..bolt(0) };
        st.casts = vec![4, 0, 0, 2];
        let ActStep::NeedRoll { target, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &cast(counter.clone()), true) else { panic!("asks the die") };
        assert_eq!(target, 4, "clamp(4 - 3) = 2, then + 2 interference");
        let (done, _) = answer_dice(&statics, &st, cast(counter).to_vec(), &[1]);
        let ActStep::Done { state, .. } = done else { panic!("a failed cast is taken") };
        assert!(state.buffs[0].is_empty(), "the Focus once-record is spent by the roll: {:?}", state.buffs[0]);
    }

    /// CC-5c: the cast comes AFTER the activation's own Dangerous test (the core's order), and a Shaken friendly battery that
    /// cannot lend says so before the announce. RED: the cast slot before the Dangerous test -> the first roll is the cast.
    #[test]
    fn the_cast_die_follows_the_dangerous_test_and_a_shaken_battery_says_so() {
        use crate::terrain::{CellParams, PlainTerrain, DANGEROUS};
        let (mut st, mut statics) = die_line();
        st.positions[0] = vec![[4.0 * INCHES_TO_METERS, 0.0, 0.0], [5.0 * INCHES_TO_METERS, 0.0, 0.0]];
        (st.wounds[0], st.alive[0]) = (vec![1, 1], 2);
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS / 2.0; 2];
        (statics[1].is_caster, statics[1].spell_accumulator) = (false, true);
        st.shaken[1] = true;
        let cells = vec![[16.0, 14.0, DANGEROUS as f64], [16.0, 15.0, DANGEROUS as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        let board = Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params, ..Default::default() });
        let t = vec![Begin, intent(HOLD, None), Input::Cast(CastInput { base: 4, threshold: 1, ..bolt(0) })];
        let first = step_activation(&statics, &st, "a", &board, Seams { dangerous_end_morale: true, ..seams() }, &t, true);
        assert!(matches!(&first, ActStep::NeedRoll { kind: "dangerous", owner_key, count: 2, .. } if owner_key == "a"), "the Dangerous test first, named for its count-the-1s line: {first:?}");
        let t = [t, vec![Faces(vec![6, 6])]].concat();
        let ActStep::NeedRoll { kind: "cast", lines, .. } = step_activation(&statics, &st, "a", &board, Seams { dangerous_end_morale: true, ..seams() }, &t, true) else { panic!("then the cast die") };
        assert_eq!(lines.iter().map(|l| l.text.as_str()).next(), Some("Spell Accumulator: Hero is Shaken \u{2014} its tokens do not feed friendly casters"));
    }

    /// CC-5d (item 1): a cast with `conduit != ""` is resolved instead of refused — shaken conduits and the active conduit log in
    /// the table's exact format (`main.gd:5633-5641`, centre via `geom::centre` in Godot's `str(Vector3)` format), the conduit mod
    /// joins the casting net first (`Spell Conduit +1`), and unknown conduit keys are refused at the cast's index.
    #[test]
    fn a_conduit_cast_applies_its_mod_and_logs_the_tables_lines() {
        use crate::mods::LiveMod;
        let (mut st, mut statics) = die_line();
        (statics[1].name, statics[1].spell_conduit, statics[1].spell_conduit_casting_mod) = ("Relay".into(), true, 1);
        st.positions[1] = vec![[0.0, 0.0, 0.0], [1.016, 0.0, 0.6096]]; // f32 centre = (0.508, 0.0, 0.3048)
        (st.wounds[1], st.alive[1]) = (vec![1, 1], 2);
        statics[3].name = "ShakenRelay".into();
        let c = CastInput { base: 4, threshold: 1, conduit: "ah".into(), conduit_shaken: vec!["bh".into()], ..bolt(0) };
        let t = vec![Begin, intent(HOLD, None), Input::Cast(c.clone())];
        let ActStep::NeedRoll { kind: "cast", target, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) else { panic!("conduit cast asks its die") };
        assert_eq!(target, 3, "base 4 - conduit +1 = 3+");
        let got: Vec<&str> = lines.iter().map(|l| l.text.as_str()).collect();
        assert_eq!(got, [
            "Spell Conduit: ShakenRelay is Shaken \u{2014} its conduit does not help Mystic cast",
            // main.gd:5639 prints "(%s)" around str(Vector3), which carries its own parens
            "Spell Conduit: Mystic casts as if standing at Relay ((0.508, 0.0, 0.3048))",
            "+1 to casting rolls (Spell Conduit +1) \u{2014} Mystic casts on 3+ (base 4+)",
            "Mystic casts Bolt at Foe",
            "Mystic casts Bolt at Foe \u{2014} needs 3+ (1 token)",
        ]);
        assert!(matches!(answer_dice(&statics, &st, t.clone(), &[1]).0, ActStep::Done { .. }), "a failed conduit cast is taken");
        // conduit note precedes casting records and Spell Amplifier (`caster_casting_net` solo_controller.gd:5228-5240)
        statics[0].spell_amplifier_casting_mod = 1;
        let focus = LiveMod { move_mod: 0, range_in: 0, hit_mod: 0, casting_mod: 1, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: true, name: Rc::from("Focus") };
        st.buffs[0] = vec![focus];
        let ActStep::NeedRoll { target, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) else { panic!("conduit + amp") };
        assert_eq!(target, 2, "4 - 3 clamps to 2+");
        assert_eq!(lines[2].text, "+3 to casting rolls (Spell Conduit +1, Focus +1, Spell Amplifier +1) \u{2014} Mystic casts on 2+ (base 4+)");
        // unknown conduit / shaken conduit is refused at its input index
        for bad in [CastInput { conduit: "zz".into(), ..c.clone() }, CastInput { conduit_shaken: vec!["zz".into()], ..c }] {
            let bt = vec![Begin, intent(HOLD, None), Input::Cast(bad)];
            assert!(matches!(step_activation(&statics, &st, "a", &Terrain::default(), seams(), &bt, true), ActStep::Refused { index: 2, .. }));
        }
    }

    /// CC-5d (item 2): a CastInput with empty `targets` is refused at its input index when the spell takes targets (`target_count > 0`),
    /// instead of fizzling via vacuous `all()`; an untargeted spell (`target_count == 0`) with empty `targets` is not refused.
    #[test]
    fn an_empty_target_list_is_refused_unless_the_spell_is_untargeted() {
        let (mut st, mut statics) = die_line();
        statics[0].spells.push(crate::rules::Spell { name: "Aura".into(), effect_kind: "buff".into(), threshold: 1, target_count: 0, ..Default::default() });
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        let empty = CastInput { targets: vec![], threshold: 1, ..bolt(0) };
        let ActStep::Refused { index, reason } = ask(&[Begin, intent(HOLD, None), Input::Cast(empty)]) else { panic!("targeted spell with no targets must be refused") };
        assert_eq!((index, reason.as_str()), (2, "cast 0: Bolt has no targets"));
        let untargeted = CastInput { spell: "Aura".into(), targets: vec![], threshold: 1, ..bolt(0) };
        assert!(!matches!(ask(&[Begin, intent(HOLD, None), Input::Cast(untargeted)]), ActStep::Refused { .. }), "untargeted spell is not refused");
        let _ = &mut st;
    }

    /// CC-5d (item 3): the Shaken-battery line ports `solo_controller.shaken_lenders` (`solo_controller.gd:5802-5822`): reserve units
    /// are skipped, destroyed hosts are skipped (their living attached hero only appears at its own entry), and each surviving host
    /// walks `[host] + attached` in table unit order rather than plain roster order.
    #[test]
    fn the_shaken_battery_line_follows_the_tables_order_reserve_and_destroyed_rules() {
        let (mut st, statics) = die_line();
        let mut s_host = UnitStatic { name: "Host".into(), ..Default::default() };
        let s_bat = |n: &str| UnitStatic { name: n.into(), spell_accumulator: true, ..Default::default() };
        let s_caster = statics[0].clone();
        let s_foe = statics[2].clone();
        s_host.model_count = 1;
        let statics = vec![s_host, s_bat("ReserveBat"), s_bat("MidBat"), s_bat("HeroBat"), s_caster, s_foe];
        let keys: Vec<String> = ["h", "r", "m", "hb", "c", "f"].into_iter().map(String::from).collect();
        let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
        let n = keys.len();
        st.roster = Rc::new(crate::state::Roster { keys, index, profile: (0..n).collect() });
        st.profiles = Rc::new(crate::state::Profiles { list: vec![st.profiles.list[0].clone(); n], index: std::collections::HashMap::new() });
        st.player = vec![0, 0, 0, 0, 0, 1];
        st.alive = vec![1; n];
        st.activated = vec![false; n];
        st.shaken = vec![false, true, true, true, false, false];
        st.fatigued = vec![false; n];
        st.in_cover = vec![false; n];
        st.aircraft = vec![false; n];
        st.dormant = vec![false, true, false, false, false, false]; // ReserveBat is in reserve
        st.dormant_models = vec![0; n];
        st.dormant_wounds = vec![Vec::new(); n];
        st.casts = vec![0, 2, 2, 2, 4, 0];
        st.morale_bonus = vec![0; n];
        st.ambush_arrived_round = vec![-1; n];
        st.earliest_arrival_round = vec![-1; n];
        st.wound_frac = vec![1.0; n];
        st.positions = (0..n).map(|i| vec![[i as f64 * INCHES_TO_METERS, 0.0, 0.0]]).collect();
        st.wounds = vec![vec![1]; n];
        st.radii = Rc::new(vec![vec![INCHES_TO_METERS]; n]);
        st.mods = vec![crate::state::Mods::default(); n];
        st.mods_base = (0..n).map(|_| Rc::new(crate::state::Mods::default())).collect();
        st.attached = Rc::new(vec![vec![3], vec![], vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, Some(0), None, None]);
        st.los = vec![None; n];
        st.bands = vec![crate::state::Bands::default(); n];
        st.shroud = vec![None; n];
        st.charge_no_difficult = vec![false; n];
        st.charge_probe_r = vec![0.0; n];
        st.buffs = vec![Vec::new(); n];
        st.vs_mark_round = vec![-1; n];
        st.hit_and_run_round = vec![-1; n];
        st.moved_round = vec![-1; n];
        st.delayed_action_round = vec![-1; n];
        st.coordinate_via_round = vec![-1; n];
        st.reckless_rolled_round = vec![-1; n];
        st.reckless_ap_round = vec![-1; n];
        st.reckless_backfire_round = vec![-1; n];
        st.versatile_pick_round = vec![-1; n];
        st.versatile_pick_mode = vec![0; n];
        st.retreating_strike_round = vec![-1; n];
        st.mind_control_moved_round = vec![-1; n];
        st.growth_markers = vec![0; n];
        st.vengeance_markers = vec![0; n];
        st.growth_round = vec![-1; n];
        st.growth_strike_round = vec![-1; n];
        st.second_wind_used = vec![false; n];
        st.surprise_attack_used = vec![false; n];
        st.teleport_used = vec![false; n];
        st.reinforcement_used = vec![false; n];
        st.limited_used = Rc::new(vec![Vec::new(); n]);
        st.piercing_tag_used = vec![false; n];
        st.piercing_tag_markers = vec![0; n];
        st.piercing_tag_persistent = vec![false; n];
        st.piercing_spot_round = vec![-1; n];
        st.spot_markers = vec![0; n];
        st.tag_markers = vec![0; n];
        st.spot_round = vec![-1; n];
        st.precision_used = Rc::new(vec![Vec::new(); n]);
        st.storm_used = Rc::new(vec![Vec::new(); n]);
        st.feats_used = Rc::new(vec![Vec::new(); n]);
        let cast = CastInput { seq: 0, caster: "c".into(), spell: "Bolt".into(), targets: vec!["f".into()], base: 4, threshold: 1, ..Default::default() };
        let t = vec![Begin, intent(HOLD, None), Input::Cast(cast)];
        let shaken_names = |state: &State| -> Vec<String> {
            let ActStep::NeedRoll { kind: "cast", lines, .. } = step_activation(&statics, state, "c", &Terrain::default(), seams(), &t, true) else { panic!("asks die") };
            lines.iter().filter_map(|l| l.text.strip_prefix("Spell Accumulator: ")?.split(" is Shaken").next().map(String::from)).collect()
        };
        // Host alive: Host's members emit HeroBat BEFORE MidBat, ReserveBat is skipped, HeroBat's own entry emits it again.
        assert_eq!(shaken_names(&st), ["HeroBat", "MidBat", "HeroBat"]);
        // Host destroyed: Host is skipped, so HeroBat only appears at its own entry AFTER MidBat.
        let mut dead_host = st.clone();
        dead_host.alive[0] = 0;
        assert_eq!(shaken_names(&dead_host), ["MidBat", "HeroBat"]);
        // Host in reserve (captured with its attached hero dormant too): neither Host nor HeroBat appears.
        let mut res_host = st.clone();
        (res_host.dormant[0], res_host.dormant[3]) = (true, true);
        assert_eq!(shaken_names(&res_host), ["MidBat"]);
    }

    /// CC-5d: Godot's `str(Vector3)` format (6 decimals, minus `floor(log10|x|)` when `|x| > 10`, trailing zeros trimmed, `".0"` kept).
    #[test]
    fn godot_vec3_matches_godots_str_vector3_format() {
        for (v, want) in [
            ([0.508, 0.0, 0.3048], "(0.508, 0.0, 0.3048)"),
            (crate::geom::to_f32([-0.12345678, 12.345678, 100.123456]), "(-0.123457, 12.34568, 100.1235)"),
            ([0.0, 0.0, 0.0], "(0.0, 0.0, 0.0)"),
            ([1.0e-7, -1.0e-7, 0.0], "(0.0, 0.0, 0.0)"),
            ([10.0, -10.5, 1_000_000.0], "(10.0, -10.5, 1000000.0)"),
        ] {
            assert_eq!(crate::geom::godot_vec3(v), want, "{v:?}");
        }
    }

    /// CC-5a: the refusal comes before ANY roll. "a" stands in Dangerous terrain, so its activation owes the Dangerous test
    /// first (the plain transcript asks it); the same transcript with an unknown spell is refused and asks nothing. RED: the
    /// check moved behind the first draw (only when faces are supplied) -> this transcript asks the Dangerous roll.
    #[test]
    fn an_unknown_spell_is_refused_while_a_dangerous_test_is_owed_and_no_roll_is_asked() {
        use crate::terrain::{CellParams, PlainTerrain, DANGEROUS};
        let (mut st, statics) = caster_line();
        st.positions[0] = vec![[4.0 * INCHES_TO_METERS, 0.0, 0.0], [5.0 * INCHES_TO_METERS, 0.0, 0.0]];
        (st.wounds[0], st.alive[0]) = (vec![1, 1], 2);
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS / 2.0; 2];
        let cells = vec![[16.0, 14.0, DANGEROUS as f64], [16.0, 15.0, DANGEROUS as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        let board = Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params, ..Default::default() });
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &board, Seams { dangerous_end_morale: true, ..seams() }, t, true);
        let start = vec![Begin, intent(HOLD, Some("b"))];
        assert!(matches!(ask(&start), ActStep::NeedRoll { owner_key, .. } if owner_key == "a"), "fixture: the Dangerous test is owed first");
        let t = [&start[..], &[Input::Cast(CastInput { spell: "Nope".into(), ..bolt(0) })]].concat();
        assert!(matches!(ask(&t), ActStep::Refused { index: 2, reason } if reason == "cast 0: a has no spell named Nope"));
    }

    // ---- CC-6a: a damage spell's hits ----

    /// CC-2's damage board (`golden_witness_harness.gd` `cast_damage_scenarios`): "a" = Mystic with one token and "Test Bolt" (`hits`
    /// fixed hits, weapon `rules`), "b" = Foe, `foes` one-wound models in a line 1.3" apart, Defense 4+, Quality 4+, no kit loadout.
    fn bolt_board(hits: i64, rules: &[&str], foes: usize) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = die_line();
        st.profiles = Rc::new(crate::state::Profiles { list: vec![st.profiles.list[0].clone(); 4], index: Default::default() }); // one per unit: the casualty order reads the host's profile
        statics[0].spells = vec![crate::rules::Spell { name: "Test Bolt".into(), effect_kind: "damage".into(), effect_hits: hits, weapon_rules: rules.iter().map(|r| r.to_string()).collect(), threshold: 1, range_in: 12.0, ..Default::default() }];
        (st.casts, st.attached, st.attached_to) = (vec![1, 0, 0, 0], Rc::new(vec![Vec::new(); 4]), Rc::new(vec![None; 4])); // no joined heroes
        (statics[2].model_count, statics[2].wounds_max) = (foes as i64, vec![1; foes]);
        statics[2].ctx = crate::unit::Ctx { defense: 4, quality: 4, tough: 1, modifier_sum: true, ..Default::default() };
        // The line is symmetric, so every outermost pair ties on the casualty order's distance to the centroid and the table broke each
        // tie by Godot's unstable sort (the shared casualty fixture "carries no exact ties"). Slots 4 and 2 are nudged 0.001" out so the
        // core's order is the one the golden recorded (slots 0 and 5, then 4, 1, 2, 3); what is pinned is the landing, not tie-breaking.
        let nudge = |i: usize| [0.0, 0.0, -0.001, 0.0, 0.001, 0.0].get(i).copied().unwrap_or(0.0);
        st.positions[2] = (0..foes).map(|i| [8.0 * INCHES_TO_METERS, 0.0, (1.3 * i as f64 + nudge(i)) * INCHES_TO_METERS]).collect();
        (st.wounds[2], st.alive[2]) = (vec![1; foes], foes as i64);
        Rc::make_mut(&mut st.radii)[2] = vec![0.63 * INCHES_TO_METERS; foes];
        st.kits = vec![Rc::new(Vec::new()), Rc::new(Vec::new()), Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 1 }; foes]), Rc::new(Vec::new())];
        (st, statics)
    }

    fn test_bolt() -> CastInput {
        CastInput { spell: "Test Bolt".into(), base: 2, threshold: 1, ..bolt(0) }
    }

    /// Answers each roll `NeedRoll` asks with the next of `groups`; the final answer and the rolls asked as "kind|CxT+|owner".
    fn replay(statics: &[UnitStatic], st: &State, cast: CastInput, groups: &[Vec<u8>]) -> (ActStep, Vec<String>) {
        let mut t = vec![Begin, intent(HOLD, None), Input::Cast(cast)];
        let mut asked = Vec::new();
        for g in groups {
            match step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                    assert_eq!(faces, g.len(), "{kind}: the golden's group has the faces the core asks");
                    asked.push(format!("{kind}|{count}x{target}+|{owner}"));
                    t.push(Faces(g.clone()));
                }
                other => return (other, asked),
            }
        }
        (step_activation(statics, st, "a", &Terrain::default(), seams(), &t, true), asked)
    }

    /// CC-6a/8a: the plain damage cases of CC-2's golden (`golden_cast_damage.json`, recorded from the table with the core off), replayed
    /// through the step path on the recorded faces: the same rolls in the same order (the die is `cast`, the saves `spell_defense`,
    /// the post-damage morale `spell_morale`; the table's save target is unclamped, the core's 2..6), the same lines but for the tray's
    /// own "AI (...)" dice lines, the same models dead in the same slots (the volley's casualty order) and the same shaken state.
    /// RED: Cover folded into the save (the in-cover test below), the AP dropped (the `morale` scenario saves at 4+), the landing
    /// report left out (no wound lines), the saves' kind left as `defense`, or morale skipped / moved out of table order (CC-8a).
    #[test]
    fn the_plain_damage_cases_of_the_cc2_golden_replay_roll_for_roll_and_line_for_line() {
        let golden: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(format!("{}/../../test/fixtures/one_core/golden_cast_damage.json", env!("CARGO_MANIFEST_DIR"))).expect("the CC-2 golden")).unwrap();
        let text = |v: &serde_json::Value| v.as_str().unwrap().to_string();
        let mut seen = std::collections::BTreeMap::new();
        for case in golden["cases"].as_array().unwrap() {
            let (name, seed) = (text(&case["scenario"]), case["seed"].as_i64().unwrap());
            let (st, statics) = match name.as_str() {
                "bolt_saves" => bolt_board(6, &[], 6),
                "bolt_morale" => bolt_board(6, &["AP(1)"], 6),
                "bolt_kill" => bolt_board(12, &["AP(4)"], 3),
                other => panic!("a scenario this test does not know: {other}"),
            };
            // the recorded rolls "leg|kind|CxT+|owner|faces": cast die, spell saves, and spell morale (CC-8a)
            let rolls: Vec<Vec<String>> = case["extra"]["rolls"].as_array().unwrap().iter().map(|r| text(r).split('|').map(String::from).collect::<Vec<_>>()).collect();
            let groups: Vec<Vec<u8>> = rolls.iter().map(|r| r[4].split(',').map(|f| f.parse().unwrap()).collect()).collect();
            let want_rolls: Vec<String> = rolls.iter().map(|r| {
                let (count, target) = r[2].trim_end_matches('+').split_once('x').map(|(c, t)| (c.to_string(), t.parse::<i64>().unwrap())).unwrap();
                let (kind, target) = match (r[0].as_str(), r[1].as_str()) {
                    ("cast", _) => ("cast", target),
                    ("spell", "morale") => ("spell_morale", target),
                    _ => ("spell_defense", target.clamp(2, 6)),
                };
                format!("{kind}|{count}x{target}+|{}", r[3].trim_start_matches("AI (").trim_end_matches(')'))
            }).collect();
            let (done, asked) = replay(&statics, &st, test_bolt(), &groups);
            let ActStep::Done { state, lines, landings, .. } = done else { panic!("{name} {seed}: taken, got {done:?}") };
            assert_eq!(asked, want_rolls, "{name} {seed}: the rolls");
            let ours: Vec<String> = lines.iter().map(|l| format!("COMBAT|{}", l.text)).collect();
            let want: Vec<String> = case["lines"].as_array().unwrap().iter().map(text).filter(|l| !l.starts_with("COMBAT|AI (")).collect();
            assert_eq!(ours, want, "{name} {seed}: the lines");
            let foe = &case["final"][1];
            let mut dead: Vec<i64> = landings.iter().filter(|l| l.unit == 2).flat_map(|l| l.models.iter().filter(|m| m.dead).map(|m| m.slot as i64)).collect();
            dead.sort();
            let gone: Vec<i64> = foe["slots"].as_array().unwrap().iter().filter(|s| !s[1].as_bool().unwrap()).map(|s| s[0].as_i64().unwrap()).collect();
            assert_eq!(
                (state.alive[2], state.shaken[2], dead, state.casts[0]),
                (foe["alive"].as_i64().unwrap(), foe["shaken"].as_bool().unwrap(), gone, 0),
                "{name} {seed}: alive, shaken, the slots that fell, the token paid"
            );
            *seen.entry(name).or_insert(0) += 1;
        }
        assert_eq!(seen.values().copied().collect::<Vec<_>>(), [8, 8, 8], "all 24 cases: {seen:?}");
    }

    /// CC-6a: Cover is for shots: a target in cover saves a spell at its own Defense, and says so before the save line (NML-104, the
    /// table's `_solo_log_defense_vs_spell`). The same faces as the golden's `bolt_saves` seed 0 (4+: 3 blocks of 6, then morale 6).
    /// RED: the cover folded in (`defense - 1`) -> the save asks 3+ and blocks 4.
    #[test]
    fn a_target_in_cover_saves_a_spell_at_its_own_defense_and_says_so() {
        let (mut st, statics) = bolt_board(6, &[], 6);
        st.in_cover[2] = true;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![4, 3, 1, 4, 1, 6], vec![6]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("taken, got {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|6x4+|Foe", "spell_morale|1x4+|Foe"]);
        let said: Vec<&str> = lines.iter().map(|l| l.text.as_str()).skip(3).collect();
        assert_eq!(said, ["Cover does not apply to spell damage (its +1 is against shooting) \u{2014} Foe saves on 4+", "Foe saves on 4+", "Foe takes 3 wounds (3/6)", "Foe loses 3 models (3/6)", "Foe passes morale"]);
        assert_eq!((state.alive[2], state.shaken[2]), (3, false));
    }

    /// CC-6a/6b: a spell and a target the core cannot resolve EXACTLY are refused at the cast's own input before any die, each with its
    /// own sentence: a weapon rule outside AP/Deadly, and a target that saves with a rule or record the core does not fold or say for
    /// spell damage yet (a live record on its chain, growth markers, Shielded, Guarded, Fortified, Armor). Plain boards, AP, Deadly and
    /// Regeneration targets ask the die. RED: a check removed -> the case asks the cast die instead.
    #[test]
    fn a_damage_spell_or_target_the_core_cannot_resolve_exactly_is_refused_before_the_die() {
        let ask = |st: &State, statics: &[UnitStatic]| step_activation(statics, st, "a", &Terrain::default(), seams(), &[Begin, intent(HOLD, None), Input::Cast(test_bolt())], true);
        let (st, statics) = bolt_board(6, &["AP(1)"], 6);
        assert!(matches!(ask(&st, &statics), ActStep::NeedRoll { kind: "cast", .. }), "control: the plain board asks the die");
        let target = "Foe meets Test Bolt with a rule the core does not say for spell damage yet";
        let mut cases: Vec<(&str, State, Vec<UnitStatic>, String)> = Vec::new();
        for rule in ["Blast(3)", "Deadly(3)", "Hazardous", "Surge", "Crack", "Bane", "Scourge", "AP"] {
            let (st, statics) = bolt_board(6, &["AP(1)", rule], 6);
            let ok = rule != "Scourge";
            cases.push((rule, st, statics, if ok { String::new() } else { format!("the core does not resolve the {rule} rule of Test Bolt yet") }));
        }
        let ward = LiveMod { move_mod: 0, range_in: 0, hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 1, defense_mod: 0, grants_rule: Rc::from(""), scope: Rc::from("melee"), attackers: false, once: false, name: Rc::from("Shield Wall") };
        let host = |mut st: State, mut statics: Vec<UnitStatic>, how: &str| {
            match how {
                "record" => st.buffs[2] = vec![ward.clone()],
                "markers" => st.growth_markers[2] = 1,
                "Regeneration" => statics[2].ctx.regeneration = true,
                "Shielded" => statics[2].ctx.shielded = true,
                "Guarded" => statics[2].ctx.guarded = true,
                "Fortified" => statics[2].ctx.fortified = true,
                _ => {}
            }
            (st, statics)
        };
        for how in ["record", "markers", "Regeneration", "Shielded", "Guarded", "Fortified"] {
            let (st, statics) = host(bolt_board(6, &[], 6).0, bolt_board(6, &[], 6).1, how);
            cases.push((how, st, statics, if how == "Regeneration" { String::new() } else { target.to_string() }));
        }
        let (mut st, statics) = bolt_board(6, &[], 6);
        let mut list = st.profiles.list.clone();
        list[2].special_rules = vec!["Armor(3)".into()];
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        cases.push(("Armor", st, statics, target.to_string()));
        for (what, st, statics, why) in cases {
            match ask(&st, &statics) {
                ActStep::Refused { index: 2, reason } => assert_eq!(reason, format!("cast 0: {why}"), "{what}"),
                ActStep::NeedRoll { kind: "cast", .. } if why.is_empty() => {}
                other => panic!("{what}: {other:?}"),
            }
        }
        // a joined hero as the target meets its HOST's records too (the table's `_solo_mods_of_chain`: the unit and its host)
        let (mut st, statics) = bolt_board(6, &[], 6);
        (st.attached_to, st.buffs[2]) = (Rc::new(vec![None, None, None, Some(2)]), vec![ward.clone()]);
        let hero = [Begin, intent(HOLD, None), Input::Cast(CastInput { targets: vec!["bh".into()], ..test_bolt() })];
        assert!(matches!(step_activation(&statics, &st, "a", &Terrain::default(), seams(), &hero, true), ActStep::Refused { index: 2, reason } if reason == "cast 0: bh meets Test Bolt with a rule the core does not say for spell damage yet"));
    }

    /// CC-6a/8a: every standing target of the spell takes its hits, in list order, each saved on its own dice (and testing morale
    /// right after its own damage when at or below half); the golden's one-model board gains a second target "bh" (two models,
    /// Defense 4+, Quality 4+). RED: only the first target hit -> the second save is never asked.
    #[test]
    fn every_standing_target_takes_the_spells_hits_in_list_order() {
        let (mut st, mut statics) = bolt_board(2, &[], 6);
        statics[3] = UnitStatic { name: "Guard".into(), model_count: 2, wounds_max: vec![1, 1], ctx: crate::unit::Ctx { defense: 4, quality: 4, tough: 1, modifier_sum: true, ..Default::default() }, ..Default::default() };
        st.positions[3] = vec![[20.0 * INCHES_TO_METERS, 0.0, 0.0], [20.0 * INCHES_TO_METERS, 0.0, 1.3 * INCHES_TO_METERS]];
        (st.wounds[3], st.alive[3]) = (vec![1, 1], 2);
        Rc::make_mut(&mut st.radii)[3] = vec![0.63 * INCHES_TO_METERS; 2];
        let cast = CastInput { targets: vec!["b".into(), "bh".into()], ..test_bolt() };
        let (done, asked) = replay(&statics, &st, cast, &[vec![6], vec![1, 1], vec![6, 1], vec![5]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("taken, got {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe", "spell_defense|2x4+|Guard", "spell_morale|1x4+|Guard"]);
        assert_eq!(lines.iter().map(|l| l.text.as_str()).skip(3).collect::<Vec<_>>(), ["Foe saves on 4+", "Foe takes 2 wounds (4/6)", "Foe loses 2 models (4/6)", "Guard saves on 4+", "Guard takes 1 wound (1/2)", "Guard loses a model (1/2)", "Guard passes morale"]);
        assert_eq!((state.alive[2], state.alive[3], state.shaken[3]), (4, 1, false));
    }

    // ---- CC-8a: morale after spell damage (table timing O2, kind spell_morale) ----

    /// CC-8a (O2): morale runs RIGHT AFTER that target's spell damage, never deferred to the activation's end. Two proofs:
    /// (1) Cast + Hold volley in one activation: Test Bolt drops Foe to 3/6 -> `spell_morale` is asked BEFORE the volley's
    ///     `attack` die, and Foe is already Shaken before the volley lands.
    /// (2) Two-target cast: Test Bolt drops Foe (target 1) to 2/4 -> Foe's `spell_morale` is asked BEFORE Guard's `spell_defense`.
    /// Planted fault: moving spell morale to the activation's end pushes `spell_morale` behind `attack` / Guard's `spell_defense` -> RED.
    #[test]
    fn spell_damage_morale_runs_right_after_that_targets_damage_before_later_rolls() {
        // (1) Cast + volley: Mystic casts Test Bolt (6 hits) at Foe AND shoots a 1-shot Rifle at Foe.
        let (st, mut statics) = bolt_board(6, &[], 6);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        let mut t = vec![Begin, intent(HOLD, Some("b")), Input::Cast(test_bolt())];
        let mut asked = Vec::new();
        for g in [vec![6u8], vec![4, 3, 1, 4, 1, 6], vec![1], vec![1]] {
            match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                    assert_eq!(faces, g.len(), "{kind}");
                    asked.push(format!("{kind}|{count}x{target}+|{owner}"));
                    t.push(Faces(g));
                }
                other => panic!("expected NeedRoll, got {other:?}"),
            }
        }
        let ActStep::Done { state, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) else { panic!("expected Done") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|6x4+|Foe", "spell_morale|1x4+|Foe", "attack|1x4+|Mystic"], "O2: spell_morale precedes the volley's attack die");
        assert_eq!((state.alive[2], state.shaken[2]), (3, true));
        let morale_at = lines.iter().position(|l| l.text == "Foe fails morale — Shaken").expect("spell morale line");
        let volley_at = lines.iter().position(|l| l.text == "Mystic fires at Foe").expect("volley announce line");
        assert!(morale_at < volley_at, "O2: spell morale line before volley announce");

        // (2) Two-target cast: target 1 ("b", 4 models) drops to 2/4 -> its spell_morale runs BEFORE target 2 ("bh") saves.
        let (mut st, mut statics) = bolt_board(2, &[], 4);
        statics[3] = UnitStatic { name: "Guard".into(), model_count: 4, wounds_max: vec![1; 4], ctx: crate::unit::Ctx { defense: 4, quality: 4, tough: 1, modifier_sum: true, ..Default::default() }, ..Default::default() };
        st.positions[3] = (0..4).map(|i| [20.0 * INCHES_TO_METERS, 0.0, 1.3 * i as f64 * INCHES_TO_METERS]).collect();
        (st.wounds[3], st.alive[3]) = (vec![1; 4], 4);
        Rc::make_mut(&mut st.radii)[3] = vec![0.63 * INCHES_TO_METERS; 4];
        let cast = CastInput { targets: vec!["b".into(), "bh".into()], ..test_bolt() };
        let (done, asked) = replay(&statics, &st, cast, &[vec![6], vec![1, 1], vec![2], vec![6, 6]]);
        let ActStep::Done { state, .. } = done else { panic!("taken, got {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe", "spell_morale|1x4+|Foe", "spell_defense|2x4+|Guard"]);
        assert_eq!((state.alive[2], state.shaken[2], state.alive[3], state.shaken[3]), (2, true, 4, false));
    }

    /// CC-8a: spell morale carries the spell name as its cause (so Banner does not add +1 and says so), skips the die when the
    /// target is already Shaken, and triggers on a single Tough model wounded to half with the table's tough-value line.
    #[test]
    fn spell_morale_drops_banner_skips_shaken_die_and_triggers_on_half_tough() {
        // Banner (+1) dropped because cause = "Test Bolt" (only shooting or melee).
        let (mut st, statics) = bolt_board(6, &[], 6);
        st.morale_bonus[2] = 1;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![4, 3, 1, 4, 1, 6], vec![3]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("taken, got {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|6x4+|Foe", "spell_morale|1x4+|Foe"]);
        assert!(lines.iter().any(|l| l.text == "Banner: Foe gets no +1 against Test Bolt (only shooting or melee)"), "{lines:?}");
        assert!(state.shaken[2], "3 fails 4+ because Banner did not apply");

        // Already Shaken: no morale die drawn, still prints the failure line.
        let (mut st, statics) = bolt_board(6, &[], 6);
        st.shaken[2] = true;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![4, 3, 1, 4, 1, 6]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("taken, got {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|6x4+|Foe"]);
        assert!(lines.iter().any(|l| l.text == "Foe fails morale — Shaken"), "{lines:?}");
        assert!(state.shaken[2]);

        // Single Tough(4) model taking 2 wounds -> 2/4 triggers morale with the tough-value line.
        let (mut st, mut statics) = bolt_board(2, &[], 1);
        (statics[2].wounds_max, statics[2].ctx.tough) = (vec![4], 4);
        st.wounds[2] = vec![4];
        st.kits[2] = Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 4 }]);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![1, 1], vec![6]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("taken, got {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe", "spell_morale|1x4+|Foe"]);
        assert!(lines.iter().any(|l| l.text.starts_with("Foe is at half its tough value (2/4) — morale test")), "{lines:?}");
        assert_eq!((state.wounds[2][0], state.shaken[2]), (2, false));
    }

    // ---- CC-6b: Deadly per model, Regeneration / Resistance at spell threshold, bypass, wound_alloc ----

    /// CC-6b: the Deadly cases of the table's volley golden (`golden_shoot_volley.json` scenario `deadly`: 10 Tough(3) models,
    /// Defense 4+, Quality 4+, Deadly(3)), replayed as a Deadly(3) spell named "Rifle" on the recorded save and morale faces:
    /// exact roll order, exact save/Deadly/loss/morale lines, exact alive/wounds/shaken state.
    #[test]
    fn the_deadly_golden_cases_replay_through_a_deadly_spell() {
        let golden: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(format!("{}/../../test/fixtures/one_core/golden_shoot_volley.json", env!("CARGO_MANIFEST_DIR"))).expect("the shoot volley golden")).unwrap();
        let mut replayed = 0;
        for case in golden["cases"].as_array().unwrap().iter().filter(|c| c["scenario"] == "deadly") {
            let lines: Vec<&str> = case["lines"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
            let Some(def_line) = lines.iter().find(|l| l.starts_with("COMBAT|AI (Def) defends: ")) else { continue };
            let parse_faces = |s: &str| -> Vec<u8> {
                s.split(':').nth(1).unwrap().split('→').next().unwrap().split_whitespace().map(|x| x.parse().unwrap()).collect()
            };
            let save_faces = parse_faces(def_line);
            let morale_faces = lines.iter().find(|l| l.starts_with("COMBAT|AI (Def): ")).map(|l| parse_faces(l));
            let (mut st, mut statics) = bolt_board(save_faces.len() as i64, &["Deadly(3)"], 10);
            statics[0].spells[0].name = "Rifle".into();
            statics[2].name = "Def".into();
            (statics[2].wounds_max, statics[2].ctx.tough) = (vec![3; 10], 3);
            let mut list = st.profiles.list.clone();
            list[2].wounds_max = vec![3; 10];
            st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
            st.wounds[2] = vec![3; 10];
            st.kits[2] = Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 3 }; 10]);
            let mut groups = vec![vec![6u8], save_faces.clone()];
            let mut want_rolls = vec!["cast|1x2+|Mystic".into(), format!("spell_defense|{}x4+|Def", save_faces.len())];
            if let Some(mf) = morale_faces {
                groups.push(mf);
                want_rolls.push("spell_morale|1x4+|Def".into());
            }
            let cast = CastInput { spell: "Rifle".into(), ..test_bolt() };
            let (done, asked) = replay(&statics, &st, cast, &groups);
            let ActStep::Done { state, lines: got_lines, .. } = done else { panic!("seed {}: {done:?}", case["seed"]) };
            assert_eq!(asked, want_rolls, "seed {}: rolls", case["seed"]);
            let ours: Vec<String> = got_lines.iter().skip(3).map(|l| format!("COMBAT|{}", l.text)).collect();
            let save_at = lines.iter().position(|l| *l == "COMBAT|Def saves on 4+").unwrap();
            let want: Vec<String> = lines[save_at..].iter().filter(|l| !l.starts_with("COMBAT|AI (")).map(|l| (*l).to_string()).collect();
            assert_eq!(ours, want, "seed {}: lines", case["seed"]);
            let def_end = &case["final"][1];
            assert_eq!(
                (state.alive[2], state.wounds[2].iter().sum::<i64>(), state.shaken[2]),
                (def_end["alive"].as_i64().unwrap(), def_end["wounds"].as_i64().unwrap(), def_end["shaken"].as_bool().unwrap()),
                "seed {}: state", case["seed"]
            );
            replayed += 1;
        }
        assert_eq!(replayed, 3, "the 3 hitting Deadly golden cases (seeds 0, 17, 49)");
    }

    /// CC-6b: Regeneration and Resistance roll at the SPELL threshold (`regen_target_spell`, e.g. 2+ for Resistance instead of
    /// its weapon threshold 6+), and Deadly(X) rolls all X dice per unsaved wound before the model's Tough cap (A4: "Drei Wuerfe
    /// muessen gelingen"). Planted fault: using the weapon threshold `regen_target` (6+) instead of `regen_target_spell` (2+) -> RED.
    #[test]
    fn spell_regeneration_and_resistance_use_the_spell_threshold_including_deadly_a4() {
        // (1) Plain spell vs Resistance (6+ vs weapons, 2+ vs spells): 4 unsaved -> asks 4x2+, faces [2, 3, 4, 1] ignore 3 -> 1 dies.
        let (st, mut statics) = bolt_board(4, &[], 6);
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 6;
        statics[2].ctx.regen_target_spell = 2;
        statics[2].ctx.regen_named = false;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![1, 1, 1, 1], vec![2, 3, 4, 1]]);
        let ActStep::Done { state, .. } = done else { panic!("plain resistance: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|4x4+|Foe", "spell_attack|4x2+|Foe"], "Resistance rolls at spell threshold 2+, not weapon 6+");
        assert_eq!(state.alive[2], 5, "3 of 4 wounds ignored at 2+");

        // (2) Deadly(3) vs 1-wound Resistance models (A4): 2 unsaved -> two separate 3-die rolls at 2+.
        // Roll 1 [2, 2, 2] ignores all 3 (survives); Roll 2 [2, 2, 1] lets 1 through (kills 1 model, no carry-over).
        let (st, mut statics) = bolt_board(2, &["Deadly(3)"], 6);
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 6;
        statics[2].ctx.regen_target_spell = 2;
        statics[2].ctx.regen_named = false;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![1, 1], vec![2, 2, 2], vec![2, 2, 1]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("deadly resistance: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe", "spell_attack|3x2+|Foe", "spell_attack|3x2+|Foe"]);
        assert_eq!(state.alive[2], 5);
        assert!(lines.iter().any(|l| l.text == "Deadly(3): 2 unsaved \u{00d7}3, no carry-over \u{2192} 1 wound dealt (Test Bolt)"), "{lines:?}");

        // (3) Deadly(3) vs Tough(2) Regeneration (5+): 1 unsaved rolls ALL 3 dice, overkill capped at 2 (no carry-over).
        let (mut st, mut statics) = bolt_board(1, &["Deadly(3)"], 3);
        (statics[2].wounds_max, statics[2].ctx.tough) = (vec![2; 3], 2);
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 5;
        statics[2].ctx.regen_target_spell = 5;
        statics[2].ctx.regen_named = true;
        let mut list = st.profiles.list.clone();
        list[2].wounds_max = vec![2; 3];
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.wounds[2] = vec![2; 3];
        st.kits[2] = Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 2 }; 3]);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![1], vec![1, 1, 1]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("deadly tough2 regen: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|1x4+|Foe", "spell_attack|3x5+|Foe"]);
        assert_eq!((state.alive[2], &state.wounds[2]), (2, &vec![2, 2]), "Tough(2) cap loses overkill 1, no carry-over");
        assert!(lines.iter().any(|l| l.text == "Deadly(3): 1 unsaved \u{00d7}3, no carry-over \u{2192} 2 wounds dealt (Test Bolt)"), "{lines:?}");
    }

    /// CC-6b: `ignores_regen` (Bane / Disintegrate facets) skips Regeneration (named), while Resistance (not named Regeneration)
    /// still rolls at its spell threshold (2+) from EPOCH_82_IGNORE_BY_NAME (R-1), both plain and Deadly(3).
    #[test]
    fn spell_ignores_regen_bypasses_regeneration_but_not_resistance_at_v36() {
        use crate::dice::ShootResult;
        use crate::sim::tray_cast;
        let run = |rules: &[&str], regen_named: bool, target_w: i64, target_sp: i64, faces: Vec<Vec<u8>>| {
            let (mut st, mut statics) = bolt_board(2, rules, 6);
            statics[2].ctx.regeneration = true;
            statics[2].ctx.regen_target = target_w;
            statics[2].ctx.regen_target_spell = target_sp;
            statics[2].ctx.regen_named = regen_named;
            let mut tray = Tray::supplied(faces);
            let mut shot = ShootResult::default();
            tray_cast(&statics, &mut st, 0, &test_bolt(), seams(), &mut tray, &mut shot);
            (st.alive[2], shot.rolls)
        };
        // Regeneration (named) bypassed by Disintegrate: only cast + save (no regen roll), 2 die.
        let (alive, rolls) = run(&["Disintegrate"], true, 5, 5, vec![vec![6], vec![1, 1]]);
        assert_eq!((alive, rolls.len()), (4, 2), "Disintegrate skips Regeneration (plain): {rolls:?}");
        // Deadly(3) + Disintegrate vs Regeneration (named): skips regen roll, kills 2 1-wound models.
        let (alive, rolls) = run(&["Deadly(3)", "Disintegrate"], true, 5, 5, vec![vec![6], vec![1, 1]]);
        assert_eq!((alive, rolls.len()), (4, 2), "Disintegrate skips Regeneration (Deadly): {rolls:?}");
        // Resistance (not named Regeneration) + Disintegrate at epoch 90: STILL rolls 2+ (plain: 2 dice at 2+).
        let (alive, rolls) = run(&["Disintegrate"], false, 6, 2, vec![vec![6], vec![1, 1], vec![2, 2]]);
        assert_eq!((alive, rolls.len(), rolls[2].target), (6, 3, 2), "Resistance still rolls at 2+ against bypass (plain)");
        // Resistance + Deadly(3) + Disintegrate at epoch 90: STILL rolls 3 dice per unsaved wound at 2+.
        let (alive, rolls) = run(&["Deadly(3)", "Disintegrate"], false, 6, 2, vec![vec![6], vec![1, 1], vec![2, 2, 2], vec![2, 2, 1]]);
        assert_eq!((alive, rolls.len(), rolls[2].target, rolls[3].target), (5, 4, 2, 2), "Resistance still rolls 3x2+ per wound against Deadly bypass");
    }

    /// CC-6b: when the wound_alloc choice switch is ON, a damage spell opens `wound_alloc:<caster>:<target>:cast:<seq>` after
    /// the saves and lands Deadly (with forced already-wounded Tough picks taking no pick) and plain wounds on the owner's picks.
    #[test]
    fn a_damage_spell_opens_and_honours_wound_alloc_for_plain_and_deadly() {
        let board = |rules: &[&str]| {
            let (mut st, mut statics) = bolt_board(2, rules, 2);
            (statics[2].wounds_max, statics[2].ctx.tough) = (vec![3, 3], 3);
            let mut list = st.profiles.list.clone();
            list[2].wounds_max = vec![3, 3];
            st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
            st.wounds[2] = vec![3, 3];
            st.kits[2] = Rc::new(vec![Kit { weapons: vec![1], equipment: 0, wounds_max: 3 }, Kit { weapons: vec![2], equipment: 0, wounds_max: 3 }]);
            (st, statics)
        };
        let id = "wound_alloc:a:b:cast:0";
        let run = |rules: &[&str], choice: Option<&str>| {
            let (st, statics) = board(rules);
            let mut t = vec![Begin, intent(HOLD, None), Input::Cast(test_bolt())];
            t.extend(choice.map(|o| Input::Choice { id: id.into(), option: o.into() }));
            for g in [vec![6u8], vec![1, 1], vec![6]] {
                match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
                    ActStep::NeedRoll { faces, .. } => {
                        assert_eq!(faces, g.len());
                        t.push(Faces(g));
                    }
                    other => return (other, st),
                }
            }
            (step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true), st)
        };
        // Deadly(2): unanswered ask opens NeedChoice after the saves, naming slot:0 and slot:1 for owner "b".
        let (ask, _) = run(&["Deadly(2)"], Some(""));
        assert!(matches!(ask, ActStep::NeedChoice { ref id, ref options, ref owner, .. } if id == "wound_alloc:a:b:cast:0" && options == &["slot:0", "slot:1"] && owner == "b"), "{ask:?}");
        // Deadly(2) auto (no choice) kills slot 0; answered "slot:1,slot:0" puts wound 1 on slot 1 (2/3) and FORCES wound 2 onto slot 1 -> slot 0 stands untouched.
        let (ActStep::Done { state: auto_st, .. }, start) = run(&["Deadly(2)"], None) else { panic!("auto") };
        assert_eq!(auto_st.positions[2], vec![start.positions[2][1]], "auto kills lead slot 0");
        let (ActStep::Done { state: picked_st, lines, .. }, _) = run(&["Deadly(2)"], Some("slot:1,slot:0")) else { panic!("picked") };
        assert_eq!((&picked_st.positions[2], &picked_st.wounds[2]), (&vec![start.positions[2][0]], &vec![3]), "picked kills slot 1, slot 0 untouched");
        assert!(lines.iter().any(|l| l.text == "Deadly(2): 2 unsaved \u{00d7}2, no carry-over \u{2192} 3 wounds dealt (Test Bolt)"), "{lines:?}");
        assert!(lines.iter().any(|l| l.text.starts_with("Deadly(2): 1 wound finish the already-wounded Tough model first")), "{lines:?}");
        assert!(lines.iter().any(|l| l.text == "b: the owner allocates 1 wound"), "forced wound took no pick: {lines:?}");

        // Plain spell (non-Deadly): "slot:1,slot:1" wounds slot 1 (leaving slot 0 at 3, slot 1 at 1) instead of automatic slot 0.
        let (ActStep::Done { state: plain_picked, lines: plain_lines, .. }, _) = run(&[], Some("slot:1,slot:1")) else { panic!("plain picked") };
        assert_eq!(plain_picked.wounds[2], vec![3, 1], "plain spell honours owner wound_alloc picks");
        assert!(plain_lines.iter().any(|l| l.text == "b: the owner allocates 2 wounds"), "{plain_lines:?}");
    }

    // ---- CC-7a: trigger roll (Surge, on-6 AP batch first, Hazardous to host), caster / unit death ----

    /// CC-7a: the trigger roll (`spell_attack`, `hits x 6+`, caster owner) drives Surge (+1 hit per 6) and on-6 AP (the upgraded
    /// batch saves FIRST with its line before the normal batch, then one shared Regeneration / Resistance landing).
    /// Planted fault: on-6 AP dropped -> Batch 1 saves at 4+ instead of 6+ and blocks the 5s -> RED.
    #[test]
    fn spell_trigger_roll_handles_surge_and_on6_ap_batch_first() {
        // (1) Surge: 4 printed hits, trigger [6, 6, 3, 1] -> 6 hits saved at 4+.
        let (st, statics) = bolt_board(4, &["Surge"], 6);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 6, 3, 1], vec![4, 4, 4, 4, 1, 1]]);
        let ActStep::Done { state, .. } = done else { panic!("surge: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_attack|4x6+|Mystic", "spell_defense|6x4+|Foe"]);
        assert_eq!(state.alive[2], 4, "4 + 2 surge hits, 4 blocked -> 2 models lost");

        // (2) On-6 AP batch first (Crack = AP(+2) on 6s) on AP(1) vs Defense 3+:
        // 4 hits, trigger [6, 2, 6, 4] -> 2 upgraded hits save FIRST at 6+ (Def 3+, AP 3), then 2 plain at 4+ (Def 3+, AP 1).
        // Faces [5, 5] fail 6+ (2 wounds), [4, 4] block 4+ (0 wounds). Dropping on-6 AP makes [5, 5] save at 4+ -> 0 wounds.
        let (st, mut statics) = bolt_board(4, &["AP(1)", "Crack"], 6);
        statics[2].ctx.defense = 3;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 2, 6, 4], vec![5, 5], vec![4, 4]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("crack: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_attack|4x6+|Mystic", "spell_defense|2x6+|Foe", "spell_defense|2x4+|Foe"]);
        assert_eq!(state.alive[2], 4, "both on-6 hits penetrate 5s at 6+, normal batch blocked on 4+");
        let on6_at = lines.iter().position(|l| l.text == "Test Bolt: 2 hits on a 6 \u{2192} AP(+2)").expect("on-6 AP line");
        let hi_save_at = lines.iter().position(|l| l.text == "Foe saves on 6+ (Def 3+, AP 3)").expect("on-6 save line");
        let lo_save_at = lines.iter().position(|l| l.text == "Foe saves on 4+ (Def 3+, AP 1)").expect("plain save line");
        assert!(on6_at < hi_save_at && hi_save_at < lo_save_at, "on-6 AP line -> on-6 batch -> plain batch: {lines:?}");

        // (3) Surge + Crack vs Resistance (2+ vs spells): 3 hits, trigger [6, 3, 2] -> 4 total hits, 1 upgraded (6+) + 3 plain (4+),
        // 1 unsaved from Batch 1 + 1 unsaved from Batch 2 -> ONE shared 2-die Resistance roll at 2+.
        let (st, mut statics) = bolt_board(3, &["AP(1)", "Surge", "Crack"], 6);
        statics[2].ctx.defense = 3;
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 6;
        statics[2].ctx.regen_target_spell = 2;
        statics[2].ctx.regen_named = false;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 3, 2], vec![5], vec![4, 4, 1], vec![2, 1]]);
        let ActStep::Done { state, .. } = done else { panic!("surge+crack+res: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_attack|3x6+|Mystic", "spell_defense|1x6+|Foe", "spell_defense|3x4+|Foe", "spell_attack|2x2+|Foe"]);
        assert_eq!(state.alive[2], 5, "2 unsaved combined -> 1 ignored by Resistance -> 1 model lost");
    }

    /// CC-7a (wipe case + multi-cast skip): a Hazardous spell's trigger 1s wound the caster's host (no save, no regen),
    /// emit the host's wound/destroyed lines + landings and the Hazardous trigger line BEFORE target morale; when the host
    /// (with no living joined hero) is wiped, any later planned cast still spends its tokens and skips silently, and the
    /// activation ends there with NO volley.
    #[test]
    fn hazardous_spell_wounds_host_and_wipe_ends_the_activation() {
        let (mut st, mut statics) = bolt_board(4, &["Hazardous"], 6);
        (statics[0].model_count, statics[0].wounds_max) = (2, vec![1, 1]);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 2, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.0, 0.0, 1.3 * INCHES_TO_METERS]];
        (st.wounds[0], st.alive[0], st.casts[0]) = (vec![1, 1], 2, 2);
        Rc::make_mut(&mut st.radii)[0] = vec![0.63 * INCHES_TO_METERS; 2];
        st.kits[0] = Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 1 }; 2]);
        // Two planned casts by Mystic + Hold volley at Foe: cast 0's Hazardous trigger [1, 4, 1, 5] wipes Mystic (2 wounds).
        // Cast 1 must still spend its token and skip silently; the Rifle volley must NEVER fire.
        let mut t = vec![
            Begin, intent(HOLD, Some("b")),
            Input::Cast(test_bolt()),
            Input::Cast(CastInput { seq: 1, ..test_bolt() }),
        ];
        let mut asked = Vec::new();
        for g in [vec![6u8], vec![1, 4, 1, 5], vec![6, 3, 2, 1], vec![5]] {
            match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
                ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                    assert_eq!(faces, g.len(), "{kind}");
                    asked.push(format!("{kind}|{count}x{target}+|{owner}"));
                    t.push(Faces(g));
                }
                other => panic!("expected NeedRoll, got {other:?}"),
            }
        }
        let ActStep::Done { state, lines, landings, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) else { panic!("expected Done") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_attack|4x6+|Mystic", "spell_defense|4x6+|Foe", "spell_morale|1x4+|Foe"], "Hazardous AP(4) saves on 6 only; wiped host skips cast 1 and volley");
        assert_eq!((state.alive[0], state.casts[0], state.alive[2], state.shaken[2]), (0, 0, 3, false), "both tokens spent, host wiped, foe took 3 and passed morale");
        let host_dead = landings.iter().filter(|l| l.unit == 0).flat_map(|l| l.models.iter().filter(|m| m.dead).map(|m| m.slot)).collect::<Vec<_>>();
        assert_eq!(host_dead.len(), 2, "both host models landed dead");
        let haz_at = lines.iter().position(|l| l.text == "Test Bolt: 2 trigger rolls of 1 \u{2014} Mystic takes 2 wounds").expect("Hazardous line");
        let host_wipe_at = lines.iter().position(|l| l.text == "Mystic destroyed").expect("host destroyed line");
        let morale_at = lines.iter().position(|l| l.text == "Foe passes morale").expect("foe morale line");
        assert!(host_wipe_at < haz_at && haz_at < morale_at, "host wounds/destroyed -> Hazardous line -> foe morale: {lines:?}");
    }

    /// CC-7a (hero-alive cases):
    /// (1) Joined hero casts a Hazardous spell: wounds go to the HOST first (heroes last), killing the 1-wound host while the
    ///     Tough(3) hero survives (with spill onto the hero on a second 1); the activation GOES ON and the hero fires its volley.
    /// (2) Dangerous terrain kills the host before casts while the joined hero lives: logs the hero-lives line, skips the dead
    ///     host's cast (tokens still spent), runs the living hero's cast, and goes on to the volley.
    #[test]
    fn hazardous_wounds_go_to_host_and_living_joined_hero_goes_on() {
        // (1) Joined hero "ah" (Tough 3, Rifle 24" A1) casts Hazardous spell -> 2 trigger 1s kill host "a" (1W) and spill 1W onto "ah" (2/3W).
        let (mut st, mut statics) = bolt_board(2, &["Hazardous"], 6);
        statics[0].name = "Host".into();
        statics[0].spells.clear();
        statics[1] = UnitStatic {
            name: "Hero".into(), model_count: 1, wounds_max: vec![3], is_caster: true,
            ctx: crate::unit::Ctx { defense: 4, quality: 4, tough: 3, modifier_sum: true, ..Default::default() },
            shoot: vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }],
            spells: vec![crate::rules::Spell { name: "Test Bolt".into(), effect_kind: "damage".into(), effect_hits: 2, weapon_rules: vec!["Hazardous".into()], threshold: 1, range_in: 12.0, ..Default::default() }],
            ..Default::default()
        };
        let mut list = st.profiles.list.clone();
        list[1].wounds_max = vec![3];
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        (st.attached, st.attached_to) = (Rc::new(vec![vec![1], vec![], vec![], vec![]]), Rc::new(vec![None, Some(0), None, None]));
        st.positions[1] = vec![[0.0, 0.0, 1.3 * INCHES_TO_METERS]];
        (st.wounds[1], st.alive[1], st.casts) = (vec![3], 1, vec![0, 1, 0, 0]);
        Rc::make_mut(&mut st.radii)[1] = vec![0.63 * INCHES_TO_METERS];
        st.kits[1] = Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 3 }]);
        let hero_seams = Seams { hero_attach: true, ..seams() };
        let hero_cast = CastInput { caster: "ah".into(), ..test_bolt() };
        let mut t = vec![Begin, intent(HOLD, Some("b")), Input::Cast(hero_cast.clone())];
        let mut asked = Vec::new();
        for g in [vec![6u8], vec![1, 1], vec![6, 6], vec![1]] {
            match step_activation(&statics, &st, "a", &Terrain::default(), hero_seams, &t, true) {
                ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                    assert_eq!(faces, g.len(), "{kind}");
                    asked.push(format!("{kind}|{count}x{target}+|{owner}"));
                    t.push(Faces(g));
                }
                other => panic!("expected NeedRoll, got {other:?}"),
            }
        }
        let ActStep::Done { state, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), hero_seams, &t, true) else { panic!("expected Done") };
        assert_eq!(asked, ["cast|1x2+|Hero", "spell_attack|2x6+|Hero", "spell_defense|2x6+|Foe", "attack|1x4+|Hero"], "host dies to Hazardous, hero lives and fires its volley");
        assert_eq!((state.alive[0], state.alive[1], state.wounds[1][0]), (0, 1, 2), "wound 1 kills host, wound 2 spills onto hero");
        assert!(lines.iter().any(|l| l.text == "Test Bolt: 2 trigger rolls of 1 \u{2014} Host takes 2 wounds"), "{lines:?}");

        // (2) Dangerous terrain kills the host before casts while joined hero lives: logs hero-lives line, skips host's cast (token spent), hero casts & shoots.
        use crate::terrain::{CellParams, PlainTerrain, DANGEROUS};
        let mut st2 = st.clone();
        let mut statics2 = statics.clone();
        statics2[0].spells = vec![crate::rules::Spell { name: "Test Bolt".into(), effect_kind: "damage".into(), effect_hits: 2, weapon_rules: vec![], threshold: 1, range_in: 12.0, ..Default::default() }];
        statics2[1].spells[0].weapon_rules.clear();
        st2.positions[0] = vec![[4.0 * INCHES_TO_METERS, 0.0, 0.0]];
        st2.positions[1] = vec![[1.0 * INCHES_TO_METERS, 0.0, 0.0]]; // outside dangerous tile
        st2.casts = vec![1, 1, 0, 0];
        let cells = vec![[16.0, 14.0, DANGEROUS as f64], [16.0, 15.0, DANGEROUS as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        let board = Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params, ..Default::default() });
        let mut t2 = vec![
            Begin, intent(HOLD, Some("b")),
            Input::Cast(CastInput { seq: 0, caster: "a".into(), ..test_bolt() }),
            Input::Cast(CastInput { seq: 1, caster: "ah".into(), ..test_bolt() }),
        ];
        let mut asked2 = Vec::new();
        let dang_seams = Seams { dangerous_end_morale: true, ..hero_seams };
        // Dangerous roll [1, 6, 6, 6] (1 Host + 3 Hero Tough) -> 1 wound kills Host -> hero lives line -> Host cast 0 skipped (token spent) -> Hero cast 1 rolls -> saves -> Hero volley.
        for g in [vec![1u8, 6, 6, 6], vec![6], vec![6, 6], vec![1]] {
            match step_activation(&statics2, &st2, "a", &board, dang_seams, &t2, true) {
                ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                    assert_eq!(faces, g.len(), "{kind}");
                    asked2.push(format!("{kind}|{count}x{target}+|{owner}"));
                    t2.push(Faces(g));
                }
                other => panic!("dangerous hero-alive: expected NeedRoll, got {other:?}"),
            }
        }
        let ActStep::Done { state: s2, lines: l2, .. } = step_activation(&statics2, &st2, "a", &board, dang_seams, &t2, true) else { panic!("expected Done") };
        assert_eq!(asked2, ["dangerous|4x6+|Host", "cast|1x2+|Hero", "spell_defense|2x4+|Foe", "attack|1x4+|Hero"]);
        assert_eq!((s2.alive[0], s2.alive[1], s2.casts[0], s2.casts[1]), (0, 1, 0, 0), "host dead (cast 0 token still spent), hero alive");
        assert!(l2.iter().any(|l| l.text == "Host is destroyed but its joined hero lives - the unit is not destroyed and goes on"), "{l2:?}");
    }

    // ---- CC-7b: Blast fan-out with target_kind, bane window, applied facets line ----

    /// CC-7b: Blast(X) fan-out replays the hitting Blast cases of `golden_shoot_volley.json` (seeds 0, 17, 49) as a Blast(3)
    /// spell, caps by `combined_alive` (including a joined hero) for `"unit"` targets, and suppresses fan-out (`1`) for
    /// `"model"` targets. Planted fault: fanning out on a `"model"` target asks 6 saves instead of 2 -> RED.
    #[test]
    fn blast_spell_replays_golden_shoot_blast_and_respects_model_target_kind() {
        let golden: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(format!("{}/../../test/fixtures/one_core/golden_shoot_volley.json", env!("CARGO_MANIFEST_DIR"))).expect("shoot volley golden")).unwrap();
        let mut replayed = 0;
        for case in golden["cases"].as_array().unwrap().iter().filter(|c| c["scenario"] == "blast") {
            let lines: Vec<&str> = case["lines"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
            let Some(def_line) = lines.iter().find(|l| l.starts_with("COMBAT|AI (Def) defends: ")) else { continue };
            let save_faces: Vec<u8> = def_line.split(':').nth(1).unwrap().split('\u{2192}').next().unwrap().split_whitespace().map(|x| x.parse().unwrap()).collect();
            let base_hits = (save_faces.len() / 3) as i64;
            let (st, mut statics) = bolt_board(base_hits, &["Blast(3)"], 10);
            statics[0].spells[0].target_kind = "unit".into();
            statics[2].name = "Def".into();
            let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], save_faces.clone()]);
            let ActStep::Done { state, lines: got_lines, .. } = done else { panic!("seed {}: {done:?}", case["seed"]) };
            assert_eq!(asked, ["cast|1x2+|Mystic".into(), format!("spell_defense|{}x4+|Def", save_faces.len())]);
            let ours: Vec<String> = got_lines.iter().skip(3).map(|l| format!("COMBAT|{}", l.text)).collect();
            let save_at = lines.iter().position(|l| *l == "COMBAT|Def saves on 4+").unwrap();
            let want: Vec<String> = lines[save_at..].iter().filter(|l| !l.starts_with("COMBAT|AI (")).map(|l| (*l).to_string()).collect();
            assert_eq!(ours, want, "seed {}: lines", case["seed"]);
            let def_end = &case["final"][1];
            assert_eq!((state.alive[2], state.wounds[2].iter().sum::<i64>(), state.shaken[2]), (def_end["alive"].as_i64().unwrap(), def_end["wounds"].as_i64().unwrap(), def_end["shaken"].as_bool().unwrap()));
            replayed += 1;
        }
        assert_eq!(replayed, 3, "all 3 hitting blast golden cases (seeds 0, 17, 49)");

        // target_kind == "model" on a 6-model target: Blast(3) does NOT fan out (2 hits -> 2 saves, not 6).
        let (st, mut statics) = bolt_board(2, &["Blast(3)"], 6);
        statics[0].spells[0].target_kind = "model".into();
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![4, 1]]);
        let ActStep::Done { state, .. } = done else { panic!("model target: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe"], "model target must not fan out Blast(3)");
        assert_eq!(state.alive[2], 5);

        // target_kind == "unit" caps Blast(3) by combined_alive: 2 host models -> 4 hits; 2 host + 1 joined hero -> 6 hits.
        let (st_two, mut statics_two) = bolt_board(2, &["Blast(3)"], 2);
        statics_two[0].spells[0].target_kind = "unit".into();
        let (_, asked_two) = replay(&statics_two, &st_two, test_bolt(), &[vec![6], vec![4, 4, 4, 4]]);
        assert_eq!(asked_two, ["cast|1x2+|Mystic", "spell_defense|4x4+|Foe"], "2-model unit caps Blast(3) at x2");

        let (mut st_chain, statics_chain) = (st_two, statics_two);
        (st_chain.attached, st_chain.attached_to) = (Rc::new(vec![vec![], vec![], vec![3], vec![]]), Rc::new(vec![None, None, None, Some(2)]));
        (st_chain.alive[3], st_chain.wounds[3]) = (1, vec![1]);
        let mut t = vec![Begin, intent(HOLD, None), Input::Cast(test_bolt())];
        let mut asked_chain = Vec::new();
        for g in [vec![6u8], vec![4, 4, 4, 4, 4, 4]] {
            match step_activation(&statics_chain, &st_chain, "a", &Terrain::default(), Seams { hero_attach: true, ..seams() }, &t, true) {
                ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                    assert_eq!(faces, g.len());
                    asked_chain.push(format!("{kind}|{count}x{target}+|{owner}"));
                    t.push(Faces(g));
                }
                other => panic!("chain blast: {other:?}"),
            }
        }
        assert_eq!(asked_chain, ["cast|1x2+|Mystic", "spell_defense|6x4+|Foe"], "combined_alive 2+1 caps Blast(3) at x3");
    }

    /// CC-7b: Bane, Lacerate, widened bane windows (Obliterate, Reap, Fragment, Decimate) and Shred resolve through
    /// `resolve_spell_hits_with_tray` with the table's re-roll dice (`spell_defense`), log lines, and Regeneration bypass rules.
    #[test]
    fn spell_bane_window_and_shred_resolve_on_tray() {
        // (1) Bane: unmodified 6 re-rolls as `spell_defense`, says Bane line, bypasses named Regeneration.
        let (st, mut statics) = bolt_board(3, &["Bane"], 6);
        (statics[2].ctx.regeneration, statics[2].ctx.regen_target, statics[2].ctx.regen_target_spell, statics[2].ctx.regen_named) = (true, 5, 5, true);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 4, 2], vec![2]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("bane: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|3x4+|Foe", "spell_defense|1x4+|Foe"], "Bane re-rolls 6 and skips named Regeneration");
        assert_eq!(state.alive[2], 4);
        assert!(lines.iter().any(|l| l.text == "Bane: Foe re-rolls 1 unmodified Defense 6"), "{lines:?}");

        // (2) Lacerate: unmodified 6 re-rolls with Lacerate line, does NOT bypass named Regeneration (A1).
        let (st, mut statics) = bolt_board(2, &["Lacerate"], 6);
        (statics[2].ctx.regeneration, statics[2].ctx.regen_target, statics[2].ctx.regen_target_spell, statics[2].ctx.regen_named) = (true, 5, 5, true);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 4], vec![2], vec![5]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("lacerate: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe", "spell_defense|1x4+|Foe", "spell_attack|1x5+|Foe"]);
        assert_eq!(state.alive[2], 6, "Regeneration ignores the 1 wound on a 5");
        assert!(lines.iter().any(|l| l.text == "Lacerate: Foe re-rolls 1 unmodified Defense 6"), "{lines:?}");

        // (3) Obliterate vs Tough(3)+ (named Regeneration): 5+ window re-rolls both 6 and 5, bypasses Regeneration, says applied-facets line.
        let (mut st, mut statics) = bolt_board(4, &["Obliterate"], 3);
        (statics[2].wounds_max, statics[2].ctx.tough) = (vec![3; 3], 3);
        (statics[2].ctx.regeneration, statics[2].ctx.regen_target, statics[2].ctx.regen_target_spell, statics[2].ctx.regen_named) = (true, 5, 5, true);
        let mut list = st.profiles.list.clone();
        list[2].wounds_max = vec![3; 3];
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.wounds[2] = vec![3; 3];
        st.kits[2] = Rc::new(vec![Kit { weapons: vec![], equipment: 0, wounds_max: 3 }; 3]);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 5, 4, 2], vec![1, 1]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("obliterate tough3: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|4x4+|Foe", "spell_defense|2x4+|Foe"]);
        assert_eq!(state.alive[2], 2, "3 unsaved wounds kill 1 Tough(3) model; Regeneration bypassed");
        assert!(lines.iter().any(|l| l.text == "Test Bolt: Obliterate \u{2014} save window 5+ vs Tough(3)+, Regeneration bypassed"), "{lines:?}");
        assert!(lines.iter().any(|l| l.text == "Bane: Foe re-rolls 2 unmodified Defense rolls of 5+"), "{lines:?}");

        // Obliterate vs Tough(1): condition fails -> no Obliterate line and no Bane re-roll.
        let (st1, statics1) = bolt_board(2, &["Obliterate"], 6);
        let (done1, asked1) = replay(&statics1, &st1, test_bolt(), &[vec![6], vec![6, 5]]);
        let ActStep::Done { lines: l1, .. } = done1 else { panic!("obliterate tough1") };
        assert_eq!(asked1, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe"]);
        assert!(!l1.iter().any(|l| l.text.contains("Obliterate")), "{l1:?}");

        // (4) Purge + Reap vs Shaken + Fatigued (Def 3+ -> AP +2 -> 5+, window 5+ re-rolls 6 and 5).
        let (mut st, mut statics) = bolt_board(3, &["Purge", "Reap"], 6);
        statics[2].ctx.defense = 3;
        (st.shaken[2], st.fatigued[2]) = (true, true);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 5, 4], vec![1, 1]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("purge+reap: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|3x5+|Foe", "spell_defense|2x5+|Foe"]);
        assert_eq!(state.alive[2], 3, "all 3 unsaved (4 failed 5+, 6 and 5 re-rolled to 1s); already shaken draws no morale die");
        assert!(lines.iter().any(|l| l.text == "Test Bolt: Purge +2 AP vs Shaken + Fatigued, Reap \u{2014} save window 5+ vs Shaken + Fatigued"), "{lines:?}");

        // (5) Fragment vs Defense 5+ (re-rolls 6 and 5); vs Defense 4+ (no Fragment).
        let (st, mut statics) = bolt_board(3, &["Fragment"], 6);
        statics[2].ctx.defense = 5;
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 5, 4], vec![1, 6]]);
        let ActStep::Done { lines, .. } = done else { panic!("fragment def5: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|3x5+|Foe", "spell_defense|2x5+|Foe"]);
        assert!(lines.iter().any(|l| l.text == "Test Bolt: Fragment \u{2014} save window 5+ vs Defense 5+"), "{lines:?}");

        // (6) Decimate: above half -> re-rolls 6s + line; at half (3/6) -> silent, no re-roll.
        let (st, statics) = bolt_board(2, &["Decimate"], 6);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![6, 4], vec![1]]);
        let ActStep::Done { lines, .. } = done else { panic!("decimate above: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe", "spell_defense|1x4+|Foe"]);
        assert!(lines.iter().any(|l| l.text == "Test Bolt: Decimate \u{2014} Bane vs a target above half"), "{lines:?}");

        let (mut st_half, statics_half) = bolt_board(2, &["Decimate"], 6);
        (st_half.alive[2], st_half.wounds[2]) = (3, vec![1; 3]);
        st_half.positions[2].truncate(3);
        let (done_h, asked_h) = replay(&statics_half, &st_half, test_bolt(), &[vec![6], vec![6, 4]]);
        let ActStep::Done { lines: lh, .. } = done_h else { panic!("decimate half") };
        assert_eq!(asked_h, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe"]);
        assert!(!lh.iter().any(|l| l.text.contains("Decimate")), "{lh:?}");

        // (7) Shred: unmodified Defense 1 adds +1 wound and says the Shred line.
        let (st, statics) = bolt_board(2, &["Shred"], 6);
        let (done, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![4, 1]]);
        let ActStep::Done { state, lines, .. } = done else { panic!("shred: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe"]);
        assert_eq!(state.alive[2], 4, "1 unsaved + 1 Shred extra wound = 2 wounds");
        assert!(lines.iter().any(|l| l.text == "Shred: 1 Defense roll of 1 \u{2192} +1 wound"), "{lines:?}");
    }

    /// CC-7b: applied-facets lines and conditional AP (`effective_ap`) match `_solo_resolve_spell_damage` (Destructive above/at
    /// half, Fracture, Shatter, Puncture, Disintegrate, Tear).
    #[test]
    fn spell_applied_facets_line_and_conditional_ap_match_table() {
        // Destructive above half -> +1 AP (4+ -> 5+); at half -> not applied (4+).
        let (st, statics) = bolt_board(2, &["Destructive"], 6);
        let (ActStep::Done { lines, .. }, asked) = replay(&statics, &st, test_bolt(), &[vec![6], vec![4, 4]]) else { panic!("destructive above") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "spell_defense|2x5+|Foe"]);
        assert!(lines.iter().any(|l| l.text == "Test Bolt: Destructive +1 AP (above half)"), "{lines:?}");

        let (mut st_h, statics_h) = bolt_board(2, &["Destructive"], 6);
        (st_h.alive[2], st_h.wounds[2]) = (3, vec![1; 3]);
        st_h.positions[2].truncate(3);
        let (ActStep::Done { lines: lh, .. }, asked_h) = replay(&statics_h, &st_h, test_bolt(), &[vec![6], vec![4, 4]]) else { panic!("destructive half") };
        assert_eq!(asked_h, ["cast|1x2+|Mystic", "spell_defense|2x4+|Foe"]);
        assert!(lh.iter().any(|l| l.text == "Test Bolt: Destructive not applied (target at or below half)"), "{lh:?}");

        // Fracture (v36: sixes get AP(+2)) & Shatter (v36: sixes get AP(+3)) say their applied-facets line BEFORE trigger roll.
        let (st_f, statics_f) = bolt_board(2, &["Fracture"], 6);
        let (ActStep::Done { lines: lf, .. }, asked_f) = replay(&statics_f, &st_f, test_bolt(), &[vec![6], vec![6, 2], vec![5], vec![4]]) else { panic!("fracture") };
        assert_eq!(asked_f, ["cast|1x2+|Mystic", "spell_attack|2x6+|Mystic", "spell_defense|1x6+|Foe", "spell_defense|1x4+|Foe"]);
        assert!(lf.iter().any(|l| l.text == "Test Bolt: Fracture \u{2014} sixes get AP(+2)"), "{lf:?}");

        let (st_s, statics_s) = bolt_board(2, &["Shatter"], 6);
        let (ActStep::Done { lines: ls, .. }, asked_s) = replay(&statics_s, &st_s, test_bolt(), &[vec![6], vec![6, 2], vec![6], vec![4]]) else { panic!("shatter") };
        assert_eq!(asked_s, ["cast|1x2+|Mystic", "spell_attack|2x6+|Mystic", "spell_defense|1x6+|Foe", "spell_defense|1x4+|Foe"]);
        assert!(ls.iter().any(|l| l.text == "Test Bolt: Shatter \u{2014} sixes get AP(+3)"), "{ls:?}");

        // Puncture vs Def 3+ (+2 AP -> 5+); Disintegrate vs Tough(3)+ (+2 AP -> 6+); Tear vs Tough(9)+ (+4 AP -> 6 only, silent).
        let (st_p, mut statics_p) = bolt_board(2, &["Puncture"], 6);
        statics_p[2].ctx.defense = 3;
        let (ActStep::Done { lines: lp, .. }, asked_p) = replay(&statics_p, &st_p, test_bolt(), &[vec![6], vec![5, 5]]) else { panic!("puncture") };
        assert_eq!(asked_p, ["cast|1x2+|Mystic", "spell_defense|2x5+|Foe"]);
        assert!(lp.iter().any(|l| l.text == "Test Bolt: Puncture \u{2014} ignores Regeneration, AP(+2) vs Defense 3 or less"), "{lp:?}");

        let (st_d, mut statics_d) = bolt_board(2, &["Disintegrate"], 6);
        statics_d[2].ctx.tough = 3;
        let (ActStep::Done { lines: ld, .. }, asked_d) = replay(&statics_d, &st_d, test_bolt(), &[vec![6], vec![6, 6]]) else { panic!("disintegrate") };
        assert_eq!(asked_d, ["cast|1x2+|Mystic", "spell_defense|2x6+|Foe"]);
        assert!(ld.iter().any(|l| l.text == "Test Bolt: Disintegrate \u{2014} ignores Regeneration, AP(+2) vs Tough(3)+"), "{ld:?}");

        let (st_t, mut statics_t) = bolt_board(2, &["Tear"], 1);
        statics_t[2].ctx.tough = 9;
        let (ActStep::Done { lines: lt, .. }, asked_t) = replay(&statics_t, &st_t, test_bolt(), &[vec![6], vec![6, 6]]) else { panic!("tear") };
        assert_eq!(asked_t, ["cast|1x2+|Mystic", "spell_defense|2x6+|Foe"]);
        assert!(lt.iter().any(|l| l.text == "Foe saves on 6 only (Def 4+, AP 4 \u{2014} a natural 6 always saves)"), "{lt:?}");

        // Direct pub(crate) smoke on spell::effective_ap and spell::bane_window.
        let f_ob = crate::spell::spell_facets(&["Obliterate".into(), "Purge".into()], crate::acts::CURRENT_RULES_EPOCH);
        let d_ctx = crate::unit::Ctx { defense: 4, tough: 3, shaken_or_fatigued: true, ..Default::default() };
        assert_eq!(crate::spell::effective_ap(&f_ob, &d_ctx), 2);
        assert_eq!(crate::spell::bane_window(&f_ob, &d_ctx), (true, 5));
    }

    // ---- CC-8b: modifier / grant effects through PlainBuff, granted reach, effect-less spells, CC-6a hazard 2 ----

    /// CC-8b: all 26 cases of CC-2's golden (`golden_cast_effects.json`: `buff_self`, `debuff_foe`, `fizzle`,
    /// `boost_interference`, `casting_once`) replay end-to-end through `step_activation`: exact rolls, exact core lines,
    /// and exact resulting `LiveMod` records on Mystic and Foe (table landing lines stay on the table, CC-12a).
    #[test]
    fn cc8b_the_effects_cases_of_the_cc2_golden_replay_roll_for_roll_and_mod_for_mod() {
        use crate::rules::{Spell, SpellModifier};
        let golden: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(format!("{}/../../test/fixtures/one_core/golden_cast_effects.json", env!("CARGO_MANIFEST_DIR"))).expect("the CC-2 golden")).unwrap();
        let text = |v: &serde_json::Value| v.as_str().unwrap().to_string();
        let fmt_mod = |r: &LiveMod| format!("{}|hit {}|def {}|cast {}|morale {}|grants {}|{}", r.name, r.hit_mod, r.def_mod, r.casting_mod, r.morale_mod, r.grants_rule, if r.once { "once" } else { "round" });
        let is_table_line = |l: &str| {
            l.starts_with("COMBAT|AI (")
                || l.contains(" takes effect on ")
                || l.contains(" token placed on ")
                || l.contains(" is ACTIVE: ")
                || l.contains(" is consumed (")
        };
        let mut seen = std::collections::BTreeMap::new();
        for case in golden["cases"].as_array().unwrap() {
            let (name, seed) = (text(&case["scenario"]), case["seed"].as_i64().unwrap());
            let (mut st, mut statics) = die_line();
            let warding = Spell { name: "Warding Chant".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, grants_rule: "Fearless".into(), ..Default::default() };
            let withering = Spell { name: "Withering Gaze".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, modifier: SpellModifier { present: true, def_mod: -1.0, ..Default::default() }, ..Default::default() };
            statics[0].spells = vec![warding, withering];
            st.casts = vec![6, 0, 0, 1];
            let cast = match name.as_str() {
                "buff_self" => CastInput { spell: "Warding Chant".into(), targets: vec!["a".into()], base: 4, threshold: 1, once: true, ..bolt(0) },
                "debuff_foe" => CastInput { spell: "Withering Gaze".into(), targets: vec!["b".into()], base: 4, threshold: 1, once: false, ..bolt(0) },
                "fizzle" => {
                    (st.alive[2], st.wounds[2], st.positions[2]) = (0, Vec::new(), Vec::new());
                    CastInput { spell: "Warding Chant".into(), targets: vec!["b".into()], base: 4, threshold: 1, once: true, ..bolt(0) }
                }
                "boost_interference" => CastInput { spell: "Warding Chant".into(), targets: vec!["a".into()], base: 4, threshold: 2, boost: 2, boost_sources: vec![("a".into(), 2)], interference: 1, interference_sources: vec![("bh".into(), 1)], once: true, ..bolt(0) },
                "casting_once" => {
                    st.buffs[0] = vec![serde_json::from_value::<crate::io::PlainLedger>(serde_json::json!({"buffs":[{"spell":"Focus","casting_mod":1,"duration":"once"}]})).unwrap()].into_iter().next().map(|l| {
                        let mut tmp = st.clone();
                        crate::io::fold_ledger(&mut tmp, 0, &l, crate::acts::CURRENT_RULES_EPOCH, 1, false, -1);
                        tmp.buffs[0].pop().unwrap()
                    }).into_iter().collect();
                    CastInput { spell: "Warding Chant".into(), targets: vec!["a".into()], base: 4, threshold: 1, once: true, ..bolt(0) }
                }
                other => panic!("unknown scenario {other}"),
            };
            let rolls: Vec<Vec<String>> = case["extra"]["rolls"].as_array().unwrap().iter().map(|r| text(r).split('|').map(String::from).collect()).collect();
            let groups: Vec<Vec<u8>> = rolls.iter().map(|r| r[4].split(',').map(|f| f.parse().unwrap()).collect()).collect();
            let want_rolls: Vec<String> = rolls.iter().map(|r| format!("cast|{}|{}", r[2], r[3].trim_start_matches("AI (").trim_end_matches(')'))).collect();
            let (done, asked) = replay(&statics, &st, cast, &groups);
            let ActStep::Done { state, lines, .. } = done else { panic!("{name} {seed}: expected Done, got {done:?}") };
            assert_eq!(asked, want_rolls, "{name} {seed}: rolls");
            let ours: Vec<String> = lines.iter().map(|l| format!("COMBAT|{}", l.text)).collect();
            let want: Vec<String> = case["lines"].as_array().unwrap().iter().map(text).filter(|l| !is_table_line(l)).collect();
            assert_eq!(ours, want, "{name} {seed}: lines");
            let mods_arr = case["extra"]["mods"].as_array().unwrap();
            let want_a: Vec<String> = mods_arr[0][1].as_array().unwrap().iter().map(text).collect();
            let want_b: Vec<String> = mods_arr[1][1].as_array().unwrap().iter().map(text).collect();
            let got_a: Vec<String> = state.buffs[0].iter().map(fmt_mod).collect();
            let got_b: Vec<String> = state.buffs[2].iter().map(fmt_mod).collect();
            assert_eq!((got_a, got_b), (want_a, want_b), "{name} {seed}: LiveMods");
            *seen.entry(name).or_insert(0) += 1;
        }
        assert_eq!(seen.values().copied().collect::<Vec<_>>(), [6, 6, 6, 6, 2], "all 26 golden_cast_effects cases: {seen:?}");
    }

    /// The tray path's spell tokens left, `[off: cast + volley, off: plain volley, on: cast + volley, on: plain volley]`,
    /// for a caster holding 4 tokens: a planned Ward cast (costs 1) and a "Big Bolt" damage spell the legacy volley rider
    /// could still buy (cost 1, in range), at `rules_epoch`. "off"/"on" is `seam_cast`.
    fn rider_tokens(rules_epoch: u32) -> [i64; 4] {
        use crate::rules::{Spell, SpellModifier};
        let (mut st, mut statics) = bolt_board(0, &[], 6);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        statics[0].spells = vec![
            Spell { name: "Ward".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, modifier: SpellModifier { present: true, def_mod: 1.0, ..Default::default() }, ..Default::default() },
            Spell { name: "Big Bolt".into(), effect_kind: "damage".into(), effect_hits: 3, weapon_rules: vec![], threshold: 1, range_in: 24.0, target_count: 1, ..Default::default() },
        ];
        st.casts[0] = 4; // spare tokens: the planned cast costs 1, the volley's rider could still buy "Big Bolt"
        let ward = CastInput { spell: "Ward".into(), targets: vec!["a".into()], base: 2, threshold: 1, ..bolt(0) };
        let tokens_after = |on: bool, t: Vec<Input>| {
            let s = Seams { cast: on, rules_epoch, ..seams() };
            let ActStep::Done { state, .. } = finish_with(&statics, &st, s, t) else { panic!("seam_cast {on}: the activation ends") };
            state.casts[0]
        };
        let with_cast = vec![Begin, intent(HOLD, Some("b")), Input::Cast(ward.clone())];
        let plain = vec![Begin, intent(HOLD, Some("b"))];
        [
            tokens_after(false, with_cast.clone()), tokens_after(false, plain.clone()),
            tokens_after(true, with_cast), tokens_after(true, plain),
        ]
    }

    /// `EPOCH_93_DANGER_RULES_RIDER` (found by the CAST-O7 probe): with `seam_cast` OFF (every shipped header) the volley's legacy spell
    /// rider (sim.rs `resolve`, the `!seams.cast` branch) spent tokens on the tray path too: a caster with SPARE tokens and
    /// an affordable damage spell in range paid for a cast it never makes, on top of the tokens its planned casts paid. The
    /// table has no rider (its casts are the planned ones, paid at plan time), so the shadow read `casts` core 0 vs table 2.
    /// From 93 the off side keeps the table's 3 and 4. RED: the gate removed -> the 93 row reads `[2, 3, 3, 2]`.
    #[test]
    fn rider_off_93_the_volleys_spell_rider_spends_no_token_on_the_tray_path() {
        // The ON side is untouched (its plain volley reads 2 because the core's own cast sub-phase fires when no tray cast
        // is offered, the seam's intended self-play meaning): only the OFF side moves, to the table's numbers.
        assert_eq!(rider_tokens(crate::acts::EPOCH_93_DANGER_RULES_RIDER), [3, 4, 3, 2], "[off cast+volley, off plain, on cast+volley, on plain]");
    }

    /// Below 93 the rider stays byte-identical: the OFF side pays 1 more token than the table (the old reading).
    #[test]
    fn rider_off_93_below_93_the_legacy_rider_still_spends_a_token() {
        assert_eq!(rider_tokens(crate::acts::EPOCH_93_DANGER_RULES_RIDER - 1), [2, 3, 3, 2], "[off cast+volley, off plain, on cast+volley, on plain]");
    }

    /// CC-8b: a debuff placed by a cast is read by the SAME activation's volley, and obeys `scope` (a melee-scoped debuff
    /// stays out of the shooting volley and stays unspent; an attackers-beneficiary hit buff improves the volley's to-hit).
    /// Planted fault: dropping `scope` makes the melee-scoped debuff fire on shooting (5+ instead of 4+) and spend -> RED.
    #[test]
    fn cc8b_a_debuff_is_read_by_the_same_activations_volley_and_obeys_scope() {
        use crate::rules::{Spell, SpellModifier};
        let (st, mut statics) = bolt_board(0, &[], 6);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        statics[0].spells = vec![
            Spell { name: "Withering".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, scope: "shooting".into(), modifier: SpellModifier { present: true, def_mod: -1.0, ..Default::default() }, ..Default::default() },
            Spell { name: "Crippling".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, scope: "melee".into(), modifier: SpellModifier { present: true, def_mod: -1.0, ..Default::default() }, ..Default::default() },
            Spell { name: "Marked".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, scope: "shooting".into(), beneficiary: "attackers".into(), modifier: SpellModifier { present: true, hit_mod: 1.0, ..Default::default() }, ..Default::default() },
        ];
        let run_cast_shoot = |spell_name: &str, once: bool, groups: &[Vec<u8>]| {
            let cast = CastInput { spell: spell_name.into(), base: 2, threshold: 1, once, ..bolt(0) };
            let mut t = vec![Begin, intent(HOLD, Some("b")), Input::Cast(cast)];
            let mut asked = Vec::new();
            for g in groups {
                match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
                    ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                        assert_eq!(faces, g.len(), "{spell_name} {kind}");
                        asked.push(format!("{kind}|{count}x{target}+|{owner}"));
                        t.push(Faces(g.clone()));
                    }
                    other => panic!("{spell_name}: expected NeedRoll, got {other:?}"),
                }
            }
            (step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true), asked)
        };
        // (1) Shooting-scoped def_mod -1 (once): Foe saves on 5+ (4 fails -> 1 dead) and the once-debuff is spent.
        let (done, asked) = run_cast_shoot("Withering", true, &[vec![6], vec![4], vec![4]]);
        let ActStep::Done { state, .. } = done else { panic!("Withering: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "attack|1x4+|Mystic", "defense|1x5+|Foe"]);
        assert_eq!((state.alive[2], state.buffs[2].len()), (5, 0), "5+ fails on 4 and once-debuff is spent");
        // (2) Melee-scoped def_mod -1 (once): stays out of shooting -> Foe saves on 4+ (4 passes -> 0 dead) and debuff persists.
        let (done, asked) = run_cast_shoot("Crippling", true, &[vec![6], vec![4], vec![4]]);
        let ActStep::Done { state, .. } = done else { panic!("Crippling: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "attack|1x4+|Mystic", "defense|1x4+|Foe"]);
        assert_eq!(state.alive[2], 6, "melee-scoped debuff must not degrade shooting save");
        assert_eq!(state.buffs[2].len(), 1, "melee-scoped debuff must stay unspent after shooting");
        assert_eq!(&*state.buffs[2][0].scope, "melee");
        // (3) Attackers-beneficiary hit_mod +1 (shooting, once): Mystic hits on 3+ and spends the mark.
        let (done, asked) = run_cast_shoot("Marked", true, &[vec![6], vec![3], vec![6]]);
        let ActStep::Done { state, .. } = done else { panic!("Marked: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "attack|1x3+|Mystic", "defense|1x4+|Foe"]);
        assert!(state.buffs[2].is_empty(), "attackers once-mark spent by the volley");
    }

    /// CAST-O7 (lead ruling O7, 20.11.): a once-grant spell cast in an activation BEFORE its own attack is spent by that same
    /// activation's volley (casting precedes attacking; the table's `_solo_spend_once_mods` does the same). The record is placed
    /// and spent inside one call, so it is in neither the capture nor the end board: the delta must still name it in
    /// `buffs_spent` (name, scope), on the unit that held it, even when that unit changed in nothing else. A once record the
    /// volley does not spend (melee scope), a round record and a record placed by NO cast (the old before/after diff) stay as they
    /// were. RED: `delta_of` reading only before vs after -> every "spent" row below is empty.
    #[test]
    fn cast_o7_a_once_buff_cast_before_the_volley_and_spent_by_it_is_in_the_delta() {
        use crate::rules::{Spell, SpellModifier};
        let (st, mut statics) = bolt_board(0, &[], 6);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        let spell = |name: &str, kind: &str, scope: &str, who: &str, m: SpellModifier| Spell {
            name: name.into(), effect_kind: kind.into(), threshold: 1, target_count: 1, scope: scope.into(), beneficiary: who.into(), modifier: m, ..Default::default()
        };
        let m = |hit: f64, def: f64, cast: f64, range: f64| SpellModifier { present: true, hit_mod: hit, def_mod: def, casting_mod: cast, range_in: range, ..Default::default() };
        statics[0].spells = vec![
            spell("Marked", "debuff", "shooting", "attackers", m(1.0, 0.0, 0.0, 0.0)),
            spell("Withering", "debuff", "shooting", "", m(0.0, -1.0, 0.0, 0.0)),
            spell("Crippling", "debuff", "melee", "", m(0.0, -1.0, 0.0, 0.0)),
            spell("Battle Rune", "buff", "shooting", "", m(0.0, 0.0, 0.0, 6.0)),
            spell("Focus", "buff", "", "", m(0.0, 0.0, 1.0, 0.0)),
            spell("Ward", "buff", "", "", m(0.0, 1.0, 0.0, 0.0)),
        ];
        // `miss`: every attack die fails (the foe's row would not exist without the spent record); otherwise every hit lands.
        let run = |casts: &[(&str, &str, bool)], tokens: i64, miss: bool| {
            let mut st = st.clone();
            st.casts[0] = tokens;
            let mut t = vec![Begin, intent(HOLD, Some("b"))];
            t.extend(casts.iter().enumerate().map(|(i, (name, at, once))| Input::Cast(CastInput { seq: i as i64, spell: (*name).into(), targets: vec![(*at).into()], base: 2, threshold: 1, once: *once, ..bolt(0) })));
            loop {
                match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
                    ActStep::NeedRoll { kind, faces, .. } => t.push(Faces(vec![if (kind == "attack" && miss) || kind == "defense" { 1 } else { 6 }; faces])),
                    ActStep::Done { state, .. } => return (st.clone(), state),
                    other => panic!("{casts:?}: {other:?}"),
                }
            }
        };
        let spent = |st: &State, after: &State, key: &str| delta_of(st, after).into_iter().find(|d| d.key == key).map(|d| d.buffs_spent);
        let pair = |n: &str, scope: &str| vec![(n.to_string(), scope.to_string())];
        // (1) a debuff on the foe the volley's save reads (def role), and the attackers-side mark its to-hit reads (vs-target role)
        let (before, after) = run(&[("Withering", "b", true)], 1, false);
        assert!(after.buffs[2].is_empty(), "the core spent it (the old behaviour)");
        assert_eq!(spent(&before, &after, "b"), Some(pair("Withering", "shooting")), "defense debuff spent by the volley");
        let (before, after) = run(&[("Marked", "b", true)], 1, true);
        assert_eq!(spent(&before, &after, "b"), Some(pair("Marked", "shooting")), "vs-target mark: the foe changed in nothing else, its row still names the spend");
        // (2) the caster's own buff (range) on itself
        let (before, after) = run(&[("Battle Rune", "a", true)], 1, false);
        assert_eq!(spent(&before, &after, "a"), Some(pair("Battle Rune", "shooting")), "the caster's own once buff");
        // (3) a casting once-record spent by the NEXT cast's roll, not by the volley
        let (before, after) = run(&[("Focus", "a", true), ("Ward", "a", false)], 2, false);
        assert_eq!(spent(&before, &after, "a"), Some(pair("Focus", "")), "Focus is spent by the second cast's die, the round Ward stays");
        assert_eq!(after.buffs[0].len(), 1, "only the round Ward is held at the end");
        // (4) what is NOT spent is not reported: a melee-scoped once record, a round record
        let (before, after) = run(&[("Crippling", "b", true)], 1, false);
        assert_eq!((after.buffs[2].len(), spent(&before, &after, "b").map_or(0, |v| v.len())), (1, 0), "melee scope stays out of the volley");
        let (before, after) = run(&[("Withering", "b", false)], 1, false);
        assert_eq!((after.buffs[2].len(), spent(&before, &after, "b").map_or(0, |v| v.len())), (1, 0), "a round record is never spent");
        // (5) a record the capture already held (no cast): the old before/after diff still names it, once
        let mut held = st.clone();
        held.buffs[2] = vec![LiveMod { attackers: true, ..once_buff("Marked", "shooting", true) }];
        let ActStep::Done { state: after, .. } = finish_with(&statics, &held, seams(), vec![Begin, intent(HOLD, Some("b"))]) else { panic!("a plain volley") };
        assert_eq!(spent(&held, &after, "b"), Some(pair("Marked", "shooting")), "a captured once record spent by the volley");
        // (6) a record in the capture AND an identical one cast on it: the volley spends both and both are named
        held.casts[0] = 1;
        let cast = Input::Cast(CastInput { seq: 0, spell: "Marked".into(), targets: vec!["b".into()], base: 2, threshold: 1, once: true, ..bolt(0) });
        // below the epoch 95 batch (SPELL_NO_STACK) the two stack and the volley spends both; from 95 the cast refreshes the captured record
        let below = Seams { rules_epoch: crate::acts::EPOCH_95_PARITY_BATCH - 1, ..seams() };
        let ActStep::Done { state: after, .. } = finish_with(&statics, &held, below, vec![Begin, intent(HOLD, Some("b")), cast.clone()]) else { panic!("a cast and a volley") };
        assert_eq!(spent(&held, &after, "b"), Some([pair("Marked", "shooting"), pair("Marked", "shooting")].concat()), "below 95 the captured record and the cast one are two spends");
        let ActStep::Done { state: after, .. } = finish_with(&statics, &held, seams(), vec![Begin, intent(HOLD, Some("b")), cast]) else { panic!("a cast and a volley") };
        assert_eq!(spent(&held, &after, "b"), Some(pair("Marked", "shooting")), "from 95 the identical cast refreshes the captured record: one spend");
    }

    /// CC-8c: the delta's `buffs_gained` names, per unit and in placement order, the effects this activation's casts landed
    /// and the activation did not spend: once and round records, a record the volley never reads (melee scope), and an
    /// effect-less spell (no modifier, no grant: nothing on the board, the table still announces it and places its token).
    /// A record placed and spent inside the activation is in `buffs_spent` only; a failed cast gains nothing; a plain
    /// activation reports no gain. RED: `cast_gained_of` returning nothing -> every "gained" below is empty; the old early
    /// return for an effect-less spell -> the "Lore" case is empty; spent records counted as gained -> the "Withering" case.
    #[test]
    fn cc8c_the_delta_names_the_effects_the_casts_landed_and_nothing_spent() {
        use crate::rules::{Spell, SpellModifier};
        let (st, mut statics) = bolt_board(0, &[], 6);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        let spell = |name: &str, kind: &str, scope: &str, m: SpellModifier| Spell {
            name: name.into(), effect_kind: kind.into(), threshold: 1, target_count: 1, scope: scope.into(), modifier: m, ..Default::default()
        };
        let m = |def: f64| SpellModifier { present: true, def_mod: def, ..Default::default() };
        statics[0].spells = vec![
            spell("Crippling", "debuff", "melee", m(-1.0)),
            spell("Withering", "debuff", "shooting", m(-1.0)),
            spell("Ward", "buff", "", m(1.0)),
            spell("Lore", "buff", "", SpellModifier::default()),
            Spell { name: "Fearless Chant".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, grants_rule: "Fearless".into(), ..Default::default() },
        ];
        // `ok`: the cast die passes (6) or fails (1); the volley's attack dice always hit, its saves always fail.
        let run = |casts: &[(&str, &str, bool)], ok: bool| {
            let mut st = st.clone();
            st.casts[0] = 5;
            let mut t = vec![Begin, intent(HOLD, Some("b"))];
            t.extend(casts.iter().enumerate().map(|(i, (name, at, once))| Input::Cast(CastInput { seq: i as i64, spell: (*name).into(), targets: vec![(*at).into()], base: 2, threshold: 1, once: *once, ..bolt(0) })));
            loop {
                match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
                    ActStep::NeedRoll { kind, faces, .. } => t.push(Faces(vec![if kind == "defense" || (kind == "cast" && !ok) { 1 } else { 6 }; faces])),
                    ActStep::Done { state, .. } => return (st.clone(), state),
                    other => panic!("{casts:?}: {other:?}"),
                }
            }
        };
        let gained = |st: &State, after: &State, key: &str| delta_of(st, after).into_iter().find(|d| d.key == key).map(|d| d.buffs_gained);
        let names = |v: &[&str]| Some(v.iter().map(|n| n.to_string()).collect::<Vec<_>>());
        // (1) kept: a melee-scope once debuff (the volley never reads it), a round buff on the caster, a grant
        let (b, a) = run(&[("Crippling", "b", true)], true);
        assert_eq!(gained(&b, &a, "b"), names(&["Crippling"]), "a once record the volley leaves");
        let (b, a) = run(&[("Ward", "a", false)], true);
        assert_eq!(gained(&b, &a, "a"), names(&["Ward"]), "a round record");
        let (b, a) = run(&[("Fearless Chant", "a", false)], true);
        assert_eq!(gained(&b, &a, "a"), names(&["Fearless Chant"]), "a granted rule");
        // (2) an effect-less spell: nothing on the board, still named
        let (b, a) = run(&[("Lore", "b", false)], true);
        assert!(a.buffs[2].is_empty(), "nothing was pushed on the board");
        assert_eq!(gained(&b, &a, "b"), names(&["Lore"]), "effect-less spells are named too");
        // (3) placement order across casts on one unit
        let (b, a) = run(&[("Ward", "a", false), ("Fearless Chant", "a", false)], true);
        assert_eq!(gained(&b, &a, "a"), names(&["Ward", "Fearless Chant"]), "placement order");
        // (4) placed and spent by this activation's own volley: spent only, not gained (no news for the table)
        let (b, a) = run(&[("Withering", "b", true)], true);
        let row = delta_of(&b, &a).into_iter().find(|d| d.key == "b").expect("the foe's row");
        assert_eq!((row.buffs_gained.clone(), row.buffs_spent.len()), (Vec::new(), 1), "{row:?}");
        // (5) a failed cast lands nothing; an activation without a cast reports no gain
        let (b, a) = run(&[("Ward", "a", false)], false);
        assert_eq!(gained(&b, &a, "a").map_or(0, |v| v.len()), 0, "a failed cast gains nothing");
        let ActStep::Done { state: a, .. } = finish_with(&statics, &st, seams(), vec![Begin, intent(HOLD, Some("b"))]) else { panic!("a plain volley") };
        assert!(delta_of(&st, &a).iter().all(|d| d.buffs_gained.is_empty()), "no cast, no gain");
    }

    /// CAST-O7: answers every die the core asks, a success for the shooter and a failed save for the foe, to the end.
    fn finish_with(statics: &[UnitStatic], st: &State, seams: Seams, mut t: Vec<Input>) -> ActStep {
        loop {
            match step_activation(statics, st, "a", &Terrain::default(), seams, &t, true) {
                ActStep::NeedRoll { kind, faces, .. } => t.push(Faces(vec![if kind == "defense" { 1 } else { 6 }; faces])),
                other => return other,
            }
        }
    }

    /// CC-8b: a reach spell cast in the same activation widens the activation's volley — both a `modifier.range_in` buff
    /// (`Battle Rune` +6", scope "shooting") and a Royal Legion-family `grants_rule` buff (`Lust Boon` -> `Enhanced Lustbound` +8").
    /// Planted fault: dropping `scope` makes a melee-scoped `range_in` buff wrongly widen shooting -> RED.
    #[test]
    fn cc8b_granted_reach_widens_the_same_activations_volley() {
        use crate::rules::{Spell, SpellModifier};
        let sight_seams = Seams { sighting: true, ..seams() };
        let drive_sight = |statics: &[UnitStatic], st: &State, mut t: Vec<Input>, groups: &[Vec<u8>]| {
            let mut asked = Vec::new();
            for g in groups {
                match step_activation(statics, st, "a", &Terrain::default(), sight_seams, &t, true) {
                    ActStep::NeedRoll { kind, count, target, owner, faces, .. } => {
                        assert_eq!(faces, g.len(), "{kind}");
                        asked.push(format!("{kind}|{count}x{target}+|{owner}"));
                        t.push(Faces(g.clone()));
                    }
                    other => return (other, asked),
                }
            }
            (step_activation(statics, st, "a", &Terrain::default(), sight_seams, &t, true), asked)
        };
        // (1) modifier.range_in +6" (`Battle Rune`, scope "shooting", once): 24" rifle reaches Foe parked 28" away.
        let (mut st, mut statics) = bolt_board(0, &[], 3);
        statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 1, count: 1, range: 24, ..Default::default() }];
        statics[0].ctx.quality = 4;
        statics[0].spells = vec![
            Spell { name: "Battle Rune".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, scope: "shooting".into(), modifier: SpellModifier { present: true, range_in: 6.0, ..Default::default() }, ..Default::default() },
            Spell { name: "Melee Reach".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, scope: "melee".into(), modifier: SpellModifier { present: true, range_in: 6.0, ..Default::default() }, ..Default::default() },
        ];
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.positions[1] = vec![[-2.0 * INCHES_TO_METERS, 0.0, 5.0 * INCHES_TO_METERS]];
        st.positions[2] = vec![[28.0 * INCHES_TO_METERS, 0.0, 0.0]; 3];
        st.positions[3] = vec![[-2.0 * INCHES_TO_METERS, 0.0, -5.0 * INCHES_TO_METERS]];
        // Control: without casting, the 24" rifle cannot reach 28".
        let (ctrl, asked) = drive_sight(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], &[]);
        assert!(matches!(ctrl, ActStep::Done { .. }) && asked.is_empty(), "control: out of 24\" reach ({asked:?})");
        // With Battle Rune (shooting, once): reaches 28", rolls attack, then spends the once-buff.
        let cast_rune = CastInput { spell: "Battle Rune".into(), targets: vec!["a".into()], base: 2, threshold: 1, once: true, ..bolt(0) };
        let (done, asked) = drive_sight(&statics, &st, vec![Begin, intent(HOLD, Some("b")), Input::Cast(cast_rune)], &[vec![6], vec![1]]);
        let ActStep::Done { state, .. } = done else { panic!("Battle Rune: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "attack|1x4+|Mystic"], "24 + 6 reaches 28\"");
        assert!(state.buffs[0].is_empty(), "once range buff spent by the shooting volley");
        // Scope control: melee-scoped range_in does NOT widen shooting.
        let cast_melee = CastInput { spell: "Melee Reach".into(), targets: vec!["a".into()], base: 2, threshold: 1, once: true, ..bolt(0) };
        let (done, asked) = drive_sight(&statics, &st, vec![Begin, intent(HOLD, Some("b")), Input::Cast(cast_melee)], &[vec![6]]);
        assert!(matches!(done, ActStep::Done { .. }), "melee reach: {done:?}");
        assert_eq!(asked, ["cast|1x2+|Mystic"], "melee-scoped range_in must not widen shooting");

        // (2) Royal Legion grant (`Lust Boon` -> `Enhanced Lustbound`, +8"): 24" rifle reaches Foe parked 30" away.
        let header = crate::read_act_header(r#"{"kind":"header","knobs":{},"profiles":{"shooter":{"unit_id":"shooter","name":"Mystic","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":1,"base_radius":0.016,"game_system":"gf","faction_folder":"lust_disciples","special_rules":["Caster(1)"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#).unwrap();
        let mut reg = crate::rules::Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
        statics[0] = UnitStatic::build_for(&mut reg, header.profiles.get("shooter").unwrap(), crate::acts::CURRENT_RULES_EPOCH);
        st.positions[2] = vec![[30.0 * INCHES_TO_METERS, 0.0, 0.0]; 3];
        let cast_boon = CastInput { spell: "Lust Boon".into(), targets: vec!["a".into()], base: 2, threshold: 1, once: true, ..bolt(0) };
        let (done, asked) = drive_sight(&statics, &st, vec![Begin, intent(HOLD, Some("b")), Input::Cast(cast_boon)], &[vec![6], vec![1]]);
        let ActStep::Done { state, .. } = done else { panic!("Lust Boon: {done:?}") };
        assert_eq!(asked, ["cast|1x2+|Mystic", "attack|1x4+|Mystic"], "24 + 8 reaches 30\"");
        assert!(state.buffs[0].is_empty(), "Lust Boon once-grant spent by the shooting volley");
    }

    /// CC-8b: a capture of the landed table record (`unit_properties["spell_records"]` folded through `PlainLedger` /
    /// `fold_ledger`) equals the core's `LiveMod` from `tray_cast`, field for field — including `scope`, `beneficiary`,
    /// `once`, `range_in` and a speed-only spell whose advance/rush stay unparsed (`move_mod == 0`).
    /// Planted fault: dropping `scope` breaks equality on every scoped case -> RED.
    #[test]
    fn cc8b_a_capture_of_the_landed_table_record_equals_the_cores_live_mod() {
        use crate::rules::{Spell, SpellModifier};
        let cases: Vec<(Spell, bool, serde_json::Value)> = vec![
            (
                Spell { name: "Withering Gaze".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, scope: "shooting".into(), modifier: SpellModifier { present: true, def_mod: -1.0, ..Default::default() }, ..Default::default() },
                false,
                serde_json::json!({"spell":"Withering Gaze","hit_mod":0,"def_mod":-1,"casting_mod":0,"morale_mod":0,"range_in":0,"advance_in":0,"rush_in":0,"grants_rule":"","scope":"shooting","beneficiary":"","duration":"round"}),
            ),
            (
                Spell { name: "Advanced Sight".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, scope: "shooting".into(), beneficiary: "attackers".into(), grants_rule: "Unstoppable".into(), ..Default::default() },
                true,
                serde_json::json!({"spell":"Advanced Sight","hit_mod":0,"def_mod":0,"casting_mod":0,"morale_mod":0,"range_in":0,"advance_in":0,"rush_in":0,"grants_rule":"Unstoppable","scope":"shooting","beneficiary":"attackers","duration":"once"}),
            ),
            (
                Spell { name: "Battle Rune".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, scope: "shooting".into(), modifier: SpellModifier { present: true, range_in: 6.0, ..Default::default() }, ..Default::default() },
                true,
                serde_json::json!({"spell":"Battle Rune","hit_mod":0,"def_mod":0,"casting_mod":0,"morale_mod":0,"range_in":6,"advance_in":0,"rush_in":0,"grants_rule":"","scope":"shooting","beneficiary":"","duration":"once"}),
            ),
            (
                Spell { name: "Fleet".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, modifier: SpellModifier { present: true, advance_in: 2.0, rush_in: 4.0, ..Default::default() }, ..Default::default() },
                false,
                serde_json::json!({"spell":"Fleet","hit_mod":0,"def_mod":0,"casting_mod":0,"morale_mod":0,"range_in":0,"advance_in":2,"rush_in":4,"grants_rule":"","scope":"","beneficiary":"","duration":"round"}),
            ),
        ];
        for (spell, once, table_rec) in cases {
            let name = spell.name.clone();
            let (st, mut statics) = bolt_board(0, &[], 3);
            statics[0].spells = vec![spell];
            let cast = CastInput { spell: name.clone(), targets: vec!["b".into()], base: 2, threshold: 1, once, ..bolt(0) };
            let (ActStep::Done { state, .. }, _) = replay(&statics, &st, cast, &[vec![6]]) else { panic!("{name}: expected Done") };
            assert_eq!(state.buffs[2].len(), 1, "{name}: one LiveMod landed");
            let ledger: crate::io::PlainLedger = serde_json::from_value(serde_json::json!({"buffs": [table_rec]})).unwrap();
            let mut captured = st.clone();
            crate::io::fold_ledger(&mut captured, 2, &ledger, crate::acts::CURRENT_RULES_EPOCH, 3, false, -1);
            assert_eq!(state.buffs[2], captured.buffs[2], "{name}: core LiveMod must equal captured table record");
        }
    }

    /// CC-8b: an effect-less buff/debuff spell (no modifier and no grant, or an all-zero modifier dict) is RESOLVED (not
    /// refused) with nothing pushed to `state.buffs`; a multi-target buff lands on every standing target and skips dead ones.
    #[test]
    fn cc8b_effectless_spells_resolve_cleanly_and_multi_target_lands_on_every_standing_target() {
        use crate::rules::{Spell, SpellModifier};
        let (mut st, mut statics) = bolt_board(0, &[], 3);
        statics[0].spells = vec![
            Spell { name: "Empty Buff".into(), effect_kind: "buff".into(), threshold: 1, target_count: 1, ..Default::default() },
            Spell { name: "Zero Mod".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, modifier: SpellModifier { present: true, ..Default::default() }, ..Default::default() },
            Spell { name: "Mass Ward".into(), effect_kind: "buff".into(), threshold: 1, target_count: 2, grants_rule: "Fearless".into(), ..Default::default() },
            // CC-13f: a utility spell is the table's announce + token + manual note: effect-less here (no record), named in the ledger
            Spell { name: "Dread".into(), effect_kind: "utility".into(), threshold: 1, target_count: 1, ..Default::default() },
        ];
        for name in ["Empty Buff", "Zero Mod", "Dread"] {
            let cast = CastInput { spell: name.into(), targets: vec!["a".into()], base: 2, threshold: 1, once: false, ..bolt(0) };
            let (ActStep::Done { state, .. }, asked) = replay(&statics, &st, cast, &[vec![6]]) else { panic!("{name}: expected Done") };
            assert_eq!(asked, ["cast|1x2+|Mystic"], "{name}");
            assert!(state.buffs[0].is_empty(), "{name}: no LiveMod pushed");
            assert_eq!(state.casts[0], 0, "{name}: token paid");
            assert_eq!(state.cast_buffs.len(), 1, "{name}: the delta names the landing (buffs_gained)");
        }
        // Multi-target: "a" and "ah" stand, "b" is dead -> lands on "a" and "ah" only.
        (st.alive[1], st.wounds[1], st.positions[1]) = (1, vec![1], vec![[1.0, 0.0, 0.0]]);
        (st.alive[2], st.wounds[2], st.positions[2]) = (0, Vec::new(), Vec::new());
        let multi = CastInput { spell: "Mass Ward".into(), targets: vec!["a".into(), "b".into(), "ah".into()], base: 2, threshold: 1, once: true, ..bolt(0) };
        let (ActStep::Done { state, .. }, _) = replay(&statics, &st, multi, &[vec![6]]) else { panic!("Mass Ward: expected Done") };
        assert_eq!((state.buffs[0].len(), state.buffs[1].len(), state.buffs[2].len()), (1, 1, 0), "lands on standing targets only");
        assert_eq!((&*state.buffs[0][0].grants_rule, &*state.buffs[1][0].grants_rule), ("Fearless", "Fearless"));
    }

    /// CC-6a hazard 2, CC-13e: a record an earlier cast of the SAME activation would place is not on the board at activation start,
    /// so a following damage cast on that target (or its joined unit) used to be refused at resolution, after the earlier cast's
    /// die. `earlier_record_break` refuses it at its own input before any die, whatever the earlier die shows.
    #[test]
    fn cc13e_damage_cast_after_an_earlier_record_is_refused_before_any_die() {
        use crate::rules::{Spell, SpellModifier};
        let (mut st, mut statics) = bolt_board(2, &[], 6);
        st.casts = vec![4, 0, 0, 0];
        let debuff = Spell { name: "Withering".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, modifier: SpellModifier { present: true, def_mod: -1.0, ..Default::default() }, ..Default::default() };
        let hollow = Spell { name: "Hollow".into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, ..Default::default() };
        statics[0].spells.extend([debuff, hollow]);
        let first = |spell: &str, target: &str| CastInput { seq: 0, spell: spell.into(), targets: vec![target.into()], base: 4, threshold: 1, once: false, ..bolt(0) };
        let run = |c0: CastInput, c1: CastInput, st: &State, faces: Option<u8>| {
            let mut t = vec![Begin, intent(HOLD, None), Input::Cast(c0), Input::Cast(c1)];
            t.extend(faces.map(|f| Faces(vec![f])));
            step_activation(&statics, st, "a", &Terrain::default(), seams(), &t, true)
        };
        let why = "cast 1: Foe meets Test Bolt after cast 0 placed a record on it or its joined unit (the core does not say that for spell damage yet)";
        // The earlier cast would put a debuff on Foe: the damage cast is refused at its input (index 3), no die asked, and the same
        // whatever the earlier die shows (Cast 0 is not even rolled).
        for faces in [None, Some(6), Some(1)] {
            match run(first("Withering", "b"), CastInput { seq: 1, ..test_bolt() }, &st, faces) {
                ActStep::Refused { index: 3, reason } => assert_eq!(reason, why, "faces {faces:?}"),
                other => panic!("faces {faces:?}: expected Cast 1 refused at start, got {other:?}"),
            }
        }
        // Controls: a buff on self (not Foe's chain), an effect-less debuff on Foe (places nothing) and a damage cast first: the earlier die is asked.
        for c0 in [first("Withering", "a"), first("Hollow", "b"), CastInput { seq: 0, ..test_bolt() }] {
            assert!(matches!(run(c0, CastInput { seq: 1, ..test_bolt() }, &st, None), ActStep::NeedRoll { kind: "cast", .. }), "not refused");
        }
        // Joined hero: the debuff lands on host "b", the damage cast targets attached hero "bh": refused too.
        st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
        st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
        (st.alive[3], st.wounds[3], st.positions[3]) = (1, vec![1], vec![[8.0 * INCHES_TO_METERS, 0.0, 0.0]]);
        let hero = CastInput { seq: 1, targets: vec!["bh".into()], ..test_bolt() };
        assert!(matches!(run(first("Withering", "b"), hero, &st, None), ActStep::Refused { index: 3, reason } if reason.starts_with("cast 1: bh meets Test Bolt after cast 0")));
    }

    // ---- CC-9a: NeedChoice carries lines and landings ----

    /// CC-9a: `ActStep::NeedChoice` carries the lines said and landings made BEFORE the choice point, never the
    /// speculative automatic landing's wounds or loss lines. Here "a" stands in Dangerous terrain (1 dies, producing
    /// a prior landing) and shoots mixed-kit "b" with `wound_alloc` probed: `NeedChoice` carries the Dangerous landing
    /// and the volley's pre-allocation lines, and NONE of "b"'s automatic wound/loss lines or landings.
    #[test]
    fn a_need_choice_carries_lines_and_landings_before_the_choice_only() {
        use crate::terrain::{CellParams, PlainTerrain, DANGEROUS};
        let (mut st, statics) = mixed_line();
        st.positions[0] = vec![[4.0 * INCHES_TO_METERS, 0.0, 0.0], [5.0 * INCHES_TO_METERS, 0.0, 0.0]];
        (st.wounds[0], st.alive[0]) = (vec![1, 1], 2);
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS / 2.0; 2];
        let cells = vec![[16.0, 14.0, DANGEROUS as f64], [16.0, 15.0, DANGEROUS as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        let board = Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params, ..Default::default() });
        let mut t = vec![Begin, intent(HOLD, Some("b")), Input::Choice { id: ALLOC_ID.into(), option: String::new() }];
        let mut step_n = 0;
        let ask = loop {
            match step_activation(&statics, &st, "a", &board, Seams { dangerous_end_morale: true, ..seams() }, &t, true) {
                ActStep::NeedRoll { faces, kind, .. } => {
                    step_n += 1;
                    // Roll 1 = Dangerous on "a" ([1, 6] kills 1 of "a" -> prior landing); roll 2 = attack (6s); roll 3 = defense (1s).
                    let g = if step_n == 1 { vec![1, 6] } else if kind == "defense" { vec![1; faces] } else { vec![6; faces] };
                    t.push(Faces(g));
                }
                other => break other,
            }
            assert!(t.len() < 12, "{t:?}");
        };
        let ActStep::NeedChoice { id, lines, landings, .. } = ask else { panic!("expected NeedChoice, got {ask:?}") };
        assert_eq!(id, ALLOC_ID);
        assert!(lines.iter().any(|l| l.text.contains("saves on")), "pre-choice lines must be present: {lines:?}");
        assert!(lines.iter().all(|l| !l.text.contains("b takes ") && !l.text.contains("b loses ")), "speculative automatic landing lines must not leak: {lines:?}");
        assert!(landings.iter().any(|l| l.unit == 0), "prior Dangerous landing on unit 0 must be present: {landings:?}");
        assert!(landings.iter().all(|l| l.unit != 2), "speculative automatic landing on target 2 must not leak: {landings:?}");
    }

    // ---- CC-9b: choices routed by id prefix ----

    /// CC-9b: `step_activation` routes `Input::Choice` by id prefix (`takedown_model:`, `wound_alloc:`, `interference:`);
    /// an unknown prefix is refused with its own sentence (never misrouted to Takedown), and an `interference:` id is
    /// never treated as a Takedown answer. RED before CC-9b: `!id.starts_with(WOUND_ALLOC)` routes both to Takedown.
    #[test]
    fn choices_are_routed_by_prefix_and_unknown_prefixes_are_refused() {
        let (st, statics) = takedown_line();
        let ask = |id: &str, option: &str| {
            let t = [Begin, intent(HOLD, Some("b")), Input::Choice { id: id.into(), option: option.into() }];
            step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true)
        };
        for bad in ["bogus:a:b", "plain_id", "takedown_model"] {
            match ask(bad, "slot:0") {
                ActStep::Refused { index: 2, reason } => {
                    assert!(reason.contains("unknown choice"), "{bad}: {reason}");
                    assert!(reason.contains(bad), "{bad}: {reason}");
                }
                other => panic!("{bad}: expected unknown-prefix Refused, got {other:?}"),
            }
        }
        // An `interference:` probe on a Takedown shooter board is NOT routed to Takedown (never says "the open choice is takedown_model:...").
        let probe = ask("interference:0:a:1", "");
        assert!(!matches!(&probe, ActStep::Refused { reason, .. } if reason.contains("takedown_model")), "must not route interference: to takedown: {probe:?}");
        // A non-integer `interference:` answer is refused as a bad interference option, never routed to Takedown.
        match ask("interference:0:a:1", "slot:0") {
            ActStep::Refused { index: 2, reason } => assert!(reason.contains("token count"), "{reason}"),
            other => panic!("expected interference refusal, got {other:?}"),
        }
        // Takedown + wound_alloc together: Takedown answers cleanly while wound_alloc is also probed.
        let t = [
            Begin,
            intent(HOLD, Some("b")),
            Input::Choice { id: TAKEDOWN_ID.into(), option: "slot:0".into() },
            Input::Choice { id: ALLOC_ID.into(), option: String::new() },
        ];
        assert!(matches!(step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true), ActStep::NeedRoll { index: 0, .. }));
    }

    // ---- CC-9c: cast interference NeedChoice from pools ----

    /// CC-9c: an `open` cast is refused while no interference probe/answer is present; with a probe it opens
    /// `NeedChoice { id: "interference:<seq>:<caster>:<slot>", options: "0".."pool", owner: first_pool_unit, lines, landings }`
    /// carrying the cast's announce and needs lines; answering 1 spends in list order, logs the table's interference line
    /// and raises the target by +1; answering 2 spills to the second payer in list order; answering 0 leaves target and
    /// tokens unchanged (O3); bad / out-of-range options are refused at the Choice's index.
    #[test]
    fn an_open_cast_opens_interference_choice_and_spends_in_list_order_raising_the_target() {
        let (mut st, mut statics) = die_line();
        statics[3].name = "FoeHero".into();
        st.casts = vec![4, 2, 1, 2]; // Mystic=4, Hero=2, Foe=1, FoeHero=2
        let open_cast = CastInput {
            base: 4,
            threshold: 1,
            open: true,
            pools: vec![(1, vec![("b".into(), 1), ("bh".into(), 2)])],
            ..bolt(0)
        };
        let id = "interference:0:a:1";
        let start = vec![Begin, intent(HOLD, None), Input::Cast(open_cast.clone())];

        // 1. Open with no probe/answer -> refused at the cast's index before any roll.
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &start, true) {
            ActStep::Refused { index: 2, reason } => assert_eq!(reason, "cast 0: a foe's answer to Bolt cannot be asked yet"),
            other => panic!("open cast without probe must be refused, got {other:?}"),
        }

        // 2. Probed -> NeedChoice with id carrying seq, options "0".."3", owner "b", pre-choice cast lines.
        let mut probed = start.clone();
        probed.push(Input::Choice { id: id.into(), option: String::new() });
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &probed, true) {
            ActStep::NeedChoice { id: got_id, options, owner, lines, landings } => {
                assert_eq!((got_id.as_str(), owner.as_str()), (id, "b"));
                assert_eq!(options, vec!["0", "1", "2", "3"]);
                assert!(landings.is_empty());
                assert_eq!(
                    lines.iter().map(|l| l.text.as_str()).collect::<Vec<_>>(),
                    ["Mystic casts Bolt at Foe", "Mystic casts Bolt at Foe \u{2014} needs 4+ (1 token)"]
                );
            }
            other => panic!("expected interference NeedChoice, got {other:?}"),
        }

        // 3. Answer "1" -> target 4+ -> 5+, spends 1 from "b" only, logs the interference line, face 4 fails.
        let with_opt = |opt: &str| {
            let mut t = start.clone();
            t.push(Input::Choice { id: id.into(), option: opt.into() });
            t
        };
        let t1 = with_opt("1");
        let ActStep::NeedRoll { kind: "cast", target, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t1, true) else {
            panic!("expected cast die after interference answer 1");
        };
        assert_eq!(target, 5, "1 interference raises 4+ to 5+");
        assert_eq!(
            lines.last().map(|l| l.text.as_str()),
            Some("Interference: Foe \u{00d7}1 spends 1 token \u{2014} the cast roll worsens to 5+ (casters within 18\", no line of sight needed)")
        );
        let (done1, _) = answer_dice(&statics, &st, t1, &[4]);
        let ActStep::Done { state: s1, lines: l1, .. } = done1 else { panic!("face 4 fails 5+, got {done1:?}") };
        assert_eq!(s1.casts, vec![3, 2, 0, 2], "only Foe spent 1 token; FoeHero untouched");
        assert_eq!(l1.last().map(|l| l.text.as_str()), Some("Bolt: cast roll 4 vs 5+ \u{2014} FAILED"));

        // 4. Answer "2" -> spends in list order (1 from Foe, 1 from FoeHero), plural verb "spend", target 6+.
        let t2 = with_opt("2");
        let ActStep::NeedRoll { kind: "cast", target, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t2, true) else {
            panic!("expected cast die after interference answer 2");
        };
        assert_eq!(target, 6, "2 interference raises 4+ to 6+");
        assert_eq!(
            lines.last().map(|l| l.text.as_str()),
            Some("Interference: Foe \u{00d7}1, FoeHero \u{00d7}1 spend 2 tokens \u{2014} the cast roll worsens to 6+ (casters within 18\", no line of sight needed)")
        );
        let (done2, _) = answer_dice(&statics, &st, t2, &[5]);
        let ActStep::Done { state: s2, .. } = done2 else { panic!("face 5 fails 6+, got {done2:?}") };
        assert_eq!(s2.casts, vec![3, 2, 0, 1], "Foe spent 1, FoeHero spent 1");

        // 5. Answer "0" (including O3 no-answer path) -> target stays 4+, no foe tokens spent, no spend line.
        let t0 = with_opt("0");
        let ActStep::NeedRoll { kind: "cast", target, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t0, true) else {
            panic!("expected cast die after interference answer 0");
        };
        assert_eq!(target, 4);
        assert!(lines.iter().all(|l| !l.text.starts_with("Interference:")), "{lines:?}");
        let (done0, _) = answer_dice(&statics, &st, t0, &[1]);
        let ActStep::Done { state: s0, .. } = done0 else { panic!("face 1 fails 4+, got {done0:?}") };
        assert_eq!(s0.casts, vec![3, 2, 1, 2]);

        // 6. Bad / out-of-range options refused at the Choice's index (3).
        for (bad, want) in [("4", "is not an option"), ("-1", "token count"), ("abc", "token count"), ("+1", "token count"), ("01", "token count")] {
            match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &with_opt(bad), true) {
                ActStep::Refused { index: 3, reason } => assert!(reason.contains(want) && reason.contains(bad), "{bad}: {reason}"),
                other => panic!("{bad}: expected Refused at 3, got {other:?}"),
            }
        }
    }

    /// CC-9c: live pool shrinks across casts (`seq` 0 -> `seq` 1), multi-slot pools ask in order (carrying slot 1's
    /// interference line in slot 2's `NeedChoice`), an empty pool logs the table's "no caster of P<slot>" line when
    /// that side holds caster tokens elsewhere, and bad pool keys / unreached answers are refused.
    #[test]
    fn interference_respects_seq_live_tokens_multi_slot_and_empty_pool() {
        let (mut st, mut statics) = die_line();
        statics[2].is_caster = true;
        statics[3].name = "FoeTwo".into();
        st.casts = vec![4, 0, 2, 1];

        // (1) Two open casts in one activation: cast 0 spends 1 of Foe's 2 -> cast 1's pool is live-capped to 1.
        let c0 = CastInput { base: 4, threshold: 1, open: true, pools: vec![(1, vec![("b".into(), 2)])], ..bolt(0) };
        let c1 = CastInput { base: 4, threshold: 1, open: true, pools: vec![(1, vec![("b".into(), 2)])], ..bolt(1) };
        let t = vec![
            Begin,
            intent(HOLD, None),
            Input::Cast(c0),
            Input::Cast(c1),
            Input::Choice { id: "interference:0:a:1".into(), option: "1".into() },
            Input::Choice { id: "interference:1:a:1".into(), option: String::new() },
            Faces(vec![1]), // cast 0 fails 5+
        ];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::NeedChoice { id, options, owner, lines, .. } => {
                assert_eq!((id.as_str(), owner.as_str()), ("interference:1:a:1", "b"));
                assert_eq!(options, vec!["0", "1"], "only 1 token remains after cast 0 spent 1");
                assert!(lines.iter().any(|l| l.text.contains("FAILED")), "cast 0's result line precedes cast 1's choice: {lines:?}");
            }
            other => panic!("expected cast 1 NeedChoice, got {other:?}"),
        }

        // (2) Multi-slot co-op pools: slot 1 then slot 2; slot 2's NeedChoice carries slot 1's interference line.
        st.player[3] = 2;
        let multi = CastInput { base: 4, threshold: 1, open: true, pools: vec![(1, vec![("b".into(), 1)]), (2, vec![("bh".into(), 1)])], ..bolt(0) };
        let t_multi = vec![
            Begin,
            intent(HOLD, None),
            Input::Cast(multi.clone()),
            Input::Choice { id: "interference:0:a:1".into(), option: String::new() },
            Input::Choice { id: "interference:0:a:2".into(), option: String::new() },
        ];
        assert!(matches!(step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t_multi, true), ActStep::NeedChoice { ref id, .. } if id == "interference:0:a:1"));
        let t_slot2 = vec![
            Begin,
            intent(HOLD, None),
            Input::Cast(multi.clone()),
            Input::Choice { id: "interference:0:a:1".into(), option: "1".into() },
            Input::Choice { id: "interference:0:a:2".into(), option: String::new() },
        ];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t_slot2, true) {
            ActStep::NeedChoice { id, options, owner, lines, .. } => {
                assert_eq!((id.as_str(), owner.as_str()), ("interference:0:a:2", "bh"));
                assert_eq!(options, vec!["0", "1"]);
                assert!(lines.iter().any(|l| l.text.starts_with("Interference: Foe")), "{lines:?}");
            }
            other => panic!("expected slot 2 NeedChoice, got {other:?}"),
        }
        let t_both = vec![
            Begin,
            intent(HOLD, None),
            Input::Cast(multi),
            Input::Choice { id: "interference:0:a:1".into(), option: "1".into() },
            Input::Choice { id: "interference:0:a:2".into(), option: "1".into() },
        ];
        assert!(matches!(step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t_both, true), ActStep::NeedRoll { kind: "cast", target: 6, .. }));

        // (3) Empty pool when foe slot 1 has a caster with tokens elsewhere -> logs "no caster of P1", asks cast die directly.
        let empty_pool = CastInput { base: 4, threshold: 1, open: true, pools: vec![(1, vec![])], ..bolt(0) };
        let t_empty = vec![Begin, intent(HOLD, None), Input::Cast(empty_pool), Input::Choice { id: "interference:0:a:1".into(), option: String::new() }];
        let ActStep::NeedRoll { kind: "cast", target: 4, lines, .. } = step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t_empty, true) else {
            panic!("empty pool goes straight to cast die");
        };
        assert!(lines.iter().any(|l| l.text == "Bolt: no caster of P1 within 18\", no line of sight needed \u{2014} no interference"), "{lines:?}");

        // (4) Unknown pool unit key -> refused at the cast's index.
        let bad_pool = CastInput { base: 4, threshold: 1, open: true, pools: vec![(1, vec![("zz".into(), 1)])], ..bolt(0) };
        let t_bad = vec![Begin, intent(HOLD, None), Input::Cast(bad_pool), Input::Choice { id: "interference:0:a:1".into(), option: String::new() }];
        assert!(matches!(step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t_bad, true), ActStep::Refused { index: 2, ref reason } if reason.contains("zz")));

        // (5) Fizzled open cast with an unreached interference answer -> refused on Done; an unreached probe resolves cleanly.
        let mut dead_target = st.clone();
        (dead_target.alive[2], dead_target.positions[2], dead_target.wounds[2]) = (0, Vec::new(), Vec::new());
        let fizz = CastInput { base: 4, threshold: 1, open: true, pools: vec![(1, vec![("bh".into(), 1)])], ..bolt(0) };
        let t_fizz_ans = vec![Begin, intent(HOLD, None), Input::Cast(fizz.clone()), Input::Choice { id: "interference:0:a:1".into(), option: "1".into() }];
        assert!(matches!(step_activation(&statics, &dead_target, "a", &Terrain::default(), seams(), &t_fizz_ans, true), ActStep::Refused { index: 3, ref reason } if reason.contains("no interference choice is open")));
        let t_fizz_probe = vec![Begin, intent(HOLD, None), Input::Cast(fizz), Input::Choice { id: "interference:0:a:1".into(), option: String::new() }];
        assert!(matches!(step_activation(&statics, &dead_target, "a", &Terrain::default(), seams(), &t_fizz_probe, true), ActStep::Done { .. }));
    }

    // ---- step 12: cancel ----

    /// The one cancel sentence (O15 (3)); `side` is the unit's player slot.
    fn cancel_line(name: &str, side: i64) -> LogLine {
        LogLine { rule: "activation_cancel", category: Category::Movement, side, text: format!("{name} cancelled its activation - back at its start."), detail: None }
    }

    /// A cancel before the first die ends the activation with exactly that line and leaves the
    /// state alone, with or without a drag or an intent in front of it (RED: cancel arm deleted ->
    /// `Refused`; cancel arm behind the resolver -> `Open`, `NeedRoll` or the O3 refusal instead).
    #[test]
    fn a_cancel_before_the_first_die_is_cancelled() {
        let (st, statics) = volley_line();
        let moved: Vec<[f64; 3]> = st.positions[0].iter().map(|p| [p[0] + 3.0 * INCHES_TO_METERS, p[1], p[2]]).collect();
        let before = st.clone();
        let ask = |t: &[Input]| step_activation(&statics, &st, "a", &Terrain::default(), seams(), t, true);
        for t in [
            vec![Begin, Cancel],
            vec![Begin, placed(moved.clone()), Cancel],
            vec![Begin, intent(HOLD, Some("b")), Cancel],
            vec![Begin, placed(moved), intent(RUSH, Some("b")), Cancel], // the O3 refusal never shows: nothing was resolved
        ] {
            let ActStep::Cancelled { lines } = ask(&t) else { panic!("{t:?}") };
            assert_eq!(lines, vec![cancel_line("a", 0)], "{t:?}");
        }
        // the other seat's unit: its own name and player slot on the line
        let ActStep::Cancelled { lines } = step_activation(&statics, &st, "b", &Terrain::default(), seams(), &[Begin, Cancel], true) else { panic!("b") };
        assert_eq!(lines, vec![cancel_line("b", 1)]);
        assert_eq!(st, before, "the caller's state is untouched");
    }

    /// After the first die a cancel stays refused with rule 4's sentence.
    #[test]
    fn a_cancel_after_the_first_die_is_refused() {
        let (st, statics) = volley_line();
        let t = [Begin, intent(HOLD, Some("b")), Faces(vec![5, 5, 5, 5]), Cancel];
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (3, "cancel is not possible after the first die")),
            other => panic!("expected rule 4, got {other:?}"),
        }
    }
    /// The delta of a plain Hold+shoot names exactly the models that died: as many as the target
    /// lost, and every survivor is an untouched start position (RED: `removed = 0..n_dead`).
    #[test]
    fn the_delta_names_the_models_that_died_and_nothing_else() {
        let (st, statics) = volley_line();
        let (mut hit, mut first_alive) = (0, 0);
        for seed in 0..200i64 {
            let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            let d = delta_of(&st, &state);
            assert!(d.iter().all(|x| x.key == "b"), "seed {seed}: only the target changes: {d:?}");
            let lost = st.alive[2] - state.alive[2];
            let Some(b) = d.first() else {
                assert_eq!((lost, state.shaken[2]), (0, false), "seed {seed}: a changed target must have a delta");
                continue;
            };
            assert_eq!((b.removed.len() as i64, b.alive, b.shaken, b.moved, b.unknown), (lost, state.alive[2], state.shaken[2], false, false), "seed {seed}");
            for (i, p) in st.positions[2].iter().enumerate() {
                assert_eq!(b.removed.contains(&i), !state.positions[2].contains(p), "seed {seed}: slot {i}");
            }
            assert!(state.positions[2].iter().all(|p| st.positions[2].contains(p)), "seed {seed}: a survivor moved");
            (hit, first_alive) = (hit + (lost > 0) as i32, first_alive + (lost > 0 && b.removed[0] > 0) as i32);
        }
        assert!(hit > 0, "fixture must kill");
        println!("delta fixture: {hit} seeds lost a model, {first_alive} of them not slot 0 first");
    }
    /// The seeded fixture kills slot 0 first on every seed, so slot order proves little there: pin
    /// the other cases by hand (RED: `removed = 0..n_dead` fails the slot-1 case).
    #[test]
    fn the_delta_tells_a_removal_from_a_move() {
        let (st, _) = volley_line();
        let one = |f: &dyn Fn(&mut State)| {
            let mut after = st.clone();
            f(&mut after);
            delta_of(&st, &after)
        };
        let shift = |p: &mut [f64; 3]| p[0] += 3.0 * INCHES_TO_METERS;
        assert_eq!(one(&|_| {}), vec![]);
        for dead in 0..2 {
            let d = one(&|s| (s.positions[2].remove(dead), s.alive[2] -= 1).1);
            assert_eq!(d.len(), 1);
            assert_eq!((d[0].key.as_str(), &d[0].removed[..], d[0].alive, d[0].moved, d[0].unknown), ("b", &[dead][..], 1, false, false));
        }
        let d = one(&|s| s.positions[0].iter_mut().for_each(shift));
        assert_eq!((d[0].key.as_str(), d[0].removed.len(), d[0].moved, d[0].unknown), ("a", 0, true, false));
        let d = one(&|s| (shift(&mut s.positions[2][0]), s.positions[2].remove(1), s.alive[2] -= 1).0);
        assert_eq!((d[0].removed.len(), d[0].moved, d[0].unknown), (0, true, true));
        assert!(one(&|s| s.moved_round[3] += 1)[0].moved);
        assert!(one(&|s| s.shaken[2] = true)[0].shaken);
    }
    /// P4.0-4d: a unit whose ONLY change is the table-owned ledger (fatigue, casts) still gets a row, and
    /// the row carries both values AFTER (RED: drop the ledger term -> no row; drop a field -> the default).
    #[test]
    fn the_delta_carries_the_ledger_a_plain_activation_cannot_change() {
        let (st, _) = volley_line();
        let one = |f: &dyn Fn(&mut State)| {
            let mut after = st.clone();
            f(&mut after);
            delta_of(&st, &after)
        };
        assert_eq!(one(&|_| {}), vec![], "no change, no row");
        let d = one(&|s| {
            s.fatigued[2] = true;
            s.casts[2] = 3;
        });
        assert_eq!(d.len(), 1);
        assert_eq!((d[0].key.as_str(), d[0].fatigued, d[0].casts), ("b", true, 3));
        assert_eq!((d[0].shaken, d[0].moved, d[0].removed.len()), (false, false, 0), "no board news");
    }
    /// P4.0-4e: a unit whose only change is a round stamp gets a row carrying all twelve, AFTER; a core-resolved
    /// volley's rows carry them too (RED: drop the stamp term -> no row; drop a pair -> the count is 11).
    #[test]
    fn the_delta_carries_the_round_stamps() {
        let (st, statics) = volley_line();
        let mut after = st.clone();
        after.spot_round[2] = 4;
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].stamps.len(), 12);
        assert!(d[0].stamps.contains(&("spot_round", 4)));
        assert!(d[0].stamps.contains(&("moved_round", st.moved_round[2])));
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(delta_of(&st, &state).iter().all(|x| x.stamps.len() == 12), "a core row carries the stamps");
    }
    /// HR-POS: a unit whose models moved carries its surviving AFTER positions in slot order (the Hit & Run step the core
    /// takes after a volley), also when it lost models; a unit that only lost models carries none, its losses ride
    /// `removed`. RED: drop the field from the push -> empty, the table's landing has nothing to put the stepped models on.
    #[test]
    fn the_delta_carries_the_stepped_positions() {
        let (st, _) = volley_line();
        let mut after = st.clone();
        for p in after.positions[0].iter_mut() {
            p[0] += 0.0762;
        }
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1, "a step is a change: {d:?}");
        assert!(d[0].moved);
        assert_eq!(d[0].positions, after.positions[0], "the stepped positions ride the row, slot by slot");
        let mut lost = st.clone();
        lost.positions[2].remove(0);
        lost.alive[2] -= 1;
        let d = delta_of(&st, &lost);
        assert_eq!((d.len(), d[0].removed.len()), (1, 1), "{d:?}");
        assert!(d[0].positions.is_empty(), "a loss is no step: {d:?}");
        // Lost a model (a Hazardous self-wound) AND stepped: the survivor's new spot rides, in order.
        let mut both = lost.clone();
        both.positions[2][0][0] += 0.0762;
        let d = delta_of(&st, &both);
        assert!(d[0].moved && d[0].unknown, "{d:?}");
        assert_eq!(d[0].positions, both.positions[2], "the survivors' stepped positions ride the row");
    }
    /// P4.0-4g: a core-resolved Versatile volley carries the latched pick in its delta (the int mode the table's
    /// `versatile_pick` Dictionary is built from). RED: drop `versatile_pick_mode` from the push -> 0, no pick.
    #[test]
    fn a_core_versatile_volley_carries_the_pick_mode() {
        let (st, mut statics) = volley_line();
        statics[0].shoot[0].versatile_attack = true;
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(matches!(state.versatile_pick_mode[0], 1 | 2), "the core picked: {:?}", state.versatile_pick_mode);
        assert_eq!(state.versatile_pick_round[0], state.round);
        assert_eq!(delta_of(&st, &state)[0].versatile_pick_mode, state.versatile_pick_mode[0], "the delta carries the pick");
    }
    /// P4.0-4f: a unit whose only change is a marker pool gets a row carrying all four, AFTER; a core-resolved
    /// volley's rows carry them too (RED: drop the pool term -> no row; drop a pair -> the count is 3).
    #[test]
    fn the_delta_carries_the_marker_pools() {
        let (st, statics) = volley_line();
        let mut after = st.clone();
        after.tag_markers[2] = 2;
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].pools.len(), 4);
        assert!(d[0].pools.contains(&("tag_markers", 2)));
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(delta_of(&st, &state).iter().all(|x| x.pools.len() == 4), "a core row carries the pools");
    }

    /// A unit whose only change is a spent feat gets a row naming the feat; a latch already spent in `before` is no news.
    /// RED: drop the `feats_used` term from the change test -> no row; drop the field from the push -> an empty list.
    #[test]
    fn the_delta_carries_the_spent_feats() {
        let (st, _) = volley_line();
        let mut after = st.clone();
        std::rc::Rc::make_mut(&mut after.feats_used)[2].push("Protection Feat".to_string());
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1, "a spent feat is a change: {d:?}");
        assert_eq!(d[0].feats_used, vec!["Protection Feat".to_string()]);
        assert!(delta_of(&st, &st).is_empty(), "no spend, no row");
        let again = delta_of(&after, &after);
        assert!(again.is_empty(), "a latch that was already spent is no news: {again:?}");
    }

    /// C-12: a unit whose only change is a Piercing-Tag latch gets a row carrying both AFTER: the bearer's
    /// once-per-game `piercing_tag_used` and the target's standing-pool flag `piercing_tag_persistent`.
    /// RED: drop a term from the change test -> no row; drop a field from the push -> the false default.
    #[test]
    fn the_delta_carries_the_piercing_tag_latches() {
        let (st, _) = volley_line();
        let mut after = st.clone();
        after.piercing_tag_used[0] = true;
        after.piercing_tag_persistent[2] = true;
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 2, "each latch is a change: {d:?}");
        assert!(d[0].piercing_tag_used, "the bearer's latch rides its row");
        assert!(!d[0].piercing_tag_persistent);
        assert!(d[1].piercing_tag_persistent, "the standing flag rides the target's row");
        assert!(!d[1].piercing_tag_used);
        assert!(delta_of(&st, &st).is_empty(), "no placement, no row");
        let again = delta_of(&after, &after);
        assert!(again.is_empty(), "a latch already closed is no news: {again:?}");
    }

    /// D19 (a): a unit whose only change is the Surprise Attack latch gets a row carrying it AFTER (`tray_surprise_attack`
    /// stamps the bearer before the candidate search, so a bearer with no target burns it too). RED: drop the change term ->
    /// no row; plant `false` in the push -> the false default.
    #[test]
    fn the_delta_carries_the_surprise_attack_latch() {
        let (st, _) = volley_line();
        let mut after = st.clone();
        after.surprise_attack_used[0] = true;
        let d = delta_of(&st, &after);
        assert_eq!(d.len(), 1, "the latch is a change: {d:?}");
        assert!(d[0].surprise_attack_used, "the burned latch rides its row");
        assert!(delta_of(&st, &st).is_empty(), "no burst, no row");
        let again = delta_of(&after, &after);
        assert!(again.is_empty(), "a latch already closed is no news: {again:?}");
    }

    /// C-11: a unit whose only change is a spent Limited weapon / Storm Attack / Precision latch gets a row naming each; a name
    /// already spent in `before` is no news. RED: drop a term from the change test -> no row; drop a field from the push -> [].
    #[test]
    fn the_delta_carries_the_spent_once_lists() {
        let (st, _) = volley_line();
        for (field, set) in [("limited_used", 0), ("storm_used", 1), ("precision_used", 2)] {
            let mut after = st.clone();
            let list = match set {
                0 => &mut after.limited_used,
                1 => &mut after.storm_used,
                _ => &mut after.precision_used,
            };
            std::rc::Rc::make_mut(list)[2].push("Spent Rule".to_string());
            let d = delta_of(&st, &after);
            assert_eq!(d.len(), 1, "{field}: a spend is a change: {d:?}");
            let named = [&d[0].limited_used, &d[0].storm_used, &d[0].precision_used];
            assert_eq!(named[set], &vec!["Spent Rule".to_string()], "{field}");
            assert_eq!(named.iter().map(|l| l.len()).sum::<usize>(), 1, "{field}: only its own list names it");
            assert!(delta_of(&after, &after).is_empty(), "{field}: already spent is no news");
        }
    }
    /// C-11: a core-resolved volley of a Limited weapon spends it in the core's state and its delta says so (the table path
    /// writes it through `mark_limited_used`, a core door must land it). RED: drop `limited_used` from the push -> [].
    #[test]
    fn a_core_limited_volley_carries_its_spend() {
        let (st, mut statics) = volley_line();
        statics[0].shoot[0].limited = true;
        let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert_eq!(state.limited_used[0], vec!["rifle".to_string()], "the core spent it");
        let d = delta_of(&st, &state);
        assert_eq!(d.iter().find(|x| x.key == "a").map(|x| x.limited_used.clone()), Some(vec!["rifle".to_string()]), "{d:?}");
    }

    /// C-13: a unit whose only change is its Growth marker count gets a row carrying the count AFTER; a core volley that fully
    /// destroys a target spends the kill into the shooter's counter and the row says so (the table's `_solo_growth_on_kill` did not
    /// run on that path). RED: drop the term from the change test -> no row; drop the field from the push -> 0.
    #[test]
    fn the_delta_carries_the_growth_markers() {
        let (st, mut statics) = volley_line();
        let mut after = st.clone();
        after.growth_markers[2] = 3;
        let d = delta_of(&st, &after);
        assert_eq!((d.len(), d[0].growth_markers), (1, 3), "{d:?}");
        assert!(delta_of(&st, &st).is_empty());
        statics[0].growth = vec![crate::unit::GrowthRule { name: "Frenzy".into(), on_kill: true, max_markers: 2, ..Default::default() }];
        let mut st = st;
        (st.wounds[2], statics[2].wounds_max, statics[2].ctx.tough) = (vec![1, 1], vec![1, 1], 1);
        let mut kills = 0;
        for seed in 0..40i64 {
            let (got, _) = drive(&statics, &st, vec![Begin, intent(HOLD, Some("b"))], seed);
            let ActStep::Done { state, .. } = got else { panic!("seed {seed}: {got:?}") };
            if state.alive[2] == 0 {
                kills += 1;
                assert_eq!(state.growth_markers[0], 1, "seed {seed}: the kill banks a marker");
                assert_eq!(delta_of(&st, &state).iter().find(|x| x.key == "a").map(|x| x.growth_markers), Some(1), "seed {seed}");
            }
        }
        assert!(kills > 0, "no seed destroyed the target: the volley proves nothing");
    }

    fn once_buff(name: &str, scope: &str, once: bool) -> LiveMod {
        LiveMod {
            hit_mod: 1, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
            grants_rule: "".into(), scope: scope.into(), attackers: false, once, name: name.into(),
        }
    }
    /// C-15: a unit whose only change is a spent once buff gets a row naming it (name, scope); a buff it still holds, a round buff
    /// and a buff the core ADDED are no spend. A core volley spends the shooter's own once hit mod and says so.
    /// RED: drop the `buffs` term from the change test -> no row; drop the field from the push -> [].
    #[test]
    fn the_delta_carries_the_spent_once_buffs() {
        let (mut st, statics) = volley_line();
        st.buffs[0] = vec![once_buff("Fury", "shooting", true), once_buff("Fury", "shooting", true), once_buff("Round", "", false)];
        let mut after = st.clone();
        after.buffs[0].remove(0);
        let d = delta_of(&st, &after);
        assert_eq!((d.len(), d[0].buffs_spent.clone()), (1, vec![("Fury".to_string(), "shooting".to_string())]), "{d:?}");
        after.buffs[0] = vec![once_buff("Fury", "shooting", true)];
        let d = delta_of(&st, &after);
        assert_eq!(d[0].buffs_spent.len(), 1, "one Fury is spent and one kept; the removed round buff is no spend: {d:?}");
        let mut added = st.clone();
        added.buffs[0].push(once_buff("New", "melee", true));
        assert!(delta_of(&st, &added)[0].buffs_spent.is_empty(), "an addition is not a spend");
        let (got, _) = drive(&statics, &{ let mut s = st.clone(); s.buffs[0] = vec![once_buff("Fury", "shooting", true)]; s }, vec![Begin, intent(HOLD, Some("b"))], 7);
        let ActStep::Done { state, .. } = got else { panic!("seed 7: {got:?}") };
        assert!(state.buffs[0].is_empty(), "the core spent the once hit mod on its volley");
    }

    // ---- step 14: allowance and move check ----

    use crate::state::{Bands, Roster};
    use std::rc::Rc;

    /// `four_unit_line` with its roster indexed; every unit reads the one static "Squad". Unit "a"
    /// is one model at the origin.
    fn squad_line() -> (State, Vec<UnitStatic>) {
        let mut st = crate::sim::tests::four_unit_line();
        let keys = st.roster.keys.clone();
        st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0; 4] });
        (st, vec![UnitStatic { name: "Squad".into(), ..Default::default() }])
    }

    /// Unit "a"'s one model dropped `d` inches east of its start.
    fn east(d: f64) -> Vec<[f64; 3]> {
        vec![[d * INCHES_TO_METERS, 0.0, 0.0]]
    }

    fn check(st: &State, statics: &[UnitStatic], mode: i64, placed: Vec<[f64; 3]>, enforce: bool) -> Check {
        check_move(statics, st, 0, seams(), &Terrain::default(), &Drop { mode, placed, ..Default::default() }, enforce)
    }

    fn refusal(reason: &str) -> Check {
        Check::Refused { reason: reason.to_string() }
    }

    const OK: Check = Check::Ok { lines: Vec::new() };

    #[test]
    fn a_plain_unit_s_allowance_is_its_printed_band() {
        let (st, statics) = squad_line();
        let want = Allowance { advance: 6.0, rush: 12.0, charge: 12.0, widened_by: vec![] };
        assert_eq!(allowance(&statics, &st, 0, seams(), &Terrain::default()), want);
    }

    /// Each model's horizontal straight line against the declared mode's allowance, refused with
    /// the O3 sentence when enforced (RED: drop the distance check -> 6.2" Advance and 12.2" Rush Ok).
    #[test]
    fn an_enforced_move_past_the_allowance_is_refused() {
        let (st, statics) = squad_line();
        let go = |mode, placed| check(&st, &statics, mode, placed, true);
        assert_eq!(go(ADVANCE, east(5.9)), OK);
        assert_eq!(go(ADVANCE, east(6.009)), OK, "inside the 0.01\" float noise");
        assert_eq!(go(ADVANCE, east(6.2)), refusal("Squad: a model moved 6.2\" - the Advance allowance is 6.0\"."));
        assert_eq!(go(RUSH, east(6.2)), OK);
        assert_eq!(go(RUSH, east(12.2)), refusal("Squad: a model moved 12.2\" - the Rush allowance is 12.0\"."));
        assert_eq!(go(CHARGE, east(12.2)), refusal("Squad: a model moved 12.2\" - the Charge allowance is 12.0\"."));
        assert_eq!(go(ADVANCE, vec![[0.0, 9.0 * INCHES_TO_METERS, 0.0]]), OK, "height is not horizontal");
        assert_eq!(go(HOLD, east(1.0)), refusal("movement mode not declared"));
        assert_eq!(go(ADVANCE, vec![]), refusal("placement does not match the unit's models"));
    }

    /// Heightfield plan step 13. A 4 x 4 board of 3 in cells (x, z from -6 to 6 in): the columns at x >= 0 are a 3 in tier, a
    /// ladder joins it in the row z -3..0, the rest of the border at x = 0 is a cliff. Unit "a" starts 2 in west of it.
    fn laddered_start(z_in: f64) -> (State, Vec<UnitStatic>, Terrain) {
        let (mut st, statics) = squad_line();
        st.positions[0] = vec![[-2.0 * INCHES_TO_METERS, 0.0, z_in * INCHES_TO_METERS]];
        let t = crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { 3.0 } else { 0.0 }).collect(), vec![[5, 6]]);
        (st, statics, t)
    }

    fn go_at(st: &State, statics: &[UnitStatic], t: &Terrain, epoch: u32, mode: i64, to: [f64; 3]) -> Check {
        let seams = Seams { rules_epoch: epoch, ..seams() };
        check_move(statics, st, 0, seams, t, &Drop { mode, placed: vec![to], ..Default::default() }, true)
    }

    /// Red before: the check measured the ground only, so a placement up a sheer face was accepted.
    #[test]
    fn a_placed_move_up_a_cliff_is_refused() {
        let (st, statics, t) = laddered_start(1.5);
        let to = [2.0 * INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS];
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, ADVANCE, to), refusal("Squad: cliff: no ladder here"));
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, RUSH, to), refusal("Squad: cliff: no ladder here"), "every mode");
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH - 1, ADVANCE, to), OK, "one epoch below the gate the board is flat");
        // a move that stays on the ground side of the cliff is no crossing
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, ADVANCE, [-4.0 * INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]), OK);
    }

    /// Pins what step 11 already gives: the ladder is a climb, so 4 in of ground + 3 in of ladder is a 7 in move.
    #[test]
    fn a_placed_move_up_a_ladder_pays_3_in() {
        let (st, statics, t) = laddered_start(-1.5);
        let to = [2.0 * INCHES_TO_METERS, 0.0, -1.5 * INCHES_TO_METERS];
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, ADVANCE, to), refusal("Squad: a model moved 7.0\" - the Advance allowance is 6.0\"."));
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, RUSH, to), OK, "the Rush band pays it");
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH - 1, ADVANCE, to), OK, "no climb below the gate: 4 in of ground");
    }

    /// Heightfield plan step 13b (lead call L-3): a drop of up to 3 in is regular movement where the book prints drops (gff,
    /// aofs) and counts its height; the mass-battle books refuse every cliff, and a drop over 3 in or a climb is refused
    /// everywhere. Unit "a" stands on the 3 in tier, 1 in east of the cliff; the row z 0..3 has no ladder.
    #[test]
    fn a_placed_drop_of_3_in_is_regular_movement_in_gff_only() {
        let (mut st, statics, t) = laddered_start(1.5);
        st.positions[0] = vec![[1.0 * INCHES_TO_METERS, 3.0 * INCHES_TO_METERS, 1.5 * INCHES_TO_METERS]];
        let to = |x_in: f64| [x_in * INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS];
        let go = |st: &State, x_in: f64| go_at(st, &statics, &t, EPOCH_94_PARITY_BATCH, ADVANCE, to(x_in));
        assert_eq!(go(&st, -1.0), refusal("Squad: cliff: no ladder here"), "gf: a cliff is impassable both ways");
        Rc::get_mut(&mut st.profiles).expect("owned").list[0].game_system = "gff".into();
        let line = LogLine { rule: "drop", category: Category::Movement, side: 0,
            text: "Squad: Drop 3 in - a drop is regular movement and counts its height".into(), detail: None };
        assert_eq!(go(&st, -1.0), Check::Ok { lines: vec![line] }, "gff: 2 in of ground + the 3 in drop = 5 in, one line");
        assert_eq!(go(&st, -3.5), refusal("Squad: a model moved 7.5\" - the Advance allowance is 6.0\"."), "4.5 in + the 3 in drop pays its height");
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH - 1, ADVANCE, to(-1.0)), OK, "below the gate the board is flat: no drop, no line");
        // the other way is a climb: refused in gff too; a 6 in face is no drop either
        let (up_st, ..) = laddered_start(1.5);
        let mut up_st = up_st;
        Rc::get_mut(&mut up_st.profiles).expect("owned").list[0].game_system = "gff".into();
        assert_eq!(go(&up_st, 2.0), refusal("Squad: cliff: no ladder here"));
        let tall = crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { 6.0 } else { 0.0 }).collect(), Vec::new());
        assert_eq!(go_at(&st, &statics, &tall, EPOCH_94_PARITY_BATCH, ADVANCE, to(-1.0)), refusal("Squad: cliff: no ladder here"), "6 in");
    }

    /// A leg through the grid vertex where the ladder ends and the cliff begins crosses no edge in the segment test; the
    /// level change on the leg still makes it a cliff. A Flying unit goes over.
    #[test]
    fn a_leg_through_a_grid_vertex_is_no_way_up_and_a_flier_ignores_cliffs() {
        let (mut st, mut statics, t) = laddered_start(-1.5);
        st.positions[0] = vec![[-1.5 * INCHES_TO_METERS, 0.0, -1.5 * INCHES_TO_METERS]];
        let to = [1.5 * INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS];
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, ADVANCE, to), refusal("Squad: cliff: no ladder here"), "through (0, 0)");
        statics[0].name = "Flier".into();
        Rc::get_mut(&mut st.profiles).expect("owned").list[0].special_rules = vec!["Flying".into()];
        assert_eq!(go_at(&st, &statics, &t, EPOCH_94_PARITY_BATCH, ADVANCE, to), OK);
    }

    /// Enforce off: the drop stands and exactly one line names the overrun (O3 verbatim).
    #[test]
    fn an_overrun_without_enforce_is_accepted_with_one_line() {
        let (st, statics) = squad_line();
        let text = "Squad: a model moved 6.2\" - the Advance allowance is 6.0\".".to_string();
        let line = LogLine { rule: "move_overrun", category: Category::Movement, side: 0, text, detail: None };
        assert_eq!(check(&st, &statics, ADVANCE, east(6.2), false), Check::Ok { lines: vec![line] });
    }

    /// Fast rides the printed band (8"/16", step 13's fixture), so it names no rule.
    #[test]
    fn a_fast_unit_moves_its_wider_band() {
        let (mut st, statics) = squad_line();
        st.bands[0] = Bands { advance: 8.0, rush: 16.0, charge: None };
        let want = Allowance { advance: 8.0, rush: 16.0, charge: 16.0, widened_by: vec![] };
        assert_eq!(allowance(&statics, &st, 0, seams(), &Terrain::default()), want);
        assert_eq!(check(&st, &statics, ADVANCE, east(7.9), true), OK);
    }

    /// A live Great Musician row (the `ev_move_grants.rs` row with `move_mod` 1) is +1" over the
    /// printed band, and the overrun line names it (RED: read `live_bands_of` -> a buff row is no
    /// grant, the no-grants shortcut answers the printed 6").
    #[test]
    fn a_great_musician_row_widens_the_allowance() {
        let (mut st, statics) = squad_line();
        st.buffs[0].push(crate::mods::LiveMod { hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 1, range_in: 0, grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: false, name: Rc::from("Great Musician") });
        let a = allowance(&statics, &st, 0, seams(), &Terrain::default());
        assert_eq!((a.advance, a.rush, &a.widened_by[..]), (7.0, 13.0, &["Great Musician".to_string()][..]));
        assert_eq!(check(&st, &statics, ADVANCE, east(6.9), true), OK);
        let Check::Ok { lines } = check(&st, &statics, ADVANCE, east(7.2), false) else { panic!("enforce off accepts") };
        assert_eq!(lines.len(), 1);
        assert_eq!((lines[0].text.as_str(), lines[0].detail.as_deref()), ("Squad: a model moved 7.2\" - the Advance allowance is 7.0\".", Some("Great Musician")));
    }

    /// A trail in world XZ metres from inch points.
    fn trail(points: &[[f64; 2]]) -> Vec<[f64; 2]> {
        points.iter().map(|p| [p[0] * INCHES_TO_METERS, p[1] * INCHES_TO_METERS]).collect()
    }

    /// With a trail of 2+ points the check measures the walked path, which must run from the
    /// model's start to its placed position (RED: measure the chord when a trail exists -> the
    /// 4"+4" walk, chord 5.66", turns Ok; skip the start check -> the 1"-off trail, 5.1" long, Ok).
    #[test]
    fn the_check_measures_the_walked_path() {
        let (st, statics) = squad_line();
        let go = |placed: Vec<[f64; 3]>, trails: Vec<Vec<[f64; 2]>>| {
            check_move(&statics, &st, 0, seams(), &Terrain::default(), &Drop { mode: ADVANCE, placed, trails }, true)
        };
        let corner = vec![[4.0 * INCHES_TO_METERS, 0.0, 4.0 * INCHES_TO_METERS]];
        assert_eq!(go(corner.clone(), vec![trail(&[[0.0, 0.0], [4.0, 0.0], [4.0, 4.0]])]), refusal("Squad: a model moved 8.0\" - the Advance allowance is 6.0\"."));
        assert_eq!(go(corner.clone(), vec![]), OK, "no trail: the chord, 5.66\"");
        assert_eq!(go(corner, vec![trail(&[[4.0, 4.0]])]), OK, "one point is no path: the chord");
        assert_eq!(go(east(5.9), vec![trail(&[[0.0, 0.0], [5.9, 0.0]])]), OK);
        assert_eq!(go(east(6.2), vec![]), refusal("Squad: a model moved 6.2\" - the Advance allowance is 6.0\"."));
        let mismatch = refusal("trail does not match the placed model");
        assert_eq!(go(east(5.0), vec![trail(&[[0.0, 1.0], [5.0, 0.0]])]), mismatch, "starts 1\" off the start");
        assert_eq!(go(east(5.0), vec![trail(&[[0.0, 0.0], [4.0, 0.0]])]), mismatch, "ends 1\" short of the placement");
    }

    /// An Ethereal unit the table already placed this activation (`teleport_used`): its trail ends where the walk ended and
    /// the model stands up to 6" further on; the walk is measured, the hop is held to the reach (RED on the old check: the
    /// hop reads "trail does not match the placed model" and the AI's volley is held). Without the latch, past the reach,
    /// or for a plain Teleport off an Advance past its 3" reach, the mismatch still refuses.
    #[test]
    fn a_teleported_model_stands_off_its_trail_end() {
        let (mut st, mut statics) = squad_line();
        let go = |st: &State, statics: &[UnitStatic], mode, placed: Vec<[f64; 3]>| {
            let trails = vec![trail(&[[0.0, 0.0], [4.0, 0.0]])];
            check_move(statics, st, 0, seams(), &Terrain::default(), &Drop { mode, placed, trails }, true)
        };
        let mismatch = refusal("trail does not match the placed model");
        statics[0].teleport = Some(crate::unit::TeleportSpec { name: "Ethereal".into(), standalone_reposition: true });
        assert_eq!(go(&st, &statics, ADVANCE, east(9.0)), mismatch, "no latch: the table did not place it");
        st.teleport_used[0] = true;
        assert_eq!(go(&st, &statics, ADVANCE, east(9.0)), OK, "4\" walked, placed 5\" on");
        assert_eq!(go(&st, &statics, ADVANCE, vec![[4.0 * INCHES_TO_METERS, 0.0, 6.0 * INCHES_TO_METERS]]), OK, "6\" sideways");
        assert_eq!(go(&st, &statics, ADVANCE, east(10.2)), mismatch, "6.2\" past the walk's end");
        statics[0].teleport = Some(crate::unit::TeleportSpec { name: "Teleport".into(), standalone_reposition: false });
        assert_eq!(go(&st, &statics, ADVANCE, east(9.0)), mismatch, "Teleport reaches 3\" off an Advance");
        assert_eq!(go(&st, &statics, RUSH, east(9.0)), OK, "and 6\" off a Rush");
    }

    /// `mv::step`'s climb board: one long container, x 3..6", z -18..18", on a 6x4 ft table; its two
    /// long edges are 2.5" climbs from epoch 73, priced from epoch 74.
    fn container_board() -> Terrain {
        use crate::terrain::{CellParams, Obb, PlainTerrain};
        let e = |ax: f64, az: f64, bx: f64, bz: f64| [[ax * INCHES_TO_METERS, az * INCHES_TO_METERS], [bx * INCHES_TO_METERS, bz * INCHES_TO_METERS]];
        Terrain::build(&PlainTerrain {
            cells: (9..=20).map(|j| [16.0, j as f64, crate::terrain::CONTAINER as f64]).collect(),
            sandbox: Vec::<Obb>::new(),
            pieces: Vec::new(),
            containers: Vec::new(),
            walls: vec![e(3.0, -18.0, 6.0, -18.0), e(6.0, -18.0, 6.0, 18.0), e(6.0, 18.0, 3.0, 18.0), e(3.0, 18.0, 3.0, -18.0)],
            cell_params: CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS },
            ..Default::default()
        })
    }

    /// A trail that walks 4.0" east from the origin climbs onto the container over one edge: 4.0 +
    /// 2.5 = 6.5" (RED: skip the climb sum -> 4.0", Advance Ok; ignore Flying -> the Flying case
    /// refused). Epoch 73 has the ledge but does not price it, as for the AI.
    #[test]
    fn check_pays_the_climb() {
        let (mut st, statics) = squad_line();
        let t = container_board();
        let go = |st: &State, mode, epoch| {
            let drop = Drop { mode, placed: east(4.0), trails: vec![trail(&[[0.0, 0.0], [4.0, 0.0]])] };
            check_move(&statics, st, 0, Seams { rules_epoch: epoch, ..seams() }, &t, &drop, true)
        };
        assert_eq!(go(&st, ADVANCE, 75), refusal("Squad: a model moved 6.5\" - the Advance allowance is 6.0\"."));
        assert_eq!(go(&st, RUSH, 75), OK);
        assert_eq!(go(&st, ADVANCE, 73), OK, "epoch 73: the ledge is not priced");
        let mut p = st.profiles.list[0].clone();
        p.special_rules.push("Flying".into());
        st.profiles = Rc::new(crate::state::Profiles { list: vec![p], index: Default::default() });
        assert_eq!(go(&st, ADVANCE, 75), OK, "Flying climbs nothing");
    }

    /// `sim::tests::forest_bar_board`: a 72" x 48" board with Difficult forest at x 3..6", z -3..3".
    fn forest_bar_board() -> Terrain {
        use crate::terrain::{CellParams, PlainTerrain, FOREST};
        let cells = vec![[16.0, 14.0, FOREST as f64], [16.0, 15.0, FOREST as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params, ..Default::default() })
    }

    /// RUSH: model A's trail clips the forest, so EVERY model is capped at 6" and B's 8" in the open
    /// is refused (RED: cap only the model whose trail crosses -> B's 8" passes; drop the Strider
    /// exemption -> the Strider case refused). A trail that stops short of the forest caps nothing.
    #[test]
    fn check_difficult_caps_every_model() {
        let (mut st, statics) = squad_line();
        st.positions[0] = vec![[0.0; 3], [0.0, 0.0, 6.0 * INCHES_TO_METERS]];
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS; 2];
        let t = forest_bar_board();
        let go = |st: &State, a: f64, b: f64, enforce| {
            let placed = vec![[a * INCHES_TO_METERS, 0.0, 0.0], [b * INCHES_TO_METERS, 0.0, 6.0 * INCHES_TO_METERS]];
            let trails = vec![trail(&[[0.0, 0.0], [a, 0.0]]), trail(&[[0.0, 6.0], [b, 6.0]])];
            check_move(&statics, st, 0, seams(), &t, &Drop { mode: RUSH, placed, trails }, enforce)
        };
        let over = "Squad: a model moved 8.0\" - the Rush allowance is 6.0\" in Difficult terrain.";
        assert_eq!(go(&st, 5.0, 8.0, true), refusal(over));
        assert_eq!(go(&st, 5.9, 5.9, true), OK);
        assert_eq!(go(&st, 1.5, 8.0, true), OK, "A stops short of the forest: no cap");
        let Check::Ok { lines } = go(&st, 5.0, 8.0, false) else { panic!("enforce off accepts") };
        assert_eq!((lines.len(), lines[0].text.as_str(), lines[0].detail.as_deref()), (1, over, Some("Difficult terrain")));
        let mut debuffed = st.clone();
        debuffed.buffs[0].push(crate::mods::LiveMod { hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 0, range_in: 0, grants_rule: Rc::from("Difficult Terrain"), scope: Rc::from(""), attackers: false, once: false, name: Rc::from("Debuff") });
        assert_eq!(go(&debuffed, 1.5, 8.0, true), refusal(over), "the carried debuff caps without forest");
        let mut p = st.profiles.list[0].clone();
        p.special_rules.push("Strider".into());
        st.profiles = Rc::new(crate::state::Profiles { list: vec![p], index: Default::default() });
        assert_eq!(go(&st, 5.0, 8.0, true), OK, "Strider ignores Difficult");
    }

    /// The last `Placed`'s walked paths reach the move check: a 4"+4" walk (chord 5.66") is refused
    /// at that `Placed` (RED: build the check's `Drop` without them -> the chord passes, `Done`).
    #[test]
    fn step_activation_checks_the_last_placement_s_trails() {
        let (st, statics) = squad_line();
        let walk = Input::Placed { at: vec![[4.0 * INCHES_TO_METERS, 0.0, 4.0 * INCHES_TO_METERS]], trails: vec![trail(&[[0.0, 0.0], [4.0, 0.0], [4.0, 4.0]])] };
        match step_activation(&statics, &st, "a", &Terrain::default(), seams(), &[Begin, walk, intent(ADVANCE, None)], true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (1, "Squad: a model moved 8.0\" - the Advance allowance is 6.0\".")),
            other => panic!("expected the walked-path refusal, got {other:?}"),
        }
    }

    /// The activation checks its last placement: an enforced overrun is refused at that `Placed`
    /// (RED: skip the check in `step_activation` -> the moving shot resolves on to the resolver's
    /// `Refused { index: 3, "MovedShootLos" }`, this fixture carries no LOS). Without a shot, enforce
    /// off resolves with the overrun line first, and a move inside the band is the same either way.
    #[test]
    fn step_activation_checks_the_last_placement() {
        let (st, statics) = squad_line();
        let ask = |d: f64, shoot, enforce| step_activation(&statics, &st, "a", &Terrain::default(), seams(), &[Begin, placed(east(d)), intent(ADVANCE, shoot)], enforce);
        match ask(6.2, Some("b"), true) {
            ActStep::Refused { index, reason } => assert_eq!((index, reason.as_str()), (1, "Squad: a model moved 6.2\" - the Advance allowance is 6.0\".")),
            other => panic!("expected the overrun refusal, got {other:?}"),
        }
        let r = ask(6.2, None, false);
        let ActStep::Done { lines, .. } = r else { panic!("enforce off resolves: {r:?}") };
        assert_eq!(lines.iter().filter(|l| l.rule == "move_overrun").count(), 1);
        assert_eq!(lines[0].rule, "move_overrun");
        let (ActStep::Done { state: a, lines: la, .. }, ActStep::Done { state: b, lines: lb, .. }) = (ask(5.9, None, true), ask(5.9, None, false)) else { panic!("5.9\" resolves") };
        assert!(la.iter().all(|l| l.rule != "move_overrun"));
        assert_eq!((a, la), (b, lb));
    }

    /// R2: "a" and "b" both named "Riflemen" (a mirror match). "a" stands in Dangerous terrain (x 3..6") with two
    /// one-wound models, holds and shoots "b"; its test kills one, so after "b"'s saves and morale the activation ends
    /// with "a"'s OWN morale test. Every roll names its unit by roster key (RED: the first unit carrying the name ->
    /// "a" owns "b"'s dice; morale and saves by kind to the target -> "b" owns "a"'s last die; no replay -> "").
    #[test]
    fn every_roll_names_its_unit_by_key_when_two_units_share_a_name() {
        use crate::terrain::{CellParams, PlainTerrain, DANGEROUS};
        let (mut st, mut statics) = volley_line();
        (statics[0].name, statics[2].name) = ("Riflemen".into(), "Riflemen".into());
        st.positions[0] = vec![[4.0 * INCHES_TO_METERS, 0.0, 0.0], [5.0 * INCHES_TO_METERS, 0.0, 0.0]];
        (st.wounds[0], st.alive[0]) = (vec![1, 1], 2);
        Rc::make_mut(&mut st.radii)[0] = vec![INCHES_TO_METERS / 2.0; 2];
        let cells = vec![[16.0, 14.0, DANGEROUS as f64], [16.0, 15.0, DANGEROUS as f64]];
        let cell_params = CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: INCHES_TO_METERS };
        let board = Terrain::build(&PlainTerrain { cells, sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![], cell_params, ..Default::default() });
        let seams = Seams { dangerous_end_morale: true, ..seams() };
        let (mut t, mut asked) = (vec![Begin, intent(HOLD, Some("b"))], Vec::new());
        while let ActStep::NeedRoll { faces, kind, owner, owner_key, .. } = step_activation(&statics, &st, "a", &board, seams, &t, true) {
            assert_eq!(owner, "Riflemen", "the label stays the name");
            asked.push((kind, owner_key));
            // the Dangerous test kills one of "a", every hit lands, every save fails, both morale tests pass
            t.push(Faces(match asked.len() { 1 => vec![1, 6], 3 => vec![1; faces], _ => vec![6; faces] }));
            assert!(asked.len() < 8, "{asked:?}");
        }
        let want = [("dangerous", "a"), ("attack", "a"), ("defense", "b"), ("morale", "b"), ("morale", "a")];
        assert_eq!(asked, want.map(|(k, o)| (k, o.to_string())));
    }

    /// P4.0-9: the same duplicate name without the Dangerous detour. Two units are both "Riflemen"; "a" holds and
    /// shoots "b". Every asked roll names its owner by roster key per step: the attack die is the shooter's ("a"), the
    /// saves and the morale die the target's ("b"). The step answers from the draw's stamped unit, never a second
    /// resolve — the keys pin both readings. (RED: name-only owner gives "a" for the saves; first named unit too.)
    #[test]
    fn a_duplicate_name_keeps_the_attack_with_the_shooter_and_the_saves_with_the_target() {
        let (st, mut statics) = volley_line();
        (statics[0].name, statics[2].name) = ("Riflemen".into(), "Riflemen".into());
        let (mut t, mut asked) = (vec![Begin, intent(HOLD, Some("b"))], Vec::new());
        while let ActStep::NeedRoll { faces, kind, owner, owner_key, .. } =
            step_activation(&statics, &st, "a", &Terrain::default(), seams(), &t, true)
        {
            assert_eq!(owner, "Riflemen", "the label stays the name");
            asked.push((kind, owner_key));
            t.push(Faces(match kind { "attack" => vec![6; faces], "defense" => vec![1; faces], _ => vec![6; faces] }));
            assert!(asked.len() < 8, "{asked:?}");
        }
        let want = [("attack", "a"), ("defense", "b"), ("morale", "b")];
        assert_eq!(asked, want.map(|(k, o)| (k, o.to_string())));
    }

    /// R3: a model that moved without a 2+ point trail is checked as its straight segment [start, end]: a trail-less
    /// (or one-point) 4" drop onto the container pays the 2.5" climb (6.5" > the 6" Advance), and a trail-less 8" Rush
    /// across the forest strip is capped at 6" (RED: the bare chord, 4.0" and no crossing -> both accepted). Open ground
    /// and a model that stayed are unchanged.
    #[test]
    fn a_trailless_drop_is_checked_along_its_straight_line() {
        let (st, statics) = squad_line();
        let go = |t: &Terrain, mode, placed, trails| check_move(&statics, &st, 0, seams(), t, &Drop { mode, placed, trails }, true);
        let climb = refusal("Squad: a model moved 6.5\" - the Advance allowance is 6.0\".");
        assert_eq!(go(&container_board(), ADVANCE, east(4.0), vec![]), climb);
        assert_eq!(go(&container_board(), ADVANCE, east(4.0), vec![trail(&[[0.0, 0.0]])]), climb, "one point is no trail");
        assert_eq!(go(&forest_bar_board(), RUSH, east(8.0), vec![]), refusal("Squad: a model moved 8.0\" - the Rush allowance is 6.0\" in Difficult terrain."));
        assert_eq!(go(&Terrain::default(), ADVANCE, east(5.9), vec![]), OK, "open ground: the straight line");
        assert_eq!(go(&forest_bar_board(), RUSH, east(0.05), vec![]), OK, "a model that stayed crosses nothing");
    }
}

#[cfg(test)]
#[path = "tests/activation_skirmish_vertical.rs"]
mod skirmish_vertical_tests;

#[cfg(test)]
#[path = "tests/activation_blast_choice.rs"]
mod blast_choice_tests;

#[cfg(test)]
#[path = "tests/activation_push_choice.rs"]
mod push_choice_tests;

#[cfg(test)]
mod ruin_ledge_tests {
    use super::*;
    use crate::terrain::{CellParams, Obb, PlainTerrain, Slab, TierGrid};
    const I: f64 = crate::IN2M;

    /// A 2 x 1 board of 3 in cells, board-centred: cell 0 (x in -3..0 in) and cell 1 (0..3 in). `tier` raises cell 0 to
    /// `h`; else cell 0 carries a free ruin's floor `h` up.
    fn board(h: f64, tier: bool) -> Terrain {
        let slab = Slab { c: [-1.5 * I, 0.0], he: [1.5 * I, 1.5 * I], yaw: 0.0, y0: h * I - 0.01, y1: h * I };
        Terrain::build(&PlainTerrain {
            cell_params: CellParams { table_size_feet: [0.5, 0.25], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: I },
            tiers: Some(TierGrid { nx: 2, nz: 1, cell_in: 3.0, level_in: if tier { vec![h, 0.0] } else { vec![0.0, 0.0] }, ladders: vec![], stairs: vec![] }),
            sandbox: if tier { vec![] } else { vec![Obb { c: slab.c, he: slab.he, yaw: 0.0, kind: 0, slabs: vec![slab] }] },
            ..Default::default()
        })
    }

    /// What `cliff_drop_in` makes of a skirmish walk from cell 0 to cell 1: the height dropped as movement, and each jump's
    /// (height, dice) - `None` when it refuses.
    fn walk(t: &Terrain, h: f64, floor: bool) -> Option<(f64, Vec<(f64, u32)>)> {
        cliff_drop_in(t, &[[-1.5 * I, 0.0], [1.5 * I, 0.0]], true, true, floor.then_some(h * I))
            .map(|(d, j)| ((d * 1000.0).round() / 1000.0, j.iter().map(|x| ((x.dy * 1000.0).round() / 1000.0, x.dice)).collect()))
    }

    /// Lead 26.11.: no restated thresholds - the same drop off a tier cliff and off a ruin floor ends the same way at
    /// 3.5, 4, 6 and 6.5 in (and at 2 in, a plain drop), because both are edges of one walk.
    #[test]
    fn a_ruin_floor_drops_like_a_tier_cliff() {
        for h in [2.0, 3.5, 4.0, 6.0, 6.5] {
            assert_eq!(walk(&board(h, false), h, true), walk(&board(h, true), h, false), "{h} in");
        }
        assert!(walk(&board(6.5, true), 6.5, false).is_none(), "over 6 in: refused on both");
        assert_eq!(walk(&board(4.0, true), 4.0, false).map(|w| w.1.len()), Some(1), "4 in: a jump on both");
    }

    /// The old leg: below `PENDING_EPOCH_RUIN_LEDGES` the walker's height is not read, so a ruin floor is no ledge (as every
    /// record before it played); from it, it is.
    #[test]
    fn ruin_ledges_ride_their_epoch() {
        let e = crate::acts::PENDING_EPOCH_RUIN_LEDGES;
        assert!(!rule_on(crate::acts::CURRENT_RULES_EPOCH, e), "a placeholder no record has played");
        let seams = |epoch: u32| Seams { rules_epoch: epoch, ..Seams::default() };
        assert_eq!(ruin_floor_y(seams(e - 1), &[0.0, 0.1, 0.0]), None);
        assert_eq!(ruin_floor_y(seams(e), &[0.0, 0.1, 0.0]), Some(0.1));
        let t = board(4.0, false);
        let path = [[-1.5 * I, 0.0], [1.5 * I, 0.0]];
        assert_eq!(cliff_drop_in(&t, &path, true, true, ruin_floor_y(seams(e - 1), &[0.0, 4.0 * I, 0.0])).map(|r| r.1.len()), Some(0));
        assert_eq!(cliff_drop_in(&t, &path, true, true, ruin_floor_y(seams(e), &[0.0, 4.0 * I, 0.0])).map(|r| r.1.len()), Some(1));
    }
}

#[cfg(test)]
mod ruin_floor_geometry_tests {
    use super::*;
    use crate::terrain::{CellParams, Obb, PlainTerrain, Slab};

    /// The three-storey sandbox ruin as the table hands it (`ruin_large_3f` at the origin, read off a real e2e): two 3 in
    /// arms and two 6 in arms, heights as float32 metres.
    fn ruin() -> Terrain {
        let s = |c: [f64; 2], he: [f64; 2], y0: f64, y1: f64| Slab { c, he, yaw: 0.0, y0, y1 };
        let (lo, hi) = (f64::from(0.0762f32), f64::from(0.1524f32));
        let slabs = vec![s([-0.0381, -0.04445], [0.0762, 0.03175], lo - 0.01, lo), s([-0.08255, -0.0254], [0.03175, 0.0508], lo - 0.01, lo),
            s([-0.075438, -0.04445], [0.038862, 0.03175], hi - 0.01, hi), s([-0.08255, -0.050292], [0.03175, 0.025908], hi - 0.01, hi)];
        Terrain::build(&PlainTerrain {
            cell_params: CellParams { table_size_feet: [4.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 1.0, inches_to_meters: crate::IN2M },
            sandbox: vec![Obb { c: [0.0, 0.0], he: [0.1143, 0.0762], yaw: 0.0, kind: 1, slabs }],
            ..Default::default()
        })
    }

    /// Off the top floor over the 3 in floor: two plain 3 in drops (float32 puts the first at 3.00000014 in - still the
    /// 3 in drop, not a cliff); off the top floor's other side straight to the ground: one 6 in jump.
    #[test]
    fn a_real_ruin_steps_down_floor_by_floor_or_jumps_to_the_ground() {
        let (t, hi) = (ruin(), f64::from(0.1524f32));
        let down = |to: [f64; 2]| cliff_drop_in(&t, &[[-0.075438, -0.04445], to], true, true, Some(hi))
            .map(|(d, j)| ((d * 1000.0).round() / 1000.0, j.len()));
        assert_eq!(down([-0.075438, 0.0635]), Some((6.0, 0)), "two plain drops, 3 in each");
        assert_eq!(down([-0.075438, -0.1270]), Some((0.0, 1)), "one 6 in jump");
    }
}

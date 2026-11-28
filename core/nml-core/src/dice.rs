//! NML-1073 M5 D1-B3 — the table's DICE TRAY as a pure stream.
//!
//! The shipped game rolls every combat die through `_solo_tray_roll`
//! (main.gd:7126-7180). In batch mode — the only reproducible one
//! (arena_match.gd:253) — that is exactly this, main.gd:7152-7159:
//!
//! ```text
//! for _di in maxi(1, count):
//!     _inst.append(_tray_rng.randi_range(1, 6))
//! ```
//!
//! TWO things a naive port gets wrong, both pinned by the tests below:
//!
//!   1. `maxi(1, count)` — a ZERO-die roll STILL BURNS ONE DRAW. Skip it and
//!      the whole stream shifts from the first empty volley onward, and every
//!      activation after it is a different game.
//!   2. The tray has its OWN generator. `seed_tray_rng` (main.gd:7120-7121) is
//!      a plain `_tray_rng.seed = seed_value`, i.e. `GodotRng::new(seed)`, and
//!      the arena hands it `_dice_seed` AFTER deployment (arena_match.gd:478),
//!      where `_dice_seed` defaults to the game seed (arena_match.gd:984-985).
//!      Deployment and the roll-off draw from OTHER generators — see the
//!      stream split in `selfplay.py`.
//!
//! Nothing here is new randomness: `GodotRng` is the fixture-proven Godot 4.6
//! `RandomPCG` twin (GATE R, 6003/6003), and a tray face is one
//! `randi_range(1, 6)` on it.

use crate::activation::{CastInput, ConsolidatePlan};
#[cfg(test)]
use crate::combat::modified_hit_target;
use crate::acts::{rule_on, EPOCH_73_V36};
use crate::combat::{
    cond_ap_why, cond_met, conditional_ap_bonus, conditional_ap_bonus_vs, covered_defense, deadly_multiplier, fortified_ap, guarded_defense, hit_ev, CondApTarget,
    impact_total_dice, melee_hit_modifier, fold_hit, reliable_quality, save_target,
    shielded_defense, morale_target, shooting_hit_modifier, shrouded_reach, thrust_to_hit,
    versatile_best_mode, BEST_HIT_TARGET, FEARLESS_RECOVER_TARGET, HEAVY_IMPACT_AP,
    IMPACT_HIT_TARGET, LONG_RANGE_IN, NO_RETREAT_SELF_WOUND_MAX, RAVAGE_WOUND_TARGET,
    RENDING_AP_BONUS, THRUST_AP_BONUS, UNMODIFIED_SIX,
};
use crate::landing::Landing;
use crate::logline::{Category, LogLine};
use crate::rng::GodotRng;
use crate::unit::{CondAp, Ctx, ShieldedAlias, ShootProfile};

/// One entry of the strike's pass-1 hit list (`resolve_melee_leg`'s `pending`).
type Pending<'a> = (&'a Shooter<'a>, &'a ShootProfile, Vec<u8>, i64, i64, i64, bool, i64);

/// One dice tray: the generator `seed_tray_rng` seeds, and nothing else.
#[derive(Debug, Clone)]
pub struct Tray {
    rng: GodotRng,
    /// One-core Phase 0 (`step.rs`): faces supplied from outside, one group per
    /// roll in draw order. `None` (every existing construction site) = the seeded
    /// stream; `Some` = the stream is never touched.
    feed: Option<Feed>,
    /// NML-1100, `EPOCH_67_MARKERS_BURSTS`: false (the default, every existing
    /// construction site) keeps the pre-batch-D `maxi(1, count)` burn. Set
    /// per-resolve by `resolve_stochastic_tray_on_board` (the sole production
    /// site a real `Tray` reaches a `.roll()` from) via `set_zero_draws`, off
    /// the RECORD's own `seams.rules_epoch` — never baked into construction,
    /// since one long-lived `Tray` replays acts stamped at different epochs.
    zero_draws: bool,
    /// One-core P3: `say` lines, each stamped with the feed's draws so far.
    lines: Vec<(usize, LogLine)>,
    /// One-core P3: `land` landings, each stamped with the feed's draws so far.
    landings: Vec<(usize, Landing)>,
    /// The index of a morale outcome line the wounds of the SAME test are still to be reported ahead of: No Retreat's
    /// self-wounds land (and say so) before the table writes "passes morale". Set by `hold_outcome`, spent by `say_wounds`.
    outcome_at: Option<usize>,
    /// The name the table calls the volley's target by when it is not the unit the dice resolve against: a lone hero's host
    /// ("X fires W at <host>"). Set by the volley around its resolve, `None` otherwise.
    aimed: Option<String>,
    /// meleefix: the planner's consolidation inputs (`Tray::offer_consolidation`); empty = the core's own goal.
    consolidate: Vec<ConsolidatePlan>,
    /// The skirmish Pushing rule: the attacker's push offer (`Tray::offer_push`); `None` = no push.
    push: Option<crate::activation::PushInput>,
}

impl Tray {
    /// Names the target the next lines call it by (`None` = the unit itself).
    pub fn aim(&mut self, name: Option<String>) {
        self.aimed = name;
    }

    /// `main.seed_tray_rng(dice_seed)` — `RandomNumberGenerator.seed = seed`.
    ///
    /// The seed is `i64`, not `u64`, because that is what GDScript hands the
    /// engine and what `GodotRng::new` mirrors; a negative seed must land on
    /// the same stream on both sides.
    pub fn seeded(seed: i64) -> Tray {
        Tray { rng: GodotRng::new(seed), feed: None, zero_draws: false, lines: Vec::new(), landings: Vec::new(), outcome_at: None, aimed: None, consolidate: Vec::new(), push: None }
    }

    /// A tray that continues a generator already in flight — how a replay
    /// reaches a recorded position in the stream.
    pub fn from_rng(rng: GodotRng) -> Tray {
        Tray { rng, feed: None, zero_draws: false, lines: Vec::new(), landings: Vec::new(), outcome_at: None, aimed: None, consolidate: Vec::new(), push: None }
    }

    /// Re-seeds in place, as a second `seed_tray_rng` call would.
    pub fn seed(&mut self, seed: i64) {
        self.rng.seed(seed);
    }

    /// NML-1100: `on` = a `count == 0` roll draws NOTHING and burns no stream
    /// position, the table's own rules-path reading (the tray WIDGET keeps
    /// its own display-only `maxi(1, …)`, untouched — main.gd:7951). `off` (the
    /// default) keeps the old UI-guard-leaked-into-the-rules-path burn.
    pub fn set_zero_draws(&mut self, on: bool) {
        self.zero_draws = on;
    }

    /// One roll: `maxi(1, count)` faces of `randi_range(1, 6)`, in draw order
    /// — or, from `EPOCH_67_MARKERS_BURSTS` (`zero_draws`), exactly `count`
    /// faces, so a `count == 0` roll draws nothing. Below the gate `count ==
    /// 0` still returns ONE face — the die the table burns and reads as
    /// nothing; callers that asked for zero dice must ignore the value, not
    /// the draw.
    pub fn roll(&mut self, count: usize) -> Vec<u8> {
        let n = if self.zero_draws { count } else { count.max(1) };
        if let Some(feed) = self.feed.as_mut() {
            return feed.take(n);
        }
        (0..n).map(|_| self.rng.randi_range(1, 6) as u8).collect()
    }

    /// One-core Phase 0: a tray that serves `groups` (one per roll, draw order)
    /// instead of drawing. Past the last group it serves 1s and records where it
    /// first ran dry (`starved_at`) — the step API turns that into `NeedRoll`.
    pub fn supplied(groups: Vec<Vec<u8>>) -> Tray {
        let feed = Feed { groups, next: 0, starved_at: None, mismatch: None, placed: None, placed_trails: None, kinds: Vec::new(), owners: Vec::new(), wound_choices: Vec::new(), interference_choices: Vec::new(), strike_back_choices: Vec::new(), blast_choices: Vec::new(), free_choices: Vec::new(), blast_at: None, choice_seq: 0, casts: Vec::new(), cast_refused: None, paid: (false, false), no_step: false };
        Tray { rng: GodotRng::new(0), feed: Some(feed), zero_draws: false, lines: Vec::new(), landings: Vec::new(), outcome_at: None, aimed: None, consolidate: Vec::new(), push: None }
    }

    /// The supplied feed, if this tray has one.
    pub fn feed(&self) -> Option<&Feed> {
        self.feed.as_ref()
    }

    /// One-core P3: the player's own per-model end positions for this step's
    /// ADVANCE/RUSH and each model's walked path (world XZ metres, may be empty).
    /// Only a supplied tray keeps them; a seeded tray ignores the call.
    pub fn place(&mut self, p: Vec<[f64; 3]>, trails: Vec<Vec<[f64; 2]>>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.placed = Some(p);
            feed.placed_trails = Some(trails);
        }
    }

    /// D-PAR3 14a: the table already resolved this activation's start triggers / its pre-attack phase (`Input::Paid`). Only a
    /// supplied tray keeps them; a seeded tray ignores the call.
    pub fn pay(&mut self, start: bool, beats: bool) {
        if let Some(feed) = self.feed.as_mut() {
            feed.paid = (start, beats);
        }
    }

    /// Step 20: the intent's `no_step` - the core takes no Hit & Run step after the attack (a human player drags it). Only a supplied
    /// tray keeps it; a seeded tray ignores the call.
    pub fn hold_step(&mut self, no_step: bool) {
        if let Some(feed) = self.feed.as_mut() {
            feed.no_step = no_step;
        }
    }

    /// Step 20: whether the intent asked for no Hit & Run step (`false` on every seeded tray).
    pub fn no_step(&self) -> bool {
        self.feed.as_ref().is_some_and(|f| f.no_step)
    }

    /// D-PAR3 14a: whether the table already resolved the start triggers (`false` on every seeded tray).
    pub fn paid_start(&self) -> bool {
        self.feed.as_ref().is_some_and(|f| f.paid.0)
    }

    /// D-PAR3 14b: whether the table already resolved the pre-attack phase (`false` on every seeded tray).
    pub fn paid_beats(&self) -> bool {
        self.feed.as_ref().is_some_and(|f| f.paid.1)
    }

    /// The supplied placement's walked paths, if any (`None` on every seeded tray).
    pub fn placed_trails(&self) -> Option<&[Vec<[f64; 2]>]> {
        self.feed.as_ref().and_then(|f| f.placed_trails.as_deref())
    }

    /// One-core P3: the table's own `roll_kind` for the NEXT draw where its roll record keeps the replay gates'
    /// "attack" (the morale die): a supplied tray keeps it for `NeedRoll`; a seeded tray ignores the call.
    pub fn name_next(&mut self, kind: &'static str) {
        if let Some(feed) = self.feed.as_mut() {
            feed.kinds.push((feed.next, kind));
        }
    }

    /// CC-8a: re-tag morale draws taken since `from` as spell-leg morale rolls (`morale` -> `spell_morale`,
    /// `fearless` -> `spell_fearless`, `no_retreat` -> `spell_no_retreat`). Seeded trays ignore the call.
    pub fn tag_spell_morale(&mut self, from: usize) {
        let Some(feed) = self.feed.as_mut() else { return };
        for (at, k) in &mut feed.kinds {
            if *at >= from {
                *k = match *k {
                    "morale" => "spell_morale",
                    "fearless" => "spell_fearless",
                    "no_retreat" => "spell_no_retreat",
                    other => other,
                };
            }
        }
    }

    /// Coverage ledger: a damage spell's wound-ignore dice stay the cast leg's plain `spell_attack` (the door maps it to the tray kind attack,
    /// leg spell; `CAST_KINDS` has no `spell_regeneration`), so the `regeneration` name `roll_ignore_group` gave the draws taken since `from` is
    /// taken back. Seeded trays ignore the call.
    pub fn tag_spell_regeneration(&mut self, from: usize) {
        let Some(feed) = self.feed.as_mut() else { return };
        for (at, k) in &mut feed.kinds {
            if *at >= from && *k == "regeneration" {
                *k = "spell_attack";
            }
        }
    }

    /// One-core P4 step 4.0-9: the unit a resolver is about to draw for, stamped for the next draw. A supplied tray keeps
    /// it for `NeedRoll`'s `owner_key` (no second resolve); a seeded tray ignores the call.
    pub fn owner_next(&mut self, unit: Option<usize>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.owners.push((feed.next, unit));
        }
    }

    /// The transcript names a wound-allocation choice `id` (answered when `answer` is `Some`); one per
    /// target group. A supplied tray keeps it; a seeded tray ignores the call, so every seeded path lands automatically as before.
    pub fn offer_wound_alloc(&mut self, id: String, answer: Option<Vec<usize>>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.wound_choices.push(WoundChoice { id, answer, reached: None, bad: None, lines: Vec::new(), landings: Vec::new(), order: 0 });
        }
    }

    /// A group's pool landing reaches choice `id` with the target's living capture slots `options`.
    /// `Some(slots)` = the owner's valid answer, to land first; `None` = automatic (nothing offered for this id, an
    /// unanswered ask, or an answer with a slot outside `options`, kept as `bad`). The step API reads `reached`.
    pub fn wound_alloc(&mut self, id: &str, options: Vec<usize>, owner: &str) -> Option<Vec<usize>> {
        let feed = self.feed.as_mut()?;
        let c = feed.wound_choices.iter_mut().find(|c| c.id == id)?;
        c.reached = Some((feed.next, options.clone(), owner.to_string()));
        c.order = feed.choice_seq;
        feed.choice_seq += 1;
        c.bad = c.answer.as_ref().and_then(|a| a.iter().find(|s| !options.contains(s)).copied());
        if c.answer.is_none() {
            c.lines = self.lines.iter().map(|(_, l)| l.clone()).collect();
            c.landings = self.landings.iter().map(|(_, l)| l.clone()).collect();
        }
        c.answer.clone().filter(|_| c.bad.is_none())
    }

    /// CC-9c: the transcript names an interference choice `id` (`interference:<seq>:<caster>:<slot>`, answered when
    /// `answer` is `Some`). A supplied tray keeps it; a seeded tray ignores the call.
    pub fn offer_interference(&mut self, id: String, answer: Option<i64>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.interference_choices.push(InterferenceChoice { id, answer, reached: None, bad: None, lines: Vec::new(), landings: Vec::new(), order: 0 });
        }
    }

    /// CC-9c: `tray_cast` reaches interference choice `id` for a foe slot with `pool` available tokens and `owner`
    /// (first pool unit's roster key). `Some(n)` = valid token spend `0..=pool`; `None` = unanswered ask or out-of-range
    /// answer (kept in `bad`). Captures pre-choice lines and landings when unanswered.
    pub fn interference(&mut self, id: &str, pool: i64, owner: &str) -> Option<i64> {
        let feed = self.feed.as_mut()?;
        let c = feed.interference_choices.iter_mut().find(|c| c.id == id)?;
        c.reached = Some((feed.next, pool, owner.to_string()));
        c.order = feed.choice_seq;
        feed.choice_seq += 1;
        c.bad = c.answer.filter(|&n| n < 0 || n > pool);
        if c.answer.is_none() {
            c.lines = self.lines.iter().map(|(_, l)| l.clone()).collect();
            c.landings = self.landings.iter().map(|(_, l)| l.clone()).collect();
        }
        c.answer.filter(|_| c.bad.is_none())
    }

    /// E-24: the transcript names the strike-back choice `id` (`strike_back:<charger>:<defender>`; `Some(true)` = strike,
    /// `Some(false)` = hold, `None` = only asked). A supplied tray keeps it; a seeded tray ignores the call.
    pub fn offer_strike_back(&mut self, id: String, answer: Option<bool>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.strike_back_choices.push(StrikeBackChoice { id, answer, reached: None, lines: Vec::new(), landings: Vec::new(), order: 0 });
        }
    }

    /// E-24: the melee reaches the defender's strike-back choice `id` (owner = the defender's roster key). `Some` = the
    /// owner's answer; `None` = nothing offered or only asked (the core strikes back, the AI's rule). Captures the lines and
    /// landings before the choice when unanswered.
    pub fn strike_back(&mut self, id: &str, owner: &str) -> Option<bool> {
        self.reach_two_way(|c| c.id == id, owner)
    }

    /// Step 22a: the volley reaches the activation's Versatile mode pick (`versatile_mode:<unit>`, owner = that unit). `Some(true)` =
    /// AP(+1), `Some(false)` = +1 to hit; `None` = nothing offered or only asked (the core's own best mode, the AI's rule).
    pub fn versatile_mode(&mut self) -> Option<bool> {
        let owner = self.feed.as_ref()?.strike_back_choices.iter().find(|c| c.id.starts_with("versatile_mode:"))?.id["versatile_mode:".len()..].to_string();
        self.reach_two_way(|c| c.id.starts_with("versatile_mode:"), &owner)
    }

    /// Step 29b: the transcript names the Blast split choice `id` (`blast_split:<shooter>:<target>`; `Some(keys)` = the units
    /// that take the remainder hits, `None` = only asked). A supplied tray keeps it; a seeded tray ignores the call.
    pub fn offer_blast_split(&mut self, id: String, answer: Option<Vec<String>>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.blast_choices.push(BlastChoice { id, answer, reached: None, bad: false, lines: Vec::new(), landings: Vec::new(), order: 0 });
        }
    }

    /// Step 29d: the transcript names a free-answer choice `id` (`None` = only asked). A seeded tray ignores the call.
    pub fn offer_free(&mut self, id: String, answer: Option<String>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.free_choices.push(FreeChoice { id, hints: Vec::new(), answer, reached: None, bad: None, lines: Vec::new(), landings: Vec::new(), order: 0 });
        }
    }

    /// Step 29d: the resolution reaches the free choice `id` (owner = the answering unit's key): its answer, or `None`
    /// (nothing offered, or only asked).
    pub fn reach_free(&mut self, id: &str, owner: &str) -> Option<String> {
        let feed = self.feed.as_mut()?;
        let c = feed.free_choices.iter_mut().find(|c| c.id == id)?;
        if c.reached.is_none() {
            c.reached = Some((feed.next, owner.to_string()));
            c.order = feed.choice_seq;
            feed.choice_seq += 1;
            if c.answer.is_none() {
                c.lines = self.lines.iter().map(|(_, l)| l.clone()).collect();
                c.landings = self.landings.iter().map(|(_, l)| l.clone()).collect();
            }
        }
        c.answer.clone()
    }

    /// [`Tray::reach_free`] with `hints` the owner's side reads (step 29e-2a: `pushed:<slot>`, the model the rest gather at).
    pub fn reach_free_hinted(&mut self, id: &str, owner: &str, hints: Vec<String>) -> Option<String> {
        if let Some(c) = self.feed.as_mut().and_then(|f| f.free_choices.iter_mut().find(|c| c.id == id)) {
            c.hints = hints;
        }
        self.reach_free(id, owner)
    }

    /// Step 29d: the core refuses the free answer of `id` with `why` (the step answers Refused at that input).
    pub fn refuse_free(&mut self, id: &str, why: String) {
        if let Some(c) = self.feed.as_mut().and_then(|f| f.free_choices.iter_mut().find(|c| c.id == id)) {
            c.bad = Some(why);
        }
    }

    /// Step 29d (D-29-R2): the attacker's push choice `id` (`push:<attacker>:<target>`), reached after the attack's dice:
    /// `Some(true)` = push, `Some(false)` = no, `None` = nothing offered or only asked (no push).
    pub fn push_choice(&mut self, id: &str, owner: &str) -> Option<bool> {
        self.reach_two_way(|c| c.id == id, owner)
    }

    /// Step 29b: the shooting leg names its Blast choice id and the spread's units (target first) before the volley.
    pub fn blast_units(&mut self, id: String, keys: Vec<String>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.blast_at = Some((id, keys));
        }
    }

    /// Step 29b: the volley reaches the even split's remainder: `left` extra hits for `left` of the `open` units (indices into
    /// the spread's units). The options are every such set, named by roster keys; the owner's answer as indices, or `None`
    /// (nothing offered, only asked, or no option: the core's own, target first).
    pub fn blast_split_pick(&mut self, open: &[usize], left: usize) -> Option<Vec<usize>> {
        let feed = self.feed.as_mut()?;
        let (id, keys) = feed.blast_at.clone()?;
        let c = feed.blast_choices.iter_mut().find(|c| c.id == id && c.reached.is_none())?;
        let mut sets: Vec<Vec<usize>> = vec![Vec::new()];
        for &i in open.iter().rev() {
            sets = sets.into_iter().flat_map(|s| [s.clone(), [vec![i], s].concat()]).filter(|s| s.len() <= left).collect();
        }
        sets.retain(|s| s.len() == left);
        sets.sort();
        let label = |s: &Vec<usize>| s.iter().map(|&i| keys.get(i).cloned().unwrap_or_default()).collect::<Vec<_>>().join(",");
        c.reached = Some((feed.next, sets.iter().map(label).collect(), keys.first().cloned().unwrap_or_default()));
        c.order = feed.choice_seq;
        feed.choice_seq += 1;
        let pick = c.answer.as_ref().map(|a| a.join(","));
        let hit = pick.as_ref().and_then(|p| sets.iter().find(|s| label(s) == *p).cloned());
        c.bad = pick.is_some() && hit.is_none();
        if c.answer.is_none() {
            c.lines = self.lines.iter().map(|(_, l)| l.clone()).collect();
            c.landings = self.landings.iter().map(|(_, l)| l.clone()).collect();
        }
        hit
    }

    /// The shared reach of a two-way choice: the first reach stamps where (draws so far) and keeps the lines and landings before it.
    fn reach_two_way(&mut self, find: impl Fn(&StrikeBackChoice) -> bool, owner: &str) -> Option<bool> {
        let feed = self.feed.as_mut()?;
        let c = feed.strike_back_choices.iter_mut().find(|c| find(c))?;
        if c.reached.is_some() {
            return c.answer;
        }
        c.reached = Some((feed.next, owner.to_string()));
        c.order = feed.choice_seq;
        feed.choice_seq += 1;
        if c.answer.is_none() {
            c.lines = self.lines.iter().map(|(_, l)| l.clone()).collect();
            c.landings = self.landings.iter().map(|(_, l)| l.clone()).collect();
        }
        c.answer
    }

    /// CC-5a: the transcript's planned casts, in plan order. A supplied tray keeps them (the cast slot of `resolve_with` reads them
    /// and the expectation `cast_phase` stays off); a seeded tray ignores the call, so every seeded path is unchanged.
    pub fn offer_casts(&mut self, casts: Vec<CastInput>) {
        if let Some(feed) = self.feed.as_mut() {
            feed.casts = casts;
        }
    }

    /// meleefix: the planner's consolidation inputs, one per melee unit: the step path's `Input::Consolidate`, or a replay that
    /// read them off the record's `consolidate` line. Nobody else offers any, so every other path keeps the core's own goal.
    /// A push decided up front (a replay or a test): the same answer as the `push:` + `push_to:` choices.
    pub fn offer_push(&mut self, push: Option<crate::activation::PushInput>) {
        self.push = push;
    }

    /// The push offered for this activation, if any.
    pub fn push(&self) -> Option<&crate::activation::PushInput> {
        self.push.as_ref()
    }

    pub fn offer_consolidation(&mut self, plans: Vec<ConsolidatePlan>) {
        self.consolidate = plans;
    }

    /// meleefix: the consolidation inputs offered for the unit keyed `key`; `None` when none was offered.
    pub fn consolidation_of(&self, key: &str) -> Option<&ConsolidatePlan> {
        self.consolidate.iter().find(|c| c.unit == key)
    }

    /// CC-5c/8b: the cast `seq` could not be resolved at this point (unhandled spell kind, or CC-6a hazard 2: an earlier
    /// cast in the same activation placed a record on a damage spell's target). Keeps the first one with its draw index.
    pub fn note_cast_refused(&mut self, seq: i64, reason: String) {
        if let Some(feed) = self.feed.as_mut() {
            feed.cast_refused.get_or_insert((feed.next, seq, reason));
        }
    }

    /// The casts `offer_casts` kept; empty on every seeded tray and on a supplied one nobody offered to.
    pub fn casts(&self) -> &[CastInput] {
        self.feed.as_ref().map_or(&[][..], |f| f.casts.as_slice())
    }

    /// The supplied placement, if any (`None` on every seeded tray).
    pub fn placed(&self) -> Option<&[[f64; 3]]> {
        self.feed.as_ref().and_then(|f| f.placed.as_deref())
    }

    /// One-core P3: a supplied tray keeps the line, stamped with the draws so
    /// far; a seeded tray never calls `f` (training cost unchanged).
    pub fn say(&mut self, f: impl FnOnce() -> LogLine) {
        if let Some(feed) = self.feed.as_ref() {
            self.lines.push((feed.next, f()));
        }
    }

    /// Where the next line would stand: how many lines this tray holds and how many draws it has taken (both 0 on a seeded one), the mark
    /// `say_at` goes back to.
    pub fn mark(&self) -> (usize, usize) {
        (self.lines.len(), self.feed.as_ref().map_or(0, |f| f.next))
    }

    /// A line said at an earlier `mark`, not at the end, stamped with the draws taken then: the table lands a Deadly weapon right after its
    /// saves, ahead of the next weapon's rolls, and the core only knows the landing once the whole fold has rolled. A seeded tray keeps nothing.
    pub fn say_at(&mut self, mark: (usize, usize), f: impl FnOnce() -> LogLine) {
        if self.feed.is_none() {
            return;
        }
        let at = mark.0.min(self.lines.len());
        self.lines.insert(at, (mark.1, f()));
        if let Some(held) = self.outcome_at.as_mut().filter(|h| **h >= at) {
            *held += 1;
        }
    }

    /// The line just said is a morale outcome the test's own wounds (No Retreat's self-wounds) are to be reported ahead of:
    /// the table logs "has No Retreat", the wounds it dealt, and only then "passes morale". Seeded trays keep nothing.
    pub fn hold_outcome(&mut self) {
        if self.feed.is_some() && !self.lines.is_empty() {
            self.outcome_at = Some(self.lines.len() - 1);
        }
    }

    /// A wound or loss line of a landing report: ahead of the held outcome line when there is one and nothing was said
    /// since, else at the end like `say`.
    pub fn say_wounds(&mut self, f: impl FnOnce() -> LogLine) {
        let Some(feed) = self.feed.as_ref() else { return };
        let line = (feed.next, f());
        match self.outcome_at {
            Some(at) if at + 1 == self.lines.len() => {
                self.lines.insert(at, line);
                self.outcome_at = Some(at + 1);
            }
            _ => self.lines.push(line),
        }
    }

    /// The landing report is done: the held outcome line (if any) stays where it now stands.
    pub fn release_outcome(&mut self) {
        self.outcome_at = None;
    }

    /// The lines said before draw `draw` was taken (stamp <= `draw`): what a
    /// step that starved at roll `draw` may show; later lines read 1s.
    pub fn lines_upto(&self, draw: usize) -> Vec<LogLine> {
        self.lines.iter().filter(|(at, _)| *at <= draw).map(|(_, l)| l.clone()).collect()
    }

    /// Every line said on this tray, in order.
    pub fn all_lines(&self) -> Vec<LogLine> {
        self.lines.iter().map(|(_, l)| l.clone()).collect()
    }

    /// One-core P3: a supplied tray keeps the landing, stamped with the draws
    /// so far; a seeded tray never calls `f` (training cost unchanged).
    pub fn land(&mut self, f: impl FnOnce() -> Landing) {
        if let Some(feed) = self.feed.as_ref() {
            self.landings.push((feed.next, f()));
        }
    }

    /// The landings made before draw `draw` was taken (stamp <= `draw`).
    pub fn landings_upto(&self, draw: usize) -> Vec<Landing> {
        self.landings.iter().filter(|(at, _)| *at <= draw).map(|(_, l)| l.clone()).collect()
    }

    /// P4.0-1: the capture-order slots of `unit`'s models the landings so far removed (a supplied tray only: a seeded
    /// one keeps no landing, so this is empty and allocates nothing). `landing_of` skips them to name a model's slot.
    pub fn dead_slots(&self, unit: usize) -> Vec<usize> {
        let dead = self.landings.iter().filter(|(_, l)| l.unit == unit).flat_map(|(_, l)| &l.models).filter(|m| m.dead);
        dead.map(|m| m.slot).collect()
    }

    /// Every landing made on this tray, in order.
    pub fn all_landings(&self) -> Vec<Landing> {
        self.landings.iter().map(|(_, l)| l.clone()).collect()
    }

    /// `rng.state` — the cheap replay checkpoint GATE R already compares.
    pub fn state_i64(&self) -> i64 {
        self.rng.state_i64()
    }
}

/// Supplied faces for `Tray::supplied`.
#[derive(Debug, Clone)]
pub struct Feed {
    groups: Vec<Vec<u8>>,
    next: usize,
    /// First roll no group was supplied for: (index, faces it draws).
    pub starved_at: Option<(usize, usize)>,
    /// First roll whose supplied group had the wrong size: (index, wanted, got).
    pub mismatch: Option<(usize, usize, usize)>,
    /// One-core P3: supplied per-model end positions (`Tray::place`); `None` = the move port decides.
    placed: Option<Vec<[f64; 3]>>,
    /// One-core P3: the supplied placement's per-model walked paths (`Tray::place`).
    placed_trails: Option<Vec<Vec<[f64; 2]>>>,
    /// One-core P3: (draw, the table's kind) from `Tray::name_next`.
    kinds: Vec<(usize, &'static str)>,
    /// One-core P4 step 4.0-9: (draw, the drawing unit) from `Tray::owner_next`.
    owners: Vec<(usize, Option<usize>)>,
    /// The transcript's wound-allocation choices, one per id (`Tray::offer_wound_alloc`).
    pub wound_choices: Vec<WoundChoice>,
    /// CC-9c: the transcript's cast-interference choices, one per id (`Tray::offer_interference`).
    pub interference_choices: Vec<InterferenceChoice>,
    /// E-24: the transcript's strike-back choices (`Tray::offer_strike_back`).
    pub strike_back_choices: Vec<StrikeBackChoice>,
    /// Step 29b: the transcript's Blast split choices (`Tray::offer_blast_split`).
    pub blast_choices: Vec<BlastChoice>,
    /// Step 29d: the transcript's free-answer choices (`push_to:`), `Tray::offer_free`.
    pub free_choices: Vec<FreeChoice>,
    /// Step 29b: the shooting leg's open Blast choice id and the units its spread reaches, target first (`Tray::blast_units`).
    blast_at: Option<(String, Vec<String>)>,
    /// Monotonic reach ordinal across both choice families (breaks ties when two choices occur at the same draw).
    choice_seq: usize,
    /// CC-5a: the transcript's planned casts (`Tray::offer_casts`).
    casts: Vec<CastInput>,
    /// CC-5c/8b: the first offered cast refused during resolution `(draw, seq, reason)` (`Tray::note_cast_refused`).
    pub cast_refused: Option<(usize, i64, String)>,
    /// D-PAR3 14a: (start, beats) the table already paid (`Tray::pay`).
    paid: (bool, bool),
    /// Step 20: the intent's `no_step` (`Tray::hold_step`).
    no_step: bool,
}

/// The step API's wound-allocation choice as the volley's landing sees it. `answer` = the
/// owner's ordered capture slots (`None` = only asked). `reached` = (draws so far, options, owner) once a group's
/// landing came to it; `bad` = the first answered slot that is no option. CC-9a: `lines` and `landings` hold
/// everything said/landed on this tray BEFORE this choice was reached (when `answer` is `None`).
#[derive(Debug, Clone)]
pub struct WoundChoice {
    pub id: String,
    pub answer: Option<Vec<usize>>,
    pub reached: Option<(usize, Vec<usize>, String)>,
    pub bad: Option<usize>,
    pub lines: Vec<LogLine>,
    pub landings: Vec<Landing>,
    pub order: usize,
}

/// CC-9c: the step API's cast-interference choice as `tray_cast` sees it. `answer` = token count to spend
/// (`None` = only asked). `reached` = (draws so far, pool total, owner key); `bad` = out-of-range answer.
#[derive(Debug, Clone)]
pub struct InterferenceChoice {
    pub id: String,
    pub answer: Option<i64>,
    pub reached: Option<(usize, i64, String)>,
    pub bad: Option<i64>,
    pub lines: Vec<LogLine>,
    pub landings: Vec<Landing>,
    pub order: usize,
}

/// E-24: the step API's strike-back choice as the melee sees it. `reached` = (draws so far, owner key) once the melee came
/// to the defender's strike-back; `lines` / `landings` = everything before that point (when `answer` is `None`).
#[derive(Debug, Clone)]
pub struct FreeChoice {
    pub id: String,
    pub hints: Vec<String>,
    pub answer: Option<String>,
    pub reached: Option<(usize, String)>,
    pub bad: Option<String>,
    pub lines: Vec<LogLine>,
    pub landings: Vec<Landing>,
    pub order: usize,
}

/// Step 29d: a choice whose answer is free text (the push spot), not one of a list. `reached` = (draws so far, owner key);
/// `bad` = why the core refused the answer.
#[derive(Debug, Clone)]
pub struct BlastChoice {
    pub id: String,
    pub answer: Option<Vec<String>>,
    pub reached: Option<(usize, Vec<String>, String)>,
    pub bad: bool,
    pub lines: Vec<LogLine>,
    pub landings: Vec<Landing>,
    pub order: usize,
}

/// Step 29b (D-29-R1): the defender's Blast split choice as the shooting volley sees it. `answer` = the roster keys that take
/// the remainder hits (`None` = only asked); `reached` = (draws so far, options, owner = the target's key); `bad` = an answer
/// that is no option.
#[derive(Debug, Clone)]
pub struct StrikeBackChoice {
    pub id: String,
    pub answer: Option<bool>,
    pub reached: Option<(usize, String)>,
    pub lines: Vec<LogLine>,
    pub landings: Vec<Landing>,
    pub order: usize,
}

impl Feed {
    /// Rolls drawn so far (served, mismatched or starved alike).
    pub fn draws(&self) -> usize {
        self.next
    }

    /// The table's kind `Tray::name_next` gave draw `index`, if any.
    pub fn kind_of(&self, index: usize) -> Option<&'static str> {
        self.kinds.iter().find(|(at, _)| *at == index).map(|(_, k)| *k)
    }

    /// The unit `Tray::owner_next` stamped for draw `index`, if any.
    pub fn owner_of(&self, index: usize) -> Option<usize> {
        self.owners.iter().find(|(at, _)| *at == index).and_then(|(_, u)| *u)
    }

    fn take(&mut self, n: usize) -> Vec<u8> {
        let i = self.next;
        self.next += 1;
        match self.groups.get(i) {
            Some(g) if g.len() == n => g.clone(),
            Some(g) => {
                self.mismatch.get_or_insert((i, n, g.len()));
                vec![1; n]
            }
            None => {
                self.starved_at.get_or_insert((i, n));
                vec![1; n]
            }
        }
    }
}

/// Successes in a roll — `DiceRules.count_successes(faces, target, 0)`
/// (dice_rules.gd:55-71), the OPR quality/defense test:
/// a 6 ALWAYS succeeds, a 1 ALWAYS fails, anything else needs `>= target`.
///
/// The modifier is fixed at 0 on purpose: `_solo_tray_roll` sets
/// `_success_modifier = 0` (main.gd:7143) for every scripted roll, so an AI
/// tray roll is never modifier-counted — the modified threshold is baked into
/// `target` by the caller before the dice leave the cup.
pub fn faces_to_hits(faces: &[u8], target: u8) -> usize {
    if target == 0 {
        return 0; // `TARGET_NONE` — dice_rules.gd:57, nothing is being tested.
    }
    faces.iter().filter(|&&f| f >= 6 || (f > 1 && f >= target)).count()
}

// ------------------------------------------------- D1-B4: SHOOTING on the tray ---

/// One tray roll, in the shape `AiDiceRecorder` writes to `dice.jsonl`
/// (main.gd:7170-7178) — the gate compares these tuples line by line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Roll {
    /// `_solo_tray_roll`'s `roll_kind`: "attack" for hit/Regeneration dice,
    /// "defense" for a save batch and its Bane re-roll.
    pub kind: &'static str,
    pub count: i64,
    pub target: i64,
    pub faces: Vec<u8>,
    /// `_solo_tray_roll`'s `owner` (main.gd:7173), WITHOUT the `"AI (%s)"`
    /// wrapper `_solo_owner_label` (:7039-7040) puts on it: the firing MEMBER's
    /// name for an attack roll (main.gd:3199-3200 — `shooter_name` is
    /// `member.get_name()`, so an attached hero signs its own dice) and the
    /// DEFENDER's for a save batch (:6448) and the Regeneration roll (:6543).
    pub owner: String,
}

/// One weapon's share of a skirmish Blast spread: the shooter (index into the volley's `shooters`), the profile (index into
/// its `profiles`) and the hits each neighbour unit takes, in the order the caller passed `blast_spread`.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct BlastSpill {
    pub shooter: usize,
    pub profile: usize,
    pub hits: Vec<i64>,
}

/// What one shooting activation did on the tray.
#[derive(Debug, Default, Clone)]
pub struct ShootResult {
    /// Unsaved wounds after Deadly, Shred and Regeneration — handed to the
    /// trainer's OWN casualty machinery, which decides who dies.
    pub wounds: i64,
    /// SHO-15a/15b Scourge phantom wounds: never landed. The shooting morale trigger and the melee winner tally read them.
    pub scourge_wounds: i64,
    /// D1-B5: wounds caused BEFORE Regeneration, which is the tally the table's
    /// melee-winner comparison runs on — `caused += w` sits inside the weapon
    /// loop (main.gd:6113/:6148) and `caused += rv_wounds` inside Ravage
    /// (:6001), both ahead of the pooled `_solo_land_wounds` (:6161). Land
    /// `wounds`; compare `caused`. Using the landed number instead lets a
    /// Regeneration roll decide who tests morale, which the table never does.
    pub caused: i64,
    /// MEL-10r (`EPOCH_73_V36`) — the melee-winner tally as wounds actually TAKEN: like `caused`,
    /// but a wound Regeneration (or its family) cancels does NOT count. On the 73 leg only; below
    /// it `taken == caused` (the pre-Regeneration tally, pinned byte-exact). `caused` stays
    /// pre-Regeneration so Regenerative Strength still sees what Regeneration ignored.
    pub taken: i64,
    /// Every roll drawn, in draw order.
    pub rolls: Vec<Roll>,
    /// Table branches this port does NOT reproduce that THIS activation hit.
    /// Never silent: a flagged activation is a reported divergence, not a skip.
    pub unported: Vec<&'static str>,
    /// Block B13 — the rules-must-log lines THIS activation wrote, in order:
    /// the twin has no battle log, so an applied rule names itself here (the
    /// table's `battle_log.log_event`, e.g. "Retaliate: %s lashes back — %d
    /// hits", main.gd:6162-6165). Carried beside the dice stream, never a roll
    /// of its own.
    pub log: Vec<String>,
    /// The skirmish Blast spread: one entry per weapon that spread, in firing order. Empty when the volley spread nothing.
    pub blast_spill: Vec<BlastSpill>,
    /// The skirmish Jumping rule: each model of the activating unit whose jump failed - (unit, model, inches it fell) -
    /// for the fall (step 17). Empty when nobody jumped or every jump landed.
    pub falls: Vec<(usize, usize, f64)>,
    /// Ruling D15: every unit this activation's attack hit (a volley's or a strike's target, a Blast bystander, a damage
    /// spell's target), for the push. Never absorbed.
    pub attacked: Vec<usize>,
    /// The skirmish Blast spread in melee: each neighbour a strike's spill wounded, once, with its living models and wounds
    /// left before (`sim::land_blast_spill`), kept until the melee's own morale test is done. Never absorbed.
    pub melee_spilled: Vec<(usize, i64, i64)>,
    /// WAVE 3 — the family's alias/boost arm ACTUALLY lowered a save target
    /// this activation (main.gd's `ap < ap_before` guard), as read by
    /// `save_batch`; the orchestrators turn it into the rules-must-log line.
    pub fortified_fired: bool,
    /// Wave 4 (`rules-wave4-boostbases`) — the volley's ACTIVE Bane Boost
    /// window for THIS batch (the "Mischievous Boost" stamp, strictly past
    /// the entry's own `over_in`; 0 = the base 6s-only window). Set by the
    /// volley per weapon, read by `save_batch`; the melee resolve never sets
    /// it — its save batches run on fresh results, the base window.
    pub bane_low: i64,
    /// Rules 3.6 (SHO-10): the re-roll entry's target condition did NOT hold
    /// against this defender, so the whole Bane window (base 6s leg included) stays shut.
    pub bane_gated: bool,
    /// How many saves the WIDENED window added to the re-roll batches (the
    /// successful 5s the base 6s-only leg would never have touched) — the volley
    /// turns a non-zero count into the one rules-must-log line.
    pub bane_rerolled: i64,
    /// Audit 2026-09-13 §2.1 — the volley's Deadly groups, `(post-regeneration
    /// unsaved, X)` per weapon: Regeneration draws on the RAW unsaved count
    /// (the table's own roll inside `_solo_land_deadly_wounds`, main.gd:6762),
    /// the landing then multiplies PER MODEL with no carry-over
    /// (`SoloController.apply_deadly_wounds`, solo_controller.gd:8333). Empty
    /// on every non-Deadly activation; the landing sites drain it.
    pub deadly_groups: Vec<(i64, i64)>,
    /// EPOCH_94_PARITY_BATCH: the picks the volley made inside the dice, `(roster index, AP(+1) mode)`, one per member
    /// whose activation had no pick yet. The volley seam stamps them on the State's round latch after the call.
    pub versatile_picks: Vec<(usize, bool)>,
    /// The volley's Deadly weapons, one entry per weapon for the table's line (`_solo_land_deadly_wounds`): `(weapon, raw
    /// unsaved, X, how many of `deadly_groups` it pushed)`, in the same order. The volley landing drains both together.
    pub deadly_lines: Vec<(String, i64, i64, usize)>,
    /// The vs-target Marks (`tray_vs_marks`) this activation placed and has not yet seen spent: `(mark name, unit holding the record,
    /// marked target)`. Sim-level bookkeeping for the table's consumption line (`say_marks_consumed`); never merged by `absorb`.
    pub marks_open: Vec<(String, usize, usize)>,
    /// The melee fold's tray mark (`Tray::mark`) when each `deadly_lines` entry was pushed (that weapon's own save lines are behind it): the table
    /// lands a Deadly weapon right there, so the landing's lines go back to that mark. Empty unless the melee fold filled it.
    pub deadly_marks: Vec<(usize, usize)>,
    /// Wounds the target's ignore rules (Regeneration and its family) cancelled in the melee being resolved, summed over its phases by the
    /// sim (`strike_phase`, Impact) for the table's "cancelled by Regeneration" note on the melee result line (`_solo_regen_ignored`).
    pub regen_ignored: i64,
    /// The same groups' PRE-regeneration raw unsaved count — the shooting
    /// tally keeps it (`total_caused += w`, main.gd:3318) while the landing
    /// uses the group's post-regeneration count.
    pub deadly_tally: i64,
    /// Tray-exact S7 — the volley's Takedown groups (`Seams::tray_exact` only): per Takedown weapon,
    /// its unsaved wounds x max(Deadly, 1) AFTER the picked model's Regeneration (main.gd:4059-4067);
    /// the drain lands each on ONE model, overkill lost. Their raw count rides `deadly_tally`.
    pub takedown_groups: Vec<i64>,
    /// Per Takedown group pushed into `takedown_groups`: `(weapon_name, picked_model_label)` for the landing line.
    pub takedown_lines: Vec<(String, String)>,
    /// The volley fold's tray mark after each Takedown group beside another weapon: the table lands it there, so its lines go back to it.
    pub takedown_marks: Vec<(usize, usize)>,
    /// Rules 3.6 (`EPOCH_73_V36`) — Hazardous self-wounds the dice legs read off the hit roll:
    /// `(owner, weapon, unmodified 1s, X, mark)` with X = max(Blast, Deadly, 1) and the tray mark right after the hit roll (a volley's
    /// own shot only): the table wounds the firer there, ahead of the "fires" line. The sim lands them on the
    /// bearer (main.gd `_solo_hazardous_self_wounds`); below the gate they are ignored.
    pub hazardous_self: Vec<HazardousSelf>,
}

/// One Hazardous self-wound entry of `ShootResult::hazardous_self`: owner, weapon, unmodified 1s, X, the volley's tray mark after the hit roll.
pub type HazardousSelf = (String, String, i64, i64, Option<(usize, usize)>);

impl ShootResult {
    /// Flag a table branch this activation hit and this port does not
    /// reproduce. Public because D1-B5's melee sub-phases are orchestrated from
    /// `sim.rs`, where the state-level branches are the visible ones.
    pub fn mark(&mut self, what: &'static str) {
        if !self.unported.contains(&what) {
            self.unported.push(what);
        }
    }

    /// Fold a SUB-PHASE's draw into this activation's report, in draw order, and
    /// hand back its wounds so the caller lands them itself. One activation is
    /// one report: Impact, the strikes and the strike-back all queue here, which
    /// is what lets the replay gate compare a whole melee roll by roll. `caused`
    /// accumulates with it, so the melee-winner tally is the pre-Regeneration
    /// one the table compares.
    pub fn absorb(&mut self, other: ShootResult) -> i64 {
        self.rolls.extend(other.rolls);
        self.caused += other.caused;
        self.taken += other.taken;
        self.log.extend(other.log);
        self.fortified_fired = self.fortified_fired || other.fortified_fired;
        self.bane_rerolled += other.bane_rerolled;
        self.deadly_groups.extend(other.deadly_groups);
        self.deadly_lines.extend(other.deadly_lines);
        self.deadly_marks.extend(other.deadly_marks);
        self.deadly_tally += other.deadly_tally;
        self.takedown_groups.extend(other.takedown_groups);
        self.takedown_lines.extend(other.takedown_lines);
        self.takedown_marks.extend(other.takedown_marks);
        self.hazardous_self.extend(other.hazardous_self);
        for u in other.unported {
            self.mark(u);
        }
        other.wounds
    }
}

#[inline]
fn sixes(faces: &[u8]) -> i64 {
    faces.iter().filter(|&&f| f == 6).count() as i64
}

/// Row MEL-09's rules-must-log line, the table's same text (`_solo_melee_strike_phase`).
fn fatigued_sixes_line(owner: &str, n: i64) -> String {
    format!("Fatigued: {owner} — {n} unmodified 6{} hit but trigger no special rules", if n == 1 { "" } else { "s" })
}

/// Rules 3.6 row MOR-12c — `AiEv.stamp_sergeant`'s bearer share, applied at the
/// strike: `max(1, round(attacks / alive models))` of this profile's attack
/// dice, and that share's fraction of the plain hits
/// `min(normal, round(normal * share / attacks))`. `att.models` is the live
/// alive count (`ctx_of` writes `state.alive`), the Ctx twin of the table's
/// `GameUnit.get_alive_count()`. 0 without the rules 3.6 stamp. `attacks` is
/// the pool the share is a fraction of: the weapon's full attack total on the
/// volley leg (the table stamps before the sighted scaling), the strike's own
/// scaled count on the melee leg (the table stamps its melee profile after it).
fn sergeant_hits(p: &ShootProfile, attacks: i64, normal: i64, att: &Ctx) -> i64 {
    if p.sergeant_ap <= 0 || attacks <= 0 || normal <= 0 {
        return 0;
    }
    let alive = att.models.max(1) as f64;
    let share = (attacks as f64 / alive).round().max(1.0);
    let hits = (normal as f64 * share / attacks as f64).round() as i64;
    hits.min(normal).max(0)
}

/// Row MOR-12c's rules-must-log line, the table's same text (`_solo_resolve_saves`): said before the bearer's own
/// save batch, on the tray and in the resolve's `log` alike. The rule's own name, as the registry carries it.
fn sergeant_line(p: &ShootProfile, owner: &str, hits: i64) -> String {
    format!("{}: {owner} strikes {hits} hit{} with AP(+{})", p.sergeant_rule, if hits == 1 { "" } else { "s" }, p.sergeant_ap)
}

/// The Shielded-family alias's rules-must-log line, the volley and melee
/// resolves' shared twin: the +1 kinds name the rule and the floored rung
/// ("{name}: {owner} — +1 to defense rolls (saves on N+)"), while the rating
/// kind (`acts::EPOCH_54_DEFENSE_RATING`) names its own number —
/// "Defense(X): +X Defense vs non-spell hits" — exactly the clause the
/// table's Shielded part prints (main.gd:5594-5597).
fn shielded_alias_line(def: &Ctx, def_owner: &str) -> String {
    if def.shielded_alias == ShieldedAlias::DefenseRating {
        let x = def.shielded_rating;
        return format!("Defense({x}): +{x} Defense vs non-spell hits");
    }
    format!(
        "{}: {def_owner} — +1 to defense rolls (saves on {}+)",
        def.shielded_alias.name(),
        shielded_defense(def.defense, def.shielded_bonus(), def.def_floor())
    )
}

/// The table's per-part Defense line (`_solo_log_defense_parts`, NML-932) for each record behind `def.defense_mod`: its own name, its
/// signed shift and the working Defense before AP, cover and the over-9" family (Shielded, the growth ladder and every token folded,
/// the table's 2..6 window).
fn defense_token_lines(def: &Ctx, def_owner: &str) -> Vec<String> {
    let rung = (def.defense - def.shielded_bonus() - def.growth_def_mod + def.defense_mod).clamp(2, 6);
    def.defense_mod_parts.lines().filter_map(|l| l.split_once('\t'))
        .map(|(name, x)| format!("{def_owner} is {name}: {x} Defense (saves on {rung}+)")).collect()
}

/// Block B6 — the extra-ATTACK-DIE form of the "unmodified 6 to hit" family
/// (Bloodborn / Clan Warrior / Primal / Predator / Royal Warrior / Crazed /
/// Psychotic and their book aliases, `unit.rs::stamp`'s `surge_attack` /
/// `surge_attack_low`, `_solo_hits` main.gd:4417-4432): for each unmodified 6
/// among `faces` — plus each unmodified 5 too, once `surge_attack_low < 6`
/// (the Primal-Boost-style upgrade) — draw ONE more attack die at
/// `count_target`, as its own tray slot; the extras are counted as hits but
/// never re-trigger (`faces` here is always the ORIGINAL roll, never the
/// extras). Shared by `resolve_volley_with_tray` and `resolve_melee_with_tray`
/// — the table resolves both through the same `_solo_hits`.
/// Wave 2 grant stand-ins — the family's printed shapes, uniform on every
/// shipped occurrence (HIT_AND_RUN_MOVE_IN precedent).
fn primal_boost_grant_profile() -> ShootProfile {
    ShootProfile { surge_attack: true, surge_attack_low: 5, ..Default::default() }
}

fn slayer_grant_cond() -> CondAp {
    CondAp {
        ap_bonus: 2, condition: "vs_tough_ge".into(), threshold: 3,
        gate: "ranged_over_or_charge".into(), over_in: 9.0, ..Default::default()
    }
}

fn piercing_assault_grant_cond() -> CondAp {
    CondAp { ap_bonus: 1, condition: "on_charge".into(), ..Default::default() }
}

/// The table's over-9" Defense line of the Guarded family (`_solo_resolve_ai_volley`): once per volley, before the first die, hit or miss; its
/// "(most of its models carry it)" note needs per-model carriers. The table says it right after the armor / Shielded / growth lines and BEFORE
/// the announce, so the door's volley says it there (`sim.rs`, `Ctx::guarded_said`); a volley with no announce (the Strafing move-through)
/// still says it from the fold.
pub(crate) fn say_guarded(tray: &mut Tray, def: &Ctx, def_owner: &str, mod_dist_in: f64) {
    if def.guarded && mod_dist_in > LONG_RANGE_IN && !def.sturdy_boost_gates_guarded {
        let saves = guarded_defense(shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), true, def.def_floor());
        say_rule(tray, "guarded", def.side, || format!("{def_owner} ({}): shot from over {}\" — +1 Defense (saves on {}+)",
            def.guarded_name, LONG_RANGE_IN as i64, saves.clamp(BEST_HIT_TARGET, 6)));
    }
}

/// The table's `_solo_log_armor` line (`<U> has Armor(X): counts as Defense X+`), said once before the volley's announce when Armor improves the
/// target's Defense; ahead of the Shielded / growth lines, which fold on top of it.
pub(crate) fn say_armor(tray: &mut Tray, def: &Ctx, name: &str) {
    if def.armor_line > 0 {
        let x = def.armor_line;
        say_rule(tray, "armor", def.side, || format!("{name} has Armor({x}): counts as Defense {x}+"));
    }
}

/// A rule's battle-log line on a supplied tray, in the table's words (a seeded tray never builds the text).
/// The table's `_solo_log_defense_parts` line for the Shielded family (`<U> is <rule>: +N Defense (saves on M+)`), said once before the
/// volley's announce; the rule is the literal or the alias that drives `shielded`. None when the target has no bonus to name.
pub(crate) fn say_shielded(tray: &mut Tray, def: &Ctx, name: &str) {
    let Some((rule, bonus)) = shielded_label(def) else { return };
    say_rule(tray, "shielded", def.side, || format!("{name} is {rule}: +{bonus} Defense (saves on {}+)", parts_defense(def).clamp(BEST_HIT_TARGET, 6)));
}

/// The Shielded family's part as the table names it (`_solo_defense_parts`): the rule (the literal or the alias driving `shielded`, with
/// its most-models note) and the bonus; None when the target has no bonus to name.
fn shielded_label(def: &Ctx) -> Option<(String, i64)> {
    let bonus = def.shielded_bonus();
    if !def.shielded || bonus <= 0 {
        return None;
    }
    let rule = match def.shielded_alias {
        ShieldedAlias::None => "Shielded",
        ShieldedAlias::PlusOneToDefense => "+1 to Defense",
        ShieldedAlias::SturdyBoost => "Enhanced Sturdy",
        ShieldedAlias::SafetyGearBoost => "Safety Gear Boost",
        ShieldedAlias::TenaciousBoost => "Tenacious Boost",
        ShieldedAlias::GroundedReinforcement => "Grounded Defense",
        ShieldedAlias::DefenseRating => "Defense",
    };
    let note = if def.shielded_alias == ShieldedAlias::None && def.shielded_note { " (most of its models carry it)" } else { "" };
    Some((format!("{rule}{note}"), bonus))
}

/// The working Defense the table's defence-part lines print as "saves on N+" (`_solo_defense_vs`: Shielded, then the growth ladder and the
/// ledger's token modifier, no cover, no AP): `save_batch`'s own fold without the AP. Shielded alone reads as it always did.
fn parts_defense(def: &Ctx) -> i64 {
    let d = shielded_defense(def.defense, def.shielded_bonus(), def.def_floor());
    let gd = def.growth_def_mod;
    if gd == 0 {
        d
    } else if def.modifier_sum {
        d - gd + def.defense_mod
    } else if def.growth_def_lowers {
        ((d - gd).clamp(2, 6) + def.defense_mod).max(BEST_HIT_TARGET)
    } else {
        (d + gd + def.defense_mod).max(BEST_HIT_TARGET)
    }
}

/// The table's `_solo_log_defense_parts` lines for the Growth Markers defence ladder (Defensive Growth / Frenzy): one line per rule that
/// earned a bonus, `<U> is <rule>: +N Defense (saves on M+)`, after the Shielded line and before the announce.
pub(crate) fn say_growth_defense(tray: &mut Tray, def: &Ctx, name: &str, parts: &[(String, i64)]) {
    if def.growth_def_mod == 0 {
        return;
    }
    for (rule, bonus) in parts {
        say_rule(tray, "growth_def", def.side, || format!("{name} is {rule}: +{bonus} Defense (saves on {}+)", parts_defense(def).clamp(BEST_HIT_TARGET, 6)));
    }
}

/// The table's last `_solo_log_defense_parts` line (C-STURDY-BOOST, from `EPOCH_73_V36`): a Boost that replaces the unit's Sturdy-family rule
/// says so, after the Defense part lines. Only a unit that carries the base rule too (`guarded_name`) has one to replace.
pub(crate) fn say_sturdy_replaces(tray: &mut Tray, def: &Ctx) {
    let base = def.shielded_alias.replaced_rule();
    if def.v36_rules && def.sturdy_boost_gates_guarded && def.guarded && !base.is_empty() && def.guarded_name == base {
        say_rule(tray, "shielded", def.side, || format!("{}: replaces {base} — +1 Defense at any range, no extra +1 from over 9\"", def.shielded_alias.name()));
    }
}

/// The table's line for the Growth-marker AP a save batch carries (`_solo_resolve_saves`, from `EPOCH_73_V36`), after the conditional AP
/// lines: `<rule>: <striker> adds AP(+N) from its growth markers`, once per weapon profile that has hits to save.
pub(crate) fn say_growth_ap(tray: &mut Tray, att: &Ctx, owner: &str) {
    if att.growth_ap_mod > 0 && att.v36_rules && !att.growth_ap_name.is_empty() {
        say_rule(tray, "growth_ap", att.side, || format!("{}: {owner} adds AP(+{}) from its growth markers", att.growth_ap_name, att.growth_ap_mod));
    }
}

/// The table's line before the AP-on-6 batch (`_solo_resolve_saves`): Rending, Destructive or the book entry's name, shooting and melee alike.
fn say_on6_ap(tray: &mut Tray, p: &ShootProfile, att: &Ctx, ap4: i64, on6: i64) {
    if ap4 > 0 {
        let label = if p.rending || att.rending_grant { "Rending" } else if p.destructive { "Destructive" }
            else if p.on6_rule.is_empty() { "Crack" } else { p.on6_rule.as_str() };
        say_rule(tray, "on6_ap", att.side, || format!("{label}: {ap4} hit{} on a 6 → AP(+{on6})", if ap4 == 1 { "" } else { "s" }));
    }
}

pub(crate) fn say_rule(tray: &mut Tray, rule: &'static str, side: i64, text: impl FnOnce() -> String) {
    tray.say(|| LogLine { rule, category: Category::Combat, side, text: text(), detail: None });
}

/// The table's Pierce line (`_solo_resolve_saves`, shooting and melee alike): the weapon's name and the target's positive Defense parts in
/// `_solo_defense_parts` order (Shielded, growth ladder, spell token), then Cover when the target has it (`cover`; never in melee).
fn say_pierce(tray: &mut Tray, side: i64, weapon: &str, def: &Ctx, cover: bool) {
    if tray.feed().is_none() {
        return;
    }
    let mut ignored: Vec<String> = shielded_label(def).map(|(n, b)| format!("{n} +{b}")).into_iter().collect();
    if !def.growth_def_parts.is_empty() { ignored.push(def.growth_def_parts.to_string()); }
    if def.defense_mod < 0 { ignored.push(format!("Defense Buff +{}", -def.defense_mod)); }
    if cover { ignored.push("Cover +1".into()); }
    if !ignored.is_empty() {
        say_rule(tray, "pierce", side, || format!("Pierce: {weapon} ignores {}", ignored.join(", ")));
    }
}

/// The table's Regeneration-bypass naming (`_solo_ignores_regen`, asked once per weapon with hits), in its arm order: a Bane / Rending
/// weapon answers silently; the printed Unstoppable says `Unstoppable: Regeneration ignored`; a registry bypass rule says its own name
/// (`<rule>: Regeneration ignored`); the unit's own rules come next (`ShootProfile::regen_unit_arm`: Anti-Regen, Unstoppable when Shooting,
/// Bane when Shooting), the granted Unstoppable Mark says `Unstoppable Mark: <U> — Regeneration is ignored (once)`, and a unit-level Rending
/// says `Rending (granted)`. From 73 only a target that really has a Regeneration roll to skip is told so (`_solo_regen_bypass_named`). The
/// aura grant answers silently.
/// `asked` = the table asked for this weapon at all (a Deadly or Takedown weapon only when it dealt wounds).
fn say_regen_bypass(tray: &mut Tray, side: i64, p: &ShootProfile, att: &Ctx, def: &Ctx, owner: &str, asked: bool) {
    if !asked || tray.feed().is_none() || (att.v36_rules && !(def.regeneration && def.regen_target > 0 && def.bypass_skips_ignore())) {
        return;
    }
    for r in &p.rules {
        let s = r.trim();
        if s.starts_with("Bane") || s.starts_with("Rending") {
            return;
        }
        if s.starts_with("Lacerate") {
            continue;
        }
        if s.split('(').next().is_some_and(|b| b.trim() == "Unstoppable") {
            say_rule(tray, "anti_regen", side, || "Unstoppable: Regeneration ignored".to_string());
            return;
        }
        if !p.regen_bypass_rule.is_empty() && crate::rules::base_rule_name(s) == p.regen_bypass_rule {
            say_rule(tray, "anti_regen", side, || format!("{}: Regeneration ignored", p.regen_bypass_rule));
            return;
        }
    }
    // The table's unit-level arms, after the weapon's own rules (`_solo_ignores_regen`): the first that applies answers - a rule name's
    // line, or none ("Rending in Melee"). Ranged profiles only (see `ShootProfile::regen_unit_arm`).
    if p.range > 0 {
        if let Some(name) = &p.regen_unit_arm {
            if !name.is_empty() {
                say_rule(tray, "anti_regen", side, || format!("{name}: Regeneration ignored"));
            }
            return;
        }
    }
    if att.unstoppable_mark {
        say_rule(tray, "anti_regen", side, || format!("Unstoppable Mark: {owner} — Regeneration is ignored (once)"));
    } else if att.v36_rules && p.range > 0 && p.rending {
        // the profile's `rending` flag past the weapon's own printed Rending (which answered silently above): a unit-level Rending rule
        // ("Rending when Shooting") - the table's flag arm names it granted. From 73, like the unit arms; the Unstoppable / Bane flag arms
        // are not said here.
        say_rule(tray, "anti_regen", side, || "Rending (granted): Regeneration ignored".to_string());
    }
}

/// The skirmish Blast(X) spread (Firefight / AoF: Skirmish p.13), per ORIGINAL hit: each hit becomes `x` hits dealt
/// one at a time in turn over the target (index 0) and the `neighbour_models` units (indices 1..), each unit capped at
/// its own living models; what no unit can take is lost. The turn starts at the target, so an odd hit lands there
/// (the default when the defender places none). Returns the hits per unit; `x` <= 1 leaves every hit on the target.
/// No neighbours = today's `hits * x.clamp(1, models)` (the shooting leg's Blast multiply). Read by the shooting volley when a book spreads Blast.
pub fn blast_split(hits: i64, x: i64, target_models: i64, neighbour_models: &[i64]) -> Vec<i64> {
    let caps: Vec<i64> = std::iter::once(target_models.max(1)).chain(neighbour_models.iter().map(|m| (*m).max(0))).collect();
    let mut one = vec![0i64; caps.len()];
    let mut left = x.max(1);
    while left > 0 && one.iter().zip(&caps).any(|(n, c)| n < c) {
        for (n, c) in one.iter_mut().zip(&caps) {
            if left > 0 && *n < *c {
                *n += 1;
                left -= 1;
            }
        }
    }
    one.iter().map(|n| n * hits.max(0)).collect()
}

/// [`blast_split`] at `rules_epoch`: from `PENDING_EPOCH_BLAST_EVEN` (ruling D-29-R1) the whole attack's hits split evenly -
/// every unit the same share up to its room (`hits` x its models, as a hit's X never put more than one hit per model on a
/// unit), what a full unit cannot take shared among the rest, the remainder one each in unit order (target first). The total
/// stays `hits x min(X, all models)`, so a single hit or a lone target lands exactly as before; below the epoch, `blast_split`.
pub fn blast_split_at(hits: i64, x: i64, target_models: i64, neighbour_models: &[i64], rules_epoch: u32) -> Vec<i64> {
    if !rule_on(rules_epoch, crate::acts::PENDING_EPOCH_BLAST_EVEN) {
        return blast_split(hits, x, target_models, neighbour_models);
    }
    let (out, caps, left) = blast_even_base(hits, x, target_models, neighbour_models);
    blast_give(out, &caps, left, None)
}

/// The even split before its remainder: every unit's level share, its room, and the hits still to give (one each).
fn blast_even_base(hits: i64, x: i64, target_models: i64, neighbour_models: &[i64]) -> (Vec<i64>, Vec<i64>, i64) {
    let caps: Vec<i64> = std::iter::once(target_models.max(1)).chain(neighbour_models.iter().map(|m| (*m).max(0))).map(|c| c * hits.max(0)).collect();
    let total = hits.max(0) * x.max(1).min(caps.iter().sum::<i64>() / hits.max(1));
    let level = (0..=caps.iter().copied().max().unwrap_or(0)).take_while(|&l| caps.iter().map(|c| (*c).min(l)).sum::<i64>() <= total).last().unwrap_or(0);
    let out: Vec<i64> = caps.iter().map(|c| (*c).min(level)).collect();
    let left = total - out.iter().sum::<i64>();
    (out, caps, left)
}

/// The remainder one each, to the units `to` names (the defender's pick, step 29b) or else in unit order, target first.
fn blast_give(mut out: Vec<i64>, caps: &[i64], mut left: i64, to: Option<&[usize]>) -> Vec<i64> {
    let order: Vec<usize> = to.map_or_else(|| (0..out.len()).collect(), <[usize]>::to_vec);
    for i in order {
        if left > 0 && out[i] < caps[i] {
            out[i] += 1;
            left -= 1;
        }
    }
    out
}

/// The table's `blast_log_text`: names Blast(X) and, when the model count clamps the multiplier, the cap.
fn blast_log(x: i64, hits: i64, boosted: i64, models: i64, stale: bool) -> String {
    let mult = boosted / hits.max(1);
    let capped = if mult >= x { String::new() } else { format!(" (capped by {models} model{} in target)", if models == 1 { "" } else { "s" }) };
    // the table's note when casualties since the volley began made the cap's model count out of date (`blast_models > alive`)
    let note = if stale { " (cap read when the volley started)" } else { "" };
    format!("Blast({x}): {hits} hit{} ×{mult}{capped} → {boosted} hits{note}", if hits == 1 { "" } else { "s" })
}

fn surge_attack_hits(p: &ShootProfile, faces: &[u8], count_target: i64, owner: &str, tray: &mut Tray, rolls: &mut Vec<Roll>) -> i64 {
    surge_attack_say(p, faces, count_target, owner, tray, rolls, None)
}

/// `surge_attack_hits`, plus the table's `_solo_hits` line when `say_side` is the shooter's seat (the volley and strike
/// legs; the melee Bloodthirsty leg stays silent).
fn surge_attack_say(
    p: &ShootProfile,
    faces: &[u8],
    count_target: i64,
    owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
    say_side: Option<i64>,
) -> i64 {
    if !p.surge_attack {
        return 0;
    }
    let mut xn = sixes(faces);
    if p.surge_attack_low < 6 {
        xn += faces.iter().filter(|&&f| f == 5 && count_target <= 5).count() as i64;
    }
    if xn <= 0 {
        return 0;
    }
    let extra_faces = tray.roll(xn as usize);
    rolls.push(Roll {
        kind: "attack",
        count: xn,
        target: count_target,
        faces: extra_faces.clone(),
        owner: owner.into(),
    });
    let hits = faces_to_hits(&extra_faces, count_target as u8) as i64;
    if let Some(side) = say_side {
        let rule = if p.surge_attack_rule.is_empty() { "Extra attacks" } else { p.surge_attack_rule.as_str() };
        say_rule(tray, "extra_attack", side, || format!("{rule}: {xn} extra attack{} from unmodified 6s — {hits} hit{}",
            if xn == 1 { "" } else { "s" }, if hits == 1 { "" } else { "s" }));
    }
    hits
}

/// `EPOCH_96_PARITY_BATCH`: the "Enhanced Primal" grant only widens a printed extra-attack form; a profile
/// without one gains nothing from it. Below the gate every grant reaches (byte-exact).
fn primal_grant_reaches(p: &ShootProfile, rules_epoch: u32) -> bool {
    p.surge_attack || !rule_on(rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH)
}

/// G4R5 F-PRIMAL-GRANT-ONCE (`EPOCH_73_V36`): ONE live "Enhanced Primal" grant is carried in two channels (the overlay rule on
/// the unit's rules and the ledger buff the spell records) and rolls ONE extras group, like the table's idempotent profile flag.
/// On a member that PRINTS the extra-die form the grant only LOWERS that form's threshold to 5s; only a member without the
/// printed form rolls the grant's own group. Below 73 both groups roll (replay). Returns the extras' hits.
#[allow(clippy::too_many_arguments)]
fn primal_extras(p: &ShootProfile, grant: bool, v36: bool, faces: &[u8], count_target: i64, owner: &str, side: i64, tray: &mut Tray, out: &mut ShootResult) -> i64 {
    if !(grant && v36 && p.surge_attack) {
        let hits = surge_attack_say(p, faces, count_target, owner, tray, &mut out.rolls, Some(side));
        return hits + if grant { surge_attack_say(&primal_boost_grant_profile(), faces, count_target, owner, tray, &mut out.rolls, Some(side)) } else { 0 };
    }
    if faces.iter().any(|&f| f == 6 || (f == 5 && count_target <= 5)) {
        let line = format!("Enhanced Primal: {owner} — one extra-attack roll on unmodified 5s and 6s (the grant widens the Primal, it adds no second roll)");
        say_rule(tray, "enhanced_primal", side, || line.clone()); // the step path's lines are the tray's
        out.log.push(line);
    }
    surge_attack_say(&ShootProfile { surge_attack_low: p.surge_attack_low.min(5), ..p.clone() }, faces, count_target, owner, tray, &mut out.rolls, Some(side))
}

/// The widened window (wave 4, "Mischievous Boost"'s `reroll_save_low: 5`):
/// every SUCCESSFUL unmodified save at or above `from` re-rolls too, not
/// just 6s (`from` 6 = the base leg, byte-exact). A face below the save
/// target is no success — it never re-rolls.
fn blocks_with_bane_from(faces: &[u8], reroll: &[u8], target: i64, from: i64) -> i64 {
    let mut ri = 0usize;
    let mut blocks = 0i64;
    for &f in faces {
        let eff = if f == 6 || (f as i64 >= from && f as i64 >= target) {
            let r = reroll.get(ri).copied().unwrap_or(f);
            ri += 1;
            r
        } else {
            f
        };
        if eff >= 6 || (eff > 1 && eff as i64 >= target) {
            blocks += 1;
        }
    }
    blocks
}

/// Scourge's `phantom_wounds_per_save_one` (rules_mechanics_gf/aof.json `common`; the table reads the map).
pub const SCOURGE_PHANTOM_WOUNDS: i64 = 2;

/// `AiCombatMath.shred_bonus_wounds` :475-485 — unmodified Defense 1s on the
/// FINAL faces (a 6 that Bane re-rolled into a 1 counts, the 6 itself never).
/// The Shred Boost generalizes the window to `low` (failed rolls 1..=low — a
/// 1 always fails, a higher face only strictly under the save target);
/// `low = 1` is the base rule and this function's old shape.
fn shred_faces(faces: &[u8], reroll: &[u8], low: i64, target: i64) -> i64 {
    let mut ri = 0usize;
    let mut wounds = 0i64;
    for &f in faces {
        if f == 6 && ri < reroll.len() {
            let g = reroll[ri] as i64;
            ri += 1;
            if g <= low && (g == 1 || g < target) {
                wounds += 1;
            }
        } else if (f as i64) <= low && (f == 1 || (f as i64) < target) {
            wounds += 1;
        }
    }
    wounds
}

/// Rules 3.6 (SHO-14) — `Pierce`: the save ignores POSITIVE Defense modifiers; Armor and negatives stay.
pub(crate) fn pierce_ignores(p: &ShootProfile, epoch_ctx: &Ctx) -> bool {
    rule_on(epoch_ctx.rules_epoch, EPOCH_73_V36) && p.rules.iter().any(|r| r.trim() == "Pierce")
}

/// One-core P3 step 25: `save_threshold_text` (main.gd:11634) — Defense `d` worsened by AP `a`; a natural 6
/// always saves, so past 6 the text says so instead of the raw sum.
fn save_threshold_text(d: i64, a: i64) -> String {
    let shown = d.clamp(BEST_HIT_TARGET, 6);
    if a > 0 && d + a > 6 {
        format!("6 only (Def {shown}+, AP {a} — a natural 6 always saves)")
    } else if a > 0 {
        format!("{}+ (Def {shown}+, AP {a})", (d + a).clamp(BEST_HIT_TARGET, 6))
    } else {
        format!("{shown}+")
    }
}

/// `main._solo_save_batch` :6385-6483 — ONE batch for the whole defender (not
/// per model), Fortified first, then the dice, then Bane's re-roll of the
/// unmodified 6s, then Shred — the pool's Deadly shape is the
/// `EPOCH_14_DEADLY_LANDING` gate's two legs: below 14 the multiply against
/// the unit's printed Tough rides the pool (verbatim), from 14 the pool stays
/// RAW and the landing multiplies per model (audit 2026-09-13 §2.1).
///
/// `shred_alias_dice` is the Shred-FAMILY epoch gate
/// (`sim.rs` passes `rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES)`): the
/// unit-level alias stamp (`ShootProfile.shred_alias` — Destroyer/Infected/
/// Warbound and the two scoped halves) reaches the batch only at the current
/// epoch, so every pre-port corpus replays byte-exact.
///
/// `shred_low` is the ACTIVE save-fail window for THIS batch (the Shred
/// Boost's widened faces 1-2, precomputed by the volley behind its own
/// epoch-4 gate; 1 = the base window — melee resolves at 1, it never has a
/// distance to clear).
#[allow(clippy::too_many_arguments)]
fn save_batch(
    p: &ShootProfile,
    def: &Ctx,
    def_owner: &str,
    count: i64,
    defense: i64,
    ap: i64,
    shred_grant: bool,
    shred_alias_dice: bool,
    shred_low: i64,
    deadly_per_model: bool,
    tray: &mut Tray,
    out: &mut ShootResult,
) -> i64 {
    if count <= 0 {
        return 0;
    }
    // SHO-14 — Pierce drops the positive growth ladder and a buff's negative `defense_mod`.
    let pierce = pierce_ignores(p, def);
    let growth_def = if pierce { 0 } else { def.growth_def_mod };
    let defense_mod = if pierce && def.defense_mod < 0 { 0 } else { def.defense_mod };
    // Plain Fortified first (main.gd:6440-6447), then the WAVE 3 alias arm in
    // its ELSE — Boost ungated, gated aliases past the volley's over-9" flag,
    // both clamped at AP(0) like `fortified_ap`.
    let mut eff_ap = fortified_ap(ap, def.fortified);
    let mut fortified_rule = if def.fortified { "Fortified" } else { "" };
    let mut fortified_note = def.fortified && def.fortified_notes[0];
    if !def.fortified {
        let gated = if def.fortified_alias_over9 { def.fortified_alias_ap } else { 0 };
        let red = def.fortified_boost_ap.max(gated);
        if red > 0 && ap > 0 {
            eff_ap = (ap - red).max(0);
            out.fortified_fired = true;
            let boost = def.fortified_boost_ap >= gated;
            fortified_rule = if boost { def.fortified_boost_name } else { def.fortified_alias_name };
            fortified_note = def.fortified_notes[if boost { 1 } else { 2 }];
        }
    }
    // rules-wave3-growthmark (epoch 6) — the DEFENDER-side facets ride the
    // same save target: the +X-to-Defense ladder and Fortified Growth's
    // attacker-AP cut, floored at the hard 0 the rule prints. Both ctx
    // fields are zero unless `sim::ctx_live` folded them behind
    // `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`, so pre-epoch corpora
    // replay byte-exact.
    // SEAM 4 step 2 (epoch 7) — the ledger's `defense_mod` rides the SAME
    // rung: the stamp already carries the negated roll sum (a "+1 to
    // defense rolls" text lowers the rung, the covered/Shielded shape) and
    // the floor is the clamp the Shielded fold uses. Zero below epoch 7.
    //
    // Issue #854 (wave 4, `growth_def_lowers` stamped behind the FROZEN
    // `EPOCH_7_TABLE_RULES`) — the ladder's direction follows the table:
    // every defence part folds as `base = clampi(base - bonus, 2, 6)`
    // (main.gd:5510), so a "+1 to Defense rolls" LOWERS the target. The
    // clamp sits BEFORE the AP add because the table clamps the defence
    // STAT only (`base - bonus`); the AP is not part of the stat and rides
    // `save_target`'s own `+ ap.max(0)` afterwards. #853's roll bonus is
    // NOT part of the stat either — it folds onto the clamped base the way
    // it folds onto the raw one, floored at `BEST_HIT_TARGET`. Below 7 the
    // flag stays false and the wave-3 reading replays byte-exact.
    let target = if def.modifier_sum {
        // D21 (`EPOCH_68_MODIFIER_SUM`): every defence step arrives unfloored;
        // the SUM incl. AP is clamped once, a natural 1/6 stay with the die.
        save_target(defense - growth_def + defense_mod, (eff_ap + def.growth_fortify_ap).max(0)).clamp(2, 6)
    } else if def.growth_def_lowers {
        save_target(
            ((defense - growth_def).clamp(2, 6) + defense_mod).max(BEST_HIT_TARGET),
            (eff_ap + def.growth_fortify_ap).max(0),
        )
    } else {
        save_target(
            (defense + growth_def + defense_mod).max(BEST_HIT_TARGET),
            (eff_ap + def.growth_fortify_ap).max(0),
        )
    };
    let stat = if def.modifier_sum { defense - growth_def + defense_mod } else { target - (eff_ap + def.growth_fortify_ap).max(0) };
    if eff_ap < ap && !fortified_rule.is_empty() {
        // The table's line (`_solo_save_batch`), once per save batch whose AP the rule cut, before the threshold line.
        say_rule(tray, "fortified", def.side, || format!("{fortified_rule}: {def_owner} takes the hits at AP({eff_ap}) instead of AP({ap}) — saves on {}+{}", stat + eff_ap,
            if fortified_note { " (most of its models carry it)" } else { "" }));
    }
    // Fortified Growth's own cut composes with a Fortified above and says its own line after it (the table's `_solo_resolve_saves`,
    // NML-937): AP before = the AP the plain rule left, AP after = the floored sum, the Defense it then saves on, no "most models" note.
    if def.growth_fortify_ap != 0 && !def.growth_fortify_name.is_empty() {
        let after = (eff_ap + def.growth_fortify_ap).max(0);
        if after < eff_ap {
            say_rule(tray, "fortified", def.side, || format!("{}: {def_owner} takes the hits at AP({after}) instead of AP({eff_ap}) — saves on {}+",
                def.growth_fortify_name, stat + after));
        }
    }
    // One-core P3 step 25: the table's threshold line before the save dice (`_solo_log_save_threshold`,
    // main.gd:9823), from the stat and the AP `target` was built from (only modifier_sum clamps the sum).
    tray.say(|| {
        let a = (eff_ap + def.growth_fortify_ap).max(0);
        let d = stat;
        LogLine { rule: "save", category: Category::Combat, side: def.side,
            text: format!("{def_owner} saves on {}", save_threshold_text(d, a)), detail: None }
    });
    tray.owner_next(def.unit);
    let faces = tray.roll(count as usize);
    out.rolls.push(Roll {
        kind: "defense",
        count,
        target,
        faces: faces.clone(),
        owner: def_owner.into(),
    });
    let mut reroll: Vec<u8> = Vec::new();
    // Wave 4 — the widened window (0 = the base 6s-only leg, byte-exact):
    // successful unmodified saves from `bane_low` up re-roll too.
    // SHO-10: a re-roll entry's target condition shuts the whole window.
    let bane = p.bane && !out.bane_gated;
    let bane_from = if bane && out.bane_low > 1 { out.bane_low } else { 6 };
    if bane {
        let n = faces.iter().filter(|&&f| f == 6 || (f as i64 >= bane_from && f as i64 >= target)).count() as i64;
        if n > 0 {
            {
                // The table's line (rules-must-log), said before the re-roll dice like the table's: the rule is the unit-level facet, else the
                // weapon alias, else Lacerate alone, else plain Bane; a widened window names the Boost that opened it.
                let name: &str = if !p.bane_name.is_empty() { &p.bane_name } else if !p.bane_alias.is_empty() { &p.bane_alias }
                    else if crate::unit::lacerate_only(&p.rules) { "Lacerate" } else { "Bane" };
                let s = if n == 1 { "" } else { "s" };
                let line = if bane_from < 6 {
                    // the condition's words only on the widened form
                    format!("{}: {def_owner} re-rolls {n} unmodified Defense roll{s} of {bane_from}+{}", if p.bane_rule.is_empty() { name } else { p.bane_rule }, cond_ap_why(&p.bane_condition))
                } else {
                    format!("{name}: {def_owner} re-rolls {n} unmodified Defense 6{s}")
                };
                say_rule(tray, "bane", def.side, || line);
            }
            tray.owner_next(def.unit);
            reroll = tray.roll(n as usize);
            out.rolls.push(Roll {
                kind: "defense",
                count: n,
                target,
                faces: reroll.clone(),
                owner: def_owner.into(),
            });
            // AI-G2 rules-must-log: a weapon alias (Smash, Reap, Decimate) names its own book rule.
            if !p.bane_alias.is_empty() {
                let s = if n == 1 { "" } else { "s" };
                let what = if bane_from < 6 { format!("roll{s} of {bane_from}+") } else { format!("6{s}") };
                out.log.push(format!("{}: {def_owner} re-rolls {n} unmodified Defense {what}{}", p.bane_alias, cond_ap_why(&p.bane_condition)));

            } else {
                // The widened window's own share — the successful 5s the base leg
                // would never have touched (rules-must-log count).
                out.bane_rerolled += faces.iter().filter(|&&f| out.bane_low > 1 && f < 6 && f as i64 >= out.bane_low && f as i64 >= target).count() as i64;
            }
        }
    }
    let unsaved = (count - blocks_with_bane_from(&faces, &reroll, target, bane_from)).max(0);
    // SHO-15a/15b Scourge: the unmodified 1s on the FINAL faces (Shred's own read), counted, never landed.
    // The shooting morale trigger and the melee winner tally both read this one count.
    if p.rules.iter().any(|r| r.trim() == "Scourge") {
        out.scourge_wounds += shred_faces(&faces, &reroll, 1, target) * SCOURGE_PHANTOM_WOUNDS;
    }
    let shred = if p.shred || shred_grant || (p.shred_alias && shred_alias_dice) {
        // Wave 3: the per-face wound amount rides the profile's epoch-6
        // stamped `extra_wound_per_save_one` read (0 = unread -> the base
        // +1 the wave-1 alias arm hard-codes, byte-exact at every earlier
        // epoch). The firing names itself (rules-must-log) only when the
        // read actually rode along — every pre-epoch-6 corpus stays silent.
        let bonus = p.shred_ones_wound_bonus.max(1);
        let shreds = shred_faces(&faces, &reroll, shred_low.max(1), target);
        let wound = shreds * bonus;
        if shreds > 0 {
            // The table's line (`_solo_save_batch`): the widened window names its Boost, the plain one the rule that pays the 1s.
            let s = if shreds == 1 { "" } else { "s" };
            if shred_low > 1 {
                let gate = if p.shred_over_in < 0.0 { String::new() } else { format!(" (over {}\")", p.shred_over_in) };
                say_rule(tray, "shred", def.side, || format!("{}: Shred on failed saves of 1-{shred_low}{gate} — {shreds} extra wound{s}", p.shred_boost_name));
            } else {
                let name = if p.shred_name.is_empty() { "Shred" } else { p.shred_name.as_str() };
                say_rule(tray, "shred", def.side, || format!("{name}: {shreds} Defense roll{s} of 1 → +{shreds} wound{s}"));
            }
        }
        if wound > 0 && p.shred_ones_wound_bonus > 0 {
            out.log.push(format!(
                "Shred ({}): {} — {} failed save rolls cost {} extra wounds against {}",
                p.shred_ones_rule, p.shred_ones_owner, shreds, wound, def_owner));
        }
        wound
    } else {
        0
    };
    // Audit 2026-09-13 §2.1 — BOTH LEGS of the `EPOCH_14_DEADLY_LANDING` gate.
    // Below 14 (every pre-14 recording): the pool carries the multiply against
    // the unit's printed Tough, verbatim, and the landing spills. From 14 on:
    // the pool stays RAW — the multiply happens PER MODEL at the landing
    // (sim::land_deadly_wounds, the table's `apply_deadly_wounds`), and the
    // overkill never carries onto the next model.
    if deadly_per_model {
        unsaved + shred
    } else {
        let mult = if p.deadly > 0 { deadly_multiplier(p.deadly, def.tough.max(1)) } else { 1 };
        unsaved * mult + shred
    }
}

/// ONE shooting activation resolved on the tray, in the TABLE's draw order
/// (`main._solo_resolve_ai_volley` :3047, per shot, main.gd line in brackets):
///
///   hit dice [:3200] -> Hazardous reads those faces, draws nothing [:16555]
///   -> surge/extra-attack dice [:4454] -> the defender's saves as ONE batch
///   [:6448] -> Bane re-roll [:6463] -> (next weapon) -> Regeneration, pooled
///   over the whole volley [:6543/:6624] -> morale [:8313].
///
/// The stream is left standing exactly BEFORE the morale roll: morale, Fearless
/// and No Retreat are B5's, and drawing them here would shift every later
/// activation.
///
/// PORTED: the to-hit target (`profile_ev`'s shooting branch verbatim —
/// Reliable, the range/Stealth/Artillery/Evasive modifiers, Unstoppable's
/// clamp, Versatile Attack, Precise), the unmodified-6 bonus hits of Relentless
/// and Surge plus Surge's own gates (Point-Blank's within-12" cap, the Boosts'
/// successful 5s past 9" — epoch-3, ungated for pre-epoch records), block B6's
/// extra-ATTACK-DIE Surge siblings (Bloodborn / Primal /
/// Predator / Clan Warrior and their book aliases, `surge_attack_hits`), Blast,
/// the Rending/Destructive/on-6 AP sub-batch, Fortified, Shielded/Guarded/Cover
/// on the save target, Bane's re-roll, Shred, the per-model Deadly groups
/// (audit 2026-09-13 §2.1) and the pooled Regeneration roll.
///
/// PORTED SINCE THE DOOR PROBES — each measured EQUAL 16/16 on the AI body
/// against this door at epoch 88: the Stealth / Evasive / stationary data
/// aliases (`unit.rs::stealth_alias_of`, tests/dice/stealth_alias.rs), the
/// Fortified aliases Guardian / Primeborn (tests/dice/fortified.rs), Fortified
/// Growth's marker-driven AP (`EPOCH_6_TABLE_RULES`,
/// tests/sim/growth_markers_epoch6.rs), the unit-level Lacerate sixes re-roll
/// (`EPOCH_72_PLAYTEST_RULES`, `unit.rs::stamp_unit_strikers`), Instinctive
/// (tests/sim/instinctive.rs), Sergeant's bearer share
/// (tests/dice/g4r4_sergeant_scale.rs), the Takedown unit-of-[1] pick
/// (tests/dice/takedown_unit_of_one.rs) and the hero's own range gap
/// (`EPOCH_73_V36`, `att.member_gap_in`). The unit-level Bane re-roll rides
/// the same stamp; its Regeneration half diverges (below).
///
/// NOT PORTED OR DIVERGENT, by the door's measurement. Nothing here is a
/// silent skip: everything the trainer's own profile model can SEE is flagged
/// per activation in `unported`; everything below the line has no field to
/// detect it by and is listed instead.
///
/// FLAGGED (a counter per activation):
///   * `surge_gates` — LEGACY REPLAY ONLY since the epoch-3 surge-gates port:
///     the volley now reads the table's own gates off the profile
///     (`surge_within_in`, `surge_low`/`surge_over_in`, main.gd:4465-4482) and
///     flags nothing; every pre-epoch record keeps the ungated read. The
///     MELEE fold is the table's own 0.0" read and flags nothing either; only
///     its Bloodthirsty extra dice flag, when a sentinel low window's 5s go
///     unpaid there (main.gd:7128 pays them).
///   * `hazardous`   — Hazardous wounds the FIRER on its natural 1s (:16555).
///   * `deadly`      — LEGACY REPLAY ONLY: the activation carried a Deadly
///     weapon below `EPOCH_14_DEADLY_LANDING`, where the pooled multiply still
///     lands it (audit 2026-09-13 §2.1). From 14 the per-model landing IS the
///     table's and flags nothing (stage-0 P9: the tray tree declined every
///     Deadly activation on this flag alone).
///   * `takedown`    — resolved "as a unit of [1]" against a picked model, with
///     that model's own Defense (:3155).
///   * `strafing`    — the table splits a Strafing weapon per model (:2918).
///
/// STREAM-DESYNCING DRAWS: the two this list used to name are both PORTED and
/// roll in the table's own slot. The Unpredictable die, ONE per volley before
/// any weapon fires (:3114), came in block B12 for the SHOOTING leg
/// (`resolve_volley_with_tray`: the exact "Unpredictable"/"Unpredictable
/// Shooter" pair, never the melee-only Fighter); the MELEE leg was already in
/// `resolve_melee_with_tray` (block D1-B5a). The extra-ATTACK dice of the
/// Bloodborn/Primal/Predator/Clan Warrior family (:4454) came in block B6 —
/// see `surge_attack_hits`.
///
/// SHOT SELECTION AND SCALING (all of them change the die COUNT, which is the
/// largest divergence class the replay gate measures):
///   * per-model SIGHTING — the table scales attacks by `_solo_sighted_count`
///     (:4131), a per-model geometric LOS plus base-edge range gate
///     (:4283-4304); this port scales by `alive` through `effective_attacks`
///     (not re-measured on the door).
///   * PORTED in D1-B4b: attached HEROES fire as their own shots inside the
///     host's volley (:2954-2990), through `resolve_volley_with_tray`. With
///     `hero_attach="off"` the state carries no attachment at all, so that
///     path is never entered.
///   * PORTED in D1-B4b, for EVERY `dice="table"` volley and not only the ones
///     with a hero in them: the Takedown -> Deadly -> rest resolve-first sort
///     of the shot list (:3033-3040/:3052-3062). It is the table's order, it
///     changes which models die, and it moved the replay gate on its own
///     (87 -> 88 of 670 FULL-equal acts with no hero shots added) — a
///     deliberate B4 fidelity fix, declared rather than smuggled.
///   * per-copy bearer scaling of a weapon's carriers
///     (solo_controller.gd:457-467) — not measured on the door.
///
/// PORTED in NML-1150: SPLIT FIRE (:2996-3005) — one call of THIS function per
/// target group, in the table's group order, on the same tray (sim.rs builds
/// the groups from the act's `split` aim). A multi-member volley at ONE target
/// is not split fire and no longer raises any flag.
///
/// TO-HIT AND SAVE MODIFIERS — the measured state:
///   * Indirect's moved -1 (:3163-3169) — PORTED in the quick-readjustment
///     wave: the weapon's `indirect_moved_hit_penalty` stamp (the registry
///     `moved_hit_penalty`) folds -N into the to-hit sum whenever the
///     shooter moved this activation (Ctx::moved_this_round), unless the
///     unit carries "Quick Readjustment" (Ctx::quick_readjustment, the
///     `no_moved_penalty` opt-out) — both behind the FROZEN
///     `EPOCH_7_TABLE_RULES` (tests/dice/indirect_moved.rs). The GH #325
///     GRANTED-INDIRECT leg of main.gd:3220's gate has no attacker-side field
///     here, but needs none: the grant's sight waiver is stamped on the
///     profile (`unit.rs`, the `indirect` facet) and the table stops folding
///     the moved penalty itself at `EPOCH_73_V36`, so a granted-Indirect
///     volley measured EQUAL 16/16 with the target hidden behind a screen.
///   * Spot markers, Reckless AP, `AiEv.stamp_conditional_ap`
///     (Shatter / Tear / Disintegrate) — not measured on the door. The
///     Piercing tag PORTED in wave 3 (the marker pool + the `tag_ap_mod` fold
///     above); vs-target Marks PORTED in B2b (`tray_vs_marks`).
///   * unit-level Bane / Lacerate — the STRIKER's own special rules, not just
///     the weapon's (:6490-6500) — PORTED (`EPOCH_72_PLAYTEST_RULES`,
///     `unit.rs::stamp_unit_strikers`): the sixes re-roll fires from the unit
///     rule alone, measured EQUAL 16/16 for Lacerate. DECLARED DIVERGENCE for
///     a plain unit-level `Bane`: the core also sets the Regeneration bypass
///     (`u_bypass`), the table's `_solo_ignores_regen` does not — measured
///     UNEQUAL 16/16, first difference the Regeneration roll (the table heals,
///     the core refuses).
///   * Vengeance and the charge-/terrain-/movement-gated Stealth/Evasive alias
///     shapes (auras, boosts, melee) — not measured on the door. The plain and
///     over-9" aliases themselves are PORTED (above). `Shot Modifier`
///     itself: PORTED for its three flat/over-9" carriers (block B4 — Good
///     Shot, Bad Shot, Targeting Visor; `unit.rs::stamp_shot_modifier`). The
///     melee-/charge-/terrain-scoped family members (Grounded Precision,
///     Precision Fighter/Charge Aura) are NOT — they never reach the shooting
///     branch this function resolves anyway (main.gd:5627-5636's
///     `all_attacks` / `melee_only` / `when: charge` gate keeps them out).
///
/// AND morale, Fearless and No Retreat (:8313-8342) — B5's, deliberately left
/// undrawn so the stream stands exactly where the table's morale roll begins.
///
/// `keep`/`attacks` are `shoot_ev`'s, so the range gate and the survivor
/// scaling are the ones the EV path already agreed on. NOTE: this path never
/// touches `State::wound_frac` — deliberately. The remainder carry is an
/// artefact of resolving a volley in EXPECTATION; real dice produce whole
/// wounds, so there is no sub-wound remainder to carry and no coin flip to
/// spend. A `dice="table"` game therefore leaves `wound_frac` wherever the
/// last expected-value activation (melee, spells — B5's) left it.
pub fn resolve_shooting_with_tray(
    profiles: &[ShootProfile],
    keep: &[usize],
    attacks: &[i64],
    att: &Ctx,
    def: &Ctx,
    dist_in: f64,
    tray: &mut Tray,
) -> ShootResult {
    let one = [Shooter { profiles, keep, attacks, att, owner: "" }];
    // Single-scalar convenience form (tests only — sim.rs's real caller
    // supplies the two distances separately): range gate and modifier gate
    // are the SAME point here. Assumes the shipped `cond_ap_dice=true` state
    // and the current rules epoch (both surge gates, the Shred-family alias
    // gate and the Shred Boost's epoch-4 gate on); a legacy-OFF test calls
    // `resolve_volley_with_tray` directly (see the RED/GREEN pairs below).
    resolve_volley_with_tray(&one, def, "", dist_in, dist_in, true, true, true, true, tray)
}

/// NML-1073 M5 D1-B4b — ONE member of a shooting activation's volley.
///
/// The table builds the shot list over `members = [unit] + unit
/// .get_attached_heroes()` (`main._run_ai_shooting` :2954-2958), one shot per
/// (member, ranged weapon), each stamped with THAT member's `quality` and its
/// own `alive`/`max` scaling (:2985-2990) — so a joined hero fires its own
/// guns, at its own Quality, under the host's activation, and signs the dice
/// with its own name (:3199-3200).
pub struct Shooter<'a> {
    /// The member's own ranged set (`UnitStatic::shoot`).
    pub profiles: &'a [ShootProfile],
    /// Indices into `profiles` that passed the range gate, in `profiles_of`
    /// order — which IS the member's weapon order, the table's build order.
    pub keep: &'a [usize],
    /// Survivor-scaled attack counts, index-parallel to `keep`.
    pub attacks: &'a [i64],
    /// The member's own shooting context (its Quality above all).
    pub att: &'a Ctx,
    /// The member's name, for `Roll::owner`.
    pub owner: &'a str,
}

/// The volley of `shooters` — the host first, then each attached hero — against
/// one defender, on one tray. Everything the single-shooter form documents
/// holds; the members are simply walked in the table's build order, and
/// Regeneration stays pooled over the WHOLE volley (`_solo_land_wounds` :6623),
/// not per member.
///
/// THE MEMBERS' measured state, now visible because the members are:
///
///   * The hero's RANGE: the LIVE door measures per member — `EPOCH_73_V36`,
///     `sim.rs`'s `hero_own_gap` stamps `att.member_gap_in` and the dice fold's
///     `reach_gate` prefers it — measured EQUAL 16/16 with the hero's 12"
///     pistol 14" off the target. The table measures per member
///     (`_solo_nearest_model_gap_in` :4370-4386); only the single-shooter
///     convenience wrapper below still gates every member by the host's one
///     `dist_in`.
///   * The Takedown SHOT bonus group (that family's "Takedown Shot" rule,
///     resolver wave A, main.gd:3046-3086) is STAMPED
///     (`unit.rs::stamp_takedown_shot_named`, `EPOCH_7_TABLE_RULES`,
///     tests/sim/feat_takedown_shot.rs) but measured UNEQUAL 16/16: the table
///     scales the bonus to one die per SIGHTED model of the carrier (a
///     synthetic `alive=1`/`max=1` profile handed `sighted` through
///     `effective_attacks`), this port rolls its own single `attacks` die
///     (`sim.rs::profiles_of`'s `extra_attack_q` arm). The first difference is
///     the die COUNT (8 vs 1), never the faces. Its once-per-game latch also
///     has no write-back through the door, so `feats_used` differs even on a
///     one-model carrier. Its MELEE sibling "Takedown
///     Strike" left this note in the wave-4 follow-up port: the stamp appends
///     the synthetic limited melee profile (unit.rs
///     `stamp_takedown_strike_named`) and the melee fold rolls it at its own
///     Quality through the existing `limited_used` ledger — see that
///     function's own doc.
///
/// SORT STABILITY, the one caveat on the order below: Godot's `sort_custom`
/// is an introsort whose quicksort half only engages above 16 elements
/// (`SortArray::__introsort_loop`, INTROSORT_THRESHOLD), below which the final
/// insertion sort leaves equal-priority shots where they were. `sort_by_key` is
/// stable ALWAYS, so a volley of more than 16 shots may order its equal-priority
/// shots differently from the table's. Measured: 16 and 17 equal-priority shots
/// stayed EQUAL 16/16, 20 shots came out UNEQUAL 16/16 — the table led with the
/// second weapon of the build order, this port kept the build order (same batch
/// multiset, same end state; the gate reads it as a `kind`/`count` part).
///
/// DEADLY'S TWO LEGS (audit 2026-09-13 §2.1, `EPOCH_14_DEADLY_LANDING`): this wrapper is the
/// LEGACY leg (the pool carries the multiply against the unit's printed Tough, verbatim, and the
/// landing spills — byte-exact for every corpus recorded at 13 or below); `resolve_volley_leg(.., true)`
/// is the 14+ per-model leg. sim.rs's call sites pick by `rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING)`.
pub fn resolve_volley_with_tray(
    shooters: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    dist_in: f64,
    mod_dist_in: f64,
    cond_ap_dice: bool,
    surge_gates: bool,
    shred_alias_dice: bool,
    shred_boost_dice: bool,
    tray: &mut Tray,
) -> ShootResult {
    resolve_volley_leg(shooters, def, def_owner, dist_in, mod_dist_in, cond_ap_dice, surge_gates, shred_alias_dice, shred_boost_dice, false, false, &|_| false, &|_, _| None, tray)
}

/// `EPOCH_94_PARITY_BATCH`: the caller's landing of one weapon's Deadly groups on a scratch state; answers the models the target's chain
/// still has (0 = wiped).
pub(crate) type InlineLand<'a> = &'a mut dyn FnMut(&[(i64, i64)]) -> i64;
/// The Takedown pick callback: after `groups`, (the next pick in cover, its label, models the groups killed so far).
pub(crate) type TakedownPickInfo<'a> = &'a dyn Fn(&[i64]) -> (bool, String, i64);

/// The table's resolve-first rank of a shot (`_solo_shot_priority`): Takedown, then Deadly, then the rest.
pub fn shot_rank(p: &ShootProfile) -> u8 {
    if p.takedown {
        0
    } else if p.deadly > 0 {
        1
    } else {
        2
    }
}

// The leg split adds one gate-bool to the resolver's existing pack.
#[allow(clippy::too_many_arguments)]
pub fn resolve_volley_leg(
    shooters: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    dist_in: f64,
    mod_dist_in: f64,
    cond_ap_dice: bool,
    surge_gates: bool,
    shred_alias_dice: bool,
    shred_boost_dice: bool,
    deadly_per_model: bool,
    takedown_exact: bool,
    takedown_cover: &dyn Fn(&[i64]) -> bool,
    // One-core P3 step 27: (shooter index, profile index) -> (models with range and sight, models alive), the hit
    // line's "(n/m models sighted)" part; asked only when that line is said (a tray with a feed). Step 42d: and why the
    // weapon would stay silent (the table's reason).
    sighted: &dyn Fn(usize, usize) -> Option<(i64, i64, &'static str)>,
    tray: &mut Tray,
) -> ShootResult {
    resolve_volley_with_pick_label(shooters, def, def_owner, dist_in, mod_dist_in, cond_ap_dice, surge_gates,
        shred_alias_dice, shred_boost_dice, deadly_per_model, takedown_exact,
        &|gr| (takedown_cover(gr), "trooper".into(), 0), sighted, None, None, &[], tray)
}

/// `resolve_volley_leg` whose Takedown pick callback also answers the picked model's label (the table's `_solo_model_label`),
/// for the door's Takedown lines.
#[allow(clippy::too_many_arguments)]
pub(crate) fn resolve_volley_with_pick_label(
    shooters: &[Shooter<'_>], def: &Ctx, def_owner: &str, dist_in: f64, mod_dist_in: f64,
    cond_ap_dice: bool, surge_gates: bool, shred_alias_dice: bool, shred_boost_dice: bool,
    deadly_per_model: bool, takedown_exact: bool, takedown_pick_info: TakedownPickInfo<'_>,
    sighted: &dyn Fn(usize, usize) -> Option<(i64, i64, &'static str)>,
    // `EPOCH_94_PARITY_BATCH`: asked after each Deadly weapon with the (unsaved, X) groups it pushed; the caller lands them on a scratch
    // copy of the state and answers how many models the target's chain has left (0 = wiped: the weapons still to fire then read `Ctx::wiped`).
    // `None` below 94.
    inline_land: Option<InlineLand<'_>>,
    // `EPOCH_95_PARITY_BATCH`: on the finished Deadly groups, is the target's chain dead? Its Deadly wounds left then roll no
    // ignore dice (the melee leg's `deadly_wipes`). `None` below 95.
    deadly_wipes: Option<&dyn Fn(&ShootResult) -> bool>,
    // The skirmish Blast spread: the living models of each enemy unit within the book's spread distance of the target
    // (`sim::blast_neighbours`). Empty = no spread, the plain multiply below.
    blast_spread: &[i64],
    tray: &mut Tray,
) -> ShootResult {
    let mut inline_land = inline_land;
    let mut wiped = false;
    let mut live_models: Option<i64> = None; // the target's models after the Deadly groups landed so far (inline mode only)
    let mut out = ShootResult::default();
    let (mut regenable, mut regen_proof) = (0i64, 0i64);
    // the wounds of bypass weapons that JOINED the pool (the target has no group named Regeneration): the table's `ignore only Regeneration` line counts them
    let mut regen_joined = 0i64;
    // PORTED — Unpredictable's SHOOTING leg :3096-3110: ONE die for the whole
    // volley, before any weapon fires, off the FIRST shooter's context. A face
    // at or under `low_roll_max` is +ap_bonus on every profile of this volley
    // (folded into the shot's AP below, the duplicate-profile leg of
    // main.gd:3188-3190), above it +hit_bonus to hit (main.gd:3180, folded
    // into the per-shot modifier sum). The melee-only "Unpredictable Fighter"
    // is stamped out of `Ctx::unpredictable_shooting` (unit.rs).
    let mut upr_ap = 0i64;
    let mut upr_hit = 0i64;
    let mut hero_upr: Vec<(usize, i64, i64)> = Vec::new(); // (shooter index, ap, hit): a joined hero's own die
    let mut versatile_made: Vec<(Option<usize>, (i64, i64))> = Vec::new(); // the picks made in this volley (`Ctx::versatile_defer`)
    // EPOCH_95_PARITY_BATCH: the die is owed only by a shooter with a weapon in reach (the loop's own range gate below);
    // a volley with none is no volley at the table ("no target in range or sight"), so no die. Below the epoch every shooter owes it.
    let fires = |sh: &Shooter<'_>| {
        !rule_on(sh.att.rules_epoch, crate::acts::EPOCH_95_PARITY_BATCH)
            || sh.keep.iter().any(|&pi| {
                let p = &sh.profiles[pi];
                let printed = p.range as f64 + p.reach_bonus_in.max(sh.att.granted_reach_in);
                let reach = if def.ranged_shrouding { shrouded_reach(printed, def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in) } else { printed };
                sh.att.strafe_volley || (p.range > 0 && reach + def.range_mark_in >= sh.att.member_gap_in.unwrap_or(dist_in).ceil())
            })
    };
    if shooters.first().is_some_and(|sh| sh.att.unpredictable_shooting && shooters.iter().any(&fires)) {
        let att0 = shooters[0].att;
        tray.owner_next(att0.unit);
        let faces = tray.roll(1);
        let low = (faces[0] as i64) <= att0.unpredictable_low_roll_max;
        if low {
            upr_ap = att0.unpredictable_ap_bonus;
        } else {
            upr_hit = att0.unpredictable_hit_bonus;
        }
        let (name, face, owner) = (att0.unpredictable_name, faces[0], shooters[0].owner);
        say_rule(tray, "unpredictable", att0.side, || format!("{name}: {owner}'s volley rolls {face} → {}", if low { "AP(+1)" } else { "+1 to hit" }));
        out.rolls.push(Roll {
            kind: "attack",
            count: 1,
            target: BEST_HIT_TARGET,
            faces,
            owner: shooters[0].owner.into(),
        });
    } else if shooters.first().is_some_and(|sh| sh.att.v36_rules) {
        // AIG-G2 R5 (EPOCH_73_V36): the host rolled none, so each joined hero who carries the rule himself rolls ONE
        // die for his OWN profiles, before any weapon fires. Table twin: `_solo_hero_unpredictable`.
        for (i, sh) in shooters.iter().enumerate().skip(1).filter(|(_, sh)| sh.att.unpredictable_shooting && fires(sh)) {
            tray.owner_next(sh.att.unit);
            let faces = tray.roll(1);
            let low = (faces[0] as i64) <= sh.att.unpredictable_low_roll_max;
            let (name, face, owner) = (sh.att.unpredictable_name, faces[0], sh.owner);
            say_rule(tray, "unpredictable", sh.att.side, || format!("{name}: {owner}'s volley rolls {face} → {}", if low { "AP(+1)" } else { "+1 to hit" }));
            hero_upr.push((i, if low { sh.att.unpredictable_ap_bonus } else { 0 }, if low { 0 } else { sh.att.unpredictable_hit_bonus }));
            out.rolls.push(Roll { kind: "attack", count: 1, target: BEST_HIT_TARGET, faces, owner: sh.owner.into() });
        }
    }
    // `dist_in` gates RANGE VALIDITY only (`reach_gate`, B11's edge/nearest-
    // model gap). `mod_dist_in` is the separate over-9" modifier distance:
    // unit centres for recorded epochs through 65 (NML-1152), nearest live
    // base gap from epoch 66, matching the table's AI volley.
    let reach_gate = dist_in.ceil();
    // Wave 3 — the Ranged-Shrouding clamp's own rules-must-log flag: set the
    // moment a profile's working reach actually drops below its raw range
    // (dice.rs `ShootResult.log` precedent), one line per volley below.
    let mut shroud_shortened = false;
    // Wave 3 — the Indirect family's rules-must-log flag: set the moment an
    // alias-marked profile's cover skip actually lands on an in-cover target
    // (`shroud_shortened`'s shape) — one line per volley below.
    let mut alias_cover_logged = false;
    // Rules 3.6 (SHO-01b) — the kept-cover line's once-per-volley flag.
    let mut indirect_cover_logged = false;
    // I4 (table `cover_logged`): the plain "is in cover" line, said once per volley and only when a save really used the cover.
    let mut cover_logged = false;
    // Rules 3.6 (SHO-14) — the Pierce line's once-per-volley flag.
    let mut pierce_logged = false;
    // The weapons whose Indirect already said it lifts the sight-blocker cover (one line per weapon).
    let mut screen_lift_logged: Vec<String> = Vec::new();
    // Wave 3 — the Shot Modifier family's two runtime-gated members name
    // themselves once per volley per firing member (rules-must-log): the
    // member's owner, its hit bonus and (Mobile Artillery only) its own
    // `over_in` gate, as first fired.
    let mut ma_fired: Vec<(&str, i64, f64)> = Vec::new();
    // Wave 4 (port-entrenched) — the stationary alias's rules-must-log flag.
    let mut ent_fired = false;
    // SHO-06 (rules 3.6) — the target-side Artillery penalty's rules-must-log flag.
    let mut target_art_fired = false;
    let mut gp_fired: Vec<(&str, i64)> = Vec::new();
    // Wave 4 (port-quick-readjustment) — the moved-penalty legs' once-per-
    // member rules-must-log flags (`ma_fired`'s shape).
    let mut im_fired: Vec<&str> = Vec::new();
    let mut qr_fired: Vec<&str> = Vec::new();
    // Wave 4 — the evasive Boosts' once-per-volley rules-must-log flag (the
    // defender-side alias marker, the alias_cover_logged shape); the RULE
    // that fired is `def.evasive_alias_name` ("Machine-Fog Boost" at epoch 6,
    // "Empyrean Spirit Boost" at epoch 7).
    let mut evasive_boost_fired = false;
    // EPOCH_73_V36 — the Aircraft to-hit penalty's once-per-volley log flag.
    let mut aircraft_fired = false;
    // The table's "Reliable: ... shoots at Quality N+" line, once per volley (`reliable_logged`).
    let mut reliable_said = false;
    // The table's `warbound_logged`: the widened Shred window names itself once per volley.
    let mut shred_announced = false;
    // Rules 3.6 (D-MOST) — Stealth's -1 rode the most-models read: one line per volley.
    let mut stealth_most_fired = false;
    // FAB-C15 — the once-granted Stealth's own rules-must-log flag.
    let mut stealth_grant_fired = false;
    // SHO-05 (rules 3.6) — the Artillery shooter's gated +1 names itself once per
    // firing member (the `ma_fired` shape).
    let mut art_shooter_fired: Vec<&str> = Vec::new();
    // Wave 4 — and the widened Bane window's own rule name, sticky once a
    // weapon opened it ("Mischievous Boost" at epoch 6, "Bestial Boost" at
    // epoch 7); "" = the base 6s-only window fired nothing.
    let mut bane_rule = "";
    // SHO-10 — the words naming the target condition that opened the window.
    let mut bane_why = "";
    // Wave 3 — the Shielded-family alias's own rules-must-log flag: the +1
    // rode a family DATA alias rather than the literal name, one line per
    // volley below (`ShootResult.log` precedent).
    let mut shielded_alias_fired = false;
    let mut defense_token_fired = false;
    // WAVE 3 — the aliases' over-9" SAVE gate (main.gd:3090/6415), ONCE per
    // volley on this local copy; non-volley paths leave it false — the
    // table's own reading (melee `dist_in: -1.0`, :6119). Stamp-gated.
    // MOR-17a (rules 3.6): Warding's 6+ needs a shot from OVER its gate — inside it the 6+ die of this kind never rolls. Alone it takes the whole
    // fold with it (the old reading); beside other groups (`Ctx::regen_gated`) only its own group drops out.
    let gate_on = def.gate_in_force();
    let gate_shut = gate_on && def.regen_gate_over_in > 0.0 && mod_dist_in <= def.regen_gate_over_in;
    let def = &{
        let c = Ctx {
            fortified_alias_over9: def.fortified_alias_ap > 0
                && def.fortified_alias_over_in > 0.0
                && mod_dist_in > def.fortified_alias_over_in,
            ..*def
        };
        if gate_shut { c.gate_shut() } else { c.open_named(mod_dist_in, false) }
    };
    let def_live: &Ctx = def;
    let def_wiped: Ctx = if inline_land.is_some() { def_live.wiped() } else { *def_live };
    // FLATTENED on purpose: one pass over the (member, profile) pairs, so the
    // body below stays the single-shooter one.
    //
    // ORDER — `_solo_resolve_ai_volley` :3052-3062, GF v3.5.1 p.14: "Takedown
    // attacks must be resolved before other weapons" and "Hits from Deadly must
    // be resolved first", the ladder `_solo_shot_priority` :3033-3040 spells
    // out. It runs over the WHOLE shot list, host and heroes together, which is
    // why an attached hero's Deadly gun fires before the host's plain rifles.
    // `sort_custom` on a volley-sized array is Godot's final insertion sort and
    // therefore stable, so equal-priority shots keep the build order (the host's
    // weapons, then each hero's) — `sort_by_key` is stable and is the twin.
    let mut shots: Vec<(&Shooter<'_>, usize, usize)> = shooters
        .iter()
        .flat_map(|sh| sh.keep.iter().enumerate().map(move |(k, &pi)| (sh, k, pi)))
        .collect();
    shots.sort_by_key(|&(sh, _, pi)| shot_rank(&sh.profiles[pi]));
    if !def.guarded_said && !shots.is_empty() {
        say_guarded(tray, def, def_owner, mod_dist_in);
    }
    if def.ranged_shrouding && !shots.is_empty() {
        // The table's line (`_solo_resolve_ai_volley`), once per volley whether or not a weapon was shortened.
        say_rule(tray, "shroud", def.side, || format!("{}: {def_owner} — weapon ranges against it {}\" shorter (min {}\")",
            def.ranged_shroud_name, def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in));
    }
    let n_shots = shots.len();
    for (sh, k, pi) in shots {
        let def: &Ctx = if wiped { &def_wiped } else { def_live };
        let att = sh.att;
        let p = &sh.profiles[pi];
        // The member's own die when a joined hero rolled one (AIG-G2 R5), else the unit's (the host's) die.
        let (upr_ap, upr_hit) = hero_upr
            .iter()
            .find(|h| std::ptr::eq(&shooters[h.0], sh))
            .map_or((upr_ap, upr_hit), |h| (h.1, h.2));
        let reach_gate = att.member_gap_in.map_or(reach_gate, f64::ceil);
        // Rules 3.6: the shooter's own range grant rides the PRINTED range, the target-side shrink
        // applies to the sum (main.gd: `base_range + range_bonus`, then `effective_shoot_reach_in`).
        let printed = p.range as f64 + p.reach_bonus_in.max(att.granted_reach_in);
        let mut reach = if def.ranged_shrouding {
            let r = shrouded_reach(printed, def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in);
            shroud_shortened |= r < printed;
            r
        } else {
            printed
        };
        // WAVE 3 MARK (`acts::rule_on` inside `ctx_live`, EPOCH_6_TABLE_RULES):
        // the target's live "+6\" shooting range" record extends the reach the
        // range gate tests — `ctx_of` (the EV imagination) leaves it 0.
        reach += def.range_mark_in;
        if !att.strafe_volley && (p.range <= 0 || reach < reach_gate) {
            continue;
        }
        if p.reach_bonus_in > 0.0 && (p.range as f64) < reach_gate && reach >= reach_gate {
            let line = format!("{}: {} gains +{:.0}\" reach on {}", p.reach_bonus_rule, sh.owner, p.reach_bonus_in, def_owner);
            say_rule(tray, "reach_bonus", att.side, || line.clone());
            out.log.push(line);
        }
        // The Mark names itself only where it was needed: a shooter the grant already carries is not its beneficiary.
        if def.range_mark_in > 0.0 && (p.range as f64) < reach_gate && reach >= reach_gate && reach - def.range_mark_in < reach_gate {
            let line = format!("Increased Shooting Range Mark: {} gains +{:.0}\" reach on {}", sh.owner, def.range_mark_in, def_owner);
            say_rule(tray, "range_mark", att.side, || line.clone());
            out.log.push(line);
        }
        let n = sh.attacks[k];
        if n <= 0 {
            // main.gd:3163 — a silent weapon leaves before any die; step 42d: one its models see says why, as the table
            // does (NML-1035). A weapon no model sees is not in the table's shot list at all.
            let seen = shooters.iter().position(|s| std::ptr::eq(s, sh)).and_then(|i| sighted(i, pi));
            if let Some((_, _, why)) = seen.filter(|s| s.0 > 0) {
                tray.say(|| LogLine { rule: "shoot", category: Category::Combat, side: att.side,
                    text: format!("{}: {} silent — {why}", sh.owner, p.name), detail: None });
            }
            continue;
        }
        // EPOCH_94_PARITY_BATCH, the table's `Simultaneous fire` line (SHO-PAR-F6): casualties since the declaration did not shrink this shot.
        if def.blast_models.zip(live_models).is_some_and(|(declared, live)| declared > live) {
            if let Some((seen, _, _)) = shooters.iter().position(|s| std::ptr::eq(s, sh)).and_then(|i| sighted(i, pi)) {
                say_rule(tray, "simultaneous", att.side, || format!("Simultaneous fire: {} fires {} as declared ({seen} model{} in range and sight before the first roll)",
                    sh.owner, p.name, if seen == 1 { "" } else { "s" }));
            }
        }
        // G4R4 C-GRANTED-BANE (`EPOCH_73_V36`): a live "Bane when Shooting" grant makes this ranged weapon a Bane
        // weapon for the volley (the table's `_solo_striker_has_bane`); the re-roll's log line names the book rule.
        let granted_bane;
        // EPOCH_96_PARITY_BATCH: the Mark also lifts a Bane-family weapon that does not ignore Regeneration (Lacerate) to full Bane.
        let p = if (att.bane_grant && !p.bane) || (att.bane_mark_grant && !(p.bane && p.bypass_regen)) {
            let alias = if p.bane { p.bane_alias.clone() } else if att.bane_grant { "Bane when Shooting".into() } else { "Bane Mark".into() };
            granted_bane = ShootProfile { bane: true, bypass_regen: true, bane_alias: alias, ..p.clone() };
            &granted_bane
        } else {
            p
        };
        // --- to-hit, `profile_ev` ai_ev.gd:335-370's shooting branch ---
        // FEAT PR 2 — the once-per-game bonus shot strikes at its OWN
        // Quality (main.gd:3100: `"quality": int(tgd.get("quality", 2))`),
        // never the member's; 0 = every ordinary profile, the Ctx quality
        // as always (the ranged twin of `melee_hit_target`'s override).
        let q = if p.extra_attack_q > 0 { p.extra_attack_q } else { att.quality };
        let target = reliable_quality(q, p.reliable);
        // Good Shot / Bad Shot / Targeting Visor (main.gd:5681-5701) — the
        // table's DICE path folds these in; `p.hit_bonus`/`p.hit_bonus_over9`
        // are this shot's own profile stamp (unit.rs::stamp_shot_modifier).
        // `def.stealth_alias_penalty`/`def.stealth_alias_over_in` are the
        // SAME dice path's Stealth data-alias leg (Changebound et al.,
        // main.gd:5588-5610/5698-5701) — `unit.rs::stealth_alias_of`.
        // Wave 4 (port-entrenched) — resolve the effective pair in the CALLER
        // (main.gd:5694-5702): stationary only while the target is UNMOVED,
        // larger penalty wins; zero below the FROZEN gate.
        let mut alias_pen = def.stealth_alias_penalty;
        let mut alias_over = def.stealth_alias_over_in;
        let mut alias_name = def.stealth_alias_name;
        if def.stationary_alias_penalty > alias_pen && def.moved_round != def.round {
            alias_pen = def.stationary_alias_penalty;
            alias_over = def.stationary_alias_over_in;
            alias_name = def.stationary_alias_name;
            if !ent_fired {
                ent_fired = true;
                out.log.push(format!(
                    "[{}] -{alias_pen} to hit over {alias_over:.0}\" vs {def_owner}: unmoved this round",
                    def.stationary_alias_name
                ));
            }
        }
        // SHO-05 (rules 3.6): the shooter's own +1 needs a Hold and a target past
        // `shooter_over_in`; both stamp 0/false below EPOCH_73_V36, so older
        // epochs keep the shared over-9" gate alone.
        let v36_artillery = att.artillery_shooter_needs_hold || att.artillery_shooter_over_in > 0.0;
        let art_gate_ok = (!att.artillery_shooter_needs_hold || att.held)
            && (att.artillery_shooter_over_in <= 0.0 || mod_dist_in > att.artillery_shooter_over_in);
        let art_bonus_val = att.artillery_shooter_hit_bonus.unwrap_or(crate::combat::ARTILLERY_SHOOTER_HIT_BONUS);
        let art_shooter_bonus = if art_gate_ok { art_bonus_val } else { 0 };
        // SHO-06 (rules 3.6): the target-side penalty is -1 past 12" and only while most models
        // carry the rule and the unit has not moved this round. Below the gate the old over-9"
        // -2 leg stays byte-exact.
        let v36_target_art = def.artillery_target_over_in > 0.0;
        let target_art = if v36_target_art {
            def.artillery_target_most_models && def.moved_round != def.round
        } else {
            def.artillery
        };
        let target_pen = if v36_target_art {
            def.artillery_target_hit_penalty_v36.unwrap_or(1)
        } else {
            def.artillery_target_hit_penalty.unwrap_or(crate::combat::ARTILLERY_TARGET_HIT_PENALTY)
        };
        let mut m = shooting_hit_modifier(
            mod_dist_in, att.artillery, def.stealth,
            if v36_target_art { false } else { target_art }, def.evasive,
            p.hit_bonus, p.hit_bonus_over9,
            alias_pen, alias_over,
            art_shooter_bonus,
            target_pen,
        )
            // B2b: the LIVE ledger's own nets — `_solo_hit_mod_info`
            // :5703-5709 adds the shooter's `_solo_spell_hit_mod` and the
            // target's `_solo_spell_hit_mod_vs` to the SAME `mod` that then
            // goes through ONE `modified_hit_target`. Kept apart from the
            // STATIC `p.hit_bonus` stamp above (#487): that one is baked per
            // weapon at build time, these two are per-activation records.
            + att.hit_mod
            + def.vs_hit_mod
            // Block B7 — Precision Frenzy: main.gd:5677-5680's marker-driven
            // hit bonus, shooting only (`_solo_hit_mod_info`'s melee branch
            // returns before that code runs).
            + att.growth_hit_mod
            // FEAT PR 3 — Precision Feat's once-per-game window (the volley
            // seam stamps it while the #827 latch is open): the entry's own
            // +1 to hit on EVERY shot of this activation.
            + att.feat_hit_bonus
            // Unpredictable's 4-6 half (main.gd:3180): folded into the SAME
            // sum, BEFORE the Unstoppable clamp, like the melee leg.
            + upr_hit
            // EPOCH_73_V36 — rules 3.6: a shot at an Aircraft is -N to hit,
            // inside the Unstoppable clamp (an enemy-side negative modifier).
            - def.aircraft_hit_penalty;
        if v36_target_art && target_art && mod_dist_in > def.artillery_target_over_in {
            m -= target_pen;
            if !target_art_fired {
                target_art_fired = true;
                out.log.push(format!(
                    "Artillery target: -{target_pen} to hit over {:.0}\" (most models, unmoved)",
                    def.artillery_target_over_in
                ));
            }
        }
        aircraft_fired |= def.aircraft_hit_penalty > 0;
        if att.artillery && v36_artillery && mod_dist_in > LONG_RANGE_IN
            && art_shooter_fired.iter().all(|o| *o != sh.owner)
        {
            art_shooter_fired.push(sh.owner);
            let over = att.artillery_shooter_over_in;
            let line = if art_gate_ok {
                format!("Artillery: +1 to hit (held, target over {over:.0}in)")
            } else if !att.artillery_shooter_needs_hold || !att.held {
                format!("Artillery: no +1 to hit, {} moved", sh.owner)
            } else {
                format!("Artillery: no +1 to hit, target within {over:.0}in")
            };
            out.log.push(line);
        }
        // Wave 3 — the Shot Modifier family's runtime-gated members
        // (main.gd:5761-5779) ride the SAME sum: Mobile Artillery's
        // `requires_stationary` gate is the shooter's act-scope `moved`
        // flag (Ctx::moved_this_round), Grounded Precision's
        // `terrain_within_in` gate the core's own cover read (Ctx::in_cover).
        let ma = mobile_artillery_mod(att, mod_dist_in);
        let gp = grounded_precision_mod(att);
        m += ma + gp;
        if ma != 0 && ma_fired.iter().all(|(o, _, _)| *o != sh.owner) {
            ma_fired.push((sh.owner, ma, att.mobile_artillery_over_in));
        }
        if gp != 0 && gp_fired.iter().all(|(o, _)| *o != sh.owner) {
            gp_fired.push((sh.owner, gp));
        }
        // Wave 4 (port-quick-readjustment) — Indirect's moved to-hit penalty
        // (main.gd:3220-3224): a shooter that moved this activation takes
        // -`moved_hit_penalty` on every Indirect weapon, "Quick Readjustment"
        // (`no_moved_penalty`) waives it. Inside the Unstoppable clamp below,
        // like the table's own mod fold.
        let im = indirect_moved_mod(att, p);
        m += im;
        if im != 0 && im_fired.iter().all(|o| *o != sh.owner) {
            im_fired.push(sh.owner);
            out.log.push(format!("Indirect moved {im}: {} shoots after moving", sh.owner));
        } else if rule_on(att.rules_epoch, EPOCH_73_V36)
            && (p.indirect || def.indirect_mark) // a mark on the target makes the shot Indirect, as the table's profile bridge does
            && att.moved_this_round
            && im_fired.iter().all(|o| *o != sh.owner)
        {
            // Rules 3.6 (SHO-02): the non-application names itself (rules-must-log).
            im_fired.push(sh.owner);
            out.log.push(format!(
                "Indirect: no moved penalty: {} shoots after moving", sh.owner));
        } else if att.indirect_own && att.moved_this_round && im_fired.iter().all(|o| *o != sh.owner) {
            // EPOCH_94_PARITY_BATCH: an Indirect granted to the shooter's own unit makes every shot Indirect (`granted_indirect_of`).
            im_fired.push(sh.owner);
            out.log.push(format!("Indirect: no moved penalty: {} shoots after moving", sh.owner));
        }
        if im == 0
            && p.indirect_moved_hit_penalty > 0
            && att.moved_this_round
            && att.quick_readjustment
            && !rule_on(att.rules_epoch, EPOCH_73_V36)
            && qr_fired.iter().all(|o| *o != sh.owner)
        {
            qr_fired.push(sh.owner);
            out.log.push(format!(
                "Quick Readjustment: {} ignores the Indirect moved penalty", sh.owner));
        }
        let info_mod = m - upr_hit;
        // Wave 4 — the evasive Boost names itself once per volley: the
        // unconditional -1 rode this weapon's to-hit sum (the defender-side
        // alias marker, Ctx::evasive_alias).
        evasive_boost_fired |= def.evasive_alias;
        // EPOCH_73_V36 — Unstoppable ignores only the minus from OTHER sources; the shooter's own
        // rules' modifiers stay outside the clamp (0 below 73 = one clamp over the whole sum).
        let art = if att.artillery { art_shooter_bonus } else { 0 };
        let over9 = if mod_dist_in > LONG_RANGE_IN { p.hit_bonus_over9 + art } else { 0 };
        let own = if att.v36_rules { p.hit_bonus + over9 + att.growth_hit_mod + upr_hit + ma + gp + im } else { 0 };
        if (p.unstoppable || att.unstoppable_mark || att.unstoppable_aura) && own < 0 {
            out.log.push(format!("Unstoppable: {} keeps its own {own} to hit", sh.owner));
        }
        stealth_most_fired |= def.stealth_most_models && mod_dist_in > LONG_RANGE_IN;
        stealth_grant_fired |= def.stealth_grant && mod_dist_in > LONG_RANGE_IN;
        // EPOCH 34 UNSTOPPABLE MARK — the granted mark's CLAMP half: the
        // once-grant the mark seam leaves on the bearer (`ctx_live`'s
        // `unstoppable_mark`) counts like the weapon's own `p.unstoppable`,
        // the same grant the Regeneration split below already reads. The
        // rules-must-log line names the grant the one time the clamp actually
        // bites for it; a weapon's own flag stays silent as before.
        // The table's `_solo_unstoppable_fold` names the fold of a weapon's own Unstoppable, one line per weapon (the granted mark and aura
        // say theirs below). Same three shapes and wording; below EPOCH_73_V36 `own` is 0, so only the first shape can occur.
        if p.unstoppable {
            let rest = m - own;
            let fold = if own >= 0 {
                (rest < 0).then(|| "Unstoppable: negative to-hit modifiers ignored".to_string())
            } else if rest >= 0 {
                Some(format!("Unstoppable: own rules' {own} to hit kept"))
            } else {
                Some(format!("Unstoppable: {rest} to hit from other sources ignored, own rules' {own} kept"))
            };
            if let Some(text) = fold {
                say_rule(tray, "unstoppable_fold", att.side, || text);
            }
        }
        if (p.unstoppable || att.unstoppable_mark || att.unstoppable_aura) && m - own < 0 {
            if att.unstoppable_mark {
                out.log.push(format!(
                    "Unstoppable: {} — negative to-hit modifiers ignored (once)", sh.owner));
            }
            // EPOCH 37 UNSTOPPABLE AURA — rules-must-log, the clamp half: the
            // aura names itself the one time the clamp bites for it. The
            // melee fold never reads `unstoppable_aura`, so the line fires on
            // the shooting side only.
            if att.unstoppable_aura {
                out.log.push(format!(
                    "Unstoppable: {} — negative to-hit modifiers ignored (aura)", sh.owner));
            }
            m = own;
        }
        let unit_of_one = takedown_exact && p.takedown;
        let (td_own, td_label, _) = if unit_of_one {
            takedown_pick_info(&out.takedown_groups)
        } else {
            (false, String::new(), 0)
        };
        if unit_of_one {
            let rule = if p.takedown_rule.is_empty() { "Takedown" } else { p.takedown_rule.as_str() };
            say_rule(tray, "takedown", att.side, || format!(
                "{rule} ({}): targets the {td_label} in {def_owner} — resolved as a unit of [1]", p.name));
        }
        let (mut raw, mut target) = fold_hit(def.modifier_sum, target, m);
        if p.reliable && !std::mem::replace(&mut reliable_said, true) {
            say_rule(tray, "reliable", att.side, || format!("Reliable: {} shoots at Quality {target}+", sh.owner));
        }
        if (p.shred || p.shred_alias) && !shred_announced {
            if let Some((rule, low, widens)) = &p.shred_announce {
                shred_announced = true;
                say_rule(tray, "shred", att.side, || if *widens {
                    format!("{rule}: failed saves of 1-{low} count as wounds on {def_owner}")
                } else {
                    format!("{rule}: unmodified 1s to block deal an extra wound at any distance on {def_owner}")
                });
            }
        }
        let mut versatile_ap = 0;
        if (p.versatile_attack || att.versatile_grant)
            && (att.versatile_no_gate || mod_dist_in > LONG_RANGE_IN)
        {
            // Wave 3 — the "Vinci Tech Boost" form (`pick_one: false`,
            // stamped only under the frozen EPOCH_6_TABLE_RULES gate): BOTH
            // arms instead of the pick. The flag rides the same stamp the
            // generic buff rides, so a pre-epoch-6 record keeps the pick.
            // EPOCH_38_WATCHBORN_LATCH — a latched activation pick rides the
            // Ctx (sim::versatile_latch): ONE pick per activation, no
            // per-volley re-decision; the pick line was logged at the stamp.
            let (hit_mod, ap_mod) = if att.versatile_latched {
                (att.versatile_pick_hit, att.versatile_pick_ap)
            } else if p.versatile_both {
                (1, 1)
            } else if let Some(&(_, pick)) = versatile_made.iter().find(|(u, _)| *u == att.unit) {
                pick
            } else if att.versatile_defer {
                // EPOCH_94_PARITY_BATCH: the activation's first eligible shot decides on the number it rolls at (the table's
                // `to_hit` after every modifier), the Defense after the Guarded fold (`shot_base`) and AP with the Unpredictable bonus.
                let guarded = def.guarded && mod_dist_in > LONG_RANGE_IN && !def.sturdy_boost_gates_guarded;
                let best = versatile_best_mode(
                    target,
                    guarded_defense(shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), guarded, def.def_floor()),
                    p.ap + upr_ap,
                    p.bane,
                );
                // Step 22a (OD-2): the player's own pick (`versatile_mode:<unit>`) replaces the best mode; unanswered = the best mode.
                let pick = match tray.versatile_mode() { Some(true) => (0, 1), Some(false) => (1, 0), None => best };
                versatile_made.push((att.unit, pick));
                if let Some(mi) = att.unit {
                    out.versatile_picks.push((mi, pick.1 > 0));
                }
                let rule = if p.versatile_name.is_empty() { "Versatile Attack" } else { p.versatile_name.as_str() };
                crate::sim::say_versatile_pick(rule, &p.versatile_say_name, sh.owner, pick.1 > 0, att.side, &mut out.log, Some(&mut *tray), att.rules_epoch);
                pick
            } else {
                versatile_best_mode(
                    target,
                    shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()),
                    p.ap + upr_ap,
                    p.bane,
                )
            };
            versatile_ap = ap_mod;
            (raw, target) = fold_hit(def.modifier_sum, raw, hit_mod);
            // Rules-must-log — only the wave-3 NAMED family forms log (the
            // named arm's stamp); the generic stamps stay silent, so every
            // earlier epoch's replay is byte-identical. At 36 the latched
            // activation already named its pick at the stamp — once per
            // activation, never per volley.
            if !p.versatile_name.is_empty() && !att.versatile_latched && !att.versatile_defer {
                let what = if p.versatile_both {
                    "AP(+1) and +1 to hit"
                } else if ap_mod > 0 {
                    "AP(+1)"
                } else {
                    "+1 to hit"
                };
                out.log.push(format!(
                    "{}: {} on {}'s volley over 9\"",
                    p.versatile_name, what, sh.owner
                ));
            }
        }
        // Table's `_solo_log_hit_mod` (main.gd:5392, 9053-9058): once per shot after Reliable/Versatile,
        // right before the attack roll, whenever `hit_mod_worth_logging` holds (`info_mod != 0 || !note.is_empty()`).
        let base_hit_note = if tray.feed().is_some() && p.fixed_hits.is_none() {
            let target_art_applies = def.artillery && if v36_target_art {
                target_art && mod_dist_in > def.artillery_target_over_in
            } else {
                mod_dist_in > LONG_RANGE_IN
            };
            let (base_note, full_note) = compose_to_hit_note(
                att, def, p, mod_dist_in, alias_pen, alias_over, alias_name,
                art_gate_ok, art_bonus_val, target_art_applies, target_pen, ma, gp, im,
            );
            if info_mod != 0 || !full_note.trim().is_empty() {
                let aimed = tray.aimed.clone();
                say_rule(tray, "to_hit", att.side, || format!(
                    "To-hit vs {}: {full_note} → hits on {target}+", aimed.as_deref().unwrap_or(def_owner)));
            }
            base_note
        } else {
            String::new()
        };
        // Precise is NOT in the rolled target. `_solo_tray_roll` is handed the
        // plain `to_hit` (main.gd:3200) and `_solo_hits` applies the +1 when it
        // COUNTS (:4405-4406) — so the die count is scored one better while the
        // RECORDED target stays raw, which is what `dice.jsonl` carries.
        // A fixed-hits weapon (the Blast spread's neighbour leg) rolls no attack die: no faces, no attack roll.
        let faces = if p.fixed_hits.is_some() {
            Vec::new()
        } else {
            tray.owner_next(sh.att.unit);
            let faces = tray.roll(n as usize);
            out.rolls.push(Roll { kind: "attack", count: n, target, faces: faces.clone(), owner: sh.owner.into() });
            faces
        };
        let roll_mark = tray.feed().is_some().then(|| tray.mark());
        // AIG-G2: a weapon-borne Imprecise is Precise's mirror, the -1 read from `EPOCH_73_V36`.
        let imprecise = att.v36_rules && p.imprecise;
        let weapon_mod = p.precise as i64 - imprecise as i64;
        let count_target = if weapon_mod != 0 { fold_hit(def.modifier_sum, raw, weapon_mod).1 } else { target };
        if p.precise {
            out.log.push(format!("Precise: +1 to hit on {}'s volley", sh.owner));
            say_rule(tray, "precise", att.side, || "Precise: +1 to hit".into());
        }
        if imprecise {
            out.log.push(format!("Imprecise: -1 to hit on {}'s volley", sh.owner));
            say_rule(tray, "imprecise", att.side, || "Imprecise: -1 to hit".into());
        }
        if p.hazardous {
            let ones = faces.iter().filter(|&&f| f == 1).count() as i64;
            if ones > 0 {
                out.hazardous_self.push((sh.owner.to_string(), p.name.clone(), ones, p.blast.max(p.deadly).max(1), roll_mark));
            }
            out.mark("hazardous");
        }
        if p.strafing {
            out.mark("strafing");
        }
        if p.takedown {
            if takedown_exact {
                out.log.push(takedown_pick_line(p, def_owner)); // tray-exact S10, main.gd:4171's pick line
            } else {
                out.mark("takedown");
            }
            // Wave 4 (rules-wave4-renames): the UNIT-level name that stamped
            // the flag ("Takedown when Shooting") names itself here
            // (rules-must-log); a weapon's own Takedown tag carries no name
            // and stays as silent as every earlier epoch logged it.
            if !p.takedown_rule.is_empty() {
                out.log.push(format!("{}: Takedown on {}'s volley", p.takedown_rule, sh.owner));
            }
        }
        // FEAT PR 2 — "Takedown Shot" names itself once per game
        // (rules-must-log, the table's own log line at main.gd:17026-17028,
        // the melee fold's Takedown Strike leg shape).
        if p.extra_attack_q > 0 {
            out.log.push(format!(
                "{}: {} makes one extra attack at Quality {}+ with AP({}), Deadly({}), Takedown (once per game)",
                p.name, sh.owner, p.extra_attack_q, p.ap, p.deadly));
            say_rule(tray, "takedown_bonus", att.side, || format!(
                "{}: {} makes one extra attack at Quality {}+ with AP({}), Deadly({}), Takedown (once per game)",
                p.name, sh.owner, p.extra_attack_q, p.ap, p.deadly));
        }
        // --- `_solo_hits` :4404-4487 ---
        let mut hits = p.fixed_hits.unwrap_or_else(|| faces_to_hits(&faces, count_target as u8) as i64);
        if (p.relentless || att.relentless_grant) && mod_dist_in > LONG_RANGE_IN {
            hits += sixes(&faces);
            // The table's line, a Mark's grant names its source and the marked unit.
            if sixes(&faces) > 0 {
                let on = tray.aimed.clone().unwrap_or_else(|| def_owner.to_string());
                let from = if att.relentless_from.is_empty() { String::new() } else { format!(" — from {} on {on}", att.relentless_from) };
                say_rule(tray, "relentless", att.side, || format!("Relentless: +{} hit{} (unmodified 6s){from}",
                    sixes(&faces), if sixes(&faces) == 1 { "" } else { "s" }));
            }
        }
        let surge_before = hits;
        let mut surge_fives = 0;
        if p.surge {
            // SHO-18 (rules 3.6): a Surge ALIAS fires only from a shot over 9".
            let alias_fires = !p.alias_gate
                || p.surge_alias_rule.is_empty()
                || p.surge_over_in < 0.0
                || mod_dist_in > LONG_RANGE_IN;
            if surge_gates {
                // The table's own gates (main.gd:4465-4482): `surge_within_in`
                // (Point-Blank) caps the whole bonus at or under the centre
                // distance; a Boost adds successful unmodified 5s only PAST
                // `surge_over_in` — melee (0.0) never qualifies.
                if alias_fires && (p.surge_within_in <= 0.0 || mod_dist_in <= p.surge_within_in) {
                    hits += sixes(&faces) * p.bonus_hits_per_six.max(1);
                    if p.surge_low < 6 && mod_dist_in > p.surge_over_in {
                        surge_fives = faces.iter().filter(|&&f| f == 5 && count_target <= 5).count() as i64;
                        hits += surge_fives;
                    }
                    if !p.surge_alias_rule.is_empty() && sixes(&faces) > 0 {
                        if p.alias_gate && p.surge_over_in < 0.0 {
                            // Rules 3.6: a plain alias pays at any range, so its line names no 9in band.
                            out.log.push(format!("{}: bonus hits on unmodified 6s", p.surge_alias_rule));
                        } else {
                            out.log.push(format!(
                                "{}: shot from over {:.0}in — bonus hits on unmodified 6s",
                                p.surge_alias_rule, LONG_RANGE_IN));
                        }
                    }
                }
            } else {
                // LEGACY REPLAY ONLY — the ungated read, kept for every
                // pre-epoch record (epoch < 3), plus its divergence counter.
                hits += sixes(&faces) * p.bonus_hits_per_six.max(1);
                out.mark("surge_gates");
            }
        }
        if p.surge && hits > surge_before && surge_gates {
            // The table's lines (`_solo_hits`): the alias names its gate, then the plain total.
            let bonus = hits - surge_before;
            if !p.surge_alias_rule.is_empty() {
                let plain = p.alias_gate && p.surge_over_in < 0.0;
                say_rule(tray, "surge", att.side, || if plain { format!("{}: bonus hits on unmodified 6s", p.surge_alias_rule) }
                    else { format!("{}: shot from over {}\" — bonus hits on unmodified 6s", p.surge_alias_rule, LONG_RANGE_IN as i64) });
            }
            say_rule(tray, "surge", att.side, || format!("Surge: +{bonus} hit{} (unmodified {})",
                if bonus == 1 { "" } else { "s" }, if surge_fives == 0 { "6s" } else { "5-6s" }));
        }
        // Block B6 — the extra-ATTACK-DIE Surge siblings, ported (see the
        // helper's own doc). Draws its own tray slot right after Surge's,
        // matching `_solo_hits`'s order.
        // Wave 2 — a granted "Primal Boost", the same low-surge form (one group per member: `primal_extras`).
        hits += primal_extras(p, att.surge_grant && primal_grant_reaches(p, att.rules_epoch), rule_on(att.rules_epoch, EPOCH_73_V36), &faces, count_target, sh.owner, att.side, tray, &mut out);
        // EPOCH 44 SURGE MARK — the mark's once-grant ("Surge", placed by
        // `tray_vs_marks` at the attack seam, spent with the exchange) reads
        // against the marked target ONLY: +1 hit per unmodified 6, the plain
        // auto-hit form. Rules-must-log: the grant names itself when it fires.
        // Below 44 no such record exists (the recorded self-Surge replays
        // through `p.surge` alone).
        if att.surge_mark_grant {
            let mark_sixes = sixes(&faces);
            if mark_sixes > 0 {
                hits += mark_sixes;
                out.log.push(format!(
                    "Surge Mark: {} — +{} bonus hit{} on unmodified 6s against the marked target (once)",
                    sh.owner, mark_sixes, if mark_sixes == 1 { "" } else { "s" }));
                // The table's own words (`_solo_hits`): the mark's total replaces the plain Surge line.
                say_rule(tray, "surge_mark", att.side, || format!("Surge Mark: +{mark_sixes} hit{} (unmodified 6s) against the marked {def_owner} (once)", if mark_sixes == 1 { "" } else { "s" }));
            }
        }
        // `AiCombatMath.sergeant_bonus_hits` :493-494 — the bearer's unmodified
        // 6s, capped at its own attack share. The EV path values this
        // (combat.rs:339-342); the dice path must not be the poorer twin, even
        // though `stamp_sergeant` leaves the field at 0 in this port today.
        if p.sergeant_attacks > 0 {
            hits += sixes(&faces).min(p.sergeant_attacks);
        }
        // Tray-exact S8: a Takedown resolves as a unit of [1] — Blast has one model to spill onto
        // (main.gd `_solo_hits`, TC-023) and the save reads the pick's own square.
        if hits > 0 && p.blast > 1 && !blast_spread.is_empty() && !unit_of_one {
            let cap = def.blast_models.unwrap_or(def.models).max(1);
            let split = if rule_on(att.rules_epoch, crate::acts::PENDING_EPOCH_BLAST_EVEN) {
                // Step 29b (D-29-R1 "defender picks how"): the remainder goes where the target's owner says.
                let (base, caps, left) = blast_even_base(hits, p.blast, cap, blast_spread);
                let open: Vec<usize> = (0..base.len()).filter(|&i| base[i] < caps[i]).collect();
                let pick = if left > 0 && (left as usize) < open.len() { tray.blast_split_pick(&open, left as usize) } else { None };
                blast_give(base, &caps, left, pick.as_deref())
            } else {
                blast_split(hits, p.blast, cap, blast_spread)
            };
            let shooter = shooters.iter().position(|s| std::ptr::eq(s, sh)).unwrap_or(0);
            out.blast_spill.push(BlastSpill { shooter, profile: pi, hits: split[1..].to_vec() });
            let (kept, spread) = (split[0], split[1..].iter().sum::<i64>());
            let line = format!("Blast({}): {hits} hit{} -> {kept} on {def_owner}, {spread} on units within reach, {} lost",
                p.blast, if hits == 1 { "" } else { "s" }, hits * p.blast - kept - spread);
            out.log.push(line.clone());
            say_rule(tray, "blast", att.side, || line);
            hits = kept;
        } else if hits > 0 && p.blast > 1 {
            let cap = if unit_of_one { 1 } else { def.blast_models.unwrap_or(def.models).max(1) };
            let boosted = hits * p.blast.clamp(1, cap);
            if def.blast_models.is_some() {
                out.log.push(blast_log(p.blast, hits, boosted, cap, false));
            }
            let stale = def.blast_models.zip(live_models).is_some_and(|(declared, live)| declared > live);
            say_rule(tray, "blast", att.side, || blast_log(p.blast, hits, boosted, cap, stale)); // the table says it always (#169)
            hits = boosted;
        }
        // One-core P3 step 24: the table's line after `_solo_hits` (main.gd:5056-5057), a miss included; step 27: with
        // the table's sight part when not every model of the member sees the target (main.gd:5129).
        let aimed = tray.aimed.clone();
        tray.say(|| {
            let note = shooters.iter().position(|s| std::ptr::eq(s, sh)).and_then(|i| sighted(i, pi))
                .filter(|&(n, m, _)| n < m).map_or(String::new(), |(n, m, _)| format!(" ({n}/{m} models sighted)"));
            LogLine { rule: "shoot", category: Category::Combat, side: att.side,
                text: format!("{} fires {} at {}{note} — {hits} hit{}", sh.owner, p.name, aimed.as_deref().unwrap_or(def_owner), if hits == 1 { "" } else { "s" }),
                detail: None }
        });
        if hits <= 0 {
            continue; // :3210 — no hits, no save batch
        }
        // --- `_solo_resolve_saves` :6337-6376: the on-6 AP sub-batch first ---
        // The Shred Boost's widened window rides its own epoch-4 gate
        // (`shred_boost_dice`, sim.rs's `rule_on(seams.rules_epoch, 4)`
        // literal) plus the entry's own `over_in` distance — strictly past
        // 9", like every other over-9" read. `shred_low` 1 = the base window.
        let shred_low = if shred_boost_dice && p.shred_low > 1 && mod_dist_in > p.shred_over_in {
            p.shred_low
        } else {
            1
        };
        // Wave 4 — "Mischievous Boost"'s widened Bane window: strictly past
        // the entry's own over_in, the shred window's own volley gate shape.
        // 0 = the base 6s-only window; the melee resolve never sets it (its
        // save batches run on fresh results), so melee never widens — no
        // pre-charge gap (the shred2 precedent).
        // SHO-10: the re-roll entry's optional target condition, the SAME test the
        // conditional-AP leg runs; "" on every shipped entry keeps this byte-identical.
        out.bane_gated = !p.bane_condition.is_empty() && !cond_met(&CondAp { condition: p.bane_condition.clone(), threshold: p.bane_threshold, ..Default::default() }, &CondApTarget::of(def, p.range as f64), false, mod_dist_in, false);
        out.bane_low = if p.bane_low > 1 && mod_dist_in > p.bane_over_in && !out.bane_gated { p.bane_low } else { 0 };
        if out.bane_low > 1 {
            bane_rule = p.bane_rule;
            bane_why = cond_ap_why(&p.bane_condition);
        }
        let on6 = if p.on6_ap > 0 {
            p.on6_ap
        } else if p.rending || p.destructive || att.rending_grant {
            RENDING_AP_BONUS
        } else {
            0
        };
        let ap4 = if on6 > 0 { sixes(&faces).min(hits) } else { 0 };
        // Defense, in main.gd's own order: Shielded, then Guarded (over 9"),
        // then Cover — which Blast / Indirect / Ignores Cover skip (:3221).
        let pierce = pierce_ignores(p, att);
        let shielded_def = shielded_defense(def.defense, if pierce { 0 } else { def.shielded_bonus() }, def.def_floor());
        let mut base = shielded_def;
        // Audit 2026-09-13 §2.4 — the Sturdy-kind Boost REPLACES the base
        // rule's over-9" condition ("always ... instead of only when shot or
        // charged from over 9\" away"): while one of its aliases supplied the
        // shielded half, the guarded leg's MAX reading is already on the
        // table, so the second -1 must not stack (the Fortified pair's shape
        // at :329-333).
        let guarded_applies = def.guarded && mod_dist_in > LONG_RANGE_IN && !def.sturdy_boost_gates_guarded;
        base = guarded_defense(base, guarded_applies && !pierce, def.def_floor());
        shielded_alias_fired |= def.shielded && def.shielded_alias != ShieldedAlias::None;
        if !defense_token_fired {
            for l in defense_token_lines(def, def_owner) {
                say_rule(tray, "defense_part", def.side, || l);
            }
        }
        defense_token_fired = true;
        // Rules 3.6 (FAB-A3): an Indirect shot lifts cover granted by sight blockers only, so terrain cover
        // (`in_cover`) stays for it, held or not; the sight-blocker half (`screened`, from 95) is lifted per
        // weapon by `lifts_screen` below. Blast and Ignores Cover
        // keep dropping it at every epoch (`indirect_cover_needs_hold` is stamped only from
        // EPOCH_73_V36, so older records keep their unconditional skip).
        let indirect_keeps_cover = p.indirect && p.indirect_cover_needs_hold;
        let skips_cover = p.blast > 1 || p.ignores_cover || (p.indirect && !indirect_keeps_cover);
        // (`EPOCH_95_PARITY_BATCH`): cover from sight blockers (`def.screened`, stamped by the volley seam from 95
        // only) joins terrain cover as ONE +1; an Indirect whose cover waiver holds (Hold kept where the entry needs it) or the
        // Indirect mark on the target lifts it, and terrain cover stays.
        // A moved Indirect gun without the Hold its entry needs is not firing indirectly: no lift, mark or not (lead 21.11.).
        let lifts_screen = (p.indirect || (def.indirect_mark && rule_on(att.rules_epoch, EPOCH_73_V36)))
            && !(p.indirect_cover_needs_hold && !att.held);
        let in_cover = def.in_cover || (def.screened && !lifts_screen);
        let cov_def = covered_defense(base, if pierce { false } else if unit_of_one { td_own } else { in_cover }, def.def_floor());
        let save_def = if skips_cover { base } else { cov_def };
        if pierce && !pierce_logged {
            pierce_logged = true;
            let mut ign: Vec<String> = Vec::new();
            if def.shielded_bonus() > 0 { ign.push(format!("Shielded +{}", def.shielded_bonus())); }
            if !skips_cover && (if unit_of_one { td_own } else { in_cover }) { ign.push("Cover +1".into()); }
            if guarded_applies { ign.push("Guarded +1".into()); }
            if def.growth_def_mod > 0 { ign.push(format!("Defensive growth +{}", def.growth_def_mod)); }
            if def.defense_mod < 0 { ign.push(format!("Defense Buff +{}", -def.defense_mod)); }
            // tray twin: pierce
            if !ign.is_empty() { out.log.push(format!("Pierce: {} ignores {}", sh.owner, ign.join(", "))); }
        }
        // The table's Pierce line (`_solo_resolve_saves`, said for every weapon with hits to save, not once per volley): the weapon's name and
        // the target's positive Defense parts in `_solo_defense_parts` order (Shielded, growth ladder, spell token), then Cover.
        if pierce {
            say_pierce(tray, att.side, &p.name, def, if unit_of_one { td_own } else { def.in_cover || def.screened });
        }
        if unit_of_one {
            // Tray-exact S10 — `_solo_log_takedown_context`: the save the pick really rolls, and why.
            let why = if skips_cover { "cover ignored" }
                else if td_own { "in cover of its own" } else { "no cover of its own" };
            out.log.push(format!("Takedown ({}): the pick saves on {save_def}+ ({why})", p.name));
            say_rule(tray, "takedown", att.side, || {
                let mut parts = vec![format!("hits on {target}+")];
                if !base_hit_note.is_empty() { parts.push(base_hit_note.clone()); }
                parts.push(if !td_own { "no cover of its own".into() }
                    else if cov_def == base { format!("in cover, but Defense is already {}+", base.clamp(BEST_HIT_TARGET, 6)) }
                    else if save_def == cov_def { "in cover: +1 Defense".into() }
                    else { "in cover, but this weapon ignores cover".into() });
                if guarded_applies && !pierce && base != shielded_def {
                    let gn = if def.guarded_name.is_empty() { "Guarded" } else { def.guarded_name };
                    parts.push(format!("{gn}: +1 Defense"));
                }
                parts.push(format!("saves on {}+", save_def.clamp(BEST_HIT_TARGET, 6)));
                format!("Takedown ({}) vs the {td_label} of {def_owner} — unit of [1]: {}", p.name, parts.join(", "))
            });
        }
        // Wave 3 — rules-must-log: the unit-level Indirect names ("Indirect
        // when Shooting" / "Ignores Cover when Shooting", unit.rs build_for's
        // epoch-6 walk) stamp their skip with an `*_alias` marker, so the
        // volley names the RULE — not the weapon tag — the one time its cover
        // skip lands (`Ranged Shrouding`'s one-line shape). An epoch-5 static
        // carries no markers and stays silent.
        if !alias_cover_logged
            && (def.in_cover || def.screened)
            && skips_cover
            && p.blast <= 1
            && (p.indirect_alias || p.ignores_cover_alias || !p.cover_rule.is_empty())
        {
            alias_cover_logged = true;
            let rule = if !p.cover_rule.is_empty() {
                p.cover_rule.as_str()
            } else if p.ignores_cover_alias {
                "Ignores Cover when Shooting"
            } else {
                "Indirect when Shooting"
            };
            out.log
                .push(format!("{rule}: {} — {}'s cover save is skipped", sh.owner, def_owner));
        }
        // The door writes the tray's lines, not `out.log`. The table's AI-08a line (`_solo_resolve_ai_volley`): a weapon whose cover skip
        // is a named map-read rule says so for every shot that skips a cover the target really had (no once-per-volley latch, no
        // Blast, no Takedown pick), in its own words (the human volley's variant is the table half the one-core delete retires).
        if !unit_of_one && skips_cover && cov_def < base && p.blast <= 1 && !p.cover_rule.is_empty() {
            say_rule(tray, "cover_skip", att.side, || format!("{}: {} ignores {def_owner}'s cover (save skipped)", p.cover_rule, sh.owner));
        }
        // The table's `shot_uses_cover`: the save rolls at the covered Defense, and the cover really lowered it (a Defense already at
        // the floor, or a Pierce shot, leaves cover == base and the table says nothing).
        let uses_cover = cov_def < base && save_def == cov_def;
        // Rules 3.6 (FAB-A3) — rules-must-log: an Indirect shot's target KEEPS its terrain cover. A mark on the target makes the
        // shot Indirect on the table (profile bridge, `def.indirect_mark`): its cover counts, so the line is said for it too.
        let marked_indirect = def.indirect_mark && !p.indirect && rule_on(att.rules_epoch, EPOCH_73_V36);
        if !indirect_cover_logged && (indirect_keeps_cover || marked_indirect) && uses_cover && p.blast <= 1 {
            indirect_cover_logged = true;
            out.log.push(format!(
                "Indirect: {} — {}'s cover counts (only sight-blocker cover is ignored)",
                sh.owner, def_owner));
            say_rule(tray, "cover_kept", def.side, || format!(
                "Indirect: {} — {def_owner}'s cover counts (only sight-blocker cover is ignored)", sh.owner));
        }
        if def.screened && lifts_screen && !skips_cover && !screen_lift_logged.contains(&p.name) {
            screen_lift_logged.push(p.name.clone());
            out.log.push(format!("Indirect: {} ignores {def_owner}'s cover from sight blockers", p.name));
            say_rule(tray, "cover_screen_lift", def.side, || format!("Indirect: {} ignores {def_owner}'s cover from sight blockers", p.name));
        }
        // I4 (table `_solo_ai_shoot` / the human volley): a covered save says so once, with the Defense it rolls on.
        if !unit_of_one && !cover_logged && uses_cover {
            cover_logged = true;
            out.log.push(format!("{def_owner} is in cover: +1 Defense (saves on {}+)", save_def.clamp(BEST_HIT_TARGET, 6)));
            // The door writes the tray's lines, not `out.log` (the recorded log): without this the human and AI doors said no cover line.
            say_rule(tray, "cover", def.side, || format!("{def_owner} is in cover: +1 Defense (saves on {}+)", save_def.clamp(BEST_HIT_TARGET, 6)));
        }
        // Block B7 — Piercing Growth: main.gd:4287's marker-driven AP delta,
        // shooting and melee both (`_solo_attack_groups` adds it to `prof
        // ["ap"]` regardless of which the caller built profiles for).
        let mut ap = p.ap + upr_ap + versatile_ap + att.growth_ap_mod
            // Ambush family (rules-wave2-ambush): "Ambushing Piercing Shot"'s
            // arrival-round AP(+1) — SHOOTING only, the melee fold at :992
            // never reads it (its own facet gate).
            + att.ambush_arrival_ap
            // Wave 3 — Piercing Tag's spent markers: +AP(markers) on THIS
            // volley only (main.gd:3123/:9857), stamped by the tray seam
            // after the pool zeroes (sim.rs). The melee fold never reads it —
            // the table's melee seams have no tag spend — and the EV
            // imagination stays blind, the table's own resolve-time spend.
            + att.tag_ap_mod
            // Wave 4 follow-up — Reckless Piercing's round stamps
            // (main.gd:9877): the chain's buff stamp and the TARGET's
            // backfire stamp, epoch-7-gated at the sim seams that set
            // `Ctx::reckless_ap`.
            + att.reckless_ap
            // FEAT PR 3 — Piercing Feat's once-per-game window (the volley
            // seam stamps it while the #827 latch is open): AP(+1) on every
            // attack of this activation, the `any_attack` condition's own
            // reading.
            + att.feat_ap_bonus
            // SEAM 4 step 2 (epoch 7) — Piercing Debuff's "loses AP(+1) when
            // attacking": the DEBUFFED unit's own volley rides `ap_mod` one
            // lower, floored like every AP sum by save_target's `max(0)`.
            + att.ap_mod;
        // Wave 2 — the "AP(+1) when shooting" mark's flat AP, off its
        // epoch-gated Ctx leg (`sim::ctx_live`).
        if att.pierce_shooting_grant {
            ap += 1;
        }
        // Rung I (audit 2026-09-02, DEFECT_LEDGER row 31) — the SAME `cond_ap`
        // fold `profile_ev` uses (combat.rs) now reaches the dice save target
        // too, gated by `Knobs::cond_ap_dice` (absent/OFF replays every
        // pre-PR corpus unchanged). Shooting never charges, so `is_charging`
        // is false here; the `ranged_over`/`ranged_over_or_charge` gates read
        // `mod_dist_in`, the NML-1152 modifier-distance split, not the plain
        // range gap.
            let cap = CondApTarget { shooter_held: att.held, ..CondApTarget::of(def, p.range as f64) };
            if cond_ap_dice {
            for c in &p.cond_ap {
                let d = conditional_ap_bonus_vs(c, &cap, false, mod_dist_in, false);
                ap += d;
                // Rules-must-log: the wave-3 NAMED forms log their own AP
                // (rule, unit, what changed). The generic pass's specs carry
                // no name — old replays log nothing, byte-identical. A rules
                // 3.6 spelling is named at the stamp and adds its condition.
                // SHO-20: the 3.6 Slayer gate names the Hold (or says why it
                // was switched off); the pre-73 spelling stays silent.
                if c.gate == "hold_or_charge" {
                    if d > 0 {
                        out.log.push(format!("Slayer: AP(+{}) because {} held", d, sh.owner));
                        say_rule(tray, "slayer", att.side, || format!("Slayer: AP(+{}) because {} held", d, sh.owner));
                    } else if !att.held && (att.v36_rules || mod_dist_in > c.over_in)
                        && c.condition == "vs_tough_ge" && def.tough.max(1) >= c.threshold
                    {
                        out.log.push(format!("Slayer: no AP, {} moved", sh.owner));
                        say_rule(tray, "slayer", att.side, || format!("Slayer: no AP, {} moved", sh.owner));
                    }
                } else if d > 0 && !c.name.is_empty() {
                    out.log.push(format!("{}: AP(+{}) on {}'s volley{}", c.name, d, sh.owner, cond_ap_why(&c.condition)));
                    say_rule(tray, "cond_ap", att.side, || format!("{}: AP(+{}) against {def_owner}{}", c.name, d, cond_ap_why(&c.condition)));
                } else if d > 0 && !c.say_name.is_empty() {
                    // H-17a: the generic pass's rules (Disintegrate, Tear, ...) say the table's line; `out.log` stays as it was.
                    say_rule(tray, "cond_ap", att.side, || format!("{}: AP(+{}) against {def_owner}", c.say_name, d));
                }
            }
            // The table's conditional-AP part of the Piercing Feat and its Mark line, after the weapon's own (`_solo_resolve_saves`).
            if att.feat_ap_bonus > 0 {
                say_rule(tray, "cond_ap", att.side, || format!("Piercing Feat: AP(+{}) against {def_owner}", att.feat_ap_bonus));
            }
            if att.pierce_shooting_grant {
                say_rule(tray, "mark", att.side, || format!("Piercing Mark: friendly attackers get AP(+1) against {def_owner} (once)"));
            }
            // Wave 2 — the Slayer mark's granted conditional (epoch-gated).
            if att.slayer_grant {
                let mut spec = slayer_grant_cond();
                if att.v36_rules {
                    spec.gate = "hold_or_charge".to_string();
                }
                let d = conditional_ap_bonus_vs(&spec, &cap, false, mod_dist_in, false);
                ap += d;
                if att.v36_rules {
                    if d > 0 {
                        out.log.push(format!("Slayer: AP(+{}) because {} held", d, sh.owner));
                        say_rule(tray, "slayer", att.side, || format!("Slayer: AP(+{}) because {} held", d, sh.owner));
                    } else if !att.held && (att.v36_rules || mod_dist_in > spec.over_in) && def.tough.max(1) >= 3 {
                        out.log.push(format!("Slayer: no AP, {} moved", sh.owner));
                        say_rule(tray, "slayer", att.side, || format!("Slayer: no AP, {} moved", sh.owner));
                    }
                }
            }
        }
        say_growth_ap(tray, att, sh.owner);
        let normal = hits - ap4;
        // SHO-18 (rules 3.6): a Shred ALIAS fires only from a shot over 9".
        let shred_alias_fires = shred_alias_dice
            && (!p.alias_gate || p.shred_any_distance || mod_dist_in > LONG_RANGE_IN);
        if p.alias_gate && p.shred_alias && shred_alias_fires && p.shred_ones_wound_bonus > 0 {
            let name: &str = if p.shred_ones_rule.is_empty() { "Shred" } else { p.shred_ones_rule.as_str() };
            if p.shred_any_distance {
                out.log.push(format!("{}: unmodified 1s take +1 wound at any distance", name));
            } else {
                out.log.push(format!("{}: shot from over {:.0}in — unmodified 1s take +1 wound",
                    name, LONG_RANGE_IN));
            }
        }
        // Rules 3.6 row MOR-12c: the bearer's share of the plain hits saves as
        // its own batch at AP(+sergeant_ap), the table's band (`main.gd:8372-8387`).
        // G4R4 C-SERGEANT-SCALE: the table stamps the share on the FULL-strength profile, before the sighted
        // scaling, so the share is a fraction of the weapon's whole attack pool (`p.attacks`), not of the
        // sighted dice `n` (the stamp exists only from `EPOCH_73_V36`, so below it nothing changes).
        let sgt_hits = sergeant_hits(p, p.attacks.max(n), normal, att);
        say_on6_ap(tray, p, att, ap4, on6);
        let mut w = save_batch(p, def, def_owner, ap4, save_def, ap + on6, att.shred_grant, shred_alias_fires, shred_low, deadly_per_model, tray, &mut out);
        if sgt_hits > 0 {
            let line = sergeant_line(p, sh.owner, sgt_hits);
            tray.say(|| LogLine { rule: "shoot", category: Category::Combat, side: att.side, text: line.clone(), detail: None });
            out.log.push(line);
            w += save_batch(p, def, def_owner, sgt_hits, save_def, ap + p.sergeant_ap, att.shred_grant, shred_alias_fires, shred_low, deadly_per_model, tray, &mut out);
        }
        w += save_batch(p, def, def_owner, normal - sgt_hits, save_def, ap, att.shred_grant, shred_alias_fires, shred_low, deadly_per_model, tray, &mut out);
        // `_solo_ignores_regen` :6927-6933 — Bane / Rending (and Unstoppable,
        // ai_ev.gd:433) cut through Regeneration; everything else is poolable.
        // B2b: `_solo_ignores_regen`'s last line (main.gd:6941) also answers
        // for a LIVE "Unstoppable" grant — the Unstoppable Mark seam.
        // Audit 2026-09-13 §2.3 — the regen split reads the BYPASS flag, not
        // `bane`: the Bane-primitive aliases (Bestial, Mischievous, Scrapper,
        // Vicious) re-roll sixes but carry no Regeneration clause, so they
        // never join this proof. Pre-port records stamp both flags alike.
        // Audit 2026-09-13 §2.1 — on the 14+ leg a Deadly weapon's share is its
        // OWN group: its Regeneration roll draws on the RAW unsaved count (the
        // table's roll inside `_solo_land_deadly_wounds`, main.gd:6762), the
        // landing multiplies PER MODEL with no carry-over
        // (`apply_deadly_wounds`, solo_controller.gd:8333). The tally keeps the
        // raw count (`total_caused += w`, main.gd:3318). The legacy leg keeps
        // the pool multiply verbatim and lands through `land_wounds` as before.
        // EPOCH 46 DISINTEGRATE REGEN — the registry-driven weapon-rule
        // bypass joins the SAME seam the Bane family uses (`_solo_ignores_regen`'s
        // registry arm, main.gd:7133-7137): the stamp carries the rule NAME,
        // so an empty field is the pre-46 silence, replay-exact.
        let disintegrate_regen = !p.regen_bypass_rule.is_empty();
        let bypass_flag = p.bypass_regen
            || p.rending
            || p.unstoppable
            || att.rending_grant
            || att.unstoppable_grant
            || disintegrate_regen;
        let ignores_regen = bypass_flag && def.bypass_skips_ignore();
        // Rules-must-log: the refusal names the rule — the table's
        // Bane-in-Melee arm's own line (main.gd:7175-7176). DAT-16b: from rules 3.6
        // the line is written only when the target really has a Regeneration-family
        // roll to skip (the pool's own `regeneration` / `regen_target` seam); below
        // 73 the old line stays byte-identical for replay.
        if disintegrate_regen && w > 0
            && (!att.v36_rules || (def.regeneration && def.regen_target > 0 && def.bypass_skips_ignore()))
        {
            out.log.push(format!("{}: Regeneration ignored", p.regen_bypass_rule));
        }
        // The door's twin (`_solo_ignores_regen`, asked once per weapon with hits: a Deadly or Takedown weapon asks only when it dealt wounds,
        // a plain one always, even when every save held).
        let regen_asked = if p.deadly > 0 || (takedown_exact && p.takedown) { w > 0 } else { true };
        say_regen_bypass(tray, att.side, p, att, def, sh.owner, regen_asked);
        // EPOCH 34 UNSTOPPABLE MARK — rules-must-log, the Regeneration half:
        // the granted mark names itself the one time its bypass is the reason
        // this weapon's wounds skip the regen pool. Gated with the clamp half
        // (the stamp), so every pre-34 corpus replays its silent bypass.
        if ignores_regen && att.unstoppable_mark && w > 0 {
            // tray twin: anti_regen
            out.log.push(format!(
                "Unstoppable: {} — ignores {}'s Regeneration (once)", sh.owner, def_owner));
        }
        // EPOCH 37 UNSTOPPABLE AURA — rules-must-log, the Regeneration half on
        // the shooting side: the aura names itself the one time its bypass is
        // the reason this weapon's wounds skip the regen pool. The melee half
        // never fires from 37 (the melee read answers only non-shooting
        // scopes), so there is no melee twin.
        if ignores_regen && att.unstoppable_aura && w > 0 {
            out.log.push(format!(
                "Unstoppable: {} — ignores {}'s Regeneration (aura)", sh.owner, def_owner));
        }
        // Only the pooled LEGACY leg is a divergence: from EPOCH_14 the
        // per-model groups below land through `land_deadly_wounds`, the
        // table's own `apply_deadly_wounds` (and the tray tree declines on
        // every flag, stage-0 P9).
        if p.deadly > 0 && !deadly_per_model {
            out.mark("deadly");
        }
        let groups_before = out.deadly_groups.len();
        if takedown_exact && p.takedown {
            // Tray-exact S7 — the table's Takedown landing: w x max(Deadly, 1) BEFORE the
            // picked model's own Regeneration roll, all of it for that one model (the drain).
            let td = w * p.deadly.max(1);
            out.takedown_groups.push(ignore_batch(if ignores_regen { 0 } else { td }, if ignores_regen { td } else { 0 }, if bypass_flag && !ignores_regen { td } else { 0 }, def, def_owner, tray, &mut out.rolls));
            out.takedown_lines.push((p.name.clone(), td_label));
            // Plan H (H-17 lines): the table lands the Takedown here - its lines go back to this mark, and a model it killed makes the next
            // weapon (if there is one) say `Simultaneous fire`. Lines only: the dice keep reading the declared target.
            // A lone Takedown weapon lands the same way (coverage ledger): its casualty line, then its own line, right after its saves.
            if tray.feed().is_some() {
                out.takedown_marks.push(tray.mark());
                let killed = takedown_pick_info(&out.takedown_groups).2;
                if n_shots > 1 && killed > 0 {
                    live_models = def.blast_models.map(|m| m - killed);
                }
            }
            out.deadly_tally += w;
        } else if deadly_per_model && p.deadly > 0 {
            let first = out.deadly_groups.len();
            push_deadly_groups(&mut out, w, p.deadly.max(1), ignores_regen, bypass_flag, def, def_owner, tray, deadly_wipes);
            out.deadly_lines.push((p.name.clone(), w, p.deadly.max(1), out.deadly_groups.len() - first));
            // Inline mode only: the table lands this weapon right here, so its landing lines go back to this mark (the melee fold's twin).
            if inline_land.is_some() {
                out.deadly_marks.push(tray.mark());
            }
            out.deadly_tally += w;
        } else if ignores_regen {
            regen_proof += w;
        } else {
            regenable += w;
            if bypass_flag {
                regen_joined += w;
            }
        }
        // EPOCH_94_PARITY_BATCH: the table lands this weapon's Deadly wounds NOW, before the next weapon rolls.
        if out.deadly_groups.len() > groups_before {
            if let Some(land) = inline_land.as_mut() {
                let left = land(&out.deadly_groups[groups_before..]);
                live_models = Some(left);
                wiped |= left <= 0;
            }
        }
    }
    let def: &Ctx = if wiped { &def_wiped } else { def_live };
    // --- `_solo_land_wounds` :6623 -> `_solo_apply_regeneration` :6543 ---
    if shroud_shortened {
        out.log.push(format!(
            "Ranged Shrouding: {def_owner} — enemy weapon ranges -{:.0}\" (min {:.0}\") against it",
            def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in
        ));
    }
    for (owner, hit, over) in &ma_fired {
        out.log.push(format!(
            "Mobile Artillery: {owner} — {hit:+} to hit past {over:.0}\" (stationary)"
        ));
    }
    for (owner, hit) in &gp_fired {
        out.log.push(format!("Grounded Precision: {owner} — {hit:+} to hit (in terrain)"));
    }
    // Wave 4 — the two Boostbases rules-must-log lines, once per volley, each
    // naming the RULE that fired (wave 3's two spellings and wave 4's two).
    if evasive_boost_fired {
        out.log.push(format!(
            "{}: {def_owner} — attackers get -1 to hit (always)",
            def.evasive_alias_name
        ));
    }
    if aircraft_fired {
        out.log.push(format!("Aircraft: {def_owner} — shots at it get -{} to hit", def.aircraft_hit_penalty));
    }
    if stealth_most_fired {
        out.log.push(format!("Stealth: {def_owner} — -1 to hit past 9\", most models carry it"));
    }
    if stealth_grant_fired {
        out.log.push(format!("Stealth: {def_owner} — -1 to hit past 9\" (granted once)"));
    }
    if out.bane_rerolled > 0 {
        out.log.push(format!(
            "{bane_rule}: {def_owner} — {} successful save(s) of 5-6 re-roll{bane_why}",
            out.bane_rerolled
        ));
    }
    if shielded_alias_fired {
        out.log.push(shielded_alias_line(def, def_owner));
    }
    if defense_token_fired {
        out.log.extend(defense_token_lines(def, def_owner));
    }
    // MOR-17a — rules-must-log, once per volley: the gate's verdict, under the
    // rule's name (Warding, Knightborn and Angelic Blessing are one rule).
    if gate_on && def.regen_gate_over_in > 0.0 && (regenable > 0 || regen_proof > 0 || out.deadly_tally > 0) {
        let gate = def.regen_gate_over_in;
        let line = if !def.regen_gate_shut && def.regen_target > 0 {
            format!("Warding: {def_owner} ignores wounds on 6+ (shot from over {gate:.0}in)")
        } else {
            format!("Warding: no 6+ ignore, {def_owner} was shot from within {gate:.0}in")
        };
        out.log.push(line.clone());
        say_rule(tray, "ignore", def.side, || line);
    }
    out.caused = regen_proof + regenable + out.deadly_tally;
    if regenable + regen_proof <= 0 && !def.regen_note.is_empty() {
        // the table's landing at the volley's end says the held-aside verdict even when no wound is left to ignore
        say_rule(tray, "ignore", def.side, || format!("{def_owner} — {}", def.regen_note));
    }
    out.wounds = ignore_batch(regenable, regen_proof, regen_joined, def, def_owner, tray, &mut out.rolls);
    out
}

/// `main._solo_apply_regeneration` :6543 — one tray die per incoming wound, each
/// `regen_target`+ ignoring it; the wounds that survive come back. Split out of
/// the volley tail because D1-B5's melee needs it three more times: Ravage lands
/// at once (:6002), each Impact pool lands at once (:6337), and the strike phase
/// pools its own (:6161).
/// A4 (`EPOCH_72_PLAYTEST_RULES`, the table's `_solo_land_deadly_wounds` since #1914): each unsaved
/// Deadly(X) wound is X wounds, and the Regeneration family rolls all X before the model's cap — one
/// landing group per wound, a wound whose X are all ignored lands nothing. Below 72 (or with nothing
/// to roll) the legacy leg: one roll on the RAW unsaved count, then ×X per model.
#[allow(clippy::too_many_arguments)] // the two bypass flags and the landing context
fn push_deadly_groups(out: &mut ShootResult, w: i64, x: i64, ignores_regen: bool, bypass_flag: bool, def: &Ctx, def_owner: &str, tray: &mut Tray, wiped: Option<&dyn Fn(&ShootResult) -> bool>) {
    if def.playtest_rules && !ignores_regen && def.regeneration && def.regen_target > 0 {
        for _ in 0..w {
            // The table drops the wounds left once the chain is dead: no pick, no ignore dice (`wiped`, melee only, from the pending epoch).
            if wiped.is_some_and(|f| f(out)) {
                break;
            }
            let post = regen_batch(x, if bypass_flag { x } else { 0 }, def, def_owner, tray, &mut out.rolls);
            // A wound whose X are all ignored still takes its pick (the table's `deadly_pick` runs before the ignore roll, so the "finish the
            // already-wounded Tough model first" count includes it): an x = 0 group lands nothing and only counts the forced pick.
            out.deadly_groups.push((1, post));
        }
        return;
    }
    // The table's `_solo_land_deadly_wounds` asks its ignore step once per unsaved wound, over the X wounds that wound deals. Where no ignore die
    // can come of it (a bypass weapon at one group, or no ignore rule) the legacy leg's dice stand and only the lines are the table's.
    if def.playtest_rules && (!def.regeneration || (ignores_regen && !def.groups_valid())) {
        for _ in 0..w {
            ignore_batch(if ignores_regen { 0 } else { x }, if ignores_regen { x } else { 0 }, 0, def, def_owner, tray, &mut out.rolls);
        }
        out.deadly_groups.push((w, x));
        return;
    }
    let post = ignore_batch(if ignores_regen { 0 } else { w }, if ignores_regen { w } else { 0 }, if bypass_flag && !ignores_regen { w } else { 0 }, def, def_owner, tray, &mut out.rolls);
    out.deadly_groups.push((post, x));
}

pub(crate) fn regen_batch(
    w: i64,
    joined: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
) -> i64 {
    ignore_batch(w, 0, joined, def, def_owner, tray, rolls)
}

/// One ignore roll: a die per wound of `w`, each `target`+ ignoring it; the wounds that survive come back.
fn roll_ignore_group(w: i64, target: i64, name: &str, def: &Ctx, def_owner: &str, tray: &mut Tray, rolls: &mut Vec<Roll>) -> i64 {
    if w <= 0 || !def.regeneration || target <= 0 {
        return w.max(0);
    }
    tray.owner_next(def.unit);
    // The table asks every wound-ignore die as `regeneration` (`_solo_roll_ignore_group`: `_owner_roll(.., "regeneration", ..)`): the step names
    // it so, and the door's volley beats no longer read it as a hit roll (a tracer, the shot counter). The roll RECORD keeps the replay gates'
    // `attack` below (as the morale die does): the gates compare recordings that call it `attack`.
    tray.name_next("regeneration");
    let faces = tray.roll(w as usize);
    let ignored = faces.iter().filter(|&&f| f as i64 >= target).count() as i64;
    if !name.is_empty() {
        // The table's line (`_solo_roll_ignore_group`): the group's own name, "die" for one wound, "dice" for more.
        say_rule(tray, "ignore", def.side, || format!("{def_owner} rolls {w} {name} di{} ({target}+) — {ignored} wound{} ignored",
            if w == 1 { "e" } else { "ce" }, if ignored == 1 { "" } else { "s" }));
    }
    rolls.push(Roll {
        kind: "attack",
        count: w,
        target,
        faces,
        owner: def_owner.into(),
    });
    (w - ignored).max(0)
}

/// The display of an ignore group in the table's "still rolls" list (`display_of` in `_solo_ignore_wounds`): the three named forms capitalised.
fn display_ignore_name(n: &str) -> String {
    match n {
        "regeneration" => "Regeneration".to_string(),
        "self-repair" => "Self-Repair".to_string(),
        "resistance" => "Resistance".to_string(),
        o => o.to_string(),
    }
}

/// `main._solo_ignore_wounds`: the wounds of `pool` (regenable) and `bypass` (a Bane / Rending / Unstoppable weapon's) meet the ignore
/// groups in the table's order. The bypassed wounds skip only the group named Regeneration and join the pool at the first other group;
/// each group rolls on the wounds still standing. Returns ALL wounds that land. Without valid groups (below epoch 82, or one name, or a
/// live leg beside them) it is today's single roll on `pool` plus the bypassed wounds untouched.
#[allow(clippy::too_many_arguments)] // the pool, the Regeneration-bypass wounds and the joined-bypass count are three counts of one landing
pub(crate) fn ignore_batch(
    pool: i64,
    bypass: i64,
    joined: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
) -> i64 {
    let bypass = bypass.max(0);
    if pool.max(0) + bypass > 0 && !def.regen_note.is_empty() {
        say_rule(tray, "ignore", def.side, || format!("{def_owner} — {}", def.regen_note));
    }
    // 29a: a once-per-game ignore rule already spent says so where it would have rolled (the table's PF-a line).
    if pool.max(0) + bypass > 0 && !def.regen_feat_spent.is_empty() {
        say_rule(tray, "ignore", def.side, || format!("{}: {def_owner} already used it this game — no ignore roll", def.regen_feat_spent));
    }
    if pool.max(0) + bypass > 0 && def.regeneration && !def.regen_most_name.is_empty() {
        say_rule(tray, "ignore", def.side, || format!("{def_owner} — {}: most models carry it, so a joined hero without it does not switch it off", def.regen_most_name));
    }
    if !def.groups_valid() {
        // One group: its own name when the static stamp holds exactly one, else a granted Regeneration (the Aura / Medical Training forms).
        let mut live = def.regen_groups.iter().zip(def.regen_names).filter(|(t, _)| **t > 0 && **t == def.regen_target);
        let name = match (live.next(), live.next()) {
            (Some((_, n)), None) => n,
            _ if def.regen_named => "regeneration",
            _ if !def.regen_note.is_empty() => def.regen_pending_notes[2], // the held-aside rule that bound this roll
            _ if def.regen_feat > 0 && def.regen_target == def.regen_feat => def.regen_pending_notes[3],
            _ => "",
        };
        if name == "regeneration" && bypass > 0 {
            say_rule(tray, "ignore", def.side, || format!("{def_owner}: {bypass} wound{} ignore Regeneration — no regeneration roll", if bypass == 1 { "" } else { "s" }));
        } else if !name.is_empty() && name != "regeneration" && joined > 0 {
            // a bypass weapon at a group not named Regeneration: its wounds join the pool and the group still rolls them
            say_rule(tray, "ignore", def.side, || format!("{def_owner}: {joined} wound{} ignore only Regeneration — {} still rolls", if joined == 1 { "" } else { "s" }, display_ignore_name(name)));
        }
        return bypass + roll_ignore_group(pool, def.regen_target, name, def, def_owner, tray, rolls);
    }
    let others: Vec<String> = def.regen_groups.iter().zip(def.regen_names).enumerate().filter(|(i, (t, _))| *i > 0 && **t > 0).map(|(_, (_, n))| display_ignore_name(n)).collect();
    // no group named Regeneration: the bypass wounds that already joined the pool are the ones the first group announces
    let announce = if def.regen_groups[0] > 0 { bypass } else { joined };
    let mut pool = pool.max(0);
    let mut joined = false;
    for (slot, (&target, name)) in def.regen_groups.iter().zip(def.regen_names).enumerate() {
        if target <= 0 {
            continue;
        }
        if slot == 0 {
            if bypass > 0 {
                say_rule(tray, "ignore", def.side, || format!("{def_owner}: {bypass} wound{} ignore Regeneration — no {name} roll", if bypass == 1 { "" } else { "s" }));
            }
        } else if !joined {
            joined = true;
            if announce > 0 {
                say_rule(tray, "ignore", def.side, || format!("{def_owner}: {announce} wound{} ignore only Regeneration — {} still rolls", if announce == 1 { "" } else { "s" }, others.join(" and ")));
            }
            pool += bypass;
        }
        pool = roll_ignore_group(pool, target, name, def, def_owner, tray, rolls);
    }
    if joined { pool } else { pool + bypass }
}

/// Block B13 — Retaliate(X)'s saves on the tray, `_solo_melee_strike_phase`
/// main.gd:6166-6170: the lashed-back hits are saved at the STRIKER's
/// Shielded-adjusted Defense (melee reads neither Cover nor Guarded — the
/// strike saves' own ladder, `shielded_defense`), AP 0, and NOT a weapon: the
/// table's rprofile is `{"name": "Retaliate", "ap": 0, "deadly": 0, "rules":
/// []}`, so no Bane re-roll, no Shred, no Deadly multiplier. The table lands
/// them with `_solo_land_wounds(striker, rw, 0)` — its `0` is the REGEN_PROOF
/// bucket, so every failed save stays regenerable and the STRIKER's own
/// Regeneration draws here, AFTER the save batch, exactly the table's draw
/// order (:6170). Returns `(unsaved, landed)`: the tally credit is the
/// PRE-Regeneration unsaved count (`_solo_retaliate_credit += rw`,
/// main.gd:6171), the landing is the post-Regeneration one.
pub fn retaliate_saves_with_tray(
    hits: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
    rolls: &mut Vec<Roll>,
) -> (i64, i64) {
    if hits <= 0 {
        return (0, 0);
    }
    let save_def = shielded_defense(def.defense, def.shielded_bonus(), def.def_floor());
    let mut sub = ShootResult::default();
    let unsaved =
        save_batch(&ShootProfile::default(), def, def_owner, hits, save_def, 0, false, false, 1, false, tray, &mut sub);
    rolls.extend(sub.rolls);
    let landed = regen_batch(unsaved, 0, def, def_owner, tray, rolls);
    (unsaved, landed)
}

// ------------------------------- D1-B5a: MELEE and IMPACT on the same tray ---

/// The melee to-hit target `_solo_melee_strike_phase` hands the tray
/// (main.gd:6046-6062), in the table's own order and with its own clamping.
///
/// FATIGUE IS NOT A MODIFIER. main.gd:6062 reads
/// `to_hit = 6 if fatigued else modified_hit_target(..)`, so a fatigued striker
/// hits on an unmodified 6 and NOTHING — not Unpredictable's +1, not Thrust —
/// reaches it (p.9). Applying a bonus on top of the 6 turns it into a 5+ and the
/// recorded target stops matching.
///
/// ONE CLAMP, ON THE SUM. main.gd:6053-6055 builds `m_mod = p_mod.mod + uf_hit`,
/// clamps THAT to 0 for an Unstoppable weapon, and calls `modified_hit_target`
/// exactly once. Clamping the defender's modifier alone and then folding
/// `uf_hit` in through a second `modified_hit_target` clamps twice: Quality 6,
/// Evasive, Unpredictable's +1 is a 6+ on the table (-1 +1 = 0) and a 5+ that
/// way.
///
/// Reliable sets the base Quality FIRST — "Reliable only changes the Quality
/// value, so the roll can still be modified" (p.14) — then Thrust's charge
/// bonus. This is deliberately NOT `profile_ev`'s melee branch, which drops
/// Reliable (ai_ev.gd:336-341) and would roll a Reliable weapon at the unit's
/// plain Quality: a recorded target the port could never match.
fn melee_hit_target(
    p: &ShootProfile, att: &Ctx, def: &Ctx, charging: bool, uf_hit: i64,
    charge_from_in: f64, screened_melee: bool,
) -> (i64, bool) {
    if att.fatigued {
        return (UNMODIFIED_SIX, false);
    }
    // Wave 4 follow-up (port-takedown-strike) — the synthetic bonus group
    // strikes at its OWN Quality (main.gd:16772: `"quality": extra_attack_q`),
    // never the member's; 0 = every ordinary profile, the Ctx quality as
    // always.
    let q = if p.extra_attack_q > 0 { p.extra_attack_q } else { att.quality };
    let base = thrust_to_hit(reliable_quality(q, p.reliable), charging && (p.thrust || att.thrust_grant), def.def_floor());
    // B2b: the melee half of `_solo_hit_mod_info` (:5637-5638) sums the same
    // two live nets into `mm` before the single clamp below.
    // EPOCH_22_SCREENED_MELEE (sweep B, row `Screened`) — the Stealth
    // DATA-alias's CHARGE leg (`applies_charged`, main.gd:5729) reaches the
    // melee fold through `screened_melee`: below the gate the caller passes
    // false and the alias pair stays 0, byte-exact. `charge_from_in` is the
    // pre-charge unit-centre distance the caller measured (0.0 for the
    // strike-back and the counter phases).
    let alias_pen = if screened_melee { def.stealth_alias_penalty } else { 0 };
    let mut m = melee_hit_modifier(
        def.evasive,
        def.melee_evasion,
        alias_pen,
        def.stealth_alias_over_in,
        def.stealth_alias_applies_charged,
        charge_from_in,
    ) + uf_hit + att.hit_mod
        + def.vs_hit_mod;
    // Block C2 — the melee branch's Shot Modifier loop (main.gd:5658-5668):
    // `melee_only` names on every strike, `when: "charge"` names only on one.
    // Stamped per NAME in `ctx_for` (`melee_hit_bonus*`), never via the shared
    // primitive. Inside the Unstoppable clamp below, like the table's, whose
    // clamp reads `p_mod.mod + uf_hit` with the bonuses already in `p_mod`
    // (main.gd:6043-6045).
    m += att.melee_hit_bonus;
    if charging {
        m += att.melee_hit_bonus_charge;
    }
    // Wave 3 — the all-attacks Grounded Precision reaches melee too
    // (main.gd:5698-5713's coverage wave), gated on the core's own cover
    // read (Ctx::in_cover), inside the same Unstoppable clamp as the C2
    // bonuses above.
    m += grounded_precision_mod(att);
    // R3-X1b (`EPOCH_73_V36`) — Precision Feat's +1 on every strike of the phase that spent the latch (stamped by sim.rs).
    m += att.feat_hit_bonus;
    // EPOCH 34 UNSTOPPABLE MARK — the melee clamp half, the volley fold's
    // twin: the granted mark (`ctx_live`'s `unstoppable_mark`) counts like
    // the weapon's own `p.unstoppable`. The bool return carries "the GRANT
    // did the clamping" to the caller, which owns the rules-must-log line
    // (this function has no report of its own).
    // EPOCH_73_V36 — the volley's own-rules split, melee twin; 0 below 73 = one clamp on the sum.
    let charge_bonus = if charging { att.melee_hit_bonus_charge } else { 0 };
    let own = if att.v36_rules { uf_hit + att.melee_hit_bonus + charge_bonus + grounded_precision_mod(att) } else { 0 };
    if (p.unstoppable || att.unstoppable_mark) && m - own < 0 {
        return (fold_hit(def.modifier_sum, base, own).0, att.unstoppable_mark);
    }
    (fold_hit(def.modifier_sum, base, m).0, false)
}

/// Wave 4 (port-quick-readjustment) — Indirect's moved to-hit penalty
/// (main.gd:3220-3224): -`moved_hit_penalty` on every shot a MOVED shooter
/// fires with an Indirect weapon (Ctx::moved_this_round, the act-scope flag
/// sim.rs stamps at its volley site), unless the unit carries "Quick
/// Readjustment" (Ctx::quick_readjustment, the `no_moved_penalty` opt-out).
/// The magnitude rides the weapon static
/// (ShootProfile::indirect_moved_hit_penalty, stamped behind the FROZEN
/// `EPOCH_7_TABLE_RULES`); 0 = silent. Rules 3.6 (SHO-02, `EPOCH_73_V36`)
/// removes the penalty: the function answers 0 and neither log line fires.
fn indirect_moved_mod(att: &Ctx, p: &ShootProfile) -> i64 {
    // Rules 3.6 (SHO-02): the moved penalty is gone from `EPOCH_73_V36` on —
    // the same reading the table's `AiCombatMath.indirect_hit_modifier` takes.
    if rule_on(att.rules_epoch, EPOCH_73_V36) {
        return 0;
    }
    if p.indirect
        && att.moved_this_round
        && !att.quick_readjustment
        && p.indirect_moved_hit_penalty > 0
    {
        -p.indirect_moved_hit_penalty
    } else {
        0
    }
}

/// Mobile Artillery's volley leg (main.gd:5773-5779): +N to hit strictly
/// past the entry's own `over_in`, only while the shooter has NOT moved this
/// round — Ctx::moved_this_round, the act-scope `moved` flag sim.rs stamps
/// over the template at its volley site (the twin of the table's
/// `moved_round == current_round` stamp, main.gd:7650).
fn mobile_artillery_mod(att: &Ctx, mod_dist_in: f64) -> i64 {
    if att.mobile_artillery_hit != 0
        && !att.moved_this_round
        && mod_dist_in > att.mobile_artillery_over_in
    {
        att.mobile_artillery_hit
    } else {
        0
    }
}

/// Grounded Precision's leg (main.gd:5710/:5771): +N on every attack while
/// the attacker stands in terrain (Ctx::in_cover — the core's own cover
/// read, the centre-probe stand-in for the table's majority-of-models gate,
/// `_solo_majority_in_cover` main.gd:7065-7083). 0 = silent.
fn grounded_precision_mod(att: &Ctx) -> i64 {
    if att.grounded_precision_hit != 0 && att.in_cover {
        att.grounded_precision_hit
    } else {
        0
    }
}

/// Wave 4 follow-up (port-bloodthirsty-fighter) — the blocked-1s counter of
/// ONE just-drawn save batch: the FIRST "defense" slot pushed at `idx` (the
/// batch's own dice, before any Bane re-roll — a 6 re-rolled into a 1 is not
/// an unmodified 1). `None` when the batch drew nothing (count 0).
fn fresh_save_ones(out: &ShootResult, idx: usize) -> i64 {
    out.rolls
        .get(idx)
        .filter(|r| r.kind == "defense")
        .map(|r| r.faces.iter().filter(|&&f| f == 1).count() as i64)
        .unwrap_or(0)
}

/// Rules 3.6 (`EPOCH_73_V36`) — one Parry event: roll min(X * carrier models, hits) dice;
/// each 6+ cancels one hit. Shared by the strike's event and MEL-07d's follow-up event.
/// MEL-07c-fix — the dice come from the host-plus-joined-heroes sum
/// (`sim::parry_dice_total`, the Impact event's own source); the hand-built dice
/// fixtures keep the old per-host read.
fn parry_event(def: &Ctx, def_owner: &str, hits: i64, gated: bool, tray: &mut Tray, out: &mut ShootResult) -> i64 {
    let dice = def.parry_dice_total.unwrap_or(def.parry_dice * def.models);
    let n = if gated { dice.min(hits) } else { 0 };
    if n <= 0 { return 0; }
    tray.owner_next(def.unit);
    let faces = tray.roll(n as usize);
    let k = faces.iter().filter(|&&f| f >= 6).count() as i64;
    out.rolls.push(Roll { kind: "parry", count: n, target: 6, faces, owner: def_owner.into() });
    out.log.push(format!("Parry: {def_owner} rolls {n} dice and cancels {k} strike hits"));
    say_rule(tray, "parry", def.side, || format!("Parry: {def_owner} rolls {n} dice and cancels {k} strike hits"));
    k
}

/// Rules 3.6 (`EPOCH_73_V36`) — one Parry event per strike: roll min(X * carrier models,
/// hits) dice; each 6+ cancels the highest-worth hit (its own AP plus the on-6 bonus).
pub(crate) fn parry_strike(pending: &mut [Pending<'_>], def: &Ctx, def_owner: &str, gated: bool, tray: &mut Tray, out: &mut ShootResult) {
    let taken: i64 = pending.iter().map(|x| x.3).sum();
    let k = parry_event(def, def_owner, taken, gated, tray, out);
    if k <= 0 { return; }
    let mut cand: Vec<(f64, usize, bool)> = Vec::new();
    for (i, t) in pending.iter().enumerate() {
        let (_sh, p, faces, hits, _, _, mute, _) = t;
        let sixes_hit = if *mute { 0 } else { sixes(faces).min(*hits) };
        for j in 0..*hits { cand.push((hit_ev(p, j < sixes_hit, def), i, j < sixes_hit)); }
    }
    cand.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    for &(_, i, is_six) in cand.iter().take(k as usize) {
        pending[i].3 -= 1;
        if let Some(pos) = if is_six { pending[i].2.iter().position(|&f| f == 6) } else { None } { pending[i].2.remove(pos); }
    }
}

/// ONE melee strike phase on the tray — `main._solo_melee_strike_phase` :5941,
/// in its own draw order (main.gd line in brackets):
///
///   Unpredictable's one die for the whole phase [:5957] -> Ravage per MEMBER,
///   each landing at once with its own Regeneration roll [:5983/:6002] -> per
///   member, per profile: hit dice [:6060] -> the on-6 AP sub-batch and then the
///   rest of the saves [:6337], Bane's re-roll inside -> the phase's pooled
///   Regeneration roll [:6161].
///
/// `strikers` are the table's attack GROUPS in build order
/// (`_solo_attack_groups` :4284-4290): the unit, then each attached hero, each
/// with its own melee set, Quality and fatigue. `Shooter::keep` is every melee
/// profile — melee has no range gate (`melee_profiles_of` sim.rs).
///
/// PORTED: Reliable/Thrust/Evasive/Melee Evasion/Unstoppable on the to-hit, both
/// variants of the Unpredictable die and both of its halves, Ravage, Furious's
/// unmodified-6 bonus hits on the charge, Surge and its block-B6 extra-ATTACK-
/// DIE siblings (Predator Fighter et al., `surge_attack_hits`), Bloodthirsty
/// Fighter's blocked-1s extra attacks (`stamp_bloodthirsty_named`'s flag, the
/// melee fold's own leg below), Sergeant, Blast,
/// the Rending/Destructive/on-6 AP sub-batch, Thrust's charge AP, Bane's
/// re-roll, Shred, the per-model Deadly groups (audit 2026-09-13 §2.1) and every
/// Regeneration roll in
/// its place, and — wave-4 follow-up — Reckless Piercing's round AP stamp
/// (main.gd:6017's `_solo_reckless_ap` fold, the `Ctx::reckless_ap` leg).
///
/// FLAGGED per activation, never skipped in silence: `deadly` (the landing's
/// shape is the `EPOCH_14_DEADLY_LANDING` gate's — per model from 14 on, the
/// pooled multiply below, audit 2026-09-13 §2.1), `takedown`, `hazardous`,
/// and `surge_gates`. (`counter_strikes_first` is the charge's, `sim::tray_charge`:
/// a CHARGER's Counter weapon strikes in its normal slot, and was never a gap.)
///
/// NOT PORTED, in the order they cost the most, and none of them has a field
/// this port can flag them by:
///   1. UNWIELDY's chain half. The swap itself IS ported (`sim::tray_charge`
///      reads `Ctx::unwieldy`), but the table asks the whole joined chain
///      (:16677) and an attached hero reaches this port as rule NAMES only, so
///      an Unwieldy ALIAS carried only by a hero is missed.
///   2. The STRIKE REACH. The table scales each member's attacks by
///      `striking_models_for` (:4331), the models within 2"; this port scales by
///      `alive`, as the EV path does. That is the melee twin of shooting's
///      per-model sighting and the largest die-COUNT class in the replay gate.
///   3. Retaliate (:6175), Deathstrike / Self-Destruct (:6198). (Bloodthirsty
///      Fighter left this list in the wave-4 follow-up port: the melee fold
///      rolls its blocked-1s extra attacks in place — see the leg above.)
///   4. Versatile Attack's melee half (:6076), vs-target Marks, Takedown's unit-of-[1] pick, its melee
///      bonus group ("Takedown Strike", main.gd:6032-6034 — see the shooting
///      leg's NEEDS PRIMITIVE note above: no once-per-game ledger to spend it
///      through) and Limited's once-per-game ledger.
///   5. Guarded / Versatile Defense's charged-from-over-9" +1 Defense (:5948)
///      and the Shred Boost's charge half (the widened 1-2 window "when it
///      charges enemies over 9" away"): the port never measured a pre-charge
///      gap for those legs — melee resolves the base 1s window only. (The
///      Screened-family charge leg does see one since
///      `EPOCH_22_SCREENED_MELEE`: `resolve_melee_leg`'s `charge_from_in`.)
///      The shooting half of
///      the Boost IS ported (the volley's `shred_boost_dice` gate), the
///      table's own Surge-Boost precedent is shooting-only too.
///
/// DEADLY'S TWO LEGS (audit 2026-09-13 §2.1, `EPOCH_14_DEADLY_LANDING`): `resolve_melee_with_tray`
/// below is the LEGACY leg (pool multiply verbatim); `resolve_melee_leg(.., true)` is the 14+
/// per-model leg — sim.rs's call site picks by `rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING)`.
pub fn resolve_melee_with_tray(
    strikers: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    charging: bool,
    cond_ap_dice: bool,
    shred_alias_dice: bool,
    tray: &mut Tray,
) -> ShootResult {
    resolve_melee_leg(
        strikers, def, def_owner, charging, cond_ap_dice, shred_alias_dice,
        false, 0.0, false, false, false, false, false, tray,
    )
}

// The leg split adds one gate-bool to the resolver's existing pack;
// EPOCH_22_SCREENED_MELEE adds the gate and the pre-charge distance the
// alias's charge leg folds on.
#[allow(clippy::too_many_arguments)]
pub fn resolve_melee_leg(
    strikers: &[Shooter<'_>], def: &Ctx, def_owner: &str, charging: bool, cond_ap_dice: bool, shred_alias_dice: bool,
    deadly_per_model: bool, charge_from_in: f64, screened_melee: bool, tray_exact: bool, hits_first: bool,
    fatigue_mutes_sixes: bool, tally_post_regen: bool, tray: &mut Tray,
) -> ShootResult {
    resolve_melee_leg_wipe(
        strikers, def, def_owner, charging, cond_ap_dice, shred_alias_dice, deadly_per_model, charge_from_in,
        screened_melee, tray_exact, hits_first, fatigue_mutes_sixes, tally_post_regen, None, &[], tray,
    )
}

/// `resolve_melee_leg` plus R3-C2 (`EPOCH_73_V36`): `deadly_wipes` answers, on the finished Deadly groups, whether they
/// already destroy the whole defender; the table lands Deadly first and the pool after, so the pool's Regeneration die is
/// then never rolled. `None` (every caller below 73) rolls it as before.
#[allow(clippy::too_many_arguments)]
pub fn resolve_melee_leg_wipe(
    strikers: &[Shooter<'_>],
    def: &Ctx,
    def_owner: &str,
    charging: bool,
    cond_ap_dice: bool,
    shred_alias_dice: bool,
    deadly_per_model: bool,
    charge_from_in: f64,
    screened_melee: bool,
    tray_exact: bool,
    // EPOCH_73_V36 — the strike rolls every hit before any save (see the chunk loop below).
    hits_first: bool,
    // EPOCH_73_V36 (row MEL-09) — a fatigued striker's sixes fire no rule (see `trig` below).
    fatigue_mutes_sixes: bool,
    // MEL-10r (`EPOCH_73_V36`) — the melee tally counts only wounds Regeneration did NOT cancel.
    tally_post_regen: bool,
    deadly_wipes: Option<&dyn Fn(&ShootResult) -> bool>,
    // The skirmish Blast spread's neighbour models, as the volley's `blast_spread`; empty = the plain multiply.
    blast_spread: &[i64],
    tray: &mut Tray,
) -> ShootResult {
    // The alias's charged leg fires on the CHARGER's strikes only — a
    // strike-back or counter phase rides 0.0, which never clears the
    // alias's `over_in` gate (the table's `charged_ok and melee` reading).
    let charge_from_in = if charging { charge_from_in } else { 0.0 };
    // MOR-17a (rules 3.6): Warding's 6+ needs a charge from OVER its gate. A
    // strike-back rides 0.0 — it did the charging, so the 6+ never rolls.
    let gate_on = def.gate_in_force();
    let def = &if gate_on && def.regen_gate_charge_in > 0.0 && charge_from_in <= def.regen_gate_charge_in { def.gate_shut() } else { def.open_named(charge_from_in, true) };
    let mut out = ShootResult::default();
    // Wave 3 — the Shielded-family alias's rules-must-log flag, the volley
    // fold's melee twin (Shielded is the whole melee Defense ladder here).
    let mut shielded_alias_fired = false;
    let mut defense_token_fired = false;
    // (1) Unpredictable :5957 — ONE die for the whole phase, before anything
    //     else: 1-3 is AP(+1) on every melee weapon, 4-6 is +1 to hit
    //     (`unpredictable_fighter_effect` ai_combat_math.gd:387-388).
    let mut uf_ap = 0;
    let mut uf_hit = 0;
    if strikers.first().is_some_and(|sh| sh.att.unpredictable) {
        tray.owner_next(strikers[0].att.unit);
        let faces = tray.roll(1);
        if faces[0] <= 3 {
            uf_ap = 1;
        } else {
            uf_hit = 1;
        }
        out.rolls.push(Roll {
            kind: "attack",
            count: 1,
            target: BEST_HIT_TARGET,
            faces,
            owner: strikers[0].owner.into(),
        });
    }
    // (2) Ravage :5983 — X dice per alive bearer, per MEMBER, each 6+ a DIRECT
    //     wound: no hit roll, no save. They land at once (:6002), so their
    //     Regeneration rolls here and not into the phase pool, and the tally
    //     takes the PRE-regeneration count (:6001).
    for sh in strikers {
        let n = sh.att.ravage * sh.att.models.max(0);
        if n <= 0 {
            continue;
        }
        tray.owner_next(sh.att.unit);
        let faces = tray.roll(n as usize);
        let w = faces.iter().filter(|&&f| f as i64 >= RAVAGE_WOUND_TARGET).count() as i64;
        out.rolls.push(Roll {
            kind: "attack",
            count: n,
            target: RAVAGE_WOUND_TARGET,
            faces,
            owner: sh.owner.into(),
        });
        out.caused += w;
        out.wounds += regen_batch(w, 0, def, def_owner, tray, &mut out.rolls);
    }
    // MEL-12 (`EPOCH_73_V36`) — Regenerative Strength's banked tokens: one die
    // per token, each 4+ a DIRECT wound (no hit roll, no save; Regeneration
    // applies). Rolled once per round, before the strikes; the gate lives in
    // `sim::strike_phase`, which zeroes the count and logs every skip.
    for sh in strikers {
        let n = sh.att.growth_wound_dice;
        if n <= 0 {
            continue;
        }
        tray.owner_next(sh.att.unit);
        let faces = tray.roll(n as usize);
        let w = faces.iter().filter(|&&f| f as i64 >= 4).count() as i64;
        out.rolls.push(Roll { kind: "attack", count: n, target: 4, faces, owner: sh.owner.into() });
        out.log.push(format!(
            "Regenerative Strength: {} rolls {} dice, {} wounds", sh.owner, n, w));
        tray.say(|| LogLine {
            rule: "melee", category: Category::Combat, side: sh.att.side, detail: None,
            text: format!("Regenerative Strength: {} rolls {} dice, {} wound{}", sh.owner, n, w, if w == 1 { "" } else { "s" }),
        });
        out.caused += w;
        out.wounds += regen_batch(w, 0, def, def_owner, tray, &mut out.rolls);
    }
    // (3) the strikes :6060-6148. `regenable`/`regen_proof` are the PHASE's, not
    //     the member's — the table declares them before the group loop and lands
    //     them once after it (:6161).
    let (mut regenable, mut regen_proof) = (0i64, 0i64);
    // the wounds of bypass weapons that JOINED the pool (the target has no group named Regeneration): the table's `ignore only Regeneration` line counts them
    let mut regen_joined = 0i64;
    // Wave 3 — Grounded Precision's melee half names itself once per member
    // (rules-must-log, the volley's own flag shape).
    let mut gp_fired: Vec<(&str, i64)> = Vec::new();
    // Wave 4 — the evasive Boosts' once-per-melee rules-must-log flag.
    let mut evasive_boost_fired = false;
    for sh in strikers {
        let gp = grounded_precision_mod(sh.att);
        if gp != 0 && gp_fired.iter().all(|(o, _)| *o != sh.owner) {
            gp_fired.push((sh.owner, gp));
        }
    }
    // EPOCH_73_V36 — one strike is ONE hits event: pass 1 rolls every
    // member's every profile to its hit count, pass 2 then runs each
    // profile's saves, landing and Bloodthirsty extras in the same order.
    // Below the gate each chunk is one profile: today's interleaved draws.
    let order: Vec<(&Shooter<'_>, usize, usize)> = strikers.iter()
        .flat_map(|sh| sh.keep.iter().enumerate().map(move |(k, &pi)| (sh, k, pi))).collect();
    // Rules 3.6 (row W1.TRACE-c) — Thrust's charge leg names itself once per
    // striking profile (arm `thrust-in-melee`). The switch is read ONCE here,
    // never per model or per die.
    let trace_thrust = strikers.first()
        .is_some_and(|sh| rule_on(sh.att.rules_epoch, EPOCH_73_V36))
        && crate::mv::plain_memo::trace_rules_on();
    // EPOCH_96_PARITY_BATCH: a striker attacking a Bane-Marked unit strikes with Bane (the volley's granted-Bane twin).
    let marked: Vec<Vec<ShootProfile>> = strikers.iter().map(|sh| if sh.att.bane_mark_grant {
        sh.profiles.iter().map(|p| if p.bane && p.bypass_regen { p.clone() } else {
            ShootProfile { bane: true, bypass_regen: true, bane_alias: if p.bane { p.bane_alias.clone() } else { "Bane Mark".into() }, ..p.clone() }
        }).collect()
    } else { Vec::new() }).collect();
    for part in order.chunks(if hits_first { order.len().max(1) } else { 1 }) {
        let mut pending = Vec::new();
        for &(sh, k, pi) in part {
            let si = strikers.iter().position(|s| std::ptr::eq(s, sh)).unwrap_or(0);
            let p = if sh.att.bane_mark_grant { &marked[si][pi] } else { &sh.profiles[pi] };
            let n = sh.attacks[k];
            if n <= 0 {
                continue;
            }
            if trace_thrust && charging && (p.thrust || sh.att.thrust_grant) {
                crate::sim::trace_rule("thrust-in-melee", "Thrust in Melee", &format!(
                    "{}: Thrust adds its charge bonus to {}", sh.owner, p.name));
            }
            // Wave 4 follow-up — "Takedown Strike" names itself once per
            // strike (rules-must-log, the table's own log line at
            // main.gd:16780-16783).
            if p.extra_attack_q > 0 {
                out.log.push(format!(
                    "{}: {} makes one extra attack at Quality {}+ with AP({}), Deadly({}), Takedown (once per game)",
                    p.name, sh.owner, p.extra_attack_q, p.ap, p.deadly));
                say_rule(tray, "takedown_bonus", sh.att.side, || format!(
                    "{}: {} makes one extra attack at Quality {}+ with AP({}), Deadly({}), Takedown (once per game)",
                    p.name, sh.owner, p.extra_attack_q, p.ap, p.deadly));
            }
            if p.takedown {
                if tray_exact {
                    out.log.push(takedown_pick_line(p, def_owner)); // tray-exact S10, main.gd:7191
                } else {
                    out.mark("takedown");
                }
            }
            if p.hazardous {
                out.mark("hazardous");
            }
            // Wave 4 — the unconditional -1 rode this strike's to-hit sum.
            evasive_boost_fired |= def.evasive_alias;
            // EPOCH_38_WATCHBORN_LATCH — the melee half the planner already
            // counted (`profile_ev`'s `!melee || charging` leg): the latched
            // pick reaches the melee fold for charges from over 9", the
            // volley fold's pick read mirrored. Fatigue keeps the
            // unmodified-6 target (main.gd:6159's order); the AP half folds.
            let mut versatile_ap = 0;
            let (raw0, unstop_grant_clamped) = melee_hit_target(
                p, sh.att, def, charging, uf_hit, charge_from_in, screened_melee,
            );
            let (mut raw, mut target) = fold_hit(def.modifier_sum, raw0, 0);
            // EPOCH 34 UNSTOPPABLE MARK — the melee clamp half's rules-must-log
            // line, the volley fold's twin (the weapon's own flag stays silent).
            if unstop_grant_clamped {
                out.log.push(format!(
                    "Unstoppable: {} — negative to-hit modifiers ignored (once)", sh.owner));
            }
            if sh.att.versatile_latched
                && charging
                && (sh.att.versatile_no_gate
                    || charge_from_in > crate::combat::charge_gate_in(sh.att.rules_epoch))
                && (p.versatile_attack || sh.att.versatile_grant)
            {
                if !sh.att.fatigued {
                    (raw, target) = fold_hit(def.modifier_sum, raw, sh.att.versatile_pick_hit);
                }
                versatile_ap = sh.att.versatile_pick_ap;
            }
            tray.owner_next(sh.att.unit);
            let faces = tray.roll(n as usize);
            out.rolls.push(Roll {
                kind: "attack",
                count: n,
                target,
                faces: faces.clone(),
                owner: sh.owner.into(),
            });
            // MEL-02 (rules-must-log): a Limited weapon's spend names itself right after its roll, as the table's strike loop does; the engine-log line
            // (`strike_phase`) never reaches the door.
            if p.limited {
                say_rule(tray, "limited", sh.att.side, || format!("{} (Limited) is used up in melee", p.name));
            }
            if p.hazardous {
                let ones = faces.iter().filter(|&&f| f == 1).count() as i64;
                if ones > 0 {
                    out.hazardous_self.push((sh.owner.to_string(), p.name.clone(), ones, p.blast.max(p.deadly).max(1), None));
                }
            }
            // EPOCH_73_V36 (row MEL-09) — a fatigued striker (a Shaken strike-back
            // counts as one) still hits on its sixes, but they fire no rule: every
            // hit-six reader below sees `trig`, empty when muted. Saves untouched.
            let mute = fatigue_mutes_sixes && sh.att.fatigued;
            let trig: &[u8] = if mute { &[] } else { &faces };
            if mute && sixes(&faces) > 0 {
                out.log.push(fatigued_sixes_line(sh.owner, sixes(&faces)));
            }
            // Precise scores one better than it ROLLS — `_solo_hits` :4405-4406
            // applies the +1 when counting, so the recorded target stays raw.
            // AIG-G2: a weapon-borne Imprecise is Precise's mirror, the -1 read from `EPOCH_73_V36`.
            let imprecise = sh.att.v36_rules && p.imprecise;
            let weapon_mod = p.precise as i64 - imprecise as i64;
            let count_target = if weapon_mod != 0 { fold_hit(def.modifier_sum, raw, weapon_mod).1 } else { target };
            if p.precise {
                out.log.push(format!("Precise: +1 to hit on {}'s strikes", sh.owner));
            }
            if imprecise {
                out.log.push(format!("Imprecise: -1 to hit on {}'s strikes", sh.owner));
            }
            let mut hits = faces_to_hits(&faces, count_target as u8) as i64;
            // SHO-18 (rules 3.6): a Surge ALIAS fires only on a charge over 6"; a non-charging
            // strike (the strike-back) pays nothing, and every pre-73 record keeps the old read.
            let alias_fires = !p.alias_gate
                || p.surge_alias_rule.is_empty()
                || charge_from_in > crate::combat::CHARGE_LONG_RANGE_IN;
            let surge_before = hits;
            let mut surge_fives = 0;
            if p.surge && alias_fires {
                // No flag: at 0.0" this IS the table's gated read (the within
                // cap passes, the low window below opens only for the sentinel).
                hits += sixes(trig) * p.bonus_hits_per_six.max(1);
                // EPOCH_50 SURGE LOW — the volley fold's twin (:996-1007): the
                // entry's own printed low window (Great Sergeant's "5 or 6")
                // pays its successful unmodified 5s in melee too. Melee
                // resolves at 0.0" (main.gd:6103), so the strict
                // `dist > surge_over_in` gate opens ONLY for the ungated
                // sentinel (-1.0) the named walk stamps from
                // `EPOCH_50_SURGE_LOW` — the Boost's 9.0 stays shut here,
                // exactly like the table (main.gd:4539 at dist 0.0).
                if p.surge_low < 6 && p.surge_over_in < 0.0 {
                    surge_fives = trig.iter().filter(|&&f| f == 5 && count_target <= 5).count() as i64;
                    hits += surge_fives;
                }
                if !p.surge_alias_rule.is_empty() && sixes(trig) > 0 {
                    out.log.push(format!("{}: charged from over {:.0}in — bonus hits on unmodified 6s",
                        p.surge_alias_rule, crate::combat::CHARGE_LONG_RANGE_IN));
                }
            }
            if p.surge && alias_fires && hits > surge_before {
                // The table's lines (`_solo_hits`): a charging alias names its gate, then the plain total (a strike-back pays no alias).
                let bonus = hits - surge_before;
                if charging && !p.surge_alias_rule.is_empty() {
                    say_rule(tray, "surge", sh.att.side, || format!("{}: charged from over {}\" — bonus hits on unmodified 6s",
                        p.surge_alias_rule, crate::combat::CHARGE_LONG_RANGE_IN as i64));
                }
                say_rule(tray, "surge", sh.att.side, || format!("Surge: +{bonus} hit{} (unmodified {})",
                    if bonus == 1 { "" } else { "s" }, if surge_fives == 0 { "6s" } else { "5-6s" }));
            }
            // Block B6 — the extra-ATTACK-DIE Surge siblings (Predator Fighter
            // is melee-only, so this is the branch it actually fires on).
            // Wave 2 — a granted "Primal Boost", the same low-surge form (one group per member: `primal_extras`).
            hits += primal_extras(p, sh.att.surge_grant && primal_grant_reaches(p, sh.att.rules_epoch), rule_on(sh.att.rules_epoch, EPOCH_73_V36), trig, count_target, sh.owner, sh.att.side, tray, &mut out);
            // EPOCH 44 SURGE MARK — the strike fold's twin of the volley leg
            // above: the mark's once-grant adds +1 hit per unmodified 6
            // against the marked target only, named once when it fires.
            if sh.att.surge_mark_grant {
                let mark_sixes = sixes(trig);
                if mark_sixes > 0 {
                    hits += mark_sixes;
                    out.log.push(format!(
                        "Surge Mark: {} — +{} bonus hit{} on unmodified 6s against the marked target (once)",
                        sh.owner, mark_sixes, if mark_sixes == 1 { "" } else { "s" }));
                    // The table's own words (`_solo_hits`): the mark's total replaces the plain Surge line.
                    say_rule(tray, "surge_mark", sh.att.side, || format!("Surge Mark: +{mark_sixes} hit{} (unmodified 6s) against the marked {def_owner} (once)", if mark_sixes == 1 { "" } else { "s" }));
                }
            }
            // Furious :4477 — the unit-level rule the table stamps onto every
            // melee profile (main.gd:4343): unmodified 6s, charge only.
            if charging && sh.att.furious {
                let furious_hits = sixes(trig);
                hits += furious_hits;
                if furious_hits > 0 {
                    // The table's line (`_solo_hits`, rules-must-log): a Furious bearer names the extra hits; one named rule, one line, one hit per 6.
                    say_rule(tray, "furious", sh.att.side, || format!("Furious: +{furious_hits} hit{} on the charge (unmodified 6s)", if furious_hits == 1 { "" } else { "s" }));
                }
            }
            if p.sergeant_attacks > 0 {
                hits += sixes(trig).min(p.sergeant_attacks);
            }
            if hits > 0 && p.blast > 1 && !blast_spread.is_empty() && !(tray_exact && p.takedown) {
                let split = blast_split_at(hits, p.blast, def.blast_models.unwrap_or(def.models).max(1), blast_spread, sh.att.rules_epoch);
                out.blast_spill.push(BlastSpill { shooter: si, profile: pi, hits: split[1..].to_vec() });
                let (kept, spread) = (split[0], split[1..].iter().sum::<i64>());
                let line = format!("Blast({}): {hits} hit{} -> {kept} on {def_owner}, {spread} on units within reach, {} lost",
                    p.blast, if hits == 1 { "" } else { "s" }, hits * p.blast - kept - spread);
                out.log.push(line.clone());
                say_rule(tray, "blast", sh.att.side, || line);
                hits = kept;
            } else if hits > 0 && p.blast > 1 {
                let cap = if tray_exact && p.takedown { 1 } else { def.blast_models.unwrap_or(def.models).max(1) };
                let boosted = hits * p.blast.clamp(1, cap);
                if def.blast_models.is_some() {
                    out.log.push(blast_log(p.blast, hits, boosted, cap, false));
                }
                say_rule(tray, "blast", sh.att.side, || blast_log(p.blast, hits, boosted, cap, false)); // the table says it always (#169), melee too
                hits = boosted;
            }
            // The table's line after each melee hit roll (`_solo_melee_strike_phase`), a miss included.
            tray.say(|| LogLine { rule: "melee", category: Category::Combat, side: sh.att.side,
                text: format!("{} strikes with {} at {def_owner} — {hits} hit{}", sh.owner, p.name, if hits == 1 { "" } else { "s" }),
                detail: None });
            if hits <= 0 {
                continue;
            }
            pending.push((sh, p, faces, hits, count_target, versatile_ap, mute, n));
        }
        // MEL-07c — one Parry event per strike, after every hit roll and before any save.
        parry_strike(&mut pending, def, def_owner, hits_first, tray, &mut out);
        for (sh, p, faces, hits, count_target, versatile_ap, mute, n) in pending {
            let on6 = if mute {
                0
            } else if p.on6_ap > 0 {
                p.on6_ap
            } else if p.rending || p.destructive || sh.att.rending_grant {
                RENDING_AP_BONUS
            } else {
                0
            };
            let ap4 = if on6 > 0 { sixes(&faces).min(hits) } else { 0 };
            // SHO-17: the charge leg reads the 6" gate stamped on the defender's context; 0.0 below
            // the epoch keeps the old over-9" reading (with `tray_exact`) byte-identical.
            let gate_in = if def.guarded_charge_over_in > 0.0 { def.guarded_charge_over_in } else { LONG_RANGE_IN };
            let over9 = def.guarded && charge_from_in > gate_in && !def.sturdy_boost_gates_guarded;
            let applies = over9 && (tray_exact || def.guarded_charge_over_in > 0.0);
            if over9 && !applies {
                out.mark("guarded_over9");
            }
            if over9 && applies && def.guarded_charge_over_in > 0.0 {
                let rule = if def.guarded_name.is_empty() { "Guarded" } else { def.guarded_name };
                out.log.push(format!("{rule}: {def_owner} charged from over {}in — +1 Defense", gate_in as i64));
            }
            let pierce = pierce_ignores(p, sh.att);
            if pierce {
                say_pierce(tray, sh.att.side, &p.name, def, false); // the table's line is said for a strike too (no Cover in melee)
            }
            let save_def = guarded_defense(
                shielded_defense(def.defense, if pierce { 0 } else { def.shielded_bonus() }, def.def_floor()),
                applies && !pierce, def.def_floor());
            shielded_alias_fired |= def.shielded && def.shielded_alias != ShieldedAlias::None;
            if !defense_token_fired {
                for l in defense_token_lines(def, def_owner) {
                    say_rule(tray, "defense_part", def.side, || l);
                }
            }
            defense_token_fired = true;
            // Block B7 — Piercing Growth's AP delta, melee half (see the
            // shooting site's own note above).
            let mut ap = p.ap + uf_ap + versatile_ap + sh.att.growth_ap_mod
                + sh.att.reckless_ap
                // FEAT PR 3 — Piercing Feat's once-per-game window, the melee
                // half of the volley seam's stamp (see the volley fold above).
                + sh.att.feat_ap_bonus
                // SEAM 4 step 2 (epoch 7) — the same `ap_mod` net's melee
                // half; the charging/assault leg is this fold's own sum (the
                // pierce-assault site below is the CONDITIONAL family).
                + sh.att.ap_mod
                + if charging && (p.thrust || sh.att.thrust_grant) { THRUST_AP_BONUS } else { 0 }
                + if sh.att.pierce_melee_grant { 1 } else { 0 };
            // Rung I — the melee half of the same `cond_ap` fold, same
            // `Knobs::cond_ap_dice` gate as the shooting half. Real `charging`
            // is already this function's own parameter (unlike `profile_ev`'s
            // EV call, which is structurally stuck at `false`), so
            // `on_charge`/`vs_tough_ge` gates fire correctly here.
            if cond_ap_dice {
                let cap = CondApTarget::of(def, p.range as f64);
                let use_target_state = rule_on(sh.att.rules_epoch, crate::acts::EPOCH_92_MELEE_CAUSES);
                for c in &p.cond_ap {
                    let d = if use_target_state {
                        conditional_ap_bonus_vs(c, &cap, charging, charge_from_in, true)
                    } else {
                        conditional_ap_bonus(c, def.tough.max(1), def.defense, charging, charge_from_in, true)
                    };
                    ap += d;
                    // Rules-must-log, the melee half: only the wave-3 NAMED
                    // forms log; unnamed specs stay silent (old replays).
                    // SHO-20: the 3.6 charge leg names the charge.
                    if c.gate == "hold_or_charge" {
                        if d > 0 {
                            let line = format!("Slayer: AP(+{}) because it charged", d);
                            out.log.push(line.clone());
                            say_rule(tray, "slayer", sh.att.side, || line);
                        }
                    } else if d > 0 && !c.name.is_empty() {
                        out.log.push(format!("{}: AP(+{}) on {}'s strike{}", c.name, d, sh.owner, cond_ap_why(&c.condition)));
                        say_rule(tray, "cond_ap", sh.att.side, || format!("{}: AP(+{}) against {def_owner}{}", c.name, d, cond_ap_why(&c.condition)));
                    } else if d > 0 && !c.say_name.is_empty() {
                        // H-17a's melee twin: the generic pass's rules (Disintegrate, Tear, ...) say the table's line; `out.log` stays as it was.
                        say_rule(tray, "cond_ap", sh.att.side, || format!("{}: AP(+{}) against {def_owner}", c.say_name, d));
                    }
                }
                // Wave 2 — the Slayer mark and Piercing Assault on their
                // granted legs, the same ladder the weapon-stamped conds ride.
                if sh.att.slayer_grant {
                    let d = conditional_ap_bonus(&slayer_grant_cond(), def.tough.max(1), def.defense, charging, 0.0, true);
                    ap += d;
                    if d > 0 && sh.att.v36_rules {
                        let line = format!("Slayer: AP(+{}) because it charged", d);
                        out.log.push(line.clone());
                        say_rule(tray, "slayer", sh.att.side, || line);
                    }
                }
                if sh.att.pierce_assault_grant {
                    ap += conditional_ap_bonus(&piercing_assault_grant_cond(), def.tough.max(1), def.defense, charging, 0.0, true);
                }
            }
            say_growth_ap(tray, sh.att, sh.owner);
            // 1 = the base shred window — melee NEVER widens: the Shred
            // Boost's charge half needs a pre-charge gap this port never
            // measured (see the NOT-PORTED list on resolve_melee_with_tray).
            let idx_ap = out.rolls.len();
            // Rules 3.6 row MOR-12c: the bearer's share of the plain hits, the
            // volley leg's twin (main.gd:8372-8387).
            // SHO-18 (rules 3.6): a Shred ALIAS pays only on a charge over 6"; a strike-back pays nothing.
            let shred_alias_fires = shred_alias_dice
                && (!p.alias_gate || (p.shred_any_distance && charging)
                    || charge_from_in > crate::combat::CHARGE_LONG_RANGE_IN);
            if p.shred_alias && p.alias_gate && shred_alias_fires && p.shred_ones_wound_bonus > 0 {
                let name: &str = if p.shred_ones_rule.is_empty() { "Shred" } else { p.shred_ones_rule.as_str() };
                if p.shred_any_distance {
                    out.log.push(format!("{}: charge — unmodified 1s take +1 wound at any distance", name));
                } else {
                    out.log.push(format!("{}: charged from over {:.0}in — unmodified 1s take +1 wound",
                        name, crate::combat::CHARGE_LONG_RANGE_IN));
                }
            }
            // AI-G2: the melee half of the volley's Bane-condition gate (the table's `bane_applies`, melee = true).
            out.bane_gated = !p.bane_condition.is_empty() && !cond_met(&CondAp { condition: p.bane_condition.clone(), threshold: p.bane_threshold, ..Default::default() }, &CondApTarget::of(def, p.range as f64), false, 0.0, true);
            out.bane_low = if p.bane_low > 1 && 0.0 > p.bane_over_in && !out.bane_gated { p.bane_low } else { 0 };
            say_on6_ap(tray, p, sh.att, ap4, on6);
            let normal = hits - ap4;
            let sgt_hits = sergeant_hits(p, n, normal, sh.att);
            let mut w = save_batch(p, def, def_owner, ap4, save_def, ap + on6, sh.att.shred_grant, shred_alias_fires, 1, deadly_per_model, tray, &mut out);
            if sgt_hits > 0 {
                let line = sergeant_line(p, sh.owner, sgt_hits);
                tray.say(|| LogLine { rule: "melee", category: Category::Combat, side: sh.att.side, text: line.clone(), detail: None });
                out.log.push(line);
                w += save_batch(p, def, def_owner, sgt_hits, save_def, ap + p.sergeant_ap, sh.att.shred_grant, shred_alias_fires, 1, deadly_per_model, tray, &mut out);
            }
            // Wave 4 follow-up — the batch's OWN blocked unmodified 1s (the
            // FIRST "defense" slot of the batch, never Bane's re-rolls: a 6
            // re-rolled into a 1 is not an unmodified 1), Bloodthirsty
            // Fighter's table counter read (main.gd:6505-6509).
            let ones_ap = fresh_save_ones(&out, idx_ap);
            let idx_rest = out.rolls.len();
            w += save_batch(p, def, def_owner, normal - sgt_hits, save_def, ap, sh.att.shred_grant, shred_alias_fires, 1, deadly_per_model, tray, &mut out);
            let ones_rest = fresh_save_ones(&out, idx_rest);
            // Wave 4 follow-up — Bloodthirsty Fighter (aof/war_disciples):
            // each unmodified 1 the DEFENDER rolled blocking this weapon pays
            // for ONE extra attack with the SAME weapon at the SAME to-hit
            // target (`count_target`), pooled through normal saves at the
            // batch's own AP, and NEVER chaining — the extras' own save 1s
            // are consumed after this leg has moved on (the table's reset,
            // main.gd:6184). The extra-attack leg is the melee Surge family's
            // own shape (`surge_attack_hits`, the melee fold's sibling).
            if !p.bloodthirsty_rule.is_empty() && hits > 0 {
                let bt_ones = ones_ap + ones_rest;
                if bt_ones > 0 {
                    // The entry's own per-one count (`extra_attack_per_enemy_save_one`,
                    // dead-parameter recount 2026-09-15, family 2) — 1 replays
                    // the recorded one-extra-attack-per-blocked-1 byte-exact.
                    let bt_extra = bt_ones * p.extra_attack_per_enemy_save_one.max(1);
                    out.log.push(format!(
                        "{}: {} blocked 1{} — {} rolls {} extra attack{}",
                        p.bloodthirsty_rule, bt_ones, if bt_ones == 1 { "" } else { "s" },
                        sh.owner, bt_extra, if bt_extra == 1 { "" } else { "s" }));
                    // The table's line names the weapon too (`_solo_attack_groups`' Bloodthirsty leg).
                    say_rule(tray, "bloodthirsty", sh.att.side, || format!(
                        "{}: {} blocked 1{} — {} rolls {} extra attack{} with {}",
                        p.bloodthirsty_rule, bt_ones, if bt_ones == 1 { "" } else { "s" },
                        sh.owner, bt_extra, if bt_extra == 1 { "" } else { "s" }, p.name));
                    tray.owner_next(sh.att.unit);
                    let bt_faces = tray.roll(bt_extra as usize);
                    out.rolls.push(Roll {
                        kind: "attack",
                        count: bt_extra,
                        target: count_target,
                        faces: bt_faces.clone(),
                        owner: sh.owner.into(),
                    });
                    let mut bt_hits = faces_to_hits(&bt_faces, count_target as u8) as i64;
                    let bt_trig: &[u8] = if mute { &[] } else { &bt_faces };
                    if p.surge {
                        bt_hits += sixes(bt_trig) * p.bonus_hits_per_six.max(1);
                        // The one real gap: the table's `_solo_hits` (main.gd:7128)
                        // also pays the sentinel window's 5s on these extra dice.
                        if p.surge_low < 6 && p.surge_over_in < 0.0 {
                            out.mark("surge_gates");
                        }
                    }
                    bt_hits += surge_attack_hits(p, bt_trig, count_target, sh.owner, tray, &mut out.rolls);
                    // MEL-07d — the follow-up is its own strike: one more Parry event, same dice count.
                    bt_hits -= parry_event(def, def_owner, bt_hits, hits_first, tray, &mut out);
                    if bt_hits > 0 {
                        // The table resolves the extras pooled with the same
                        // effective AP (main.gd:6180-6182) — one batch, no
                        // separate on-6 AP sub-batch, no Deadly special-case:
                        // they join the weapon's own batch, and on a Deadly
                        // weapon its per-model group below.
                        let btw = save_batch(p, def, def_owner, bt_hits, save_def, ap + on6, sh.att.shred_grant, shred_alias_fires, 1, deadly_per_model, tray, &mut out);
                        w += btw;
                    }
                }
            }
            // Audit 2026-09-13 §2.3 — the regen split reads the BYPASS flag, not
            // `bane`: the Bane-primitive aliases re-roll sixes but carry no
            // Regeneration clause, so they never join this proof.
            // Audit 2026-09-13 §2.1 — on the 14+ leg a Deadly weapon's share is
            // its OWN group: its Regeneration roll draws on the RAW unsaved
            // count (the table's roll inside `_solo_land_deadly_wounds`,
            // main.gd:6762), the landing multiplies PER MODEL with no carry-over
            // (`apply_deadly_wounds`, solo_controller.gd:8333). The tally keeps
            // the raw count. The legacy leg keeps the pool multiply verbatim
            // and lands through `land_wounds` as before.
            // EPOCH 37 UNSTOPPABLE AURA — the melee half's final answer, not
            // the scope-blind union: below 37 `unstoppable_regen_melee` IS
            // the union (recorded leak replays), from 37 only a grant whose
            // record is NOT shooting-scoped — the "Unstoppable when Shooting"
            // aura stops cutting through melee Regeneration.
            // EPOCH 46 DISINTEGRATE REGEN — the melee fold's twin of the
            // volley seam: the registry-driven weapon-rule bypass joins the
            // SAME union (the table's arm is reach-blind, main.gd:7133-7137).
            let disintegrate_regen = !p.regen_bypass_rule.is_empty();
            let bypass_flag = p.bypass_regen
                || p.rending
                || p.unstoppable
                || sh.att.rending_grant
                || sh.att.unstoppable_regen_melee
                || disintegrate_regen;
            let ignores_regen = bypass_flag && def.bypass_skips_ignore();
            // Rules-must-log: the refusal names the rule, the volley fold's
            // twin (main.gd:7175-7176). DAT-16b: same target gate as the ranged
            // leg — from 73 only a real Regeneration roll is named.
            if disintegrate_regen && w > 0
                && (!sh.att.v36_rules || (def.regeneration && def.regen_target > 0 && def.bypass_skips_ignore()))
            {
                out.log.push(format!("{}: Regeneration ignored", p.regen_bypass_rule));
            }
            // The table asks once per strike weapon with hits (`_solo_ignores_regen`): a Takedown or per-model Deadly weapon only when it
            // dealt wounds. The line (`<rule>: Regeneration ignored`, the printed `Unstoppable: ...`, the Mark's) goes on the tray here.
            let regen_asked = if (tray_exact && p.takedown) || (deadly_per_model && p.deadly > 0) { w > 0 } else { true };
            say_regen_bypass(tray, sh.att.side, p, sh.att, def, sh.owner, regen_asked);
            // EPOCH 34 UNSTOPPABLE MARK — rules-must-log, the melee Regeneration
            // half, the volley fold's twin: the granted mark names itself the
            // one time its bypass is the reason this weapon's wounds skip the
            // regen pool. Gated with the clamp half, replay-exact below 34.
            if ignores_regen && sh.att.unstoppable_mark && w > 0 {
                // tray twin: anti_regen
                out.log.push(format!(
                    "Unstoppable: {} — ignores {}'s Regeneration (once)", sh.owner, def_owner));
            }
            if p.deadly > 0 && !deadly_per_model {
                out.mark("deadly"); // the volley fold's twin: only the pooled legacy leg diverges
            }
            if tray_exact && p.takedown {
                // Tray-exact S9 — the melee twin of S7 (Takedown Strike included, main.gd:7275-7283):
                // w x max(Deadly, 1) through the pick's Regeneration, one model, overkill lost.
                let td = w * p.deadly.max(1);
                out.takedown_groups.push(ignore_batch(if ignores_regen { 0 } else { td }, if ignores_regen { td } else { 0 }, if bypass_flag && !ignores_regen { td } else { 0 }, def, def_owner, tray, &mut out.rolls));
                out.deadly_tally += w;
            } else if deadly_per_model && p.deadly > 0 {
                let first = out.deadly_groups.len();
                let stops = deadly_wipes.filter(|_| rule_on(sh.att.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH));
                push_deadly_groups(&mut out, w, p.deadly.max(1), ignores_regen, bypass_flag, def, def_owner, tray, stops);
                out.deadly_lines.push((p.name.clone(), w, p.deadly.max(1), out.deadly_groups.len() - first));
                out.deadly_marks.push(tray.mark());
                out.deadly_tally += w;
            } else if ignores_regen {
                regen_proof += w;
            } else {
                regenable += w;
                if bypass_flag {
                    regen_joined += w;
                }
            }
        }
    }
    for (owner, hit) in &gp_fired {
        out.log.push(format!("Grounded Precision: {owner} — {hit:+} to hit (in terrain)"));
    }
    // Rules 3.6 (`EPOCH_73_V36`) — the Precision Fighter / Precision Charge BASES name themselves per member.
    for sh in strikers {
        if sh.att.precision_fighter_base {
            out.log.push(format!("Precision Fighter: {} — +1 to hit (melee)", sh.owner));
        }
        if sh.att.precision_charge_base && charging {
            out.log.push(format!("Precision Charge: {} — +1 to hit (charging)", sh.owner));
        }
    }
    // Wave 4 — the Boost's rules-must-log line, once per melee resolve.
    if evasive_boost_fired {
        out.log.push(format!(
            "{}: {def_owner} — attackers get -1 to hit (always)",
            def.evasive_alias_name
        ));
    }
    if shielded_alias_fired {
        out.log.push(shielded_alias_line(def, def_owner));
    }
    if defense_token_fired {
        out.log.extend(defense_token_lines(def, def_owner));
    }
    // MOR-17a — rules-must-log, once per fight: the gate's verdict, the volley
    // fold's melee twin (same rule name).
    if gate_on && def.regen_gate_charge_in > 0.0 && (regenable > 0 || out.deadly_tally > 0) {
        let gate = def.regen_gate_charge_in;
        out.log.push(if !def.regen_gate_shut && def.regen_target > 0 {
            format!("Warding: {def_owner} ignores wounds on 6+ (charged from over {gate:.0}in)")
        } else {
            format!("Warding: no 6+ ignore, {def_owner} was charged from within {gate:.0}in")
        });
    }
    out.caused += regen_proof + regenable + out.deadly_tally;
    // R3-C2: Deadly lands first (tray-exact order), so wounds that land on an already destroyed defender roll no ignore die.
    let pool_lands_on_dead = tray_exact && regenable > 0 && def.regeneration && def.regen_target > 0 && deadly_wipes.is_some_and(|w| w(&out));
    if pool_lands_on_dead {
        out.log.push(format!("Regeneration: {def_owner} is already destroyed by the Deadly wounds - no ignore roll for the other wounds"));
    }
    out.wounds += if pool_lands_on_dead { regen_proof + regenable } else { ignore_batch(regenable, regen_proof, regen_joined, def, def_owner, tray, &mut out.rolls) };
    // MEL-10r — a wound Regeneration cancels is not TAKEN: the 73 tally counts what landed.
    out.taken = if tally_post_regen { out.wounds + out.deadly_tally } else { out.caused };
    out
}

/// The charge's two Impact pools in the table's order — plain Impact (2+, no AP)
/// and then Heavy Impact (saves at AP(1)), with the defender's Counter models
/// stripping the HEAVY dice first, defender-optimal (`_solo_charge_impact`
/// :6292-6303). A fatigued charger rolls nothing at all (p.13).
///
/// Defender-side reduction: the Counter entry's
/// `impact_reduction_per_model` (dead-parameter recount 2026-09-15,
/// family 1) scales `def.counter_models` — hard 1 pre-EPOCH_13 via
/// `unwrap_or(1)` keeps every earlier replay byte-exact. Stripping the
/// HEAVY dice first, defender-optimal (`_solo_charge_impact`
/// :6292-6303). A fatigued charger rolls nothing at all (p.13).
///
/// Rules 3.6 (`EPOCH_73_V36`) — the `brace_models` carrier flag adds the
/// single rating X once (the caller zeroes it while the defender is Fatigued).
pub fn impact_pools(att: &Ctx, def: &Ctx) -> [(i64, i64); 2] {
    if att.fatigued {
        return [(0, 0), (0, 0)];
    }
    // Rules 3.6 (row W1.TRACE-c) — the Counter cut names itself once per
    // Impact event (arm `counter-in-melee`). The switch is read ONCE here.
    let trace_counter = rule_on(att.rules_epoch, EPOCH_73_V36)
        && crate::mv::plain_memo::trace_rules_on();
    let models = att.models.max(0);
    let heavy_raw = att.heavy_impact * models;
    let counter_cut = def
        .counter_models
        .saturating_mul(def.counter_impact_per_model.unwrap_or(1));
    let brace_cut = if def.brace_models > 0 {
        def.brace_impact_per_model.unwrap_or(1)
    } else {
        0
    };
    let cut = counter_cut + brace_cut;
    if trace_counter && counter_cut > 0 {
        crate::sim::trace_rule("counter-in-melee", "Counter in Melee", &format!(
            "Counter models take {counter_cut} Impact dice off"));
    }
    let heavy_cut = cut.min(heavy_raw);
    [
        (impact_total_dice(att.impact, models, cut - heavy_cut), 0),
        (heavy_raw - heavy_cut, HEAVY_IMPACT_AP),
    ]
}

/// Rules 3.6 (`EPOCH_73_V36`) — Parry's cancellation: every face of 6 or more
/// cancels one hit, the HEAVY pool first (the hits carrying AP are worth more),
/// then the plain pool. `pools` is `impact_pools`'s order: [plain, heavy].
pub fn parry_cancel(faces: &[u8], pools: [(i64, i64); 2]) -> [(i64, i64); 2] {
    let mut left = faces.iter().filter(|&&f| f >= 6).count() as i64;
    let mut out = pools;
    let heavy = left.min(out[1].0);
    out[1].0 -= heavy;
    left -= heavy;
    out[0].0 -= left.min(out[0].0);
    out
}

/// ONE Impact pool on the tray: the hit roll at 2+, then ONE save batch (no
/// to-hit faces reach it, so no Rending sub-batch and no Bane), then its own
/// Regeneration roll — the pool LANDS at once (`_solo_land_wounds` :6337).
///
/// One pool per call on purpose. main.gd:6304 re-checks
/// `_solo_combined_alive(defender) <= 0` before EVERY pool, so an Impact pool
/// that wiped the defender means the Heavy pool never rolls; only the caller,
/// which lands the wounds, can answer that.
///
/// FLAGGED: `guarded_over9` — the table raises the Impact save by 1 when the
/// charge came from over 9" (:6309), a pre-charge gap this port never measured.
/// Tray-exact S10 — `_solo_takedown_pick`'s line: the rule (its unit-level name, else Takedown), the
/// weapon, and the unit of [1] it resolves as.
fn takedown_pick_line(p: &ShootProfile, def_owner: &str) -> String {
    let rule = if p.takedown_rule.is_empty() { "Takedown" } else { p.takedown_rule.as_str() };
    format!("{rule} ({}): targets the most valuable model in {def_owner} — resolved as a unit of [1]", p.name)
}

/// Table's `_solo_hit_mod_info` shooting note (main.gd:8826-8920) in exact fragment order, plus the
/// volley's Indirect / Spotted / Tagged tail (main.gd:5325-5344). Returns `(base_note, full_note)`.
#[allow(clippy::too_many_arguments)]
fn compose_to_hit_note(
    att: &Ctx, def: &Ctx, p: &ShootProfile, mod_dist_in: f64,
    alias_pen: i64, alias_over: f64, alias_name: &str,
    art_gate_ok: bool, art_bonus_val: i64, target_art_applies: bool, target_pen: i64,
    ma: i64, gp: i64, im: i64,
) -> (String, String) {
    let mut notes: Vec<String> = Vec::new();
    let over_nine = mod_dist_in > LONG_RANGE_IN;
    let v36_art = att.artillery_shooter_needs_hold || att.artillery_shooter_over_in > 0.0;
    if att.artillery && over_nine && v36_art {
        notes.push(if art_gate_ok {
            format!("Artillery +{art_bonus_val} (Held, target over {}\")", att.artillery_shooter_over_in as i64)
        } else if att.artillery_shooter_needs_hold && !att.held {
            format!("Artillery: no +{art_bonus_val} (shooter did not Hold)")
        } else {
            format!("Artillery: no +{art_bonus_val} (target within {}\")", att.artillery_shooter_over_in as i64)
        });
    } else if att.artillery {
        notes.push(if over_nine { format!("Artillery +{art_bonus_val}") }
            else { format!("Artillery: no +{art_bonus_val} (target within 9\")") });
    }
    if def.stealth {
        notes.push(if !over_nine { "Stealth: no -1 (within 9\")".into() }
            else if def.stealth_most_models { "Stealth -1 (most models carry it)".into() }
            else { "Stealth -1".into() });
    }
    if alias_pen > 0 && !(def.stealth && over_nine) && (alias_over <= 0.0 || mod_dist_in > alias_over) && !alias_name.is_empty() {
        notes.push(if alias_over > 0.0 && rule_on(def.rules_epoch, EPOCH_73_V36) {
            format!("{alias_name} -{alias_pen} over {}\"", alias_over as i64)
        } else { format!("{alias_name} -{alias_pen}") });
    }
    if def.artillery {
        notes.push(if def.artillery_target_over_in > 0.0 {
            if target_art_applies { format!("Artillery target -{target_pen} over {}\" (unmoved)", def.artillery_target_over_in as i64) }
            else if def.moved_round == def.round { format!("Artillery target: no -{target_pen} (moved this round)") }
            else if !def.artillery_target_most_models { format!("Artillery target: no -{target_pen} (most models lack it)") }
            else { format!("Artillery target: no -{target_pen} (within {}\")", def.artillery_target_over_in as i64) }
        } else if over_nine { format!("Artillery target -{target_pen}") }
        else { format!("Artillery target: no -{target_pen} (within 9\")") });
    }
    if def.aircraft_hit_penalty > 0 {
        let an = if def.aircraft_hit_name.is_empty() { "Aircraft" } else { def.aircraft_hit_name };
        notes.push(format!("{an} -{}", def.aircraft_hit_penalty));
    }
    if def.evasive {
        notes.push(if !def.evasive_stand_down_name.is_empty() {
            format!("{}: -1 to hit (base Evasive stood down)", def.evasive_stand_down_name)
        } else { "Evasive -1".into() });
    }
    if att.growth_hit_mod != 0 { notes.push(format!("Growth {:+}", att.growth_hit_mod)); }
    let (mut ma_done, mut gp_done, mut feat_done) = (false, false, false);
    for e in att.shot_mod_notes {
        if e.name.is_empty() { break; }
        let hit = match e.kind {
            0 => if e.over_in <= 0.0 || mod_dist_in > e.over_in { e.bonus } else { 0 },
            1 => { ma_done = true; ma }
            2 => { gp_done = true; gp }
            3 => { feat_done = true; att.feat_hit_bonus }
            _ => 0,
        };
        if hit != 0 { notes.push(format!("{} {hit:+}", e.name)); }
    }
    if !ma_done && ma != 0 { notes.push(format!("Mobile Artillery {ma:+}")); }
    if !gp_done && gp != 0 { notes.push(format!("Grounded Precision {gp:+}")); }
    if !feat_done && att.feat_hit_bonus != 0 { notes.push(format!("Precision Feat {:+}", att.feat_hit_bonus)); }
    if att.instinctive_applied != 0 {
        let n = if att.instinctive_name.is_empty() { "Instinctive" } else { att.instinctive_name };
        notes.push(format!("{n} {:+} (closest target)", att.instinctive_applied));
    }
    let base_note = notes.join(", ");
    if att.moved_this_round && (p.indirect || (def.indirect_mark && rule_on(att.rules_epoch, EPOCH_73_V36))) {
        if rule_on(att.rules_epoch, EPOCH_73_V36) { notes.push("Indirect: no moved penalty".into()); }
        else if im != 0 { notes.push(format!("Indirect moved {im}")); }
    }
    if att.moved_this_round && att.indirect_own && !p.indirect { notes.push("Indirect: no moved penalty".into()); }   // EPOCH_94_PARITY_BATCH
    if att.spot_hit_note != 0 { notes.push(format!("Spotted {:+}", att.spot_hit_note)); }
    if att.tag_hit_note != 0 { notes.push(format!("Tagged {:+}", att.tag_hit_note)); }
    (base_note, notes.join(", "))
}

/// ONE Impact pool's hit roll — the `attack` slot `resolve_impact_pool_at`
/// records, split out so a Parry event can roll every pool's hits before any
/// save. Returns the recorded roll and its hit count.
pub fn impact_hit_roll(dice: i64, att_owner: &str, tray: &mut Tray) -> (Roll, i64) {
    let faces = tray.roll(dice as usize);
    let hits = faces_to_hits(&faces, IMPACT_HIT_TARGET as u8) as i64;
    (
        Roll { kind: "attack", count: dice, target: IMPACT_HIT_TARGET, faces, owner: att_owner.into() },
        hits,
    )
}

pub fn resolve_impact_pool_with_tray(
    dice: i64,
    ap: i64,
    att_owner: &str,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
) -> ShootResult {
    resolve_impact_pool_at(dice, ap, att_owner, def, def_owner, None, tray)
}

/// ONE Impact pool's save batch once its hits are known — the tail of
/// `resolve_impact_pool_at`. A Parry event calls this per pool after its
/// cancellation, in the pools' own order.
pub fn impact_saves_with_tray(
    hits: i64, ap: i64, def: &Ctx, def_owner: &str, charge: Option<(f64, bool)>, tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if hits <= 0 { return out; }
    // SHO-17 — the 6" gate off the defender's context; 0.0 below the epoch keeps the old read.
    let gate_in = if def.guarded_charge_over_in > 0.0 { def.guarded_charge_over_in } else { LONG_RANGE_IN };
    let (over9, epoch_gate) = match charge {
        None => (def.guarded, false),
        Some((gap_in, _)) => {
            let over = def.guarded && gap_in > gate_in && !def.sturdy_boost_gates_guarded;
            (over, over && def.guarded_charge_over_in > 0.0)
        }
    };
    let exact = over9 && (matches!(charge, Some((_, true))) || epoch_gate);
    if over9 && !exact { out.mark("guarded_over9"); }
    if epoch_gate {
        let rule = if def.guarded_name.is_empty() { "Guarded" } else { def.guarded_name };
        out.log.push(format!("{rule}: {def_owner} charged from over {}in — +1 Defense", gate_in as i64));
    }
    let bare = ShootProfile { ap, ..Default::default() };
    let sd = guarded_defense(shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), exact, def.def_floor());
    let w = save_batch(&bare, def, def_owner, hits, sd, ap, false, false, 1, false, tray, &mut out);
    out.caused = w;
    // MOR-17a (rules 3.6): Warding's 6+ needs a charge from OVER its gate. A
    // charge from the gate or closer folds nothing — the GD side's
    // `_solo_land_wounds` gate, mirrored here. `None` keeps the old blanket read.
    let regen_def = &match charge {
        Some((gap_in, _)) if def.gate_in_force() && def.regen_gate_charge_in > 0.0 && gap_in <= def.regen_gate_charge_in => def.gate_shut(),
        Some((gap_in, _)) => def.open_named(gap_in, true),
        _ => *def,
    };
    out.wounds = regen_batch(w, 0, regen_def, def_owner, tray, &mut out.rolls);
    out
}

/// `resolve_impact_pool_with_tray` knowing the charge: `charge` = (the pre-charge gap in inches,
/// `Seams::tray_exact`). Tray-exact: a Guarded-family defender charged from over 9" saves at
/// +1 Defense (main.gd:7440-7441), unflagged; without the switch the old save, flagged only when
/// that gate really applies. `None` (no charge known) keeps the old blanket flag.
pub fn resolve_impact_pool_at(
    dice: i64,
    ap: i64,
    att_owner: &str,
    def: &Ctx,
    def_owner: &str,
    charge: Option<(f64, bool)>,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if dice <= 0 {
        return out;
    }
    let (roll, hits) = impact_hit_roll(dice, att_owner, tray);
    out.rolls.push(roll);
    if hits <= 0 {
        return out;
    }
    out.wounds = out.absorb(impact_saves_with_tray(hits, ap, def, def_owner, charge, tray));
    out
}

/// BLOCK B3 — Breath Attack's hit->defense->wound leg on the tray:
/// `_solo_resolve_saves`/`_solo_save_batch` (main.gd:6310-6459) called with a
/// FIXED hit count — Blast(3) already applied by the caller (main.gd:5307-
/// 5308), so unlike Impact's `resolve_impact_pool_with_tray` this pool never
/// draws an "attack" roll of its own — then `_solo_land_wounds` (main.gd:
/// 6596-6600, Regeneration on the RAW unsaved count). A bare profile carrying
/// only the pool's AP, the Impact precedent's shape (no Bane, no Shred, no
/// Deadly — Breath Attack's own `bprofile` carries none of them either).
pub fn resolve_breath_attack_with_tray(
    hits: i64,
    ap: i64,
    def: &Ctx,
    def_owner: &str,
    tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if hits <= 0 {
        return out;
    }
    let bare = ShootProfile { ap, ..Default::default() };
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), ap, false, false, 1, false, tray, &mut out);
    out.caused = w;
    out.wounds = regen_batch(w, 0, def, def_owner, tray, &mut out.rolls);
    out
}

/// CC-6a/6b/7a/7b: a damage spell's fixed hits saved on the tray, `_solo_resolve_spell_damage` main.gd:5747 -> `_solo_save_batch` at
/// the Defense a SPELL hit meets (NML-104): the unit's own Defense, Armor already in it, and neither Shielded nor Cover nor the over-9"
/// family (their wording limits them to attacks), so the batch saves at `def.defense`, never the volley's ladder.
/// CC-7a: when `upgraded > 0`, the on-6 AP batch (`ap + on6_ap`) saves FIRST, then `hits - upgraded` at `ap`, combined into one landing.
/// CC-7b: Bane / widened `bane` window `(active, from)`, Lacerate (`rules`), and `shred` ride the shared `save_batch`.
/// CC-6b: Deadly(X) pushes per-model groups (`push_deadly_groups`), Regeneration / Resistance roll at the SPELL threshold
/// (`def.regen_target_spell`, falling back to `def.regen_target`), and `ignores_regen` bypasses only when `bypass_skips_ignore()` holds.
#[allow(clippy::too_many_arguments)]
pub fn resolve_spell_hits_with_tray(
    hits: i64, upgraded: i64, ap: i64, on6_ap: i64, deadly: i64, ignores_regen: bool,
    bane: (bool, i64), shred: bool, rules: &[String], spell_name: &str, def: &Ctx, def_owner: &str, tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if hits <= 0 {
        return out;
    }
    out.bane_low = if bane.0 && bane.1 < 6 { bane.1 } else { 0 };
    let upgraded = upgraded.clamp(0, hits);
    let base = ShootProfile { ap, deadly, bane: bane.0, shred, rules: rules.to_vec(), ..Default::default() };
    let mut w = 0;
    if upgraded > 0 {
        let hi = ShootProfile { ap: ap + on6_ap, ..base.clone() };
        w += save_batch(&hi, def, def_owner, upgraded, def.defense, ap + on6_ap, false, false, 1, deadly > 0, tray, &mut out);
    }
    if hits - upgraded > 0 {
        w += save_batch(&base, def, def_owner, hits - upgraded, def.defense, ap, false, false, 1, deadly > 0, tray, &mut out);
    }
    let spell_target = if def.regen_target_spell > 0 { def.regen_target_spell } else { def.regen_target };
    let spell_def = Ctx { regen_target: spell_target, ..*def };
    let bypass = ignores_regen && spell_def.bypass_skips_ignore();
    out.caused = w;
    if deadly > 0 {
        let first = out.deadly_groups.len();
        push_deadly_groups(&mut out, w, deadly.max(1), bypass, ignores_regen, &spell_def, def_owner, tray, None);
        out.deadly_lines.push((spell_name.into(), w, deadly.max(1), out.deadly_groups.len() - first));
        out.deadly_tally = w;
    } else {
        out.wounds = ignore_batch(if bypass { 0 } else { w }, if bypass { w } else { 0 }, if ignores_regen && !bypass { w } else { 0 }, &spell_def, def_owner, tray, &mut out.rolls);
    }
    out
}

/// The Storm Attack family's payload (wave 3): `hits` direct hits landed as
/// ONE save batch carrying the burst's keyword facet — Bane's six-re-roll and
/// Shred's save-fail +1 through the same `save_batch` legs every ported Bane/
/// Shred carrier rides, AP(1) as the batch's own AP. Bane's wounds cut through
/// Regeneration (`_solo_ignores_regen`, the volley tail's own ladder at the
/// `p.bane` arm above), the other facets land regenerable. The table twin is
/// `_solo_apply_storm_attack`'s `_solo_save_batch` call (main.gd:17287).
pub fn resolve_storm_hits_with_tray(
    hits: i64, ap: i64, bane: bool, shred_grant: bool, def: &Ctx, def_owner: &str, tray: &mut Tray,
) -> ShootResult {
    let mut out = ShootResult::default();
    if hits <= 0 { return out; }
    let bare = ShootProfile { ap, bane, ..Default::default() };
    let w = save_batch(&bare, def, def_owner, hits, shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), ap, shred_grant, false, 1, false, tray, &mut out);
    out.caused = w;
    out.wounds = if bane { w } else { regen_batch(w, 0, def, def_owner, tray, &mut out.rolls) };
    out
}

// ------------------------------------- D1-B5b: MORALE on the same tray ---

/// `AiCombatMath.Morale` — the three outcomes of a morale test.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Morale {
    Passed,
    Shaken,
    Routed,
}

/// ONE morale test on the tray — `main._solo_morale_test` :8305, in its order:
///
///   the test die at the Banner-modified Quality target [:8336] -> Fearless's
///   single re-roll of a FAILED test, a 4+ counting as passed [:8347] -> No
///   Retreat, which turns the still-failed test into a pass and pays for it in
///   self-wounds, one die per wound needed to destroy the unit [:8365].
///
/// TWO things a naive port gets wrong, both pinned by the tests below:
///
///   1. An ALREADY Shaken unit fails automatically and draws NO die at all
///      (:8310-8317). Burn one there and every later activation of the game is
///      on different faces.
///   2. ROUT exists only in MELEE (p.10, PDF-verified): a shooting-caused
///      failure is Shaken whatever the unit's strength. `melee` is that gate.
///
/// The morale die is stamped `roll_kind` "attack" like every other tray roll
/// (main.gd:8336), so the replay gate can only tell it apart by where it sits.
/// The step API names the three dice as the table does (`Tray::name_next`: "morale", "fearless", "no_retreat"),
/// and the Fearless recovery die and the No Retreat self-wound dice say the table's line after the roll.
///
/// Returns the outcome and the report; `wounds` are No Retreat's self-wounds,
/// which land DIRECTLY — "can't be ignored", so no Regeneration roll follows.
///
/// NOT PORTED: the spell morale tokens that join the Banner bonus in the target
/// (:8348-8355) — this port carries no spell-token ledger.
#[allow(clippy::too_many_arguments)] // the step's own owner stamp is one optional seat, beside the seven resolver inputs
pub fn resolve_morale_with_tray(
    unit: &Ctx,
    owner: &str,
    owner_unit: Option<usize>,
    melee: bool,
    below_half: bool,
    shaken: bool,
    wounds_to_destroy: i64,
    tray: &mut Tray,
) -> (Morale, ShootResult) {
    let mut out = ShootResult::default();
    let failed = if below_half && melee { Morale::Routed } else { Morale::Shaken };
    let mut result = if shaken {
        failed // `morale_result_shaken` :558 — no Quality roll, and no draw.
    } else {
        let target = morale_target(unit.quality, unit.morale_bonus);
        tray.name_next("morale"); // the table's kind (main.gd `_solo_morale_test`): its dice line says passed/failed
        tray.owner_next(owner_unit);
        let faces = tray.roll(1);
        let passed = faces_to_hits(&faces, target as u8) > 0;
        out.rolls.push(Roll { kind: "attack", count: 1, target, faces, owner: owner.into() });
        if passed {
            Morale::Passed
        } else {
            failed
        }
    };
    if result != Morale::Passed && unit.fearless {
        tray.name_next("fearless"); // the table's kind (main.gd `_solo_morale_test`): the recovery die is its own kind
        tray.owner_next(owner_unit);
        let faces = tray.roll(1);
        let passed = faces_to_hits(&faces, FEARLESS_RECOVER_TARGET as u8) > 0;
        out.rolls.push(Roll {
            kind: "attack",
            count: 1,
            target: FEARLESS_RECOVER_TARGET,
            faces,
            owner: owner.into(),
        });
        if passed {
            result = Morale::Passed;
        }
        // The table's line after the recovery die, same words for both outcomes (rule name exact, target as the table prints it).
        tray.say(|| LogLine { rule: "morale", category: Category::Combat, side: unit.side, detail: None,
            text: format!("{owner} is Fearless — recovery die ({FEARLESS_RECOVER_TARGET}+) {}", if passed { "holds" } else { "fails" }) });
    }
    if result != Morale::Passed && unit.no_retreat {
        // `maxi(1, wounds_to_destroy)` :8364 — the zero-die rule applies here
        // too, and the recorded target is the SAFE face, `MAX + 1`.
        let n = wounds_to_destroy.max(1);
        tray.name_next("no_retreat"); // the table's kind (main.gd `_solo_morale_test`): the self-wound dice are their own kind
        tray.owner_next(owner_unit);
        let faces = tray.roll(n as usize);
        out.wounds =
            faces.iter().filter(|&&f| (f as i64) <= NO_RETREAT_SELF_WOUND_MAX).count() as i64;
        out.caused = out.wounds;
        out.rolls.push(Roll {
            kind: "attack",
            count: n,
            target: NO_RETREAT_SELF_WOUND_MAX + 1,
            faces,
            owner: owner.into(),
        });
        result = Morale::Passed;
        // The table's line after the self-wound dice, before the wounds land (`_solo_morale_test`).
        let w = out.wounds;
        tray.say(|| LogLine { rule: "morale", category: Category::Combat, side: unit.side, detail: None,
            text: format!("{owner} has No Retreat — the test counts as passed; {w} self-wound{} (1-{NO_RETREAT_SELF_WOUND_MAX} on {n} dice, can't be ignored)",
                if w == 1 { "" } else { "s" }) });
    }
    (result, out)
}

#[cfg(test)]
#[path = "tests/dice/mod.rs"]
mod tests;

//! GATE G3 (NML-1073 M2-2) — the ROLLOUT VALUE, pinned on the recorded ACT
//! corpus `tests/fixtures/acts_25.jsonl` (the same 23 activations G1/G2 use;
//! see `tests/menu.rs` for how it was recorded and why it was re-recorded).
//!
//! Each act's `trace.rs` is a list of `{idx, rs}`: for every candidate that
//! survived the 1-ply prefilter, the number `AiPlanner.plan_with_rollout`
//! (ai_planner.gd:200-202) computed as
//! `_blend_score(rollout_boundaries(state, action, player), player)`. That is
//! the whole M2-2 contract: `idx` names a candidate, `rs` is what the search
//! paid a full round rollout to learn about it, and the pick is an argmax over
//! exactly those numbers.
//!
//! `idx` is the candidate's position in the UNSORTED build order of
//! `plan_with_rollout`'s prefilter (:129-141): every un-activated living unit of
//! the acting player, in CAPTURE order, each contributing its whole menu in menu
//! order. This file rebuilds that flat list from `trace.menus` and checks it
//! against `trace.scored` before it trusts a single `idx` — the instrument comes
//! first, the measurement second.
//!
//! The candidate handed to the rollout is the RECORDED one, not the one
//! `menu::candidates` regenerates. G2 already proved those are identical; using
//! the recording here keeps G3 measuring the ROLLOUT rather than re-measuring
//! the menu.

use std::collections::BTreeMap;

use nml_core::acts::Knobs;
use nml_core::menu::Candidate;
use nml_core::playout::Policy;
use nml_core::rollout::{Rollout, Stop};
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, Act, ActCorpus, Seams, State, Terrain};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// The parity bar. `rs` is a blend of f64 scores written by
/// `JSON.stringify(.., full_precision=true)`, so an exact hit is achievable and
/// anything above 1e-9 is a real difference in the arithmetic, not in the print.
const RS_EPS: f64 = 1e-9;

fn corpus() -> ActCorpus {
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

/// One entry of the flat build order — `idx` is this entry's position.
struct Entry<'a> {
    key: &'a str,
    cand: &'a Candidate,
}

/// `AiPlanner.plan_with_rollout` ai_planner.gd:129-141 — the prefilter's
/// iteration, rebuilt off the RECORDED menus. Capture order, then menu order.
fn flat_build_order<'a>(act: &'a Act) -> Vec<Entry<'a>> {
    let st: &State = &act.state;
    let mut out = Vec::new();
    for i in 0..st.units() {
        if st.player[i] != act.player || st.activated[i] || st.alive[i] <= 0 {
            continue;
        }
        let key = st.key(i);
        let menu = act
            .menus
            .get(key)
            .unwrap_or_else(|| panic!("pool unit {key} has no recorded menu"));
        for c in menu {
            out.push(Entry { key, cand: c });
        }
    }
    out
}

/// What one full sweep of the corpus measured.
#[derive(Default)]
struct Report {
    /// Rollouts run.
    n: usize,
    /// `rs` reproduced bit for bit.
    exact: usize,
    /// `rs` reproduced within `RS_EPS` (a superset of `exact`).
    within: usize,
    max_diff: f64,
    /// The candidate that missed by the most, for the failure message.
    worst: String,
    /// boundary count -> how many rollouts produced it.
    boundaries: BTreeMap<usize, usize>,
    /// stop reason -> count.
    stops: BTreeMap<&'static str, usize>,
    /// Total imagined round boundaries priced.
    priced: usize,
}

fn stop_name(s: Stop) -> &'static str {
    match s {
        Stop::Horizon => "horizon",
        Stop::GameEnd => "game-end",
        Stop::TailCap => "tail-cap",
        Stop::Guard => "GUARD",
    }
}

/// The G3 sweep with BOTH halves of the configuration exposed to a red proof:
/// `bend` perturbs the recorded search knobs, `bend_policy` the greedy brain
/// itself. Both are the identity for the gate.
fn sweep_board(
    c: &ActCorpus,
    terrain: &Terrain,
    bend: impl Fn(&mut Knobs),
    bend_policy: impl Fn(&mut Policy),
) -> Report {
    let statics = build_act_statics(c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement };
    let mut policy = Policy::new(&statics, terrain, seams);
    bend_policy(&mut policy);
    let mut knobs = c.knobs;
    bend(&mut knobs);
    let roll = Rollout::new(policy, knobs);
    let mut sc = Scratch::default();
    let mut r = Report::default();
    for (ai, act) in c.acts.iter().enumerate() {
        let flat = flat_build_order(act);
        for rv in &act.rs {
            let e = &flat[rv.idx as usize];
            let (ends, stop) = roll
                .rollout_traced(&act.state, e.cand, act.player, -1, &mut sc)
                .unwrap_or_else(|u| panic!("act {ai} idx {}: unsupported {u:?}", rv.idx));
            let got = roll.blend_score(&ends, act.player, act.statics.opener_seat);
            let diff = (got - rv.rs).abs();
            r.n += 1;
            if got.to_bits() == rv.rs.to_bits() {
                r.exact += 1;
            }
            if diff <= RS_EPS {
                r.within += 1;
            } else if diff > r.max_diff {
                r.worst = format!(
                    "act {ai} idx {} unit {} kind {}: {got:.17} vs recorded {:.17}",
                    rv.idx, e.key, e.cand.kind, rv.rs
                );
            }
            if diff > r.max_diff {
                r.max_diff = diff;
            }
            *r.boundaries.entry(ends.len()).or_insert(0) += 1;
            *r.stops.entry(stop_name(stop)).or_insert(0) += 1;
            r.priced += ends.len();
        }
    }
    r
}

fn sweep_with(
    c: &ActCorpus,
    bend: impl Fn(&mut Knobs),
    bend_policy: impl Fn(&mut Policy),
) -> Report {
    sweep_board(c, &c.terrain, bend, bend_policy)
}

fn sweep(c: &ActCorpus, bend: impl Fn(&mut Knobs)) -> Report {
    sweep_with(c, bend, |_| {})
}

/// The instrument before the measurement: `idx` must name the candidate the
/// recorder says it names, or every G3 number is measured against the wrong row.
#[test]
fn the_flat_build_order_is_the_recorded_idx_space() {
    let c = corpus();
    let (mut units, mut cands, mut checked) = (0usize, 0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        // The pool the recorder wrote must be the filter this file reproduces.
        let mine: Vec<&str> = (0..act.state.units())
            .filter(|&i| {
                act.state.player[i] == act.player
                    && !act.state.activated[i]
                    && act.state.alive[i] > 0
            })
            .map(|i| act.state.key(i))
            .collect();
        let theirs: Vec<&str> = act.pool.iter().map(|s| s.as_str()).collect();
        assert_eq!(mine, theirs, "act {ai}: pool order is not capture order");
        units += mine.len();
        let flat = flat_build_order(act);
        cands += flat.len();
        assert_eq!(
            flat.len(),
            act.scored.len(),
            "act {ai}: {} menu entries but {} scored rows",
            flat.len(),
            act.scored.len()
        );
        for s in &act.scored {
            let e = &flat[s.idx as usize];
            assert_eq!(e.key, s.unit, "act {ai} idx {}: unit", s.idx);
            assert_eq!(e.cand.kind, s.kind, "act {ai} idx {}: kind", s.idx);
            checked += 1;
        }
        for &pi in &act.pool_idx {
            assert!((pi as usize) < flat.len(), "act {ai}: pool idx {pi} out of range");
        }
        assert_eq!(act.pool_idx.len(), act.rs.len(), "act {ai}: pool and rs disagree");
        for (p, rv) in act.pool_idx.iter().zip(&act.rs) {
            assert_eq!(*p, rv.idx, "act {ai}: rs is not in pool order");
        }
    }
    println!(
        "idx space: {cands} candidates over {units} pool units in {} acts, \
         {checked} (unit, kind) rows cross-checked against trace.scored",
        c.acts.len()
    );
    assert_eq!(cands, 529, "the recorded candidate count is part of the contract");
}

/// The corpus must have been recorded by the search this port implements — a
/// net-guided playout or the fitted eval would be a different brain, and green
/// against it would mean nothing.
#[test]
fn the_corpus_was_recorded_by_the_ported_search() {
    let c = corpus();
    let net = c.acts.iter().filter(|a| !a.statics.heuristic_playout()).count();
    let fitted = c.acts.iter().filter(|a| a.statics.fit_mode).count();
    let arb = c.acts.iter().filter(|a| a.statics.playout_search).count();
    let openers = c.acts.iter().filter(|a| a.statics.opener_seat).count();
    println!(
        "statics: net-guided {net}/{}, fit_mode {fitted}, playout_search {arb}, \
         opener_seat {openers}",
        c.acts.len()
    );
    println!(
        "knobs: horizon {} tail_cap {}/{} imagined_round_end {} depth_discount {} \
         seat_mode {} seams spacing={} cast={}",
        c.knobs.horizon,
        c.knobs.tail_cap_p1,
        c.knobs.tail_cap_p2,
        c.knobs.imagined_round_end,
        c.knobs.depth_discount,
        c.knobs.seat_mode,
        c.knobs.seam_spacing,
        c.knobs.seam_cast
    );
    assert_eq!(net, 0, "{net} acts used a net-guided playout, which this port declines");
    assert_eq!(fitted, 0, "{fitted} acts used the fitted eval, which score.rs does not port");
    assert!(openers > 0, "no act carries opener_seat — the seat red proof would be vacuous");
}

#[test]
fn g3_the_rust_rollout_value_matches_every_recorded_pool_candidate() {
    let c = corpus();
    let horizon = c.knobs.horizon.max(1) as usize;
    let r = sweep(&c, |_| {});
    let hist: Vec<String> =
        r.boundaries.iter().map(|(b, n)| format!("{b} boundary(-ies): {n}")).collect();
    let stops: Vec<String> = r.stops.iter().map(|(s, n)| format!("{s}: {n}")).collect();
    println!(
        "G3 rollout value: {}/{} candidates within {RS_EPS:.0e} ({} exact), \
         max |diff| {:.3e}",
        r.within, r.n, r.exact, r.max_diff
    );
    println!("G3 boundaries: {} | {} priced leaves", hist.join(", "), r.priced);
    println!("G3 stop reasons: {}", stops.join(", "));
    assert_eq!(r.n, 266, "the recorded pool size is part of the contract");
    // A boundary array is never empty and never longer than the horizon: index 0
    // is the end of the CURRENT round, and the loop returns as soon as
    // `rounds_left` runs out (ai_planner.gd:388-390).
    for (&b, &n) in &r.boundaries {
        assert!(b >= 1 && b <= horizon, "{n} rollouts returned {b} boundaries, horizon is {horizon}");
    }
    assert_eq!(
        r.stops.get("GUARD").copied().unwrap_or(0),
        0,
        "a rollout hit the (units + 2) * rounds_left backstop — that is a policy bug, not a rule"
    );
    assert_eq!(r.within, r.n, "{} candidates differ; worst: {}", r.n - r.within, r.worst);
}

/// RED PROOF 1 — the depth discount is load-bearing. 0.5 -> 0.6 reweights every
/// blend that prices more than one boundary; a rollout that ends at a single
/// boundary is arithmetically immune (total/weights = score either way), so the
/// count that moves is exactly the multi-boundary population, and that is
/// reported rather than glossed as "some".
#[test]
fn the_depth_discount_is_load_bearing() {
    let c = corpus();
    let base = sweep(&c, |_| {});
    let multi: usize = base.boundaries.iter().filter(|(&b, _)| b > 1).map(|(_, n)| *n).sum();
    let bent = sweep(&c, |k| k.depth_discount = 0.6);
    println!(
        "RED depth_discount 0.5 -> 0.6: {} of {} candidates differ \
         (multi-boundary population: {multi}), max |diff| {:.3e}",
        bent.n - bent.within,
        bent.n,
        bent.max_diff
    );
    assert!(
        bent.n - bent.within > 0,
        "changing the depth discount moved nothing — the blend cannot fail"
    );
    assert_eq!(
        bent.n - bent.within,
        multi,
        "exactly the multi-boundary rollouts should move"
    );
}

/// RED PROOF 2 — the seat branch is load-bearing. The corpus was recorded at
/// seat_mode 0 (both seats blend), so forcing mode 1 must change the value of
/// every OPENER-seat candidate whose rollout has more than one boundary: it
/// switches that seat to a last-boundary-only vote. Responder-seat candidates
/// are untouched, which is the branch's whole point and is asserted, not assumed.
#[test]
fn the_seat_branch_is_load_bearing() {
    let c = corpus();
    assert_eq!(c.knobs.seat_mode, 0, "the corpus is the seat_off recording");
    let on = sweep(&c, |k| k.seat_mode = 1);
    let inv = sweep(&c, |k| k.seat_mode = 2);
    println!(
        "RED seat_mode 0 -> 1 (opener votes last): {} of {} differ; \
         0 -> 2 (responder votes last): {} of {} differ",
        on.n - on.within,
        on.n,
        inv.n - inv.within,
        inv.n
    );
    assert!(on.n - on.within > 0, "seat_mode 1 moved nothing on a corpus that has openers");
    assert!(inv.n - inv.within > 0, "seat_mode 2 moved nothing");
    // The two modes partition the pool: a candidate cannot move under both.
    assert_eq!(
        (on.n - on.within) + (inv.n - inv.within),
        {
            let base = sweep(&c, |_| {});
            base.boundaries.iter().filter(|(&b, _)| b > 1).map(|(_, n)| *n).sum::<usize>()
        },
        "modes 1 and 2 must split the multi-boundary population between the seats"
    );
}

/// RED PROOF 3 — the imagined round end is load-bearing. Turning it off
/// (`NML_IMAGINED_ROUND_END=off`, the A/B seam that restores the frozen-ledger
/// boundary) stops the seize from being booked, so every boundary keeps the
/// marker ownership the round started with.
#[test]
fn the_imagined_round_end_is_load_bearing() {
    let c = corpus();
    let off = sweep(&c, |k| k.imagined_round_end = false);
    println!(
        "RED imagined_round_end off: {} of {} candidates differ, max |diff| {:.3e}",
        off.n - off.within,
        off.n,
        off.max_diff
    );
    assert!(
        off.n - off.within > 0,
        "skipping the round-end bookkeeping moved nothing — the seize is invisible to the blend"
    );
}

/// RED PROOF 4 — the tail cap truncates. The corpus ran uncapped; a cap of 1
/// must collapse every rollout of that seat to a single mid-round boundary.
#[test]
fn the_tail_cap_truncates_mid_round() {
    let c = corpus();
    assert_eq!((c.knobs.tail_cap_p1, c.knobs.tail_cap_p2), (0, 0), "the corpus ran uncapped");
    let capped = sweep(&c, |k| {
        k.tail_cap_p1 = 1;
        k.tail_cap_p2 = 1;
    });
    let single = capped.boundaries.get(&1).copied().unwrap_or(0);
    println!(
        "RED tail_cap 1: {} of {} candidates differ, {single}/{} rollouts stop at one \
         mid-round boundary ({} tail-cap stops)",
        capped.n - capped.within,
        capped.n,
        capped.n,
        capped.stops.get("tail-cap").copied().unwrap_or(0)
    );
    assert_eq!(capped.stops.get("tail-cap").copied().unwrap_or(0), capped.n);
    assert_eq!(single, capped.n, "a capped rollout must return exactly one boundary");
    assert!(capped.n - capped.within > 0, "the cap changed no value at all");
}

/// RED PROOF 5 — R9's rich/cheap LEAF SPLIT is load-bearing. The rollout prices
/// OUR side's imagined steps with the reply threat and the opponent's without
/// it; forcing either leaf onto both sides must move values, or the split is
/// decorative and G3 would be green for the wrong reason.
#[test]
fn the_rich_cheap_leaf_split_is_load_bearing() {
    let c = corpus();
    let all_rich = sweep_with(&c, |_| {}, |p| p.force_leaf = Some(true));
    let all_cheap = sweep_with(&c, |_| {}, |p| p.force_leaf = Some(false));
    println!(
        "RED leaf forced rich: {} of {} differ (max |diff| {:.3e}); \
         forced cheap: {} of {} differ (max |diff| {:.3e})",
        all_rich.n - all_rich.within,
        all_rich.n,
        all_rich.max_diff,
        all_cheap.n - all_cheap.within,
        all_cheap.n,
        all_cheap.max_diff
    );
    assert!(
        all_rich.n - all_rich.within > 0,
        "pricing the imagined OPPONENT richly changed nothing"
    );
    assert!(
        all_cheap.n - all_cheap.within > 0,
        "pricing our OWN imagined side cheaply changed nothing"
    );
}

/// RED PROOF 6 — the HORIZON is load-bearing, and with it the whole second
/// imagined round: `_cross_round` only ever runs when the horizon is greater
/// than 1, so a horizon of 1 must move exactly the rollouts that reached a
/// second boundary.
#[test]
fn the_horizon_and_the_round_crossing_are_load_bearing() {
    let c = corpus();
    let base = sweep(&c, |_| {});
    let multi: usize = base.boundaries.iter().filter(|(&b, _)| b > 1).map(|(_, n)| *n).sum();
    let flat = sweep(&c, |k| k.horizon = 1);
    println!(
        "RED horizon 2 -> 1 (no round crossing at all): {} of {} candidates differ, \
         max |diff| {:.3e}; second-round population {multi}",
        flat.n - flat.within,
        flat.n,
        flat.max_diff
    );
    assert_eq!(flat.boundaries.keys().copied().collect::<Vec<_>>(), vec![1]);
    assert_eq!(
        flat.n - flat.within,
        multi,
        "exactly the rollouts that crossed a round should move"
    );
}

/// The rollout policy's own TUNABLES sit on a plateau in this corpus, and that
/// is measured rather than assumed. Neither `_safe_advance`'s D22 cover bonus
/// nor the p.13 Strider/Flying exemption moves a single rollout value — the
/// patient advance never wins the greedy argmax inside a playout (it forgoes the
/// marker, which is precisely why `plan_with_rollout` needs its R8 pool
/// guarantee at the ROOT, ai_planner.gd:170-176), and no imagined charge in
/// these 23 activations has both a gap past the 6" difficult cap and a corridor
/// through difficult ground.
///
/// So this file does NOT claim those two branches as gated. The branch that
/// proves the rollout really walks `policy_candidates` / `policy_step` is the
/// leaf split above: forcing either leaf moves 165 and 159 of 266 values, which
/// is impossible unless every imagined activation is being scored here.
#[test]
fn the_rollout_policy_tunables_are_measured_not_assumed() {
    let c = corpus();
    let mut moved = 0usize;
    for b in [5.0f64, 3.0, 1.0, 0.0] {
        let bent = sweep_with(&c, |_| {}, |p| p.tuning.cover_bonus_in = b);
        println!(
            "PROBE policy cover bonus 6.0 -> {b}: {} of {} differ",
            bent.n - bent.within,
            bent.n
        );
        moved += bent.n - bent.within;
    }
    let nd = sweep_with(&c, |_| {}, |p| p.tuning.honour_no_difficult = false);
    println!("PROBE Strider/Flying exemption off: {} of {} differ", nd.n - nd.within, nd.n);
    moved += nd.n - nd.within;
    // The restricted menu itself must still be the four-entry one, or the
    // plateau above would be the plateau of a menu that is simply not built.
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement };
    let policy = Policy::new(&statics, &c.terrain, seams);
    let mut sc = Scratch::default();
    let mut kinds = [0usize; 4];
    let mut menus = 0usize;
    for act in &c.acts {
        for i in 0..act.state.units() {
            if act.state.player[i] != act.player
                || act.state.activated[i]
                || act.state.alive[i] <= 0
            {
                continue;
            }
            menus += 1;
            for cand in policy.policy_candidates(&act.state, i, &mut sc) {
                kinds[cand.kind as usize] += 1;
            }
        }
    }
    println!(
        "policy menus at the act roots: {menus} menus, HOLD {} ADVANCE {} RUSH {} CHARGE {} \
         (plateau total: {moved} of 266 x 5 probes)",
        kinds[0], kinds[1], kinds[2], kinds[3]
    );
    assert_eq!(menus, 73, "one restricted menu per pool unit");
    assert!(kinds.iter().all(|&k| k > 0), "a whole candidate kind is missing from the policy menu");
}

/// RED PROOF 7 — the BOARD is load-bearing inside the rollout. `resolve` re-probes
/// the mover's cover at its post-move centre (battle_sim.gd:598-600), and a
/// rollout invents destinations no recorder ever visited, so that probe cannot
/// be replayed from a recording — it has to be computed. Take the board away and
/// the imagined cover (and with it every EV the leaf prices) must change.
#[test]
fn the_board_is_load_bearing_inside_the_rollout() {
    let c = corpus();
    let blank = Terrain::absent();
    let bent = sweep_board(&c, &blank, |_| {}, |_| {});
    println!(
        "RED terrain absent: {} of {} candidates differ, max |diff| {:.3e}",
        bent.n - bent.within,
        bent.n,
        bent.max_diff
    );
    assert!(
        bent.n - bent.within > 0,
        "removing the board changed nothing — the post-move cover probe is not being made"
    );
}

/// What this fixture CANNOT gate, stated rather than hidden — the same duty
/// `tests/menu.rs::the_oracle_names_what_it_does_not_cover` discharges for G2.
#[test]
fn the_oracle_names_what_the_rollout_does_not_cover() {
    let c = corpus();
    let markers: usize = c.acts.iter().map(|a| a.state.markers_meta.len()).sum();
    let vp: usize = c.acts.iter().filter(|a| a.state.vp.is_some()).count();
    let flavour: usize = c.acts.iter().filter(|a| a.state.vp_flavour.is_some()).count();
    // ROOT-state counts only: a rollout can still SHAKE a unit through
    // `_expected_shooting_morale`, which this cannot see from outside.
    let shaken: usize =
        c.acts.iter().map(|a| a.state.shaken.iter().filter(|s| **s).count()).sum();
    // `_cross_round`'s opener rule: the side with FEWER alive units opens; the
    // TIE arm (lower slot) only fires when both sides are equally strong.
    let mut ties = 0usize;
    for a in &c.acts {
        let (mut p1, mut p2) = (0i64, 0i64);
        for i in 0..a.state.units() {
            if a.state.alive[i] > 0 {
                if a.state.player[i] == 1 {
                    p1 += 1;
                } else {
                    p2 += 1;
                }
            }
        }
        if p1 == p2 {
            ties += 1;
        }
    }
    let casters = c.profiles.list.iter().filter(|p| p.caster_value > 0).count();
    let caster_groups = c
        .profiles
        .list
        .iter()
        .filter(|p| p.special_rules.iter().any(|r| r.starts_with("Caster Group")))
        .count();
    let refresh_rules = c
        .profiles
        .list
        .iter()
        .filter(|p| {
            p.special_rules
                .iter()
                .any(|r| r.starts_with("Battleborn") || r.starts_with("Steadfast"))
        })
        .count();
    println!(
        "uncovered by this fixture: markers_meta entries {markers} (destroy step + \
         demolition/sabotage VP), states carrying a vp ledger {vp}, vp_flavour {flavour}; \
         Caster Group units {caster_groups}, Battleborn/Steadfast units {refresh_rules}; \
         exercised: ROOT-state shaken units {shaken}, casters {casters}, \
         acts whose root alive counts TIE (the _cross_round tie arm) {ties}"
    );
    // The mission half of _imagined_round_end that this corpus cannot reach.
    assert_eq!(markers, 0);
    assert_eq!(flavour, 0);
    assert_eq!(caster_groups, 0);
    assert_eq!(refresh_rules, 0);
}

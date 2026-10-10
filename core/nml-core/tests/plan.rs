//! GATE G4 (NML-1073 M2-3) — the PICK, pinned on the recorded ACT corpus
//! `tests/fixtures/acts_25.jsonl` (the same 23 activations G1/G2/G3 use).
//!
//! G1 gated the charge gate, G2 the menu, G3 the rollout value of one candidate.
//! G4 is the whole search: `plan::plan_with_rollout` reads an act's state and
//! has to answer with the activation the shipped GDScript answered with —
//! WHICH unit, WHICH action, and the numbers behind it.
//!
//! The bar is deliberately not "the same unit_key". A pick can be right by luck
//! while the prefilter, the pool or the argmax are all wrong, so every stage the
//! recorder captured is compared on its own:
//!
//!   * `trace.scored` — the ranked prefilter: same length, same ORDER, same
//!     (idx, unit, kind) per row and the 1-ply score to 1e-9;
//!   * `trace.pool_idx` — which candidates the four guarantees admitted, in pool
//!     order, EXACTLY;
//!   * `trace.rs` — one rollout value per pool candidate, to 1e-9;
//!   * `trace.best_idx` / `trace.runner_idx` — the winner's and runner-up's
//!     positions in the SORTED array, exactly;
//!   * `pick` — unit_key, the action field by field, expectation before/after to
//!     1e-9, `waits`, and `rolled_units` as a set.
//!
//! A mismatch in any one of them names the stage that broke, which is the whole
//! reason the trace fields are on `Pick` at all.

use std::cell::Cell;
use std::collections::{BTreeMap, BTreeSet};

use nml_core::acts::{Knobs, PickRec, PolicyMode};
use nml_core::menu::Candidate;
use nml_core::plan::{build_pool, rank, LeafValue, PlanBend, ScoredRow, Search, REPLY_TOP_K};
use nml_core::playout::{other_player, Policy};
use nml_core::policy::{Policy as PolicyHarness, PolicyNet};
use nml_core::rollout::Rollout;
use nml_core::sim::{Scratch, Unsupported, HOLD, RUSH};
use nml_core::{act_statics, build_act_statics, load_acts, Act, ActCorpus, Pick, Seams};

mod common;

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
/// NML-1073 M2-5b — the two-activation corpus whose second act has the host's
/// attached hero DEAD. See `g4b_a_fallen_hero_stops_lending_its_rules_to_its_host`
/// for how it was authored and why it is not a plain recording.
const HERO_DEAD: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_hero_dead.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// The parity bar for every float. Both sides are f64 written by
/// `JSON.stringify(.., full_precision=true)`, so an exact hit is achievable and
/// anything above this is a difference in the arithmetic, not in the print.
const EPS: f64 = 1e-9;

fn corpus() -> ActCorpus {
    common::pin_legacy_no_cond_ap();
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

/// Field-by-field candidate equality — the same helper `tests/menu.rs` uses, so
/// G2 and G4 hold the action to one bar. `dest` is an f32 value written at full
/// precision, so 1e-9 is a formality: the port has to land on it exactly.
fn same_action(got: &Candidate, want: &Candidate) -> Result<(), String> {
    if got.kind != want.kind {
        return Err(format!("kind {} != {}", got.kind, want.kind));
    }
    if got.unit != want.unit {
        return Err(format!("unit {} != {}", got.unit, want.unit));
    }
    match (&got.dest, &want.dest) {
        (None, None) => {}
        (Some(a), Some(b)) => {
            for k in 0..3 {
                if (a[k] - b[k]).abs() > EPS {
                    return Err(format!("dest {a:?} != {b:?}"));
                }
            }
        }
        _ => return Err(format!("dest {:?} != {:?}", got.dest, want.dest)),
    }
    if got.shoot != want.shoot {
        return Err(format!("shoot {:?} != {:?}", got.shoot, want.shoot));
    }
    if got.charge != want.charge {
        return Err(format!("charge {:?} != {:?}", got.charge, want.charge));
    }
    if got.patient != want.patient {
        return Err(format!("patient {} != {}", got.patient, want.patient));
    }
    if got.wave != want.wave {
        return Err(format!("wave {:?} != {:?}", got.wave, want.wave));
    }
    Ok(())
}

/// The G4 field list, in report order. Every name is one comparison the gate
/// makes; a red proof is read by which of these move and by how much.
const FIELDS: [&str; 12] = [
    "unit_key",
    "action",
    "expectation.before",
    "expectation.after",
    "runner_up",
    "waits",
    "rolled_units",
    "trace.scored",
    "trace.pool_idx",
    "trace.rs",
    "trace.best_idx",
    "trace.runner_idx",
];

#[derive(Default)]
struct Report {
    acts: usize,
    /// Acts the search declined instead of picking (reason -> count).
    declined: BTreeMap<String, usize>,
    /// field -> how many ACTS mismatch on it.
    bad: BTreeMap<&'static str, usize>,
    /// Acts where `rolled_units` matched as a set AND in order.
    rolled_in_order: usize,
    /// Acts reproduced on EVERY field.
    clean: usize,
    first: Option<String>,
}

impl Report {
    fn total_bad(&self) -> usize {
        self.bad.values().sum()
    }
    fn get(&self, f: &str) -> usize {
        self.bad.get(f).copied().unwrap_or(0)
    }
    fn line(&self) -> String {
        FIELDS
            .iter()
            .map(|f| format!("{f} {}", self.get(f)))
            .collect::<Vec<_>>()
            .join(", ")
    }
}

/// Compare one produced pick against one recorded act. Returns the fields that
/// differ, each with the first message that explains why.
fn diff(act: &Act, want: &PickRec, got: &Pick) -> (Vec<(&'static str, String)>, bool) {
    let mut out: Vec<(&'static str, String)> = Vec::new();
    if got.unit_key != want.unit_key {
        out.push(("unit_key", format!("{} != {}", got.unit_key, want.unit_key)));
    }
    match &want.action {
        None => out.push(("action", "the recording carries no action".to_string())),
        Some(a) => {
            if let Err(e) = same_action(&got.action, a) {
                out.push(("action", e));
            }
        }
    }
    if (got.expectation_before - want.expectation.before).abs() > EPS {
        out.push((
            "expectation.before",
            format!("{:.17} != {:.17}", got.expectation_before, want.expectation.before),
        ));
    }
    if (got.expectation_after - want.expectation.after).abs() > EPS {
        out.push((
            "expectation.after",
            format!("{:.17} != {:.17}", got.expectation_after, want.expectation.after),
        ));
    }
    match (&got.runner_up, &want.runner_up.action) {
        (None, None) => {}
        (Some((uk, a, s)), Some(wa)) => {
            let mut why: Option<String> = None;
            if *uk != want.runner_up.unit_key {
                why = Some(format!("unit {uk} != {}", want.runner_up.unit_key));
            } else if let Err(e) = same_action(a, wa) {
                why = Some(e);
            } else if (s - want.runner_up.score).abs() > EPS {
                why = Some(format!("score {s:.17} != {:.17}", want.runner_up.score));
            }
            if let Some(w) = why {
                out.push(("runner_up", w));
            }
        }
        _ => out.push((
            "runner_up",
            format!("present {} vs recorded {}", got.runner_up.is_some(), want.runner_up.action.is_some()),
        )),
    }
    if got.waits != want.waits {
        out.push(("waits", format!("{} != {}", got.waits, want.waits)));
    }
    let mine: BTreeSet<&str> = got.rolled_units.iter().map(|s| s.as_str()).collect();
    let theirs: BTreeSet<&str> = want.rolled_units.iter().map(|s| s.as_str()).collect();
    if mine != theirs {
        out.push((
            "rolled_units",
            format!("{} keys vs recorded {}", got.rolled_units.len(), want.rolled_units.len()),
        ));
    }
    let in_order = got.rolled_units == want.rolled_units;
    // trace.scored — length, order, and every row.
    let mut why: Option<String> = None;
    if got.scored.len() != act.scored.len() {
        why = Some(format!("{} rows vs recorded {}", got.scored.len(), act.scored.len()));
    } else {
        for (r, (g, w)) in got.scored.iter().zip(&act.scored).enumerate() {
            if g.0 != w.idx {
                why = Some(format!("rank {r}: idx {} != {}", g.0, w.idx));
            } else if g.1 != w.unit {
                why = Some(format!("rank {r}: unit {} != {}", g.1, w.unit));
            } else if g.2 != w.kind {
                why = Some(format!("rank {r}: kind {} != {}", g.2, w.kind));
            } else if (g.3 - w.score).abs() > EPS {
                why = Some(format!("rank {r}: score {:.17} != {:.17}", g.3, w.score));
            }
            if why.is_some() {
                break;
            }
        }
    }
    if let Some(w) = why {
        out.push(("trace.scored", w));
    }
    // trace.pool_idx — exact, including order.
    let pool: Vec<i64> = got.pool_idx.iter().map(|&i| i as i64).collect();
    if pool != act.pool_idx {
        out.push((
            "trace.pool_idx",
            format!("{} entries {:?} vs recorded {} {:?}", pool.len(), pool, act.pool_idx.len(), act.pool_idx),
        ));
    }
    // trace.rs — same order, same idx, value to 1e-9.
    let mut why: Option<String> = None;
    if got.rs.len() != act.rs.len() {
        why = Some(format!("{} values vs recorded {}", got.rs.len(), act.rs.len()));
    } else {
        for (n, (g, w)) in got.rs.iter().zip(&act.rs).enumerate() {
            if g.0 != w.idx {
                why = Some(format!("slot {n}: idx {} != {}", g.0, w.idx));
            } else if (g.1 - w.rs).abs() > EPS {
                why = Some(format!("slot {n} idx {}: {:.17} != {:.17}", g.0, g.1, w.rs));
            }
            if why.is_some() {
                break;
            }
        }
    }
    if let Some(w) = why {
        out.push(("trace.rs", w));
    }
    if got.best_idx != act.best_idx {
        out.push(("trace.best_idx", format!("{} != {}", got.best_idx, act.best_idx)));
    }
    if got.runner_idx != act.runner_idx {
        out.push(("trace.runner_idx", format!("{} != {}", got.runner_idx, act.runner_idx)));
    }
    (out, in_order)
}

/// The offset of build-order `idx` inside its own unit's recorded menu — the
/// flat prefilter order is capture order over units, each contributing its whole
/// menu (see `tests/rollout.rs::flat_build_order`).
fn flat_slot(act: &Act, idx: i64) -> usize {
    let mut n = 0usize;
    for i in 0..act.state.units() {
        if act.state.player[i] != act.player || act.state.activated[i] || act.state.alive[i] <= 0 {
            continue;
        }
        let len = act.menus[act.state.key(i)].len();
        if (idx as usize) < n + len {
            return idx as usize - n;
        }
        n += len;
    }
    panic!("build idx {idx} is past the recorded menus")
}

/// One full sweep of the corpus with `bend` applied. `PlanBend::default()` is
/// the gate; every other bend is a red proof.
fn sweep(c: &ActCorpus, bend: PlanBend) -> Report {
    let statics = build_act_statics(c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let mut r = Report::default();
    for (ai, act) in c.acts.iter().enumerate() {
        let want = act.pick.as_ref().unwrap_or_else(|| panic!("act {ai} has no recorded pick"));
        let mut search = Search::new(roll, &act.statics);
        search.bend = bend;
        r.acts += 1;
        match search.run(&act.state, act.player, &mut sc, None) {
            Err(u) => {
                *r.declined.entry(format!("{u:?}")).or_insert(0) += 1;
            }
            Ok(got) => {
                let (bad, in_order) = diff(act, want, &got);
                if in_order {
                    r.rolled_in_order += 1;
                }
                if bad.is_empty() {
                    r.clean += 1;
                }
                for (f, why) in bad {
                    *r.bad.entry(f).or_insert(0) += 1;
                    if r.first.is_none() {
                        r.first = Some(format!("act {ai} R{} p{}: {f}: {why}", act.round, act.player));
                    }
                }
            }
        }
    }
    r
}

/// The instrument before the measurement: this corpus has to be one this port
/// is allowed to answer at all, and its `arbitration` has to be empty — a single
/// arbitrated pick would make G4 a gate on a search the port does not implement.
#[test]
fn the_corpus_is_one_the_ported_search_may_answer() {
    let c = corpus();
    assert_eq!(c.acts.len(), 23, "the fixture is the whole 23-activation recording");
    let arb = c.acts.iter().filter(|a| !a.arbitration.is_null()).count();
    let searchers = c.acts.iter().filter(|a| a.statics.playout_search).count();
    let net = c.acts.iter().filter(|a| !a.statics.heuristic_playout()).count();
    let fitted = c.acts.iter().filter(|a| a.statics.fit_mode).count();
    let used = c.acts.iter().filter(|a| a.pick.as_ref().is_some_and(|p| p.used)).count();
    println!(
        "corpus admissibility: arbitration non-null {arb}, playout_search {searchers}, \
         net-guided {net}, fit_mode {fitted}, picks with used=true {used}/{}; top_k knob {}",
        c.acts.len(),
        c.knobs.top_k
    );
    assert_eq!(arb, 0, "{arb} acts were decided by the stochastic arbitration (M2-4)");
    assert_eq!(searchers, 0, "{searchers} acts ran with playout_search on");
    assert_eq!(net, 0, "{net} acts used a net-guided playout, which this port declines");
    assert_eq!(fitted, 0, "{fitted} acts used the fitted eval, which score.rs does not port");
    assert_eq!(used, 23, "every recorded act must carry a real pick");
    assert_eq!(c.knobs.top_k, 6, "the recorded rollout budget is part of the contract");
}

#[test]
fn g4_the_rust_search_reproduces_every_recorded_pick() {
    let c = corpus();
    let r = sweep(&c, PlanBend::default());
    let scored: usize = c.acts.iter().map(|a| a.scored.len()).sum();
    let pool: usize = c.acts.iter().map(|a| a.pool_idx.len()).sum();
    println!(
        "G4 pick parity: {}/{} activations reproduced on all {} fields \
         ({scored} prefilter rows, {pool} rollouts)",
        r.clean,
        r.acts,
        FIELDS.len()
    );
    println!("G4 per-field mismatches: {}", r.line());
    println!(
        "G4 rolled_units: {}/{} match as a set AND in insertion order",
        r.rolled_in_order, r.acts
    );
    assert!(r.declined.is_empty(), "the search declined {:?}", r.declined);
    assert_eq!(
        r.total_bad(),
        0,
        "{} field mismatches over {} acts; first: {}",
        r.total_bad(),
        r.acts,
        r.first.unwrap_or_default()
    );
    // Reported, not merely implied: the pool guarantees really do fire here, or
    // three of the four passes would be untested scenery.
    assert_eq!(scored, 529, "the recorded candidate count is part of the contract");
    assert_eq!(pool, 266, "the recorded pool size is part of the contract");
}

/// RED PROOF 1 — the ROLLOUT BUDGET is load-bearing. `top_k` 6 -> 3 halves the
/// global slice, so every act whose pool drew more than its coverage from the
/// slice must lose candidates. If nothing moved, the top-K pass would be
/// decoration on top of the per-unit coverage.
#[test]
fn the_top_k_budget_is_load_bearing() {
    let c = corpus();
    let bent = sweep(&c, PlanBend { top_k: Some(3), ..PlanBend::default() });
    let base_pool: usize = c.acts.iter().map(|a| a.pool_idx.len()).sum();
    println!(
        "RED top_k 6 -> 3: pool_idx differs on {}/{} acts (rs {}, best_idx {}, \
         unit_key {}, action {}); recorded pool was {base_pool} rollouts",
        bent.get("trace.pool_idx"),
        bent.acts,
        bent.get("trace.rs"),
        bent.get("trace.best_idx"),
        bent.get("unit_key"),
        bent.get("action")
    );
    assert!(
        bent.get("trace.pool_idx") > 0,
        "shrinking the rollout budget changed no pool — the top-K slice is not being applied"
    );
}

/// RED PROOF 2 — the explicit `idx` TIEBREAK is load-bearing. The corpus carries
/// 277 tied prefilter rows, so without the second comparator clause the ranked
/// order is whatever the sort happens to produce. `rank` sorts UNSTABLY on
/// purpose (see its doc-comment) so that this proof measures the missing
/// tiebreak rather than Rust's own stability.
#[test]
fn the_idx_tiebreak_is_load_bearing() {
    let c = corpus();
    let mut ties = 0usize;
    let mut tied_acts = 0usize;
    for a in &c.acts {
        let mut seen: BTreeMap<u64, usize> = BTreeMap::new();
        for s in &a.scored {
            *seen.entry(s.score.to_bits()).or_insert(0) += 1;
        }
        let t: usize = seen.values().filter(|&&v| v > 1).map(|v| v - 1).sum();
        ties += t;
        if t > 0 {
            tied_acts += 1;
        }
    }
    let bent = sweep(&c, PlanBend { idx_tiebreak: false, ..PlanBend::default() });
    println!(
        "RED no idx tiebreak: {} tied prefilter rows over {tied_acts}/{} acts; \
         trace.scored differs on {}, pool_idx {}, rs {}, best_idx {}, runner_idx {}, \
         unit_key {}, action {}",
        ties,
        c.acts.len(),
        bent.get("trace.scored"),
        bent.get("trace.pool_idx"),
        bent.get("trace.rs"),
        bent.get("trace.best_idx"),
        bent.get("trace.runner_idx"),
        bent.get("unit_key"),
        bent.get("action")
    );
    assert!(ties > 0, "no tied scores at all — the tiebreak would be unreachable");
    assert!(
        bent.total_bad() > 0,
        "dropping the idx tiebreak moved nothing on {ties} tied rows — see the synthetic \
         proof in the_idx_tiebreak_orders_a_synthetic_tie"
    );
}

/// A synthetic prefilter of 24 candidates in three blocks of eight EQUAL scores,
/// ordered so the sort has real work to do. With the tiebreak the ranked order
/// is fully determined — score descending, build order within a block. Without
/// it the same input comes back permuted. Independent of the corpus, so the
/// claim survives a future recording that happens to carry no ties.
#[test]
fn the_idx_tiebreak_orders_a_synthetic_tie() {
    let rows: Vec<ScoredRow> = (0..24)
        .map(|i| ScoredRow {
            idx: i,
            unit_key: format!("u{}", i % 4),
            cand: Candidate::new(&format!("u{}", i % 4), HOLD),
            score: (i / 8) as f64 * 0.1,
        })
        .collect();
    let with = rank(&rows, true);
    let without = rank(&rows, false);
    println!("SYNTHETIC 3 x 8 tied rows: with tiebreak {with:?}");
    println!("SYNTHETIC 3 x 8 tied rows: without        {without:?}");
    let want: Vec<usize> = (16..24).chain(8..16).chain(0..8).collect();
    assert_eq!(with, want, "the tiebreak must give score desc, then build order");
    assert_ne!(without, with, "the unstable sort reproduced build order by luck");
}

/// RED PROOF 3 — the pool dedupes by ROW, not by MOVE. Each candidate dictionary
/// carries its own `idx`, so on this corpus the two readings cannot be told
/// apart: no two prefilter rows share their content. That is MEASURED here
/// rather than assumed, and the synthetic case below shows the two readings do
/// diverge as soon as a board produces the same move twice (two objectives on
/// one point, say) — which is why the port dedupes by `idx`.
#[test]
fn the_pool_dedupe_is_by_row_not_by_move() {
    let c = corpus();
    let bent = sweep(&c, PlanBend { dedupe_by_value: true, ..PlanBend::default() });
    // How many rows the corpus actually offers a value-dedupe to collapse. The
    // FULL-content key is the one `dedupe_by_value` compares; the coarse key is
    // what an even sloppier port ("the same unit doing the same kind of move")
    // would compare, and it is reported to show how much room there is to be
    // wrong here.
    let (mut full, mut coarse) = (0usize, 0usize);
    for a in &c.acts {
        let mut seen_full: BTreeSet<(String, String)> = BTreeSet::new();
        let mut seen_coarse: BTreeSet<(String, i64, u64)> = BTreeSet::new();
        for s in &a.scored {
            let cand = &a.menus[&s.unit][flat_slot(a, s.idx)];
            let key = format!(
                "{}|{:?}|{:?}|{:?}|{}|{:?}|{}",
                cand.kind,
                cand.dest.map(|d| [d[0].to_bits(), d[1].to_bits(), d[2].to_bits()]),
                cand.shoot,
                cand.charge,
                cand.patient,
                cand.wave,
                s.score.to_bits()
            );
            if !seen_full.insert((s.unit.clone(), key)) {
                full += 1;
            }
            if !seen_coarse.insert((s.unit.clone(), s.kind, s.score.to_bits())) {
                coarse += 1;
            }
        }
    }
    println!(
        "RED dedupe by value: pool_idx differs on {}/{} acts (rs {}, unit_key {}); \
         collisions available in the corpus: {full} on the full candidate content, \
         {coarse} on the coarse (unit, kind, score) key",
        bent.get("trace.pool_idx"),
        bent.acts,
        bent.get("trace.rs"),
        bent.get("unit_key")
    );
    assert_eq!(full, 0, "the corpus DOES offer a content collision — the count above is wrong");
    // A synthetic act where the same unit offers the SAME move twice at the same
    // score — the only shape that separates the two readings.
    let twin = |i: usize| ScoredRow {
        idx: i,
        unit_key: "u0".to_string(),
        cand: {
            let mut c = Candidate::new("u0", RUSH);
            c.dest = Some([1.0, 0.0, 2.0]);
            c
        },
        score: 0.9,
    };
    let rows = vec![
        twin(0),
        twin(1),
        ScoredRow { idx: 2, unit_key: "u1".into(), cand: Candidate::new("u1", HOLD), score: 0.1 },
    ];
    let order = rank(&rows, true);
    let by_row = build_pool(&rows, &order, 6, PlanBend::default()).1;
    let by_move =
        build_pool(&rows, &order, 6, PlanBend { dedupe_by_value: true, ..PlanBend::default() }).1;
    println!("SYNTHETIC duplicate move: by row {by_row:?}, by move {by_move:?}");
    assert_eq!(by_row, vec![0, 2, 1], "the row reading rolls both twins out");
    assert_eq!(by_move, vec![0, 2], "the move reading drops the second twin");
    assert_ne!(by_row, by_move, "the two readings must be distinguishable at all");
}

/// RED PROOF 4 — the ORDER of the pool guarantees is load-bearing. Running the
/// global top-K before the per-unit coverage builds the same SET on most acts
/// but a different SEQUENCE, and the pool is played out front to back with a
/// first-wins argmax, so the sequence is part of the answer.
#[test]
fn the_pool_guarantee_order_is_load_bearing() {
    let c = corpus();
    let bent = sweep(&c, PlanBend { top_k_first: true, ..PlanBend::default() });
    println!(
        "RED top-K before coverage: pool_idx differs on {}/{} acts (rs {}, \
         best_idx {}, runner_idx {}, unit_key {}, action {}, expectation.after {})",
        bent.get("trace.pool_idx"),
        bent.acts,
        bent.get("trace.rs"),
        bent.get("trace.best_idx"),
        bent.get("trace.runner_idx"),
        bent.get("unit_key"),
        bent.get("action"),
        bent.get("expectation.after")
    );
    assert!(
        bent.get("trace.pool_idx") > 0,
        "swapping the first two guarantees changed no pool at all"
    );
}

/// The `top_k <= 0` safety valve (:126) routes to the 1-ply `plan()`, which
/// answers with a DIFFERENT dictionary — no `waits`, no `rolled_units`, and an
/// "after" that is a 1-ply score. The search says so instead of inventing them.
///
/// `plan()`'s winner has a real oracle in the recording: it is a strict argmax
/// over the same 1-ply scores in BUILD order, and the recorded `trace.scored` is
/// exactly those scores sorted by score with an idx tiebreak — so `scored[0]`
/// IS `plan()`'s pick. The runner-up has no recorded counterpart (it is a
/// running second best, not the second-ranked row) and is not claimed here.
#[test]
fn the_one_ply_valve_routes_to_plan_and_plan_picks_the_ranked_head() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let (mut checked, mut bad, mut valve) = (0usize, 0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let mut search = Search::new(roll, &act.statics);
        search.bend = PlanBend { top_k: Some(0), ..PlanBend::default() };
        match search.run(&act.state, act.player, &mut sc, None) {
            Err(Unsupported::OnePlyDegrade) => valve += 1,
            other => panic!("act {ai}: top_k 0 answered {other:?} instead of the valve"),
        }
        let head = &act.scored[0];
        let got = Search::new(roll, &act.statics)
            .plan(&act.state, act.player, &mut sc)
            .unwrap_or_else(|u| panic!("act {ai}: plan declined {u:?}"))
            .unwrap_or_else(|| panic!("act {ai}: plan found no candidate"));
        checked += 1;
        let want = act.pick.as_ref().unwrap();
        if got.unit_key != head.unit
            || got.action.kind != head.kind
            || (got.expectation_after - head.score).abs() > EPS
            || (got.expectation_before - want.expectation.before).abs() > EPS
        {
            bad += 1;
        }
    }
    println!(
        "1-ply valve: {valve}/{} acts route to plan(); plan()'s pick equals the ranked \
         head on {}/{checked} acts (base score also equals the recorded expectation.before)",
        c.acts.len(),
        checked - bad
    );
    assert_eq!(valve, c.acts.len());
    assert_eq!(bad, 0, "{bad} of {checked} 1-ply picks are not the ranked head");
}

/// What G4 CANNOT gate, stated rather than hidden — the same duty
/// `tests/rollout.rs::the_oracle_names_what_the_rollout_does_not_cover`
/// discharges for G3.
#[test]
fn the_oracle_names_what_the_pick_does_not_cover() {
    let c = corpus();
    let mut patient = 0usize;
    let mut wave = 0usize;
    let mut shaken_pool = 0usize;
    let mut single_pool = 0usize;
    // NML-1073 M2-1b: the pick census, because the re-recorded corpus lost the
    // three CHARGE picks the pre-S1d one had. S1d hands the menu the RAW edge
    // gap (0.25" larger than S1b's), so the rush band refuses more charge
    // candidates (13 -> 10) and none of them survives the ranking here. G4
    // therefore does NOT gate a CHARGE pick end to end; the CHARGE branch is
    // still gated by G2 (10 candidates), by G3's rollouts and by parity GATE B.
    let mut picked = [0usize; 4];
    for a in &c.acts {
        for m in a.menus.values() {
            for cand in m {
                if cand.patient {
                    patient += 1;
                }
                if !cand.wave.as_deref().unwrap_or("").is_empty() {
                    wave += 1;
                }
            }
        }
        for i in 0..a.state.units() {
            if a.state.player[i] == a.player
                && !a.state.activated[i]
                && a.state.alive[i] > 0
                && a.state.shaken[i]
            {
                shaken_pool += 1;
            }
        }
        if a.pool_idx.len() < 2 {
            single_pool += 1;
        }
        if let Some(action) = a.pick.as_ref().and_then(|p| p.action.as_ref()) {
            picked[action.kind as usize] += 1;
        }
    }
    println!(
        "uncovered by this fixture: the stochastic playout ARBITRATION (playout_search off \
         on all 23 acts, trace.arbitration null), the `used: false` answer (every act picks), \
         a single-candidate pool that leaves runner_up empty ({single_pool} acts), \
         plan()'s running runner-up (no recorded counterpart), \
         a CHARGE pick (picked kinds HOLD {} ADVANCE {} RUSH {} CHARGE {}); \
         exercised: patient candidates {patient}, second-wave candidates {wave}, \
         SHAKEN units in the activation pool {shaken_pool}",
        picked[0], picked[1], picked[2], picked[3]
    );
    assert_eq!(single_pool, 0, "the empty-runner_up branch is not reached by this corpus");
    assert_eq!(picked[3], 0, "a CHARGE pick appeared — this corpus no longer needs the caveat");
}

// ------------------------------------------- NML-1073 M2-5b: the dead hero ---

/// GATE G4b — a hero that FALLS stops lending its rules to the unit it joined,
/// and the port has to see that within the same game.
///
/// `AiEv.rule_on_all_models` (ai_ev.gd:74-85) lets a unit-wide rule fire only
/// when every ALIVE attached hero carries it too. The game header writes each
/// unit's profile ONCE, so before M2-5b a hero that died mid-game kept voting in
/// the port's copy for the rest of the game: the host stayed un-Shielded in the
/// imagination while the table had already handed it the rule.
///
/// THE FIXTURE, stated rather than implied: it is act 14 of `acts_25.jsonl`
/// (round 3, player 2, the Protector Sisters' own activation) twice — once
/// verbatim, once with their attached Fanatic Superior dead (`alive` 0, no
/// models, and the host's per-act `attached_hero_rules` empty, which is what
/// `BattleSim._attached_hero_rules` answers for a fallen hero). The 23-act
/// recording holds no dead hero to record, so the state was EDITED; both picks
/// are then the answer the live GDScript search gives for that state, taken
/// through `tools/act_recheck.gd write=` — the same replay that reproduces all
/// 23 real recordings field for field, and it reproduces act 1's recorded pick
/// here exactly, which is what makes its answer for act 2 worth trusting.
///
/// The one rule that flips is `Shielded`: the Protector Sisters carry it, the
/// Fanatic Superior does not. It reaches the dice through
/// `AiCombatMath.shielded_defense` (+1 defence), so this is a difference the
/// score can actually feel — and it does: the live search changes its PICK.
#[test]
fn g4b_a_fallen_hero_stops_lending_its_rules_to_its_host() {
    common::pin_legacy_no_cond_ap();
    let c = load_acts(HERO_DEAD).unwrap_or_else(|e| panic!("{e}"));
    assert_eq!(c.acts.len(), 2, "the fixture is one activation before and one after the death");
    let (a1, a2) = (&c.acts[0], &c.acts[1]);

    // --- the instrument: the two acts really do read two different tables ---
    assert!(
        std::rc::Rc::ptr_eq(&a1.state.profiles, &c.profiles),
        "act 1 reads the header's own table (nothing has moved yet)"
    );
    assert!(
        !std::rc::Rc::ptr_eq(&a2.state.profiles, &c.profiles),
        "act 2 must read a REBUILT table — otherwise this test proves nothing"
    );
    // The HOST is the unit whose inherited rules changed, not merely a unit with
    // a hero: this recording holds four hero-carrying units and only one of them
    // lost its hero.
    let host = (0..a1.state.units())
        .find(|&i| {
            !a1.state.profile(i).attached_hero_rules.is_empty()
                && a2.state.profile(i).attached_hero_rules.is_empty()
        })
        .expect("act 2 must show one host that stopped inheriting");
    let hero = (0..a1.state.units())
        .find(|&i| a1.state.alive[i] > 0 && a2.state.alive[i] == 0)
        .expect("act 2 must hold exactly the death this fixture is about");
    println!(
        "G4b fixture: host {:?} rules {:?}; hero {:?} rules {:?}",
        a1.state.profile(host).name,
        a1.state.profile(host).special_rules,
        a1.state.profile(hero).name,
        a1.state.profile(hero).special_rules,
    );
    assert!(
        a1.state.profile(host).special_rules.iter().any(|r| r == "Shielded"),
        "the host has to carry the rule whose quantifier the hero was blocking"
    );
    assert!(
        !a1.state.profile(hero).special_rules.iter().any(|r| r == "Shielded"),
        "the hero has to LACK it, or nothing flips when it dies"
    );
    assert!(a2.state.profile(host).attached_hero_rules.is_empty(), "the hero stopped voting");

    // --- and the derived closure flips with it, which is what the search reads ---
    let statics = act_statics(&c, REPO);
    assert!(
        !statics[0][a1.state.roster.profile[host]].ctx.shielded,
        "with the hero alive the host is NOT shielded"
    );
    assert!(
        statics[1][a2.state.roster.profile[host]].ctx.shielded,
        "with the hero dead the host IS shielded — the whole point of M2-5b"
    );

    // --- the picks, on the same bar G4 uses ---
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let mut sc = Scratch::default();
    let mut clean = 0;
    for (ai, act) in c.acts.iter().enumerate() {
        let want = act.pick.as_ref().unwrap_or_else(|| panic!("act {ai} has no pick"));
        let roll = Rollout::new(Policy::new(&statics[ai], &c.terrain, seams), c.knobs);
        let search = Search::new(roll, &act.statics);
        let got = search
            .run(&act.state, act.player, &mut sc, None)
            .unwrap_or_else(|u| panic!("act {} declined: {u:?}", ai + 1));
        let (bad, _) = diff(act, want, &got);
        println!(
            "G4b act {}: picked {} (recorded {}), {} field(s) off",
            ai + 1,
            got.unit_key,
            want.unit_key,
            bad.len()
        );
        for (f, why) in &bad {
            println!("  {f}: {why}");
        }
        if bad.is_empty() {
            clean += 1;
        }
    }
    assert_eq!(clean, 2, "both activations must reproduce field for field");

    // The two acts must not answer the same, or the fixture would be green for
    // a port that ignores the per-act reading entirely.
    let p1 = c.acts[0].pick.as_ref().unwrap();
    let p2 = c.acts[1].pick.as_ref().unwrap();
    assert_ne!(
        p1.unit_key, p2.unit_key,
        "the death has to change the ANSWER, not just a number"
    );

    // --- RED, kept: act 2 through the HEADER's closure, i.e. the pre-M2-5b port ---
    let roll = Rollout::new(Policy::new(&statics[0], &c.terrain, seams), c.knobs);
    let stale = Search::new(roll, &a2.statics)
        .run(&a2.state, a2.player, &mut sc, None)
        .unwrap_or_else(|u| panic!("stale run declined: {u:?}"));
    let (bad, _) = diff(a2, p2, &stale);
    println!(
        "G4b RED proof: act 2 on the deployment closure is off on {} field(s): {:?}",
        bad.len(),
        bad.iter().map(|(f, _)| *f).collect::<Vec<_>>()
    );
    assert!(
        !bad.is_empty(),
        "a stale profile table has to be VISIBLE here, or this gate cannot fail"
    );
}

/// What the per-activation rebuild COSTS. `ProfileCache` hands back the same
/// table while nothing moves, so this is paid once per hero death / rule grant,
/// not once per activation — but the number belongs in the record either way.
/// The bound is deliberately loose: it can only trip on a real regression, not
/// on a busy machine.
#[test]
fn the_per_activation_rebuild_is_cheap() {
    use nml_core::{Registries, StaticsCache};
    common::pin_legacy_no_cond_ap();
    let c = load_acts(HERO_DEAD).unwrap_or_else(|e| panic!("{e}"));
    let mut reg = Registries::new(REPO);
    // warm the registry maps: the first build pays for reading the mechanics
    // JSON, which a mid-game rebuild never pays again.
    let _ = StaticsCache::new().get(&mut reg, &c.profiles);
    let t0 = std::time::Instant::now();
    const N: u32 = 20;
    for _ in 0..N {
        let mut fresh = StaticsCache::new();
        let _ = fresh.get(&mut reg, &c.acts[1].state.profiles);
    }
    let per = t0.elapsed().as_secs_f64() * 1e6 / f64::from(N);
    println!(
        "M2-5b rebuild cost: {:.1} us for {} unit profiles (search itself: ~9000 us/activation)",
        per,
        c.profiles.list.len()
    );
    assert!(per < 20_000.0, "a rebuild that costs {per:.0} us is a regression, not a cache miss");
}

/// The loud half of the same contract: there is no ONE static closure for a
/// corpus whose dynamic profile reading moved, and asking for one says so
/// instead of quietly handing back the header's.
#[test]
#[should_panic(expected = "use act_statics()")]
fn a_corpus_with_a_moved_profile_read_refuses_a_single_static_closure() {
    common::pin_legacy_no_cond_ap();
    let c = load_acts(HERO_DEAD).unwrap_or_else(|e| panic!("{e}"));
    let _ = build_act_statics(&c, REPO);
}


// ---------------------------------------------------------------------------
// NML-1158c — the exploration knob. eps=0 (with or without a stream) must be
// byte-identical to the recorded picks; eps=1 must mark every pick `explored`
// and move at least one of them onto a different pool candidate.

/// Every answerable act's pick, with the knob set the caller names. `None` is
/// the shipping call; `Some((eps, seed))` builds the dedicated stream per act,
/// the way the harness would.
fn run_corpus(c: &ActCorpus, explore: Option<(f64, i64)>) -> Vec<(usize, Pick)> {
    use nml_core::GodotRng;
    let statics = build_act_statics(c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let mut picks = Vec::new();
    for (ai, act) in c.acts.iter().enumerate() {
        let search = Search::new(roll, &act.statics);
        let got = match &explore {
            None => search.run(&act.state, act.player, &mut sc, None),
            Some((eps, seed)) => {
                let mut xr = GodotRng::new(*seed);
                search.run(&act.state, act.player, &mut sc, Some((*eps, &mut xr)))
            }
        };
        if let Ok(p) = got {
            picks.push((ai, p));
        }
    }
    picks
}

#[test]
fn the_explore_knob_is_inert_at_zero_and_live_at_one() {
    let c = corpus();
    let argmax = run_corpus(&c, None);
    let zero_with_stream = run_corpus(&c, Some((0.0, 7)));
    assert_eq!(argmax.len(), zero_with_stream.len(), "the knob must not change who answers");
    for ((ai, a), (_, z)) in argmax.iter().zip(&zero_with_stream) {
        assert!(!a.explored, "act {ai}: no stream, yet explored=true");
        assert_eq!(a.unit_key, z.unit_key, "act {ai}: eps=0 moved the pick");
        assert!((a.expectation_after - z.expectation_after).abs() <= EPS);
    }
    let full = run_corpus(&c, Some((1.0, 7)));
    assert_eq!(full.len(), argmax.len());
    let explored = full.iter().filter(|(_, p)| p.explored).count();
    assert_eq!(explored, full.len(), "eps=1 must mark every pick explored");
    let moved = full
        .iter()
        .zip(&argmax)
        .filter(|((_, p), (_, a))| p.unit_key != a.unit_key || p.action.kind != a.action.kind)
        .count();
    assert!(moved > 0, "eps=1 over {len} acts never left the argmax", len = full.len());
}

/// NML-1158b step 5 — ORDER mode (design §4, §7 step 5). A SYNTHETIC net
/// (no file, no `NML_POLICY_NET`) scores a candidate by its `kind` alone
/// (`100 + kind`, strictly monotonic over HOLD/ADVANCE/RUSH/CHARGE) so the
/// "matches the net's logits exactly" bar is checkable straight off the
/// `pick.scored` trace without reconstructing the net's own arithmetic.
fn kind_ranking_net() -> PolicyNet {
    let (state_dim, act_dim, hidden) = (93usize, 20usize, 1usize);
    let mut w1 = vec![vec![0.0f64; hidden]; state_dim + act_dim];
    for k in 0..4usize {
        w1[state_dim + k][0] = k as f64; // the 5-wide kind one-hot, CHARGE(3) highest
    }
    PolicyNet {
        schema: "policy_net/1".into(),
        state_dim,
        act_dim,
        hidden,
        w1,
        b1: vec![100.0], // keeps ReLU linear over every real action vector
        w2: vec![1.0],
        b2: 0.0,
        selftest: None,
    }
}

#[test]
fn order_mode_off_is_byte_identical_order_reorders_within_unit_only() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let mut sc = Scratch::default();
    let harness = PolicyHarness::new(kind_ranking_net(), REPO)
        .unwrap_or_else(|e| panic!("policy harness must load the checked-in rule vocab: {e}"));

    // Baseline: net UNARMED — every recorded act, the G4 order.
    let bare = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut base: Vec<Vec<(i64, String, i64, f64)>> = Vec::new();
    for act in &c.acts {
        let got = Search::new(bare, &act.statics)
            .run(&act.state, act.player, &mut sc, None)
            .unwrap_or_else(|e| panic!("{e:?}"));
        base.push(got.scored);
    }

    let mut armed = Policy::new(&statics, &c.terrain, seams);
    armed.policy_net = Some(&harness);
    let roll = Rollout::new(armed, c.knobs);
    let mut units_reordered = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        // The net ARMED, mode still off: must not move a single row — the
        // KNOB decides, not the net's mere presence.
        let off = Search::new(roll, &act.statics)
            .run(&act.state, act.player, &mut sc, None)
            .unwrap_or_else(|e| panic!("{e:?}"));
        assert_eq!(off.scored, base[ai], "act {ai}: an armed-but-off net moved the plan");

        let mut doctored = act.statics.clone();
        doctored.policy_mode = PolicyMode::Order;
        let on = Search::new(roll, &doctored)
            .run(&act.state, act.player, &mut sc, None)
            .unwrap_or_else(|e| panic!("{e:?}"));
        assert_eq!(on.scored.len(), off.scored.len(), "act {ai}: ORDER mode changed the row count");

        // The SET of positions each unit owns is design §1's cross-unit
        // decision — ORDER mode must not touch it, even though it is free to
        // fill those positions with a DIFFERENT one of that unit's own rows.
        let mut off_by_unit: BTreeMap<String, Vec<usize>> = BTreeMap::new();
        for (p, row) in off.scored.iter().enumerate() {
            off_by_unit.entry(row.1.clone()).or_default().push(p);
        }
        let mut on_by_unit: BTreeMap<String, Vec<usize>> = BTreeMap::new();
        for (p, row) in on.scored.iter().enumerate() {
            on_by_unit.entry(row.1.clone()).or_default().push(p);
        }
        assert_eq!(off_by_unit, on_by_unit,
            "act {ai}: ORDER mode moved a slot to a DIFFERENT unit");

        for (unit, positions) in &on_by_unit {
            let kinds: Vec<i64> = positions.iter().map(|&p| on.scored[p].2).collect();
            for w in kinds.windows(2) {
                assert!(w[0] >= w[1],
                    "act {ai} unit {unit}: not sorted by the net's own logit order (kind {} before {})",
                    w[0], w[1]);
            }
            let moved = positions.iter().map(|&p| on.scored[p].0).collect::<Vec<_>>()
                != positions.iter().map(|&p| off.scored[p].0).collect::<Vec<_>>();
            if moved {
                units_reordered += 1;
            }
        }
    }
    assert!(units_reordered > 0,
        "ORDER mode never reordered a single unit's own menu across {} acts", c.acts.len());
}

/// `policy_mode == Order` with no net wired declines rather than silently
/// falling back to the hand order (`admissible`, mirroring `fit_mode`).
#[test]
fn order_mode_with_no_net_wired_declines() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let act = &c.acts[0];
    let mut doctored = act.statics.clone();
    doctored.policy_mode = PolicyMode::Order;
    let err = Search::new(roll, &doctored)
        .run(&act.state, act.player, &mut sc, None)
        .expect_err("policy_mode=order with no net wired must decline, not silently reorder");
    assert!(matches!(err, Unsupported::PolicyOrder), "wrong decline reason: {err:?}");
}

/// The G4 seams, verbatim from `run_corpus` — the four tests below all build
/// their own `Search`, and a second copy of this literal is a second thing to
/// keep in step.
fn seams_of(c: &ActCorpus) -> Seams {
    Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing,
        movement: c.knobs.movement, move_rigid: c.knobs.move_rigid,
        no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() }
}

/// NML-1164 (DESIGN_policy_player §6 R4) — the `cand_logits` seam, on a state
/// doctored down to ONE activatable unit so that PHASE 2 is the only stage
/// that can move: at `top_k = 1` the top-K slice and the per-unit coverage
/// admit exactly ONE candidate, and the seam decides WHICH.
///
/// The crafted logit names the row the HAND order ranked LAST — a candidate
/// the off-mode search never rolls at all — and the bar is that the search
/// comes back with THAT candidate: `scored[best_idx].idx` is the winner's own
/// build index. A search that ignored the vector could not pass by accident,
/// and the off-mode pick beside it is the control.
#[test]
fn cand_logits_name_the_pool_and_the_pick_at_top_k_one() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let seams = seams_of(&c);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();

    let mut hit: Option<(usize, usize, Pick, Pick)> = None;
    'outer: for (ai, act) in c.acts.iter().enumerate() {
        let live: Vec<usize> = (0..act.state.units())
            .filter(|&i| act.state.can_activate(i, act.player, seams.hero_attach))
            .collect();
        for &keep in &live {
            let mut state = act.state.clone();
            for &i in &live {
                state.activated[i] = i != keep;
            }
            let mut off = Search::new(roll, &act.statics);
            off.bend.top_k = Some(1);
            let Ok(hand) = off.run(&state, act.player, &mut sc, None) else { continue };
            if hand.scored.len() < 2 {
                continue; // a one-row menu has no order to show
            }
            let target = hand.scored.last().unwrap().0 as usize;
            if hand.scored[hand.best_idx as usize].0 as usize == target {
                continue; // the hand already answers with it — no contrast
            }
            let mut lg = vec![0.0f32; hand.scored.len()];
            lg[target] = 1.0;
            let mut doctored = act.statics.clone();
            doctored.policy_mode = PolicyMode::Order;
            let mut on = Search::new(roll, &doctored);
            on.bend.top_k = Some(1);
            on.cand_logits = Some(&lg);
            let got = on.run(&state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("{e:?}"));
            if got.scored[got.best_idx as usize].0 as usize == target {
                hit = Some((ai, target, hand, got));
                break 'outer;
            }
        }
    }
    let (ai, target, hand, got) =
        hit.expect("no corpus position let a crafted logit carry the pick at top_k=1");

    assert_eq!(got.scored[0].0 as usize, target, "act {ai}: the logit head is not the order head");
    assert_eq!(got.pool_idx[0], target, "act {ai}: top_k=1 kept a row that is not the top BY LOGIT");
    assert_eq!(
        got.scored[got.best_idx as usize].0 as usize,
        target,
        "act {ai}: the search did not return the crafted candidate",
    );
    // The control: the hand order neither rolled nor picked it.
    assert!(!hand.pool_idx.contains(&target), "act {ai}: the hand rolled the target anyway");
    assert!(
        same_action(&got.action, &hand.action).is_err() || got.unit_key != hand.unit_key,
        "act {ai}: the crafted vector left the hand's own pick in place",
    );
}

/// The vector has to line up with the menu it re-ranks: a shorter or longer
/// one names the WRONG candidates, so it declines instead of re-ranking part
/// of the order.
#[test]
fn cand_logits_of_the_wrong_length_decline() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
    let mut sc = Scratch::default();
    let act = &c.acts[0];
    let mut doctored = act.statics.clone();
    doctored.policy_mode = PolicyMode::Order;
    let short = vec![0.0f32; 3];
    let mut search = Search::new(roll, &doctored);
    search.cand_logits = Some(&short);
    let err = search
        .run(&act.state, act.player, &mut sc, None)
        .expect_err("a wrong-length logit vector must decline");
    assert!(matches!(err, Unsupported::CandLogits(3, _)), "wrong decline reason: {err:?}");
}

/// DEFAULT OFF: the knob decides, not the vector's mere presence. Every act of
/// the recorded corpus, run with a logit vector that would REVERSE the order
/// if it were read, has to answer with the G4 pick unchanged.
#[test]
fn cand_logits_are_inert_while_policy_mode_is_off() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let Ok(base) = Search::new(roll, &act.statics).run(&act.state, act.player, &mut sc, None)
        else {
            continue;
        };
        // Descending by rank: read, this would stand the order on its head.
        let mut lg = vec![0.0f32; base.scored.len()];
        for (r, row) in base.scored.iter().enumerate() {
            lg[row.0 as usize] = r as f32;
        }
        let mut search = Search::new(roll, &act.statics);
        search.cand_logits = Some(&lg);
        let got = search
            .run(&act.state, act.player, &mut sc, None)
            .unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        assert_eq!(got.scored, base.scored, "act {ai}: an off-mode vector moved the order");
        assert_eq!(got.pool_idx, base.pool_idx, "act {ai}: an off-mode vector moved the pool");
        assert_eq!(got.unit_key, base.unit_key, "act {ai}: an off-mode vector moved the pick");
        assert!(same_action(&got.action, &base.action).is_ok());
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

// ------------------------------------------------- NML-1165 R4: leaf value ---

/// A crafted `LeafValue` for the R4 red proof: `bump` on the flat leaf range
/// `[lo, hi)` and nothing anywhere else, plus a call counter. The counter IS
/// half the bar — the seam's whole reason to exist is ONE batch per
/// activation, and a per-leaf hook would answer 34 times instead of once.
struct CraftedLeafValue {
    lo: usize,
    hi: usize,
    bump: f64,
    /// `None` = answer with the wrong length, the decline arm below.
    truncate: Option<usize>,
    calls: Cell<usize>,
    leaves: Cell<usize>,
}

impl CraftedLeafValue {
    fn bumping(lo: usize, hi: usize) -> CraftedLeafValue {
        CraftedLeafValue {
            lo,
            hi,
            bump: 1000.0,
            truncate: None,
            calls: Cell::new(0),
            leaves: Cell::new(0),
        }
    }
}

impl LeafValue for CraftedLeafValue {
    fn value(&self, leaves: &[&nml_core::State], _side: i64) -> Result<Vec<f64>, Unsupported> {
        self.calls.set(self.calls.get() + 1);
        self.leaves.set(leaves.len());
        let n = self.truncate.unwrap_or(leaves.len());
        Ok((0..n).map(|j| if j >= self.lo && j < self.hi { self.bump } else { 0.0 }).collect())
    }
}

/// NML-1165 R4 (DESIGN_value_net §7) — the leaf value seam CARRIES THE PICK.
///
/// The hand search names its own winner; the crafted evaluator then favours
/// the leaves of ONE OTHER pooled candidate and nothing else, and at `w = 1.0`
/// the search has to come back with THAT candidate. The leaf ranges are taken
/// from `Rollout::rollout_boundaries` itself — the same public rollout PHASE 4
/// runs — so the test knows exactly which flat slice belongs to which pool row
/// without the search having to export one.
///
/// A search that ignored the hook could not pass by accident, and the hand
/// pick beside it is the control. `calls == 1` is the second bar: the whole
/// activation's leaves arrive in ONE batch.
#[test]
fn leaf_value_flips_the_pick_at_w_one() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
    let mut sc = Scratch::default();

    let mut hit: Option<(usize, Pick, Pick, usize)> = None;
    for (ai, act) in c.acts.iter().enumerate() {
        let Ok(hand) = Search::new(roll, &act.statics).run(&act.state, act.player, &mut sc, None)
        else {
            continue;
        };
        if hand.pool_idx.len() < 2 {
            continue; // a one-row pool has no other candidate to promote
        }
        // The flat leaf offsets, pool row by pool row.
        let mut off: Vec<usize> = vec![0];
        for &i in &hand.pool_idx {
            let n = roll
                .rollout_boundaries(&act.state, &hand.cands[i], act.player, -1, &mut sc)
                .unwrap_or_else(|e| panic!("act {ai}: {e:?}"))
                .len();
            off.push(off.last().unwrap() + n);
        }
        let win = hand.scored[hand.best_idx as usize].0 as usize;
        let Some(t) = hand.pool_idx.iter().position(|&x| x != win) else { continue };
        let hook = CraftedLeafValue::bumping(off[t], off[t + 1]);
        let mut on = Search::new(roll, &act.statics);
        on.leaf_value = Some(&hook);
        on.leaf_value_w = 1.0;
        let got = on.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("{e:?}"));
        assert_eq!(hook.calls.get(), 1, "act {ai}: the leaf batch was not ONE call per activation");
        assert_eq!(
            hook.leaves.get(),
            *off.last().unwrap(),
            "act {ai}: the batch is not every pooled rollout's boundaries",
        );
        let target = hand.pool_idx[t];
        assert_eq!(
            got.scored[got.best_idx as usize].0 as usize,
            target,
            "act {ai}: the crafted leaf value did not carry the pick",
        );
        if same_action(&got.action, &hand.action).is_err() || got.unit_key != hand.unit_key {
            hit = Some((ai, hand, got, target));
            break;
        }
    }
    let (ai, hand, got, target) =
        hit.expect("no corpus act let a crafted leaf value move the pick away from the hand's");
    assert_ne!(
        hand.scored[hand.best_idx as usize].0 as usize,
        target,
        "act {ai}: the hand already answered with the promoted candidate — no contrast",
    );
    // The blend is `hand + w * value`, so the promoted row's rollout value has
    // to have moved by the bump — the pick did not merely change, it changed
    // for the reason the seam claims.
    let before = hand.rs.iter().find(|(i, _)| *i as usize == target).expect("target was pooled").1;
    let after = got.rs.iter().find(|(i, _)| *i as usize == target).expect("target stayed pooled").1;
    assert!(
        (after - before - 1000.0).abs() < 1e-6,
        "act {ai}: promoted row moved by {} , not by the bump",
        after - before,
    );
}

/// The batch has to line up with the leaves it prices: a shorter answer names
/// the WRONG leaves, so the search declines instead of blending part of the
/// backup — the same contract `CandLogits` carries for the menu.
#[test]
fn leaf_values_of_the_wrong_length_decline() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
    let mut sc = Scratch::default();
    let act = &c.acts[0];
    let mut hook = CraftedLeafValue::bumping(0, 0);
    hook.truncate = Some(3);
    let mut search = Search::new(roll, &act.statics);
    search.leaf_value = Some(&hook);
    search.leaf_value_w = 1.0;
    let err = search
        .run(&act.state, act.player, &mut sc, None)
        .expect_err("a short leaf-value batch must decline");
    assert!(matches!(err, Unsupported::LeafValue(3, _)), "wrong decline reason: {err:?}");
}

/// A weight armed with no evaluator wired declines rather than quietly pricing
/// the hand leaf and calling the game a value-net game (`admissible`,
/// mirroring `fit_mode` and `policy_mode == Order`).
#[test]
fn leaf_value_weight_with_no_hook_declines() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
    let mut sc = Scratch::default();
    let act = &c.acts[0];
    let mut search = Search::new(roll, &act.statics);
    search.leaf_value_w = 0.5;
    let err = search
        .run(&act.state, act.player, &mut sc, None)
        .expect_err("leaf_value_w with no hook must decline");
    assert!(matches!(err, Unsupported::LeafValueMissing), "wrong decline reason: {err:?}");
}

/// DEFAULT OFF: the WEIGHT decides, not the hook's mere presence. Every act of
/// the recorded corpus, run with an evaluator that would swamp the hand score
/// if it were read, has to answer with the G4 pick unchanged — trace included,
/// to the BIT — and the hook must never be called at all.
#[test]
fn leaf_value_is_inert_at_weight_zero() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
    let mut sc = Scratch::default();
    let hook = CraftedLeafValue::bumping(0, usize::MAX);
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let Ok(base) = Search::new(roll, &act.statics).run(&act.state, act.player, &mut sc, None)
        else {
            continue;
        };
        let mut search = Search::new(roll, &act.statics);
        search.leaf_value = Some(&hook);
        let got = search
            .run(&act.state, act.player, &mut sc, None)
            .unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        assert_eq!(got.scored, base.scored, "act {ai}: an unarmed hook moved the order");
        assert_eq!(got.pool_idx, base.pool_idx, "act {ai}: an unarmed hook moved the pool");
        for (g, b) in got.rs.iter().zip(&base.rs) {
            assert_eq!(g.0, b.0);
            assert_eq!(g.1.to_bits(), b.1.to_bits(), "act {ai}: an unarmed hook moved a value");
        }
        assert_eq!(
            got.expectation_after.to_bits(),
            base.expectation_after.to_bits(),
            "act {ai}: an unarmed hook moved the expectation",
        );
        assert_eq!(got.unit_key, base.unit_key, "act {ai}: an unarmed hook moved the pick");
        assert!(same_action(&got.action, &base.action).is_ok());
        checked += 1;
    }
    assert_eq!(hook.calls.get(), 0, "an unarmed hook was called anyway");
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

// ------------------------------- opponent-model diagnosis (a): `Knobs::reply_by_net` ---

/// A seat-aware counting hook: every call is logged as `(side, opener_seat, leaves)` and every leaf
/// answers 0.0, so at any weight the counts measure the net WORK a search asks for and nothing else.
struct SeatLog {
    root_seat: bool,
    calls: std::cell::RefCell<Vec<(i64, bool, usize)>>,
}

impl SeatLog {
    fn new(root_seat: bool) -> SeatLog {
        SeatLog { root_seat, calls: std::cell::RefCell::new(Vec::new()) }
    }
}

impl LeafValue for SeatLog {
    fn value(&self, leaves: &[&nml_core::State], side: i64) -> Result<Vec<f64>, Unsupported> {
        self.value_for_seat(leaves, side, self.root_seat)
    }

    fn value_for_seat(&self, leaves: &[&nml_core::State], side: i64, opener_seat: bool)
                      -> Result<Vec<f64>, Unsupported> {
        self.calls.borrow_mut().push((side, opener_seat, leaves.len()));
        Ok(vec![0.0; leaves.len()])
    }
}

fn reply_knobs(c: &ActCorpus, on: bool, tail_cap: i64) -> Knobs {
    let mut k = c.knobs;
    k.reply_by_net = on;
    (k.tail_cap_p1, k.tail_cap_p2) = (tail_cap, tail_cap);
    k
}

/// ON: with ONE scripted step allowed (`tail_cap 1`) the rollout's only step after the opener IS
/// the nested search's answer for the opponent (`Search::reply_pick` on the post-opener state,
/// resolved as a root move); OFF it is the scripted brain's. A knob that never reaches the rollout
/// leaves the scripted reply in place wherever the two disagree — the RED.
#[test]
fn reply_by_net_the_first_opponent_reply_is_the_nested_search_pick() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let (on_roll, off_roll) =
        (Rollout::new(policy, reply_knobs(&c, true, 1)), Rollout::new(policy, reply_knobs(&c, false, 1)));
    let mut sc = Scratch::default();
    let dbg = |s: &nml_core::State| format!("{s:?}");
    let (mut n, mut asked, mut nested_won, mut scripted_differs) = (0usize, 0usize, 0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let (on, off) = (Search::new(on_roll, &act.statics), Search::new(off_roll, &act.statics));
        let Ok(hand) = off.run(&act.state, act.player, &mut sc, None) else { continue };
        let opp = other_player(&act.state, act.player);
        for &i in &hand.pool_idx {
            let cand = &hand.cands[i];
            let got_on = on.rollout_of(&act.state, cand, act.player, &mut sc).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
            let got_off = off.rollout_of(&act.state, cand, act.player, &mut sc).unwrap();
            let mut opened = policy.resolve_root(&act.state, cand).unwrap();
            on_roll.coordinate_hand_off(&mut opened, cand, act.player, &mut sc).unwrap();
            n += 1;
            let Some(r) = on.reply_pick(&opened, opp, &mut sc).unwrap() else { continue };
            asked += 1;
            let mut want = policy.resolve_root(&opened, &r).unwrap();
            on_roll.coordinate_hand_off(&mut want, &r, act.player, &mut sc).unwrap();
            nested_won += usize::from(got_on.len() == 1 && dbg(&got_on[0]) == dbg(&want));
            scripted_differs += usize::from(dbg(&got_off[0]) != dbg(&want));
        }
    }
    println!(
        "reply_by_net: {n} pooled rollouts, {asked} with an opponent reply; ON plays the nested pick in {nested_won}; \
         the scripted reply differs from it in {scripted_differs}"
    );
    assert!(asked > 0, "no rollout had an opponent reply — the test proves nothing");
    assert!(scripted_differs > 0, "the nested search agreed with the script everywhere — no contrast");
    assert_eq!(nested_won, asked, "ON: the first opponent reply must be the nested search's pick");
}

/// OFF is today's search: the knob explicitly false, even with a grade set, answers every fixture act
/// with the default search's pick and values to the bit, and asks the hook ONE batch per act.
#[test]
fn reply_by_net_off_is_todays_search() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let base_roll = Rollout::new(policy, c.knobs);
    let mut k = reply_knobs(&c, false, c.knobs.tail_cap_p1);
    (k.reply_top_k, k.reply_horizon) = (7, 2);
    let off_roll = Rollout::new(policy, k);
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let (h_base, h_off) = (SeatLog::new(act.statics.opener_seat), SeatLog::new(act.statics.opener_seat));
        let mut base = Search::new(base_roll, &act.statics);
        base.leaf_value = Some(&h_base);
        base.leaf_value_w = 1.0;
        let Ok(want) = base.run(&act.state, act.player, &mut sc, None) else { continue };
        let mut off = Search::new(off_roll, &act.statics);
        off.leaf_value = Some(&h_off);
        off.leaf_value_w = 1.0;
        let got = off.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        assert_eq!(got.pool_idx, want.pool_idx, "act {ai}: OFF moved the pool");
        for (g, w) in got.rs.iter().zip(&want.rs) {
            assert_eq!((g.0, g.1.to_bits()), (w.0, w.1.to_bits()), "act {ai}: OFF moved a rollout value");
        }
        assert_eq!(got.unit_key, want.unit_key, "act {ai}: OFF moved the pick");
        assert!(same_action(&got.action, &want.action).is_ok(), "act {ai}: OFF moved the action");
        assert_eq!(*h_off.calls.borrow(), *h_base.calls.borrow(), "act {ai}: OFF changed the hook calls");
        assert_eq!(h_off.calls.borrow().len(), 1, "act {ai}: OFF asks ONE leaf batch per activation");
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

/// ON — the seats and the cost. The root still asks ONE batch from its own seat, and it is the LAST
/// call (PHASE 4b follows every rollout); every earlier call is a nested reply search asking from
/// the OPPONENT's side with the flipped `opener_seat`, at most one per pooled rollout (one level
/// only). Reported: hook calls and leaves per decision, ON vs OFF — the net work the knob adds.
#[test]
fn reply_by_net_asks_the_hook_from_the_opponent_seat_one_level_only() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let tail = c.knobs.tail_cap_p1;
    let (on_roll, off_roll) =
        (Rollout::new(policy, reply_knobs(&c, true, tail)), Rollout::new(policy, reply_knobs(&c, false, tail)));
    let mut sc = Scratch::default();
    let (mut decisions, mut nested_calls) = (0usize, 0usize);
    let (mut calls_off, mut calls_on, mut leaves_off, mut leaves_on) = (0usize, 0usize, 0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let (h_off, h_on) = (SeatLog::new(act.statics.opener_seat), SeatLog::new(act.statics.opener_seat));
        let mut off = Search::new(off_roll, &act.statics);
        off.leaf_value = Some(&h_off);
        off.leaf_value_w = 1.0;
        if off.run(&act.state, act.player, &mut sc, None).is_err() {
            continue;
        }
        let mut on = Search::new(on_roll, &act.statics);
        on.leaf_value = Some(&h_on);
        on.leaf_value_w = 1.0;
        let pick = on.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        let calls = h_on.calls.borrow();
        let (root, nested) = calls.split_last().expect("the root batch");
        assert_eq!((root.0, root.1), (act.player, act.statics.opener_seat), "act {ai}: the root batch moved seat");
        let opp = other_player(&act.state, act.player);
        for &(side, seat, _) in nested {
            assert_eq!((side, seat), (opp, !act.statics.opener_seat), "act {ai}: a nested batch from the wrong seat");
        }
        assert!(nested.len() <= pick.pool_idx.len(), "act {ai}: more nested searches than pooled rollouts");
        decisions += 1;
        nested_calls += nested.len();
        calls_off += h_off.calls.borrow().len();
        calls_on += calls.len();
        leaves_off += h_off.calls.borrow().iter().map(|c| c.2).sum::<usize>();
        leaves_on += calls.iter().map(|c| c.2).sum::<usize>();
    }
    let per = |x: usize| x as f64 / decisions.max(1) as f64;
    println!(
        "reply_by_net cost on {decisions} fixture decisions (grade 3/1, top_k {} horizon {}): hook calls/decision \
         OFF {:.2} ON {:.2}; leaves/decision OFF {:.1} ON {:.1} (x{:.2})",
        c.knobs.top_k, c.knobs.horizon, per(calls_off), per(calls_on), per(leaves_off), per(leaves_on),
        leaves_on as f64 / leaves_off.max(1) as f64
    );
    assert!(decisions > 0 && nested_calls > 0, "no nested reply search ran — the test proves nothing");
}

/// The three knobs parse from a header; absent = OFF at the default grade (`REPLY_TOP_K` 3,
/// `REPLY_HORIZON` 1).
#[test]
fn reply_by_net_parses_from_a_header_and_defaults_off() {
    let head = |knobs: &str| format!(r#"{{"kind":"header","profiles":{{}},"knobs":{{{knobs}}}}}"#);
    let on = nml_core::read_act_header(&head(r#""reply_by_net":true,"reply_top_k":5,"reply_horizon":2"#)).unwrap().knobs;
    let off = nml_core::read_act_header(&head("")).unwrap().knobs;
    assert!(on.reply_by_net && (on.reply_top_k, on.reply_horizon) == (5, 2));
    assert!(!off.reply_by_net && (off.reply_top_k, off.reply_horizon) == (0, 0));
    let d = Knobs::default();
    assert!(!d.reply_by_net && (d.reply_top_k, d.reply_horizon) == (0, 0));
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let act = &c.acts[0].statics;
    assert_eq!(Search::new(Rollout::new(policy, off), act).reply_grade(), (3, 1));
    assert_eq!(Search::new(Rollout::new(policy, on), act).reply_grade(), (5, 2));
}

// --------------- reply_by_net's cost: `Knobs::reply_pool_cap` / `Knobs::reply_menu_restricted` ---

/// Every nested reply search the fixture asks for, run directly: for each act, each ROOT pool row's
/// post-opener state (the opener resolved as a root move plus its Coordinate hand-off, where
/// `rollout_traced_reply` asks) and the opponent's `Search::reply_search` on it under `tweak`'s knobs
/// (laid over `reply_knobs(on)`). `f` sees (act, the opened state, the opponent, the nested pick);
/// returns how many nested searches answered.
fn each_nested_reply(c: &ActCorpus, tweak: impl Fn(&mut Knobs),
                     mut f: impl FnMut(usize, &nml_core::State, i64, &Pick)) -> usize {
    let statics = build_act_statics(c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(c));
    let tail = c.knobs.tail_cap_p1;
    let mut k = reply_knobs(c, true, tail);
    tweak(&mut k);
    let (roll, off_roll) = (Rollout::new(policy, k), Rollout::new(policy, reply_knobs(c, false, tail)));
    let mut sc = Scratch::default();
    let mut n = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let Ok(root) = Search::new(off_roll, &act.statics).run(&act.state, act.player, &mut sc, None) else { continue };
        let on = Search::new(roll, &act.statics);
        let opp = other_player(&act.state, act.player);
        for &i in &root.pool_idx {
            let cand = &root.cands[i];
            let mut opened = policy.resolve_root(&act.state, cand).unwrap();
            roll.coordinate_hand_off(&mut opened, cand, act.player, &mut sc).unwrap();
            match on.reply_search(&opened, opp, &mut sc) {
                Ok(p) => {
                    n += 1;
                    f(ai, &opened, opp, &p);
                }
                Err(Unsupported::NoCandidate) => {}
                Err(e) => panic!("act {ai}: {e:?}"),
            }
        }
    }
    n
}

/// One arm of #1705's counting-hook probe: every fixture act the default search answers, searched ON
/// under `tweak` with `SeatLog` at weight 1. Returns (decisions, hook calls, leaves, the largest NESTED
/// batch, wall ms of the ON searches).
fn reply_cost(c: &ActCorpus, tweak: impl Fn(&mut Knobs)) -> (usize, usize, usize, usize, f64) {
    let statics = build_act_statics(c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(c));
    let tail = c.knobs.tail_cap_p1;
    let mut k = reply_knobs(c, true, tail);
    tweak(&mut k);
    let (roll, off_roll) = (Rollout::new(policy, k), Rollout::new(policy, reply_knobs(c, false, tail)));
    let mut sc = Scratch::default();
    let (mut decisions, mut calls, mut leaves, mut nested_max, mut ms) = (0usize, 0usize, 0usize, 0usize, 0.0f64);
    for (ai, act) in c.acts.iter().enumerate() {
        if Search::new(off_roll, &act.statics).run(&act.state, act.player, &mut sc, None).is_err() {
            continue;
        }
        let hook = SeatLog::new(act.statics.opener_seat);
        let mut s = Search::new(roll, &act.statics);
        s.leaf_value = Some(&hook);
        s.leaf_value_w = 1.0;
        let t = std::time::Instant::now();
        s.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        ms += t.elapsed().as_secs_f64() * 1e3;
        let log = hook.calls.borrow();
        let (_, nested) = log.split_last().expect("the root batch");
        nested_max = nested_max.max(nested.iter().map(|b| b.2).max().unwrap_or(0));
        decisions += 1;
        calls += log.len();
        leaves += log.iter().map(|b| b.2).sum::<usize>();
    }
    (decisions, calls, leaves, nested_max, ms)
}

/// RED (a) — `reply_pool_cap` K = 3: every nested reply search prices at most 3 rows, and they are the
/// top 3 of ITS OWN prefilter order (no per-unit coverage, patient-advance or second-wave row on top).
/// The counting hook sees the same through the real search: at the reply horizon 1 a nested batch
/// carries one leaf per priced row, so no nested batch exceeds 3. Cap 0 (#1705's pool) is the contrast
/// that proves the bar can fail: its nested pools carry every opponent unit.
#[test]
fn reply_pool_cap_prices_at_most_k_rows_in_every_nested_search() {
    let c = corpus();
    let mut max0 = 0usize;
    let n0 = each_nested_reply(&c, |_| {}, |_, _, _, p| max0 = max0.max(p.pool_idx.len()));
    let (mut max3, mut not_top) = (0usize, 0usize);
    let n3 = each_nested_reply(&c, |k| k.reply_pool_cap = 3, |ai, _, _, p| {
        max3 = max3.max(p.pool_idx.len());
        let top: Vec<usize> = p.scored.iter().take(3).map(|s| s.0 as usize).collect();
        if p.pool_idx != top {
            not_top += 1;
            if not_top == 1 {
                println!("act {ai}: nested pool {:?}, the top-3 prefilter rows {top:?}", p.pool_idx);
            }
        }
    });
    let (_, _, _, hook0, _) = reply_cost(&c, |_| {});
    let (d, calls, _, hook3, _) = reply_cost(&c, |k| k.reply_pool_cap = 3);
    println!(
        "reply_pool_cap: {n0} nested searches; largest nested pool cap 0 {max0} / cap 3 {max3} ({not_top} not the \
         top-3 rows); counting hook over {d} decisions ({calls} calls): largest nested batch cap 0 {hook0} / cap 3 {hook3}"
    );
    assert!(n0 > 0 && max0 > 3 && hook0 > 3, "cap 0 never prices more than 3 rows — the bar cannot fail");
    assert_eq!(n3, n0, "the cap moved how many nested searches answer");
    assert!(max3 <= 3, "cap 3: a nested search priced {max3} rows");
    assert_eq!(not_top, 0, "cap 3: the nested pool must be the top 3 rows of its own prefilter order");
    assert!(hook3 <= 3, "cap 3: a nested hook batch carried {hook3} leaves");
}

/// (b) cap 0 IS #1705's nested search: every nested pool at cap 0 is `build_pool`'s four guarantees over
/// that search's own prefilter at the reply top_k, and the whole ON search at cap 0 and at a negative cap
/// (which reads as 0) answers every fixture act like the knob-absent ON search: pool, rs to the bit,
/// pick, hook calls. (The box gate repeats the bit-for-bit bar against #1705's own binary, 515 picks.)
#[test]
fn reply_pool_cap_zero_is_reply_by_nets_guaranteed_pool() {
    let c = corpus();
    let mut bad = 0usize;
    let n = each_nested_reply(&c, |k| k.reply_pool_cap = 0, |ai, _, _, p| {
        let order: Vec<usize> = p.scored.iter().map(|s| s.0 as usize).collect();
        let mut rows: Vec<ScoredRow> = p.cands.iter().enumerate()
            .map(|(idx, cand)| ScoredRow { idx, unit_key: String::new(), cand: cand.clone(), score: f64::NAN })
            .collect();
        for s in &p.scored {
            (rows[s.0 as usize].unit_key, rows[s.0 as usize].score) = (s.1.clone(), s.3);
        }
        let (_, want) = build_pool(&rows, &order, REPLY_TOP_K, PlanBend::default());
        if p.pool_idx != want {
            bad += 1;
            if bad == 1 {
                println!("act {ai}: nested pool {:?}, the four guarantees' {want:?}", p.pool_idx);
            }
        }
    });
    assert!(n > 0, "no nested search ran — the test proves nothing");
    assert_eq!(bad, 0, "cap 0 moved a nested pool off build_pool's four guarantees");
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let tail = c.knobs.tail_cap_p1;
    let base_roll = Rollout::new(policy, reply_knobs(&c, true, tail));
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for cap in [0i64, -1] {
        let mut k = reply_knobs(&c, true, tail);
        k.reply_pool_cap = cap;
        let roll = Rollout::new(policy, k);
        for (ai, act) in c.acts.iter().enumerate() {
            let (h_base, h_got) = (SeatLog::new(act.statics.opener_seat), SeatLog::new(act.statics.opener_seat));
            let mut base = Search::new(base_roll, &act.statics);
            base.leaf_value = Some(&h_base);
            base.leaf_value_w = 1.0;
            let Ok(want) = base.run(&act.state, act.player, &mut sc, None) else { continue };
            let mut s = Search::new(roll, &act.statics);
            s.leaf_value = Some(&h_got);
            s.leaf_value_w = 1.0;
            let got = s.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
            assert_eq!(got.pool_idx, want.pool_idx, "cap {cap} act {ai}: moved the pool");
            for (g, w) in got.rs.iter().zip(&want.rs) {
                assert_eq!((g.0, g.1.to_bits()), (w.0, w.1.to_bits()), "cap {cap} act {ai}: moved a rollout value");
            }
            assert_eq!(got.unit_key, want.unit_key, "cap {cap} act {ai}: moved the pick");
            assert!(same_action(&got.action, &want.action).is_ok(), "cap {cap} act {ai}: moved the action");
            assert_eq!(*h_got.calls.borrow(), *h_base.calls.borrow(), "cap {cap} act {ai}: moved the hook calls");
            checked += 1;
        }
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

/// `reply_menu_restricted`: the nested reply search offers the scripted brain's own menu — its prefilter
/// rows are exactly `Policy::policy_candidates` of every opponent unit that may activate, in capture
/// order — and that is NOT the full root menu (the contrast: the widths differ somewhere).
#[test]
fn reply_menu_restricted_offers_the_playout_menu_in_the_nested_search() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let mut sc = Scratch::default();
    let (mut widths, mut bad) = (Vec::new(), 0usize);
    let lite = |k: &mut Knobs| (k.reply_pool_cap, k.reply_menu_restricted) = (3, true);
    let n = each_nested_reply(&c, lite, |ai, st, opp, p| {
        let want: Vec<Candidate> = (0..st.units())
            .filter(|&u| st.can_activate(u, opp, policy.seams.hero_attach))
            .flat_map(|u| policy.policy_candidates(st, u, &mut sc))
            .collect();
        let same = p.cands.len() == want.len() && p.cands.iter().zip(&want).all(|(g, w)| same_action(g, w).is_ok());
        if !same {
            bad += 1;
            if bad == 1 {
                println!("act {ai}: nested menu {} rows, the playout menu {} rows", p.cands.len(), want.len());
            }
        }
        widths.push(p.cands.len());
    });
    let mut full = Vec::new();
    each_nested_reply(&c, |k| k.reply_pool_cap = 3, |_, _, _, p| full.push(p.cands.len()));
    let differ = widths.iter().zip(&full).filter(|(a, b)| a != b).count();
    println!(
        "reply_menu_restricted: {n} nested searches, {bad} not the playout menu; the width differs from the full \
         menu in {differ} (restricted {} rows, full {} rows in all)",
        widths.iter().sum::<usize>(), full.iter().sum::<usize>()
    );
    assert!(n > 0 && widths.len() == full.len(), "no nested search ran, or the two arms ran different ones");
    assert_eq!(bad, 0, "the nested search must offer the playout menu");
    assert!(differ > 0, "the restricted menu equals the full menu everywhere — no contrast");
}

/// Knob OFF identity: with `reply_by_net` OFF, `reply_pool_cap` 3 and `reply_menu_restricted` move nothing
/// — pool, rs to the bit, pick, ONE hook batch per act; and ON, they leave the ROOT search's own
/// prefilter and pool untouched (only the nested searches change).
#[test]
fn reply_pool_cap_and_menu_are_inert_off_and_never_touch_the_root_pool() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let policy = Policy::new(&statics, &c.terrain, seams_of(&c));
    let tail = c.knobs.tail_cap_p1;
    let lite = |mut k: Knobs| {
        (k.reply_pool_cap, k.reply_menu_restricted) = (3, true);
        k
    };
    let (base_roll, off_roll) = (Rollout::new(policy, c.knobs), Rollout::new(policy, lite(c.knobs)));
    let (on0, on3) = (Rollout::new(policy, reply_knobs(&c, true, tail)), Rollout::new(policy, lite(reply_knobs(&c, true, tail))));
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let (h_base, h_off) = (SeatLog::new(act.statics.opener_seat), SeatLog::new(act.statics.opener_seat));
        let mut base = Search::new(base_roll, &act.statics);
        base.leaf_value = Some(&h_base);
        base.leaf_value_w = 1.0;
        let Ok(want) = base.run(&act.state, act.player, &mut sc, None) else { continue };
        let mut off = Search::new(off_roll, &act.statics);
        off.leaf_value = Some(&h_off);
        off.leaf_value_w = 1.0;
        let got = off.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        assert_eq!(got.pool_idx, want.pool_idx, "act {ai}: OFF moved the pool");
        for (g, w) in got.rs.iter().zip(&want.rs) {
            assert_eq!((g.0, g.1.to_bits()), (w.0, w.1.to_bits()), "act {ai}: OFF moved a rollout value");
        }
        assert_eq!(got.unit_key, want.unit_key, "act {ai}: OFF moved the pick");
        assert!(same_action(&got.action, &want.action).is_ok(), "act {ai}: OFF moved the action");
        assert_eq!(*h_off.calls.borrow(), *h_base.calls.borrow(), "act {ai}: OFF changed the hook calls");
        assert_eq!(h_off.calls.borrow().len(), 1, "act {ai}: OFF asks ONE leaf batch per activation");
        let r0 = Search::new(on0, &act.statics).run(&act.state, act.player, &mut sc, None).unwrap();
        let r3 = Search::new(on3, &act.statics).run(&act.state, act.player, &mut sc, None).unwrap();
        assert_eq!(r3.pool_idx, r0.pool_idx, "act {ai}: the nested cap moved the ROOT pool");
        assert_eq!(r3.scored.len(), r0.scored.len(), "act {ai}: the nested menu moved the ROOT prefilter");
        for (g, w) in r3.scored.iter().zip(&r0.scored) {
            assert_eq!((g.0, &g.1, g.2, g.3.to_bits()), (w.0, &w.1, w.2, w.3.to_bits()), "act {ai}: ROOT prefilter row");
        }
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

/// COST PROBE (#1705's counting hook, per arm): hook calls, leaves and debug-build wall ms per fixture
/// decision — OFF, ON at cap 0 (#1705: 12.13 calls, 158.9 leaves), cap 3, cap 5, and cap 3 on the
/// restricted menu. The cap leaves the CALLS alone (one nested search per pooled root rollout with an
/// opponent reply) and cuts the leaves.
#[test]
fn reply_pool_cap_cost_probe() {
    let c = corpus();
    type Arm = (&'static str, fn(&mut Knobs));
    let arms: [Arm; 5] = [
        ("OFF", |k| k.reply_by_net = false),
        ("ON cap 0 (#1705)", |_| {}),
        ("ON cap 3", |k| k.reply_pool_cap = 3),
        ("ON cap 5", |k| k.reply_pool_cap = 5),
        ("ON cap 3 + restricted menu", |k| (k.reply_pool_cap, k.reply_menu_restricted) = (3, true)),
    ];
    let mut got = Vec::new();
    for (name, tweak) in arms {
        let (d, calls, leaves, nested_max, ms) = reply_cost(&c, tweak);
        let per = |x: f64| x / d.max(1) as f64;
        println!(
            "reply cost probe [{name}] over {d} decisions: hook calls/decision {:.2}, leaves/decision {:.1}, \
             largest nested batch {nested_max}, debug ms/decision {:.1}",
            per(calls as f64), per(leaves as f64), per(ms)
        );
        got.push((d, calls, leaves));
    }
    let (off, on, cap3, cap5) = (got[0], got[1], got[2], got[3]);
    assert!(on.0 > 0 && on.1 > on.0, "no nested reply search ran — the probe measures nothing");
    assert!(got.iter().all(|g| g.0 == off.0), "the arms answered different acts");
    assert_eq!((cap3.1, cap5.1, got[4].1), (on.1, on.1, on.1), "the cap moved the number of nested searches");
    assert!(cap3.2 < on.2 && cap3.2 <= cap5.2, "the cap must cut the leaves: cap 3 {} cap 5 {} cap 0 {}", cap3.2, cap5.2, on.2);
}

/// The two knobs parse from a header; absent = off (cap 0, the full menu), as `Knobs::default()`.
#[test]
fn reply_pool_cap_and_menu_parse_from_a_header_and_default_off() {
    let head = |knobs: &str| format!(r#"{{"kind":"header","profiles":{{}},"knobs":{{{knobs}}}}}"#);
    let on = nml_core::read_act_header(&head(r#""reply_by_net":true,"reply_pool_cap":3,"reply_menu_restricted":true"#))
        .unwrap()
        .knobs;
    let off = nml_core::read_act_header(&head("")).unwrap().knobs;
    assert!(on.reply_by_net && on.reply_pool_cap == 3 && on.reply_menu_restricted);
    assert!(off.reply_pool_cap == 0 && !off.reply_menu_restricted);
    let d = Knobs::default();
    assert!(d.reply_pool_cap == 0 && !d.reply_menu_restricted);
}

// LAZARUS M1 step 9b RED: grid_k widens the chosen unit with reachable 1-inch cells. OFF is
// byte-identical; ON `scored` grows by that unit's cells as TAIL rows. Main ignores the keys.
#[test]
fn grid_k_widens_the_chosen_unit() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, hero_last: c.knobs.hero_last, path: c.knobs.seam_path, hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, movement: c.knobs.movement, move_rigid: c.knobs.move_rigid, no_engage_fold: !c.knobs.engage_fold, los_model: c.knobs.los_model, dangerous_end_morale: c.knobs.dangerous_end_morale, consolidate: c.knobs.consolidate, ..Seams::default() };
    let mut sc = Scratch::default();
    let mut grew = 0;
    for (ai, act) in c.acts.iter().enumerate() {
        let run = |k: Knobs| Rollout::new(Policy::new(&statics, &c.terrain, seams), k);
        let Ok(base) = Search::new(run(c.knobs), &act.statics).run(&act.state, act.player, &mut sc, None) else { continue };
        let mut k = c.knobs;
        k.grid_k = 4; k.grid_units = 1;
        let hook = SeatLog::new(act.statics.opener_seat);
        let mut grid = Search::new(run(k), &act.statics);
        grid.leaf_value = Some(&hook);
        grid.leaf_value_w = 0.0;
        let Ok(got) = grid.run(&act.state, act.player, &mut sc, None) else { continue };
        assert_eq!(got.unit_key, base.unit_key, "act {ai}: the widened pick left the hand argmax's unit");
        assert_eq!(got.n_hand, base.scored.len(), "act {ai}: n_hand is not the hand row count");
        if got.scored.len() > base.scored.len() {
            grew += 1;
            let g = got.grid.as_ref().expect("a widened pick carries a grid trace");
            assert!(g.completed > 0 && g.rows.len() == g.completed, "act {ai}: grid trace counts disagree");
        }
    }
    assert!(grew > 0, "grid_k widened no act of the corpus");
}

/// LAZARUS M1 step 9b — the widen needs the pool's own leaf hook. On every act the grid-off search
/// can answer, `grid_k > 0` with no hook declines with `GridNeedsOpenerLeaf`.
#[test]
fn grid_needs_opener_leaf() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let mut seen = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let off = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
        let Ok(_) = Search::new(off, &act.statics).run(&act.state, act.player, &mut sc, None) else { continue };
        let mut k = c.knobs;
        k.grid_k = 4; k.grid_units = 1;
        let on = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), k);
        match Search::new(on, &act.statics).run(&act.state, act.player, &mut sc, None) {
            Err(Unsupported::GridNeedsOpenerLeaf) => seen += 1,
            other => panic!("act {ai}: grid_k without a leaf hook answered {other:?}, not GridNeedsOpenerLeaf"),
        }
    }
    assert!(seen > 0, "the corpus declined everywhere — the gate proves nothing");
}

/// LAZARUS M1 step 9b identity gate — `grid_k` 0 (absent OR explicit 0) is byte-identical to the
/// baseline: pool, rollout values to the bit, pick, no grid trace stamped.
#[test]
fn grid_off_is_byte_identical() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let (hb, ho) = (SeatLog::new(act.statics.opener_seat), SeatLog::new(act.statics.opener_seat));
        let mut k = c.knobs; k.grid_k = 0;
        let mk = |kk: Knobs| Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), kk);
        let mut base = Search::new(mk(c.knobs), &act.statics);
        base.leaf_value = Some(&hb); base.leaf_value_w = 1.0;
        let Ok(want) = base.run(&act.state, act.player, &mut sc, None) else { continue };
        let mut off = Search::new(mk(k), &act.statics);
        off.leaf_value = Some(&ho); off.leaf_value_w = 1.0;
        let got = off.run(&act.state, act.player, &mut sc, None).unwrap_or_else(|e| panic!("act {ai}: {e:?}"));
        assert_eq!(got.pool_idx, want.pool_idx, "act {ai}: grid_k 0 moved the pool");
        assert_eq!(got.unit_key, want.unit_key, "act {ai}: grid_k 0 moved the pick");
        assert!(got.grid.is_none(), "act {ai}: grid_k 0 stamped a grid trace");
        assert_eq!(got.n_hand, want.scored.len(), "act {ai}: n_hand off");
        for (g, w) in got.rs.iter().zip(&want.rs) {
            assert_eq!((g.0, g.1.to_bits()), (w.0, w.1.to_bits()), "act {ai}: grid_k 0 moved a rollout value");
        }
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}
/// LAZARUS M1 step 9b — the widen is deterministic: two runs rank and pick identically.
#[test]
fn grid_is_deterministic() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let mut k = c.knobs; k.grid_k = 4; k.grid_units = 1;
        let hook = SeatLog::new(act.statics.opener_seat);
        let mut run = || {
            let mut s = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), k), &act.statics);
            s.leaf_value = Some(&hook); s.leaf_value_w = 0.0;
            s.run(&act.state, act.player, &mut sc, None)
        };
        let (a, b) = (run(), run());
        let (Ok(a), Ok(b)) = (a, b) else { continue };
        assert_eq!(a.scored, b.scored, "act {ai}: two grid runs ranked differently");
        assert_eq!(a.unit_key, b.unit_key, "act {ai}: two grid runs picked differently");
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}
/// LAZARUS M1 step 9b — a huge `grid_margin` keeps the HAND pick: grid rows can never outrank it.
#[test]
fn grid_margin_keeps_the_hand_pick() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let base_roll = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
        let Ok(base) = Search::new(base_roll, &act.statics).run(&act.state, act.player, &mut sc, None) else { continue };
        let mut k = c.knobs; k.grid_k = 4; k.grid_units = 1; k.grid_margin = 1e9;
        let hook = SeatLog::new(act.statics.opener_seat);
        let mut on = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), k), &act.statics);
        on.leaf_value = Some(&hook); on.leaf_value_w = 0.0;
        let Ok(got) = on.run(&act.state, act.player, &mut sc, None) else { continue };
        assert_eq!(got.unit_key, base.unit_key, "act {ai}: a huge grid_margin still moved the pick");
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

/// LAZARUS M1 step 9d RED — a grid ADVANCE+shoot whose MOVED cell has no LOS to its target must be
/// DROPPED, not declined: the whole act stays searched. Grid path only; the hand menu is unchanged.
#[test]
fn grid_moved_cell_without_los_is_skipped_not_declined() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let hook = SeatLog::new(true);
    let mut checked = 0usize;
    let mut declined = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let off = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), c.knobs);
        let Ok(_) = Search::new(off, &act.statics).run(&act.state, act.player, &mut sc, None) else { continue };
        let mut k = c.knobs; k.grid_k = 4; k.grid_units = 1;
        let on = Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c)), k);
        let mut s = Search::new(on, &act.statics);
        s.leaf_value = Some(&hook); s.leaf_value_w = 0.0;
        match s.run(&act.state, act.player, &mut sc, None) {
            Ok(_) => checked += 1,
            Err(e) => { declined += 1; if declined == 1 { println!("act {ai}: grid declined {e:?}"); } }
        }
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
    assert_eq!(declined, 0, "grid_k declined an act the hand search answered");
}

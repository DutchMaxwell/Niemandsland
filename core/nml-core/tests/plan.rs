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

use std::collections::{BTreeMap, BTreeSet};

use nml_core::acts::PickRec;
use nml_core::menu::Candidate;
use nml_core::plan::{build_pool, rank, PlanBend, ScoredRow, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::{Scratch, Unsupported, HOLD, RUSH};
use nml_core::{act_statics, build_act_statics, load_acts, Act, ActCorpus, Pick, Seams};

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
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let mut r = Report::default();
    for (ai, act) in c.acts.iter().enumerate() {
        let want = act.pick.as_ref().unwrap_or_else(|| panic!("act {ai} has no recorded pick"));
        let mut search = Search::new(roll, &act.statics);
        search.bend = bend;
        r.acts += 1;
        match search.run(&act.state, act.player, &mut sc) {
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
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let (mut checked, mut bad, mut valve) = (0usize, 0usize, 0usize);
    for (ai, act) in c.acts.iter().enumerate() {
        let mut search = Search::new(roll, &act.statics);
        search.bend = PlanBend { top_k: Some(0), ..PlanBend::default() };
        match search.run(&act.state, act.player, &mut sc) {
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
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false };
    let mut sc = Scratch::default();
    let mut clean = 0;
    for (ai, act) in c.acts.iter().enumerate() {
        let want = act.pick.as_ref().unwrap_or_else(|| panic!("act {ai} has no pick"));
        let roll = Rollout::new(Policy::new(&statics[ai], &c.terrain, seams), c.knobs);
        let search = Search::new(roll, &act.statics);
        let got = search
            .run(&act.state, act.player, &mut sc)
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
        .run(&a2.state, a2.player, &mut sc)
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
    let c = load_acts(HERO_DEAD).unwrap_or_else(|e| panic!("{e}"));
    let _ = build_act_statics(&c, REPO);
}

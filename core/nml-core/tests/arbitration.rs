//! GATE G5 (NML-1073 M2-4) — the PLAYOUT ARBITRATION, pinned on
//! `tests/fixtures/acts_arb.jsonl`: an arena game recorded with the
//! `planner_v0s` preset (planner_v0 + `playout_search`) at
//! `NML_PLAYOUT_MARGIN=0.2`, a margin wide enough that the arbitration fires on
//! every activation instead of once a game.
//!
//! G4 gated the search up to the point where the blend cannot separate the top
//! two. G5 gates what happens next, and it is a different KIND of claim: the
//! arbitration plays both branches out to the end of the game with stochastic
//! wound rounding, so its verdict is the product of hundreds of `randf()` draws
//! spread over dozens of activations. There is no partial credit — a stream that
//! drifts once produces a different battle from there on.
//!
//! Four numbers per arbitrated act are compared EXACTLY:
//!   * `n`       — playouts per branch (3, 5 or 7): the escalation ladder;
//!   * `sum_b`   — the best branch's summed signed marker delta;
//!   * `sum_r`   — the runner-up's;
//!   * `swapped` — whether the runner-up took the pick.
//! Plus the 12 pick/trace fields G4 compares, because a correct arbitration that
//! swapped the wrong pair of candidates is still a wrong answer.
//!
//! `sig` is an INPUT. `AiPlanner._playout_sig` hashes Godot's own text rendering
//! of the whole board; the recorder writes the value it used, and this gate
//! feeds it back. What is being gated is the DICE and the GAME, not Godot's
//! String hash — see `arbitration.rs`'s module header.

use std::collections::{BTreeMap, BTreeSet};

use nml_core::acts::PickRec;
use nml_core::arbitration::ArbBend;
use nml_core::menu::Candidate;
use nml_core::plan::{PlanBend, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, Act, ActCorpus, Pick, Seams};

mod common;

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_arb.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const EPS: f64 = 1e-9;

fn corpus() -> ActCorpus {
    common::pin_legacy_no_cond_ap();
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

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

/// The G5 field list, in report order: the four arbitration numbers first,
/// then the pick and trace fields G4 already gates.
const FIELDS: [&str; 16] = [
    "arb.n",
    "arb.sum_b",
    "arb.sum_r",
    "arb.swapped",
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
    arbitrated: usize,
    plain: usize,
    declined: BTreeMap<String, usize>,
    bad: BTreeMap<&'static str, usize>,
    clean: usize,
    /// Acts where all FOUR arbitration numbers matched.
    arb_clean: usize,
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
        FIELDS.iter().map(|f| format!("{f} {}", self.get(f))).collect::<Vec<_>>().join(", ")
    }
}

fn diff(act: &Act, want: &PickRec, got: &Pick) -> Vec<(&'static str, String)> {
    let mut out: Vec<(&'static str, String)> = Vec::new();
    // --- the four arbitration numbers ---
    match (act.arbitration_rec(), got.arbitration) {
        (None, None) => {}
        (Some(w), Some(g)) => {
            if g.n != w.n {
                out.push(("arb.n", format!("{} != {}", g.n, w.n)));
            }
            if (g.sum_b - w.sum_b).abs() > EPS {
                out.push(("arb.sum_b", format!("{} != {}", g.sum_b, w.sum_b)));
            }
            if (g.sum_r - w.sum_r).abs() > EPS {
                out.push(("arb.sum_r", format!("{} != {}", g.sum_r, w.sum_r)));
            }
            if g.swapped != w.swapped {
                out.push(("arb.swapped", format!("{} != {}", g.swapped, w.swapped)));
            }
        }
        (w, g) => out.push((
            "arb.n",
            format!("fired: recorded {} vs port {}", w.is_some(), g.is_some()),
        )),
    }
    // --- the G4 fields ---
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
            format!(
                "present {} vs recorded {}",
                got.runner_up.is_some(),
                want.runner_up.action.is_some()
            ),
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
    let pool: Vec<i64> = got.pool_idx.iter().map(|&i| i as i64).collect();
    if pool != act.pool_idx {
        out.push(("trace.pool_idx", format!("{pool:?} vs recorded {:?}", act.pool_idx)));
    }
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
    out
}

/// One full sweep with `bend` applied. `PlanBend::default()` is the gate;
/// anything else is a red proof.
fn sweep(c: &ActCorpus, bend: PlanBend) -> Report {
    let statics = build_act_statics(c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false, no_engage_fold: !c.knobs.engage_fold };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let mut r = Report::default();
    for (ai, act) in c.acts.iter().enumerate() {
        let want = act.pick.as_ref().unwrap_or_else(|| panic!("act {ai} has no recorded pick"));
        let rec = act.arbitration_rec();
        if rec.is_some() {
            r.arbitrated += 1;
        } else {
            r.plain += 1;
        }
        let mut search = Search::new(roll, &act.statics);
        search.bend = bend;
        // The recorded signature, fed back in. Acts that never arbitrated get
        // none — and must not need one.
        search.sig = rec.map(|a| a.sig);
        r.acts += 1;
        match search.run(&act.state, act.player, &mut sc, None) {
            Err(u) => {
                *r.declined.entry(format!("{u:?}")).or_insert(0) += 1;
            }
            Ok(got) => {
                let bad = diff(act, want, &got);
                if !bad.iter().any(|(f, _)| f.starts_with("arb.")) {
                    r.arb_clean += 1;
                }
                if bad.is_empty() {
                    r.clean += 1;
                }
                for (f, why) in bad {
                    *r.bad.entry(f).or_insert(0) += 1;
                    if r.first.is_none() {
                        r.first =
                            Some(format!("act {ai} R{} p{}: {f}: {why}", act.round, act.player));
                    }
                }
            }
        }
    }
    r
}

/// The instrument before the measurement: this corpus only earns its name if
/// the arbitration actually fired on it, and often.
#[test]
fn the_corpus_actually_arbitrates() {
    let c = corpus();
    let arb = c.acts.iter().filter(|a| !a.arbitration.is_null()).count();
    let searchers = c.acts.iter().filter(|a| a.statics.playout_search).count();
    let net = c.acts.iter().filter(|a| !a.statics.heuristic_playout()).count();
    let fitted = c.acts.iter().filter(|a| a.statics.fit_mode).count();
    let swaps = c.acts.iter().filter_map(|a| a.arbitration_rec()).filter(|a| a.swapped).count();
    let mut ladder: BTreeMap<i64, usize> = BTreeMap::new();
    for a in c.acts.iter().filter_map(|a| a.arbitration_rec()) {
        *ladder.entry(a.n).or_insert(0) += 1;
    }
    println!(
        "corpus: {} acts, {arb} arbitrated ({swaps} swapped the pick), playout_search {searchers}, \
         net-guided {net}, fit_mode {fitted}; escalation ladder (n per branch -> acts) {ladder:?}; \
         knobs: playout_margin {}, playout_rich {}, seam_spacing {}, seam_cast {}, top_k {}",
        c.acts.len(),
        c.knobs.playout_margin,
        c.knobs.playout_rich,
        c.knobs.seam_spacing,
        c.knobs.seam_cast,
        c.knobs.top_k
    );
    assert!(arb >= 5, "only {arb} arbitrated acts — the gate would measure nothing");
    assert_eq!(net, 0, "{net} acts used a net-guided playout, which this port declines");
    assert_eq!(fitted, 0, "{fitted} acts used the fitted eval, which score.rs does not port");
    assert!(swaps > 0, "no recorded arbitration ever swapped the pick");
    assert!(ladder.len() > 1, "every arbitration stopped at the same n — the ladder is untested");
    assert!(
        (c.knobs.playout_margin - 0.2).abs() < 1e-12,
        "the recording knob NML_PLAYOUT_MARGIN=0.2 must be in the header"
    );
}

#[test]
fn g5_the_rust_arbitration_reproduces_every_recorded_verdict() {
    let c = corpus();
    let r = sweep(&c, PlanBend::default());
    let playouts: i64 = c.acts.iter().filter_map(|a| a.arbitration_rec()).map(|a| a.n * 2).sum();
    println!(
        "G5 arbitration parity: {}/{} acts reproduced on all {} fields; \
         arbitration numbers exact on {}/{} arbitrated acts ({playouts} full playouts replayed); \
         non-arbitrated acts in this corpus: {}",
        r.clean,
        r.acts,
        FIELDS.len(),
        r.arb_clean,
        r.arbitrated,
        r.plain
    );
    if r.total_bad() > 0 {
        println!("G5 mismatch counts: {}", r.line());
    }
    assert!(r.declined.is_empty(), "G5: the port declined {:?}", r.declined);
    assert_eq!(r.clean, r.acts, "G5: {}\nfirst: {:?}", r.line(), r.first);
}

/// RED PROOF 1 — `PLAYOUT_DECIDE_MARGIN` 0.5 -> 0.4. The escalation stops when
/// the two branches are far enough apart; a different threshold stops at a
/// different `n`, and a shorter or longer sum can flip `swapped`.
#[test]
fn red_proof_decide_margin_is_load_bearing() {
    let c = corpus();
    let mut bend = PlanBend::default();
    bend.arb = ArbBend { decide_margin: 0.4, ..ArbBend::default() };
    let r = sweep(&c, bend);
    println!(
        "RED PROOF decide_margin 0.5 -> 0.4: {}/{} acts still clean; \
         arb.n wrong on {}, arb.swapped wrong on {}, arb.sum_b {}, arb.sum_r {}, unit_key {}",
        r.clean,
        r.acts,
        r.get("arb.n"),
        r.get("arb.swapped"),
        r.get("arb.sum_b"),
        r.get("arb.sum_r"),
        r.get("unit_key")
    );
    assert!(r.get("arb.n") > 0, "a wrong decide margin has to move the escalation ladder");
    assert!(r.clean < r.acts, "a wrong decide margin has to break at least one act");
}

/// RED PROOF 2 — the wound rounding WITHOUT the rng draw. `resolve_stochastic`'s
/// only difference from `resolve` is that the sub-wound remainder is spent on a
/// `randf()` coin flip instead of carried; drop the draw and both branches play
/// the same deterministic game from the same position.
#[test]
fn red_proof_stochastic_wound_rounding_is_load_bearing() {
    let c = corpus();
    let mut bend = PlanBend::default();
    bend.arb = ArbBend { stochastic_wounds: false, ..ArbBend::default() };
    let r = sweep(&c, bend);
    println!(
        "RED PROOF stochastic wounds off: {}/{} acts still clean; \
         arb.sum_b wrong on {}, arb.sum_r wrong on {}, arb.n {}, arb.swapped {}, unit_key {}",
        r.clean,
        r.acts,
        r.get("arb.sum_b"),
        r.get("arb.sum_r"),
        r.get("arb.n"),
        r.get("arb.swapped"),
        r.get("unit_key")
    );
    assert!(
        r.get("arb.sum_b") > 0 || r.get("arb.sum_r") > 0,
        "without the dice the playout sums have to differ"
    );
    assert!(r.clean < r.acts, "deterministic rounding has to break at least one act");
}

/// The signature is an INPUT, and the port says so rather than inventing one: an
/// arbitrated act replayed WITHOUT its recorded `sig` must decline, not guess.
#[test]
fn a_close_top_two_without_a_signature_declines() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false, no_engage_fold: !c.knobs.engage_fold };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();
    let mut declined = 0usize;
    let mut arbitrated = 0usize;
    for act in &c.acts {
        if act.arbitration_rec().is_none() {
            continue;
        }
        arbitrated += 1;
        let search = Search::new(roll, &act.statics); // sig stays None
        if matches!(
            search.run(&act.state, act.player, &mut sc, None),
            Err(nml_core::Unsupported::PlayoutArbitration)
        ) {
            declined += 1;
        }
    }
    println!("without sig: {declined}/{arbitrated} arbitrated acts declined");
    assert_eq!(declined, arbitrated, "a missing signature must never be guessed around");
}

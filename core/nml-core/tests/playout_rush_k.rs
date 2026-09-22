//! Wave 6 (`rushk`) — the rollout's greedy brain rushes the k NEAREST
//! objectives instead of only the nearest.
//!
//! `Policy::policy_candidates` carried a single RUSH leg (the nearest objective,
//! `Tuning::rush_k == 1` today). The knob widens it to the first `rush_k`
//! objectives sorted by distance from the unit centre, stable on ties by the
//! objective's order in `state.objectives`; the EXISTING rush/demotion block runs
//! once per objective, unchanged. The fixture is `acts_wide_25.jsonl`, loaded the
//! way `menu_advance_k.rs` does.
//!
//! (a) `green_k1_matches_captured_main` — with `rush_k == 1` (the default an
//!     absent header key resolves to) every policy candidate list must equal the
//!     lists captured from the UNCHANGED code in the RED commit
//!     (`fixtures/playout_rush_k_k1.tsv`, written by re-running this test with
//!     `NML_RUSH_GOLDEN_OUT` set). The byte-identity claim rests on that capture
//!     plus the diff being a pure refactor with `take(rush_k)`; a captured k=1 run
//!     is not an independent oracle, it only catches a refactor that moves k=1.
//! (b) `green_k2_rushes_the_two_nearest_objectives` — with `rush_k == 2`, every
//!     activation whose state has >= 2 objectives carries exactly one more
//!     RUSH/ADVANCE-to-objective candidate than k=1, to a DIFFERENT dest, with
//!     every other candidate identical and in the same order.
use nml_core::menu::Candidate;
use nml_core::plan::{seams_of, tuning_of};
use nml_core::playout::Policy;
use nml_core::sim::{Scratch, ADVANCE, RUSH};
use nml_core::{act_statics, load_acts, ActCorpus, State};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const GOLDEN: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/playout_rush_k_k1.tsv");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const DEST_EPS: f64 = 1e-9;

fn corpus() -> ActCorpus {
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn idx(state: &State, key: &str) -> usize {
    *state.roster.index.get(key).unwrap_or_else(|| panic!("unknown unit key {key}"))
}

/// One candidate, canonically serialised. Floats ride `Debug` (the engine is
/// deterministic f32/f64 here), so the line is stable across runs.
fn ser(cands: &[Candidate]) -> String {
    let mut parts = Vec::new();
    for c in cands {
        parts.push(format!(
            "{}:{}:{:?}:{:?}:{:?}:{}:{:?}",
            c.unit, c.kind, c.dest, c.shoot, c.charge, c.patient, c.wave
        ));
    }
    parts.join(" | ")
}

/// The k=1 (default) candidate list of every pool unit of every recorded
/// activation — the unchanged `policy_candidates`.
fn k1_lines(c: &ActCorpus) -> Vec<String> {
    let per_act = act_statics(c, REPO);
    let seams = seams_of(&c.knobs);
    let mut sc = Scratch::default();
    let mut out = Vec::new();
    for (ai, act) in c.acts.iter().enumerate() {
        let p = Policy::new(&per_act[ai], &c.terrain, seams);
        for key in &act.pool {
            let i = idx(&act.state, key);
            let cands = p.policy_candidates(&act.state, i, &mut sc);
            out.push(format!("{ai}\t{key}\t{}", ser(&cands)));
        }
    }
    out
}

/// (a) GREEN — `rush_k == 1` replays every captured main candidate list.
#[test]
fn green_k1_matches_captured_main() {
    let c = corpus();
    assert_eq!(tuning_of(&c.knobs).rush_k, 1, "an absent playout_rush_k must resolve to 1");
    let got = k1_lines(&c);
    if let Ok(out) = std::env::var("NML_RUSH_GOLDEN_OUT") {
        std::fs::write(&out, format!("{}\n", got.join("\n"))).unwrap_or_else(|e| panic!("{e}"));
        println!("captured {} k=1 policy menus to {out}", got.len());
        return;
    }
    let want = std::fs::read_to_string(GOLDEN).unwrap_or_else(|e| panic!("{e}"));
    let want: Vec<&str> = want.trim_end().lines().collect();
    assert!(got.len() > 20, "a whole game: {} policy menus", got.len());
    assert_eq!(got.len(), want.len(), "menu count moved off the captured main run");
    let mut bad = 0usize;
    let mut first = None;
    for (i, (g, w)) in got.iter().zip(&want).enumerate() {
        if g != w {
            bad += 1;
            first.get_or_insert(format!("menu {i}: {g:?} != captured {w:?}"));
        }
    }
    println!("playout_rush_k k=1: {}/{} menus byte-identical to the captured main run", got.len() - bad, got.len());
    assert_eq!(bad, 0, "{bad} menus moved; first: {}", first.unwrap_or_default());
}

fn cand_eq(a: &Candidate, b: &Candidate) -> bool {
    if a.kind != b.kind
        || a.unit != b.unit
        || a.shoot != b.shoot
        || a.charge != b.charge
        || a.patient != b.patient
        || a.wave != b.wave
    {
        return false;
    }
    match (&a.dest, &b.dest) {
        (None, None) => true,
        (Some(x), Some(y)) => (0..3).all(|k| (x[k] - y[k]).abs() <= DEST_EPS),
        _ => false,
    }
}

/// The RUSH leg's own candidates: a RUSH, or the demotion's ADVANCE (patient is
/// false; the patient safe-advance is a separate leg).
fn is_objective_rush(c: &Candidate) -> bool {
    c.kind == RUSH || (c.kind == ADVANCE && !c.patient)
}

/// (b) GREEN — `rush_k = 2` adds exactly the second-nearest objective's rush to
/// every menu whose state has >= 2 objectives, and moves nothing else.
#[test]
fn green_k2_rushes_the_two_nearest_objectives() {
    let c = corpus();
    let per_act = act_statics(&c, REPO);
    let seams = seams_of(&c.knobs);
    let mut sc = Scratch::default();
    let (mut multi, mut checked, mut bad) = (0usize, 0usize, 0usize);
    let mut first = None;
    for (ai, act) in c.acts.iter().enumerate() {
        if act.state.objectives.len() < 2 {
            continue;
        }
        multi += 1;
        let mut p1 = Policy::new(&per_act[ai], &c.terrain, seams);
        let mut p2 = p1;
        p1.tuning.rush_k = 1;
        p2.tuning.rush_k = 2;
        for key in &act.pool {
            let i = idx(&act.state, key);
            let g1 = p1.policy_candidates(&act.state, i, &mut sc);
            let g2 = p2.policy_candidates(&act.state, i, &mut sc);
            checked += 1;
            let mut note = |msg: String| {
                bad += 1;
                first.get_or_insert(msg);
            };
            let r1: Vec<usize> = (0..g1.len()).filter(|&k| is_objective_rush(&g1[k])).collect();
            let r2: Vec<usize> = (0..g2.len()).filter(|&k| is_objective_rush(&g2[k])).collect();
            if r1.len() != 1 {
                note(format!("act {ai} unit {key}: k=1 rushed {} objectives", r1.len()));
                continue;
            }
            if r2.len() != 2 {
                note(format!("act {ai} unit {key}: k=2 rushed {} objectives", r2.len()));
                continue;
            }
            if !cand_eq(&g1[r1[0]], &g2[r2[0]]) {
                note(format!(
                    "act {ai} unit {key}: the first rush left the k=1 pick: {:?} != {:?}",
                    g2[r2[0]], g1[r1[0]]
                ));
            }
            let extra = r2[1];
            if g2[extra].dest == g2[r2[0]].dest {
                note(format!("act {ai} unit {key}: the second rush shares the first's dest"));
            }
            let mut g2r = g2.clone();
            g2r.remove(extra);
            if g2r.len() != g1.len() {
                note(format!(
                    "act {ai} unit {key}: k=2 without the extra rush is {} != k=1 {}",
                    g2r.len(),
                    g1.len()
                ));
            } else {
                for (j, (a, b)) in g2r.iter().zip(&g1).enumerate() {
                    if !cand_eq(a, b) {
                        note(format!("act {ai} unit {key}: candidate {j} moved: {a:?} != {b:?}"));
                    }
                }
            }
        }
    }
    assert!(multi > 0, "no recorded activation had >= 2 objectives — the fixture proves nothing");
    assert!(checked > 0, "no policy menu to compare");
    println!("playout_rush_k k=2: {checked} menus over {multi} multi-objective activations");
    assert_eq!(bad, 0, "{bad} mismatches; first: {}", first.unwrap_or_default());
}
//! Wave 6 (`advancek`) — the LIVE menu widens its patient safe-advance leg from
//! ONE candidate to the frontier's top-`advance_k` destinations.
//!
//! `safe_advances()` scores the safest eight frontier points along the one
//! bearing to the nearest objective (`SAFE_FRONTIER = 8`) and returns the best
//! `Tuning::advance_k` of them, best first, stable on ties by frontier order —
//! exactly the single candidate today when `advance_k == 1`. This test proves
//! the two halves on the SAME recorded oracle `menu_wide_recorded.rs` uses
//! (`acts_wide_25.jsonl`, a whole arena game whose trace carries every menu):
//! (a) `advance_k = 1` replays every recorded menu byte-exact, so an absent
//! `menu_advance_k` corpus is untouched; (b) `advance_k = 3` grows every menu
//! that carried a safe advance to up to three DISTINCT destinations, the first
//! identical to the k = 1 pick and every other candidate untouched.
use nml_core::menu::{candidates_tuned, Candidate};
use nml_core::plan::tuning_of;
use nml_core::sim::Scratch;
use nml_core::{act_statics, load_acts, ActCorpus, State};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const DEST_EPS: f64 = 1e-9;

fn corpus() -> ActCorpus {
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn idx(state: &State, key: &str) -> usize {
    *state.roster.index.get(key).unwrap_or_else(|| panic!("unknown unit key {key}"))
}

fn same(got: &Candidate, want: &Candidate) -> Result<(), String> {
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
                if (a[k] - b[k]).abs() > DEST_EPS {
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
    Ok(())
}

/// The CONTIGUOUS run of `patient` (safe-advance) candidates: `(first, end)`,
/// `end` exclusive. The menu builds them in one push, so they cannot interleave.
fn patient_run(menu: &[Candidate]) -> Option<(usize, usize)> {
    let start = menu.iter().position(|c| c.patient)?;
    let mut end = start;
    while end < menu.len() && menu[end].patient {
        end += 1;
    }
    Some((start, end))
}

fn counted_patients(menu: &[Candidate]) -> usize {
    menu.iter().filter(|c| c.patient).count()
}

fn dest_eq(a: &Option<[f64; 3]>, b: &Option<[f64; 3]>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(a), Some(b)) => (0..3).all(|k| (a[k] - b[k]).abs() <= DEST_EPS),
        _ => false,
    }
}

/// (a) GREEN — `advance_k = 1` (the default an absent header key resolves to)
/// replays the recorded oracle exactly.
#[test]
fn green_k1_equals_the_recorded_menus() {
    let c = corpus();
    let per_act = act_statics(&c, REPO);
    let tuning = tuning_of(&c.knobs);
    assert_eq!(tuning.advance_k, 1, "an absent menu_advance_k must resolve to 1");
    let mut sc = Scratch::default();
    let (mut menus, mut cands, mut bad) = (0usize, 0usize, 0usize);
    let mut first = None;
    for (ai, act) in c.acts.iter().enumerate() {
        for key in &act.pool {
            let want =
                act.menus.get(key).unwrap_or_else(|| panic!("act {ai}: unit {key} has no recorded menu"));
            let got = candidates_tuned(
                &act.state, &c.terrain, &per_act[ai], idx(&act.state, key), &mut sc, tuning,
            );
            menus += 1;
            cands += want.len();
            if got.len() != want.len() {
                bad += 1;
                first.get_or_insert(format!(
                    "act {ai} unit {key}: menu length {} != recorded {}",
                    got.len(),
                    want.len()
                ));
                continue;
            }
            for (i, (g, w)) in got.iter().zip(want).enumerate() {
                if let Err(why) = same(g, w) {
                    bad += 1;
                    first.get_or_insert(format!("act {ai} unit {key} candidate {i}: {why}"));
                }
            }
        }
    }
    assert!(menus > 20, "a whole game: {menus} menus");
    println!("advance_k=1 parity: {}/{} candidates over {menus} menus", cands - bad, cands);
    assert_eq!(bad, 0, "{bad} mismatches; first: {}", first.unwrap_or_default());
}

/// (b) GREEN — `advance_k = 3` widens every safe-advance run to at most three
/// DISTINCT destinations, keeps the k = 1 winner first, and leaves every other
/// candidate exactly where it was.
#[test]
fn green_k3_offers_the_top_three_safe_advances() {
    let c = corpus();
    let per_act = act_statics(&c, REPO);
    let k1 = tuning_of(&c.knobs);
    let mut k3 = k1;
    k3.advance_k = 3;
    let mut sc = Scratch::default();
    let (mut runs, mut widened, mut bad) = (0usize, 0usize, 0usize);
    let mut first = None;
    for (ai, act) in c.acts.iter().enumerate() {
        for key in &act.pool {
            let unit = idx(&act.state, key);
            let g1 = candidates_tuned(&act.state, &c.terrain, &per_act[ai], unit, &mut sc, k1);
            let g3 = candidates_tuned(&act.state, &c.terrain, &per_act[ai], unit, &mut sc, k3);
            let mut note = |msg: String| {
                bad += 1;
                first.get_or_insert(msg);
            };
            match patient_run(&g1) {
                None => {
                    if counted_patients(&g3) != 0 {
                        note(format!("act {ai} unit {key}: k=1 had no safe advance, k=3 did"));
                    }
                }
                Some((s1, e1)) => {
                    runs += 1;
                    if e1 - s1 != 1 {
                        note(format!("act {ai} unit {key}: k=1 carried {} safe advances", e1 - s1));
                    }
                    let Some((s3, e3)) = patient_run(&g3) else {
                        note(format!("act {ai} unit {key}: k=3 dropped the safe advance"));
                        continue;
                    };
                    let m = e3 - s3;
                    if m > 3 {
                        note(format!("act {ai} unit {key}: k=3 offered {m} safe advances"));
                    }
                    if m > 1 {
                        widened += 1;
                    }
                    if s3 != s1 {
                        note(format!("act {ai} unit {key}: safe-advance run starts at {s3} != {s1}"));
                    }
                    if let Err(why) = same(&g3[s3], &g1[s1]) {
                        note(format!("act {ai} unit {key}: the first safe advance moved: {why}"));
                    }
                    for a in s3..e3 {
                        for b in (a + 1)..e3 {
                            if dest_eq(&g3[a].dest, &g3[b].dest) {
                                note(format!("act {ai} unit {key}: safe advances {a}/{b} share a dest"));
                            }
                        }
                    }
                    if g3.len() != g1.len() + (m - 1) {
                        note(format!(
                            "act {ai} unit {key}: menu {} != {} + {}",
                            g3.len(),
                            g1.len(),
                            m - 1
                        ));
                    }
                    for k in 0..s1.min(g3.len()) {
                        if let Err(why) = same(&g3[k], &g1[k]) {
                            note(format!("act {ai} unit {key}: candidate {k} moved: {why}"));
                        }
                    }
                    for k in e3..g3.len() {
                        let j = k - (m - 1);
                        if j < g1.len() {
                            if let Err(why) = same(&g3[k], &g1[j]) {
                                note(format!("act {ai} unit {key}: candidate {j} moved: {why}"));
                            }
                        }
                    }
                }
            }
        }
    }
    assert!(runs > 0, "no menu carried a safe advance — the fixture proves nothing");
    assert!(widened > 0, "advance_k=3 never widened a single menu");
    println!("advance_k=3: {runs} safe-advance runs, {widened} widened");
    assert_eq!(bad, 0, "{bad} mismatches; first: {}", first.unwrap_or_default());
}

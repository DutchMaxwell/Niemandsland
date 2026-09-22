//! W1 ADVANCE+shoot — the LIVE leg on the table (22.09.) replays byte-exact
//! through the core's `menu_wide` knob.
//!
//! `acts_wide_25.jsonl` is one whole `tools/arena_match.gd` game recorded with
//! `NML_MENU_WIDE=1` (GDScript planner, menus in the trace, header knob
//! `menu_wide: true`). The recording is the oracle: every menu the table built
//! with the leg on must equal the core's `candidates_tuned` with
//! `wide_shoot: true` — same entries, same order, same shoot targets — and the
//! RED half proves the corpus carries moving shots at all: with the knob OFF the
//! core menus must DIFFER from the recording.
use nml_core::menu::{candidates_tuned, Candidate, Tuning};
use nml_core::plan::tuning_of;
use nml_core::sim::{Scratch, ADVANCE};
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

/// (menus, candidates, mismatches, moving shots in the RECORDING, first mismatch)
fn sweep(c: &ActCorpus, tuning: Tuning) -> (usize, usize, usize, usize, Option<String>) {
    // Per-act statics: this game carries a dynamic profile read mid-game (a hero
    // fell / a spell granted a rule), so one header-wide closure would be stale.
    let per_act = act_statics(c, REPO);
    let (mut menus, mut cands, mut bad, mut moving) = (0usize, 0usize, 0usize, 0usize);
    let mut first = None;
    let mut sc = Scratch::default();
    for (ai, act) in c.acts.iter().enumerate() {
        for key in &act.pool {
            let want = act.menus.get(key).unwrap_or_else(|| panic!("act {ai}: unit {key} has no recorded menu"));
            let got = candidates_tuned(&act.state, &c.terrain, &per_act[ai], idx(&act.state, key), &mut sc, tuning);
            menus += 1;
            moving += want.iter().filter(|w| w.kind == ADVANCE && w.shoot.is_some()).count();
            cands += want.len();
            if got.len() != want.len() {
                bad += want.len().max(got.len());
                first.get_or_insert(format!("act {ai} unit {key}: menu length {} != recorded {}", got.len(), want.len()));
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
    (menus, cands, bad, moving, first)
}

#[test]
fn the_recording_was_made_with_the_wide_leg_on() {
    let c = corpus();
    assert!(c.knobs.menu_wide, "the fixture's header must say menu_wide: true");
    let (menus, _, _, moving, _) = sweep(&c, Tuning::default());
    assert!(menus > 20, "a whole game: {menus} menus");
    assert!(moving > 0, "the recording carries no ADVANCE+shoot entry — the table leg did not fire");
}

#[test]
fn red_the_off_menu_differs_from_the_wide_recording() {
    let c = corpus();
    let (_, cands, bad, _, _) = sweep(&c, Tuning::default());
    assert!(bad > 0, "with wide_shoot OFF the core must NOT reproduce a recording made with the leg ON ({cands} candidates)");
}

#[test]
fn green_the_core_wide_menu_equals_every_recorded_menu() {
    let c = corpus();
    let tuning = tuning_of(&c.knobs);
    assert!(tuning.wide_shoot, "tuning_of must arm wide_shoot from the header knob");
    let (menus, cands, bad, moving, first) = sweep(&c, tuning);
    println!("WIDE menu parity: {}/{} candidates over {menus} menus, {moving} moving shots", cands - bad, cands);
    assert_eq!(bad, 0, "{bad} mismatches; first: {}", first.unwrap_or_default());
}

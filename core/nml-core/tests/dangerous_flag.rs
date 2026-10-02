//! Tree plan step 5b — `dangerous_rigid_end_only` names a real divergence only.
//!
//! A rigid move (no landing trail) rolls a model's Dangerous test off its END
//! and START bases (`sim::dangerous_dice`). That reading can part from the
//! table's per-model trail only where the straight route start -> end meets a
//! Dangerous cell between two clean ends, so the flag must fire exactly there:
//! never on a board with no Dangerous terrain at all, still on a route that
//! crosses one. The dice themselves never read the flag and stay untouched.

use std::rc::Rc;

use nml_core::plan::{seams_of, tuning_of};
use nml_core::sim::Scratch;
use nml_core::terrain::{base_in_terrain, is_dangerous, DANGEROUS};
use nml_core::{
    act_statics, candidates_tuned, load_acts, read_acts, resolve_stochastic_tray_on_board, ActCorpus, Candidate,
    GodotRng, Roll, State, Tray, UnitStatic,
};

const WIDE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const FLAG: &str = "dangerous_rigid_end_only";

/// Every pool row of act `ai` (a SHAKEN unit offers its recovery hold only).
fn rows(c: &ActCorpus, statics: &[Rc<Vec<UnitStatic>>], ai: usize, sc: &mut Scratch) -> Vec<Candidate> {
    let act = &c.acts[ai];
    let mut out = Vec::new();
    for key in &act.pool {
        let i = act.state.roster.index[key.as_str()];
        if act.state.shaken[i] {
            out.push(Candidate::hold(key));
        } else {
            out.extend(candidates_tuned(&act.state, &c.terrain, &statics[ai], i, sc, tuning_of(&c.knobs)));
        }
    }
    out
}

/// One row through the tray path: the next state, its rolls, and whether it flagged.
fn tray(c: &ActCorpus, statics: &[Rc<Vec<UnitStatic>>], ai: usize, cand: &Candidate) -> (State, Vec<Roll>, bool) {
    let (mut rng, mut tray) = (GodotRng::new(ai as i64), Tray::seeded(50_000 + ai as i64));
    let (next, shot) = resolve_stochastic_tray_on_board(&statics[ai], &c.acts[ai].state, &cand.action(),
                                                        &c.terrain, seams_of(&c.knobs), &mut rng, &mut tray).unwrap();
    let flagged = shot.unported.contains(&FLAG);
    (next, shot.rolls, flagged)
}

/// A moved model's (start, end, base radius).
type Route = ([f64; 3], [f64; 3], f64);

/// The moved models' routes, and whether any START or END base
/// stands in Dangerous terrain.
fn routes(c: &ActCorpus, st: &State, next: &State) -> (Vec<Route>, bool) {
    let (mut out, mut dirty) = (Vec::new(), false);
    for u in 0..st.units() {
        for (m, (a, b)) in st.positions[u].iter().zip(&next.positions[u]).enumerate() {
            if a != b {
                let r = next.radii[u][m];
                let inside = |p: &[f64; 3]| base_in_terrain([p[0] as f32, p[1] as f32, p[2] as f32], r, &c.terrain, is_dangerous);
                dirty |= inside(a) || inside(b);
                out.push((*a, *b, r));
            }
        }
    }
    (out, dirty)
}

#[test]
fn no_dangerous_terrain_no_flag() {
    let c = load_acts(WIDE).unwrap_or_else(|e| panic!("{e}"));
    let text = std::fs::read_to_string(WIDE).unwrap();
    let head: serde_json::Value = serde_json::from_str(text.lines().next().unwrap()).unwrap();
    let dangerous = head["terrain"]["cells"].as_array().unwrap().iter().filter(|x| x[2] == DANGEROUS).count();
    assert_eq!(dangerous, 0, "the wide board is the clean control");
    let (mut n, mut flagged, mut sc, statics) = (0usize, 0usize, Scratch::default(), act_statics(&c, REPO));
    for ai in 0..c.acts.len() {
        for cand in rows(&c, &statics, ai, &mut sc) {
            flagged += usize::from(tray(&c, &statics, ai, &cand).2);
            n += 1;
        }
    }
    println!("clean board: {flagged} of {n} tray rows flagged {FLAG}");
    assert_eq!(flagged, 0, "a board with no Dangerous cell cannot part from the table's trail");
}

#[test]
fn a_route_across_a_dangerous_cell_still_flags_and_rolls_nothing_new() {
    let c = load_acts(WIDE).unwrap_or_else(|e| panic!("{e}"));
    let text = std::fs::read_to_string(WIDE).unwrap();
    let (mut sc, statics) = (Scratch::default(), act_statics(&c, REPO));
    for ai in 0..c.acts.len() {
        for cand in rows(&c, &statics, ai, &mut sc) {
            let (next, rolls, _) = tray(&c, &statics, ai, &cand);
            let (moved, _) = routes(&c, &c.acts[ai].state, &next);
            let Some(&(a, b, _)) = moved.first() else { continue };
            let mid = [(a[0] + b[0]) / 2.0, 0.0, (a[2] + b[2]) / 2.0];
            // One Dangerous cell under the first moved model's mid-route (3" cells,
            // a 30-cell grid offset by 15 on this 6' x 4' board).
            let cell = |x: f64| (x / 0.0762 + 15.0).floor() as i64;
            let mut lines: Vec<String> = text.lines().map(String::from).collect();
            let mut head: serde_json::Value = serde_json::from_str(&lines[0]).unwrap();
            head["terrain"]["cells"].as_array_mut().unwrap().push(serde_json::json!([cell(mid[0]), cell(mid[2]), DANGEROUS]));
            lines[0] = head.to_string();
            let d = read_acts(std::io::Cursor::new(lines.join("\n").into_bytes()), "doctored").unwrap();
            assert_eq!(d.terrain.type_at([mid[0] as f32, 0.0, mid[2] as f32]), DANGEROUS, "the cell missed the route");
            let (dnext, drolls, dflag) = tray(&d, &statics, ai, &cand);
            let (_, dirty) = routes(&d, &d.acts[ai].state, &dnext);
            if dirty || dnext.positions != next.positions {
                continue; // an end touches the cell, or the move bent: not the case under test
            }
            println!("act {ai} kind {}: route across a Dangerous cell, clean ends -> flagged {dflag}", cand.kind);
            assert!(dflag, "a route across Dangerous terrain between clean ends must still flag");
            assert_eq!(format!("{drolls:?}"), format!("{rolls:?}"), "clean ends roll nothing: the flag reports, never rolls");
            return;
        }
    }
    panic!("no rigid row of the wide fixture crossed the doctored cell with clean ends");
}

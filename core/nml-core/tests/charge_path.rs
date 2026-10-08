//! aifix F6 (inventory row M20): `charge_needs_path` drops a charge target the mover cannot walk to within its charge
//! band. Fixture: the #857 act (charger "Change Brothers" and its victim, band 12") with a wall of Container cells
//! across the whole table between them — no way round.
use nml_core::{
    act_statics, acts::read_acts, menu::{best_charge, Tuning}, sim::Scratch,
};
use serde_json::{json, Value};
use std::io::Cursor;

const FIXTURE: &str = include_str!("fixtures/charge857_fall_short.json");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// The fixture act's best charge target (key, or None), with `column` filled with Container cells (None = untouched
/// terrain) and the knob `needs_path`.
fn target(column: Option<i64>, needs_path: bool) -> (Option<String>, String) {
    let fx: Value = serde_json::from_str(FIXTURE).unwrap();
    let mut header = fx["header"].clone();
    if let Some(c) = column {
        let cells = header["terrain"]["cells"].as_array_mut().unwrap();
        cells.retain(|cell| cell[0].as_i64() != Some(c));
        for z in 0..40 {
            cells.push(json!([c, z, 3]));
        }
    }
    let text = format!("{}\n{}\n", header, fx["act_line"]);
    let corpus = read_acts(Cursor::new(text), "fixture").unwrap();
    let acts = act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    let state = &act.state;
    let charger = state.roster.index[fx["act_line"]["pick"]["action"]["unit"].as_str().unwrap()];
    let victim = fx["act_line"]["pick"]["action"]["charge"].as_str().unwrap().to_string();
    let tuning = Tuning { charge_needs_path: needs_path, ..Tuning::default() };
    let mut sc = Scratch::default();
    let t = best_charge(state, &corpus.terrain, acts[0].as_slice(), charger, &mut sc, tuning, 8, None);
    (t.map(|e| state.key(e).to_string()), victim)
}

/// The Container column between the two units: the charger's nearest model sits in cell column 23, the victim's in 21
/// (cell column = floor(inch / 3) + 3 on this board), so column 22 is the building between them.
const BETWEEN: i64 = 22;

#[test]
fn a_building_across_the_table_between_two_units_removes_the_charge_when_the_knob_is_on() {
    let (off, victim) = target(Some(BETWEEN), false);
    assert_eq!(off.as_deref(), Some(victim.as_str()), "knob off: the charge is generated through the building");
    let (on, _) = target(Some(BETWEEN), true);
    assert_ne!(on.as_deref(), Some(victim.as_str()), "knob on: no charge row through the building, got {on:?}");
}

#[test]
fn with_a_clear_way_the_knob_keeps_the_charge() {
    let (off, victim) = target(None, false);
    let (on, _) = target(None, true);
    assert_eq!(off.as_deref(), Some(victim.as_str()));
    assert_eq!(on, off, "clear terrain: the knob changes nothing");
    // a building well behind the charger is no obstacle either
    let (behind, _) = target(Some(BETWEEN - 3), true);
    assert_eq!(behind.as_deref(), Some(victim.as_str()), "a building off the line keeps the charge");
}

//! G4-C2 (a): the menu's charge reach query applies the table's p.11 difficult-ground cap (6") from rules epoch 73.
//! Fixture: the #857 act (charger "Change Brothers" and its victim, 10.2" apart, charge band 12"). One FOREST cell is
//! painted where the charger's two front models stand: no route out of it avoids difficult ground, so the table's probe
//! plans the whole charge inside 6" and refuses it at execution. The cell is off the unit-centre line, so the menu's gate
//! (`corridor_forced_through`) stays silent — only the reach query can see it.
use nml_core::{
    act_statics,
    acts::{read_acts, EPOCH_73_V36},
    menu::{best_charge, Tuning},
    mods::LiveMod,
    sim::Scratch,
};
use serde_json::{json, Value};
use std::io::Cursor;
use std::rc::Rc;

const FIXTURE: &str = include_str!("fixtures/charge857_fall_short.json");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// The cell under the charger's two front models (26.4", 7.0" and 26.4", 8.6" from the table centre; 3" cells, half grid 15).
const UNDER_FRONT_MODELS: [i64; 3] = [23, 17, 2];

#[derive(Clone, Copy)]
struct Case {
    forest: bool,
    rules_epoch: u32,
    /// The live `buffs` ledger entry "Difficult Terrain (spell)" on the charger.
    granted_difficult: bool,
    /// Strider / Flying: `charge_no_difficult`, the p.13 exemption.
    exempt: bool,
}

const OPEN: Case = Case { forest: false, rules_epoch: EPOCH_73_V36, granted_difficult: false, exempt: false };

/// The fixture act's best charge target at the case's epoch (key, or None) next to the recorded victim.
fn target(c: Case) -> (Option<String>, String) {
    let fx: Value = serde_json::from_str(FIXTURE).unwrap();
    let mut header = fx["header"].clone();
    // The recorded ruin walls and cells go: this file pins the one forest cell alone.
    header["terrain"]["walls"] = json!([]);
    // The recording's epoch rides the header (`statics`), which is what the menu's path check reads.
    header["knobs"]["rules_epoch"] = json!(c.rules_epoch);
    let cells = header["terrain"]["cells"].as_array_mut().unwrap();
    cells.clear();
    if c.forest {
        cells.push(json!(UNDER_FRONT_MODELS));
    }
    let text = format!("{}\n{}\n", header, fx["act_line"]);
    let corpus = read_acts(Cursor::new(text), "fixture").unwrap();
    let acts = act_statics(&corpus, REPO);
    let mut state = corpus.acts[0].state.clone();
    let charger = state.roster.index[fx["act_line"]["pick"]["action"]["unit"].as_str().unwrap()];
    let victim = fx["act_line"]["pick"]["action"]["charge"].as_str().unwrap().to_string();
    state.charge_no_difficult[charger] = c.exempt;
    if c.granted_difficult {
        state.buffs[charger] = vec![LiveMod {
            hit_mod: 0,
            casting_mod: 0,
            morale_mod: 0,
            ap_mod: 0,
            def_mod: 0,
            defense_mod: 0,
            move_mod: 0,
            grants_rule: Rc::from("Difficult Terrain (spell)"),
            scope: Rc::from(""),
            attackers: false,
            once: true,
            name: Rc::from(""),
        }];
    }
    let tuning = Tuning { charge_needs_path: true, ..Tuning::default() };
    let mut sc = Scratch::default();
    let t = best_charge(&state, &corpus.terrain, acts[0].as_slice(), charger, &mut sc, tuning, c.rules_epoch, None);
    (t.map(|e| state.key(e).to_string()), victim)
}

#[test]
fn a_charger_standing_in_forest_loses_the_charge_beyond_six_inches_from_rules_3_6_on() {
    let (open, victim) = target(OPEN);
    assert_eq!(open.as_deref(), Some(victim.as_str()), "open ground: the 10.2\" charge fits the 12\" band");
    let (forest, _) = target(Case { forest: true, ..OPEN });
    assert_ne!(forest.as_deref(), Some(victim.as_str()), "forest under the front models caps the charge at 6\", got {forest:?}");
}

#[test]
fn below_rules_3_6_the_forest_changes_nothing() {
    let (forest, victim) = target(Case { forest: true, rules_epoch: EPOCH_73_V36 - 1, ..OPEN });
    assert_eq!(forest.as_deref(), Some(victim.as_str()), "the cap is a 3.6 rule: epoch 72 is byte-identical");
}

#[test]
fn strider_and_flying_never_pay_the_cap() {
    let (exempt, victim) = target(Case { forest: true, exempt: true, ..OPEN });
    assert_eq!(exempt.as_deref(), Some(victim.as_str()), "the p.13 exemption keeps the full band");
}

/// The carried Difficult Terrain rule needs no new code: `charge_band_in` -> `live_bands_of` has capped the band at 6"
/// since epoch 27, so the menu already drops the charge on open ground at BOTH epochs. Pinned so the claim stays true.
#[test]
fn a_granted_difficult_terrain_rule_already_caps_the_charge_on_open_ground() {
    for rules_epoch in [EPOCH_73_V36 - 1, EPOCH_73_V36] {
        let (granted, victim) = target(Case { granted_difficult: true, rules_epoch, ..OPEN });
        assert_ne!(granted.as_deref(), Some(victim.as_str()), "epoch {rules_epoch}: the carried rule caps the band, got {granted:?}");
    }
}

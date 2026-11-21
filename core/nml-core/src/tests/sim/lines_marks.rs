//! Lines audit (21.11.): the marker families' placement and spend sentences were pushed to `ShootResult.log` alone. Each test runs the act
//! on a SUPPLIED tray (what a door step runs on) with the dice a seeded run drew, and reads the tray's lines.
use super::*;

/// The tray lines of one act: a seeded run draws the dice, a supplied tray replays them.
fn tray_texts(st: &State, statics: &[UnitStatic], action: &Action, seed: i64, epoch: u32) -> Vec<String> {
    let terrain = crate::terrain::Terrain::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let run = |tray: &mut Tray| resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut crate::rng::GodotRng::new(0), tray).unwrap().1;
    let seeded = run(&mut Tray::seeded(seed));
    let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
    run(&mut tray);
    tray.all_lines().into_iter().map(|l| l.text).collect()
}

fn volley_on_b() -> Action {
    Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None }
}

fn has(lines: &[String], text: &str) -> bool {
    lines.iter().any(|l| l == text)
}

/// Piercing Tag below 73 (the table's 3.5 words) and at 73 (one token, +1 AP): the placement and the spend each say themselves on the tray.
/// RED on main: both were `ShootResult.log` only.
#[test]
fn a_piercing_tag_says_its_placement_and_its_spend_on_the_door_tray() {
    let (st, statics) = tag_line("Piercing Tag", 1, 24.0);
    let old = tray_texts(&st, &statics, &volley_on_b(), 27, 6);
    assert!(has(&old, "Piercing Tag: tagger places 1 marker on b — friendly attackers may spend them for +AP"), "{old:?}");
    assert!(has(&old, "Piercing Tag: 1 marker spent — +AP(1) on this volley"), "{old:?}");
    let v36 = tray_texts(&st, &statics, &volley_on_b(), 27, crate::acts::EPOCH_73_V36);
    assert!(has(&v36, "Piercing Tag: tagger places 1 token, stacked on b — a friendly attack may spend one token for +1 AP"), "{v36:?}");
    assert!(has(&v36, "Piercing Tag: one token spent — +1 AP on this volley (0 left)"), "{v36:?}");
}

/// Piercing Target stands while its target lives (from 67): below 73 `+AP(<markers>)`, from 73 the table's `+AP(1) ... (+1 (Target))` (the recorded
/// log words it `+1 (Target) stands`).
#[test]
fn a_piercing_target_says_it_stands_in_the_tables_words() {
    let (st, statics) = tag_line("Piercing Target", 1, 18.0);
    let old = tray_texts(&st, &statics, &volley_on_b(), 27, crate::acts::EPOCH_67_MARKERS_BURSTS);
    assert!(has(&old, "Piercing Target: +AP(1) stands while b lives"), "{old:?}");
    let v36 = tray_texts(&st, &statics, &volley_on_b(), 27, crate::acts::EPOCH_73_V36);
    assert!(has(&v36, "Piercing Target: tagger places 1 token on each of b — a friendly attack gets +1 AP"), "{v36:?}");
    assert!(has(&v36, "Piercing Target: +AP(1) stands while b lives (+1 (Target))"), "{v36:?}");
}

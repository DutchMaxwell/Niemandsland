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

/// Piercing Tag below 73 (the table's 3.5 words) and at 73 (one token, +1 AP): the placement says itself on the tray; the SPEND does not
/// (the door runs the table's own spend, `CoreActivation._spend_tag`, which writes the line: a tray line would say it twice).
/// RED on main: the placement was `ShootResult.log` only.
#[test]
fn a_piercing_tag_says_its_placement_on_the_door_tray_and_leaves_the_spend_to_the_door() {
    let (st, statics) = tag_line("Piercing Tag", 1, 24.0);
    let old = tray_texts(&st, &statics, &volley_on_b(), 27, 6);
    assert!(has(&old, "Piercing Tag: tagger places 1 marker on b — friendly attackers may spend them for +AP"), "{old:?}");
    assert!(old.iter().all(|l| !l.contains(" spent")), "the door says the spend: {old:?}");
    let v36 = tray_texts(&st, &statics, &volley_on_b(), 27, crate::acts::EPOCH_73_V36);
    assert!(has(&v36, "Piercing Tag: tagger places 1 token, stacked on b — a friendly attack may spend one token for +1 AP"), "{v36:?}");
    assert!(v36.iter().all(|l| !l.contains(" spent")), "the door says the spend: {v36:?}");
}

/// Piercing Target placements in the table's words; the `... stands while <T> lives` spend is the door's (`CoreActivation._spend_tag`).
#[test]
fn a_piercing_target_says_its_placement_in_the_tables_words() {
    let (st, statics) = tag_line("Piercing Target", 1, 18.0);
    let old = tray_texts(&st, &statics, &volley_on_b(), 27, crate::acts::EPOCH_67_MARKERS_BURSTS);
    assert!(has(&old, "Piercing Target: tagger places 1 marker on b — friendly attackers may spend them for +AP"), "{old:?}");
    assert!(old.iter().all(|l| !l.contains("stands while")), "the door says the spend: {old:?}");
    let v36 = tray_texts(&st, &statics, &volley_on_b(), 27, crate::acts::EPOCH_73_V36);
    assert!(has(&v36, "Piercing Target: tagger places 1 token on each of b — a friendly attack gets +1 AP"), "{v36:?}");
    assert!(v36.iter().all(|l| !l.contains("stands while")), "the door says the spend: {v36:?}");
}

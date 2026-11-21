//! Coverage ledger, AI shoot door (lane covfix-lines, 21.11.): the label and line classes the ledger found between the table and the core.
//! Lines and labels only - no die, save target or end state moves.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::step::{shoot_step, Step};

/// The kinds a door step asks for, in draw order: the loop a door runs (roll each `NeedRoll` from a seeded tray, feed it back).
fn asked_kinds(run: impl Fn(&mut Tray) -> ShootResult, seed: i64) -> Vec<&'static str> {
    let mut dice = Tray::seeded(seed);
    let (mut faces, mut kinds): (Vec<Vec<u8>>, Vec<&'static str>) = (Vec::new(), Vec::new());
    loop {
        match shoot_step(&faces, &run) {
            Step::NeedRoll { faces: n, kind, .. } => {
                kinds.push(kind);
                faces.push(dice.roll(n));
            }
            Step::Done(..) => return kinds,
            Step::Refused { reason, .. } => panic!("seed {seed}: {reason}"),
        }
    }
}

/// The table asks its Regeneration-family dice as `regeneration` (`_solo_roll_ignore_group`: `_owner_roll(.., "regeneration", ..)`), and so does
/// the door's step now; it said `attack`, which the door's own volley beats read as a hit roll (a tracer, the shot counter) and the ledger read
/// as 101 label-only differences. The roll RECORD keeps `attack`, the replay gates' kind (they compare recordings that call it so). RED on main:
/// the step asked `attack` for the ignore die.
#[test]
fn a_regeneration_die_is_asked_as_regeneration_and_recorded_as_attack() {
    let p = [ShootProfile { ap: 1, ..rifle(8) }];
    let att = shooter(3);
    let def = Ctx { regeneration: true, regen_target: 5, ..defender(4, 5) };
    let run = |t: &mut Tray| resolve_shooting_with_tray(&p, &[0], &[8], &att, &def, 12.0, t);
    let mut regen_dice = 0;
    for seed in 0..20 {
        let asked = asked_kinds(run, seed);
        let rec: Vec<&str> = run(&mut Tray::seeded(seed)).rolls.iter().map(|r| r.kind).collect();
        assert_eq!(asked.len(), rec.len(), "seed {seed}: one ask per record");
        assert!(rec.iter().all(|k| ["attack", "defense"].contains(k)), "seed {seed}: the record keeps the replay gates' kinds: {rec:?}");
        for (a, r) in asked.iter().zip(&rec) {
            assert!(if *a == "regeneration" { *r == "attack" } else { a == r }, "seed {seed}: asked {asked:?}, recorded {rec:?}");
        }
        regen_dice += asked.iter().filter(|&&k| k == "regeneration").count();
        if rec.len() > 2 {
            assert_eq!(asked[2], "regeneration", "seed {seed}: hits, saves, then the ignore die: {asked:?}");
        }
    }
    assert!(regen_dice > 0, "no seed reached the ignore roll, the check proved nothing");
}

/// A damage spell's ignore dice stay the cast leg's plain `spell_attack` (`CAST_KINDS` has no `spell_regeneration`): the name the ignore group
/// gave the draws taken since `from` is taken back, an earlier draw keeps it.
#[test]
fn a_spells_ignore_dice_keep_the_cast_legs_plain_kind() {
    let mut tray = Tray::supplied(vec![vec![3], vec![4]]);
    tray.name_next("regeneration");
    tray.roll(1);
    tray.name_next("regeneration");
    tray.roll(1);
    tray.tag_spell_regeneration(1);
    let feed = tray.feed().expect("supplied tray");
    assert_eq!((feed.kind_of(0), feed.kind_of(1)), (Some("regeneration"), Some("spell_attack")));
}

/// The tray lines of one volley of `n` shooters (one weapon each, six attacks) at a defender called "Def", run on a SUPPLIED tray with the
/// dice a seeded run drew (what a door step runs on).
fn tray_lines(att: &Ctx, def: &Ctx, weapon: ShootProfile, n: usize) -> Vec<String> {
    let profiles = [weapon];
    let dice = [6];
    let run = |tray: &mut Tray| {
        let shooters: Vec<Shooter> = ["Att", "Mate"].iter().take(n)
            .map(|o| Shooter { profiles: &profiles, keep: &[0], attacks: &dice, att, owner: o }).collect();
        resolve_volley_with_tray(&shooters, def, "Def", 12.0, 12.0, true, true, true, true, tray)
    };
    let seeded = run(&mut Tray::seeded(27));
    let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
    run(&mut tray);
    tray.all_lines().into_iter().map(|l| l.text).collect()
}

fn said(lines: &[String], text: &str) -> usize {
    lines.iter().filter(|l| l.as_str() == text).count()
}

/// Ledger 3 (20 cells): the table names the UNIT-level rule that cuts through Regeneration (`_solo_ignores_regen`'s unit arms, after the
/// weapon's own rules): Bane when Shooting, Anti-Regen / Unstoppable when Shooting (the Lacerate primitive) by their name, a unit-level
/// Rending as `Rending (granted)`; once per weapon with hits, only when the target has a Regeneration roll to skip. RED on main: silence.
#[test]
fn a_unit_level_regeneration_bypass_names_itself_on_the_door_tray() {
    let att = Ctx { rules_epoch: EPOCH_73_V36, v36_rules: true, ..shooter(4) };
    let regen = Ctx { regeneration: true, regen_target: 5, ..defender(4, 5) };
    let gun = |arm: Option<&str>, rending: bool| ShootProfile { bypass_regen: true, rending, regen_unit_arm: arm.map(Into::into), ..rifle(6) };
    for (arm, rending, want) in [
        (Some("Bane when Shooting"), false, "Bane when Shooting: Regeneration ignored"),
        (Some("Anti-Regen"), false, "Anti-Regen: Regeneration ignored"),
        (Some("Unstoppable when Shooting"), false, "Unstoppable when Shooting: Regeneration ignored"),
        (None, true, "Rending (granted): Regeneration ignored"),
    ] {
        let lines = tray_lines(&att, &regen, gun(arm, rending), 2);
        assert_eq!(said(&lines, want), 2, "once per weapon: {lines:?}");
        let bare = tray_lines(&att, &defender(4, 5), gun(arm, rending), 1);
        assert_eq!(said(&bare, want), 0, "no Regeneration roll to skip, no line: {bare:?}");
    }
    let silent = tray_lines(&att, &regen, gun(Some(""), true), 1);
    assert!(silent.iter().all(|l| !l.ends_with("Regeneration ignored")), "a unit arm that answers silently ends the walk: {silent:?}");
    let melee = ShootProfile { range: 0, ..gun(Some("Anti-Regen"), true) };
    let lines = tray_lines(&att, &regen, melee, 1);
    assert!(lines.iter().all(|l| !l.ends_with("Regeneration ignored")), "ranged profiles only: {lines:?}");
}

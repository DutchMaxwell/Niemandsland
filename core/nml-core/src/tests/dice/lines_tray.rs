//! Lines audit (21.11.): rule sentences that were pushed to `ShootResult.log` alone, now said on the tray the doors write, in the table's
//! words. Each test runs a volley on a SUPPLIED tray (what a door step runs on) with the dice a seeded run drew, so the dice are the same.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// The tray lines of one volley of `n` shooters (one weapon each) at a defender called "Def".
fn tray_lines(att: &Ctx, def: &Ctx, weapon: ShootProfile, n: usize) -> Vec<String> {
    tray_lines_of(att, def, weapon, n, 6)
}

/// `tray_lines` with `attacks` dice per weapon.
fn tray_lines_of(att: &Ctx, def: &Ctx, weapon: ShootProfile, n: usize, attacks: i64) -> Vec<String> {
    let profiles = [weapon];
    let dice = [attacks];
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

fn pierce_gun() -> ShootProfile {
    ShootProfile { rules: vec!["Pierce".into()], ..rifle(6) }
}

const PIERCE: &str = "Pierce: Rifle ignores Shielded +1, Cover +1";

/// The table's Pierce line (`_solo_resolve_saves`): the weapon's name and every positive Defense part the target holds, in
/// `_solo_defense_parts` order (Shielded, growth ladder, spell token), Cover last, said for EVERY weapon with hits (twice for two
/// shooters, no once-per-volley latch). RED on main: the line was only in `ShootResult.log`, worded with the shooter.
#[test]
fn a_pierce_weapon_names_what_it_ignores_on_the_door_tray() {
    let att = Ctx { rules_epoch: EPOCH_73_V36, ..shooter(4) };
    let target = Ctx { shielded: true, in_cover: true, ..defender(4, 5) };
    let lines = tray_lines(&att, &target, pierce_gun(), 2);
    assert_eq!(said(&lines, PIERCE), 2, "per weapon, in the table's order: {lines:?}");
    let all = Ctx { growth_def_mod: 2, growth_def_parts: "Defensive Growth +2", defense_mod: -1, ..target };
    let lines = tray_lines(&att, &all, pierce_gun(), 1);
    assert_eq!(said(&lines, "Pierce: Rifle ignores Shielded +1, Defensive Growth +2, Defense Buff +1, Cover +1"), 1, "{lines:?}");
}

/// Nothing positive to ignore, a plain weapon, or the pre-73 reading: no line.
#[test]
fn pierce_says_nothing_when_it_ignores_nothing() {
    let att = Ctx { rules_epoch: EPOCH_73_V36, ..shooter(4) };
    let target = Ctx { shielded: true, in_cover: true, ..defender(4, 5) };
    for (why, lines) in [
        ("a bare target", tray_lines(&att, &defender(4, 5), pierce_gun(), 1)),
        ("a plain weapon", tray_lines(&att, &target, rifle(6), 1)),
        ("epoch 72", tray_lines(&Ctx { rules_epoch: EPOCH_72_PLAYTEST_RULES, ..att }, &target, pierce_gun(), 1)),
    ] {
        assert!(lines.iter().all(|l| !l.starts_with("Pierce:")), "{why}: {lines:?}");
    }
}

fn anti_regen() -> ShootProfile {
    ShootProfile { bypass_regen: true, regen_bypass_rule: "Anti-Regen".into(), rules: vec!["Anti-Regen".into()], ..rifle(6) }
}

const REGEN: &str = "Anti-Regen: Regeneration ignored";

/// The table's `_solo_ignores_regen` line (rules 3.6): a weapon whose Regeneration bypass is a named map-read rule names it when the target
/// really has a Regeneration roll to skip, once per weapon with hits, whether or not a wound got through. RED on main: `out.log` only.
#[test]
fn an_anti_regen_weapon_names_its_bypass_on_the_door_tray() {
    let att = Ctx { rules_epoch: EPOCH_73_V36, v36_rules: true, ..shooter(4) };
    let regen = Ctx { regeneration: true, regen_target: 5, ..defender(4, 5) };
    let lines = tray_lines(&att, &regen, anti_regen(), 2);
    assert_eq!(said(&lines, REGEN), 2, "once per weapon: {lines:?}");
    let none = tray_lines(&att, &defender(4, 5), anti_regen(), 1);
    assert_eq!(said(&none, REGEN), 0, "no Regeneration roll to skip, no line: {none:?}");
    let plain = tray_lines(&att, &regen, rifle(6), 1);
    assert_eq!(said(&plain, REGEN), 0, "a plain weapon has no bypass rule to name: {plain:?}");
}

/// The Surge Mark's own line (`_solo_hits`), in the table's words, when the mark's grant paid at least one 6.
/// RED on main: only `out.log`, worded `Surge Mark: <shooter> — +N bonus hits ... against the marked target (once)`.
#[test]
fn a_surge_mark_names_its_bonus_on_the_door_tray() {
    let att = Ctx { surge_mark_grant: true, ..shooter(4) };
    let lines = tray_lines_of(&att, &defender(4, 5), rifle(24), 1, 24);
    let said_mark: Vec<&String> = lines.iter().filter(|l| l.starts_with("Surge Mark:")).collect();
    assert_eq!(said_mark.len(), 1, "once: {lines:?}");
    assert!(said_mark[0].starts_with("Surge Mark: +") && said_mark[0].ends_with(" (unmodified 6s) against the marked Def (once)"), "{said_mark:?}");
    let off = tray_lines_of(&shooter(4), &defender(4, 5), rifle(24), 1, 24);
    assert!(off.iter().all(|l| !l.starts_with("Surge Mark")), "no mark, no line: {off:?}");
}

/// The once-per-game extra attack names itself (`_solo_takedown_bonus_groups`, same words) on the tray as well as in the recorded log.
/// RED on main: `ShootResult.log` only.
#[test]
fn a_takedown_shot_names_its_extra_attack_on_the_door_tray() {
    let gun = ShootProfile { name: "Takedown Shot".into(), extra_attack_q: 2, ap: 2, deadly: 3, takedown: true, ..rifle(1) };
    let lines = tray_lines(&shooter(4), &defender(4, 5), gun, 1);
    assert_eq!(said(&lines, "Takedown Shot: Att makes one extra attack at Quality 2+ with AP(2), Deadly(3), Takedown (once per game)"), 1, "{lines:?}");
}

fn unstoppable_gun() -> ShootProfile {
    ShootProfile { rules: vec!["Unstoppable".into()], unstoppable: true, ..rifle(6) }
}

/// The table says a printed Unstoppable cutting through Regeneration (`_solo_ignores_regen`, the S1-06 arm): `Unstoppable: Regeneration
/// ignored`, once per weapon with hits, only against a target that really has a Regeneration roll (from 73). A Bane weapon answers
/// silently. RED on main: the core said nothing at all, not even in the recorded log.
#[test]
fn a_printed_unstoppable_names_its_regeneration_cut_on_the_door_tray() {
    let att = Ctx { rules_epoch: EPOCH_73_V36, v36_rules: true, ..shooter(4) };
    let regen = Ctx { regeneration: true, regen_target: 5, ..defender(4, 5) };
    let lines = tray_lines(&att, &regen, unstoppable_gun(), 2);
    assert_eq!(said(&lines, "Unstoppable: Regeneration ignored"), 2, "once per weapon: {lines:?}");
    assert_eq!(said(&tray_lines(&att, &defender(4, 5), unstoppable_gun(), 1), "Unstoppable: Regeneration ignored"), 0, "nothing to skip, no line");
    let bane = ShootProfile { rules: vec!["Bane".into()], bane: true, bypass_regen: true, ..rifle(6) };
    assert!(tray_lines(&att, &regen, bane, 1).iter().all(|l| !l.contains("Regeneration ignored")), "Bane answers silently");
}

/// The granted Unstoppable Mark says itself on the tray in the table's words (`<mark>: <U> — Regeneration is ignored (once)`); the recorded
/// log words it `Unstoppable: <U> — ignores <T>'s Regeneration (once)`. RED on main: `out.log` only.
#[test]
fn the_unstoppable_mark_names_its_regeneration_cut_on_the_door_tray() {
    let att = Ctx { rules_epoch: EPOCH_73_V36, v36_rules: true, unstoppable_mark: true, unstoppable_grant: true, ..shooter(4) };
    let regen = Ctx { regeneration: true, regen_target: 5, ..defender(4, 5) };
    let lines = tray_lines(&att, &regen, rifle(6), 1);
    assert_eq!(said(&lines, "Unstoppable Mark: Att — Regeneration is ignored (once)"), 1, "{lines:?}");
}

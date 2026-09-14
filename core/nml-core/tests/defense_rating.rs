//! The Defense(X) alias (STANDALONE_SWEEP_E_2026-09-14, row `Defense`,
//! TABLE-ONLY) — the Shielded family's RATING kind. The registry's gf-common
//! entry `Defense | primitive Shielded, defense_bonus_from_rating` drives the
//! table's Shielded coverage read off the rule's own rating (main.gd:5577-
//! 5593, `maxi(rating, 0)`), so the printed Defense(2) saves 2 better against
//! non-spell hits on the table. The core's Shielded-alias walk listed only the
//! five +1 names, so the sim gave a Defense(X) carrier nothing at all. The fix
//! reads the entry BY NAME (the #489 lesson — never the bare primitive) behind
//! `acts::EPOCH_54_DEFENSE_RATING` and folds +X into the SAME floored
//! non-spell-only seam the five aliases use (`combat::shielded_defense` via
//! `Ctx::shielded_bonus`), with the rules-must-log line naming the rating.
//! Frozen constants, never `CURRENT_RULES_EPOCH`: a wave-N bump must not
//! re-date what these assertions mean. The old leg is pinned to the frozen
//! constant of the epoch immediately below the bump at rebase time
//! (`EPOCH_52_UTILITY_SPELLS` at push time); re-point on rebase per the
//! wave protocol.

use nml_core::acts::{EPOCH_52_UTILITY_SPELLS, EPOCH_54_DEFENSE_RATING};
use nml_core::dice::{resolve_volley_with_tray, Shooter, Tray};
use nml_core::state::{MoveBands, Profile, Weapon};
use nml_core::unit::{Ctx, UnitStatic};
use nml_core::Registries;

/// A single-model carrier of one family name, in the faction block whose
/// mechanics entry fields the name, with one ranged weapon so the stamped
/// array is non-empty (the boost_bases_family harness, ranged half).
fn carrier(system: &str, faction: &str, rules: &[&str]) -> Profile {
    Profile {
        unit_id: "u".into(),
        name: "u".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![],
        model_count: 1,
        weapons: vec![Weapon {
            name: "Rifle".into(),
            range: 24.0,
            attacks: 2,
            count: 1,
            ap: 0,
            rules: vec![],
        }],
        special_rules: rules.iter().map(|s| s.to_string()).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: system.into(),
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    }
}

fn build_at(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
    let repo = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
    let mut reg = Registries::new(&repo);
    UnitStatic::build_for(&mut reg, &carrier(system, faction, rules), epoch)
}

/// A plain 4+ shooter, so the only thing that can move the save rung is the
/// defender's own fold (the machine_fog test's attacker shape).
fn volley_against(us: &UnitStatic, def: &Ctx, tray: &mut Tray) -> nml_core::dice::ShootResult {
    let p = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let strikers = [Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    resolve_volley_with_tray(&strikers, def, "Target", 12.0, 12.0, true, false, false, false, tray)
}

/// The board picture the defect names: a unit printing Defense(2) saves 2
/// better against a non-spell hit on the table and not at all better in the
/// sim. From 54 the walk honours the entry: the save rung folds defense 4 ->
/// 2 (the same floored non-spell-only seam the five +1 aliases ride), and the
/// rules-must-log line names the rating. At the epoch immediately below the
/// bump the record predates the wave — the rung stays 4+, byte-exact.
#[test]
fn defense_rating_folds_two_vs_non_spell_hits_at_epoch_54() {
    let us = build_at("gf", "common", &["Defense(2)"], EPOCH_54_DEFENSE_RATING);
    let mut t54 = Tray::seeded(27);
    let on = volley_against(&us, &us.ctx, &mut t54);
    let saves = &on.rolls[1];
    assert_eq!(saves.kind, "defense", "rolls[1] is the save batch");
    assert_eq!(
        saves.target, 2,
        "at the gate: Defense(2) saves 2 better vs the non-spell volley (defense 4 -> 2) (RED before the fix)"
    );
    assert!(
        on.log.iter().any(|l| l.contains("Defense(2)")
            && l.contains("+2 Defense vs non-spell hits")),
        "rules-must-log: the rating names itself (RED before the fix)"
    );

    let us_old = build_at("gf", "common", &["Defense(2)"], EPOCH_52_UTILITY_SPELLS);
    let mut t_old = Tray::seeded(27);
    let off = volley_against(&us_old, &us_old.ctx, &mut t_old);
    assert_eq!(
        off.rolls[1].target, 4,
        "below the bump: the record predates the wave, no fold — byte-exact"
    );
    assert!(
        !off.log.iter().any(|l| l.contains("Defense(2)")),
        "below the bump: the rating is not born yet, nothing logs"
    );
}

/// A bare "Defense" has no rating to read — the table's `maxi(rating, 0)`
/// yields no part at all (main.gd:5592/5594), so the walk must not stamp a
/// bonus for it either, at any epoch.
#[test]
fn bare_defense_without_rating_stays_inert() {
    let us = build_at("gf", "common", &["Defense"], EPOCH_54_DEFENSE_RATING);
    assert!(!us.ctx.shielded, "no rating, no shielded half (RED before the fix)");
    let mut t = Tray::seeded(27);
    let shot = volley_against(&us, &us.ctx, &mut t);
    assert_eq!(
        shot.rolls[1].target, 4,
        "the bare name folds nothing — the rung stays 4+"
    );
}

/// The literal "Shielded" keeps its pre-port silent read beside the new kind:
/// a carrier of the base name never walks the alias arm (the walk's own first
/// gate), so its rung stays the classic +1 either way.
#[test]
fn literal_shielded_keeps_its_plus_one() {
    let us = build_at("gf", "common", &["Shielded"], EPOCH_54_DEFENSE_RATING);
    assert!(us.ctx.shielded, "the literal's pre-port read");
    let mut t = Tray::seeded(27);
    let shot = volley_against(&us, &us.ctx, &mut t);
    assert_eq!(shot.rolls[1].target, 3, "the literal folds its +1, byte-exact");
}

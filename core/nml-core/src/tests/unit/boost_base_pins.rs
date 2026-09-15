use super::*;
use crate::state::{Profile, Weapon};

// ---- TEST WAVE 2026-09-15 — the BOOST BASES family of proven_vs_read_
// part2.tsv ("boost bases (save/to-hit window params)"): Changebound Boost,
// Clan Warrior Boost, Hive Bond Boost, Mischievous Boost. The fifth row,
// Rapid Blink Boost, pins its window through the activation placement and
// lives in tests/sim/growth_place_pins.rs. One test per row, by the rule's
// EXACT NAME through the REAL gf registry (the #489 lesson), at
// `CURRENT_RULES_EPOCH` — no epoch bump, nothing changes behaviour. The
// fixture is a one-model carrier printing the names the books print them
// (base first, `list_to_profile.py`'s own append order), with a rifle and a
// blade so both stamped arrays are non-empty.

fn boost_carrier(faction: &str, rules: &[&str], attacks: i64) -> Profile {
    Profile {
        unit_id: "u".into(),
        name: "u".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![
            Weapon { name: "Rifle".into(), range: 24.0, attacks, count: 1, ap: 0, rules: vec![] },
            Weapon { name: "Blade".into(), range: 0.0, attacks: 1, count: 1, ap: 0, rules: vec![] },
        ],
        special_rules: rules.iter().map(|s| s.to_string()).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    }
}

fn boost_unit(faction: &str, rules: &[&str], attacks: i64) -> UnitStatic {
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &boost_carrier(faction, rules, attacks), CURRENT_RULES_EPOCH)
}

/// One `attacks`-dice rifle volley AT `us` (the carrier is the DEFENDER) at
/// centre distance `dist_in` — the seam the Stealth alias's -1 to hit rides.
fn incoming(us: &UnitStatic, dist_in: f64, attacks: i64) -> crate::dice::ShootResult {
    let profiles = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let strikers = [crate::dice::Shooter {
        profiles: &profiles, keep: &[0], attacks: &[attacks], att: &att, owner: "att",
    }];
    let mut tray = crate::dice::Tray::seeded(27);
    crate::dice::resolve_volley_with_tray(
        &strikers, &us.ctx, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
    )
}

/// One `attacks`-dice rifle volley BY `us` at a plain Defense-5 target.
fn outgoing(us: &UnitStatic, attacks: i64) -> crate::dice::ShootResult {
    let profiles = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
    let strikers = [crate::dice::Shooter {
        profiles: &profiles, keep: &[0], attacks: &[attacks], att: &att, owner: "att",
    }];
    let mut tray = crate::dice::Tray::seeded(6);
    crate::dice::resolve_volley_with_tray(
        &strikers, &def, "Target", 12.0, 12.0, true, false, false, false, &mut tray,
    )
}

/// "Changebound Boost" (gf/change_disciples): the Stealth-primitive DATA
/// ALIAS pair. The read is `stealth_alias_of_excluding`'s strict-`>` fold,
/// and the printed base always comes first, so the pair reads the BASE
/// entry's over-9" window — the Boost's own unconditional entry (no
/// `over_in` key) never wins the tie, exactly RULE_FIDELITY_WAVE2 2B.1's
/// finding, pinned as-is: at 6" no penalty, past 9" the -1, with and without
/// the Boost alike.
#[test]
fn changebound_boost_keeps_the_base_over_nine_inch_window() {
    let on = boost_unit("change_disciples", &["Changebound", "Changebound Boost"], 8);
    assert_eq!(on.ctx.stealth_alias_penalty, 1, "the alias -1 stamps");
    assert_eq!(
        on.ctx.stealth_alias_over_in, 9.0,
        "the strict-> fold keeps the BASE entry's over-9\" gate — the Boost never widens it"
    );
    assert!(on.ctx.stealth_alias_applies_charged, "the charge leg both entries print");
    let at6 = incoming(&on, 6.0, 8);
    assert_eq!(at6.rolls[0].target, 4, "6\" is inside the 9\" window: no penalty");
    let at12 = incoming(&on, 12.0, 8);
    assert_eq!(at12.rolls[0].target, 5, "past 9\": Quality 4+ reads 5+ (the -1)");

    let base = boost_unit("change_disciples", &["Changebound"], 8);
    assert_eq!(base.ctx.stealth_alias_over_in, 9.0, "the base alone: the same window");
    assert_eq!(base.ctx.stealth_alias_penalty, 1);
    assert_eq!(incoming(&base, 6.0, 8).rolls[0].target, 4, "without the Boost the 6\" read is identical");
    assert_eq!(incoming(&base, 12.0, 8).rolls[0].target, 5, "and so is the past-9\" read");
}

/// "Clan Warrior Boost" (gf/eternal_dynasty): the extra-ATTACK-die Surge's
/// own Boost — the entry's `surge_low: 5` behind its `upgrades` coupling
/// ("Clan Warrior") moves `surge_attack_low` from the unboosted 6 to 5, so
/// a successful unmodified 5 draws an extra attack die too. Seed 6's eight
/// attack faces carry one 6 and two 5s: three extra dice with the Boost,
/// the six alone without, each rolling at the weapon's own to-hit target.
#[test]
fn clan_warrior_boost_draws_the_fives_extra_attack_dice() {
    let on = boost_unit("eternal_dynasty", &["Clan Warrior", "Clan Warrior Boost"], 8);
    assert!(on.shoot[0].surge_attack, "the base rule's extra-attack facet");
    assert_eq!(on.shoot[0].surge_attack_low, 5, "the Boost's printed 5-6 window");
    let on_v = outgoing(&on, 8);
    let faces = &on_v.rolls[0].faces;
    assert_eq!(
        (faces.iter().filter(|f| **f == 6).count(), faces.iter().filter(|f| **f == 5).count()),
        (1, 2),
        "fixture guard: seed 6 draws one 6 and two 5s"
    );
    let extras = on_v
        .rolls
        .iter()
        .find(|x| x.kind == "attack" && x.count != 8)
        .expect("the extra-attack dice roll");
    assert_eq!(extras.count, 3, "the 6 plus both 5s draw three extra dice");
    assert_eq!(extras.target, 4, "the extras roll at the weapon's own to-hit target");

    let off = boost_unit("eternal_dynasty", &["Clan Warrior"], 8);
    assert!(off.shoot[0].surge_attack, "the base facet without the Boost");
    assert_eq!(off.shoot[0].surge_attack_low, 6, "unboosted: only the 6s draw");
    let off_v = outgoing(&off, 8);
    let extras_off = off_v
        .rolls
        .iter()
        .find(|x| x.kind == "attack" && x.count != 8)
        .expect("the extra-attack dice roll");
    assert_eq!(extras_off.count, 1, "the 6 alone");
}

/// "Hive Bond Boost" (gf/alien_hives): the Banner primitive's DATA-ALIAS
/// walk — the carried name's own entry rides `banner_bonus_of`'s max, so the
/// Boost's `morale_bonus: 2` wins over the base Hive Bond's 1 (the wave-2
/// §3.6 correction's own read: the walk "finds the Boost entry ... and
/// returns max(1, 2) = 2 — the book's number"). The morale seam: Quality 4
/// routs at 2+ with the Boost, 3+ with the base alone, 4+ bare.
#[test]
fn hive_bond_boost_lifts_the_banner_bonus_to_two() {
    let on = {
        let mut reg = Registries::new(&repo_root());
        crate::unit::capture_reads_for_epoch(
            &mut reg,
            &boost_carrier("alien_hives", &["Hive Bond", "Hive Bond Boost"], 2),
            CURRENT_RULES_EPOCH,
        )
    };
    assert_eq!(on.morale_bonus, 2, "the Boost's morale_bonus wins the banner max");
    assert_eq!(crate::combat::morale_target(4, 2), 2, "Quality 4+ routs at 2+ with the Boost");

    let base = {
        let mut reg = Registries::new(&repo_root());
        crate::unit::capture_reads_for_epoch(
            &mut reg,
            &boost_carrier("alien_hives", &["Hive Bond"], 2),
            CURRENT_RULES_EPOCH,
        )
    };
    assert_eq!(base.morale_bonus, 1, "the base alias's own 1");
    assert_eq!(crate::combat::morale_target(4, 1), 3, "and at 3+ with the base alone");

    let plain = {
        let mut reg = Registries::new(&repo_root());
        crate::unit::capture_reads_for_epoch(
            &mut reg,
            &boost_carrier("alien_hives", &[], 2),
            CURRENT_RULES_EPOCH,
        )
    };
    assert_eq!(plain.morale_bonus, 0, "no banner alias, no bonus");
}

/// "Mischievous Boost" (gf/goblin_reclaimers): the Bane family's widened
/// save re-roll window — the entry's own `reroll_save_low: 5` + `over_in: 9`
/// behind the `upgrades` coupling ("If this model has Mischievous"), stamped
/// on the SHOOT array by `stamp_bane_boost`'s epoch-6 arm. Seed 27's
/// sixty-four attack faces draw 30 hits whose save batch carries three 5s
/// and six 6s: all nine re-roll at 12", only the sixes at exactly 9", and
/// the firing names itself (rules-must-log). The widened window's numbers
/// are double-pinned by the merged integration test
/// (`tests/boost_bases_family.rs`); this pin adds the stamped fields and the
/// log line by the exact name.
#[test]
fn mischievous_boost_stamps_the_widened_bane_window_by_name() {
    let on = boost_unit("goblin_reclaimers", &["Mischievous", "Mischievous Boost"], 64);
    assert!(on.shoot[0].bane, "the base alias banes at every epoch");
    assert_eq!(on.shoot[0].bane_low, 5, "the widened window's 5");
    assert_eq!(on.shoot[0].bane_over_in, 9.0, "strictly past 9\"");
    assert_eq!(on.shoot[0].bane_rule, "Mischievous Boost", "the stamped read names the rule (#489)");

    let volley = |us: &UnitStatic, dist_in: f64| {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &def, "Target", dist_in, dist_in, true, false, false, false, &mut tray,
        )
    };
    let at12 = volley(&on, 12.0);
    let saves = &at12.rolls[1];
    assert_eq!(saves.kind, "defense", "rolls[1] is the save batch");
    let fives = saves.faces.iter().filter(|&&f| f == 5).count();
    let sixes = saves.faces.iter().filter(|&&f| f == 6).count();
    assert_eq!((fives, sixes), (3, 6), "fixture guard: seed 27's save batch");
    assert_eq!(
        at12.rolls[2].count as usize,
        fives + sixes,
        "12\": every successful 5-6 re-rolls (the widened window)"
    );
    assert!(
        at12
            .log
            .iter()
            .any(|l| l == &format!("Mischievous Boost: Target — {fives} successful save(s) of 5-6 re-roll")),
        "rules-must-log: the widened window names itself: {:?}",
        at12.log
    );

    let at9 = volley(&on, 9.0);
    assert_eq!(at9.rolls[2].count as usize, sixes, "exactly 9\" is not \"over\": the base 6s-only window");

    let base = boost_unit("goblin_reclaimers", &["Mischievous"], 64);
    assert_eq!(base.shoot[0].bane_low, 0, "no Boost, no widening");
    assert_eq!(base.shoot[0].bane_rule, "", "and nothing to name");
    let without = volley(&base, 12.0);
    assert_eq!(without.rolls[2].count as usize, sixes, "no Boost: only the 6s re-roll");
    assert!(
        !without.log.iter().any(|l| l.contains("Mischievous Boost")),
        "no widened window fired, nothing logs"
    );
}

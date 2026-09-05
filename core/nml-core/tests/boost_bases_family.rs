//! The Boost Bases family (wave 4, epoch 6) — one test per ported name,
//! through the REAL registry (each name's own (system, faction) entry, the
//! folder its book prints). The six Boost auras already read PORTED (the
//! "Aura Channel" wave); this family ports their GRANTED BASES, so an aura
//! grant lands on a live handler instead of a name the core never reads.
//! Every new spelling is stated BY NAME by build_for's epoch-6 named arms
//! (`acts::EPOCH_6_TABLE_RULES`, the frozen gate); the named forms log at
//! the dice folds (rules-must-log). Epoch literals 6/5, never
//! `CURRENT_RULES_EPOCH`: a wave-5 bump must not re-date what these
//! assertions mean. "Guardian Boost" (the Fortified family's own Boost) is
//! the inverted ladder — already ported by its family's wave, PRESENT at 5
//! through the generic stamp, and covered there.

use nml_core::dice::{resolve_volley_with_tray, Shooter, Tray};
use nml_core::state::{MoveBands, Profile, Weapon};
use nml_core::unit::{CondAp, Ctx, ShootProfile, UnitStatic};
use nml_core::Registries;

/// A single-model carrier of one family name, in the faction block whose
/// mechanics entry fields the name, with one ranged and one melee weapon so
/// both stamped arrays are non-empty.
fn carrier(system: &str, faction: &str, rules: &[&str]) -> Profile {
    Profile {
        unit_id: "u".into(),
        name: "u".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![],
        model_count: 1,
        weapons: vec![
            Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 2,
                count: 1,
                ap: 0,
                rules: vec![],
            },
            Weapon {
                name: "Claws".into(),
                range: 0.0,
                attacks: 1,
                count: 1,
                ap: 0,
                rules: vec![],
            },
        ],
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

/// Every stamped conditional-AP spec whose condition is `cond`, across the
/// ranged and melee arrays.
fn forms_with<'a>(us: &'a UnitStatic, cond: &str) -> Vec<&'a CondAp> {
    us.shoot
        .iter()
        .chain(us.melee.iter())
        .flat_map(|sp: &ShootProfile| sp.cond_ap.iter())
        .filter(|c| c.condition == cond)
        .collect()
}

/// "Havocbound Boost" (gf/havoc_brothers): the printed always leg ("always
/// gets AP(+1) from Havocbound (instead of only when shooting over 9" away,
/// or when charging)"), stated BY NAME behind the entry's own `upgrades`
/// coupling. PRESENT at 6, ABSENT at 5 — and at 6 it REPLACES the base's two
/// conditional legs (never stacks), while without the Boost those legs stamp
/// exactly as the piercehunt wave shipped them.
#[test]
fn havocbound_boost_stamps_the_always_leg_from_epoch_6() {
    let on = build_at("gf", "havoc_brothers", &["Havocbound", "Havocbound Boost"], 6);
    let always = forms_with(&on, "always");
    assert_eq!(
        always.len(),
        2,
        "epoch 6: the always leg on both stamped profiles (RED before the fix)"
    );
    assert_eq!(always[0].ap_bonus, 1, "epoch 6: AP(+1)");
    assert_eq!(always[0].name, "Havocbound Boost", "the named form logs itself");
    assert!(
        forms_with(&on, "on_charge").is_empty(),
        "the Boost replaces the charge leg, never stacks"
    );
    assert!(
        forms_with(&on, "ranged_over").is_empty(),
        "the Boost replaces the ranged leg, never stacks"
    );

    let off = build_at("gf", "havoc_brothers", &["Havocbound", "Havocbound Boost"], 5);
    assert!(
        forms_with(&off, "always").is_empty(),
        "epoch 5: pre-port records stay inert (RED before the fix)"
    );

    let without = build_at("gf", "havoc_brothers", &["Havocbound"], 6);
    assert!(forms_with(&without, "always").is_empty(), "no Boost, no always leg");
    assert_eq!(
        forms_with(&without, "on_charge").len(),
        2,
        "without the Boost the base's own two legs stamp, byte-exact"
    );
}

/// "Mischievous Boost" (gf/goblin_reclaimers): the Bane family's widened
/// re-roll window — the entry's own `reroll_save_low: 5` + `over_in: 9`,
/// behind the `upgrades` coupling ("If this model has Mischievous"). The
/// volley consumes it strictly past 9": successful unmodified saves of 5-6
/// re-roll (instead of only on 6), and the firing names itself
/// (rules-must-log). PRESENT at 6, ABSENT at 5 (the base "Mischievous" alias
/// itself is a wave-3 spelling — an epoch-5 record never banes), and the
/// base-only carrier keeps the 6s-only window either way.
#[test]
fn mischievous_boost_widens_the_bane_window_over_nine_inches_at_epoch_6() {
    let us = build_at("gf", "goblin_reclaimers", &["Mischievous", "Mischievous Boost"], 6);
    let p = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
    let strikers = [Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    // Seed 27 draws 30 hits at 4+, then 3 fives and 6 sixes among the saves.
    let mut t6 = Tray::seeded(27);
    let on = resolve_volley_with_tray(
        &strikers, &def, "Target", 12.0, 12.0, true, false, false, false, &mut t6,
    );
    let saves = &on.rolls[1];
    assert_eq!(saves.kind, "defense", "rolls[1] is the save batch");
    let fives = saves.faces.iter().filter(|&&f| f == 5).count();
    let sixes = saves.faces.iter().filter(|&&f| f == 6).count();
    assert!(fives > 0 && sixes > 0, "this seed must land both faces or the test is blind");
    let rerolls = &on.rolls[2];
    assert_eq!(
        rerolls.count as usize,
        fives + sixes,
        "epoch 6, 12\": every successful 5-6 re-rolls (the widened window)"
    );
    assert!(
        on.log.iter().any(|l| l.contains("Mischievous Boost")),
        "rules-must-log: the widened window names itself"
    );

    // Exactly 9" is not "over": the base 6s-only window.
    let mut t9 = Tray::seeded(27);
    let at9 = resolve_volley_with_tray(
        &strikers, &def, "Target", 9.0, 9.0, true, false, false, false, &mut t9,
    );
    let sixes9 = at9.rolls[1].faces.iter().filter(|&&f| f == 6).count() as i64;
    assert_eq!(at9.rolls[2].count, sixes9, "exactly 9\" stays shut");

    // Epoch 5: the record predates the wave — the base 6s-only window,
    // byte-exact ("Mischievous" itself baned since the bane wave; only the
    // WIDENED window is epoch-6 born).
    let us5 = build_at("gf", "goblin_reclaimers", &["Mischievous", "Mischievous Boost"], 5);
    let p5 = [us5.shoot[0].clone()];
    let strikers5 = [Shooter { profiles: &p5, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    let mut t5 = Tray::seeded(27);
    let off = resolve_volley_with_tray(
        &strikers5, &def, "Target", 12.0, 12.0, true, false, false, false, &mut t5,
    );
    assert_eq!(
        off.rolls[2].count as usize,
        sixes,
        "epoch 5: the base 6s-only window, byte-exact"
    );
    assert!(
        !off.log.iter().any(|l| l.contains("Mischievous Boost")),
        "epoch 5: the widened window is not born yet"
    );

    // Without the Boost the base carrier keeps the 6s-only window.
    let base = build_at("gf", "goblin_reclaimers", &["Mischievous"], 6);
    let pb = [base.shoot[0].clone()];
    let strikers_b = [Shooter { profiles: &pb, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    let mut tb = Tray::seeded(27);
    let without = resolve_volley_with_tray(
        &strikers_b, &def, "Target", 12.0, 12.0, true, false, false, false, &mut tb,
    );
    assert_eq!(
        without.rolls[2].count as usize,
        sixes,
        "no Boost: only the 6s re-roll, the base window"
    );
    assert!(
        !without.log.iter().any(|l| l.contains("Mischievous Boost")),
        "no widened window fired, nothing logs"
    );
}

/// "Machine-Fog Boost" (gf/machine_cults): the printed unconditional form of
/// Machine-Fog's own -1 ("enemies attacking them always get -1 to hit …
/// instead of only when being shot/charged from over 9" away"). It folds
/// into the evasive flag (both legs, any range) and the base entry's
/// conditional alias leg stands down so the two never stack. PRESENT at 6,
/// ABSENT at 5 (the alias leg keeps its over-9" gate, byte-exact), and the
/// volley's to-hit target shows the -1 inside 9" with the rules-must-log
/// line.
#[test]
fn machine_fog_boost_makes_the_minus_one_unconditional_at_epoch_6() {
    let on = build_at("gf", "machine_cults", &["Machine-Fog", "Machine-Fog Boost"], 6);
    assert!(
        on.ctx.evasive,
        "epoch 6: the Boost folds into the evasive flag (RED before the fix)"
    );
    assert_eq!(
        on.ctx.stealth_alias_penalty, 0,
        "the base entry's conditional alias leg stands down (never stacks)"
    );

    let off = build_at("gf", "machine_cults", &["Machine-Fog", "Machine-Fog Boost"], 5);
    assert!(!off.ctx.evasive, "epoch 5: pre-port records stay inert");
    assert_eq!(
        off.ctx.stealth_alias_penalty, 1,
        "epoch 5: the base alias leg keeps its over-9\" gate, byte-exact"
    );

    // The volley, 6" out (inside the alias gate): the -1 lands from the Boost.
    let p = [on.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let strikers = [Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    let mut t6 = Tray::seeded(27);
    let shot = resolve_volley_with_tray(
        &strikers, &on.ctx, "Target", 6.0, 6.0, false, false, false, false, &mut t6,
    );
    assert_eq!(
        shot.rolls[0].target, 5,
        "epoch 6, 6\": the always -1 (4+ minus 1 = 5+) (RED before the fix)"
    );
    assert!(
        shot.log.iter().any(|l| l.contains("Machine-Fog Boost")),
        "rules-must-log: the Boost names itself at the volley seam"
    );

    // Without the Boost the conditional leg stays shut inside 9".
    let base = build_at("gf", "machine_cults", &["Machine-Fog"], 6);
    let pb = [base.shoot[0].clone()];
    let strikers_b = [Shooter { profiles: &pb, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    let mut tb = Tray::seeded(27);
    let base_shot = resolve_volley_with_tray(
        &strikers_b, &base.ctx, "Target", 6.0, 6.0, false, false, false, false, &mut tb,
    );
    assert_eq!(
        base_shot.rolls[0].target, 4,
        "without the Boost the conditional alias stays shut inside 9\""
    );
    assert!(
        !base_shot.log.iter().any(|l| l.contains("Machine-Fog Boost")),
        "nothing fired, nothing logs"
    );
}

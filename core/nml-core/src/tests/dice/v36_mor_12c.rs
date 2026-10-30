//! Rules 3.6 row MOR-12c tests (dice module); owned by lane morale.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::acts::read_act_header;
use crate::rules::Registries;
use crate::unit::UnitStatic;

// Row MOR-12c: the Rust core strikes with the Sergeant bearer's AP share, the
// way the table (`main._solo_resolve_saves`) and the GDScript EV
// (`AiEv.stamp_sergeant` / `profile_ev`) already do from rules 3.6. The share
// is the first profile's own attacks over the live alive count (min 1), and
// that fraction of the plain hits saves as its own batch at AP(+ap_bonus).

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Five models, a 24" rifle and a blade, each pooling 10 attacks. Built
/// through the REAL registry at `epoch`, with the carrier rule `rule`.
fn bearer(rule: &str, epoch: u32) -> UnitStatic {
    let header = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{"sgt":{{"unit_id":"sgt","name":"Bearer",
        "quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":5,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres","special_rules":["{rule}"],
        "item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":10,"count":1,"ap":0,"rules":[]}},
        {{"name":"Blade","range":0,"attacks":10,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    let hdr = read_act_header(&header).expect("header parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, hdr.profiles.get("sgt").expect("sgt"), epoch)
}

fn reports(us: &UnitStatic, rule: &str) -> usize {
    us.unimplemented.iter().filter(|u| u.rule == rule).count()
}

fn attacker(alive: i64) -> Ctx {
    Ctx { quality: 4, models: alive, ..Default::default() }
}

fn target() -> Ctx {
    defender(4, 5)
}

/// The first save roll of a result, and every plain (non-6-upgraded) save.
fn first_save_target(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "defense").expect("a save batch").target
}

fn failed(faces: &[u8], save_target: i64) -> i64 {
    faces.iter().filter(|&&f| (f as i64) < save_target).count() as i64
}

/// Rules 3.6: no Sergeant report, and the bearer's share of the plain hits
/// saves one AP worse while the rest keeps the printed Defense.
#[test]
fn a_sergeant_strike_saves_its_bearer_share_at_ap_plus_1_at_epoch_73() {
    let us = bearer("Sergeant", EPOCH_73_V36);
    assert_eq!(reports(&us, "Sergeant"), 0, "the core plays the rule from 73");

    let p = [us.shoot[0].clone()];
    let att = attacker(5);
    let def = target();
    let mut tray = Tray::seeded(27);
    let r = resolve_volley_with_tray(&[striker(&p, &[0], &[10], &att)], &def, "Target", 12.0, 12.0, true, true, true, false, &mut tray);
    assert_eq!(first_save_target(&r), 5, "AP(+1) on Defense 4+");
}

/// The wounds mirror the table's split exactly: the bearer's fraction of the
/// plain hits (10 attacks / 5 models = share 2, so 2/10 of the hits) saves on
/// 5+, the rest on 4+.
#[test]
fn the_bearers_share_and_the_rest_land_the_tables_wounds_at_epoch_73() {
    let us = bearer("Sergeant", EPOCH_73_V36);
    let p = [us.shoot[0].clone()];
    let att = attacker(5);
    let def = target();

    let mut probe = Tray::seeded(1300);
    let attack_faces = probe.roll(10);
    let hits = faces_to_hits(&attack_faces, 4) as i64;
    let share = (10.0_f64 / 5.0_f64).round().max(1.0) as i64;
    let sgt = (hits as f64 * share as f64 / 10.0_f64).round() as i64;
    let sgt_faces = probe.roll(sgt as usize);
    let rest_faces = probe.roll((hits - sgt) as usize);
    let want = failed(&sgt_faces, 5) + failed(&rest_faces, 4);

    let mut tray = Tray::seeded(1300);
    let r = resolve_volley_with_tray(&[striker(&p, &[0], &[10], &att)], &def, "Target", 12.0, 12.0, true, true, true, false, &mut tray);
    assert_eq!(r.wounds, want, "bearer share at AP(+1), the rest at AP(0)");
    assert!(
        r.log.iter().any(|l| l == &format!("Sergeant: Striker strikes {sgt} hits with AP(+1)")),
        "log: {:?}", r.log
    );
}

/// The same numbers as the GDScript EV case: 10 attacks hit on 4+ = 5 hits,
/// share 2/10, Defense 4. The bearer's 1 hit saves on 5+ (2/3 unsaved), the
/// other 4 on 4+ (2 unsaved): 2 + 2/3 instead of the plain 2.5.
#[test]
fn the_ev_prices_the_bearers_share_like_the_table_at_epoch_73() {
    let us = bearer("Sergeant", EPOCH_73_V36);
    let ev = crate::combat::profile_ev(&us.shoot[0], 10, &attacker(5), &target(), 12.0, false);
    assert!((ev - (2.0 + 2.0 / 3.0)).abs() < 1e-9, "ev: {ev}");
}

/// Great Sergeant strikes at AP(+2) instead of surging on 5-6.
#[test]
fn a_great_sergeant_strike_saves_at_ap_plus_2_at_epoch_73() {
    let us = bearer("Great Sergeant", EPOCH_73_V36);
    assert_eq!(reports(&us, "Great Sergeant"), 0, "the core plays the rule from 73");
    assert!(!us.melee[0].surge, "no 5-6 extra hits from 73");

    let p = [us.melee[0].clone()];
    let att = attacker(5);
    let def = target();
    let mut tray = Tray::seeded(27);
    let r = resolve_melee_with_tray(&[striker(&p, &[0], &[10], &att)], &def, "Target", false, true, true, &mut tray);
    assert_eq!(first_save_target(&r), 6, "AP(+2) on Defense 4+");
}

/// Control: at rules 3.5 the report still names the rule and no AP share is
/// stamped, so the save keeps the printed Defense.
#[test]
fn epoch_72_keeps_the_report_and_no_ap_share() {
    let us = bearer("Sergeant", EPOCH_72_PLAYTEST_RULES);
    assert_eq!(reports(&us, "Sergeant"), 1, "still unimplemented below the gate");
    assert_eq!(us.melee[0].sergeant_attacks, 0, "the share is never guessed");
    assert_eq!(us.shoot[0].ap, 0, "no AP share below the gate");

    let p = [us.shoot[0].clone()];
    let att = attacker(5);
    let def = target();
    let mut tray = Tray::seeded(27);
    let r = resolve_volley_with_tray(&[striker(&p, &[0], &[10], &att)], &def, "Target", 12.0, 12.0, true, true, true, false, &mut tray);
    assert_eq!(first_save_target(&r), 4, "plain Defense 4+");
}

/// Control: Great Sergeant keeps its 3.5 5-6 window at 72, no report.
#[test]
fn epoch_72_keeps_great_sergeants_surge_window() {
    let us = bearer("Great Sergeant", EPOCH_72_PLAYTEST_RULES);
    assert_eq!(reports(&us, "Great Sergeant"), 0, "no report below the gate");
    assert!(us.melee[0].surge, "the 5-6 window replays");
    assert_eq!(us.melee[0].surge_low, 5, "the printed 5-6 window replays");
}

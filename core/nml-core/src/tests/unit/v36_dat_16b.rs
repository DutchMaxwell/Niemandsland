//! DAT-16b — a Regeneration-bypass line names the rule only when the target actually has a
//! Regeneration-family roll to skip. Below `EPOCH_73_V36` the line stays byte-identical (replay).

use super::*;

/// A gf/blessed_sisters carrier whose weapon prints "Disintegrate" (the book's own shape), built off
/// the REAL registry entry (`bypass_regen: true`, condition `vs_armor`, threshold 3) at `epoch`.
fn disintegrate_carrier(weapon_range: i64, epoch: u32) -> UnitStatic {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":2,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Flamer","range":{weapon_range},"attacks":24,"count":1,"ap":0,
          "rules":["Disintegrate"]}}]}}}}}}"#
    );
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("carrier").expect("carrier");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// One exchange of the carrier's Disintegrate weapon against a Defense 4 target. `target_regen`
/// decides whether the target has a Regeneration(5+) roll; `v36` stamps the rules-3.6 context (the
/// gate the bypass line reads), the same shape `ctx_for` writes from the record's epoch.
fn disintegrate_volley(us: &UnitStatic, melee: bool, target_regen: bool, v36: bool) -> crate::dice::ShootResult {
    let att = Ctx {
        quality: 2,
        models: 1,
        v36_rules: v36,
        rules_epoch: if v36 { crate::acts::EPOCH_73_V36 } else { crate::acts::EPOCH_46_DISINTEGRATE_REGEN },
        ..Default::default()
    };
    let def = Ctx {
        defense: 4,
        tough: 1,
        models: 1,
        regeneration: target_regen,
        regen_target: if target_regen { 5 } else { 0 },
        playtest_rules: v36,
        rules_epoch: if v36 { crate::acts::EPOCH_73_V36 } else { crate::acts::EPOCH_46_DISINTEGRATE_REGEN },
        ..Default::default()
    };
    let mut tray = crate::dice::Tray::seeded(27);
    if melee {
        let prof = us.melee[0].clone();
        crate::dice::resolve_melee_with_tray(
            &[crate::dice::Shooter {
                profiles: std::slice::from_ref(&prof),
                keep: &[0],
                attacks: &[24],
                att: &att,
                owner: "Carrier",
            }],
            &def, "Target", true, false, false, &mut tray,
        )
    } else {
        let prof = us.shoot[0].clone();
        crate::dice::resolve_shooting_with_tray(&[prof], &[0], &[24], &att, &def, 12.0, &mut tray)
    }
}

fn named_bypass(out: &crate::dice::ShootResult) -> bool {
    out.log.iter().any(|l| l.contains("Disintegrate") && l.contains("Regeneration ignored"))
}

/// From rules 3.6 the line is written only when the hit target really regenerates: a plain target
/// never "ignores" a roll it does not have, and a Regeneration target still names the refusal.
#[test]
fn a_regen_bypass_line_is_written_only_for_a_regenerating_target() {
    let us = disintegrate_carrier(24, crate::acts::EPOCH_73_V36);
    let plain = disintegrate_volley(&us, false, false, true);
    assert!(plain.caused > 0, "fixture seed no longer wounds — pick another");
    assert!(!named_bypass(&plain), "a plain target has no Regeneration to ignore: {:?}", plain.log);
    let regenerating = disintegrate_volley(&us, false, true, true);
    assert!(regenerating.caused > 0, "fixture seed no longer wounds — pick another");
    assert!(named_bypass(&regenerating), "rules-must-log: {:?}", regenerating.log);
}

/// The melee leg reads the same target flag and the same epoch gate.
#[test]
fn the_melee_regen_bypass_line_is_gated_the_same_way() {
    let us = disintegrate_carrier(0, crate::acts::EPOCH_73_V36);
    let plain = disintegrate_volley(&us, true, false, true);
    assert!(plain.caused > 0, "fixture seed no longer wounds — pick another");
    assert!(!named_bypass(&plain), "a plain melee target has no Regeneration to ignore: {:?}", plain.log);
    let regenerating = disintegrate_volley(&us, true, true, true);
    assert!(regenerating.caused > 0, "fixture seed no longer wounds — pick another");
    assert!(named_bypass(&regenerating), "rules-must-log: {:?}", regenerating.log);
}

/// Below rule 73 the old line stays byte-identical: it still names the bypass against a plain target,
/// so every pre-73 replay keeps the log it recorded.
#[test]
fn below_rules_36_the_old_line_stays_byte_exact() {
    let us = disintegrate_carrier(24, crate::acts::EPOCH_46_DISINTEGRATE_REGEN);
    let plain = disintegrate_volley(&us, false, false, false);
    assert!(plain.caused > 0, "fixture seed no longer wounds — pick another");
    assert!(named_bypass(&plain), "pre-73 replay keeps the old line: {:?}", plain.log);
}

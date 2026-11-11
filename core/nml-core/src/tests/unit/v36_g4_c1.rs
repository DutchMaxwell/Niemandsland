//! Rules 3.6 unit-level Relentless bridge: the table grants a unit's own
//! Relentless to its shooting profiles at the reading seam, so a carrier whose
//! weapon does not print the rule still rolls the bonus hit over 9". The core
//! must mirror that bridge on the shoot array only, from `EPOCH_73_V36` on.

mod g4_c1 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Giant","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The real `build_for` product: one unit-level rule (empty = none) over a
    /// 24" rifle and a melee blade, neither weapon printing the rule.
    fn carrier(unit_rule: &str, epoch: u32) -> UnitStatic {
        let printed = if unit_rule.is_empty() { String::new() } else { format!("\"{unit_rule}\"") };
        let tpl = HEADER.replace(
            "\"special_rules\":[]",
            &format!("\"special_rules\":[{printed}]"),
        );
        let header = read_act_header(&tpl).expect("HEADER parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
    }

    /// One two-die volley from `us`'s rifle at a lone Defense-4 model `dist`
    /// inches away, on the same seed: faces [6, 2], exactly one unmodified 6.
    fn volley(us: &UnitStatic, dist: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[2], att: &att, owner: "att",
        }];
        let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
        let mut tray = crate::dice::Tray::seeded(5);
        crate::dice::resolve_volley_with_tray(
            &strikers, &def, "def", dist, dist, true, false, false, false, &mut tray,
        )
    }

    fn save_counts(out: &crate::dice::ShootResult) -> Vec<i64> {
        out.rolls.iter().filter(|r| r.kind == "defense" && r.count > 0).map(|r| r.count).collect()
    }

    #[test]
    fn the_unit_rule_bridges_onto_the_shoot_array_at_73() {
        let us = carrier("Relentless", EPOCH_73_V36);
        assert!(us.shoot[0].relentless, "the unit's own Relentless reaches the rifle");
    }

    #[test]
    fn below_epoch_73_the_unit_rule_stays_off_the_shoot_array() {
        let us = carrier("Relentless", EPOCH_72_PLAYTEST_RULES);
        assert!(!us.shoot[0].relentless, "epoch 72 replays byte-identical");
    }

    #[test]
    fn a_unit_without_the_rule_is_not_stamped() {
        let us = carrier("", EPOCH_73_V36);
        assert!(!us.shoot[0].relentless, "no rule, no bridge");
    }

    #[test]
    fn the_unit_rule_never_reaches_the_melee_array() {
        let us = carrier("Relentless", EPOCH_73_V36);
        assert!(!us.melee[0].relentless, "melee is out of scope; the over-9 gate cannot fire there");
    }

    #[test]
    fn the_bridged_rule_adds_the_bonus_hit_over_nine_inches() {
        let on = volley(&carrier("Relentless", EPOCH_73_V36), 12.0);
        let atk = on.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        let plain = atk.faces.iter().filter(|&&f| f >= 4).count() as i64;
        let sixes = atk.faces.iter().filter(|&&f| f == 6).count() as i64;
        assert_eq!(sixes, 1, "the fixed seed draws exactly one unmodified 6");
        assert_eq!(
            save_counts(&on),
            vec![plain + sixes],
            "over 9\": the bridged rule adds one hit for the unmodified 6"
        );

        let before = volley(&carrier("Relentless", EPOCH_72_PLAYTEST_RULES), 12.0);
        let atk_before = before.rolls.iter().find(|r| r.kind == "attack").expect("the attack roll");
        let plain_before = atk_before.faces.iter().filter(|&&f| f >= 4).count() as i64;
        assert_eq!(
            save_counts(&before),
            vec![plain_before],
            "epoch 72: no bridge, no bonus hit"
        );
    }
}

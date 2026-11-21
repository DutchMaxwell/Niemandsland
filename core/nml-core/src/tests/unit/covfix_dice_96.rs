//! Coverage ledger shoot m1, lane covfix-dice: the pending-96 dice batch. Every carrier is the real `build_for` product through
//! the real registry; each test reads one rule at 95 (byte-exact replay) and at 96 (the army-book reading).

mod pending_96 {
    use super::super::*;
    use crate::acts::{PENDING_EPOCH_ENHANCED_PRIMAL_NEEDS_PRIMAL, PENDING_EPOCH_UNIT_BANE_ALIAS, PENDING_EPOCH_UNIT_IMPRECISE};

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// A gf carrier of `faction` whose OWN rules are `unit_rules` and whose one rifle prints `weapon_rules`, read at `epoch`.
    fn carrier(faction: &str, unit_rules: &[&str], weapon_rules: &[&str], epoch: u32) -> UnitStatic {
        let q = |v: &[&str]| v.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = HEADER
            .replace("\"battle_brothers\"", &format!("\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{}]", q(unit_rules)))
            .replace("\"rules\":[]", &format!("\"rules\":[{}]", q(weapon_rules)));
        let header = read_act_header(&tpl).expect("HEADER parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
    }

    #[test]
    fn a_unit_borne_imprecise_costs_its_shooting_one_to_hit_from_96() {
        let e = PENDING_EPOCH_UNIT_IMPRECISE;
        assert_eq!(carrier("alien_hives", &["Imprecise"], &[], e - 1).shoot[0].hit_bonus, 0, "95 replays the unread rule");
        assert_eq!(carrier("alien_hives", &["Imprecise"], &[], e).shoot[0].hit_bonus, -1, "96: the bearer gets -1 to hit");
        let both = carrier("alien_hives", &["Imprecise"], &["Imprecise"], e);
        assert!(both.shoot[0].imprecise && both.shoot[0].hit_bonus == 0, "a weapon that prints it pays once, in the dice fold");
    }

    #[test]
    fn a_unit_borne_obliterate_reads_like_the_weapon_from_96() {
        let e = PENDING_EPOCH_UNIT_BANE_ALIAS;
        let old = &carrier("daemons_of_lust", &["Obliterate"], &[], e - 1).shoot[0];
        assert!(old.bane && !old.bypass_regen, "95: the flat sixes re-roll, Regeneration kept");
        let new = &carrier("daemons_of_lust", &["Obliterate"], &[], e).shoot[0];
        assert!(new.bane && new.bypass_regen, "96: Obliterate ignores Regeneration");
        assert_eq!((new.bane_condition.as_str(), new.bane_threshold, new.bane_low), ("vs_tough_ge", 3, 5), "96: 5-6 window vs Tough(3)+");
    }

    #[test]
    fn a_unit_borne_reap_keeps_its_condition_from_96() {
        let e = PENDING_EPOCH_UNIT_BANE_ALIAS;
        assert_eq!(carrier("rebel_guerrillas", &["Reap"], &[], e - 1).shoot[0].bane_condition, "", "95: no condition read");
        assert_eq!(carrier("rebel_guerrillas", &["Reap"], &[], e).shoot[0].bane_condition, "shaken_or_fatigued", "96: only vs Shaken / Fatigued");
    }

    #[test]
    fn a_bane_mark_gives_its_bearer_no_standing_bane_at_96() {
        let us = carrier("saurian_starhosts", &["Bane Mark"], &[], PENDING_EPOCH_UNIT_BANE_ALIAS);
        assert!(!us.shoot[0].bane && !us.melee[0].bane, "96: the Mark is a runtime mark, never a standing Bane on the bearer");
    }

    /// The real volley of 64 shots from `us`'s rifle with an Enhanced Primal grant live, at `epoch`.
    fn granted_volley(us: &UnitStatic, epoch: u32) -> crate::dice::ShootResult {
        let p = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, rules_epoch: epoch, surge_grant: true, ..Default::default() };
        let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(&strikers, &def, "Target", 12.0, 12.0, true, false, false, false, &mut tray)
    }

    #[test]
    fn an_enhanced_primal_grant_without_primal_rolls_nothing_from_96() {
        let e = PENDING_EPOCH_ENHANCED_PRIMAL_NEEDS_PRIMAL;
        let plain = carrier("battle_brothers", &[], &[], e);
        assert!(!plain.shoot[0].surge_attack, "the carrier prints no extra-attack form");
        let attack_rolls = |r: &crate::dice::ShootResult| r.rolls.iter().filter(|x| x.kind == "attack").count();
        assert_eq!(attack_rolls(&granted_volley(&plain, e - 1)), 2, "95: the grant rolls its own extras group");
        assert_eq!(attack_rolls(&granted_volley(&plain, e)), 1, "96: no Primal, nothing to widen");
    }
}

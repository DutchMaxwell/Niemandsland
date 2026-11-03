//! Rules 3.6 wave, AI gate AI-G2 (alias primitives): a WEAPON rule the faction map resolves to the Bane
//! primitive (Smash, Reap, Decimate) re-rolls the defender's Defense 6s like the printed Bane, from the 3.6
//! epoch on, under its own book name. Every carrier is the real `build_for` product through the real registry,
//! and the volley is the real dice path. Twin: test/v36/aig_g2_test.gd.

mod aig_g2 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// A carrier whose one 24" rifle prints `rule`, read at `epoch`.
    fn carrier(faction: &str, rule: &str, epoch: u32) -> UnitStatic {
        let printed = if rule.is_empty() { String::new() } else { format!("\"{rule}\"") };
        let tpl = HEADER
            .replace("\"battle_brothers\"", &format!("\"{faction}\""))
            .replace("\"rules\":[]", &format!("\"rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("HEADER parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
    }

    /// The real volley of 64 shots from `us`'s rifle at a lone Defense-5 model `dist` inches away.
    fn volley(us: &UnitStatic, dist: f64) -> crate::dice::ShootResult {
        let p = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(&strikers, &def, "Target", dist, dist, true, false, false, false, &mut tray)
    }

    /// Control: the printed Bane keeps both halves, unconditionally.
    #[test]
    fn the_printed_bane_keeps_its_reroll_and_its_regeneration_bypass() {
        let us = carrier("battle_brothers", "Bane", EPOCH_73_V36);
        assert!(us.shoot[0].bane && us.shoot[0].bypass_regen, "printed Bane");
        assert_eq!(us.shoot[0].bane_condition, "", "no gate on the printed rule");
    }

    /// Control: below the 3.6 epoch the alias weapons replay as before (no Bane at all).
    #[test]
    fn below_epoch_73_a_smash_weapon_stays_plain() {
        let us = carrier("battle_brothers", "Smash", EPOCH_72_PLAYTEST_RULES);
        assert!(!us.shoot[0].bane, "epoch 72 replays byte-identical");
    }

    /// Smash prints `reroll_save_sixes` + `over_half_range` and no Regeneration bypass.
    #[test]
    fn a_smash_weapon_banes_through_its_map_entry_at_73() {
        let us = carrier("battle_brothers", "Smash", EPOCH_73_V36);
        assert!(us.shoot[0].bane, "Smash resolves to the Bane primitive");
        assert!(!us.shoot[0].bypass_regen, "the entry's bypass_regen is false: the alias never cuts Regeneration");
        assert_eq!(us.shoot[0].bane_condition, "over_half_range", "the entry's own gate rides along");
    }

    /// Decimate prints `above_half_strength`.
    #[test]
    fn a_decimate_weapon_banes_above_half_strength() {
        let us = carrier("daemons_of_plague", "Decimate", EPOCH_73_V36);
        assert!(us.shoot[0].bane, "Decimate resolves to the Bane primitive");
        assert_eq!(us.shoot[0].bane_condition, "above_half_strength");
    }

    /// Reap prints `shaken_or_fatigued` (its widened 5+ window is a follow-up, not part of this alias row).
    #[test]
    fn a_reap_weapon_banes_against_a_shaken_or_fatigued_target() {
        let us = carrier("rebel_guerrillas", "Reap", EPOCH_73_V36);
        assert!(us.shoot[0].bane, "Reap resolves to the Bane primitive");
        assert_eq!(us.shoot[0].bane_condition, "shaken_or_fatigued");
    }

    /// The live volley: past half range the Smash gate is open and the log names the book rule; inside
    /// half range the gate is shut, nothing is re-rolled and the volley equals the plain rifle's.
    #[test]
    fn the_volley_logs_smash_past_half_range_and_stays_plain_inside_it() {
        let us = carrier("battle_brothers", "Smash", EPOCH_73_V36);
        let open = volley(&us, 18.0);
        assert!(open.log.iter().any(|l| l.starts_with("Smash:")), "rules-must-log: {:?}", open.log);
        let shut = volley(&us, 6.0);
        let plain = volley(&carrier("battle_brothers", "", EPOCH_73_V36), 6.0);
        assert!(!shut.log.iter().any(|l| l.contains("Smash")), "gate shut: {:?}", shut.log);
        assert_eq!(shut.wounds, plain.wounds, "a shut gate changes nothing");
    }
}

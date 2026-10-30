//! Rules 3.6 lane morale tests for the unit module; owned by lane morale.

// --- Row MOR-12: Sergeant / Great Sergeant strike with AP instead of extra hits.
mod mor_12 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    /// One Great Sergeant bearer (aof/ogres, the folder the book prints) with a rifle and a
    /// blade, so both facets are observable, built through the REAL registry at `epoch`.
    fn great_sergeant(rules: &str, epoch: u32) -> UnitStatic {
        let header = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{"gs":{{"unit_id":"gs","name":"Bearer",
            "quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"aof","faction_folder":"ogres","special_rules":[{rules}],
            "item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
            "weapons":[{{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}},
            {{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
        );
        let hdr = read_act_header(&header).expect("header parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, hdr.profiles.get("gs").expect("gs"), epoch)
    }

    fn reports(us: &UnitStatic, rule: &str) -> usize {
        us.unimplemented.iter().filter(|u| u.rule == rule).count()
    }

    /// Rules 3.6: Great Sergeant's 5-6 extra-hit window is gone; the bearer strikes at AP(+2)
    /// instead. That share needs the live alive count (Sergeant's own gap), so the static stamp
    /// reports it by name rather than surging.
    #[test]
    fn a_great_sergeant_leaves_the_surge_window_and_reports_its_gap_at_epoch_73() {
        let us = great_sergeant("\"Great Sergeant\"", EPOCH_73_V36);
        assert!(!us.shoot[0].surge, "no extra hits when shooting from 73");
        assert!(!us.melee[0].surge, "no extra hits in melee from 73");
        assert_eq!(us.shoot[0].surge_low, 6, "no 5-6 window from 73");
        assert_eq!(reports(&us, "Great Sergeant"), 1, "exactly one report, by the exact name");
    }

    /// The rules 3.5 leg: every game recorded at 72 replays the 5-6 window, no report.
    #[test]
    fn a_great_sergeant_keeps_its_surge_window_at_epoch_72() {
        let us = great_sergeant("\"Great Sergeant\"", EPOCH_72_PLAYTEST_RULES);
        assert!(us.shoot[0].surge, "the facet replays at 72");
        assert_eq!(us.shoot[0].surge_low, 5, "the printed 5-6 replays at 72");
        assert_eq!(reports(&us, "Great Sergeant"), 0, "no report at 72");
    }

    /// Sergeant keeps its live-count report at BOTH epochs: the core never guesses the share.
    #[test]
    fn a_sergeant_reports_its_live_count_gap_at_epoch_72_and_epoch_73() {
        for e in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            let us = great_sergeant("\"Sergeant\"", e);
            assert_eq!(reports(&us, "Sergeant"), 1, "epoch {e}: one report, by the exact name");
            assert_eq!(us.melee[0].sergeant_attacks, 0, "epoch {e}: the share is never guessed");
            assert_eq!(reports(&great_sergeant("", e), "Sergeant"), 0, "epoch {e}: no rule, no report");
        }
    }
}

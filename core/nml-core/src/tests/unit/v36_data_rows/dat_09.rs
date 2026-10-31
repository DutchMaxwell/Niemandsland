//! DAT-09 tests (rules 3.6, lane data); empty until the row lands - start with `use super::super::*;`.
use super::super::*;

    // ------- DAT-09: the Shrouding primitives' 3.6 numbers ----------------
    //
    // The core reads both Shrouding primitives off the carrier book's own
    // entry in the REAL gf / aof maps (`melee_shroud_params`,
    // `ranged_shroud_params`). Rules 3.6 takes 2" off a charge against Melee
    // Shrouding (3.5: 3") and 4" off a shot against Ranged Shrouding (3.5:
    // 6"), both still stopping at the 6" floor.

    /// A one-model carrier printing `rule` in `<system>/<book>`.
    const DAT09_CARRIER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"SYS","faction_folder":"BOOK",
        "special_rules":["RULE"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn dat09_header(system: &str, book: &str, rule: &str) -> String {
        DAT09_CARRIER
            .replace("\"SYS\"", &format!("\"{system}\""))
            .replace("\"BOOK\"", &format!("\"{book}\""))
            .replace("\"RULE\"", &format!("\"{rule}\""))
    }

    /// The capture read (the melee charge shroud lives there).
    fn dat09_capture(system: &str, book: &str, rule: &str) -> CaptureReads {
        let header = read_act_header(&dat09_header(system, book, rule)).expect("header parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        capture_reads_for_epoch(&mut reg, p, CURRENT_RULES_EPOCH)
    }

    /// The built unit (the ranged shroud lives on its `Ctx`).
    fn dat09_unit(system: &str, book: &str, rule: &str) -> UnitStatic {
        let header = read_act_header(&dat09_header(system, book, rule)).expect("header parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH)
    }

    #[test]
    fn dat09_melee_shrouding_takes_two_inches_off_a_charge_in_both_systems() {
        for (system, book) in [("gf", "battle_brothers"), ("aof", "orcs")] {
            assert_eq!(
                dat09_capture(system, book, "Melee Shrouding").shroud,
                Some([2.0, 6.0]),
                "{system}/{book}: the entry's own 2\" penalty, 6\" floor"
            );
        }
    }

    #[test]
    fn dat09_ranged_shrouding_takes_four_inches_off_shooting_in_both_systems() {
        for (system, book) in [("gf", "custodian_brothers"), ("aof", "havoc_warriors")] {
            let u = dat09_unit(system, book, "Ranged Shrouding");
            assert!(u.ctx.ranged_shrouding, "{system}/{book}: the rule resolves");
            assert_eq!(u.ctx.ranged_shroud_penalty_in, 4.0, "{system}/{book}: the entry's own 4\"");
            assert_eq!(u.ctx.ranged_shroud_floor_in, 6.0, "{system}/{book}: the 6\" floor");
        }
    }

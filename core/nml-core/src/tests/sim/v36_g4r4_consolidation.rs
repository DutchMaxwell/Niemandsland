//! AI-G4 round 4, row G4R4-CONS (rules epoch 73): the Consolidation Moves of a melee. After the fight
//! the TABLE moves a unit — the charger back 1" when neither side was destroyed, the survivor up to 3"
//! when the enemy was — and then rolls the Dangerous terrain test if that move touches Dangerous ground
//! (`SoloController.consolidate_after_melee_win` / `separate_from_melee`, main.gd `_solo_consolidate_melee`).
//! The core had no consolidation at all on its live path (only the dormant `consolidate` knob), so its
//! search never priced the trailing test. The fixtures are real units from the production loaders
//! (`state_from_json`, `UnitStatic::build_for`) fighting a real charge on a board with Dangerous cells;
//! the epoch alone decides the rule, no flag is set by hand.

mod g4r4_cons {
    use super::super::*;
    use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::dice::Roll;
    use crate::io;
    use crate::rules::Registries;
    use crate::state::ProfileCache;
    use serde_json::{json, Value};

    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// One profile: `models` models of Tough `tough`, a Blade with `attacks` attacks. No quality is 6, so a
    /// roll with target 6 is a Dangerous test and nothing else.
    fn profile(id: &str, models: usize, tough: i64, quality: i64, defense: i64, attacks: i64) -> String {
        format!(
            r#""{id}":{{"unit_id":"{id}","name":"{id}","quality":{quality},"defense":{defense},"tough":{tough},
            "wounds_max":{w},"model_count":{models},"caster_value":0,"base_radius":0.0254,
            "game_system":"gf","faction_folder":"robot_legions","special_rules":[],
            "item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
            "weapons":[{{"name":"Blade","range":0,"attacks":{attacks},"count":1,"ap":0,"rules":[]}}]}}"#,
            w = json!(vec![tough; models]),
        )
    }

    fn unit(player: i64, xs: &[f64], tough: i64) -> Value {
        let pos: Vec<[f64; 3]> = xs.iter().map(|x| [x * IN2M, 0.0, 0.0]).collect();
        json!({"player": player, "alive": pos.len(), "wounds": vec![tough; pos.len()],
            "radii": vec![IN2M; pos.len()], "positions": pos, "in_cover": false, "shaken": false,
            "fatigued": false, "activated": false, "casts": 0, "morale_bonus": 0,
            "aircraft": false, "dormant": false, "ambush_arrived_round": -1,
            "earliest_arrival_round": -1, "wound_frac": 0.0, "mods": {}, "mods_base": {},
            "bands": {"advance": 6.0, "rush": 12.0}, "ledger": {},
            "attached": [], "attached_to": ""})
    }

    /// The charger "p1_0_a" (`a_xs` models, Tough `a_t`, `a_attacks` Blade attacks) charges the one-model target
    /// "p2_0_b" (Tough `b_t`, Defense `b_def`) standing at `b_x`; a second enemy "p2_1_c" stands far off on the
    /// x axis - the survivor's consolidation goal when the target is gone.
    fn scene(a_xs: &[f64], a_t: i64, a_attacks: i64, b_x: f64, b_t: i64, b_def: i64) -> (State, Vec<UnitStatic>) {
        let head = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{{},{},{}}}}}"#,
            profile("p1_0_a", a_xs.len(), a_t, 2, 4, a_attacks),
            profile("p2_0_b", 1, b_t, 4, b_def, 1),
            profile("p2_1_c", 1, 1, 4, 4, 1)
        );
        let mut units = serde_json::Map::new();
        units.insert("p1_0_a".into(), unit(1, a_xs, a_t));
        units.insert("p2_0_b".into(), unit(2, &[b_x], b_t));
        units.insert("p2_1_c".into(), unit(2, &[30.0], 1));
        let plain = json!({"round": 1, "rounds_total": 4, "scoring": "end", "units": units});
        let mut cache = ProfileCache::new(read_act_header(&head).expect("header").profiles);
        let mut roster = None;
        let st = io::state_from_json(&plain.to_string(), &mut cache, &mut roster).expect("state");
        let mut reg = Registries::new(&repo_root());
        let statics = st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, EPOCH_73_V36)).collect();
        (st, statics)
    }

    /// The real charge of "p1_0_a" at "p2_0_b" on the Dangerous-bar board (the Dangerous cells lie on the x axis,
    /// from about 3" to 9"), at `epoch`.
    fn charge(st: &State, statics: &[UnitStatic], epoch: u32) -> (State, Vec<Roll>, Vec<String>) {
        let action = Action {
            kind: CHARGE, unit: "p1_0_a".into(), dest: None, shoot: None, charge: Some("p2_0_b".into()),
            patient: false, split: None, traced: None, teleport: None,
        };
        let seams = Seams { movement: true, hero_attach: true, rules_epoch: epoch, ..Seams::default() };
        let (next, shot) = resolve_stochastic_tray_on_board(
            statics, st, &action, &dangerous_bar_board(), seams, &mut GodotRng::new(0), &mut Tray::seeded(7),
        )
        .unwrap();
        (next, shot.rolls, shot.log)
    }

    fn is_dangerous_roll(r: &Roll) -> bool {
        r.kind == "attack" && r.target == DANGEROUS_TARGET
    }

    /// The charger wipes the target (30 Blade attacks on a 1-wound model) and the survivor is the
    /// charger, two Tough 3 models in a tight pair so both stand on whatever ground the pair reaches.
    /// The target stands at x = 2", the charge ends in contact near the origin, the 3" consolidation
    /// toward the far enemy ends at about x = 3" - on the bar.
    fn winner_on_the_bar() -> (State, Vec<UnitStatic>) {
        scene(&[-6.0, -6.02], 3, 30, 2.0, 1, 6)
    }

    /// The same wipe with the target moved so far back that the 3" consolidation ends on clear ground.
    fn winner_on_clear_ground() -> (State, Vec<UnitStatic>) {
        scene(&[-26.0, -26.02], 3, 30, -22.0, 1, 6)
    }

    /// Neither side is destroyed (a one-attack charger against a Tough 20 target): the charger, one model,
    /// stands in contact at x = 10.2" after the charge (the bar ends at 9", a base there is clear) and
    /// backs 1" west to 9.2" - onto the bar's edge.
    fn separation_onto_the_bar() -> (State, Vec<UnitStatic>) {
        scene(&[20.0], 20, 1, 8.2, 20, 2)
    }

    #[test]
    fn the_winner_consolidates_and_rolls_the_dangerous_test_for_the_ground_it_reaches_at_73() {
        let (st, statics) = winner_on_the_bar();
        let (next, rolls, log) = charge(&st, &statics, EPOCH_73_V36);
        assert!(next.alive[1] == 0 && next.alive[0] > 0, "the fixture must wipe the target: {:?}", next.alive);
        let dang: Vec<usize> = (0..rolls.len()).filter(|&i| is_dangerous_roll(&rolls[i])).collect();
        assert_eq!(dang, vec![rolls.len() - 1], "ONE test, and it is the last die of the activation: {rolls:?}");
        assert_eq!(rolls[rolls.len() - 1].owner, "p1_0_a");
        assert_eq!(rolls[rolls.len() - 1].count, 2, "the table's `_run_ai_dangerous(survivor, dang)`: one die per model that crossed");
        assert!(log.iter().any(|l| l.starts_with("Consolidation: p1_0_a consolidates up to 3\"")), "{log:?}");
    }

    #[test]
    fn the_consolidation_that_reaches_clear_ground_rolls_no_test_but_still_logs_the_rule() {
        let (st, statics) = winner_on_clear_ground();
        let (_, rolls, log) = charge(&st, &statics, EPOCH_73_V36);
        assert!(!rolls.iter().any(is_dangerous_roll), "{rolls:?}");
        assert!(log.iter().any(|l| l.starts_with("Consolidation: p1_0_a consolidates up to 3\"")), "{log:?}");
    }

    #[test]
    fn the_charger_backs_off_one_inch_when_neither_side_is_destroyed_at_73() {
        let (st, statics) = separation_onto_the_bar();
        let (at72, _, _) = charge(&st, &statics, EPOCH_72_PLAYTEST_RULES);
        let (at73, _, log) = charge(&st, &statics, EPOCH_73_V36);
        assert!(at73.alive[0] > 0 && at73.alive[1] > 0, "neither side may be destroyed: {:?}", at73.alive);
        let back = at72.positions[0][0][0] - at73.positions[0][0][0];
        assert!((back - IN2M).abs() < 0.05 * IN2M, "1\" away from the target (east of it), got {} in", back / IN2M);
        assert!(log.iter().any(|l| l.starts_with("Consolidation: p1_0_a moves back 1\"")), "{log:?}");
    }

    #[test]
    fn the_back_step_onto_dangerous_ground_rolls_the_test_at_73() {
        let (st, statics) = separation_onto_the_bar();
        let (_, rolls, _) = charge(&st, &statics, EPOCH_73_V36);
        let dang: Vec<usize> = (0..rolls.len()).filter(|&i| is_dangerous_roll(&rolls[i])).collect();
        assert_eq!(dang, vec![rolls.len() - 1], "ONE test, the last die: {rolls:?}");
        assert_eq!((rolls[rolls.len() - 1].count, rolls[rolls.len() - 1].owner.as_str()), (1, "p1_0_a"));
    }

    #[test]
    fn below_73_nobody_consolidates_and_no_trailing_test_rolls() {
        for (st, statics) in [winner_on_the_bar(), separation_onto_the_bar()] {
            let (_, rolls, log) = charge(&st, &statics, EPOCH_72_PLAYTEST_RULES);
            assert!(!rolls.iter().any(is_dangerous_roll), "{rolls:?}");
            assert!(!log.iter().any(|l| l.starts_with("Consolidation")), "{log:?}");
        }
    }
}

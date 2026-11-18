//! P4.D-46: a CHARGE through the step API (`activation::step_activation`) is the whole-activation charge
//! (`resolve_stochastic_tray_on_board`, same `Action`, same faces): the landing via `charge_move`, then the strike phase
//! with every face asked for in draw order. Real units from the production loaders on a clear board, no epoch.

mod charge_step {
    use super::super::*;
    use crate::acts::{read_act_header, CURRENT_RULES_EPOCH};
    use crate::activation::{step_activation, ActStep, Input};
    use crate::dice::Roll;
    use crate::io;
    use crate::rules::Registries;
    use crate::state::ProfileCache;
    use serde_json::{json, Value};

    fn profile(id: &str, models: usize, attacks: i64, rules: &[&str]) -> String {
        let weapons = if attacks > 0 { format!(r#"[{{"name":"Blade","range":0,"attacks":{attacks},"count":1,"ap":0,"rules":[]}}]"#) } else { "[]".into() };
        format!(
            r#""{id}":{{"unit_id":"{id}","name":"{id}","quality":4,"defense":4,"tough":1,"wounds_max":{w},
            "model_count":{models},"caster_value":0,"base_radius":0.0254,"game_system":"gf","faction_folder":"robot_legions",
            "special_rules":{r},"item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},"weapons":{weapons}}}"#,
            w = json!(vec![1; models]),
            r = json!(rules),
        )
    }

    /// `n` models in a line along z (1.2" apart) at x = `x` inches.
    fn unit(player: i64, x: f64, n: usize) -> Value {
        let pos: Vec<[f64; 3]> = (0..n).map(|i| [x * IN2M, 0.0, i as f64 * 1.2 * IN2M]).collect();
        json!({"player": player, "alive": n, "wounds": vec![1; n], "radii": vec![IN2M; n], "positions": pos,
            "in_cover": false, "shaken": false, "fatigued": false, "activated": false, "casts": 0, "morale_bonus": 0,
            "aircraft": false, "dormant": false, "ambush_arrived_round": -1, "earliest_arrival_round": -1,
            "wound_frac": 0.0, "mods": {}, "mods_base": {}, "bands": {"advance": 6.0, "rush": 12.0}, "ledger": {},
            "attached": [], "attached_to": ""})
    }

    /// Charger "p1_0_a" (5 models, `a_attacks` Blade, `a_rules`) 8" west of target "p2_0_b" (5 models, `b_attacks`).
    fn scene(a_attacks: i64, a_rules: &[&str], b_attacks: i64) -> (State, Vec<UnitStatic>) {
        let head = format!(r#"{{"kind":"header","knobs":{{}},"profiles":{{{},{}}}}}"#,
            profile("p1_0_a", 5, a_attacks, a_rules), profile("p2_0_b", 5, b_attacks, &[]));
        let mut units = serde_json::Map::new();
        units.insert("p1_0_a".into(), unit(1, -6.0, 5));
        units.insert("p2_0_b".into(), unit(2, 2.0, 5));
        let plain = json!({"round": 1, "rounds_total": 4, "scoring": "end", "units": units});
        let mut cache = ProfileCache::new(read_act_header(&head).expect("header").profiles);
        let st = io::state_from_json(&plain.to_string(), &mut cache, &mut None).expect("state");
        let mut reg = Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
        let statics = st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH)).collect();
        (st, statics)
    }

    fn clear_board() -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![], sandbox: vec![], walls: vec![], pieces: vec![], containers: Vec::new(),
            cell_params: crate::terrain::CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: IN2M },
        })
    }

    fn seams() -> Seams {
        Seams { movement: true, hero_attach: true, rules_epoch: CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() }
    }

    /// Over 200 seeds: the step answers equal the whole run - state, roll records, log lines (the supplied whole run's
    /// tray lines and its `shot.log` against the seeded run's) and landings. Returns how often the target lost a model,
    /// the charger lost a model (strike back) and the first roll was the Impact pool (5 models x Impact(2)).
    fn equal_over_seeds(st: &State, statics: &[UnitStatic]) -> (usize, usize, usize) {
        let board = clear_board();
        let action = Action { kind: CHARGE, unit: "p1_0_a".into(), dest: None, shoot: None, charge: Some("p2_0_b".into()),
            patient: false, split: None, traced: None, teleport: None };
        let (mut hit, mut struck_back, mut impact) = (0, 0, 0);
        for seed in 0..200i64 {
            let (want, shot) = resolve_stochastic_tray_on_board(statics, st, &action, &board, seams(), &mut GodotRng::new(seed), &mut Tray::seeded(seed)).unwrap();
            let charge = Input::Intent { kind: CHARGE, shoot: None, split: None, charge: Some("p2_0_b".into()) };
            let (mut t, mut dice, mut rolls, mut faces) = (vec![Input::Begin, charge], Tray::seeded(seed), Vec::new(), Vec::new());
            dice.set_zero_draws(true);
            let (state, lines, landings) = loop {
                match step_activation(statics, st, "p1_0_a", &board, seams(), &t, true) {
                    ActStep::NeedRoll { faces: n, kind, count, target, owner, .. } => {
                        let f = dice.roll(n);
                        rolls.push(Roll { kind: if kind == "morale" { "attack" } else { kind }, count, target, faces: f.clone(), owner });
                        faces.push(f.clone());
                        t.push(Input::Faces(f));
                    }
                    ActStep::Done { state, lines, landings, .. } => break (state, lines, landings),
                    other => panic!("seed {seed}: {other:?}"),
                }
            };
            assert_eq!(rolls, shot.rolls, "seed {seed}: roll records");
            assert_eq!(state, want, "seed {seed}: end state");
            let mut whole = Tray::supplied(faces);
            let (again, shot2) = resolve_stochastic_tray_on_board(statics, st, &action, &board, seams(), &mut GodotRng::new(0), &mut whole).unwrap();
            assert_eq!(again, want, "seed {seed}: the supplied whole run");
            assert_eq!(shot2.log, shot.log, "seed {seed}: log");
            assert_eq!(lines, whole.all_lines(), "seed {seed}: log lines");
            assert_eq!(landings, whole.all_landings(), "seed {seed}: landings");
            assert!(state.positions[0] != st.positions[0], "seed {seed}: the charge did not move");
            hit += (want.alive[1] < st.alive[1]) as usize;
            struck_back += (want.alive[0] < st.alive[0]) as usize;
            impact += shot.rolls.first().is_some_and(|r| r.target == crate::combat::IMPACT_HIT_TARGET && r.count == 10) as usize;
        }
        (hit, struck_back, impact)
    }

    /// RED (proved by hand): drop `charge` from the step path's `Action` (no move, no strike), or replace the last face group
    /// of a charge with sixes (the strike leg reads other faces): every case below fails.
    #[test]
    fn a_stepped_charge_on_a_target_without_melee_equals_the_whole_run() {
        let (st, statics) = scene(2, &[], 0);
        let (hit, back, _) = equal_over_seeds(&st, &statics);
        assert!(hit > 0 && back == 0, "{hit} {back}");
    }

    #[test]
    fn a_stepped_charge_with_strike_back_equals_the_whole_run() {
        let (st, statics) = scene(2, &[], 2);
        let (hit, back, _) = equal_over_seeds(&st, &statics);
        assert!(hit > 0 && back > 0, "the fixture must strike back: {hit} {back}");
    }

    #[test]
    fn a_stepped_charge_with_impact_equals_the_whole_run() {
        let (st, statics) = scene(1, &["Impact(2)"], 1);
        let (hit, back, impact) = equal_over_seeds(&st, &statics);
        assert!(hit > 0 && back > 0 && impact > 0, "the fixture must roll Impact: {hit} {back} {impact}");
    }
}

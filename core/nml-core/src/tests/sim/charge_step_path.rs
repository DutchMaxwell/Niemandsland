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
            ..Default::default()
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

    /// P4.D-48: the header's search seams may carry `movement` OFF (the table's step seams come from them); a stepped charge
    /// still moves, snaps and fights exactly as with it ON. RED: drop the CHARGE override in `step_activation` -> a fightless
    /// `Done` with the charger where it stood.
    #[test]
    fn a_stepped_charge_moves_with_the_header_movement_seam_off() {
        let (st, statics) = scene(2, &[], 2);
        let board = clear_board();
        let charge = Input::Intent { kind: CHARGE, shoot: None, split: None, charge: Some("p2_0_b".into()) };
        let off = Seams { movement: false, plain_only: true, ..seams() };
        for seed in 0..16i64 {
            let run = |s: Seams| {
                let (mut t, mut dice) = (vec![Input::Begin, charge.clone()], Tray::seeded(seed));
                dice.set_zero_draws(true);
                loop {
                    match step_activation(&statics, &st, "p1_0_a", &board, s, &t, true) {
                        ActStep::NeedRoll { faces: n, .. } => t.push(Input::Faces(dice.roll(n))),
                        ActStep::Done { state, lines, .. } => break (state, lines),
                        other => panic!("seed {seed}: {other:?}"),
                    }
                }
            };
            let (want, want_lines) = run(seams());
            let (got, got_lines) = run(off);
            assert!(want.positions[0] != st.positions[0], "seed {seed}: the charge did not move");
            assert_eq!(got, want, "seed {seed}: end state with the movement seam off");
            assert_eq!(got_lines, want_lines, "seed {seed}: lines");
        }
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

    /// 5v8 row fixture matching the melee matrix layout (0.016 m bases, 1.3" att / 1.4" def z-pitch, count=10 Blade)
    /// at `gap_in`, with optional attacker bands/rules and defender `shroud: [pen, floor]`.
    fn row_scene(gap_in: f64, faction: &str, att_bands: (f64, f64), att_rules: &[&str], def_shroud: Option<[f64; 2]>) -> (State, Vec<UnitStatic>) {
        let r = crate::sim::DEFAULT_BASE_RADIUS_M;
        let fix = |s: String, bands: (f64, f64)| s
            .replace(r#""count":1"#, r#""count":10"#)
            .replace(r#""base_radius":0.0254"#, r#""base_radius":0.016"#)
            .replace(r#""faction_folder":"robot_legions""#, &format!(r#""faction_folder":"{faction}""#))
            .replace(r#""advance":6.0,"rush":12.0"#, &format!(r#""advance":{},"rush":{}"#, bands.0, bands.1));
        let head = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{{},{}}}}}"#,
            fix(profile("p1_0_a", 5, 2, att_rules), att_bands),
            fix(profile("p2_0_b", 8, 2, &[]), (6.0, 12.0)),
        );
        let mk = |player: i64, x: f64, n: usize, z_step: f64, nudge: bool, bands: (f64, f64), shroud: Option<[f64; 2]>| {
            let pos: Vec<[f64; 3]> = (0..n).map(|i| {
                let nz = if nudge { ((i * 7) % 5) as f64 * 0.0001 } else { 0.0 };
                [(x * IN2M) as f32 as f64, 0.0, (i as f64 * z_step * IN2M + nz) as f32 as f64]
            }).collect();
            let kits: Vec<Value> = vec![json!({"weapons": [], "equipment": 0, "wounds_max": 1}); n];
            let mut u = json!({"player": player, "alive": n, "wounds": vec![1; n], "radii": vec![r; n], "positions": pos,
                "kits": kits, "in_cover": false, "shaken": false, "fatigued": false, "activated": false, "casts": 0,
                "morale_bonus": 0, "aircraft": false, "dormant": false, "ambush_arrived_round": -1,
                "earliest_arrival_round": -1, "wound_frac": 0.0, "mods": {}, "mods_base": {},
                "bands": {"advance": bands.0, "rush": bands.1, "charge": bands.1},
                "ledger": {}, "attached": [], "attached_to": ""});
            if let Some(s) = shroud {
                u.as_object_mut().unwrap().insert("shroud".into(), json!(s));
            }
            u
        };
        let mut units = serde_json::Map::new();
        units.insert("p1_0_a".into(), mk(1, 0.0, 5, 1.3, false, att_bands, None));
        units.insert("p2_0_b".into(), mk(2, gap_in, 8, 1.4, true, (6.0, 12.0), def_shroud));
        let plain = json!({"round": 1, "rounds_total": 4, "scoring": "end", "units": units});
        let mut cache = ProfileCache::new(read_act_header(&head).expect("header").profiles);
        let st = io::state_from_json(&plain.to_string(), &mut cache, &mut None).expect("state");
        let mut reg = Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
        let statics = st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH)).collect();
        (st, statics)
    }

    fn run_stepped_charge(st: &State, statics: &[UnitStatic], board: &crate::terrain::Terrain, s: Seams, seed: i64) -> (State, usize) {
        let charge = Input::Intent { kind: CHARGE, shoot: None, split: None, charge: Some("p2_0_b".into()) };
        let (mut t, mut dice, mut rolls) = (vec![Input::Begin, charge], Tray::seeded(seed), 0usize);
        dice.set_zero_draws(true);
        loop {
            match step_activation(statics, st, "p1_0_a", board, s, &t, true) {
                ActStep::NeedRoll { faces: n, .. } => {
                    rolls += 1;
                    t.push(Input::Faces(dice.roll(n)));
                }
                ActStep::Done { state, .. } => return (state, rolls),
                other => panic!("seed {seed}: {other:?}"),
            }
        }
    }

    /// DS-GMC2 Cause 2 (Slow, GF v3.5.1 p.8/9): an executed step-path CHARGE (`step_activation`) runs `_charge_move`
    /// directly without demoting to `plain_move` (which holds 1" away and skips melee). On Slow at 8.3" (edge gap
    /// 7.04" <= 8.0"), the arc cap creates a tiny overlap that trips `#857`'s replay-only `short` guard; the step
    /// path must still land in contact and fight, while default-seam replay preserves `#857`.
    #[test]
    fn slow_stepped_charge_lands_and_fights_without_plain_move_demotion() {
        let (st, statics) = row_scene(8.3, "robot_legions", (4.0, 8.0), &["Slow"], None);
        let board = clear_board();
        let (end, rolls) = run_stepped_charge(&st, &statics, &board, seams(), 0);
        assert!(rolls > 0, "Slow stepped charge at 7.04\" edge gap must land and fight (got 0 rolls)");
        assert!(end.alive[1] < st.alive[1] || end.alive[0] < st.alive[0] || end.fatigued[0],
            "Slow stepped charge must complete melee");
        // Recorded replay path (`charge_direct: false`) stays byte-identical (#857 fallback preserved).
        let action = Action { kind: CHARGE, unit: "p1_0_a".into(), dest: None, shoot: None, charge: Some("p2_0_b".into()),
            patient: false, split: None, traced: None, teleport: None };
        let (rep_st, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &board, seams(), &mut GodotRng::new(0), &mut Tray::seeded(0)).unwrap();
        assert!(shot.rolls.is_empty(),
            "default replay seam must preserve #857 plain_move fallback (rolls={}, pos0={:?})",
            shot.rolls.len(), rep_st.positions[0]);
    }

    /// DS-GMC2 Cause 3 (`EPOCH_92_MELEE_CAUSES`, Melee Shrouding GF v3.5.3): `resolve_with` applies
    /// `gate::melee_shroud_charge_in` to `band_in` on CHARGE behind `EPOCH_92_MELEE_CAUSES`. At 11.8"
    /// (edge gap 10.54"): shrouded 10" band falls short (0 rolls, ends ~0.54" away), while epoch 91 keeps
    /// the unshrouded 12" band so recorded corpora stay byte-exact.
    #[test]
    fn melee_shrouding_shortens_charge_band_from_epoch_92() {
        let (st, statics) = row_scene(11.8, "battle_brothers", (6.0, 12.0), &[], Some([2.0, 6.0]));
        let board = clear_board();
        let legacy = Seams { rules_epoch: crate::acts::EPOCH_91_JOINED_HERO_FATIGUE, ..seams() };
        let (_, legacy_rolls) = run_stepped_charge(&st, &statics, &board, legacy, 0);
        assert!(legacy_rolls > 0, "epoch 91 must keep unshrouded 12\" band for recorded games");

        let gmc2 = Seams { rules_epoch: crate::acts::EPOCH_92_MELEE_CAUSES, ..seams() };
        let (end, shrouded_rolls) = run_stepped_charge(&st, &statics, &board, gmc2, 0);
        assert_eq!(shrouded_rolls, 0, "Melee Shrouding (-2\" -> 10\" band) must fall short at 10.54\" edge gap");
        let rem_gap = crate::geom::edge_gap_in(&end.positions[0], &end.radii[0], &end.positions[1], &end.radii[1], crate::menu::DEFAULT_BASE_RADIUS_M);
        assert!(rem_gap < 0.8, "charge shortfall must move as close as possible (~0.54\"), not 1\" plain_move buffer (got {rem_gap:.2}\")");
    }

    /// End-to-end verification of all 4 DS-GMC2 "charge reach" matrix cells against the exact Godot table endpoints
    /// captured from `melee_matrix_cli.gd` (Melee Shrouding TU gap=10.8 seed 0, Versatile Reach CU gap=14.0 seed 8,
    /// Fast CU gap=15.0 seed 0, Slow CU gap=8.3 seed 0) at `EPOCH_92_MELEE_CAUSES`.
    #[test]
    fn gmc2_all_four_charge_reach_cells_match_table_endpoints() {
        let board = clear_board();
        let gmc2 = Seams {
            rules_epoch: crate::acts::EPOCH_92_MELEE_CAUSES,
            bands_prefolded: true,
            charge_landing: true,
            melee_reach: true,
            consolidate: true,
            cond_ap_dice: true,
            versatile_reach: true,
            range_by_base_edge: true,
            fire_in_range_only: true,
            casualties_bearers_last: true,
            hero_counts_in_size: true,
            reply_threat_by_speed: true,
            fearless_roll_when_shaken: true,
            ..seams()
        };
        let sort_in = |pos: &[[f64; 3]]| -> Vec<(f64, f64)> {
            let mut v: Vec<(f64, f64)> = pos.iter().map(|p| (p[0] / IN2M, p[2] / IN2M)).collect();
            v.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.total_cmp(&b.1)));
            v
        };
        let mut errs = Vec::new();
        let mut check_near = |label: &str, got: &[(f64, f64)], want: &[(f64, f64)]| {
            if got.len() != want.len() {
                errs.push(format!("{label}: model count got={} want={} got={got:?}", got.len(), want.len()));
                return;
            }
            for (i, (g, w)) in got.iter().zip(want).enumerate() {
                let d = (g.0 - w.0).hypot(g.1 - w.1);
                if d >= 0.002 {
                    errs.push(format!("{label}[{i}]: got ({:.6}, {:.6}) want ({:.6}, {:.6}) diff={d:.6}\"\n  all got={got:?}", g.0, g.1, w.0, w.1));
                    break;
                }
            }
        };
        // 1. Melee Shrouding TU (gap=10.8, seed 0)
        let (st, statics) = row_scene(10.8, "battle_brothers", (6.0, 12.0), &[], Some([2.0, 6.0]));
        let (end, rolls) = run_stepped_charge(&st, &statics, &board, gmc2, 0);
        assert!(rolls > 0, "Melee Shrouding at 10.8\" must fight");
        check_near("Melee Shrouding att", &sort_in(&end.positions[0]), &[
            (8.379976, 4.654086), (8.542289, 3.404803), (8.909125, 0.175144), (8.928949, 2.205761),
        ]);
        // 2. Versatile Reach CU (gap=14.0, seed 8)
        let (st, statics) = row_scene(14.0, "battle_brothers", (6.0, 12.0), &["Versatile Reach"], None);
        let (end, rolls) = run_stepped_charge(&st, &statics, &board, gmc2, 8);
        assert!(rolls > 0, "Versatile Reach at 14.0\" must fight");
        check_near("Versatile Reach foe", &sort_in(&end.positions[1]), &[
            (13.91287, 6.911833), (14.0, 2.815748), (14.0, 4.203937), (14.0, 5.611812),
        ]);
        // 3. Fast CU (gap=15.0, seed 0)
        let (st, statics) = row_scene(15.0, "robot_legions", (8.0, 16.0), &["Fast"], None);
        let (end, rolls) = run_stepped_charge(&st, &statics, &board, gmc2, 0);
        assert!(rolls > 0, "Fast at 15.0\" must fight");
        check_near("Fast att", &sort_in(&end.positions[0]), &[
            (13.07591, 3.812896), (13.14391, 5.271881), (13.25865, 0.935929), (13.49451, 2.518461),
        ]);
        // 4. Slow CU (gap=8.3, seed 0)
        let (st, statics) = row_scene(8.3, "robot_legions", (4.0, 8.0), &["Slow"], None);
        let (end, rolls) = run_stepped_charge(&st, &statics, &board, gmc2, 0);
        assert!(rolls > 0, "Slow at 8.3\" must fight");
        check_near("Slow att", &sort_in(&end.positions[0]), &[
            (6.045187, 0.655914), (6.220162, 3.407425), (6.291533, 5.291536), (6.602158, 2.20521),
        ]);
        assert!(errs.is_empty(), "{}", errs.join("\n"));
    }
}

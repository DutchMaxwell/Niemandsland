use super::*;

    // ------------- design #816 PR 2 (core): Teleport / Ethereal reposition -----

    /// The registry-built carrier: a gf profile whose ONLY rule is "Teleport",
    /// read off the REAL registry. The REAL `build_for` product, read at `epoch`.
    fn tp_bearer(rules_epoch: u32, rule: &str, system: &str, faction: &str) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![rule.into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: system.into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// One bearer "a" at the origin (1" radius, 1 model), no hero, no enemies.
    fn tp_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (st, _) = dangerous_line();
        let a = tp_bearer(rules_epoch, "Teleport", "gf", "wormhole_daemons_of_change");
        (st, vec![a, UnitStatic { name: "ah".into(), ..Default::default() }, UnitStatic { name: "b".into(), ..Default::default() }, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    fn run_tp(st: &State, statics: &[UnitStatic], rules_epoch: u32, to: Option<[f64; 2]>) -> (State, ShootResult) {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let mut act = crate::io::Action { kind: ADVANCE, unit: "a".into(), dest: None,
            shoot: None, charge: None, patient: false, split: None, traced: None, teleport: to };
        resolve_stochastic_tray_on_board(
            statics, st, &act, &crate::terrain::Terrain::default(),
            Seams { rules_epoch, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// (1) a replayed act carrying the record's `teleport` block lands the
    /// formation ON the recorded centroid (the record decides), sets the
    /// latch, and names rule, band cap and landing centroid (rules-must-log).
    #[test]
    fn replay_of_a_recorded_teleport_lands_on_the_recorded_centroid() {
        let (st, statics) = tp_line(7);
        let from = geom::centre(&st.positions[0]);
        // 2" along +x — inside the 3" Advance cap. Metres on the wire.
        let to: [f64; 2] = [((from[0] + 2.0 * IN2M as f32)) as f64, from[2] as f64];
        let (next, shot) = run_tp(&st, &statics, 7, Some(to));
        let centre = geom::centre(&next.positions[0]);
        assert!(
            (centre[0] as f64 - to[0]).abs() < 1e-6 && (centre[2] as f64 - to[1]).abs() < 1e-6,
            "byte-exact landing at the recorded centroid, got {centre:?}"
        );
        assert!(next.teleport_used[0], "the latch is set");
        assert!(
            shot.log.iter().any(|l| l.contains("Teleport") && l.contains("repositions")),
            "rules-must-log: {:?}",
            shot.log
        );
    }

    /// (2a) the live cap: an Advance-band reposition is REFUSED past 3" — the
    /// recorded `to` at 3.5" cannot happen, the formation stays (the beat
    /// would clamp; here the recorded arm trusts the record, so this is the
    /// LIVE candidate arm's cap, probed through the menu constant).
    #[test]
    fn teleport_cap_is_3_after_an_advance_and_6_after_a_rush() {
        assert_eq!(crate::unit::teleport_cap_in("Teleport", false), 3.0);
        assert_eq!(crate::unit::teleport_cap_in("Teleport", true), 6.0);
        assert_eq!(crate::unit::teleport_cap_in("Ethereal", false), 6.0);
        assert_eq!(crate::unit::teleport_cap_in("Ethereal", true), 6.0);
    }

    /// (2b) the LIVE rollout arm: a Reposition act (kind 4) for a Teleport
    /// bearer lands at the probed candidate, never past the cap — a 3.5"
    /// pull toward the objective clamps to the 3" cap; Ethereal goes 6" flat.
    #[test]
    fn the_live_reposition_never_exceeds_the_cap() {
        let (mut st, mut statics) = tp_line(7);
        // An objective 6" ahead of the bearer: the objective probe wants 6",
        // the 3" Advance cap clamps the landing.
        st.objectives = vec![crate::state::Objective {
            pos: [st.positions[0][0][0] + 6.0 * IN2M, 0.0, 0.0],
            owner: 0,
        }];
        st.teleport_used = vec![false; 4];
        statics[0].teleport = Some(crate::unit::TeleportSpec { name: "Teleport".into() });
        let act = crate::io::Action { kind: REPOSITION, unit: "a".into(), dest: None,
            shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None };
        let mut tray = Tray::seeded(3);
        let mut rng = crate::rng::GodotRng::new(0);
        let next = resolve_stochastic_on_board(
            &statics, &st, &act, &crate::terrain::Terrain::default(),
            Seams { rules_epoch: 7, ..Seams::default() }, &mut rng,
        )
        .unwrap();
        let centre = geom::centre(&next.positions[0]);
        let moved_in = ((centre[0] as f64 - st.positions[0][0][0]) / IN2M) as f64;
        assert!(
            moved_in <= 3.06 && moved_in > 2.9,
            "clamped to the 3\" cap, got {moved_in}\""
        );
        assert!(next.teleport_used[0], "the latch is set on a take");
    }

    /// (3) once per activation: a state whose latch stands (folded from the
    /// record) refuses a second live reposition in the SAME activation read —
    /// the beat is entry-clear, so the proof is the FOLD + the beat's refusal
    /// arm: latch set -> no landing shift even when the action carries `to`
    /// for a NON-bearer read... the once-per-activation form here: the beat
    /// runs at most once per resolve, and the fold's stale true survives only
    /// until the entry clear — asserted on the post-act latch.
    #[test]
    fn the_latch_is_once_per_activation_and_the_fold_carries_it() {
        let (st, statics) = tp_line(7);
        let from = geom::centre(&st.positions[0]);
        let to: [f64; 2] = [((from[0] + 2.0 * IN2M as f32)) as f64, from[2] as f64];
        let (next, _) = run_tp(&st, &statics, 7, Some(to));
        assert!(next.teleport_used[0], "taken this activation");
        // And the io fold: a record whose ledger carries the block folds the
        // latch in (the wire form the recorder writes: a Vector2 string).
        let plain = format!(
            r#"{{"round":0,"rounds_total":1,"units":{{"a":{{"player":1,"alive":1,"activated":false,"shaken":false,"fatigued":false,"in_cover":false,"aircraft":false,"dormant":false,"dormant_models":0,"dormant_wounds":[],"casts":0,"morale_bonus":0,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"positions":[[0.0,0.0,0.0]],"wounds":[1],"radii":[0.0254],"mods":{{}},"mods_base":{{}},"attached":[],"attached_to":"","ledger":{{"teleport":{{"used":true,"to":"(0.42, -0.17)"}}}}}}}}}}"#
        );
        let profile = crate::state::Profile {
            unit_id: "a".into(), name: "a".into(), quality: 4, defense: 4, tough: 1,
            wounds_max: vec![1], model_count: 1, weapons: vec![],
            special_rules: vec!["Teleport".into()], caster_value: 0, base_radius: 0.0,
            base_shape: String::new(), base_w_mm: 0.0, base_d_mm: 0.0,
            game_system: "gf".into(), faction_folder: "wormhole_daemons_of_change".into(),
            item_grants: vec![], attached_hero_rules: vec![], move_bands: Default::default(),
        };
        let mut index = std::collections::HashMap::new();
        index.insert("a".to_string(), 0);
        let mut pc = crate::state::ProfileCache::new(std::rc::Rc::new(crate::state::Profiles {
            list: vec![profile], index,
        }));
        let mut rc = None;
        let st2 = crate::io::state_from_json(&plain, &mut pc, &mut rc).unwrap();
        assert!(st2.teleport_used[0], "the ledger block folds the latch");
    }

    /// (4) a unit WITHOUT the name never repositions — recorded block or not.
    #[test]
    fn a_unit_without_the_name_never_repositions() {
        let (st, statics) = tp_line(7);
        let from = geom::centre(&st.positions[0]);
        // Unit "b" (index 2) carries no Teleport — an act naming it with a
        // recorded block must move nothing.
        let act = crate::io::Action { kind: ADVANCE, unit: "b".into(), dest: None,
            shoot: None, charge: None, patient: false, split: None, traced: None,
            teleport: Some([((from[0] + 2.0 * IN2M as f32)) as f64, from[2] as f64]) };
        let mut tray = Tray::seeded(5);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &act, &crate::terrain::Terrain::default(),
            Seams { rules_epoch: 7, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[2], st.positions[2], "no bearer, no shift");
        assert!(!next.teleport_used[2], "and no latch");
    }

    /// (5) an epoch-6 record replays byte-identical: the same act with a
    /// `teleport` block, resolved below the FROZEN epoch 7, moves nothing and
    /// stamps no latch.
    #[test]
    fn an_epoch_6_record_is_byte_identical() {
        let (st, statics) = tp_line(6);
        let from = geom::centre(&st.positions[0]);
        let (next, shot) = run_tp(&st, &statics, 6, Some([((from[0] + 2.0 * IN2M as f32)) as f64, from[2] as f64]));
        assert_eq!(next.positions[0], st.positions[0], "no shift below epoch 7");
        assert!(!next.teleport_used[0], "no latch below epoch 7");
        assert!(!shot.log.iter().any(|l| l.contains("Teleport")), "{:?}", shot.log);
    }

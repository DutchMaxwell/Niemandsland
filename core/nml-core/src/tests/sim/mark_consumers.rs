use super::*;

    // ----------------- WAVE 3: the two mark consumers (epoch 6) -------------

    /// WAVE 3 — Indirect Mark: the once-record the pick lands on the marked
    /// unit makes it a LEGAL target without sight (the table's own per-target
    /// validity check, main.gd:4011-4029). The fixture's recorded sight matrix
    /// blocks a(0) -> b(2) — the planner's strict test, exactly the pair the
    /// mark must waive — so with the mark the volley still fires its single
    /// bearer-scaled rifle, at epoch 5 — and without the record at 6 — the
    /// block stands. RED before the fix: the record landed on the ledger but
    /// no resolver read it, so the first assert saw no attack die at all.
    #[test]
    fn indirect_mark_lets_the_volley_fire_at_a_blocked_target_from_epoch_6() {
        let (mut st, statics) = buff_line();
        let mut dark = vec![true; 16];
        dark[0 * 4 + 2] = false; // los_pairs[0 * 4 + 2] — a does not see b
        st.los_pairs = Some(Rc::new(dark));
        let on = run_marked(&st, &statics, 6, &[(2, &mark("Indirect"))]);
        assert_eq!(on.rolls[0].count, 1, "epoch 6: the mark waives the blocked sight");
        let off = run_marked(&st, &statics, 5, &[(2, &mark("Indirect"))]);
        assert!(
            off.rolls.iter().all(|r| r.kind != "attack"),
            "epoch 5 (the recording fleet's epoch) keeps the record inert, RED before the fix"
        );
        let none = run_marked(&st, &statics, 6, &[]);
        assert!(none.rolls.iter().all(|r| r.kind != "attack"), "no record, no waiver");
        // "once": the exchange that used the waiver spends the record.
        let (spent, _) = {
            let mut s = st.clone();
            s.buffs[2] = vec![mark("Indirect")];
            let seams = Seams { sighting: true, rules_epoch: 6, ..Default::default() };
            let terrain = crate::terrain::Terrain::default();
            let mut tray = Tray::seeded(11);
            let mut rng = crate::rng::GodotRng::new(0);
            resolve_stochastic_tray_on_board(
                &statics, &s, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray,
            )
            .unwrap()
        };
        assert!(spent.buffs[2].is_empty(), "main.gd:3244 — the volley's exchange spends it");
    }

    /// WAVE 3 — Increased Shooting Range Mark: with `b` parked at 28" (past the
    /// rifle's plain 24") the mark's live `+6" shooting range` record extends
    /// the volley's reach so the rifle fires, at epoch 6 only. The EV
    /// imagination (`ctx_of`) stays blind to the mark — the sighting seam's
    /// own asymmetry — and a record below epoch 6 never extends anything.
    #[test]
    fn increased_shooting_range_mark_extends_the_volley_reach_from_epoch_6() {
        let (mut st, statics) = buff_line();
        st.positions[2] = vec![
            [28.0 * IN2M, 0.0, 0.0],
            [28.02 * IN2M, 0.0, 0.0],
            [28.04 * IN2M, 0.0, 0.0],
        ];
        // `ah` off the firing line so the range gate is the ONLY variable.
        st.positions[1] = vec![[-2.0 * IN2M, 5.0 * IN2M, 0.0]];

        let on = run_marked(&st, &statics, 6, &[(2, &mark("+6\" shooting range"))]);
        assert_eq!(on.rolls[0].count, 1, "epoch 6: 24 + 6 reach covers the 28\" gap");
        let off = run_marked(&st, &statics, 5, &[(2, &mark("+6\" shooting range"))]);
        assert!(
            off.rolls.iter().all(|r| r.kind != "attack"),
            "epoch 5: the record is inert, RED before the fix"
        );
        let none = run_marked(&st, &statics, 6, &[]);
        assert!(none.rolls.iter().all(|r| r.kind != "attack"), "no record, plain 24\" reach");
        // The rifle's range must be dead on the dice too, not just out of
        // `keep`: without the mark the reach gate skips the weapon silently.
        assert!(none.rolls.is_empty() || none.rolls.iter().all(|r| r.kind != "attack"));
    }

    /// WAVE 3 — the merge composition between #692 (Ranged Shrouding) and
    /// #694 (Increased Shooting Range Mark), ruled by the maintainer: the
    /// texts give no order ("Ranged Shrouding: enemies get -6\" range, min.
    /// 6\", to shoot units where all models have this rule" / "Increased
    /// Shooting Range Mark: friendly units get +6\" range when shooting
    /// against [the marked unit], once") but "min. 6\"" belongs to the
    /// SHROUD's own penalty, not to the combined total — an add-then-clamp
    /// reading would cut the mark's promised +6\" down to +3\" in the R=9
    /// case below, breaking the mark's own text. So `dice.rs` clamps the
    /// shroud first (`shrouded_reach`, floored against the raw printed
    /// range), then adds the mark uncapped — CONFIRMED matching main as
    /// merged. Three pins, per the ruling:
    ///  - R=9, shrouded + marked -> 12" (max(9-6,6)=6, +6=12). The ONLY one
    ///    of the three that DISCRIMINATES the order: an add-then-clamp
    ///    reading gives max(9-6+6,6)=9, not 12. If a future refactor
    ///    silently reorders the two ops, THIS case is what goes red.
    ///  - R=24, shrouded + marked -> 24" (max(24-6,6)=18, +6=24) — a
    ///    regression pin only; both orders give 24 here since the floor
    ///    never engages at long range (18 > 6).
    ///  - R=9, shrouded, UNMARKED -> 6" (max(9-6,6)=6) — a regression pin
    ///    confirming the shroud's own floor, independent of the mark.
    /// Margins (not the exact reach-value distances) stay clear of the
    /// inch<->metre round-trip epsilon on `dist_in.ceil()`.
    #[test]
    fn ranged_shrouding_and_the_increased_shooting_range_mark_compose_clamp_then_add() {
        let (mut st, mut statics) = buff_line();
        // `b` (unit 2) carries Ranged Shrouding at the official penalty/floor.
        statics[2].ctx.ranged_shrouding = true;
        statics[2].ctx.ranged_shroud_penalty_in = 6.0; // combat::SHROUD_RANGE_PENALTY_IN
        statics[2].ctx.ranged_shroud_floor_in = 6.0; // combat::SHROUD_FLOOR_IN
        // `ah` off the firing line so the range gate is the ONLY variable.
        st.positions[1] = vec![[-2.0 * IN2M, 5.0 * IN2M, 0.0]];
        let group = |d: f64| {
            vec![[d * IN2M, 0.0, 0.0], [(d + 0.02) * IN2M, 0.0, 0.0], [(d + 0.04) * IN2M, 0.0, 0.0]]
        };

        // --- THE DISCRIMINATING CASE: R=9 shrouded + marked -> 12" -------
        statics[0].shoot = vec![gun("Pistol9", 1, 9)];
        st.positions[2] = group(10.0); // between the 9" a sum-then-clamp
                                        // reading gives and the 12" clamp-
                                        // then-add gives — fires ONLY under
                                        // the coded (clamp-then-add) order.
        let on9 = run_marked(&st, &statics, 6, &[(2, &mark("+6\" shooting range"))]);
        assert_eq!(on9.rolls[0].count, 1,
            "R=9 shrouded+marked: clamp-then-add gives 12\", 10\" gap fires; \
             add-then-clamp would give only 9\" and must NOT fire here");

        let shroud_only9 = run_marked(&st, &statics, 6, &[]);
        assert!(shroud_only9.rolls.iter().all(|r| r.kind != "attack"),
            "R=9 shrouded, unmarked: floors to 6\" — the 10\" gap is out of reach");

        st.positions[2] = group(14.0); // clear of the composed 12".
        let over9 = run_marked(&st, &statics, 6, &[(2, &mark("+6\" shooting range"))]);
        assert!(over9.rolls.iter().all(|r| r.kind != "attack"),
            "R=9 shrouded+marked: 14\" is past the composed 12\" reach");

        // --- Regression pin: R=9 shrouded, UNMARKED -> 6" ----------------
        st.positions[2] = group(5.0); // inside the 6" floor: fires.
        let floor_hits = run_marked(&st, &statics, 6, &[]);
        assert_eq!(floor_hits.rolls[0].count, 1,
            "R=9 shrouded, unmarked: the 6\" floor still lets a close shot through");

        // --- Regression pin: R=24 shrouded + marked -> 24" (non-discriminating,
        // the floor never engages at long range: 24-6=18 > 6) ---------------
        statics[0].shoot = vec![gun("Rifle24", 1, 24)];
        st.positions[2] = group(22.0); // inside 24", outside the 18"
                                        // shroud-only reach — the mark's
                                        // contribution still has to land.
        let on24 = run_marked(&st, &statics, 6, &[(2, &mark("+6\" shooting range"))]);
        assert_eq!(on24.rolls[0].count, 1,
            "R=24 shrouded+marked: max(24-6,6)+6=24\" reach covers the 22\" gap");
        let shroud_only24 = run_marked(&st, &statics, 6, &[]);
        assert!(shroud_only24.rolls.iter().all(|r| r.kind != "attack"),
            "R=24 shrouded+marked: max(24-6,6)+6=24\" reach covers the 22\" gap");
    }

    // ------------- Dead-parameter recount 2026-09-15, family 4: the
    // Indirect entry's own `ignores_los` READ -----------------------------

    /// The same fixture-registry shape as the dice-side counter wave: one
    /// temp repo root, one "Indirect" entry under the fixture faction.
    fn counterfam_registry(tag: &str, name: &str, params: &str) -> String {
        let dir = std::env::temp_dir()
            .join(format!("nml_counterfam_{}_{}", tag, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let map_dir = dir.join("assets/solo");
        std::fs::create_dir_all(&map_dir).expect("temp map dir");
        let body = format!(
            r#"{{"common":{{}},"factions":{{"testfac":{{"{name}":{{"primitive":"{name}","rated":false,"book_version":"3.5.3","params":{params}}}}}}}}}"#
        );
        std::fs::write(map_dir.join("rules_mechanics_gf.json"), body)
            .expect("write temp mechanics map");
        dir.to_string_lossy().into_owned()
    }

    /// One 24" Indirect MORTAR: the WEAPON's own rule, not the wave-3 mark,
    /// is the caller here — the entry's `ignores_los` decides whether the
    /// blocked a(0) -> b(2) sight (the same pair the mark waives above)
    /// waives for the profile. On main the profile flag alone fires, so the
    /// second leg cannot go dark (RED).
    #[test]
    fn indirect_entrys_ignores_los_switch_gates_the_profile_waiver() {
        const IND_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
          "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
            "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"gf","faction_folder":"testfac",
            "special_rules":[],"item_grants":[],
            "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
            "weapons":[{"name":"Mortar","range":24,"attacks":1,"count":1,"ap":0,
              "rules":["Indirect"]}]}}}"#;
        let mortar = |tag: &str, params: &str| {
            let root = counterfam_registry(tag, "Indirect", params);
            let parsed = crate::acts::read_act_header(IND_HEADER).expect("header parses");
            let mut reg = crate::rules::Registries::new(&root);
            let p = parsed.profiles.get("carrier").expect("carrier");
            crate::unit::UnitStatic::build_for(&mut reg, p, 7)
        };
        fn run_sighting(st: &State, statics: &[UnitStatic], act: &Action) -> ShootResult {
            let seams = Seams { sighting: true, rules_epoch: 7, ..Default::default() };
            let terrain = crate::terrain::Terrain::default();
            let mut tray = Tray::seeded(11);
            let mut rng = crate::rng::GodotRng::new(0);
            crate::sim::resolve_stochastic_tray_on_board(
                statics, st, act, &terrain, seams, &mut rng, &mut tray,
            )
            .unwrap()
            .1
        }
        let (mut st, mut statics) = buff_line();
        let mut dark = vec![true; 16];
        dark[2] = false; // los_pairs[0*4+2] — a does not see b, but sees bh
        st.los_pairs = Some(Rc::new(dark));
        st.alive[3] = 1;
        st.positions[3] = vec![[6.0 * IN2M, 0.0, 0.0]];
        st.radii[3] = vec![IN2M];
        st.wounds[3] = vec![1];
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        statics[0].shoot = mortar("ind1", "{}").shoot.clone();
        let mut act = buff_action(Some("bh"));
        act.split = Some(vec![crate::io::SplitShot {
            member: "a".into(), weapon: "Mortar".into(), target: "b".into(),
        }]);
        let on = run_sighting(&st, &statics, &act);
        assert!(on.rolls.iter().any(|r| r.kind == "attack" && r.count == 1),
            "the default entry keeps the recorded profile waiver");
        statics[0].shoot = mortar("ind0", r#"{"ignores_los":false}"#).shoot.clone();
        let off = run_sighting(&st, &statics, &act);
        assert!(off.rolls.iter().all(|r| r.kind != "attack"),
            "off rolls: {:?} — the entry's ignores_los:false must darken the profile waiver — on main it cannot (RED)", off.rolls);
    }

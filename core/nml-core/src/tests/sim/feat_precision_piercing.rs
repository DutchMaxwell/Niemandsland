use super::*;

    // ------------------- wave 5 group (b): Precision + Piercing Feat -----

    // FEAT PR 3 (docs/plans/FEAT_DESIGN_2026-09-08.md §3-4, PRs 3+4 folded
    // by coordinator ruling). The two aof once-per-game latch feats ride the
    // #827 `feats_used` ledger: Precision Feat (primitive Shot Modifier,
    // hit_bonus 1 / all_attacks true — ghostly_undead + ossified_undead)
    // gives EVERY shooting attack of the activation +1 to hit; Piercing Feat
    // (primitive Piercing Assault, ap_bonus 1 / condition any_attack —
    // ogres) gives every attack AP(+1). Four tests, one per brief line: the
    // first shooting activation hits at +1 on every attack and the second at
    // base (a), AP(+1) once then base (b), below epoch 7 nothing fires and
    // the replay stays byte-identical (c), and the latch is one key per feat
    // name — spending Precision never spends Speed Feat (d).

    /// The bearer: an aof profile whose ONLY rule is the named feat, read off
    /// the REAL registry (`assets/solo/rules_mechanics_aof.json`). The REAL
    /// `build_for` product. `weapons` gives the ranged tests a die of their
    /// own; the melee test overwrites `melee` directly (the Reckless Piercing
    /// precedent).
    fn fp_bearer(rules_epoch: u32, faction: &str, rules: &[&str]) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![crate::state::Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 3,
                count: 1,
                ap: 0,
                rules: vec![],
            }],
            special_rules: rules.iter().map(|r| r.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    fn fp_dummy(name: &str) -> UnitStatic {
        UnitStatic { name: name.into(), ..Default::default() }
    }

    /// Bearer "a" vs a 3-model Defense-4 target "b" at 5", sighted on the
    /// plain rows — `ts_line`'s shape, the rifle draws ALL the volley's dice.
    fn fp_line(rules_epoch: u32, faction: &str, rules: &[&str]) -> (State, Vec<UnitStatic>) {
        let (st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        let bearer = fp_bearer(rules_epoch, faction, rules);
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        (st, vec![bearer, fp_dummy("ah"), b, fp_dummy("bh")])
    }

    /// One HOLD+shoot activation on the tray path.
    fn run_shoot(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> (State, ShootResult) {
        let action = Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: Some("b".into()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
            teleport: None,
        };
        let terrain = Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    fn attack_targets(shot: &ShootResult) -> Vec<i64> {
        shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.target).collect()
    }

    /// (a) — Precision Feat: the FIRST shooting activation hits at +1 on
    /// every attack (Quality 4 → 3+), the latch gains the DISPLAY name and
    /// the rules-must-log line names the spend; the SECOND activation hits
    /// at base (4+) and never re-spends. RED before the read: the rifle
    /// rolls at 4+ both times and the latch stays empty.
    #[test]
    fn precision_first_shooting_activation_plus_one_then_base() {
        let (st, statics) = fp_line(7, "ghostly_undead", &["Precision Feat"]);
        let (next, shot) = run_shoot(&st, &statics, 7);
        let t = attack_targets(&shot);
        assert!(!t.is_empty(), "the rifle fires: {:?}", shot.rolls);
        assert!(t.iter().all(|&x| x == 3), "every attack at 3+ (+1 on 4+): {:?}", t);
        assert_eq!(
            next.feats_used[0],
            vec!["Precision Feat".to_string()],
            "the ledger shows the name (the recorder's key)"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("[feat] Precision Feat spent by a")),
            "rules-must-log: {:?}",
            shot.log
        );
        // Second activation: base to-hit, the latch holds, no re-log.
        let (next2, shot2) = run_shoot(&next, &statics, 7);
        let t2 = attack_targets(&shot2);
        assert!(t2.iter().all(|&x| x == 4), "base 4+ after the spend: {:?}", t2);
        assert_eq!(next2.feats_used[0], vec!["Precision Feat".to_string()]);
        assert!(!shot2.log.iter().any(|l| l.contains("[feat]")), "no re-spend: {:?}", shot2.log);
    }

    /// (b) — Piercing Feat: AP(+1) once (Defense 4 saves at 5+), then base
    /// (4+). The feat's condition is `any_attack`, so the MELEE fold spends
    /// it exactly like a volley would. RED before the read: saves at 4+ and
    /// the latch stays empty.
    #[test]
    fn piercing_ap_plus_one_once_then_base() {
        let seams = Seams { rules_epoch: 7, ..Seams::default() };
        let strike = |st: &mut State, statics: &[UnitStatic]| {
            let mut tray = Tray::seeded(11);
            let mut shot = ShootResult::default();
            strike_phase(statics, st, 0, 2, true, seams, &mut tray, &mut shot);
            shot
        };
        let (mut st, mut statics) = fp_line(7, "ogres", &["Piercing Feat"]);
        statics[0].melee = vec![gun("Blade", 64, 0)];
        st.alive[2] = 1;
        st.wounds[2] = vec![1];
        st.positions[2] = vec![[1.2 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        let shot = strike(&mut st, &statics);
        assert!(
            shot.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "AP(+1): the saves run at 5+ -- got {:#?}",
            shot.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
        assert!(
            shot.log.iter().any(|l| l.contains("[feat] Piercing Feat spent by a")),
            "rules-must-log: {:?}",
            shot.log
        );
        // Second activation: the spend holds in the state's latch — base AP.
        assert_eq!(st.feats_used[0], vec!["Piercing Feat".to_string()]);
        let shot2 = strike(&mut st, &statics);
        assert!(
            shot2.rolls.iter().any(|r| r.kind == "defense" && r.target == 4)
                && !shot2.rolls.iter().any(|r| r.kind == "defense" && r.target == 5),
            "base AP after the spend -- got {:#?}",
            shot2.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
        assert_eq!(st.feats_used[0], vec!["Piercing Feat".to_string()], "no re-spend");
    }

    /// (c) — below epoch 7 nothing exists: a pre-folded latch key rides
    /// INERTLY (no bonus, no spend, no log) and two epoch-6 runs — folded
    /// and clean — draw byte-identical dice. RED under a mutation that drops
    /// the frozen gate.
    #[test]
    fn below_epoch_seven_nothing_fires_and_the_replay_is_byte_identical() {
        let (mut stf, statics) = fp_line(6, "ghostly_undead", &["Precision Feat"]);
        let (stc, _) = fp_line(6, "ghostly_undead", &["Precision Feat"]);
        stf.feats_used[0].push("Precision Feat".to_string());
        let (next, shot) = run_shoot(&stf, &statics, 6);
        assert!(
            attack_targets(&shot).iter().all(|&x| x == 4),
            "epoch 6: base to-hit: {:?}",
            attack_targets(&shot)
        );
        assert!(next.feats_used[0].len() == 1, "the key rides along, nothing re-spends");
        assert!(!shot.log.iter().any(|l| l.contains("[feat]")), "epoch 6: nothing logs");
        let (_, shot_clean) = run_shoot(&stc, &statics, 6);
        assert_eq!(shot.rolls, shot_clean.rolls, "byte-identical below the gate");
    }

    /// (d) — the latch is one key per feat NAME: spending Precision leaves
    /// Speed Feat's key untouched, so the move seam's read still grants. The
    /// Speed Feat spec is stamped by hand (aof's own Speed Feat entry lives
    /// in the orcs faction — no single bearer carries both books' names).
    #[test]
    fn the_latch_is_one_key_per_feat_name() {
        let (st, mut statics) = fp_line(7, "ghostly_undead", &["Precision Feat"]);
        statics[0].speed_feat =
            Some(crate::unit::SpeedFeatSpec { name: "Speed Feat".into(), advance_mod: 2.0, rush_mod: 4.0 });
        let (next, _) = run_shoot(&st, &statics, 7);
        assert_eq!(
            next.feats_used[0],
            vec!["Precision Feat".to_string()],
            "exactly its own key: {:?}",
            next.feats_used[0]
        );
        assert!(
            speed_feat_band_in(&statics, &next, 0, ADVANCE, 7) > 0.0,
            "Speed Feat's read stays open: {:?}",
            next.feats_used[0]
        );
    }

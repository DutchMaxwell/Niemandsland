use super::*;

    // ------------- block B7b: the epoch-6 Growth Markers wave -------------

    /// Growth Markers wave (epoch 6) — `growth_defense_of`, the DEFENDER-side
    /// sister of `growth_bonus_of`: the two Defensive names' +X-to-Defense
    /// ladder and Fortified Growth's attacker-AP cut, zero for a non-bearer.
    #[test]
    fn growth_defense_of_sums_the_defense_and_fortify_ladders() {
        let mut st = four_unit_line();
        let mut statics = vec![UnitStatic::default()];
        statics[0].growth = vec![
            GrowthRule { defense_per_marker: 1, ..Default::default() },
            GrowthRule { defense_per_two: 1, enemy_ap_per_two: -1, ..Default::default() },
        ];
        assert_eq!(growth_defense_of(&statics, &st, 0), (0, 0), "no markers, no ladder");
        st.growth_markers[0] = 3;
        assert_eq!(
            growth_defense_of(&statics, &st, 0),
            (4, -1),
            "3 markers: +3 +1 to Defense, -1 AP per two markers"
        );
    }

    /// rules-wave3-growthmark (epoch 6) — "Defensive Frenzy" PRESENT at
    /// rules_epoch 6, ABSENT at 5: two banked markers lift the bearer's OWN
    /// save target by 2. Same draws at both epochs (same seed), so the only
    /// thing that can move the defense target is the rule gate.
    #[test]
    fn defensive_frenzys_defense_ladder_applies_only_at_epoch_6() {
        let (mut st, mut statics) = buff_line();
        statics[2].growth = vec![GrowthRule {
            name: "Defensive Frenzy".into(),
            on_kill: true, max_markers: 2, defense_per_marker: 1, ..Default::default()
        }];
        statics[0].shoot = vec![gun("Rifle", 20, 24)];
        st.growth_markers[2] = 2;
        let terrain = crate::terrain::Terrain::default();
        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (next6, shot6) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 6, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot6.rolls[1].kind, "defense");
        assert_eq!(shot6.rolls[1].target, 6, "2 markers x +1 on Defense 4+");
        assert!(shot6.log.iter().any(|l| l.contains("Defensive Frenzy")),
            "the LOGGING-RULE line: {:?}", shot6.log);

        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (next5, shot5) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 5, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot5.rolls[1].kind, "defense");
        assert_eq!(shot5.rolls[1].target, 4, "rules_epoch 5 replays byte-exact");
        assert_eq!(next5.growth_markers[2], 2);
        assert!(shot5.log.iter().all(|l| !l.contains("Defensive")), "no log line");
        assert_eq!(next6.growth_markers[2], next5.growth_markers[2]);
    }

    /// rules-wave3-growthmark (epoch 6) — "Defensive Growth": +1 to Defense
    /// per TWO markers (3 banked markers = +1, not +3 — the ladder is
    /// `markers / 2`), and the same epoch gate as its Frenzy sister.
    #[test]
    fn defensive_growths_defense_per_two_applies_only_at_epoch_6() {
        let (mut st, mut statics) = buff_line();
        statics[2].growth = vec![GrowthRule {
            name: "Defensive Growth".into(),
            per_round: true, max_markers: 4, defense_per_two: 1, ..Default::default()
        }];
        statics[0].shoot = vec![gun("Rifle", 20, 24)];
        st.growth_markers[2] = 3;
        let terrain = crate::terrain::Terrain::default();
        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (_, shot6) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 6, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot6.rolls[1].target, 5, "3 markers = 1 pair -> +1 on Defense 4+ (not +3)");
        assert!(shot6.log.iter().any(|l| l.contains("Defensive Growth")),
            "the LOGGING-RULE line: {:?}", shot6.log);

        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (_, shot5) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 5, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot5.rolls[1].target, 4, "rules_epoch 5 replays byte-exact");
        assert!(shot5.log.iter().all(|l| !l.contains("Defensive")), "no log line");
    }

    /// rules-wave3-growthmark (epoch 6) — "Fortified Growth": every unit
    /// attacking the bearer rides AP(-1) per two markers, floored at AP(0)
    /// (the AP(2) rifle at 4 banked markers swings the save target back from
    /// 6+ to 4+), epoch-gated like the Defensive pair.
    #[test]
    fn fortified_growths_ap_cut_applies_only_at_epoch_6() {
        let (mut st, mut statics) = buff_line();
        statics[2].growth = vec![GrowthRule {
            name: "Fortified Growth".into(),
            per_round: true, max_markers: 4, enemy_ap_per_two: -1, ..Default::default()
        }];
        let mut rifle = gun("Rifle", 20, 24);
        rifle.ap = 2;
        statics[0].shoot = vec![rifle];
        st.growth_markers[2] = 4;
        let terrain = crate::terrain::Terrain::default();
        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (_, shot6) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 6, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot6.rolls[1].target, 4,
            "AP(2) cut by 2 (4 markers = 2 pairs) -> AP(0), Defense 4+");
        assert!(shot6.log.iter().any(|l| l.contains("Fortified Growth")),
            "the LOGGING-RULE line: {:?}", shot6.log);

        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (_, shot5) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 5, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot5.rolls[1].target, 6, "rules_epoch 5 replays byte-exact: AP(2) stands");
    }

    /// rules-wave3-growthmark (epoch 6) — "Regenerative Strength": every
    /// wound the bearer IGNORED banks one marker (Regeneration's own
    /// ignored count), and the gain carries the LOGGING-RULE line. A
    /// rules_epoch 5 replay banks nothing — the gate, not the wound count,
    /// is what differs between the two runs.
    #[test]
    fn regenerative_strength_banks_markers_when_it_ignores_wounds_at_epoch_6() {
        let (mut st, mut statics) = buff_line();
        statics[2].growth = vec![GrowthRule {
            on_ignore_wound: true, max_markers: 4, ..Default::default()
        }];
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 2;
        statics[2].ctx.regen_target_spell = 2;
        statics[0].shoot = vec![gun("Rifle", 20, 24)];
        st.growth_markers[2] = 0;
        let terrain = crate::terrain::Terrain::default();
        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (next6, shot6) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 6, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(next6.growth_markers[2] >= 1,
            "wounds ignored at 2+ banked markers: {:?} log {:?}", next6.growth_markers, shot6.log);
        assert!(shot6.log.iter().any(|l| l.contains("Regenerative Strength")),
            "the LOGGING-RULE line: {:?}", shot6.log);

        let mut rng = crate::rng::GodotRng::new(0);
        let mut tray = Tray::seeded(27);
        let (next5, shot5) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain,
            Seams { rules_epoch: 5, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next5.growth_markers[2], 0, "rules_epoch 5 replays byte-exact: no markers banked");
        assert!(shot5.log.iter().all(|l| !l.contains("Regenerative Strength")));
    }

    /// rules-wave3-growthmark (epoch 6) — "Regenerative Strength" 's melee
    /// facet: +X attacks with one melee weapon, X = the bearer's own marker
    /// count, PRESENT at rules_epoch 6 and ABSENT at 5 (`melee_parts`).
    #[test]
    fn regenerative_strengths_attacks_facet_applies_only_at_epoch_6() {
        let (mut st, mut statics) = buff_line();
        statics[0].growth = vec![GrowthRule {
            on_ignore_wound: true, attacks_per_marker: 1, max_markers: 4, ..Default::default()
        }];
        st.growth_markers[0] = 3;
        let parts6 = melee_parts(&statics, &st, 0, 2, Seams { rules_epoch: 6, ..Default::default() });
        assert_eq!(parts6[0].1.attacks[0], 1 + 3, "3 markers x +1 attack");
        let parts5 = melee_parts(&statics, &st, 0, 2, Seams { rules_epoch: 5, ..Default::default() });
        assert_eq!(parts5[0].1.attacks[0], 1, "rules_epoch 5 replays byte-exact");
    }

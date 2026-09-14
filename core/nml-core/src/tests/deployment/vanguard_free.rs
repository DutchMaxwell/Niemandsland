use super::*;

    // ---- EPOCH_16 (sweeps A/C — one defect under three names, rows
    //      `Vanguard`/`Drakesworn`/`Fanatic`; ledger
    //      proven_vs_read_part2.tsv, families "placement / target tie-break"
    //      and "unit-stat bases", proof_kind "none"): the printed text is
    //      "After this model is deployed, it may be placed anywhere fully
    //      within 9\" of its position" — the FREE choice
    //      (`deployment::vanguard_free_place`), not a push toward the enemy.
    //      Each row reads ITS OWN registry entry by the rule's EXACT NAME
    //      (the #489 lesson), asserts the entry's own number (`place_in: 9`),
    //      then the deployment seam spending it: a legal spot ~8" toward an
    //      objective the zone scan can never reach, the epoch-aware log law
    //      naming the free choice.

    /// The deployment seam, fed from the REAL registry entry: one carrier in
    /// a south-edge zone, one objective 1 m off the zone — the ladder's own
    /// scan lands at the zone's edge (0.7 m from the objective) and only the
    /// rule's free 9" choice closes most of that gap.
    fn free_place_leg(system: &str, faction: &str, rule: &str) -> crate::deployment::SideDeploy {
        let mut reg = crate::rules::Registries::new(&repo_root());
        let e = reg
            .rules_for(system)
            .lookup(faction, rule)
            .unwrap_or_else(|| panic!("{rule}: no registry entry for {system}/{faction}"));
        assert_eq!(e.primitive.as_deref(), Some("Vanguard"), "{rule}'s own primitive");
        let place_in = e.param_f("place_in", 9.0);
        assert!((place_in - 9.0).abs() < 1e-9, "{rule} carries place_in 9, got {place_in}");
        let board = empty_board();
        let specs = vec![crate::deployment::UnitSpec {
            key: "bearer".into(),
            model_count: 1,
            base_r_m: 0.016,
            footprint: vec![(0.0, 0.0)],
            vanguard: true,
            place_in_m: Some(place_in * crate::IN2M),
            model_shapes: vec![crate::deployment::ModelShape {
                is_oval: false,
                w_mm: 32,
                d_mm: 32,
                tough: 1,
                n: 1,
            }],
            ..Default::default()
        }];
        let zone = crate::deployment::Rect::new(-0.15, -0.3, 0.30, 0.3);
        let objs = vec![(0.0_f64, -1.0_f64)];
        crate::deployment::deploy_side(
            &specs, &zone, &objs, &board, 7, crate::acts::CURRENT_RULES_EPOCH,
        )
    }

    /// THE NUMBER: the free choice steps ~8" off the zone's edge toward the
    /// objective — inside the 9" disc, far past the ladder spot — and the
    /// epoch-aware log law names the rule, the direction-neutral distance and
    /// the free placement.
    fn assert_free_nine_inch_reach(rule: &str, sd: &crate::deployment::SideDeploy) {
        assert_eq!(sd.placements.len(), 1);
        let p = &sd.placements[0];
        assert!(p.vanguard_pushed, "{rule}: the free placement moved the unit: {p:?}");
        assert!(p.spot.1 < -0.45, "{rule}: stepped back toward the objective: {p:?}");
        assert_eq!(sd.events.len(), 1, "{rule}: one deploy event: {:?}", sd.events);
        assert_eq!(sd.events[0].unit, "bearer");
        assert_eq!(sd.events[0].rule, crate::deployment::VANGUARD_FREE_RULE_TEXT);
        assert_eq!(sd.events[0].why, "vanguard free placement");
        let chosen = sd.events[0].chosen.clone();
        let dist_in: f64 = chosen
            .trim_end_matches("\" repositioned")
            .trim()
            .parse()
            .unwrap_or_else(|_| panic!("{rule}: the chosen distance: {chosen}"));
        assert!(
            dist_in > 7.0 && dist_in <= 9.0,
            "{rule}: the 9\" disc's reach, the table's own chosen law: {chosen}"
        );
    }

    #[test]
    fn vanguards_free_choice_reaches_the_nine_inch_disc_edge() {
        let sd = free_place_leg("aof", "change_disciples", "Vanguard");
        assert_free_nine_inch_reach("Vanguard", &sd);
    }

    #[test]
    fn drakesworns_free_choice_reaches_the_nine_inch_disc_edge() {
        let sd = free_place_leg("aof", "volcanic_dwarves", "Drakesworn");
        assert_free_nine_inch_reach("Drakesworn", &sd);
    }

    #[test]
    fn fanatics_free_choice_reaches_the_nine_inch_disc_edge() {
        let sd = free_place_leg("gf", "soul_snatcher_cults", "Fanatic");
        assert_free_nine_inch_reach("Fanatic", &sd);
    }

use super::*;

    // ------------------- wave 4 follow-up: Extended Buff Range (the relay waiver) ---

    /// The registry-built carrier: a gf/human_defense_force profile whose ONLY
    /// rule is the REAL registry entry (`assets/solo/rules_mechanics_gf.json`,
    /// primitive "Extended Buff Range", params relay 24 / pick 12 /
    /// hero_link 0). The REAL `build_for` product, read at `epoch`.
    fn ebr_bearer(rules_epoch: u32, faction: (&str, &str), rules: &[&str]) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: rules.iter().map(|r| r.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: faction.0.into(),
            faction_folder: faction.1.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// The stamp: the carrier's own params off the registry entry, behind the
    /// FROZEN `EPOCH_7_TABLE_RULES` — present at 7, absent at 6.
    #[test]
    fn the_real_registry_stamps_extended_buff_range_at_epoch_seven_not_six() {
        for (system, faction) in [("gf", "human_defense_force"), ("aof", "human_empire")] {
            let on = ebr_bearer(7, (system, faction), &["Extended Buff Range"]);
            let s = on.ebr.as_ref().expect("epoch 7: the entry is stamped");
            assert_eq!(s.relay_range_in, 24.0, "the relay link, {system}");
            assert_eq!(s.hero_link_in, 0.0, "the Hero must be IN the unit, {system}");
            let off = ebr_bearer(6, (system, faction), &["Extended Buff Range"]);
            assert!(off.ebr.is_none(), "epoch 6: the record predates the wave ({system})");
        }
    }

    /// One friendly 12"-pick buff carrier ("a", itself the relay: it carries
    /// the rule and the Hero clause is its own is_hero) and a friendly target
    /// "b" 16" away -- beyond the printed 12", inside the 24" relay link, and
    /// itself a carrier. The relayed pick must land the buff record on "b".
    fn ebr_line(rules_epoch: u32, a_ebr: bool, b_ebr: bool) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(); 4],
            index: HashMap::new(),
        });
        // All friendly: the pick's candidates are "ah" (2", in range) and "b"
        // (16", relayed only).
        st.player = vec![0, 0, 0, 0];
        st.alive = vec![1, 0, 1, 0];
        st.wounds = vec![vec![1], vec![], vec![1], vec![]];
        st.positions[2] = vec![[16.0 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.positions[3] = vec![];
        let ebr = if rules_epoch >= 7 { Some(crate::unit::EbrStamp { relay_range_in: 24.0, hero_link_in: 0.0 }) } else { None };
        let ebr_a = if a_ebr { ebr.clone() } else { None };
        let ebr_b = if b_ebr { ebr.clone() } else { None };
        let mut a = UnitStatic {
            name: "a".into(),
            model_count: 1,
            is_hero: true,
            utility_buffs: vec![ub("Hold the Line Boost Buff")],
            ebr: ebr_a,
            ..Default::default()
        };
        a.utility_buffs[0].morale_mod = 1;
        a.wounds_max = vec![1];
        a.ctx.quality = 4;
        let mut b = UnitStatic { name: "b".into(), ebr: ebr_b, ..Default::default() };
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        (st, vec![a, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    fn run_ebr(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> State {
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: None,
            charge: None, patient: false, split: None, traced: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
            .0
    }

    /// The port: a friendly candidate beyond the printed 12" is a legal pick
    /// when the relay clause holds -- both ends carry the rule, the relay has
    /// its Hero, the link is within the relay range (main.gd:16473-16520,
    /// `SoloController.ebr_relay_ok` :892-895). Epoch-6 control: the record
    /// predates the wave, the relay stays shut.
    #[test]
    fn the_relay_waiver_reaches_a_carrier_beyond_the_printed_pick_range() {
        let (st, statics) = ebr_line(7, true, true);
        let next = run_ebr(&st, &statics, 7);
        assert!(
            !next.buffs[2].is_empty(),
            "relayed: the buff lands on the 16\" carrier -- got {:#?}",
            (next.buffs[0].len(), next.buffs[2].len())
        );

        let (st6, statics6) = ebr_line(6, true, true);
        let next6 = run_ebr(&st6, &statics6, 6);
        assert!(
            next6.buffs[2].is_empty(),
            "epoch 6: no relay waiver -- got {:#?}",
            next6.buffs.iter().map(|b| b.len()).collect::<Vec<_>>()
        );
    }

    /// The both-ends gate: the TARGET must carry the rule itself ("another
    /// friendly unit WITH THIS RULE") -- without the target's own entry the
    /// relayed pick is refused (main.gd:16531-16532).
    #[test]
    fn the_target_must_carry_the_rule_itself() {
        // Positive control first: with BOTH ends carrying, the relayed pick
        // lands, so the guard below falls under any impl that never relays.
        let (st, statics) = ebr_line(7, true, true);
        let control = run_ebr(&st, &statics, 7);
        assert!(
            !control.buffs[2].is_empty(),
            "control: both ends carry, the buff lands -- got {:#?}",
            control.buffs.iter().map(|b| b.len()).collect::<Vec<_>>()
        );
        let (st, statics) = ebr_line(7, true, false);
        let next = run_ebr(&st, &statics, 7);
        assert!(next.buffs[2].is_empty(), "no rule on the target: no relayed pick");
    }

    /// The relay link is bounded: a candidate beyond the relay range (24") is
    /// refused even with both ends carrying (ebr_relay_ok's gap clause).
    #[test]
    fn the_relay_link_is_bounded_at_the_relay_range() {
        // Positive control first: the same line INSIDE the 24" relay range
        // relays, so the bounded-refusal below falls under a never-relay impl.
        let (st, statics) = ebr_line(7, true, true);
        let control = run_ebr(&st, &statics, 7);
        assert!(
            !control.buffs[2].is_empty(),
            "control: inside the relay range the buff lands -- got {:#?}",
            control.buffs.iter().map(|b| b.len()).collect::<Vec<_>>()
        );
        let (mut st, statics) = ebr_line(7, true, true);
        st.positions[2] = vec![[30.0 * IN2M, 0.0, 0.0]];
        let next = run_ebr(&st, &statics, 7);
        assert!(next.buffs[2].is_empty(), "beyond 24\": the link is dead");
    }

    /// The bearer's own unit must carry the rule (the relay IS the buffing
    /// hero's unit) -- a bare Hero without the radio reaches nobody.
    #[test]
    fn the_relay_itself_must_carry_the_rule() {
        // Positive control first: with the radio on the relay the buff lands,
        // so the guard below falls under any impl that never relays.
        let (st, statics) = ebr_line(7, true, true);
        let control = run_ebr(&st, &statics, 7);
        assert!(
            !control.buffs[2].is_empty(),
            "control: the radio on the relay lands the buff -- got {:#?}",
            control.buffs.iter().map(|b| b.len()).collect::<Vec<_>>()
        );
        let (st, statics) = ebr_line(7, false, true);
        let next = run_ebr(&st, &statics, 7);
        assert!(next.buffs[2].is_empty(), "no radio on the relay: no relayed pick");
    }

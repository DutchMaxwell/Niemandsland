use super::*;

    // ------------------- seam 4 step 1: the ap/def record shape (epoch 7) ---

    /// The registry-built carrier: a profile whose ONLY rule is the REAL
    /// registry entry (`assets/solo/rules_mechanics_*.json`, primitive
    /// "Utility Buff", a single ap/def knob). The REAL `build_for` product,
    /// read at `epoch`.
    fn ap_def_bearer(rules_epoch: u32, faction: (&str, &str), rule: &str) -> UnitStatic {
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
            game_system: faction.0.into(),
            faction_folder: faction.1.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// The bearer "a" and one target "b" 5" away (inside every pick range);
    /// ah/bh field no models. `enemy` picks the PLAYER split for the
    /// enemy-side debuffs ("Piercing Debuff"), the all-friendly line for the
    /// friendly buffs ("Defense Buff").
    fn ap_def_line(
        rules_epoch: u32,
        faction: (&str, &str),
        rule: &str,
        enemy: bool,
    ) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        if !enemy {
            st.player = vec![0, 0, 0, 0];
        }
        st.alive = vec![1, 0, 1, 0];
        st.wounds = vec![vec![1], vec![], vec![1], vec![]];
        st.positions[2] = vec![[5.0 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.positions[3] = vec![];
        (
            st,
            vec![
                ap_def_bearer(rules_epoch, faction, rule),
                UnitStatic { name: "ah".into(), ..Default::default() },
                UnitStatic { name: "b".into(), ..Default::default() },
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    fn run_ap_def(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> State {
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: None,
            charge: None, patient: false, split: None, traced: None,
            teleport: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
            .0
    }

    /// SEAM 4 step 1 (design §4(d)): a "Utility Buff" row whose ONLY knob is
    /// `def_mod`/`ap_mod` survives `record_buff`'s all-zero guard at
    /// `EPOCH_7_TABLE_RULES` and the record carries the knob. The knobs are
    /// asserted through the record's own `Debug` — the READS are PR 2, so the
    /// row must land without any behaviour at the dice changing.
    #[test]
    fn ap_and_defense_only_buff_rows_survive_record_buff_at_epoch_7() {
        // Defense Buff (aof human_empire): def_mod 1, friendly 12" — the
        // friendly pick is the bearer itself (alive+Tough beats the bare "b").
        let (st, statics) = ap_def_line(7, ("aof", "human_empire"), "Defense Buff", false);
        let next = run_ap_def(&st, &statics, 7);
        assert_eq!(
            next.buffs[0].len(), 1,
            "RED before the fix: the all-zero guard dropped the def-only row"
        );
        assert!(
            format!("{:?}", next.buffs[0][0]).contains("def_mod: 1"),
            "the record carries the knob: {:?}", next.buffs[0][0]
        );

        // Piercing Debuff (gf machine_cults): ap_mod -1, enemy 18", needs_los.
        let (st, statics) = ap_def_line(7, ("gf", "machine_cults"), "Piercing Debuff", true);
        let next = run_ap_def(&st, &statics, 7);
        assert_eq!(
            next.buffs[2].len(), 1,
            "RED before the fix: the all-zero guard dropped the ap-only row"
        );
        assert!(
            format!("{:?}", next.buffs[2][0]).contains("ap_mod: -1"),
            "the record carries the knob: {:?}", next.buffs[2][0]
        );
    }

    /// The epoch-6 twin: below `EPOCH_7_TABLE_RULES` the same rows keep being
    /// dropped, so the old corpora's stamps (and the replay) stay byte-identical.
    #[test]
    fn the_ap_and_defense_only_rows_are_still_dropped_at_epoch_6() {
        let (st, statics) = ap_def_line(6, ("aof", "human_empire"), "Defense Buff", false);
        let next = run_ap_def(&st, &statics, 6);
        assert!(
            next.buffs[0].is_empty(),
            "below 7 the def-only row keeps being dropped -- got {:?}",
            next.buffs.iter().map(|b| b.len()).collect::<Vec<_>>()
        );
        let (st, statics) = ap_def_line(6, ("gf", "machine_cults"), "Piercing Debuff", true);
        let next = run_ap_def(&st, &statics, 6);
        assert!(
            next.buffs[2].is_empty(),
            "below 7 the ap-only row keeps being dropped -- got {:?}",
            next.buffs.iter().map(|b| b.len()).collect::<Vec<_>>()
        );
    }

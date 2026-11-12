use super::*;

    /// P3 step 13: `band_parts(..).total()` is the distance the real move spends. A Fast unit (8"/16") with a live +1"
    /// move row walks away from the enemy line, so nothing but its band stops it. The hand sums 8 + 1 and 16 + 1 pin
    /// the parts `total` adds: a part dropped from the sum (say `buff`) turns this red.
    #[test]
    fn the_band_total_is_the_distance_the_real_move_spends() {
        let mut st = four_unit_line();
        let keys = st.roster.keys.clone();
        let index = keys.iter().cloned().zip(0..).collect();
        st.roster = Rc::new(Roster { keys, index, profile: vec![0; 4] });
        st.bands[0] = Bands { advance: 8.0, rush: 16.0, charge: None };
        st.buffs[0].push(mods::LiveMod { hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 1, grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: false, name: Rc::from("GM") });
        let statics = vec![UnitStatic::default(); 4];
        let t = crate::terrain::Terrain::default();
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        for (kind, want) in [(ADVANCE, 9.0), (RUSH, 17.0)] {
            let parts = band_parts(&statics, &st, &st, 0, kind, None, 0.0, Cover::Board(&t), seams, false);
            assert_eq!(parts.total(), want, "{parts:?}");
            let a = Action { kind, unit: "a".into(), dest: Some([-40.0 * IN2M, 0.0, 0.0]), shoot: None, charge: None,
                patient: false, split: None, traced: None, teleport: None };
            let (next, _) = resolve_stochastic_tray_on_board(&statics, &st, &a, &t, seams, &mut GodotRng::new(0), &mut Tray::seeded(7)).unwrap();
            let travel = (next.positions[0][0][0] - st.positions[0][0][0]).abs() / IN2M;
            assert!((travel - parts.total()).abs() < 0.01, "kind {kind}: moved {travel}\", band {}", parts.total());
        }
    }

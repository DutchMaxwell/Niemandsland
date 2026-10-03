use super::*;

    // ------------------------- tray-exact tail: Guarded (over 9") on melee saves ---

    /// The defence roll's target in a result (the first "defense" batch).
    fn save_target(r: &ShootResult) -> i64 {
        r.rolls.iter().find(|x| x.kind == "defense").map(|x| x.target).unwrap_or(-1)
    }

    fn guarded(defense: i64) -> Ctx {
        Ctx { guarded: true, ..defender(defense, 10) }
    }

    /// The table raises the CHARGED side's save by 1 when a Guarded-family defender is charged from
    /// over 9" — the Impact pools (main.gd:7440-7441) and the melee strikes (main.gd:7096-7098). With
    /// `Seams::tray_exact` the core does both, unflagged; without it the old save stands and only a
    /// charge that really clears the gate is flagged (the Impact pool used to flag every Guarded
    /// defender, the melee strikes none). A charge from 8" and a strike-back change nothing.
    #[test]
    fn a_guarded_defender_charged_from_over_9_saves_better_with_tray_exact() {
        let impact = |charge: Option<(f64, bool)>| {
            resolve_impact_pool_at(20, 0, "a", &guarded(4), "b", charge, &mut Tray::seeded(3))
        };
        let exact = impact(Some((10.0, true)));
        assert_eq!((save_target(&exact), exact.unported.is_empty()), (3, true), "{:?}", exact.unported);
        let old = impact(Some((10.0, false)));
        assert_eq!((save_target(&old), old.unported.contains(&"guarded_over9")), (4, true));
        let near = impact(Some((8.0, true)));
        assert_eq!((save_target(&near), near.unported.is_empty()), (4, true));

        let att = Ctx { quality: 2, ..Default::default() };
        let blade = [ShootProfile { name: "Blade".into(), attacks: 20, count: 1, ..Default::default() }];
        let melee = |charging: bool, exact: bool| {
            resolve_melee_leg(&[striker(&blade, &[0], &[20], &att)], &guarded(4), "b", charging, true, true,
                true, 10.0, false, exact, &mut Tray::seeded(3))
        };
        let m = melee(true, true);
        assert_eq!((save_target(&m), m.unported.contains(&"guarded_over9")), (3, false));
        let m_old = melee(true, false);
        assert_eq!((save_target(&m_old), m_old.unported.contains(&"guarded_over9")), (4, true));
        let back = melee(false, true);
        assert_eq!((save_target(&back), back.unported.contains(&"guarded_over9")), (4, false));
    }

use super::*;

    // ------------------------- tray-exact S8: a Takedown shot as a unit of [1] ---

    /// The defence batches' dice and the first batch's target.
    fn saves(r: &ShootResult) -> (i64, i64) {
        let d: Vec<&Roll> = r.rolls.iter().filter(|x| x.kind == "defense").collect();
        (d.iter().map(|x| x.count).sum(), d.first().map(|x| x.target).unwrap_or(-1))
    }

    /// The table resolves a Takedown "as a unit of [1]" (main.gd `_solo_takedown_context` and
    /// `_solo_hits`, TC-023): Blast(3) has ONE model to spill onto, and a non-Blast save reads the
    /// picked model's OWN square — a pick in the open saves uncovered although the unit's majority
    /// stands in woods. With `Seams::tray_exact` the core does both; without it Blast multiplies onto
    /// the unit and the save keeps the unit's cover.
    #[test]
    fn a_takedown_shot_resolves_as_a_unit_of_one_with_tray_exact() {
        let def = Ctx { in_cover: true, ..defender(4, 5) };
        let att = shooter(2);
        let fire = |blast: i64, exact: bool| {
            let gun = [ShootProfile { takedown: true, blast, ..rifle(6) }];
            let r = resolve_volley_leg(&[Shooter { profiles: &gun, keep: &[0], attacks: &[6], att: &att, owner: "a" }],
                &def, "b", 12.0, 12.0, true, true, true, true, true, exact, &|_| false, &mut Tray::seeded(3));
            saves(&r)
        };
        let (exact, old) = (fire(3, true), fire(3, false));
        assert!(exact.0 > 0, "fixture: the volley hits");
        assert_eq!(old.0, exact.0 * 3, "Blast(3) multiplies onto the unit only without the switch");
        assert_eq!((fire(0, true).1, fire(0, false).1), (4, 3), "the pick's own square vs the unit's cover");
    }

    /// Tray-exact S10: with the switch a Takedown volley is no longer flagged — it names its pick and
    /// the save that pick rolls (rules-must-log, main.gd `_solo_takedown_pick` and
    /// `_solo_log_takedown_context`). The table re-picks per profile (main.gd:4171): S8 asks the
    /// caller for the pick's own square from the groups landed so far, so a second Takedown profile
    /// saves on ITS pick's cover, unflagged. Without the switch `takedown` stands.
    #[test]
    fn a_takedown_volley_is_unflagged_and_logged_with_tray_exact() {
        let def = Ctx { in_cover: true, ..defender(4, 5) };
        let att = shooter(2);
        let rifle = |name: &str| ShootProfile { name: name.into(), takedown: true, ..rifle(6) };
        let fire = |guns: &[ShootProfile], exact: bool, own: &dyn Fn(&[i64]) -> bool| {
            let (keep, attacks): (Vec<usize>, Vec<i64>) = (0..guns.len()).map(|i| (i, 6)).unzip();
            resolve_volley_leg(&[Shooter { profiles: guns, keep: &keep, attacks: &attacks, att: &att, owner: "a" }],
                &def, "b", 12.0, 12.0, true, true, true, true, true, exact, own, &mut Tray::seeded(3))
        };
        let one = [rifle("Rifle")];
        let r = fire(&one, true, &|_| false);
        assert!(r.unported.is_empty(), "{:?}", r.unported);
        assert!(r.log.iter().any(|l| l.ends_with("targets the most valuable model in b — resolved as a unit of [1]")), "{:?}", r.log);
        assert!(r.log.iter().any(|l| l == "Takedown (Rifle): the pick saves on 4+ (no cover of its own)"), "{:?}", r.log);
        assert!(fire(&one, false, &|_| false).unported.contains(&"takedown"));
        // The first pick stands in woods; once a group landed, the next pick stands in the open.
        let r2 = fire(&[rifle("Rifle"), rifle("Pistol")], true, &|g: &[i64]| !g.iter().any(|&x| x > 0));
        assert!(r2.takedown_groups.first().is_some_and(|&g| g > 0), "fixture: the first lands");
        assert!(r2.unported.is_empty(), "{:?}", r2.unported);
        assert!(r2.log.iter().any(|l| l == "Takedown (Rifle): the pick saves on 3+ (in cover of its own)"), "{:?}", r2.log);
        assert!(r2.log.iter().any(|l| l == "Takedown (Pistol): the pick saves on 4+ (no cover of its own)"), "{:?}", r2.log);
    }


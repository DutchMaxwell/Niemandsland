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

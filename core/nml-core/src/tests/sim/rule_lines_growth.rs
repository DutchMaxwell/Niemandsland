use super::*;
use super::rule_lines_defense::rule_lines;

    // ---- Door rule lines (lane lift92): the Growth Markers family's lines in the table's words ----

    fn growth(name: &str, edit: impl FnOnce(&mut GrowthRule)) -> Vec<GrowthRule> {
        let mut g = GrowthRule { name: name.into(), max_markers: 4, per_round: true, ..Default::default() };
        edit(&mut g);
        vec![g]
    }

    /// Piercing Growth / Frenzy name the AP their markers add once per weapon profile that has hits to save, after the Fortified and
    /// conditional-AP lines and before the save (the table's `_solo_resolve_saves`, `EPOCH_73_V36`). Nothing at 0 or 1 marker (the ladder is
    /// per two). RED: the line is missing.
    #[test]
    fn a_growth_carrier_names_the_ap_its_markers_add() {
        let faces = || vec![vec![6, 6, 6, 1], vec![1, 1, 1]];
        let with = |markers: i64| rule_lines(move |st, s| { s[0].ctx.v36_rules = true; s[0].growth = growth("Piercing Growth", |g| g.ap_per_two = 1); (st.growth_markers[0], st.growth_round[0]) = (markers, st.round); }, faces());
        let two = with(2);
        let at = two.iter().position(|l| l == "Piercing Growth: Att adds AP(+1) from its growth markers").unwrap_or_else(|| panic!("{two:?}"));
        assert!(two[at + 1].starts_with("Def saves on"), "the threshold line follows: {two:?}");
        assert!(with(4).iter().any(|l| l == "Piercing Growth: Att adds AP(+2) from its growth markers"), "{:?}", with(4));
        assert!(with(1).iter().all(|l| !l.contains("growth markers")), "one marker is no AP: {:?}", with(1));
        // Piercing Frenzy: one AP per marker, named as its own rule
        let frenzy = rule_lines(|st, s| { s[0].ctx.v36_rules = true; s[0].growth = growth("Piercing Frenzy", |g| { g.ap_per_marker = 1; g.per_round = false; g.on_kill = true }); st.growth_markers[0] = 1; }, faces());
        assert!(frenzy.iter().any(|l| l == "Piercing Frenzy: Att adds AP(+1) from its growth markers"), "{frenzy:?}");
    }

    /// Defensive Growth / Frenzy name their Defense bonus once, after the Shielded line and before the announce, with the Defense the target
    /// then saves on (the table's `_solo_log_defense_parts`). RED: the line is missing.
    #[test]
    fn a_defensive_growth_target_names_its_defense_bonus_before_the_announce() {
        let faces = || vec![vec![6, 1, 1, 1], vec![1]];
        let with = |name: &'static str, per_two: bool, markers: i64| rule_lines(move |st, s| {
            s[2].growth = growth(name, |g| if per_two { g.defense_per_two = 1 } else { g.defense_per_marker = 1; g.per_round = false });
            st.growth_markers[2] = markers;
        }, faces());
        let growth2 = with("Defensive Growth", true, 2);
        assert_eq!(growth2[..2], ["Def is Defensive Growth: +1 Defense (saves on 3+)", "Att fires at Def"], "{growth2:?}");
        assert_eq!(with("Defensive Growth", true, 4)[0], "Def is Defensive Growth: +2 Defense (saves on 2+)");
        assert_eq!(with("Defensive Frenzy", false, 1)[0], "Def is Defensive Frenzy: +1 Defense (saves on 3+)");
        assert!(with("Defensive Growth", true, 1).iter().all(|l| !l.contains("is Defensive")), "one marker is no Defense: {:?}", with("Defensive Growth", true, 1));
    }

    /// Fortified Growth names its AP cut once per save batch after a plain Fortified's line (the table composes the two), with the AP
    /// before and after and the Defense it then saves on; nothing is said when the weapon has no AP to cut. RED: the line is missing.
    #[test]
    fn a_fortified_growth_target_names_its_ap_cut() {
        let faces = || vec![vec![6, 6, 6, 1], vec![1, 1, 1]];
        let ap2 = |p: &mut ShootProfile| p.ap = 2;
        let fg = |markers: i64, plain: bool, ap: fn(&mut ShootProfile)| rule_lines(move |st, s| {
            ap(&mut s[0].shoot[0]);
            s[2].growth = growth("Fortified Growth", |g| g.enemy_ap_per_two = -1);
            s[2].ctx.fortified = plain;
            st.growth_markers[2] = markers;
        }, faces());
        let two = fg(2, false, ap2);
        let at = two.iter().position(|l| l == "Fortified Growth: Def takes the hits at AP(1) instead of AP(2) — saves on 5+").unwrap_or_else(|| panic!("{two:?}"));
        assert!(two[at + 1].starts_with("Def saves on"), "the threshold line follows: {two:?}");
        assert!(fg(4, false, ap2).iter().any(|l| l == "Fortified Growth: Def takes the hits at AP(0) instead of AP(2) — saves on 4+"));
        // beside a plain Fortified (AP 2 -> 1) the growth cut starts from the AP the plain rule left (1 -> 0)
        let both = fg(2, true, ap2);
        let plain_at = both.iter().position(|l| l.starts_with("Fortified: Def takes the hits at AP(1) instead of AP(2)")).unwrap_or_else(|| panic!("{both:?}"));
        assert_eq!(both[plain_at + 1], "Fortified Growth: Def takes the hits at AP(0) instead of AP(1) — saves on 4+", "{both:?}");
        assert!(fg(2, false, |_| {}).iter().all(|l| !l.contains("takes the hits at AP")), "no AP, nothing to cut");
        assert!(fg(1, false, ap2).iter().all(|l| !l.contains("takes the hits at AP")), "one marker cuts nothing");
    }

    /// Piercing / Precision Frenzy say the marker a kill earns where it is placed, with the count and the cap; nothing at the cap.
    /// RED: the marker is placed silently.
    #[test]
    fn a_frenzy_kill_names_its_marker() {
        let mut st = four_unit_line();
        let mut statics = vec![UnitStatic::default()];
        statics[0].name = "Att".into();
        statics[0].growth = growth("Precision Frenzy", |g| { g.on_kill = true; g.max_markers = 2; g.hit_per_marker = 1; g.per_round = false });
        let mut tray = Tray::supplied(vec![]);
        growth_on_kill(&statics, &mut st, 0, &mut tray);
        growth_on_kill(&statics, &mut st, 0, &mut tray);
        growth_on_kill(&statics, &mut st, 0, &mut tray);
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(lines, ["Precision Frenzy: Att gains a marker for the kill (1/2)", "Precision Frenzy: Att gains a marker for the kill (2/2)"], "the cap says nothing");
    }

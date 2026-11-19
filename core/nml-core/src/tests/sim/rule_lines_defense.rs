use super::*;
use super::volley_landings::volley_line;

    // ---- Door rule lines (lane dlines2): the defender's rule lines in the table's words ----

    /// The lines one volley of `Att`'s `Rifle` (4 attacks, Quality 2+) at `Def` (two Tough(3) models, Defense 4+) says on the
    /// supplied faces; `tune` edits the fixture first. Epoch = the current one, so a wording change on an epoch turns it red.
    fn rule_lines(tune: impl FnOnce(&mut State, &mut [UnitStatic]), faces: Vec<Vec<u8>>) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() }); // one profile per roster slot
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        tune(&mut st, &mut statics);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::supplied(faces);
        resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// The Ranged Shrouding family names its range cut once per volley, before the first die, whether or not a weapon was shortened
    /// (the table's `_solo_resolve_ai_volley`). RED: drop the say. The target's own name, the clamp pair as the entry prints it.
    #[test]
    fn a_shrouded_target_names_the_range_cut_once() {
        let shroud = |_: &mut State, s: &mut [UnitStatic]| {
            s[2].ctx.ranged_shrouding = true;
            (s[2].ctx.ranged_shroud_name, s[2].ctx.ranged_shroud_penalty_in, s[2].ctx.ranged_shroud_floor_in) = ("Wild Veil", 6.0, 6.0);
        };
        let lines = rule_lines(shroud, vec![vec![6, 1, 1, 1], vec![1]]);
        assert_eq!(lines[..2], ["Att fires at Def", "Wild Veil: Def — weapon ranges against it 6\" shorter (min 6\")"], "{lines:?}");
        assert_eq!(lines.iter().filter(|l| l.contains("weapon ranges against it")).count(), 1, "{lines:?}");
        assert!(rule_lines(|_, _| {}, vec![vec![6, 1, 1, 1], vec![1]]).iter().all(|l| !l.contains("weapon ranges")), "no shroud, no line");
    }

    /// The re-roll line names the rule that gave the re-roll: plain Bane, a lone Lacerate, a unit-level alias (Mischievous, Unstoppable
    /// when Shooting) - the weapon alias had it already. RED: the line stays silent unless a weapon alias is stamped.
    #[test]
    fn the_reroll_line_names_bane_lacerate_or_the_units_alias() {
        let faces = || vec![vec![6, 6, 6, 1], vec![6, 1, 1], vec![1]];
        let said = |tune: fn(&mut ShootProfile)| rule_lines(move |_, s| { let p = &mut s[0].shoot[0]; p.bane = true; tune(p); }, faces());
        assert!(said(|_| {}).iter().any(|l| l == "Bane: Def re-rolls 1 unmodified Defense 6"), "{:?}", said(|_| {}));
        assert!(said(|p| p.rules = vec!["Lacerate".into()]).iter().any(|l| l == "Lacerate: Def re-rolls 1 unmodified Defense 6"));
        assert!(said(|p| p.bane_name = "Mischievous".into()).iter().any(|l| l == "Mischievous: Def re-rolls 1 unmodified Defense 6"));
        // the Boost that widened the window names itself, and the successful rolls it re-rolls
        let boost = said(|p| { p.bane_name = "Mischievous".into(); p.bane_rule = "Mischievous Boost"; p.bane_low = 5; p.bane_over_in = 0.0; });
        assert!(boost.iter().any(|l| l == "Mischievous Boost: Def re-rolls 1 unmodified Defense roll of 5+"), "{boost:?}");
        assert!(rule_lines(|_, _| {}, faces()).iter().all(|l| !l.contains("re-rolls")), "no Bane, no line");
    }

    /// A Fortified target names the AP cut once per save batch, before the threshold line, with the AP before and after and the Defense
    /// it then saves on; a Boost / gated alias names itself. Nothing is said when the weapon has no AP to cut. RED: the line is missing.
    #[test]
    fn a_fortified_target_names_its_ap_cut() {
        let faces = || vec![vec![6, 6, 6, 1], vec![1, 1, 1]];
        let ap2 = |p: &mut ShootProfile| p.ap = 2;
        let plain = rule_lines(|_, s| { ap2(&mut s[0].shoot[0]); s[2].ctx.fortified = true; }, faces());
        let at = plain.iter().position(|l| l == "Fortified: Def takes the hits at AP(1) instead of AP(2) — saves on 5+").unwrap_or_else(|| panic!("{plain:?}"));
        assert!(plain[at + 1].starts_with("Def saves on"), "the threshold line follows: {plain:?}");
        let boost = rule_lines(|_, s| { ap2(&mut s[0].shoot[0]); s[2].ctx.fortified_boost_ap = 1; s[2].ctx.fortified_boost_name = "Guardian Boost"; }, faces());
        assert!(boost.iter().any(|l| l.starts_with("Guardian Boost: Def takes the hits at AP(1) instead of AP(2) — saves on 5+")), "{boost:?}");
        let none = rule_lines(|_, s| { s[2].ctx.fortified = true; }, faces());
        assert!(none.iter().all(|l| !l.contains("takes the hits at AP")), "AP(0) has nothing to cut: {none:?}");
    }

    /// A Shielded target names its +1 Defense once, before the announce (the table's `_solo_log_defense_parts`); the alias names itself, a
    /// target most (not all) of whose models carry the literal says so. RED: the line is missing.
    #[test]
    fn a_shielded_target_names_its_defense_bonus_before_the_announce() {
        let faces = || vec![vec![6, 1, 1, 1], vec![1]];
        let plain = rule_lines(|_, s| s[2].ctx.shielded = true, faces());
        assert_eq!(plain[..2], ["Def is Shielded: +1 Defense (saves on 3+)", "Att fires at Def"], "{plain:?}");
        let alias = rule_lines(|_, s| { s[2].ctx.shielded = true; s[2].ctx.shielded_alias = crate::unit::ShieldedAlias::SturdyBoost; }, faces());
        assert_eq!(alias[0], "Def is Enhanced Sturdy: +1 Defense (saves on 3+)", "{alias:?}");
        let most = rule_lines(|_, s| { s[2].ctx.shielded = true; s[2].ctx.shielded_note = true; }, faces());
        assert_eq!(most[0], "Def is Shielded (most of its models carry it): +1 Defense (saves on 3+)", "{most:?}");
        assert!(rule_lines(|_, _| {}, faces()).iter().all(|l| !l.contains("is Shielded")), "no Shielded, no line");
    }

    /// The target's ignore roll names its group the way the table spells it ("regeneration", singular "die" for one wound); a bypass
    /// weapon (Rending / Bane / Unstoppable) names the skip, and the group that still rolls the bypassed wounds. RED: no line at all.
    #[test]
    fn the_ignore_roll_and_the_bypass_name_their_groups() {
        let regen = |groups: [i64; 4], names: [&'static str; 4], bypass: bool| move |_: &mut State, s: &mut [UnitStatic]| {
            let c = &mut s[2].ctx;
            c.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
            (c.regeneration, c.regen_named, c.regen_target, c.regen_groups, c.regen_names) = (true, groups[0] > 0, groups.iter().copied().filter(|&t| t > 0).min().unwrap(), groups, names);
            s[0].shoot[0].bypass_regen = bypass;
        };
        let names = ["regeneration", "self-repair", "", ""];
        let plain = rule_lines(regen([5, 0, 0, 0], names, false), vec![vec![6, 6, 6, 6], vec![1, 1, 1, 1], vec![5, 1, 1, 1]]);
        assert!(plain.iter().any(|l| l == "Def rolls 4 regeneration dice (5+) — 1 wound ignored"), "{plain:?}");
        let one = rule_lines(regen([5, 0, 0, 0], names, false), vec![vec![6, 1, 1, 1], vec![1], vec![1]]);
        assert!(one.iter().any(|l| l == "Def rolls 1 regeneration die (5+) — 0 wounds ignored"), "{one:?}");
        let skipped = rule_lines(regen([5, 0, 0, 0], names, true), vec![vec![6, 6, 6, 6], vec![1, 1, 1, 1]]);
        assert!(skipped.iter().any(|l| l == "Def: 4 wounds ignore Regeneration — no regeneration roll"), "{skipped:?}");
        assert!(skipped.iter().all(|l| !l.contains("rolls 4 regeneration")), "a bypass is not rolled: {skipped:?}");
        let both = rule_lines(regen([5, 6, 0, 0], names, true), vec![vec![6, 6, 6, 6], vec![1, 1, 1, 1], vec![1, 1, 1, 1]]);
        let at = |t: &str| both.iter().position(|l| l == t).unwrap_or_else(|| panic!("{t}: {both:?}"));
        assert!(at("Def: 4 wounds ignore Regeneration — no regeneration roll") < at("Def: 4 wounds ignore only Regeneration — Self-Repair still rolls"), "{both:?}");
        assert!(at("Def: 4 wounds ignore only Regeneration — Self-Repair still rolls") < at("Def rolls 4 self-repair dice (6+) — 0 wounds ignored"), "{both:?}");
        assert!(rule_lines(|_, _| {}, vec![vec![6, 6, 6, 6], vec![1, 1, 1, 1]]).iter().all(|l| !l.contains("ignore")), "no ignore rule, no line");
    }

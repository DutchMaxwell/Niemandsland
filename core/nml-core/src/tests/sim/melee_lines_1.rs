use super::*;
use super::melee_landing_gaps::{exact_seams, two_unit_melee};

    // ---- Melee door lines (lane lift92, melee train 1): the strike's lines the core did not say, in the table's words ----

    /// Every die the strike asks for is 1 unless a case plants it: the tray must never run dry in a line test.
    fn tray_with(planted: Vec<Vec<u8>>) -> Tray {
        let mut faces = planted;
        faces.extend((0..24).map(|_| vec![1u8; 24]));
        Tray::supplied(faces)
    }

    fn strike_lines(tune: impl FnOnce(&mut [UnitStatic], &mut State), planted: Vec<Vec<u8>>) -> Vec<String> {
        let (mut statics, mut st) = two_unit_melee(3, 5, 1);
        tune(&mut statics, &mut st);
        let mut tray = tray_with(planted);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// A Blast weapon in melee names its multiplier before the strike line, capped or not (the table says it always, #169). RED: no line.
    #[test]
    fn a_blast_strike_names_its_multiplier() {
        let blast = |s: &mut [UnitStatic], _: &mut State| s[0].melee[0].blast = 3;
        let lines = strike_lines(blast, vec![vec![4, 4, 1, 1, 1, 1]]);
        let at = lines.iter().position(|l| l == "Blast(3): 2 hits ×3 → 6 hits").unwrap_or_else(|| panic!("{lines:?}"));
        assert!(lines[at + 1].starts_with("Att strikes with Blade at Def — 6 hits"), "the strike line follows: {lines:?}");
        let capped = strike_lines(|s, st| { s[0].melee[0].blast = 3; st.alive[1] = 2; s[1].ctx.models = 2; }, vec![vec![4, 4, 1, 1, 1, 1]]);
        assert!(capped.iter().any(|l| l.starts_with("Blast(3): 2 hits ×2 (capped by 2 models in target) → 4 hits")), "{capped:?}");
    }

    /// Rending in melee names the hits on a 6 that go to AP(+4), once per weapon before the save (the table's `_solo_resolve_saves`). RED: no line.
    #[test]
    fn a_rending_strike_names_its_ap_on_sixes() {
        let lines = strike_lines(|s, _| s[0].melee[0].rending = true, vec![vec![6, 6, 4, 1, 1, 1]]);
        let at = lines.iter().position(|l| l.starts_with("Rending: 2 hits on a 6 → AP(+")).unwrap_or_else(|| panic!("{lines:?}"));
        assert!(lines[at - 1].starts_with("Att strikes with Blade at Def — 3 hits"), "after the strike line: {lines:?}");
        assert!(strike_lines(|_, _| {}, vec![vec![6, 6, 4, 1, 1, 1]]).iter().all(|l| !l.contains("on a 6")), "no Rending, no line");
    }

    /// A Shielded defender names its Defense bonus before the strikes in melee too (the table's `_solo_log_defense_parts`); a Defensive
    /// Growth defender names its own. RED: the melee strike says neither.
    #[test]
    fn a_shielded_defender_names_its_defense_bonus_in_melee() {
        let lines = strike_lines(|s, _| s[1].ctx.shielded = true, vec![]);
        assert_eq!(lines[0], "Def is Shielded: +1 Defense (saves on 3+)", "{lines:?}");
        let growth = strike_lines(|s, st| {
            s[1].growth = vec![GrowthRule { name: "Defensive Growth".into(), defense_per_two: 1, max_markers: 4, per_round: true, ..Default::default() }];
            st.growth_markers[1] = 2;
        }, vec![]);
        assert_eq!(growth[0], "Def is Defensive Growth: +1 Defense (saves on 3+)", "{growth:?}");
        assert!(strike_lines(|_, _| {}, vec![]).iter().all(|l| !l.contains(" is Shielded")), "no Shielded, no line");
    }

    /// A Deadly weapon's wounds land per model and say ONE Deadly line per weapon (with the dealt count and the weapon), not a "takes N wounds"
    /// line for them (the table's `_solo_land_deadly_wounds`). RED: the core said "Def takes 9 wounds" and no Deadly line.
    #[test]
    fn a_deadly_strike_says_its_deadly_line_instead_of_a_wound_line() {
        let deadly = |s: &mut [UnitStatic], st: &mut State| {
            s[0].melee[0].deadly = 3;
            s[1].wounds_max = vec![3; 5];
            st.wounds[1] = vec![3; 5];
            s[1].ctx.tough = 3;
        };
        let lines = strike_lines(deadly, vec![vec![4, 4, 4, 1, 1, 1], vec![1, 1, 1]]);
        let at = lines.iter().position(|l| l == "Deadly(3): 3 unsaved ×3, no carry-over → 9 wounds dealt (Blade)").unwrap_or_else(|| panic!("{lines:?}"));
        assert!(lines[at + 1..].iter().all(|l| !l.starts_with("Def takes 9 wound")), "the wounds were said by the Deadly line: {lines:?}");
        assert!(lines.iter().any(|l| l.starts_with("Def loses 3 models")), "the casualties are still said: {lines:?}");
    }

    /// A Surge weapon in melee names its bonus hits ("Surge: +N hits (unmodified 6s)"); a charging alias (Devout) names its charge gate first and
    /// a strike-back pays no alias at all (the table's `_solo_hits`). RED: the strike says neither line.
    #[test]
    fn a_surge_strike_names_its_bonus_hits_and_the_alias_gate() {
        let surge = |alias: &'static str| move |s: &mut [UnitStatic], _: &mut State| {
            let p = &mut s[0].melee[0];
            p.surge = true;
            if !alias.is_empty() {
                (p.surge_alias_rule, p.alias_gate) = (alias.into(), true);
            }
        };
        let plain = strike_lines(surge(""), vec![vec![6, 6, 4, 1, 1, 1]]);
        let at = plain.iter().position(|l| l == "Surge: +2 hits (unmodified 6s)").unwrap_or_else(|| panic!("{plain:?}"));
        assert!(plain[at + 1].starts_with("Att strikes with Blade at Def"), "before the strike line: {plain:?}");
        let alias = strike_lines(surge("Devout"), vec![vec![6, 6, 4, 1, 1, 1]]);
        let gate = alias.iter().position(|l| l == "Devout: charged from over 6\" — bonus hits on unmodified 6s").unwrap_or_else(|| panic!("{alias:?}"));
        assert_eq!(alias[gate + 1], "Surge: +2 hits (unmodified 6s)", "{alias:?}");
        assert!(strike_lines(|_, _| {}, vec![vec![6, 6, 4, 1, 1, 1]]).iter().all(|l| !l.starts_with("Surge")), "no Surge, no line");
    }

    /// A defender with no melee weapon at all says so on the step path too, with the book cite placeholder the door fills in (the table's
    /// `_solo_run_ai_melee`). RED: the line lives in the engine log only.
    #[test]
    fn a_defender_without_melee_weapons_says_it_cannot_strike_back() {
        let (mut statics, mut st) = two_unit_melee(3, 3, 1);
        statics[1].melee.clear();
        let mut tray = tray_with(vec![vec![4, 4, 1, 1, 1, 1]]);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, exact_seams(), &mut tray, &mut shot, 7.0, Cover::Recorded(None));
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert!(lines.iter().any(|l| l == "Def has no melee weapons — cannot strike back ({cite})"), "{lines:?}");
    }

    /// A bypass weapon (Rending / Bane) in melee at a target whose ignore group is not Regeneration names the wounds that joined that group's
    /// pool ONCE ("N wounds ignore only Regeneration - Self-Repair still rolls"); the melee leg used to count each such wound twice. Only the
    /// line moves (the count feeds no die). RED: the line says twice the unsaved wounds.
    #[test]
    fn a_bypass_strike_counts_the_wounds_that_join_the_pool_once() {
        let setup = |s: &mut [UnitStatic], _: &mut State| {
            s[0].melee[0].bypass_regen = true;
            let c = &mut s[1].ctx;
            c.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
            (c.regeneration, c.regen_named, c.regen_target) = (true, false, 6);
            (c.regen_groups, c.regen_names) = ([0, 6, 0, 0], ["", "self-repair", "", ""]);
        };
        let lines = strike_lines(setup, vec![vec![4, 4, 4, 4, 1, 1], vec![1, 1, 1, 1]]);
        assert!(lines.iter().any(|l| l == "Def: 4 wounds ignore only Regeneration — Self-Repair still rolls"), "{lines:?}");
    }

use super::*;
use super::rule_lines_defense::rule_lines;

    // ---- Door rule lines (lane dlines3): the attacker's rule lines in the table's words ----

    /// The Shred family names the rule that pays unmodified Defense 1s (plain Shred, a data alias, the Enhanced form), once per save batch,
    /// with the singular for one roll; the widened Boost window names its Boost and its distance gate; the announcement of the widening
    /// (or of the Enhanced form's "at any distance") comes once per volley before the first hit roll. RED: no Shred line at all.
    #[test]
    fn the_shred_family_names_its_pay_line_and_its_window() {
        let shred = |name: &'static str| move |_: &mut State, s: &mut [UnitStatic]| {
            let p = &mut s[0].shoot[0];
            (p.shred, p.shred_name) = (true, name.to_string());
        };
        let two = rule_lines(shred("Warbound"), vec![vec![6, 6, 6, 6], vec![1, 1, 5, 5]]);
        assert!(two.iter().any(|l| l == "Warbound: 2 Defense rolls of 1 → +2 wounds"), "{two:?}");
        let one = rule_lines(shred(""), vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(one.iter().any(|l| l == "Shred: 1 Defense roll of 1 → +1 wound"), "{one:?}");
        assert!(rule_lines(|_, _| {}, vec![vec![6, 6, 6, 6], vec![1, 1, 5, 5]]).iter().all(|l| !l.contains("Defense roll")), "no Shred, no line");
        let widened = rule_lines(|_, s| {
            let p = &mut s[0].shoot[0];
            (p.shred, p.shred_low, p.shred_over_in, p.shred_boost_name) = (true, 2, 9.0, "Warbound Boost".to_string());
        }, vec![vec![6, 6, 6, 6], vec![1, 2, 5, 5]]);
        let line = widened.iter().find(|l| l.starts_with("Warbound Boost: Shred on failed saves")).unwrap_or_else(|| panic!("{widened:?}"));
        assert_eq!(line, "Warbound Boost: Shred on failed saves of 1-2 (over 9\") — 2 extra wounds", "{widened:?}");
        let announced = rule_lines(|_, s| {
            let p = &mut s[0].shoot[0];
            (p.shred, p.shred_announce) = (true, Some(("Enhanced Warbound".to_string(), 2, false)));
        }, vec![vec![6, 6, 6, 6], vec![5, 5, 5, 5]]);
        let at = |t: &str| announced.iter().position(|l| l == t).unwrap_or_else(|| panic!("{t}: {announced:?}"));
        assert!(at("Enhanced Warbound: unmodified 1s to block deal an extra wound at any distance on Def") < at("Att fires Rifle at Def — 4 hits"), "{announced:?}");
    }

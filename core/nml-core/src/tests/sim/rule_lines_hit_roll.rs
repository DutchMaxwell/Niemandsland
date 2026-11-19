use super::*;
use super::volley_landings::volley_line;

    // ---- Door rule lines (lane dlines, PR 2): the hit roll's and AP's lines in the table's words ----

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

    /// The lines between the announce and the volley's hit line: what the weapon's hit roll adds (the table's `_solo_hits`).
    fn hit_roll_lines(tune: impl FnOnce(&mut ShootProfile), faces: Vec<u8>) -> Vec<String> {
        let lines = rule_lines(|_, s| tune(&mut s[0].shoot[0]), vec![faces, vec![1; 6]]);
        let end = lines.iter().position(|l| l.starts_with("Att fires Rifle at Def")).expect("the hit line");
        lines[1..end].to_vec()
    }

    /// Reliable says its Quality once per volley, before the roll (the table's `reliable_logged`). RED: drop the say.
    #[test]
    fn a_reliable_weapon_says_its_quality_before_the_roll() {
        let lines = rule_lines(|_, s| s[0].shoot[0].reliable = true, vec![vec![6, 1, 1, 1], vec![1]]);
        assert_eq!(lines[..2], ["Att fires at Def", "Reliable: Att shoots at Quality 2+"], "{lines:?}");
        assert_eq!(lines.iter().filter(|l| l.starts_with("Reliable")).count(), 1, "{lines:?}");
    }

    /// Precise / Imprecise and Relentless name their effect on the hit roll, Relentless only when a 6 paid.
    #[test]
    fn precise_imprecise_and_relentless_name_themselves() {
        assert_eq!(hit_roll_lines(|p| p.precise = true, vec![6, 1, 1, 1]), ["Precise: +1 to hit"]);
        assert_eq!(hit_roll_lines(|p| p.relentless = true, vec![6, 6, 3, 1]), ["Relentless: +2 hits (unmodified 6s)"]);
        assert_eq!(hit_roll_lines(|p| p.relentless = true, vec![6, 3, 1, 1]), ["Relentless: +1 hit (unmodified 6s)"]);
        assert!(hit_roll_lines(|p| p.relentless = true, vec![5, 3, 1, 1]).is_empty(), "no 6, no line");
    }

    /// A Surge alias names its gate and then the plain total; the plain 3.6 alias names no 9" band (the table's two lines).
    #[test]
    fn a_surge_alias_names_its_gate_and_the_bonus() {
        let alias = |p: &mut ShootProfile| { p.surge = true; p.surge_low = 6; p.surge_alias_rule = "Ferocious".into(); };
        assert_eq!(hit_roll_lines(alias, vec![6, 6, 3, 1]),
            ["Ferocious: shot from over 9\" — bonus hits on unmodified 6s", "Surge: +2 hits (unmodified 6s)"]);
        let plain = |p: &mut ShootProfile| { alias(p); p.alias_gate = true; p.surge_over_in = -1.0; };
        assert_eq!(hit_roll_lines(plain, vec![6, 3, 1, 1]), ["Ferocious: bonus hits on unmodified 6s", "Surge: +1 hit (unmodified 6s)"]);
        let none = hit_roll_lines(alias, vec![5, 3, 1, 1]);
        assert!(none.is_empty(), "no 6, no bonus, no line: {none:?}");
    }

    /// The AP-on-6 rules name the hits they upgraded before the save they roll (the table's `_solo_resolve_saves`): Rending by name,
    /// a book entry (Crack) by its own, one hit in the singular.
    #[test]
    fn an_ap_on_6_weapon_names_its_upgraded_hits() {
        let say = |tune: fn(&mut ShootProfile), faces: Vec<u8>| rule_lines(|_, s| tune(&mut s[0].shoot[0]), vec![faces, vec![1; 4]]);
        let rending = say(|p| p.rending = true, vec![6, 6, 3, 1]);
        let at = rending.iter().position(|l| l == "Rending: 2 hits on a 6 → AP(+4)").unwrap_or_else(|| panic!("{rending:?}"));
        assert_eq!(rending[at - 1], "Att fires Rifle at Def — 3 hits", "{rending:?}");
        let crack = say(|p| { p.on6_ap = 2; p.on6_rule = "Crack".into(); }, vec![6, 3, 1, 1]);
        assert!(crack.iter().any(|l| l == "Crack: 1 hit on a 6 → AP(+2)"), "{crack:?}");
        assert!(say(|p| p.rending = true, vec![5, 3, 1, 1]).iter().all(|l| !l.starts_with("Rending")), "no 6, no line");
    }

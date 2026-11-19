use super::*;
use super::volley_landings::volley_line;

    // ---- Door rule lines (lane dlines): the step path says the table's words for the rules a volley applies ----

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

    /// Blast(X) names itself on every volley that hits, capped or not, before the hit line (the table's `blast_log_text`).
    /// RED: drop the `say_rule` in the volley leg.
    #[test]
    fn a_blast_volley_says_its_multiplier_and_the_cap() {
        for (x, want) in [(3, "Blast(3): 3 hits ×2 (capped by 2 models in target) → 6 hits"), (2, "Blast(2): 3 hits ×2 → 6 hits")] {
            let lines = rule_lines(|_, s| s[0].shoot[0].blast = x, vec![vec![6, 6, 6, 1], vec![1; 6]]);
            let at = lines.iter().position(|l| l == want).unwrap_or_else(|| panic!("no {want:?} in {lines:?}"));
            assert_eq!(lines[at + 1], "Att fires Rifle at Def — 6 hits", "{lines:?}");
        }
    }

    /// Deadly(X): one line per weapon after its wounds landed (the table's `_solo_land_deadly_wounds`), with the weapon; the
    /// wounds it dealt are not also reported as "takes N wounds". Three unsaved wounds x3 on two Tough(3) models: two die, one is wasted.
    /// RED: drop the landing's `say_rule`, or let `land_chain_report` count the inline wounds.
    #[test]
    fn a_deadly_volley_says_what_it_dealt_and_nothing_else_about_the_wounds() {
        let lines = rule_lines(|_, s| s[0].shoot[0].deadly = 3, vec![vec![6, 6, 6, 1], vec![1; 3]]);
        let at = lines.iter().position(|l| l == "Deadly(3): 3 unsaved ×3, no carry-over → 6 wounds dealt (Rifle)").unwrap_or_else(|| panic!("{lines:?}"));
        assert_eq!(lines[at + 1], "Def loses 2 models (1/2)", "{lines:?}"); // (the host chain counts its joined hero)
        assert!(lines.iter().all(|l| !l.starts_with("Def takes")), "{lines:?}");
        let one = rule_lines(|_, s| s[0].shoot[0].deadly = 3, vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(one.iter().any(|l| l == "Deadly(3): 1 unsaved ×3, no carry-over → 3 wounds dealt (Rifle)"), "{one:?}");
        assert!(one.iter().any(|l| l == "Def loses a model (2/2)"), "{one:?}");
    }

    /// A Deadly wound that finishes a model already wounded says so once more (the table's second line, with the rules cite).
    #[test]
    fn a_deadly_wound_on_a_wounded_tough_model_names_it() {
        let tune = |st: &mut State, s: &mut [UnitStatic]| {
            s[0].shoot[0].deadly = 3;
            st.wounds[2] = vec![2, 3];
            let mut list = st.profiles.list.clone();
            list[2].wounds_max = vec![3, 3];
            st.profiles = Rc::new(Profiles { list, index: HashMap::new() });
        };
        let lines = rule_lines(tune, vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(lines.iter().any(|l| l == "Deadly(3): 1 unsaved ×3, no carry-over → 2 wounds dealt (Rifle)"), "{lines:?}");
        assert!(lines.iter().any(|l| l == "Deadly(3): 1 wound finish the already-wounded Tough model first ({cite})"), "{lines:?}");
    }

    /// The extra-attack form of the unmodified-6 family (Bloodborn et al.) says its dice after the roll (the table's `_solo_hits`).
    #[test]
    fn a_bloodborn_volley_says_its_extra_attacks() {
        let lines = rule_lines(|_, s| { s[0].shoot[0].surge_attack = true; s[0].shoot[0].surge_attack_rule = "Bloodborn".into(); },
            vec![vec![6, 6, 3, 1], vec![6, 1], vec![1; 4]]);
        let at = lines.iter().position(|l| l == "Bloodborn: 2 extra attacks from unmodified 6s — 1 hit").unwrap_or_else(|| panic!("{lines:?}"));
        assert_eq!(lines[at + 1], "Att fires Rifle at Def — 4 hits", "{lines:?}");
    }

    /// "Ambushing Piercing Shot" names itself once per member in its arrival round, before the announce; a unit that did not
    /// arrive this round says nothing.
    #[test]
    fn an_ambushing_member_names_its_arrival_ap_before_the_announce() {
        let arrived = |st: &mut State, s: &mut [UnitStatic]| {
            st.ambush_arrived_round[0] = st.round;
            s[0].ambush_family.deploy_round_ap = 1;
        };
        let lines = rule_lines(arrived, vec![vec![6, 1, 1, 1], vec![1]]);
        assert_eq!(lines[..2], ["Ambushing Piercing Shot: Att shoots with AP(+1) in its arrival round", "Att fires at Def"], "{lines:?}");
        let other_round = rule_lines(|st, s| { arrived(st, s); st.ambush_arrived_round[0] = st.round - 1; }, vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(other_round.iter().all(|l| !l.starts_with("Ambushing")), "{other_round:?}");
    }

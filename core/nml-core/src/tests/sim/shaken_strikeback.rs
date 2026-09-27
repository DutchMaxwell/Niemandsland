use super::*;
use crate::acts::{EPOCH_64_DEPLOY_LARGE_RESPOT, EPOCH_65_MELEE_TRUTH};

    /// Wave 3 S1-02 — GF/AoF v3.5.1 p.10 SHAKEN UNITS: "Shaken units must stay
    /// idle, but may strike back counting as fatigued". A Shaken Q4 defender
    /// charged by a plain unit: its strike-back hit roll is the fatigued one
    /// (unmodified 6s) from `EPOCH_65_MELEE_TRUTH`, its full Quality below.
    fn shaken_defender_strike_back_target(rules_epoch: u32) -> i64 {
        let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
        let blade = |n: &str| ShootProfile { name: n.into(), attacks: 1, count: 1, range: 0, ..Default::default() };
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Charger".into(),
                melee: vec![blade("Blade")],
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
                name: "Defender".into(),
                melee: vec![blade("Club")],
                model_count: 3,
                wounds_max: vec![1; 3],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![1, 3];
        st.shaken = vec![false, true];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = vec![[IN2M, 0.0, 0.0]];
        st.wounds[0] = vec![1];
        st.radii[0] = vec![IN2M];
        st.positions[1] = vec![[0.0, 0.0, 0.0]; 3];
        st.wounds[1] = vec![1; 3];
        st.radii[1] = vec![IN2M; 3];

        let seams = Seams { rules_epoch, ..Default::default() };
        let mut tray = Tray::seeded(27);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
        let back = shot
            .rolls
            .iter()
            .find(|r| r.kind == "attack" && r.owner == "Defender")
            .expect("the Shaken defender still strikes back (p.10: it may)");
        back.target
    }

    #[test]
    fn a_shaken_defender_strikes_back_counting_as_fatigued_from_epoch_65() {
        assert_eq!(
            shaken_defender_strike_back_target(EPOCH_65_MELEE_TRUTH),
            6,
            "S1-02: a Shaken unit strikes back counting as fatigued — unmodified 6s only"
        );
    }

    #[test]
    fn below_epoch_65_a_shaken_defender_strikes_back_at_full_quality() {
        assert_eq!(
            shaken_defender_strike_back_target(EPOCH_64_DEPLOY_LARGE_RESPOT),
            4,
            "the old leg replays byte-exact: Quality 4+ below the gate"
        );
    }

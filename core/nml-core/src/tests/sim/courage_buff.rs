use super::*;

use crate::rules::Registries;

    // ---- STANDALONE_SWEEP_E_2026-09-14, row `Courage Buff` (ledger
    //      proven_vs_read.tsv line 104, proof_kind "none"): the morale mod —
    //      the registry entry `{morale_mod: 1, range_in: 12, target: friendly,
    //      once: true}` rides the Utility-Buff stamp (unit.rs) and the record
    //      joins the morale test's [2,6]-clamped target via `tray_morale`
    //      (sim.rs). -------

    /// The checkout this crate lives in — mirrors the dice tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The buff carrier's REAL profile: gf/blessed_sisters fields
    /// "Courage Buff" as a friendly Utility Buff with the printed +1.
    fn courage_carrier() -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "Banner".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Courage Buff".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "blessed_sisters".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH)
    }

    /// The buff_line with the bearer slot swapped for the REAL stamp (the
    /// boost_line shape) and the state trimmed to the carrier's own model.
    fn courage_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        statics[0] = courage_carrier();
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.radii[0] = vec![IN2M];
        st.wounds[0] = vec![1];
        st.alive[0] = 1;
        (st, statics)
    }

    /// THE NUMBER: the exact name carries the printed +1 — stamped on the
    /// unit, recorded on the friendly pick (the bearer itself, best value in
    /// range), and the next morale test rolls at Quality 4+ -> 3+ under it,
    /// spent by that test die ("once").
    #[test]
    fn courage_buff_records_plus_one_on_its_side_and_eases_the_morale_test() {
        let (st, statics) = courage_line();
        let ub = &statics[0].utility_buffs;
        assert_eq!(ub.len(), 1, "one Utility Buff stamped: {:?}", ub);
        assert_eq!(
            (ub[0].name.as_str(), ub[0].morale_mod, ub[0].range_in, ub[0].target.as_str(), ub[0].once),
            ("Courage Buff", 1, 12.0, "friendly", true),
            "the registry entry's own params, read by the rule's exact name"
        );
        let (mut next, shot) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(shot.rolls.is_empty(), "the buff arm is dice-free");
        assert_eq!(next.buffs[0].len(), 1, "the friendly pick (the bearer itself) carries the record");
        assert_eq!(next.buffs[0][0].morale_mod, 1);
        let mut tray = Tray::seeded(5);
        let mut mshot = ShootResult::default();
        tray_morale(
            &mut next, &statics[0], 0, false, crate::acts::CURRENT_RULES_EPOCH,
            &mut tray, &mut mshot,
        );
        assert_eq!(mshot.rolls[0].target, 3, "Quality 4+ tested at 3+ under the +1");
        assert!(next.buffs[0].is_empty(), "the test die spends the once-record");
    }

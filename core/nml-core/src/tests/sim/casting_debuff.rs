use super::*;

use crate::rules::Registries;

    // ---- STANDALONE_SWEEP_E_2026-09-14, row `Casting Debuff` (ledger
    //      proven_vs_read.tsv line 100, proof_kind "none"): the casting mod —
    //      the registry entry `{casting_mod: -1, range_in: 18, target: enemy,
    //      needs_los: true}` rides the Utility-Buff stamp (unit.rs) and the
    //      record sums into the enemy caster's net via `casting_net_of`
    //      (sim.rs, the EPOCH_6 gate). -------

    /// The checkout this crate lives in — mirrors the dice tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The debuff carrier's REAL profile: gf/blessed_sisters fields
    /// "Casting Debuff" as a Utility Buff with the printed -1.
    fn debuff_carrier() -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "Hexer".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Casting Debuff".into()],
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
    fn debuff_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        statics[0] = debuff_carrier();
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.radii[0] = vec![IN2M];
        st.wounds[0] = vec![1];
        st.alive[0] = 1;
        (st, statics)
    }

    /// THE NUMBER: the exact name carries the printed -1 — stamped on the
    /// unit, recorded on the enemy pick by the pre-attack buff arm, and summed
    /// into the enemy's casting net at the current epoch (zero below the
    /// EPOCH_6 gate, the corpus replay reading).
    #[test]
    fn casting_debuff_records_minus_one_on_the_enemy_and_lowers_the_cast_net() {
        let (st, statics) = debuff_line();
        let ub = &statics[0].utility_buffs;
        assert_eq!(ub.len(), 1, "one Utility Buff stamped: {:?}", ub);
        assert_eq!(
            (ub[0].name.as_str(), ub[0].casting_mod, ub[0].range_in, ub[0].target.as_str()),
            ("Casting Debuff", -1, 18.0, "enemy"),
            "the registry entry's own params, read by the rule's exact name"
        );
        let (next, shot) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(shot.rolls.is_empty(), "the buff arm is dice-free");
        assert_eq!(next.buffs[2].len(), 1, "the enemy pick carries the record");
        assert_eq!(next.buffs[2][0].casting_mod, -1);
        let seams =
            Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        assert_eq!(
            casting_net_of(&statics, &next, 2, seams),
            -1,
            "the debuff sums into the enemy caster's casting net"
        );
        let old =
            Seams { rules_epoch: crate::acts::EPOCH_6_TABLE_RULES - 1, ..Seams::default() };
        assert_eq!(casting_net_of(&statics, &next, 2, old), 0, "below the gate the net is the flat zero");
    }

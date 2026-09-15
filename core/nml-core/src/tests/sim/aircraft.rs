use super::*;

use crate::rules::Registries;

    // ---- STANDALONE_SWEEP_E_2026-09-14, row `Aircraft` (ledger
    //      proven_vs_read.tsv line 84, proof_kind "none"): the targeting/bands
    //      read — `unit_rule_active(reg, p, "Aircraft")` stamps the flag
    //      (unit.rs), the flag feeds the -12" target range penalty
    //      (`sight_reach_in`, sim.rs) and the cannot-be-charged gate
    //      (gate.rs). -------

    /// The checkout this crate lives in — mirrors the dice tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// A single-model unit's REAL capture read: gf carries "Aircraft" in its
    /// COMMON map (`target_range_penalty_in: 12`, `cannot_be_charged`,
    /// `cannot_seize`), so an empty faction folder resolves it
    /// (`RulesMap.lookup` falls through to common). The stamp answers through
    /// `capture_reads_for_epoch` — the same read the capture writes into the
    /// state's `aircraft` flags.
    fn flyer_stamp(special_rules: Vec<String>) -> bool {
        let p = Profile {
            unit_id: "b".into(),
            name: "Flyer".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules,
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = Registries::new(&repo_root());
        crate::unit::capture_reads_for_epoch(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH)
            .aircraft
    }

    /// THE STAMP: the exact name "Aircraft" is what flips the flag — and a
    /// unit without the name stays ground-bound.
    #[test]
    fn the_aircraft_stamp_answers_the_exact_name_through_the_registry() {
        assert!(flyer_stamp(vec!["Aircraft".into()]), "Aircraft stamps the flag");
        assert!(!flyer_stamp(vec![]), "a plain unit stays ground-bound");
    }

    /// THE NUMBER: `target_range_penalty_in` = 12 — a 24" weapon reaches
    /// 24 - 12 = 12" against an Aircraft target and loses nothing against a
    /// ground one (SoloController.AIRCRAFT_TARGET_RANGE_PENALTY_IN).
    #[test]
    fn an_aircraft_target_shrinks_a_24_inch_weapons_reach_to_12_inch() {
        let air = flyer_stamp(vec!["Aircraft".into()]);
        assert!(air, "setup: the stamp fired");
        assert_eq!(
            sight_reach_in(24.0, air, &Ctx::default()),
            12.0,
            "the STAMPED flag rides the -12\" penalty"
        );
        assert_eq!(
            sight_reach_in(24.0, false, &Ctx::default()),
            24.0,
            "the control: a ground target loses nothing"
        );
    }

    /// cannot_be_charged: the charge gate refuses an aircraft victim outright,
    /// whatever the gap — the same geometry is legal against a ground unit.
    /// The state flag is the capture's write of the stamp above.
    #[test]
    fn an_aircraft_cannot_be_charged() {
        let mut st = four_unit_line();
        let t = crate::terrain::Terrain::default();
        st.aircraft[2] = true;
        let statics: Vec<UnitStatic> = (0..4).map(|_| UnitStatic::default()).collect();
        assert!(
            crate::gate::charge_illegal(&st, &statics, &t, 0, 2, 5.0, None, None),
            "the gate refuses the aircraft at a 5\" gap"
        );
        st.aircraft[2] = false;
        assert!(
            !crate::gate::charge_illegal(&st, &statics, &t, 0, 2, 5.0, None, None),
            "the same 5\" gap is legal against a ground unit"
        );
    }

    /// cannot_seize: the referee's marker-eligibility read drops an Aircraft
    /// outright — the same marker is holdable for the ground twin. The
    /// `cannot_seize` param of the gf Aircraft entry, keyed by the stamped
    /// flag (`score::can_hold_marker`, battle_sim.gd:297-302 — the read
    /// mission.rs awards markers through).
    #[test]
    fn an_aircraft_cannot_seize_a_marker() {
        let mut st = four_unit_line();
        st.aircraft[2] = true;
        assert!(
            !crate::score::can_hold_marker(&st, 2, 0),
            "the Aircraft never holds or seizes a marker"
        );
        st.aircraft[2] = false;
        assert!(
            crate::score::can_hold_marker(&st, 2, 0),
            "the ground twin holds the very same marker"
        );
    }

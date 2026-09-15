use super::*;
    use crate::state::{Bands, Mods, MoveBands, Profile, Profiles, Roster};
    use std::collections::HashMap;
    use std::rc::Rc;

    // ---- STANDALONE_SWEEP_A_2026-09-14, row `Immobile` (ledger
    //      proven_vs_read.tsv line 25, proof_kind "none"): the hold-only
    //      ACTION MENU — `forces_hold` keys the exact name (menu.rs:158) and
    //      the menu for a carrier ends after its two holds (menu.rs:739), so
    //      no RUSH/CHARGE/ADVANCE is ever offered. -------

    /// A two-unit state: unit 0 the carrier (the caller's rules), unit 1 an
    /// enemy 8" down the line. The `units_state` shape of the mv tests,
    /// trimmed to what the menu reads.
    fn hold_line(carrier_rules: &[&str]) -> State {
        let n = 2;
        let carrier = Profile {
            unit_id: "u".into(),
            name: "Holder".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![],
            model_count: 1,
            weapons: vec![],
            special_rules: carrier_rules.iter().map(|s| s.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: String::new(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut foe = carrier.clone();
        foe.unit_id = "f".into();
        foe.name = "Foe".into();
        foe.special_rules = vec![];
        let profiles = Rc::new(Profiles { list: vec![carrier, foe], index: HashMap::new() });
        let roster = Rc::new(Roster {
            keys: vec!["u0".into(), "u1".into()],
            index: HashMap::new(),
            profile: vec![0, 1],
        });
        let attached: Vec<Vec<usize>> = vec![vec![], vec![]];
        let mut attached_to = vec![None; n];
        for (host, hs) in attached.iter().enumerate() {
            for &h in hs {
                attached_to[h] = Some(host);
            }
        }
        State {
            roster,
            profiles,
            round: 0,
            rounds_total: 1,
            scoring: Rc::from(""),
            objectives: vec![],
            markers_meta: vec![],
            destroy_seq: vec![],
            vp: None,
            vp_flavour: None,
            vp_memo: None,
            cast_events: vec![],
            player: vec![0, 1],
            alive: vec![1; n],
            activated: vec![false; n],
            shaken: vec![false; n],
            fatigued: vec![false; n],
            in_cover: vec![false; n],
            aircraft: vec![false; n],
            dormant: vec![false; n],
            dormant_models: vec![0; n],
            dormant_wounds: vec![Vec::new(); n],
            casts: vec![0; n],
            morale_bonus: vec![0; n],
            ambush_arrived_round: vec![-1; n],
            earliest_arrival_round: vec![-1; n],
            wound_frac: vec![1.0; n],
            wounds: vec![vec![1], vec![1]],
            positions: vec![vec![[0.0, 0.0, 0.0]], vec![[8.0 * IN2M, 0.0, 0.0]]],
            radii: vec![vec![IN2M], vec![IN2M]],
            mods: vec![Mods::default(); n],
            mods_base: (0..n).map(|_| Rc::new(Mods::default())).collect(),
            attached: Rc::new(attached),
            attached_to: Rc::new(attached_to),
            los: vec![None; n],
            los_pairs: None,
            bands: vec![Bands::default(); n],
            shroud: vec![None; n],
            charge_no_difficult: vec![false; n],
            charge_probe_r: vec![0.0; n],
            buffs: (0..n).map(|_| Vec::new()).collect(),
            vs_mark_round: vec![-1; n],
            hit_and_run_round: vec![-1; n],
            moved_round: vec![-1; n],
            delayed_action_round: vec![-1; n],
            coordinate_via_round: vec![-1; n],
            reckless_rolled_round: vec![-1; n],
            reckless_ap_round: vec![-1; n],
            reckless_backfire_round: vec![-1; n],
            versatile_pick_round: vec![-1; n],
            versatile_pick_mode: vec![0; n],
            retreating_strike_round: vec![-1; n],
            growth_markers: vec![0; n],
            vengeance_markers: vec![0; n],
            growth_round: vec![-1; n],
            second_wind_used: vec![false; n], teleport_used: vec![false; n],
            reinforcement_used: vec![false; n],
            second_wind_round: -1,
            second_wind_uses: 0,
            sidestep_budget: Default::default(),
            limited_used: vec![Vec::new(); n],
            piercing_tag_used: vec![false; n],
            piercing_tag_markers: vec![0; n],
            spot_markers: vec![0; n],
            tag_markers: vec![0; n],
            spot_round: vec![-1; n],
            precision_used: vec![Vec::new(); n],
            storm_used: vec![Vec::new(); n],
            feats_used: vec![Vec::new(); n],
        }
    }

    /// One static per state unit, named like the fixture's own two slots.
    fn menu_statics() -> Vec<UnitStatic> {
        vec![
            UnitStatic {
                ctx: crate::unit::Ctx {
                    quality: 4, defense: 4, tough: 1, models: 1, ..Default::default()
                },
                name: "Holder".into(),
                model_count: 1,
                ..Default::default()
            },
            UnitStatic {
                ctx: crate::unit::Ctx {
                    quality: 4, defense: 4, tough: 1, models: 1, ..Default::default()
                },
                name: "Foe".into(),
                model_count: 1,
                ..Default::default()
            },
        ]
    }

    /// THE NAME READ: `forces_hold` keys "Immobile" (and "Artillery") after a
    /// trim — and nothing else.
    #[test]
    fn forces_hold_keys_the_exact_names() {
        assert!(forces_hold(&["Immobile".to_string()]));
        assert!(forces_hold(&[" Artillery".to_string()]), "the read trims before it matches");
        assert!(!forces_hold(&["Ethereal".to_string()]), "a near-neighbour name must not match");
    }

    /// THE MENU: an Immobile carrier's candidates end after the holds — no
    /// RUSH, no CHARGE, no ADVANCE is ever offered (p.13: Hold actions only).
    #[test]
    fn an_immobile_carriers_menu_ends_after_the_holds() {
        let st = hold_line(&["Immobile"]);
        let statics = menu_statics();
        let mut sc = Scratch::default();
        let menu = candidates_tuned(
            &st, &Terrain::default(), &statics, 0, &mut sc, Tuning::default(),
        );
        assert!(
            menu.iter().all(|c| c.kind == HOLD),
            "Immobile may only Hold — the menu must end after its holds: {:?}",
            menu
        );
    }

    /// The control: the same line WITHOUT the rule offers a move, so the
    /// hold-only leg above is not vacuous.
    #[test]
    fn the_same_line_without_the_rule_offers_a_move() {
        let st = hold_line(&[]);
        let statics = menu_statics();
        let mut sc = Scratch::default();
        let menu = candidates_tuned(
            &st, &Terrain::default(), &statics, 0, &mut sc, Tuning::default(),
        );
        assert!(
            menu.iter().any(|c| c.kind != HOLD),
            "the control must offer a move: {:?}",
            menu
        );
    }

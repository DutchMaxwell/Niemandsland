use super::*;

    // ---- family 6 — the gap math prices the terrain debuffs a unit CARRIES
    // (`mods::granted_terrain_debuff`, EPOCH_27_TERRAIN_DEBUFF): the carried
    // "Difficult Terrain" caps the priced bands exactly where
    // `mv::step::execute` caps the real move (`reach = band_in.min(6")`,
    // mv/step.rs:691), and the carried "Dangerous Terrain" rides the
    // `dangerous_dice` expectation (one max(1, wounds_max) die per alive
    // mover, wound on a 1 → dice/6) into `best_charge`'s EV. ----

    /// One live grant overlay row — the `ev_move_grants.rs` fixture's own
    /// shape; the debuff reads are name-only (`mods::granted`), so the row
    /// needs nothing but the granted rule's name.
    fn grant_row(rule: &str) -> mods::LiveMod {
        mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0,
            ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 0,
            grants_rule: Rc::from(rule),
            scope: Rc::from(""),
            attackers: false,
            once: false,
            name: Rc::from(""),
        }
    }

    /// The mover's book: an aof profile whose faction entry fields the
    /// printed band params (the `ev_move_grants.rs` fixture's shape), with
    /// the melee attacks a knob so the dangerous twin can park its raw EV
    /// between the futile bar and the bar plus the loss.
    fn bearer_profile(faction: &str, attacks: i64) -> Profile {
        Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![crate::state::Weapon {
                name: "Fist".into(),
                range: 0.0,
                attacks,
                count: 1,
                ap: 0,
                rules: vec![],
            }],
            special_rules: vec![],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        }
    }

    /// A + B: two IDENTICAL single-model units on side 0 — A (unit 0) carries
    /// the terrain debuff records, B (unit 1) does not. E1/E2 are enemies
    /// parked so the base-edge gap to each side's own mover is exactly
    /// `gap_in` while neither enemy is anywhere near the OTHER mover's gate
    /// range — only the DEBUFF may split the verdicts. Fresh-game fixture:
    /// the statics are built at CURRENT_RULES_EPOCH, never a stamped number.
    fn carried_pair(
        faction: &str, rules: &[&str], gap_in: f64, attacks: i64,
    ) -> (State, Vec<UnitStatic>) {
        let p = bearer_profile(faction, attacks);
        let mut reg = crate::rules::Registries::new(&repo_root());
        // Two builds off the SAME profile+registry: identical stamps, and
        // `UnitStatic` carries no Clone for a reason (its fields are stamped).
        let bearer_a = UnitStatic::build_for(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH);
        let bearer_b = UnitStatic::build_for(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH);
        let enemy_ctx = Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() };
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into(), "e1".into(), "e2".into()],
            index: ["a", "b", "e1", "e2"]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.to_string(), i))
                .collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.profiles = Rc::new(Profiles {
            list: vec![p.clone(), p.clone(), p.clone(), p],
            index: HashMap::new(),
        });
        // The line fixture joins B into A — the grant chain would hand A's
        // debuff to B. Both movers stand alone, exactly the brief's pair.
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None; 4]);
        // A at 0", E1 a `gap_in` edge gap ahead; B at 40", E2 mirrored. B's
        // distance to E1 (and A's to E2) stays far past every band under test.
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![[40.0 * IN2M, 0.0, 0.0]],
            vec![[(gap_in + 2.0) * IN2M, 0.0, 0.0]],
            vec![[(gap_in + 42.0) * IN2M, 0.0, 0.0]],
        ];
        st.buffs[0] = rules.iter().map(|r| grant_row(r)).collect();
        (
            st,
            vec![
                bearer_a,
                bearer_b,
                UnitStatic { name: "e1".into(), ctx: enemy_ctx, model_count: 1, wounds_max: vec![1], ..Default::default() },
                UnitStatic { name: "e2".into(), ctx: enemy_ctx, model_count: 1, wounds_max: vec![1], ..Default::default() },
            ],
        )
    }

    /// The Difficult twin: A carries the debuff, B does not, otherwise
    /// identical. A's band read is capped at the p.11 6"
    /// (`gate::DIFFICULT_MOVE_CAP_IN`) on both axes — the seam the gate's
    /// charge band, the menu's charge leg and the playout's rush demotion all
    /// read — so A refuses a 10" gap and its best-charge leg never enters,
    /// while the bare twin takes both.
    #[test]
    fn a_carried_difficult_debuff_caps_every_band_read() {
        let (st, statics) = carried_pair("ogres", &["Difficult Terrain"], 10.0, 4);
        let t = crate::terrain::Terrain::default();
        assert_eq!(
            crate::sim::live_bands_of(&statics, &st, 0),
            (6.0, 6.0),
            "the debuffed unit's advance and rush both cap at the p.11 6\""
        );
        assert_eq!(
            crate::sim::live_bands_of(&statics, &st, 1),
            (6.0, 12.0),
            "the bare twin keeps its printed bands"
        );
        assert!(
            crate::gate::charge_illegal_tuned(&st, &statics, &t, 0, 2, 10.0, None, None, true),
            "the capped 6\" charge band cannot cover the 10\" gap"
        );
        assert!(
            !crate::gate::charge_illegal_tuned(&st, &statics, &t, 1, 3, 10.0, None, None, true),
            "the bare twin's printed 12\" band covers the same gap"
        );
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 0, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            None,
            "the debuffed unit's charge on e1 never enters the menu"
        );
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 1, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            Some(3),
            "the bare twin takes the same 10\" gap"
        );
    }

    /// The Dangerous twin: the dice the charge's own move will roll price
    /// into `best_charge`'s EV. One model, tough 1 → one die, wound on a 1 →
    /// the loss is 1/6. The single-attack Fist's charging EV (hit 4-or-3+,
    /// wound 4+) lands between the 0.2 futile bar and the bar plus that
    /// loss, so the bare twin's charge enters and the debuffed twin's priced
    /// EV drops under the bar: the only decision a per-unit constant can
    /// move. The bands themselves stay untouched — dangerous never caps.
    #[test]
    fn a_carried_dangerous_debuff_lowers_the_priced_charge_ev() {
        let (st, statics) = carried_pair("ogres", &["Dangerous Terrain"], 2.0, 1);
        let t = crate::terrain::Terrain::default();
        assert_eq!(
            crate::sim::live_bands_of(&statics, &st, 0),
            (6.0, 12.0),
            "dangerous never touches the band read — only the charge EV"
        );
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 0, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            None,
            "the raw EV minus the dice/6 loss drops under the futile bar"
        );
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 1, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            Some(3),
            "the bare twin's raw EV clears the bar unchanged"
        );
    }

use super::*;

    // ---- evmove — the evaluator's band reads fold the live solo move grants.
    // Family 1 of EV_GRANT_BLINDNESS_2026-09-15 (`solo_move_grant_delta_in`,
    // EPOCH_19_MOVE_GRANTS_FOLD): a unit granted Fast/Slow/Swift/Rapid
    // Advance/Rapid Rush moves with the delta in the real move, but the gate's
    // charge band, the net tokens' band columns and the menu's charge leg all
    // priced the UNGRANTED band. ----

    /// One live grant overlay row — the `move_grants.rs` fixture's own shape.
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

    /// The mover's book: an aof profile whose faction entry fields the granted
    /// name's band params (the `move_grants.rs` fixture's shape), plus a plain
    /// Fist so the charge leg's melee EV clears the futile bar.
    fn bearer_profile(faction: &str) -> Profile {
        Profile {
            cost: 0,
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
                attacks: 4,
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
    /// the live grant, B (unit 1) does not. E1/E2 are enemies parked so the
    /// base-edge gap to each side's own mover is exactly `gap_in` (the 1"
    /// radii come off the line fixture) while neither enemy is anywhere near
    /// the OTHER mover's gate range — only the GRANT may split the verdicts.
    /// Fresh-game fixture: the statics are built at CURRENT_RULES_EPOCH, never
    /// a stamped number.
    fn granted_pair(faction: &str, grants: &[&str], gap_in: f64) -> (State, Vec<UnitStatic>) {
        granted_pair_at(faction, grants, gap_in, crate::acts::CURRENT_RULES_EPOCH)
    }

    fn granted_pair_at(
        faction: &str, grants: &[&str], gap_in: f64, rules_epoch: u32,
    ) -> (State, Vec<UnitStatic>) {
        let p = bearer_profile(faction);
        let mut reg = crate::rules::Registries::new(&repo_root());
        // Two builds off the SAME profile+registry: identical stamps, and
        // `UnitStatic` carries no Clone for a reason (its fields are stamped).
        let bearer_a = UnitStatic::build_for(&mut reg, &p, rules_epoch);
        let bearer_b = UnitStatic::build_for(&mut reg, &p, rules_epoch);
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
        // Fast to B. Both movers stand alone, exactly the brief's pair.
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
        st.buffs[0] = grants.iter().map(|g| grant_row(g)).collect();
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

    fn token_band_columns(st: &State, statics: &[UnitStatic]) -> ([f32; crate::tokens::F_U], [f32; crate::tokens::F_U]) {
        let terrain = crate::terrain::Terrain::default();
        let mut enc = crate::rows::RowEncoder::new(&repo_root());
        let t = crate::tokens::build(st, 0, statics, &terrain, &mut enc, &[], -1, false, false,
            crate::acts::CURRENT_RULES_EPOCH).unwrap();
        (t.units[0], t.units[1])
    }

    /// (a) The gate's charge band folds the live grant: A (granted Fast) is
    /// legal at the 13" edge gap its 12+4 band covers, B (bare) is not.
    /// rules_mechanics_aof.json, common "Fast": advance_mod 2, rush_mod 4.
    #[test]
    fn a_live_fast_grant_widens_the_gate_s_charge_band() {
        let (st, statics) = granted_pair("ogres", &["Fast"], 13.0);
        let t = crate::terrain::Terrain::default();
        assert!(
            !crate::gate::charge_illegal_tuned(&st, &statics, &t, 0, 2, 13.0, None, None, true),
            "the granted Fast rides +4\" on the charge band: 16\" covers the 13\" gap"
        );
        assert!(
            crate::gate::charge_illegal_tuned(&st, &statics, &t, 1, 3, 13.0, None, None, true),
            "the ungranted twin still prices its printed 12\" band"
        );
    }

    /// (b) The token band columns fold the same grant — A's advance and rush
    /// slots read the granted bands, B's the printed ones.
    #[test]
    fn a_live_fast_grant_widens_the_token_band_columns() {
        let (st, statics) = granted_pair("ogres", &["Fast"], 13.0);
        let (a, b) = token_band_columns(&st, &statics);
        assert!(a[28] > b[28], "advance column: granted {} vs bare {}", a[28], b[28]);
        assert!(a[29] > b[29], "rush column: granted {} vs bare {}", a[29], b[29]);
    }

    /// (c) The menu's charge leg reaches a target for A that B cannot: the
    /// gate inside `best_charge` admits A's 16" band at 13", refuses B's 12".
    #[test]
    fn the_menu_s_charge_leg_reaches_a_target_for_the_granted_unit_only() {
        let (st, statics) = granted_pair("ogres", &["Fast"], 13.0);
        let t = crate::terrain::Terrain::default();
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 0, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            Some(2),
            "the granted unit's charge on e1 enters the menu"
        );
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 1, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            None,
            "the ungranted twin cannot reach either enemy"
        );
    }

    /// The Slow mirror (shorter): the granted unit's bands SHRINK — the gate
    /// refuses a gap the bare twin takes, the token columns read lower, and
    /// the menu's charge leg inverts. rules_mechanics_aof.json, common "Slow":
    /// advance_mod -2, rush_mod -4.
    #[test]
    fn a_live_slow_grant_shrinks_every_band_read() {
        let (st, statics) = granted_pair("dwarves", &["Slow"], 10.0);
        let t = crate::terrain::Terrain::default();
        assert!(
            crate::gate::charge_illegal_tuned(&st, &statics, &t, 0, 2, 10.0, None, None, true),
            "the granted Slow rides -4\" on the charge band: 8\" cannot cover 10\""
        );
        assert!(
            !crate::gate::charge_illegal_tuned(&st, &statics, &t, 1, 3, 10.0, None, None, true),
            "the ungranted twin still covers 10\" with its printed 12\" band"
        );
        let (a, b) = token_band_columns(&st, &statics);
        assert!(a[28] < b[28], "advance column: slowed {} vs bare {}", a[28], b[28]);
        assert!(a[29] < b[29], "rush column: slowed {} vs bare {}", a[29], b[29]);
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 0, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            None,
            "the slowed unit's 8\" band cannot reach the 10\" target"
        );
        assert_eq!(
            crate::menu::best_charge(&st, &t, &statics, 1, &mut Scratch::default(), crate::menu::Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None),
            Some(3),
            "the ungranted twin takes the same 10\" gap"
        );
    }

    /// The seam itself: A's pair is printed + the granted delta, B's the
    /// printed band — in one state, off identical statics.
    #[test]
    fn live_bands_of_answers_printed_plus_the_granted_delta() {
        let (st, statics) = granted_pair("ogres", &["Fast"], 13.0);
        assert_eq!(crate::sim::live_bands_of(&statics, &st, 0), (8.0, 16.0));
        assert_eq!(crate::sim::live_bands_of(&statics, &st, 1), (6.0, 12.0));
        let (st, statics) = granted_pair("dwarves", &["Slow"], 10.0);
        assert_eq!(crate::sim::live_bands_of(&statics, &st, 0), (4.0, 8.0));
        assert_eq!(crate::sim::live_bands_of(&statics, &st, 1), (6.0, 12.0));
    }

    /// The replay-safety leg — the EV twin of `move_grants.rs`'s epoch gate:
    /// a fixture whose statics are built BELOW the fold reads the printed
    /// bands through the same helper, grant or no grant (the stamp is None).
    #[test]
    fn a_pre_fold_fixture_reads_printed_bands_through_the_seam() {
        let (st, statics) = granted_pair_at("ogres", &["Fast"], 13.0, 18);
        assert_eq!(
            crate::sim::live_bands_of(&statics, &st, 0),
            (6.0, 12.0),
            "an epoch-18 fixture replays at the printed band"
        );
        assert_eq!(crate::sim::live_bands_of(&statics, &st, 1), (6.0, 12.0));
    }

    // ---- differential: the no-grants shortcut of `live_bands_of` equals the full body ----

    /// One scenario for the differential: a chain layout and the records on it.
    struct BandsCase {
        what: &'static str,
        faction: &'static str,
        rules_epoch: u32,
        /// (unit, grants_rule, attackers, move_mod)
        records: Vec<(usize, &'static str, bool, i64)>,
        /// unit 1 joined into unit 0 (host 0, attached hero 1)
        joined: bool,
        /// band values written to unit 0, to exercise the `x + 0.0` bit pattern
        band0: Option<(f64, f64)>,
    }

    fn bands_case(
        what: &'static str, faction: &'static str, records: Vec<(usize, &'static str, bool, i64)>,
    ) -> BandsCase {
        BandsCase { what, faction, rules_epoch: crate::acts::CURRENT_RULES_EPOCH, records, joined: false, band0: None }
    }

    /// Both bodies on every unit of the state: the pair must agree bit for bit (`to_bits`, so -0.0 vs +0.0
    /// and NaN payloads count). Returns how many units took the grant-free shortcut.
    fn assert_bands_equal(c: &BandsCase) -> usize {
        let (mut st, statics) = granted_pair_at(c.faction, &[], 13.0, c.rules_epoch);
        if c.joined {
            st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
            st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        }
        if let Some((a, r)) = c.band0 {
            st.bands[0].advance = a;
            st.bands[0].rush = r;
        }
        for &(u, rule, attackers, mv) in &c.records {
            let mut row = grant_row(rule);
            row.attackers = attackers;
            row.move_mod = mv;
            st.buffs[u].push(row);
        }
        let mut shortcut = 0;
        for i in 0..4 {
            let fast = crate::sim::live_bands_of(&statics, &st, i);
            let full = crate::sim::live_bands_walk(&statics, &st, i);
            assert_eq!(
                (fast.0.to_bits(), fast.1.to_bits()),
                (full.0.to_bits(), full.1.to_bits()),
                "{}: unit {i}: shortcut {fast:?} vs full body {full:?}",
                c.what
            );
            if !crate::mods::chain_has_grants(&st, i) {
                shortcut += 1;
            }
        }
        shortcut
    }

    #[test]
    fn the_no_grants_shortcut_of_live_bands_of_equals_the_full_body() {
        let mut cases = vec![
            bands_case("no records at all", "ogres", vec![]),
            bands_case("no records, stamp-less faction", "no_such_faction", vec![]),
            bands_case("Fast grant on the bearer", "ogres", vec![(0, "Fast", false, 0)]),
            bands_case("Slow grant on the bearer", "dwarves", vec![(0, "Slow", false, 0)]),
            bands_case("Slow cancelled by granted Swift", "dwarves", vec![(0, "Slow", false, 0), (0, "Swift", false, 0)]),
            bands_case("Rapid Advance", "ogres", vec![(0, "Rapid Advance", false, 0)]),
            bands_case("Rapid Rush", "ogres", vec![(0, "Rapid Rush", false, 0)]),
            bands_case("Difficult Terrain debuff", "ogres", vec![(0, "Difficult Terrain", false, 0)]),
            bands_case("Dangerous Terrain debuff", "ogres", vec![(0, "Dangerous Terrain", false, 0)]),
            bands_case("a grant of an unrelated rule", "ogres", vec![(0, "Furious", false, 0)]),
            bands_case("attackers-side grant only", "ogres", vec![(0, "Fast", true, 0)]),
            bands_case("parenthesised grant name", "ogres", vec![(0, "Fast (spell)", false, 0)]),
            bands_case("grant on the other side's unit", "ogres", vec![(2, "Fast", false, 0)]),
            // records WITHOUT a grants_rule: the shortcut must fire and agree
            bands_case("modifier-only record", "ogres", vec![(0, "", false, 2)]),
        ];
        let mut joined = bands_case("grant on the attached hero", "ogres", vec![(1, "Fast", false, 0)]);
        joined.joined = true;
        cases.push(joined);
        let mut joined = bands_case("joined chain, no records", "ogres", vec![]);
        joined.joined = true;
        cases.push(joined);
        let mut joined = bands_case("grant on the host", "ogres", vec![(0, "Slow", false, 0)]);
        joined.joined = true;
        cases.push(joined);
        let mut pre = bands_case("pre-fold statics (no stamp) with a grant", "ogres", vec![(0, "Fast", false, 0)]);
        pre.rules_epoch = 18;
        cases.push(pre);
        let mut pre = bands_case("pre-fold statics, no records", "ogres", vec![]);
        pre.rules_epoch = 18;
        cases.push(pre);
        for band in [(-0.0, -0.0), (0.0, 0.0), (6.0, 12.0), (f64::MIN_POSITIVE, 1.0e300), (f64::NAN, 3.0)] {
            let mut c = bands_case("odd band values, no records", "ogres", vec![]);
            c.band0 = Some(band);
            cases.push(c);
            let mut c = bands_case("odd band values, Fast grant", "ogres", vec![(0, "Fast", false, 0)]);
            c.band0 = Some(band);
            cases.push(c);
        }
        let shortcuts: usize = cases.iter().map(assert_bands_equal).sum();
        assert!(shortcuts > 40, "the differential must exercise the shortcut path, saw {shortcuts} units");
        // and the positive control: a grant-bearing state still moves the band (the walk is NOT bypassed)
        let c = bands_case("control", "ogres", vec![(0, "Fast", false, 0)]);
        let (mut st, statics) = granted_pair_at(c.faction, &[], 13.0, c.rules_epoch);
        st.buffs[0].push(grant_row("Fast"));
        assert_eq!(crate::sim::live_bands_of(&statics, &st, 0), (8.0, 16.0));
    }

use super::*;
use crate::acts::read_act_header;
use crate::io;

    // ------------------- wave 5 group (b): the feat latch + Speed Feat ---

    // FEAT PR 1 (docs/plans/FEAT_DESIGN_2026-09-08.md §4). The latch is
    // `State.feats_used` (the Storm Attack shape); its first reader is the
    // move seam's Speed Feat band pass, gated on `EPOCH_7_TABLE_RULES`.
    // Four tests, one per brief line: the recorded spend replays and the
    // latch holds (a), the statics of a bearer stay unspent-feat-blind (b),
    // a fresh act after the spend shows no bonus (c), and an epoch-6 record
    // is byte-identical (d).

    /// The registry-built bearer: a gf/ratmen_clans profile whose ONLY rule
    /// is "Speed Feat", read off the REAL registry
    /// (`assets/solo/rules_mechanics_gf.json`, params advance_mod 2 /
    /// rush_mod 4 / uses_per_game 1). The REAL `build_for` product.
    fn feat_bearer_static(rules_epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Speed Feat".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "orc_marauders".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// The spend act's fixture: the `storm_line` shape (bearer "a" at 0",
    /// no enemy in reach) with the ENDGAME round set — `rounds_left = 4 - 3
    /// + 1 = 2`, the table's own spend window (`_rounds_left() > 2: continue`,
    /// solo_controller.gd:1715). The bearer's bands are the plain 6"/12"
    /// (the import's band pass skips `uses_per_game` entries).
    fn feat_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        st.rounds_total = 4;
        st.round = 3;
        // Movement reads every unit's base profile; all four indices exist.
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(); 4],
            index: HashMap::new(),
        });
        let bearer = feat_bearer_static(rules_epoch);
        (st, vec![bearer, storm_line_dummy("ah"), storm_line_dummy("b"), storm_line_dummy("bh")])
    }

    fn storm_line_dummy(name: &str) -> UnitStatic {
        UnitStatic { name: name.into(), ..Default::default() }
    }

    /// One move on the tray path — the seed never matters (a plain move
    /// draws no die).
    fn run_move(
        st: &State,
        statics: &[UnitStatic],
        action: &Action,
        rules_epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    fn rush_to(x_in: f64) -> Action {
        Action {
            kind: RUSH,
            unit: "a".into(),
            dest: Some([x_in * IN2M as f64, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    /// (a) part 1 — the spend act. At `rounds_left <= 2` an unspent bearer's
    /// ADVANCE rides +2" (the entry's own `advance_mod`) and its RUSH +4"
    /// (the entry's own `rush_mod`), the latch gains the DISPLAY name, and
    /// the rules-must-log line names the rule. RED before the read: the
    /// bands stay 6"/12" and the moves clamp at 6"/12".
    #[test]
    fn the_endgame_spend_grants_and_stamps_the_latch() {
        let (st, statics) = feat_line(7);
        let (next, shot) = run_move(&st, &statics, &advance_to(9.0), 7);
        assert_eq!(next.feats_used[0], vec!["Speed Feat".to_string()], "replayed feats_used matches the table's flag");
        let x = next.positions[0][0][0];
        assert!((x - 8.0 * IN2M).abs() < 1e-6, "the ADVANCE rides +2\": {x}");
        assert!(
            shot.log.iter().any(|l| l.contains("Speed Feat")),
            "rules-must-log: the applied rule names its line: {:?}",
            shot.log
        );
        let (next_r, _) = run_move(&st, &statics, &rush_to(17.0), 7);
        let xr = next_r.positions[0][0][0];
        assert!((xr - 16.0 * IN2M).abs() < 1e-6, "the RUSH rides +4\": {xr}");
        // The out-of-window control: the same bearer at round 1 (rounds_left
        // 4) is NOT spent — the table's planner holds the feat for the push.
        let (mut early, statics_early) = feat_line(7);
        early.round = 1;
        early.activated = vec![false, true, false, false];
        let (next_e, _) = run_move(&early, &statics_early, &advance_to(9.0), 7);
        assert!(next_e.feats_used[0].is_empty(), "outside the window the feat stays unspent");
        let xe = next_e.positions[0][0][0];
        assert!((xe - 6.0 * IN2M).abs() < 1e-6, "no band bonus outside the window: {xe}");
    }

    // (a) part 2 / (c) — the SECOND move in the replay, read out of the
    // RECORDING: the next act's state_before carries the recorder's
    // `feats_used` ledger key, the fold closes the latch, and a fresh move
    // gets no bonus. RED before the fold: the key never lands and the read
    // (already live) re-grants — the replay drifts past the recorded dest.
    //
    // THE FIXTURE is one recorded act, the #803 shape: header (one gf
    // carrier) + state_before at `rounds_left = 2` with the ledger row.
    const HEADER: &str = r#"{"kind":"header","profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.02,
        "game_system":"gf","faction_folder":"orc_marauders","special_rules":["Speed Feat"],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}},
      "knobs":{"rules_epoch":7}}"#;

    const SPENT: &str = r#"{"round":3,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},
        "ledger":{"feats_used":["Speed Feat"]}}}}"#;

    /// The recorded act's state: the fold must land the DISPLAY names in
    /// `State.feats_used`, and the statics must be built at the record's own
    /// epoch.
    fn recorded(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        assert_eq!(header.knobs.rules_epoch, 7, "the fixture's own epoch");
        let mut cache = crate::state::ProfileCache::new(header.profiles.clone());
        let mut roster = None;
        let st = io::state_from_json(SPENT, &mut cache, &mut roster).expect("state");
        let mut reg = crate::rules::Registries::new(&repo_root());
        let statics: Vec<UnitStatic> =
            st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, epoch)).collect();
        (st, statics)
    }

    fn move_of(unit: &str, x_in: f64) -> Action {
        Action {
            kind: ADVANCE,
            unit: unit.into(),
            dest: Some([x_in * IN2M as f64, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    /// (c) — the fresh act after the spend: the recorded ledger folds the
    /// latch CLOSED, so the same endgame move replays at the plain 6" band
    /// and the latch does not re-spend. RED before the fold: the state's
    /// `feats_used` stays empty, the read re-grants and the move drifts to
    /// 8" — the #493 divergence shape, one seam over.
    #[test]
    fn a_fresh_act_after_the_spend_shows_no_bonus() {
        let (st, statics) = recorded(7);
        assert_eq!(
            st.feats_used[0],
            vec!["Speed Feat".to_string()],
            "the recorded ledger folds into the state's latch"
        );
        let (next, _) = run_move(&st, &statics, &move_of("p1_0_a", 9.0), 7);
        let x = next.positions[0][0][0];
        assert!((x - 6.0 * IN2M).abs() < 1e-6, "no second bonus on the recorded act: {x}");
        assert_eq!(next.feats_used[0], vec!["Speed Feat".to_string()], "the replay does not re-spend");
    }

    /// (b) — the statics of a bearer are unchanged by an UNSPENT feat: the
    /// stamp carries the entry's own params for the move seam ONLY, the
    /// flat band pass stays empty (`move_rule_mods` is None — unit.rs:794's
    /// dead-data rule, #489's over-credit shape), and a record below the
    /// frozen epoch carries nothing at all. RED under the mutation that
    /// stamps the feat flat into `move_rule_mods`.
    #[test]
    fn the_statics_of_a_bearer_are_unchanged_by_an_unspent_feat() {
        let s7 = feat_bearer_static(7);
        let spec = s7.speed_feat.as_ref().expect("a carrier is stamped at epoch 7");
        assert_eq!(spec.name, "Speed Feat");
        assert_eq!(spec.advance_mod, 2.0, "the entry's own advance_mod");
        assert_eq!(spec.rush_mod, 4.0, "the entry's own rush_mod");
        assert!(s7.move_rule_mods.is_none(), "no flat band stamp for a once-per-game feat");
        let s6 = feat_bearer_static(6);
        assert!(s6.speed_feat.is_none(), "an epoch-6 record carries no feat stamp");
    }

    /// (d) — an epoch-6 record is byte-identical: even the hypothetical key
    /// in an old-epoch record cannot fire the read (the frozen gate), so the
    /// endgame move clamps at the plain 6" band exactly as it did before
    /// this port. RED under the mutation that drops the epoch gate.
    #[test]
    fn an_epoch_6_record_is_byte_identical() {
        let (st, statics) = recorded(6);
        let (next, _) = run_move(&st, &statics, &move_of("p1_0_a", 9.0), 6);
        let x = next.positions[0][0][0];
        assert!((x - 6.0 * IN2M).abs() < 1e-6, "an epoch-6 record replays at the plain band: {x}");
        // The folded key rides along INERTLY below the gate: the read is
        // epoch-gated, so nothing spends it again and no replay byte moves.
        assert_eq!(
            next.feats_used[0],
            vec!["Speed Feat".to_string()],
            "the fold lands the key, the gate keeps it inert"
        );
    }

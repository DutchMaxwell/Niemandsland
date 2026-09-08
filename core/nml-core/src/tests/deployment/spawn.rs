use super::*;

    // --------------------------------------------------- Spawn (wave 4, S5) ---
    //
    // THE RULE. The registry entry is the clause the core ports, and it ships
    // identically on both systems (gf: alien_hives, ratmen_clans,
    // robot_legions, wormhole_daemons_of_lust; aof: dwarves,
    // rift_daemons_of_lust, saurians, vampiric_undead, wood_elves):
    //     {"place_in": 6, "once_per_game": true}
    // The table's beat (`_solo_try_spawn`, main.gd:17375-17401): a standing
    // carrier places a FRESH unit, fully within `place_in` of the anchor,
    // once per game per entry (`spawn_spent`), offered at most once per round
    // (`spawn_offered_round`). The core rides the S5 withdraw-and-recreate
    // seam (`rollout::spawn_round_start`): the standing carrier steps off,
    // a fresh full-strength copy of it is parked by
    // `withdraw_as_destroyed`, and `arrive_one` puts it down within the
    // `place_in` square around where the carrier stood. The three declared
    // simplifications (timing, the copy's profile, square-not-circle) are
    // documented on the driver.
    //
    // THE FIXTURE. `p1_0_a` is a ratmen_clans carrier of three 2-wound models
    // standing around the origin; `p2_0_b` a plain enemy 1 m away, so the
    // board is not one-sided and the copy's `occupied` list has something to
    // book against. The board is 6x4 ft and empty, so the 6" square decides
    // the spot and nothing else does.
    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":2,
        "wounds_max":[2,2,2],"model_count":3,"caster_value":0,"base_radius":0.02,
        "game_system":"gf","faction_folder":"ratmen_clans",
        "special_rules":["Spawn"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.02,
        "game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p3_0_c":{"unit_id":"p3_0_c","name":"C","quality":4,"defense":3,"tough":1,
        "wounds_max":[1,1,1,1,1,1,1,1],"model_count":8,"caster_value":0,
        "base_radius":0.22,"game_system":"gf","faction_folder":"ratmen_clans",
        "special_rules":[],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":3,"wounds":[2,2,2],"radii":[0.02,0.02,0.02],
        "positions":[[0.0,0.0,0.0],[0.05,0.0,0.0],[-0.05,0.0,0.0]],
        "in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},
      "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    /// The crowded variant: the same board plus `p3_0_c`, eight wide friendly
    /// bases tiled over the whole 6" square around the anchor, so no free
    /// lattice point (`best_spot`'s 0.025 m step) is left inside the zone.
    const CROWDED: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":3,"wounds":[2,2,2],"radii":[0.02,0.02,0.02],
        "positions":[[0.0,0.0,0.0],[0.05,0.0,0.0],[-0.05,0.0,0.0]],
        "in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},
      "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p3_0_c":{"player":1,"alive":8,"wounds":[1,1,1,1,1,1,1,1],
        "radii":[0.22,0.22,0.22,0.22,0.22,0.22,0.22,0.22],
        "positions":[[-0.08,0.0,-0.08],[0.0,0.0,-0.08],[0.08,0.0,-0.08],
                     [-0.08,0.0,0.0],[0.08,0.0,0.0],
                     [-0.08,0.0,0.08],[0.0,0.0,0.08],[0.08,0.0,0.08]],
        "in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    fn line_crowded(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(CROWDED, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    fn seams_at(epoch: u32) -> Seams {
        Seams { rules_epoch: epoch, ..Seams::default() }
    }

    /// One round-start beat at `round`, on the real driver.
    fn beat(statics: &[UnitStatic], board: &Terrain, st: &mut State, round: i64) {
        st.round = round;
        spawn_round_start(statics, board, seams_at(CURRENT_RULES_EPOCH), st);
    }

    /// The table's reach (`place_in`, 6") rebuilt in the test's own arithmetic:
    /// every model base CENTRE within the entry's inches of the anchor, and no
    /// base hanging off the table.
    fn in_reach(p: [f64; 3], r: f64) -> bool {
        let (x1, z1) = (36.0 * crate::IN2M, 24.0 * crate::IN2M);
        let band = 6.0 * crate::IN2M;
        (p[0] * p[0] + p[2] * p[2]).sqrt() <= band + r + 1e-9
            && p[0] - r >= -x1 - 1e-6
            && p[0] + r <= x1 + 1e-6
            && p[2] - r >= -z1 - 1e-6
            && p[2] + r <= z1 + 1e-6
    }

    /// 1. THE READ, and its epoch gate. `place_in` and `once_per_game` come
    /// off the shipped registry entry through the production path; below
    /// `EPOCH_7_TABLE_RULES` the carrier reads as no carrier at all.
    #[test]
    fn the_registry_read_is_gated_on_the_frozen_epoch() {
        let (st, now) = line(CURRENT_RULES_EPOCH);
        let (_, before) = line(6);
        let i = idx(&st, "p1_0_a");
        let pi = st.roster.profile[i];
        assert_eq!(now[pi].spawn.place_in, 6.0, "the reach, off the entry");
        assert!(now[pi].spawn.once_per_game, "and the once-per-game param it ships with");
        assert_eq!(before[pi].spawn.place_in, 0.0, "epoch 6 reads no carrier");
        // The neighbour that must NOT resolve: a unit without the name is no
        // carrier, whatever its faction's map fields.
        let plain = idx(&st, "p2_0_b");
        assert_eq!(now[st.roster.profile[plain]].spawn.place_in, 0.0, "no name, no reach");
    }

    /// 2. THE SUMMON. The standing carrier steps off and a FRESH copy of it —
    /// full starting size, full wounds, not the strength it carried — stands
    /// within the entry's 6" of where the carrier stood. RED before the port:
    /// nothing in the core ever minted a copy.
    #[test]
    fn the_carrier_spawns_a_fresh_copy_within_six_inches() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        assert!(!st.dormant[i], "the copy is not parked — it arrives the same beat");
        assert!(st.reinforcement_used[i], "the seam's once-per-game latch is spent");
        assert_eq!(st.alive[i], 3, "a new copy at full starting size");
        assert_eq!(st.wounds[i], vec![2, 2, 2], "full wounds, not the standing unit's");
        assert_eq!(st.positions[i].len(), 3, "three model bases on the table");
        for m in &st.positions[i] {
            assert!(in_reach(*m, 0.02), "model at {m:?} is outside the 6\" reach");
        }
    }

    /// 3. THE ZONE BINDS — the f1f1b15d pattern. The 6" square around the
    /// anchor is crowded edge to edge with wide friendly bases, so
    /// `best_spot`'s lattice has no free point left inside it. A plain
    /// rectangle (the WHOLE table, what `ArrivalZone::admits` would allow if
    /// the zone were dropped) finds the open midfield at once and this test
    /// FALLS; the real zone refuses it and the summon is simply not made —
    /// a summon is never half-made.
    #[test]
    fn no_summon_when_the_six_inch_square_is_crowded() {
        let (mut st, statics) = line_crowded(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        let before = st.clone();
        beat(&statics, &board, &mut st, 1);
        assert_eq!(st.alive[i], 3, "no free spot in the square, so no copy");
        assert!(!st.reinforcement_used[i], "and the once-per-game latch is NOT spent");
        assert_eq!(
            st.positions[i], before.positions[i],
            "the carrier stands exactly where it stood"
        );
        let c = idx(&st, "p3_0_c");
        assert_eq!(st.alive[c], 8, "the crowd is untouched");
    }

    /// 4. ONCE PER GAME. The registry entry's `once_per_game` is the clause —
    /// a second boundary does not mint a second copy. RED: drop the latch and
    /// every boundary duplicates the carrier.
    #[test]
    fn the_second_summon_is_refused() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        assert!(st.reinforcement_used[i], "spent once");
        beat(&statics, &board, &mut st, 2);
        assert_eq!(st.alive[i], 3, "still exactly the one copy");
        assert_eq!(st.wounds[i], vec![2, 2, 2], "and the copy took no second mint");
    }

    /// 5. THE EPOCH GATE. A record stamped below `EPOCH_7_TABLE_RULES`
    /// crosses its boundary exactly as it was recorded — the frozen-constant
    /// rule, and the line that keeps every pre-wave corpus replaying
    /// byte-identically. The statics are built at the CURRENT epoch and only
    /// the seams say 6 (the #803 pattern): the read's own gate already leaves
    /// `place_in` at 0.0, so building both at 6 would prove nothing.
    #[test]
    fn an_epoch_6_record_never_spawns() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        let before = st.clone();
        st.round = 1;
        spawn_round_start(&statics, &board, seams_at(6), &mut st);
        assert_eq!(st.positions[i], before.positions[i], "an epoch-6 record knows no summon");
        assert_eq!(st.alive[i], before.alive[i], "and moves no unit at all");
        assert!(!st.reinforcement_used[i], "nor stamps a flag no epoch-6 corpus carries");
    }

    /// 6. NO NAME, NO SUMMON. A unit without the name — even on a board where
    /// a copy would fit — spawns nothing.
    #[test]
    fn a_unit_without_the_name_spawns_nothing() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let j = idx(&st, "p2_0_b");
        let before = st.clone();
        beat(&statics, &board, &mut st, 1);
        assert_eq!(st.positions[j], before.positions[j], "the plain unit stands still");
        assert_eq!(st.alive[j], 1, "and no copy of it appeared");
        assert!(!st.reinforcement_used[j], "no latch was spent on it");
    }

    /// 7. THE WIRING, not the rule: the beat has to run at the core's REAL
    /// round boundary, not only where a test calls it. RED: leave
    /// `spawn_round_start` out of `rollout_traced` and this is the only test
    /// that notices.
    #[test]
    fn the_round_boundary_runs_the_beat() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        let roll = Rollout::new(
            Policy::new(&statics, &board, seams_at(CURRENT_RULES_EPOCH)),
            Knobs::default(),
        );
        let mut sc = Scratch::default();
        let (ends, _stop) = roll
            .rollout_traced(&st, &Candidate::hold("p2_0_b"), 2, 2, &mut sc)
            .expect("the rollout resolves");
        let end = ends.last().expect("a boundary state");
        assert!(end.round > st.round, "the rollout crossed a round boundary at all");
        assert!(end.reinforcement_used[i], "and the standing carrier spawned at it");
        assert!(!end.dormant[i], "the copy arrived, it did not stay parked");
        assert_eq!(end.alive[i], 3, "a full-strength copy stands");
    }

use super::*;

    // ------------------------------------------- Reinforcement (wave 4, S5) ---
    //
    // THE RULE, verbatim from the army book (byte-identical in all four
    // snapshot books that carry it — gf: Ratmen Clans, Soul-Snatcher Cults;
    // aof: Ratmen, Volcanic Dwarves): "When a unit where all models have this
    // rule is Shaken or fully destroyed, you may remove it from the table as
    // destroyed and place a new copy of it fully within 12" of any table edge
    // at the beginning of the next round after Ambushers have been deployed.
    // Units that deploy via Reinforcement can't seize or contest objectives on
    // the round they deploy, and this rule doesn't apply to the new copy of
    // the unit."
    //
    // THE FIXTURE. `p1_0_a` is a Ratmen Clans carrier of three 2-wound models,
    // SHAKEN and down to its last model with one wound left — the rule's first
    // trigger, and a strength worth telling apart from a fresh one. `p2_0_b`
    // is a plain enemy 1 m away, there so the board is not one-sided and so
    // the arrival's `occupied` list has something to book against. The board
    // is 6x4 ft and empty, so the 12" band decides the spot and nothing else
    // does.
    //
    // WHY THE WOUNDS MATTER. `arrive_unit` restores the strength a unit
    // PARKED; `withdraw_as_destroyed` parks a FRESH one. That single
    // disagreement is what makes Reinforcement a different rule from Ambush
    // Re-Deployment, and test 1 is the line that holds it.

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":2,
        "wounds_max":[2,2,2],"model_count":3,"caster_value":0,"base_radius":0.02,
        "game_system":"gf","faction_folder":"ratmen_clans",
        "special_rules":["Reinforcement"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.02,
        "game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p3_0_c":{"unit_id":"p3_0_c","name":"C","quality":4,"defense":3,"tough":1,
        "wounds_max":[1,1,1,1,1],"model_count":5,"caster_value":0,"base_radius":0.22,
        "game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":true,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},
      "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    /// The crowded variant of `PLAIN`: the same two units plus `p3_0_c`, five
    /// wide friendly bases tiled along the owner's own back edge.
    const CROWDED: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":true,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},
      "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],
        "positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p3_0_c":{"player":1,"alive":5,"wounds":[1,1,1,1,1],"radii":[0.22,0.22,0.22,0.22,0.22],
        "positions":[[-0.65,0.0,-0.38],[-0.325,0.0,-0.38],[0.0,0.0,-0.38],
                     [0.325,0.0,-0.38],[0.65,0.0,-0.38]],
        "in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    /// The fixture with the carrier's ledger left empty (a no-op fold: every
    /// `PlainLedger` field defaults to what the state already holds).
    fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
        line_with(epoch, "{}")
    }

    /// The fixture with `ledger` spliced into the carrier's unit object, so a
    /// recorded row reaches the state through `state_of`'s own fold path and
    /// never through a hand-set field.
    fn line_with(epoch: u32, ledger: &str) -> (State, Vec<UnitStatic>) {
        let plain = PLAIN.replace(r#""ledger":{}"#, &format!(r#""ledger":{ledger}"#));
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(&plain, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    /// The crowded fixture: the same board plus `p3_0_c`, five wide friendly
    /// bases tiled along the owner's own back edge so the 12-inch band's near
    /// strip has no free lattice point left (measured over `best_spot`'s own
    /// 0.025 m scan grid, step `DEPLOY_SPOT_STEP_M`).
    fn line_crowded(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(CROWDED, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    /// 1. THE WITHDRAW, and the one place it disagrees with its own inverse.
    /// `arrive_unit` brings a unit back with the strength it PARKED
    /// (deployment.rs, Ambush Re-Deployment withdraws a DAMAGED unit);
    /// Reinforcement removes the unit "as destroyed" and places "a new COPY of
    /// it", which the table rebuilds at full starting size from the original's
    /// own army-list entry (main.gd:10303-10307). RED before the port:
    /// `withdraw_as_destroyed` does not exist — the only non-test write to
    /// `State.dormant` in the whole core wrote `false`.
    #[test]
    fn a_shaken_carrier_withdraws_as_destroyed_and_parks_a_fresh_copy() {
        let (mut st, _) = line(CURRENT_RULES_EPOCH);
        let i = idx(&st, "p1_0_a");
        assert_eq!((st.alive[i], st.wounds[i].clone()), (1, vec![1]), "one model, one wound left");
        withdraw_as_destroyed(&mut st, i, 1);
        assert_eq!(st.alive[i], 0, "removed from the table as destroyed");
        assert!(st.dormant[i], "and parked in reserve, which no core write did before");
        assert!(st.positions[i].is_empty(), "nothing of it stands on the table");
        assert!(!st.shaken[i], "Shaken left with the unit — the copy arrives fresh");
        assert_eq!(st.dormant_models[i], 3, "a NEW copy: full starting size, not the one survivor");
        assert_eq!(st.dormant_wounds[i], vec![2, 2, 2], "and full wounds, not the parked [1]");
        assert_eq!(st.earliest_arrival_round[i], 2, "due at the beginning of the NEXT round");
    }

    /// 1b. THE INVERSE, on the same fixture, so the disagreement above is
    /// measured rather than described: the parked copy comes BACK at the
    /// strength the withdraw parked, which is the full one.
    #[test]
    fn the_parked_copy_returns_at_full_strength() {
        let (mut st, _) = line(CURRENT_RULES_EPOCH);
        let i = idx(&st, "p1_0_a");
        withdraw_as_destroyed(&mut st, i, 1);
        arrive_unit(&mut st, i, (0.0, -0.5), 2);
        assert_eq!(st.alive[i], 3, "three models back on the table");
        assert_eq!(st.wounds[i], vec![2, 2, 2], "unwounded, because the copy is new");
        assert!(!st.dormant[i] && st.earliest_arrival_round[i] == -1, "off the reserve books");
        assert_eq!(st.ambush_arrived_round[i], 2, "stamped with the round it deployed in");
    }

    /// 2. THE READ, and its epoch gate. `within_in` and `once` come off the
    /// shipped registry entry through the production path; below
    /// `EPOCH_7_TABLE_RULES` the carrier reads as no carrier at all, which is
    /// what keeps every pre-wave replay byte-identical.
    #[test]
    fn the_registry_read_is_gated_on_the_frozen_epoch() {
        let (st, now) = line(CURRENT_RULES_EPOCH);
        let (_, before) = line(6);
        let i = idx(&st, "p1_0_a");
        let pi = st.roster.profile[i];
        assert_eq!(now[pi].reinforcement.within_in, 12.0, "the band's depth, off the entry");
        assert!(now[pi].reinforcement.once, "and the once-per-game param it ships with");
        assert_eq!(before[pi].reinforcement.within_in, 0.0, "epoch 6 reads no carrier");
        // The neighbour that must NOT resolve: `Grounded Reinforcement` is a
        // different rule under a different primitive, and only the exact-name
        // match keeps the two apart.
        let plain = idx(&st, "p2_0_b");
        assert_eq!(now[st.roster.profile[plain]].reinforcement.within_in, 0.0, "no rule, no band");
    }

    /// 3. THE LEDGER. A corpus where the TABLE already spent the promise must
    /// replay with it spent (`AiActRecorder._ledger_of` exports
    /// `reinforcement_spent` beside the ledgers it already writes). RED: drop
    /// the fold and a replayed act reads the rule as unspent, which is how a
    /// core would withdraw a unit the table has already brought back — the
    /// #493/#498 divergence shape.
    #[test]
    fn the_ledger_restores_a_reinforcement_already_spent_on_the_table() {
        let (spent, _) = line_with(CURRENT_RULES_EPOCH, r#"{"reinforcement_used":true}"#);
        let (fresh, _) = line(CURRENT_RULES_EPOCH);
        let i = idx(&spent, "p1_0_a");
        assert!(spent.reinforcement_used[i], "the recorded row folded in");
        assert!(!fresh.reinforcement_used[i], "and an empty ledger leaves it unspent");
        assert!(
            !fresh.reinforcement_used.iter().any(|&u| u),
            "every corpus recorded before this key replays with the rule unspent"
        );
    }

    fn seams_at(epoch: u32) -> Seams {
        Seams { rules_epoch: epoch, ..Seams::default() }
    }

    /// One round-start beat at `round`, on the real driver.
    fn beat(statics: &[UnitStatic], board: &Terrain, st: &mut State, round: i64) {
        st.round = round;
        reinforcement_round_start(statics, board, seams_at(CURRENT_RULES_EPOCH), st);
    }

    /// The 12" band as the TABLE measures it (`reinforcement_spot_in_strip`,
    /// solo_controller.gd:6089-6098), rebuilt in the test's own arithmetic so
    /// the assertion never asks the code under test whether it is right.
    fn in_band(p: (f64, f64), r: f64) -> bool {
        let (x1, z1) = (36.0 * crate::IN2M, 24.0 * crate::IN2M);
        let band = 12.0 * crate::IN2M;
        if p.0 - r < -x1 - 1e-6 || p.0 + r > x1 + 1e-6 {
            return false; // a model may not hang off the table
        }
        if p.1 - r < -z1 - 1e-6 || p.1 + r > z1 + 1e-6 {
            return false;
        }
        (p.0 + r) + x1 <= band
            || x1 - (p.0 - r) <= band
            || (p.1 + r) + z1 <= band
            || z1 - (p.1 - r) <= band
    }

    /// 4. THE ARRIVAL. The promised copy comes back, at full starting size,
    /// on its owner's own edge, with EVERY model base inside the 12" band.
    /// RED before the driver: nothing in the core ever brought a unit back —
    /// `arrive_one`'s only caller in the whole repo was a test.
    ///
    /// WHAT THIS TEST DOES NOT PIN, measured rather than assumed. Swapping the
    /// band for a plain rectangle leaves it GREEN, and that is a property of
    /// the rule, not a hole in the fixture: the table's own prefer point
    /// (`_reinforcement_prefer_point`, the owner's back edge at 5% of the
    /// table depth) lies INSIDE a 12" band on any table under 20 ft deep, so
    /// on an empty board the ordering alone already lands the copy there. The
    /// band only binds when that edge is crowded. The band's GEOMETRY — and
    /// the fact that it refuses what a rectangle allows — is pinned in #788
    /// (`an_edge_strip_arrival_lands_inside_the_band`), where the objective
    /// pulls the other way.
    #[test]
    fn the_copy_arrives_within_twelve_inches_of_an_edge() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        assert!(st.dormant[i], "round 1: the carrier is Shaken, so it steps off");
        beat(&statics, &board, &mut st, 2);
        assert!(!st.dormant[i], "round 2: the promised copy is due and lands");
        assert_eq!(st.alive[i], 3, "a new copy at full starting size");
        assert_eq!(st.positions[i].len(), 3, "three model bases on the table");
        for m in &st.positions[i] {
            assert!(in_band((m[0], m[2]), 0.02), "model at {m:?} is outside the 12\" band");
        }
    }

    /// 4b. THE BAND BINDS — the case test 4 cannot reach, because the table's
    /// own prefer point already lies inside the band on an empty board. Here
    /// the owner's back edge is crowded: five wide friendly bases tile the
    /// near strip, so `best_spot`'s nearest FREE point to the prefer point is
    /// the open midfield — OUTSIDE the 12-inch band. A plain-rectangle
    /// arrival zone (what `ArrivalZone::admits` would allow if the strip
    /// check were dropped) puts the copy there and this test FALLS; the real
    /// `EdgeStrip` refuses the midfield and lands the copy in the side band
    /// instead, fully inside the rule's 12 inches.
    #[test]
    fn the_copy_arrives_within_twelve_inches_when_the_back_edge_is_crowded() {
        let (mut st, statics) = line_crowded(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        assert!(st.dormant[i], "round 1: the carrier is Shaken, so it steps off");
        beat(&statics, &board, &mut st, 2);
        assert!(!st.dormant[i], "round 2: the promised copy is due and lands");
        assert_eq!(st.alive[i], 3, "a new copy at full starting size");
        assert_eq!(st.positions[i].len(), 3, "three model bases on the table");
        for m in &st.positions[i] {
            assert!(in_band((m[0], m[2]), 0.02), "model at {m:?} is outside the 12\" band");
        }
    }

    /// 5. THE RIDER, through its own consumer. "Units that deploy via
    /// Reinforcement can't seize or contest objectives on the round they
    /// deploy" — the SAME `ambush_arrived_round` stamp `score::can_hold_marker`
    /// already reads, so the clause ports for free and is asserted through
    /// that reader rather than through the raw field.
    #[test]
    fn the_copy_cannot_seize_on_the_round_it_arrives() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        beat(&statics, &board, &mut st, 2);
        assert_eq!(st.ambush_arrived_round[i], 2, "stamped with the round it deployed in");
        assert!(!crate::score::can_hold_marker(&st, i, 2), "no seize on the arrival round");
        assert!(crate::score::can_hold_marker(&st, i, 3), "and the lock lasts exactly one round");
    }

    /// 6. ONCE PER GAME. "This rule doesn't apply to the new copy of the unit"
    /// — on the table the copy is a different GameUnit built from a rules list
    /// with the name stripped; the core has ONE roster index for both, so
    /// `reinforcement_used` is what carries the clause. RED: drop the flag and
    /// a carrier that is Shaken again reinforces forever.
    #[test]
    fn the_copy_does_not_reinforce_a_second_time() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        beat(&statics, &board, &mut st, 2);
        assert!(!st.dormant[i] && st.reinforcement_used[i], "back on the table, promise spent");
        st.shaken[i] = true; // Shaken again, two rounds later
        beat(&statics, &board, &mut st, 3);
        assert!(!st.dormant[i], "the copy has no Reinforcement — it stays, and stays Shaken");
        assert!(st.shaken[i], "and nothing else cleaned it up either");
    }

    /// 7. THE EPOCH GATE, on the DRIVER rather than on the read. A record
    /// stamped below `EPOCH_7_TABLE_RULES` crosses its rounds exactly as it
    /// was recorded — the frozen-constant rule, and the line that keeps every
    /// pre-wave corpus replaying byte-identically.
    ///
    /// The statics are deliberately built at the CURRENT epoch and only the
    /// seams say 6. Building both at 6 would prove nothing about this gate:
    /// the read's own gate (#792) already leaves `within_in` at 0.0, so the
    /// driver would decline for the other reason and the test would pass with
    /// the gate deleted — measured, not assumed (a first RED run with both at
    /// epoch 6 stayed green under exactly that mutation).
    #[test]
    fn an_epoch_6_record_never_reinforces() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        let before = st.clone();
        st.round = 1;
        reinforcement_round_start(&statics, &board, seams_at(6), &mut st);
        assert!(!st.dormant[i], "an epoch-6 record knows no withdraw");
        assert_eq!(st.alive[i], before.alive[i], "and moves no unit at all");
        assert!(!st.reinforcement_used[i], "nor stamps a flag no epoch-6 corpus carries");
    }

    /// 8. THE WIRING, not the rule: the beat has to run at the core's REAL
    /// round boundary, not only where a test calls it. The carrier is FULLY
    /// DESTROYED rather than Shaken — the rule's other trigger, and the one a
    /// playout cannot undo (a Shaken unit that idles is no longer Shaken by
    /// the time the round ends, which is the AI recovering, not a broken
    /// fixture). RED: leave `reinforcement_round_start` out of
    /// `rollout_traced` and this is the only test that notices.
    #[test]
    fn the_round_boundary_runs_the_beat() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        st.alive[i] = 0;
        st.shaken[i] = false;
        st.positions[i] = Vec::new();
        st.wounds[i] = Vec::new();
        st.radii[i] = Vec::new();
        let st = st;
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
        assert!(end.dormant[i], "and the destroyed carrier withdrew at that boundary");
    }

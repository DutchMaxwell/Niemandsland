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
    // THIS FILE IS PART 2 OF 3. It pins the PRIMITIVE — the withdraw, the
    // registry read and the ledger row. The round-start driver that calls the
    // withdraw, the arrival into the 12" band and the four tests that need it
    // are part 3; the branch is split because the guard caps a step at 120
    // production lines, not because the rule stops here.
    //
    // THE FIXTURE. `p1_0_a` is a Ratmen Clans carrier of three 2-wound models,
    // SHAKEN and down to its last model with one wound left — the rule's first
    // trigger, and a strength worth telling apart from a fresh one.
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

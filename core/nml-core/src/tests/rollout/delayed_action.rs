use super::*;

    // ------------------------------------- Pass Turn / Delayed Action (wave 4) ---
    //
    // THE RULE, verbatim from the book (word-identical in all 11 snapshot books
    // that carry it): "Once per round, if your opponent has more units left to
    // activate than you, then this model's unit may pass its turn instead of
    // activating (may still be activated later)."
    //
    // THE FIXTURE. Player 2 fields three plain units (`p2_0_b`, `p2_1_c`,
    // `p2_2_d`), player 1 a single Delayed Action carrier (`p1_0_a`) 30 m away —
    // far enough that no charge and no volley is ever on the menu, so every
    // activation is a bare HOLD and the only thing the rollout can vary is WHO
    // acts next. `p2_0_b` is spent as the rollout's opening action, which leaves
    // player 2 with two activations against player 1's one: the strict surplus
    // the rule asks for.
    //
    // WHY A TAIL CAP. Boundaries are the only states `rollout_traced` hands back,
    // and at a boundary every unit is activated — the activation ORDER is
    // invisible there. `tail_cap_p2 = 1` truncates the rollout mid-round
    // (`Stop::TailCap`), so the returned state shows exactly who moved and who
    // did not. That is what makes the pass observable at all.

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"human_inquisition",
        "special_rules":["Delayed Action"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"human_inquisition","special_rules":[],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p2_1_c":{"unit_id":"p2_1_c","name":"C","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"human_inquisition","special_rules":[],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p2_2_d":{"unit_id":"p2_2_d","name":"D","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"human_inquisition","special_rules":[],
        "item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[30.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p2_1_c":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[30.0,0.0,3.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p2_2_d":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[30.0,0.0,6.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn pass_line(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    /// One truncated rollout from `p2_0_b`'s hold, seen from player 2's seat.
    /// `tail_cap_p2` is the per-seat activation cap; the state handed back is
    /// the mid-round truncation, which is where the order is readable.
    fn truncated(st: &State, statics: &[UnitStatic], epoch: u32, tail_cap_p2: i64) -> State {
        let terrain = Terrain::default();
        let seams = Seams { rules_epoch: epoch, ..Seams::default() };
        let knobs = Knobs { tail_cap_p2, ..Knobs::default() };
        let roll = Rollout::new(Policy::new(statics, &terrain, seams), knobs);
        let mut sc = Scratch::default();
        let (ends, _stop) = roll
            .rollout_traced(st, &Candidate::hold("p2_0_b"), 2, 1, &mut sc)
            .expect("the rollout resolves");
        ends.last().expect("a truncation state").clone()
    }

    /// THE RED. Player 2 opens, which leaves it two activations against player
    /// 1's one — the strict surplus. Under plain alternation the carrier is
    /// handed the turn and spends it. With the rule, it passes: the carrier is
    /// still un-activated when the cap truncates, and player 2 has had to commit
    /// a SECOND unit first, which is the whole point of the delay.
    #[test]
    fn a_carrier_passes_instead_of_activating_when_the_opponent_has_more_left() {
        let (st, statics) = pass_line(CURRENT_RULES_EPOCH);
        let end = truncated(&st, &statics, CURRENT_RULES_EPOCH, 1);
        assert!(
            !end.activated[idx(&st, "p1_0_a")],
            "the carrier passed its turn — it may still be activated later"
        );
        assert!(
            end.activated[idx(&st, "p2_1_c")] || end.activated[idx(&st, "p2_2_d")],
            "the turn went back to the opponent, which had to commit a second unit"
        );
    }

    /// Guard (a), the antisymmetric one: with the counts EQUAL the rule refuses,
    /// so the carrier takes its turn normally. Two carriers can therefore never
    /// pass at each other forever — `opponent > own` cannot hold for both sides
    /// at the same instant.
    #[test]
    fn the_pass_is_refused_without_the_surplus() {
        let (mut st, statics) = pass_line(CURRENT_RULES_EPOCH);
        let d = idx(&st, "p2_2_d");
        st.activated[d] = true; // 1 v 1 once the opener is spent
        let end = truncated(&st, &statics, CURRENT_RULES_EPOCH, 1);
        assert!(
            end.activated[idx(&st, "p1_0_a")],
            "no surplus, no pass: the carrier activates like any other unit"
        );
    }

    /// The epoch gate. A record stamped below `EPOCH_7_TABLE_RULES` replays the
    /// alternation it was recorded under, carrier or not — the frozen-constant
    /// rule, so no earlier corpus moves.
    #[test]
    fn an_epoch_6_record_never_passes() {
        let (st, statics) = pass_line(6);
        let end = truncated(&st, &statics, 6, 1);
        assert!(
            end.activated[idx(&st, "p1_0_a")],
            "epoch 6 knows no pass step: byte-identical to today's alternation"
        );
    }

    /// Guard (b): "once per round" binds the CARRIER UNIT. A carrier already
    /// stamped in THIS round activates instead of passing a second time — the
    /// stamp is what keeps a round from looping on one unit.
    #[test]
    fn a_carrier_passes_at_most_once_per_round() {
        let (mut st, statics) = pass_line(CURRENT_RULES_EPOCH);
        let a = idx(&st, "p1_0_a");
        st.delayed_action_round[a] = st.round;
        let end = truncated(&st, &statics, CURRENT_RULES_EPOCH, 1);
        assert!(end.activated[a], "the pass was already spent this round");
    }

    /// The table bridge. `AiActRecorder._ledger_of` exports the carrier's
    /// `unit_properties["delayed_action_round"]`, and a replayed act must read it
    /// back: a pass the TABLE already spent cannot come back to life on replay
    /// (the #493/#498 divergence shape — an accumulating once-per-round flag
    /// silently vanishing between activations).
    #[test]
    fn the_ledger_restores_a_pass_already_spent_on_the_table() {
        let plain = PLAIN.replace(
            r#""p1_0_a":{"player":1,"#,
            r#""p1_0_a":{"ledger":{"delayed_action_round":2},"player":1,"#,
        );
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(&plain, &mut cache, &mut roster).expect("state");
        let a = idx(&st, "p1_0_a");
        assert_eq!(st.delayed_action_round[a], 2, "the table's stamp survives the fold");
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        let end = truncated(&st, &statics, CURRENT_RULES_EPOCH, 1);
        assert!(end.activated[a], "the pass was spent on the table, not again here");
    }

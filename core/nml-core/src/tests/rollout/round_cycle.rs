use super::*;
use crate::acts::CURRENT_RULES_EPOCH;

    // ---------------- Round-start refresh (ai_planner.gd:446-459) ----------
    //
    // What the game refreshes at every round start, ported as
    // `round_start_refresh`: spell tokens refill (a plain caster accumulates by
    // `casts_per_round` up to `CASTER_POINTS_CAP`, a Caster Group RESETS to its
    // bearer count), the activation flags clear, and only a Battleborn or
    // Steadfast carrier loses Shaken for free. One helper serves BOTH the
    // rollout's `_cross_round` and the playout's round loop.

    /// `p1_0_a`: a plain caster (`caster_value` 2). `p1_0_b`: a Caster Group
    /// (`caster_value` 0) whose refill is its bearer count. Both resolved out
    /// of the shipped gf/battle_brothers registry.
    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
        "wounds_max":[1,1,1,1],"model_count":4,"caster_value":2,"base_radius":0.016,
        "game_system":"gf","faction_folder":"battle_brothers",
        "special_rules":[],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p1_0_b":{"unit_id":"p1_0_b","name":"B","quality":4,"defense":3,"tough":1,
        "wounds_max":[1,1,1,1],"model_count":4,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"battle_brothers",
        "special_rules":["Caster Group"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":4,"wounds":[1,1,1,1],"radii":[0.016],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p1_0_b":{"player":1,"alive":4,"wounds":[1,1,1,1],"radii":[0.016],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    /// The live state plus its PRODUCTION statics (`UnitStatic::build_for` over
    /// the header's own profiles) at the current epoch.
    fn fresh() -> (State, Vec<UnitStatic>) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        (st, statics)
    }

    /// A plain caster adds its `casts_per_round` (1 + 2 = 3) and never passes
    /// the cap (a full pool stays 6). RED without the cap: the full pool grows.
    #[test]
    fn a_plain_caster_accumulates_to_the_cap() {
        let (mut st, statics) = fresh();
        let i = idx(&st, "p1_0_a");
        st.casts[i] = 1;
        round_start_refresh(&statics, &mut st, i);
        assert_eq!(st.casts[i], 3, "1 + 2 tokens at the round start");
        st.casts[i] = CASTER_POINTS_CAP;
        round_start_refresh(&statics, &mut st, i);
        assert_eq!(st.casts[i], CASTER_POINTS_CAP, "a full pool stays at the cap");
    }

    /// A Caster Group RESETS to its bearer count, it does not accumulate: an
    /// empty pool fills to 4 alive, a rich pool of 9 snaps back to 2 alive.
    #[test]
    fn a_caster_group_resets_to_its_bearer_count() {
        let (mut st, statics) = fresh();
        let i = idx(&st, "p1_0_b");
        st.alive[i] = 4;
        st.casts[i] = 0;
        round_start_refresh(&statics, &mut st, i);
        assert_eq!(st.casts[i], 4, "empty pool fills to the bearer count");
        st.alive[i] = 2;
        st.casts[i] = 9;
        round_start_refresh(&statics, &mut st, i);
        assert_eq!(st.casts[i], 2, "a rich pool resets to the bearer count");
    }

    /// The refresh clears both activation flags. RED when they are kept.
    #[test]
    fn the_refresh_clears_activated_and_fatigued() {
        let (mut st, statics) = fresh();
        let i = idx(&st, "p1_0_a");
        st.activated[i] = true;
        st.fatigued[i] = true;
        round_start_refresh(&statics, &mut st, i);
        assert!(!st.activated[i], "activated clears at the round start");
        assert!(!st.fatigued[i], "fatigued clears at the round start");
    }

    /// A rule-less Shaken unit keeps the marker: only a Battleborn or Steadfast
    /// carrier clears it, and their own tests own that leg.
    #[test]
    fn a_plain_unit_stays_shaken() {
        let (mut st, statics) = fresh();
        let i = idx(&st, "p1_0_a");
        st.shaken[i] = true;
        round_start_refresh(&statics, &mut st, i);
        assert!(st.shaken[i], "a plain unit stays Shaken");
    }

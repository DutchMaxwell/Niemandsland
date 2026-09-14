use super::*;
use crate::acts::{EPOCH_41_SELF_DESTRUCT_SURVIVORS, EPOCH_43_BATTLEBORN_ROLL};
use crate::rng::GodotRng;

    // ---------------- Battleborn round-start recovery (sweep E, epoch 43) --
    //
    // THE RULE (gf/battle_brothers — the TUTORIAL faction; the registry
    // `Battleborn; recover_target=4` entry): "If a unit where all models have
    // this rule is Shaken at the beginning of the round, roll one die. On a
    // 4+, it stops being Shaken." The table rolls the real die at its
    // round-start beat (`_solo_battleborn_recovery`): `_solo_tray_roll(1,
    // target, ..)` draws ONE seeded `randi_range(1, 6)` face per Shaken
    // eligible unit (main.gd) and `AiCombatMath.battleborn_recovers` reads it
    // back against the entry's `recover_target` — so the unit stays Shaken
    // half the time. The core FREE-CLEARED the marker the moment
    // `battleborn_active` read true, no die, and the die-roll alias stamp
    // listed only the four wave-3 aliases (+ "Steadfast" from 40) — never the
    // plain "Battleborn" name — the net learned a recovery the player never
    // gets.
    //
    // THE FIXTURE. `p1_0_a`: one model, a literal "Battleborn" carrier
    // resolved out of the shipped gf/battle_brothers registry (the same
    // faction the tutorial army fields). The round-start leg runs EXACTLY the
    // playout boundary's order (arbitration.rs): `round_start_refresh` first,
    // then `battleborn_recovery_roll` off the seeded `GodotRng` — the same
    // stream `_solo_tray_roll` draws, one die per Shaken eligible unit in
    // roster order, so a recorded table game replays byte-exact and a fresh
    // core game consumes the stream the table's own beat consumes.
    //
    // The NEW leg (from the epoch-43 gate): the seeded die decides. The OLD
    // leg (at the frozen epoch immediately below the bump — re-pointed by its
    // frozen constant at rebase): the free clear every recorded corpus
    // replays, no die at all.

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"battle_brothers",
        "special_rules":["Battleborn"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    /// A Shaken "Battleborn" carrier's live state plus its PRODUCTION statics
    /// (`UnitStatic::build_for` over the real registry) at `epoch`.
    fn shaken_battleborn(epoch: u32) -> (State, Vec<UnitStatic>, usize) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let mut st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let i = idx(&st, "p1_0_a");
        st.shaken[i] = true;
        let statics = statics_of(&st, epoch);
        (st, statics, i)
    }

    /// The NEW leg: at the epoch-43 gate the recovery is the seeded die the
    /// table rolls — a FORCED 3 keeps the unit Shaken, a forced 4 recovers.
    /// RED on the pre-port core, whose free clear recovers the unit on every
    /// face with no die at all.
    #[test]
    fn a_shaken_battleborn_unit_stays_shaken_on_a_forced_3_and_recovers_on_a_4_from_epoch_43() {
        // The two seeds' first `randi_range(1, 6)` faces, derived from the
        // GATE R fixture's bit-exact PCG32 mapping
        // (tests/fixtures/rng_godot.json): seed 8 opens with a 3, seed 1
        // with a 4.
        assert_eq!(GodotRng::new(8).randi_range(1, 6), 3, "seed 8 forces the 3");
        assert_eq!(GodotRng::new(1).randi_range(1, 6), 4, "seed 1 forces the 4");
        let (mut st, statics, i) = shaken_battleborn(EPOCH_43_BATTLEBORN_ROLL);
        round_start_refresh(&statics, &mut st, i);
        battleborn_recovery_roll(&statics, &mut st, i, &mut GodotRng::new(8));
        assert!(st.shaken[i], "face 3 misses the 4+ recovery: the unit stays Shaken");
        let (mut st, statics, i) = shaken_battleborn(EPOCH_43_BATTLEBORN_ROLL);
        round_start_refresh(&statics, &mut st, i);
        battleborn_recovery_roll(&statics, &mut st, i, &mut GodotRng::new(1));
        assert!(!st.shaken[i], "face 4 reaches the 4+ recovery");
    }

    /// The NEW leg across the seed sweep: at the epoch-43 gate the recovery
    /// is the seeded die the table rolls — faces 1-3 stay Shaken, faces 4-6
    /// recover, and BOTH halves occur across the seeds. RED on the pre-port
    /// core, whose free clear recovers the unit on every face with no die at
    /// all.
    #[test]
    fn a_shaken_battleborn_unit_rolls_the_seeded_die_at_target_from_epoch_43() {
        let mut low = 0;
        let mut high = 0;
        for seed in 0..64i64 {
            // The probe roll predicts the face the recovery leg will draw:
            // a fresh `GodotRng` at the same seed answers the same stream,
            // and the round-start refresh draws nothing before the die.
            let face = GodotRng::new(seed).randi_range(1, 6);
            let (mut st, statics, i) = shaken_battleborn(EPOCH_43_BATTLEBORN_ROLL);
            round_start_refresh(&statics, &mut st, i);
            battleborn_recovery_roll(&statics, &mut st, i, &mut GodotRng::new(seed));
            if face <= 3 {
                assert!(
                    st.shaken[i],
                    "face {face} misses the 4+ recovery: the unit stays Shaken"
                );
                low += 1;
            } else {
                assert!(!st.shaken[i], "face {face} reaches the 4+ recovery");
                high += 1;
            }
        }
        assert!(low > 0 && high > 0, "both die halves must occur across the seeds");
    }

    /// The OLD leg: at the frozen epoch immediately below the bump
    /// (`EPOCH_41_SELF_DESTRUCT_SURVIVORS` after the 16:4x rebase —
    /// re-pointed by its frozen constant at rebase) the same Shaken unit
    /// recovers WITHOUT a die — the wave-3 free-clear reading every
    /// recorded corpus replays. Green before and after the port.
    #[test]
    fn the_pregate_leg_clears_the_shaken_battleborn_unit_for_free() {
        let (mut st, statics, i) = shaken_battleborn(EPOCH_41_SELF_DESTRUCT_SURVIVORS);
        round_start_refresh(&statics, &mut st, i);
        assert!(!st.shaken[i], "below the gate the free clear stands");
    }

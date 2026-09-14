use super::*;
use crate::acts::EPOCH_37_UNSTOPPABLE_AURA;
use crate::rng::GodotRng;

    // ---------------- Steadfast round-start recovery (sweep H, epoch 40) ---
    //
    // THE RULE (gf/aof disciples + more — the registry `Steadfast;
    // recover_target=4` entry): "If a unit where all models have this rule is
    // Shaken at the beginning of the round, roll one die. On a 4+, it stops
    // being Shaken." The table rolls the real die at its round-start beat
    // (`_solo_battleborn_recovery`, main.gd:10718): `_solo_tray_roll(1,
    // target, ..)` draws ONE seeded `randi_range(1, 6)` face per Shaken
    // eligible unit (main.gd:10730) and `AiCombatMath.battleborn_recovers`
    // reads it back against the entry's `recover_target` (main.gd:10731) —
    // so the unit stays Shaken a third of the time. The core FREE-CLEARED
    // the marker the moment `steadfast_active` (or the dynamic grant) read
    // true, no die, and the die-roll alias list omitted Steadfast — the net
    // learned a recovery the player never gets.
    //
    // THE FIXTURE. `p1_0_a`: one model, a literal "Steadfast" carrier
    // resolved out of the shipped gf/change_disciples registry (the same
    // faction the Steadfast Aura wave reads). The round-start leg runs
    // EXACTLY the playout boundary's order (arbitration.rs:247-251):
    // `round_start_refresh` first, then `battleborn_recovery_roll` off the
    // seeded `GodotRng` — the same stream `_solo_tray_roll` draws, one die
    // per Shaken eligible unit in roster order, so a recorded table game
    // replays byte-exact and a fresh core game consumes the stream the
    // table's own beat consumes.
    //
    // The NEW leg (from `EPOCH_40_STEADFAST_ROLL`): the seeded die decides.
    // The OLD leg (at the frozen epoch immediately below the bump —
    // `EPOCH_37_UNSTOPPABLE_AURA` at this writing, re-pointed by its frozen
    // constant at rebase): the wave-3 free clear every recorded corpus
    // replays, no die at all.

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"change_disciples",
        "special_rules":["Steadfast"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    /// A Shaken "Steadfast" carrier's live state plus its PRODUCTION statics
    /// (`UnitStatic::build_for` over the real registry) at `epoch`.
    fn shaken_steadfast(epoch: u32) -> (State, Vec<UnitStatic>, usize) {
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let mut st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let i = idx(&st, "p1_0_a");
        st.shaken[i] = true;
        let statics = statics_of(&st, epoch);
        (st, statics, i)
    }

    /// The NEW leg: at `EPOCH_40_STEADFAST_ROLL` the recovery is the seeded
    /// die the table rolls — faces 1-3 stay Shaken, faces 4-6 recover, and
    /// BOTH halves occur across the seed sweep. RED on the pre-port core,
    /// whose free clear recovers the unit on every face with no die at all.
    #[test]
    fn a_shaken_steadfast_unit_stays_shaken_on_a_low_die_from_epoch_40() {
        let mut low = 0;
        let mut high = 0;
        for seed in 0..64i64 {
            // The probe roll predicts the face the recovery leg will draw:
            // a fresh `GodotRng` at the same seed answers the same stream,
            // and the round-start refresh draws nothing before the die.
            let face = GodotRng::new(seed).randi_range(1, 6);
            let (mut st, statics, i) = shaken_steadfast(40);
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

    /// The OLD leg: at the frozen epoch immediately below the bump the same
    /// Shaken unit recovers WITHOUT a die — the wave-3 free-clear reading
    /// every recorded corpus replays. Green before and after the port.
    #[test]
    fn the_pregate_epoch_37_leg_clears_the_shaken_steadfast_unit_for_free() {
        let (mut st, statics, i) = shaken_steadfast(EPOCH_37_UNSTOPPABLE_AURA);
        round_start_refresh(&statics, &mut st, i);
        assert!(!st.shaken[i], "below the gate the free clear stands");
    }

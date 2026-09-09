use super::*;
use crate::dice::{ShootResult, Tray};
use crate::io::Action;
use crate::rng::GodotRng;
use crate::sim::{ctx_live, ctx_of, resolve_stochastic_tray_on_board, HOLD};

    // ------------------------------- Vengeance (wave 4 follow-up) ---
    //
    // THE RULE, verbatim and word-identical in all three carrier books
    // (gf/eternal_dynasty, aof/dragon_empire, aof/halflings): "When this unit
    // is fully destroyed, place as many Vengeance markers on the unit that
    // destroyed it as models with this rule in this unit at the beginning of
    // the game. Friendly units get +X to hit rolls when attacking that unit,
    // where X is the number of markers on it."
    //
    // THE FIXTURE. `p1_0_a` (one model, a 64-attack Rifle, Quality 4) sits
    // ~8" from `p2_0_b` — three models, each a "Vengeance" carrier resolved
    // out of the shipped gf/eternal_dynasty registry — and from `p2_1_c`,
    // the same three-model body WITHOUT the rule. One HOLD-and-shoot
    // activation wipes the target. The markers the rule banks on the
    // DESTROYER are read back through the one seam every attacker of a
    // marked unit already folds — `Ctx::vs_hit_mod`, `ctx_live`'s vs-side
    // sum, which the tray's shooting leg (dice.rs volley fold) and melee leg
    // (`melee_hit_target`) BOTH consume — so the RED fixture names no
    // production symbol the port has yet to add: the assertion reads
    // today's fields alone.

    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
        "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"human_inquisition",
        "special_rules":[],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":64,"count":1,"ap":0,"rules":[]}]},
      "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":3,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":["Vengeance"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "p2_1_c":{"unit_id":"p2_1_c","name":"C","quality":4,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":3,"caster_value":0,"base_radius":0.016,
        "game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":[],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
      "p1_0_a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],
        "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p2_0_b":{"player":2,"alive":3,"wounds":[1,1,1],"radii":[0.016,0.016,0.016],
        "positions":[[0.2,0.0,0.0],[0.2005,0.0,0.0],[0.201,0.0,0.0]],
        "in_cover":false,"shaken":false,"fatigued":false,
        "activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
        "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,
        "mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},
      "p2_1_c":{"player":2,"alive":3,"wounds":[1,1,1],"radii":[0.016,0.016,0.016],
        "positions":[[0.2,0.0,0.05],[0.2005,0.0,0.05],[0.201,0.0,0.05]],
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

    fn volley(st: &State, statics: &[UnitStatic], target: &str, epoch: u32) -> (State, ShootResult) {
        let terrain = Terrain::default();
        let action = Action {
            kind: HOLD,
            unit: "p1_0_a".into(),
            dest: None,
            shoot: Some(target.into()),
            charge: None,
            patient: false,
            split: None,
            traced: None, teleport: None, };
        let mut rng = GodotRng::new(0);
        let mut tray = Tray::seeded(9);
        resolve_stochastic_tray_on_board(
            statics, st, &action, &terrain,
            Seams { rules_epoch: epoch, ..Seams::default() }, &mut rng, &mut tray,
        )
        .expect("the volley resolves")
    }

    /// The fold every attacker of a marked unit already reads: `ctx_live`'s
    /// vs-side sum on the marked unit's own context — the Ctx the tray's
    /// shooting leg folds as `def.vs_hit_mod` and the melee leg folds inside
    /// `melee_hit_target`'s single sum.
    fn vs_hit(st: &State, statics: &[UnitStatic], i: usize, epoch: u32) -> i64 {
        ctx_live(ctx_of(&statics[st.roster.profile[i]], st, i), statics, st, i, false, epoch)
            .vs_hit_mod
    }

    /// THE RED. The wipe banks the dead unit's START size (three carrier
    /// models = three markers) on the DESTROYER, and the very next attacker
    /// of the destroyer rides +3 to hit — read through the existing fold.
    #[test]
    fn a_wiped_carrier_banks_its_start_size_on_the_destroyer() {
        let (st, statics) = line(CURRENT_RULES_EPOCH);
        let (next, shot) = volley(&st, &statics, "p2_0_b", CURRENT_RULES_EPOCH);
        assert_eq!(next.alive[idx(&next, "p2_0_b")], 0, "the fixture wipes the carrier");
        assert_eq!(
            vs_hit(&next, &statics, idx(&next, "p1_0_a"), CURRENT_RULES_EPOCH),
            3,
            "3 start models banked: every attacker of the destroyer rides +3 to hit"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Vengeance")),
            "the logging-rule line: {:?}",
            shot.log
        );
    }

    /// Control: the same body WITHOUT the rule banks nothing, wiped or not.
    #[test]
    fn a_wiped_non_carrier_banks_nothing() {
        let (st, statics) = line(CURRENT_RULES_EPOCH);
        let (next, shot) = volley(&st, &statics, "p2_1_c", CURRENT_RULES_EPOCH);
        assert_eq!(next.alive[idx(&next, "p2_1_c")], 0, "the fixture wipes the control too");
        assert_eq!(
            vs_hit(&next, &statics, idx(&next, "p1_0_a"), CURRENT_RULES_EPOCH),
            0,
            "no Vengeance, no markers: the destroyer stays unmarked"
        );
        assert!(shot.log.iter().all(|l| !l.contains("Vengeance")), "no log line");
    }

    /// The epoch gate. A record stamped below `EPOCH_7_TABLE_RULES` banks no
    /// markers and logs nothing — the frozen-constant rule, so no earlier
    /// corpus moves.
    #[test]
    fn an_epoch_6_record_banks_no_markers() {
        let (st, statics) = line(6);
        let (next, shot) = volley(&st, &statics, "p2_0_b", 6);
        assert_eq!(next.alive[idx(&next, "p2_0_b")], 0, "the wipe itself is epoch-blind");
        assert_eq!(
            vs_hit(&next, &statics, idx(&next, "p1_0_a"), 6),
            0,
            "rules_epoch 6 replays byte-exact: no markers banked"
        );
        assert!(shot.log.iter().all(|l| !l.contains("Vengeance")), "no log line");
    }

    /// The table bridge. `AiActRecorder._ledger_of` exports the marker pool
    /// (`unit_properties["vengeance_markers"]`, main.gd:5898) and a replayed
    /// act must read it back: markers the TABLE banked two activations ago
    /// cannot silently vanish between acts (the #498 divergence shape, one
    /// marker at a time).
    #[test]
    fn the_ledger_restores_markers_already_on_the_table() {
        let plain = PLAIN.replace(
            r#""p2_0_b":{"player":2,"#,
            r#""p2_0_b":{"ledger":{"vengeance_markers":2},"player":2,"#,
        );
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(&plain, &mut cache, &mut roster).expect("state");
        let b = idx(&st, "p2_0_b");
        assert_eq!(st.vengeance_markers[b], 2, "the table's marker pool survives the fold");
        let statics = statics_of(&st, CURRENT_RULES_EPOCH);
        assert_eq!(vs_hit(&st, &statics, b, CURRENT_RULES_EPOCH), 2,
            "every attacker of the marked unit rides +2 to hit, straight off the ledger");
    }

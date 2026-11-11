//! Rules 3.6 lane ux tests for the rollout module; owned by lane ux.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::state::Objective;
use crate::terrain::PlainTerrain;

    // ---------------- UX-16: a spawned unit cannot hold a marker yet ---
    //
    // Rules 3.6: a unit Spawn places can neither seize nor contest an
    // objective in the round it appears. The core reuses the Ambush arrival
    // stamp: `spawn_round_start` arrives the copy through
    // `deployment::arrive_unit`, which writes `ambush_arrived_round`, and
    // `can_hold_marker` (the gate every seize path reads) drops the unit for
    // that round. Split has no core beat (only the table creates that unit),
    // so it has no leg here.
    //
    // THE FIXTURE. `p1_0_a` carries `Spawn(Rat Swarm [2])` and stands at the
    // origin; the named template is a two-model unit. `p2_0_b` is a plain
    // enemy that is moved onto the marker under the fresh copy.
    const CARRIER: &str = r#""p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":2,"wounds_max":[2,2,2],"model_count":3,"caster_value":0,"base_radius":0.02,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":["Spawn(Rat Swarm [2])"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;
    const ENEMY: &str = r#""p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.02,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;
    const TEMPLATE: &str = r#""spawn:p1_0_a:Spawn(Rat Swarm [2])":{"unit_id":"spawn:p1_0_a:Spawn(Rat Swarm [2])","name":"Rat Swarm","quality":4,"defense":3,"tough":1,"wounds_max":[4,4],"model_count":2,"caster_value":0,"base_radius":0.03,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;
    const PLAIN: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{"p1_0_a":{"player":1,"alive":3,"wounds":[2,2,2],"radii":[0.02,0.02,0.02],"positions":[[0.0,0.0,0.0],[0.05,0.0,0.0],[-0.05,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},"p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],"positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn empty_board() -> Terrain {
        let plain: PlainTerrain = serde_json::from_value(serde_json::json!({
            "cells": [], "sandbox": [], "walls": [],
            "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0,
                            "grid_size_inches": 6.0, "inches_to_meters": crate::IN2M},
        }))
        .expect("plain terrain");
        Terrain::build(&plain)
    }

    /// The Spawn beat at `round` and `epoch`; then the carrier steps far away,
    /// the enemy stands on a marker under the fresh copy, and the enemy holds it.
    fn contested_marker_after_spawn(epoch: u32, round: i64) -> (State, Vec<i64>, usize) {
        let header = read_act_header(&format!(
            r#"{{"kind":"header","knobs":{{"rules_epoch":8}},"profiles":{{{CARRIER},{ENEMY},{TEMPLATE}}}}}"#
        ))
        .expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let mut st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        st.round = round;
        spawn_round_start(&statics, &empty_board(), Seams { rules_epoch: epoch, ..Seams::default() }, &mut st);
        let j = idx(&st, "spawn:p1_0_a:Spawn(Rat Swarm [2])");
        let at = st.positions[j][0];
        let carrier = idx(&st, "p1_0_a");
        st.positions[carrier] = vec![[1.5, 0.0, 1.0]; 3];
        let enemy = idx(&st, "p2_0_b");
        st.positions[enemy] = vec![at];
        st.objectives = vec![Objective { pos: [at[0], 0.0, at[2]], owner: 2 }];
        (st, vec![2], j)
    }

    #[test]
    fn a_freshly_spawned_unit_cannot_contest_on_its_placement_round_at_epoch_73() {
        let (mut st, mut owners, j) = contested_marker_after_spawn(EPOCH_73_V36, 2);
        assert_eq!(st.ambush_arrived_round[j], 2, "the copy carries the arrival stamp");
        playout_seize(&mut st, &mut owners);
        assert_eq!(owners, vec![2], "placed by Spawn this round: the enemy keeps the marker uncontested");
        st.round = 3;
        playout_seize(&mut st, &mut owners);
        assert_eq!(owners, vec![0], "from the next round on the copy contests like any unit");
    }

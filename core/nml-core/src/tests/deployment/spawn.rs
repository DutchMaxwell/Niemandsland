use super::*;

    // --------------------------------------------------- Spawn (wave 4, S5) ---
    //
    // PART (a) — the loader seam (SPAWN_DESIGN_2026-09-08 §3.1/§3.2(b), PR 2a).
    // The record's header grows ONE optional map, `spawn_profiles`, keyed
    // `spawn:<carrier_key>:<rule_string>`, values in the ordinary unit shape.
    // The map indexes into the SAME immutable `Profiles` table the roster
    // reads, behind `EPOCH_8_PLANNER_MENU`. A record at epoch >= 8 whose
    // standing Spawn carrier finds no matching template is REFUSED at load —
    // the ruling of record, never a silent fallback to the carrier's profile
    // (review-7's HOLD on #823). The beat that mints the copy is part (b).
    //
    // The FIXTURE. `p1_0_a` is a ratmen_clans carrier of three 2-wound models
    // standing around the origin, carrying `Spawn(Rat Swarm [2])`; the named
    // template is a TWO-model, four-wound unit — every stat differs from the
    // carrier's, so a bearer-copy fallback cannot hide. `p2_0_b` a plain
    // enemy. The JSON snippets are SINGLE-LINE on purpose: `read_nodes` reads
    // its corpus with `BufRead::lines()`, so one record is one physical line.
    const CARRIER: &str = r#""p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":2,"wounds_max":[2,2,2],"model_count":3,"caster_value":0,"base_radius":0.02,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":["Spawn(Rat Swarm [2])"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;
    const ENEMY: &str = r#""p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.02,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;
    const TEMPLATE: &str = r#""spawn:p1_0_a:Spawn(Rat Swarm [2])":{"unit_id":"spawn:p1_0_a:Spawn(Rat Swarm [2])","name":"Rat Swarm","quality":4,"defense":3,"tough":1,"wounds_max":[4,4],"model_count":2,"caster_value":0,"base_radius":0.03,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;

    /// The act-corpus header: the template rides next to the base profiles,
    /// and the header's own `knobs.rules_epoch` is the CURRENT one, so
    /// `read_act_header` indexes the map exactly as an epoch-8 record loads.
    fn act_header() -> String {
        format!(
            r#"{{"kind":"header","knobs":{{"rules_epoch":8}},"profiles":{{{CARRIER},{ENEMY},{TEMPLATE}}}}}"#
        )
    }

    const PLAIN: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{"p1_0_a":{"player":1,"alive":3,"wounds":[2,2,2],"radii":[0.02,0.02,0.02],"positions":[[0.0,0.0,0.0],[0.05,0.0,0.0],[-0.05,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},"p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],"positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(&act_header()).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    fn seams_at(epoch: u32) -> Seams {
        Seams { rules_epoch: epoch, ..Seams::default() }
    }

    /// A one-node nodes corpus off the fixture: `with_map` ships the header's
    /// `spawn_profiles`, `epoch` is the record's own `seams.rules_epoch`.
    fn corpus(epoch: u32, with_map: bool) -> String {
        let map = if with_map {
            format!(r#","spawn_profiles":{{{TEMPLATE}}}"#)
        } else {
            String::new()
        };
        let node = format!(
            r#"{{"state_before":{PLAIN},"state_after":{PLAIN},"action":{{"kind":0,"unit":"p1_0_a"}},"score":0.0,"player":1}}"#
        );
        format!(
            r#"{{"profiles":{{{CARRIER},{ENEMY}}},"seams":{{"rules_epoch":{epoch}}}{map}}}
{node}
"#
        )
    }

    /// 1. THE READ, and its epoch gates. `place_in` and `once_per_game` come
    /// off the shipped registry entry through the production path; below
    /// `EPOCH_7_TABLE_RULES` the carrier reads as no carrier at all. The
    /// NAMED target (`raw`/`name`/`count`, parsed off the raw rule string) is
    /// `EPOCH_8_PLANNER_MENU`'s read: an epoch-7 record parses no target, so
    /// nothing ever looks up a template it cannot have.
    #[test]
    fn the_registry_read_is_gated_on_the_frozen_epoch() {
        let (st, now) = line(CURRENT_RULES_EPOCH);
        let (_, before) = line(6);
        let (_, at7) = line(7);
        let i = idx(&st, "p1_0_a");
        let pi = st.roster.profile[i];
        assert_eq!(now[pi].spawn.place_in, 6.0, "the reach, off the entry");
        assert!(now[pi].spawn.once_per_game, "and the once-per-game param it ships with");
        assert_eq!(now[pi].spawn.raw, "Spawn(Rat Swarm [2])", "the raw string, the map's key half");
        assert_eq!(now[pi].spawn.name, "Rat Swarm", "the NAMED target off the raw string");
        assert_eq!(now[pi].spawn.count, 2, "and its bracketed model count");
        assert_eq!(before[pi].spawn.place_in, 0.0, "epoch 6 reads no carrier");
        assert_eq!(at7[pi].spawn.name, "", "epoch 7 reads no target — the template seam is epoch 8's");
        // The neighbour that must NOT resolve: a unit without the name is no
        // carrier, whatever its faction's map fields.
        let plain = idx(&st, "p2_0_b");
        assert_eq!(now[st.roster.profile[plain]].spawn.place_in, 0.0, "no name, no reach");
    }

    /// 2. THE LOAD ERROR. An epoch-8 record whose standing Spawn carrier has
    /// no matching `spawn:` template is REFUSED AT LOAD — the loader's twin
    /// of `roster_of`'s unknown-key error. RED while the loader ignored the
    /// map: the same bytes loaded fine and left the beat to fall back to the
    /// carrier's own profile — the exact #823 break, now loud instead.
    #[test]
    fn an_epoch_8_record_without_the_template_is_refused_at_load() {
        let corpus = corpus(8, false);
        let err = io::read_nodes(corpus.as_bytes(), "test").expect_err("the record is refused");
        assert!(
            err.contains("spawn_profiles"),
            "the error names the missing template: {err}"
        );
        assert!(err.contains("p1_0_a"), "and the carrier it lacks it for: {err}");
    }

    /// 3. THE MAP INDEXES. The same record WITH the map loads, and the
    /// template lands in the profile table under its `spawn:` key — the beat
    /// resolves it from there. The copy earns no roster slot: no unit key in
    /// the state names it.
    #[test]
    fn the_header_map_indexes_into_the_profile_table() {
        let corpus = corpus(8, true);
        let nodes = io::read_nodes(corpus.as_bytes(), "test").expect("the record loads");
        let key = "spawn:p1_0_a:Spawn(Rat Swarm [2])";
        let ti = *nodes.profiles.index.get(key).expect("the template is indexed");
        assert_eq!(nodes.profiles.list[ti].name, "Rat Swarm", "the NAMED unit's profile");
        assert_eq!(nodes.profiles.list[ti].model_count, 2, "and its own shape");
        // The act-corpus loader reads the same map the same way.
        let header = read_act_header(&act_header()).expect("the act header loads");
        let ti = *header.profiles.index.get(key).expect("the template is indexed");
        assert_eq!(header.profiles.list[ti].name, "Rat Swarm");
    }

    /// 4. BELOW THE GATE THE MAP IS NOT READ. An epoch-7 header carrying the
    /// map still loads, and the map never reaches the profile table — the
    /// byte-identity every pre-epoch-8 corpus leans on.
    #[test]
    fn an_epoch_7_header_ignores_the_map() {
        let corpus = corpus(7, true);
        let nodes = io::read_nodes(corpus.as_bytes(), "test").expect("the record loads");
        assert!(
            !nodes.profiles.index.contains_key("spawn:p1_0_a:Spawn(Rat Swarm [2])"),
            "the map is not read below the gate"
        );
    }

    /// 4b. THE CROWD. The same board plus `p3_0_c`, eight wide friendly bases
    /// tiled around the anchor, so no free lattice point (`best_spot`'s
    /// 0.025 m step) is left inside the 6" circle.
    const CROWD: &str = r#""p3_0_c":{"unit_id":"p3_0_c","name":"C","quality":4,"defense":3,"tough":1,"wounds_max":[1,1,1,1,1,1,1,1],"model_count":8,"caster_value":0,"base_radius":0.22,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#;

    const CROWDED: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","units":{"p1_0_a":{"player":1,"alive":3,"wounds":[2,2,2],"radii":[0.02,0.02,0.02],"positions":[[0.0,0.0,0.0],[0.05,0.0,0.0],[-0.05,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0},"ledger":{}},"p2_0_b":{"player":2,"alive":1,"wounds":[1],"radii":[0.02],"positions":[[1.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},"p3_0_c":{"player":1,"alive":8,"wounds":[1,1,1,1,1,1,1,1],"radii":[0.22,0.22,0.22,0.22,0.22,0.22,0.22,0.22],"positions":[[-0.08,0.0,-0.08],[0.0,0.0,-0.08],[0.08,0.0,-0.08],[-0.08,0.0,0.0],[0.08,0.0,0.0],[-0.08,0.0,0.08],[0.0,0.0,0.08],[0.08,0.0,0.08]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#;

    fn line_crowded(epoch: u32) -> (State, Vec<UnitStatic>) {
        let header = read_act_header(&format!(
            r#"{{"kind":"header","knobs":{{"rules_epoch":8}},"profiles":{{{CARRIER},{ENEMY},{CROWD},{TEMPLATE}}}}}"#
        ))
        .expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = io::state_from_json(CROWDED, &mut cache, &mut roster).expect("state");
        let statics = statics_of(&st, epoch);
        (st, statics)
    }

    /// One round-start beat at `round`, on the real driver at the CURRENT
    /// epoch (the #803 pattern: the seams carry the gate, never the statics).
    fn beat(statics: &[UnitStatic], board: &Terrain, st: &mut State, round: i64) {
        st.round = round;
        spawn_round_start(statics, board, seams_at(CURRENT_RULES_EPOCH), st);
    }

    /// The table's circle law rebuilt in the test's own arithmetic: every
    /// model base CENTRE within (`place_in` + the anchor's own base radius)
    /// MINUS the copy's base radius of the anchor — the point of the base
    /// FARTHEST from the anchor stays inside the reach — and no base hanging
    /// off the table.
    fn in_reach(p: [f64; 3], r: f64) -> bool {
        let (x1, z1) = (36.0 * crate::IN2M, 24.0 * crate::IN2M);
        let band = 6.0 * crate::IN2M + 0.02;
        (p[0] * p[0] + p[2] * p[2]).sqrt() + r <= band + 1e-9
            && p[0] - r >= -x1 - 1e-6
            && p[0] + r <= x1 + 1e-6
            && p[2] - r >= -z1 - 1e-6
            && p[2] + r <= z1 + 1e-6
    }

    /// 5. THE FROZEN RECORD. An epoch-7 record WITHOUT the map loads exactly
    /// as it always did: the profile table carries exactly the roster's own
    /// keys, nothing synthesised, and the node state replays — the byte
    /// -identity every pre-epoch-8 record leans on (SPAWN_DESIGN_2026-09-08
    /// §6, the epoch gate's whole point).
    #[test]
    fn an_epoch_7_record_without_the_map_loads_byte_identically() {
        let corpus = corpus(7, false);
        let nodes = io::read_nodes(corpus.as_bytes(), "test").expect("the record loads");
        let mut keys: Vec<&String> = nodes.profiles.index.keys().collect();
        keys.sort();
        assert_eq!(keys.len(), 2, "exactly the roster's own profiles");
        assert_eq!(keys[0], "p1_0_a");
        assert_eq!(keys[1], "p2_0_b");
        let st = &nodes.nodes[0].state_before;
        assert_eq!(st.units(), 2, "both units replay");
        assert_eq!(st.alive[idx(st, "p1_0_a")], 3, "the carrier's models are untouched");
    }

    // ------------------------------------------------------------- PART (b) ---
    //
    // THE BEAT (SPAWN_DESIGN_2026-09-08 §3.3/§3.4/§3.5, PR 2b). The round
    // boundary — the S5 beat's home, right after the part-3 Reinforcement
    // driver — resolves the carrier's template off part (a)'s map and MINTS
    // the NAMED unit as a brand-new State slot beside the standing carrier:
    // nothing is withdrawn (the table's summon CREATES a second unit,
    // main.gd:17525), the copy is the TEMPLATE's statics inside the `place_in`
    // CIRCLE around the anchor (`ArrivalZone::Circle`, §3.5, the anchor's own
    // base radius folded into `radius_m`), table-clamped with occupancy
    // respected, once per game on the shared `reinforcement_used` latch, and
    // stamped with the #803 `ambush_arrived_round` so the copy is census- and
    // objective-excluded on its arrival round.
    //
    // #823's bearer-copy expectations were the fidelity break, so their
    // assertions changed shape: where the held branch asserted the CARRIER's
    // own index arriving as the copy (`st.alive[i] == 2`, the carrier gone),
    // these assert the carrier STANDS (alive 3, positions untouched) beside a
    // NEW roster slot whose stats are the template's — every one different
    // from the carrier's, so no bearer-copy fallback can hide.

    /// 6. THE NAMED COPY. The beat mints the TEMPLATE's unit, not the
    /// carrier's and not a rebuild of the carrier's statics: full starting
    /// size, wounds and base radius off the `spawn:` profile the record
    /// header shipped. RED while no beat exists at all.
    #[test]
    fn the_beat_mints_the_templates_unit_and_the_carrier_stands() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        beat(&statics, &board, &mut st, 1);
        assert_eq!(st.units(), 3, "the copy is a brand-new State slot");
        let j = idx(&st, "spawn:p1_0_a:Spawn(Rat Swarm [2])");
        assert_ne!(j, i, "the copy is not the carrier's slot");
        assert_eq!(st.player[j], 1, "the copy fights for the carrier's side");
        assert!(
            !st.dormant[j] && st.alive[j] == 2,
            "the TEMPLATE's model count (2), not the carrier's (3)"
        );
        assert_eq!(st.wounds[j], vec![4, 4], "the TEMPLATE's full wounds, not the carrier's [2,2,2]");
        assert_eq!(st.radii[j], vec![0.03, 0.03], "the TEMPLATE's base radius, not the carrier's 0.02");
        assert_eq!(st.ambush_arrived_round[j], 1, "stamped with the arrival round (#803)");
        assert!(
            !st.dormant[i] && st.reinforcement_used[i] && st.alive[i] == 3,
            "the carrier stands, spent once"
        );
        for m in &st.positions[j] {
            assert!(in_reach(*m, 0.03), "model at {m:?} is outside the 6\" reach of the anchor");
        }
    }

    /// 7. THE ZONE BINDS — the f1f1b15d pattern. The 6" circle around the
    /// anchor is crowded edge to edge with wide friendly bases, so
    /// `best_spot`'s lattice has no free point left inside it. A plain
    /// table-wide rectangle would find the open midfield at once and this
    /// test FALLS; the real zone refuses it and the summon is simply not
    /// made — a summon is never half-made, and the latch is not spent.
    #[test]
    fn no_summon_when_the_six_inch_circle_is_crowded() {
        let (mut st, statics) = line_crowded(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        let before = st.clone();
        beat(&statics, &board, &mut st, 1);
        assert_eq!(st.units(), 3, "no free spot in the circle, so no copy");
        assert!(
            !st.reinforcement_used[i],
            "and the once-per-game latch is NOT spent"
        );
        assert_eq!(
            st.positions[i], before.positions[i],
            "the carrier stands exactly where it stood"
        );
        let c = idx(&st, "p3_0_c");
        assert_eq!(st.alive[c], 8, "the crowd is untouched");
    }

    /// 8. ONCE PER GAME. The registry entry's `once_per_game` is the clause —
    /// a second boundary does not mint a second copy. RED: drop the latch and
    /// every boundary duplicates the carrier.
    #[test]
    fn the_second_summon_is_refused() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        beat(&statics, &board, &mut st, 1);
        let i = idx(&st, "p1_0_a");
        assert!(st.reinforcement_used[i], "spent once");
        beat(&statics, &board, &mut st, 2);
        assert_eq!(st.units(), 3, "still exactly the one copy");
    }

    /// 9. THE EPOCH-7 GATE. The named-template seam is `EPOCH_8_PLANNER_MENU`'s
    /// (a new unit in the rollout changes later menus), not #823's epoch-7: a
    /// record stamped 7 crosses the boundary exactly as it was recorded — no
    /// beat, no template lookup, byte-identical. The statics are built at the
    /// CURRENT epoch (target parsed) and only the seams say 7, so this pins
    /// the GATE, not a statics accident.
    #[test]
    fn an_epoch_7_record_never_spawns() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let i = idx(&st, "p1_0_a");
        let before = st.clone();
        st.round = 1;
        spawn_round_start(&statics, &board, seams_at(7), &mut st);
        assert_eq!(st.positions, before.positions, "an epoch-7 record replays byte-identical");
        assert_eq!(st.units(), before.units(), "and mints no unit at all");
        assert!(!st.reinforcement_used[i], "nor stamps a flag no epoch-7 corpus carries");
    }

    /// 10. NO NAME, NO SUMMON. A unit without the name — even on a board where
    /// a copy would fit — spawns nothing and is not the template's reader.
    #[test]
    fn a_unit_without_the_name_spawns_nothing() {
        let (mut st, statics) = line(CURRENT_RULES_EPOCH);
        let board = empty_board();
        let j = idx(&st, "p2_0_b");
        let before = st.clone();
        beat(&statics, &board, &mut st, 1);
        assert_eq!(st.positions[j], before.positions[j], "the plain unit stands still");
        assert_eq!(st.units(), before.units(), "and no copy appeared");
        assert!(!st.reinforcement_used[j], "no latch was spent on it");
    }

    /// 11. THE WIRING, not the rule: the beat has to run at the core's REAL
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
        assert_eq!(end.units(), 3, "the standing carrier spawned a copy at the boundary");
        assert!(end.reinforcement_used[i], "the once-per-game latch spent");
        assert!(!end.dormant[i], "the carrier still stands — nothing was withdrawn");
        let j = idx(end, "spawn:p1_0_a:Spawn(Rat Swarm [2])");
        assert_eq!(end.alive[j], 2, "a full-strength copy of the TEMPLATE stands");
    }

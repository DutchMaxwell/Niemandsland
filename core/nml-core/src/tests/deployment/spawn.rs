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

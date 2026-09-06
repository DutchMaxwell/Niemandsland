    use super::*;

    /// THE TRAP. Two trays on one seed: burning a zero-die roll must cost
    /// exactly one draw, so the first tray's next three faces are the second's
    /// faces 2..4.
    #[test]
    fn a_zero_die_roll_burns_exactly_one_draw() {
        let mut burned = Tray::seeded(27);
        let mut straight = Tray::seeded(27);
        let zero = burned.roll(0);
        assert_eq!(zero.len(), 1, "maxi(1, count): a zero-die roll still rolls one");
        assert_eq!(burned.roll(3), straight.roll(4)[1..].to_vec());
        assert_eq!(burned.state_i64(), straight.state_i64(), "and only one");
    }

    /// RED PROOF for the rule above: the same two trays with `count` taken
    /// literally. The zero-die roll then costs nothing and every later face is
    /// off by one draw.
    #[test]
    fn red_proof_dropping_the_max_1_rule_shifts_the_stream() {
        let mut naive = GodotRng::new(27);
        let zero_count = 0usize; // `count` taken literally, without `maxi(1, ..)`
        let naive_zero: Vec<u8> =
            (0..zero_count).map(|_| naive.randi_range(1, 6) as u8).collect();
        assert!(naive_zero.is_empty(), "the naive form draws nothing for count 0");
        let after: Vec<u8> = (0..3).map(|_| naive.randi_range(1, 6) as u8).collect();
        let first_four = Tray::seeded(27).roll(4);
        assert_eq!(after, first_four[..3].to_vec(), "the naive form reads faces 1..3");
        assert_ne!(after, first_four[1..].to_vec(), "the table reads faces 2..4 — a shift");
    }

    #[test]
    fn every_face_is_a_d6_face_and_the_stream_is_deterministic() {
        let mut a = Tray::seeded(1_099_511_627_783);
        let mut b = Tray::seeded(1_099_511_627_783);
        let fa = a.roll(600);
        assert_eq!(fa.len(), 600);
        assert!(fa.iter().all(|&f| (1..=6).contains(&f)), "faces outside 1..=6");
        assert_eq!(fa, b.roll(600), "same seed, same faces");
        // Uniform enough that a broken mapping (e.g. `% 6` without the +1)
        // cannot hide: all six faces must actually appear.
        for face in 1u8..=6 {
            assert!(fa.contains(&face), "face {face} never came up in 600 rolls");
        }
    }

    /// A tray is `randi_range(1, 6)` on the twin and nothing else — one draw
    /// per die, in order, sharing the generator's state.
    #[test]
    fn the_tray_is_randi_range_1_6_on_the_twin() {
        let mut tray = Tray::seeded(12345);
        let mut rng = GodotRng::new(12345);
        let faces = tray.roll(64);
        let want: Vec<u8> = (0..64).map(|_| rng.randi_range(1, 6) as u8).collect();
        assert_eq!(faces, want);
        assert_eq!(tray.state_i64(), rng.state_i64());
    }


    /// A plain rifle: `quality`+ to hit at `defense`+ to save, nothing else.
    fn rifle(attacks: i64) -> ShootProfile {
        ShootProfile { name: "Rifle".into(), attacks, count: 1, range: 24, ..Default::default() }
    }

    fn shooter(quality: i64) -> Ctx {
        Ctx { quality, ..Default::default() }
    }

    fn defender(defense: i64, models: i64) -> Ctx {
        Ctx { defense, models, tough: 1, ..Default::default() }
    }





    /// One AP(1) rifle round — the volley leg's probe weapon.
    fn ap_rifle(attacks: i64) -> ShootProfile {
        ShootProfile { ap: 1, ..rifle(attacks) }
    }

    /// `DiceRules.is_success` in full: the natural 6 beats an impossible
    /// target, the natural 1 fails an automatic one, and `TARGET_NONE` counts
    /// nothing.

    fn blade(attacks: i64) -> ShootProfile {
        ShootProfile { name: "Blade".into(), attacks, count: 1, range: 0, ..Default::default() }
    }

    fn striker<'a>(profiles: &'a [ShootProfile], keep: &'a [usize], attacks: &'a [i64],
                   att: &'a Ctx) -> Shooter<'a> {
        Shooter { profiles, keep, attacks, att, owner: "Striker" }
    }

    fn faces_of(r: &ShootResult) -> Vec<u8> {
        r.rolls.iter().flat_map(|x| x.faces.clone()).collect()
    }




    /// ONE volley call at `d` inches, gate switch explicit: every RED/GREEN
    /// leg below names which epoch's reading it asserts.
    fn surge_volley(
        p: &[ShootProfile],
        quality: i64,
        d: f64,
        gates: bool,
        tray: &mut Tray,
    ) -> ShootResult {
        resolve_volley_with_tray(
            &[Shooter { profiles: p, keep: &[0], attacks: &[8], att: &shooter(quality), owner: "" }],
            &defender(4, 5), "Target", d, d, true, gates, true, true, tray,
        )
    }




    use crate::acts::read_act_header;
    use crate::rules::Registries;
    use crate::unit::UnitStatic;

    /// The checkout this crate lives in — mirrors the unit.rs tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// Block C2's fixture, end to end through the REAL registry: a Good Fighter
    /// carrier (aof/goblins, `{hit_bonus: 1, melee_only: true}`), a Precision
    /// Charge Aura carrier (gf/orc_marauders, `{hit_bonus: 1, when: "charge"}`)
    /// and a plain rule-less unit — each with a rifle and a blade, so the melee
    /// stamp and the shooting non-stamp are both observable.
    const C2_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "good_fighter":{"unit_id":"good_fighter","name":"Good Fighter","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"goblins",
        "special_rules":["Good Fighter"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "charge_aura":{"unit_id":"charge_aura","name":"Charge Aura","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"orc_marauders",
        "special_rules":["Precision Charge Aura"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain":{"unit_id":"plain","name":"Plain","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn c2_static(id: &str) -> UnitStatic {
        let header = read_act_header(C2_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build(&mut reg, p)
    }


    /// Block C3's fixture, end to end through the REAL registry: a Buccaneer
    /// carrier (aof/sky_city_dwarves, `{hit_bonus: 1, over_in: 9}`) and a
    /// Targeting Visor Boost carrier (gf/dao_union, `{hit_bonus: 1}`), each
    /// with one 24" rifle.
    const C3_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "buccaneer":{"unit_id":"buccaneer","name":"Buccaneer","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"sky_city_dwarves",
        "special_rules":["Buccaneer"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "visor_boost":{"unit_id":"visor_boost","name":"Visor Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"dao_union",
        "special_rules":["Targeting Visor Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn c3_static(id: &str) -> UnitStatic {
        let header = read_act_header(C3_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build(&mut reg, p)
    }


    /// The wave-3 runtime-gated fixture, end to end through the REAL registry:
    /// a Mobile Artillery carrier (aof/ossified_undead, `{hit_bonus: 1,
    /// over_in: 9, requires_stationary: true}`) and a Grounded Precision
    /// carrier (gf/soul_snatcher_cults, `{hit_bonus: 1, terrain_within_in: 1,
    /// all_attacks: true}`), each with a 24" rifle and a blade, so the shoot
    /// fold and the all-attacks melee fold are both observable.
    const C6_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "mobile_artillery":{"unit_id":"mobile_artillery","name":"Mobile Artillery","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ossified_undead",
        "special_rules":["Mobile Artillery"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "grounded_precision":{"unit_id":"grounded_precision","name":"Grounded Precision","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"soul_snatcher_cults",
        "special_rules":["Grounded Precision"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn c6_static(id: &str, epoch: u32) -> UnitStatic {
        let header = read_act_header(C6_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    // path now folds `cond_ap` too, not just `profile_ev`'s EV imagination.

    /// One fixture per condition kind, each pulled from the REAL gf registry
    /// (`rules_mechanics_gf.json`) so the `ap_bonus`/`condition`/`gate` values
    /// are the book's own, not a synthetic `CondAp` literal.
    const COND_AP_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "piercing_assault":{"unit_id":"piercing_assault","name":"Piercing Assault","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Piercing Assault"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "melee_slayer":{"unit_id":"melee_slayer","name":"Melee Slayer","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blood_prime_brothers",
        "special_rules":["Melee Slayer"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "piercing_hunter":{"unit_id":"piercing_hunter","name":"Piercing Hunter","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Piercing Hunter"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "slayer":{"unit_id":"slayer","name":"Slayer","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"dao_union",
        "special_rules":["Slayer"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn cond_ap_static(id: &str) -> UnitStatic {
        let header = read_act_header(COND_AP_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build(&mut reg, p)
    }

    // 6 -> dice.rs::save_batch's `shred_alias_dice` epoch gate). One RED/GREEN
    // pair per ported name: the alias shreds at `rules_epoch =
    // CURRENT_RULES_EPOCH` (what a fresh play_game() stamps), stays silent at
    // epoch 0 (every pre-port corpus) and without the rule.

    /// Fixtures pulled from the REAL registries — `Destroyer` is an aof ogres
    /// faction entry, `Infected` a gf infected_colonies one, `Warbound` a gf
    /// war_disciples one, the two scoped halves live in gf's COMMON block
    /// (lookup's faction->common fallback fields them for any faction).
    const SHRED_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "destroyer":{"unit_id":"destroyer","name":"Destroyer","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres",
        "special_rules":["Destroyer"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "plain_ogre":{"unit_id":"plain_ogre","name":"Plain Ogre","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "infected":{"unit_id":"infected","name":"Infected","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"infected_colonies",
        "special_rules":["Infected"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "warbound":{"unit_id":"warbound","name":"Warbound","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"war_disciples",
        "special_rules":["Warbound"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "warbound_boost":{"unit_id":"warbound_boost","name":"Warbound Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"war_disciples",
        "special_rules":["Warbound","Warbound Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "warbound_boost_only":{"unit_id":"warbound_boost_only","name":"Warbound Boost Only","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"war_disciples",
        "special_rules":["Warbound Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "destroyer_boost":{"unit_id":"destroyer_boost","name":"Destroyer Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres",
        "special_rules":["Destroyer","Destroyer Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "infected_boost":{"unit_id":"infected_boost","name":"Infected Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"infected_colonies",
        "special_rules":["Infected","Infected Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "shred_melee":{"unit_id":"shred_melee","name":"Shred in Melee","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Shred in Melee"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "shred_shooting":{"unit_id":"shred_shooting","name":"Shred when Shooting","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Shred when Shooting"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
      "plain_gf":{"unit_id":"plain_gf","name":"Plain","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn shred_static(id: &str) -> UnitStatic {
        let header = read_act_header(SHRED_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build(&mut reg, p)
    }

    // -> dice.rs::save_batch's `shred_low` window, the volley's
    // `shred_boost_dice` gate at the LITERAL epoch 4). One RED/GREEN set per
    // ported name: the widened 1-2 window fires over the entry's own 9" at
    // epoch 4, stays the base 1s window at epoch 3 (`rule_on(3, 4)` — the
    // frozen EPOCH_3_TABLE_RULES reading, spelled in LITERALS so the test
    // keeps its meaning after the next epoch bump) and without the rule;
    // exactly 9" is not "over" and stays shut.

    /// The seed the Boost tests share — picked so the save batch lands 1s
    /// AND failing 2s (the widened window's whole point).
    const SHRED_BOOST_SEED: i64 = 3;

    // ::build_for's epoch-6 arm -> dice.rs::save_batch's wound-amount
    // multiply, the entry's own `extra_wound_per_save_one`). One RED/GREEN
    // test per ported name, on a fixture registry whose entry says 2: the
    // shipped books all say 1, which is exactly the +1 the wave-1 alias arm
    // hard-codes, so a real-book run cannot tell the read apart. At the
    // LITERAL epoch 6 the entry's param is the per-face cost; at the LITERAL
    // epoch 5 the read is gated off and the wave-1 base +1 replays (the
    // alias already shreds at 5 — earlier epochs stay byte-exact); a non-
    // carrier on the same seed never shreds. The firing names itself in
    // ShootResult.log (rules-must-log) at 6, stays silent at 5.

    fn shred_param_registry(tag: &str, system: &str, faction: &str, name: &str) -> String {
        let dir = std::env::temp_dir().join(format!("nml_shred3_{}_{}", tag, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let map_dir = dir.join("assets/solo");
        std::fs::create_dir_all(&map_dir).expect("temp map dir");
        let body = format!(
            r#"{{"common":{{}},"factions":{{"{faction}":{{"{name}":{{"primitive":"Shred","rated":false,"book_version":"3.5.3","params":{{"extra_wound_per_save_one":2}}}}}}}}}}"#
        );
        std::fs::write(map_dir.join(format!("rules_mechanics_{system}.json")), body)
            .expect("write temp mechanics map");
        dir.to_string_lossy().into_owned()
    }

    fn shred_param_built(root: &str, id: &str, epoch: u32) -> UnitStatic {
        let header = read_act_header(SHRED_HEADER).expect("header");
        let mut reg = Registries::new(root);
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build_for(&mut reg, p, epoch)
    }

// Per-family test modules (wave-4 layout): one file per family, so two
// family PRs in the same wave never append to the same region. A new
// family adds ONE line to this ALPHABETICAL list plus its own file; the
// fixtures every family shares stay here, in the module root.
mod fortified;
mod growth_markers;
mod melee_impact_order;
mod morale_dice;
mod rung_i_dice;
mod shooting_order;
mod shot_modifier;
mod shot_modifier_flat;
mod shot_modifier_melee;
mod shot_modifier_runtime;
mod shred_alias;
mod shred_boost;
mod shred_per_save_one;
mod stealth_alias;
mod surge_extra_attack;
mod surge_gates;
mod surge_low_gate;
mod unpredictable_shooter;

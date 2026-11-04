//! Rules 3.6 row G4-C8a: the strike count of a melee phase is the table's `striking_models_for`
//! from `EPOCH_73_V36` on — a model strikes when its base EDGE is within 3" across (and 3" up) of ANY
//! enemy base edge, the enemy being the target host plus its joined heroes. The centre-space fallback
//! (`melee_reach="table"` knob) and the "every alive model strikes" default stay for every older epoch.
//! Fixtures come off the production loaders (`state_from_json`, `UnitStatic::build_for`); the epoch
//! alone decides the measure, no flag is set by hand in the live-seam tests.

mod g4_c8a {
    use super::super::*;
    use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::io;
    use crate::rules::Registries;
    use crate::state::ProfileCache;
    use serde_json::{json, Value};

    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The charger: five models with one melee weapon (five attacks in all). The target: one model;
    /// its joined hero: one model. Every base carries the radius under test.
    fn header(radius: f64) -> String {
        let unit = |id: &str, models: usize, rules: &str| {
            format!(
                r#""{id}":{{"unit_id":"{id}","name":"{id}","quality":4,"defense":4,"tough":1,
                "wounds_max":{w},"model_count":{models},"caster_value":0,"base_radius":{radius},
                "game_system":"gf","faction_folder":"robot_legions","special_rules":[{rules}],
                "item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
                "weapons":[{{"name":"Blade","range":0,"attacks":{models},"count":1,"ap":0,"rules":[]}}]}}"#,
                w = json!(vec![1; models]),
            )
        };
        format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{{},{},{}}}}}"#,
            unit("p1_0_a", 5, ""),
            unit("p2_0_b", 1, ""),
            unit("p2_1_h", 1, "\"Hero\"")
        )
    }

    fn unit(player: i64, pos: &[[f64; 3]], r: f64, attached: &[&str], attached_to: &str) -> Value {
        json!({"player": player, "alive": pos.len(), "wounds": vec![1; pos.len()],
            "radii": vec![r; pos.len()], "positions": pos, "in_cover": false, "shaken": false,
            "fatigued": false, "activated": false, "casts": 0, "morale_bonus": 0,
            "aircraft": false, "dormant": false, "ambush_arrived_round": -1,
            "earliest_arrival_round": -1, "wound_frac": 0.0, "mods": {}, "mods_base": {},
            "bands": {"advance": 6.0, "rush": 12.0}, "ledger": {},
            "attached": attached, "attached_to": attached_to})
    }

    /// Positions on the x axis, the given centre distances from the origin.
    fn line(xs: &[f64]) -> Vec<[f64; 3]> {
        xs.iter().map(|x| [x * IN2M, 0.0, 0.0]).collect()
    }

    /// The charger (unit 0) in a line at `xs` inches, the target host at `host_x` inches and, when
    /// `hero_x` is given, a joined hero at that spot; all bases of radius `r`.
    fn fight(r: f64, xs: &[f64], host_x: f64, hero_x: Option<f64>) -> (State, Vec<UnitStatic>) {
        let mut units = serde_json::Map::new();
        units.insert("p1_0_a".into(), unit(1, &line(xs), r, &[], ""));
        let kids: Vec<&str> = hero_x.iter().map(|_| "p2_1_h").collect();
        units.insert("p2_0_b".into(), unit(2, &line(&[host_x]), r, &kids, ""));
        if let Some(hx) = hero_x {
            units.insert("p2_1_h".into(), unit(2, &line(&[hx]), r, &[], "p2_0_b"));
        }
        let plain = json!({"round": 1, "rounds_total": 4, "scoring": "end", "units": units});
        let head = read_act_header(&header(r)).expect("header");
        let mut cache = ProfileCache::new(head.profiles);
        let mut roster = None;
        let st = io::state_from_json(&plain.to_string(), &mut cache, &mut roster).expect("state");
        let mut reg = Registries::new(&repo_root());
        let statics = st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, EPOCH_73_V36)).collect();
        (st, statics)
    }

    /// The charger's first melee weapon's attack count after the strike scaling of `melee_parts`.
    fn blade_attacks(st: &State, statics: &[UnitStatic], seams: Seams) -> i64 {
        melee_parts(statics, st, 0, 1, seams)[0].1.attacks[0]
    }

    fn at(epoch: u32, knob: bool) -> Seams {
        Seams { rules_epoch: epoch, melee_reach: knob, ..Seams::default() }
    }

    /// 1" bases, the charger's models 2.5" .. 6.5" from the target's centre: edge gaps 0.5 .. 4.5",
    /// so three strike by base edge (the centre measure of 4" would keep only two).
    const WIDE: [f64; 5] = [2.5, 3.5, 4.5, 5.5, 6.5];
    /// 0.25" bases, centres 3.4" .. 5.4" out: edge gaps 2.9 .. 4.9", so ONE strikes by base edge
    /// (the centre measure of 4" would let a second one in).
    const SMALL: [f64; 5] = [3.4, 3.9, 4.4, 4.9, 5.4];

    #[test]
    fn the_live_seam_counts_by_base_edge_at_73_with_no_flag_set() {
        let (st, statics) = fight(0.0254, &WIDE, 0.0, None);
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_73_V36, false)), 3, "3 of 5 models are within 3\" edge to edge");
    }

    #[test]
    fn the_knob_measures_the_base_edge_not_the_centre_at_73() {
        let (st, statics) = fight(0.0254, &WIDE, 0.0, None);
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_73_V36, true)), 3, "a 1\" base 4.5\" out is 2.5\" from the edge");
    }

    #[test]
    fn small_bases_do_not_reach_past_three_inches_edge_to_edge() {
        let (st, statics) = fight(0.00635, &SMALL, 0.0, None);
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_73_V36, false)), 1, "only the 3.4\" centre is within 3\" edge to edge");
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_73_V36, true)), 1, "the knob measures the same edge");
    }

    #[test]
    fn a_joined_enemy_hero_is_a_target_of_the_reach() {
        let (st, statics) = fight(0.0254, &WIDE, 30.0, Some(0.0));
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_73_V36, false)), 3, "the host stands 30\" away; the hero is within reach");
    }

    #[test]
    fn below_73_the_centre_measure_and_the_all_alive_default_stay() {
        let (st, statics) = fight(0.0254, &WIDE, 0.0, None);
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_72_PLAYTEST_RULES, false)), 5, "epoch 72 default: every model strikes");
        assert_eq!(blade_attacks(&st, &statics, at(EPOCH_72_PLAYTEST_RULES, true)), 1, "epoch 72 knob: the 3\" centre measure");
    }
}

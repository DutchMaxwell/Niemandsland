//! Rules 3.6 row UX-18 tests (Bounding aliases) for the unit module; owned by lane ux.
use super::*;

mod ux18 {
    use super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::dice::Tray;
    use crate::io::{Action, Seams};
    use crate::rng::GodotRng;
    use crate::sim::{resolve_stochastic_tray_on_board, ADVANCE};
    use crate::IN2M;
    use std::rc::Rc;

    /// The alias carriers and the book that prints them: name, system, folder.
    const ALIASES: [(&str, &str, &str); 3] = [
        ("Wolfborn", "gf", "wolf_brothers"),
        ("Wave-Step", "aof", "deep_sea_elves"),
        ("Rapid Blink", "gf", "elven_jesters"),
    ];

    fn ux18_profile(rule: &str, system: &str, faction: &str) -> crate::state::Profile {
        crate::state::Profile {
            cost: 0,
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![rule.into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: system.into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: crate::state::MoveBands { advance: 6.0, rush: 12.0, charge: None },
        }
    }

    /// The carrier: a profile whose only rule is the alias, read off the REAL
    /// registry at `epoch`.
    fn ux18_carrier(rule: &str, system: &str, faction: &str, epoch: u32) -> UnitStatic {
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &ux18_profile(rule, system, faction), epoch)
    }

    /// A 6x4 ft board with ONE wall at x = 1.5", running z = -20" .. 20":
    /// right across the straight line from the carrier to its objective and
    /// too long to walk around inside one activation's band. `walls: []`
    /// gives the same board without it.
    fn ux18_board(walls: Vec<[[f64; 2]; 2]>) -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
            sandbox: vec![],
            pieces: vec![],
            walls,
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn ux18_wall() -> Vec<[[f64; 2]; 2]> {
        vec![[[1.5 * IN2M, -20.0 * IN2M], [1.5 * IN2M, 20.0 * IN2M]]]
    }

    /// The carrier "a" as ONE model (0.5" radius) at the origin, the
    /// objective 10" up +x behind the wall.
    fn ux18_line(
        rule: &str, system: &str, faction: &str, epoch: u32,
    ) -> (crate::state::State, Vec<UnitStatic>) {
        let profile = ux18_profile(rule, system, faction);
        let mut index = std::collections::HashMap::new();
        index.insert("a".to_string(), 0);
        let mut pc = crate::state::ProfileCache::new(Rc::new(crate::state::Profiles {
            list: vec![profile],
            index,
        }));
        let mut rc = None;
        let text = r#"{"round":0,"rounds_total":1,
            "objectives":[{"pos":[0.254,0,0]}],
            "units":{"a":{"player":1,"alive":1,"positions":[[0,0,0]],
              "wounds":[1],"radii":[0.0127]}}}"#;
        let st = crate::io::state_from_json_with_epoch(text, &mut pc, &mut rc, epoch)
            .expect("state parses");
        (st, vec![ux18_carrier(rule, system, faction, epoch)])
    }

    /// Seeds are searched, not guessed: the first seeded stream whose first
    /// D3 is a 3, so the roll is 3" (a hop that long clears the wall).
    fn ux18_seed() -> i64 {
        (0i64..).find(|&s| GodotRng::new(s).randi_range(1, 3) == 3).unwrap()
    }

    fn ux18_action(x_in: f64) -> Action {
        Action {
            kind: ADVANCE,
            unit: "a".into(),
            dest: Some([x_in * IN2M, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
            teleport: None,
        }
    }

    /// One fresh-sim ADVANCE toward x = 20" (no recorded trace), the seeded
    /// stream live; returns the landing x in inches, the log and the stream
    /// as the activation left it.
    fn ux18_run(
        rule: &str, system: &str, faction: &str, epoch: u32,
        board: &crate::terrain::Terrain, movement: bool,
    ) -> (f64, Vec<String>, GodotRng) {
        let (st, statics) = ux18_line(rule, system, faction, epoch);
        let mut tray = Tray::seeded(11);
        let mut rng = GodotRng::new(ux18_seed());
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics,
            &st,
            &ux18_action(20.0),
            board,
            Seams { rules_epoch: epoch, movement, ..Seams::default() },
            &mut rng,
            &mut tray,
        )
        .unwrap();
        (next.positions[0][0][0] / IN2M, shot.log, rng)
    }

    /// The OLD leg for every alias: the hop places the carrier on the far side
    /// of the wall before the move, and the log says it was placed.
    #[test]
    fn bounding_aliases_hop_over_a_wall_at_epoch_72() {
        for (rule, system, faction) in ALIASES {
            let (x_in, log, _) =
                ux18_run(rule, system, faction, EPOCH_72_PLAYTEST_RULES, &ux18_board(ux18_wall()), true);
            assert!(x_in > 1.5, "{rule}: the hop placed the unit past the wall: x = {x_in}\"");
            assert!(
                log.iter().any(|l| l.contains(rule) && l.contains("placed")),
                "{rule}: the 72 wording stays: {log:?}"
            );
        }
    }

    /// The NEW leg for every alias: the rolled inches are a move, so the wall
    /// stops the carrier on its own side, and the log says it moves (alias
    /// name in the line, rules-must-log), never that it was placed.
    #[test]
    fn bounding_aliases_cannot_cross_a_wall_at_epoch_73() {
        for (rule, system, faction) in ALIASES {
            let (x_in, log, _) =
                ux18_run(rule, system, faction, EPOCH_73_V36, &ux18_board(ux18_wall()), true);
            assert!(x_in < 1.5, "{rule}: the move stays on its side of the wall: x = {x_in}\"");
            assert!(
                log.iter().any(|l| l.contains(rule) && l.contains("moves up to") && l.contains("rolled 3\"")),
                "{rule}: rules-must-log names the alias and the rolled move: {log:?}"
            );
            assert!(!log.iter().any(|l| l.contains("placed")), "{rule}: no placement at 73: {log:?}");
        }
    }

    /// The NEW leg on an open board: the ADVANCE band grows by exactly the
    /// rolled 3" (6" + D3 3), the table's band model.
    #[test]
    fn bounding_aliases_widen_the_advance_band_by_the_roll_at_epoch_73() {
        for (rule, system, faction) in ALIASES {
            let (x_in, _, _) =
                ux18_run(rule, system, faction, EPOCH_73_V36, &ux18_board(vec![]), false);
            assert!((x_in - 9.0).abs() < 1e-6, "{rule}: band 6\" + the rolled 3\": {x_in}\"");
        }
    }

    /// Both legs take the same dice from the seeded stream: the stream after
    /// the activation is the same at 72 and at 73, for every alias.
    #[test]
    fn bounding_aliases_draw_the_same_dice_at_epoch_72_and_at_epoch_73() {
        for (rule, system, faction) in ALIASES {
            let board = ux18_board(ux18_wall());
            let (_, _, mut rng72) =
                ux18_run(rule, system, faction, EPOCH_72_PLAYTEST_RULES, &board, true);
            let (_, _, mut rng73) =
                ux18_run(rule, system, faction, EPOCH_73_V36, &board, true);
            assert_eq!(
                rng72.randi_range(1, 1_000_000),
                rng73.randi_range(1, 1_000_000),
                "{rule}: the same seeded draws at both epochs"
            );
        }
    }
}

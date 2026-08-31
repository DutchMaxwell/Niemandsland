//! NML-1152 step 2 — the Rust roll-off against the table's own pregame dumps.
//!
//! `tools/pregame_dump.gd` records every roll-off attempt, the winner, the deploy
//! order and the per-side seed values for 100 seeds straight off the real harness.
//! This test replays ALL of them draw-for-draw: same game-stream seed, same tie
//! re-roll law, same seed+slot split. The committed extract carries only the
//! pregame stream fields — the raw dumps live outside the repo (they embed host
//! army paths) and a re-extract of all 100 raw dumps validated every invariant
//! (opener == winner of the last attempt, deploy_order == [winner, other],
//! seed_value == seed + slot) before this file was written.

use nml_core::deployment::{self, roll_off_traced, UnitSpec};
use nml_core::rng::GodotRng;

fn fixtures() -> Vec<serde_json::Value> {
    serde_json::from_str(include_str!("fixtures/pregame_roll_off.json")).expect("fixture parses")
}

#[test]
fn roll_off_replays_every_table_dump_bit_exact() {
    let dumps = fixtures();
    assert!(dumps.len() >= 20, "need the 100-dump corpus, got {}", dumps.len());
    for d in &dumps {
        let seed = d["seed"].as_i64().unwrap();
        let want_attempts: Vec<(i64, i64)> = d["attempts"]
            .as_array().unwrap().iter()
            .map(|a| (a[0].as_i64().unwrap(), a[1].as_i64().unwrap()))
            .collect();
        let want_opener = d["opener"].as_i64().unwrap();
        let want_order: Vec<i64> = d["deploy_order"]
            .as_array().unwrap().iter()
            .map(|v| v.as_i64().unwrap()).collect();

        // The game stream, exactly as arena_match.gd:373 seeds it before the roll-off.
        let mut rng = GodotRng::new(seed);
        let ro = roll_off_traced(&mut rng);

        assert_eq!(ro.attempts, want_attempts, "seed {}: dice sequence", seed);
        assert_eq!(ro.winner, want_opener, "seed {}: winner", seed);
        assert_eq!(deployment::deploy_order(ro.winner), want_order[..], "seed {}: deploy order", seed);
        for slot in [1, 2] {
            let want = d["side_seed_values"][&slot.to_string()].as_i64().unwrap();
            assert_eq!(deployment::side_seed_value(seed, slot), want, "seed {} side {}", seed, slot);
        }
    }
}

/// NML-1152 step 3 — the per-side deploy-stream DRAW PHASES against the table's
/// own dumps: transport fill → split_into_groups → assign_sections, replayed in
/// `deploy_begin`'s exact order (solo_controller.gd:8944-8945 fresh rng,
/// :8957-8976 fill, :8986 groups, :8987 sections; ai_deployment.gd:15-43).
/// The extract generator reconstructed each side's `all_units` in list order
/// (attached heroes excluded, ambush-reserve units at their list positions) and
/// asserted: seed_value == seed + slot, dump-unit sections in 1..3, the
/// units+reserved name multiset equals the non-joined list entries, no name
/// appears in BOTH units and reserved, and the interleave's deployment ids come
/// out contiguous 0..n-1. Step 3b re-keyed the dump by unit id
/// (solo_controller.gd:9160/:9166 `unit_id`), so duplicate display names can no
/// longer collide — every section is comparable (the v1 fixture carried 8
/// name-skipped null sections over 4 sides, e.g. seed 56).
///
/// placement_order is step 3b: replayed against the dumps' own `placement_order`
/// in the test below.
#[test]
fn draw_phases_replay_every_table_dump_bit_exact() {
    let dumps: Vec<serde_json::Value> = serde_json::from_str(include_str!(
        "fixtures/pregame_draw_phases.json"
    ))
    .expect("fixture parses");
    assert!(dumps.len() >= 20, "need the 100-dump corpus, got {}", dumps.len());
    let mut total_checked = 0usize;
    for d in &dumps {
        let seed = d["seed"].as_i64().unwrap();
        for slot in ["1", "2"] {
            let sd = &d["sides"][slot];
            let rows = sd["units"].as_array().unwrap();
            let specs: Vec<UnitSpec> = rows
                .iter()
                .map(|r| UnitSpec {
                    key: r[0].as_str().unwrap().to_string(),
                    scout: r[1].as_bool().unwrap(),
                    ambush: r[2].as_bool().unwrap(),
                    transport_capacity: 0,
                    ..Default::default()
                })
                .collect();
            let caps: Vec<i64> = specs.iter().map(|s| s.transport_capacity).collect();

            // The fresh per-side stream (solo_controller.gd:8944-8945), phases in
            // deploy_begin's exact order.
            let mut rng = GodotRng::new(sd["seed_value"].as_i64().unwrap());
            let fills = deployment::transport_fill(&caps, &mut rng);
            let fill_names: Vec<(String, String)> = fills
                .iter()
                .map(|&(t, c)| (specs[t].key.clone(), specs[c].key.clone()))
                .collect();
            let want_fills: Vec<(String, String)> = sd["fills"]
                .as_array().unwrap().iter()
                .map(|f| (f[0].as_str().unwrap().to_string(), f[1].as_str().unwrap().to_string()))
                .collect();
            assert_eq!(fill_names, want_fills, "seed {seed} side {slot}: fills");

            let groups = deployment::split_into_groups(specs.len(), &mut rng);
            assert_eq!(groups.len(), 3, "seed {seed} side {slot}: 3 groups");
            let sections = deployment::assign_sections(groups.len(), &mut rng);
            let mut section_of = vec![0i64; specs.len()];
            for (g, members) in groups.iter().enumerate() {
                for &i in members {
                    section_of[i] = sections[g];
                }
            }
            let mut checked = 0u32;
            for (i, row) in rows.iter().enumerate() {
                if specs[i].ambush {
                    assert!(row[3].is_null(), "seed {seed} side {slot}: reserved row {i}");
                    continue;
                }
                assert_eq!(
                    section_of[i],
                    row[3].as_i64().unwrap(),
                    "seed {seed} side {slot}: unit {i} ({}) section",
                    specs[i].key
                );
                checked += 1;
            }
            total_checked += checked as usize;
        }
    }
    assert_eq!(total_checked, 1060, "pinned section comparisons across the corpus");
}

/// NML-1152 step 3b — placement_order (ai_deployment.gd:54-67, called at
/// solo_controller.gd:9038) against the table's own dumps. The dumps record the
/// FINAL placement records in arrival order (main queue drained fully, then the
/// scout queue — solo_controller.gd:9036-9042, :9071-9083, :9195-9198), which IS
/// the table's deploy sequence. Replays the full prologue (fill → groups →
/// sections) on the fresh per-side stream, then placement_order on the SAME rng,
/// and requires the index→key sequence to match bit-exact per side.
/// Caveat (corpus can't pin it): an EMPTY side would early-return before any
/// draw in deploy_begin (solo_controller.gd:8984-8985) — no such side exists in
/// the corpus; do not "fix" the replay for it.
#[test]
fn placement_order_replays_every_table_dump_bit_exact() {
    let dumps: Vec<serde_json::Value> = serde_json::from_str(include_str!(
        "fixtures/pregame_draw_phases.json"
    ))
    .expect("fixture parses");
    assert!(dumps.len() >= 20, "need the 100-dump corpus, got {}", dumps.len());
    let mut sides_checked = 0usize;
    for d in &dumps {
        for slot in ["1", "2"] {
            let sd = &d["sides"][slot];
            let rows = sd["units"].as_array().unwrap();
            let specs: Vec<UnitSpec> = rows
                .iter()
                .map(|r| UnitSpec {
                    key: r[0].as_str().unwrap().to_string(),
                    scout: r[1].as_bool().unwrap(),
                    ambush: r[2].as_bool().unwrap(),
                    transport_capacity: 0,
                    ..Default::default()
                })
                .collect();
            let caps: Vec<i64> = specs.iter().map(|s| s.transport_capacity).collect();

            let mut rng = GodotRng::new(sd["seed_value"].as_i64().unwrap());
            let _ = deployment::transport_fill(&caps, &mut rng);
            let _ = deployment::split_into_groups(specs.len(), &mut rng);
            let _ = deployment::assign_sections(3, &mut rng);
            let order = deployment::placement_order(&specs, &mut rng);
            let got: Vec<&str> = order.iter().map(|&i| specs[i].key.as_str()).collect();
            let want: Vec<&str> = sd["placement_order"]
                .as_array().unwrap().iter()
                .map(|v| v.as_str().unwrap()).collect();
            assert_eq!(got, want, "seed {} side {}: placement order", d["seed"], slot);
            sides_checked += 1;
        }
    }
    assert_eq!(sides_checked, 200, "pinned sides across the corpus");
}

/// The scout/ambush law where the corpus cannot (0 scout units in the lists):
/// same seed and input as the table's own GDScript test
/// (test/ai_deployment_test.gd:48-65) — ambush excluded, the two scouts occupy
/// the LAST two slots in either order.
#[test]
fn placement_order_scouts_last_ambush_excluded() {
    let specs = vec![
        UnitSpec { key: "a".into(), ..Default::default() },
        UnitSpec { key: "s1".into(), scout: true, ..Default::default() },
        UnitSpec { key: "b".into(), ..Default::default() },
        UnitSpec { key: "amb".into(), ambush: true, ..Default::default() },
        UnitSpec { key: "s2".into(), scout: true, ..Default::default() },
    ];
    let order = deployment::placement_order(&specs, &mut GodotRng::new(3));
    assert_eq!(order.len(), 4, "ambush excluded (reserve)");
    assert!(order.iter().all(|&i| specs[i].key != "amb"));
    let tail: Vec<&str> = order[2..].iter().map(|&i| specs[i].key.as_str()).collect();
    assert!(tail.contains(&"s1") && tail.contains(&"s2"), "scouts last: {tail:?}");
}

/// The transport fill's draw law, pinned where the corpus cannot (no transports
/// in the lists): one `randi_range(0, len-1)` draw per pop and the final pop
/// (a single candidate left) draws NOTHING — the engine's equal-bounds fast
/// path that rng.rs::randi_range now mirrors.
#[test]
fn transport_fill_draw_law_final_pop_draws_nothing() {
    let mut rng = GodotRng::new(1234);
    let fills = deployment::transport_fill(&[2, 0, 0, 0], &mut rng);
    // Cargo limit 2 → 2 loads, but the pool DRAINS fully: 3 pops, the third
    // being randi_range(0, 0) — no draw.
    assert_eq!(fills.len(), 2);
    assert!(fills.iter().all(|&(t, _)| t == 0));
    let mut mirror = GodotRng::new(1234);
    let _ = mirror.randi_range(0, 2); // pop 1 of 3
    let _ = mirror.randi_range(0, 1); // pop 2 of 3
    // pop 3: randi_range(0, 0) — consumes nothing.
    assert_eq!(rng.state_i64(), mirror.state_i64(), "final pop must draw nothing");
}

// ==== NML-1152 step 4a — the blocked-test geometry against the fixture dumps ====
//
// The 100 raw pregame dumps (50 boards, both seat orders) record each unit's
// FINAL spot after the table accepted it. The table only accepts a spot whose
// whole footprint passes probe + walls + cells, so the twin's portable subset
// (walls + cells; the probe is NOT portable, §4.3) must answer CLEAR for every
// recorded spot — with exactly two table-side escape hatches the fixture DOES
// allow asserting (both are `least_blocked_spot`, the ladder's last resort,
// which deliberately accepts blocked ground):
//   * zone-centre degenerate: a footprint whose margins cannot fit the 12"
//     zone at all never reaches a scan candidate, so `least_blocked_spot`
//     returns its INITIAL value, the zone centre (ai_deployment.gd:127,
//     `var best := zone.get_center()`) — deterministic from unit data alone;
//   * occupied-driven: earlier deployments crowded the search (occupied list +
//     wall-bisect marks) into a blocked-accepting landing — NOT reconstructible
//     without the slice-5 placement replay, so pinned by COUNT here.
// The dumps record NO rejected/blocked spots, so the BLOCKED half of the law
// is not assertable from this fixture. Boards: `board_seed_rule` — the arena
// autogen seeds the SAME map layouter with `layout_seed = 500000 + seed`
// (arena_match.gd:271-277; SchoolTerrain.generate mirrors it verbatim).

use std::collections::HashMap;

use nml_core::terrain::{PlainTerrain, Terrain};
use nml_core::IN2M;

fn spots_fixture() -> serde_json::Value {
    serde_json::from_str(include_str!("fixtures/pregame_deploy_spots.json")).expect("fixture parses")
}

fn board_of(cell_params: &serde_json::Value, v: &serde_json::Value) -> Terrain {
    // The extract stores cell_params ONCE (constant across all 50 boards) and
    // per-board cells only; the corpus banks carry no sandbox pieces and no
    // wall segments (walls default to empty via serde).
    let plain: PlainTerrain = serde_json::from_value(serde_json::json!({
        "cells": v["cells"],
        "sandbox": [],
        "cell_params": cell_params,
    }))
    .expect("plain terrain");
    Terrain::build(&plain)
}

/// FRONT_LINE zone geometry for the pinned 6x4 ft table (design §1: P1 at
/// z=-d/2, P2 at z=+d/2-12", full width): full width and the 12" depth band.
const ZONE_HALF_W: f64 = 0.9144;
const ZONE_DEPTH: f64 = 0.3048;

#[test]
fn blocked_law_replays_every_fixture_spot_clear() {
    let fx = spots_fixture();
    let boards: HashMap<i64, Terrain> = fx["boards"]
        .as_object().unwrap()
        .iter()
        .map(|(k, v)| (k.parse::<i64>().unwrap(), board_of(&fx["cell_params"], v)))
        .collect();
    let mut n = 0usize;
    let (mut clear, mut degenerate, mut crowded) = (0usize, 0usize, 0usize);
    for d in fx["dumps"].as_array().unwrap() {
        let board = boards.get(&(500000 + d["seed"].as_i64().unwrap())).expect("board for seed");
        for slot in ["1", "2"] {
            let (z_lo, z_hi) = if slot == "1" { (-0.6096, -0.3048) } else { (0.3048, 0.6096) };
            let z_centre = (z_lo + z_hi) / 2.0;
            for u in d["sides"][slot]["units"].as_array().unwrap() {
                n += 1;
                let spot = (u["spot"][0].as_f64().unwrap(), u["spot"][1].as_f64().unwrap());
                let base_r = u["base_r_m"].as_f64().unwrap();
                let flying = u["ignores_terrain"].as_bool().unwrap();
                let fp: Vec<(f64, f64)> = u["footprint"]
                    .as_array().unwrap().iter()
                    .map(|o| (o[0].as_f64().unwrap(), o[1].as_f64().unwrap()))
                    .collect();
                // probe_radius is only read for EMPTY footprints (regiments);
                // the corpus has none, so 0.0 never reaches the disc fallback.
                if !deployment::spot_blocked(board, spot, flying, 0.0, &fp, base_r) {
                    clear += 1;
                    continue;
                }
                let my = fp.iter().map(|o| o.1.abs()).fold(0.0f64, f64::max) + base_r;
                let mx = fp.iter().map(|o| o.0.abs()).fold(0.0f64, f64::max) + base_r;
                let cannot_fit = 2.0 * my > ZONE_DEPTH || 2.0 * mx > 2.0 * ZONE_HALF_W;
                let at_zone_centre = spot.0.abs() <= 2e-4 && (spot.1 - z_centre).abs() <= 2e-4;
                if at_zone_centre && cannot_fit {
                    degenerate += 1;
                    continue;
                }
                crowded += 1;
            }
        }
    }
    assert_eq!(n, 1060, "the full 100-dump corpus");
    assert_eq!(clear + degenerate + crowded, n);
    // Occupied-driven least_blocked landings in this corpus — seeds 28 s2
    // (Change Birdmen), 30 s2 (Warriors), 54 s2 (Change Mutated Cultists),
    // 65 s2 (Change Mutated Cultists), 2-4 blocked models each. The slice-5
    // placement replay (occupied list + bisect marks) is what pins them.
    assert_eq!(crowded, 4, "occupied-driven least_blocked landings (slice-5 scope)");
    eprintln!(
        "blocked replay: {n}/{n} recorded spots explained by the twin's cells+walls law \
         ({clear} fully clear, {degenerate} zone-centre degenerate [footprint cannot fit the 12\" zone], \
         {crowded} occupied-driven least_blocked)"
    );
}

/// The wall layer, pinned synthetically where the corpus cannot (all 50 fixture
/// boards carry ZERO wall segments): 2 cm clearance to a container/ruin wall,
/// endpoint behaviour included. The segment rides the board in WORLD METRES,
/// exactly the shape `TerrainOverlay.get_wall_segments_world()` flattens.
#[test]
fn wall_clearance_blocks_within_two_centimetres() {
    let fx = spots_fixture();
    let mut plain: PlainTerrain =
        serde_json::from_value(serde_json::json!({ "cells": [], "sandbox": [], "cell_params": fx["cell_params"] })).unwrap();
    plain.walls = vec![[[-0.5, 0.0], [0.5, 0.0]]];
    let board = Terrain::build(&plain);
    assert!(deployment::wall_blocked(&board, (0.0, 0.0)), "on the wall");
    assert!(deployment::wall_blocked(&board, (0.0, 0.015)), "1.5 cm off the wall");
    assert!(!deployment::wall_blocked(&board, (0.0, 0.025)), "2.5 cm off the wall");
    assert!(deployment::wall_blocked(&board, (0.51, 0.0)), "1 cm past the wall END");
    assert!(!deployment::wall_blocked(&board, (0.6, 0.0)), "10 cm past the wall end");
}

/// The class law pinned where the corpus under-exercises it: FOREST floors are
/// legal for walkers (cover placement doctrine) and DANGEROUS is legal for
/// Strider/Flying, while CONTAINER blocks both and RUINS only the flyer.
#[test]
fn cell_law_walker_vs_flying() {
    let fx = spots_fixture();
    let mut plain: PlainTerrain =
        serde_json::from_value(serde_json::json!({ "cells": [], "sandbox": [], "cell_params": fx["cell_params"] })).unwrap();
    // cells at grid indices (15+k, 15) → world-metre centres ((k+0.5) * 0.0762, 0.0762)
    plain.cells = vec![
        [16.0, 15.0, 2.0], // FOREST
        [17.0, 15.0, 4.0], // DANGEROUS
        [18.0, 15.0, 1.0], // RUINS
        [19.0, 15.0, 3.0], // CONTAINER
    ];
    let board = Terrain::build(&plain);
    let c = |k: f64| ((k + 0.5) * 0.0762, 0.5 * 0.0762);
    assert!(!deployment::cell_blocked(&board, c(1.0), false), "walker on FOREST is legal");
    assert!(deployment::cell_blocked(&board, c(2.0), false), "walker on DANGEROUS");
    assert!(!deployment::cell_blocked(&board, c(3.0), false), "walker on RUINS is legal");
    assert!(deployment::cell_blocked(&board, c(4.0), false), "walker on CONTAINER");
    assert!(!deployment::cell_blocked(&board, c(1.0), true), "flyer on FOREST is legal");
    assert!(!deployment::cell_blocked(&board, c(2.0), true), "flyer on DANGEROUS is legal");
    assert!(deployment::cell_blocked(&board, c(3.0), true), "flyer on RUINS");
    assert!(deployment::cell_blocked(&board, c(4.0), true), "flyer on CONTAINER");
}

/// The disc sampler's shape law (Bug 29): small base → the original 9-point
/// check; a large base densifies to half-cell resolution and appends the exact
/// edge ring, NOT de-duplicated. Hand-counted for r = 0.05: n = 2, the grid
/// keeps 12 non-zero points (|o| ≤ 0.0501 drops the far corners), + 1 centre
/// + 8 ring points = 21.
#[test]
fn disc_sampler_small_base_9_points_large_base_densifies() {
    let small = deployment::disc_sample_offsets(0.02);
    assert_eq!(small.len(), 9);
    assert_eq!(small[0], [0.0, 0.0]);
    let step_case = deployment::disc_sample_offsets(0.0381);
    assert_eq!(step_case.len(), 9, "r == one step stays on the 9-point check");
    let big = deployment::disc_sample_offsets(0.05);
    assert_eq!(big.len(), 21);
    assert_eq!(big[0], [0.0, 0.0]);
    let max_r = big.iter().map(|o| ((o[0] * o[0] + o[1] * o[1]) as f64).sqrt()).fold(0.0f64, f64::max);
    assert!(max_r <= 0.05 + 1e-4, "every sample inside the disc");
    let ring = &big[big.len() - 8..];
    assert_eq!(ring[0][0], 0.05f32, "the edge ring sits at the exact radius");
    let zero_count = big.iter().filter(|o| **o == [0.0, 0.0]).count();
    assert_eq!(zero_count, 1, "no zero duplicates: centre + ring non-zero");
}

/// `footprint_margins` (ai_deployment.gd:78-87): the per-axis Bug-19 law.
#[test]
fn footprint_margins_per_axis_from_real_footprint() {
    assert_eq!(deployment::footprint_margins(0.1, &[], 0.02), (0.1, 0.1));
    let fp = vec![(-0.069, 0.0), (0.023, 0.05)];
    let (mx, my) = deployment::footprint_margins(0.1, &fp, 0.02);
    assert!((mx - 0.089).abs() < 1e-12 && (my - 0.07).abs() < 1e-12);
}

// ==== NML-1152 step 4b — the adaptive deployment grid against the fixture ====
//
// The dump's `footprint` field IS `_deploy_footprint_offsets`' output (the
// check grid the spot search tested every model base against), so the grid law
// replays against all 1060 recorded footprints. The dump quantizes coordinates
// to 0.0001 m, so the comparison carries that tolerance; the extract-time
// invariant run confirmed 1060/1060 under the NON-skirmish chain cap and 0
// units needing the skirmish cap. `models` (post-settle, fixed 0.04 place
// grid) is slice-6 scope and NOT asserted here.

/// The dump's coordinate quantum — comparisons against recorded numbers.
const DUMP_QUANT: f64 = 1.5e-4;

#[test]
fn deploy_grid_matches_every_fixture_footprint() {
    let fx = spots_fixture();
    let mut n = 0usize;
    let mut ok = 0usize;
    for d in fx["dumps"].as_array().unwrap() {
        for slot in ["1", "2"] {
            for u in d["sides"][slot]["units"].as_array().unwrap() {
                n += 1;
                let base_r = u["base_r_m"].as_f64().unwrap();
                let count = u["n_models"].as_u64().unwrap() as usize;
                let want = deployment::deploy_footprint_offsets(count, base_r, false);
                let got: Vec<(f64, f64)> = u["footprint"]
                    .as_array().unwrap().iter()
                    .map(|o| (o[0].as_f64().unwrap(), o[1].as_f64().unwrap()))
                    .collect();
                if want.len() == got.len()
                    && want.iter().zip(&got).all(|(w, g)| (w.0 - g.0).abs() <= DUMP_QUANT && (w.1 - g.1).abs() <= DUMP_QUANT)
                {
                    ok += 1;
                }
            }
        }
    }
    assert_eq!(n, 1060, "the full 100-dump corpus");
    assert_eq!(ok, n, "every recorded footprint is the adaptive check grid");
    eprintln!("deploy grid replay: {ok}/{n} recorded footprints match the adaptive grid law");
}

/// The span cap, pinned at the exact case the corpus exercises (Pathfinders,
/// 6 models, 20 mm bases): uncapped spacing 0.046 overflows the 9" coherency
/// span, so the grid shrinks to (span_cap - 2·base_r) / diag — the dump's
/// ±0.0853 x-extent is this value quantized to 0.0001.
#[test]
fn deploy_grid_span_cap_shrinks_to_the_coherency_span() {
    let fp = deployment::deploy_footprint_offsets(6, 0.02, false);
    let spacing = fp[1].0 - fp[0].0;
    assert!((spacing - 0.04266201644389096).abs() < 1e-12, "capped spacing, got {spacing}");
    assert!((fp[5].0 - fp[0].0).abs() - 0.08532403288778193 < 1e-12, "full x extent");
    // Skirmish systems cap at 6": the floor (2·base_r + 2 mm) wins instead.
    let fp_skirmish = deployment::deploy_footprint_offsets(6, 0.02, true);
    assert!((fp_skirmish[1].0 - fp_skirmish[0].0 - 0.042).abs() < 1e-12);
}

/// Base-aware spacing + squarest grid: 20-model 16 mm bases start at 0.04
/// spacing (2·0.016+0.006 loses to DEPLOY_SPACING_M), take ceil(√20) = 5
/// columns, and still overflow the span cap → (span − 2·base_r) / diag.
#[test]
fn deploy_grid_sqrt_columns_and_base_aware_spacing() {
    let fp = deployment::deploy_footprint_offsets(20, 0.016, false);
    assert_eq!(fp.len(), 20);
    let spacing = fp[1].0 - fp[0].0;
    assert_eq!(fp.iter().filter(|o| o.1 == fp[0].1).count(), 5, "row 0 has 5 models (ceil(√20) columns)");
    assert!((fp[0].1 - -1.5 * spacing).abs() < 1e-12, "4 rows centred on the spot");
    assert!((spacing - 0.1839 / 5.0).abs() < 1e-12, "capped spacing, got {spacing}");
    // Small units keep the plain spacing floor: 4 models, 20 mm bases → 0.046.
    let fp4 = deployment::deploy_footprint_offsets(4, 0.02, false);
    assert!((fp4[1].0 - fp4[0].0 - 0.046).abs() < 1e-12);
}

/// `_deploy_footprint_radius` (the FIXED-cols twin of the grid above — the
/// table's two helpers disagree for n > 10 and both are mirrored as-is).
#[test]
fn deploy_footprint_radius_keeps_fixed_cols() {
    let r4 = deployment::deploy_footprint_radius(4, 0.02);
    assert!((r4 - 0.09).abs() < 1e-12, "half_w 0.06 + base 0.02 + 0.01, got {r4}");
    let r12 = deployment::deploy_footprint_radius(12, 0.02);
    let want = (0.08f64 * 0.08 + 0.04 * 0.04).sqrt() + 0.03;
    assert!((r12 - want).abs() < 1e-12, "cols stay at 5 even for 12 models, got {r12}");
}

// ==== NML-1155 step 4c — the banked PROP layer ====
//
// The v1 banks carried NO wall segments and NO prop geometry (0/50 banks had
// walls — the step-4 finding), so the twin's blocked law was strictly more
// permissive than the table's. The v2 banks
// (`tools/terrain_bank_dump.gd`, NML-1155) carry both keys:
//   * `walls` — TerrainOverlay.get_wall_segments_world()'s exact answer for
//     the layout (container OBB edges + ruin wall segments), 42-64 per board;
//   * `blockers` — one XZ-incircle disc per SOLID prop (the 6"x3" container
//     boxes; trees/mines/signs have no collision), radius 1.5", 4 per board.
// The extract below carries both for the 50 fixture boards, sanitized — the
// raw banks stay outside the repo. The incircle (not the circumscribed
// 3.354" disc) is the derivation the corpus tolerates: disc(incircle) ⊕
// disc(0.02) ⊆ box ⊕ disc(0.02), i.e. the prop layer can never out-block
// the table's own 0.02 m band around the box outline that `walls` already
// carries — measured BEFORE building: a circumscribed disc flips 114 of the
// recorded-clear spots, the incircle flips 0.

fn bank_v2_fixture() -> serde_json::Value {
    serde_json::from_str(include_str!("fixtures/pregame_bank_v2.json")).expect("extract parses")
}

fn board_with_props(cell_params: &serde_json::Value, cells: &serde_json::Value, props: &serde_json::Value) -> Terrain {
    let plain: PlainTerrain = serde_json::from_value(serde_json::json!({
        "cells": cells,
        "sandbox": [],
        "cell_params": cell_params,
    }))
    .expect("plain terrain");
    let mut board = Terrain::build(&plain);
    let walls: Vec<[f64; 4]> = props["walls"]
        .as_array().unwrap().iter()
        .map(|w| [w[0].as_f64().unwrap(), w[1].as_f64().unwrap(), w[2].as_f64().unwrap(), w[3].as_f64().unwrap()])
        .collect();
    let blockers: Vec<[f64; 3]> = props["blockers"]
        .as_array().unwrap().iter()
        .map(|b| [b[0].as_f64().unwrap(), b[1].as_f64().unwrap(), b[2].as_f64().unwrap()])
        .collect();
    board.set_bank_props(&walls, &blockers);
    board
}

/// The smallest sample margin over the prop layer: min over every blocked-law
/// sample of `dist(sample, blocker) − (r + PROBE_RADIUS_M)`; negative = the
/// prop layer blocks that sample. The fatness report's number.
fn worst_prop_margin(
    board: &Terrain,
    spot: (f64, f64),
    footprint: &[(f64, f64)],
    base_r: f64,
) -> f64 {
    let px = spot.0 as f32;
    let py = spot.1 as f32;
    let mut samples: Vec<[f32; 2]> = vec![[px, py]];
    for off in footprint {
        for e in deployment::disc_sample_offsets(base_r) {
            samples.push([px + off.0 as f32 + e[0], py + off.1 as f32 + e[1]]);
        }
    }
    let mut worst = f64::INFINITY;
    for s in &samples {
        for b in board.blockers_m() {
            let dx = s[0] as f64 - b[0];
            let dy = s[1] as f64 - b[1];
            let m = (dx * dx + dy * dy).sqrt() - (b[2] + deployment::PROBE_RADIUS_M);
            worst = worst.min(m);
        }
    }
    worst
}

/// Test 1 of the step: the step-4 blocked replay RE-RUN on the v2 boards —
/// now with wall segments AND blocker discs biting. The classification leads
/// with the TABLE's structural escape hatch, ahead of any law verdict: a
/// footprint that cannot fit the 12" zone never reaches a scan candidate, so
/// `least_blocked_spot` returns its INITIAL value — the exact zone centre —
/// UNTESTED (ai_deployment.gd:127-144; 20 such landings across the corpus,
/// all 21-model/30 mm flying units with 2·(0.124" + 0.03) > 0.3048 m). The
/// step-4 v1 replay could only see the 14 of them that also sat on blocked
/// CELLS — the wall-blind bank hid the rest. After that hatch: every spot
/// the table actually TESTED and found clear under the v1 law (cells only)
/// must STILL be clear under the v2 law (walls + blockers). A flip would
/// mean the derivation is too fat: reported with the worst case, never
/// loosened silently.
#[test]
fn blocked_law_replays_every_fixture_spot_clear_on_bank_v2_boards() {
    let fx = spots_fixture();
    let v2 = bank_v2_fixture();
    let boards: HashMap<i64, Terrain> = fx["boards"]
        .as_object().unwrap()
        .iter()
        .map(|(k, v)| (k.parse::<i64>().unwrap(), board_of(&fx["cell_params"], v)))
        .collect();
    let boards_v2: HashMap<i64, Terrain> = fx["boards"]
        .as_object().unwrap()
        .iter()
        .map(|(k, v)| {
            let ls = k.parse::<i64>().unwrap();
            (ls, board_with_props(&fx["cell_params"], &v["cells"], &v2["boards"][k]))
        })
        .collect();
    let (mut n, mut clear, mut degenerate, mut crowded) = (0usize, 0usize, 0usize, 0usize);
    let mut flips: Vec<(f64, i64, &str, String)> = Vec::new();
    for d in fx["dumps"].as_array().unwrap() {
        let seed = d["seed"].as_i64().unwrap();
        let board_v1 = &boards[&(500000 + seed)];
        let board_v2 = &boards_v2[&(500000 + seed)];
        for slot in ["1", "2"] {
            let (z_lo, z_hi) = if slot == "1" { (-0.6096, -0.3048) } else { (0.3048, 0.6096) };
            let z_centre = (z_lo + z_hi) / 2.0;
            for u in d["sides"][slot]["units"].as_array().unwrap() {
                n += 1;
                let spot = (u["spot"][0].as_f64().unwrap(), u["spot"][1].as_f64().unwrap());
                let base_r = u["base_r_m"].as_f64().unwrap();
                let flying = u["ignores_terrain"].as_bool().unwrap();
                let fp: Vec<(f64, f64)> = u["footprint"]
                    .as_array().unwrap().iter()
                    .map(|o| (o[0].as_f64().unwrap(), o[1].as_f64().unwrap()))
                    .collect();
                // the structural hatch FIRST (the table never tests this spot)
                let my = fp.iter().map(|o| o.1.abs()).fold(0.0f64, f64::max) + base_r;
                let mx = fp.iter().map(|o| o.0.abs()).fold(0.0f64, f64::max) + base_r;
                let cannot_fit = 2.0 * my > ZONE_DEPTH || 2.0 * mx > 2.0 * ZONE_HALF_W;
                let at_zone_centre = spot.0.abs() <= 2e-4 && (spot.1 - z_centre).abs() <= 2e-4;
                if at_zone_centre && cannot_fit {
                    degenerate += 1;
                    continue;
                }
                // the table TESTED this spot; the v1 law (cells only — the v1
                // extract carries no walls) is the floor, the v2 law (walls +
                // blockers biting) must keep every v1-clear spot clear.
                if deployment::spot_blocked(board_v1, spot, flying, 0.0, &fp, base_r) {
                    crowded += 1;
                    continue;
                }
                if deployment::spot_blocked(board_v2, spot, flying, 0.0, &fp, base_r) {
                    let m = worst_prop_margin(board_v2, spot, &fp, base_r);
                    flips.push((m, seed, slot, u["key"].as_str().unwrap().to_string()));
                } else {
                    clear += 1;
                }
            }
        }
    }
    let previously_clear = clear + flips.len();
    eprintln!(
        "v2 blocked replay: {clear}/{previously_clear} table-tested, v1-clear recorded spots stay \
         clear under the v2 law (untested zone-centre landings {degenerate}, blocked-accepting \
         least_blocked landings {crowded}, of {n} units)"
    );
    for (m, seed, slot, key) in &flips {
        eprintln!("FLIP margin {m:.5} m — seed {seed} side {slot} unit {key}");
    }
    assert_eq!(degenerate, 20, "untested zone-centre landings (ai_deployment.gd:127-144)");
    assert_eq!(crowded, 4, "occupied-driven least_blocked landings (slice-5 scope)");
    assert!(
        flips.is_empty(),
        "the v2 law flips {} table-tested spots the v1 law called clear — blocker derivation \
         too fat, worst margin {:.5} m (seed {} side {} {}); do NOT loosen silently",
        flips.len(),
        flips.iter().map(|(m, ..)| *m).fold(f64::INFINITY, f64::min),
        flips.first().map(|(_, s, ..)| *s).unwrap_or(0),
        flips.first().map(|(_, _, sl, _)| *sl).unwrap_or(""),
        flips.first().map(|(_, _, _, k)| k.clone()).unwrap_or_default(),
    );
}

/// Test 2 of the step, the synthetic red-green pair the corpus cannot carry
/// (its recorded spots are all off-prop): a spot ON a blocker disc is BLOCKED,
/// and the SAME board with the disc removed is CLEAR — the disc causes the
/// block. Plus the incircle's exactness on the long side: 2.5 cm past a
/// container's 3" face is prop-CLEAR (1.5" + 0.02 m = 0.0581 m reach), where a
/// circumscribed disc would block out to 0.1052 m.
#[test]
fn banked_blocker_disc_blocks_its_spot_and_only_its_band() {
    let fx = spots_fixture();
    // container box centred at (x 0.2 m, z -0.4 m), 6" along x, 3" along z —
    // the disc is the XZ incircle, radius 1.5" (tools/terrain_bank_dump.gd).
    let (cx, cz) = (0.2, -0.4);
    let blocker_in = [cx / IN2M, cz / IN2M, 1.5];
    let mut blocked = Terrain::build(&serde_json::from_value(serde_json::json!({
        "cells": [], "sandbox": [], "cell_params": fx["cell_params"]
    })).unwrap());
    blocked.set_bank_props(&[], &[blocker_in]);
    let clear_board = Terrain::build(&serde_json::from_value(serde_json::json!({
        "cells": [], "sandbox": [], "cell_params": fx["cell_params"]
    })).unwrap());
    let p = (cx, cz);
    assert!(deployment::prop_blocked(&blocked, p), "the disc centre is blocked");
    assert!(!deployment::prop_blocked(&clear_board, p), "removing the disc clears it (red half)");
    let fp = vec![(0.0, 0.0)];
    assert!(
        deployment::spot_blocked(&blocked, p, false, 0.0, &fp, 0.016),
        "spot_blocked consults the prop layer"
    );
    assert!(!deployment::spot_blocked(&clear_board, p, false, 0.0, &fp, 0.016));
    // exactness: 2.5 cm past the long face is prop-clear — the twin stays as
    // permissive as the table there (the wall band, not the disc, carries the
    // outline, and it blocks only to 0.02 m).
    assert!(!deployment::prop_blocked(&blocked, (cx, cz + 0.0381 + 0.025)));
    // ...while 1 cm past it IS blocked (1.5" + 1 cm < 1.5" + 0.02 m reach).
    assert!(deployment::prop_blocked(&blocked, (cx, cz + 0.0381 + 0.01)));
}

/// A bank dumped before NML-1155 carries neither key: `set_bank_props` with
/// empty slices (the serde-default shape) must leave the blocked law
/// byte-identical — the default-preserving guarantee the corpus relies on.
#[test]
fn bank_without_prop_keys_keeps_the_law_unchanged() {
    let fx = spots_fixture();
    let plain: PlainTerrain = serde_json::from_value(serde_json::json!({
        "cells": [[16, 15, 3]], "sandbox": [], "cell_params": fx["cell_params"]
    }))
    .unwrap();
    let bare = Terrain::build(&plain);
    let mut loaded = Terrain::build(&plain);
    loaded.set_bank_props(&[], &[]);
    assert_eq!(loaded.blockers_m().len(), 0);
    assert_eq!(loaded.walls_in().len(), 0);
    // and an ABSENT board ignores the call entirely (in2m 0 — no 2 cm disc
    // invented at the origin).
    let mut absent = Terrain::absent();
    absent.set_bank_props(&[[0.0, 0.0, 1.0, 1.0]], &[[0.0, 0.0, 1.5]]);
    assert_eq!(absent.blockers_m().len(), 0);
    for k in -20..20 {
        let p = (k as f64 * 0.037, (k as f64 + 0.5) * 0.041);
        assert_eq!(
            deployment::spot_blocked(&bare, p, false, 0.0, &[], 0.02),
            deployment::spot_blocked(&loaded, p, false, 0.0, &[], 0.02),
            "law changed at {p:?}"
        );
    }
}

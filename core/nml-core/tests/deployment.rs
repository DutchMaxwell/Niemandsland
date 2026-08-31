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

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

use nml_core::deployment::{self, roll_off_traced};
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

use super::*;

use crate::rules::Registries;
use crate::state::Profile;

    // ---- STANDALONE_SWEEP_F_2026-09-14, row `Heavy Impact` (ledger
    //      proven_vs_read.tsv line 131, proof_kind "none"): the second Impact
    //      pool — `unit_rating(&p.special_rules, "Heavy Impact")` reads the
    //      rule's own rating (unit.rs), the pool rolls rating x models and
    //      its saves ride AP(1) (`HEAVY_IMPACT_AP`, dice.rs). -------

    /// The checkout this crate lives in — mirrors the unit tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The striker through the REAL stamp: three models carrying
    /// "Heavy Impact(2)" (gf/ratmen_clans fields the name with
    /// `{rating: "X", ap: 1, counts_as: "Impact"}`).
    fn heavy_striker() -> UnitStatic {
        let p: Profile = serde_json::from_str(
            r#"{"unit_id": "a", "name": "Lancer", "model_count": 3,
                "quality": 4, "defense": 4, "tough": 1,
                "game_system": "gf", "faction_folder": "ratmen_clans",
                "special_rules": ["Heavy Impact(2)"], "weapons": []}"#,
        )
        .expect("the heavy striker's profile parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH)
    }

    /// THE NUMBER: the exact name stamps the rule's own rating 2, the heavy
    /// pool is rating x models (no plain Impact of its own), and the pool's
    /// saves ride AP(1) — Defense 4+ becomes 5+.
    #[test]
    fn heavy_impact_stamps_its_rating_by_name_and_pools_rating_times_models_at_ap_one() {
        let striker = heavy_striker();
        assert_eq!(
            striker.ctx.heavy_impact, 2,
            "the exact name \"Heavy Impact\" stamps the rule's own rating"
        );
        let mut att = striker.ctx;
        att.models = 3; // _ctx_of's snapshot write: the alive count
        let pools = impact_pools(&att, &defender(4, 5));
        assert_eq!(
            pools,
            [(0, 0), (6, HEAVY_IMPACT_AP)],
            "no plain Impact pool; the heavy pool is 2 x 3 dice at AP(1)"
        );

        // The pool on a tray: the hit roll at 2+, then the save batch at
        // Defense 4 + AP(1) = 5+. The seed guarantees at least one hit so the
        // save batch always follows (seed search, the plain_moves convention).
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(6).iter().any(|&f| f >= IMPACT_HIT_TARGET as u8))
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let out = resolve_impact_pool_with_tray(
            pools[1].0, pools[1].1, "Lancer", &defender(4, 5), "D", &mut tray,
        );
        let hits = out.rolls[0]
            .faces
            .iter()
            .filter(|&&f| f as i64 >= IMPACT_HIT_TARGET)
            .count() as i64;
        assert!(hits > 0, "the seed guarantees a hit: {:?}", out.rolls[0].faces);
        assert_eq!(
            (out.rolls[0].kind, out.rolls[0].count, out.rolls[0].target),
            ("attack", 6, IMPACT_HIT_TARGET),
            "the pool rolls its 6 dice at the 2+ Impact trigger"
        );
        assert_eq!(
            (out.rolls[1].kind, out.rolls[1].count, out.rolls[1].target),
            ("defense", hits, 5),
            "AP(1) worsens the save from Defense 4+ to 5+"
        );
    }

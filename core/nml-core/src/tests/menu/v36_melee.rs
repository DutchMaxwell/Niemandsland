//! Rules 3.6 lane melee tests for the menu module; owned by lane melee.

/// MEL-PAR-F8: the menu's charge path check (`charge_needs_path`) must treat the board's ruin walls as impassable,
/// like the table's charge move does. Fixture: the #857 act (charger ~10" from its victim, 12" band) with the
/// header's own walls replaced by one long wall.
mod mel_par_f8 {
    use crate::acts::read_acts;
    use crate::menu::{best_charge, nearest_chargeable, Tuning};
    use crate::sim::Scratch;
    use crate::IN2M;
    use serde_json::{json, Value};
    use std::io::Cursor;

    const FIXTURE: &str = include_str!("../../../tests/fixtures/charge857_fall_short.json");
    const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

    /// A unit's centroid `[x, z]` in world metres, read from the act line.
    fn centroid(fx: &Value, key: &str) -> [f64; 2] {
        let ps = fx["act_line"]["state"]["units"][key]["positions"].as_array().unwrap();
        let s = ps.iter().fold([0.0, 0.0], |a, p| [a[0] + p[0].as_f64().unwrap(), a[1] + p[2].as_f64().unwrap()]);
        [s[0] / ps.len() as f64, s[1] / ps.len() as f64]
    }

    /// (best_charge, nearest_chargeable, victim) with ONE 36" wall square across the line between the two units,
    /// its middle `shift_in` inches from their midpoint toward the charger; `None` = a board without walls. Every
    /// model of both units sits within the wall's span, so going round it costs far more than the 12" band.
    fn charges(shift_in: Option<f64>) -> (Option<String>, Option<String>, String) {
        let fx: Value = serde_json::from_str(FIXTURE).unwrap();
        let action = &fx["act_line"]["pick"]["action"];
        let (us, them) = (action["unit"].as_str().unwrap(), action["charge"].as_str().unwrap());
        let (a, b) = (centroid(&fx, us), centroid(&fx, them));
        let len = (a[0] - b[0]).hypot(a[1] - b[1]);
        let d = [(a[0] - b[0]) / len, (a[1] - b[1]) / len];
        let mut header = fx["header"].clone();
        header["terrain"]["walls"] = shift_in.map_or(json!([]), |s| {
            let m = [(a[0] + b[0]) / 2.0 + d[0] * s * IN2M, (a[1] + b[1]) / 2.0 + d[1] * s * IN2M];
            let h = 18.0 * IN2M;
            json!([[[m[0] - d[1] * h, m[1] + d[0] * h], [m[0] + d[1] * h, m[1] - d[0] * h]]])
        });
        let corpus = read_acts(Cursor::new(format!("{}\n{}\n", header, fx["act_line"])), "fixture").unwrap();
        let statics = crate::act_statics(&corpus, REPO);
        let st = &corpus.acts[0].state;
        let i = st.roster.index[us];
        let tuning = Tuning { charge_needs_path: true, ..Tuning::default() };
        let mut sc = Scratch::default();
        let best = best_charge(st, &corpus.terrain, &statics[0], i, &mut sc, tuning, 8, None);
        let near = nearest_chargeable(st, &corpus.terrain, &statics[0], i, &mut sc, tuning, 8);
        let key = |e: Option<usize>| e.map(|e| st.key(e).to_string());
        (key(best), key(near), them.to_string())
    }

    #[test]
    fn a_wall_whose_detour_exceeds_the_band_removes_the_charge() {
        let (best, near, victim) = charges(Some(0.0));
        assert_ne!(best.as_deref(), Some(victim.as_str()), "best_charge goes through the wall");
        assert_ne!(near.as_deref(), Some(victim.as_str()), "nearest_chargeable goes through the wall");
    }

    #[test]
    fn no_wall_or_a_wall_behind_the_charger_keeps_the_charge() {
        for shift in [None, Some(15.0)] {
            let (best, near, victim) = charges(shift);
            assert_eq!(best.as_deref(), Some(victim.as_str()), "best_charge, wall shift {shift:?}");
            assert_eq!(near.as_deref(), Some(victim.as_str()), "nearest_chargeable, wall shift {shift:?}");
        }
    }
}

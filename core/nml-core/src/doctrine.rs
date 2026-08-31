//! NML-1140 step 1 — doctrine skeleton: the mode enum, the canonical
//! per-army summary and the style label, extracted ONCE here from the
//! act-header profiles (`battle_sim.gd:_unit_profile` schema,
//! loader_gate.py parity-gated, field names pinned to list_to_profile.py).
//! Value in, ints out — means x2, half-integers exact. No callers yet, zero
//! RNG. UNSURE: label calibration probe-deferred like FAIRNESS_EPS; shots =
//! attacks x count on range > 0 weapons, 24" / 12" bands.
use serde_json::Value;

/// Doctrine mode (design 4/5); "random" is today's byte-identical path.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode { Random, Style, Search }

impl Mode {
    pub fn as_str(self) -> &'static str {
        match self { Mode::Random => "random", Mode::Style => "style", Mode::Search => "search" }
    }
    pub fn of_str(s: &str) -> Option<Mode> {
        match s { "random" => Some(Mode::Random), "style" => Some(Mode::Style), "search" => Some(Mode::Search), _ => None }
    }
}

/// Style label: argmax shooting / fast / tough, ties in that fixed order (design 2).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StyleLabel { Shooting, Fast, Tough }

/// Canonical per-army summary (design 2); `*_x2` = doubled means, exact ints.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Summary {
    pub shots_far: i64,     // ranged volume (attacks x count) at >= 24"
    pub shots_mid: i64,     // ranged volume at 12-24"
    pub advance_x2: i64,    // mean move_bands.advance over units, x2
    pub rush_x2: i64,       // mean move_bands.rush over units, x2
    pub wounds_total: i64,  // sum of wounds_max over all models
    pub models: i64,        // sum of model_count over units
    pub tough_mean_x2: i64, // mean unit-level tough over units, x2
}

const MOVE_REF_IN: i64 = 12; // label fast scale: the OPR baseline rush band
const WOUND_REF: i64 = 4; // label tough scale: a 4-wound model line

/// Half-up doubled mean, integer arithmetic only.
fn mean_x2(sum: i64, n: i64) -> i64 {
    if n <= 0 { 0 } else { (2 * sum + n / 2) / n }
}

impl Summary {
    /// One army's summary off the header's `profiles` object; missing -> 0.
    pub fn of_profiles(profiles: &Value) -> Summary {
        let int_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_i64).unwrap_or(0);
        let units: Vec<&Value> = profiles.as_object().map(|m| m.values().collect()).unwrap_or_default();
        let (mut far, mut mid, mut adv, mut rush, mut tough, mut wounds, mut models) = (0, 0, 0, 0, 0, 0, 0);
        for p in &units {
            for w in p.get("weapons").and_then(Value::as_array).into_iter().flatten() {
                let vol = int_of(w, "attacks") * int_of(w, "count");
                let r = int_of(w, "range");
                if r >= 24 { far += vol; } else if r >= 12 { mid += vol; }
            }
            adv += p.get("move_bands").and_then(|b| b.get("advance")).and_then(Value::as_f64).unwrap_or(0.0).round() as i64;
            rush += p.get("move_bands").and_then(|b| b.get("rush")).and_then(Value::as_f64).unwrap_or(0.0).round() as i64;
            wounds += p.get("wounds_max").and_then(Value::as_array).map(|ws| ws.iter().filter_map(Value::as_i64).sum::<i64>()).unwrap_or(0);
            models += int_of(p, "model_count");
            tough += int_of(p, "tough");
        }
        let n = units.len() as i64;
        Summary {
            shots_far: far, shots_mid: mid, advance_x2: mean_x2(adv, n), rush_x2: mean_x2(rush, n),
            tough_mean_x2: mean_x2(tough, n), wounds_total: wounds, models,
        }
    }

    /// Label: cross-multiplied integer shares, ties to the earlier arm.
    pub fn label(&self) -> StyleLabel {
        let sh = 4 * MOVE_REF_IN * WOUND_REF * (self.shots_far + self.shots_mid);
        let fa = WOUND_REF * self.models * (self.advance_x2 + self.rush_x2);
        let tu = 4 * MOVE_REF_IN * self.wounds_total;
        if sh >= fa && sh >= tu { StyleLabel::Shooting } else if fa >= tu { StyleLabel::Fast } else { StyleLabel::Tough }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Pinned fixture, schema exactly as battle_sim._unit_profile stamps it
    /// (list_to_profile.py:1015-1059): a two-unit shooting army.
    const SHOOTY: &str = r#"{
        "p1_0_inf": {"unit_id": "p1_0_inf", "name": "Line Infantry",
            "quality": 4, "defense": 4, "tough": 1,
            "wounds_max": [1, 1, 1, 1, 1], "model_count": 5,
            "weapons": [
                {"name": "Rifle", "range": 30, "attacks": 2, "count": 1, "ap": 1, "rules": []},
                {"name": "Carbine", "range": 18, "attacks": 1, "count": 2, "ap": 0, "rules": []}],
            "special_rules": [], "caster_value": 0,
            "move_bands": {"advance": 6.0, "rush": 12.0},
            "base_radius": 0.016, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [],
            "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0},
        "p1_1_walker": {"unit_id": "p1_1_walker", "name": "Heavy Walker",
            "quality": 4, "defense": 4, "tough": 6, "wounds_max": [6],
            "model_count": 1,
            "weapons": [
                {"name": "Cannon", "range": 24, "attacks": 6, "count": 1, "ap": 2, "rules": []}],
            "special_rules": [], "caster_value": 0,
            "move_bands": {"advance": 6.0, "rush": 12.0},
            "base_radius": 0.025, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [],
            "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0}
    }"#;

    #[test]
    fn summary_fields_on_pinned_fixture() {
        let s = Summary::of_profiles(&serde_json::from_str(SHOOTY).unwrap());
        assert_eq!(s.shots_far, 8); // 2x1 @30" + 6x1 @24"
        assert_eq!(s.shots_mid, 2); // 1x2 @18"
        assert_eq!(s.advance_x2, 12); // (6+6)/2 = 6
        assert_eq!(s.rush_x2, 24);
        assert_eq!(s.wounds_total, 11); // 5x1 + 6
        assert_eq!(s.models, 6);
        assert_eq!(s.tough_mean_x2, 7); // (1+6)/2 = 3.5, x2 exact
    }

    #[test]
    fn label_shooting_on_pinned_fixture() {
        let s = Summary::of_profiles(&serde_json::from_str(SHOOTY).unwrap());
        assert_eq!(s.label(), StyleLabel::Shooting);
    }

    #[test]
    fn label_fast_army() {
        let army = json!({
            "u1": {"model_count": 3, "wounds_max": [1, 1, 1], "tough": 1,
                   "weapons": [], "move_bands": {"advance": 12.0, "rush": 24.0}},
            "u2": {"model_count": 3, "wounds_max": [1, 1, 1], "tough": 1,
                   "weapons": [], "move_bands": {"advance": 12.0, "rush": 24.0}}
        });
        assert_eq!(Summary::of_profiles(&army).label(), StyleLabel::Fast);
    }

    #[test]
    fn label_tough_army() {
        let army = json!({
            "u1": {"model_count": 4, "wounds_max": [6, 6, 6, 6], "tough": 6,
                   "weapons": [{"range": 12, "attacks": 1, "count": 1}],
                   "move_bands": {"advance": 4.0, "rush": 8.0}},
            "u2": {"model_count": 4, "wounds_max": [6, 6, 6, 6], "tough": 6,
                   "weapons": [{"range": 12, "attacks": 1, "count": 1}],
                   "move_bands": {"advance": 4.0, "rush": 8.0}}
        });
        assert_eq!(Summary::of_profiles(&army).label(), StyleLabel::Tough);
    }

    #[test]
    fn ties_resolve_in_fixed_order() {
        let all_zero = Summary { models: 5, ..Default::default() };
        assert_eq!(all_zero.label(), StyleLabel::Shooting);
        // fast == tough > shooting -> Fast (the earlier arm wins ties).
        let tie = Summary {
            advance_x2: 16,
            rush_x2: 32,
            wounds_total: 16,
            models: 4,
            tough_mean_x2: 8,
            ..Default::default()
        };
        assert_eq!(tie.label(), StyleLabel::Fast);
    }

    #[test]
    fn empty_and_missing_fields_answer_zero() {
        assert_eq!(Summary::of_profiles(&json!({})), Summary::default());
        assert_eq!(Summary::of_profiles(&json!({})).label(), StyleLabel::Shooting);
        let sparse = Summary::of_profiles(&json!({"u": {}}));
        assert_eq!(sparse.models, 0);
        assert_eq!(sparse.shots_far, 0);
    }

    #[test]
    fn mode_strings_roundtrip() {
        for (m, word) in [
            (Mode::Random, "random"),
            (Mode::Style, "style"),
            (Mode::Search, "search"),
        ] {
            assert_eq!(m.as_str(), word);
            assert_eq!(Mode::of_str(word), Some(m));
        }
        assert_eq!(Mode::of_str("aggressive"), None);
    }
}


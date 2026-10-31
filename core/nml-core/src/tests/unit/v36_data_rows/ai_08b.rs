//! AI-08b tests (rules 3.6, lane data): Crossing Strike behaves like its 3.5 weapon name.
use super::super::*;

/// AI-08b: Crossing Strike is the 3.6 name of the weapon that attacks only when its bearer moves
/// through an enemy unit. It must behave like its 3.5 name: out of every normal volley, in the
/// move-through trigger's own set, and carrying the strafing flag.
fn flagged_weapon(rule: &str) -> Weapon {
    Weapon { name: "Twin Autocannon".into(), range: 24.0, attacks: 4, count: 1, ap: 0, rules: vec![rule.into()] }
}

fn plain_gun() -> Weapon {
    Weapon { name: "Lash Cannon".into(), range: 24.0, attacks: 2, count: 1, ap: 0, rules: vec![] }
}

#[test]
fn ai_08b_a_crossing_strike_weapon_never_joins_a_normal_volley() {
    let volley = profiles_in_range(&[flagged_weapon("Crossing Strike"), plain_gun()], 6.0);
    let names: Vec<&str> = volley.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, vec!["Lash Cannon"], "a Crossing Strike weapon fired in a normal volley");
}

#[test]
fn ai_08b_a_crossing_strike_weapon_is_in_the_move_through_set_with_the_strafing_flag() {
    let set = strafing_profiles(&[flagged_weapon("Crossing Strike"), plain_gun()]);
    assert_eq!(set.len(), 1, "only the Crossing Strike weapon belongs to the move-through set");
    assert_eq!(set[0].name, "Twin Autocannon");
    assert_eq!(set[0].attacks, 4);
    assert!(set[0].strafing, "the move-through weapon must carry the strafing flag");
}

#[test]
fn ai_08b_the_move_through_log_names_the_rule_the_weapon_carries() {
    let new_name = strafing_profiles(&[flagged_weapon("Crossing Strike")]);
    let old_name = strafing_profiles(&[flagged_weapon("Strafing")]);
    assert_eq!(strafing_rule_name(&new_name), "Crossing Strike");
    assert_eq!(strafing_rule_name(&old_name), "Strafing");
}

/// Control: the 3.5 name keeps behaving exactly as before.
#[test]
fn ai_08b_control_a_strafing_weapon_is_unchanged() {
    let volley = profiles_in_range(&[flagged_weapon("Strafing"), plain_gun()], 6.0);
    let names: Vec<&str> = volley.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, vec!["Lash Cannon"], "a Strafing weapon fired in a normal volley");
    let set = strafing_profiles(&[flagged_weapon("Strafing"), plain_gun()]);
    assert_eq!(set.len(), 1);
    assert!(set[0].strafing);
}

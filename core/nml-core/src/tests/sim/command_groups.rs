//! The AoF: Skirmish command groups (AS36 p.13; ruling D16): the picks a Banner or Musician lends its bonus to.
use super::*;

/// Unit "a" (player 0, `sys`, with `rules`) at the origin; its side's "ah" 5 in east and the enemy "b" 2 in west, the
/// enemy "bh" far off. `extra` adds a second friendly unit by moving "bh" onto player 0 at (x, z) in inches.
fn picks_line(sys: &str, rules: &[&str], extra: Option<(f64, f64)>) -> State {
    let mut st = four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
    let mut list = Vec::new();
    for i in 0..4 {
        let mut p = st.profiles.list[0].clone();
        p.game_system = sys.into();
        p.special_rules = if i == 0 { rules.iter().map(|r| r.to_string()).collect() } else { Vec::new() };
        list.push(p);
    }
    st.profiles = Rc::new(Profiles { list, index: HashMap::new() });
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions = vec![vec![at(0.0, 0.0)], vec![at(5.0, 0.0)], vec![at(-2.0, 0.0)], vec![at(30.0, 30.0)]];
    st.player = vec![0, 0, 1, 1];
    st.alive = vec![1, 1, 1, 1];
    if let Some((x, z)) = extra {
        st.positions[3] = vec![at(x, z)];
        st.player[3] = 0;
    }
    st
}

/// The default picks: the two nearest LIVING FRIENDLY units by unit-centre distance, ties by unit key; never the enemy,
/// never the unit itself; nothing for a unit without a command group or outside the AoF: Skirmish book.
#[test]
fn default_command_picks_are_the_two_nearest_friends() {
    assert_eq!(picks_line("aofs", &["Banner"], None).default_command_picks(0), vec!["ah".to_string()], "one friend, the enemy at 2 in is no pick");
    assert_eq!(picks_line("aofs", &["Musician"], Some((3.0, 0.0))).default_command_picks(0), vec!["bh".to_string(), "ah".to_string()], "nearest first");
    assert_eq!(picks_line("aofs", &["Banner"], Some((-5.0, 0.0))).default_command_picks(0), vec!["ah".to_string(), "bh".to_string()], "a tie goes by key");
    let mut three = picks_line("aofs", &["Banner"], Some((3.0, 0.0)));
    three.player[2] = 0;
    assert_eq!(three.default_command_picks(0), vec!["b".to_string(), "bh".to_string()], "three friends: only the two nearest");
    let mut dead = picks_line("aofs", &["Banner"], Some((3.0, 0.0)));
    dead.alive[3] = 0;
    assert_eq!(dead.default_command_picks(0), vec!["ah".to_string()], "a dead unit is no pick");
    assert!(picks_line("aofs", &[], Some((3.0, 0.0))).default_command_picks(0).is_empty(), "no command group");
    assert!(picks_line("aof", &["Banner"], Some((3.0, 0.0))).default_command_picks(0).is_empty(), "aof has no picks");
}

/// The picks ride the header profile: `command_picks` reads as written, and a header without the key reads none.
#[test]
fn command_picks_read_off_the_header_profile() {
    let with: crate::state::Profile = serde_json::from_str(r#"{"unit_id":"a","name":"A","quality":4,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":1,"base_radius":0.016,"game_system":"aofs","faction_folder":"x","special_rules":["Banner"],
        "command_picks":["ah","bh"],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#).expect("profile");
    assert_eq!(with.command_picks, vec!["ah".to_string(), "bh".to_string()]);
    let without: crate::state::Profile = serde_json::from_str(r#"{"unit_id":"a","name":"A","quality":4,"defense":4,"tough":1,
        "wounds_max":[1],"model_count":1,"base_radius":0.016,"game_system":"aofs","faction_folder":"x","special_rules":["Banner"],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}"#).expect("profile");
    assert!(without.command_picks.is_empty());
}

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

/// `att_def`'s Def (unit 2, player 1, Quality 4, five models) tests morale once on one die; `own` gives Def its own
/// Banner (stamped +1) with the bearer alive or killed, `pick` lets unit 3 "Ban" (Def's side, or the enemy's) carry a
/// Banner that picked Def with its bearer alive or killed. `None` = not there. The lines said before the die.
fn banner_test(epoch: u32, own: Option<bool>, pick: Option<(bool, bool)>, cause: Option<&str>) -> Vec<String> {
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let (mut st, mut statics) = super::save_lines::att_def(5, 1);
    (statics[2].model_count, statics[2].ctx.quality, statics[2].quality, statics[3].name) = (10, 4, 4, "Ban".into());
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys: keys.clone(), profile: vec![0, 1, 2, 3] });
    let mut list = Vec::new();
    for _ in 0..4 {
        let mut p = st.profiles.list[0].clone();
        p.game_system = "aofs".into();
        p.special_rules = Vec::new();
        list.push(p);
    }
    st.cmd_bearer = vec![None; 4];
    if let Some(alive) = own {
        list[2].special_rules = vec!["Banner".into()];
        st.morale_bonus[2] = 1;
        st.cmd_bearer[2] = alive.then_some(4);
    }
    if let Some((friend, alive)) = pick {
        list[3].special_rules = vec!["Banner".into()];
        list[3].command_picks = vec![keys[2].clone()];
        st.player[3] = if friend { 1 } else { 0 };
        (st.alive[3], st.cmd_bearer[3]) = (1, Some(0));
        if !alive {
            st.kit_remove(3, 0); // the bearer's slot leaves the table, as the attack that kills him removes it
        }
    }
    st.profiles = Rc::new(Profiles { list, index: HashMap::new() });
    let mut tray = Tray::supplied(vec![vec![6]]);
    tray_morale_for(&mut st, &statics, 2, false, true, cause, seams, &mut tray, &mut ShootResult::default(), None, None);
    tray.lines_upto(0).into_iter().map(|l| l.text).collect()
}

const S4A: u32 = crate::acts::PENDING_EPOCH_COMMAND_BANNER;

/// Ruling D17, the own half (E15-04): a command group's own Banner counts while its bearer lives; once he is killed the unit
/// loses the +1 and says so. Below the placeholder the stamped +1 stays, as every record before it.
#[test]
fn the_own_banner_goes_with_its_bearer() {
    assert_eq!(banner_test(S4A, Some(true), None, None), ["Banner: Def gets +1 to morale test rolls (passes on 3+)"]);
    assert_eq!(banner_test(S4A, Some(false), None, None),
        ["Banner: Def's bearer (the last model carries it - no per-model data) is dead - no +1"]);
    assert_eq!(banner_test(S4A - 1, Some(false), None, None), ["Banner: Def gets +1 to morale test rolls (passes on 3+)"], "old leg");
}

/// Ruling D17, the picked half (E15-02, E15-04): a friendly Banner unit's pick gets +1 on a shooting or melee test while the
/// bearer lives and loses it with him; never on a test another rule forced, never from the enemy's Banner, never below the
/// placeholder.
#[test]
fn a_picked_unit_gets_the_banner_while_its_bearer_lives() {
    assert_eq!(banner_test(S4A, None, Some((true, true)), None),
        ["Banner (from Ban, the last model carries it - no per-model data): Def gets +1 to its morale test roll (passes on 3+)"]);
    assert_eq!(banner_test(S4A, None, Some((true, false)), None),
        ["Banner (from Ban): its bearer is dead - Def's morale test gets no +1"]);
    assert!(banner_test(S4A, None, Some((true, true)), Some("Dangerous terrain")).is_empty(), "only shooting or melee");
    assert!(banner_test(S4A, None, Some((false, true)), None).is_empty(), "the enemy's Banner lends nothing");
    assert!(banner_test(S4A - 1, None, Some((true, true)), None).is_empty(), "old leg: no picks");
}

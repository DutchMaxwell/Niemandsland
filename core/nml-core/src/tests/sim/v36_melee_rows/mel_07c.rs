//! MEL-07c-fix tests (rules 3.6, lane melee): the strike Parry counts the
//! joined heroes like the table and the Rust Impact event do. Live path only:
//! the defender's Parry dice come from the real registry stamp and the state's
//! attached-hero chain, never a hand-set model count.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;

/// A unit through the REAL stamp: `models` models at Quality 4 carrying
/// `rules` ("Parry(1)") and the given weapon JSON, built at `epoch` so the
/// Parry stamp is epoch-gated like production.
fn unit(name: &str, models: i64, rules: &[&str], weapons: &str, epoch: u32) -> (UnitStatic, Profile) {
    let listed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let json = format!(
        r#"{{"unit_id":"u","name":"{name}","model_count":{models},"quality":4,"defense":4,"tough":1,"game_system":"gf","faction_folder":"","special_rules":[{listed}],"weapons":[{weapons}]}}"#
    );
    let p: Profile = serde_json::from_str(&json).expect("the profile parses");
    let mut reg = Registries::new(&repo_root());
    (UnitStatic::build_for(&mut reg, &p, epoch), p)
}

/// Unit 0 strikes unit 1 (the defender host) with a 10-attack melee weapon.
/// Unit 2 is the defender's joined hero when `hero` is set. The defender's
/// Parry dice are the real stamp, and the hero chain is the state's own.
fn board(epoch: u32, host_models: i64, hero: bool) -> (Vec<UnitStatic>, State) {
    let (attacker, att_p) = unit(
        "Attacker", 1, &[],
        r#"{"name":"Blade","range":0,"attacks":10,"count":1,"ap":0,"rules":[]}"#, epoch,
    );
    let (defender, def_p) = unit("Defender", host_models, &["Parry(1)"], "", epoch);
    let (hero_u, hero_p) = unit("Hero", 1, &["Parry(1)"], "", epoch);
    let statics = vec![attacker, defender, hero_u];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into(), "bh".into(), "x".into()],
        index: HashMap::new(),
        profile: vec![0, 1, 2, 0],
    });
    st.profiles = Rc::new(Profiles {
        list: vec![att_p.clone(), def_p, hero_p, att_p],
        index: HashMap::new(),
    });
    st.player = vec![0, 1, 1, 0];
    st.alive = vec![1, host_models, if hero { 1 } else { 0 }, 0];
    st.attached = Rc::new(vec![vec![], if hero { vec![2] } else { vec![] }, vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, if hero { Some(1) } else { None }, None]);
    let n = host_models as usize;
    st.positions[1] = vec![[0.0, 0.0, 0.0]; n];
    st.wounds[1] = vec![1; n];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M; n];
    (statics, st)
}

fn strike(statics: &[UnitStatic], st: &mut State, epoch: u32) -> ShootResult {
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let mut shot = ShootResult::default();
    strike_phase(
        statics, st, 0, 1, false, 0.0, seams, &mut Tray::seeded(7), &mut shot,
        StrikeSet::All, Cover::Recorded(None),
    );
    shot
}

fn parry_roll(shot: &ShootResult) -> &crate::dice::Roll {
    shot.rolls.iter().find(|r| r.kind == "parry").expect("a Parry roll is drawn")
}

/// RED before the fix: the host and its joined hero each carry Parry(1), so the
/// strike Parry must draw two dice, exactly like the Impact event does.
#[test]
fn the_strike_parry_counts_a_joined_heros_parry_at_epoch_73() {
    let (statics, mut st) = board(EPOCH_73_V36, 1, true);
    let shot = strike(&statics, &mut st, EPOCH_73_V36);
    let hits: i64 = shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.count).sum();
    assert!(hits >= 2, "the seeded strike lands at least two hits: {:?}", shot.rolls);
    assert_eq!(parry_roll(&shot).count, 2, "host and hero each bring one Parry(1) die: {:?}", shot.rolls);
}

/// CONTROL: a lone host counts as before — two Parry(1) models draw two dice.
#[test]
fn a_lone_host_still_counts_its_own_parry_models_at_epoch_73() {
    let (statics, mut st) = board(EPOCH_73_V36, 2, false);
    let shot = strike(&statics, &mut st, EPOCH_73_V36);
    assert_eq!(parry_roll(&shot).count, 2, "two host models, two dice: {:?}", shot.rolls);
}

/// Epoch 72 is pinned: the Parry stamp is off, so no Parry die is drawn.
#[test]
fn no_strike_parry_dice_are_drawn_at_epoch_72() {
    let (statics, mut st) = board(EPOCH_72_PLAYTEST_RULES, 1, true);
    let shot = strike(&statics, &mut st, EPOCH_72_PLAYTEST_RULES);
    assert!(shot.rolls.iter().all(|r| r.kind != "parry"), "{:?}", shot.rolls);
    assert!(shot.log.iter().all(|l| !l.starts_with("Parry:")), "{:?}", shot.log);
}

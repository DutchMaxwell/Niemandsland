//! MEL-07b tests (rules 3.6, lane melee): from `EPOCH_73_V36` a defender's Parry(X) rolls X dice per
//! living carrier model against the charge's Impact hits, AFTER the Impact hit dice and BEFORE the
//! Impact saves. The heavy pool (AP) is cancelled first, then the plain one; the dice never exceed the
//! hits taken. Epoch 72 keeps today's behaviour (no Parry dice at all).
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::IMPACT_HIT_TARGET;
use crate::dice::Roll;
use crate::rules::Registries;

/// A defender through the REAL stamp: `models` models at Defense `def`, carrying `rules`
/// ("Parry(1)"), built at `epoch` so the Parry stamp is epoch-gated like production.
fn parry_unit(name: &str, models: i64, def: i64, rules: &[&str], epoch: u32) -> UnitStatic {
    let listed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let json = format!(
        r#"{{"unit_id":"u","name":"{name}","model_count":{models},"quality":4,"defense":{def},"tough":1,"game_system":"gf","faction_folder":"","special_rules":[{listed}],"weapons":[]}}"#
    );
    let p: Profile = serde_json::from_str(&json).expect("the defender's profile parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// One charge melee: a 1-model charger with Impact(`impact`) into a `def_models`-model defender
/// carrying `def_rules`, optionally with a 1-model hero carrying `hero_rules` joined to it. No melee
/// weapons on either side, so Impact is the only dice the charge draws. Returns the report and the
/// defender's survivors.
fn charge(
    epoch: u32,
    impact: i64,
    def_models: i64,
    def_rules: &[&str],
    hero_rules: Option<&[&str]>,
) -> (ShootResult, i64) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let charger = UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, impact, ..Default::default() },
        name: "Charger".into(),
        model_count: 1,
        wounds_max: vec![1],
        ..Default::default()
    };
    let defender = parry_unit("Defender", def_models, 4, def_rules, epoch);
    let hero = match hero_rules {
        Some(rules) => parry_unit("Hero", 1, 4, rules, epoch),
        None => UnitStatic { name: "Hero".into(), model_count: 1, wounds_max: vec![1], ..Default::default() },
    };
    let statics = vec![charger, defender, hero];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into(), "bh".into()], index: HashMap::new(), profile: vec![0, 1, 2] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1, 1];
    st.alive = vec![1, def_models, if hero_rules.is_some() { 1 } else { 0 }];
    st.attached = Rc::new(vec![vec![], if hero_rules.is_some() { vec![2] } else { vec![] }, vec![]]);
    st.attached_to = Rc::new(vec![None, None, if hero_rules.is_some() { Some(1) } else { None }]);
    let n = def_models as usize;
    st.positions[0] = vec![[IN2M, 0.0, 0.0]];
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0]) = (vec![1], vec![IN2M]);
    (st.positions[1], st.wounds[1], Rc::make_mut(&mut st.radii)[1]) = (vec![[0.0, 0.0, 0.0]; n], vec![1; n], vec![IN2M; n]);
    (st.positions[2], st.wounds[2], Rc::make_mut(&mut st.radii)[2]) = (vec![[0.0, 0.0, 0.0]], vec![1], vec![IN2M]);
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let (mut tray, mut shot) = (Tray::seeded(7), ShootResult::default());
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    (shot, st.alive[1])
}

fn parry_roll(shot: &ShootResult) -> &Roll {
    shot.rolls.iter().find(|r| r.kind == "parry").expect("a Parry roll is drawn")
}

/// The brief's example: 2 Parry(1) models charged by Impact(4). Seed 7 draws the four Impact dice
/// [6,2,5,6] (4 hits) and then the two Parry dice [4,6] — one 6, so one hit is cancelled before the
/// saves, which roll the remaining 3 dice.
#[test]
fn two_parry_models_cancel_an_impact_hit_before_the_saves_at_epoch_73() {
    let (shot, _) = charge(EPOCH_73_V36, 4, 2, &["Parry(1)"], None);
    let kinds: Vec<&str> = shot.rolls.iter().map(|r| r.kind).collect();
    assert_eq!(kinds, ["attack", "parry", "defense"], "{:?}", shot.rolls);
    assert_eq!((shot.rolls[0].count, shot.rolls[0].target), (4, IMPACT_HIT_TARGET));
    assert_eq!(shot.rolls[0].faces, vec![6, 2, 5, 6]);
    let parry = parry_roll(&shot);
    assert_eq!((parry.count, parry.target), (2, 6), "one die per Parry(1) model");
    assert_eq!(parry.faces, vec![4, 6]);
    let cancelled = parry.faces.iter().filter(|&&f| f == 6).count() as i64;
    assert_eq!(cancelled, 1, "the cancelled count comes off the tray");
    assert_eq!(shot.rolls[2].count, 4 - cancelled, "the save batch rolls the remaining hits");
    assert!(shot.log.iter().any(|l| l == "Parry: Defender rolls 2 dice and ignores 1 Impact hits"), "{:?}", shot.log);
}

/// Epoch 72 is byte-exact: the Parry stamp is off, so no Parry die is drawn and all four Impact hits
/// go straight to the saves.
#[test]
fn no_parry_dice_are_drawn_at_epoch_72() {
    let (shot, _) = charge(EPOCH_72_PLAYTEST_RULES, 4, 2, &["Parry(1)"], None);
    assert!(shot.rolls.iter().all(|r| r.kind != "parry"), "{:?}", shot.rolls);
    assert!(shot.log.iter().all(|l| !l.starts_with("Parry:")), "{:?}", shot.log);
    assert_eq!(shot.rolls.iter().find(|r| r.kind == "defense").unwrap().count, 4);
}

/// CONTROL: a defender without Parry draws no Parry dice at epoch 73 either.
#[test]
fn a_defender_without_parry_draws_no_parry_dice() {
    let (shot, _) = charge(EPOCH_73_V36, 4, 2, &[], None);
    assert!(shot.rolls.iter().all(|r| r.kind != "parry"), "{:?}", shot.rolls);
    assert!(shot.log.iter().all(|l| !l.starts_with("Parry:")), "{:?}", shot.log);
}

/// A joined hero's Parry counts beside the host's: one Parry(1) host model and one Parry(1) hero
/// model draw two dice.
#[test]
fn a_joined_heros_parry_counts_beside_the_hosts() {
    let (shot, _) = charge(EPOCH_73_V36, 4, 1, &["Parry(1)"], Some(&["Parry(1)"]));
    assert_eq!(parry_roll(&shot).count, 2, "host and hero each add one Parry(1) die");
}

/// Never more dice than hits taken: Impact(1) on one model rolls one hit, so 2 Parry(1) models draw
/// ONE die, not two.
#[test]
fn parry_dice_never_exceed_the_hits_taken() {
    let (shot, _) = charge(EPOCH_73_V36, 1, 2, &["Parry(1)"], None);
    assert_eq!((shot.rolls[0].count, shot.rolls[0].faces.clone()), (1, vec![6]), "one Impact die, one hit");
    assert_eq!(parry_roll(&shot).count, 1, "one hit caps two Parry dice at one");
}

//! The skirmish Pushing rule (3.6 Firefight / AoF: Skirmish p.15): "When a unit is Shaken after being attacked, the
//! attacker may try to push it." The attacker's offer is `activation::Input::Push`, resolved at the end of the attack.
use super::*;
use crate::activation::PushInput;

/// Unit "a" (player 0, `sys`) fires 6 shots (Quality 2) at "b": two models 12 in east, Defense 6, Quality 6, so a lost
/// model usually fails its morale test. `shaken_before` marks "b" Shaken at the start. A push of b's first model 1 in east
/// is offered for `target`.
fn push_game(sys: &str, epoch: u32, seed: i64, target: &str, shaken_before: bool) -> ShootResult {
    let mut st = four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
    let mut p = st.profiles.list[0].clone();
    p.game_system = sys.into();
    st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions = vec![vec![at(0.0, 0.0)], vec![at(-30.0, 0.0)], vec![at(12.0, 0.0), at(12.0, 1.5)], vec![at(30.0, 20.0)]];
    st.radii = Rc::new(vec![vec![0.5 * IN2M], vec![0.5 * IN2M], vec![0.5 * IN2M; 2], vec![0.5 * IN2M]]);
    st.wounds = vec![vec![1], vec![1], vec![1, 1], vec![1]];
    st.alive = vec![1, 1, 2, 1];
    st.shaken[2] = shaken_before;
    let gun = ShootProfile { name: "Rifle".into(), attacks: 6, count: 1, range: 24, ..Default::default() };
    let unit = |name: &str, n: i64, q: i64, shoot: Vec<ShootProfile>| UnitStatic {
        name: name.into(), shoot, model_count: n, wounds_max: vec![1; n as usize],
        ctx: Ctx { quality: q, defense: 6, models: n, ..Default::default() }, ..Default::default()
    };
    let statics = vec![unit("Gunners", 1, 2, vec![gun]), unit("Spare", 1, 4, vec![]), unit("Target", 2, 6, vec![]), unit("Far", 1, 4, vec![])];
    let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let mut tray = Tray::seeded(seed);
    tray.offer_push(Some(PushInput { target: target.into(), model: 0, to: at(13.0, 0.0) }));
    resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap().1
}

fn push_line(shot: &ShootResult) -> Option<&String> {
    shot.log.iter().find(|l| l.starts_with("Push: "))
}

/// GFF/AOFS-E10 (legality), end to end: the push holds when this attack left the target Shaken. A target that stays steady
/// and one that was Shaken before are each told no; one epoch below, and in gf, no push is read at all.
#[test]
fn a_push_holds_only_against_the_target_this_attack_shook() {
    let e = crate::acts::PENDING_EPOCH_SKIRMISH_PUSH;
    assert!(e > crate::acts::CURRENT_RULES_EPOCH, "a placeholder no record has played");
    let shook = (0..200).find(|&s| push_line(&push_game("gff", e, s, "b", false)).is_some_and(|l| l.contains("may push")))
        .expect("a seed where the volley shakes b");
    assert_eq!(push_line(&push_game("aofs", e, shook, "b", false)).map(String::as_str), Some("Push: Gunners may push Target (Shaken by this attack)"));
    let steady = (0..200).find(|&s| push_line(&push_game("gff", e, s, "b", false)).is_some_and(|l| l.contains("no push")))
        .expect("a seed where b holds");
    assert_eq!(push_line(&push_game("gff", e, steady, "b", false)).map(String::as_str), Some("Push: no push - Target is not Shaken by this attack"));
    assert_eq!(push_line(&push_game("gff", e, shook, "b", true)).map(String::as_str), Some("Push: no push - Target is not Shaken by this attack"), "Shaken before");
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        assert_eq!(push_line(&push_game(sys, epoch, shook, "b", false)), None, "{sys} at {epoch}");
    }
}

/// `push_holds` on its own (ruling D15): an enemy the attack hit and left Shaken; never the attacker's side, never a unit
/// that was Shaken already, is gone, or was Shaken by something the attack did not hit it with.
#[test]
fn push_holds_reads_enemy_hit_newly_shaken_and_standing() {
    let before = four_unit_line();
    let mut now = before.clone();
    now.shaken = vec![false, true, true, true];
    let hit = [1, 2];
    assert!(push_holds(&before, &now, 0, 2, &hit), "the enemy the attack hit, Shaken now");
    assert!(!push_holds(&before, &now, 0, 3, &hit), "an enemy Shaken now that the attack never hit");
    assert!(!push_holds(&before, &now, 0, 1, &hit), "the attacker's own side, Shaken now");
    let mut shaken_before = before.clone();
    shaken_before.shaken[2] = true;
    assert!(!push_holds(&shaken_before, &now, 0, 2, &hit), "Shaken before the attack");
    now.alive[2] = 0;
    assert!(!push_holds(&before, &now, 0, 2, &hit), "gone");
}

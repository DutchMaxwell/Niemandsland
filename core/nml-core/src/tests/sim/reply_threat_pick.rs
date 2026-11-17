use super::*;

/// The `BattleSim.reply_threat` danger term (battle_sim.gd:1780-1831): every
/// living enemy replies ONCE with the best-EV visible target. A 4-attack rifle
/// at Q4+ vs Def4+ is worth 1.0 expected wound on an open target and 2/3 into
/// cover, so the OPEN twin must win even though the covered one comes FIRST in
/// the roster — "the first target" is not a plan. Blocking the open target's
/// sight line moves the reply to the covered one; blind to both prices nothing.
#[test]
fn reply_threat_picks_the_best_visible_target_not_the_first() {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["Enemy".into(), "Covered".into(), "Open".into(), "Spare".into()],
        index: HashMap::new(),
        profile: vec![0, 0, 0, 0],
    });
    st.player = vec![1, 2, 2, 2];
    st.alive = vec![1, 1, 1, 0];
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.positions = vec![
        vec![[0.0, 0.0, 0.0]],
        vec![[0.0, 0.0, 12.0 * IN2M]],
        vec![[12.0 * IN2M, 0.0, 0.0]],
        vec![[0.0, 0.0, 0.0]],
    ];
    st.in_cover = vec![false, true, false, false];
    let base = UnitStatic {
        model_count: 1,
        wounds_max: vec![1],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        ..Default::default()
    };
    let mut statics = vec![base; 4];
    statics[0].name = "Enemy".into();
    statics[0].shoot = vec![gun("Rifle", 4, 24)];

    let threat = reply_threat(&statics, &st, 2);
    assert!((threat[2] - 1.0).abs() < 0.001, "the open target is worth 1.0: {threat:?}");
    assert_eq!(threat[1], 0.0, "the covered target comes first but is not the best: {threat:?}");
    assert_eq!(threat[3], 0.0);

    st.los[0] = Some(Rc::new(HashMap::from([
        ("Open".to_string(), false),
        ("Covered".to_string(), true),
    ])));
    st.rebuild_sees();
    let threat = reply_threat(&statics, &st, 2);
    assert!((threat[1] - 2.0 / 3.0).abs() < 0.001, "sight moves the reply into cover: {threat:?}");
    assert_eq!(threat[2], 0.0);

    st.los[0] = Some(Rc::new(HashMap::from([
        ("Open".to_string(), false),
        ("Covered".to_string(), false),
    ])));
    st.rebuild_sees();
    assert!(reply_threat(&statics, &st, 2).iter().all(|&x| x == 0.0), "blind to both: no threat");
}

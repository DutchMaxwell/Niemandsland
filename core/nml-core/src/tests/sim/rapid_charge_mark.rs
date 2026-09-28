use super::*;

#[test]
fn marked_target_opens_a_fourteen_inch_charge_only_at_epoch_66() {
    let (mut st, mut statics) = vr_charge_line(14.0);
    let charger_profile: Profile = serde_json::from_str(
        r#"{"unit_id":"a","name":"Charger","game_system":"aof","faction_folder":"dark_elves"}"#,
    ).unwrap();
    let mut registry = crate::rules::Registries::new(&repo_root());
    let charger_stamp = UnitStatic::build_for(&mut registry, &charger_profile, 66);
    assert_eq!(charger_stamp.rapid_charge_grant_in, 4.0,
        "the charger's book supplies the Mark's four inches");
    statics[0].rapid_charge_grant_in = charger_stamp.rapid_charge_grant_in;
    // Keep the target alive so the post-charge base gap remains measurable.
    st.wounds[1] = vec![20];
    statics[1].ctx.tough = 20;
    statics[1].wounds_max = vec![20];
    st.buffs[1].push(mods::LiveMod {
        hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0,
        def_mod: 0, defense_mod: 0, move_mod: 0,
        grants_rule: Rc::from("Rapid Charge"), scope: Rc::from("melee"),
        attackers: true, once: true, name: Rc::from("Rapid Charge Mark"),
    });
    let charge = vr_charge();
    let run = |epoch| {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &small_board(),
            Seams { rules_epoch: epoch, movement: true, ..Seams::default() },
            &mut rng, &mut tray,
        ).unwrap()
    };
    let (old, old_log) = run(65);
    assert!(vr_gap(&old) > 1.0, "without the grant, 12\" cannot close 14\"");
    assert!(old_log.log.iter().all(|line| !line.contains("Rapid Charge Mark: +4\"")));
    let (new, new_log) = run(66);
    assert!(vr_gap(&new) < 0.3, "the mark's +4\" opens the 14\" charge, gap {}", vr_gap(&new));
    assert!(new_log.log.iter().any(|line| line.contains("Rapid Charge Mark: +4\" charge reach against Target")));
}

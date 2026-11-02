use super::*;

// DAT-06 follow-up — the AoF "Piercing Charge Buff" hands one friendly unit
// the granted rule "Piercing Charge" (the mechanics map's `grants_rule`). The
// charge fold only asked for the literal "Piercing Assault", so a unit that
// carried the buff's grant got no AP. From `EPOCH_73_V36` the granted rule must
// read as the same primitive; below 73 the recorded ledger stays blind and the
// corpus replays byte-identically.

/// The grant one recorded "Piercing Charge Buff" leaves on its bearer: the
/// buff's OWN name, the granted rule the mechanics map wires.
fn piercing_charge_grant() -> mods::LiveMod {
    let mut reg = crate::rules::Registries::new(&repo_root());
    let profile: Profile = serde_json::from_str(
        r#"{"unit_id":"a","name":"a","game_system":"aof","faction_folder":"dark_elves","special_rules":["Piercing Charge Buff"]}"#,
    )
    .unwrap();
    let carrier = UnitStatic::build_for(&mut reg, &profile, crate::acts::EPOCH_73_V36);
    assert_eq!(carrier.utility_buffs.len(), 1, "the buff resolves off the registry");
    let grants_rule = carrier.utility_buffs[0].grants_rule.clone();
    assert_eq!(
        grants_rule, "Piercing Charge",
        "the buff hands out the new base name, not its own entry name"
    );
    mods::LiveMod {
        hit_mod: 0,
        casting_mod: 0,
        morale_mod: 0,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        grants_rule: Rc::from(grants_rule.as_str()),
        scope: Rc::from(""),
        attackers: false,
        once: true,
        name: Rc::from("Piercing Charge Buff"),
    }
}

/// A charged exchange: `a` (the buff's bearer) reaches `b` at 2.5" with a
/// 64-attack CCW so the strike save batch always draws.
fn charge_grant_line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    st.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
    Rc::make_mut(&mut st.radii)[2] = vec![IN2M];
    st.wounds[2] = vec![1];
    st.alive[2] = 1;
    statics[2].model_count = 1;
    statics[2].wounds_max = vec![1];
    statics[0].melee = vec![gun("CCW", 64, 0)];
    st.buffs[0].push(piercing_charge_grant());
    (st, statics)
}

fn charge_b() -> Action {
    Action {
        kind: CHARGE,
        unit: "a".into(),
        dest: None,
        shoot: None,
        charge: Some("b".into()),
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    }
}

fn run_charge_epoch(
    st: &State,
    statics: &[UnitStatic],
    epoch: u32,
) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics,
        st,
        &charge_b(),
        &terrain,
        Seams { rules_epoch: epoch, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .unwrap()
}

fn save_targets(res: &ShootResult) -> Vec<i64> {
    res.rolls
        .iter()
        .filter(|r| r.kind == "defense")
        .map(|r| r.target)
        .collect()
}

#[test]
fn the_piercing_charge_buff_grant_gives_the_charge_ap_bonus_at_73_and_not_at_72() {
    let (st, statics) = charge_grant_line();

    // ----- epoch 73: the grant reads as the Piercing Assault primitive -----
    let (_, struck73) = run_charge_epoch(&st, &statics, crate::acts::EPOCH_73_V36);
    let saves73 = save_targets(&struck73);
    assert!(!saves73.is_empty(), "the 64-attack charge draws the strike saves");
    assert!(
        saves73.iter().all(|&t| t == 5),
        "at 73 every strike save rides AP(+1): defense 4 saves at 5+, got {:?}",
        saves73
    );

    // ----- epoch 72: the live predecessor epoch — the ledger stays blind -----
    let (_, struck72) = run_charge_epoch(&st, &statics, 72);
    let saves72 = save_targets(&struck72);
    assert!(!saves72.is_empty(), "the same charge draws the strike saves at 72");
    assert!(
        saves72.iter().all(|&t| t == 4),
        "below 73 the granted buff is not the primitive: plain defense 4, got {:?}",
        saves72
    );
}

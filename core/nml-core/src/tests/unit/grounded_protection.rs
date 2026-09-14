use super::*;

/// EPOCH 56 GROUNDED PROTECTION (sweep F 2026-09-14, row `Grounded
/// Protection`) — the fixture: an aof/volcanic_dwarves unit carrying
/// "Grounded Protection" (the REAL registry entry — primitive Regeneration,
/// ignore_target 5, all_models true, terrain_within_in 1), built off the
/// header at `epoch`.
fn gp_unit(epoch: u32) -> UnitStatic {
    let tpl = r#"{"kind":"header","knobs":{},"profiles":{
      "gp":{"unit_id":"gp","name":"Hammer Guard","quality":3,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"volcanic_dwarves",
        "special_rules":["Grounded Protection"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;
    let header = read_act_header(tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("gp").expect("gp");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// The exchange: 24 rifle dice at Quality 2 into the carrier (Defense 3,
/// Tough 1, seed 27) — the disintegrate_bypass harness's own numbers, with
/// the DEFENDER's context answered by `sim::ctx_live` over the state's own
/// `in_cover` (the verdict site).
fn volley_at_56(us: &UnitStatic, st: &crate::state::State) -> crate::dice::ShootResult {
    let shooter = shooter_unit();
    let att = Ctx { quality: 2, models: 1, ..Default::default() };
    let def = crate::sim::ctx_live(
        crate::sim::ctx_of(us, st, 0), std::slice::from_ref(us), st, 0, false,
        crate::acts::EPOCH_56_GROUNDED_PROTECTION,
    );
    let mut tray = crate::dice::Tray::seeded(27);
    crate::dice::resolve_shooting_with_tray(
        &shooter.shoot, &[0], &[24], &att, &def, 12.0, &mut tray,
    )
}

/// The attacker: a bare gf shooter with one ranged weapon (no rules of its
/// own), the volley harness's plain aggressor.
fn shooter_unit() -> UnitStatic {
    let tpl = r#"{"kind":"header","knobs":{},"profiles":{
      "sh":{"unit_id":"sh","name":"Shooter","quality":2,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":24,"count":1,"ap":0,
          "rules":[]}]}}}"#;
    let header = read_act_header(tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("sh").expect("sh");
    UnitStatic::build_for(&mut reg, p, OLD_EPOCH)
}

/// The one-unit state, read back through the io round-trip (the teleport
/// latch's shape) — `in_cover` is the ONLY thing that varies.
fn state_of(in_cover: bool) -> crate::state::State {
    let plain = format!(
        r#"{{"round":0,"rounds_total":1,"units":{{"gp":{{"player":1,"alive":1,"activated":false,"shaken":false,"fatigued":false,"in_cover":{in_cover},"aircraft":false,"dormant":false,"dormant_models":0,"dormant_wounds":[],"casts":0,"morale_bonus":0,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"positions":[[0.0,0.0,0.0]],"wounds":[1],"radii":[0.0254],"mods":{{}},"mods_base":{{}},"attached":[],"attached_to":""}}}}}}"#
    );
    let profile = crate::state::Profile {
        unit_id: "gp".into(), name: "Hammer Guard".into(), quality: 3, defense: 3, tough: 1,
        wounds_max: vec![1], model_count: 1, weapons: vec![],
        special_rules: vec!["Grounded Protection".into()], caster_value: 0, base_radius: 0.0,
        base_shape: String::new(), base_w_mm: 0.0, base_d_mm: 0.0,
        game_system: "aof".into(), faction_folder: "volcanic_dwarves".into(),
        item_grants: vec![], attached_hero_rules: vec![], move_bands: Default::default(),
    };
    let mut index = std::collections::HashMap::new();
    index.insert("gp".to_string(), 0);
    let mut pc = crate::state::ProfileCache::new(std::rc::Rc::new(crate::state::Profiles {
        list: vec![profile], index,
    }));
    let mut rc = None;
    crate::io::state_from_json(&plain, &mut pc, &mut rc).unwrap()
}

/// The old-leg pin — the frozen constant of the epoch immediately below the
/// bump AT REBASE TIME (re-pointed at every rebase, never the live symbol;
/// 54 is `EPOCH_55_FORTIFIED_AURA`'s own landed leg, #976).
const OLD_EPOCH: u32 = crate::acts::EPOCH_55_FORTIFIED_AURA;

/// EPOCH 56 GROUNDED PROTECTION — the STAMP split: at 56 the alias fold holds
/// the terrain-gated target ASIDE (`regen_target` 0 — the fold no longer
/// reads as unconditional), below 56 the recorded flat fold replays (5+).
#[test]
fn the_stamp_holds_the_terrain_gated_target_aside_at_56_and_folds_flat_below() {
    let at_53 = gp_unit(crate::acts::EPOCH_56_GROUNDED_PROTECTION);
    assert_eq!(
        at_53.ctx.regen_target, 0,
        "the terrain condition is the rule's whole point — the stamp must not fold it flat"
    );
    assert_eq!(
        at_53.ctx.regen_pending, 5,
        "the held-aside target waits for the save-moment verdict"
    );
    let old = gp_unit(OLD_EPOCH);
    assert_eq!(
        old.ctx.regen_target, 5,
        "below 56 the recorded reading replays — wounds ignored on 5+ anywhere"
    );
}

/// EPOCH 56 GROUNDED PROTECTION — the SAVE-MOMENT verdict: `ctx_live` over the
/// open snapshot answers NO Regeneration; over the in-cover snapshot the
/// held-aside 5+ folds (the Shielded family's terrain-pending resolution,
/// sim.rs's `c.in_cover` read). Below 56 the recorded reading replays — the
/// protection applies in the open too (the defect, frozen).
#[test]
fn the_verdict_answers_in_the_open_and_in_cover_at_56_below_52_stays_flat() {
    let us = gp_unit(crate::acts::EPOCH_56_GROUNDED_PROTECTION);
    let open = crate::sim::ctx_live(
        crate::sim::ctx_of(&us, &state_of(false), 0),
        std::slice::from_ref(&us), &state_of(false), 0, false, crate::acts::EPOCH_56_GROUNDED_PROTECTION,
    );
    assert_eq!(
        open.regen_target, 0,
        "in the open there is no Grounded Protection — no Regeneration fold"
    );
    let near = crate::sim::ctx_live(
        crate::sim::ctx_of(&us, &state_of(true), 0),
        std::slice::from_ref(&us), &state_of(true), 0, false, crate::acts::EPOCH_56_GROUNDED_PROTECTION,
    );
    assert!(
        near.regeneration && near.regen_target == 5,
        "within terrain the held-aside 5+ folds (regeneration {}, target {})",
        near.regeneration, near.regen_target
    );
    let old = gp_unit(OLD_EPOCH);
    let old_open = crate::sim::ctx_live(
        crate::sim::ctx_of(&old, &state_of(false), 0),
        std::slice::from_ref(&old), &state_of(false), 0, false, OLD_EPOCH,
    );
    assert_eq!(
        old_open.regen_target, 5,
        "below 56 the recorded reading replays — 5+ in the open too"
    );
}

/// EPOCH 56 GROUNDED PROTECTION — the DICE-level proof: a Grounded Protection
/// unit in the open takes every unsaved wound and draws NO Regeneration roll,
/// the same unit within terrain pools them (a 5+ roll on the record), and
/// below 56 the recorded reading replays (the pool fires in the open too).
/// The asserts read the ROLL RECORD, never the drawn faces — deterministic.
#[test]
fn the_open_unit_takes_every_wound_at_56_and_below_55_still_pools() {
    let us = gp_unit(crate::acts::EPOCH_56_GROUNDED_PROTECTION);
    let new_open = volley_at_56(&us, &state_of(false));
    assert!(
        new_open.caused > 0,
        "fixture seed no longer wounds — pick another"
    );
    assert_eq!(
        new_open.wounds, new_open.caused,
        "in the open there is no Regeneration roll — every wound lands"
    );
    assert!(
        new_open.rolls.iter().all(|r| r.target != 5),
        "no 5+ Regeneration roll in the open at 55: {:?}",
        new_open.rolls
    );
    let new_near = volley_at_56(&us, &state_of(true));
    assert!(
        new_near.rolls.iter().any(|r| r.target == 5),
        "within terrain the 5+ pool fires (rolls {:?})",
        new_near.rolls
    );
    let old = gp_unit(OLD_EPOCH);
    let old_open = volley_at_56(&old, &state_of(false));
    assert!(
        old_open.rolls.iter().any(|r| r.target == 5),
        "below 56 the recorded reading replays — the pool fires in the open (rolls {:?})",
        old_open.rolls
    );
}

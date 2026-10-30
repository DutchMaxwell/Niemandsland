use super::super::*;

/// SHO-PAR-F6 (lead ruling O1: all weapons of a volley fire together): the core takes every shot's
/// attack count from the declaration and never re-reads the target's survivors between weapons. A
/// Deadly missile that wipes a one-model target first still leaves the flamer's three declared dice
/// on the tray; the table matches this from EPOCH_73_V36 (main.gd `_solo_resolve_ai_volley`).
#[test]
fn a_later_weapon_rolls_its_declared_dice_after_a_deadly_wipe() {
    let att = shooter(2);
    let def = defender(6, 1);
    let guns = [
        ShootProfile { name: "Missile".into(), ap: 4, deadly: 3, ..rifle(4) },
        ShootProfile { name: "Flamer".into(), range: 6, ..rifle(3) },
    ];
    let r = resolve_volley_leg(&[Shooter { profiles: &guns, keep: &[0, 1], attacks: &[4, 3], att: &att, owner: "a" }],
        &def, "b", 4.0, 4.0, true, true, true, true, true, true, &|_| false, &mut Tray::seeded(7));
    let attacks: Vec<i64> = r.rolls.iter().filter(|x| x.kind == "attack").map(|x| x.count).collect();
    assert!(r.deadly_tally >= 1, "fixture: the missile wipes the one-model target first");
    assert_eq!(attacks, vec![4, 3], "the flamer keeps its declared dice after the wipe");
}

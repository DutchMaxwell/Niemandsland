use super::*;
use crate::acts::EPOCH_51_CASTER_INTERFERENCE;

// --- Sweep F row `Fortified Aura` (epoch 53): the aofs/gff aura entry's
// `lost_if_bearer_killed` / `max_picks` become READ data. ---
//
// Registry, two spellings: aof = "Fortified Aura" is an `Aura Channel`
// (grants the bare base, the loader/`apply_aura_channel` leg); aofs/gff =
// "Fortified Aura" is ITSELF a `Fortified`-primitive entry with
// `aura_expand`, `max_picks 3`, `lost_if_bearer_killed`. The import
// expansion stamps the granted base on every member, so the bearer's death
// must end the squad's AP(-1) — and the entry's pick cap must refuse a pick
// past `max_picks`.
//
// The squad fixture: duchies_of_vinci (aofs) fields the aura entry; the
// squad carries the import-granted bare "Fortified" and, while he lives,
// the bearer hero's list (the loader grants the base to EVERY member, so
// the hero's own list is the aura name AND the granted base). The DEAD
// leg is the same header with the hero fallen — `ProfileDyn` drops a dead
// hero's list wholesale, so `[]` is exactly what a rebuild sees.

const SQUAD_HEAD: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "squad":{"unit_id":"squad","name":"Squad","quality":4,"defense":4,"tough":1,
    "wounds_max":[1],"model_count":5,"caster_value":0,"base_radius":0.016,
    "game_system":"aofs","faction_folder":"duchies_of_vinci",
    "special_rules":["Fortified"],"item_grants":[],
    "attached_hero_rules":__HEROES__,
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":1,"rules":[]}]}}}"#;

const BEARER_ALIVE: &str = "[[\"Fortified Aura\",\"Fortified\"]]";

/// The raw aofs spelling: NO import grants anywhere — the core's own
/// `aura_expand` fold is the only grant leg, so the pick cap is observable
/// straight off `build_for`'s all-models read (one ungranted member
/// withholds the unit-wide rule).
const RAW_AURA: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "squad":{"unit_id":"squad","name":"Squad","quality":4,"defense":4,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"aofs","faction_folder":"duchies_of_vinci",
    "special_rules":["Fortified Aura"],"item_grants":[],
    "attached_hero_rules":__HEROES__,
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":1,"rules":[]}]}}}"#;

fn hero_lists(n: usize) -> String {
    let one = "[\"Fortified Aura\"]".to_string();
    let inner: Vec<String> = (0..n).map(|_| one.clone()).collect();
    format!("[{}]", inner.join(","))
}

fn squad_ctx(template: &str, heroes: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(&template.replace("__HEROES__", heroes)).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("squad").expect("squad");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// The bearer hero falls: at the sweep's epoch the squad's save loses the
/// Fortified bonus (the entry's `lost_if_bearer_killed` is READ); at the
/// frozen epoch immediately below the bump the old leg keeps it. Epoch
/// literals 53 and `EPOCH_51_CASTER_INTERFERENCE` (the frozen constant of
/// the epoch immediately below the bump at rebase time), never
/// `CURRENT_RULES_EPOCH` — a wave bump must not re-date these.
#[test]
fn bearer_death_ends_the_fortified_bonus_at_53_and_keeps_it_below() {
    let alive = squad_ctx(SQUAD_HEAD, BEARER_ALIVE, 53);
    assert!(alive.ctx.fortified, "bearer alive: the granted base fires");
    let (target_alive, fired_alive) = fortified_volley(&alive, 12.0);
    assert_eq!(
        (target_alive, fired_alive),
        (4, true),
        "defense 4 at AP(1) with the Fortified read: saves on 4+"
    );

    let dead = squad_ctx(SQUAD_HEAD, "[]", 53);
    assert!(
        !dead.ctx.fortified,
        "bearer dead: lost_if_bearer_killed ends the benefit — RED before the fix"
    );
    let (target_dead, fired_dead) = fortified_volley(&dead, 12.0);
    assert_eq!(
        (target_dead, fired_dead),
        (3, false),
        "the squad's save falls back to the raw AP(1): saves on 3+"
    );

    // OLD LEG — the frozen epoch immediately below the bump: the reading is
    // the shipped one, the fallen bearer keeps the squad at AP(-1).
    let old = squad_ctx(SQUAD_HEAD, "[]", EPOCH_51_CASTER_INTERFERENCE);
    assert!(old.ctx.fortified, "below the bump: the old leg keeps the benefit");
    let (target_old, fired_old) = fortified_volley(&old, 12.0);
    assert_eq!((target_old, fired_old), (4, true), "old leg byte-exact");
}

/// The pick cap: the raw-header chain (bearer unit + N heroes, all carrying
/// the aura, nothing import-granted) is granted the base by the core's own
/// `aura_expand` fold — up to `max_picks` (3) members. The 4th pick is
/// refused, which the all-models read answers FALSE on; the in-cap control
/// answers TRUE. Below the bump the fold is inert (both FALSE — the old
/// leg replays the raw header untouched).
#[test]
fn a_fourth_pick_is_refused_at_53() {
    let two = squad_ctx(RAW_AURA, &hero_lists(2), 53);
    assert!(
        two.ctx.fortified,
        "in cap (unit + 2 heroes = 3 picks): every member carries the base"
    );
    let three = squad_ctx(RAW_AURA, &hero_lists(3), 53);
    assert!(
        !three.ctx.fortified,
        "a 4th pick is refused at max_picks 3 — RED before the fix"
    );
    let old_two = squad_ctx(RAW_AURA, &hero_lists(2), EPOCH_51_CASTER_INTERFERENCE);
    let old_three = squad_ctx(RAW_AURA, &hero_lists(3), EPOCH_51_CASTER_INTERFERENCE);
    assert!(
        !old_two.ctx.fortified && !old_three.ctx.fortified,
        "below the bump the fold is inert: the raw header replays ungranted"
    );
}

use super::super::*;

/// SHO-15a: Scourge is a 3.6 weapon rule with one meaning in every gf and aof book that fields it, so
/// both maps carry it once in `common`: 2 phantom wounds per unmodified 1 on the block roll.
#[test]
fn sho_15a_scourge_resolves_in_both_systems_with_two_phantom_wounds() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "dwarf_guilds"), ("aof", "dwarves")] {
        let map = reg.rules_for(system);
        let entry = map.lookup(book, "Scourge").expect("a Scourge entry");
        assert_eq!(entry.primitive.as_deref(), Some("Scourge"), "{system} / {book}: Scourge primitive");
        assert_eq!(entry.params, serde_json::json!({"phantom_wounds_per_save_one": 2}), "{system} / {book}: params");
    }
}

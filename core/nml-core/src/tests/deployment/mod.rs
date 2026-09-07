    //! Per-family tests that own a DEPLOYMENT seam — putting a unit onto the
    //! table and taking one off it, not one activation's resolve. Wired the
    //! `tests/sim` way (`#[path = "tests/deployment/mod.rs"]`), so the rule
    //! census never reads a test literal as a resolver arm
    //! (`rule_universe_census.py::core_src_files` excludes `src/tests/`).
    use super::*;
    // Tests exercise "the current epoch" generically (bumped forward each
    // wave); production reads the FROZEN `EPOCH_7_TABLE_RULES` instead.
    use crate::acts::{read_act_header, CURRENT_RULES_EPOCH};
    use crate::io;
    use crate::rules::Registries;
    use crate::state::{ProfileCache, State};
    use crate::unit::UnitStatic;

    /// The checkout this crate lives in — mirrors `tests/rollout/mod.rs`.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// Index of a unit by its capture key, so a fixture asserts on names
    /// rather than on the JSON object's order.
    fn idx(st: &State, key: &str) -> usize {
        (0..st.units()).find(|&i| st.key(i) == key).unwrap_or_else(|| panic!("no unit {key}"))
    }

    /// Statics off the PRODUCTION path (`UnitStatic::build_for` over the
    /// header's own profile table), so a rule flag in a fixture is the one the
    /// shipped registry data resolves — never a hand-set field.
    fn statics_of(st: &State, epoch: u32) -> Vec<UnitStatic> {
        let mut reg = Registries::new(&repo_root());
        st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, epoch)).collect()
    }

    mod reinforcement;

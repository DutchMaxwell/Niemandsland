# Glossary

The words below are the project's shared vocabulary. Code, tests, log lines, docs and pull
requests use them with exactly this meaning. When a change needs a new term, add it here in the
same pull request; do not invent a synonym for a term that already exists.

| Term | Meaning | Avoid |
| --- | --- | --- |
| rules core | The Rust crate `core/nml-core`: dice, state and legality of a game, deterministic for a given seed. The single source of truth for rules. | "engine", "backend", "simulator" for the core alone |
| table | The Godot game (`scripts/`): what the player sees and touches - board, models, dialogs, battle log. It asks the rules core and presents the answer. | "frontend", "client" |
| table resolver | The GDScript code that still resolves a rule itself instead of asking the rules core. Legacy; removed step by step. | "old engine", "GD rules" |
| door | `CoreActivation` (`scripts/solo/core_activation.gd`): the seam where the table hands an activation to the rules core and receives the result. See ADR 0001. | "bridge", "adapter" |
| activation | One unit's turn step: its action (Hold, Advance, Rush, Charge), movement, shooting or melee and the rolls that follow. | "move" for the whole step |
| volley | All shooting of one unit in one activation against its target(s), resolved as one batch of rolls. | "attack" for shooting only |
| held volley | A volley the rules core cannot resolve and the table no longer resolves: it is not fired, and one battle-log line names the unit and the reason. | "skipped shot", "dropped volley" |
| rules epoch | The integer `CURRENT_RULES_EPOCH`: every change of a rule outcome is gated behind the epoch it ships in, so old replays and recordings stay reproducible. See ADR 0002. | "rules version" |
| battle log | The in-game list of rule events a player reads; every applied special rule writes a line to it. | "console", "game log" |
| snapshot pin | A literal expected value in a test that records what the rules core produced on `main`, not a value derived from the rulebook. See ADR 0005. | "golden value" without saying it is a snapshot |
| digest | A hash over a seeded run of the rules core; identical digests before and after a change prove the change did not alter any outcome. | "checksum" |
| generated board | A board built from a seed by `boardgen` (layout, levels, walls, ladders); its grid is the gameplay truth for movement, cover and sight. | "map", "level" |
| dressing | The authored modules placed over a generated board for its look; it never changes what the grid says. See ADR 0003. | "decoration", "skin" |
| kit / module / manifest | The dressing's assets: a module is one authored mesh (wall panel, roof segment, ...), the kit is the set of modules, the manifest (`assets/ruintown_dress.json`) lists them with their materials and bounds. See ADR 0004. | "prefab", "tile" |
| honesty rules | The checks R0-R5 in `BoardgenDressRules` that a dressing must pass so it never lies about the grid (no fake cover, no blocked ladder, no overhang over a walkable cell). | "validation" alone |

# Free shelf piece sight parity

`cases.json`: 1,000 seeded sight lines, each against ONE freely placed shelf piece (a 6x3" 2.5" solid, a 9x6"
6" ruin hull or a 6x4" 3.4" forest hull; yaw 0/45/90 deg or random), with the table's verdict
(`VolumetricLos.has_los`). Values are stored exactly as GDScript holds them (Vector2 = 32-bit floats).
`test/shelf_sight_parity_test.gd` pins every verdict to the table; the Rust core replays the same file.
Regenerate (seed 20261003): `godot --headless --path . -s tools/shelf_sight_parity.gd`.

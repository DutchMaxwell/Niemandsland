//! Runtime seam regression. Cargo builds the cdylib as an integration-test
//! dependency; opt in once Godot and the optional manifest are installed.
use std::{path::Path, process::Command};

#[test]
#[ignore = "requires Godot 4.6 and the installed GDExtension manifest"]
fn pinned_shape_fixture_crosses_the_godot_move_boundary() {
    run_pin("base_shapes.json", "base_shapes");
}

#[test]
#[ignore = "requires Godot 4.6 and the installed GDExtension manifest"]
fn pinned_shorten_fixture_crosses_the_godot_move_boundary() {
    run_pin("whole_unit_shorten.json", "whole_unit_shorten");
}

#[test]
#[ignore = "requires Godot 4.6 and the installed GDExtension manifest"]
fn pinned_charge_fixture_crosses_the_godot_move_boundary() {
    run_pin("charge_gates.json", "charge_snap");
}

fn run_pin(pin_file: &str, capability: &str) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap();
    let result = Command::new("python3")
        .current_dir(root)
        .args(["-c", r#"
import json, os, sys, tempfile
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, str(Path.cwd() / 'tools'))
import position_parity as p
fixtures = json.loads(p.FIXTURES.read_text())
pin = json.loads((p.FIXTURES.parent / sys.argv[1]).read_text())
fixtures['cases'] = [c for c in fixtures['cases'] if c['id'] == pin['source_case']]
assert len(fixtures['cases']) == 1
with tempfile.TemporaryDirectory(prefix='position-parity-seam-') as directory:
    directory = Path(directory)
    source, raw, log = [directory / x for x in ('cases.json', 'report.json', 'godot.log')]
    source.write_text(json.dumps(fixtures))
    args = SimpleNamespace(godot=os.environ.get('GODOT_BIN', 'godot'), fixtures=source, timeout=300)
    try:
        p.run_godot(args, raw, log)
    except Exception:
        if log.exists(): print(log.read_text())
        raise
    report = json.loads(raw.read_text())
    row, = report['rows']
    assert row['rust_ok'], row['boundary_error']
    assert sys.argv[2] in row['table_stages']
    assert sys.argv[2] in row['rust_capabilities']
    if sys.argv[2] == 'charge_snap':
        assert abs(row['rust_snap_in'] - row['table_snap_in']) <= pin['tolerance_in']
    measured = p.measure(fixtures, report)
    assert measured['summary']['declined'] == 0, measured
    assert measured['summary']['within_0.5in'] == 1, measured
    print(p.summary_line(measured))
"#, pin_file, capability])
        .status().expect("launch the Godot seam test driver");
    assert!(result.success(), "the pinned fixture must cross the live MOVE seam");
}

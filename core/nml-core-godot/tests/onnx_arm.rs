//! Arm switch harness (M1b-1): the pure `arm_from` decision — one positive arm
//! and every decline on its own reason. tract only.
#![cfg(feature = "onnx-tract")]

use nml_core_godot::onnx::arm_from;
use serde_json::Value;

fn fixture(name: &str) -> Vec<u8> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/onnx")
        .join(name);
    std::fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn brain_path() -> String {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/onnx/standin-v2x2.onnx")
        .to_str().unwrap().to_string()
}

fn provenance_sha() -> String {
    let provenance: Value =
        serde_json::from_slice(&fixture("provenance_standin-v2x2.json")).unwrap();
    provenance["runs"]["run1"]["raw_sha256"].as_str().unwrap().to_string()
}

fn decline(developer: bool, url_set: bool, sha256: &str, w: &str) -> String {
    match arm_from(developer, url_set, &brain_path(), sha256, w) {
        Some(Err(reason)) => reason,
        Some(Ok(_)) => panic!("this arm must decline"),
        None => panic!("the path is set"),
    }
}

#[test]
fn arm_from_loads_the_standin_on_the_provenance_sha() {
    let sha = provenance_sha();
    let arm = arm_from(true, false, &brain_path(), &sha, "")
        .expect("the path is set").expect("the stand-in must arm");
    assert_eq!(arm.weight, 1.0);
    assert_eq!(arm.brain.label(), "standin-v2x2");
    assert_eq!(arm.brain.sha256(), sha);
    assert_eq!(arm.brain.members(), 2);
    assert_eq!(arm.brain.static_batch(), 32);
    println!("ONNX_ARM case=positive weight={} label={} sha={} selftest=ok",
        arm.weight, arm.brain.label(), arm.brain.sha256());
}

#[test]
fn arm_from_flipped_sha_declines() {
    let sha = provenance_sha();
    let flipped = format!("0{}", &sha[1..]);
    assert_ne!(flipped, sha);
    assert!(decline(true, false, &flipped, "").contains("onnx: sha256 mismatch"));
}

#[test]
fn arm_from_bad_weight_declines() {
    let sha = provenance_sha();
    for w in ["0", "nan"] {
        let reason = decline(true, false, &sha, w);
        assert!(reason.contains("onnx: weight"), "w={w}: {reason}");
    }
}

#[test]
fn arm_from_url_conflict_declines() {
    assert!(decline(true, true, &provenance_sha(), "").contains("onnx: NML_BRAIN_URL set"));
}

#[test]
fn arm_from_non_developer_declines() {
    assert!(decline(false, false, &provenance_sha(), "").contains("onnx: DeveloperOnly"));
}

#[test]
fn arm_from_empty_path_is_unset() {
    assert!(arm_from(true, false, "", &provenance_sha(), "").is_none());
}
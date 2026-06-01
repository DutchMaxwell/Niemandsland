"""Tests for publish_manifest.build_manifest (model manifest generation)."""

from __future__ import annotations

import hashlib

import publish_manifest as pm


def _make_glb(root, faction, filename, data=b"GLBDATA"):
    glb = root / "miniatures" / faction / "glb" / filename
    glb.parent.mkdir(parents=True, exist_ok=True)
    glb.write_bytes(data)
    return glb


def test_unit_name_strips_numbered_prefix(tmp_path):
    glb = _make_glb(tmp_path, "alien_hives", "01_Hive Lord.glb")
    assert pm.unit_name_from_filename(glb) == "Hive Lord"


def test_model_key_is_case_insensitive():
    assert pm.model_key("Alien_Hives", "Hive Lord") == "alien_hives/hive lord"


def test_build_manifest_keys_hashes_and_sizes(tmp_path):
    data = b"hello-glb"
    _make_glb(tmp_path, "alien_hives", "01_Hive Lord.glb", data)
    _make_glb(tmp_path, "dao_union", "16_Surge Titan.glb", data)

    manifest = pm.build_manifest(tmp_path / "miniatures", base_url="https://cdn/")

    assert manifest["version"] == 1
    assert manifest["base_url"] == "https://cdn/"
    assert set(manifest["models"]) == {"alien_hives/hive lord", "dao_union/surge titan"}

    entry = manifest["models"]["alien_hives/hive lord"]
    expected_sha = hashlib.sha256(data).hexdigest()
    assert entry["sha256"] == expected_sha
    assert entry["url"] == f"{expected_sha}.glb"
    assert entry["size"] == len(data)


def test_build_manifest_empty_dir(tmp_path):
    (tmp_path / "miniatures").mkdir()
    manifest = pm.build_manifest(tmp_path / "miniatures")
    assert manifest["models"] == {}

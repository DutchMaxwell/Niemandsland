"""Optional integration with externally maintained fleet recorders.

NML_FARM_RECORDERS points to a directory containing gen0_one.py/gen1_one.py.
NML_FARM_IDENTITY_PATCH=1 tests the proposed patch on temporary copies only.
No private scripts or checkpoints are shipped by this repository.
"""
import copy
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import types

import nml_core
import pytest
import selfplay
from core_identity import CoreIdentityCheck
from test_build_identity import ROOT, play, tiny_record


@pytest.mark.parametrize("recorder", ["gen0_one", "gen1_one"])
def test_fleet_recorder_preserves_identity(recorder, tiny_record, tmp_path, monkeypatch, capsys):
    source = os.environ.get("NML_FARM_RECORDERS")
    if not source:
        pytest.skip("external fleet recorders not provided; set NML_FARM_RECORDERS")
    drivers = tmp_path / "drivers"
    drivers.mkdir()
    for name in ("gen0_one", "gen1_one"):
        shutil.copyfile(Path(source) / (name + ".py"), drivers / (name + ".py"))
    if os.environ.get("NML_FARM_IDENTITY_PATCH") == "1":
        subprocess.run(["git", "apply", str(ROOT / "farm/patches/preserve-core-identity.patch")],
                       cwd=drivers, check=True, capture_output=True, text=True)

    # Use a real core-produced game, then exercise the actual recorder main,
    # including serialization. Training/model execution is outside this test.
    fresh = play(tiny_record, True)
    bank, army = tiny_record
    checkpoint = tmp_path / "checkpoint"
    checkpoint.write_bytes(b"identity-test-only")
    output = tmp_path / "records"
    monkeypatch.setenv("NML_REPO", str(ROOT))
    monkeypatch.setitem(sys.modules, "value_player", types.SimpleNamespace(TokenValuePlayer=None))
    # Both private drivers install core shims at import; restore them afterwards.
    monkeypatch.setattr(nml_core, "objective_layout", nml_core.objective_layout)
    monkeypatch.setattr(nml_core, "Tray", nml_core.Tray)
    monkeypatch.setattr(sys, "path", list(sys.path))
    driver = runpy.run_path(str(drivers / (recorder + ".py")))
    monkeypatch.setattr(selfplay, "play_game", lambda *args, **kwargs: copy.deepcopy(fresh))
    args = [recorder, str(output), "--seed", "17", "--dice-seed", "23",
            "--army1", str(army), "--army2", str(army), "--bank", str(bank)]
    if recorder == "gen1_one":
        args += ["--ckpt", str(checkpoint), "--value-seats", "none"]
    monkeypatch.setattr(sys, "argv", args)
    assert driver["main"]() == 0
    written = json.loads((output / "gen0_s17_d23.json").read_text())
    assert written["prescreen"]["core_commit"] == nml_core.BUILD_COMMIT
    assert written["prescreen"]["core_build"] == nml_core.BUILD_INFO
    # Prove the new stamp works even without the legacy top-level copy.
    written.pop("core_commit")
    CoreIdentityCheck(True).check(written, "fleet.json")
    assert capsys.readouterr().err == ""

"""Regression test: the idle runtime and the army tray style must preload in standalone Godot --script mode."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("probe,marker", [("idle_autoload_probe.gd", "IDLE_AUTOLOAD_PROBE_OK"),
                                          ("army_tray_autoload_probe.gd", "TRAY_AUTOLOAD_PROBE_OK")])
def test_autoload_probe_has_no_script_errors(probe, marker):
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        pytest.skip("Godot 4 is not on PATH (set GODOT_BIN); the probe needs the engine")
    with tempfile.TemporaryDirectory(prefix="idle-autoload-probe-") as tmp:
        env = os.environ.copy()
        for key, subdir in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            path = Path(tmp) / subdir
            path.mkdir()
            env[key] = str(path)
        run = subprocess.Popen(
            [godot, "--headless", "--path", str(ROOT), "--script", str(ROOT / "tools" / probe)],
            cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        try:
            output, _ = run.communicate(timeout=8)
        except subprocess.TimeoutExpired:
            run.kill()
            output, _ = run.communicate()
            raise AssertionError("standalone probe stalled:\n" + output)
    assert run.returncode == 0, output
    assert "SCRIPT ERROR" not in output, output
    assert marker in output, output


if __name__ == "__main__":
    test_autoload_probe_has_no_script_errors("idle_autoload_probe.gd", "IDLE_AUTOLOAD_PROBE_OK")
    test_autoload_probe_has_no_script_errors("army_tray_autoload_probe.gd", "TRAY_AUTOLOAD_PROBE_OK")
    print("idle autoload standalone probe: PASS")

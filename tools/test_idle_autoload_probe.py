"""Regression test: the idle runtime must preload in standalone Godot --script mode."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "idle_autoload_probe.gd"


def test_bone_idle_probe_has_no_script_errors():
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    assert godot, "Godot 4 is required for the standalone idle autoload probe"
    with tempfile.TemporaryDirectory(prefix="idle-autoload-probe-") as tmp:
        env = os.environ.copy()
        for key, subdir in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            path = Path(tmp) / subdir
            path.mkdir()
            env[key] = str(path)
        run = subprocess.Popen(
            [godot, "--headless", "--path", str(ROOT), "--script", str(PROBE)],
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
    assert "IDLE_AUTOLOAD_PROBE_OK" in output, output


if __name__ == "__main__":
    test_bone_idle_probe_has_no_script_errors()
    print("idle autoload standalone probe: PASS")

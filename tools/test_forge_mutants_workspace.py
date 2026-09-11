import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forge_mutants as fm


class Proc:
    def __init__(self, stdout='', returncode=0):
        self.stdout, self.stderr, self.returncode = stdout, '', returncode


def test_build_diffs_cache_strips_workspace_prefix(monkeypatch, tmp_path):
    crate_dir = tmp_path / 'core' / 'nml-core'
    crate_dir.mkdir(parents=True)
    out_dir = tmp_path / 'out'
    out_dir.mkdir()

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ['cargo', 'metadata']:
            root = json.dumps({'workspace_root': str(tmp_path / 'core')})
            return Proc(root)
        assert cmd[:3] == ['cargo', 'mutants', '--list'], cmd
        assert cmd[cmd.index('--file') + 1] == 'nml-core/src/x.rs', cmd
        return Proc(
            'nml-core/src/x.rs:12:5: replace foo with bar\n'
            '--- nml-core/src/x.rs\n'
            '+++ nml-core/src/x.rs\n'
            '@@ -12,1 +12,1 @@\n'
            '-foo 1\n'
            '+foo 2\n'
        )

    monkeypatch.setattr(fm.subprocess, 'run', fake_run)

    target = {'file': 'src/x.rs', 'line': 12, 'col': 5, 'desc': 'replace foo with bar',
              'raw': 'src/x.rs:12:5: replace foo with bar'}
    cache = fm.build_diffs_cache(crate_dir, [target], out_dir)

    assert target['raw'] in cache
    assert cache[target['raw']]['diff'].splitlines()[0] == '--- src/x.rs'

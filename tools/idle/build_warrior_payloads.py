#!/usr/bin/env python3
"""Locally package the proven Warrior real-idle forms; never publishes or uploads.

Inputs are the original video forms index and its keep_rig/idle exports. --reauthor
reruns the preserved animation authoring on each existing keep_rig.glb first.
A new keep_rig bake is intentionally not guessed from arbitrary Forge recipes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--forms', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--reauthor', action='store_true')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    forms = json.loads(args.forms.read_text())
    manifest = json.loads(args.manifest.read_text())
    jobs = []
    for key, form in sorted(forms.items()):
        if key.split('#')[0] != 'warriors':
            continue
        assert form['body'] == 'ratmen_warrior_body' and form['tail_bones'] == 5, key
        assert 'weapon_hold' not in json.loads(Path(form['recipe']).read_text()) or form['twohand'], key
        full_key = 'ratmen/' + key
        assert full_key in manifest['models'], full_key
        out = args.out / key.replace('#', '__').replace('+', '_')
        out.mkdir(exist_ok=True)
        source = Path(form['glb'])
        keep_rig = source.with_name('keeprig.glb')
        assert source.is_file() and keep_rig.is_file(), key
        if args.reauthor:
            source = out / 'idle.glb'
            with (out / 'author.log').open('w') as log:
                subprocess.run(['blender', '-b', '-t', '2', '--factory-startup', '--python-exit-code', '1',
                                '-P', str(here / 'author_warrior_idle.py'), '--', str(keep_rig), str(source),
                                str(out / 'animation.json'), str(int(form['twohand']))],
                               stdout=log, stderr=subprocess.STDOUT, check=True, timeout=900)
        jobs.append(dict(key=full_key, source=str(source), out=str(out),
                         materials_by_name={m['name']: m for m in manifest['models'][full_key]['ctex']['materials']},
                         feet_z=form['feet_z'], tail_bones=form['tail_bones'], twohand=form['twohand'],
                         recipe=form['recipe'], keep_rig_sha256=hashlib.sha256(keep_rig.read_bytes()).hexdigest()))
    assert jobs, 'No proven Warrior forms'
    (args.out / 'jobs.json').write_text(json.dumps(jobs, indent=2) + '\n')
    project = args.out / 'export_project'
    project.mkdir(exist_ok=True)
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Idle payload export"\n')
    env = dict(os.environ, XDG_DATA_HOME=str(args.out / 'export_userdata'), XDG_CONFIG_HOME=str(args.out / 'config'))
    with (args.out / 'export.log').open('w') as log:
        subprocess.run(['godot', '--headless', '--path', str(project), '--script', str(here / 'export_payload.gd'),
                        '--', str(args.out / 'jobs.json')], stdout=log, stderr=subprocess.STDOUT,
                       env=env, check=True, timeout=1800)
    log_text = (args.out / 'export.log').read_text()
    assert 'SCRIPT ERROR' not in log_text and 'ERROR:' not in log_text, 'Inspect export.log'
    cache = args.out / 'model_cache'
    cache.mkdir(exist_ok=True)
    report = []
    for job in jobs:
        entry = json.loads((Path(job['out']) / 'idle.json').read_text())
        entry['keep_rig_sha256'] = job['keep_rig_sha256']
        for role in ['mesh', 'poses']:
            blob = entry[role]
            source = Path(blob['url'])
            assert hashlib.sha256(source.read_bytes()).hexdigest() == blob['sha256']
            shutil.copyfile(source, cache / (blob['sha256'] + '.res'))
            blob['url'] = blob['sha256'] + '.res'
        manifest['models'][job['key']]['idle'] = entry
        report.append({'key': job['key'], 'idle': entry})
    (args.out / 'model_manifest.idle.local.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.out / 'export_report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Exported {len(jobs)} real Warrior forms locally; no upload. {args.out}')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Prepare an isolated, entirely offline user directory for the GPU capture lane.
Copies settings and links individual cached blobs read-only by convention; cache
folders themselves are new, so downloads cannot write into the source cache.
"""
import argparse
from pathlib import Path
import shutil

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--payloads', type=Path, required=True)
p.add_argument('--source-user', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
user = a.out.resolve() / 'data/godot/app_userdata/Niemandsland'
user.mkdir(parents=True, exist_ok=True)
for folder in a.source_user.glob('*_cache'):
    if not folder.is_dir():
        continue
    dest = user / folder.name
    dest.mkdir(exist_ok=True)
    for blob in folder.iterdir():
        if blob.is_file() and not (dest / blob.name).exists():
            (dest / blob.name).symlink_to(blob.resolve())
cache = user / 'model_cache'
cache.mkdir(exist_ok=True)
for blob in (a.payloads / 'model_cache').glob('*.res'):
    target = cache / blob.name
    if not target.exists():
        target.symlink_to(blob.resolve())
shutil.copyfile(a.payloads / 'model_manifest.idle.local.json', user / 'manifest_override.json')
(user / 'graphics_settings.cfg').write_text('[graphics]\npreset=2\nfullscreen=false\nreduce_motion=false\nidle_motion=true\n')
print(f'Prepared {user}; point XDG_DATA_HOME at {a.out.resolve() / "data"}')

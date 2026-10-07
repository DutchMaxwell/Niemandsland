#!/usr/bin/env python3
"""Same-seed game identity gate (aifix training-speed lane): every `g*/gen0_s*_d*.json` under dirA must match
dirB (canonical hash minus wall-clock/provenance fields). Exit 1 on any difference or when nothing is comparable."""
import glob, hashlib, json, os, sys
DROP = {"wall_seconds", "core_commit", "core_build", "wall"}
def digest(path):
    r = json.load(open(path))
    def clean(o):
        if isinstance(o, dict):
            return {k: clean(v) for k, v in o.items() if k not in DROP}
        if isinstance(o, list):
            return [clean(v) for v in o]
        return o
    return hashlib.sha256(json.dumps(clean(r), sort_keys=True, allow_nan=True).encode()).hexdigest()
def games(d):
    return {os.path.basename(os.path.dirname(f)): digest(f) for f in glob.glob(os.path.join(d, "g*", "gen0_s*_d*.json"))}
def main(argv):
    a, b = games(argv[1]), games(argv[2])
    common = sorted(set(a) & set(b))
    bad = [g for g in common if a[g] != b[g]]
    print(f"GAME_GATE games_a={len(a)} games_b={len(b)} compared={len(common)} different={len(bad)} {bad[:5]}")
    return 1 if bad or not common else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

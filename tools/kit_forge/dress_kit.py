# dress_kit.py - the ruin-town dressing kit forge.
# Nominal manifest (no Blender needed):  python3 tools/kit_forge/dress_kit.py --manifest-only [<kit dir>]
# Full forge:  blender -b --factory-startup --python tools/kit_forge/dress_kit.py -- [<kit dir>]
# The module table lives in kit_table.py; the builders in kit_build.py; the checks in check_kit.py.
# Without a <kit dir> the output goes to build/kit_forge/ (git-ignored).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_table

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
manifest_only = "--manifest-only" in argv
args = [a for a in argv if not a.startswith("--")]
OUT = args[0] if args else os.path.join(REPO, "build", "kit_forge")

if manifest_only:
    T = kit_table.table()
    kit_table.write(os.path.join(OUT, "ruintown_dress.json"), T)
    print("MANIFEST_DONE", len(T))
else:
    import kit_build
    kit_build.forge(OUT, argv)

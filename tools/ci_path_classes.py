#!/usr/bin/env python3
"""Path classes whose isolation from the rest of the game is a CHECKED fact, not a comment.

  ci_path_classes.py --check              fail when a file outside a class names a class symbol
                                          (class_name or a class file's basename) other than through
                                          the class's one allowed door, or sets its env flag in test/ or .github/
  ci_path_classes.py --suites look        the *_test.gd suites that touch the class
  ci_path_classes.py --is-only look F...  exit 0 only when every F is in the class or under docs/
"""
import fnmatch
import os
import re
import subprocess
import sys

CLASSES = {
    "look": {
        "globs": ["scripts/boardgen_*.gd", "scripts/tiefwerk_*.gd", "shaders/tiefwerk_*",
                  "assets/tiefwerk_manifest.json", "test/boardgen_*_test.gd", "test/tiefwerk_*_test.gd"],
        "doors": [("scripts/main.gd", "BoardgenGreybox.attach_from_env(")],
        "env": "NML_BOARDGEN_SEED",
    },
}
SCAN = ("scripts/", "scenes/", "shaders/", "materials/", "assets/", "tools/", "addons/", "test/", "project.godot")
SELF = ("tools/ci_path_classes.py", "tools/ci_path_classes_test.py")


def in_class(path, cls):
    return any(fnmatch.fnmatch(path, g) for g in CLASSES[cls]["globs"])


def _text(root, path):
    try:
        with open(os.path.join(root, path), "rb") as f:
            data = f.read()
        return None if b"\0" in data[:8192] else data.decode("utf-8", "replace")
    except OSError:
        return None


def symbols(root, files, cls):
    own = [f for f in files if in_class(f, cls) and not f.endswith("_test.gd")]
    names = {os.path.splitext(os.path.basename(f))[0] for f in own}
    for f in own:
        names.update(re.findall(r"^class_name\s+(\w+)", _text(root, f) or "", re.M))
    return re.compile(r"\b(" + "|".join(sorted(map(re.escape, names))) + r")\b")


def check(root, files, cls):
    spec, sym, errors = CLASSES[cls], symbols(root, files, cls), []
    for f in files:
        if in_class(f, cls) or f in SELF:
            continue
        text = _text(root, f) if f.startswith(SCAN) or f.startswith(".github/") else None
        for n, line in enumerate((text or "").splitlines(), 1):
            door = any(f == p and d in line for p, d in spec["doors"])
            if f.startswith(SCAN) and sym.search(line) and not door:
                door_files = " / ".join(os.path.basename(p) for p, _ in spec["doors"])
                errors.append(f"{f}:{n}: {cls.upper()} class reaches the game outside {door_files}'s door "
                              f"(names {sym.search(line).group(1)}); go through the door or move the file into the class")
            if spec["env"] in line and f.startswith(("test/", ".github/")):
                errors.append(f"{f}:{n}: {cls.upper()} class flag {spec['env']} set outside the class (test/ or .github/)")
    return errors


def suites(root, files, cls):
    sym = symbols(root, files, cls)
    return sorted(f for f in files if f.startswith("test/") and f.endswith("_test.gd") and sym.search(_text(root, f) or ""))


def is_only(paths, cls):
    return bool(paths) and all(in_class(p, cls) or p.startswith("docs/") for p in paths)


def main(argv):
    root = os.getcwd()
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split("\n")[:-1]
    if argv[:1] == ["--check"]:
        errors = [e for cls in CLASSES for e in check(root, files, cls)]
        print("\n".join(errors) or f"path classes isolated: " + ", ".join(f"{c} ({len(suites(root, files, c))} suites)" for c in CLASSES))
        return 1 if errors else 0
    if argv[:1] == ["--suites"]:
        print("\n".join(suites(root, files, argv[1])))
        return 0
    if argv[:1] == ["--is-only"]:
        return 0 if is_only(argv[2:], argv[1]) else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

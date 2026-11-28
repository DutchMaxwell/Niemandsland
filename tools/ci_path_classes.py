#!/usr/bin/env python3
"""Path classes whose isolation from the rest of the game is a CHECKED fact, not a comment.

  ci_path_classes.py --check              fail when a file outside a class names a class symbol
                                          (class_name or a class file's basename) other than through
                                          the class's one allowed door, or sets its env flag in test/ or .github/
  ci_path_classes.py --suites look        the *_test.gd suites that touch the class
  ci_path_classes.py --is-only look F...  exit 0 only when every F is in the class or under docs/
  ci_path_classes.py --pr-is-only look    the same for the files this PR changes (git diff HEAD^1 HEAD of the merge ref;
                                          any git problem or an empty diff exits 1 = not LOOK-only = the full run)
  ci_path_classes.py --lane look          the suites of the LOOK short run: the class suites, the suites that walk a whole
                                          source root, and CANARY
"""
import fnmatch
import os
import re
import subprocess
import sys

CLASSES = {
    "look": {
        "globs": [g.strip() for g in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ci_look_paths.txt"))
                  if g.strip() and not g.startswith("#")],
        "list": "tools/ci_look_paths.txt",
        "doors": [("scripts/main.gd", "BoardgenGreybox.attach_from_env("),
                  # test-only (plan step 27-pre P3, lead 26.11.): a rules e2e on a drawn board. Remove when the
                  # player-facing generate path (D-GEN) exists; the e2e then uses that path.
                  ("scripts/main.gd", "_board_look = BoardgenGreybox.attach(table, "),
                  # GEN-13 (lead 28.11.): the setup's board card asks whether the kit is cached through ONE main.gd static;
                  # no setup or menu file names the class.
                  ("scripts/main.gd", "return BoardgenKit.wait_state(holder, kit_theme)")],
        "env": "NML_BOARDGEN_SEED",
    },
}
# The LOOK short run also boots the real game once: a class file that does not compile or does not load breaks
# scripts/main.gd through its one door, and only a boot of scenes/main.tscn sees that. Any suite that boots it will
# do; tools/ci_look_lane_test.py keeps this one such a suite.
CANARY = "test/e2e/e2e_local_table_no_implicit_ai_test.gd"
# A suite that names a whole source root (res://scripts, res://scenes, ...) walks every file in it, so a class file can
# trip it without naming any class symbol: it runs in the short run too.
WALKS_A_ROOT = re.compile(r"[\"']res://(?:scripts|scenes|shaders|assets|materials)/?[\"']")
SCAN = ("scripts/", "scenes/", "shaders/", "materials/", "assets/", "tools/", "addons/", "test/", "project.godot")
SELF = ("tools/ci_path_classes.py", "tools/ci_path_classes_test.py", "tools/ci_look_lane_test.py", "tools/ci_dev_view_gate_test.py", "tools/ci_look_paths.txt", "tools/gdformat_clean.txt", "tools/gdlint_clean.txt")


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
    # A Markdown file is never loaded by the game: its name (README, LICENSES, ...) is no symbol another file can reach.
    own = [f for f in files if in_class(f, cls) and not f.endswith("_test.gd") and not f.endswith(".md")]
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
            comment = line.lstrip().startswith(("#", "//")) and not line.lstrip().startswith("#include")
            if f.startswith(SCAN) and sym.search(line) and not door and not comment:
                door_files = " / ".join(os.path.basename(p) for p, _ in spec["doors"])
                errors.append(f"{f}:{n}: {cls.upper()} class reaches the game outside {door_files}'s door "
                              f"(names {sym.search(line).group(1)}); go through the door, or if {f} is board-look work add its glob "
                              f"to {spec['list']} in the same PR")
            if spec["env"] in line and f.startswith(("test/", ".github/")):
                errors.append(f"{f}:{n}: {cls.upper()} class flag {spec['env']} set outside the class (test/ or .github/)")
    return errors


def suites(root, files, cls):
    sym = symbols(root, files, cls)
    return sorted(f for f in files if f.startswith("test/") and f.endswith("_test.gd") and sym.search(_text(root, f) or ""))


def walkers(root, files):
    return sorted(f for f in files if f.startswith("test/") and f.endswith("_test.gd") and WALKS_A_ROOT.search(_text(root, f) or ""))


def lane(root, files, cls):
    return sorted(set(suites(root, files, cls)) | set(walkers(root, files)) | {CANARY})


def pr_files(root):
    p = subprocess.run(["git", "diff", "-z", "--no-renames", "--name-only", "HEAD^1", "HEAD"], cwd=root, capture_output=True, text=True)
    return [f for f in p.stdout.split("\0") if f] if p.returncode == 0 else []


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
    if argv[:1] == ["--lane"]:
        print("\n".join(lane(root, files, argv[1])))
        return 0
    if argv[:1] == ["--pr-is-only"]:
        changed = pr_files(root)
        print(f"{len(changed)} changed file(s); LOOK-only: {is_only(changed, argv[1])}")
        return 0 if is_only(changed, argv[1]) else 1
    if argv[:1] == ["--is-only"]:
        return 0 if is_only(argv[2:], argv[1]) else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

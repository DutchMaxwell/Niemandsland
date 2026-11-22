"""The class cannot switch its own board on in every debug game: the debug + env decision is main.gd's, in front of the
door (LOOK short run, hole A). A LOOK-only PR that renames the flag goes red here and has to touch main.gd (a full run)."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_main_gd_decides_the_dev_view_before_the_door():
    env = re.search(r'const ENV_SEED := "(\w+)"', open(os.path.join(ROOT, "scripts/boardgen_greybox.gd"), encoding="utf-8").read()).group(1)
    main = open(os.path.join(ROOT, "scripts/main.gd"), encoding="utf-8").read().splitlines()
    door = next(i for i, line in enumerate(main) if "BoardgenGreybox.attach_from_env(" in line)
    gate = main[door - 1].strip()
    assert gate.startswith("if OS.is_debug_build() and") and f'OS.get_environment("{env}")' in gate and gate.endswith(":"), \
        f"main.gd must gate the door on debug build + {env}"
    assert main[door].startswith("\t\t"), "the door must sit inside that if"

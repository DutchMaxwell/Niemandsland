#!/usr/bin/env python3
"""Release guard: exit 1 unless a platform zip carries the Rust core library.

Usage:  python3 tools/check_release_zip.py ZIP linux|windows|macos   (the reason goes to stderr)
"""

import sys
import zipfile

CORE = {"linux": "libnml_core_godot.so", "windows": "nml_core_godot.dll",
        "macos": "Contents/Frameworks/libnml_core_godot.dylib"}


def main(argv):
    if len(argv) != 3 or argv[2] not in CORE:
        print("usage: check_release_zip.py ZIP linux|windows|macos", file=sys.stderr)
        return 1
    path, want = argv[1], CORE[argv[2]]
    try:
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
    except (OSError, zipfile.BadZipFile) as err:
        print("FAIL: cannot read %s as a zip: %s" % (path, err), file=sys.stderr)
        return 1
    if not any(n == want or n.endswith("/" + want) for n in names):
        print("FAIL: %s has no %s (%d entries); a release without the Rust core must not ship"
              % (path, want, len(names)), file=sys.stderr)
        return 1
    print("OK: %s carries %s" % (path, want))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

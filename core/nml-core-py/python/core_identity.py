"""Compatibility check shared by record readers; every mismatch is counted."""
import os
import sys

import nml_core


def add_core_argument(parser):
    parser.add_argument("--require-same-core", action="store_true",
                        help="refuse missing/different build stamps (exit 3); also NML_REQUIRE_SAME_CORE=1")
    parser.add_argument("--allow-unknown-core", action="store_true",
                        help="deliberate local run: downgrade an unverifiable running stamp (BUILD_COMMIT=unknown) "
                             "from refusal to warning; also NML_ALLOW_UNKNOWN_CORE=1")


class CoreIdentityCheck:
    def __init__(self, require_same_core=False, allow_unknown_core=False):
        self.required = require_same_core or os.environ.get("NML_REQUIRE_SAME_CORE") == "1"
        self.running = getattr(nml_core, "BUILD_COMMIT", "unknown")
        self.unknown_ok = allow_unknown_core or os.environ.get("NML_ALLOW_UNKNOWN_CORE") == "1"
        self.mismatches = 0

    def check(self, record, path):
        recorded = ((record.get("prescreen") or {}).get("core_commit")
                    or record.get("core_commit") or "unknown")
        if recorded == self.running and recorded != "unknown":
            return
        self.mismatches += 1
        message = "core identity record=%s recorded=%s running=%s" % (path, recorded, self.running)
        if self.running == "unknown":
            # An unverifiable identity is worse than a mismatched one: it is
            # silent. Refuse by default; the opt-out names what it disabled.
            if not self.unknown_ok:
                print("REFUSED " + message
                      + " (running core identity is unverifiable; deliberate local run: "
                        "--allow-unknown-core / NML_ALLOW_UNKNOWN_CORE=1 disables this refusal)",
                      file=sys.stderr)
                raise SystemExit(3)
            print("WARN (refusal disabled by --allow-unknown-core / NML_ALLOW_UNKNOWN_CORE=1) "
                  + message, file=sys.stderr)
        elif self.required:
            print("REFUSED " + message, file=sys.stderr)
            raise SystemExit(3)
        elif self.mismatches == 1:
            print("WARN " + message, file=sys.stderr)
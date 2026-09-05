"""Compatibility check shared by record readers; one warning per invocation."""
import os
import sys

import nml_core


def add_core_argument(parser):
    parser.add_argument("--require-same-core", action="store_true",
                        help="refuse missing/different build stamps (exit 3); also NML_REQUIRE_SAME_CORE=1")


class CoreIdentityCheck:
    def __init__(self, require_same_core=False):
        self.required = require_same_core or os.environ.get("NML_REQUIRE_SAME_CORE") == "1"
        self.running = getattr(nml_core, "BUILD_COMMIT", "unknown")
        self.warned = False

    def check(self, record, path):
        recorded = ((record.get("prescreen") or {}).get("core_commit")
                    or record.get("core_commit") or "unknown")
        if recorded == self.running and recorded != "unknown":
            return
        message = "core identity record=%s recorded=%s running=%s" % (path, recorded, self.running)
        if self.required:
            print("REFUSED " + message, file=sys.stderr)
            raise SystemExit(3)
        if not self.warned:
            print("WARN " + message, file=sys.stderr)
            self.warned = True

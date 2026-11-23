#!/usr/bin/env bash
# Format and lint gate for the files that are already clean.
#
# Why an allowlist: the repo has ~1,550 hand-written GDScript files and only a small part of them
# pass the formatter today. A "changed files" gate would reformat a whole legacy file on its first
# touch (scripts/main.gd alone is ~26k lines) and produce unreviewable diffs. So the gate checks
# only the files named in tools/gdformat_clean.txt and tools/gdlint_clean.txt; those lists only
# grow, and a new or edited file joins them by being formatted first.
#
# rustfmt is deferred: on the commit that added this gate, `cargo fmt --all --check` in core/
# reported 606 files that would change. Re-enable it by setting RUSTFMT_CLEAN=1 once core/ is
# formatted (the job then needs a Rust toolchain).
#
# Usage: bash tools/format_gate.sh
# Tools: gdtoolkit 4.5.0 (`pip install gdtoolkit==4.5.0`); GDFORMAT / GDLINT override the binaries.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

GDFORMAT="${GDFORMAT:-gdformat}"
GDLINT="${GDLINT:-gdlint}"
RUSTFMT_CLEAN=0
RUSTFMT_DIFF_FILES=606

fail=0

check_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: '$tool' not found - install it with: pip install gdtoolkit==4.5.0" >&2
        exit 2
    fi
}

# Reads an allowlist, drops blanks and comments, and reports entries that no longer exist.
read_list() {
    local list="$1"
    local path missing=()
    list_files=()
    while IFS= read -r path; do
        case "$path" in
            ''|'#'*) continue ;;
        esac
        if [[ -f "$path" ]]; then
            list_files+=("$path")
        else
            missing+=("$path")
        fi
    done < "$list"
    if (( ${#missing[@]} > 0 )); then
        echo "error: $list names file(s) that do not exist - remove them from the list:" >&2
        printf '  %s\n' "${missing[@]}" >&2
        fail=1
        list_files=()
    fi
}

run_listed() {
    local label="$1" tool="$2" flags="$3" list="$4"
    read_list "$list"
    if (( ${#list_files[@]} == 0 )); then
        return
    fi
    local output status
    # shellcheck disable=SC2086 # flags is a fixed flag string, intentionally split
    output=$("$tool" $flags "${list_files[@]}" 2>&1)
    status=$?
    if (( status != 0 )); then
        echo "$output"
        echo "FAIL: $label on ${#list_files[@]} listed files ($list)" >&2
        fail=1
    else
        echo "ok: $label - ${#list_files[@]} listed files clean ($list)"
    fi
}

check_tool "$GDFORMAT"
check_tool "$GDLINT"

echo "gdformat: $("$GDFORMAT" --version 2>&1)"
echo "gdlint: $("$GDLINT" --version 2>&1)"

run_listed "gdformat --check" "$GDFORMAT" "--check" tools/gdformat_clean.txt
run_listed "gdlint" "$GDLINT" "" tools/gdlint_clean.txt

if (( RUSTFMT_CLEAN )); then
    if ! command -v cargo >/dev/null 2>&1; then
        echo "error: RUSTFMT_CLEAN=1 but 'cargo' is not on PATH" >&2
        fail=1
    elif ( cd core && cargo fmt --all --check ); then
        echo "ok: cargo fmt --all --check"
    else
        echo "FAIL: cargo fmt --all --check (core/)" >&2
        fail=1
    fi
else
    echo "deferred: cargo fmt --all --check skipped - $RUSTFMT_DIFF_FILES files in core/ would change on main"
fi

if (( fail != 0 )); then
    echo "format gate: FAILED" >&2
    exit 1
fi
echo "format gate: OK"

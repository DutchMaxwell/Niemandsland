"""
Reprocess existing GLB miniatures with the optimization pipeline.
================================================================

Geht alle GLBs unter assets/miniatures/ durch und wendet die Optimierung
(Mesh-Decimation + Texture-Resize) an. Originale werden vor dem Ersetzen
nach *.glb.orig-backup gesichert (idempotent: wenn das Backup schon
existiert, wird es nicht ueberschrieben).

Skipped wird:
  - GLBs, die bereits unter SKIP_BELOW_BYTES liegen (vermutlich schon optimiert)
  - GLBs, fuer die schon ein .orig-backup existiert UND der GLB klein ist
    (idempotent: zweite Ausfuehrung tut nichts)

Usage:
    python reprocess_existing.py                    # alle Fraktionen
    python reprocess_existing.py alien_hives        # nur eine Fraktion
    python reprocess_existing.py --dry-run          # nur listen, nichts machen
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from glb_optimizer import optimize_glb


PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
MINIATURES_DIR = PROJECT_ROOT / "assets" / "miniatures"

# GLBs, die bereits unter dieser Schwelle liegen, gelten als optimiert und
# werden uebersprungen (Optimierung produziert typisch 1-3 MB).
SKIP_BELOW_BYTES = 5 * 1024 * 1024


def collect_glbs(faction_filter: str | None) -> list[Path]:
    """Sammelt alle GLB-Dateien unterhalb assets/miniatures/<faction>/glb/."""
    if not MINIATURES_DIR.is_dir():
        print(f"ERROR: {MINIATURES_DIR} existiert nicht", file=sys.stderr)
        return []

    glbs: list[Path] = []
    for faction_dir in sorted(MINIATURES_DIR.iterdir()):
        if not faction_dir.is_dir():
            continue
        if faction_filter and faction_dir.name != faction_filter:
            continue
        glb_dir = faction_dir / "glb"
        if not glb_dir.is_dir():
            continue
        glbs.extend(sorted(glb_dir.glob("*.glb")))
    return glbs


def process(glb: Path, dry_run: bool) -> tuple[bool, str]:
    """Optimiert eine einzelne GLB. Returns (changed, message)."""
    size = glb.stat().st_size
    backup = glb.with_suffix(glb.suffix + ".orig-backup")

    if size < SKIP_BELOW_BYTES and backup.exists():
        return False, f"skip (already optimized, backup exists): {size/1024/1024:.2f} MB"
    if size < SKIP_BELOW_BYTES:
        return False, f"skip (already small, no backup needed): {size/1024/1024:.2f} MB"

    if dry_run:
        return False, f"would optimize: {size/1024/1024:.2f} MB"

    if not backup.exists():
        backup.write_bytes(glb.read_bytes())

    res = optimize_glb(backup, glb)
    if not res.success:
        # Restore original to avoid leaving a half-broken file
        glb.write_bytes(backup.read_bytes())
        return False, f"FAILED: {res.error}"

    return True, (
        f"{res.input_bytes/1024/1024:.2f} MB -> {res.output_bytes/1024/1024:.2f} MB "
        f"(-{res.reduction_percent:.0f}%)"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("faction", nargs="?", help="Optional: nur eine Fraktion verarbeiten")
    parser.add_argument("--dry-run", action="store_true", help="Nur listen, nichts modifizieren")
    args = parser.parse_args()

    glbs = collect_glbs(args.faction)
    if not glbs:
        print("Keine GLBs gefunden.")
        return 1

    print(f"Gefunden: {len(glbs)} GLB-Dateien" + (" (dry run)" if args.dry_run else ""))
    print()

    total_in = 0
    total_out = 0
    changed_count = 0
    failed_count = 0

    for i, glb in enumerate(glbs, 1):
        rel = glb.relative_to(PROJECT_ROOT)
        size_in = glb.stat().st_size
        total_in += size_in

        changed, msg = process(glb, args.dry_run)
        size_out = glb.stat().st_size
        total_out += size_out

        marker = "OK " if changed else "-- " if not msg.startswith("FAILED") else "ERR"
        print(f"[{i:3d}/{len(glbs)}] {marker} {rel}  {msg}")

        if changed:
            changed_count += 1
        if msg.startswith("FAILED"):
            failed_count += 1

    print()
    print(f"Verarbeitet:   {changed_count} geaendert, {failed_count} Fehler, {len(glbs)-changed_count-failed_count} uebersprungen")
    print(f"Gesamt-Groesse: {total_in/1024/1024:.1f} MB -> {total_out/1024/1024:.1f} MB", end="")
    if total_in > 0:
        print(f" ({(1.0 - total_out/total_in)*100:.1f}% Reduktion)")
    else:
        print()

    return 0 if failed_count == 0 else 2


if __name__ == "__main__":
    sys.exit(main())

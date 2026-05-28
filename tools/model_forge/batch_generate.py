"""
Bulk Generation CLI fuer Model Forge
=====================================

Headless-Pipeline, die fuer eine oder mehrere Fraktionen alle Mini-Bilder
generiert, qualitaetsprueft (inkl. GW-IP) und als optimierte GLBs nach
assets/miniatures/{faction}/glb/ exportiert.

Workflow pro Fraktion:
    1. YAML laden -> DesignLanguage + PromptEngine
    2. Hero-Mini auswaehlen (heuristic oder YAML-override)
    3. Falls noch kein _reference.webp: Hero generieren mit Quality-Gate,
       bei PASS als Reference persistieren
    4. Fuer jede andere Unit:
       - Prompt generieren (inkl. IP-Compliance-Block)
       - Image generieren mit Reference-Pinning
       - Quality-Gate (technisch + IP)
       - Re-Roll bis max-attempts bei FAIL
       - TRELLIS 3D-Konvertierung
       - GLB-Optimierung (Mesh-Decimation + Texture-Resize)
       - Export nach assets/miniatures/{faction}/glb/{NN}_{Name}.glb

Resume-Logic: pro Fraktion eine Session unter state/, die bereits erfolgreich
verarbeitete Units skippt.

Usage:
    python batch_generate.py --faction alien_hives
    python batch_generate.py --all
    python batch_generate.py --faction alien_hives --max-attempts 5 --skip-trellis
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from glb_optimizer import optimize_glb
from hero_workflow import (
    UnitClass,
    class_reference_image_path,
    classify_unit,
    has_class_reference_image,
    has_reference_image,
    reference_image_path,
    select_class_anchor,
    select_hero_unit,
    store_class_reference_image,
    store_reference_image,
)


# Klassen, fuer die wir Anchor-Referenzen anlegen koennen. INFANTRY laeuft
# weiterhin ueber den Hero-Workflow.
NON_INFANTRY_CLASSES: tuple[UnitClass, ...] = (
    UnitClass.WALKER,
    UnitClass.VEHICLE,
    UnitClass.AIRCRAFT,
    UnitClass.TITAN,
)
from image_generator import ImageGenerator, ImageModel
from pipeline_state import PipelineSession, UnitStatus
from prompt_engine import PromptEngine, load_design_language
from quality_gate import QualityGate, QualityResult
from trellis_bridge import convert_image_to_glb


# =============================================================================
# KONSTANTEN
# =============================================================================

THIS_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = THIS_DIR.parent.parent
DESIGN_LANG_DIR: Path = THIS_DIR / "design_languages"
SESSIONS_DIR: Path = THIS_DIR / "state"
MINIATURES_DIR: Path = PROJECT_ROOT / "assets" / "miniatures"

GEMINI_KEY_FILE: Path = THIS_DIR / ".gemini_key"
HF_TOKEN_FILE: Path = THIS_DIR / ".hf_token"
TRELLIS_SPACE_FILE: Path = THIS_DIR / ".trellis_space"

DEFAULT_MAX_ATTEMPTS: int = 3
HF_QUOTA_BACKOFF_SECONDS: int = 300  # 5 Min bei vermutetem Quota-Limit

logger: logging.Logger = logging.getLogger("batch_generate")


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class FactionStats:
    """Aggregierte Statistik pro Fraktion."""

    faction: str
    total_units: int = 0
    skipped: int = 0
    generated: int = 0
    quality_failed: int = 0
    ip_flagged: int = 0
    glb_failed: int = 0
    errors: list[str] = field(default_factory=list)


# =============================================================================
# HILFSFUNKTIONEN: SECRETS LADEN
# =============================================================================

def _read_secret(path: Path, label: str) -> str | None:
    """Liest API-Key/Token aus Datei. Gibt None und loggt wenn fehlend."""
    if not path.exists():
        logger.warning("%s nicht gefunden: %s", label, path)
        return None
    return path.read_text().strip() or None


# =============================================================================
# HAUPTLOGIK
# =============================================================================

def process_faction(
    faction: str,
    *,
    max_attempts: int,
    skip_trellis: bool,
    image_gen: ImageGenerator,
    quality_gate: QualityGate | None,
    hf_token: str | None,
    trellis_space: str | None,
) -> FactionStats:
    """
    Verarbeitet eine Fraktion komplett.

    Args:
        faction: Faction-Folder-Name (z.B. "alien_hives")
        max_attempts: Max. Re-Rolls pro Unit bei Quality-Gate-Fail
        skip_trellis: Nur Bilder, kein 3D (fuer Tests)
        image_gen: ImageGenerator-Instanz
        quality_gate: Optionales QualityGate (None = kein Check)
        hf_token: HF-Token fuer TRELLIS
        trellis_space: HF-Space-ID fuer TRELLIS

    Returns:
        FactionStats mit Zaehlern.
    """
    stats = FactionStats(faction=faction)
    yaml_path = DESIGN_LANG_DIR / f"{faction}.yaml"

    if not yaml_path.exists():
        stats.errors.append(f"YAML nicht gefunden: {yaml_path}")
        return stats

    dl = load_design_language(yaml_path)
    engine = PromptEngine(dl)
    stats.total_units = len(dl.unit_overrides)

    # Session anlegen oder fortsetzen
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    session = _get_or_create_session(faction, dl)

    # Hero-Reference sicherstellen
    if not has_reference_image(PROJECT_ROOT, faction):
        if not _generate_hero_reference(
            faction, dl, engine, image_gen, quality_gate, max_attempts, stats,
        ):
            stats.errors.append("Hero-Reference konnte nicht erstellt werden — Fraktion abgebrochen")
            return stats

    ref_path: Path = reference_image_path(PROJECT_ROOT, faction)
    glb_dir: Path = MINIATURES_DIR / faction / "glb"
    glb_dir.mkdir(parents=True, exist_ok=True)

    # Hero-Unit ermitteln, damit wir sie nicht doppelt verarbeiten
    hero_sel = select_hero_unit(dl)
    hero_unit_key: str = hero_sel.unit_key if hero_sel else ""

    # Class-Anchors: pro Non-Infantry-Klasse (Walker/Vehicle/Aircraft/Titan)
    # eine eigene Reference erzeugen, falls die Fraktion Units dieser Klasse
    # enthaelt und noch keine Reference gespeichert ist.
    class_anchor_keys: dict[UnitClass, str] = {}
    class_ref_paths: dict[UnitClass, Path] = {}
    for cls in NON_INFANTRY_CLASSES:
        sel = select_class_anchor(dl, cls)
        if sel is None:
            continue
        class_anchor_keys[cls] = sel.unit_key
        if not has_class_reference_image(PROJECT_ROOT, faction, cls):
            if not _generate_class_reference(
                faction, dl, engine, image_gen, quality_gate, max_attempts, stats, cls,
            ):
                stats.errors.append(
                    f"{cls.value.title()}-Anchor-Reference konnte nicht erstellt werden — "
                    f"{cls.value}-Units werden mit Hero-Reference generiert (Stil-Bias moeglich)"
                )
        if has_class_reference_image(PROJECT_ROOT, faction, cls):
            class_ref_paths[cls] = class_reference_image_path(PROJECT_ROOT, faction, cls)

    # Alle Units verarbeiten
    for index, (unit_key, override) in enumerate(dl.unit_overrides.items(), start=1):
        unit_name = override.get("name") if isinstance(override, dict) else ""
        unit_name = unit_name or unit_key.replace("_", " ").title()

        target_glb = glb_dir / f"{index:02d}_{unit_name}.glb"
        if target_glb.exists() and target_glb.stat().st_size > 0:
            stats.skipped += 1
            logger.info("[%s] %s -> skip (GLB existiert: %s)",
                        faction, unit_name, target_glb.name)
            continue

        unit_state = session.add_unit(unit_key, unit_name)

        # Prompt erzeugen (Hero-Reference ueberschreibt nicht; der Prompt ist
        # gleich, nur die Image-Generation bekommt das Reference-Bild)
        try:
            prompt = _build_prompt_for(engine, unit_key, override)
        except Exception as exc:
            stats.errors.append(f"Prompt-Generierung fehlgeschlagen ({unit_name}): {exc}")
            continue

        # Image-Generation mit Quality-Gate-Loop
        unit_class: UnitClass = classify_unit(override)
        is_hero = (unit_key == hero_unit_key)
        is_class_anchor = (
            unit_class in class_anchor_keys
            and class_anchor_keys[unit_class] == unit_key
        )

        # Hero / Class-Anchor ueberspringen — wurden bereits als Reference
        # erzeugt; die Reference dient als finales Bild zum 3D-Konvertieren
        if is_hero:
            image_for_3d = ref_path
        elif is_class_anchor and unit_class in class_ref_paths:
            image_for_3d = class_ref_paths[unit_class]
        else:
            # Reference dispatchen: Klassen-Reference wenn vorhanden,
            # sonst Hero-Reference (Fallback).
            effective_ref: Path | None = class_ref_paths.get(unit_class, ref_path)

            image_path = _images_dir(session) / f"{unit_key}.png"
            success = _generate_with_quality_loop(
                prompt=prompt,
                output_path=image_path,
                unit_name=unit_name,
                faction_name=dl.faction_name,
                unit_description=str(override.get("extra_details", "")) if isinstance(override, dict) else "",
                image_gen=image_gen,
                quality_gate=quality_gate,
                reference_image_path=effective_ref,
                max_attempts=max_attempts,
                stats=stats,
            )
            if not success:
                continue
            image_for_3d = image_path

        unit_state.image_path = str(image_for_3d)
        unit_state.status = UnitStatus.IMAGE_APPROVED
        session.save()

        if skip_trellis:
            stats.generated += 1
            continue

        # TRELLIS 3D
        glb_dir_session = _glb_dir(session)
        glb = convert_image_to_glb(
            image_for_3d,
            glb_dir_session,
            hf_token=hf_token,
            preprocess=True,
            space_id=trellis_space,
            unit_class=unit_class.value if hasattr(unit_class, "value") else str(unit_class),
        )
        if glb is None:
            stats.glb_failed += 1
            stats.errors.append(f"TRELLIS-Konvertierung fehlgeschlagen: {unit_name}")
            continue

        # Optimieren + ins finale Verzeichnis
        opt_result = optimize_glb(glb, target_glb)
        if not opt_result.success:
            # Fallback: unoptimiertes GLB rueberkopieren
            target_glb.write_bytes(glb.read_bytes())
            stats.errors.append(
                f"GLB-Optimierung fehlgeschlagen fuer {unit_name}: {opt_result.error} (Original verwendet)"
            )

        unit_state.glb_path = str(target_glb)
        unit_state.status = UnitStatus.EXPORTED
        session.save()
        stats.generated += 1
        logger.info("[%s] %s -> %s (%s)",
                    faction, unit_name, target_glb.name,
                    f"{opt_result.output_bytes/1024/1024:.2f} MB" if opt_result.success else "no opt")

    return stats


def _generate_hero_reference(
    faction: str,
    dl,
    engine: PromptEngine,
    image_gen: ImageGenerator,
    quality_gate: QualityGate | None,
    max_attempts: int,
    stats: FactionStats,
) -> bool:
    """Erzeugt das Hero-Reference-Image fuer eine Fraktion."""
    hero_sel = select_hero_unit(dl)
    if hero_sel is None:
        stats.errors.append("Keine Hero-Unit fuer Fraktion ermittelbar")
        return False

    logger.info(
        "[%s] Hero-Reference: %s (%s)",
        faction, hero_sel.unit_name, hero_sel.reason,
    )

    override = dl.unit_overrides.get(hero_sel.unit_key, {})
    try:
        prompt = _build_prompt_for(engine, hero_sel.unit_key, override)
    except Exception as exc:
        stats.errors.append(f"Hero-Prompt-Generierung fehlgeschlagen: {exc}")
        return False

    tmp_image = MINIATURES_DIR / faction / "_hero_tmp.png"
    tmp_image.parent.mkdir(parents=True, exist_ok=True)

    success = _generate_with_quality_loop(
        prompt=prompt,
        output_path=tmp_image,
        unit_name=hero_sel.unit_name,
        faction_name=dl.faction_name,
        unit_description=str(override.get("extra_details", "")) if isinstance(override, dict) else "",
        image_gen=image_gen,
        quality_gate=quality_gate,
        reference_image_path=None,  # Hero hat keine Reference
        max_attempts=max_attempts,
        stats=stats,
    )

    if not success:
        return False

    store_reference_image(tmp_image, PROJECT_ROOT, faction)
    tmp_image.unlink(missing_ok=True)
    logger.info("[%s] Hero-Reference gespeichert: %s",
                faction, reference_image_path(PROJECT_ROOT, faction))
    return True


def _generate_class_reference(
    faction: str,
    dl,
    engine: PromptEngine,
    image_gen: ImageGenerator,
    quality_gate: QualityGate | None,
    max_attempts: int,
    stats: FactionStats,
    target_class: UnitClass,
) -> bool:
    """Erzeugt das Anchor-Reference-Image einer Non-Infantry-Klasse.

    Analog zum Hero-Reference, aber fuer WALKER/VEHICLE/AIRCRAFT/TITAN. Wird
    ohne Reference generiert, damit die Body-Shape nicht vom Infanterie-Hero
    beeinflusst wird (Battlesuit-Bias-Problem aus Galerie-Review 2026-05-07).
    """
    sel = select_class_anchor(dl, target_class)
    if sel is None:
        return False

    logger.info(
        "[%s] %s-Anchor: %s (%s)",
        faction, target_class.value.title(), sel.unit_name, sel.reason,
    )

    override = dl.unit_overrides.get(sel.unit_key, {})
    try:
        prompt = _build_prompt_for(engine, sel.unit_key, override)
    except Exception as exc:
        stats.errors.append(
            f"{target_class.value.title()}-Anchor-Prompt-Generierung fehlgeschlagen: {exc}"
        )
        return False

    tmp_image = MINIATURES_DIR / faction / f"_{target_class.value}_anchor_tmp.png"
    tmp_image.parent.mkdir(parents=True, exist_ok=True)

    success = _generate_with_quality_loop(
        prompt=prompt,
        output_path=tmp_image,
        unit_name=sel.unit_name,
        faction_name=dl.faction_name,
        unit_description=str(override.get("extra_details", "")) if isinstance(override, dict) else "",
        image_gen=image_gen,
        quality_gate=quality_gate,
        reference_image_path=None,  # ohne Reference — sonst Stil-Bias vom Hero
        max_attempts=max_attempts,
        stats=stats,
    )

    if not success:
        tmp_image.unlink(missing_ok=True)
        return False

    store_class_reference_image(tmp_image, PROJECT_ROOT, faction, target_class)
    tmp_image.unlink(missing_ok=True)
    logger.info(
        "[%s] %s-Anchor-Reference gespeichert: %s",
        faction,
        target_class.value.title(),
        class_reference_image_path(PROJECT_ROOT, faction, target_class),
    )
    return True


def _generate_with_quality_loop(
    *,
    prompt: str,
    output_path: Path,
    unit_name: str,
    faction_name: str,
    unit_description: str,
    image_gen: ImageGenerator,
    quality_gate: QualityGate | None,
    reference_image_path: Path | None,
    max_attempts: int,
    stats: FactionStats,
) -> bool:
    """
    Generiert ein Bild mit Re-Roll-Loop falls Quality-Gate FAIL meldet.

    Returns True bei Erfolg, False wenn alle Versuche fehlgeschlagen sind.
    """
    last_qresult: QualityResult | None = None
    for attempt in range(1, max_attempts + 1):
        gen_result = image_gen.generate(
            prompt=prompt,
            output_path=output_path,
            reference_image_path=reference_image_path,
        )
        if not gen_result.success:
            stats.errors.append(
                f"{unit_name} Versuch {attempt}: image-gen fehlgeschlagen: {gen_result.error}"
            )
            # Bei vermutetem Quota-Limit kurze Pause
            if "quota" in gen_result.error.lower() or "rate" in gen_result.error.lower():
                logger.info("Quota-Hinweis erkannt, warte %ds...", HF_QUOTA_BACKOFF_SECONDS)
                time.sleep(HF_QUOTA_BACKOFF_SECONDS)
            continue

        if quality_gate is None:
            return True

        last_qresult = quality_gate.check_image(
            output_path,
            unit_name=unit_name,
            faction_name=faction_name,
            unit_description=unit_description,
        )
        if last_qresult.passed:
            return True

        # Logging: was war kaputt?
        assessment = last_qresult.overall_assessment or last_qresult.error or "(ohne Begruendung)"
        msg = (
            f"[{faction_name}] {unit_name} Versuch {attempt}: Quality-Gate FAIL — "
            f"technical={last_qresult.technical_issues} ip={last_qresult.ip_concerns} "
            f"assessment={assessment!r}"
        )
        logger.warning(msg)
        if last_qresult.has_ip_concern:
            stats.ip_flagged += 1
        else:
            stats.quality_failed += 1

    # Alle Versuche fehlgeschlagen
    if last_qresult is not None:
        stats.errors.append(
            f"{unit_name}: {max_attempts} Versuche, alle FAIL. Letzte Bewertung: {last_qresult.overall_assessment}"
        )
    return False


def _build_prompt_for(engine: PromptEngine, unit_key: str, override: object) -> str:
    """Baut den Prompt fuer eine Unit aus deren game_stats."""
    if not isinstance(override, dict):
        raise ValueError(f"Unit-Override nicht dict: {unit_key}")
    stats = override.get("game_stats", {})
    weapons_raw = stats.get("weapons", []) if isinstance(stats, dict) else []
    rules_raw = stats.get("rules", []) if isinstance(stats, dict) else []
    size_raw = stats.get("size", 1) if isinstance(stats, dict) else 1
    base_raw = stats.get("base", 32) if isinstance(stats, dict) else 32

    # OPRWeapon-aehnliche Objekte aus stats konstruieren
    from opr_client import OPRWeapon

    weapons = []
    if isinstance(weapons_raw, list):
        for w in weapons_raw:
            if not isinstance(w, dict):
                continue
            weapons.append(OPRWeapon(
                name=w.get("name", ""),
                range_value=int(w.get("range", 0)),
                attacks=int(w.get("attacks", 0)),
                special_rules=list(w.get("rules", [])) if isinstance(w.get("rules"), list) else [],
            ))

    rules = [str(r) for r in rules_raw] if isinstance(rules_raw, list) else []
    base_size = _base_to_int(base_raw)
    unit_name = unit_key.replace("_", " ").title()

    return engine.generate_prompt(
        unit_name=unit_name,
        unit_key=unit_key,
        weapons=weapons,
        special_rules=rules,
        size=int(size_raw),
        base_size=base_size,
    )


def _base_to_int(base: object) -> int:
    """Konvertiert base-Field zu int (max-Dimension bei oval)."""
    if isinstance(base, int):
        return base
    if isinstance(base, str):
        if "x" in base.lower():
            try:
                p = base.lower().split("x")
                return max(int(p[0]), int(p[1]))
            except (ValueError, IndexError):
                return 32
        try:
            return int(base)
        except ValueError:
            return 32
    return 32


# =============================================================================
# SESSION-MANAGEMENT
# =============================================================================

def _get_or_create_session(faction: str, dl) -> PipelineSession:
    """Findet die juengste Session fuer eine Fraktion oder erstellt eine neue."""
    existing = sorted(SESSIONS_DIR.glob(f"{faction}_*"), reverse=True)
    if existing:
        try:
            return PipelineSession.load(existing[0])
        except Exception as exc:
            logger.warning("Session %s nicht ladbar (%s) - erstelle neue", existing[0], exc)
    return PipelineSession.create(SESSIONS_DIR, dl.faction_name, faction)


def _images_dir(session: PipelineSession) -> Path:
    """Bilder-Verzeichnis der aktuellen Session."""
    return session._session_dir / "images"  # type: ignore[attr-defined]


def _glb_dir(session: PipelineSession) -> Path:
    """GLB-Verzeichnis der aktuellen Session."""
    return session._session_dir / "glb"  # type: ignore[attr-defined]


# =============================================================================
# CLI
# =============================================================================

def _list_factions() -> list[str]:
    """Listet alle Fraktionen mit YAML auf."""
    return sorted(
        p.stem for p in DESIGN_LANG_DIR.glob("*.yaml")
        if p.stem != "_template"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Bulk-Generierung von Mini-GLBs.")
    parser.add_argument("--faction", help="Eine Fraktion verarbeiten (z.B. alien_hives)")
    parser.add_argument("--all", action="store_true", help="Alle 38 Fraktionen verarbeiten")
    parser.add_argument("--max-attempts", type=int, default=DEFAULT_MAX_ATTEMPTS,
                        help=f"Max. Re-Rolls pro Unit (Default {DEFAULT_MAX_ATTEMPTS})")
    parser.add_argument("--skip-trellis", action="store_true",
                        help="Nur Bilder generieren, kein 3D (fuer Quality-Tests)")
    parser.add_argument("--no-quality-gate", action="store_true",
                        help="Quality-Gate deaktivieren (Vision-LLM nicht aufrufen)")
    parser.add_argument("--list", action="store_true",
                        help="Alle verfuegbaren Fraktionen listen und beenden")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    if args.list:
        for f in _list_factions():
            print(f)
        return 0

    if not args.faction and not args.all:
        parser.error("--faction X oder --all erforderlich")

    factions = _list_factions() if args.all else [args.faction]
    invalid = [f for f in factions if not (DESIGN_LANG_DIR / f"{f}.yaml").exists()]
    if invalid:
        logger.error("Unbekannte Fraktionen: %s", invalid)
        return 2

    # Secrets laden
    gemini_key = _read_secret(GEMINI_KEY_FILE, "Gemini-Key")
    if not gemini_key:
        logger.error("Gemini-Key fehlt unter %s", GEMINI_KEY_FILE)
        return 3
    hf_token = _read_secret(HF_TOKEN_FILE, "HF-Token")
    trellis_space_raw = _read_secret(TRELLIS_SPACE_FILE, "TRELLIS-Space")
    trellis_space = trellis_space_raw if trellis_space_raw else None

    image_gen = ImageGenerator(
        model=ImageModel.NANO_BANANA,
        gemini_api_key=gemini_key,
    )
    quality_gate: QualityGate | None = None
    if not args.no_quality_gate:
        quality_gate = QualityGate(gemini_api_key=gemini_key)

    all_stats: list[FactionStats] = []
    for faction in factions:
        logger.info("=" * 60)
        logger.info("FRAKTION: %s", faction)
        logger.info("=" * 60)
        stats = process_faction(
            faction=faction,
            max_attempts=args.max_attempts,
            skip_trellis=args.skip_trellis,
            image_gen=image_gen,
            quality_gate=quality_gate,
            hf_token=hf_token,
            trellis_space=trellis_space,
        )
        all_stats.append(stats)
        logger.info(
            "[%s] total=%d skipped=%d generated=%d quality_fail=%d ip_flag=%d glb_fail=%d",
            stats.faction, stats.total_units, stats.skipped,
            stats.generated, stats.quality_failed, stats.ip_flagged,
            stats.glb_failed,
        )

    # Gesamt-Bericht
    print()
    print("=" * 80)
    print(f"{'Faction':<28} {'Total':>6} {'Done':>6} {'Skip':>6} {'Q-Fail':>7} {'IP':>4} {'GLB-Fail':>9}")
    print("-" * 80)
    for s in all_stats:
        print(f"{s.faction:<28} {s.total_units:>6} {s.generated:>6} {s.skipped:>6} "
              f"{s.quality_failed:>7} {s.ip_flagged:>4} {s.glb_failed:>9}")
    print("=" * 80)
    total_errors = sum(len(s.errors) for s in all_stats)
    if total_errors:
        print(f"\n{total_errors} Fehler insgesamt. Details siehe Log oder ./state/{{faction}}_*/session.json")
    return 0 if total_errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

"""Schlanke Flask Review-UI fuer 2D-Image- und 3D-GLB-Approval.

Workflow:
    1. batch_generate.py erzeugt Bilder pro Faction (CLI).
    2. Diese App: User reviewed jede Image (A/R) im Browser.
    3. Approved Images werden via _convert_approved-CLI/Knopf zu GLB.
    4. Diese App: User reviewed jedes GLB (A/R).
    5. Export-CLI kopiert nur GLB_APPROVED ins Niemandsland-Repo.

Start:
    PYTHONPATH=../../assets/3d_pipeline:. venv/bin/python review_app.py
    -> http://localhost:5070

Port 5061 ist im Browser auf der Blockliste (SIP-TLS), deshalb 5070.
"""

from __future__ import annotations

import logging
import sys
import threading
import traceback
from pathlib import Path
from typing import Any

from flask import Flask, abort, jsonify, render_template, request, send_file

PROJECT_ROOT: Path = Path(__file__).resolve().parents[2]
TOOLS_DIR: Path = Path(__file__).resolve().parent
sys.path.insert(0, str(PROJECT_ROOT / "assets" / "3d_pipeline"))
sys.path.insert(0, str(TOOLS_DIR))

from pipeline_state import PipelineSession, UnitState, UnitStatus  # noqa: E402
from trellis_bridge import convert_batch  # noqa: E402
from hero_workflow import (  # noqa: E402
    classify_unit,
    class_reference_image_path,
    has_class_reference_image,
)
from prompt_engine import (  # noqa: E402
    DesignLanguage,
    PromptEngine,
    create_army_from_design_language,
    load_design_language,
)
from exporter import export_army  # noqa: E402
from image_generator import ImageGenerator, ImageModel  # noqa: E402
from batch_generate import _build_prompt_for  # noqa: E402

STATE_DIR: Path = TOOLS_DIR / "state"
DESIGN_LANGUAGES_DIR: Path = TOOLS_DIR / "design_languages"
HF_TOKEN_FILE: Path = TOOLS_DIR / ".hf_token"
TRELLIS_SPACE_FILE: Path = TOOLS_DIR / ".trellis_space"
GEMINI_KEY_FILE: Path = TOOLS_DIR / ".gemini_key"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger(__name__)

app = Flask(
    __name__,
    template_folder=str(TOOLS_DIR / "templates"),
    static_folder=str(TOOLS_DIR / "static"),
    static_url_path="/static",
)


# =============================================================================
# JOB-TRACKING (Background-Threads pro Session)
# =============================================================================

# Pro Session ein Job-Status-Eintrag:
#   { "phase": "idle"/"converting"/"exporting"/"done"/"error",
#     "current": int, "total": int,
#     "message": str }
_jobs: dict[str, dict[str, Any]] = {}
_jobs_lock = threading.Lock()


def _set_job(sid: str, **fields: Any) -> None:
    with _jobs_lock:
        state = _jobs.setdefault(sid, {"phase": "idle", "current": 0, "total": 0, "message": ""})
        state.update(fields)


def _get_job(sid: str) -> dict[str, Any]:
    with _jobs_lock:
        return dict(_jobs.get(sid, {"phase": "idle", "current": 0, "total": 0, "message": ""}))


def _is_job_running(sid: str) -> bool:
    return _get_job(sid)["phase"] in ("converting", "exporting")


# Pro Unit ein Regen-Status (2D-Bild neu wuerfeln), Key = "{sid}/{unit_key}":
#   { "phase": "idle"/"running"/"done"/"error", "message": str }
_regen_jobs: dict[str, dict[str, Any]] = {}
_regen_lock = threading.Lock()


def _regen_key(sid: str, unit_key: str) -> str:
    return f"{sid}/{unit_key}"


def _set_regen(sid: str, unit_key: str, **fields: Any) -> None:
    with _regen_lock:
        state = _regen_jobs.setdefault(_regen_key(sid, unit_key), {"phase": "idle", "message": ""})
        state.update(fields)


def _get_regen(sid: str, unit_key: str) -> dict[str, Any]:
    with _regen_lock:
        return dict(_regen_jobs.get(_regen_key(sid, unit_key), {"phase": "idle", "message": ""}))


# =============================================================================
# HELPERS
# =============================================================================

def _list_sessions() -> list[dict[str, Any]]:
    """Listet Sessions aus state/ auf, sortiert nach Modified-Time (neuste oben)."""
    if not STATE_DIR.exists():
        return []
    items: list[tuple[Path, float]] = []
    for child in STATE_DIR.iterdir():
        session_json: Path = child / "session.json"
        if child.is_dir() and session_json.exists():
            items.append((child, session_json.stat().st_mtime))
    items.sort(key=lambda t: t[1], reverse=True)
    out: list[dict[str, Any]] = []
    for path, _mt in items:
        try:
            session = PipelineSession.load(path)
        except Exception:
            continue
        progress = session.get_progress()
        out.append({
            "id": path.name,
            "total": progress["total"],
            "image_pending": progress["generated"],
            "image_approved": progress["approved"],
            "glb_pending": progress["converted"],
            "glb_approved": progress["glb_approved"],
            "exported": progress["exported"],
        })
    return out


def _load_session_or_404(session_id: str) -> PipelineSession:
    session_dir: Path = STATE_DIR / session_id
    if not (session_dir / "session.json").exists():
        abort(404, f"Session nicht gefunden: {session_id}")
    return PipelineSession.load(session_dir)


def _unit_dict(unit: UnitState) -> dict[str, Any]:
    return {
        "key": unit.unit_key,
        "name": unit.unit_name,
        "status": unit.status.value,
        "unit_class": unit.unit_class,
        "generation_count": unit.generation_count,
    }


# =============================================================================
# ROUTES — HTML pages
# =============================================================================

@app.route("/")
def index():
    sessions = _list_sessions()
    return render_template("index.html", sessions=sessions)


def _first_existing_glb_url() -> str | None:
    """Sucht in allen Sessions die erste real existierende GLB-Datei
    und gibt die /asset/glb/<key> URL zurueck — fuer die Diagnose-Seite."""
    if not STATE_DIR.exists():
        return None
    for child in sorted(STATE_DIR.iterdir(),
                        key=lambda p: p.stat().st_mtime, reverse=True):
        if not (child / "session.json").exists():
            continue
        try:
            session = PipelineSession.load(child)
        except Exception:
            continue
        for unit in session.get_all_units():
            if unit.glb_path and Path(unit.glb_path).exists():
                return f"/{child.name}/asset/glb/{unit.unit_key}"
    return None


@app.route("/diag")
def diag():
    return render_template("diag.html", test_glb_url=_first_existing_glb_url())


@app.route("/<session_id>/2d")
def review_2d(session_id: str):
    session = _load_session_or_404(session_id)
    reviewable_statuses = (
        UnitStatus.IMAGE_GENERATED,
        UnitStatus.IMAGE_APPROVED,
        UnitStatus.IMAGE_REJECTED,
    )
    units: list[dict[str, Any]] = []
    for unit in session.get_all_units():
        if unit.status in reviewable_statuses and unit.image_path:
            if Path(unit.image_path).exists():
                units.append(_unit_dict(unit))
    return render_template(
        "review_2d.html",
        session_id=session_id,
        units=units,
    )


@app.route("/<session_id>/3d")
def review_3d(session_id: str):
    session = _load_session_or_404(session_id)
    reviewable_statuses = (
        UnitStatus.GLB_READY,
        UnitStatus.GLB_APPROVED,
        UnitStatus.GLB_REJECTED,
    )
    units: list[dict[str, Any]] = []
    for unit in session.get_all_units():
        if unit.status in reviewable_statuses and unit.glb_path:
            if Path(unit.glb_path).exists():
                units.append(_unit_dict(unit))
    return render_template(
        "review_3d.html",
        session_id=session_id,
        units=units,
    )


# =============================================================================
# ROUTES — Asset-Streaming
# =============================================================================

@app.route("/<session_id>/asset/image/<unit_key>")
def serve_image(session_id: str, unit_key: str):
    session = _load_session_or_404(session_id)
    for unit in session.get_all_units():
        if unit.unit_key == unit_key and unit.image_path:
            path = Path(unit.image_path)
            if path.exists():
                return send_file(path)
    abort(404)


@app.route("/<session_id>/asset/glb/<unit_key>")
def serve_glb(session_id: str, unit_key: str):
    session = _load_session_or_404(session_id)
    for unit in session.get_all_units():
        if unit.unit_key == unit_key and unit.glb_path:
            path = Path(unit.glb_path)
            if path.exists():
                return send_file(path, mimetype="model/gltf-binary")
    abort(404)


# =============================================================================
# ROUTES — Status-Mutationen (JSON-API)
# =============================================================================

def _set_status(session_id: str, unit_key: str, new_status: UnitStatus):
    session = _load_session_or_404(session_id)
    try:
        session.update_status(unit_key, new_status)
    except KeyError:
        abort(404, f"Unit nicht gefunden: {unit_key}")
    session.save()
    return jsonify({"ok": True, "unit_key": unit_key, "status": new_status.value})


@app.post("/api/<session_id>/approve-image/<unit_key>")
def api_approve_image(session_id: str, unit_key: str):
    return _set_status(session_id, unit_key, UnitStatus.IMAGE_APPROVED)


@app.post("/api/<session_id>/reject-image/<unit_key>")
def api_reject_image(session_id: str, unit_key: str):
    return _set_status(session_id, unit_key, UnitStatus.IMAGE_REJECTED)


@app.post("/api/<session_id>/approve-glb/<unit_key>")
def api_approve_glb(session_id: str, unit_key: str):
    return _set_status(session_id, unit_key, UnitStatus.GLB_APPROVED)


@app.post("/api/<session_id>/reject-glb/<unit_key>")
def api_reject_glb(session_id: str, unit_key: str):
    return _set_status(session_id, unit_key, UnitStatus.GLB_REJECTED)


# =============================================================================
# WORKER — 3D-KONVERTIERUNG IM HINTERGRUND
# =============================================================================

def _read_secret(p: Path) -> str | None:
    if not p.exists():
        return None
    val = p.read_text(encoding="utf-8").strip()
    return val or None


def _load_design_language_for_session(session: PipelineSession) -> DesignLanguage | None:
    """Versucht die Design-Language anhand des faction_folder zu laden."""
    faction: str | None = getattr(session, "faction_folder", None)
    if not faction:
        return None
    yaml_path: Path = DESIGN_LANGUAGES_DIR / f"{faction}.yaml"
    if not yaml_path.exists():
        return None
    try:
        return load_design_language(yaml_path)
    except Exception as exc:
        logger.warning("DL load failed for %s: %s", faction, exc)
        return None


def _convert_worker(session_id: str) -> None:
    """Background-Worker: TRELLIS-Konvertierung aller IMAGE_APPROVED Units."""
    try:
        session_dir = STATE_DIR / session_id
        session = PipelineSession.load(session_dir)

        # Design-Language laden fuer unit_class-Lookup (falls Session noch
        # ohne unit_class Feld auskommt — alte Sessions).
        dl = _load_design_language_for_session(session)

        approved = session.get_units_by_status(UnitStatus.IMAGE_APPROVED)
        if not approved:
            _set_job(session_id, phase="done", current=0, total=0,
                     message="Keine genehmigten Bilder zum Konvertieren.")
            return

        # Resume: vorhandene GLBs ueberspringen, damit ein unterbrochener Lauf nicht von
        # vorne anfaengt (sonst werden bereits konvertierte Units erneut durch TRELLIS
        # gejagt = verschwendete Credits).
        glb_dir = session_dir / "glb"

        image_paths: dict[str, Path] = {}
        unit_classes: dict[str, str] = {}
        skipped_existing = 0
        for u in approved:
            existing_glb = glb_dir / f"{u.unit_key}.glb"
            if existing_glb.exists() and existing_glb.stat().st_size > 0:
                skipped_existing += 1
                continue
            if u.image_path and Path(u.image_path).exists():
                image_paths[u.unit_key] = Path(u.image_path)
                # Versuch 1: gespeichertes unit_class. Versuch 2: aus DL.
                cls = u.unit_class
                if (not cls or cls == "infantry") and dl is not None:
                    override = dl.unit_overrides.get(u.unit_key, {})
                    cls = classify_unit(override).value
                unit_classes[u.unit_key] = cls
        logger.info("Convert resume: %d GLBs existieren bereits, %d zu konvertieren",
                    skipped_existing, len(image_paths))

        total = len(image_paths)
        if total == 0:
            _set_job(session_id, phase="done", current=0, total=0,
                     message="Keine gueltigen Bilddateien gefunden.")
            return

        _set_job(session_id, phase="converting", current=0, total=total,
                 message="Konvertierung laeuft...")

        glb_dir.mkdir(parents=True, exist_ok=True)
        hf_token = _read_secret(HF_TOKEN_FILE)
        space_id = _read_secret(TRELLIS_SPACE_FILE)

        def progress_cb(current: int, total_count: int, unit_key: str) -> None:
            _set_job(session_id, phase="converting", current=current, total=total_count,
                     message=f"Konvertiere: {unit_key}")

        def status_cb(msg: str) -> None:
            # Freitext-Status (z.B. waehrend TRELLIS-Auto-Restart) in die Job-Message
            _set_job(session_id, phase="converting", message=msg)

        results = convert_batch(
            image_paths=image_paths,
            output_dir=glb_dir,
            hf_token=hf_token,
            preprocess=True,
            progress_callback=progress_cb,
            space_id=space_id,
            unit_classes=unit_classes,
            status_callback=status_cb,
        )

        success = 0
        failed = 0
        for unit_key, glb_path in results.items():
            if glb_path is not None:
                session.update_status(unit_key, UnitStatus.GLB_READY,
                                      glb_path=str(glb_path))
                success += 1
            else:
                failed += 1
        session.save()

        _set_job(session_id, phase="done", current=total, total=total,
                 message=f"Fertig: {success} erfolgreich, {failed} fehlgeschlagen.")
    except Exception as exc:
        logger.error("Convert worker failed:\n%s", traceback.format_exc())
        _set_job(session_id, phase="error", message=f"Fehler: {exc}")


def _export_worker(session_id: str) -> None:
    """Background-Worker: Export der GLB_APPROVED Units nach Niemandsland."""
    try:
        session_dir = STATE_DIR / session_id
        session = PipelineSession.load(session_dir)

        dl = _load_design_language_for_session(session)
        if dl is None:
            _set_job(session_id, phase="error",
                     message="Design-Language fuer Fraktion nicht gefunden.")
            return

        army = create_army_from_design_language(dl, session.faction_folder)
        unit_states = session.get_all_units()

        _set_job(session_id, phase="exporting", current=0, total=len(unit_states),
                 message="Exportiere nach assets/miniatures/ ...")

        result = export_army(
            army=army,
            unit_states=unit_states,
            project_root=PROJECT_ROOT,
        )

        if result.success:
            for u in unit_states:
                if u.status == UnitStatus.GLB_APPROVED:
                    session.update_status(u.unit_key, UnitStatus.EXPORTED)
            session.save()
            _set_job(session_id, phase="done",
                     current=result.exported_count, total=len(unit_states),
                     message=f"Exportiert: {result.exported_count} Modelle nach {result.glb_dir}")
        else:
            err = "\n".join(result.errors) if result.errors else "Unbekannter Fehler"
            _set_job(session_id, phase="error", message=f"Export fehlgeschlagen: {err}")
    except Exception as exc:
        logger.error("Export worker failed:\n%s", traceback.format_exc())
        _set_job(session_id, phase="error", message=f"Fehler: {exc}")


def _regenerate_image_worker(session_id: str, unit_key: str, feedback: str = "") -> None:
    """Background-Worker: ein einzelnes 2D-Bild neu generieren (Re-Roll).

    Baut den Prompt aus der Design-Language neu (nano-banana hat keinen Seed,
    derselbe Prompt liefert ein anderes Bild) und ueberschreibt das vorhandene
    Bild der Unit. Status geht zurueck auf IMAGE_GENERATED.

    feedback: optionale Nutzer-Beschreibung der gewuenschten Aenderung; wird
    prominent ans Prompt-Ende angehaengt, damit Gemini sie priorisiert.
    """
    try:
        session_dir = STATE_DIR / session_id
        session = PipelineSession.load(session_dir)
        unit = session.get_unit(unit_key)
        if unit is None:
            _set_regen(session_id, unit_key, phase="error", message="Unit nicht gefunden.")
            return

        dl = _load_design_language_for_session(session)
        if dl is None:
            _set_regen(session_id, unit_key, phase="error",
                       message="Design-Language fuer Fraktion nicht gefunden.")
            return

        override = dl.unit_overrides.get(unit_key)
        if override is None:
            _set_regen(session_id, unit_key, phase="error",
                       message=f"Unit {unit_key} nicht in Design-Language.")
            return

        gemini_key = _read_secret(GEMINI_KEY_FILE)
        if not gemini_key:
            _set_regen(session_id, unit_key, phase="error",
                       message="Gemini-Key fehlt (.gemini_key).")
            return

        feedback = (feedback or "").strip()
        unit_class = classify_unit(override)

        # Zielpfad: vorhandenes Bild ueberschreiben, sonst neu anlegen.
        if unit.image_path:
            image_path = Path(unit.image_path)
        else:
            images_dir = session_dir / "images"
            images_dir.mkdir(parents=True, exist_ok=True)
            image_path = images_dir / f"{unit_key}.png"

        current_image = Path(unit.image_path) if unit.image_path else None
        do_edit = bool(feedback) and current_image is not None and current_image.exists()

        gen = ImageGenerator(model=ImageModel.NANO_BANANA, gemini_api_key=gemini_key)

        if do_edit:
            # Echtes Image-Editing: nur die gewuenschte Aenderung anwenden,
            # Rest des Bildes bleibt erhalten.
            _set_regen(session_id, unit_key, phase="running",
                       message="Bearbeite Bild (nur gewuenschte Aenderung)...")
            edit_instruction = (
                "Edit this tabletop wargaming miniature image. Apply ONLY the "
                "following change(s) and keep EVERYTHING ELSE exactly as in the "
                "original — identical character, pose, proportions, equipment, "
                "colours, materials, art style, camera angle and framing, and the "
                "same plain background with no base, stand or pedestal.\n\n"
                "CHANGE(S) TO MAKE:\n" + feedback
            )
            result = gen.generate(
                prompt=edit_instruction,
                output_path=image_path,
                edit_image_path=current_image,
            )
            stored_prompt = edit_instruction
        else:
            # Frische Generierung im Fraktions-Stil (Re-Roll ohne Feedback):
            # Stil-Referenz = Klassen-Anchor (INFANTRY = Hero).
            _set_regen(session_id, unit_key, phase="running", message="Generiere neues Bild...")
            engine = PromptEngine(dl)
            prompt = _build_prompt_for(engine, unit_key, override)
            reference: Path | None = None
            if has_class_reference_image(PROJECT_ROOT, session.faction_folder, unit_class):
                reference = class_reference_image_path(PROJECT_ROOT, session.faction_folder, unit_class)
            result = gen.generate(
                prompt=prompt,
                output_path=image_path,
                reference_image_path=reference,
            )
            stored_prompt = prompt

        if not result.success:
            _set_regen(session_id, unit_key, phase="error",
                       message=f"Generierung fehlgeschlagen: {result.error}")
            return

        next_count = unit.generation_count + 1
        session.update_status(
            unit_key,
            UnitStatus.IMAGE_GENERATED,
            image_path=str(image_path),
            prompt=stored_prompt,
            model_used=result.model_used,
            generation_count=next_count,
            rejection_feedback=feedback,
        )
        session.save()
        mode = "bearbeitet" if do_edit else "neu generiert"
        _set_regen(session_id, unit_key, phase="done",
                   message=f"Bild {mode} (Versuch {next_count}).")
    except Exception as exc:
        logger.error("Regenerate worker failed:\n%s", traceback.format_exc())
        _set_regen(session_id, unit_key, phase="error", message=f"Fehler: {exc}")


# =============================================================================
# JOB-API
# =============================================================================

@app.post("/api/<session_id>/convert-3d")
def api_start_convert(session_id: str):
    if not (STATE_DIR / session_id / "session.json").exists():
        abort(404)
    if _is_job_running(session_id):
        return jsonify({"ok": False, "message": "Job laeuft bereits."}), 409
    _set_job(session_id, phase="converting", current=0, total=0, message="Starte...")
    threading.Thread(target=_convert_worker, args=(session_id,), daemon=True).start()
    return jsonify({"ok": True})


@app.post("/api/<session_id>/export")
def api_start_export(session_id: str):
    if not (STATE_DIR / session_id / "session.json").exists():
        abort(404)
    if _is_job_running(session_id):
        return jsonify({"ok": False, "message": "Job laeuft bereits."}), 409
    _set_job(session_id, phase="exporting", current=0, total=0, message="Starte...")
    threading.Thread(target=_export_worker, args=(session_id,), daemon=True).start()
    return jsonify({"ok": True})


@app.get("/api/<session_id>/job-status")
def api_job_status(session_id: str):
    return jsonify(_get_job(session_id))


@app.post("/api/<session_id>/regenerate-image/<unit_key>")
def api_regenerate_image(session_id: str, unit_key: str):
    if not (STATE_DIR / session_id / "session.json").exists():
        abort(404)
    if _get_regen(session_id, unit_key)["phase"] == "running":
        return jsonify({"ok": False, "message": "Regenerierung laeuft bereits."}), 409
    payload = request.get_json(silent=True) or {}
    feedback = str(payload.get("feedback", "") or "").strip()
    _set_regen(session_id, unit_key, phase="running", message="Starte...")
    threading.Thread(
        target=_regenerate_image_worker, args=(session_id, unit_key, feedback), daemon=True
    ).start()
    return jsonify({"ok": True})


@app.get("/api/<session_id>/regen-status/<unit_key>")
def api_regen_status(session_id: str, unit_key: str):
    return jsonify(_get_regen(session_id, unit_key))


# =============================================================================
# TRELLIS-SPACE — Status & Aufwecken (HuggingFace)
# =============================================================================

# HF-Space-Stage -> (css-Klasse, Klartext, ready?)
_STAGE_INFO: dict[str, tuple[str, str, bool]] = {
    "RUNNING": ("running", "Laeuft — bereit zum Generieren", True),
    "RUNNING_APP_STARTING": ("building", "App startet…", False),
    "RUNNING_BUILDING": ("building", "Startet (Build laeuft)…", False),
    "APP_STARTING": ("building", "App startet…", False),
    "BUILDING": ("building", "Baut…", False),
    "SLEEPING": ("sleeping", "Schlaeft", False),
    "PAUSED": ("paused", "Pausiert — aufwecken noetig", False),
    "STOPPED": ("paused", "Gestoppt — aufwecken noetig", False),
    "BUILD_ERROR": ("error", "Build-Fehler", False),
    "RUNTIME_ERROR": ("error", "Runtime-Fehler", False),
    "CONFIG_ERROR": ("error", "Config-Fehler", False),
    "NO_APP_FILE": ("error", "Keine App-Datei", False),
}


def _trellis_runtime() -> tuple[Any, str | None, str | None]:
    """Liefert (SpaceRuntime|None, space_id, fehler-text)."""
    space = _read_secret(TRELLIS_SPACE_FILE)
    token = _read_secret(HF_TOKEN_FILE)
    if not space:
        return None, None, ".trellis_space fehlt"
    try:
        from huggingface_hub import HfApi
        rt = HfApi().get_space_runtime(space, token=token)
        return rt, space, None
    except Exception as exc:
        return None, space, str(exc)


@app.get("/api/trellis/status")
def api_trellis_status():
    rt, space, err = _trellis_runtime()
    if rt is None:
        return jsonify({"ok": False, "stage": "ERROR", "css": "error",
                        "ready": False, "space": space, "message": err or "unbekannt"})
    stage = str(rt.stage)
    css, msg, ready = _STAGE_INFO.get(stage, ("building", stage, stage == "RUNNING"))
    hardware = getattr(rt, "hardware", None) or getattr(rt, "requested_hardware", None)
    return jsonify({"ok": True, "stage": stage, "css": css, "ready": ready,
                    "message": msg, "space": space, "hardware": hardware})


@app.post("/api/trellis/wake")
def api_trellis_wake():
    space = _read_secret(TRELLIS_SPACE_FILE)
    token = _read_secret(HF_TOKEN_FILE)
    if not space:
        return jsonify({"ok": False, "message": ".trellis_space fehlt"}), 400
    if not token:
        return jsonify({"ok": False, "message": ".hf_token fehlt (fuer restart noetig)"}), 400
    try:
        from huggingface_hub import HfApi
        api = HfApi()
        rt = api.get_space_runtime(space, token=token)
        if str(rt.stage) == "RUNNING":
            return jsonify({"ok": True, "stage": "RUNNING", "message": "Laeuft bereits."})
        api.restart_space(space, token=token)
        return jsonify({"ok": True, "stage": str(rt.stage), "message": "Aufwecken angestossen."})
    except Exception as exc:
        return jsonify({"ok": False, "message": str(exc)})


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5070, debug=False)

#!/usr/bin/env python3
"""R2 Model Browser — view, 3D-inspect and delete the miniature GLBs live on Cloudflare R2.

A local Flask tool (separate from the session-oriented review_app.py) that works off the
production `assets/model_manifest.json` — i.e. exactly what the game fetches from R2:

- **Overview** (`/`): every faction's R2 coverage (models on R2 vs roster total) — the "unit
  database" to see where to course-correct and which factions still need work.
- **Per-faction grid** (`/faction/<f>`): each shipped unit with its 2D source thumbnail, an
  on-demand 3D preview (model-viewer, GLB streamed same-origin from R2), the R2 hash/size, the
  public URL, and a confirmed **DELETE** — for pulling models that sit too close to an IP. Delete
  removes the R2 object (only if no other unit shares that content-addressed hash) AND the manifest
  entry; it also lists the faction's roster gaps (units not on R2) so you can ask the agent to
  re-generate them.

After deleting, the local `assets/model_manifest.json` is updated — ask the agent to commit it to
`main` so the change reaches the game. The tool never touches git itself.

Run:  ./venv/bin/python r2_model_browser.py   →  http://localhost:5072
"""
from __future__ import annotations

import json
from pathlib import Path

from flask import Flask, Response, abort, jsonify, render_template, request, send_file

import publish_manifest as pm  # reuse _load_r2_config (.r2_credentials)

# === Constants ===

THIS: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = THIS.parents[1]
MANIFEST: Path = PROJECT_ROOT / "assets" / "model_manifest.json"
STATE: Path = THIS / "state"
PORT: int = 5072

app = Flask(__name__)

# === Manifest + session helpers ===


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def save_manifest(m: dict) -> None:
    MANIFEST.write_text(json.dumps(m, indent=2) + "\n", encoding="utf-8")


def faction_units(m: dict) -> dict[str, list[tuple[str, str, dict]]]:
    """{faction_folder: [(unit_name, manifest_key, entry), ...]} sorted by unit name."""
    out: dict[str, list[tuple[str, str, dict]]] = {}
    for key, entry in m.get("models", {}).items():
        if "/" not in key:
            continue
        fac, unit = key.split("/", 1)
        out.setdefault(fac, []).append((unit, key, entry))
    for fac in out:
        out[fac].sort(key=lambda t: t[0])
    return out


def latest_session(faction: str) -> Path | None:
    cands = [d for d in STATE.glob(f"{faction}_2026*")
             if d.is_dir() and "_archived" not in d.name and "_discarded" not in d.name]
    return max(cands, key=lambda d: d.stat().st_mtime) if cands else None


def session_units(faction: str) -> list[dict]:
    s = latest_session(faction)
    if not s or not (s / "session.json").exists():
        return []
    return json.loads((s / "session.json").read_text(encoding="utf-8")).get("units", [])


def session_image_map(faction: str) -> dict[str, Path]:
    """unit-name-lower -> the picked 2D image path (from the latest session's images/)."""
    s = latest_session(faction)
    if not s:
        return {}
    out: dict[str, Path] = {}
    for u in session_units(faction):
        name = (u.get("unit_name") or "").strip().lower()
        img = s / "images" / f"{u.get('unit_key')}.png"
        if name and img.exists():
            out[name] = img
    return out


def r2_client():
    cfg = pm._load_r2_config("", "")
    import boto3
    from botocore.config import Config
    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    return s3, cfg["bucket"]


# === Routes ===


@app.route("/")
def overview():
    m = load_manifest()
    fu = faction_units(m)
    rows = []
    for fac in sorted(fu):
        roster = len(session_units(fac))
        rows.append({"faction": fac, "on_r2": len(fu[fac]),
                     "roster": roster, "gaps": max(0, roster - len(fu[fac]))})
    return render_template("r2_overview.html", rows=rows,
                           total=len(m.get("models", {})), factions=len(fu),
                           base_url=m.get("base_url", ""))


@app.route("/faction/<faction>")
def faction(faction: str):
    m = load_manifest()
    fu = faction_units(m).get(faction, [])
    imgmap = session_image_map(faction)
    on_r2_names = {u[0] for u in fu}
    gaps = [u.get("unit_name") for u in session_units(faction)
            if (u.get("unit_name") or "").strip().lower() not in on_r2_names]
    units = [{
        "unit": unit, "sha": entry["sha256"][:12], "size_mb": round(entry["size"] / 1e6, 1),
        "has_2d": unit in imgmap, "public_url": m.get("base_url", "") + entry["url"],
    } for unit, key, entry in fu]
    return render_template("r2_faction.html", faction=faction, units=units,
                           gaps=[g for g in gaps if g], on_r2=len(fu))


@app.route("/2d/<faction>/<path:unit>")
def serve_2d(faction: str, unit: str):
    p = session_image_map(faction).get(unit.strip().lower())
    if not p or not p.exists():
        abort(404)
    return send_file(str(p), mimetype="image/png")


@app.route("/glb/<faction>/<path:unit>")
def serve_glb(faction: str, unit: str):
    entry = load_manifest().get("models", {}).get(f"{faction}/{unit}")
    if not entry:
        abort(404)
    s3, bucket = r2_client()
    try:
        obj = s3.get_object(Bucket=bucket, Key=entry["url"])
    except Exception as e:  # noqa: BLE001
        abort(502, description=str(e))
    return Response(obj["Body"].read(), mimetype="model/gltf-binary")


@app.route("/api/delete", methods=["POST"])
def api_delete():
    data = request.get_json(force=True)
    faction, unit = data.get("faction", ""), data.get("unit", "")
    key = f"{faction}/{unit}"
    m = load_manifest()
    entry = m.get("models", {}).get(key)
    if not entry:
        return jsonify({"ok": False, "error": "manifest entry not found: " + key}), 404
    sha = entry.get("sha256", "")
    shared = [k for k, v in m["models"].items() if k != key and v.get("sha256") == sha]
    deleted_r2 = False
    if not shared:
        try:
            s3, bucket = r2_client()
            s3.delete_object(Bucket=bucket, Key=entry["url"])
            deleted_r2 = True
        except Exception as e:  # noqa: BLE001
            return jsonify({"ok": False, "error": "R2 delete failed: " + str(e)}), 502
    del m["models"][key]
    save_manifest(m)
    return jsonify({"ok": True, "deleted_from_r2": deleted_r2,
                    "shared_with": shared, "remaining": len(m["models"])})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=PORT, debug=False)

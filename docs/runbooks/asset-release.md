# Runbook — Modelle als GitHub-Release veröffentlichen (On-Demand go-live)

**Zweck:** Die Mini-GLBs auf ein **GitHub-Release** hochladen und das
`assets/model_manifest.json` befüllen, damit das Spiel die Modelle **on-demand**
lädt (statt sie zu bündeln). Hintergrund: [`../ASSET_DELIVERY.md`](../ASSET_DELIVERY.md).

> Läuft **lokal** (braucht die GLBs + `gh` + Token). Risikoarm und wiederholbar:
> Modelle sind content-addressed (`<sha256>.glb`), das Manifest ist klein, und das
> Spiel fällt bei fehlendem Modell auf Bundle/Platzhalter zurück.

## 0. Voraussetzungen
```bash
gh auth status                     # GitHub CLI eingeloggt
python3 --version                  # für publish_manifest.py
ls assets/miniatures/*/glb/*.glb | head   # GLBs lokal vorhanden
```
Tag festlegen, z. B. `models-v1` (Modelle werden separat von Code-Releases versioniert).

## 1. Release anlegen (einmal pro Tag)
```bash
gh release create models-v1 \
  --repo DutchMaxwell/openTTS \
  --title "OpenTTS models v1" \
  --notes "On-demand miniature models (content-addressed GLBs)."
```

## 2. Manifest erzeugen + GLBs hochladen (in einem Schritt)
```bash
python tools/model_forge/publish_manifest.py \
  assets/miniatures assets/model_manifest.json \
  --base-url "https://github.com/DutchMaxwell/openTTS/releases/download/models-v1/" \
  --upload --tag models-v1 --repo DutchMaxwell/openTTS
```
Das schreibt `assets/model_manifest.json` (Keys `faction/unit`, sha256, size) und
lädt jede GLB als `<sha256>.glb` ins Release (`--clobber` überschreibt bei Re-Runs).

## 3. Manifest committen
```bash
git add assets/model_manifest.json
git commit -m "chore(assets): publish model manifest (models-v1)"
git push
```

## 4. Im Spiel prüfen
- Eine Armee importieren → benötigte Modelle werden aus dem Release geladen und in
  `user://model_cache/<sha256>.glb` gecached (zweiter Import lädt nicht erneut).
- Kein Eintrag im Manifest → Bundle-Fallback bzw. Platzhalter (kein Crash).

## 5. Optional: gebündelte GLBs aus dem Repo entfernen
Sobald alle Factions im Manifest sind und das Laden verifiziert ist:
```bash
git rm -r assets/miniatures/<faction>/glb        # je migrierter Faction
git commit -m "chore(assets): drop bundled GLBs (now on-demand)"
```
*(Für echte Repo-Verkleinerung gehören die GLBs später auch aus der History — siehe
[`history-scrub.md`](history-scrub.md).)*

## Wichtig
- **`base_url` muss exakt der Release-Download-URL entsprechen** (Tag im Pfad!).
- Neuer/anderer Tag → `--base-url` und `--tag` konsistent anpassen, Manifest neu erzeugen.
- GitHub Releases liefern permissive CORS → funktioniert auch im Web-Build.

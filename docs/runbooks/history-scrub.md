# Runbook — Git-History scrubben (vor öffentlicher / MIT-Freigabe)

**Zweck:** Inhalte, die nur aus dem aktuellen Stand (`git rm`) entfernt wurden,
**rückwirkend aus der gesamten Git-History** tilgen, bevor das Repo öffentlich /
MIT wird:
- **OPR-Daten** (Stats/Listen sind OPR-Inhalt, nicht MIT-lizenzierbar),
- der **AGPL-`dice_roller`-Addon** (Copyleft),
- *(optional)* bereits on-demand migrierte **GLBs** (nur zur Repo-Verkleinerung).

> ⚠️ **Destruktiv und einmalig.** `git filter-repo` schreibt **alle Commit-SHAs neu**.
> Force-Push nötig; **alle bestehenden Klone/Forks/PRs werden inkompatibel** und müssen
> neu geklont werden. Erst ausführen, wenn das Repo konsolidiert ist (offene PRs
> gemerged/geschlossen, möglichst wenige aktive Branches — aktuell gibt es viele
> `claude/*`-Branches, die danach verworfen/neu gezogen werden müssen).

## 0. Voraussetzungen
```bash
pip install git-filter-repo        # oder: brew install git-filter-repo
git filter-repo --version
```
- GitHub-**Branch-Protection** auf `main` ggf. kurz deaktivieren (Force-Push).
- Alle wichtigen Branches lokal gesichert / gemerged.

## 1. Frischer Mirror-Klon (Sicherheit — nie im Arbeits-Repo!)
```bash
git clone --mirror https://github.com/DutchMaxwell/openTTS.git scrub.git
cd scrub.git
```

## 2. Pfade aus der GESAMTEN History entfernen
```bash
git filter-repo --invert-paths \
  --path-glob 'assets/miniatures/*/units.json' \
  --path 'assets/opr_samples' \
  --path-glob 'examples/*.json' \
  --path 'addons/dice_roller'
```
*Optional zusätzlich* (Repo-Größe; nur GLBs, die schon on-demand laufen):
```bash
  # an obigen Aufruf anhängen, z. B.:
  --path-glob 'assets/miniatures/*/glb/*'
```

## 3. Kontrolle — es darf nichts mehr gefunden werden
```bash
git log --all --oneline -- 'addons/dice_roller' | head        # erwartet: leer
git log --all --oneline -- 'assets/opr_samples' | head        # erwartet: leer
git grep -n -i "qua\":" $(git rev-list --all) -- 'assets/miniatures/*/units.json' | head  # leer
```

## 4. Rewritten History pushen (Force, alle Refs)
```bash
git push --force --mirror https://github.com/DutchMaxwell/openTTS.git
```

## 5. Danach
- Branch-Protection wieder aktivieren.
- **Alle** lokal neu klonen (`git clone …`); alte Arbeitskopien wegwerfen.
- Nicht mehr benötigte `claude/*`-Branches löschen (sie basieren auf alter History).
- **Hinweis:** GitHub cached unerreichbare Commits eine Weile und **Forks behalten die
  Daten**. Für vollständige Tilgung ggf. GitHub-Support kontaktieren und Forks prüfen.

## Verknüpfte Checkliste
Hakt die Punkte „Scrub git history" in [`../PRE_RELEASE_LICENSING.md`](../PRE_RELEASE_LICENSING.md) ab.

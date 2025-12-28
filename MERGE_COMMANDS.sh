#!/bin/bash
# openTTS Branch Merge Commands
# Session: 7SMn2 - UI Graphics Overhaul & 10x Scale Experiment

echo "=== openTTS Branch Merge Script ==="
echo ""
echo "Dieses Script hilft beim Mergen der Feature-Branches in main."
echo "WICHTIG: Lies BRANCH_MERGE_DOCUMENTATION.md vor der Ausführung!"
echo ""

# Sicherheitsabfrage
read -p "Hast du BRANCH_MERGE_DOCUMENTATION.md gelesen? (ja/nein): " READ_DOCS
if [ "$READ_DOCS" != "ja" ]; then
    echo "Bitte lies zuerst die Dokumentation!"
    exit 1
fi

echo ""
echo "=== SCHRITT 1: Backup-Tag erstellen ==="
git tag -a pre-merge-$(date +%Y%m%d) -m "Backup vor Branch-Merge am $(date)"
git push origin --tags
echo "✓ Backup-Tag erstellt"
echo ""

# UI Graphics Overhaul Merge
echo "=== SCHRITT 2: UI Graphics Overhaul Branch mergen ==="
read -p "UI Graphics Overhaul in main mergen? (ja/nein): " MERGE_UI
if [ "$MERGE_UI" == "ja" ]; then
    echo "Merge UI Graphics Overhaul..."
    git checkout main
    git pull origin main
    git merge claude/ui-graphics-overhaul-7SMn2 --no-ff -m "Merge UI Graphics Overhaul: Kenney Themes & Shadow Optimizations"

    if [ $? -eq 0 ]; then
        echo "✓ Merge erfolgreich!"
        git push origin main
        echo "✓ Gepusht zu origin/main"

        read -p "Branch claude/ui-graphics-overhaul-7SMn2 löschen? (ja/nein): " DELETE_UI
        if [ "$DELETE_UI" == "ja" ]; then
            git branch -d claude/ui-graphics-overhaul-7SMn2
            git push origin --delete claude/ui-graphics-overhaul-7SMn2
            echo "✓ Branch gelöscht"
        fi
    else
        echo "✗ Merge-Konflikt! Bitte manuell lösen."
        exit 1
    fi
else
    echo "⊘ UI Graphics Overhaul Merge übersprungen"
fi

echo ""
echo "=== SCHRITT 3: 10x Scale Experiment ==="
echo "ACHTUNG: Experimenteller Branch - Testing erforderlich!"
read -p "10x Scale Branch in main mergen? (ja/nein): " MERGE_10X
if [ "$MERGE_10X" == "ja" ]; then
    echo "Merge 10x Scale Experiment..."
    git checkout main
    git pull origin main
    git merge claude/10x-scale-experiment-7SMn2 --no-ff -m "Merge 10x Scale Experiment for improved shadow quality"

    if [ $? -eq 0 ]; then
        echo "✓ Merge erfolgreich!"
        git push origin main
        echo "✓ Gepusht zu origin/main"

        read -p "Branch claude/10x-scale-experiment-7SMn2 löschen? (ja/nein): " DELETE_10X
        if [ "$DELETE_10X" == "ja" ]; then
            git branch -d claude/10x-scale-experiment-7SMn2
            git push origin --delete claude/10x-scale-experiment-7SMn2
            echo "✓ Branch gelöscht"
        fi
    else
        echo "✗ Merge-Konflikt! Bitte manuell lösen."
        exit 1
    fi
else
    echo "⊘ 10x Scale Merge übersprungen"
    echo "   Branch bleibt für spätere Entwicklung erhalten."
fi

echo ""
echo "=== FERTIG ==="
echo "Branch-Status:"
git branch -a
echo ""
echo "Letzte Commits auf main:"
git log --oneline -5
echo ""
echo "✓ Merge-Prozess abgeschlossen!"

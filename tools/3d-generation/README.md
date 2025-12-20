# 3D-Modell-Generierung für OpenTTS

Erstelle texturierte 3D-Modelle aus Bildern für deine Tabletop-Spiele.

## TRELLIS.2 (Empfohlen)

**Microsoft's Open-Source Image-to-3D mit vollen Texturen**

| Feature | Details |
|---------|---------|
| Lizenz | MIT (frei für kommerzielle Nutzung) |
| Output | Mesh + PBR-Texturen (Farbe, Roughness, Metallic) |
| Qualität | 4 Milliarden Parameter, bis 1536³ Auflösung |

### Option 1: HuggingFace Space (Einfachste Methode)

Keine Installation nötig - läuft direkt im Browser:

**[TRELLIS.2 Demo öffnen](https://huggingface.co/spaces/microsoft/TRELLIS.2)**

**Workflow:**
1. Link öffnen
2. Bild hochladen
3. "Generate" klicken
4. GLB herunterladen
5. In OpenTTS importieren: `Spawn > Import GLB`

### Option 2: Google Colab (Colab Pro mit A100)

Für Batch-Verarbeitung oder mehr Kontrolle:

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/DutchMaxwell/openTTS/blob/main/tools/3d-generation/trellis2_colab.ipynb)

**Voraussetzung:** Colab Pro mit A100 GPU (24GB+ VRAM erforderlich)

## Tipps für beste Ergebnisse

- **Sauberer Hintergrund**: Weiß oder transparent
- **Ein Objekt pro Bild**: Klare Silhouette
- **Gute Beleuchtung**: Gleichmäßig, keine harten Schatten
- **Hohe Auflösung**: Mindestens 512x512 Pixel

## Import in OpenTTS

1. GLB-Datei herunterladen
2. In OpenTTS: `Spawn > Import GLB`
3. Positionieren und skalieren
4. `L` drücken zum Fixieren (für Terrain)

## Lizenz

- **TRELLIS.2**: MIT License ([Microsoft/TRELLIS.2](https://github.com/microsoft/TRELLIS.2))
- **Generierte Modelle**: Gehören dir, frei nutzbar

## Links

- [TRELLIS.2 GitHub](https://github.com/microsoft/TRELLIS.2)
- [TRELLIS.2 Paper](https://arxiv.org/abs/2512.14692)
- [HuggingFace Model](https://huggingface.co/microsoft/TRELLIS.2-4B)

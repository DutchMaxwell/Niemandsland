# Alien Hives Unit Asset Generation Workflow

## Overview
Dieses Dokument beschreibt den Workflow zur Generierung von 3D-Modellen für die GF - Alien Hives v3.5.1 Armeeliste.

**Workflow:**
1. Bildgenerierung mit Gemini 2.5 Flash Image (Nano Banana)
2. 3D-Konvertierung mit Trellis.2
3. Export als GLB für OpenTTS

---

## Optimierter Master-Prompt für Gemini

### Basis-Prompt Template (für alle Einheiten)

```
[UNIT_NAME], alien bioorganic creature miniature for tabletop wargaming.

CRITICAL REQUIREMENTS:
- NO base, NO pedestal, NO platform, NO ground, NO stand
- Floating pose with feet/appendages visible from below
- Clean silhouette against pure white background (#FFFFFF)
- Single centered creature, full body visible
- Isometric 3/4 view angle (optimal for 3D reconstruction)
- Consistent dramatic lighting from upper left
- High detail on surface textures (chitin, carapace, organic armor)
- 28mm tabletop miniature aesthetic and proportions

STYLE:
- Grimdark sci-fi horror aesthetic
- Tyranid/Xenomorph inspired alien design
- Biomechanical organic armor plating
- Bioluminescent accents in purple/green
- Muted color palette: dark purple, bone white, toxic green, deep red

OUTPUT:
- Square aspect ratio 1:1
- Resolution 1024x1024
- Clean edges for easy background removal
```

### Einheiten-spezifische Prompt-Erweiterungen

Ersetze `[UNIT_NAME]` und füge die spezifische Beschreibung hinzu:

---

## Komplette Einheitenliste (38 Einheiten)

### Infantry / Grunts

| # | Unit Name | Size | Prompt Extension |
|---|-----------|------|------------------|
| 1 | Hive Lord | 1 | massive alpha creature, commanding pose, crown of horns, multiple limbs with heavy claws and shredder cannon, towering presence |
| 2 | Prime Warrior | 1 | elite warrior creature, shredder gun integrated into arm, heavy razor claws, heroic pose |
| 3 | Snatcher Lord | 1 | fast predator, heavy claws elongated for grabbing, agile hunting pose |
| 4 | Grunt Veteran | 1 | veteran soldier creature, razor claws, battle-scarred carapace |
| 5 | Assault Grunts | 10 | swarm warrior, razor claws, aggressive charging pose |
| 6 | Shooter Grunts | 10 | ranged warrior, bio-spiner weapon fused to arm, aiming pose |
| 7 | Psycho-Grunts | 10 | feral warrior, rending claws, berserk aggressive pose |
| 8 | Winged Grunts | 10 | flying warrior, large insectoid wings, bio-spiners, aerial attack pose |
| 9 | Support Grunts | 3 | heavy weapons creature, bio-cannon shoulder mounted, braced firing pose |

### Specialists

| # | Unit Name | Size | Prompt Extension |
|---|-----------|------|------------------|
| 10 | Soul-Snatchers | 5 | fast predator, heavy claws, leaping attack pose |
| 11 | Hive Swarms | 3 | mass of small creatures, swarm of bugs, clustered together |
| 12 | Hive Warriors | 3 | elite warrior, razor claws, combat stance |
| 13 | Ravenous Beasts | 3 | feral quadruped beast, razor claws, predatory crouch |
| 14 | Venom Beasts | 3 | toxic creature, poison spurts from back, toxin dripping claws |
| 15 | Hive Guardians | 3 | defensive warrior, heavy armor plates, protective stance |
| 16 | Shadow Leapers | 3 | stealthy assassin, razor claws, crouched ready to spring |
| 17 | Synapse Beasts | 3 | psychic creature, enlarged cranium, psy-blast energy around head |

### Spores & Floaters

| # | Unit Name | Size | Prompt Extension |
|---|-----------|------|------------------|
| 18 | Spores | 5 | floating organic mine, tentacle tendrils, hovering pose |
| 19 | Massive Spores | 3 | large floating organism, multiple tendrils, bloated body |
| 20 | Invasion Carrier Spore | 1 | transport organism, cargo cavity visible, razor tendrils |
| 21 | Invasion Artillery Spore | 1 | floating artillery platform, spore gun, tendril stabilizers |

### Monsters

| # | Unit Name | Size | Prompt Extension |
|---|-----------|------|------------------|
| 22 | Shadow Hunter | 1 | stealthy monster, heavy razor claws, predatory stealth pose |
| 23 | Mortar Beast | 1 | artillery creature, spore gun on back, stomp feet |
| 24 | Synapse Tyrant | 1 | psychic overlord, massive cranium, psy-stinger weapon, commanding |
| 25 | Flamer Beast | 1 | fire-spitting creature, spit flames weapon, heavy claws |
| 26 | Carnivo-Rex | 1 | massive predator, heavy razor claws, powerful stomp legs |
| 27 | Toxico-Rex | 1 | toxic giant, acid spurt weapon, whip limbs, corrosive drool |
| 28 | Psycho-Rex | 1 | psychic monster, psy-stinger, heavy claws, mind-blast aura |
| 29 | Hive Burrower | 1 | tunneling creature, heavy razor claws, stomp feet, earth-moving |

### Heavy Beasts

| # | Unit Name | Size | Prompt Extension |
|---|-----------|------|------------------|
| 30 | Tyrant Heavy Beast | 1 | massive war-beast, bio-pod carrier, stinger launcher, armored |
| 31 | Spawning Heavy Beast | 1 | brood carrier, multiple stinger launchers, spawning sacs |
| 32 | Devourer Heavy Beast | 1 | consumption beast, devouring tongue, massive maw, razor claws |
| 33 | Artillery Heavy Beast | 1 | siege creature, shredder bio-artillery, massive frame |

### Titans

| # | Unit Name | Size | Prompt Extension |
|---|-----------|------|------------------|
| 34 | Hive Titan | 1 | colossal bio-titan, titanic heavy claws, massive stomp feet |
| 35 | Rapacious Beast | 1 | flying titan, caustic cannon, spore bombs, massive wings |

---

## Gemini Batch API Script

### Installation

```bash
pip install google-generativeai
```

### Python Batch Script

Siehe `generate_units.py` für das komplette Script.

---

## Trellis.2 Integration

Nach der Bildgenerierung:

1. **Hintergrund entfernen** (falls nötig - sollte bei weißem Hintergrund einfach sein)
2. **Trellis.2 Parameter:**
   - Format: GLB mit Texturen
   - Resolution: Standard (für Tabletop ausreichend)
   - Texture Resolution: 1024x1024

---

## Ordnerstruktur

```
assets/miniatures/alien_hives/
├── GENERATION_WORKFLOW.md    # Diese Datei
├── generate_units.py         # Batch-Generation Script
├── units.json                # Einheitendefinitionen
├── prompts/                  # Generierte Prompts
├── images/                   # Generierte Bilder
├── models/                   # GLB Dateien von Trellis.2
└── final/                    # Finale, optimierte Modelle
```

---

## Tipps für beste Ergebnisse

### Bildgenerierung (Gemini)
1. **Immer "NO base"** explizit erwähnen - Gemini neigt dazu, Basen hinzuzufügen
2. **Weißer Hintergrund** für einfache Segmentierung in Trellis
3. **3/4 Isometrische Ansicht** gibt Trellis die beste Tiefeninfo
4. **Konsistente Beleuchtung** für einheitlichen Stil der Armee

### 3D-Konvertierung (Trellis.2)
1. **Bilder auf ~1024x1024** skalieren vor Upload
2. **Einzelne Objekte** pro Bild (keine Gruppen)
3. **Klare Silhouette** ohne überlappende Teile

### Nachbearbeitung
1. **Basis nachträglich hinzufügen** in Blender (25mm rund für Infantry, 32mm für Monsters, etc.)
2. **LOD generieren** für Performance (Low Poly für Tabletop)
3. **Materialen vereinfachen** auf PBR Basics

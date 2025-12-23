#!/usr/bin/env python3
"""
Alien Hives Unit Image Generator for OpenTTS
=============================================

Verwendet Google Gemini 2.5 Flash Image (Nano Banana) für Batch-Bildgenerierung.
Die generierten Bilder sind optimiert für 3D-Konvertierung mit Trellis.2.

Usage:
    python generate_units.py --api-key YOUR_API_KEY
    python generate_units.py --api-key YOUR_API_KEY --unit "Hive Lord"
    python generate_units.py --api-key YOUR_API_KEY --batch

Environment:
    GEMINI_API_KEY - API Key kann auch als Umgebungsvariable gesetzt werden
"""

import os
import json
import time
import argparse
from pathlib import Path
from datetime import datetime

try:
    import google.generativeai as genai
    from google.generativeai import types
except ImportError:
    print("Bitte installiere google-generativeai: pip install google-generativeai")
    exit(1)


# ============================================================================
# KONFIGURATION
# ============================================================================

BASE_PROMPT = """
{unit_name}, alien bioorganic creature miniature for tabletop wargaming.

CRITICAL REQUIREMENTS:
- NO base, NO pedestal, NO platform, NO ground, NO stand, NO shadow on ground
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

SPECIFIC DETAILS:
{unit_details}

OUTPUT:
- Square aspect ratio 1:1
- Clean edges, no artifacts
- Professional miniature photography style
"""

# Alle Einheiten der Alien Hives v3.5.1 Armeeliste
UNITS = {
    # Infantry / Grunts
    "hive_lord": {
        "name": "Hive Lord",
        "size": 1,
        "details": "massive alpha creature, commanding pose, crown of horns, multiple limbs with heavy claws and shredder cannon integrated into arm, towering presence, apex predator of the hive"
    },
    "prime_warrior": {
        "name": "Prime Warrior",
        "size": 1,
        "details": "elite warrior creature, shredder gun bio-weapon integrated into arm, heavy razor claws on other arm, heroic commanding pose, scarred veteran"
    },
    "snatcher_lord": {
        "name": "Snatcher Lord",
        "size": 1,
        "details": "fast predator, elongated heavy claws designed for grabbing prey, agile hunting pose, lithe muscular body, hunter stalking"
    },
    "grunt_veteran": {
        "name": "Grunt Veteran",
        "size": 1,
        "details": "veteran soldier creature, razor claws, battle-scarred carapace with old wounds, experienced warrior stance"
    },
    "assault_grunts": {
        "name": "Assault Grunt",
        "size": 10,
        "details": "basic swarm warrior, razor claws on both arms, aggressive charging pose, horde creature, expendable soldier"
    },
    "shooter_grunts": {
        "name": "Shooter Grunt",
        "size": 10,
        "details": "ranged warrior, bio-spiner ranged weapon fused to arm, aiming pose, organic rifle arm"
    },
    "psycho_grunts": {
        "name": "Psycho-Grunt",
        "size": 10,
        "details": "feral warrior, rending claws with serrated edges, berserk aggressive pose, foam at mouth, crazed expression"
    },
    "winged_grunts": {
        "name": "Winged Grunt",
        "size": 10,
        "details": "flying warrior, large translucent insectoid wings, bio-spiners for ranged attack, aerial diving attack pose, gargoyle-like"
    },
    "support_grunts": {
        "name": "Support Grunt",
        "size": 3,
        "details": "heavy weapons creature, ravager bio-cannon shoulder mounted, braced firing pose, ammunition sacs on back"
    },

    # Specialists
    "soul_snatchers": {
        "name": "Soul-Snatcher",
        "size": 5,
        "details": "fast assassin predator, heavy rending claws, leaping attack pose mid-air, lithe body, stealth hunter"
    },
    "hive_swarms": {
        "name": "Hive Swarm",
        "size": 3,
        "details": "mass of small creatures, swarm of alien bugs clustered together, dozens of tiny organisms, crawling mass"
    },
    "hive_warriors": {
        "name": "Hive Warrior",
        "size": 3,
        "details": "elite warrior, razor claws, combat stance ready to strike, armored carapace, disciplined soldier"
    },
    "ravenous_beasts": {
        "name": "Ravenous Beast",
        "size": 3,
        "details": "feral quadruped beast, razor claws, predatory crouch ready to pounce, wolf-like alien, pack hunter"
    },
    "venom_beasts": {
        "name": "Venom Beast",
        "size": 3,
        "details": "toxic quadruped creature, poison spurts vents from back, toxin dripping from claws, corrosive slime trail"
    },
    "hive_guardians": {
        "name": "Hive Guardian",
        "size": 3,
        "details": "defensive warrior, extra heavy armor plates, protective stance with claws raised, shield-like carapace"
    },
    "shadow_leapers": {
        "name": "Shadow Leaper",
        "size": 3,
        "details": "stealthy assassin, razor claws, crouched ready to spring, shadowy dark coloring, ambush predator"
    },
    "synapse_beasts": {
        "name": "Synapse Beast",
        "size": 3,
        "details": "psychic creature, massively enlarged cranium, psy-blast energy crackling around head, floating stance, telepathic"
    },

    # Spores & Floaters
    "spores": {
        "name": "Spore Mine",
        "size": 5,
        "details": "floating organic mine, multiple tentacle tendrils hanging down, hovering pose, balloon-like body, bio-explosive"
    },
    "massive_spores": {
        "name": "Massive Spore",
        "size": 3,
        "details": "large floating organism, multiple long tendrils, bloated gas-filled body, jellyfish-like alien"
    },
    "invasion_carrier_spore": {
        "name": "Invasion Carrier Spore",
        "size": 1,
        "details": "transport organism, cargo cavity visible in translucent body, razor tendrils, carrying smaller organisms inside"
    },
    "invasion_artillery_spore": {
        "name": "Invasion Artillery Spore",
        "size": 1,
        "details": "floating artillery platform, spore gun bio-cannon underneath, tendril stabilizers, bombardment organism"
    },

    # Monsters
    "shadow_hunter": {
        "name": "Shadow Hunter",
        "size": 1,
        "details": "large stealthy monster, heavy razor claws, predatory stealth pose, chameleon skin, infiltrator beast"
    },
    "mortar_beast": {
        "name": "Mortar Beast",
        "size": 1,
        "details": "artillery creature, massive spore gun mortar on back, heavy stomp feet, artillery platform beast"
    },
    "synapse_tyrant": {
        "name": "Synapse Tyrant",
        "size": 1,
        "details": "psychic overlord monster, massive glowing cranium, psy-stinger bio-weapon, commanding pose, psychic nexus"
    },
    "flamer_beast": {
        "name": "Flamer Beast",
        "size": 1,
        "details": "fire-spitting creature, spit flames bio-weapon mouth, heavy claws, burning drool, pyrokinetic beast"
    },
    "carnivo_rex": {
        "name": "Carnivo-Rex",
        "size": 1,
        "details": "massive predator dinosaur, heavy razor claws, powerful stomp legs, T-Rex inspired alien, apex carnivore"
    },
    "toxico_rex": {
        "name": "Toxico-Rex",
        "size": 1,
        "details": "toxic giant dinosaur, acid spurt bio-weapon, whip limbs, corrosive drool, melting everything around"
    },
    "psycho_rex": {
        "name": "Psycho-Rex",
        "size": 1,
        "details": "psychic monster dinosaur, psy-stinger bio-weapon, heavy claws, mind-blast energy aura around head"
    },
    "hive_burrower": {
        "name": "Hive Burrower",
        "size": 1,
        "details": "tunneling creature, massive digging heavy razor claws, stomp feet, mole-like alien, earth-moving beast"
    },

    # Heavy Beasts
    "tyrant_heavy_beast": {
        "name": "Tyrant Heavy Beast",
        "size": 1,
        "details": "massive war-beast carrier, bio-pod launcher on back, stinger launcher weapons, heavily armored tank beast"
    },
    "spawning_heavy_beast": {
        "name": "Spawning Heavy Beast",
        "size": 1,
        "details": "brood carrier beast, multiple stinger launchers, visible spawning sacs with creatures inside, mother beast"
    },
    "devourer_heavy_beast": {
        "name": "Devourer Heavy Beast",
        "size": 1,
        "details": "consumption beast, massive devouring tongue weapon, enormous maw with rows of teeth, heavy razor claws"
    },
    "artillery_heavy_beast": {
        "name": "Artillery Heavy Beast",
        "size": 1,
        "details": "siege creature, shredder bio-artillery cannon on back, massive reinforced frame, walking artillery platform"
    },

    # Titans
    "hive_titan": {
        "name": "Hive Titan",
        "size": 1,
        "details": "colossal bio-titan towering monster, titanic heavy claws, massive stomp feet, city-destroyer scale, ultimate war beast"
    },
    "rapacious_beast": {
        "name": "Rapacious Beast",
        "size": 1,
        "details": "flying titan monster, caustic cannon bio-weapon, spore bombs dropping, massive dragon-like wings, aerial destroyer"
    }
}


# ============================================================================
# GENERATOR CLASS
# ============================================================================

class AlienHivesGenerator:
    """Generator für Alien Hives Einheiten-Bilder."""

    def __init__(self, api_key: str, output_dir: str = None):
        """
        Initialisiert den Generator.

        Args:
            api_key: Google Gemini API Key
            output_dir: Ausgabeverzeichnis für Bilder
        """
        self.api_key = api_key
        self.output_dir = Path(output_dir) if output_dir else Path(__file__).parent / "images"
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Prompts-Verzeichnis
        self.prompts_dir = Path(__file__).parent / "prompts"
        self.prompts_dir.mkdir(parents=True, exist_ok=True)

        # Gemini konfigurieren
        genai.configure(api_key=api_key)

        # Model für Bildgenerierung
        self.model = genai.GenerativeModel("gemini-2.0-flash-exp")  # oder gemini-2.5-flash-image wenn verfügbar

    def build_prompt(self, unit_key: str) -> str:
        """Erstellt den vollständigen Prompt für eine Einheit."""
        unit = UNITS.get(unit_key)
        if not unit:
            raise ValueError(f"Unbekannte Einheit: {unit_key}")

        return BASE_PROMPT.format(
            unit_name=unit["name"],
            unit_details=unit["details"]
        )

    def generate_image(self, unit_key: str, variation: int = 0) -> Path:
        """
        Generiert ein Bild für eine Einheit.

        Args:
            unit_key: Schlüssel der Einheit aus UNITS
            variation: Variationsnummer für mehrere Versuche

        Returns:
            Pfad zur gespeicherten Bilddatei
        """
        unit = UNITS.get(unit_key)
        if not unit:
            raise ValueError(f"Unbekannte Einheit: {unit_key}")

        prompt = self.build_prompt(unit_key)

        # Prompt speichern für Referenz
        prompt_file = self.prompts_dir / f"{unit_key}_prompt.txt"
        prompt_file.write_text(prompt, encoding="utf-8")

        print(f"🎨 Generiere: {unit['name']} (Variation {variation})...")

        try:
            # Bildgenerierung mit Gemini
            response = self.model.generate_content(
                prompt,
                generation_config=types.GenerationConfig(
                    response_mime_type="image/png",
                )
            )

            # Bild speichern
            if response.candidates and response.candidates[0].content.parts:
                for part in response.candidates[0].content.parts:
                    if hasattr(part, 'inline_data') and part.inline_data:
                        # Dateiname erstellen
                        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        filename = f"{unit_key}_v{variation}_{timestamp}.png"
                        filepath = self.output_dir / filename

                        # Bild speichern
                        filepath.write_bytes(part.inline_data.data)
                        print(f"✅ Gespeichert: {filepath}")
                        return filepath

            print(f"⚠️  Keine Bilddaten in Antwort für {unit['name']}")
            return None

        except Exception as e:
            print(f"❌ Fehler bei {unit['name']}: {e}")
            return None

    def generate_all(self, delay: float = 2.0, variations: int = 1):
        """
        Generiert Bilder für alle Einheiten.

        Args:
            delay: Verzögerung zwischen Anfragen (Rate Limiting)
            variations: Anzahl Variationen pro Einheit
        """
        total = len(UNITS) * variations
        current = 0
        results = {"success": [], "failed": []}

        print(f"\n🚀 Starte Batch-Generierung für {len(UNITS)} Einheiten ({total} Bilder)...\n")

        for unit_key, unit in UNITS.items():
            for v in range(variations):
                current += 1
                print(f"\n[{current}/{total}] ", end="")

                result = self.generate_image(unit_key, v)

                if result:
                    results["success"].append({"unit": unit_key, "file": str(result)})
                else:
                    results["failed"].append(unit_key)

                # Rate Limiting
                if current < total:
                    print(f"⏳ Warte {delay}s...")
                    time.sleep(delay)

        # Zusammenfassung
        print(f"\n{'='*50}")
        print(f"📊 ZUSAMMENFASSUNG")
        print(f"{'='*50}")
        print(f"✅ Erfolgreich: {len(results['success'])}/{total}")
        print(f"❌ Fehlgeschlagen: {len(results['failed'])}/{total}")

        if results["failed"]:
            print(f"\nFehlgeschlagene Einheiten:")
            for unit in results["failed"]:
                print(f"  - {UNITS[unit]['name']}")

        # Ergebnisse speichern
        results_file = self.output_dir / "generation_results.json"
        with open(results_file, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        print(f"\n📄 Ergebnisse gespeichert: {results_file}")

        return results


def create_batch_jsonl(output_file: str = "batch_requests.jsonl"):
    """
    Erstellt eine JSONL-Datei für die Gemini Batch API.

    Für große Batch-Verarbeitung mit 50% Rabatt und höheren Rate Limits.
    Turnaround: bis zu 24 Stunden.
    """
    output_path = Path(__file__).parent / output_file

    with open(output_path, "w", encoding="utf-8") as f:
        for unit_key, unit in UNITS.items():
            prompt = BASE_PROMPT.format(
                unit_name=unit["name"],
                unit_details=unit["details"]
            )

            request = {
                "key": unit_key,
                "request": {
                    "contents": [
                        {
                            "parts": [
                                {"text": prompt}
                            ]
                        }
                    ],
                    "generationConfig": {
                        "responseMimeType": "image/png"
                    }
                }
            }

            f.write(json.dumps(request, ensure_ascii=False) + "\n")

    print(f"📄 Batch JSONL erstellt: {output_path}")
    print(f"   Enthält {len(UNITS)} Anfragen")
    print(f"\n   Verwendung mit Batch API:")
    print(f"   1. Upload: client.files.upload(path='{output_file}')")
    print(f"   2. Job erstellen: client.batches.create(model='gemini-2.5-flash-image', src=file)")
    print(f"   3. Status prüfen: client.batches.get(name=batch_job.name)")

    return output_path


def export_units_json():
    """Exportiert die Einheitenliste als JSON."""
    output_path = Path(__file__).parent / "units.json"

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(UNITS, f, indent=2, ensure_ascii=False)

    print(f"📄 Einheiten exportiert: {output_path}")
    return output_path


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Alien Hives Unit Image Generator für OpenTTS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Beispiele:
  # Einzelne Einheit generieren
  python generate_units.py --api-key KEY --unit hive_lord

  # Alle Einheiten generieren (Echtzeit)
  python generate_units.py --api-key KEY --all

  # Batch-JSONL für Batch API erstellen
  python generate_units.py --create-batch

  # Einheitenliste exportieren
  python generate_units.py --export-units

  # Verfügbare Einheiten anzeigen
  python generate_units.py --list
        """
    )

    parser.add_argument("--api-key", help="Gemini API Key (oder GEMINI_API_KEY env)")
    parser.add_argument("--unit", help="Einzelne Einheit generieren (unit_key)")
    parser.add_argument("--all", action="store_true", help="Alle Einheiten generieren")
    parser.add_argument("--variations", type=int, default=1, help="Variationen pro Einheit")
    parser.add_argument("--delay", type=float, default=2.0, help="Verzögerung zwischen Requests (Sekunden)")
    parser.add_argument("--output", help="Ausgabeverzeichnis")
    parser.add_argument("--create-batch", action="store_true", help="Batch JSONL für Batch API erstellen")
    parser.add_argument("--export-units", action="store_true", help="Einheitenliste als JSON exportieren")
    parser.add_argument("--list", action="store_true", help="Verfügbare Einheiten anzeigen")

    args = parser.parse_args()

    # Einheitenliste anzeigen
    if args.list:
        print("\n📋 Verfügbare Einheiten (Alien Hives v3.5.1):\n")
        for key, unit in UNITS.items():
            print(f"  {key:30} - {unit['name']} [{unit['size']}]")
        print(f"\n   Gesamt: {len(UNITS)} Einheiten")
        return

    # Batch JSONL erstellen
    if args.create_batch:
        create_batch_jsonl()
        return

    # Einheiten exportieren
    if args.export_units:
        export_units_json()
        return

    # API Key erforderlich für Generierung
    api_key = args.api_key or os.environ.get("GEMINI_API_KEY")

    if args.unit or args.all:
        if not api_key:
            print("❌ Fehler: API Key erforderlich (--api-key oder GEMINI_API_KEY)")
            return

        generator = AlienHivesGenerator(api_key, args.output)

        if args.unit:
            if args.unit not in UNITS:
                print(f"❌ Unbekannte Einheit: {args.unit}")
                print("   Verwende --list für verfügbare Einheiten")
                return
            generator.generate_image(args.unit)
        elif args.all:
            generator.generate_all(delay=args.delay, variations=args.variations)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()

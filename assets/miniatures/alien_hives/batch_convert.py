#!/usr/bin/env python3
"""
OpenTTS 3D Pipeline - Batch Converter (Terminal Version)
=========================================================

Konvertiert alle PNG-Bilder im aktuellen Ordner zu 3D-Modellen.

Verwendung:
    python batch_convert.py

Oder für bestimmte Dateien:
    python batch_convert.py bild1.png bild2.png
"""

import os
import sys
from pathlib import Path

def main():
    # Get script directory
    script_dir = Path(__file__).parent
    os.chdir(script_dir)

    # Check for token file
    token_file = script_dir / ".hf_token"
    if token_file.exists():
        hf_token = token_file.read_text().strip()
        print(f"✅ Token geladen aus .hf_token")
    else:
        print("=" * 50)
        print("HuggingFace Token benötigt!")
        print("Hol dir einen Token von: huggingface.co/settings/tokens")
        print("=" * 50)
        hf_token = input("Token eingeben: ").strip()
        if hf_token:
            save = input("Token speichern für nächstes Mal? (j/n): ").lower()
            if save == 'j':
                token_file.write_text(hf_token)
                print("✅ Token gespeichert")

    if not hf_token:
        print("❌ Kein Token - Abbruch")
        return

    # Get files to process
    if len(sys.argv) > 1:
        # Files specified as arguments
        files = [Path(f) for f in sys.argv[1:] if Path(f).exists()]
    else:
        # Find all PNG files (exclude _clean and _preprocessed)
        files = [f for f in script_dir.glob("*.png")
                 if not f.stem.endswith("_clean")
                 and not f.stem.endswith("_preprocessed")]

    if not files:
        print("❌ Keine PNG-Bilder gefunden")
        print("   Lege Bilder in diesen Ordner oder gib sie als Argument an:")
        print("   python batch_convert.py bild1.png bild2.png")
        return

    print(f"\n📁 Gefundene Bilder: {len(files)}")
    for f in files:
        print(f"   - {f.name}")

    # Quality settings
    print("\n⚙️ Qualitätseinstellungen:")
    print("   1) Schnell (512, niedrig)")
    print("   2) Normal (1024, mittel) [Standard]")
    print("   3) Hoch (1536, hoch)")

    choice = input("Wähle (1/2/3) oder Enter für Standard: ").strip()

    if choice == "1":
        resolution, decimation, texture = "512", 100000, 1024
    elif choice == "3":
        resolution, decimation, texture = "1536", 500000, 4096
    else:
        resolution, decimation, texture = "1024", 300000, 2048

    print(f"\n🚀 Starte Pipeline mit {len(files)} Bild(ern)...")
    print(f"   Auflösung: {resolution}, Mesh: {decimation}, Textur: {texture}")
    print("=" * 50)

    # Import pipeline
    try:
        from pipeline import HuggingFaceTrellis
    except ImportError as e:
        print(f"❌ Import-Fehler: {e}")
        print("   Stelle sicher, dass alle Dependencies installiert sind:")
        print("   pip install requests gradio_client Pillow")
        return

    # Initialize TRELLIS
    try:
        print("\n🔗 Verbinde mit TRELLIS.2...")
        trellis = HuggingFaceTrellis(
            hf_token=hf_token,
            resolution=resolution,
            decimation=decimation,
            texture_size=texture,
            preprocess=True  # Wichtig: Entfernt weißen Hintergrund
        )
    except Exception as e:
        print(f"❌ Verbindungsfehler: {e}")
        return

    # Process files
    success = 0
    failed = 0

    for i, filepath in enumerate(files, 1):
        print(f"\n[{i}/{len(files)}] {filepath.name}")
        print("-" * 40)

        try:
            # Generate 3D (includes watermark removal)
            result = trellis.generate(filepath, script_dir)

            if result:
                print(f"   ✅ Fertig: {result.name}")
                success += 1
            else:
                print("   ❌ Fehlgeschlagen (kein Output)")
                failed += 1

        except Exception as e:
            print(f"   ❌ Fehler: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

    # Summary
    print("\n" + "=" * 50)
    print("📊 FERTIG!")
    print(f"   ✅ Erfolgreich: {success}")
    print(f"   ❌ Fehlgeschlagen: {failed}")
    print("=" * 50)

    # Show output location
    models_dir = script_dir / "models"
    if models_dir.exists():
        print(f"\n📂 Modelle gespeichert in: {models_dir}")


if __name__ == "__main__":
    main()

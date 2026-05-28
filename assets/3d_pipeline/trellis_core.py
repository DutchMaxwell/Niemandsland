#!/usr/bin/env python3
"""
Trellis 3D Pipeline - Core Functions
=====================================

Kernfunktionen fuer die Konvertierung von Bildern zu 3D-Modellen
mit Microsoft TRELLIS.2 ueber HuggingFace Spaces.

Qualitaet: Immer Maximum (1536px, 500k Polygone, 4K Textur)
"""

import os
import sys
import random
import shutil
import traceback
from pathlib import Path
from typing import Optional

# Dependencies check
try:
    from gradio_client import Client as GradioClient
    from gradio_client import handle_file
    HAS_GRADIO = True
except ImportError:
    HAS_GRADIO = False
    print("FEHLER: gradio_client nicht installiert")
    print("       pip install gradio_client")

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("WARNUNG: Pillow nicht installiert - Preprocessing deaktiviert")
    print("         pip install Pillow")


# =============================================================================
# KONSTANTEN - MAXIMALE QUALITAET
# =============================================================================

DEFAULT_TRELLIS_SPACE: str = "microsoft/TRELLIS.2"

RESOLUTION = "1536"           # Hoechste Aufloesung
DECIMATION = 100000           # Default-Polygonzahl (Server-Minimum, ausreichend
                              # fuer alle Klassen ausser TITAN)
TEXTURE_SIZE = 4096           # 4K Texturen (Server-Maximum)

# Pro UnitClass-Wert. Titan-Voxel-Latents sind zu komplex fuer
# aggressive Server-Decimation und crashen das extract_glb bei <300000;
# alle anderen Klassen laufen sauber am Server-Minimum.
DECIMATION_BY_CLASS: dict[str, int] = {
    "infantry": 100000,
    "walker":   100000,
    "vehicle":  100000,
    "aircraft": 100000,
    "titan":    300000,
}

SUPPORTED_FORMATS = ('.png', '.jpg', '.jpeg', '.webp')


# =============================================================================
# BILD-PREPROCESSING
# =============================================================================

def remove_gemini_watermark(img: "Image.Image") -> "Image.Image":
    """
    Entfernt das Gemini-Wasserzeichen aus der rechten unteren Ecke.
    Verwendet Paint-Over Methode mit der echten Hintergrundfarbe.
    """
    width, height = img.size
    pixels = img.load()

    watermark_size = 200

    # Hintergrundfarbe aus sicherem Bereich samplen
    sample_x = max(0, width - watermark_size - 50)
    sample_y = max(0, height - watermark_size - 50)

    if img.mode == "RGBA":
        bg_r, bg_g, bg_b, bg_a = pixels[sample_x, sample_y]
        bg_color = (bg_r, bg_g, bg_b, 255)
    else:
        bg_r, bg_g, bg_b = pixels[sample_x, sample_y]
        bg_color = (bg_r, bg_g, bg_b)

    bg_brightness = (bg_r + bg_g + bg_b) / 3
    BRIGHTNESS_THRESHOLD = bg_brightness + 10

    for y in range(height - watermark_size, height):
        for x in range(width - watermark_size, width):
            if img.mode == "RGBA":
                r, g, b, a = pixels[x, y]
            else:
                r, g, b = pixels[x, y]

            brightness = (r + g + b) / 3

            if brightness > BRIGHTNESS_THRESHOLD:
                pixels[x, y] = bg_color

    return img


def preprocess_image(image_path: Path, output_path: Optional[Path] = None) -> Path:
    """
    Bereitet ein Bild fuer TRELLIS vor:
    1. Entfernt Gemini-Wasserzeichen
    2. Ersetzt weissen Hintergrund durch Transparenz
    3. Schneidet auf quadratisches Format zu
    4. Zentriert das Motiv
    """
    if not HAS_PIL:
        return image_path

    img = Image.open(image_path).convert("RGBA")

    # Wasserzeichen entfernen
    img = remove_gemini_watermark(img)

    pixels = img.load()
    width, height = img.size

    # Motiv finden (nicht-weisse Pixel)
    min_x, min_y = width, height
    max_x, max_y = 0, 0

    new_img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    new_pixels = new_img.load()

    WHITE_THRESHOLD = 240

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]

            if r > WHITE_THRESHOLD and g > WHITE_THRESHOLD and b > WHITE_THRESHOLD:
                pass  # Transparent lassen
            else:
                new_pixels[x, y] = (r, g, b, 255)
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    if max_x <= min_x or max_y <= min_y:
        return image_path

    # Quadratisch zuschneiden mit 10% Padding
    subject_width = max_x - min_x
    subject_height = max_y - min_y
    subject_center_x = min_x + subject_width // 2
    subject_center_y = min_y + subject_height // 2

    square_size = int(max(subject_width, subject_height) * 1.1)

    left = max(0, subject_center_x - square_size // 2)
    top = max(0, subject_center_y - square_size // 2)
    right = min(width, left + square_size)
    bottom = min(height, top + square_size)

    if right - left < square_size:
        left = max(0, right - square_size)
    if bottom - top < square_size:
        top = max(0, bottom - square_size)

    cropped = new_img.crop((left, top, right, bottom))

    crop_w, crop_h = cropped.size
    final_size = max(crop_w, crop_h)
    final_img = Image.new("RGBA", (final_size, final_size), (0, 0, 0, 0))

    paste_x = (final_size - crop_w) // 2
    paste_y = (final_size - crop_h) // 2
    final_img.paste(cropped, (paste_x, paste_y))

    if output_path is None:
        output_path = image_path.parent / f"{image_path.stem}_preprocessed.png"

    final_img.save(output_path, "PNG")
    return output_path


# =============================================================================
# TRELLIS 3D GENERATOR
# =============================================================================

class TrellisGenerator:
    """
    Konvertiert Bilder zu 3D-Modellen mit TRELLIS.2 via HuggingFace Space.
    Verwendet immer maximale Qualitaet.
    """

    def __init__(
        self,
        hf_token: Optional[str] = None,
        log_callback=None,
        space_id: Optional[str] = None,
    ):
        """
        Initialisiert den Generator.

        Args:
            hf_token: HuggingFace Token fuer Pro-Quota
            log_callback: Funktion zum Loggen von Nachrichten
            space_id: HuggingFace Space-ID (z.B. "DutchyMaxwell/TRELLIS-2").
                      Faellt zurueck auf DEFAULT_TRELLIS_SPACE.
        """
        if not HAS_GRADIO:
            raise ImportError("gradio_client nicht installiert: pip install gradio_client")

        self.log = log_callback or print
        resolved_space: str = space_id or DEFAULT_TRELLIS_SPACE

        self.log(f"Verbinde mit {resolved_space}...")

        if hf_token:
            os.environ["HF_TOKEN"] = hf_token
            self.log("   HF Pro Token gesetzt")

        self.client = GradioClient(resolved_space)
        self.log("   Verbunden!")
        self.log(f"   Qualitaet: {RESOLUTION}px, {DECIMATION} Polygone, {TEXTURE_SIZE}px Textur")

    def convert(self, image_path: Path, output_dir: Path,
                preprocess: bool = True,
                unit_class: Optional[str] = None) -> Optional[Path]:
        """
        Konvertiert ein Bild zu einem 3D-Modell.

        Args:
            image_path: Pfad zum Eingabebild
            output_dir: Ausgabeverzeichnis fuer GLB-Datei
            preprocess: Bild vorverarbeiten (Wasserzeichen, Hintergrund)
            unit_class: Optionaler UnitClass-Wert (str: "infantry"/"walker"/
                        "vehicle"/"aircraft"/"titan"). Steuert das
                        Decimation-Target via DECIMATION_BY_CLASS.

        Returns:
            Pfad zur GLB-Datei oder None bei Fehler
        """
        try:
            # Preprocessing
            if preprocess and HAS_PIL:
                self.log("   Preprocessing...")
                processed_path = preprocess_image(image_path)
            else:
                processed_path = image_path

            # 3D generieren
            self.log("   Generiere 3D-Modell (1-3 Minuten)...")

            seed = random.randint(0, 2147483647)

            self.log(f"   Sende Bild an API: {processed_path}")
            self.log(f"   Seed: {seed}, Resolution: {RESOLUTION}")

            result = self.client.predict(
                image=handle_file(str(processed_path)),
                seed=seed,
                resolution=RESOLUTION,
                ss_guidance_strength=7.5,
                ss_guidance_rescale=0.7,
                ss_sampling_steps=12,
                ss_rescale_t=5.0,
                shape_slat_guidance_strength=7.5,
                shape_slat_guidance_rescale=0.5,
                shape_slat_sampling_steps=12,
                shape_slat_rescale_t=3.0,
                tex_slat_guidance_strength=1.0,
                tex_slat_guidance_rescale=0.0,
                tex_slat_sampling_steps=12,
                tex_slat_rescale_t=3.0,
                api_name="/image_to_3d"
            )

            self.log(f"   image_to_3d Ergebnis: {type(result)} - {result}")

            decimation = DECIMATION_BY_CLASS.get(unit_class or "", DECIMATION)

            self.log("   Extrahiere GLB...")
            self.log(f"   Decimation: {decimation} (class={unit_class or 'default'}), Texture: {TEXTURE_SIZE}")

            glb_result = self.client.predict(
                decimation_target=decimation,
                texture_size=TEXTURE_SIZE,
                api_name="/extract_glb"
            )

            self.log(f"   extract_glb Ergebnis: {type(glb_result)} - {glb_result}")

            glb_path = glb_result[0] if isinstance(glb_result, tuple) else glb_result
            self.log(f"   GLB Pfad: {glb_path}")

            if glb_path and os.path.exists(glb_path):
                # Ausgabedatei mit gleichem Namen wie Eingabe
                output_name = image_path.stem + ".glb"
                output_path = output_dir / output_name
                output_dir.mkdir(parents=True, exist_ok=True)

                shutil.copy(glb_path, output_path)
                self.log(f"   Gespeichert: {output_path.name}")
                return output_path
            else:
                self.log("   FEHLER: GLB-Extraktion fehlgeschlagen")
                return None

        except Exception as e:
            self.log(f"   FEHLER: {e}")
            self.log(f"   TRACEBACK:")
            for line in traceback.format_exc().split('\n'):
                self.log(f"   {line}")
            return None


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def find_images(directory: Path) -> list:
    """Findet alle unterstuetzten Bilddateien in einem Verzeichnis."""
    images = []
    for ext in SUPPORTED_FORMATS:
        images.extend(directory.glob(f"*{ext}"))
        images.extend(directory.glob(f"*{ext.upper()}"))

    # Preprocessed/Clean Dateien ausschliessen
    images = [
        img for img in images
        if "_preprocessed" not in img.stem and "_clean" not in img.stem
    ]

    return sorted(images)


def get_token_path() -> Path:
    """Gibt den Pfad zur Token-Datei zurueck."""
    return Path(__file__).parent / ".hf_token"


def load_token() -> Optional[str]:
    """Laedt den gespeicherten HF-Token."""
    token_path = get_token_path()
    if token_path.exists():
        return token_path.read_text().strip()
    return None


def save_token(token: str) -> None:
    """Speichert den HF-Token."""
    token_path = get_token_path()
    token_path.write_text(token)

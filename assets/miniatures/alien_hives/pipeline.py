#!/usr/bin/env python3
"""
Image-to-3D Pipeline for OpenTTS
================================

Zwei Modi:

1. EMPFOHLEN: Gemini-Bilder zu 3D konvertieren
   - Generiere Bilder manuell auf aistudio.google.com (beste Qualität!)
   - Konvertiere sie automatisch zu 3D mit Trellis.2

   python pipeline.py --image hive_lord.png
   python pipeline.py --image bild1.png --image bild2.png

2. Vollautomatisch: FLUX + Trellis (100% kostenlos)
   - Bildgenerierung via FLUX.1-schnell
   - 3D-Konvertierung via Trellis.2

   python pipeline.py --unit hive_lord
   python pipeline.py --all

Requirements:
    pip install gradio_client requests
"""

import os
import sys
import json
import time
import argparse
import base64
from pathlib import Path
from datetime import datetime
from typing import Optional, Literal

# ============================================================================
# DEPENDENCIES
# ============================================================================

try:
    import requests
except ImportError:
    print("❌ pip install requests")
    sys.exit(1)

# Optional: Gradio Client für Hugging Face Spaces
try:
    from gradio_client import Client as GradioClient
    from gradio_client import handle_file
    HAS_GRADIO = True
except ImportError:
    HAS_GRADIO = False

# Optional: PIL for image preprocessing
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


# ============================================================================
# IMAGE PREPROCESSING (like TRELLIS web interface)
# ============================================================================

def preprocess_image_for_trellis(image_path: Path, output_path: Path = None) -> Path:
    """
    Preprocess image like TRELLIS web interface does:
    1. Replace white/light background with transparency
    2. Find subject bounding box
    3. Crop to square with subject centered
    4. Add padding around subject
    """
    if not HAS_PIL:
        print("   ⚠️ PIL not installed, skipping preprocessing")
        return image_path

    img = Image.open(image_path).convert("RGBA")
    pixels = img.load()
    width, height = img.size

    # Step 1: Find non-white pixels (the subject) and make white transparent
    min_x, min_y = width, height
    max_x, max_y = 0, 0

    # Create new image with transparent background
    new_img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    new_pixels = new_img.load()

    # Threshold for "white" (light background)
    WHITE_THRESHOLD = 240

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]

            # Check if pixel is "white" (background)
            if r > WHITE_THRESHOLD and g > WHITE_THRESHOLD and b > WHITE_THRESHOLD:
                # Make transparent (already transparent in new_img)
                pass
            else:
                # Copy subject pixel
                new_pixels[x, y] = (r, g, b, 255)
                # Track bounding box
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    # Step 2: Calculate square crop with padding
    if max_x <= min_x or max_y <= min_y:
        print("   ⚠️ Could not find subject, using original image")
        return image_path

    subject_width = max_x - min_x
    subject_height = max_y - min_y
    subject_center_x = min_x + subject_width // 2
    subject_center_y = min_y + subject_height // 2

    # Make square based on larger dimension, add 10% padding
    square_size = int(max(subject_width, subject_height) * 1.1)

    # Calculate crop box (centered on subject)
    left = max(0, subject_center_x - square_size // 2)
    top = max(0, subject_center_y - square_size // 2)
    right = min(width, left + square_size)
    bottom = min(height, top + square_size)

    # Adjust if we hit edges
    if right - left < square_size:
        left = max(0, right - square_size)
    if bottom - top < square_size:
        top = max(0, bottom - square_size)

    # Step 3: Crop and create final square image
    cropped = new_img.crop((left, top, right, bottom))

    # Ensure perfectly square by padding if needed
    crop_w, crop_h = cropped.size
    final_size = max(crop_w, crop_h)
    final_img = Image.new("RGBA", (final_size, final_size), (0, 0, 0, 0))

    # Center the cropped image
    paste_x = (final_size - crop_w) // 2
    paste_y = (final_size - crop_h) // 2
    final_img.paste(cropped, (paste_x, paste_y))

    # Save preprocessed image as PNG with transparency
    if output_path is None:
        output_path = image_path.parent / f"{image_path.stem}_preprocessed.png"

    final_img.save(output_path, "PNG")
    print(f"   ✅ Preprocessed: {output_path.name} ({final_size}x{final_size}, transparent bg)")

    return output_path


# ============================================================================
# PROMPT TEMPLATES
# ============================================================================

ALIEN_HIVES_BASE_PROMPT = """
{unit_name}, alien bioorganic creature for tabletop gaming.

COMPOSITION - CRITICAL:
- ONLY ONE single creature
- ONLY ONE viewing angle (3/4 isometric from front-left)
- NOT a character sheet, NOT a turnaround, NOT multiple views
- Single isolated render, centered in frame

CREATURE DESIGN:
{unit_details}

COLOR PALETTE:
- Deep crimson red carapace and exoskeleton
- Bone white armor plates and horns
- Dark red muscle tissue visible between plates

STYLE:
- Inspiration: HR Giger xenomorph, Starship Troopers bugs, Zerg from Starcraft
- Biomechanical organic textures: chitin, sinew, bone ridges
- NOT Games Workshop / Tyranid designs
- No skulls, no gothic elements, no GW iconography

TECHNICAL:
- NO base, NO ground, NO pedestal, NO shadow on floor
- Pure white background (#FFFFFF)
- Full body visible from head to feet
- Clean silhouette edges
- Optimized for AI 3D model reconstruction
"""

HUMAN_DEFENSE_FORCE_PROMPT = """
{unit_name}, futuristic human soldier for tabletop gaming.

COMPOSITION - CRITICAL:
- ONLY ONE single figure
- ONLY ONE viewing angle (3/4 isometric from front-left)
- NOT a character sheet, NOT a turnaround, NOT multiple views
- Single isolated render, centered in frame

SOLDIER DESIGN:
{unit_details}

COLOR PALETTE:
- Grey tactical armor panels
- Light blue utility uniform fabric
- Black boots and equipment

STYLE:
- Near-future realistic military aesthetic
- Inspiration: Mass Effect, Halo, XCOM soldiers
- Clean functional design, no gothic or fantasy elements
- NOT Games Workshop / Warhammer aesthetic
- No skulls, no religious symbols, no oversized shoulders

TECHNICAL:
- NO base, NO ground, NO pedestal, NO shadow on floor
- Pure white background (#FFFFFF)
- Full body visible from head to feet
- Clean silhouette edges
- Optimized for AI 3D model reconstruction
"""

# Unit definitions
UNITS = {
    # Alien Hives
    "hive_lord": {
        "name": "Hive Lord",
        "army": "alien_hives",
        "details": """- Huge bipedal alien organism, 3 meters tall imposing presence
- Crown of curved horns/antennae on elongated head
- Four arms: two massive scything claws, one arm with integrated bio-cannon
- Powerful digitigrade legs with armored hooves
- Commanding stance, arms raised aggressively
- Mouth open showing rows of teeth"""
    },
    "assault_grunt": {
        "name": "Assault Grunt",
        "army": "alien_hives",
        "details": """- Medium humanoid alien warrior
- Hunched aggressive posture
- Two arms with razor-sharp claws
- Armored carapace on back and shoulders
- Running/charging pose
- Snarling face with mandibles"""
    },
    "carnivo_rex": {
        "name": "Carnivo-Rex",
        "army": "alien_hives",
        "details": """- Massive dinosaur-like alien predator
- Towering bipedal stance, T-Rex inspired
- Huge crushing jaws with rows of teeth
- Small but deadly clawed arms
- Powerful legs with armored scales
- Roaring pose, tail for balance"""
    },

    # Human Defense Force
    "hdf_soldier": {
        "name": "Defense Force Soldier",
        "army": "human_defense",
        "details": """- Standard infantry soldier
- Tactical vest over utility uniform
- Modern helmet with visor
- Assault rifle held at ready
- Standing alert combat stance
- Equipment pouches on belt"""
    },
    "hdf_sergeant": {
        "name": "Defense Force Sergeant",
        "army": "human_defense",
        "details": """- Veteran infantry NCO
- Heavier tactical armor
- Helmet with command antenna
- Rifle in one hand, pointing with other
- Commanding pose
- Extra equipment and grenades"""
    },
}


# ============================================================================
# GEMINI IMAGE GENERATOR
# ============================================================================

class HuggingFaceImageGenerator:
    """Generates images using Hugging Face Spaces (FLUX) - works worldwide!"""

    def __init__(self):
        if not HAS_GRADIO:
            raise ImportError("❌ pip install gradio_client")

        print("🔗 Connecting to FLUX image generator...")
        # Using black-forest-labs FLUX.1-schnell - free and fast
        self.client = GradioClient("black-forest-labs/FLUX.1-schnell")
        print("   ✅ Connected!")

    def generate(self, unit_key: str, output_dir: Path) -> Optional[Path]:
        """Generate image for a unit."""
        unit = UNITS.get(unit_key)
        if not unit:
            raise ValueError(f"Unknown unit: {unit_key}")

        # Select template based on army
        if unit["army"] == "alien_hives":
            template = ALIEN_HIVES_BASE_PROMPT
        else:
            template = HUMAN_DEFENSE_FORCE_PROMPT

        prompt = template.format(
            unit_name=unit["name"],
            unit_details=unit["details"]
        )

        print(f"🎨 Generating image: {unit['name']}...")

        try:
            # FLUX.1-schnell API
            result = self.client.predict(
                prompt=prompt,
                seed=0,
                randomize_seed=True,
                width=1024,
                height=1024,
                num_inference_steps=4,
                api_name="/infer"
            )

            # Result is (image_path, seed)
            if result and len(result) > 0:
                image_path = result[0]
                if image_path and os.path.exists(image_path):
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    filename = f"{unit_key}_{timestamp}.png"
                    filepath = output_dir / "images" / filename
                    filepath.parent.mkdir(parents=True, exist_ok=True)

                    import shutil
                    shutil.copy(image_path, filepath)
                    print(f"   ✅ Saved: {filepath}")
                    return filepath

            print(f"   ⚠️ No image data in response")
            return None

        except Exception as e:
            print(f"   ❌ Error: {e}")
            return None


# ============================================================================
# TRELLIS 3D GENERATORS
# ============================================================================

class ReplicateTrellis:
    """Generate 3D models using Replicate API."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.model_version = "firtoz/trellis"
        self.api_url = "https://api.replicate.com/v1/predictions"

    def generate(self, image_path: Path, output_dir: Path) -> Optional[Path]:
        """Convert image to 3D model."""
        print(f"🔮 Converting to 3D (Replicate)...")

        # Read and encode image
        with open(image_path, "rb") as f:
            image_data = base64.b64encode(f.read()).decode("utf-8")

        # Create prediction
        headers = {
            "Authorization": f"Token {self.api_key}",
            "Content-Type": "application/json"
        }

        payload = {
            "version": "2034f5d49dba29730f8bf8279f8dff72f5ef68fb79e6f426b665badb4e57e0f4",
            "input": {
                "image": f"data:image/png;base64,{image_data}",
                "texture_size": 1024,
                "mesh_simplify": 0.95,
                "generate_model": True,
                "generate_color": True,
            }
        }

        # Start prediction
        response = requests.post(self.api_url, headers=headers, json=payload)
        if response.status_code != 201:
            print(f"   ❌ API Error: {response.text}")
            return None

        prediction = response.json()
        prediction_id = prediction["id"]
        print(f"   ⏳ Prediction started: {prediction_id}")

        # Poll for completion
        poll_url = f"{self.api_url}/{prediction_id}"
        while True:
            time.sleep(5)
            response = requests.get(poll_url, headers=headers)
            status = response.json()

            if status["status"] == "succeeded":
                # Download GLB
                glb_url = status["output"].get("model_file") or status["output"].get("glb")
                if glb_url:
                    glb_response = requests.get(glb_url)

                    output_name = image_path.stem + ".glb"
                    output_path = output_dir / "models" / output_name
                    output_path.parent.mkdir(parents=True, exist_ok=True)

                    output_path.write_bytes(glb_response.content)
                    print(f"   ✅ 3D Model saved: {output_path}")
                    return output_path

            elif status["status"] == "failed":
                print(f"   ❌ Prediction failed: {status.get('error')}")
                return None

            print(f"   ⏳ Status: {status['status']}...")


class FalTrellis:
    """Generate 3D models using fal.ai API."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.api_url = "https://queue.fal.run/fal-ai/trellis-2"

    def generate(self, image_path: Path, output_dir: Path) -> Optional[Path]:
        """Convert image to 3D model."""
        print(f"🔮 Converting to 3D (fal.ai)...")

        # Read and encode image
        with open(image_path, "rb") as f:
            image_data = base64.b64encode(f.read()).decode("utf-8")

        headers = {
            "Authorization": f"Key {self.api_key}",
            "Content-Type": "application/json"
        }

        payload = {
            "image_url": f"data:image/png;base64,{image_data}",
            "ss_guidance_strength": 7.5,
            "ss_sampling_steps": 12,
            "slat_guidance_strength": 3,
            "slat_sampling_steps": 12,
            "mesh_simplify": 0.95,
            "texture_size": 1024
        }

        # Submit job
        response = requests.post(self.api_url, headers=headers, json=payload)
        if response.status_code != 200:
            print(f"   ❌ API Error: {response.text}")
            return None

        result = response.json()

        # Check if queued or immediate
        if "request_id" in result:
            # Poll for result
            status_url = f"https://queue.fal.run/fal-ai/trellis-2/requests/{result['request_id']}/status"
            while True:
                time.sleep(5)
                status_response = requests.get(status_url, headers=headers)
                status = status_response.json()

                if status.get("status") == "COMPLETED":
                    result = status.get("response", {})
                    break
                elif status.get("status") == "FAILED":
                    print(f"   ❌ Job failed")
                    return None

                print(f"   ⏳ Status: {status.get('status')}...")

        # Download GLB
        glb_url = result.get("glb", {}).get("url")
        if glb_url:
            glb_response = requests.get(glb_url)

            output_name = image_path.stem + ".glb"
            output_path = output_dir / "models" / output_name
            output_path.parent.mkdir(parents=True, exist_ok=True)

            output_path.write_bytes(glb_response.content)
            print(f"   ✅ 3D Model saved: {output_path}")
            return output_path

        print(f"   ❌ No GLB in response")
        return None


class HuggingFaceTrellis:
    """Generate 3D models using Hugging Face Space."""

    def __init__(self, hf_token: str = None, resolution: str = "1024",
                 decimation: int = 300000, texture_size: int = 2048):
        if not HAS_GRADIO:
            raise ImportError("❌ pip install gradio_client")

        self.resolution = resolution
        self.decimation = decimation
        self.texture_size = texture_size

        print("🔗 Connecting to Hugging Face Space...")
        if hf_token:
            print("   🔑 Using HF Pro authentication")
            # Set HF_TOKEN env var for gradio_client authentication
            os.environ["HF_TOKEN"] = hf_token
        self.client = GradioClient("microsoft/TRELLIS.2")
        print("   ✅ Connected!")
        print(f"   📐 Resolution: {resolution}, Decimation: {decimation}, Texture: {texture_size}")

    def generate(self, image_path: Path, output_dir: Path) -> Optional[Path]:
        """Convert image to 3D model via Hugging Face Space."""
        print(f"🔮 Converting to 3D (Hugging Face Space)...")

        try:
            # Step 0: Preprocess image like web interface does
            print("   🖼️ Preprocessing image...")
            processed_path = preprocess_image_for_trellis(image_path)

            # Step 1: Generate 3D with correct API parameters
            print("   ⏳ Generating 3D model (this may take 1-2 minutes)...")

            # Use random seed like web interface
            import random
            seed = random.randint(0, 2147483647)
            print(f"   🎲 Seed: {seed}")

            result = self.client.predict(
                image=handle_file(str(processed_path)),
                seed=seed,
                resolution=self.resolution,
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
            print(f"   ✅ 3D generation complete")

            # Step 2: Extract GLB
            print("   📦 Extracting GLB...")
            glb_result = self.client.predict(
                decimation_target=self.decimation,
                texture_size=self.texture_size,
                api_name="/extract_glb"
            )

            # glb_result is (extracted_glb, download_glb) - both are filepaths
            glb_path = glb_result[0] if isinstance(glb_result, tuple) else glb_result

            if glb_path and os.path.exists(glb_path):
                output_name = image_path.stem + ".glb"
                output_path = output_dir / "models" / output_name
                output_path.parent.mkdir(parents=True, exist_ok=True)

                import shutil
                shutil.copy(glb_path, output_path)
                print(f"   ✅ 3D Model saved: {output_path}")
                return output_path
            else:
                print(f"   ❌ GLB extraction failed: {glb_result}")
                return None

        except Exception as e:
            print(f"   ❌ Error: {e}")
            import traceback
            traceback.print_exc()
            return None


# ============================================================================
# MAIN PIPELINE
# ============================================================================

class Pipeline:
    """Complete Image → 3D Pipeline."""

    def __init__(
        self,
        trellis_key: str = None,
        hf_token: str = None,
        backend: Literal["huggingface", "replicate", "fal"] = "huggingface",
        output_dir: str = None,
        image_only: bool = False,  # Skip image generation, only do 3D
        resolution: str = "1024",
        decimation: int = 300000,
        texture_size: int = 2048
    ):
        self.output_dir = Path(output_dir) if output_dir else Path(__file__).parent
        self.image_only = image_only

        # Only init image generator if needed
        if not image_only:
            self.image_generator = HuggingFaceImageGenerator()
        else:
            self.image_generator = None

        # 3D generation backend
        if backend == "huggingface":
            self.trellis = HuggingFaceTrellis(
                hf_token=hf_token,
                resolution=resolution,
                decimation=decimation,
                texture_size=texture_size
            )
        elif backend == "replicate":
            if not trellis_key:
                raise ValueError("Replicate backend requires --replicate-key")
            self.trellis = ReplicateTrellis(trellis_key)
        elif backend == "fal":
            if not trellis_key:
                raise ValueError("fal.ai backend requires --fal-key")
            self.trellis = FalTrellis(trellis_key)
        else:
            raise ValueError(f"Unknown backend: {backend}")

    def process_image(self, image_path: str) -> Optional[Path]:
        """Convert an existing image to 3D model."""
        image_path = Path(image_path)
        if not image_path.exists():
            print(f"❌ Image not found: {image_path}")
            return None

        print(f"\n{'='*50}")
        print(f"Converting to 3D: {image_path.name}")
        print(f"{'='*50}")

        model_path = self.trellis.generate(image_path, self.output_dir)
        if model_path:
            print(f"\n✅ Done! Model saved: {model_path}")
        return model_path

    def process_unit(self, unit_key: str) -> dict:
        """Process a single unit through the full pipeline."""
        print(f"\n{'='*50}")
        print(f"Processing: {UNITS[unit_key]['name']}")
        print(f"{'='*50}")

        result = {
            "unit": unit_key,
            "image": None,
            "model": None,
            "success": False
        }

        # Step 1: Generate image
        image_path = self.image_generator.generate(unit_key, self.output_dir)
        if not image_path:
            return result
        result["image"] = str(image_path)

        # Step 2: Convert to 3D
        time.sleep(2)  # Brief pause between APIs
        model_path = self.trellis.generate(image_path, self.output_dir)
        if not model_path:
            return result
        result["model"] = str(model_path)

        result["success"] = True
        return result

    def process_all(self, delay: float = 5.0) -> list:
        """Process all units."""
        results = []
        total = len(UNITS)

        print(f"\n🚀 Starting pipeline for {total} units...\n")

        for i, unit_key in enumerate(UNITS.keys(), 1):
            print(f"\n[{i}/{total}]")
            result = self.process_unit(unit_key)
            results.append(result)

            if i < total:
                print(f"⏳ Waiting {delay}s before next unit...")
                time.sleep(delay)

        # Summary
        success = sum(1 for r in results if r["success"])
        print(f"\n{'='*50}")
        print(f"📊 PIPELINE COMPLETE")
        print(f"{'='*50}")
        print(f"✅ Success: {success}/{total}")
        print(f"❌ Failed: {total - success}/{total}")

        # Save results
        results_file = self.output_dir / "pipeline_results.json"
        with open(results_file, "w") as f:
            json.dump(results, f, indent=2)
        print(f"📄 Results: {results_file}")

        return results


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Image-to-3D Pipeline for OpenTTS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Beispiele:
  # Bild zu 3D konvertieren (mit HF Pro für mehr Quota)
  python pipeline.py --image hive_lord.png --hf-token YOUR_TOKEN

  # Mehrere Bilder konvertieren
  python pipeline.py --image bild1.png --image bild2.png --hf-token YOUR_TOKEN

  # Mit Qualitätseinstellungen (höhere Auflösung, mehr Detail)
  python pipeline.py --image hive_lord.png --resolution 1536 --decimation 400000 --texture-size 4096

  # Automatische Pipeline (FLUX + Trellis)
  python pipeline.py --unit hive_lord
        """
    )

    # Image-to-3D Modus (empfohlen für Gemini-Bilder)
    parser.add_argument("--image", action="append", help="Bild zu 3D konvertieren (kann mehrfach verwendet werden)")

    # Automatische Pipeline
    parser.add_argument("--unit", help="Einheit automatisch generieren")
    parser.add_argument("--all", action="store_true", help="Alle Einheiten generieren")

    # Hugging Face Pro (mehr GPU Quota)
    parser.add_argument("--hf-token", help="Hugging Face Token für Pro-Quota (https://huggingface.co/settings/tokens)")

    # Backend Optionen
    parser.add_argument("--replicate-key", help="Replicate API Token")
    parser.add_argument("--fal-key", help="fal.ai API Key")
    parser.add_argument("--backend", choices=["huggingface", "replicate", "fal"], default="huggingface")

    # TRELLIS.2 Quality Settings
    parser.add_argument("--resolution", choices=["512", "1024", "1536"], default="1024",
                        help="3D model resolution (default: 1024)")
    parser.add_argument("--decimation", type=int, default=300000,
                        help="Mesh decimation target 100000-500000 (default: 300000)")
    parser.add_argument("--texture-size", type=int, default=2048,
                        help="Texture size 1024-4096 (default: 2048)")

    # Andere Optionen
    parser.add_argument("--output", help="Output directory")
    parser.add_argument("--list", action="store_true", help="Einheiten anzeigen")
    parser.add_argument("--delay", type=float, default=10.0, help="Delay zwischen Einheiten")

    args = parser.parse_args()

    if args.list:
        print("\n📋 Available Units:\n")
        for key, unit in UNITS.items():
            print(f"  {key:20} - {unit['name']} ({unit['army']})")
        return

    # Check gradio_client is installed
    if not HAS_GRADIO:
        print("❌ gradio_client required")
        print("   pip install gradio_client")
        return

    # Get trellis key only if needed for paid backends
    trellis_key = None
    if args.backend == "replicate":
        trellis_key = args.replicate_key or os.environ.get("REPLICATE_API_TOKEN")
        if not trellis_key:
            print("❌ Replicate API key required for --backend replicate")
            return
    elif args.backend == "fal":
        trellis_key = args.fal_key or os.environ.get("FAL_KEY")
        if not trellis_key:
            print("❌ fal.ai API key required for --backend fal")
            return

    # Get Hugging Face token
    hf_token = args.hf_token or os.environ.get("HF_TOKEN")

    # Image-to-3D Modus
    if args.image:
        pipeline = Pipeline(
            trellis_key=trellis_key,
            hf_token=hf_token,
            backend=args.backend,
            output_dir=args.output,
            image_only=True,  # Skip FLUX, only Trellis
            resolution=args.resolution,
            decimation=args.decimation,
            texture_size=args.texture_size
        )
        for img in args.image:
            pipeline.process_image(img)
        return

    # Automatische Pipeline
    pipeline = Pipeline(
        trellis_key=trellis_key,
        hf_token=hf_token,
        backend=args.backend,
        output_dir=args.output,
        resolution=args.resolution,
        decimation=args.decimation,
        texture_size=args.texture_size
    )

    if args.unit:
        if args.unit not in UNITS:
            print(f"❌ Unknown unit: {args.unit}")
            return
        pipeline.process_unit(args.unit)
    elif args.all:
        pipeline.process_all(delay=args.delay)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()

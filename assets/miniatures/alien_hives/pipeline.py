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
    """Generate 3D models using Hugging Face Space (KOSTENLOS!)."""

    def __init__(self):
        if not HAS_GRADIO:
            raise ImportError("❌ pip install gradio_client")

        print("🔗 Connecting to Hugging Face Space...")
        self.client = GradioClient("microsoft/TRELLIS.2")
        print("   ✅ Connected!")

    def generate(self, image_path: Path, output_dir: Path) -> Optional[Path]:
        """Convert image to 3D model via Hugging Face Space."""
        print(f"🔮 Converting to 3D (Hugging Face Space - FREE)...")

        try:
            # Step 1: Upload image and preprocess
            print("   📤 Uploading image...")
            preprocess_result = self.client.predict(
                image=handle_file(str(image_path)),
                api_name="/preprocess_image"
            )

            # Step 2: Generate 3D (returns multiple outputs)
            print("   ⏳ Generating 3D model (this may take 1-2 minutes)...")
            result = self.client.predict(
                seed=42,
                randomize_seed=True,
                ss_guidance_strength=7.5,
                ss_sampling_steps=12,
                slat_guidance_strength=3,
                slat_sampling_steps=12,
                api_name="/image_to_3d"
            )

            # Result contains: (seed, video_path, 3d_model_state)
            # We need to extract the GLB

            # Step 3: Extract GLB
            print("   📦 Extracting GLB...")
            glb_result = self.client.predict(
                mesh_simplify=0.95,
                texture_size=1024,
                api_name="/extract_glb"
            )

            # glb_result should be the path to the GLB file
            if glb_result and os.path.exists(glb_result):
                output_name = image_path.stem + ".glb"
                output_path = output_dir / "models" / output_name
                output_path.parent.mkdir(parents=True, exist_ok=True)

                # Copy GLB to output directory
                import shutil
                shutil.copy(glb_result, output_path)
                print(f"   ✅ 3D Model saved: {output_path}")
                return output_path
            else:
                print(f"   ❌ GLB extraction failed")
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
    """Complete Image → 3D Pipeline (100% FREE via Hugging Face!)."""

    def __init__(
        self,
        trellis_key: str = None,
        backend: Literal["huggingface", "replicate", "fal"] = "huggingface",
        output_dir: str = None,
        image_only: bool = False  # Skip image generation, only do 3D
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
            self.trellis = HuggingFaceTrellis()
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
  # Bild direkt zu 3D konvertieren (empfohlen!)
  python pipeline.py --image hive_lord.png

  # Mehrere Bilder konvertieren
  python pipeline.py --image bild1.png --image bild2.png

  # Automatische Pipeline (FLUX + Trellis)
  python pipeline.py --unit hive_lord
        """
    )

    # Image-to-3D Modus (empfohlen für Gemini-Bilder)
    parser.add_argument("--image", action="append", help="Bild zu 3D konvertieren (kann mehrfach verwendet werden)")

    # Automatische Pipeline
    parser.add_argument("--unit", help="Einheit automatisch generieren")
    parser.add_argument("--all", action="store_true", help="Alle Einheiten generieren")

    # Backend Optionen
    parser.add_argument("--replicate-key", help="Replicate API Token")
    parser.add_argument("--fal-key", help="fal.ai API Key")
    parser.add_argument("--backend", choices=["huggingface", "replicate", "fal"], default="huggingface")

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

    # Image-to-3D Modus
    if args.image:
        pipeline = Pipeline(
            trellis_key=trellis_key,
            backend=args.backend,
            output_dir=args.output,
            image_only=True  # Skip FLUX, only Trellis
        )
        for img in args.image:
            pipeline.process_image(img)
        return

    # Automatische Pipeline
    pipeline = Pipeline(
        trellis_key=trellis_key,
        backend=args.backend,
        output_dir=args.output
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

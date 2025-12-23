#!/usr/bin/env python3
"""
Simplified Image-to-3D Pipeline for OpenTTS
Only requires: pip install google-generativeai gradio_client
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

# Check dependencies
try:
    import google.generativeai as genai
except ImportError:
    print("❌ pip install google-generativeai")
    sys.exit(1)

try:
    from gradio_client import Client, handle_file
except ImportError:
    print("❌ pip install gradio_client")
    sys.exit(1)


PROMPT_TEMPLATE = """
{unit_name}, alien bioorganic creature for tabletop gaming.

COMPOSITION - CRITICAL:
- ONLY ONE single creature
- ONLY ONE viewing angle (3/4 isometric from front-left)
- NOT a character sheet, NOT a turnaround, NOT multiple views
- Single isolated render, centered in frame

CREATURE DESIGN:
{details}

COLOR PALETTE:
- Deep crimson red carapace and exoskeleton
- Bone white armor plates and horns
- Dark red muscle tissue visible between plates

STYLE:
- Inspiration: HR Giger xenomorph, Starship Troopers bugs, Zerg from Starcraft
- NOT Games Workshop / Tyranid designs

TECHNICAL:
- NO base, NO ground, NO pedestal, NO shadow on floor
- Pure white background (#FFFFFF)
- Full body visible
- Optimized for AI 3D model reconstruction
"""

UNITS = {
    "hive_lord": {
        "name": "Hive Lord",
        "details": """- Huge bipedal alien organism, 3 meters tall
- Crown of curved horns on elongated head
- Four arms: two massive scything claws, one with bio-cannon
- Powerful digitigrade legs
- Commanding stance, arms raised aggressively"""
    },
    "assault_grunt": {
        "name": "Assault Grunt",
        "details": """- Medium humanoid alien warrior
- Hunched aggressive posture
- Two arms with razor-sharp claws
- Armored carapace on back
- Running/charging pose"""
    },
    "carnivo_rex": {
        "name": "Carnivo-Rex",
        "details": """- Massive dinosaur-like alien predator
- Towering bipedal stance, T-Rex inspired
- Huge crushing jaws
- Small but deadly clawed arms
- Roaring pose"""
    }
}


def generate_image(gemini_key: str, unit_key: str, output_dir: Path) -> Path:
    """Generate image with Gemini."""
    print(f"🎨 Generating image for {UNITS[unit_key]['name']}...")

    genai.configure(api_key=gemini_key)
    model = genai.GenerativeModel("gemini-2.0-flash-exp")

    prompt = PROMPT_TEMPLATE.format(
        unit_name=UNITS[unit_key]["name"],
        details=UNITS[unit_key]["details"]
    )

    response = model.generate_content(prompt)

    # Extract image from response
    for part in response.candidates[0].content.parts:
        if hasattr(part, 'inline_data') and part.inline_data:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{unit_key}_{timestamp}.png"
            filepath = output_dir / "images" / filename
            filepath.parent.mkdir(parents=True, exist_ok=True)
            filepath.write_bytes(part.inline_data.data)
            print(f"   ✅ Image saved: {filepath}")
            return filepath

    raise Exception("No image in response")


def convert_to_3d(image_path: Path, output_dir: Path) -> Path:
    """Convert image to 3D using HuggingFace Space."""
    print(f"🔮 Converting to 3D (this may take 1-2 minutes)...")

    client = Client("microsoft/TRELLIS.2")

    # Step 1: Preprocess
    print("   📤 Uploading...")
    client.predict(
        image=handle_file(str(image_path)),
        api_name="/preprocess_image"
    )

    # Step 2: Generate 3D
    print("   ⏳ Generating 3D...")
    client.predict(
        seed=42,
        randomize_seed=True,
        ss_guidance_strength=7.5,
        ss_sampling_steps=12,
        slat_guidance_strength=3,
        slat_sampling_steps=12,
        api_name="/image_to_3d"
    )

    # Step 3: Extract GLB
    print("   📦 Extracting GLB...")
    glb_path = client.predict(
        mesh_simplify=0.95,
        texture_size=1024,
        api_name="/extract_glb"
    )

    if glb_path and os.path.exists(glb_path):
        import shutil
        output_name = image_path.stem + ".glb"
        output_path = output_dir / "models" / output_name
        output_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(glb_path, output_path)
        print(f"   ✅ 3D Model saved: {output_path}")
        return output_path

    raise Exception("GLB extraction failed")


def main():
    parser = argparse.ArgumentParser(description="Image-to-3D Pipeline")
    parser.add_argument("--gemini-key", required=True, help="Gemini API Key")
    parser.add_argument("--unit", required=True, choices=list(UNITS.keys()))
    parser.add_argument("--output", default=".", help="Output directory")
    args = parser.parse_args()

    output_dir = Path(args.output)

    print(f"\n{'='*50}")
    print(f"Processing: {UNITS[args.unit]['name']}")
    print(f"{'='*50}\n")

    # Step 1: Generate image
    image_path = generate_image(args.gemini_key, args.unit, output_dir)

    # Step 2: Convert to 3D
    model_path = convert_to_3d(image_path, output_dir)

    print(f"\n{'='*50}")
    print(f"✅ DONE!")
    print(f"   Image: {image_path}")
    print(f"   Model: {model_path}")
    print(f"{'='*50}\n")


if __name__ == "__main__":
    main()

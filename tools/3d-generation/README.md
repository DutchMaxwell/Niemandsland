# 3D Model Generation for OpenTTS

Generate 3D models from images using AI for your tabletop games.

## TripoSG (Recommended)

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/DutchMaxwell/openTTS/blob/main/tools/3d-generation/triposg_colab.ipynb)

**TripoSG** by VAST-AI-Research generates high-quality 3D models from single images.

### Quick Start

1. Click the "Open in Colab" badge above
2. Go to `Runtime > Change runtime type > GPU` (T4 recommended)
3. Run all cells in order
4. Upload your images to Google Drive (`MyDrive/OpenTTS_3D/input`)
5. Download generated `.glb` models from `MyDrive/OpenTTS_3D/output`

### Requirements

- Google account (for Colab)
- GPU runtime (free T4 works well)
- ~3-5 minutes per model

### Output Settings

| Quality | Faces | Use Case |
|---------|-------|----------|
| Low | 5,000 | Best for game performance |
| Medium | 10,000 | Good balance (default) |
| High | 20,000 | Detailed close-ups |

### Tips for Best Results

- **Clean background**: White or transparent works best
- **Single object**: One item per image
- **Good lighting**: Even, no harsh shadows
- **Clear silhouette**: Distinct edges help the AI

### Import to OpenTTS

1. Copy `.glb` files to your local machine
2. In OpenTTS: `Spawn > Import GLB`
3. Position and scale as needed
4. Use `L` key to lock terrain pieces

## License

- **TripoSG**: MIT License ([VAST-AI-Research/TripoSG](https://github.com/VAST-AI-Research/TripoSG))
- **This notebook**: MIT License (same as OpenTTS)

## Troubleshooting

**"No GPU detected"**
- Go to `Runtime > Change runtime type > GPU`

**Out of memory**
- Restart runtime: `Runtime > Restart runtime`
- Use lower face count (5000)

**Model looks wrong**
- Try a cleaner input image
- Ensure object is centered
- Remove complex backgrounds

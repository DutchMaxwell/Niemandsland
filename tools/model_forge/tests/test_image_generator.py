"""
Tests fuer den Image Generator.

Testet die Bildgenerierung mit gemockten API-Clients.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch, PropertyMock

import pytest

from image_generator import (
    ImageGenerator,
    ImageModel,
    GenerationResult,
    _extract_image_path,
    _extract_path_str,
)


# =============================================================================
# TEST: Leerer Prompt
# =============================================================================

class TestGenerateEmptyPrompt:
    """Leerer Prompt muss Fehler zurueckgeben."""

    def test_empty_string_fails(self, tmp_path: Path) -> None:
        generator = ImageGenerator(model=ImageModel.NANO_BANANA)
        result: GenerationResult = generator.generate("", tmp_path / "out.png")

        assert result.success is False
        assert "leer" in result.error.lower()

    def test_whitespace_only_fails(self, tmp_path: Path) -> None:
        generator = ImageGenerator(model=ImageModel.NANO_BANANA)
        result: GenerationResult = generator.generate("   ", tmp_path / "out.png")

        assert result.success is False
        assert "leer" in result.error.lower()


# =============================================================================
# TEST: Nano Banana Client-Typ
# =============================================================================

class TestNanoBananaClient:
    """NANO_BANANA muss den Gemini Client verwenden, nicht gradio_client."""

    @patch("image_generator.genai")
    def test_uses_gemini_client(self, mock_genai: MagicMock) -> None:
        mock_client = MagicMock()
        mock_genai.Client.return_value = mock_client

        generator = ImageGenerator(
            model=ImageModel.NANO_BANANA,
            gemini_api_key="test-key-123",
        )
        generator._ensure_client()

        mock_genai.Client.assert_called_once_with(api_key="test-key-123")
        assert generator._gemini_client is mock_client

    def test_missing_api_key_raises(self) -> None:
        generator = ImageGenerator(model=ImageModel.NANO_BANANA)

        with pytest.raises(ValueError, match="Gemini API Key"):
            generator._ensure_client()


# =============================================================================
# TEST: Nano Banana kein Seed-Support
# =============================================================================

class TestNanoBananaNoSeed:
    """Gemini bietet keine Seed-Reproduzierbarkeit — Seed im Result ist 0."""

    @patch("image_generator.genai")
    def test_seed_is_zero_in_result(
        self, mock_genai: MagicMock, tmp_path: Path
    ) -> None:
        # Mock: Gemini Client + Response mit inline_data
        mock_client = MagicMock()
        mock_genai.Client.return_value = mock_client

        # Simuliere eine Response mit einem Bild-Part
        png_bytes: bytes = _create_minimal_png()
        mock_part = MagicMock()
        mock_part.inline_data = MagicMock()
        mock_part.inline_data.mime_type = "image/png"
        mock_part.inline_data.data = png_bytes

        mock_response = MagicMock()
        mock_response.candidates = [MagicMock()]
        mock_response.candidates[0].content.parts = [mock_part]

        mock_client.models.generate_content.return_value = mock_response

        # Konfiguriere genai.types fuer GenerateContentConfig
        mock_genai.types.GenerateContentConfig.return_value = MagicMock()

        generator = ImageGenerator(
            model=ImageModel.NANO_BANANA,
            gemini_api_key="test-key",
        )

        output_path = tmp_path / "test_output.png"
        result: GenerationResult = generator.generate(
            prompt="A fierce warrior",
            output_path=output_path,
            seed=42,
        )

        assert result.success is True
        assert result.seed == 0
        assert result.model_used == "gemini-2.5-flash-image"


# =============================================================================
# TEST: _extract_image_path - Dict-Format
# =============================================================================

class TestExtractImagePathDict:
    """Gradio-Dict-Response wird korrekt zu einem Pfad aufgeloest."""

    def test_dict_with_path_key(self, tmp_path: Path) -> None:
        test_file = tmp_path / "image.png"
        test_file.write_bytes(b"fake png")

        result = _extract_image_path(({"path": str(test_file)}, 42))

        assert result is not None
        assert result == test_file

    def test_dict_without_path_key(self) -> None:
        result = _extract_image_path(({"url": "http://example.com"}, 42))

        assert result is None


# =============================================================================
# TEST: _extract_image_path - String-Format
# =============================================================================

class TestExtractImagePathString:
    """Gradio-String-Response wird korrekt zu einem Pfad aufgeloest."""

    def test_string_path_existing_file(self, tmp_path: Path) -> None:
        test_file = tmp_path / "image.png"
        test_file.write_bytes(b"fake png")

        result = _extract_image_path((str(test_file), 42))

        assert result is not None
        assert result == test_file

    def test_string_path_nonexistent_file(self) -> None:
        result = _extract_image_path(("/nonexistent/path.png", 42))

        assert result is None

    def test_none_result(self) -> None:
        result = _extract_image_path(None)

        assert result is None


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _create_minimal_png() -> bytes:
    """Erstellt minimale gueltige PNG-Bytes fuer Tests."""
    # PNG Signature + minimal IHDR + IEND
    import struct
    import zlib

    signature = b"\x89PNG\r\n\x1a\n"

    # IHDR: 1x1 pixel, 8-bit RGB
    ihdr_data = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    ihdr_crc = zlib.crc32(b"IHDR" + ihdr_data) & 0xFFFFFFFF
    ihdr = struct.pack(">I", 13) + b"IHDR" + ihdr_data + struct.pack(">I", ihdr_crc)

    # IDAT: minimal compressed data
    raw_data = zlib.compress(b"\x00\x00\x00\x00")
    idat_crc = zlib.crc32(b"IDAT" + raw_data) & 0xFFFFFFFF
    idat = struct.pack(">I", len(raw_data)) + b"IDAT" + raw_data + struct.pack(">I", idat_crc)

    # IEND
    iend_crc = zlib.crc32(b"IEND") & 0xFFFFFFFF
    iend = struct.pack(">I", 0) + b"IEND" + struct.pack(">I", iend_crc)

    return signature + ihdr + idat + iend

"""
Image Generator fuer Model Forge
=================================

Generiert Bilder ueber HuggingFace Spaces (gradio_client) oder die
Google Gemini API (google-genai). Unterstuetzt mehrere Modelle mit
unterschiedlichen API-Signaturen.
"""

from __future__ import annotations

import logging
import random
import shutil
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Callable

from google import genai
from gradio_client import Client


# =============================================================================
# KONSTANTEN
# =============================================================================

MAX_SEED: int = 2**31 - 1
FLUX_DEFAULT_WIDTH: int = 1024
FLUX_DEFAULT_HEIGHT: int = 1024
FLUX_DEFAULT_STEPS: int = 4

RETRY_MAX_ATTEMPTS: int = 3
RETRY_BASE_DELAY_SECONDS: float = 10.0

logger: logging.Logger = logging.getLogger(__name__)


# =============================================================================
# ENUMS
# =============================================================================

class ImageModel(str, Enum):
    """Verfuegbare Bildgenerierungs-Modelle."""

    NANO_BANANA = "gemini-2.5-flash-image"
    Z_IMAGE_TURBO = "mrfakename/Z-Image-Turbo"
    FLUX_SCHNELL = "black-forest-labs/FLUX.1-schnell"


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class GenerationResult:
    """Ergebnis einer Bildgenerierung."""

    success: bool
    image_path: str = ""
    seed: int = 0
    model_used: str = ""
    error: str = ""


# =============================================================================
# IMAGE GENERATOR
# =============================================================================

class ImageGenerator:
    """
    Generiert Bilder ueber HuggingFace Spaces.

    Verbindet sich lazy beim ersten Aufruf von generate().
    Unterstuetzt mehrere Modelle mit unterschiedlichen API-Signaturen.
    """

    def __init__(
        self,
        model: ImageModel = ImageModel.NANO_BANANA,
        hf_token: str | None = None,
        gemini_api_key: str | None = None,
    ) -> None:
        """
        Initialisiert den Generator ohne sofortige Verbindung.

        Args:
            model: Bildgenerierungs-Modell als ImageModel Enum.
            hf_token: Optionaler HuggingFace API Token fuer private Spaces.
            gemini_api_key: Optionaler Google Gemini API Key (fuer NANO_BANANA).
        """
        self._model: ImageModel = model
        self._hf_token: str | None = hf_token
        self._gemini_api_key: str | None = gemini_api_key
        self._client: Client | None = None
        self._gemini_client: genai.Client | None = None

    # =========================================================================
    # OEFFENTLICHE METHODEN
    # =========================================================================

    def generate(
        self,
        prompt: str,
        output_path: Path,
        seed: int = -1,
        width: int = 0,
        height: int = 0,
    ) -> GenerationResult:
        """
        Generiert ein einzelnes Bild aus einem Prompt.

        Args:
            prompt: Textbeschreibung fuer die Bildgenerierung.
            output_path: Zielpfad fuer das generierte Bild.
            seed: Seed fuer reproduzierbare Ergebnisse. -1 = zufaellig.
            width: Bildbreite in Pixel. 0 = Modell-Default (1024).
            height: Bildhoehe in Pixel. 0 = Modell-Default (1024).

        Returns:
            GenerationResult mit Erfolg/Fehler-Informationen.
        """
        if not prompt or not prompt.strip():
            return GenerationResult(
                success=False,
                model_used=self._model.value,
                error="Prompt darf nicht leer sein",
            )

        is_gemini: bool = self._model == ImageModel.NANO_BANANA

        # Gemini hat keinen Seed-Support
        if is_gemini:
            seed = 0
        elif seed == -1:
            seed = random.randint(0, MAX_SEED)

        try:
            self._ensure_client()
        except Exception as exc:
            error_prefix: str = (
                "Verbindung zur Gemini API fehlgeschlagen"
                if is_gemini
                else "Verbindung zu HuggingFace Space fehlgeschlagen"
            )
            return GenerationResult(
                success=False,
                seed=seed,
                model_used=self._model.value,
                error=f"{error_prefix}: {exc}",
            )

        effective_width: int = width if width > 0 else FLUX_DEFAULT_WIDTH
        effective_height: int = height if height > 0 else FLUX_DEFAULT_HEIGHT

        predict_method = self._get_predict_method()
        result_path: Path | None = None
        last_error: str = ""

        for attempt in range(RETRY_MAX_ATTEMPTS):
            try:
                result_path = predict_method(prompt, seed, effective_width, effective_height)
                last_error = ""
                break
            except RuntimeError as exc:
                last_error = f"Bildgenerierung fehlgeschlagen: {exc}"
                if attempt < RETRY_MAX_ATTEMPTS - 1:
                    delay: float = RETRY_BASE_DELAY_SECONDS * (attempt + 1)
                    logger.info(
                        "Fehler bei Versuch %d/%d, warte %.0fs: %s",
                        attempt + 1, RETRY_MAX_ATTEMPTS, delay, exc,
                    )
                    time.sleep(delay)
                    if is_gemini:
                        self._gemini_client = None
                    else:
                        self._client = None
                    self._ensure_client()
            except Exception as exc:
                return GenerationResult(
                    success=False,
                    seed=seed,
                    model_used=self._model.value,
                    error=f"Bildgenerierung fehlgeschlagen: {exc}",
                )

        if last_error:
            return GenerationResult(
                success=False,
                seed=seed,
                model_used=self._model.value,
                error=last_error,
            )

        if result_path is None:
            return GenerationResult(
                success=False,
                seed=seed,
                model_used=self._model.value,
                error="Kein Bild vom Modell zurueckgegeben",
            )

        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(result_path), str(output_path))
        except OSError as exc:
            return GenerationResult(
                success=False,
                seed=seed,
                model_used=self._model.value,
                error=f"Bild konnte nicht gespeichert werden: {exc}",
            )

        return GenerationResult(
            success=True,
            image_path=str(output_path),
            seed=seed,
            model_used=self._model.value,
        )

    def generate_batch(
        self,
        prompts: dict[str, str],
        output_dir: Path,
        progress_callback: Callable[[str, int, int], None] | None = None,
    ) -> dict[str, GenerationResult]:
        """
        Generiert Bilder fuer mehrere Einheiten sequentiell.

        Args:
            prompts: Dict von unit_key -> Prompt-Text.
            output_dir: Zielverzeichnis fuer generierte Bilder.
            progress_callback: Optionaler Callback(unit_key, index, total).

        Returns:
            Dict von unit_key -> GenerationResult.
        """
        results: dict[str, GenerationResult] = {}
        total: int = len(prompts)

        for index, (unit_key, prompt) in enumerate(prompts.items()):
            if progress_callback is not None:
                progress_callback(unit_key, index, total)

            output_path: Path = output_dir / f"{unit_key}.png"
            result: GenerationResult = self.generate(prompt, output_path)
            results[unit_key] = result

            if result.success:
                logger.info(
                    "Bild generiert: %s (Seed: %d)", unit_key, result.seed
                )
            else:
                logger.warning(
                    "Bildgenerierung fehlgeschlagen fuer %s: %s",
                    unit_key,
                    result.error,
                )

        return results

    # =========================================================================
    # PRIVATE METHODEN
    # =========================================================================

    def _ensure_client(self) -> None:
        """Stellt Lazy-Verbindung zum API-Backend her (Gemini oder HuggingFace)."""
        if self._model == ImageModel.NANO_BANANA:
            if self._gemini_client is not None:
                return
            if not self._gemini_api_key:
                raise ValueError(
                    "Gemini API Key erforderlich fuer NANO_BANANA. "
                    "Bitte in den Einstellungen hinterlegen."
                )
            logger.info("Verbinde zur Gemini API: %s", self._model.value)
            self._gemini_client = genai.Client(api_key=self._gemini_api_key)
            return

        if self._client is not None:
            return

        logger.info("Verbinde zu HuggingFace Space: %s", self._model.value)
        self._client = Client(self._model.value, token=self._hf_token)

    def _get_predict_method(self) -> Callable[[str, int, int, int], Path | None]:
        """Gibt die passende Predict-Methode fuer das aktuelle Modell zurueck."""
        predict_methods: dict[
            ImageModel, Callable[[str, int, int, int], Path | None]
        ] = {
            ImageModel.NANO_BANANA: self._predict_nano_banana,
            ImageModel.FLUX_SCHNELL: self._predict_flux_schnell,
            ImageModel.Z_IMAGE_TURBO: self._predict_z_image_turbo,
        }
        return predict_methods[self._model]

    def _predict_nano_banana(self, prompt: str, seed: int, width: int, height: int) -> Path | None:
        """
        Generiert ein Bild mit dem Gemini 2.5 Flash Image Modell (Nano Banana).

        Seed wird ignoriert — Gemini bietet keine Seed-Reproduzierbarkeit.
        Speichert das Bild direkt als PNG ueber PIL.

        Args:
            prompt: Textbeschreibung fuer die Bildgenerierung.
            seed: Wird ignoriert (Gemini hat keinen Seed-Support).
            width: Gewuenschte Bildbreite (Gemini beachtet das aus dem Prompt).
            height: Gewuenschte Bildhoehe (Gemini beachtet das aus dem Prompt).

        Returns:
            Pfad zum generierten Bild oder None bei Fehler.
        """
        if self._gemini_client is None:
            return None

        response = self._gemini_client.models.generate_content(
            model=self._model.value,
            contents=prompt,
            config=genai.types.GenerateContentConfig(
                response_modalities=["IMAGE", "TEXT"],
            ),
        )

        if not response.candidates:
            return None

        for part in response.candidates[0].content.parts:
            if part.inline_data is not None:
                import tempfile

                tmp_file = tempfile.NamedTemporaryFile(
                    suffix=".png", delete=False
                )
                tmp_file.write(part.inline_data.data)
                tmp_file.close()
                return Path(tmp_file.name)

        return None

    def _predict_z_image_turbo(self, prompt: str, seed: int, width: int, height: int) -> Path | None:
        """
        Generiert ein Bild mit dem Z-Image-Turbo Modell.

        Args:
            prompt: Textbeschreibung fuer die Bildgenerierung.
            seed: Seed fuer reproduzierbare Ergebnisse.
            width: Bildbreite in Pixel.
            height: Bildhoehe in Pixel.

        Returns:
            Pfad zum generierten Bild oder None bei Fehler.
        """
        if self._client is None:
            return None

        result = self._client.predict(
            prompt=prompt,
            seed=seed,
            randomize_seed=(seed == -1),
            height=height,
            width=width,
            num_inference_steps=9,
            api_name="/generate_image",
        )

        return _extract_image_path(result)

    def _predict_flux_schnell(self, prompt: str, seed: int, width: int, height: int) -> Path | None:
        """
        Generiert ein Bild mit dem FLUX.1-schnell Modell.

        Args:
            prompt: Textbeschreibung fuer die Bildgenerierung.
            seed: Seed fuer reproduzierbare Ergebnisse.
            width: Bildbreite in Pixel.
            height: Bildhoehe in Pixel.

        Returns:
            Pfad zum generierten Bild oder None bei Fehler.
        """
        if self._client is None:
            return None

        result = self._client.predict(
            prompt=prompt,
            seed=seed,
            randomize_seed=(seed == -1),
            width=width,
            height=height,
            num_inference_steps=FLUX_DEFAULT_STEPS,
            api_name="/infer",
        )

        return _extract_image_path(result)


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _extract_image_path(result: object) -> Path | None:
    """
    Extrahiert den Bildpfad aus dem Gradio-Ergebnis.

    Gradio gibt je nach Space und Client-Version unterschiedliche Formate zurueck:
    - Tuple (image_dict, seed) wobei image_dict = {"path": "...", ...}
    - Tuple (image_path_str, seed)
    - Direkt einen String-Pfad

    Args:
        result: Rueckgabewert von client.predict().

    Returns:
        Path zum generierten Bild oder None.
    """
    if result is None:
        return None

    first_element: object = result
    if isinstance(result, tuple) and len(result) >= 1:
        first_element = result[0]

    image_path_str: str = _extract_path_str(first_element)

    if not image_path_str:
        return None

    path: Path = Path(image_path_str)
    if path.exists():
        return path

    return None


def _extract_path_str(element: object) -> str:
    """Extrahiert einen Pfad-String aus einem Gradio-Ergebnis-Element.

    Args:
        element: Ein einzelnes Element (dict mit 'path', str, oder anderes).

    Returns:
        Pfad als String oder leerer String.
    """
    if isinstance(element, dict):
        return str(element.get("path", ""))
    if isinstance(element, str):
        return element
    return ""

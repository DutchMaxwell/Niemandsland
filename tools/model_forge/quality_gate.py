"""
Quality Gate fuer Model Forge
==============================

Visions-basierte Qualitaetspruefung fuer generierte Mini-Bilder.
Nutzt Gemini Vision (gemini-2.5-flash) um jedes Bild gegen folgende Kriterien
zu pruefen:

1. Technische Anforderungen:
   - Single centered miniature, full body visible
   - White or near-white background
   - No base, pedestal, or ground plane
   - Pose and feature consistency mit Unit-Beschreibung

2. IP-Compliance (Games Workshop):
   - Keine Aquila / Doppelkopf-Adler
   - Keine Skull-Cog / Skull-Gear-Symbole
   - Keine charakteristischen Space-Marine-Pauldrons
   - Keine Custodes-style Goldhelme
   - Keine spezifischen GW Charakter-Likenesses

Antwort als strukturiertes JSON, damit ein Caller (z.B. batch_generate)
deterministisch entscheiden kann: PASS / FAIL / RE-ROLL.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from google import genai
from google.genai import types as genai_types


# =============================================================================
# KONSTANTEN
# =============================================================================

DEFAULT_VISION_MODEL: str = "gemini-2.5-flash"

# Maximale Antwort-Tokens. Bei Gemini 2.5 deckt dieser Wert sowohl Thinking
# als auch Answer ab — daher grosszuegig: 2048 Token mit thinking_budget=0
# laesst die JSON-Antwort garantiert durch.
MAX_OUTPUT_TOKENS: int = 2048

logger: logging.Logger = logging.getLogger(__name__)


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class QualityResult:
    """Ergebnis einer Quality-Gate-Pruefung."""

    passed: bool
    technical_issues: list[str] = field(default_factory=list)
    ip_concerns: list[str] = field(default_factory=list)
    overall_assessment: str = ""
    raw_response: str = ""
    error: str = ""

    @property
    def has_ip_concern(self) -> bool:
        """True wenn das Vision-LLM mindestens ein IP-Problem flaggt."""
        return len(self.ip_concerns) > 0


# =============================================================================
# QUALITY GATE
# =============================================================================

class QualityGate:
    """
    Prueft generierte Mini-Bilder mit Gemini Vision auf Qualitaet + IP-Compliance.
    """

    def __init__(
        self,
        gemini_api_key: str,
        model_name: str = DEFAULT_VISION_MODEL,
    ) -> None:
        """
        Initialisiert das Gate.

        Args:
            gemini_api_key: Google Gemini API Key (gleicher wie image_generator).
            model_name: Vision-Modell (Default gemini-2.5-flash).
        """
        if not gemini_api_key:
            raise ValueError("Gemini API Key erforderlich fuer QualityGate")
        # 180s per-request timeout so a hung check fails instead of freezing the run.
        self._client: genai.Client = genai.Client(
            api_key=gemini_api_key, http_options=genai.types.HttpOptions(timeout=180000)
        )
        self._model_name: str = model_name
        # Strict-IP profile (set per faction). For human-power-armour factions the
        # lenient "armoured figure = fine" whitelist is dangerous (the whole design
        # reads as a specific commercial range), so strict mode flags substantial
        # similarity + requires the faction's own signature cues to be present.
        self._strict_ip: bool = False
        self._signature_cues: list[str] = []

    def set_ip_profile(self, strict: bool, signature_cues: list[str] | None = None) -> None:
        """Configure faction-specific IP strictness. Call once per faction run."""
        self._strict_ip = bool(strict)
        self._signature_cues = list(signature_cues or [])

    # =========================================================================
    # OEFFENTLICHE METHODEN
    # =========================================================================

    def check_image(
        self,
        image_path: Path,
        unit_name: str,
        faction_name: str,
        unit_description: str = "",
    ) -> QualityResult:
        """
        Prueft ein generiertes Mini-Bild.

        Args:
            image_path: Pfad zum generierten PNG/WebP.
            unit_name: Erwarteter Unit-Name (z.B. "Prime Warrior").
            faction_name: Fraktionsname (z.B. "Alien Hives") fuer Kontext.
            unit_description: Optionale erweiterte Beschreibung dessen, was
                erwartet wird (z.B. das extra_details aus der YAML).

        Returns:
            QualityResult mit PASS/FAIL plus Liste von Problemen.
        """
        if not image_path.exists():
            return QualityResult(
                passed=False,
                error=f"Bild nicht gefunden: {image_path}",
            )

        try:
            image_bytes: bytes = image_path.read_bytes()
        except OSError as exc:
            return QualityResult(
                passed=False,
                error=f"Bild konnte nicht gelesen werden: {exc}",
            )

        prompt: str = self._build_check_prompt(unit_name, faction_name, unit_description)
        mime_type: str = _guess_mime(image_path)

        try:
            response = self._client.models.generate_content(
                model=self._model_name,
                contents=[
                    genai_types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                    prompt,
                ],
                config=genai_types.GenerateContentConfig(
                    response_mime_type="application/json",
                    max_output_tokens=MAX_OUTPUT_TOKENS,
                    temperature=0.0,
                    # Thinking deaktivieren: Quality-Gate ist eine
                    # deterministische JSON-Klassifikation, kein Reasoning.
                    # Sonst frisst Thinking ~980 Tokens und die Answer wird
                    # mid-string truncated (FinishReason MAX_TOKENS).
                    thinking_config=genai_types.ThinkingConfig(thinking_budget=0),
                ),
            )
        except Exception as exc:  # pragma: no cover - API failures
            logger.warning("Vision-Call fehlgeschlagen: %s", exc)
            return QualityResult(
                passed=False,
                error=f"Vision-Call fehlgeschlagen: {exc}",
            )

        raw_text: str = _extract_response_text(response)
        result = _parse_response(raw_text)
        if result.error and "nicht parsebar" in result.error:
            # Dump fuer Debug — wir sehen sonst nicht, was das Vision-LLM
            # wirklich zurueckschickt.
            try:
                debug_path = Path("/tmp") / f"quality_gate_raw_{image_path.stem}.txt"
                debug_path.write_text(raw_text or "(leer)")
                # Plus: Voller Response-Dump (parts, finish_reason, safety_ratings)
                full_dump_path = Path("/tmp") / f"quality_gate_full_{image_path.stem}.txt"
                full_dump_path.write_text(_response_debug_dump(response))
                logger.warning(
                    "Raw-Response dumped: %s + %s", debug_path, full_dump_path
                )
            except OSError:
                pass
        return result

    # =========================================================================
    # PROMPT-AUFBAU
    # =========================================================================

    def _ip_block(self) -> str:
        """IP-violation section of the check prompt — lenient by default, strict per faction."""
        if not self._strict_ip:
            return (
                'B) HARD GW IP VIOLATIONS (only flag if a GW-specific visual mark is literally,\n'
                '   unambiguously present — not "reminds me of" or "evokes"):\n'
                '   - Double-headed eagle (Aquila), skull-and-cog, winged-skull insignia, or a named\n'
                '     GW character likeness (Calgar, Ghazghkull, Abaddon, Guilliman, etc.).\n'
                '   GENERIC GENRE ARCHETYPES ARE ALWAYS FINE — even if "kind of like" GW: an armoured\n'
                '   figure with shoulder pads (not "Space Marine"), a battlesuit (not "Tau"), an insectoid\n'
                '   (not "Tyranid"), a skeletal robot (not "Necron"), a pointy-helmed elf (not "Eldar"),\n'
                '   a golden guardian (not "Custodes"). Resemblance to a faction\'s general aesthetic is NOT\n'
                '   a violation. Only flag a literal copyrighted symbol or named-character likeness.'
            )
        cues = "; ".join(self._signature_cues) if self._signature_cues else \
            "the faction's own distinctive original cues"
        return (
            'B) IP VIOLATIONS — STRICT MODE (this is a human heavy-power-armour faction, the single most\n'
            '   IP-sensitive archetype: armoured super-soldiers read 1:1 as a specific commercial\n'
            "   miniatures range unless they are clearly the faction's OWN original design). FLAG\n"
            '   ip_concerns if ANY apply:\n'
            '   - Any literal GW mark/character (double-eagle Aquila, skull-and-cog, winged skull, named\n'
            '     character likeness).\n'
            '   - Trade-dress of a specific commercial power-armour range rather than an original design:\n'
            '     big round dinner-plate shoulder pauldrons, a boxy magazine-fed bolter-style rifle,\n'
            '     skull/eagle/halo/purity-seal iconography, or a generic "space-marine" silhouette with\n'
            '     no distinguishing original features.\n'
            '   - "Chaos"/grimdark drift: spikes, horns, daemonic skulls, spiked trim, dark corrupted\n'
            '     menace. This faction is CLEAN and NOBLE, never spiky/daemonic.\n'
            "   - HUMANOID figures (infantry, heroes) MUST clearly show the faction's required original\n"
            "     cues: " + cues + ". A humanoid that lacks these and just looks like a generic armoured\n"
            "     space marine -> FLAG.\n"
            '   - VEHICLES / aircraft / walkers / mounts (no humanoid body) do NOT need the helmet/\n'
            '     shoulder/crest cues — pass them if they are a clearly ORIGINAL design and NOT a 1:1 copy\n'
            '     of a specific commercial vehicle or mech; flag only a literal mark or an unmistakable copy.\n'
            '   IMPORTANT: for IP in this strict faction, do NOT apply the "when in doubt PASS" rule —\n'
            '   if unsure whether it reads as a generic commercial space-marine vs a clearly original\n'
            '   design, treat that as a FAIL and list the reason in ip_concerns. A clean, original,\n'
            '   non-spiky design that clearly shows the required cues PASSES.'
        )

    def _build_check_prompt(
        self,
        unit_name: str,
        faction_name: str,
        unit_description: str,
    ) -> str:
        """Baut den Check-Prompt fuer das Vision-LLM."""
        desc_block: str = (
            f"\nThe miniature is described as: {unit_description}\n"
            if unit_description
            else ""
        )

        ip_block: str = self._ip_block()
        return f"""You are a quality control reviewer for AI-generated tabletop wargaming miniature concept images. Evaluate the attached image.

EXPECTED CONTENT (CONTEXT ONLY, NOT a checklist):
- Unit: {unit_name}
- Faction: {faction_name}
{desc_block}

The unit description is loose creative context, NOT a strict checklist.
AI image generators will never reproduce every prop, count, or color exactly.
Do NOT flag mismatches like "described 2 weapons but shows 1", "skin is tan
not blue", "knife is on leg not belt", "no visible visor". Those are FINE.

Evaluate ONLY these dimensions:

A) HARD TECHNICAL FAILURES (only flag if blatantly wrong):
   - Multiple miniatures fused or stacked into one figure (2+ heads, 2+ torsos)
   - Image clearly cropped (head or feet cut off)
   - Background is a BUSY SCENE (terrain, sky, room, landscape filling the frame)
   - Severe AI artifacts (melted face, extra limbs sprouting from torso, missing
     limbs, garbled hands with 7 fingers, etc.)
   Do NOT flag: pose variations, weapon-count differences, color shifts,
   extra/missing accessories, alternative interpretations of the description.
   Do NOT flag a small base, pedestal, ground patch, contact shadow or near-white
   backdrop — those are removed automatically after generation (deshadow + base edit).

{ip_block}

Respond ONLY with strict JSON in this exact schema:

{{
  "passed": <true|false>,
  "technical_issues": ["concrete hard failure 1", ...],
  "ip_concerns": ["literal GW symbol/character seen 1", ...],
  "overall_assessment": "one short sentence summary"
}}

RULES:
- Default to PASS. Only fail if a hard criterion above is clearly violated.
- `passed` must be `true` if BOTH technical_issues AND ip_concerns are empty.
- If `passed` is `false`, you MUST list at least one concrete item in
  technical_issues OR ip_concerns. Empty lists with passed=false is invalid.
- `overall_assessment` is one short sentence summarizing the verdict.
- When in doubt, PASS. Prefer false-negatives over false-positives.
"""


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _guess_mime(path: Path) -> str:
    """Mappt Bildendung auf MIME-Typ."""
    suffix: str = path.suffix.lower()
    return {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
    }.get(suffix, "image/png")


def _response_debug_dump(response: Any) -> str:
    """Dump aller wichtigen Response-Felder fuer Truncation-Diagnose."""
    if response is None:
        return "(response is None)"
    lines: list[str] = []
    candidates = getattr(response, "candidates", None) or []
    lines.append(f"num_candidates={len(candidates)}")
    for i, cand in enumerate(candidates):
        lines.append(f"--- candidate[{i}] ---")
        lines.append(f"finish_reason={getattr(cand, 'finish_reason', None)!r}")
        lines.append(f"safety_ratings={getattr(cand, 'safety_ratings', None)!r}")
        content = getattr(cand, "content", None)
        if content is None:
            lines.append("content=None")
            continue
        parts = getattr(content, "parts", None) or []
        lines.append(f"num_parts={len(parts)}")
        for j, part in enumerate(parts):
            text = getattr(part, "text", None)
            thought = getattr(part, "thought", None)
            lines.append(f"  part[{j}] thought={thought!r} len(text)={len(text) if text else 0}")
            if text:
                lines.append(f"    text={text!r}")
    usage = getattr(response, "usage_metadata", None)
    if usage is not None:
        lines.append(f"usage_metadata={usage!r}")
    return "\n".join(lines)


def _extract_response_text(response: Any) -> str:
    """Extrahiert den Text-Content aus einer Gemini-Response."""
    if response is None:
        return ""
    candidates = getattr(response, "candidates", None)
    if not candidates:
        return ""
    content = getattr(candidates[0], "content", None)
    if content is None:
        return ""
    parts = getattr(content, "parts", None)
    if not parts:
        return ""
    text_pieces: list[str] = []
    for part in parts:
        text = getattr(part, "text", None)
        if text:
            text_pieces.append(text)
    return "\n".join(text_pieces)


def _parse_response(raw_text: str) -> QualityResult:
    """
    Parst die JSON-Antwort des Vision-LLM zu einem QualityResult.

    Falls das LLM trotz JSON-Mode mal Markdown-Fences einbaut, werden die
    entfernt; bei totalem Parse-Fehler wird konservativ FAIL zurueckgegeben.
    """
    if not raw_text:
        return QualityResult(
            passed=False,
            error="Leere Vision-Response",
            raw_response=raw_text,
        )

    cleaned: str = _strip_code_fences(raw_text).strip()

    try:
        data: dict[str, Any] = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        return QualityResult(
            passed=False,
            error=f"Vision-Response nicht parsebar: {exc}",
            raw_response=raw_text,
        )

    technical_issues_raw = data.get("technical_issues", [])
    ip_concerns_raw = data.get("ip_concerns", [])
    technical_issues: list[str] = (
        [str(x) for x in technical_issues_raw]
        if isinstance(technical_issues_raw, list)
        else []
    )
    ip_concerns: list[str] = (
        [str(x) for x in ip_concerns_raw]
        if isinstance(ip_concerns_raw, list)
        else []
    )

    passed_flag: bool = bool(data.get("passed", False))
    # Sicherheitsnetz: passed darf nur true sein, wenn keine Issues
    if technical_issues or ip_concerns:
        passed_flag = False

    return QualityResult(
        passed=passed_flag,
        technical_issues=technical_issues,
        ip_concerns=ip_concerns,
        overall_assessment=str(data.get("overall_assessment", "")),
        raw_response=raw_text,
    )


def _strip_code_fences(text: str) -> str:
    """Entfernt Markdown-Code-Fences, falls vorhanden."""
    fence_match = re.match(
        r"^\s*```(?:json|JSON)?\s*\n(.*?)\n```\s*$",
        text,
        flags=re.DOTALL,
    )
    if fence_match:
        return fence_match.group(1)
    return text

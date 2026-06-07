"""
Prompt Engine fuer Model Forge
==============================

Generiert Image-Prompts fuer 3D-Modell-Erstellung basierend auf
OPR-Einheitsdaten und Design Language YAML-Dateien.

Jede Fraktion hat eine YAML-Datei die Aesthetik, Farben, Materialien
und einen Prompt-Template definiert. Die Engine kombiniert diese mit
konkreten Einheitsdaten (Waffen, Spezialregeln, Groesse) zu einem
vollstaendigen Bild-Prompt.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any

import yaml

from opr_client import OPRArmy, OPRUnit, OPRWeapon


# =============================================================================
# KONSTANTEN
# =============================================================================

MELEE_RANGE: int = 0

TOUGH_MASSIVE_THRESHOLD: int = 6
TOUGH_STURDY_THRESHOLD: int = 3

# Schwellenwert fuer Base-Groesse ab der ein Modell als Fahrzeug gilt
VEHICLE_BASE_THRESHOLD_MM: int = 50

# =============================================================================
# IP-COMPLIANCE
# =============================================================================
# Wird zu jedem Prompt hinzugefuegt, unabhaengig vom Faction-YAML — das
# Sicherheitsnetz fuer originale, CC-BY-SA-faehige Designs.
#
# WICHTIG (Lektion aus der Hero-Iteration): Text-to-Image-Modelle koennen nicht
# negieren. Konkrete IP-Begriffe ("Aquila", "Space Marine", "Necron" …) im
# Prompt zu NENNEN — selbst um sie zu VERMEIDEN — verankert sie und produziert
# genau diese Elemente. Darum ist dieser Block REIN POSITIV formuliert: er
# fordert Originalitaet, ohne ein einziges geschuetztes Design beim Namen zu
# nennen. Die distinktiven Merkmale kommen aus den positiven SPECIFIC DETAILS /
# STYLE / original_design_cues der jeweiligen Faction.

IP_COMPLIANCE_BLOCK: str = (
    "ORIGINAL DESIGN MANDATE - this is a wholly original miniature:\n"
    "- Render ONLY the design described in the SPECIFIC DETAILS and STYLE sections; take every "
    "distinctive element (armour shapes, insignia, weapons, silhouette) from there\n"
    "- Keep all emblems, badges and heraldry ORIGINAL and abstract: simple geometric shapes "
    "(chevrons, hexagons, bars, original runes) unique to this faction\n"
    "- Use broad, generic genre archetypes only (knight, soldier, alien insect, orc, undead, "
    "robot, daemon) as the starting point, then make every specific detail original\n"
    "- Clean, distinctive, original shapes that read as this faction's own identity"
)

# Type-spezifische Form-Constraints: werden nur eingehaengt wenn die Unit ein
# explizites `type:`-Feld hat, das hier gemappt ist. Verhindert dass Aircraft
# als Suit-mit-Fluegeln rendern (Galerie-Review 2026-05-15 von dao_union zeigte
# Razor Fighter/Sun Bomber als Battlesuit-Hybride). Walker/Titan-Eintraege
# liegen praeventiv bereit, sind aktuell aber noch nicht aktiv getunte
# Problemstellen — bei Bedarf hier einkommentieren/aktivieren.
FORM_CONSTRAINTS: dict[str, str] = {
    "aircraft": (
        "AIRCRAFT FORM CONSTRAINT - render as a vehicle, NOT a mech or suit:\n"
        "- Single aerodynamic fuselage with swept wings or lifting body, "
        "purely vehicle silhouette\n"
        "- NO humanoid body, NO bipedal legs, NO arms — the airframe is the entire model\n"
        "- NOT a battlesuit, NOT a mech-with-wings, NOT a flying suit of armor\n"
        "- Cockpit canopy or pilot housing instead of a head/helmet\n"
        "- Wings are aircraft wings, not jet-pack or shoulder-mounted thrusters\n"
        "- Reference shape: a real fighter jet, atmospheric interceptor or ground-attack "
        "craft — a pure aircraft airframe"
    ),
    "vehicle": (
        "VEHICLE FORM CONSTRAINT - render as a ground vehicle, NOT a humanoid or suit:\n"
        "- A wheeled, tracked or hover ground vehicle (tank, transport, bike, buggy); the hull is "
        "the entire model\n"
        "- NO humanoid body, NO helmeted head, NO bipedal legs, NO arms or hand-held weapons\n"
        "- Weapons are hull- or turret-mounted, never carried by hands\n"
        "- A crew hatch / cockpit instead of a head — reference shape: a real armoured fighting vehicle"
    ),
    "walker": (
        "WALKER / MECH FORM CONSTRAINT - render as a piloted machine, NOT an infantry soldier:\n"
        "- A large mechanical walker / battlesuit on stout mechanical legs, clearly bigger than infantry\n"
        "- A cockpit or sensor head, NOT a humanoid face or a soldier's helmet; vehicle-scale armour panels\n"
        "- Heavy hardpoint weapons on the chassis / arms, not hand-held rifles\n"
        "- Reads as a machine, never a person in power armour"
    ),
    "titan": (
        "TITAN FORM CONSTRAINT - render as a colossal war-engine:\n"
        "- A towering, massive walking war-machine, vastly larger than infantry, heavy industrial build\n"
        "- Building-scale weapon hardpoints; a command bridge / sensor head, not a humanoid face\n"
        "- Clearly a giant machine, never an infantry-scale figure"
    ),
}

# Unit types whose silhouette is NOT a human figure. For these the infantry-style original cues
# (helmet/shoulders/crest/hand-held weapon) are NOT injected into the prompt — they would force an
# infantry render — and the FORM_CONSTRAINTS above carry the silhouette instead.
_NON_HUMANOID_TYPES: frozenset = frozenset({"vehicle", "aircraft", "walker", "titan", "monster", "mount"})


# Verhindert dass das Bildmodell Tokens wie "Impact(3)", "Tough(6)", "AP(1)",
# "18 inch range" als sichtbare Stat-Block-Annotationen aufs Bild brennt.
NO_TEXT_BLOCK: str = (
    "STRICT RENDERING RULES - THE IMAGE ITSELF MUST CONTAIN NO TEXT:\n"
    "- DO NOT render any letters, words, numbers, captions, labels, callouts, "
    "stat blocks, rule names, weapon names, range indicators, or annotations "
    "anywhere in the image\n"
    "- DO NOT add UI overlays, badges, ribbons, tooltips, arrows pointing to parts, "
    "measurement scales, or watermarks\n"
    "- Tokens like 'Impact(3)', 'Tough(6)', 'AP(1)', '18 inch', 'A4', 'Blast(3)' "
    "appear in this prompt only as gameplay context for the pose and silhouette - "
    "they must NEVER appear visibly in the rendered image\n"
    "- Pure clean miniature photography output, nothing else"
)

# =============================================================================
# ENUMS
# =============================================================================

class UnitPoseType(str, Enum):
    """Posen-Typ einer Einheit fuer die Bildgenerierung."""

    INFANTRY = "infantry"
    JUMPPACK = "jumppack"
    AIRCRAFT = "aircraft"
    VEHICLE = "vehicle"


# Mapping von UnitPoseType zu Pose-Beschreibungen fuer Image-Prompts
POSE_DESCRIPTIONS: dict[UnitPoseType, str] = {
    UnitPoseType.INFANTRY: "dynamic predatory creature stance, crouched and coiled to strike, weight on digitigrade legs, OnePageRules studio miniature hero pose",
    UnitPoseType.JUMPPACK: "dynamic leaping pose, slightly airborne, jump pack or wings propelling upward",
    UnitPoseType.AIRCRAFT: "flying through the air, dynamic flight pose, seen from slightly below",
    UnitPoseType.VEHICLE: "vehicle with no crew visible, mechanical/armored design, ground-level perspective",
}


# =============================================================================
# REGELBASIERTE KONSTANTEN
# =============================================================================

# Mapping von OPR-Regelnamen zu visuellen Beschreibungen fuer Image-Prompts
RULE_VISUAL_HINTS: dict[str, str] = {
    "Flying": "large wings, aerial pose",
    "Fast": "agile muscular body, dynamic running pose",
    "Scout": "stealthy, crouched pose",
    "Stealth": "shadowy, dark coloring, blending with shadows",
    "Ambush": "emerging from concealment",
    "Slow": "lumbering, heavy build",
    "Aircraft": "flying, large wings or jet propulsion",
    "Regeneration": "regenerating flesh, healing tissue visible",
}

# Regeln die einen numerischen Parameter haben und spezielle Logik brauchen
PARAMETERIZED_RULES: frozenset[str] = frozenset({
    "Tough",
    "Caster",
    "Fear",
    "Transport",
})


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class DesignLanguage:
    """Design Language einer Fraktion, geladen aus YAML.

    Definiert die visuelle Identitaet einer Fraktion: Aesthetik,
    Farbschema, Materialien, Kreaturtyp und Prompt-Template.
    Unit Overrides erlauben Anpassungen pro Einheitstyp.
    """

    faction_name: str
    aesthetic: dict[str, Any]  # genre, style, inspiration, explicitly_avoid
    colors: dict[str, str]     # primary, secondary, accent
    materials: list[str]
    creature_type: str
    prompt_template: str
    unit_overrides: dict[str, dict[str, Any]]  # unit_key -> {extra_details, pose, game_stats}


# =============================================================================
# YAML LADEN
# =============================================================================

def load_design_language(yaml_path: Path) -> DesignLanguage:
    """Laedt eine Design Language aus einer YAML-Datei.

    Args:
        yaml_path: Pfad zur YAML-Datei.

    Returns:
        DesignLanguage Objekt mit allen Fraktionsdaten.

    Raises:
        FileNotFoundError: Wenn die YAML-Datei nicht existiert.
        ValueError: Wenn erforderliche Felder fehlen.
        yaml.YAMLError: Bei ungueltigem YAML-Format.
    """
    if not yaml_path.exists():
        raise FileNotFoundError(f"Design Language nicht gefunden: {yaml_path}")

    with open(yaml_path, "r", encoding="utf-8") as f:
        data: dict[str, Any] = yaml.safe_load(f)

    if data is None:
        raise ValueError(f"Leere YAML-Datei: {yaml_path}")

    _validate_required_fields(data, yaml_path)

    aesthetic: dict[str, Any] = data.get("aesthetic", {})
    colors: dict[str, str] = data.get("colors", {})
    materials_raw: Any = data.get("materials", [])
    materials: list[str] = materials_raw if isinstance(materials_raw, list) else []
    unit_overrides_raw: Any = data.get("unit_overrides", {})
    unit_overrides: dict[str, dict[str, Any]] = (
        unit_overrides_raw if isinstance(unit_overrides_raw, dict) else {}
    )

    return DesignLanguage(
        faction_name=str(data.get("faction_name", "")),
        aesthetic=aesthetic,
        colors=colors,
        materials=materials,
        creature_type=str(data.get("creature_type", "")),
        prompt_template=str(data.get("prompt_template", "")),
        unit_overrides=unit_overrides,
    )


def _validate_required_fields(data: dict[str, Any], yaml_path: Path) -> None:
    """Validiert dass alle erforderlichen Felder in der YAML-Datei vorhanden sind.

    Raises:
        ValueError: Wenn ein erforderliches Feld fehlt.
    """
    required_fields: list[str] = [
        "faction_name",
        "aesthetic",
        "colors",
        "materials",
        "creature_type",
        "prompt_template",
    ]
    missing: list[str] = [
        field_name for field_name in required_fields
        if field_name not in data or data[field_name] is None
    ]
    if missing:
        raise ValueError(
            f"Fehlende Felder in {yaml_path}: {', '.join(missing)}"
        )


# =============================================================================
# PROMPT ENGINE
# =============================================================================

class PromptEngine:
    """Generiert Image-Prompts aus OPR-Einheitsdaten und Design Language.

    Kombiniert die visuelle Identitaet einer Fraktion (aus YAML) mit
    konkreten Einheitsdaten (Waffen, Regeln, Groesse) zu einem
    vollstaendigen Prompt fuer Bild-/3D-Generierung.
    """

    def __init__(self, design_language: DesignLanguage) -> None:
        """Initialisiert die Engine mit einer Design Language.

        Args:
            design_language: Fraktions-Designsprache aus YAML.
        """
        self._design_language: DesignLanguage = design_language

    # =========================================================================
    # OEFFENTLICHE METHODEN
    # =========================================================================

    def generate_prompt(
        self,
        unit_name: str,
        unit_key: str,
        weapons: list[OPRWeapon],
        special_rules: list[str],
        size: int,
        base_size: int = 32,
    ) -> str:
        """Generiert einen vollstaendigen Image-Prompt fuer eine Einheit.

        Substituiert Platzhalter im Prompt-Template der Design Language
        mit konkreten Einheitsdaten. Kombiniert Waffenbeschreibungen,
        visuelle Hints aus Spezialregeln und optionale Unit Overrides.

        Die Pose wird automatisch anhand der Spezialregeln und Base-Groesse
        bestimmt. Unit Overrides koennen den Typ oder die Pose explizit
        ueberschreiben.

        Args:
            unit_name: Anzeigename der Einheit (z.B. "Hive Warriors").
            unit_key: Schluessel fuer Unit Overrides (z.B. "hive_warriors").
            weapons: Liste der OPRWeapon-Objekte der Einheit.
            special_rules: Liste der Spezialregeln als Strings.
            size: Anzahl Modelle in der Einheit.
            base_size: Groesste Base-Dimension in mm (fuer Fahrzeug-Heuristik).

        Returns:
            Fertiger Prompt-String fuer Image-Generierung.
        """
        dl: DesignLanguage = self._design_language

        weapons_desc: str = self._weapons_to_description(weapons)
        visual_hints: str = self._rules_to_visual_hints(special_rules)

        # Unit Overrides laden
        override: dict[str, str] | None = dl.unit_overrides.get(unit_key)

        # Pose bestimmen: Override-Typ > Override-Pose > Heuristik
        override_type: str | None = override.get("type") if override else None
        override_pose: str = override.get("pose", "") if override else ""

        pose_desc: str
        if override_pose:
            pose_desc = override_pose
        else:
            pose_desc = _determine_pose(special_rules, base_size, override_type)

        # Pose als erstes Detail einfuegen
        unit_details_parts: list[str] = [pose_desc]

        if weapons_desc:
            unit_details_parts.append(weapons_desc)
        if visual_hints:
            unit_details_parts.append(visual_hints)

        # Unit Override extra_details anwenden
        if override is not None:
            extra_details: str = override.get("extra_details", "")
            if extra_details:
                unit_details_parts.append(extra_details)

        # Tabletop units are represented by a SINGLE sculpt (the game places the rest of
        # the squad), so a multi-model squad must still render as exactly one figure —
        # otherwise the single-mini quality gate rejects it.
        # Shape the look from the unit's stats: Tough -> bulk/scale (from rules),
        # defense -> how armored, quality -> how elite. Faction-neutral wording.
        stat_bits: list[str] = []
        _tough = 0
        for _r in special_rules:
            _m = re.match(r"Tough\((\d+)\)", str(_r))
            if _m:
                _tough = int(_m.group(1))

        # EXPLICIT SCALE ANCHOR from base size + Tough. Without this, small rank-and-file
        # units (e.g. 25mm grunts, no Tough) drift large. The base diameter is the single
        # strongest real-world size cue, so state it and the matching body class outright.
        if _tough >= 12:
            stat_bits.append(
                f"SCALE: a huge monster centre-piece model on a {base_size}mm base, "
                "towering many times the height of a normal soldier")
        elif _tough >= 6:
            stat_bits.append(
                f"SCALE: a large beast on a {base_size}mm base, clearly bigger and "
                "bulkier than a rank-and-file soldier but not a giant monster")
        elif _tough >= 3:
            stat_bits.append(
                f"SCALE: an elite-sized creature on a {base_size}mm base, only "
                "slightly larger than a standard soldier")
        else:
            stat_bits.append(
                f"SCALE: a small standard rank-and-file creature on a {base_size}mm "
                "base, roughly human-soldier sized, lean and NOT oversized or bulky")

        _gs = (override or {}).get("game_stats", {}) or {}
        _dfn = _gs.get("defense")
        if isinstance(_dfn, int):
            if _dfn <= 3:
                stat_bits.append("heavily armored with thick layered plating")
            elif _dfn >= 5:
                stat_bits.append("lightly armored and agile, exposed body")
        _qual = _gs.get("quality")
        if isinstance(_qual, int):
            if _qual <= 3:
                stat_bits.append("elite apex specimen, refined and distinctive")
            elif _qual >= 5:
                stat_bits.append("crude, expendable, primal")
        if stat_bits:
            unit_details_parts.append(", ".join(stat_bits))

        # "Swarm" is a signal word: such a unit is modelled as ONE base that is itself a
        # dense cluster of many small creatures (a swarm base), not a single big creature.
        is_swarm: bool = "swarm" in unit_key.lower() or "swarm" in unit_name.lower()
        if is_swarm:
            unit_details_parts.append(
                "a swarm shown as exactly 5 smaller individual creatures of this species "
                "standing close together in a tight group, NOT one big creature and NOT a "
                "base — five separate little bodies clustered side by side")
        elif size > 1:
            unit_details_parts.append(
                "render exactly ONE single representative model, one individual creature "
                "only, NOT a group, pair or multiple figures")

        unit_details: str = ", ".join(unit_details_parts)

        # Farben formatieren
        colors_str: str = _format_colors(dl.colors)

        # Materialien formatieren
        materials_str: str = ", ".join(dl.materials) if dl.materials else ""

        # Aesthetik formatieren
        aesthetic_str: str = _format_aesthetic(dl.aesthetic)

        # Distinctive original cues + signature weapon: inject ONLY for humanoid units. These are
        # infantry features (helmet, shoulders, crest, hand-held weapon); injecting them into a
        # vehicle/aircraft/walker/titan prompt makes the model render an infantry figure instead of
        # the vehicle. (For non-humanoids the FORM_CONSTRAINTS block carries the silhouette.)
        if (override_type or "").lower() not in _NON_HUMANOID_TYPES:
            _cues = dl.aesthetic.get("original_design_cues", "")
            if _cues:
                _cues_str = "; ".join(str(c) for c in _cues) if isinstance(_cues, list) else str(_cues)
                aesthetic_str += ", distinctive original design features: " + _cues_str
            _ws = str(dl.aesthetic.get("weapon_style", "") or "")
            if _ws:
                aesthetic_str += ", signature weapon: " + _ws

        # Explizit zu vermeidende Elemente
        explicitly_avoid: str = dl.aesthetic.get("explicitly_avoid", "")
        if isinstance(explicitly_avoid, list):
            explicitly_avoid = ", ".join(explicitly_avoid)

        # Template substituieren
        prompt: str = dl.prompt_template.format(
            unit_name=unit_name,
            creature_type=dl.creature_type,
            unit_details=unit_details,
            colors=colors_str,
            materials=materials_str,
            aesthetic=aesthetic_str,
            explicitly_avoid=explicitly_avoid,
        )

        # IP-Compliance + No-Text Block immer anhaengen (unverhandelbar)
        prompt = (
            prompt.rstrip()
            + "\n\n" + NO_TEXT_BLOCK
            + "\n\n" + IP_COMPLIANCE_BLOCK
        )

        # Type-spezifische Form-Constraint anhaengen (nur wenn gemappt)
        if override_type:
            constraint: str | None = FORM_CONSTRAINTS.get(override_type.lower())
            if constraint:
                prompt = prompt.rstrip() + "\n\n" + constraint

        return prompt

    # =========================================================================
    # PRIVATE METHODEN
    # =========================================================================

    def _weapons_to_description(self, weapons: list[OPRWeapon]) -> str:
        """Konvertiert OPRWeapon-Liste zu visuellen Beschreibungen.

        Unterscheidet zwischen Fernkampf- und Nahkampfwaffen und
        beschreibt sie bildlich statt mit Spielwerten.

        Args:
            weapons: Liste der Waffen einer Einheit.

        Returns:
            Komma-separierte visuelle Waffenbeschreibungen.
        """
        if not weapons:
            return ""

        # Bio-weapon biologisation (living grown weapon-organs, chitin talons) is ONLY for organic
        # factions (Alien Hives) — it was hard-coded for all factions and was poisoning manufactured
        # factions (e.g. Battle Brothers) with organic/grown "Chaos" elements on every weapon. Opt in
        # per faction via `aesthetic.bio_weapons: true`; default = manufactured hard-tech weapons.
        aesthetic = self._design_language.aesthetic
        bio: bool = bool(aesthetic.get("bio_weapons", False)) if isinstance(aesthetic, dict) else False

        descriptions: list[str] = []

        for weapon in weapons:
            if weapon is None:
                continue

            if bio:
                name_lower: str = _biologise_weapon_name(weapon.name)
                if weapon.range_value > MELEE_RANGE:
                    desc: str = (
                        f"a living biological weapon-organ ({name_lower}) grown from the "
                        f"limb, an organic fleshy-chitin bio-cannon — NOT a manufactured gun"
                    )
                    if weapon.count > 1:
                        desc = f"{weapon.count} such bio-weapon organs"
                else:
                    prefix: str = "large heavy " if weapon.attacks >= 3 else ""
                    desc = f"{prefix}organic {name_lower} (bone blade / chitin talon)"
                    if weapon.count > 1:
                        desc = f"{weapon.count}x {desc}"
            else:
                # Manufactured factions: clean hard-tech weapons, NO organic/grown/fleshy language.
                name_lower = weapon.name.strip().lower() or "ranged weapon"
                if weapon.range_value > MELEE_RANGE:
                    desc = f"a {name_lower}, a sleek manufactured hard-tech ranged weapon"
                    if weapon.count > 1:
                        desc = f"{weapon.count} {name_lower}s (manufactured hard-tech ranged weapons)"
                else:
                    prefix = "large heavy " if weapon.attacks >= 3 else ""
                    desc = f"a {prefix}{name_lower}, a manufactured close-combat weapon (forged metal blade / power weapon)"
                    if weapon.count > 1:
                        desc = f"{weapon.count}x {desc}"
            descriptions.append(desc)

        return ", ".join(descriptions)

    def _rules_to_visual_hints(self, rules: list[str]) -> str:
        """Mappt OPR-Spezialregeln auf visuelle Beschreibungen.

        Erkennt sowohl einfache Regeln (z.B. "Flying") als auch
        parametrisierte Regeln (z.B. "Tough(6)") und generiert
        passende visuelle Hints fuer den Image-Prompt.

        Args:
            rules: Liste von Spezialregel-Strings.

        Returns:
            Komma-separierte visuelle Hints.
        """
        if not rules:
            return ""

        hints: list[str] = []

        for rule in rules:
            if not rule:
                continue

            hint: str | None = self._resolve_single_rule(rule)
            if hint is not None:
                hints.append(hint)

        return ", ".join(hints)

    def _resolve_single_rule(self, rule: str) -> str | None:
        """Loest eine einzelne Regel zu einem visuellen Hint auf.

        Args:
            rule: Spezialregel als String, z.B. "Flying" oder "Tough(6)".

        Returns:
            Visueller Hint oder None wenn keine Zuordnung existiert.
        """
        # Einfache Regeln ohne Parameter
        if rule in RULE_VISUAL_HINTS:
            return RULE_VISUAL_HINTS[rule]

        # Parametrisierte Regeln parsen: "RuleName(X)"
        match: re.Match[str] | None = re.match(
            r"^(\w+)\((\d+)\)$", rule
        )
        if match is None:
            return None

        rule_name: str = match.group(1)
        param_value: int = int(match.group(2))

        return self._resolve_parameterized_rule(rule_name, param_value)

    def _resolve_parameterized_rule(
        self, rule_name: str, value: int
    ) -> str | None:
        """Loest eine parametrisierte Regel zu einem visuellen Hint auf.

        Args:
            rule_name: Name der Regel (z.B. "Tough").
            value: Numerischer Parameter der Regel.

        Returns:
            Visueller Hint oder None.
        """
        if rule_name == "Tough":
            if value >= TOUGH_MASSIVE_THRESHOLD:
                return "massive heavily armored, towering presence"
            if value >= TOUGH_STURDY_THRESHOLD:
                return "armored, sturdy build"
            return None

        if rule_name == "Caster":
            return "psychic energy crackling around enlarged cranium"

        if rule_name == "Fear":
            return "terrifying, intimidating presence"

        if rule_name == "Transport":
            return "cargo cavity, carrying capacity visible"

        return None


# =============================================================================
# POSEN-ERKENNUNG
# =============================================================================

def _determine_pose(
    special_rules: list[str],
    base_size: int,
    override_type: str | None = None,
) -> str:
    """Bestimmt die Pose einer Einheit anhand von Regeln und Base-Groesse.

    Erkennt den Einheitstyp per Heuristik aus OPR-Spezialregeln und
    Base-Groesse. Ein expliziter Override-Typ hat immer Prioritaet.

    Prioritaet (hoch -> niedrig):
        1. override_type (explizit in Design Language gesetzt)
        2. "Aircraft" in special_rules -> AIRCRAFT
        3. "Flying" in special_rules (ohne Aircraft) -> JUMPPACK
        4. "Transport" in special_rules ODER base > 50mm -> VEHICLE
        5. Alles andere -> INFANTRY

    Args:
        special_rules: Liste der Spezialregeln als Strings.
        base_size: Groesste Base-Dimension in mm.
        override_type: Optionaler expliziter Typ aus Design Language
                       (vehicle|infantry|flyer|jumppack).

    Returns:
        Pose-Beschreibung als String.
    """
    pose_type: UnitPoseType = _detect_unit_pose_type(
        special_rules, base_size, override_type
    )
    return POSE_DESCRIPTIONS[pose_type]


def _detect_unit_pose_type(
    special_rules: list[str],
    base_size: int,
    override_type: str | None = None,
) -> UnitPoseType:
    """Erkennt den Posen-Typ einer Einheit.

    Args:
        special_rules: Liste der Spezialregeln als Strings.
        base_size: Groesste Base-Dimension in mm.
        override_type: Optionaler expliziter Typ.

    Returns:
        UnitPoseType Enum-Wert.
    """
    # Override hat immer Prioritaet
    if override_type:
        type_map: dict[str, UnitPoseType] = {
            "vehicle": UnitPoseType.VEHICLE,
            "infantry": UnitPoseType.INFANTRY,
            "flyer": UnitPoseType.AIRCRAFT,
            "aircraft": UnitPoseType.AIRCRAFT,
            "jumppack": UnitPoseType.JUMPPACK,
        }
        mapped: UnitPoseType | None = type_map.get(override_type.lower())
        if mapped is not None:
            return mapped

    # Regelnamen extrahieren (ohne Parameter wie "Transport(X)")
    rule_names: set[str] = set()
    for rule in special_rules:
        if not rule:
            continue
        match: re.Match[str] | None = re.match(r"^(\w+)", rule)
        if match:
            rule_names.add(match.group(1))

    # Aircraft hat hoechste Prioritaet
    if "Aircraft" in rule_names:
        return UnitPoseType.AIRCRAFT

    # Flying ohne Aircraft -> Jumppack
    if "Flying" in rule_names:
        return UnitPoseType.JUMPPACK

    # Transport oder grosse Base -> Fahrzeug
    if "Transport" in rule_names:
        return UnitPoseType.VEHICLE

    if base_size > VEHICLE_BASE_THRESHOLD_MM:
        return UnitPoseType.VEHICLE

    return UnitPoseType.INFANTRY


# =============================================================================
# DESIGN LANGUAGE ONLY MODUS
# =============================================================================

def _key_to_display_name(key: str) -> str:
    """Konvertiert einen unit_override Key zu einem Anzeigenamen.

    Args:
        key: Snake-case Key (z.B. "hive_lord").

    Returns:
        Title-case Name (z.B. "Hive Lord").
    """
    return key.replace("_", " ").title()


def _parse_base_from_stats(
    base_raw: int | str,
) -> tuple[int, bool, int, int]:
    """Parst Base-Groesse aus game_stats.

    Unterstuetzt runde Basen (int, z.B. 32) und ovale Basen
    (String im Format "WxD", z.B. "60x35").

    Args:
        base_raw: Base-Groesse als int (rund) oder str (oval "WxD").

    Returns:
        Tuple aus (base_size_round, is_oval, width_mm, depth_mm).
    """
    if isinstance(base_raw, str) and "x" in base_raw.lower():
        parts: list[str] = base_raw.lower().split("x")
        width: int = int(parts[0])
        depth: int = int(parts[1])
        return max(width, depth), True, width, depth

    size: int = int(base_raw) if base_raw else 32
    return size, False, size, size


def create_army_from_design_language(
    dl: DesignLanguage,
    faction_folder: str,
) -> OPRArmy:
    """Erzeugt eine synthetische OPRArmy aus den unit_overrides einer Design Language.

    Erlaubt die Nutzung der gesamten Pipeline (Session, Prompts, Bilder, 3D, Export)
    ohne eine OPR Army Forge Armeeliste. Liest game_stats aus den unit_overrides
    fuer echte Punktekosten, Quality, Defense, Waffen und Spezialregeln.

    Args:
        dl: Geladene Design Language.
        faction_folder: Normalisierter Fraktionsordner (z.B. "battle_brothers").

    Returns:
        OPRArmy mit einer Unit pro unit_override Key.
    """
    units: list[OPRUnit] = []

    for key, override in dl.unit_overrides.items():
        stats: dict[str, Any] = override.get("game_stats", {})

        weapons: list[OPRWeapon] = []
        for w in stats.get("weapons", []):
            weapons.append(OPRWeapon(
                name=w.get("name", ""),
                range_value=w.get("range", 0),
                attacks=w.get("attacks", 0),
                special_rules=w.get("rules", []),
            ))

        base_raw: int | str = stats.get("base", 32)
        base_size, is_oval, width, depth = _parse_base_from_stats(base_raw)

        units.append(OPRUnit(
            name=_key_to_display_name(key),
            size=stats.get("size", 1),
            cost=stats.get("cost", 0),
            quality=stats.get("quality", 4),
            defense=stats.get("defense", 4),
            weapons=weapons,
            special_rules=stats.get("rules", []),
            base_size_round=base_size,
            base_is_oval=is_oval,
            base_width_mm=width,
            base_depth_mm=depth,
        ))

    total_cost: int = sum(u.cost for u in units)
    return OPRArmy(
        name=dl.faction_name,
        faction_name=dl.faction_name,
        faction_folder=faction_folder,
        game_system="Grimdark Future",
        points=total_cost,
        units=units,
    )


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def _format_colors(colors: dict[str, str]) -> str:
    """Formatiert das Farbschema zu einem lesbaren String.

    Args:
        colors: Dict mit primary, secondary, accent Farben.

    Returns:
        Formatierter Farbstring.
    """
    if not colors:
        return ""

    parts: list[str] = []
    primary: str = colors.get("primary", "")
    secondary: str = colors.get("secondary", "")
    accent: str = colors.get("accent", "")

    if primary:
        parts.append(f"primary {primary}")
    if secondary:
        parts.append(f"secondary {secondary}")
    if accent:
        parts.append(f"accent {accent}")

    return ", ".join(parts)


def _format_aesthetic(aesthetic: dict[str, Any]) -> str:
    """Formatiert die Aesthetik-Beschreibung zu einem lesbaren String.

    Args:
        aesthetic: Dict mit genre, style, inspiration etc.

    Returns:
        Formatierter Aesthetik-String.
    """
    if not aesthetic:
        return ""

    parts: list[str] = []
    genre: str = aesthetic.get("genre", "")
    style: str = aesthetic.get("style", "")
    inspiration: Any = aesthetic.get("inspiration", "")

    if genre:
        parts.append(genre)
    if style:
        parts.append(style)
    if inspiration:
        if isinstance(inspiration, list):
            parts.append(", ".join(str(item) for item in inspiration))
        else:
            parts.append(str(inspiration))

    return ", ".join(parts)


# =============================================================================
# WAFFEN-BIOLOGISIERUNG
# =============================================================================

# Manufactured-weapon Wörter, die im Bild zu menschlichen Schusswaffen führen.
_MANUFACTURED_WEAPON_WORDS: dict[str, str] = {
    "cannon": "spitting-maw",
    "gun": "spitter-organ",
    "rifle": "spine-launcher",
    "launcher": "barb-launcher organ",
    "pistol": "spitter-organ",
    "blaster": "spitter-organ",
    "artillery": "bombard-maw",
    "mortar": "bombard-maw",
    "bombs": "spore-sacs",
    "smoke": "spore-cloud",
}


def _biologise_weapon_name(name: str) -> str:
    """Ersetzt manufactured-weapon Wörter im Waffennamen durch organische Begriffe,
    damit das Bildmodell keine menschlichen Schusswaffen malt (z.B. "Shredder Gun"
    -> "shredder spitter-organ"). Faction-neutral; rein lexikalisch.
    """
    out: str = name.lower()
    for manufactured, organic in _MANUFACTURED_WEAPON_WORDS.items():
        out = re.sub(rf"\b{manufactured}\b", organic, out)
    return out

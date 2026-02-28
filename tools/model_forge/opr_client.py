"""
OPR API Client - Python-Port des GDScript OPR API Clients
=========================================================

Laedt Armeelisten von der OnePageRules Army Forge API
und parsed sie in typisierte Datenklassen.

API-Endpunkt: GET https://army-forge.onepagerules.com/api/tts?id={list_id}
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from urllib.parse import urlparse, parse_qs

import requests


# =============================================================================
# KONSTANTEN
# =============================================================================

API_BASE_URL = "https://army-forge.onepagerules.com/api"

GAME_SYSTEM_MAP = {
    "gf": "Grimdark Future",
    "gff": "Grimdark Future: Firefight",
    "aof": "Age of Fantasy",
    "aofs": "Age of Fantasy: Skirmish",
    "aofr": "Age of Fantasy: Regiments",
}

REQUEST_TIMEOUT = 30  # Sekunden


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class OPRWeapon:
    """Waffe einer Einheit."""

    name: str = ""
    range_value: int = 0  # 0 = Nahkampf
    attacks: int = 0
    count: int = 1
    special_rules: list[str] = field(default_factory=list)

    def get_display_text(self) -> str:
        count_str = "" if self.count <= 1 else f"{self.count}x "
        range_str = "Melee" if self.range_value == 0 else f'{self.range_value}"'
        text = f"{count_str}{self.name} ({range_str}, A{self.attacks})"
        if self.special_rules:
            text += f" [{', '.join(self.special_rules)}]"
        return text


@dataclass
class OPRUnit:
    """Einheit einer Armee."""

    id: str = ""
    name: str = ""
    size: int = 1
    cost: int = 0
    quality: int = 4
    defense: int = 4
    weapons: list[OPRWeapon] = field(default_factory=list)
    special_rules: list[str] = field(default_factory=list)
    base_size_round: int = 32
    base_is_oval: bool = False
    base_width_mm: int = 32
    base_depth_mm: int = 32

    def get_display_name(self) -> str:
        if self.size > 1:
            return f"{self.name} [{self.size}]"
        return self.name


@dataclass
class OPRArmy:
    """Komplette Armeeliste."""

    name: str = ""
    game_system: str = ""
    points: int = 0
    units: list[OPRUnit] = field(default_factory=list)
    faction_name: str = ""
    faction_folder: str = ""

    def get_total_models(self) -> int:
        return sum(unit.size for unit in self.units)

    def get_unique_unit_names(self) -> list[str]:
        """Gibt eine deduplizierte Liste aller Unit-Namen zurueck."""
        seen: set[str] = set()
        result: list[str] = []
        for unit in self.units:
            if unit.name not in seen:
                seen.add(unit.name)
                result.append(unit.name)
        return result


# =============================================================================
# PARSING-HILFSFUNKTIONEN
# =============================================================================

def _safe_int(value: object, default: int = 0) -> int:
    """Konvertiert einen Wert sicher zu int. Behandelt oval-Format wie '60x35'."""
    if value is None:
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        if "x" in value:
            parts = value.split("x")
            if len(parts) >= 2:
                try:
                    width = int(parts[0])
                    depth = int(parts[1])
                    return max(width, depth)
                except ValueError:
                    return default
        try:
            return int(value)
        except ValueError:
            try:
                return int(float(value))
            except ValueError:
                return default
    return default


def _parse_base_size(value: object, default: int = 32) -> tuple[bool, int, int]:
    """
    Parsed Base-Size-Wert.

    Returns:
        (is_oval, width_mm, depth_mm)
        Bei runden Basen: (False, size, size)
        Bei ovalen Basen wie '60x35': (True, min_val, max_val)
    """
    if value is None:
        return (False, default, default)

    if isinstance(value, (int, float)):
        size = int(value)
        return (False, size, size)

    if isinstance(value, str):
        if "x" in value:
            parts = value.split("x")
            if len(parts) >= 2:
                try:
                    first = int(parts[0])
                    second = int(parts[1])
                    depth = max(first, second)
                    width = min(first, second)
                    return (True, width, depth)
                except ValueError:
                    return (False, default, default)
        try:
            size = int(value)
            return (False, size, size)
        except ValueError:
            try:
                size = int(float(value))
                return (False, size, size)
            except ValueError:
                return (False, default, default)

    return (False, default, default)


def _format_rating(value: object) -> str:
    """Formatiert Rating-Wert. Entfernt '.0' bei ganzen Zahlen."""
    if isinstance(value, float) and value == int(value):
        return str(int(value))
    return str(value)


def _expand_game_system(abbrev: str) -> str:
    """Expandiert Game-System-Abkuerzung."""
    return GAME_SYSTEM_MAP.get(abbrev, abbrev)


def _clamp(value: int, min_val: int, max_val: int) -> int:
    return max(min_val, min(max_val, value))


# =============================================================================
# RULE-PARSING
# =============================================================================

def _parse_rule(rule: object) -> str:
    """Parsed eine einzelne Regel (String oder Dict mit name/rating)."""
    if isinstance(rule, str):
        return rule
    if isinstance(rule, dict):
        rule_name = rule.get("name", "")
        rule_rating = rule.get("rating")
        if rule_rating is not None and str(rule_rating) != "":
            return f"{rule_name}({_format_rating(rule_rating)})"
        if rule_name:
            return rule_name
    return ""


def _parse_rules_list(rules: list | None) -> list[str]:
    """Parsed eine Liste von Regeln zu formatierten Strings."""
    if not rules or not isinstance(rules, list):
        return []
    result: list[str] = []
    for rule in rules:
        parsed = _parse_rule(rule)
        if parsed:
            result.append(parsed)
    return result


# =============================================================================
# WEAPON-PARSING
# =============================================================================

def _parse_tts_weapon(data: object) -> OPRWeapon | None:
    """
    Parsed eine Waffe aus TTS-API-Response.
    Gibt None zurueck fuer Nicht-Waffen (String-Items oder Items ohne attacks).
    """
    if isinstance(data, str):
        return None
    if not isinstance(data, dict):
        return None

    weapon = OPRWeapon(
        name=data.get("name", data.get("label", "Unknown")),
        range_value=data.get("range", 0) or 0,
        attacks=data.get("attacks", 0) or 0,
        count=data.get("count", 1) or 1,
        special_rules=_parse_rules_list(data.get("specialRules", [])),
    )
    return weapon


# =============================================================================
# UNIT-PARSING
# =============================================================================

def _parse_tts_unit(data: dict) -> OPRUnit:
    """Parsed eine Einheit aus dem TTS-API-Response."""
    unit = OPRUnit(
        id=data.get("id", ""),
        name=data.get("name", "Unknown Unit"),
        size=data.get("size", 1),
        cost=data.get("cost", 0),
        quality=data.get("quality", 4),
        defense=data.get("defense", 4),
    )

    # Base-Size parsen
    bases = data.get("bases", {})
    if isinstance(bases, dict) and bases:
        round_size = bases.get("round", "32")
        is_oval, width, depth = _parse_base_size(round_size, 32)
        unit.base_is_oval = is_oval
        unit.base_width_mm = _clamp(width, 20, 150)
        unit.base_depth_mm = _clamp(depth, 20, 150)
        unit.base_size_round = max(unit.base_width_mm, unit.base_depth_mm)

    # Special Rules parsen (API nutzt "rules" ODER "specialRules")
    rules_field = data.get("rules") or data.get("specialRules") or []
    unit.special_rules = _parse_rules_list(rules_field)

    # Loadout/Equipment parsen
    loadout = data.get("loadout", data.get("equipment", []))
    for item in loadout:
        weapon = _parse_tts_weapon(item)
        if weapon and weapon.attacks > 0:
            unit.weapons.append(weapon)
        else:
            # Items ohne Attacks sind Upgrades/Equipment
            if isinstance(item, str):
                if item and item not in unit.special_rules:
                    unit.special_rules.append(item)
            elif isinstance(item, dict):
                item_name = item.get("name", item.get("label", ""))
                if item_name and item_name not in unit.special_rules:
                    unit.special_rules.append(item_name)

                # Auch Special Rules die durch Upgrades gewaehrt werden
                item_rules = list(item.get("specialRules", []))
                item_content = item.get("content", [])
                if isinstance(item_content, list):
                    item_rules.extend(item_content)

                for item_rule in item_rules:
                    granted = _parse_rule(item_rule)
                    if granted and granted not in unit.special_rules:
                        unit.special_rules.append(granted)

    return unit


# =============================================================================
# SHARE-LINK EXTRACTION
# =============================================================================

def extract_list_id(share_link_or_id: str) -> str:
    """
    Extrahiert die List-ID aus einem Share-Link oder gibt die ID direkt zurueck.

    Unterstuetzte Formate:
    - https://army-forge.onepagerules.com/share?id=XXX&name=YYY
    - XXX (raw ID)
    """
    input_str = share_link_or_id.strip()

    if input_str.startswith("http"):
        parsed = urlparse(input_str)
        params = parse_qs(parsed.query)
        ids = params.get("id", [])
        return ids[0] if ids else ""

    return input_str


# =============================================================================
# API CLIENT
# =============================================================================

def fetch_army(share_link_or_id: str) -> OPRArmy:
    """
    Laedt eine Armee von der OPR Army Forge API.

    Args:
        share_link_or_id: Share-Link URL oder List-ID

    Returns:
        OPRArmy Objekt

    Raises:
        ValueError: Bei ungueltiger URL/ID
        requests.RequestException: Bei Netzwerkfehlern
    """
    list_id = extract_list_id(share_link_or_id)
    if not list_id:
        raise ValueError("Ungueltige Share-URL oder List-ID")

    # TTS API aufrufen
    url = f"{API_BASE_URL}/tts?id={list_id}"
    response = requests.get(url, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()

    data = response.json()
    return _parse_tts_response(data)


def _parse_tts_response(data: dict) -> OPRArmy:
    """Parsed die TTS-API-Response in ein OPRArmy-Objekt."""
    army = OPRArmy(
        name=data.get("name", "Imported Army"),
        game_system=_expand_game_system(data.get("gameSystem", "gf")),
        points=data.get("listPoints", 0),
    )

    # Units parsen
    units_data = data.get("units", [])
    army_id = ""

    if units_data:
        first_unit = units_data[0]
        if isinstance(first_unit, dict):
            army_id = first_unit.get("armyId", "")

    for unit_data in units_data:
        if isinstance(unit_data, dict):
            unit = _parse_tts_unit(unit_data)
            army.units.append(unit)

    # Faction-Name ueber Army Book API holen
    if army_id:
        faction_name = _fetch_faction_name(army_id)
        if faction_name:
            army.faction_name = faction_name
            army.faction_folder = _normalize_folder_name(faction_name)

    return army


def _fetch_faction_name(army_id: str) -> str:
    """Holt den Faction-Namen vom Army Book API-Endpunkt."""
    try:
        url = f"{API_BASE_URL}/army-books/{army_id}"
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        if response.status_code == 200:
            data = response.json()
            return data.get("name", "")
    except requests.RequestException:
        pass
    return ""


def _normalize_folder_name(name: str) -> str:
    """Normalisiert einen Namen zum Ordnernamen: 'Alien Hives' -> 'alien_hives'."""
    return name.lower().replace(" ", "_").replace("-", "_")

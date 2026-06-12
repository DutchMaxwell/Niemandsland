class_name PlayerIdentity
extends RefCounted
## The local player's chosen display name: sanitization, a peer-id fallback and
## persistence to user://. Pure/static where it can be (mirrors DiceRules /
## LosRules) so the name rules are trivially testable; only load/save touch disk.

# === Constants ===

## Max displayed name length; longer input is clamped. Keeps chat/roster rows and
## the 3D avatar label from overflowing.
const MAX_NAME_LEN := 20
const CONFIG_PATH := "user://player_identity.cfg"
const CONFIG_SECTION := "player"
const CONFIG_KEY_NAME := "name"

# === Public (static) ===


## Cleans a raw name for display/transport: strips control characters, collapses
## runs of whitespace, trims the ends and clamps to MAX_NAME_LEN. Returns "" when
## nothing printable remains (the caller then uses the peer-id fallback).
static func sanitize(raw: String) -> String:
	var cleaned := ""
	for c: String in raw:
		# Drop ASCII control chars (incl. newlines/tabs) so a name stays one line.
		if c.unicode_at(0) >= 32:
			cleaned += c
	# Collapse internal whitespace runs to single spaces, then trim.
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	cleaned = cleaned.strip_edges()
	if cleaned.length() > MAX_NAME_LEN:
		cleaned = cleaned.substr(0, MAX_NAME_LEN).strip_edges()
	return cleaned


## Display name for a player: the sanitized name, or the "Player N" fallback when
## no name is set. Used for remote players and the roster.
static func display_name(raw_name: String, peer_id: int) -> String:
	var clean := sanitize(raw_name)
	return clean if not clean.is_empty() else "Player %d" % peer_id


# === Public: persistence ===


## The saved local name (empty string if none was ever saved).
static func load_saved_name() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return ""
	return sanitize(str(config.get_value(CONFIG_SECTION, CONFIG_KEY_NAME, "")))


## Persists the local name (sanitized) for the next session.
static func save_name(name: String) -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # keep any other keys; ignore "not found"
	config.set_value(CONFIG_SECTION, CONFIG_KEY_NAME, sanitize(name))
	config.save(CONFIG_PATH)

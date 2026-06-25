extends Node
## Autoload: checks whether a newer release of Niemandsland has been published and,
## if so, lets the startup menu offer the player a download. Desktop only — web/itch
## builds always run the latest deploy, so there is nothing to update there.
##
## The "latest version" is read from the project's GitHub Releases. The list endpoint
## (not `/releases/latest`) is used on purpose: while the project is on its alpha line
## every release is a GitHub *prerelease*, and `/releases/latest` skips those. The
## running version comes from `application/config/version` — the same string the
## multiplayer version handshake compares (see network_manager.gd).
##
## This feature is inert until releases are actually published: with no releases the
## check resolves to "up to date" and the menu shows nothing. See docs/UPDATE_CHECK.md
## for how to activate it and how to repoint it at a self-hosted version endpoint.

# ===== Constants =====

## ProjectSettings key holding the release version (e.g. "0.3.1-alpha").
const VERSION_SETTING: String = "application/config/version"

## GitHub Releases REST endpoint (list form, so alpha prereleases are included).
const RELEASES_API_URL: String = "https://api.github.com/repos/DutchMaxwell/Niemandsland/releases"

## Human-facing releases page, used as the download target when an entry lacks a URL.
const RELEASES_PAGE_URL: String = "https://github.com/DutchMaxwell/Niemandsland/releases"

## Whether prereleases (the project's alpha/beta line) count as offerable updates.
const INCLUDE_PRERELEASES: bool = true

## Abort the request if the server has not answered within this many seconds, so a
## stalled connection can never keep the player waiting.
const REQUEST_TIMEOUT_SECONDS: float = 8.0

## GitHub rejects requests without a User-Agent; identify ourselves politely.
const USER_AGENT: String = "Niemandsland-UpdateChecker"

## Number of numeric fields compared in a version's core. The project uses a 4-field scheme
## (MAJOR.MINOR.PATCH.BUILD, e.g. 0.3.7.1), so all four must be compared — comparing only three
## made 0.3.6.0 and 0.3.6.1 look identical and suppressed the in-game update prompt. A 3-field
## version (0.3.7) parses with a trailing 0 (0.3.7.0), so both schemes work.
const CORE_FIELDS: int = 4

const HTTP_OK: int = 200
const HTTP_NOT_FOUND: int = 404

## Persisted opt-out / skipped-version preferences.
const CONFIG_PATH: String = "user://update_check.cfg"
const CONFIG_SECTION: String = "update_check"
const ENABLED_KEY: String = "enabled"
const SKIP_KEY: String = "skip_version"

# ===== Signals =====

## A newer release exists. `latest_version` is normalized (no leading "v"),
## `release_url` opens the download page, `release_notes` is the raw changelog body.
signal update_available(latest_version: String, release_url: String, release_notes: String)

## No newer release than the running build (or none published yet).
signal up_to_date(current_version: String)

## The check could not complete (offline, rate-limited, malformed response, ...).
## Always non-fatal: the menu simply carries on.
signal check_failed(reason: String)

# ===== Private state =====

var _http: HTTPRequest
var _checking: bool = false

# ===== Lifecycle =====

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


# ===== Public API =====

## The running release string both the handshake and this checker compare.
func get_current_version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, "unknown"))


## Kick off an asynchronous check. Never blocks; results arrive via the signals above.
## `force` ignores the user's opt-out (e.g. a manual "Check for updates" action).
func check_for_updates(force: bool = false) -> void:
	if _checking:
		return
	if OS.has_feature("web"):
		# Web/itch is always the latest deploy — report current and do nothing.
		up_to_date.emit(get_current_version())
		return
	if not force and not is_enabled():
		return
	if _http == null:
		return
	var headers := PackedStringArray([
		"User-Agent: %s" % USER_AGENT,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
	])
	var err := _http.request(RELEASES_API_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_fail("request could not start (%d)" % err)
		return
	_checking = true


# ===== Preferences (persisted) =====

func is_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return true
	return bool(config.get_value(CONFIG_SECTION, ENABLED_KEY, true))


func set_enabled(enabled: bool) -> void:
	_store_value(ENABLED_KEY, enabled)


func is_version_skipped(version: String) -> bool:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return false
	var skipped := str(config.get_value(CONFIG_SECTION, SKIP_KEY, ""))
	return not skipped.is_empty() and skipped == normalize_tag(version)


func set_skip_version(version: String) -> void:
	_store_value(SKIP_KEY, normalize_tag(version))


func clear_skip_version() -> void:
	_store_value(SKIP_KEY, "")


# ===== Version logic (pure, static — unit tested) =====

## Strips a leading "v"/"V" and surrounding whitespace from a release tag.
static func normalize_tag(raw: String) -> String:
	var text := raw.strip_edges()
	if text.begins_with("v") or text.begins_with("V"):
		text = text.substr(1)
	return text


## Parses a SemVer-ish string into {core: PackedInt64Array(4), prerelease: PackedStringArray, valid: bool}.
## Build metadata after "+" is ignored. Non-numeric core fields make the result invalid.
static func parse_version(raw: String) -> Dictionary:
	var result := {
		"core": PackedInt64Array([0, 0, 0, 0]),
		"prerelease": PackedStringArray(),
		"valid": false,
	}
	var text := normalize_tag(raw)
	if text.is_empty():
		return result
	var plus := text.find("+")
	if plus != -1:
		text = text.substr(0, plus)
	var core_text := text
	var pre_text := ""
	var dash := text.find("-")
	if dash != -1:
		core_text = text.substr(0, dash)
		pre_text = text.substr(dash + 1)
	var parts := core_text.split(".")
	var core := PackedInt64Array([0, 0, 0, 0])
	for i in mini(parts.size(), CORE_FIELDS):
		var token := parts[i]
		if not token.is_valid_int():
			return result
		core[i] = int(token)
	result["core"] = core
	if not pre_text.is_empty():
		result["prerelease"] = pre_text.split(".")
	result["valid"] = true
	return result


## SemVer precedence: returns -1 if a < b, 0 if equal, 1 if a > b.
static func compare_versions(a_raw: String, b_raw: String) -> int:
	var a := parse_version(a_raw)
	var b := parse_version(b_raw)
	var a_core := a["core"] as PackedInt64Array
	var b_core := b["core"] as PackedInt64Array
	for i in CORE_FIELDS:
		if a_core[i] != b_core[i]:
			return -1 if a_core[i] < b_core[i] else 1
	var a_pre := a["prerelease"] as PackedStringArray
	var b_pre := b["prerelease"] as PackedStringArray
	var a_has := a_pre.size() > 0
	var b_has := b_pre.size() > 0
	if a_has != b_has:
		# A version WITHOUT a prerelease tag is the higher (stable) release.
		return 1 if not a_has else -1
	if not a_has:
		return 0
	return _compare_prerelease(a_pre, b_pre)


## True when `candidate` is a strictly newer release than `baseline`.
static func is_newer(candidate: String, baseline: String) -> bool:
	return compare_versions(candidate, baseline) > 0


## Highest valid version among `tags`, honouring `include_prereleases`. "" if none qualify.
static func select_latest(tags: Array, include_prereleases: bool) -> String:
	var best := ""
	for tag in tags:
		var tag_str := str(tag)
		var parsed := parse_version(tag_str)
		if not bool(parsed["valid"]):
			continue
		if not include_prereleases and (parsed["prerelease"] as PackedStringArray).size() > 0:
			continue
		if best.is_empty() or is_newer(tag_str, best):
			best = tag_str
	return best


# ===== Private =====

## SemVer §11 prerelease comparison: numeric identifiers rank below alphanumeric ones,
## and when all shared identifiers match the longer set wins.
static func _compare_prerelease(a: PackedStringArray, b: PackedStringArray) -> int:
	var shared := mini(a.size(), b.size())
	for i in shared:
		var ai := a[i]
		var bi := b[i]
		var a_num := ai.is_valid_int()
		var b_num := bi.is_valid_int()
		if a_num and b_num:
			var an := int(ai)
			var bn := int(bi)
			if an != bn:
				return -1 if an < bn else 1
		elif a_num != b_num:
			return -1 if a_num else 1
		elif ai != bi:
			return -1 if ai < bi else 1
	if a.size() == b.size():
		return 0
	return -1 if a.size() < b.size() else 1


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_checking = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("network error %d" % result)
		return
	if response_code == HTTP_NOT_FOUND:
		# Repository has no releases yet — nothing to offer.
		up_to_date.emit(get_current_version())
		return
	if response_code != HTTP_OK:
		_fail("HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Array):
		_fail("unexpected response format")
		return
	var releases := parsed as Array
	var newest := _select_newest_release(releases)
	var current := get_current_version()
	var latest_tag := str(newest.get("tag_name", ""))
	if latest_tag.is_empty() or not is_newer(latest_tag, current):
		up_to_date.emit(current)
		return
	if is_version_skipped(latest_tag):
		# The player asked not to be reminded about this one.
		up_to_date.emit(current)
		return
	var url := _platform_asset_url(newest)
	var notes := str(newest.get("body", ""))
	update_available.emit(normalize_tag(latest_tag), url, notes)


## Download target: the release asset matching THIS OS (so the in-game "Download" button is a single
## click straight to the right zip), falling back to the release page if no matching asset is found.
func _platform_asset_url(release: Dictionary) -> String:
	var keyword := _os_asset_keyword()
	if keyword != "":
		for entry in release.get("assets", []):
			if not (entry is Dictionary):
				continue
			var asset_name := str(entry.get("name", "")).to_lower()
			if keyword in asset_name and asset_name.ends_with(".zip"):
				var dl := str(entry.get("browser_download_url", ""))
				if not dl.is_empty():
					return dl
	return str(release.get("html_url", RELEASES_PAGE_URL))


## The release-asset filename keyword for the running OS ("" = unknown -> fall back to the page).
func _os_asset_keyword() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"Linux":
			return "linux"
		"macOS":
			return "macos"
		_:
			return ""


## Picks the highest-versioned, non-draft release object from a GitHub releases array.
func _select_newest_release(releases: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_tag := ""
	for entry in releases:
		if not (entry is Dictionary):
			continue
		var dict := entry as Dictionary
		if bool(dict.get("draft", false)):
			continue
		if not INCLUDE_PRERELEASES and bool(dict.get("prerelease", false)):
			continue
		var tag := str(dict.get("tag_name", ""))
		if tag.is_empty():
			continue
		if not bool(parse_version(tag)["valid"]):
			continue
		if best_tag.is_empty() or is_newer(tag, best_tag):
			best_tag = tag
			best = dict
	return best


func _store_value(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # ignore error: a missing file just starts empty
	config.set_value(CONFIG_SECTION, key, value)
	config.save(CONFIG_PATH)


func _fail(reason: String) -> void:
	check_failed.emit(reason)

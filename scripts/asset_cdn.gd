class_name AssetCDN
extends RefCounted
## Single source of truth for the asset-delivery host: the Cloudflare R2 custom
## domain that serves miniature + terrain GLBs, ambience audio and textures on
## demand. The shipped manifests (assets/*_manifest.json) never hardcode the host
## — they reference it through the "{cdn}" token, which expand() resolves at load
## time. To move asset delivery to a new domain, change ONLY HOST below.

# === Constants ===

## The live asset host (scheme + authority, no trailing slash). Mirror this value
## in the asset-pipeline repo (cdn_config.py) so re-published manifests stay in sync.
const HOST := "https://assets.niemandsland.xyz"

## Placeholder used in manifest base_urls in place of the host.
const TOKEN := "{cdn}"

# === Public (static) ===

## Expands the CDN token in a manifest base_url to the live host. base_urls that
## carry no token (empty, or already fully-qualified) pass through unchanged, so
## test fixtures and any absolute manifests keep working.
static func expand(base_url: String) -> String:
	return base_url.replace(TOKEN, HOST)


## An HONEST product User-Agent for CDN requests. Cloudflare bot-scoring challenges empty/default library
## UAs (Godot sends none) for low-reputation IPs — a challenge the game can't solve, so faction models
## silently fail to load; an honest product UA passes and also gives us server-side analytics. Version is
## the single source (application/config/version); OS.get_name() → "Windows"/"Linux"/"macOS" (bus 037).
static func user_agent() -> String:
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	return "Niemandsland/%s (%s; Godot 4.6)" % [ver, OS.get_name()]


## Request headers for every CDN call: the product UA + an Accept type (application/json for the manifest,
## */* for binaries). Returned as a PackedStringArray ready for HTTPRequest.request(url, headers).
static func headers(accept: String = "*/*") -> PackedStringArray:
	return PackedStringArray([
		"User-Agent: %s" % user_agent(),
		"Accept: %s" % accept,
	])

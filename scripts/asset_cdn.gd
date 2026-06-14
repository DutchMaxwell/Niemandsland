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
const HOST := "https://<legacy-cdn-host>"

## Placeholder used in manifest base_urls in place of the host.
const TOKEN := "{cdn}"

# === Public (static) ===

## Expands the CDN token in a manifest base_url to the live host. base_urls that
## carry no token (empty, or already fully-qualified) pass through unchanged, so
## test fixtures and any absolute manifests keep working.
static func expand(base_url: String) -> String:
	return base_url.replace(TOKEN, HOST)

"""Single source of truth for the asset-delivery host (Cloudflare R2 custom
domain) on the publishing side.

The game reads the same host from scripts/asset_cdn.gd; keep the two HOST values
in sync. Published manifests store the ``{cdn}`` token instead of the literal
host so the committed JSON stays domain-agnostic — to move the CDN to a new
domain, change HOST here and in asset_cdn.gd, and no manifest needs editing.
"""

# The live asset host (scheme + authority, no trailing slash).
HOST = "https://<legacy-cdn-host>"

# Placeholder written into manifest base_urls in place of the host.
TOKEN = "{cdn}"


def base_url(path: str = "") -> str:
    """A tokenized manifest base_url, e.g. base_url('/terrain-source/trees').

    The leading token keeps committed manifests host-free; the game expands it
    via AssetCDN.expand(). ``path`` should start with '/' (or be '' for root).
    """
    return f"{TOKEN}{path}"


def expand(value: str) -> str:
    """Resolve the token to the live host (for tools that need a real URL,
    e.g. previewing a model in the R2 browser)."""
    return value.replace(TOKEN, HOST)

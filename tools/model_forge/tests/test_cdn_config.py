"""Tests for cdn_config: the single source of truth for the asset host.

Mirrors scripts/asset_cdn.gd on the game side; published manifests carry the
``{cdn}`` token so the committed JSON stays domain-agnostic.
"""

from __future__ import annotations

import cdn_config


def test_base_url_root_is_tokenized():
    assert cdn_config.base_url("/") == "{cdn}/"


def test_base_url_with_path_is_tokenized():
    assert cdn_config.base_url("/terrain-source/trees") == "{cdn}/terrain-source/trees"


def test_base_url_default_is_bare_token():
    assert cdn_config.base_url() == "{cdn}"


def test_expand_resolves_token_to_host():
    assert cdn_config.expand("{cdn}/terrain-source/trees") == \
        f"{cdn_config.HOST}/terrain-source/trees"


def test_expand_leaves_untokenized_value_unchanged():
    assert cdn_config.expand("https://cdn/foo.glb") == "https://cdn/foo.glb"


def test_host_has_no_trailing_slash():
    # Guards the "{cdn}/" convention: the slash comes from the path, not HOST.
    assert not cdn_config.HOST.endswith("/")

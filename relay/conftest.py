"""pytest configuration for relay server tests."""

import pytest


def pytest_collection_modifyitems(config, items):
    """Auto-mark all async test functions with pytest.mark.asyncio."""
    for item in items:
        if item.get_closest_marker("asyncio") is None:
            if hasattr(item, "function") and asyncio_test(item.function):
                item.add_marker(pytest.mark.asyncio)


def asyncio_test(func):
    """Check if a function is an async function."""
    import asyncio
    return asyncio.iscoroutinefunction(func)

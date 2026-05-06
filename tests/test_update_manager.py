"""Tests du gestionnaire de mises à jour."""

from src.update_manager import (
    ReleaseAsset,
    ReleaseInfo,
    is_newer_version,
    select_release_asset,
)


def test_version_comparison_handles_prefix_v():
    assert is_newer_version("v1.2.0", "1.1.9") is True
    assert is_newer_version("1.2.0", "v1.2.0") is False


def test_select_release_asset_prefers_exe_on_windows_like_release():
    release = ReleaseInfo(
        version="v1.2.0",
        name="Peadra 1.2.0",
        url="https://example.com",
        body="",
        assets=(
            ReleaseAsset(name="notes.txt", download_url="https://example.com/notes.txt"),
            ReleaseAsset(name="Peadra.exe", download_url="https://example.com/Peadra.exe"),
        ),
    )

    asset = select_release_asset(release)
    assert asset is not None
    assert asset.name == "Peadra.exe"

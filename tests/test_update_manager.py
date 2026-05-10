"""Tests du gestionnaire de mises à jour."""

import errno
import os
from pathlib import Path

from src.update_manager import (
    ReleaseAsset,
    ReleaseInfo,
    _replace_file_with_fallback,
    _ensure_executable,
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
            ReleaseAsset(
                name="notes.txt", download_url="https://example.com/notes.txt"
            ),
            ReleaseAsset(
                name="Peadra.exe", download_url="https://example.com/Peadra.exe"
            ),
        ),
    )

    asset = select_release_asset(release)
    assert asset is not None
    assert asset.name == "Peadra.exe"


def test_replace_file_with_fallback_handles_cross_device(monkeypatch, tmp_path: Path):
    source = tmp_path / "source.bin"
    target = tmp_path / "target.bin"
    source.write_bytes(b"new")
    target.write_bytes(b"old")

    original_replace = os.replace
    calls = {"count": 0}

    def fake_replace(src, dst):
        calls["count"] += 1
        if calls["count"] == 1:
            raise OSError(errno.EXDEV, "Invalid cross-device link")
        return original_replace(src, dst)

    monkeypatch.setattr("src.update_manager.os.replace", fake_replace)

    _replace_file_with_fallback(source, target)

    assert target.read_bytes() == b"new"
    assert not source.exists()
    assert calls["count"] >= 2


def test_ensure_executable_sets_user_exec_bit_on_unix(monkeypatch, tmp_path: Path):
    if os.name == "nt":
        return

    test_file = tmp_path / "peadra-helper"
    test_file.write_text("binary")
    test_file.chmod(0o644)

    monkeypatch.setattr("src.update_manager.platform.system", lambda: "Linux")

    _ensure_executable(test_file)

    assert test_file.stat().st_mode & 0o100

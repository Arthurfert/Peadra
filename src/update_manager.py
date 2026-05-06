"""Gestion des mises à jour de l'application via GitHub Releases.

Le module n'utilise que la bibliothèque standard pour rester compatible avec
l'exécutable standalone généré par PyInstaller.
"""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .version import __version__

GITHUB_OWNER = "Arthurfert"
GITHUB_REPO = "Peadra"
GITHUB_RELEASE_API = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest"
DEFAULT_TIMEOUT = 5


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    download_url: str
    size: int | None = None


@dataclass(frozen=True)
class ReleaseInfo:
    version: str
    name: str
    url: str
    body: str
    assets: tuple[ReleaseAsset, ...]


@dataclass(frozen=True)
class UpdateCheckResult:
    available: bool
    current_version: str
    latest_version: str | None = None
    release_url: str | None = None
    asset_name: str | None = None
    asset_url: str | None = None
    error: str | None = None


def is_frozen_app() -> bool:
    return bool(getattr(sys, "frozen", False))


def get_current_version() -> str:
    return __version__


def _normalize_version(version: str) -> tuple[int, ...]:
    cleaned = version.strip().lower()
    if cleaned.startswith("v"):
        cleaned = cleaned[1:]

    parts = [int(part) for part in re.findall(r"\d+", cleaned)]
    return tuple(parts) if parts else (0,)


def is_newer_version(candidate: str, current: str | None = None) -> bool:
    reference = current or get_current_version()
    return _normalize_version(candidate) > _normalize_version(reference)


def _build_request(url: str) -> urllib.request.Request:
    return urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "Peadra-Updater",
        },
    )


def fetch_latest_release(timeout: int = DEFAULT_TIMEOUT) -> ReleaseInfo:
    request = _build_request(GITHUB_RELEASE_API)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))

    assets: list[ReleaseAsset] = []
    for asset in payload.get("assets", []):
        download_url = asset.get("browser_download_url")
        name = asset.get("name")
        if download_url and name:
            assets.append(
                ReleaseAsset(
                    name=name,
                    download_url=download_url,
                    size=asset.get("size"),
                )
            )

    tag = str(payload.get("tag_name") or payload.get("name") or "").strip()
    if not tag:
        raise ValueError("La release GitHub ne contient pas de tag exploitable.")

    return ReleaseInfo(
        version=tag,
        name=str(payload.get("name") or tag),
        url=str(payload.get("html_url") or ""),
        body=str(payload.get("body") or ""),
        assets=tuple(assets),
    )


def _preferred_asset_names() -> Iterable[str]:
    system_name = platform.system().lower()
    if system_name == "windows":
        return (
            "peadra.exe",
            "peadra-windows.exe",
            "peadra_windows.exe",
            "windows.exe",
        )
    if system_name == "linux":
        return (
            "peadra",
            "peadra-linux",
            "appimage",
            ".tar.gz",
            ".zip",
        )
    if system_name == "darwin":
        return (
            "peadra-macos",
            "peadra-mac",
            ".zip",
            ".dmg",
        )
    return ("peadra",)


def select_release_asset(release: ReleaseInfo) -> ReleaseAsset | None:
    preferred_names = tuple(_preferred_asset_names())
    assets = release.assets

    for asset in assets:
        asset_name = asset.name.lower()
        if any(token in asset_name for token in preferred_names):
            return asset

    system_name = platform.system().lower()
    for asset in assets:
        asset_name = asset.name.lower()
        if system_name == "windows" and asset_name.endswith(".exe"):
            return asset
        if system_name == "linux" and (
            asset_name.endswith(".appimage")
            or asset_name.endswith(".tar.gz")
            or asset_name.endswith(".zip")
        ):
            return asset
        if system_name == "darwin" and (
            asset_name.endswith(".zip") or asset_name.endswith(".dmg")
        ):
            return asset

    if system_name == "windows":
        return None

    return assets[0] if assets else None


def check_for_update(timeout: int = DEFAULT_TIMEOUT) -> UpdateCheckResult:
    try:
        release = fetch_latest_release(timeout=timeout)
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
        return UpdateCheckResult(
            available=False,
            current_version=get_current_version(),
            error=str(exc),
        )

    if not is_newer_version(release.version):
        return UpdateCheckResult(
            available=False,
            current_version=get_current_version(),
            latest_version=release.version,
            release_url=release.url or None,
        )

    asset = select_release_asset(release)
    return UpdateCheckResult(
        available=asset is not None,
        current_version=get_current_version(),
        latest_version=release.version,
        release_url=release.url or None,
        asset_name=asset.name if asset else None,
        asset_url=asset.download_url if asset else None,
        error=None if asset else "Aucun asset de mise à jour compatible n'a été trouvé.",
    )


def download_file(url: str, destination: Path, timeout: int = 30) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = _build_request(url)
    with urllib.request.urlopen(request, timeout=timeout) as response, destination.open(
        "wb"
    ) as output:
        shutil.copyfileobj(response, output)
    return destination


def _copy_current_executable_to_temp(executable_path: Path) -> Path:
    updater_dir = Path(tempfile.gettempdir()) / "peadra-updater"
    updater_dir.mkdir(parents=True, exist_ok=True)
    updater_copy = updater_dir / executable_path.name
    shutil.copy2(executable_path, updater_copy)
    return updater_copy


def _wait_for_file_unlock(path: Path, timeout: int = 120) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with path.open("ab"):
                return True
        except OSError:
            time.sleep(1)
    return False


def run_update_mode(source_path: str, target_path: str, restart_args: list[str] | None = None) -> int:
    source = Path(source_path)
    target = Path(target_path)
    restart_args = restart_args or []

    if not source.exists() or not target.exists():
        return 1

    if not _wait_for_file_unlock(target):
        return 2

    try:
        os.replace(source, target)
    except OSError:
        return 3

    try:
        subprocess.Popen([str(target), *restart_args], cwd=str(target.parent))
    except OSError:
        return 4

    return 0


def auto_update_if_needed(timeout: int = DEFAULT_TIMEOUT) -> UpdateCheckResult:
    if not is_frozen_app():
        return UpdateCheckResult(
            available=False,
            current_version=get_current_version(),
            error="Mise à jour automatique désactivée hors exécutable packagé.",
        )

    check = check_for_update(timeout=timeout)
    if not check.available or not check.asset_url:
        return check

    current_executable = Path(sys.executable)
    downloaded_path = Path(tempfile.gettempdir()) / "peadra-update" / (check.asset_name or "peadra-update.exe")

    try:
        download_file(check.asset_url, downloaded_path)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return UpdateCheckResult(
            available=False,
            current_version=check.current_version,
            latest_version=check.latest_version,
            release_url=check.release_url,
            asset_name=check.asset_name,
            asset_url=check.asset_url,
            error=str(exc),
        )

    updater_copy = _copy_current_executable_to_temp(current_executable)
    restart_args = [arg for arg in sys.argv[1:] if arg != "--apply-update"]
    subprocess.Popen(
        [
            str(updater_copy),
            "--apply-update",
            "--source",
            str(downloaded_path),
            "--target",
            str(current_executable),
            "--restart-args",
            json.dumps(restart_args),
        ],
        cwd=str(current_executable.parent),
    )

    os._exit(0)

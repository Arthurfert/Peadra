"""Gestion des mises à jour de l'application via GitHub Releases.

Le module n'utilise que la bibliothèque standard pour rester compatible avec
l'exécutable standalone généré par PyInstaller.
"""

from __future__ import annotations

import json
import errno
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Callable

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


def download_file_with_progress(
    url: str,
    destination: Path,
    on_progress: Callable[[int, int], None] | None = None,
    timeout: int = 30,
) -> Path:
    """Télécharge un fichier avec callback de progression.
    
    Args:
        url: URL du fichier à télécharger
        destination: Chemin de destination
        on_progress: Callback appelé avec (bytes_downloaded, total_bytes)
        timeout: Timeout en secondes
    
    Returns:
        Chemin du fichier téléchargé
    """
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = _build_request(url)
    
    with urllib.request.urlopen(request, timeout=timeout) as response:
        total_size = int(response.headers.get("content-length", 0))
        chunk_size = 8192
        downloaded = 0
        
        with destination.open("wb") as output:
            while True:
                chunk = response.read(chunk_size)
                if not chunk:
                    break
                output.write(chunk)
                downloaded += len(chunk)
                if on_progress and total_size > 0:
                    on_progress(downloaded, total_size)
    
    return destination


def _copy_current_executable_to_temp(executable_path: Path) -> Path:
    updater_dir = Path(tempfile.gettempdir()) / "peadra-updater"
    updater_dir.mkdir(parents=True, exist_ok=True)
    helper_name = (
        "peadra-updater-helper.exe"
        if platform.system().lower() == "windows"
        else "peadra-updater-helper"
    )
    updater_copy = updater_dir / helper_name
    shutil.copy2(executable_path, updater_copy)
    _ensure_executable(updater_copy)
    return updater_copy


def _ensure_executable(path: Path) -> None:
    if platform.system().lower() == "windows":
        return
    try:
        mode = path.stat().st_mode
        path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except OSError:
        pass


def _replace_file_with_fallback(source: Path, target: Path) -> None:
    try:
        os.replace(source, target)
        return
    except OSError as exc:
        # Cas classique Linux: /tmp est sur un autre filesystem que l'app.
        if exc.errno != errno.EXDEV:
            raise

    staged_target = target.with_name(f"{target.name}.new")
    if staged_target.exists():
        staged_target.unlink(missing_ok=True)

    shutil.copy2(source, staged_target)
    _ensure_executable(staged_target)
    os.replace(staged_target, target)
    source.unlink(missing_ok=True)


def _wait_for_file_unlock(path: Path, timeout: int = 120) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with path.open("ab"):
                return True
        except OSError:
            time.sleep(1)
    return False


def run_update_mode(
    source_path: str,
    target_path: str,
    restart_args: list[str] | None = None,
    terminate_pid: int | None = None,
) -> int:
    def _append_update_log(msg: str):
        try:
            log_file = Path(tempfile.gettempdir()) / "peadra-update.log"
            ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(f"{ts}Z - updater_mode: {msg}\n")
        except OSError:
            pass

    source = Path(source_path)
    target = Path(target_path)
    restart_args = restart_args or []

    _append_update_log(
        f"start source={source} target={target} terminate_pid={terminate_pid}"
    )

    if not source.exists() or not target.exists():
        _append_update_log("source or target missing")
        return 1

    if platform.system().lower() == "windows":
        # Le helper s'appelle peadra-updater-helper.exe, on peut donc tuer
        # sans risque toutes les instances Peadra.exe restantes (parent + child).
        try:
            result = subprocess.run(
                ["taskkill", "/IM", "Peadra.exe", "/T", "/F"],
                check=False,
                capture_output=True,
                text=True,
            )
            stdout = (result.stdout or "").strip().replace("\n", " | ")
            stderr = (result.stderr or "").strip().replace("\n", " | ")
            _append_update_log(
                f"taskkill /IM returncode={result.returncode} stdout='{stdout}' stderr='{stderr}'"
            )

            # Fallback: si /IM échoue mais qu'on a un PID initial, tenter un kill direct.
            if result.returncode != 0 and terminate_pid:
                pid_result = subprocess.run(
                    ["taskkill", "/PID", str(terminate_pid), "/T", "/F"],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                pid_stdout = (pid_result.stdout or "").strip().replace("\n", " | ")
                pid_stderr = (pid_result.stderr or "").strip().replace("\n", " | ")
                _append_update_log(
                    f"taskkill /PID returncode={pid_result.returncode} stdout='{pid_stdout}' stderr='{pid_stderr}'"
                )
        except OSError as exc:
            _append_update_log(f"taskkill /IM failed: {exc}")

    elif terminate_pid:
        try:
            os.kill(terminate_pid, 15)
            _append_update_log(f"sent SIGTERM to pid={terminate_pid}")
        except OSError as exc:
            _append_update_log(f"SIGTERM failed for pid={terminate_pid}: {exc}")

    if not _wait_for_file_unlock(target):
        _append_update_log("target remained locked after wait")
        return 2

    try:
        _replace_file_with_fallback(source, target)
        _ensure_executable(target)
    except OSError as exc:
        _append_update_log(f"file replace failed: {exc}")
        return 3

    try:
        if platform.system().lower() == "windows":
            subprocess.Popen(
                [str(target), *restart_args],
                cwd=str(target.parent),
                creationflags=(
                    subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
                ),
            )
        else:
            subprocess.Popen([str(target), *restart_args], cwd=str(target.parent))
        _append_update_log("restart subprocess started")
    except OSError:
        _append_update_log("restart subprocess failed")
        return 4

    _append_update_log("update applied and restart launched")

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

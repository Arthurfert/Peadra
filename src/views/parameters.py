"""
Vue Paramètres pour Peadra.
Permet de configurer le thème, l'import/export et le mode de calcul mensuel.
"""

import json
import logging
import os
import sys
import tempfile
import threading
import time
from datetime import datetime
from typing import Callable, Any, cast, List, Optional
from pathlib import Path

import flet as ft

logger = logging.getLogger(__name__)
from ..components.theme import PeadraTheme
from ..database import db
from ..i18n import t
from ..logger import get_current_log_path
from ..update_manager import (
    _copy_current_executable_to_temp,
    auto_update_if_needed,
    check_for_update,
    download_file_with_progress,
    fetch_latest_release,
    get_current_version,
    is_frozen_app,
    run_update_mode,
)


def get_asset_path(filename: str) -> str:
    """Retourne le chemin absolu d'un asset."""
    if getattr(sys, "frozen", False):
        # Code exécuté depuis PyInstaller/flet pack
        base_path = getattr(sys, "_MEIPASS", "")
    else:
        # Code en développement
        base_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        base_path = os.path.dirname(base_path)  # Remontée à la racine
    return os.path.join(base_path, filename)


class CustomSavePicker:
    """Sélecteur de dossier et nom de fichier personnalisé (Save File)."""

    def __init__(
        self,
        page: ft.Page,
        on_select: Callable[[str], None],
        on_cancel: Callable[[], None],
        default_extension: str = "",
    ):
        self.page = page
        self.on_select = on_select
        self.on_cancel = on_cancel
        self.default_extension = default_extension
        self.current_path = os.getcwd()

        self.path_text = ft.Text(value=self.current_path, size=12, color=PeadraTheme.placeholder_color)
        self.file_list = ft.ListView(expand=True, spacing=2)
        self.filename_field = ft.TextField(
            label=t("param_file_name"), expand=True, height=40, text_size=13
        )

        self.dialog = ft.AlertDialog(
            title=ft.Text(t("param_file_picker_title")),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.Row(
                            [
                                ft.IconButton(
                                    icon=ft.Icons.ARROW_UPWARD,
                                    on_click=self._go_up,
                                    tooltip=t("param_file_go_up"),
                                ),
                                ft.Container(
                                    content=self.path_text, expand=True, padding=5
                                ),
                            ],
                            alignment=ft.MainAxisAlignment.START,
                        ),
                        ft.Divider(height=1),
                        self.file_list,
                        ft.Divider(height=1),
                        ft.Row(
                            [self.filename_field], alignment=ft.MainAxisAlignment.CENTER
                        ),
                    ],
                    spacing=10,
                ),
                width=600,
                height=400,
                padding=10,
            ),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=lambda _: self._cancel()),
                ft.ElevatedButton(t("btn_save"), on_click=lambda _: self._save()),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

    def _cancel(self):
        self.dialog.open = False
        self.page.update()
        self.on_cancel()

    def _save(self):
        filename = (
            self.filename_field.value.strip() if self.filename_field.value else "export"
        )
        if not filename.endswith(f".{self.default_extension}"):
            filename += f".{self.default_extension}"

        full_path = os.path.join(self.current_path, filename)
        self.dialog.open = False
        self.page.update()
        self.on_select(full_path)

    def open(self, default_filename: str = "export", extension: str = "csv"):
        self.default_extension = extension
        self.filename_field.value = default_filename
        self._refresh_file_list()
        self.page.show_dialog(self.dialog)
        self.page.update()

    def _refresh_file_list(self):
        self.path_text.value = self.current_path
        self.file_list.controls.clear()

        try:
            items = os.listdir(self.current_path)
            # Sort folders first, then files
            folders = []
            files = []
            for item in items:
                full_item_path = os.path.join(self.current_path, item)
                if os.path.isdir(full_item_path):
                    folders.append(item)
                else:
                    files.append(item)

            folders.sort(key=str.lower)
            files.sort(key=str.lower)

            # Add folders
            for folder in folders:
                self.file_list.controls.append(
                    ft.ListTile(
                        leading=ft.Icon(ft.Icons.FOLDER, color=ft.Colors.AMBER),
                        title=ft.Text(folder),
                        on_click=lambda e, f=folder: self._navigate(f),
                    )
                )

            # Add files (just for viewing)
            for file in files:
                self.file_list.controls.append(
                    ft.ListTile(
                        leading=ft.Icon(
                            ft.Icons.INSERT_DRIVE_FILE, color=PeadraTheme.placeholder_color
                        ),
                        title=ft.Text(file, color=PeadraTheme.placeholder_color),
                    )
                )

        except Exception as e:
            self.file_list.controls.append(
                ft.Text(f"{t('param_file_error')} {e}", color=ft.Colors.ERROR)
            )

        self.page.update()

    def _navigate(self, folder_name: str):
        self.current_path = os.path.join(self.current_path, folder_name)
        self._refresh_file_list()

    def _go_up(self, _):
        parent = os.path.dirname(self.current_path)
        if parent and parent != self.current_path:
            self.current_path = parent
            self._refresh_file_list()


class ParametersView:
    """Vue des paramètres de l'application."""

    def __init__(
        self,
        page: ft.Page,
        theme_mode: str,
        on_data_change: Callable,
        on_toggle_theme: Callable,
        on_import: Callable,
        on_export: Callable,
        on_account_deleted: Optional[Callable] = None,
        on_language_change: Optional[Callable] = None,
    ):
        self.page = page
        self.theme_mode = theme_mode
        self.is_dark = theme_mode != "light"
        self.on_data_change = on_data_change
        self.on_toggle_theme = on_toggle_theme
        self.on_import = on_import
        self.on_export = on_export
        self.on_account_deleted = on_account_deleted or (lambda: None)
        self.on_language_change = on_language_change or (lambda language: None)
        # Charger le username depuis la base de données
        self.user_name = db.get_current_username() or ""
        # Charger le mode depuis la base de données
        self.month_mode = db.get_setting("month_mode", "strict") or "strict"
        self.display_limit = db.get_setting("transactions_display_limit", "30") or "30"
        self.max_categories_pie = db.get_setting("max_categories_pie", "5") or "5"
        self.currency = db.get_setting("currency", "€") or "€"
        # Charger la langue depuis la base de données
        self.language = db.get_setting("language", "en") or "en"
        self.current_version = get_current_version()

        self._pending_export_format = ""
        # Stocke la clé et les paramètres pour les mises à jour de statut
        self.update_status_key = "param_update_status_idle"
        self.update_status_params: dict = {}
        self.update_status = t(self.update_status_key)
        self.update_status_text = ft.Text(
            self.update_status, size=12, color=PeadraTheme.placeholder_color
        )
        self.update_available = False
        self.update_button: Optional[ft.OutlinedButton] = None
        self.changelog_button: Optional[ft.OutlinedButton] = None
        self.save_picker = CustomSavePicker(
            page=self.page,
            on_select=self._on_save_file_selected,
            on_cancel=self._on_save_picker_cancel,
        )

    def _on_save_file_selected(self, file_path: str):
        if self._pending_export_format == "logs":
            self._copy_log_file(file_path)
        elif self._pending_export_format:
            self.on_export(self._pending_export_format, file_path)

    def _on_save_picker_cancel(self):
        pass

    def _on_user_name_change(self, e):
        """Gère le changement du nom de l'utilisateur."""
        value = e.control.value
        if value is not None:
            self.user_name = value

    def _on_user_name_blur(self, e):
        """Met à jour l'username dans la base de données quand on a terminé de saisir."""
        new_username = self.user_name.strip()
        if not new_username:
            # Annuler le changement
            e.control.value = db.get_current_username()
            self.page.update()
            return

        # Vérifier que le nouveau username n'existe pas (autre que l'utilisateur courant)
        current_username = db.get_current_username()
        if new_username != current_username and db.user_exists(new_username):
            # Afficher une erreur et annuler
            e.control.value = current_username
            self.page.update()
            return

        # Mettre à jour le username dans la base de données si différent
        if new_username != current_username:
            try:
                db.update_username(new_username)
                self.user_name = new_username
                self.on_data_change()
            except ValueError:
                # Annuler le changement
                e.control.value = current_username
                self.page.update()

    def update_theme(self, theme_mode: str):
        """Met à jour le thème."""
        self.theme_mode = theme_mode
        self.is_dark = theme_mode != "light"

    def refresh(self):
        """Rafraîchit la vue (gérée par la reconstruction globale de l'UI)."""
        # ParametersView n'a pas de contenu réutilisable interne.
        # La reconstruction globale dans main.py gère le refresh complet.
        pass

    def get_month_mode(self) -> str:
        """Retourne le mode de mois actuel."""
        return self.month_mode

    def _build_section_card(
        self, title: str, icon: Any, children: List[ft.Control]
    ) -> ft.Container:
        """Construit une carte de section de paramètres."""
        text_color = PeadraTheme.text
        bg_card = (
            PeadraTheme.surface
        )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(cast(Any, icon), color=PeadraTheme.accent, size=24),
                            ft.Text(
                                title,
                                size=18,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        spacing=12,
                    ),
                    ft.Divider(
                        height=1,
                        color=PeadraTheme.divider,
                    ),
                    ft.Container(height=8),
                    *children,
                ],
                spacing=8,
            ),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            border=(
                ft.border.all(1, PeadraTheme.divider)
                if not self.is_dark
                else None
            ),
        )

    def _build_setting_row(
        self,
        label: str,
        description: Any,
        control: ft.Control,
    ) -> ft.Container:
        """Construit une ligne de paramètre."""
        text_color = PeadraTheme.text

        if isinstance(description, ft.Control):
            description_control = description
        else:
            description_control = ft.Text(description, size=12, color=PeadraTheme.placeholder_color)

        return ft.Container(
            content=ft.Row(
                [
                    ft.Column(
                        [
                            ft.Text(
                                label,
                                size=15,
                                weight=ft.FontWeight.W_500,
                                color=text_color,
                            ),
                            description_control,
                        ],
                        spacing=2,
                        expand=True,
                    ),
                    control,
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            padding=ft.padding.symmetric(vertical=8, horizontal=4),
        )

    def _build_theme_option(
        self, label: str, image_src: str, theme_val: str
    ) -> ft.Container:
        """Construit une option de thème cliquable."""
        is_selected = self.theme_mode == theme_val
        border_color = (
            PeadraTheme.accent
            if is_selected
            else PeadraTheme.divider
        )

        def on_click(e):
            if self.theme_mode != theme_val:
                self.on_toggle_theme(theme_val)

        return ft.Container(
            content=ft.Column(
                [
                    ft.Container(
                        content=ft.Image(
                            src=image_src,
                            fit=ft.BoxFit.CONTAIN,
                            border_radius=9,
                        ),
                        border=ft.border.all(3, border_color),
                        border_radius=12,
                        ink=True,
                        on_click=on_click,
                    ),
                    ft.Text(
                        label,
                        weight=(
                            ft.FontWeight.BOLD if is_selected else ft.FontWeight.NORMAL
                        ),
                        color=PeadraTheme.text,
                    ),
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                spacing=8,
            ),
            width=250,
        )

    def _on_month_mode_change(self, e):
        """Gère le changement de mode mois."""
        selected = list(e.control.selected)
        if selected:
            self.month_mode = selected[0]
            # Sauvegarder dans la base de données
            db.set_setting("month_mode", self.month_mode)
            self.on_data_change()

    def _on_display_limit_change(self, e):
        """Gère le changement du nombre de transactions affichées."""
        value = e.control.value
        if value:
            # Conserver uniquement les chiffres et ignorer le reste (comme les signes moins ou lettres)
            clean_value = "".join(filter(str.isdigit, value))

            # Si le champ contenait des caractères non numériques, on met à jour la vue avec la version propre
            if clean_value != value:
                e.control.value = clean_value
                e.control.update()

            if clean_value and int(clean_value) > 0:
                self.display_limit = clean_value
                db.set_setting("transactions_display_limit", self.display_limit)

    def _on_display_limit_blur(self, e):
        """Met à jour les données seulement quand on a terminé de saisir."""
        if self.display_limit and int(self.display_limit) > 0:
            self.on_data_change()

    def _on_max_categories_change(self, e):
        """Gère le changement du nombre max de catégories dans les pie charts."""
        value = e.control.value
        if value:
            clean_value = "".join(filter(str.isdigit, value))
            if clean_value != value:
                e.control.value = clean_value
                e.control.update()
            if clean_value and int(clean_value) > 0:
                self.max_categories_pie = clean_value
                db.set_setting("max_categories_pie", self.max_categories_pie)

    def _on_max_categories_blur(self, e):
        if self.max_categories_pie and int(self.max_categories_pie) > 0:
            self.on_data_change()

    def _on_currency_change(self, e):
        """Gère le changement de devise."""
        self.currency = e.control.value
        db.set_setting("currency", self.currency)
        self.on_data_change()

    def _on_language_change(self, e):
        """Gère le changement de langue."""
        selected_language = e.control.value
        if selected_language and selected_language != self.language:
            self.language = selected_language
            db.set_setting("language", self.language)
            # Mettre à jour le texte de statut avec la nouvelle langue
            self._refresh_update_status()
            self.on_language_change(self.language)

    def _on_export_json(self, e):
        """Lance l'export JSON."""
        self._pending_export_format = "json"
        from datetime import datetime

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.save_picker.open(
            default_filename=f"peadra_export_{timestamp}", extension="json"
        )

    def _on_export_csv(self, e):
        """Lance l'export CSV."""
        self._pending_export_format = "csv"
        from datetime import datetime

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.save_picker.open(
            default_filename=f"peadra_transactions_{timestamp}", extension="csv"
        )

    def _on_export_logs(self, e):
        """Lance l'export du fichier de log courant."""
        log_path = get_current_log_path()
        if not log_path or not os.path.exists(log_path):
            from ..i18n import t

            snack = ft.SnackBar(
                content=ft.Text(t("msg_export_error"), color=ft.Colors.WHITE),
                bgcolor=PeadraTheme.error,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            logger.warning("Log export attempted but no active log file found")
            return
        self._pending_export_format = "logs"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.save_picker.open(
            default_filename=f"peadra_logs_{timestamp}", extension="log"
        )

    def _copy_log_file(self, dest_path: str):
        """Copie le fichier de log courant vers la destination."""
        log_path = get_current_log_path()
        if log_path and os.path.exists(log_path):
            try:
                import shutil

                shutil.copy2(log_path, dest_path)
                logger.info("Log file exported to %s", dest_path)
                self._show_snackbar(
                    t("msg_export_success").format(file_path=dest_path), success=True
                )
            except Exception:
                logger.error("Failed to copy log file to %s", dest_path)
                self._show_snackbar(t("msg_export_error"), success=False)
        else:
            self._show_snackbar(t("msg_export_error"), success=False)

    def _show_snackbar(self, message: str, success: bool = True):
        color = PeadraTheme.success if success else PeadraTheme.error
        snack = ft.SnackBar(
            content=ft.Text(message, color=ft.Colors.WHITE),
            bgcolor=color,
            duration=3000,
        )
        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    def _on_import_csv(self, e):
        """Lance l'import CSV."""
        self.on_import()

    def _set_update_status(self, key: str, **params):
        """Met à jour le statut de mise à jour avec la clé de traduction et ses paramètres."""
        self.update_status_key = key
        self.update_status_params = params
        self.update_status = t(key).format(**params) if params else t(key)
        if hasattr(self, "update_status_text"):
            self.update_status_text.value = self.update_status
        self.page.update()

    def _refresh_update_status(self):
        """Rafraîchit le texte de statut avec la langue actuelle."""
        self.update_status = (
            t(self.update_status_key).format(**self.update_status_params)
            if self.update_status_params
            else t(self.update_status_key)
        )
        if hasattr(self, "update_status_text"):
            self.update_status_text.value = self.update_status

    def _set_update_button_mode(self, install_mode: bool):
        self.update_available = install_mode
        if self.update_button is None:
            return

        if install_mode:
            self.update_button.content = ft.Text(t("param_install_update"))
            self.update_button.icon = ft.Icons.DOWNLOAD
        else:
            self.update_button.content = ft.Text(t("param_check_updates"))
            self.update_button.icon = ft.Icons.SYSTEM_UPDATE_ALT

        try:
            self.update_button.update()
        except RuntimeError:
            pass

        if self.changelog_button is not None:
            self.changelog_button.visible = install_mode
            try:
                self.changelog_button.update()
            except RuntimeError:
                pass

    def _show_changelog_dialog(self, title: str, body: str, url: str | None = None):
        content_children: List[ft.Control] = [
            ft.Text(body or t("param_changelog_empty"), selectable=True),
        ]

        if url:
            content_children.append(ft.Text(url, size=12, color=PeadraTheme.placeholder_color))

        dialog = ft.AlertDialog(
            title=ft.Text(title, weight=ft.FontWeight.BOLD),
            content=ft.Container(
                content=ft.Column(
                    content_children,
                    spacing=12,
                    scroll=ft.ScrollMode.AUTO,
                    tight=True,
                ),
                width=700,
                height=500,
                padding=8,
            ),
            actions=[
                ft.TextButton(
                    t("btn_close"), on_click=lambda _: self._close_dialog(dialog)
                )
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.show_dialog(dialog)
        self.page.update()

    def _close_dialog(self, dialog: ft.AlertDialog):
        dialog.open = False
        self.page.update()

    def _on_see_whats_new(self, e):
        """Affiche le changelog de la dernière release GitHub."""
        if not is_frozen_app():
            self._show_changelog_dialog(
                t("param_changelog_title"),
                t("param_changelog_not_supported"),
            )
            return

        try:
            release = fetch_latest_release()
        except Exception as exc:
            self._show_changelog_dialog(
                t("param_changelog_title"),
                t("param_changelog_error").format(error=exc),
            )
            return

        header = f"{release.name} ({release.version})"
        body = release.body.strip() or t("param_changelog_empty")
        self._show_changelog_dialog(header, body, release.url or None)

    def _on_check_updates(self, e):
        """Vérifie si une MAJ est dispo, puis propose l'installation au clic suivant."""
        if not is_frozen_app():
            self._set_update_status("param_update_status_not_supported")
            return

        if self.update_available:
            # Lancer le téléchargement et l'installation dans un thread
            self._show_update_progress_dialog()
            return

        self._set_update_status("param_update_status_checking")
        result = check_for_update()

        if result.error and not result.available:
            self._set_update_status("param_update_status_error", error=result.error)
            self._set_update_button_mode(False)
            return

        if not result.available:
            self._set_update_status("param_update_status_up_to_date")
            self._set_update_button_mode(False)
            return

        self._set_update_status(
            "param_update_status_available", version=result.latest_version or "?"
        )
        self._set_update_button_mode(True)

    def _show_update_progress_dialog(self):
        """Affiche un dialog de progression pour la mise à jour."""
        progress_text = ft.Text(
            t("param_update_status_downloading").format(percent=0),
            size=14,
            color=PeadraTheme.text,
        )
        progress_bar = ft.ProgressBar(value=0, width=400)
        instructions_text = ft.Text(
            t("param_update_instructions").format(percent=0),
            size=14,
            color=PeadraTheme.text,
        )

        dialog = ft.AlertDialog(
            title=ft.Text(t("param_updates")),
            content=ft.Container(
                content=ft.Column(
                    [progress_text, progress_bar, instructions_text],
                    spacing=16,
                    alignment=ft.MainAxisAlignment.CENTER,
                    tight=True,
                ),
                padding=16,
            ),
            modal=True,
        )

        self.page.show_dialog(dialog)
        self.page.update()

        progress_session = f"update-{int(time.time() * 1000)}"

        def on_progress_message(message):
            if not isinstance(message, dict):
                return
            if message.get("session") != progress_session:
                return

            msg_type = message.get("type")
            if msg_type == "progress":
                progress_text.value = message.get("message", "")
                progress_bar.value = message.get("value", 0)
            elif msg_type == "error":
                progress_text.value = message.get("message", "Erreur")
                progress_bar.value = 0
            elif msg_type == "complete":
                progress_text.value = t("param_update_status_installing")
                progress_bar.value = 1.0
            elif msg_type == "shutdown":
                dialog.open = False

            try:
                self.page.update()
            except RuntimeError:
                pass

            if msg_type in ("error", "shutdown"):
                try:
                    self.page.pubsub.unsubscribe()
                except Exception:
                    pass

        try:
            self.page.pubsub.subscribe(on_progress_message)
        except Exception:
            pass

        # Lancer le téléchargement et l'installation dans un autre thread
        thread = threading.Thread(
            target=self._perform_update_with_progress, args=(progress_session,)
        )
        thread.daemon = False
        thread.start()

    def _perform_update_with_progress(self, progress_session: str):
        """Effectue la mise à jour en affichant la progression et journalise pour le debug."""

        logger.info("_perform_update_with_progress: started")

        try:
            import subprocess

            # Récupérer les infos de la mise à jour
            result = check_for_update()
            logger.info(
                "check_for_update: available=%s latest=%s asset=%s",
                result.available,
                result.latest_version,
                result.asset_name,
            )

            if not result.available or not result.asset_url or not result.asset_name:
                self.page.pubsub.send_all(
                    {
                        "session": progress_session,
                        "type": "error",
                        "message": t("param_update_status_error").format(
                            error="Impossible de récupérer la mise à jour"
                        ),
                    }
                )
                logger.warning("no update available or missing asset")
                return

            # Chemin de destination pour le téléchargement
            downloaded_path = (
                Path(tempfile.gettempdir()) / "peadra-update" / result.asset_name
            )
            logger.info("download destination: %s", downloaded_path)

            # Callback de progression
            last_logged_step = {"value": -1}

            def on_progress(downloaded: int, total: int):
                if total > 0:
                    percent = int((downloaded / total) * 100)
                    self.page.pubsub.send_all(
                        {
                            "session": progress_session,
                            "type": "progress",
                            "message": t("param_update_status_downloading").format(
                                percent=percent
                            ),
                            "value": min(percent / 100.0, 0.99),
                        }
                    )
                    # Log uniquement quand on passe une nouvelle tranche de 5%
                    step = percent // 5
                    if step != last_logged_step["value"]:
                        last_logged_step["value"] = step
                        logger.debug(
                            "download progress: %d%% (%d/%d)",
                            percent,
                            downloaded,
                            total,
                        )

            # Télécharger le fichier
            logger.info("starting download from: %s", result.asset_url)
            download_file_with_progress(
                result.asset_url, downloaded_path, on_progress=on_progress
            )
            logger.info("download finished")

            # Afficher "Downloaded, installing..."
            self.page.pubsub.send_all(
                {
                    "session": progress_session,
                    "type": "progress",
                    "message": t("param_update_status_downloaded"),
                    "value": 0.95,
                }
            )
            logger.debug("queued downloaded->installing message")

            # Préparer la mise à jour
            current_executable = Path(sys.executable)
            updater_copy = _copy_current_executable_to_temp(current_executable)
            logger.info("copied updater to: %s", updater_copy)

            # Passer le contrôle au updater
            restart_args = [arg for arg in sys.argv[1:] if arg != "--apply-update"]
            try:
                p = subprocess.Popen(
                    [
                        str(updater_copy),
                        "--apply-update",
                        "--source",
                        str(downloaded_path),
                        "--target",
                        str(current_executable),
                        "--terminate-pid",
                        str(os.getpid()),
                        "--restart-args",
                        json.dumps(restart_args),
                    ],
                    cwd=str(current_executable.parent),
                )
                logger.info("launched updater pid=%s", getattr(p, "pid", None))
            except Exception as e:
                self.page.pubsub.send_all(
                    {
                        "session": progress_session,
                        "type": "error",
                        "message": t("param_update_status_error").format(
                            error=f"Erreur subprocess: {str(e)}"
                        ),
                    }
                )
                logger.error("subprocess launch failed: %s", str(e))
                return

            # Afficher "Installing" à 100% avant de quitter
            self.page.pubsub.send_all(
                {
                    "session": progress_session,
                    "type": "complete",
                    "message": t("param_update_status_installing"),
                    "value": 1.0,
                }
            )
            logger.debug("queued complete message")

            # Demander la fermeture de la fenêtre depuis le thread UI
            self.page.pubsub.send_all({"session": progress_session, "type": "shutdown"})

            # Attendre que les messages soient traités
            time.sleep(0.15)

            # Tentative de fermeture locale (en secours) puis sortie forcée.
            try:
                logger.info("attempting graceful shutdown (SIGTERM)")
                import signal

                os.kill(os.getpid(), signal.SIGTERM)
                time.sleep(0.05)
            except Exception as e:
                logger.warning("SIGTERM failed: %s", e)

            # On Windows, SIGTERM may not terminate the process; attempt TerminateProcess
            try:
                if sys.platform.startswith("win"):
                    logger.info("attempting Windows TerminateProcess fallback")
                    import ctypes

                    try:
                        ctypes.windll.kernel32.TerminateProcess(
                            ctypes.windll.kernel32.GetCurrentProcess(), 0
                        )
                    except Exception as ce:
                        logger.warning("TerminateProcess failed: %s", ce)
            except Exception:
                pass

            try:
                logger.info("final os._exit(0)")
                os._exit(0)
            except Exception as e:
                logger.warning("os._exit failed: %s", e)

        except Exception as exc:
            self.page.pubsub.send_all(
                {
                    "session": progress_session,
                    "type": "error",
                    "message": t("param_update_status_error").format(error=str(exc)),
                }
            )
            try:
                logger.error("exception in update flow: %s", str(exc))
            except Exception:
                pass
            try:
                self._set_update_status("param_update_status_error", error=str(exc))
                self._set_update_button_mode(False)
            except RuntimeError:
                pass

    def _on_change_password_click(self, e):
        from src.database import db
        import hashlib

        has_password = bool(db.get_setting("app_password_hash"))

        old_pwd_field = ft.TextField(
            password=True,
            can_reveal_password=True,
            label=t("param_old_password"),
            width=300,
            height=45,
            text_size=13,
        )
        pwd_field = ft.TextField(
            password=True,
            can_reveal_password=True,
            label=t("param_password_new"),
            width=300,
            height=45,
            text_size=13,
        )
        confirm_field = ft.TextField(
            password=True,
            can_reveal_password=True,
            label=t("param_password_confirm"),
            width=300,
            height=45,
            text_size=13,
        )
        message = ft.Text(size=12)

        content_col = ft.Column(
            spacing=12,
            width=340,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            controls=[old_pwd_field, pwd_field, confirm_field, message],
        )

        def on_save(_):
            current_hash = db.get_setting("app_password_hash")
            if current_hash:
                old_pwd = old_pwd_field.value
                if not old_pwd:
                    message.value = t("param_password_empty")
                    message.color = ft.Colors.RED
                    self.page.update()
                    return
                if hashlib.sha256(old_pwd.encode()).hexdigest() != current_hash:
                    message.value = t("param_old_password_incorrect")
                    message.color = ft.Colors.RED
                    self.page.update()
                    return
            pwd = pwd_field.value
            confirm = confirm_field.value
            if not pwd:
                message.value = t("param_password_empty")
                message.color = ft.Colors.RED
                self.page.update()
                return
            if pwd != confirm:
                message.value = t("param_password_mismatch")
                message.color = ft.Colors.RED
                self.page.update()
                return
            hashed = hashlib.sha256(pwd.encode()).hexdigest()
            db.set_setting("app_password_hash", hashed)
            message.value = t("param_password_saved")
            message.color = PeadraTheme.success
            pwd_field.value = ""
            confirm_field.value = ""
            old_pwd_field.value = ""
            remove_btn.visible = True
            self.page.update()
            logger.info("App password was set")
            pwd = None
            confirm = None

        def on_remove(_):
            db.set_setting("app_password_hash", "")
            logger.info("App password was removed")
            message.value = t("param_password_removed")
            message.color = PeadraTheme.success
            remove_btn.visible = False
            old_pwd_field.value = ""
            pwd_field.value = ""
            confirm_field.value = ""
            self.page.update()

        def on_close(_):
            dialog.open = False
            self.page.update()

        remove_btn = ft.ElevatedButton(
            t("param_btn_remove"),
            icon=ft.Icons.DELETE_OUTLINED,
            on_click=on_remove,
            color=PeadraTheme.delete_color,
            visible=has_password,
        )
        save_btn = ft.ElevatedButton(
            t("param_btn_save"),
            icon=ft.Icons.SAVE_OUTLINED,
            on_click=on_save,
        )

        dialog = ft.AlertDialog(
            title=ft.Text(
                t("param_change_password"), size=20, weight=ft.FontWeight.BOLD
            ),
            content=ft.Container(
                content=content_col,
                padding=ft.padding.only(left=20, right=20, top=10, bottom=10),
                height=200,
            ),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=on_close),
                remove_btn,
                save_btn,
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.show_dialog(dialog)
        self.page.update()

    def _on_delete_account_click(self, e):
        """Affiche une boîte de dialogue pour confirmer la suppression du compte."""
        password_field = ft.TextField(
            password=True,
            can_reveal_password=True,
            label=t("param_password"),
            width=300,
            height=45,
        )
        error_message = ft.Text(size=12, color=ft.Colors.ERROR)

        def on_confirm(_):
            pwd = password_field.value.strip()
            if not pwd:
                error_message.value = t("param_delete_password_required")
                self.page.update()
                return

            # Vérifier le mot de passe et supprimer le compte
            if db.delete_user_account(pwd):
                dialog.open = False
                self.page.update()
                self.on_account_deleted()
                logger.info("User account deleted")
                pwd = None
            else:
                error_message.value = t("param_delete_password_incorrect")
                self.page.update()
                pwd = None

        def on_cancel(_):
            dialog.open = False
            self.page.update()

        dialog = ft.AlertDialog(
            title=ft.Text(
                t("param_delete_confirm"), size=20, weight=ft.FontWeight.BOLD
            ),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.Text(
                            t("param_delete_warning"),
                            size=14,
                            color=ft.Colors.ERROR,
                        ),
                        ft.Container(height=16),
                        ft.Text(
                            t("param_delete_password_prompt"),
                            size=13,
                            weight=ft.FontWeight.W_500,
                        ),
                        password_field,
                        error_message,
                    ],
                    spacing=12,
                ),
                padding=20,
                width=400,
                height=220,
            ),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=on_cancel),
                ft.TextButton(
                    t("param_delete_confirm"),
                    on_click=on_confirm,
                    style=ft.ButtonStyle(color=PeadraTheme.delete_color),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        self.page.show_dialog(dialog)
        self.page.update()

    def build(self) -> ft.Container:
        """Construit la vue paramètres."""
        text_color = PeadraTheme.text

        # === Section Général ===
        user_name_field = ft.TextField(
            value=self.user_name,
            label=t("param_username"),
            width=250,
            on_change=self._on_user_name_change,
            on_blur=self._on_user_name_blur,
        )

        # === Section Apparence ===
        theme_options = ft.Row(
            [
                self._build_theme_option(
                    t("param_light_theme"),
                    get_asset_path("assets/Dashboard_Light.jpg"),
                    "light",
                ),
                self._build_theme_option(
                    t("param_dark_theme"),
                    get_asset_path("assets/Dashboard.jpg"),
                    "dark",
                ),
                self._build_theme_option(
                    t("param_autumn_theme"),
                    get_asset_path("assets/Dashboard_Autumn.jpg"),
                    "autumn",
                ),
            ],
            spacing=20,
            alignment=ft.MainAxisAlignment.START,
        )

        currency_dropdown = ft.Dropdown(
            value=self.currency,
            options=[
                ft.dropdown.Option("€", t("param_currency_euro")),
                ft.dropdown.Option("$", t("param_currency_usd")),
                ft.dropdown.Option("£", t("param_currency_gbp")),
                ft.dropdown.Option("¥", t("param_currency_jpy")),
            ],
            width=200,
            on_select=self._on_currency_change,
        )

        language_dropdown = ft.Dropdown(
            value=self.language,
            options=[
                ft.dropdown.Option("en", t("param_language_en")),
                ft.dropdown.Option("fr", t("param_language_fr")),
            ],
            width=200,
            on_select=self._on_language_change,
        )

        general_section = self._build_section_card(
            t("param_general"),
            ft.Icons.SETTINGS_OUTLINED,
            [
                self._build_setting_row(
                    t("param_currency"),
                    t("param_currency_desc"),
                    currency_dropdown,
                ),
                self._build_setting_row(
                    t("param_language_label"),
                    t("param_language_desc"),
                    language_dropdown,
                ),
                ft.Container(height=8),
                ft.Column(
                    [
                        ft.Text(
                            t("param_theme_label"),
                            size=15,
                            weight=ft.FontWeight.W_500,
                            color=text_color,
                        ),
                        ft.Text(
                            t("param_theme_desc"),
                            size=12,
                            color=PeadraTheme.placeholder_color,
                        ),
                    ],
                    spacing=2,
                ),
                ft.Container(height=8),
                theme_options,
            ],
        )

        # === Section Données ===
        import_btn = ft.ElevatedButton(
            content=t("param_import_csv"),
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._on_import_csv,
            style=ft.ButtonStyle(
                bgcolor=PeadraTheme.accent,
                color=ft.Colors.WHITE,
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
            ),
        )

        export_json_btn = ft.OutlinedButton(
            content=t("param_export_json"),
            icon=ft.Icons.DATA_OBJECT,
            on_click=self._on_export_json,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.accent),
                color=PeadraTheme.accent,
            ),
        )

        export_csv_btn = ft.OutlinedButton(
            content=ft.Row(
                [
                    ft.Icon(ft.Icons.TABLE_CHART, size=18),
                    ft.Text(t("param_export_csv")),
                ],
                spacing=8,
            ),
            on_click=self._on_export_csv,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.accent),
                color=PeadraTheme.accent,
            ),
        )

        self.update_button = ft.OutlinedButton(
            content=ft.Text(t("param_check_updates")),
            icon=ft.Icons.SYSTEM_UPDATE_ALT,
            on_click=self._on_check_updates,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.accent),
                color=PeadraTheme.accent,
            ),
        )

        self.changelog_button = ft.OutlinedButton(
            content=ft.Text(t("param_see_whats_new")),
            icon=ft.Icons.INFO_OUTLINED,
            on_click=self._on_see_whats_new,
            visible=False,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.accent),
                color=PeadraTheme.accent,
            ),
        )

        # Restaurer l'état du panneau après une reconstruction de la vue,
        # notamment lors d'un changement de langue.
        self._set_update_button_mode(self.update_available)

        quick_update_panel = ft.Container(
            content=ft.Row(
                [
                    ft.Column(
                        [
                            ft.Text(
                                t("param_updates"),
                                size=15,
                                weight=ft.FontWeight.W_600,
                                color=text_color,
                            ),
                            ft.Text(
                                f"{t('param_version')} {self.current_version}",
                                size=12,
                                color=PeadraTheme.placeholder_color,
                            ),
                            self.update_status_text,
                        ],
                        spacing=2,
                        expand=True,
                    ),
                    ft.Column(
                        [self.update_button, self.changelog_button],
                        spacing=8,
                        horizontal_alignment=ft.CrossAxisAlignment.END,
                    ),
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            padding=24,
            border_radius=20,
            bgcolor=PeadraTheme.surface,
            border=(
                ft.border.all(1, PeadraTheme.divider)
                if not self.is_dark
                else None
            ),
        )

        export_logs_btn = ft.OutlinedButton(
            content=ft.Row(
                [
                    ft.Icon(ft.Icons.BUG_REPORT, size=18),
                    ft.Text(t("param_export_logs")),
                ],
                spacing=8,
            ),
            on_click=self._on_export_logs,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.accent),
                color=PeadraTheme.accent,
            ),
        )

        data_section = self._build_section_card(
            t("param_data"),
            ft.Icons.STORAGE_OUTLINED,
            [
                self._build_setting_row(
                    t("param_import"),
                    t("param_import_desc"),
                    import_btn,
                ),
                self._build_setting_row(
                    t("param_export"),
                    t("param_export_desc"),
                    ft.Row([export_json_btn, export_csv_btn], spacing=10),
                ),
                self._build_setting_row(
                    t("param_export_logs"),
                    t("param_export_logs_desc"),
                    export_logs_btn,
                ),
            ],
        )

        # === Section Transactions ===

        display_limit_field = ft.TextField(
            value=self.display_limit,
            width=80,
            keyboard_type=ft.KeyboardType.NUMBER,
            on_change=self._on_display_limit_change,
            on_blur=self._on_display_limit_blur,
            on_submit=self._on_display_limit_blur,
            text_align=ft.TextAlign.RIGHT,
            content_padding=10,
        )

        transactions_section = self._build_section_card(
            t("param_transactions"),
            ft.Icons.ACCOUNT_BALANCE_WALLET,
            [
                self._build_setting_row(
                    t("param_display_limit"),
                    t("param_display_limit_desc"),
                    display_limit_field,
                ),
            ],
        )

        # === Section Graphiques ===
        month_mode_selector = ft.SegmentedButton(
            selected=[self.month_mode],
            on_change=self._on_month_mode_change,
            segments=[
                ft.Segment(
                    value="strict",
                    label=ft.Text(t("param_calendar_month")),
                    icon=ft.Icon(ft.Icons.CALENDAR_MONTH),
                ),
                ft.Segment(
                    value="rolling",
                    label=ft.Text(t("param_rolling_30")),
                    icon=ft.Icon(ft.Icons.UPDATE),
                ),
            ],
            show_selected_icon=False,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=16, vertical=8),
            ),
        )

        max_categories_field = ft.TextField(
            value=self.max_categories_pie,
            width=80,
            keyboard_type=ft.KeyboardType.NUMBER,
            on_change=self._on_max_categories_change,
            on_blur=self._on_max_categories_blur,
            on_submit=self._on_max_categories_blur,
            text_align=ft.TextAlign.RIGHT,
            content_padding=10,
        )

        # === Section Sécurité ===
        from src.database import db

        btn_style = ft.ButtonStyle(
            padding=ft.padding.symmetric(horizontal=16, vertical=14),
            shape=ft.RoundedRectangleBorder(radius=8),
        )

        change_pwd_btn = ft.ElevatedButton(
            t("param_change_password"),
            icon=ft.Icons.LOCK_OUTLINE,
            on_click=self._on_change_password_click,
            style=btn_style,
        )

        security_section = self._build_section_card(
            t("param_security"),
            ft.Icons.SECURITY_OUTLINED,
            [
                self._build_setting_row(
                    t("param_username"),
                    t("param_username_desc"),
                    user_name_field,
                ),
                self._build_setting_row(
                    t("param_password"),
                    t("param_password_desc"),
                    change_pwd_btn,
                ),
            ],
        )

        charts_section = self._build_section_card(
            t("param_charts"),
            ft.Icons.BAR_CHART_OUTLINED,
            [
                self._build_setting_row(
                    t("param_month_mode"),
                    t("param_month_mode_desc"),
                    month_mode_selector,
                ),
                self._build_setting_row(
                    t("param_max_categories"),
                    t("param_max_categories_desc"),
                    max_categories_field,
                ),
            ],
        )

        # === Section Danger Zone ===
        delete_account_btn = ft.ElevatedButton(
            content=t("param_delete_account"),
            icon=ft.Icons.DELETE_FOREVER,
            on_click=self._on_delete_account_click,
            style=ft.ButtonStyle(
                bgcolor=PeadraTheme.delete_color,
                color=ft.Colors.WHITE,
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
            ),
        )

        danger_section = self._build_section_card(
            t("param_danger_zone"),
            ft.Icons.WARNING_ROUNDED,
            [
                self._build_setting_row(
                    t("param_delete_account"),
                    t("param_delete_account_desc"),
                    delete_account_btn,
                ),
            ],
        )

        # === Layout principal ===
        content = ft.Column(
            [
                ft.Container(
                    content=ft.Column(
                        [
                            ft.Text(
                                t("param_page_title"),
                                size=32,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.Text(
                                t("param_page_subtitle"),
                                size=16,
                                color=PeadraTheme.placeholder_color,
                            ),
                        ],
                        spacing=4,
                    ),
                    margin=ft.margin.only(bottom=20),
                ),
                quick_update_panel,
                ft.Container(height=12),
                general_section,
                ft.Container(height=12),
                data_section,
                ft.Container(height=12),
                transactions_section,
                ft.Container(height=12),
                security_section,
                ft.Container(height=12),
                charts_section,
                ft.Container(height=12),
                danger_section,
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=0,
        )

        return ft.Container(
            content=content,
            padding=ft.padding.only(left=30, right=30, top=30, bottom=8),
            expand=True,
            alignment=ft.Alignment.TOP_RIGHT,
        )

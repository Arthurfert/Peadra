"""
Vue Paramètres pour Peadra.
Permet de configurer le thème, l'import/export et le mode de calcul mensuel.
"""

import os
import sys
import flet as ft
from typing import Callable, Any, cast, List, Optional
from ..components.theme import PeadraTheme
from ..database import db
from ..i18n import t


def get_asset_path(filename: str) -> str:
    """Retourne le chemin absolu d'un asset."""
    if getattr(sys, 'frozen', False):
        # Code exécuté depuis PyInstaller/flet pack
        base_path = getattr(sys, '_MEIPASS', '')
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

        self.path_text = ft.Text(value=self.current_path, size=12, color=ft.Colors.GREY)
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
                            ft.Icons.INSERT_DRIVE_FILE, color=ft.Colors.GREY
                        ),
                        title=ft.Text(file, color=ft.Colors.GREY_400),
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
        is_dark: bool,
        on_data_change: Callable,
        on_toggle_theme: Callable,
        on_import: Callable,
        on_export: Callable,
        on_account_deleted: Optional[Callable] = None,
        on_language_change: Optional[Callable] = None,
    ):
        self.page = page
        self.is_dark = is_dark
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
        self.currency = db.get_setting("currency", "€") or "€"
        # Charger la langue depuis la base de données
        self.language = db.get_setting("language", "en") or "en"

        self._pending_export_format = ""
        self.save_picker = CustomSavePicker(
            page=self.page,
            on_select=self._on_save_file_selected,
            on_cancel=self._on_save_picker_cancel,
        )

    def _on_save_file_selected(self, file_path: str):
        if self._pending_export_format:
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

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

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
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(cast(Any, icon), color=PeadraTheme.ACCENT, size=24),
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
                        color=ft.Colors.with_opacity(0.1, ft.Colors.ON_SURFACE),
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
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_setting_row(
        self,
        label: str,
        description: str,
        control: ft.Control,
    ) -> ft.Container:
        """Construit une ligne de paramètre."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

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
                            ft.Text(
                                description,
                                size=12,
                                color=ft.Colors.GREY,
                            ),
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
        self, label: str, image_src: str, is_dark_option: bool
    ) -> ft.Container:
        """Construit une option de thème cliquable."""
        is_selected = self.is_dark == is_dark_option
        border_color = (
            PeadraTheme.ACCENT
            if is_selected
            else ft.Colors.with_opacity(0.1, ft.Colors.GREY)
        )

        def on_click(e):
            if self.is_dark != is_dark_option:
                self.on_toggle_theme(e)

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
                        weight=ft.FontWeight.BOLD
                        if is_selected
                        else ft.FontWeight.NORMAL,
                        color=PeadraTheme.DARK_TEXT
                        if self.is_dark
                        else PeadraTheme.LIGHT_TEXT,
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

    def _on_import_csv(self, e):
        """Lance l'import CSV."""
        self.on_import()

    def _on_save_password(self, e):
        pwd = self.password_field.value
        confirm = self.password_confirm_field.value
        if not pwd:
            self.password_message.value = t("param_password_empty")
            self.password_message.color = ft.Colors.RED
            self.page.update()
            return
        if pwd != confirm:
            self.password_message.value = t("param_password_mismatch")
            self.password_message.color = ft.Colors.RED
            self.page.update()
            return
        import hashlib
        from src.database import db

        hashed = hashlib.sha256(pwd.encode()).hexdigest()
        db.set_setting("app_password_hash", hashed)
        self.password_message.value = t("param_password_saved")
        self.password_message.color = ft.Colors.GREEN
        self.password_field.value = ""
        self.password_confirm_field.value = ""
        self.remove_pwd_btn.visible = True
        self.page.update()

    def _on_remove_password(self, e):
        from src.database import db

        db.set_setting("app_password_hash", "")
        self.password_message.value = t("param_password_removed")
        self.password_message.color = ft.Colors.GREEN
        self.remove_pwd_btn.visible = False
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
            else:
                error_message.value = t("param_delete_password_incorrect")
                self.page.update()

        def on_cancel(_):
            dialog.open = False
            self.page.update()

        dialog = ft.AlertDialog(
            title=ft.Text(t("param_delete_confirm"), size=20, weight=ft.FontWeight.BOLD),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.Text(
                            t("param_delete_warning"),
                            size=14,
                            color=ft.Colors.ERROR,
                        ),
                        ft.Container(height=16),
                        ft.Text(t("param_delete_password_prompt"), size=13, weight=ft.FontWeight.W_500),
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
                    style=ft.ButtonStyle(color=ft.Colors.RED),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        self.page.show_dialog(dialog)
        self.page.update()

    def build(self) -> ft.Container:
        """Construit la vue paramètres."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

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
                    t("param_light_theme"), get_asset_path("assets/Dashboard_Light.jpg"), False
                ),
                self._build_theme_option(t("param_dark_theme"), get_asset_path("assets/Dashboard.jpg"), True),
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
                            color=ft.Colors.GREY,
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
                bgcolor=PeadraTheme.ACCENT,
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
                side=ft.BorderSide(1, PeadraTheme.ACCENT),
                color=PeadraTheme.ACCENT,
            ),
        )

        export_csv_btn = ft.OutlinedButton(
            content=ft.Row(
                [ft.Icon(ft.Icons.TABLE_CHART, size=18), ft.Text(t("param_export_csv"))],
                spacing=8,
            ),
            on_click=self._on_export_csv,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.ACCENT),
                color=PeadraTheme.ACCENT,
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

        # === Section Sécurité ===
        from src.database import db

        self.password_field = ft.TextField(
            password=True,
            can_reveal_password=True,
            label=t("param_password_new"),
            width=180,
            height=45,
            text_size=13,
        )
        self.password_confirm_field = ft.TextField(
            password=True,
            can_reveal_password=True,
            label=t("param_password_confirm"),
            width=180,
            height=45,
            text_size=13,
        )
        self.password_message = ft.Text(size=12)

        btn_style = ft.ButtonStyle(
            padding=ft.padding.symmetric(horizontal=16, vertical=14),
            shape=ft.RoundedRectangleBorder(radius=8),
        )

        save_pwd_btn = ft.ElevatedButton(
            t("param_btn_save"),
            icon=ft.Icons.SAVE_OUTLINED,
            on_click=self._on_save_password,
            style=btn_style,
        )
        self.remove_pwd_btn = ft.ElevatedButton(
            t("param_btn_remove"),
            icon=ft.Icons.DELETE_OUTLINED,
            on_click=self._on_remove_password,
            color=ft.Colors.RED,
            visible=bool(db.get_setting("app_password_hash")),
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
                    ft.Column(
                        [
                            ft.Row(
                                [self.password_field, self.password_confirm_field],
                                spacing=12,
                            ),
                            ft.Row(
                                [self.remove_pwd_btn, save_pwd_btn],
                                spacing=12,
                                alignment=ft.MainAxisAlignment.END,
                            ),
                            self.password_message,
                        ],
                        spacing=12,
                        horizontal_alignment=ft.CrossAxisAlignment.END,
                    ),
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
            ],
        )

        # === Section Danger Zone ===
        delete_account_btn = ft.ElevatedButton(
            content=t("param_delete_account"),
            icon=ft.Icons.DELETE_FOREVER,
            on_click=self._on_delete_account_click,
            style=ft.ButtonStyle(
                bgcolor=ft.Colors.RED,
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
                                color=ft.Colors.GREY,
                            ),
                        ],
                        spacing=4,
                    ),
                    margin=ft.margin.only(bottom=20),
                ),
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

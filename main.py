"""
Peadra - Application de gestion de patrimoine
Point d'entrée principal de l'application.
"""

import flet as ft
from src.components.theme import PeadraTheme
from src.components.navigation import NavigationRailComponent
from src.database import db
from src.views.dashboard import DashboardView
from src.views.transactions import TransactionsView
from src.views.accounts import AccountsView
from src.views.parameters import ParametersView
from src.views.subscriptions import SubscriptionsView
from src.views.import_data import ImportDialog


class PeadraApp:
    """Application principale Peadra."""

    def __init__(self, page: ft.Page):
        self.page = page

        # Charger le thème depuis la base de données
        theme_setting = db.get_setting("theme_mode", "dark")
        self.is_dark = theme_setting == "dark"

        # Traiter les transactions récurrentes au démarrage
        try:
            db.process_recurring_transactions()
        except Exception as e:
            print(f"Error processing recurring transactions: {e}")

        self.current_view_index = 0

        # Configuration de la page
        self._setup_page()

        # Initialiser les composants
        self._init_components()

        # Construire l'interface
        self._build_ui()

    def _setup_page(self):
        """Configure la page principale."""
        self.page.title = "Peadra - Gestion de Patrimoine"
        self.page.window.width = 1400
        self.page.window.height = 900
        self.page.window.min_width = 1000
        self.page.window.min_height = 700
        self.page.padding = 0
        self.page.spacing = 0
        self.page.window.icon = "icon.ico"

        # Appliquer le thème initial
        self._apply_theme()

    def _apply_theme(self):
        """Applique le thème actuel."""
        if self.is_dark:
            self.page.theme = PeadraTheme.get_dark_theme()
            self.page.theme_mode = ft.ThemeMode.DARK
            self.page.bgcolor = PeadraTheme.DARK_BG
        else:
            self.page.theme = PeadraTheme.get_light_theme()
            self.page.theme_mode = ft.ThemeMode.LIGHT
            self.page.bgcolor = PeadraTheme.LIGHT_BG

    def _init_components(self):
        """Initialise les composants de l'application."""
        # Navigation
        self.navigation = NavigationRailComponent(
            on_change=self._on_navigation_change, is_dark=self.is_dark
        )

        # Dialogues
        self.import_dialog = ImportDialog(
            self.page, self.is_dark, self._refresh_all_views
        )

        # Vues
        self.parameters_view = ParametersView(
            self.page,
            self.is_dark,
            self._refresh_all_views,
            on_toggle_theme=self._toggle_theme,
            on_import=lambda: self.import_dialog.open(),
            on_export=self._export_data,
        )
        self.views = {
            0: DashboardView(
                self.page,
                self.is_dark,
                self._refresh_all_views,
                get_month_mode=self.parameters_view.get_month_mode,
            ),
            1: TransactionsView(self.page, self.is_dark, self._refresh_all_views),
            2: AccountsView(self.page, self.is_dark, self._refresh_all_views),
            3: SubscriptionsView(self.page, self.is_dark, self._refresh_all_views),
            4: self.parameters_view,
        }

    def _on_navigation_change(self, index: int):
        """Gère le changement de vue via la navigation."""
        self.current_view_index = index

        # Mettre à jour la navigation pour refléter la sélection
        if hasattr(self, "nav_container"):
            self.nav_container.content = self.navigation.build()
            self.nav_container.update()

        self._update_content()

    def _toggle_theme(self, e):
        """Bascule entre le mode sombre et clair."""
        self.is_dark = not self.is_dark

        # Sauvegarder dans la base de données
        db.set_setting("theme_mode", "dark" if self.is_dark else "light")

        self._apply_theme()

        # Mettre à jour tous les composants

        self.navigation.update_theme(self.is_dark)
        for view in self.views.values():
            view.update_theme(self.is_dark)
        if hasattr(self, "import_dialog"):
            self.import_dialog.update_theme(self.is_dark)

        # Reconstruire l'interface
        self._build_ui()

    def _refresh_all_views(self):
        """Rafraîchit toutes les vues (appelé après une modification de données)."""
        for view in self.views.values():
            view.refresh()

        # Rafraîchir la navigation (pour le solde)
        if hasattr(self, "nav_container"):
            self.nav_container.content = self.navigation.build()
            self.nav_container.update()

        self._update_content()

    def _export_data(self, format_type: str, file_path: str):
        """Exporte les données."""
        import os

        # S'assurer que le dossier parent existe
        export_dir = os.path.dirname(file_path)
        if export_dir:
            os.makedirs(export_dir, exist_ok=True)

        if format_type == "json":
            success = db.export_to_json(file_path)
        else:
            success = db.export_to_csv(file_path, "transactions")

        if success:
            self._show_snackbar(f"Export succeeded : {file_path}", success=True)
        else:
            self._show_snackbar("Error during export", success=False)

    def _show_snackbar(self, message: str, success: bool = True):
        """Affiche une notification."""
        color = PeadraTheme.SUCCESS if success else PeadraTheme.ERROR
        snackbar = ft.SnackBar(
            content=ft.Text(message, color=ft.Colors.WHITE),
            bgcolor=color,
            duration=3000,
        )
        self.page.overlay.append(snackbar)
        snackbar.open = True
        self.page.update()

    def _open_settings(self, e):
        """Ouvre la vue des paramètres ou la ferme si elle est déjà ouverte."""
        if self.current_view_index == 4:
            # Revenir à la vue précédente (stockée dans la navigation)
            self._on_navigation_change(self.navigation.selected_index)
        else:
            self.current_view_index = 4
            self._on_navigation_change(4)

    def _build_header(self) -> ft.Container:
        """Construit l'en-tête de l'application."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        return ft.Container(
            content=ft.Row(
                controls=[
                    # Logo et titre
                    ft.Row(
                        controls=[
                            ft.Image(
                                src="Peadra_white.png"
                                if self.is_dark
                                else "Peadra.png",
                                width=60,
                                height=60,
                                fit=ft.BoxFit.CONTAIN,
                            ),
                            ft.Text(
                                "Peadra",
                                size=28,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        spacing=12,
                    ),
                    # Spacer
                    ft.Container(expand=True),
                    # Bouton des paramètres
                    ft.IconButton(
                        icon=ft.Icons.SETTINGS,
                        tooltip="Settings",
                        on_click=lambda e: self._open_settings(e),
                    ),
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
            ),
            padding=ft.Padding(left=24, right=24, top=16, bottom=16),
            bgcolor=bg_color,
        )

    def _update_content(self):
        """Met à jour le contenu principal."""
        # Obtenir la vue actuelle
        current_view = self.views.get(self.current_view_index)
        if current_view:
            self.content_area.content = current_view.build()
            self.page.update()

    def _build_ui(self):
        """Construit l'interface utilisateur complète."""
        bg_color = PeadraTheme.DARK_BG if self.is_dark else PeadraTheme.LIGHT_BG
        surface_color = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        # Zone de contenu
        self.content_area = ft.Container(
            content=self.views[self.current_view_index].build(),
            expand=True,
            padding=0,  # Let individual views handle padding
            bgcolor=bg_color,
            border_radius=ft.BorderRadius.only(top_left=30),
        )

        # Wrapper pour le fond derrière l'angle arrondi
        content_wrapper = ft.Container(
            content=self.content_area,
            expand=True,
            bgcolor=surface_color,
        )

        # Conteneur de navigation pour permettre les mises à jour
        self.nav_container = ft.Container(content=self.navigation.build())

        # Layout du corps (Navigation + Contenu)
        body_layout = ft.Row(
            controls=[
                # Navigation latérale
                self.nav_container,
                # Contenu principal
                content_wrapper,
            ],
            spacing=0,
            expand=True,
        )

        # Layout principal (Header + Body)
        main_layout = ft.Column(
            controls=[
                self._build_header(),
                body_layout,
            ],
            spacing=0,
            expand=True,
        )

        if self.page.controls is not None:
            self.page.controls.clear()
        self.page.add(main_layout)
        self.page.update()


def main(page: ft.Page):
    import hashlib
    """Point d'entrée de l'application Flet."""
    from src.database import db
    app_password_hash = db.get_setting("app_password_hash", "")
    username = db.get_setting("user_name", "")
    welcome_str = f"Welcome, {username}" if username else "Peadra"
    
    if app_password_hash:
        def verify_password(e):
            entered_hash = hashlib.sha256(pwd_field.value.encode()).hexdigest()
            if entered_hash == app_password_hash:
                page.controls.clear()
                PeadraApp(page)
            else:
                pwd_error.value = "Incorrect password."
                pwd_field.value = ""
                _ = pwd_field.focus()
                page.update()

        pwd_field = ft.TextField(
            label="Password",
            password=True,
            can_reveal_password=True,
            width=300,
            on_submit=verify_password
        )
        pwd_error = ft.Text(color=ft.Colors.ERROR)
        submit_btn = ft.Button("Unlock", on_click=verify_password)

        lock_view = ft.Column(
            controls=[
                ft.Icon(ft.Icons.LOCK, size=64),
                ft.Text(welcome_str, theme_style=ft.TextThemeStyle.HEADLINE_LARGE, weight=ft.FontWeight.BOLD),
                ft.Text("Application locked", theme_style=ft.TextThemeStyle.TITLE_MEDIUM),
                ft.Container(height=20),
                pwd_field,
                pwd_error,
                submit_btn
            ],
            alignment=ft.MainAxisAlignment.CENTER,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        )

        page.vertical_alignment = ft.MainAxisAlignment.CENTER
        page.horizontal_alignment = ft.CrossAxisAlignment.CENTER
        page.add(lock_view)
        page.update()
    else:
        PeadraApp(page)


if __name__ == "__main__":
    ft.run(main, assets_dir="assets")

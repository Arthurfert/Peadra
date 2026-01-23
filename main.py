"""
Peadra - Application de gestion de patrimoine
Point d'entrée principal de l'application.
"""

import flet as ft
from src.components.theme import PeadraTheme
from src.components.navigation import NavigationRailComponent
from src.database.db_manager import db
from src.views.dashboard import DashboardView
from src.views.transactions import TransactionsView


class PeadraApp:
    """Application principale Peadra."""

    def __init__(self, page: ft.Page):
        self.page = page
        self.is_dark = True
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

        # Vues
        self.views = {
            0: DashboardView(self.page, self.is_dark, self._refresh_all_views),
            1: TransactionsView(self.page, self.is_dark, self._refresh_all_views),
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
        self._apply_theme()

        # Mettre à jour tous les composants
        self.navigation.update_theme(self.is_dark)
        for view in self.views.values():
            view.update_theme(self.is_dark)

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

    def _export_data(self, e, format_type: str):
        """Exporte les données."""
        import os
        from datetime import datetime

        # Créer le dossier exports s'il n'existe pas
        export_dir = "exports"
        os.makedirs(export_dir, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if format_type == "json":
            filepath = os.path.join(export_dir, f"peadra_export_{timestamp}.json")
            success = db.export_to_json(filepath)
        else:
            filepath = os.path.join(export_dir, f"peadra_transactions_{timestamp}.csv")
            success = db.export_to_csv(filepath, "transactions")

        if success:
            self._show_snackbar(f"Export réussi : {filepath}", success=True)
        else:
            self._show_snackbar("Erreur lors de l'export", success=False)

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
                    # Actions
                    ft.Row(
                        controls=[
                            # Menu export
                            ft.PopupMenuButton(
                                icon=ft.Icons.DOWNLOAD,
                                tooltip="Exporter les données",
                                items=[
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            controls=[
                                                ft.Icon(ft.Icons.DATA_OBJECT, size=18),
                                                ft.Text("Exporter en JSON"),
                                            ],
                                            spacing=8,
                                        ),
                                        on_click=lambda e: self._export_data(e, "json"),
                                    ),
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            controls=[
                                                ft.Icon(ft.Icons.TABLE_CHART, size=18),
                                                ft.Text("Exporter en CSV"),
                                            ],
                                            spacing=8,
                                        ),
                                        on_click=lambda e: self._export_data(e, "csv"),
                                    ),
                                ],
                            ),
                            # Toggle thème
                            ft.IconButton(
                                icon=(
                                    ft.Icons.LIGHT_MODE
                                    if self.is_dark
                                    else ft.Icons.DARK_MODE
                                ),
                                tooltip="Changer de thème",
                                on_click=self._toggle_theme,
                                icon_color=PeadraTheme.ACCENT,
                            ),
                        ],
                        spacing=8,
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
            border_radius=ft.border_radius.only(top_left=30),
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
    """Point d'entrée de l'application Flet."""
    PeadraApp(page)


if __name__ == "__main__":
    ft.app(main, assets_dir="assets")

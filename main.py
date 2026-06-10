"""
Peadra - Application de gestion de patrimoine
Point d'entrée principal de l'application.
"""

import argparse
import json
import logging
import os
import flet as ft
from src.components.theme import PeadraTheme
from src.logger import setup_logger
from src.components.navigation import NavigationRailComponent
from src.database import db
from src.i18n import set_language, t
from src.views.dashboard import DashboardView
from src.update_manager import run_update_mode
from src.views.transactions import TransactionsView
from src.views.accounts import AccountsView
from src.views.categories import CategoriesView
from src.views.parameters import ParametersView
from src.views.subscriptions import SubscriptionsView
from src.views.import_data import ImportDialog
from src.views.login import LoginView

logger = logging.getLogger(__name__)


class PeadraApp:
    """Application principale Peadra."""

    def __init__(self, page: ft.Page, theme_mode: str = "dark"):
        self.page = page
        self.theme_mode = theme_mode
        self.is_dark = theme_mode != "light"

        self.current_view_index = 0

        # Configuration de la page
        self._setup_page()

        # Initialiser les composants
        self._init_components()

        # Construire l'interface
        self._build_ui()

    def _logout(self):
        """Déconnecte l'utilisateur et revient à la vue de login."""
        logger.info("User logged out")
        from src.i18n import get_translator

        current_language = get_translator().get_language()
        db.set_app_setting("language", current_language)

        self.page.controls.clear()

        # Réinitialiser l'user_id
        db.user_id = None

        # Afficher la vue de login
        def on_login_success() -> None:
            """Callback appelé après une connexion réussie."""
            # Charger le thème depuis la base de données pour l'utilisateur
            theme_setting = db.get_setting("theme_mode", "dark")

            # Traiter les transactions récurrentes au démarrage
            try:
                db.process_recurring_transactions()
            except Exception as e:
                logging.getLogger(__name__).error(
                    "Error processing recurring transactions: %s", e
                )

            # Créer l'application principale
            self.page.controls.clear()
            app = PeadraApp(self.page, theme_setting)
            self.page.update()

        # Configuration initiale
        theme_mode = db.get_app_setting("theme_mode", "dark") or "dark"
        PeadraTheme.set_theme(theme_mode)
        self.page.theme = PeadraTheme.get_flet_theme()
        self.page.theme_mode = ft.ThemeMode.DARK if theme_mode != "light" else ft.ThemeMode.LIGHT
        self.page.bgcolor = PeadraTheme.bg
        self.page.title = "Peadra - Login"
        self.page.vertical_alignment = ft.MainAxisAlignment.CENTER
        self.page.horizontal_alignment = ft.CrossAxisAlignment.CENTER

        # Récupérer la liste des utilisateurs existants
        existing_users = db.get_all_usernames()

        # Créer la vue de login avec les utilisateurs existants
        login_view = LoginView(
            self.page, True, on_login_success, existing_users
        )
        login_container = login_view.build()

        self.page.add(login_container)
        self.page.update()

    def _setup_page(self):
        """Configure la page principale."""
        self.page.title = "Peadra - Financial Asset Tracker"
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
        PeadraTheme.set_theme(self.theme_mode)
        self.page.theme = PeadraTheme.get_flet_theme()
        self.page.theme_mode = ft.ThemeMode.DARK if self.is_dark else ft.ThemeMode.LIGHT
        self.page.bgcolor = PeadraTheme.bg

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
            self.theme_mode,
            self._refresh_all_views,
            on_toggle_theme=self._toggle_theme,
            on_import=lambda: self.import_dialog.open(),
            on_export=self._export_data,
            on_account_deleted=self._logout,
            on_language_change=self._on_language_change,
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
            4: CategoriesView(self.page, self.is_dark, self._refresh_all_views),
            5: self.parameters_view,
        }

    def _on_navigation_change(self, index: int):
        """Gère le changement de vue via la navigation."""
        self.current_view_index = index

        # Mettre à jour la navigation pour refléter la sélection
        if hasattr(self, "nav_container"):
            self.nav_container.content = self.navigation.build()
            self.nav_container.update()

        self._update_content()

    def _toggle_theme(self, theme_mode: str):
        """Bascule/définit le thème."""
        logger.info("Theme toggled to %s", theme_mode)
        self.theme_mode = theme_mode
        self.is_dark = theme_mode != "light"

        # Sauvegarder dans la base de données
        db.set_setting("theme_mode", theme_mode)
        db.set_app_setting("theme_mode", theme_mode)

        self._apply_theme()

        # Mettre à jour tous les composants

        self.navigation.update_theme(self.is_dark)
        for view_idx, view in self.views.items():
            if view_idx == 5:
                view.update_theme(self.theme_mode)
            else:
                view.update_theme(self.is_dark)
        if hasattr(self, "import_dialog"):
            self.import_dialog.update_theme(self.is_dark)

        # Reconstruire l'interface
        self._build_ui()

    def _on_language_change(self, language: str):
        """Gère le changement de langue."""
        logger.info("Language changed to %s", language)
        set_language(language)
        db.set_app_setting("language", language)
        self._build_ui()
        self._refresh_all_views()

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
            logger.info("Data exported to %s (format=%s)", file_path, format_type)
            self._show_snackbar(
                t("msg_export_success").format(file_path=file_path), success=True
            )
        else:
            logger.error(
                "Data export failed (format=%s, path=%s)", format_type, file_path
            )
            self._show_snackbar(t("msg_export_error"), success=False)

    def _show_snackbar(self, message: str, success: bool = True):
        """Affiche une notification."""
        color = PeadraTheme.success if success else PeadraTheme.error
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
        if self.current_view_index == 5:
            # Revenir à la vue précédente (stockée dans la navigation)
            self._on_navigation_change(self.navigation.selected_index)
        else:
            self.current_view_index = 5
            self._on_navigation_change(5)

    def _build_header(self) -> ft.Container:
        """Construit l'en-tête de l'application."""
        text_color = PeadraTheme.text
        bg_color = PeadraTheme.surface

        return ft.Container(
            content=ft.Row(
                controls=[
                    # Logo et titre
                    ft.Row(
                        controls=[
                            ft.Image(
                                src=(
                                    "Peadra_white.png" if self.is_dark else "Peadra.png"
                                ),
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
                        tooltip=t("tooltip_settings"),
                        on_click=lambda e: self._open_settings(e),
                    ),
                    # Bouton logout
                    ft.IconButton(
                        icon=ft.Icons.LOGOUT,
                        tooltip=t("tooltip_logout"),
                        on_click=lambda e: self._logout(),
                    ),
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            padding=ft.Padding(left=24, right=24, top=0, bottom=0),
            bgcolor=bg_color,
            height=90,
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
        bg_color = PeadraTheme.bg
        surface_color = PeadraTheme.surface

        # Pour la vue principale, on évite le centrage global de la page afin
        # que le layout occupe toute la hauteur disponible.
        self.page.vertical_alignment = ft.MainAxisAlignment.START
        self.page.horizontal_alignment = ft.CrossAxisAlignment.STRETCH

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
        self.nav_container = ft.Container(
            content=self.navigation.build(),
        )

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
            vertical_alignment=ft.CrossAxisAlignment.START,
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

    def on_login_success() -> None:
        """Callback appelé après une connexion réussie."""
        # Charger le thème depuis la base de données pour l'utilisateur
        theme_setting = db.get_setting("theme_mode", "dark")

        # Charger la langue depuis la base de données pour l'utilisateur
        language_setting = db.get_setting("language", "en") or "en"
        set_language(language_setting)

        # Sauvegarder aussi la langue globalement pour la prochaine session
        db.set_app_setting("language", language_setting)

        # Traiter les transactions récurrentes au démarrage
        try:
            db.process_recurring_transactions()
        except Exception as e:
            logging.getLogger(__name__).error(
                "Error processing recurring transactions: %s", e
            )

        # Créer l'application principale
        page.controls.clear()
        app = PeadraApp(page, theme_setting)
        page.update()

    # Configuration initiale
    initial_theme = db.get_app_setting("theme_mode", "dark") or "dark"
    PeadraTheme.set_theme(initial_theme)
    page.theme = PeadraTheme.get_flet_theme()
    page.theme_mode = ft.ThemeMode.DARK if initial_theme != "light" else ft.ThemeMode.LIGHT
    page.bgcolor = PeadraTheme.bg
    page.title = "Peadra - Login"
    page.window.width = 1400
    page.window.height = 900
    page.window.min_width = 1000
    page.window.min_height = 700
    page.padding = 0
    page.spacing = 0
    page.window.icon = "icon.ico"
    page.vertical_alignment = ft.MainAxisAlignment.CENTER
    page.horizontal_alignment = ft.CrossAxisAlignment.CENTER

    # Charger la langue globale de l'application (paramètre global)
    global_language = db.get_app_setting("language", "en") or "en"
    set_language(global_language)

    # Récupérer la liste des utilisateurs existants
    existing_users = db.get_all_usernames()

    # Créer la vue de login avec les utilisateurs existants
    # Si aucun utilisateur n'existe, LoginView affichera le mode enregistrement
    login_view = LoginView(page, True, on_login_success, existing_users)
    login_container = login_view.build()

    page.add(login_container)

    # Fermer proprement la connexion BDD à la fermeture de l'app
    page.on_close = lambda _: db.close()

    page.update()


if __name__ == "__main__":
    logger = setup_logger()
    logger.debug("Application started")

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--apply-update", action="store_true")
    parser.add_argument("--source")
    parser.add_argument("--target")
    parser.add_argument("--terminate-pid")
    parser.add_argument("--restart-args")
    args, _ = parser.parse_known_args()

    if args.apply_update and args.source and args.target:
        restart_args = []
        if args.restart_args:
            try:
                restart_args = json.loads(args.restart_args)
            except json.JSONDecodeError:
                restart_args = []
        terminate_pid = None
        if args.terminate_pid:
            try:
                terminate_pid = int(args.terminate_pid)
            except ValueError:
                terminate_pid = None
        exit_code = run_update_mode(
            args.source,
            args.target,
            restart_args,
            terminate_pid=terminate_pid,
        )
        # Sortie forcée du helper onefile pour éviter toute instance résiduelle.
        os._exit(exit_code)

    ft.run(main, assets_dir="assets")

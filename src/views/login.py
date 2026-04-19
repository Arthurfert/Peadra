"""
Composant de login et enregistrement.
"""

import flet as ft
from src.database import db
from src.components.theme import PeadraTheme


class LoginView:
    """Vue de login et d'enregistrement avec support des deux modes."""

    def __init__(
        self,
        page: ft.Page,
        is_dark: bool,
        on_login_success,
        existing_users: list[str] | None = None,
    ):
        """
        Initialise la vue de login.

        Args:
            page: Page Flet
            is_dark: Mode sombre activé
            on_login_success: Callback appelé après connexion réussie
            existing_users: Liste des noms d'utilisateurs existants
        """
        self.page = page
        self.is_dark = is_dark
        self.on_login_success = on_login_success
        self.existing_users = existing_users or []

        # Thème
        self.theme = (
            PeadraTheme.get_dark_theme() if is_dark else PeadraTheme.get_light_theme()
        )
        self.bg_color = PeadraTheme.DARK_BG if is_dark else PeadraTheme.LIGHT_BG

        # État : en mode registration si aucun utilisateur existant
        self.is_registration_mode = len(self.existing_users) == 0

        # Contrôles
        self.username_field: ft.TextField | None = None
        self.username_dropdown: ft.Dropdown | None = None
        self.password_field: ft.TextField | None = None
        self.password_confirm_field: ft.TextField | None = None
        self.error_text: ft.Text | None = None
        self.action_button: ft.ElevatedButton | None = None
        self.toggle_button: ft.TextButton | None = None
        self.form_column: ft.Column | None = None

    def build(self) -> ft.Container:
        """Construit la vue."""
        return ft.Container(
            content=self._build_form(),
            expand=True,
            bgcolor=self.bg_color,
        )

    def _build_form(self) -> ft.Column:
        """Construit le formulaire."""
        # Champs de password
        self.password_field = ft.TextField(
            label="Password",
            password=True,
            can_reveal_password=True,
            width=300,
        )

        self.password_confirm_field = ft.TextField(
            label="Confirm Password",
            password=True,
            can_reveal_password=True,
            width=300,
            visible=self.is_registration_mode,
        )

        self.error_text = ft.Text(color=ft.Colors.ERROR)

        # Boutons
        self.action_button = ft.ElevatedButton(
            content=ft.Text("Sign Up" if self.is_registration_mode else "Log In"),
            width=300,
            height=50,
            on_click=self._on_action_click,
        )

        self.toggle_button = ft.TextButton(
            content=ft.Text(
                "Connect to an existing account"
                if self.is_registration_mode
                else "Create a new account"
            ),
            on_click=self._on_toggle_mode,
        )

        # Construire la liste des champs en fonction du mode
        fields = [
            ft.Icon(ft.Icons.LOCK, size=64),
            ft.Text(
                "Peadra",
                theme_style=ft.TextThemeStyle.HEADLINE_LARGE,
                weight=ft.FontWeight.BOLD,
            ),
            ft.Text(
                "Financial Asset Tracker",
                theme_style=ft.TextThemeStyle.TITLE_MEDIUM,
            ),
            ft.Container(height=20),
        ]

        if self.is_registration_mode:
            # Mode enregistrement : champ username
            self.username_field = ft.TextField(
                label="Username",
                width=300,
            )
            fields.append(self.username_field)
        else:
            # Mode login : dropdown d'utilisateurs
            dropdown_options = [
                ft.dropdown.Option(username) for username in self.existing_users
            ]
            self.username_dropdown = ft.Dropdown(
                label="User",
                options=dropdown_options,
                width=300,
                focused_border_color=PeadraTheme.PRIMARY_LIGHT,
            )
            fields.append(self.username_dropdown)

        fields.extend(
            [
                self.password_field,
                self.password_confirm_field,
                self.error_text,
                ft.Container(height=10),
                self.action_button,
                self.toggle_button,
            ]
        )

        # Formulaire
        self.form_column = ft.Column(
            controls=fields,
            alignment=ft.MainAxisAlignment.CENTER,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            spacing=12,
        )

        return self.form_column

    def _on_toggle_mode(self, e):
        """Bascule entre mode login et registration."""
        # Type assertions pour Pylance
        assert self.error_text is not None
        assert self.password_field is not None
        assert self.password_confirm_field is not None
        assert self.action_button is not None
        assert self.toggle_button is not None

        self.is_registration_mode = not self.is_registration_mode

        # Nettoyer les champs
        self.error_text.value = ""
        self.password_field.value = ""
        self.password_confirm_field.value = ""

        # Reconstruire le formulaire
        self.page.controls.clear()
        self.page.add(self.build())
        self.page.update()

    def _on_action_click(self, e):
        """Gère l'action (login ou registration)."""
        # Type assertions pour Pylance
        assert self.error_text is not None
        assert self.password_field is not None

        password = self.password_field.value

        if not password:
            self.error_text.value = "Password is required."
            self.page.update()
            return

        if self.is_registration_mode:
            assert self.username_field is not None
            username = self.username_field.value
            self._register(username, password)
        else:
            assert self.username_dropdown is not None
            username = self.username_dropdown.value
            if not username:
                self.error_text.value = "Please select a user."
                self.page.update()
                return
            self._login(username, password)

    def _login(self, username: str, password: str):
        """Connecte l'utilisateur."""
        # Type assertions pour Pylance
        assert self.error_text is not None
        assert self.password_field is not None

        # Validation
        if not username:
            self.error_text.value = "Please select a user."
            self.page.update()
            return

        if len(password) < 6:
            self.error_text.value = "Password must have at least 6 characters."
            self.page.update()
            return

        user_id = db.authenticate_user(username, password)

        if user_id is None:
            self.error_text.value = "Incorrect username or password."
            self.password_field.value = ""
            _ = self.password_field.focus()
            self.page.update()
            return

        # Connecter l'utilisateur
        db.set_current_user(user_id)
        self.on_login_success()

    def _register(self, username: str, password: str):
        """Enregistre un nouvel utilisateur."""
        # Type assertions pour Pylance
        assert self.password_confirm_field is not None
        assert self.error_text is not None

        password_confirm = self.password_confirm_field.value

        # Validations
        if len(username) < 3:
            self.error_text.value = "Username must have at least 3 characters."
            self.page.update()
            return

        if len(password) < 6:
            self.error_text.value = "Password must have at least 6 characters."
            self.page.update()
            return

        if password != password_confirm:
            self.error_text.value = "Passwords do not match."
            self.page.update()
            return

        if db.user_exists(username):
            self.error_text.value = f"Username '{username}' already exists."
            self.page.update()
            return

        # Enregistrer l'utilisateur
        try:
            db.register_user(username, password)
        except ValueError as e:
            self.error_text.value = str(e)
            self.page.update()
            return

        # Connecter automatiquement
        user_id = db.authenticate_user(username, password)
        if user_id:
            db.set_current_user(user_id)
            # Auto-remplir le user_name avec le username
            db.set_setting("user_name", username)
            self.on_login_success()

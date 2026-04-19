"""
Composant de login et enregistrement.
"""

import flet as ft
from src.database import db
from src.components.theme import PeadraTheme


class LoginView:
    """Vue de login et d'enregistrement."""

    def __init__(self, page: ft.Page, is_dark: bool, on_login_success):
        """
        Initialise la vue de login.

        Args:
            page: Page Flet
            is_dark: Mode sombre activé
            on_login_success: Callback appelé après connexion réussie
        """
        self.page = page
        self.is_dark = is_dark
        self.on_login_success = on_login_success

        # Thème
        self.theme = (
            PeadraTheme.get_dark_theme() if is_dark else PeadraTheme.get_light_theme()
        )
        self.bg_color = PeadraTheme.DARK_BG if is_dark else PeadraTheme.LIGHT_BG

        # État
        self.is_login_mode = True

        # Contrôles
        self.username_field: ft.TextField | None = None
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
        # Champs
        self.username_field = ft.TextField(
            label="Username",
            width=300,
        )

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
            visible=False,  # Caché en mode login
        )

        self.error_text = ft.Text(color=ft.Colors.ERROR)

        # Boutons
        self.action_button = ft.ElevatedButton(
            content=ft.Text("Login"),
            width=300,
            height=50,
            on_click=self._on_action_click,
        )

        self.toggle_button = ft.TextButton(
            content=ft.Text("Create an account"),
            on_click=self._on_toggle_mode,
        )

        # Formulaire
        self.form_column = ft.Column(
            controls=[
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
                self.username_field,
                self.password_field,
                self.password_confirm_field,
                self.error_text,
                ft.Container(height=10),
                self.action_button,
                self.toggle_button,
            ],
            alignment=ft.MainAxisAlignment.CENTER,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            spacing=12,
        )

        return self.form_column

    def _on_toggle_mode(self, e):
        """Bascule entre mode login et register."""
        # Type assertions pour Pylance
        assert self.password_confirm_field is not None
        assert self.action_button is not None
        assert self.toggle_button is not None
        assert self.error_text is not None
        assert self.username_field is not None
        assert self.password_field is not None

        self.is_login_mode = not self.is_login_mode

        # Mettre à jour les boutons et champs
        if self.is_login_mode:
            # Mode login
            self.password_confirm_field.visible = False
            self.action_button.content = ft.Text("Login")
            self.toggle_button.content = ft.Text("Create an account")
        else:
            # Mode register
            self.password_confirm_field.visible = True
            self.action_button.content = ft.Text("Register")
            self.toggle_button.content = ft.Text("Back to Login")

        # Nettoyer les erreurs et champs
        self.error_text.value = ""
        self.username_field.value = ""
        self.password_field.value = ""
        self.password_confirm_field.value = ""

        self.page.update()

    def _on_action_click(self, e):
        """Gère l'action (login ou register)."""
        # Type assertions pour Pylance
        assert self.username_field is not None
        assert self.password_field is not None
        assert self.error_text is not None

        username = self.username_field.value
        password = self.password_field.value

        if not username or not password:
            self.error_text.value = "Please fill in all fields."
            self.page.update()
            return

        if self.is_login_mode:
            self._login(username, password)
        else:
            self._register(username, password)

    def _login(self, username: str, password: str):
        """Connecte l'utilisateur."""
        # Type assertions pour Pylance
        assert self.error_text is not None
        assert self.password_field is not None

        # Validation
        if len(username) < 3:
            self.error_text.value = (
                "Username must have at least 3 characters."
            )
            self.page.update()
            return

        if len(password) < 6:
            self.error_text.value = "Password must have at least 6 characters."
            self.page.update()
            return

        user_id = db.authenticate_user(username, password)

        if user_id is None:
            self.error_text.value = "Incorrect credentials."
            self.password_field.value = ""
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
        assert self.username_field is not None
        assert self.password_field is not None

        password_confirm = self.password_confirm_field.value

        # Validations
        if len(username) < 3:
            self.error_text.value = (
                "Username must have at least 3 characters."
            )
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
            self.on_login_success()

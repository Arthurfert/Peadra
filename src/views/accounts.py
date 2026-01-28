"""
Vue Comptes pour Peadra.
Permet de gérer les comptes (catégories) : affichage, ajout, modification, suppression.
"""

import flet as ft
from typing import Callable, Optional
from ..components.theme import PeadraTheme
from ..database.db_manager import db


class AccountsView:
    """Vue de gestion des comptes."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.accounts = []

        # Dialog components
        self.dialog = None
        self.name_field = ft.TextField(label="Account Name", width=300)
        self.color_dropdown = ft.Dropdown(
            label="Color",
            options=[
                ft.dropdown.Option(
                    "#4CAF50",
                    "Green",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#4CAF50"),
                            ft.Text("Green"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#2196F3",
                    "Blue",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#2196F3"),
                            ft.Text("Blue"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#009688",
                    "Teal",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#009688"),
                            ft.Text("Teal"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#FF9800",
                    "Orange",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#FF9800"),
                            ft.Text("Orange"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#E91E63",
                    "Pink",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#E91E63"),
                            ft.Text("Pink"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#9C27B0",
                    "Purple",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#9C27B0"),
                            ft.Text("Purple"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#F44336",
                    "Red",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#F44336"),
                            ft.Text("Red"),
                        ]
                    ),
                ),
                ft.dropdown.Option(
                    "#607D8B",
                    "Gray",
                    content=ft.Row(
                        [
                            ft.Container(width=20, height=20, bgcolor="#607D8B"),
                            ft.Text("Gray"),
                        ]
                    ),
                ),
            ],
        )
        self.editing_id: Optional[int] = None

        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
        self.refresh()

    def refresh(self):
        """Rafraîchit les données et l'affichage."""
        self._load_data()
        if hasattr(self, "content"):
            self.content.content = self._build_content()
            self.content.update()

    def _load_data(self):
        self.accounts = db.get_categories_with_balances()

    def _open_dialog(self, account: Optional[dict] = None):
        """Ouvre la boîte de dialogue d'ajout/édition."""
        if account:
            self.editing_id = account["id"]
            self.name_field.value = account["name"]
            self.color_dropdown.value = account["color"]
            title = "Edit Account"
        else:
            self.editing_id = None
            self.name_field.value = ""
            self.color_dropdown.value = "#2196F3"  # Default color
            title = "New Account"

        self.dialog = ft.AlertDialog(
            title=ft.Text(title),
            content=ft.Column(
                [
                    self.name_field,
                    self.color_dropdown,
                ],
                tight=True,
                spacing=20,
            ),
            actions=[
                ft.TextButton("Cancel", on_click=self._close_dialog),
                ft.TextButton("Save", on_click=self._save_account),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(self.dialog)
        self.dialog.open = True
        self.page.update()

    def _close_dialog(self, e):
        if self.dialog:
            self.dialog.open = False
            self.page.update()

    def _save_account(self, e):
        name = self.name_field.value
        color = self.color_dropdown.value or "#2196F3"

        if not name:
            setattr(self.name_field, "error_text", "Please enter a name")
            self.name_field.update()
            return

        if self.editing_id:
            success = db.update_category(self.editing_id, name, color)
        else:
            success = db.add_category(name, color) != -1

        if success:
            self._close_dialog(None)
            self.refresh()
            self.on_data_change()  # Notify app to refresh other views
        else:
            setattr(self.name_field, "error_text", "Error (Name may already be in use)")
            self.name_field.update()

    def _delete_account(self, account_id):
        """Supprime un compte avec confirmation."""

        def close_delete_dlg(e):
            if self.confirm_dialog:
                self.confirm_dialog.open = False
                self.page.update()

        def confirm_delete(e):
            delete_history = bool(self.delete_history_checkbox.value)
            if db.delete_category(account_id, delete_transactions=delete_history):
                close_delete_dlg(None)
                self.refresh()
                self.on_data_change()

        self.delete_history_checkbox = ft.Checkbox(
            label="Also delete associated transactions",
            value=False,
            label_style=ft.TextStyle(
                color=PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
            ),
        )

        self.confirm_dialog = ft.AlertDialog(
            title=ft.Text("Delete Account?"),
            content=ft.Column(
                [
                    ft.Text("You are about to delete this account."),
                    self.delete_history_checkbox,
                ],
                tight=True,
            ),
            actions=[
                ft.TextButton("Cancel", on_click=close_delete_dlg),
                ft.TextButton(
                    "Delete",
                    on_click=confirm_delete,
                    style=ft.ButtonStyle(color=ft.Colors.RED),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        self.page.overlay.append(self.confirm_dialog)
        self.confirm_dialog.open = True
        self.page.update()

    def _build_account_card(self, account):
        """Construit une carte pour un compte."""
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Container(
                                content=ft.Icon(
                                    ft.Icons.ACCOUNT_BALANCE_WALLET,
                                    color=ft.Colors.WHITE,
                                    size=24,
                                ),
                                bgcolor=account["color"],
                                padding=12,
                                border_radius=12,
                            ),
                            ft.PopupMenuButton(
                                icon=ft.Icons.MORE_VERT,
                                icon_color=ft.Colors.GREY_500,
                                items=[
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            [
                                                ft.Icon(ft.Icons.EDIT),
                                                ft.Text("Edit"),
                                            ]
                                        ),
                                        on_click=lambda _: self._open_dialog(account),
                                    ),
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            [
                                                ft.Icon(ft.Icons.DELETE),
                                                ft.Text("Delete"),
                                            ]
                                        ),
                                        on_click=lambda _: self._delete_account(
                                            account["id"]
                                        ),
                                    ),
                                ],
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Container(height=12),
                    ft.Column(
                        [
                            ft.Text(
                                account["name"],
                                size=14,
                                color=ft.Colors.GREY_500,
                            ),
                            ft.Text(
                                f"€{account['balance']:,.2f}",
                                size=24,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        spacing=4,
                    ),
                ]
            ),
            padding=20,
            bgcolor=bg_card,
            border_radius=20,
            border=(
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_content(self):
        """Construit le contenu de la vue."""

        grid = ft.GridView(
            runs_count=3,
            max_extent=400,
            child_aspect_ratio=2.0,
            spacing=20,
            run_spacing=20,
        )

        for account in self.accounts:
            grid.controls.append(self._build_account_card(account))

        # Add "Add Card" button as a special card or FAB
        # To match "is cards and not a list" request, we can add a special card for adding
        add_container = ft.Container(
            content=ft.Column(
                [
                    ft.Icon(
                        ft.Icons.ADD_CIRCLE_OUTLINE, size=40, color=ft.Colors.GREY_500
                    ),
                    ft.Text("Add Account", color=ft.Colors.GREY_500),
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                spacing=10,
            ),
            padding=20,
            on_click=lambda _: self._open_dialog(),
            bgcolor=PeadraTheme.DARK_SURFACE
            if self.is_dark
            else PeadraTheme.LIGHT_SURFACE,
            border=ft.border.all(
                2, ft.Colors.GREY_800 if self.is_dark else ft.Colors.GREY_300
            ),
            border_radius=20,
        )

        grid.controls.append(add_container)

        return ft.Column(
            [
                ft.Text(
                    "Accounts",
                    size=32,
                    weight=ft.FontWeight.BOLD,
                    color=PeadraTheme.DARK_TEXT
                    if self.is_dark
                    else PeadraTheme.LIGHT_TEXT,
                ),
                ft.Container(height=20),
                ft.Container(content=grid, expand=True),
            ],
            expand=True,
            spacing=0,
        )

    def build(self):
        """Retourne la vue."""
        self.content = ft.Container(
            content=self._build_content(),
            padding=30,
            expand=True,
        )
        return self.content

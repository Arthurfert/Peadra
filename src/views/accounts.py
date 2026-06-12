"""
Vue Comptes pour Peadra.
Permet de gérer les comptes (catégories) : affichage, ajout, modification, suppression.
"""

import flet as ft
import logging
from typing import Callable, Optional
from ..components.theme import PeadraTheme
from ..database import db
from ..database.db_manager import CURRENCY_DATA, get_currency_symbol, get_currency_name, get_default_currency, format_amount, format_amount_with_conversion, _SYMBOL_TO_CODE
from ..i18n import t, get_translator

logger = logging.getLogger(__name__)


class AccountsView:
    """Vue de gestion des comptes."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.accounts = []
        self.currency = "EUR"

        # Dialog components
        self.dialog = None
        self.name_field = ft.TextField(label=t("acc_name"), width=300)
        self.update_history_checkbox = ft.Checkbox(
            label=t("acc_update_history"),
            value=True,
            label_style=ft.TextStyle(size=14, color=PeadraTheme.text_secondary),
        )
        self.type_dropdown = ft.Dropdown(
            label=t("acc_type"),
            options=[
                ft.dropdown.Option("savings", t("acc_savings")),
                ft.dropdown.Option("checking", t("acc_checking")),
            ],
            value="savings",
            width=300,
        )
        self.color_dropdown = ft.Dropdown(
            label=t("acc_color"),
            options=[
                ft.dropdown.Option(
                    hex_color,
                    content=ft.Container(width=20, height=20, bgcolor=hex_color),
                )
                for hex_color in PeadraTheme.chart_palette
            ],
        )
        self.currency_dropdown = ft.Dropdown(
            label=t("param_currency"),
            width=300,
            options=[
                ft.dropdown.Option(code, f"{code} - {get_currency_name(code, get_translator().get_language())} ({get_currency_symbol(code)})")
                for code in sorted(CURRENCY_DATA.keys())
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
            try:
                self.content.update()
            except RuntimeError:
                # Le control peut exister mais ne pas être monté sur la page.
                # Ignorer la mise à jour graphique dans ce cas.
                pass

    def _load_data(self):
        self.accounts = db.get_categories_with_balances()
        raw = db.get_setting("currency", "EUR") or "EUR"
        self.currency = _SYMBOL_TO_CODE.get(raw, raw) if raw in _SYMBOL_TO_CODE or raw in CURRENCY_DATA else "EUR"

    def _open_dialog(self, account: Optional[dict] = None):
        """Ouvre la boîte de dialogue d'ajout/édition."""
        if account:
            self.editing_id = account["id"]
            self.name_field.value = account["name"]
            self.color_dropdown.value = account["color"]
            self.type_dropdown.value = account.get("type", "savings")
            acc_currency = account.get("currency")
            if acc_currency and acc_currency in CURRENCY_DATA:
                self.currency_dropdown.value = acc_currency
            else:
                self.currency_dropdown.value = get_default_currency()
            self.update_history_checkbox.visible = True
            self.update_history_checkbox.value = True
            title = t("acc_edit_account")
        else:
            self.editing_id = None
            self.name_field.value = ""
            self.color_dropdown.value = "#3b82f6"
            self.type_dropdown.value = "savings"
            self.currency_dropdown.value = get_default_currency()
            self.update_history_checkbox.visible = False
            title = t("acc_add_account")

        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(title, color=PeadraTheme.text_secondary),
            content=ft.Column(
                [
                    self.name_field,
                    self.type_dropdown,
                    self.currency_dropdown,
                    self.color_dropdown,
                    self.update_history_checkbox,
                ],
                tight=True,
                spacing=20,
            ),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=self._close_dialog),
                ft.TextButton(t("btn_save"), on_click=self._save_account),
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

    def _show_merge_dialog(self, source_id, target_id, target_name):
        """Affiche la boîte de dialogue de fusion."""

        # Hide the edit dialog first
        if self.dialog:
            self.dialog.open = False
            self.page.update()

        def close_merge_dlg(e):
            if self.merge_dialog:
                self.merge_dialog.open = False
                self.page.update()

            # Re-open the edit dialog
            if self.dialog:
                self.dialog.open = True
                self.page.update()

        def confirm_merge(e):
            if db.merge_categories(source_id, target_id):
                logger.info(
                    "Categories merged: source_id=%s into target_id=%s",
                    source_id,
                    target_id,
                )
                # Close merge dialog
                if self.merge_dialog:
                    self.merge_dialog.open = False
                    self.page.update()

                # Refresh everything
                self.refresh()
                self.on_data_change()

                snack = ft.SnackBar(
                    content=ft.Text(
                        t("acc_merge_success").format(target_name=target_name)
                    )
                )
                self.page.overlay.append(snack)
                snack.open = True
                self.page.update()

        self.merge_dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(t("acc_merge_title"), color=PeadraTheme.text_secondary),
            content=ft.Text(t("acc_merge_message").format(target_name=target_name), color=PeadraTheme.text_secondary),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=close_merge_dlg),
                ft.TextButton(
                    t("btn_merge"),
                    on_click=confirm_merge,
                    style=ft.ButtonStyle(color=PeadraTheme.add_color),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(self.merge_dialog)
        self.merge_dialog.open = True
        self.page.update()

    def _save_account(self, e):
        raw_name = self.name_field.value or ""
        name = raw_name.strip()
        color = self.color_dropdown.value or "#2196F3"
        account_type = self.type_dropdown.value or "savings"
        currency = self.currency_dropdown.value or get_default_currency()
        update_history = self.update_history_checkbox.value

        if not name:
            setattr(self.name_field, "error_text", t("acc_error_no_name"))
            self.name_field.update()
            return

        # Determine effective mode (Edit vs New)
        is_edit_mode = self.editing_id is not None and update_history

        # Check for name collision (Case Insensitive)
        collision_id = None
        collision_name = None
        for acc in self.accounts:
            if acc["name"].lower() == name.lower():
                collision_id = acc["id"]
                collision_name = acc["name"]
                break

        # If collision found
        if collision_id:
            # Case 1: Renaming existing account (Update History = True) and name taken by OTHER
            if is_edit_mode and collision_id != self.editing_id:
                self._show_merge_dialog(self.editing_id, collision_id, collision_name)
                return

            # Case 2: New account (or Edit with History Off) and name taken
            elif not is_edit_mode:
                setattr(self.name_field, "error_text", t("acc_error_exists"))
                self.name_field.update()
                return

            # Case 3: Renaming to self (no change) -> Proceed

        if is_edit_mode and self.editing_id is not None:
            success = db.update_category(
                self.editing_id, name, color, account_type=account_type, currency=currency
            )
        else:
            success = db.add_category(name, color, account_type=account_type, currency=currency) != -1

        if success:
            logger.info(
                "Account saved: id=%s name='%s' type=%s",
                self.editing_id or "new",
                name,
                account_type,
            )
            self._close_dialog(None)
            self.refresh()
            self.on_data_change()
        else:
            setattr(self.name_field, "error_text", t("acc_error_save"))
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
                logger.info(
                    "Account deleted: id=%s delete_transactions=%s",
                    account_id,
                    delete_history,
                )
                close_delete_dlg(None)
                self.refresh()
                self.on_data_change()

        self.delete_history_checkbox = ft.Checkbox(
            label=t("acc_delete_transactions"),
            value=False,
            label_style=ft.TextStyle(
                color=PeadraTheme.text_secondary
            ),
        )

        self.confirm_dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(t("acc_delete_confirm"), color=PeadraTheme.text_secondary),
            content=ft.Column(
                [
                    ft.Text(t("acc_delete_message"), color=PeadraTheme.text_secondary),
                    self.delete_history_checkbox,
                ],
                tight=True,
            ),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=close_delete_dlg),
                ft.TextButton(
                    t("btn_delete"),
                    on_click=confirm_delete,
                    style=ft.ButtonStyle(color=PeadraTheme.delete_color),
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
            PeadraTheme.surface
        )
        text_color = PeadraTheme.text

        acc_currency = account.get("currency") or get_default_currency()
        balance_text = format_amount_with_conversion(account["balance"], acc_currency, self.currency)

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
                                icon_color=PeadraTheme.placeholder_color,
                                items=[
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            [
                                                ft.Icon(ft.Icons.EDIT),
                                                ft.Text(t("btn_edit")),
                                            ]
                                        ),
                                        on_click=lambda _: self._open_dialog(account),
                                    ),
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            [
                                                ft.Icon(ft.Icons.DELETE),
                                                ft.Text(t("btn_delete")),
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
                                color=PeadraTheme.placeholder_color,
                            ),
                            ft.Text(
                                balance_text,
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
                ft.border.all(1, PeadraTheme.divider)
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

        add_container = ft.Container(
            content=ft.Column(
                [
                        ft.Icon(
                            ft.Icons.ADD_CIRCLE_OUTLINE, size=40, color=PeadraTheme.placeholder_color
                        ),
                        ft.Text(t("acc_add_account"), color=PeadraTheme.placeholder_color),
                ],
                alignment=ft.MainAxisAlignment.CENTER,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                spacing=10,
            ),
            padding=20,
            on_click=lambda _: self._open_dialog(),
            bgcolor=(
                PeadraTheme.surface
            ),
            border=ft.border.all(
                2, PeadraTheme.divider
            ),
            border_radius=20,
        )

        grid.controls.append(add_container)

        return ft.Column(
            [
                ft.Text(
                    t("acc_title"),
                    size=32,
                    weight=ft.FontWeight.BOLD,
                    color=PeadraTheme.text,
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
            padding=ft.padding.only(left=30, right=30, top=30, bottom=8),
            expand=True,
        )
        return self.content

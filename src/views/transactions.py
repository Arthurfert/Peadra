"""
Vue Transactions pour Peadra.
Interface simplifiée : Liste des transactions et gestion des actifs.
"""

import flet as ft
from typing import Callable, Optional
from datetime import datetime
from ..components.theme import PeadraTheme
from ..components.modals import TransactionModal
from ..database.db_manager import db


class TransactionsView:
    """Vue des transactions simplifiée."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.transactions = []
        self.search_query = ""
        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()

    def _load_data(self):
        """Charge les données."""
        self.transactions = db.get_all_transactions()
        self.categories = db.get_all_categories()
        self.subcategories = db.get_all_subcategories()
        # Filter if search query exists
        if self.search_query:
            q = self.search_query.lower()
            self.transactions = [
                t for t in self.transactions 
                if q in t['description'].lower() or q in (t.get('category_name') or '').lower()
            ]

    def _open_type_selector(self, e):
        """Ouvre le dialogue de sélection du type de transaction."""
        
        def close_dlg(e):
            if isinstance(self.page.dialog, ft.AlertDialog):
                self.page.dialog.open = False
                self.page.update()

        def select_bank(e):
            close_dlg(e)
            self._open_transaction_modal("bank")

        def select_asset(e):
            close_dlg(e)
            self._open_transaction_modal("asset")

        dlg = ft.AlertDialog(
            title=ft.Text("Nouveau mouvement"),
            content=ft.Column([
                ft.Text("Quel type d'opération souhaitez-vous ajouter ?"),
                ft.Container(height=20),
                ft.Row([
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.icons.ACCOUNT_BALANCE, size=30, color=PeadraTheme.PRIMARY_MEDIUM),
                            ft.Text("Banque", weight=ft.FontWeight.BOLD)
                        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                        padding=20,
                        bgcolor=ft.colors.BLUE_50,
                        border_radius=10,
                        on_click=select_bank,
                        expand=True
                    ),
                    ft.Container(
                        content=ft.Column([
                            ft.Icon(ft.icons.SHOW_CHART, size=30, color=PeadraTheme.IMMO_COLOR),
                            ft.Text("Action / Actif", weight=ft.FontWeight.BOLD)
                        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                        padding=20,
                        bgcolor=ft.colors.ORANGE_50,
                        border_radius=10,
                        on_click=select_asset,
                        expand=True
                    ),
                ], spacing=20)
            ], tight=True, width=400),
            actions=[
                ft.TextButton("Annuler", on_click=close_dlg)
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.dialog = dlg
        dlg.open = True
        self.page.update()

    def _open_transaction_modal(self, type_: str):
        """Ouvre le modal de transaction."""
        # Note: Dans une version future, on pourrait avoir un modal spécifique pour "asset"
        # Pour l'instant on utilise le même modal, mais on pourrait pré-sélectionner une catégorie "Investissement"
        # si elle existe.
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            subcategories=self.subcategories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            filter_type=type_
        )
        modal.show()

    def _save_transaction(self, data: dict):
        """Enregistre la transaction."""
        db.add_transaction(
            date=data["date"],
            description=data["description"],
            amount=data["amount"],
            transaction_type=data["transaction_type"],
            category_id=data.get("category_id"),
            subcategory_id=data.get("subcategory_id"),
            notes=data.get("notes"),
        )
        
        # Si c'était un 'asset' (logique simplifiée ici), on pourrait aussi ajouter une entrée dans 'assets'
        # Mais pour respecter "simplifier", on reste sur le flux transactionnel.
        
        self.page.snack_bar = ft.SnackBar(ft.Text("Transaction ajoutée"))
        self.page.snack_bar.open = True
        self.on_data_change()

    def _on_search_change(self, e):
        """Gère la recherche."""
        self.search_query = e.control.value
        self.on_data_change() # Trigger reload via main app which calls refresh() -> _load_data

    def _get_category_color(self, cat_name: str) -> str:
        """Retourne une couleur pastel basée sur le nom de la catégorie."""
        if not cat_name: return ft.colors.GREY_200
        cat = cat_name.lower()
        if "income" in cat or "revenu" in cat or "salaire" in cat: return ft.colors.GREEN_100
        if "food" in cat or "course" in cat or "restaurant" in cat: return ft.colors.ORANGE_100
        if "bill" in cat or "facture" in cat: return ft.colors.BLUE_100
        if "shop" in cat or "achat" in cat: return ft.colors.PURPLE_100
        if "transport" in cat: return ft.colors.YELLOW_100
        if "entertain" in cat or "loisir" in cat: return ft.colors.PINK_100
        return ft.colors.GREY_100

    def _get_category_text_color(self, cat_name: str) -> str:
        # Simple contrast: darker version of pastel
        if not cat_name: return ft.colors.GREY_800
        return ft.colors.GREY_900

    def build(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        surface_color = PeadraTheme.DARK_SURFACE if self.is_dark else ft.colors.WHITE
        
        # Header
        header = ft.Row(
            [
                ft.Column([
                    ft.Text("Transactions", size=32, weight=ft.FontWeight.BOLD, color=text_color),
                    ft.Text("View and manage your recent transactions.", size=16, color=ft.colors.GREY),
                ]),
                ft.ElevatedButton(
                    "Add Transaction",
                    icon=ft.icons.ADD,
                    bgcolor=PeadraTheme.ACCENT,
                    color=ft.colors.WHITE,
                    on_click=self._open_type_selector
                )
            ],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN
        )

        # Search Bar
        search_bar = ft.Row(
            [
                ft.TextField(
                    hint_text="Search transactions...",
                    prefix_icon=ft.icons.SEARCH,
                    border_radius=8,
                    bgcolor=ft.colors.with_opacity(0.05, text_color),
                    border_color=ft.colors.TRANSPARENT,
                    expand=True,
                    on_change=self._on_search_change
                ),
                ft.Container(width=10),
                ft.OutlinedButton(
                    "Filter",
                    icon=ft.icons.FILTER_LIST,
                    style=ft.ButtonStyle(
                        shape=ft.RoundedRectangleBorder(radius=8),
                    )
                )
            ]
        )

        # Transaction List - Table Header
        table_header = ft.Container(
            content=ft.Row(
                [
                    ft.Container(ft.Text("Description", weight=ft.FontWeight.BOLD, color=ft.colors.GREY_700), expand=3),
                    ft.Container(ft.Text("Category", weight=ft.FontWeight.BOLD, color=ft.colors.GREY_700), expand=2),
                    ft.Container(ft.Text("Date", weight=ft.FontWeight.BOLD, color=ft.colors.GREY_700), expand=2),
                    ft.Container(ft.Text("Amount", weight=ft.FontWeight.BOLD, color=ft.colors.GREY_700, text_align=ft.TextAlign.RIGHT), expand=1),
                ],
            ),
            padding=ft.padding.symmetric(horizontal=16, vertical=12),
            border=ft.border.only(bottom=ft.border.BorderSide(1, ft.colors.GREY_200)),
        )

        # Transaction Rows
        rows = []
        for t in self.transactions:
            is_income = t['transaction_type'] == 'income'
            amount_color = ft.colors.GREEN if is_income else text_color
            amount_prefix = "+" if is_income else ""
            
            icon = ft.icons.NORTH_EAST if is_income else ft.icons.SOUTH_WEST
            icon_color = ft.colors.GREEN if is_income else ft.colors.RED
            icon_bg = ft.colors.GREEN_50 if is_income else ft.colors.RED_50
            if self.is_dark:
                 icon_bg = ft.colors.with_opacity(0.1, icon_color)

            cat_name = t['subcategory_name'] or ""
            cat_bg = self._get_category_color(cat_name)
            cat_text_col = self._get_category_text_color(cat_name)
            
            if self.is_dark:
                # Adjust pastel colors for dark mode visibility or keep them with opacity?
                # Simple fix: Use opacity on the container
                pass # Already handled by specific color choices usually, but let's stick to light mode visuals as base logic

            try:
                date_obj = datetime.strptime(t['date'], "%Y-%m-%d")
                date_str = date_obj.strftime("%b %d, %Y")
            except:
                date_str = t['date']

            row = ft.Container(
                content=ft.Row(
                    [
                        # Description + Icon
                        ft.Container(
                            content=ft.Row([
                                ft.Container(
                                    content=ft.Icon(icon, color=icon_color, size=16),
                                    bgcolor=icon_bg,
                                    padding=8,
                                    border_radius=8,
                                ),
                                ft.Text(t['description'], weight=ft.FontWeight.W_500, color=text_color)
                            ], spacing=12),
                            expand=3
                        ),
                        # Category
                        ft.Container(
                            content=ft.Container(
                                content=ft.Text(cat_name, size=12, color=cat_text_col, weight=ft.FontWeight.BOLD),
                                bgcolor=cat_bg,
                                padding=ft.padding.symmetric(horizontal=12, vertical=4),
                                border_radius=12,
                            ),
                            expand=2,
                            alignment=ft.alignment.center_left
                        ),
                        # Date
                        ft.Container(
                            ft.Text(date_str, color=text_color),
                            expand=2
                        ),
                        # Amount
                        ft.Container(
                            ft.Text(f"{amount_prefix}${t['amount']:,.2f}", weight=ft.FontWeight.BOLD, color=amount_color, text_align=ft.TextAlign.RIGHT),
                            expand=1,
                            alignment=ft.alignment.center_right
                        ),
                    ]
                ),
                padding=ft.padding.symmetric(horizontal=16, vertical=16),
                border=ft.border.only(bottom=ft.border.BorderSide(1, ft.colors.with_opacity(0.1, ft.colors.GREY)))
            )
            rows.append(row)

        if not rows:
             rows.append(ft.Container(content=ft.Text("No recent transactions", color=ft.colors.GREY), padding=20, alignment=ft.alignment.center))

        list_container = ft.Container(
            content=ft.Column(
                [table_header] + rows,
                scroll=ft.ScrollMode.AUTO,
                spacing=0
            ),
            bgcolor=surface_color,
            border_radius=12,
            border=ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY)) if not self.is_dark else None,
            expand=True
        )

        return ft.Container(
            content=ft.Column(
                [
                    header,
                    ft.Container(height=20),
                    search_bar,
                    ft.Container(height=20),
                    list_container
                ],
                expand=True
            ),
            padding=30,
            expand=True
        )

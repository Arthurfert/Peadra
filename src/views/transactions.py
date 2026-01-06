"""
Vue Transactions pour Peadra.
Interface simplifiée : Liste des transactions et gestion des actifs.
"""

import flet as ft
from typing import Callable
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
        self.selected_subcategories = set()
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
                t
                for t in self.transactions
                if q in t["description"].lower()
                or q in (t.get("category_name") or "").lower()
            ]

        # Filter by subcategories
        if self.selected_subcategories:
            self.transactions = [
                t
                for t in self.transactions
                if str(t.get("subcategory_id")) in self.selected_subcategories
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
            content=ft.Column(
                [
                    ft.Text("Quel type d'opération souhaitez-vous ajouter ?"),
                    ft.Container(height=20),
                    ft.Row(
                        [
                            ft.Container(
                                content=ft.Column(
                                    [
                                        ft.Icon(
                                            ft.icons.ACCOUNT_BALANCE,
                                            size=30,
                                            color=PeadraTheme.PRIMARY_MEDIUM,
                                        ),
                                        ft.Text("Banque", weight=ft.FontWeight.BOLD),
                                    ],
                                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                padding=20,
                                bgcolor=ft.colors.BLUE_50,
                                border_radius=10,
                                on_click=select_bank,
                                expand=True,
                            ),
                            ft.Container(
                                content=ft.Column(
                                    [
                                        ft.Icon(
                                            ft.icons.SHOW_CHART,
                                            size=30,
                                            color=PeadraTheme.IMMO_COLOR,
                                        ),
                                        ft.Text(
                                            "Action / Actif", weight=ft.FontWeight.BOLD
                                        ),
                                    ],
                                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                padding=20,
                                bgcolor=ft.colors.ORANGE_50,
                                border_radius=10,
                                on_click=select_asset,
                                expand=True,
                            ),
                        ],
                        spacing=20,
                    ),
                ],
                tight=True,
                width=400,
            ),
            actions=[ft.TextButton("Annuler", on_click=close_dlg)],
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
            filter_type=type_,
        )
        modal.show()

    def _open_filter_dialog(self, e):
        """Ouvre le dialogue de filtrage par sous-catégories."""

        selected = set(self.selected_subcategories)
        checkboxes = []

        # Sort subcategories by name
        sorted_subcats = sorted(self.subcategories, key=lambda x: x["name"])

        for sub in sorted_subcats:
            sub_id = str(sub["id"])
            checkboxes.append(
                ft.Checkbox(label=sub["name"], value=(sub_id in selected), data=sub_id)
            )

        def close_dlg(e):
            if isinstance(self.page.dialog, ft.AlertDialog):
                self.page.dialog.open = False
                self.page.update()

        def apply_filter(e):
            self.selected_subcategories = {c.data for c in checkboxes if c.value}
            close_dlg(e)
            self._load_data()
            if hasattr(self, "content_column") and hasattr(self, "table_header"):
                self.content_column.controls = [
                    self.table_header
                ] + self._generate_rows()
                self.content_column.update()

        def clear_filter(e):
            for c in checkboxes:
                c.value = False
            if self.page.dialog:
                self.page.dialog.update()

        dlg = ft.AlertDialog(
            title=ft.Text("Filtrer par catégorie"),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.TextButton("Tout désélectionner", on_click=clear_filter),
                        ft.Column(checkboxes, scroll=ft.ScrollMode.AUTO, expand=True),
                    ],
                ),
                width=300,
                height=400,
            ),
            actions=[
                ft.TextButton("Annuler", on_click=close_dlg),
                ft.ElevatedButton(
                    "Appliquer",
                    on_click=apply_filter,
                    bgcolor=PeadraTheme.ACCENT,
                    color=ft.colors.WHITE,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.dialog = dlg
        dlg.open = True
        self.page.update()

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

    def _generate_rows(self):
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        rows = []
        for t in self.transactions:
            is_income = t["transaction_type"] == "income"
            amount_color = ft.colors.GREEN if is_income else text_color
            amount_prefix = "+" if is_income else ""

            icon = ft.icons.NORTH_EAST if is_income else ft.icons.SOUTH_WEST
            icon_color = ft.colors.GREEN if is_income else ft.colors.RED
            icon_bg = ft.colors.GREEN_50 if is_income else ft.colors.RED_50
            if self.is_dark:
                icon_bg = ft.colors.with_opacity(0.1, icon_color)

            cat_name = t["subcategory_name"] or ""
            cat_bg = self._get_category_color(cat_name)
            cat_text_col = self._get_category_text_color(cat_name)

            try:
                date_obj = datetime.strptime(t["date"], "%Y-%m-%d")
                date_str = date_obj.strftime("%b %d, %Y")
            except:
                date_str = t["date"]

            row = ft.Container(
                content=ft.Row(
                    [
                        # Description + Icon
                        ft.Container(
                            content=ft.Row(
                                [
                                    ft.Container(
                                        content=ft.Icon(
                                            icon, color=icon_color, size=16
                                        ),
                                        bgcolor=icon_bg,
                                        padding=8,
                                        border_radius=8,
                                    ),
                                    ft.Text(
                                        t["description"],
                                        weight=ft.FontWeight.W_500,
                                        color=text_color,
                                    ),
                                ],
                                spacing=12,
                            ),
                            expand=3,
                        ),
                        # Category
                        ft.Container(
                            content=ft.Container(
                                content=ft.Text(
                                    cat_name,
                                    size=12,
                                    color=cat_text_col,
                                    weight=ft.FontWeight.BOLD,
                                ),
                                bgcolor=cat_bg,
                                padding=ft.padding.symmetric(horizontal=12, vertical=4),
                                border_radius=12,
                            ),
                            expand=2,
                            alignment=ft.alignment.center_left,
                        ),
                        # Date
                        ft.Container(ft.Text(date_str, color=text_color), expand=2),
                        # Amount
                        ft.Container(
                            ft.Text(
                                f"{amount_prefix}€{t['amount']:,.2f}",
                                weight=ft.FontWeight.BOLD,
                                color=amount_color,
                                text_align=ft.TextAlign.RIGHT,
                            ),
                            expand=1,
                            alignment=ft.alignment.center_right,
                        ),
                    ]
                ),
                padding=ft.padding.symmetric(horizontal=16, vertical=16),
                border=ft.border.only(
                    bottom=ft.border.BorderSide(
                        1, ft.colors.with_opacity(0.1, ft.colors.GREY)
                    )
                ),
            )
            rows.append(row)

        if not rows:
            rows.append(
                ft.Container(
                    content=ft.Text("No recent transactions", color=ft.colors.GREY),
                    padding=20,
                    alignment=ft.alignment.center,
                )
            )

        return rows

    def _on_search_change(self, e):
        """Gère la recherche."""
        self.search_query = e.control.value
        self._load_data()

        if hasattr(self, "content_column") and hasattr(self, "table_header"):
            self.content_column.controls = [self.table_header] + self._generate_rows()
            self.content_column.update()

    def _get_category_color(self, cat_name: str) -> str:
        """Retourne une couleur distinctive basée sur le nom de la sous-catégorie."""
        if not cat_name:
            return ft.colors.GREY_300
        
        cat = cat_name.lower()
        
        # Cash / Banque
        if "compte courant" in cat: return ft.colors.BLUE_300
        if "livret" in cat or "épargne" in cat: return ft.colors.YELLOW_300
        if "espèces" in cat or "cash" in cat: return ft.colors.GREEN_300
        
        # Investissements
        if "crypto" in cat or "bitcoin" in cat: return ft.colors.ORANGE_400
        if "action" in cat or "etf" in cat or "pea" in cat or "bourse" in cat: return ft.colors.INDIGO_300
        if "obligation" in cat: return ft.colors.CYAN_300
        
        # Immobilier
        if "immobilier" in cat or "maison" in cat or "appart" in cat or "scpi" in cat: return ft.colors.BROWN_300
        
        # Fallback sur les mot-clés descriptions si la sous-catégorie ne matche pas
        if "salaire" in cat: return ft.colors.TEAL_300
        if "course" in cat: return ft.colors.AMBER_300
        
        return ft.colors.GREY_300

    def _get_category_text_color(self, cat_name: str) -> str:
        # Simple contrast: darker version of pastel
        if not cat_name:
            return ft.colors.GREY_800
        return ft.colors.GREY_900

    def build(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        surface_color = PeadraTheme.DARK_SURFACE if self.is_dark else ft.colors.WHITE

        # Header
        header = ft.Row(
            [
                ft.Column(
                    [
                        ft.Text(
                            "Transactions",
                            size=32,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                        ft.Text(
                            "View and manage your recent transactions.",
                            size=16,
                            color=ft.colors.GREY,
                        ),
                    ]
                ),
                ft.ElevatedButton(
                    "Add Transaction",
                    icon=ft.icons.ADD,
                    bgcolor=PeadraTheme.ACCENT,
                    color=ft.colors.WHITE,
                    on_click=self._open_type_selector,
                ),
            ],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        # Search Bar
        search_bar = ft.Row(
            [
                ft.TextField(
                    hint_text="Search transactions...",
                    value=self.search_query,
                    prefix_icon=ft.icons.SEARCH,
                    border_radius=8,
                    bgcolor=ft.colors.with_opacity(0.05, text_color),
                    border_color=ft.colors.TRANSPARENT,
                    expand=True,
                    on_change=self._on_search_change,
                ),
                ft.Container(width=10),
                ft.OutlinedButton(
                    "Filter",
                    icon=ft.icons.FILTER_LIST,
                    style=ft.ButtonStyle(
                        shape=ft.RoundedRectangleBorder(radius=8),
                    ),
                    on_click=self._open_filter_dialog,
                ),
            ]
        )

        # Transaction List - Table Header
        self.table_header = ft.Container(
            content=ft.Row(
                [
                    ft.Container(
                        ft.Text(
                            "Description",
                            weight=ft.FontWeight.BOLD,
                            color=ft.colors.GREY_700,
                        ),
                        expand=3,
                    ),
                    ft.Container(
                        ft.Text(
                            "Category",
                            weight=ft.FontWeight.BOLD,
                            color=ft.colors.GREY_700,
                        ),
                        expand=2,
                    ),
                    ft.Container(
                        ft.Text(
                            "Date", weight=ft.FontWeight.BOLD, color=ft.colors.GREY_700
                        ),
                        expand=2,
                    ),
                    ft.Container(
                        ft.Text(
                            "Amount",
                            weight=ft.FontWeight.BOLD,
                            color=ft.colors.GREY_700,
                            text_align=ft.TextAlign.RIGHT,
                        ),
                        expand=1,
                    ),
                ],
            ),
            padding=ft.padding.symmetric(horizontal=16, vertical=12),
            border=ft.border.only(bottom=ft.border.BorderSide(1, ft.colors.GREY_200)),
        )

        rows = self._generate_rows()

        self.content_column = ft.Column(
            [self.table_header] + rows, scroll=ft.ScrollMode.AUTO, spacing=0
        )

        list_container = ft.Container(
            content=self.content_column,
            bgcolor=surface_color,
            border_radius=12,
            border=(
                ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                if not self.is_dark
                else None
            ),
            expand=True,
        )

        return ft.Container(
            content=ft.Column(
                [
                    header,
                    ft.Container(height=20),
                    search_bar,
                    ft.Container(height=20),
                    list_container,
                ],
                expand=True,
            ),
            padding=30,
            expand=True,
        )

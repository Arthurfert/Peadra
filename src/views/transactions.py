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

        # Theme colors
        if self.is_dark:
            expense_bg = ft.colors.with_opacity(0.15, ft.colors.RED)
            income_bg = ft.colors.with_opacity(0.15, ft.colors.GREEN)
            transfer_bg = ft.colors.with_opacity(0.15, ft.colors.BLUE)
            expense_icon_col = ft.colors.RED_200
            income_icon_col = ft.colors.GREEN_200
            transfer_icon_col = ft.colors.BLUE_200
            text_col = ft.colors.WHITE
        else:
            expense_bg = ft.colors.RED_50
            income_bg = ft.colors.GREEN_50
            transfer_bg = ft.colors.BLUE_50
            expense_icon_col = ft.colors.RED_700
            income_icon_col = ft.colors.GREEN_700
            transfer_icon_col = ft.colors.BLUE_700
            text_col = ft.colors.BLACK

        def close_dlg(e):
            if isinstance(self.page.dialog, ft.AlertDialog):
                self.page.dialog.open = False
                self.page.update()

        def select_expense(e):
            close_dlg(e)
            self._open_transaction_modal("expense")
        
        def select_income(e):
            close_dlg(e)
            self._open_transaction_modal("income")

        def select_transfer(e):
            close_dlg(e)
            self._open_transaction_modal("transfer")

        def create_option_card(icon, label, color, bg_color, on_click):
            return ft.Container(
                content=ft.Column(
                    [
                        ft.Icon(icon, size=30, color=color),
                        ft.Text(label, weight=ft.FontWeight.BOLD, color=text_col),
                    ],
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    alignment=ft.MainAxisAlignment.CENTER,
                ),
                padding=20,
                bgcolor=bg_color,
                border_radius=10,
                on_click=on_click,
                expand=True,
            )

        dlg = ft.AlertDialog(
            title=ft.Text("New Transaction", color=text_col),
            content=ft.Container(
                content=ft.Row(
                    [
                        create_option_card(
                            ft.icons.CREDIT_CARD,
                            "Expense",
                            expense_icon_col,
                            expense_bg,
                            select_expense
                        ),
                        create_option_card(
                            ft.icons.MONETIZATION_ON,
                            "Income",
                            income_icon_col,
                            income_bg,
                            select_income
                        ),
                        create_option_card(
                            ft.icons.SWAP_HORIZ,
                            "Transfer",
                            transfer_icon_col,
                            transfer_bg,
                            select_transfer
                        ),
                    ],
                    spacing=15,
                    vertical_alignment=ft.CrossAxisAlignment.STRETCH,
                ),
                width=500,
                height=140, 
                padding=10
            ),
            actions=[ft.TextButton("Cancel", on_click=close_dlg)],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.dialog = dlg
        dlg.open = True
        self.page.update()

    def _open_transaction_modal(self, type_: str):
        """Ouvre le modal de transaction."""
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            subcategories=self.subcategories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            transaction_type=type_,
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
            title=ft.Text("Filter by categories"),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.TextButton("Deselect All", on_click=clear_filter),
                        ft.Column(checkboxes, scroll=ft.ScrollMode.AUTO, expand=True),
                    ],
                ),
                width=300,
                height=400,
            ),
            actions=[
                ft.TextButton("Cancel", on_click=close_dlg),
                ft.ElevatedButton(
                    "Apply Filters",
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
        """Enregistre ou met à jour la transaction."""
        
        if data.get("id"):
            # Mise à jour
            if data["transaction_type"] == "transfer" and data.get("other_id"):
                # Update both sides of transfer
                # 1. Expense (Source)
                db.update_transaction(
                    data["id"],
                    date=data["date"],
                    description=f"Virement vers {data.get('dest_name', 'compte')}",
                    amount=data["amount"],
                    subcategory_id=data.get("source_id"),
                    notes=data.get("notes"),
                )
                # 2. Income (Dest)
                db.update_transaction(
                    data["other_id"],
                    date=data["date"],
                    description=f"Virement de {data.get('source_name', 'compte')}",
                    amount=data["amount"],
                    subcategory_id=data.get("dest_id"),
                    notes=data.get("notes"),
                )
                msg = "Virement modifié"
            else:
                db.update_transaction(
                    data["id"],
                    date=data["date"],
                    description=data["description"],
                    amount=data["amount"],
                    transaction_type=data["transaction_type"],
                    category_id=data.get("category_id"),
                    subcategory_id=data.get("subcategory_id"),
                    notes=data.get("notes"),
                )
                msg = "Transaction modifiée"

        elif data["transaction_type"] == "transfer":
            # Création - Transfert (2 transactions)
            
            # 1. Expense from source
            db.add_transaction(
                date=data["date"],
                description=f"Virement vers {data.get('dest_name', 'compte')}",
                amount=data["amount"],
                transaction_type="expense",
                category_id=None,
                subcategory_id=data.get("source_id"),
                notes=data.get("notes"),
            )
            
            # 2. Income to dest
            db.add_transaction(
                date=data["date"],
                description=f"Virement de {data.get('source_name', 'compte')}",
                amount=data["amount"],
                transaction_type="income",
                category_id=None,
                subcategory_id=data.get("dest_id"),
                notes=data.get("notes"),
            )
            
            msg = "Virement effectué avec succès"
            
        else:
            # Création - Standard
            db.add_transaction(
                date=data["date"],
                description=data["description"],
                amount=data["amount"],
                transaction_type=data["transaction_type"],
                category_id=data.get("category_id"),
                subcategory_id=data.get("subcategory_id"),
                notes=data.get("notes"),
            )
            msg = "Transaction ajoutée"

        self.page.snack_bar = ft.SnackBar(ft.Text(msg))
        self.page.snack_bar.open = True
        self.on_data_change()

    def _edit_transaction(self, transaction):
        """Ouvre le modal d'édition."""
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            subcategories=self.subcategories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            transaction_type=transaction["transaction_type"],
        )
        modal.show(transaction)

    def _confirm_delete(self, transaction_id):
        """Demande confirmation avant suppression."""
        def close_dlg(e):
            if isinstance(self.page.dialog, ft.AlertDialog):
                self.page.dialog.open = False
                self.page.update()

        def delete(e):
            db.delete_transaction(transaction_id)
            close_dlg(e)
            self.on_data_change()
            self.page.snack_bar = ft.SnackBar(ft.Text("Transaction supprimée"))
            self.page.snack_bar.open = True

        dlg = ft.AlertDialog(
            title=ft.Text("Confirmer la suppression"),
            content=ft.Text("Voulez-vous vraiment supprimer cette transaction ?"),
            actions=[
                ft.TextButton("Annuler", on_click=close_dlg),
                ft.TextButton("Supprimer", on_click=delete, style=ft.ButtonStyle(color=ft.colors.RED)),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.dialog = dlg
        dlg.open = True
        self.page.update()

    def _group_transactions(self, transactions):
        grouped = []
        i = 0
        while i < len(transactions):
            t1 = transactions[i]
            
            # Transfer signatures
            desc1 = t1["description"] or ""
            is_transfer_candidate = desc1.startswith("Virement vers ") or desc1.startswith("Virement de ")
            
            if is_transfer_candidate and i + 1 < len(transactions):
                t2 = transactions[i+1]
                desc2 = t2["description"] or ""
                
                # Check match: same amount, date, different type
                if (t1["amount"] == t2["amount"] and 
                    t1["date"] == t2["date"] and
                    t1["transaction_type"] != t2["transaction_type"]):
                    
                    match = False
                    source = None
                    dest = None
                    source_id = None
                    dest_id = None
                    id_expense = None
                    id_income = None
                    
                    # Determine which is which
                    if t1["transaction_type"] == "expense" and desc1.startswith("Virement vers "):
                         if t2["transaction_type"] == "income" and desc2.startswith("Virement de "):
                             dest = desc1[14:]
                             source = desc2[12:]
                             source_id = t1["subcategory_id"]
                             dest_id = t2["subcategory_id"]
                             id_expense = t1["id"]
                             id_income = t2["id"]
                             match = True
                    elif t1["transaction_type"] == "income" and desc1.startswith("Virement de "):
                         if t2["transaction_type"] == "expense" and desc2.startswith("Virement vers "):
                             source = desc1[12:]
                             dest = desc2[14:]
                             source_id = t2["subcategory_id"]
                             dest_id = t1["subcategory_id"]
                             id_expense = t2["id"]
                             id_income = t1["id"]
                             match = True
                    
                    if match:
                        combined = t1.copy()
                        combined["ids"] = [t1["id"], t2["id"]] # Both IDs for deletion
                        combined["id"] = id_expense # Use expense ID as primary for editing
                        combined["other_id"] = id_income
                        combined["description"] = f"Transfert de {source} vers {dest}"
                        combined["transaction_type"] = "transfer_group"
                        combined["subcategory_name"] = "Virement"
                        combined["subcategory_id"] = None
                        combined["category_color"] = ft.colors.BLUE_GREY_100
                        combined["source_id"] = source_id
                        combined["dest_id"] = dest_id
                        grouped.append(combined)
                        i += 2
                        continue
            
            grouped.append(t1)
            i += 1
        return grouped

    def _edit_transfer_group(self, t):
        data = {
            "id": t["id"],
            "other_id": t["other_id"],
            "date": t["date"],
            "description": t["description"], # Not really used in modal for transfer pre-fill strictly but good to have
            "amount": t["amount"],
            "transaction_type": "transfer",
            "notes": t.get("notes"),
            "source_id": t["source_id"],
            "dest_id": t["dest_id"]
        }
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            subcategories=self.subcategories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            transaction_type="transfer",
        )
        modal.show(data)

    def _confirm_delete_group(self, ids):
        def close_dlg(e):
            if isinstance(self.page.dialog, ft.AlertDialog):
                self.page.dialog.open = False
                self.page.update()

        def delete(e):
            for tid in ids:
                db.delete_transaction(tid)
            close_dlg(e)
            self.on_data_change()
            self.page.snack_bar = ft.SnackBar(ft.Text("Virement supprimé"))
            self.page.snack_bar.open = True

        dlg = ft.AlertDialog(
            title=ft.Text("Confirmer la suppression"),
            content=ft.Text("Voulez-vous vraiment supprimer ce virement (2 transactions) ?"),
            actions=[
                ft.TextButton("Annuler", on_click=close_dlg),
                ft.TextButton("Supprimer", on_click=delete, style=ft.ButtonStyle(color=ft.colors.RED)),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.dialog = dlg
        dlg.open = True
        self.page.update()

    def _generate_rows(self):
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        rows = []
        
        display_transactions = self._group_transactions(self.transactions)

        for t in display_transactions:
            is_group = t.get("transaction_type") == "transfer_group"
            
            if is_group:
                # TRANSFER ROW
                icon = ft.icons.SWAP_HORIZ
                icon_color = ft.colors.BLUE
                icon_bg = ft.colors.with_opacity(0.1, ft.colors.BLUE) if self.is_dark else ft.colors.BLUE_50
                amount_color = text_color
                amount_prefix = ""
                cat_name = "Virement"
                cat_bg = ft.colors.BLUE_GREY_100
                cat_text_col = ft.colors.BLUE_GREY_900
                
                edit_action = lambda e, t=t: self._edit_transfer_group(t)
                delete_action = lambda e, ids=t["ids"]: self._confirm_delete_group(ids)
                
            else:
                # STANDARD ROW
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
                
                edit_action = lambda e, t=t: self._edit_transaction(t)
                delete_action = lambda e, id=t["id"]: self._confirm_delete(id)

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
                        # Actions
                        ft.Container(
                            ft.PopupMenuButton(
                                icon=ft.icons.MORE_VERT,
                                items=[
                                    ft.PopupMenuItem(
                                        text="Modify", 
                                        icon=ft.icons.EDIT, 
                                        on_click=edit_action
                                    ),
                                    ft.PopupMenuItem(
                                        text="Delete", 
                                        icon=ft.icons.DELETE, 
                                        on_click=delete_action
                                    ),
                                ],
                                tooltip="Actions",
                            ),
                            width=50,
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
        
        # Banque / Épargne
        if "compte courant" in cat: return ft.colors.BLUE_300
        if "livret" in cat or "épargne" in cat: return ft.colors.YELLOW_300
        
        # Quotidien
        if "salaire" in cat: return ft.colors.TEAL_300
        if "course" in cat: return ft.colors.AMBER_300
        if "loyer" in cat: return ft.colors.RED_300
        if "restaurant" in cat: return ft.colors.ORANGE_300
        if "transport" in cat: return ft.colors.CYAN_300
        
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
                    ft.Container(width=50), # Spacer for actions column
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

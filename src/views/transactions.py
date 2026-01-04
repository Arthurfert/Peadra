"""
Vue Transactions pour Peadra.
Interface type tableur pour la saisie des transactions.
"""
import flet as ft
from typing import Callable, Optional
from datetime import datetime
from ..components.theme import PeadraTheme
from ..components.modals import TransactionModal
from ..database.db_manager import db


class TransactionsView:
    """Vue des transactions avec DataTable interactif."""
    
    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.selected_transaction_id: Optional[int] = None
        self.filter_type = "all"
        self.search_query = ""
        self._load_data()
    
    def _load_data(self):
        """Charge les données des transactions."""
        self.transactions = db.get_all_transactions()
        self.categories = db.get_all_categories()
        self.subcategories = db.get_all_subcategories()
    
    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
    
    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()
    
    def _on_add_transaction(self, e):
        """Ouvre le modal pour ajouter une transaction."""
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            subcategories=self.subcategories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
        )
        modal.show()
    
    def _on_edit_transaction(self, transaction: dict):
        """Ouvre le modal pour éditer une transaction."""
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            subcategories=self.subcategories,
            on_save=lambda data: self._update_transaction(transaction["id"], data),
            is_dark=self.is_dark,
        )
        modal.show(transaction)
    
    def _save_transaction(self, data: dict):
        """Enregistre une nouvelle transaction."""
        db.add_transaction(
            date=data["date"],
            description=data["description"],
            amount=data["amount"],
            transaction_type=data["transaction_type"],
            category_id=data.get("category_id"),
            subcategory_id=data.get("subcategory_id"),
            notes=data.get("notes"),
        )
        self._show_snackbar("Transaction ajoutée avec succès")
        self.on_data_change()
    
    def _update_transaction(self, transaction_id: int, data: dict):
        """Met à jour une transaction existante."""
        db.update_transaction(
            transaction_id,
            date=data["date"],
            description=data["description"],
            amount=data["amount"],
            transaction_type=data["transaction_type"],
            category_id=data.get("category_id"),
            subcategory_id=data.get("subcategory_id"),
            notes=data.get("notes"),
        )
        self._show_snackbar("Transaction mise à jour")
        self.on_data_change()
    
    def _on_delete_transaction(self, transaction_id: int):
        """Supprime une transaction après confirmation."""
        def confirm_delete(e):
            dialog.open = False
            self.page.update()
            db.delete_transaction(transaction_id)
            self._show_snackbar("Transaction supprimée")
            self.on_data_change()
        
        def cancel_delete(e):
            dialog.open = False
            self.page.update()
        
        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Confirmer la suppression"),
            content=ft.Text("Êtes-vous sûr de vouloir supprimer cette transaction ?"),
            actions=[
                ft.TextButton("Annuler", on_click=cancel_delete),
                ft.ElevatedButton(
                    "Supprimer",
                    bgcolor=PeadraTheme.ERROR,
                    color=ft.colors.WHITE,
                    on_click=confirm_delete,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        
        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()
    
    def _show_snackbar(self, message: str, success: bool = True):
        """Affiche une notification."""
        color = PeadraTheme.SUCCESS if success else PeadraTheme.ERROR
        snackbar = ft.SnackBar(
            content=ft.Text(message, color=ft.colors.WHITE),
            bgcolor=color,
            duration=2000,
        )
        self.page.overlay.append(snackbar)
        snackbar.open = True
        self.page.update()
    
    def _filter_transactions(self) -> list:
        """Filtre les transactions selon les critères."""
        filtered = self.transactions
        
        # Filtre par type
        if self.filter_type != "all":
            filtered = [t for t in filtered if t["transaction_type"] == self.filter_type]
        
        # Filtre par recherche
        if self.search_query:
            query = self.search_query.lower()
            filtered = [
                t for t in filtered
                if query in t["description"].lower()
                or (t.get("category_name") and query in t["category_name"].lower())
                or (t.get("notes") and query in t["notes"].lower())
            ]
        
        return filtered
    
    def _on_filter_change(self, e):
        """Gère le changement de filtre."""
        self.filter_type = e.control.value
        self.on_data_change()
    
    def _on_search_change(self, e):
        """Gère le changement de recherche."""
        self.search_query = e.control.value
        self.on_data_change()
    
    def _build_toolbar(self) -> ft.Container:
        """Construit la barre d'outils."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        return ft.Container(
            content=ft.Row(
                controls=[
                    # Barre de recherche
                    ft.TextField(
                        hint_text="Rechercher une transaction...",
                        prefix_icon=ft.icons.SEARCH,
                        width=300,
                        height=45,
                        border_radius=8,
                        on_change=self._on_search_change,
                        value=self.search_query,
                    ),
                    # Filtre par type
                    ft.Dropdown(
                        label="Type",
                        width=150,
                        value=self.filter_type,
                        options=[
                            ft.dropdown.Option("all", "Tous"),
                            ft.dropdown.Option("income", "Revenus"),
                            ft.dropdown.Option("expense", "Dépenses"),
                            ft.dropdown.Option("transfer", "Transferts"),
                        ],
                        on_change=self._on_filter_change,
                    ),
                    # Spacer
                    ft.Container(expand=True),
                    # Bouton ajouter
                    ft.ElevatedButton(
                        "Nouvelle transaction",
                        icon=ft.icons.ADD,
                        bgcolor=PeadraTheme.PRIMARY_MEDIUM,
                        color=ft.colors.WHITE,
                        height=45,
                        on_click=self._on_add_transaction,
                    ),
                ],
                alignment=ft.MainAxisAlignment.START,
                spacing=16,
            ),
            margin=ft.margin.only(bottom=20),
        )
    
    def _build_data_table(self) -> ft.Container:
        """Construit le DataTable des transactions."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        header_bg = "rgba(119, 141, 169, 0.1)"
        
        filtered_transactions = self._filter_transactions()
        
        # Colonnes
        columns = [
            ft.DataColumn(ft.Text("Date", weight=ft.FontWeight.BOLD, color=text_color)),
            ft.DataColumn(ft.Text("Description", weight=ft.FontWeight.BOLD, color=text_color)),
            ft.DataColumn(ft.Text("Catégorie", weight=ft.FontWeight.BOLD, color=text_color)),
            ft.DataColumn(ft.Text("Type", weight=ft.FontWeight.BOLD, color=text_color)),
            ft.DataColumn(
                ft.Text("Montant", weight=ft.FontWeight.BOLD, color=text_color),
                numeric=True,
            ),
            ft.DataColumn(ft.Text("Actions", weight=ft.FontWeight.BOLD, color=text_color)),
        ]
        
        # Lignes
        rows = []
        for idx, tx in enumerate(filtered_transactions):
            is_expense = tx["transaction_type"] == "expense"
            amount_color = PeadraTheme.ERROR if is_expense else PeadraTheme.SUCCESS
            amount_prefix = "-" if is_expense else "+"
            
            type_labels = {
                "income": ("Revenu", PeadraTheme.SUCCESS),
                "expense": ("Dépense", PeadraTheme.ERROR),
                "transfer": ("Transfert", PeadraTheme.INFO),
            }
            type_label, type_color = type_labels.get(tx["transaction_type"], ("", text_color))
            
            # Couleur de fond alternée
            row_color = "rgba(119, 141, 169, 0.05)" if idx % 2 == 0 else None
            
            row = ft.DataRow(
                cells=[
                    ft.DataCell(ft.Text(tx["date"], color=text_color)),
                    ft.DataCell(
                        ft.Column(
                            controls=[
                                ft.Text(
                                    tx["description"],
                                    weight=ft.FontWeight.W_500,
                                    color=text_color,
                                ),
                                ft.Text(
                                    tx.get("notes", "") or "",
                                    size=11,
                                    color=secondary_color,
                                    max_lines=1,
                                    overflow=ft.TextOverflow.ELLIPSIS,
                                ) if tx.get("notes") else ft.Container(),
                            ],
                            spacing=2,
                        )
                    ),
                    ft.DataCell(
                        ft.Text(
                            tx.get("category_name", "-"),
                            color=text_color,
                        )
                    ),
                    ft.DataCell(
                        ft.Container(
                            content=ft.Text(
                                type_label,
                                size=12,
                                color=ft.colors.WHITE,
                                weight=ft.FontWeight.W_500,
                            ),
                            bgcolor=type_color,
                            border_radius=4,
                            padding=ft.padding.symmetric(horizontal=8, vertical=4),
                        )
                    ),
                    ft.DataCell(
                        ft.Text(
                            f"{amount_prefix}{PeadraTheme.format_currency(tx['amount'])}",
                            weight=ft.FontWeight.BOLD,
                            color=amount_color,
                        )
                    ),
                    ft.DataCell(
                        ft.Row(
                            controls=[
                                ft.IconButton(
                                    icon=ft.icons.EDIT_OUTLINED,
                                    icon_size=18,
                                    tooltip="Modifier",
                                    on_click=lambda e, t=tx: self._on_edit_transaction(t),
                                ),
                                ft.IconButton(
                                    icon=ft.icons.DELETE_OUTLINE,
                                    icon_size=18,
                                    icon_color=PeadraTheme.ERROR,
                                    tooltip="Supprimer",
                                    on_click=lambda e, id=tx["id"]: self._on_delete_transaction(id),
                                ),
                            ],
                            spacing=0,
                        )
                    ),
                ],
                color=row_color,
            )
            rows.append(row)
        
        if not rows:
            return PeadraTheme.card(
                content=ft.Container(
                    content=ft.Column(
                        controls=[
                            ft.Icon(
                                ft.icons.RECEIPT_LONG_OUTLINED,
                                size=64,
                                color=secondary_color,
                            ),
                            ft.Text(
                                "Aucune transaction",
                                size=18,
                                color=secondary_color,
                            ),
                            ft.Text(
                                "Cliquez sur 'Nouvelle transaction' pour commencer",
                                size=14,
                                color=secondary_color,
                            ),
                        ],
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        spacing=12,
                    ),
                    padding=40,
                    alignment=ft.Alignment(0, 0),
                ),
                is_dark=self.is_dark,
            )
        
        data_table = ft.DataTable(
            columns=columns,
            rows=rows,
            border=ft.border.all(1, "rgba(119, 141, 169, 0.2)"),
            border_radius=12,
            vertical_lines=ft.BorderSide(1, "rgba(119, 141, 169, 0.1)"),
            horizontal_lines=ft.BorderSide(1, "rgba(119, 141, 169, 0.1)"),
            heading_row_color=header_bg,
            heading_row_height=50,
            data_row_min_height=55,
            data_row_max_height=70,
            column_spacing=20,
        )
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Text(
                                f"{len(filtered_transactions)} transaction(s)",
                                size=14,
                                color=secondary_color,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.END,
                    ),
                    ft.Container(
                        content=data_table,
                        expand=True,
                    ),
                ],
                spacing=12,
            ),
            is_dark=self.is_dark,
            padding=16,
        )
    
    def _build_summary_row(self) -> ft.Container:
        """Construit la ligne de résumé."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        filtered = self._filter_transactions()
        total_income = sum(t["amount"] for t in filtered if t["transaction_type"] == "income")
        total_expense = sum(t["amount"] for t in filtered if t["transaction_type"] == "expense")
        balance = total_income - total_expense
        
        return ft.Container(
            content=ft.Row(
                controls=[
                    PeadraTheme.stat_card(
                        title="Total Revenus",
                        value=PeadraTheme.format_currency(total_income),
                        icon=ft.icons.TRENDING_UP,
                        color=PeadraTheme.SUCCESS,
                        is_dark=self.is_dark,
                    ),
                    PeadraTheme.stat_card(
                        title="Total Dépenses",
                        value=PeadraTheme.format_currency(total_expense),
                        icon=ft.icons.TRENDING_DOWN,
                        color=PeadraTheme.ERROR,
                        is_dark=self.is_dark,
                    ),
                    PeadraTheme.stat_card(
                        title="Solde",
                        value=PeadraTheme.format_currency(balance),
                        icon=ft.icons.ACCOUNT_BALANCE_WALLET,
                        color=PeadraTheme.SUCCESS if balance >= 0 else PeadraTheme.ERROR,
                        is_dark=self.is_dark,
                    ),
                ],
                spacing=16,
                wrap=True,
            ),
            margin=ft.margin.only(bottom=20),
        )
    
    def build(self) -> ft.Container:
        """Construit la vue complète des transactions."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        return ft.Container(
            content=ft.Column(
                controls=[
                    # Titre
                    ft.Text(
                        "Transactions",
                        size=28,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=24, color="transparent"),
                    # Résumé
                    self._build_summary_row(),
                    # Barre d'outils
                    self._build_toolbar(),
                    # Table des données
                    ft.Container(
                        content=self._build_data_table(),
                        expand=True,
                    ),
                ],
                scroll=ft.ScrollMode.AUTO,
                expand=True,
            ),
            expand=True,
        )

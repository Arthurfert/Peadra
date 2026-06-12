"""
Vue Transactions pour Peadra.
Interface simplifiée : Liste des transactions et gestion des actifs.
"""

import flet as ft
import logging
from typing import Callable, List
from datetime import datetime
from ..components.theme import PeadraTheme
from ..components.modals import TransactionModal, TransactionDetailsModal
from ..database import db
from ..database.db_manager import CURRENCY_DATA, get_default_currency, get_currency_symbol, format_amount, format_amount_with_conversion, _SYMBOL_TO_CODE
from ..i18n import t, get_translator

logger = logging.getLogger(__name__)


class TransactionsView:
    """Vue des transactions simplifiée."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.transactions = []
        self.search_query = ""
        self.selected_subcategories = set()
        self.has_more = False
        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()

    def _load_data(self, append: bool = False, load_all: bool = False):
        """Charge les données."""
        self.categories = db.get_all_categories()
        raw = db.get_setting("currency", "EUR") or "EUR"
        self.currency = _SYMBOL_TO_CODE.get(raw, raw) if raw in _SYMBOL_TO_CODE or raw in CURRENCY_DATA else "EUR"

        offset = len(self.transactions) if append else 0

        limit_str = db.get_setting("transactions_display_limit", "30")
        try:
            default_limit = int(limit_str) if limit_str else 30
        except (ValueError, TypeError):
            default_limit = 30

        limit = default_limit if not load_all else None

        new_tx = db.get_all_transactions(
            limit=limit,
            offset=offset,
            search_query=self.search_query,
            category_ids=self.selected_subcategories,
        )

        if append:
            self.transactions.extend(new_tx)
        else:
            self.transactions = new_tx

        if load_all:
            self.has_more = False
        else:
            self.has_more = len(new_tx) == limit

    def _open_type_selector(self, e):
        """Ouvre le dialogue de sélection du type de transaction."""

        # Theme Colors
        expense_bg = PeadraTheme.expense_bg
        income_bg = PeadraTheme.income_bg
        transfer_bg = PeadraTheme.transfer_bg
        expense_icon_col = PeadraTheme.expense_icon
        income_icon_col = PeadraTheme.income_icon
        transfer_icon_col = PeadraTheme.transfer_icon
        text_col = PeadraTheme.text_secondary

        def close_dlg(e):
            dlg.open = False
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
            title=ft.Text(t("trans_add_transaction"), color=text_col),
            content=ft.Container(
                content=ft.Row(
                    [
                        create_option_card(
                            ft.Icons.CREDIT_CARD,
                            t("trans_expense"),
                            expense_icon_col,
                            expense_bg,
                            select_expense,
                        ),
                        create_option_card(
                            ft.Icons.MONETIZATION_ON,
                            t("trans_income"),
                            income_icon_col,
                            income_bg,
                            select_income,
                        ),
                        create_option_card(
                            ft.Icons.SWAP_HORIZ,
                            t("trans_transfer"),
                            transfer_icon_col,
                            transfer_bg,
                            select_transfer,
                        ),
                    ],
                    spacing=15,
                    vertical_alignment=ft.CrossAxisAlignment.STRETCH,
                ),
                width=500,
                height=140,
                padding=10,
            ),
            actions=[ft.TextButton(t("btn_cancel"), on_click=close_dlg)],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _open_transaction_modal(self, type_: str):
        """Ouvre le modal de transaction."""
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            transaction_type=type_,
        )
        modal.show()

    def _open_filter_dialog(self, e):
        """Ouvre le dialogue de filtrage par catégories."""

        selected = set(self.selected_subcategories)
        checkboxes = []

        # Sort categories by name
        sorted_cats = sorted(self.categories, key=lambda x: x["name"])

        for cast in sorted_cats:
            cat_id = str(cast["id"])
            checkboxes.append(
                ft.Checkbox(label=cast["name"], value=(cat_id in selected), data=cat_id)
            )

        def close_dlg(e):
            dlg.open = False
            self.page.update()

        def apply_filter(e):
            self.selected_subcategories = {c.data for c in checkboxes if c.value}
            close_dlg(e)
            self._load_data(append=False)
            if hasattr(self, "content_column") and hasattr(self, "table_header"):
                new_controls: List[ft.Control] = [self.table_header]
                new_controls.extend(self._generate_rows())
                self.content_column.controls = new_controls
                self.content_column.update()

        def clear_filter(e):
            for c in checkboxes:
                c.value = False
            dlg.update()

        dlg = ft.AlertDialog(
            title=ft.Text(t("trans_filter_categories"), color=PeadraTheme.text_secondary),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.TextButton(t("btn_deselect_all"), on_click=clear_filter),
                        ft.Column(checkboxes, scroll=ft.ScrollMode.AUTO, expand=True),
                    ],
                ),
                width=300,
                height=400,
            ),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=close_dlg),
                ft.ElevatedButton(
                    t("btn_apply_filters"),
                    on_click=apply_filter,
                    bgcolor=PeadraTheme.accent,
                    color=ft.Colors.WHITE,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _save_transaction(self, data: dict):
        """Enregistre ou met à jour la transaction."""

        if data.get("is_recurring"):
            if data.get("id"):
                # We are editing an existing transaction and making it recurring
                # Calculate the next date so we don't duplicate the current one
                current_date = datetime.strptime(data["date"], "%Y-%m-%d").date()
                next_date = db._calculate_next_date(
                    current_date, data["frequency"], data["interval"]
                )

                db.add_recurring_transaction(
                    description=data["description"],
                    amount=data["amount"],
                    transaction_type=data["transaction_type"],
                    frequency=data["frequency"],
                    start_date=data["date"],
                    interval=data["interval"],
                    category_id=data.get("category_id"),
                    end_date=data.get("end_date"),
                    next_due_date=next_date.strftime("%Y-%m-%d"),
                )
                db.process_recurring_transactions()
                # Do not return here, we still need to update the existing transaction
            else:
                db.add_recurring_transaction(
                    description=data["description"],
                    amount=data["amount"],
                    transaction_type=data["transaction_type"],
                    frequency=data["frequency"],
                    start_date=data["date"],
                    interval=data["interval"],
                    category_id=data.get("category_id"),
                    end_date=data.get("end_date"),
                )
                # Process immediately so user sees it if it starts today
                db.process_recurring_transactions()

                logger.info(
                    "Recurring transaction added: desc='%s' amount=%s freq=%s",
                    data["description"],
                    data["amount"],
                    data["frequency"],
                )
                snack = ft.SnackBar(ft.Text(t("msg_recurring_added")))
                self.page.overlay.append(snack)
                snack.open = True
                self.on_data_change()
                return

        if data.get("id"):
            # Mise à jour
            if data["transaction_type"] == "transfer" and data.get("other_id"):
                # Update both sides of transfer
                # 1. Expense (Source)
                db.update_transaction(
                    data["id"],
                    date=data["date"],
                    description=f"{t('trans_transfer_to')} {data.get('dest_name', t('trans_account_default'))}",
                    amount=data["amount"],
                    category_id=data.get("source_id"),
                    notes=data.get("notes"),
                )
                # 2. Income (Dest)
                db.update_transaction(
                    data["other_id"],
                    date=data["date"],
                    description=f"{t('trans_transfer_from')} {data.get('source_name', t('trans_account_default'))}",
                    amount=data["amount"],
                    category_id=data.get("dest_id"),
                    notes=data.get("notes"),
                )
                logger.info(
                    "Transaction updated: id=%s amount=%s desc='%s'",
                    data["id"],
                    data["amount"],
                    data["description"],
                )
                msg = t("msg_transfer_modified")
            else:
                db.update_transaction(
                    data["id"],
                    date=data["date"],
                    description=data["description"],
                    amount=data["amount"],
                    transaction_type=data["transaction_type"],
                    category_id=data.get("category_id"),
                    notes=data.get("notes"),
                )
                logger.info(
                    "Transaction updated: id=%s amount=%s desc='%s'",
                    data["id"],
                    data["amount"],
                    data["description"],
                )
                msg = t("msg_transaction_modified")

        elif data["transaction_type"] == "transfer":
            # Création - Transfert (2 transactions)
            tx_currency = data.get("currency") or get_default_currency()

            # 1. Expense from source
            db.add_transaction(
                date=data["date"],
                description=f"{t('trans_transfer_to')} {data.get('dest_name', t('trans_account_default'))}",
                amount=data["amount"],
                transaction_type="expense",
                category_id=data.get("source_id"),
                notes=data.get("notes"),
                currency=tx_currency,
            )

            # 2. Income to dest
            db.add_transaction(
                date=data["date"],
                description=f"{t('trans_transfer_from')} {data.get('source_name', t('trans_account_default'))}",
                amount=data["amount"],
                transaction_type="income",
                category_id=data.get("dest_id"),
                notes=data.get("notes"),
                currency=tx_currency,
            )

            logger.info(
                "Transfer created: amount=%s from source=%s to dest=%s",
                data["amount"],
                data.get("source_id"),
                data.get("dest_id"),
            )
            msg = t("msg_transfer_completed")

        else:
            # Création - Standard
            db.add_transaction(
                date=data["date"],
                description=data["description"],
                amount=data["amount"],
                transaction_type=data["transaction_type"],
                category_id=data.get("category_id"),
                notes=data.get("notes"),
                currency=data.get("currency"),
            )
            logger.info(
                "Transaction added: type=%s amount=%s desc='%s'",
                data["transaction_type"],
                data["amount"],
                data["description"],
            )
            msg = t("msg_transaction_added")

        snack = ft.SnackBar(ft.Text(msg))
        self.page.overlay.append(snack)
        snack.open = True
        self.on_data_change()

    def _edit_transaction(self, transaction):
        """Ouvre le modal d'édition."""
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            transaction_type=transaction["transaction_type"],
        )
        modal.show(transaction)

    def _confirm_delete(self, transaction_id):
        """Demande confirmation avant suppression."""

        def close_dlg(e):
            dlg.open = False
            self.page.update()

        def delete(e):
            db.delete_transaction(transaction_id)
            logger.info("Transaction deleted: id=%s", transaction_id)
            close_dlg(e)
            self.on_data_change()
            snack = ft.SnackBar(ft.Text(t("msg_transaction_deleted")))
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

        dlg = ft.AlertDialog(
            title=ft.Text(t("msg_confirm_delete"), color=PeadraTheme.text_secondary),
            content=ft.Text(t("trans_delete_confirm"), color=PeadraTheme.text_secondary),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=close_dlg),
                ft.TextButton(
                    t("btn_delete"),
                    on_click=delete,
                    style=ft.ButtonStyle(color=PeadraTheme.delete_color),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _group_transactions(self, transactions):
        transfer_to_prefixes = (f"{t('trans_transfer_to')} ", "Transfer to ")
        transfer_from_prefixes = (f"{t('trans_transfer_from')} ", "Transfer from ")

        def starts_with_any(text: str, prefixes: tuple[str, ...]) -> bool:
            return any(text.startswith(prefix) for prefix in prefixes)

        def strip_known_prefix(text: str, prefixes: tuple[str, ...]) -> str:
            for prefix in prefixes:
                if text.startswith(prefix):
                    return text[len(prefix) :]
            return text

        grouped = []
        i = 0
        while i < len(transactions):
            t1 = transactions[i]

            # Transfer signatures
            desc1 = t1["description"] or ""
            is_transfer_candidate = starts_with_any(
                desc1, transfer_to_prefixes
            ) or starts_with_any(desc1, transfer_from_prefixes)

            if is_transfer_candidate and i + 1 < len(transactions):
                t2 = transactions[i + 1]
                desc2 = t2["description"] or ""

                # Check match: same amount, date, different type
                if (
                    t1["amount"] == t2["amount"]
                    and t1["date"] == t2["date"]
                    and t1["transaction_type"] != t2["transaction_type"]
                ):
                    match = False
                    source = None
                    dest = None
                    source_id = None
                    dest_id = None
                    id_expense = None
                    id_income = None

                    # Determine which is which
                    if t1["transaction_type"] == "expense" and starts_with_any(
                        desc1, transfer_to_prefixes
                    ):
                        if t2["transaction_type"] == "income" and starts_with_any(
                            desc2, transfer_from_prefixes
                        ):
                            dest = strip_known_prefix(desc1, transfer_to_prefixes)
                            source = strip_known_prefix(desc2, transfer_from_prefixes)
                            source_id = t1["category_id"]
                            dest_id = t2["category_id"]
                            id_expense = t1["id"]
                            id_income = t2["id"]
                            match = True
                    elif t1["transaction_type"] == "income" and starts_with_any(
                        desc1, transfer_from_prefixes
                    ):
                        if t2["transaction_type"] == "expense" and starts_with_any(
                            desc2, transfer_to_prefixes
                        ):
                            source = strip_known_prefix(desc1, transfer_from_prefixes)
                            dest = strip_known_prefix(desc2, transfer_to_prefixes)
                            source_id = t2["category_id"]
                            dest_id = t1["category_id"]
                            id_expense = t2["id"]
                            id_income = t1["id"]
                            match = True

                    if match:
                        combined = t1.copy()
                        combined["ids"] = [t1["id"], t2["id"]]  # Both IDs for deletion
                        combined["id"] = (
                            id_expense  # Use expense ID as primary for editing
                        )
                        combined["other_id"] = id_income
                        combined["description"] = t("trans_transfer_from_to").format(
                            source=source, dest=dest
                        )
                        combined["transaction_type"] = "transfer_group"
                        combined["category_name"] = t("trans_category_transfer")
                        combined["category_id"] = None
                        combined["category_color"] = ft.Colors.BLUE_GREY_100
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
            "description": t[
                "description"
            ],  # Not really used in modal for transfer pre-fill strictly but good to have
            "amount": t["amount"],
            "transaction_type": "transfer",
            "notes": t.get("notes"),
            "source_id": t["source_id"],
            "dest_id": t["dest_id"],
        }
        modal = TransactionModal(
            page=self.page,
            categories=self.categories,
            on_save=self._save_transaction,
            is_dark=self.is_dark,
            transaction_type="transfer",
        )
        modal.show(data)

    def _confirm_delete_group(self, ids):
        def close_dlg(e):
            dlg.open = False
            self.page.update()

        def delete(e):
            for tid in ids:
                db.delete_transaction(tid)
            logger.info("Transfer group deleted: ids=%s", ids)
            close_dlg(e)
            self.on_data_change()
            snack = ft.SnackBar(ft.Text(t("msg_transfer_deleted")))
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()

        dlg = ft.AlertDialog(
            title=ft.Text(t("msg_confirm_delete"), color=PeadraTheme.text_secondary),
            content=ft.Text(t("trans_delete_transfer_confirm"), color=PeadraTheme.text_secondary),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=close_dlg),
                ft.TextButton(
                    t("btn_delete"),
                    on_click=delete,
                    style=ft.ButtonStyle(color=PeadraTheme.delete_color),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.overlay.append(dlg)
        dlg.open = True
        self.page.update()

    def _open_transaction_details(self, t):
        """Ouvre le modal de détails de transaction."""
        is_group = t.get("transaction_type") == "transfer_group"

        if is_group:
            on_edit = lambda: self._edit_transfer_group(t)
            on_delete = lambda: self._confirm_delete_group(t["ids"])
        else:
            on_edit = lambda: self._edit_transaction(t)
            on_delete = lambda: self._confirm_delete(t["id"])

        modal = TransactionDetailsModal(self.page, t, on_edit, on_delete)
        modal.show()

    def _format_display_date(self, raw_date: str) -> str:
        """Formate une date ISO (YYYY-MM-DD) selon la langue active."""
        try:
            date_obj = datetime.strptime(raw_date, "%Y-%m-%d")
        except ValueError:
            return raw_date

        month_keys = {
            1: "month_january",
            2: "month_february",
            3: "month_march",
            4: "month_april",
            5: "month_may",
            6: "month_june",
            7: "month_july",
            8: "month_august",
            9: "month_september",
            10: "month_october",
            11: "month_november",
            12: "month_december",
        }
        month_name = t(month_keys[date_obj.month])

        if get_translator().get_language() == "fr":
            return f"{date_obj.day:02d} {month_name} {date_obj.year}"
        return f"{month_name} {date_obj.day:02d}, {date_obj.year}"

    def _generate_rows(self):
        text_color = PeadraTheme.text
        rows = []

        display_transactions = self._group_transactions(self.transactions)

        for transaction in display_transactions:
            is_group = transaction.get("transaction_type") == "transfer_group"

            if is_group:
                # TRANSFER ROW
                icon = ft.Icons.SWAP_HORIZ
                icon_color = PeadraTheme.transfer_color
                icon_bg = PeadraTheme.transfer_bg
                amount_color = text_color
                amount_prefix = ""
                cat_name = t("trans_category_transfer")
                cat_bg = ft.Colors.BLUE_GREY_100
                cat_text_col = ft.Colors.BLUE_GREY_900

                edit_action = lambda e, trans=transaction: self._edit_transfer_group(
                    trans
                )
                delete_action = lambda e, ids=transaction[
                    "ids"
                ]: self._confirm_delete_group(ids)

            else:
                # STANDARD ROW
                is_income = transaction["transaction_type"] == "income"
                is_expense = transaction["transaction_type"] == "expense"
                amount_color = (
                    PeadraTheme.success
                    if is_income
                    else PeadraTheme.error if is_expense else text_color
                )
                amount_prefix = "+" if is_income else "-" if is_expense else ""

                icon = ft.Icons.NORTH_EAST if is_income else ft.Icons.SOUTH_WEST
                icon_color = PeadraTheme.success if is_income else PeadraTheme.error
                icon_bg = PeadraTheme.income_bg if is_income else PeadraTheme.expense_bg

                cat_name = transaction.get("category_name", "") or ""
                cat_bg = transaction.get("category_color") or ft.Colors.GREY_300
                cat_text_col = ft.Colors.WHITE

                edit_action = lambda e, trans=transaction: self._edit_transaction(trans)
                delete_action = lambda e, id=transaction["id"]: self._confirm_delete(id)

            date_str = self._format_display_date(transaction["date"])

            tx_currency = transaction.get("category_currency") or transaction.get("currency") or get_default_currency()
            conv_display = f"{amount_prefix}{format_amount_with_conversion(transaction['amount'], tx_currency, self.currency)}"

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
                                        transaction["description"],
                                        weight=ft.FontWeight.W_500,
                                        color=text_color,
                                    ),
                                ],
                                spacing=12,
                            ),
                            expand=4,
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
                            alignment=ft.Alignment.CENTER_LEFT,
                        ),
                        # Date
                        ft.Container(ft.Text(date_str, color=text_color), expand=2),
                        # Amount
                        ft.Container(
                            ft.Text(
                                conv_display,
                                weight=ft.FontWeight.BOLD,
                                color=amount_color,
                                text_align=ft.TextAlign.RIGHT,
                                size=12,
                            ),
                            expand=1,
                            alignment=ft.Alignment.CENTER_RIGHT,
                        ),
                        # Actions
                        ft.Container(
                            ft.PopupMenuButton(
                                icon=ft.Icons.MORE_VERT,
                                items=[
                                    ft.PopupMenuItem(
                                        content=ft.Text(t("btn_modify")),
                                        icon=ft.Icons.EDIT,
                                        on_click=edit_action,
                                    ),
                                    ft.PopupMenuItem(
                                        content=ft.Text(t("btn_delete")),
                                        icon=ft.Icons.DELETE,
                                        on_click=delete_action,
                                    ),
                                ],
                                tooltip=t("tooltip_actions"),
                            ),
                            width=50,
                            alignment=ft.Alignment.CENTER_RIGHT,
                        ),
                    ]
                ),
                padding=ft.padding.symmetric(horizontal=16, vertical=16),
                on_click=lambda e, trans=transaction: self._open_transaction_details(
                    trans
                ),
                border=ft.border.only(
                    bottom=ft.border.BorderSide(1, PeadraTheme.divider)
                ),
            )
            rows.append(row)

        if not rows:
            rows.append(
                ft.Container(
                    content=ft.Text(t("trans_no_recent"), color=PeadraTheme.placeholder_color),
                    padding=20,
                    alignment=ft.Alignment.CENTER,
                )
            )
        elif getattr(self, "has_more", False):

            def update_view():
                if hasattr(self, "content_column") and hasattr(self, "table_header"):
                    new_controls: List[ft.Control] = [self.table_header]
                    new_controls.extend(self._generate_rows())
                    self.content_column.controls = new_controls
                    self.content_column.update()

            def load_more(e):
                self._load_data(append=True)
                update_view()

            def load_all(e):
                self._load_data(append=True, load_all=True)
                update_view()

            rows.append(
                ft.Container(
                    content=ft.Row(
                        [
                            ft.TextButton(t("btn_load_more"), on_click=load_more),
                            ft.TextButton(t("btn_load_all"), on_click=load_all),
                        ],
                        alignment=ft.MainAxisAlignment.CENTER,
                        spacing=20,
                    ),
                    padding=20,
                    alignment=ft.Alignment.CENTER,
                )
            )

        return rows

    def _on_search_change(self, e):
        """Gère la recherche."""
        self.search_query = e.control.value
        self._load_data(append=False)

        if hasattr(self, "content_column") and hasattr(self, "table_header"):
            new_controls: List[ft.Control] = [self.table_header]
            new_controls.extend(self._generate_rows())
            self.content_column.controls = new_controls
            self.content_column.update()

    def build(self) -> ft.Container:
        text_color = PeadraTheme.text
        surface_color = PeadraTheme.surface

        # Header
        header = ft.Row(
            [
                ft.Column(
                    [
                        ft.Text(
                            t("trans_title"),
                            size=32,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                        ft.Text(
                            t("trans_subtitle"),
                            size=16,
                            color=PeadraTheme.placeholder_color,
                        ),
                    ]
                ),
                ft.ElevatedButton(
                    t("trans_add_transaction"),
                    icon=ft.Icons.ADD,
                    bgcolor=PeadraTheme.accent,
                    color=ft.Colors.WHITE,
                    on_click=self._open_type_selector,
                ),
            ],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        # Search Bar
        search_bar = ft.Row(
            [
                ft.TextField(
                    hint_text=t("trans_search_placeholder"),
                    value=self.search_query,
                    prefix_icon=ft.Icons.SEARCH,
                    border_radius=8,
                    bgcolor=ft.Colors.with_opacity(0.05, text_color),
                    border_color=ft.Colors.TRANSPARENT,
                    expand=True,
                    on_change=self._on_search_change,
                ),
                ft.Container(width=10),
                ft.OutlinedButton(
                    t("btn_filter"),
                    icon=ft.Icons.FILTER_LIST,
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
                            t("trans_description"),
                            weight=ft.FontWeight.BOLD,
                            color=PeadraTheme.placeholder_color,
                        ),
                        expand=4,
                    ),
                    ft.Container(
                        ft.Text(
                            t("trans_category"),
                            weight=ft.FontWeight.BOLD,
                            color=PeadraTheme.placeholder_color,
                        ),
                        expand=2,
                        alignment=ft.Alignment.CENTER_LEFT,
                    ),
                    ft.Container(
                        ft.Text(
                            t("trans_date"),
                            weight=ft.FontWeight.BOLD,
                            color=PeadraTheme.placeholder_color,
                        ),
                        expand=2,
                    ),
                    ft.Container(
                        ft.Text(
                            t("trans_amount"),
                            weight=ft.FontWeight.BOLD,
                            color=PeadraTheme.placeholder_color,
                            text_align=ft.TextAlign.RIGHT,
                        ),
                        expand=1,
                        alignment=ft.Alignment.CENTER_RIGHT,
                    ),
                    ft.Container(width=50),  # Spacer for actions column
                ],
            ),
            padding=ft.padding.symmetric(horizontal=16, vertical=12),
            border=ft.border.only(bottom=ft.border.BorderSide(1, PeadraTheme.divider)),
        )

        rows = self._generate_rows()

        # Explicitly type the list to satisfy Pylance invariance check
        col_controls: List[ft.Control] = [self.table_header]
        col_controls.extend(rows)

        self.content_column = ft.Column(
            col_controls, scroll=ft.ScrollMode.AUTO, spacing=0
        )

        list_container = ft.Container(
            content=self.content_column,
            bgcolor=surface_color,
            border_radius=12,
            border=(
                ft.border.all(1, PeadraTheme.divider)
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
            padding=ft.padding.only(left=30, right=30, top=30, bottom=8),
            expand=True,
        )

"""
Modal de saisie rapide pour les transactions.
"""

import flet as ft
from datetime import datetime
from typing import Callable, List, Dict, Any, Optional
from .theme import PeadraTheme


class TransactionModal:
    """Modal pour ajouter/éditer une transaction."""

    def __init__(
        self,
        page: ft.Page,
        categories: List[Dict[str, Any]],
        on_save: Callable,
        is_dark: bool = True,
        transaction_type: str = "expense",
    ):
        self.page = page
        self.categories = categories
        self.on_save = on_save
        self.is_dark = is_dark
        self.transaction_type = transaction_type
        self.dialog = None
        self.editing_id = None
        self.other_id = None
        self.controls_list = []
        # Don't build controls in init, wait for show() or build now but clear later
        # We will build in show() to ensure fresh state

    def _build_controls(self):
        """Construit les contrôles du formulaire."""
        self.controls_list = []  # Clear previous controls

        # Date picker
        self.date_picker = ft.TextField(
            label="Date",
            value=datetime.now().strftime("%Y-%m-%d"),
            read_only=True,
            width=200,
            suffix=ft.IconButton(
                icon=ft.Icons.CALENDAR_TODAY,
                on_click=self._open_date_picker,
            ),
        )

        # Description
        hint = "Ex: Groceries, Rent..."
        if self.transaction_type == "income":
            hint = "Ex: Salary, Social Security..."

        self.description_field = ft.TextField(
            label="Description",
            hint_text=hint,
            width=350,
            autofocus=True,
        )

        # Amount
        self.amount_field = ft.TextField(
            label="Amount (€)",
            hint_text="0.00",
            width=150,
            keyboard_type=ft.KeyboardType.NUMBER,
            input_filter=ft.InputFilter(
                regex_string=r"^[0-9]*\.?[0-9]*$",
                allow=True,
            ),
        )

        # Recurring
        self.recurring_interval = ft.TextField(
            label="Every",
            value="1",
            width=80,
            keyboard_type=ft.KeyboardType.NUMBER,
            text_align=ft.TextAlign.RIGHT,
        )

        self.recurring_freq = ft.Dropdown(
            label="Frequency",
            width=200,
            options=[
                ft.dropdown.Option("daily", "Days"),
                ft.dropdown.Option("weekly", "Weeks"),
                ft.dropdown.Option("monthly", "Months"),
                ft.dropdown.Option("yearly", "Years"),
            ],
            value="monthly",
        )

        self.recurring_end_date = ft.TextField(
            label="End Date (Optional)",
            read_only=True,
            width=200,
            suffix=ft.IconButton(
                icon=ft.Icons.CALENDAR_TODAY,
                on_click=lambda e: self._open_date_picker_generic(
                    e, self.recurring_end_date
                ),
            ),
        )

        self.recurring_container = ft.Column(
            [
                ft.Row([self.recurring_interval, self.recurring_freq]),
                self.recurring_end_date,
            ],
            visible=False,
        )

        self.recurring_switch = ft.Switch(
            label="Recurring Transaction",
            value=False,
            on_change=lambda e: setattr(
                self.recurring_container, "visible", e.control.value
            )
            or self.recurring_container.update(),
        )

        # Dropdowns Selection logic

        # Filter categories (formerly subcategories)
        sorted_cats = sorted(self.categories, key=lambda x: x["name"])
        options = [ft.dropdown.Option(str(c["id"]), c["name"]) for c in sorted_cats]

        # Use explicitly typed list or append to empty list to avoid type inference issues
        self.controls_list: List[ft.Control] = [
            self.date_picker,
        ]

        # Description (only for non-transfer)
        if self.transaction_type != "transfer":
            self.controls_list.append(self.description_field)

        self.controls_list.append(self.amount_field)

        if self.transaction_type == "transfer":
            # Two dropdowns: Source and Dest
            self.source_dropdown = ft.Dropdown(
                label="Account Debited (From)",
                width=350,
                options=options,
            )
            self.dest_dropdown = ft.Dropdown(
                label="Account Credited (To)",
                width=350,
                options=options,
            )
            # Pre-select if possible
            if options:
                self.source_dropdown.value = options[0].key
                if len(options) > 1:
                    self.dest_dropdown.value = options[1].key
                else:
                    self.dest_dropdown.value = options[0].key

            self.controls_list.extend([self.source_dropdown, self.dest_dropdown])

        else:
            # Single dropdown
            label = "Account / Category"
            self.category_dropdown = ft.Dropdown(
                label=label,
                width=350,
                options=options,
            )
            if options:
                self.category_dropdown.value = options[0].key

            self.controls_list.append(self.category_dropdown)

        # Notes
        self.notes_field = ft.TextField(
            label="Notes (optional)",
            hint_text="Additional information...",
            width=350,
            multiline=True,
            min_lines=2,
            max_lines=4,
        )
        self.controls_list.append(self.notes_field)

        # Only add recurring option for new transactions (not editing)
        if hasattr(self, "recurring_switch") and not self.editing_id:
            self.controls_list.append(ft.Divider())
            self.controls_list.append(self.recurring_switch)
            self.controls_list.append(self.recurring_container)

    def _open_date_picker(self, e):
        """Ouvre le sélecteur de date principal."""
        self._open_date_picker_generic(e, self.date_picker)

    def _open_date_picker_generic(self, e, field):
        """Ouvre un sélecteur de date pour un champ donné."""
        d = datetime.now()
        if field.value:
            try:
                d = datetime.strptime(field.value, "%Y-%m-%d")
            except ValueError:
                pass

        def on_change(e):
            if e.control.value:
                field.value = e.control.value.strftime("%Y-%m-%d")
                field.update()

        date_picker = ft.DatePicker(
            first_date=datetime(2000, 1, 1),
            last_date=datetime(2100, 12, 31),
            value=d,
            on_change=on_change,
        )

        self.page.overlay.append(date_picker)
        date_picker.open = True
        self.page.update()

    def _validate_form(self) -> bool:
        """Valide le formulaire."""
        errors = []

        if self.transaction_type != "transfer":
            if (
                not self.description_field.value
                or not self.description_field.value.strip()
            ):
                errors.append("Description is required")
                self.description_field.error = "Required"
            else:
                self.description_field.error = None

        if not self.amount_field.value:
            errors.append("Amount is required")
            self.amount_field.error = "Required"
        else:
            try:
                amount = float(self.amount_field.value)
                if amount <= 0:
                    errors.append("Amount must be positive")
                    self.amount_field.error = "Must be positive"
                else:
                    self.amount_field.error = None
            except ValueError:
                errors.append("Invalid amount")
                self.amount_field.error = "Invalid amount"

        if self.transaction_type == "transfer":
            if self.source_dropdown.value == self.dest_dropdown.value:
                errors.append("Identical accounts")
                self.dest_dropdown.error_text = "Identical accounts"
            else:
                self.dest_dropdown.error_text = None

        self.page.update()
        return len(errors) == 0

    def _on_save_click(self, e):
        """Gère le clic sur le bouton Enregistrer."""
        if not self._validate_form():
            return

        description = self.description_field.value or ""
        if self.transaction_type == "transfer":
            description = "Transfer"  # Placeholder, will be overwritten
        amount_str = self.amount_field.value or "0"

        transaction_data = {
            "date": self.date_picker.value,
            "description": description.strip(),
            "amount": float(amount_str),
            "transaction_type": self.transaction_type,
            "category_id": None,
            "notes": self.notes_field.value.strip() if self.notes_field.value else None,
        }

        # Add recurring data if enabled
        if hasattr(self, "recurring_switch") and self.recurring_switch.value:
            transaction_data.update(
                {
                    "is_recurring": True,
                    "frequency": self.recurring_freq.value,
                    "interval": int(self.recurring_interval.value or 1),
                    "end_date": self.recurring_end_date.value
                    if self.recurring_end_date.value
                    else None,
                }
            )

        if self.transaction_type == "transfer":
            source_val = self.source_dropdown.value
            dest_val = self.dest_dropdown.value
            if source_val:
                transaction_data["source_id"] = int(source_val)
                # Find names for helper descriptions
                src_name = next(
                    (
                        o.text
                        for o in self.source_dropdown.options
                        if o.key == source_val
                    ),
                    "",
                )
                transaction_data["source_name"] = src_name
            if dest_val:
                transaction_data["dest_id"] = int(dest_val)
                dest_name = next(
                    (o.text for o in self.dest_dropdown.options if o.key == dest_val),
                    "",
                )
                transaction_data["dest_name"] = dest_name
        else:
            cat_val = self.category_dropdown.value
            transaction_data["category_id"] = int(cat_val) if cat_val else None

        if self.editing_id:
            transaction_data["id"] = self.editing_id
        if self.other_id:
            transaction_data["other_id"] = self.other_id

        self.close()

        if self.on_save:
            self.on_save(transaction_data)

    def _on_cancel_click(self, e):
        """Gère le clic sur le bouton Annuler."""
        self.close()

    def show(self, transaction_data: Optional[Dict[str, Any]] = None):
        """Affiche le modal."""
        self.editing_id = None

        if transaction_data:
            self.transaction_type = transaction_data.get(
                "transaction_type", self.transaction_type
            )
            self.editing_id = transaction_data.get("id")
            self.other_id = transaction_data.get("other_id")

        self._build_controls()

        if transaction_data:
            self.date_picker.value = transaction_data.get(
                "date", datetime.now().strftime("%Y-%m-%d")
            )
            self.description_field.value = transaction_data.get("description", "")
            self.amount_field.value = str(transaction_data.get("amount", ""))
            self.notes_field.value = transaction_data.get("notes", "")

            if self.transaction_type != "transfer" and transaction_data.get(
                "category_id"
            ):
                self.category_dropdown.value = str(transaction_data["category_id"])

            if self.transaction_type == "transfer":
                if transaction_data.get("source_id"):
                    self.source_dropdown.value = str(transaction_data["source_id"])
                if transaction_data.get("dest_id"):
                    self.dest_dropdown.value = str(transaction_data["dest_id"])

        type_map = {
            "income": "New Income",
            "expense": "New Expense",
            "transfer": "New Transfer",
        }
        title = type_map.get(self.transaction_type, "New Transaction")
        if transaction_data:
            title = "Edit Transaction"

        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(title, weight=ft.FontWeight.BOLD),
            content=ft.Container(
                content=ft.Column(
                    controls=self.controls_list,
                    spacing=16,
                    tight=True,
                ),
                width=500,
                padding=ft.padding.only(top=10),
            ),
            actions=[
                ft.TextButton("Cancel", on_click=self._on_cancel_click),
                ft.ElevatedButton(
                    "Save",
                    icon=ft.Icons.SAVE,
                    on_click=self._on_save_click,
                    bgcolor=PeadraTheme.PRIMARY_MEDIUM,
                    color=ft.Colors.WHITE,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        self.page.overlay.append(self.dialog)
        self.dialog.open = True
        self.page.update()

    def close(self):
        """Ferme le modal."""
        if self.dialog:
            self.dialog.open = False
            self.page.update()


class TransactionDetailsModal:
    """Modal pour afficher les détails d'une transaction."""

    def __init__(
        self,
        page: ft.Page,
        transaction: Dict[str, Any],
        on_edit: Callable,
        on_delete: Callable,
    ):
        self.page = page
        self.transaction = transaction
        self.on_edit = on_edit
        self.on_delete = on_delete
        self.dialog = None

    def show(self):
        """Affiche le modal."""
        t = self.transaction

        # Format date
        try:
            date_obj = datetime.strptime(t["date"], "%Y-%m-%d")
            date_str = date_obj.strftime("%d %B %Y")
        except ValueError:
            date_str = t["date"]

        # Determine colors and icon
        is_income = t["transaction_type"] == "income"
        is_expense = t["transaction_type"] == "expense"
        is_transfer = "transfer" in t["transaction_type"]

        if is_income:
            color = ft.Colors.GREEN
            icon = ft.Icons.ARROW_DOWNWARD
            amount_prefix = "+"
        elif is_expense:
            color = ft.Colors.RED
            icon = ft.Icons.ARROW_UPWARD
            amount_prefix = "-"
            # Fix display for expense to be positive value with - sign if desired,
            # currently amount is stored positive usually.
            amount_prefix = "- "
        else:  # Transfer
            color = ft.Colors.BLUE
            icon = ft.Icons.SWAP_HORIZ
            amount_prefix = ""

        # Amount formatting
        amount_txt = f"{amount_prefix}€{t['amount']:,.2f}"

        # Category info
        full_category = t.get("category_name") or "Uncategorized"

        # Content controls
        content_controls = [
            ft.Container(
                content=ft.Column(
                    controls=[
                        ft.Icon(icon, size=40, color=color),
                        ft.Text(
                            amount_txt, size=30, weight=ft.FontWeight.BOLD, color=color
                        ),
                        ft.Text(date_str, size=14, color=ft.Colors.GREY),
                    ],
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                alignment=ft.Alignment(0, 0),
                padding=ft.padding.only(bottom=20),
            ),
            ft.Divider(),
            ft.ListTile(
                leading=ft.Icon(ft.Icons.DESCRIPTION),
                title=ft.Text("Description", size=12, color=ft.Colors.GREY),
                subtitle=ft.Text(t["description"], size=16, weight=ft.FontWeight.W_500),
            ),
            ft.ListTile(
                leading=ft.Icon(ft.Icons.CATEGORY),
                title=ft.Text("Category", size=12, color=ft.Colors.GREY),
                subtitle=ft.Text(full_category, size=16),
            ),
        ]

        # Add Notes if present
        if t.get("notes"):
            content_controls.append(
                ft.ListTile(
                    leading=ft.Icon(ft.Icons.NOTE),
                    title=ft.Text("Notes", size=12, color=ft.Colors.GREY),
                    subtitle=ft.Text(t["notes"], size=16),
                )
            )

        self.dialog = ft.AlertDialog(
            title=ft.Text("Transaction Details"),
            content=ft.Container(
                content=ft.Column(
                    content_controls,
                    tight=True,
                    scroll=ft.ScrollMode.AUTO,
                ),
                width=400,
                padding=10,
            ),
            actions=[
                ft.TextButton("Close", on_click=self.close),
                ft.TextButton(
                    "Modify", icon=ft.Icons.EDIT, on_click=self._on_edit_click
                ),
                ft.TextButton(
                    "Delete",
                    icon=ft.Icons.DELETE,
                    on_click=self._on_delete_click,
                    style=ft.ButtonStyle(color=ft.Colors.RED),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        self.page.overlay.append(self.dialog)
        self.dialog.open = True
        self.page.update()

    def _on_edit_click(self, e):
        self.close(e)
        if self.on_edit:
            self.on_edit()

    def _on_delete_click(self, e):
        self.close(e)
        if self.on_delete:
            self.on_delete()

    def close(self, e=None):
        if self.dialog:
            self.dialog.open = False
            self.page.update()

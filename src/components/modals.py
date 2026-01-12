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
        subcategories: List[Dict[str, Any]],
        on_save: Callable,
        is_dark: bool = True,
        transaction_type: str = "expense",
    ):
        self.page = page
        self.categories = categories
        self.subcategories = subcategories
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
                icon=ft.icons.CALENDAR_TODAY,
                on_click=self._open_date_picker,
            ),
        )

        # Description
        self.description_field = ft.TextField(
            label="Description",
            hint_text="Ex: Groceries, Rent...",
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

        # Dropdowns Selection logic
        # Filter subcategories (Assuming we want banking accounts mostly for internal transfers
        # but allowing all for flexibility)
        # We sort them
        sorted_subcats = sorted(self.subcategories, key=lambda x: x["name"])
        options = [
            ft.dropdown.Option(str(sub["id"]), sub["name"]) for sub in sorted_subcats
        ]

        # Use explicitly typed list or append to empty list to avoid type inference issues
        self.controls_list: List[ft.Control] = [
            self.date_picker,
            self.description_field,
            self.amount_field,
        ]

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
            self.subcategory_dropdown = ft.Dropdown(
                label=label,
                width=350,
                options=options,
            )
            if options:
                self.subcategory_dropdown.value = options[0].key

            self.controls_list.append(self.subcategory_dropdown)

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

    def _open_date_picker(self, e):
        """Ouvre le sélecteur de date."""
        date_picker = ft.DatePicker(
            first_date=datetime(2020, 1, 1),
            last_date=datetime(2030, 12, 31),
            on_change=self._on_date_change,
        )
        self.page.overlay.append(date_picker)
        date_picker.open = True
        self.page.update()

    def _on_date_change(self, e):
        """Gère le changement de date."""
        if e.control.value:
            self.date_picker.value = e.control.value.strftime("%Y-%m-%d")
            self.page.update()

    def _validate_form(self) -> bool:
        """Valide le formulaire."""
        errors = []

        if not self.description_field.value or not self.description_field.value.strip():
            errors.append("Description is required")
            self.description_field.error_text = "Required"
        else:
            self.description_field.error_text = None

        if not self.amount_field.value:
            errors.append("Amount is required")
            self.amount_field.error_text = "Required"
        else:
            try:
                amount = float(self.amount_field.value)
                if amount <= 0:
                    errors.append("Amount must be positive")
                    self.amount_field.error_text = "Must be positive"
                else:
                    self.amount_field.error_text = None
            except ValueError:
                errors.append("Invalid amount")
                self.amount_field.error_text = "Invalid amount"

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
        amount_str = self.amount_field.value or "0"

        transaction_data = {
            "date": self.date_picker.value,
            "description": description.strip(),
            "amount": float(amount_str),
            "transaction_type": self.transaction_type,
            "category_id": None,
            "notes": self.notes_field.value.strip() if self.notes_field.value else None,
        }

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
            sub_val = self.subcategory_dropdown.value
            transaction_data["subcategory_id"] = int(sub_val) if sub_val else None

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
                "subcategory_id"
            ):
                self.subcategory_dropdown.value = str(
                    transaction_data["subcategory_id"]
                )

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
                    icon=ft.icons.SAVE,
                    on_click=self._on_save_click,
                    bgcolor=PeadraTheme.PRIMARY_MEDIUM,
                    color=ft.colors.WHITE,
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

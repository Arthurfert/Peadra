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
        filter_type: Optional[str] = None # 'bank' or 'asset'
    ):
        self.page = page
        self.categories = categories
        self.subcategories = subcategories
        self.on_save = on_save
        self.is_dark = is_dark
        self.filter_type = filter_type
        self.dialog = None
        self._build_controls()

    def _build_controls(self):
        """Construit les contrôles du formulaire."""

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
            label="Description (Type de dépense)",
            hint_text="Ex: Courses, Bar, Loyer...",
            width=350,
            autofocus=True,
        )

        # Montant
        self.amount_field = ft.TextField(
            label="Montant (€)",
            hint_text="0.00",
            width=150,
            keyboard_type=ft.KeyboardType.NUMBER,
            input_filter=ft.InputFilter(
                regex_string=r"^[0-9]*\.?[0-9]*$",
                allow=True,
            ),
        )

        # Type de transaction
        self.type_dropdown = ft.Dropdown(
            label="Sens",
            width=150,
            value="expense",
            options=[
                ft.dropdown.Option("income", "Revenu"),
                ft.dropdown.Option("expense", "Dépense"),
                ft.dropdown.Option("transfer", "Transfert"),
            ],
        )

        # Sous-catégorie (Compte / Actif)
        filtered_subcats = []
        if self.filter_type == 'bank':
             filtered_subcats = [s for s in self.subcategories if s.get('category_name') == 'Cash']
        elif self.filter_type == 'asset':
             filtered_subcats = [s for s in self.subcategories if s.get('category_name') in ['Bourse', 'Immobilier']]
        else:
             filtered_subcats = self.subcategories

        filtered_subcats.sort(key=lambda x: x['name'])

        self.subcategory_dropdown = ft.Dropdown(
            label="Compte / Actif",
            width=350,
            options=[ft.dropdown.Option(str(sub["id"]), sub["name"]) for sub in filtered_subcats],
        )
        if filtered_subcats:
            self.subcategory_dropdown.value = str(filtered_subcats[0]["id"])

        # Notes
        self.notes_field = ft.TextField(
            label="Notes (optionnel)",
            hint_text="Informations supplémentaires...",
            width=350,
            multiline=True,
            min_lines=2,
            max_lines=4,
        )

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
            errors.append("La description est requise")
            self.description_field.error_text = "Requis"
        else:
            self.description_field.error_text = None

        if not self.amount_field.value:
            errors.append("Le montant est requis")
            self.amount_field.error_text = "Requis"
        else:
            try:
                amount = float(self.amount_field.value)
                if amount <= 0:
                    errors.append("Le montant doit être positif")
                    self.amount_field.error_text = "Doit être positif"
                else:
                    self.amount_field.error_text = None
            except ValueError:
                errors.append("Montant invalide")
                self.amount_field.error_text = "Invalide"

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
            "transaction_type": self.type_dropdown.value,
            "category_id": None, 
            "subcategory_id": (
                int(self.subcategory_dropdown.value)
                if self.subcategory_dropdown.value
                else None
            ),
            "notes": self.notes_field.value.strip() if self.notes_field.value else None,
        }

        self.close()

        if self.on_save:
            self.on_save(transaction_data)

    def _on_cancel_click(self, e):
        """Gère le clic sur le bouton Annuler."""
        self.close()

    def show(self, transaction_data: Optional[Dict[str, Any]] = None):
        """Affiche le modal."""
        self._build_controls()
        
        if transaction_data:
            self.date_picker.value = transaction_data.get("date", datetime.now().strftime("%Y-%m-%d"))
            self.description_field.value = transaction_data.get("description", "")
            self.amount_field.value = str(transaction_data.get("amount", ""))
            self.type_dropdown.value = transaction_data.get("transaction_type", "expense")
            if transaction_data.get("subcategory_id"):
                self.subcategory_dropdown.value = str(transaction_data["subcategory_id"])
            self.notes_field.value = transaction_data.get("notes", "")

        title = "Modifier" if transaction_data else "Nouveau mouvement"

        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(title, weight=ft.FontWeight.BOLD),
            content=ft.Container(
                content=ft.Column(
                    controls=[
                        self.date_picker,
                        self.type_dropdown,
                        self.description_field,
                        ft.Row([self.amount_field, self.subcategory_dropdown], spacing=16),
                        self.notes_field,
                    ],
                    spacing=16,
                    tight=True,
                ),
                width=500,
                padding=ft.padding.only(top=10),
            ),
            actions=[
                ft.TextButton("Annuler", on_click=self._on_cancel_click),
                ft.ElevatedButton(
                    "Enregistrer",
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

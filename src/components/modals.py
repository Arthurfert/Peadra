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
    ):
        self.page = page
        self.categories = categories
        self.subcategories = subcategories
        self.on_save = on_save
        self.is_dark = is_dark
        self.dialog = None
        self._build_controls()
    
    def _build_controls(self):
        """Construit les contrôles du formulaire."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
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
            hint_text="Ex: Salaire, Loyer, Courses...",
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
            label="Type",
            width=150,
            value="expense",
            options=[
                ft.dropdown.Option("income", "Revenu"),
                ft.dropdown.Option("expense", "Dépense"),
                ft.dropdown.Option("transfer", "Transfert"),
            ],
        )
        
        # Catégorie
        category_options = [
            ft.dropdown.Option(str(cat["id"]), cat['name'])
            for cat in self.categories
        ]
        self.category_dropdown = ft.Dropdown(
            label="Catégorie",
            width=200,
            options=category_options,
            on_change=self._on_category_change,
        )
        
        # Sous-catégorie
        self.subcategory_dropdown = ft.Dropdown(
            label="Sous-catégorie",
            width=200,
            options=[],
        )
        
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
    
    def _on_category_change(self, e):
        """Met à jour les sous-catégories lors du changement de catégorie."""
        category_id = int(e.control.value) if e.control.value else None
        
        if category_id:
            filtered_subcategories = [
                sub for sub in self.subcategories
                if sub.get("category_id") == category_id
            ]
            self.subcategory_dropdown.options = [
                ft.dropdown.Option(str(sub["id"]), sub['name'])
                for sub in filtered_subcategories
            ]
        else:
            self.subcategory_dropdown.options = []
        
        self.subcategory_dropdown.value = None
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
            "category_id": int(self.category_dropdown.value) if self.category_dropdown.value else None,
            "subcategory_id": int(self.subcategory_dropdown.value) if self.subcategory_dropdown.value else None,
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
        # Réinitialiser les champs
        self._build_controls()
        
        # Pré-remplir si édition
        if transaction_data:
            self.date_picker.value = transaction_data.get("date", datetime.now().strftime("%Y-%m-%d"))
            self.description_field.value = transaction_data.get("description", "")
            self.amount_field.value = str(transaction_data.get("amount", ""))
            self.type_dropdown.value = transaction_data.get("transaction_type", "expense")
            if transaction_data.get("category_id"):
                self.category_dropdown.value = str(transaction_data["category_id"])
                # Mettre à jour les sous-catégories
                filtered_subcategories = [
                    sub for sub in self.subcategories
                    if sub.get("category_id") == transaction_data["category_id"]
                ]
                self.subcategory_dropdown.options = [
                    ft.dropdown.Option(str(sub["id"]), sub['name'])
                    for sub in filtered_subcategories
                ]
                if transaction_data.get("subcategory_id"):
                    self.subcategory_dropdown.value = str(transaction_data["subcategory_id"])
            self.notes_field.value = transaction_data.get("notes", "")
        
        title = "Modifier la transaction" if transaction_data else "Nouvelle transaction"
        
        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(title, weight=ft.FontWeight.BOLD),
            content=ft.Container(
                content=ft.Column(
                    controls=[
                        ft.Row(
                            controls=[self.date_picker, self.type_dropdown],
                            spacing=16,
                        ),
                        self.description_field,
                        ft.Row(
                            controls=[self.amount_field, self.category_dropdown],
                            spacing=16,
                        ),
                        self.subcategory_dropdown,
                        self.notes_field,
                    ],
                    spacing=16,
                    tight=True,
                ),
                width=400,
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


class AssetModal:
    """Modal pour ajouter/éditer un actif."""
    
    def __init__(
        self,
        page: ft.Page,
        categories: List[Dict[str, Any]],
        on_save: Callable,
        is_dark: bool = True,
    ):
        self.page = page
        self.categories = categories
        self.on_save = on_save
        self.is_dark = is_dark
        self.dialog = None
        self.editing_asset_id = None
        self._build_controls()
    
    def _build_controls(self):
        """Construit les contrôles du formulaire."""
        # Nom de l'actif
        self.name_field = ft.TextField(
            label="Nom de l'actif",
            hint_text="Ex: Appartement Paris, PEA Boursorama...",
            width=350,
            autofocus=True,
        )
        
        # Catégorie
        category_options = [
            ft.dropdown.Option(str(cat["id"]), cat['name'])
            for cat in self.categories
        ]
        self.category_dropdown = ft.Dropdown(
            label="Catégorie",
            width=350,
            options=category_options,
        )
        
        # Valeur actuelle
        self.current_value_field = ft.TextField(
            label="Valeur actuelle (€)",
            hint_text="0.00",
            width=170,
            keyboard_type=ft.KeyboardType.NUMBER,
            input_filter=ft.InputFilter(
                regex_string=r"^[0-9]*\.?[0-9]*$",
                allow=True,
            ),
        )
        
        # Valeur d'achat
        self.purchase_value_field = ft.TextField(
            label="Valeur d'achat (€)",
            hint_text="0.00",
            width=170,
            keyboard_type=ft.KeyboardType.NUMBER,
            input_filter=ft.InputFilter(
                regex_string=r"^[0-9]*\.?[0-9]*$",
                allow=True,
            ),
        )
        
        # Date d'achat
        self.purchase_date_field = ft.TextField(
            label="Date d'achat",
            value="",
            read_only=True,
            width=170,
            suffix=ft.IconButton(
                icon=ft.icons.CALENDAR_TODAY,
                on_click=self._open_date_picker,
            ),
        )
        
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
            first_date=datetime(2000, 1, 1),
            last_date=datetime.now(),
            on_change=self._on_date_change,
        )
        self.page.overlay.append(date_picker)
        date_picker.open = True
        self.page.update()
    
    def _on_date_change(self, e):
        """Gère le changement de date."""
        if e.control.value:
            self.purchase_date_field.value = e.control.value.strftime("%Y-%m-%d")
            self.page.update()
    
    def _validate_form(self) -> bool:
        """Valide le formulaire."""
        errors = []
        
        if not self.name_field.value or not self.name_field.value.strip():
            self.name_field.error_text = "Requis"
            errors.append("Nom requis")
        else:
            self.name_field.error_text = None
        
        if not self.category_dropdown.value:
            self.category_dropdown.error_text = "Requis"
            errors.append("Catégorie requise")
        else:
            self.category_dropdown.error_text = None
        
        if not self.current_value_field.value:
            self.current_value_field.error_text = "Requis"
            errors.append("Valeur requise")
        else:
            try:
                float(self.current_value_field.value)
                self.current_value_field.error_text = None
            except ValueError:
                self.current_value_field.error_text = "Invalide"
                errors.append("Valeur invalide")
        
        self.page.update()
        return len(errors) == 0
    
    def _on_save_click(self, e):
        """Gère le clic sur le bouton Enregistrer."""
        if not self._validate_form():
            return
        
        name = self.name_field.value or ""
        category_value = self.category_dropdown.value or "0"
        current_value_str = self.current_value_field.value or "0"
        
        asset_data = {
            "name": name.strip(),
            "category_id": int(category_value),
            "current_value": float(current_value_str),
            "purchase_value": float(self.purchase_value_field.value) if self.purchase_value_field.value else None,
            "purchase_date": self.purchase_date_field.value if self.purchase_date_field.value else None,
            "notes": self.notes_field.value.strip() if self.notes_field.value else None,
        }
        
        if self.editing_asset_id:
            asset_data["id"] = self.editing_asset_id
        
        self.close()
        
        if self.on_save:
            self.on_save(asset_data)
    
    def _on_cancel_click(self, e):
        """Gère le clic sur le bouton Annuler."""
        self.close()
    
    def show(self, asset_data: Optional[Dict[str, Any]] = None):
        """Affiche le modal."""
        self._build_controls()
        self.editing_asset_id = None
        
        if asset_data:
            self.editing_asset_id = asset_data.get("id")
            self.name_field.value = asset_data.get("name", "")
            if asset_data.get("category_id"):
                self.category_dropdown.value = str(asset_data["category_id"])
            self.current_value_field.value = str(asset_data.get("current_value", ""))
            if asset_data.get("purchase_value"):
                self.purchase_value_field.value = str(asset_data["purchase_value"])
            if asset_data.get("purchase_date"):
                self.purchase_date_field.value = asset_data["purchase_date"]
            self.notes_field.value = asset_data.get("notes", "")
        
        title = "Modifier l'actif" if asset_data else "Nouvel actif"
        
        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(title, weight=ft.FontWeight.BOLD),
            content=ft.Container(
                content=ft.Column(
                    controls=[
                        self.name_field,
                        self.category_dropdown,
                        ft.Row(
                            controls=[self.current_value_field, self.purchase_value_field],
                            spacing=16,
                        ),
                        self.purchase_date_field,
                        self.notes_field,
                    ],
                    spacing=16,
                    tight=True,
                ),
                width=400,
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

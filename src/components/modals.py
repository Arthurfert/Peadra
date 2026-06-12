"""
Modal de saisie rapide pour les transactions.
"""

import flet as ft
import logging
from datetime import datetime
from typing import Callable, List, Dict, Any, Optional, cast
from difflib import SequenceMatcher
from .theme import PeadraTheme
from ..database.db_manager import db, CURRENCY_DATA, get_currency_symbol, get_currency_name, get_default_currency, format_amount, format_amount_with_conversion
from ..i18n import t as translate, get_translator

logger = logging.getLogger(__name__)


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
        self._selected_currency = get_default_currency()

        # Date picker
        self.date_picker = ft.TextField(
            label=translate("trans_date"),
            value=datetime.now().strftime("%Y-%m-%d"),
            read_only=True,
            width=200,
            suffix=ft.IconButton(
                icon=ft.Icons.CALENDAR_TODAY,
                on_click=self._open_date_picker,
            ),
        )

        # Description
        hint = translate("hint_expense")
        if self.transaction_type == "income":
            hint = translate("hint_income")

        self.description_field = ft.TextField(
            label=translate("trans_description"),
            hint_text=hint,
            width=350,
            autofocus=True,
            on_change=self._on_description_change,
        )

        # Container pour les suggestions de description
        self.suggestions_list_view = ft.ListView(expand=True, spacing=0)
        self.suggestions_container = ft.Container(
            content=self.suggestions_list_view,
            visible=False,
            height=150,
            border=ft.border.all(1, ft.Colors.OUTLINE),
            border_radius=5,
            clip_behavior=ft.ClipBehavior.HARD_EDGE,
        )

        # Amount
        self._currency_label = translate("trans_amount")
        self.amount_field = ft.TextField(
            label=f"{self._currency_label} ({get_currency_symbol(self._selected_currency)})",
            hint_text=translate("hint_amount"),
            width=350,
            keyboard_type=ft.KeyboardType.NUMBER,
            input_filter=ft.InputFilter(
                regex_string=r"^[0-9]*\.?[0-9]*$",
                allow=True,
            ),
        )

        # Recurring
        self.recurring_interval = ft.TextField(
            label=translate("trans_every"),
            value="1",
            width=80,
            keyboard_type=ft.KeyboardType.NUMBER,
            text_align=ft.TextAlign.RIGHT,
        )

        self.recurring_freq = ft.Dropdown(
            label=translate("trans_frequency_label"),
            width=200,
            options=[
                ft.dropdown.Option("daily", translate("freq_daily")),
                ft.dropdown.Option("weekly", translate("freq_weekly")),
                ft.dropdown.Option("monthly", translate("freq_monthly")),
                ft.dropdown.Option("yearly", translate("freq_yearly")),
            ],
            value="monthly",
        )

        self.recurring_end_date = ft.TextField(
            label=translate("trans_end_date"),
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
            label=translate("trans_recurring"),
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
            self.controls_list.append(self.suggestions_container)

        self.controls_list.append(self.amount_field)

        if self.transaction_type == "transfer":
            # Currency selector for the transfer amount
            _lang = get_translator().get_language()
            currency_options = [
                ft.dropdown.Option(code, f"{code} - {get_currency_name(code, _lang)} ({get_currency_symbol(code)})")
                for code in CURRENCY_DATA
            ]
            self.transfer_currency_dropdown = ft.Dropdown(
                label=translate("trans_currency"),
                width=350,
                options=currency_options,
                value=self._selected_currency,
                on_select=self._on_transfer_currency_change,
            )
            self.controls_list.append(self.transfer_currency_dropdown)

            # Two dropdowns: Source and Dest
            self.source_dropdown = ft.Dropdown(
                label=translate("trans_account_from"),
                width=350,
                options=options,
            )
            self.dest_dropdown = ft.Dropdown(
                label=translate("trans_account_to"),
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
            label = translate("trans_category")
            self.category_dropdown = ft.Dropdown(
                label=label,
                width=350,
                options=options,
                on_select=self._on_category_change,
            )
            if options:
                self.category_dropdown.value = options[0].key
                self._update_currency_from_category(options[0].key)

            self.controls_list.append(self.category_dropdown)

        # Notes
        self.notes_field = ft.TextField(
            label=translate("trans_notes"),
            hint_text=translate("hint_notes"),
            width=350,
            multiline=True,
            min_lines=2,
            max_lines=4,
        )
        self.controls_list.append(self.notes_field)

        # Add recurring option for both new and editing transactions
        if hasattr(self, "recurring_switch"):
            self.controls_list.append(ft.Divider())
            self.controls_list.append(self.recurring_switch)
            self.controls_list.append(self.recurring_container)

    def _on_description_change(self, e):
        """Gère les changements dans le champ description."""
        search_term = self.description_field.value.strip()

        if search_term:
            # Récupérer les suggestions depuis la base de données
            suggestions_raw = db.get_unique_descriptions(
                transaction_type=self.transaction_type, search_term=search_term
            )
            # Trier les suggestions intelligemment
            sorted_suggestions = self._sort_suggestions(suggestions_raw, search_term)
            self._update_suggestions_ui(sorted_suggestions, search_term)
        else:
            # Masquer les suggestions si le champ est vide
            self.suggestions_container.visible = False
            self.suggestions_list_view.controls.clear()
            self.page.update()

    def _sort_suggestions(
        self, suggestions_raw: List[Dict[str, Any]], search_term: str
    ) -> List[str]:
        """Trie les suggestions selon plusieurs critères.

        Utilise un score composite pondéré :
        - Commence par le terme : +10 (fort bonus)
        - Similarité textuelle : jusqu'à +3
        - Fréquence d'occurrence : jusqu'à +6 (poids renforcé)
        """
        search_lower = search_term.lower()
        max_count = max((s["count"] for s in suggestions_raw), default=1)

        def sort_key(item: Dict[str, Any]):
            desc = item["description"].lower()
            # starts_with : +0 à +10 (bonus si la description commence par le terme)
            starts_with = desc.startswith(search_lower)
            # similarity : +0 à +3 (basé sur la similarité textuelle)
            similarity = SequenceMatcher(None, search_lower, desc).ratio()
            # count_norm : +0 à +6 (basé sur la fréquence d'occurrence, normalisée)
            count_norm = item["count"] / max_count if max_count > 0 else 0

            score = starts_with * 10.0 + similarity * 3.0 + count_norm * 6.0
            return -score

        sorted_data = sorted(suggestions_raw, key=sort_key)
        return [item["description"] for item in sorted_data]

    def _update_suggestions_ui(self, suggestions: List[str], search_term: str):
        """Met à jour l'affichage des suggestions."""
        self.suggestions_list_view.controls.clear()

        if not suggestions:
            self.suggestions_container.visible = False
            self.page.update()
            return

        # Créer des boutons pour chaque suggestion
        for suggestion in suggestions:
            suggestion_btn = ft.ListTile(
                title=ft.Text(suggestion.capitalize(), size=14, color=PeadraTheme.text_secondary),
                on_click=lambda e, s=suggestion: self._on_suggestion_selected(s),
                dense=True,
                height=30,
            )
            self.suggestions_list_view.controls.append(suggestion_btn)

        self.suggestions_container.visible = True
        self.page.update()

    def _on_suggestion_selected(self, suggestion: str):
        """Gère la sélection d'une suggestion."""
        self.description_field.value = suggestion.capitalize()
        self.suggestions_container.visible = False
        self.suggestions_list_view.controls.clear()
        self.page.update()

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
                selected_date = e.control.value
                # DatePicker peut renvoyer une datetime avec fuseau UTC.
                # On convertit en heure locale pour conserver le jour choisi.
                if selected_date.tzinfo is not None:
                    selected_date = selected_date.astimezone()
                field.value = selected_date.date().isoformat()
                field.update()

        def on_dismiss(e):
            # Le DatePicker reste dans l'overlay mais est fermé.
            # Flet gère mieux les overlays qui ne sont pas supprimés/réajoutés
            pass

        date_picker = ft.DatePicker(
            first_date=datetime(2000, 1, 1),
            last_date=datetime(2100, 12, 31),
            value=d,
            on_change=on_change,
            on_dismiss=on_dismiss,
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
                errors.append(
                    translate("trans_description")
                    + " "
                    + translate("val_required").lower()
                )
                self.description_field.error = translate("val_required")
            else:
                self.description_field.error = None

        if not self.amount_field.value:
            errors.append(
                translate("trans_amount") + " " + translate("val_required").lower()
            )
            self.amount_field.error = translate("val_required")
        else:
            try:
                amount = float(self.amount_field.value)
                if amount <= 0:
                    errors.append(
                        translate("trans_amount")
                        + " "
                        + translate("val_must_be_positive").lower()
                    )
                    self.amount_field.error = translate("val_must_be_positive")
                else:
                    self.amount_field.error = None
            except ValueError:
                errors.append(translate("val_invalid_amount"))
                self.amount_field.error = translate("val_invalid_amount")

        if self.transaction_type == "transfer":
            if self.source_dropdown.value == self.dest_dropdown.value:
                errors.append(translate("val_identical_accounts"))
                self.dest_dropdown.error_text = translate("val_identical_accounts")
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
            description = translate(
                "trans_transfer_placeholder"
            )  # Placeholder, will be overwritten
        amount_str = self.amount_field.value or "0"

        transaction_data = {
            "date": self.date_picker.value,
            "description": description.strip(),
            "amount": float(amount_str),
            "transaction_type": self.transaction_type,
            "category_id": None,
            "notes": self.notes_field.value.strip() if self.notes_field.value else None,
            "currency": self._selected_currency,
        }

        # Add recurring data if enabled
        if hasattr(self, "recurring_switch") and self.recurring_switch.value:
            transaction_data.update(
                {
                    "is_recurring": True,
                    "frequency": self.recurring_freq.value,
                    "interval": int(self.recurring_interval.value or 1),
                    "end_date": (
                        self.recurring_end_date.value
                        if self.recurring_end_date.value
                        else None
                    ),
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

        logger.debug("Transaction modal save clicked, type=%s", self.transaction_type)
        self.close()

        if self.on_save:
            self.on_save(transaction_data)

    def _update_currency_from_category(self, category_id_str: Optional[str]):
        """Met à jour la devise affichée en fonction de la catégorie sélectionnée."""
        if not category_id_str:
            self._selected_currency = get_default_currency()
        else:
            try:
                cat_id = int(category_id_str)
                cat_currency = db._get_category_currency(cat_id)
                self._selected_currency = cat_currency if cat_currency else get_default_currency()
            except (ValueError, TypeError):
                self._selected_currency = get_default_currency()
        if hasattr(self, "amount_field"):
            self.amount_field.label = f"{self._currency_label} ({get_currency_symbol(self._selected_currency)})"
            try:
                self.amount_field.update()
            except RuntimeError:
                pass

    def _on_category_change(self, e):
        """Met à jour la devise quand la catégorie change."""
        self._update_currency_from_category(e.control.value)

    def _on_transfer_currency_change(self, e):
        """Met à jour la devise quand la devise de transfert change."""
        self._selected_currency = e.control.value
        if hasattr(self, "amount_field"):
            self.amount_field.label = f"{self._currency_label} ({get_currency_symbol(self._selected_currency)})"
            try:
                self.amount_field.update()
            except RuntimeError:
                pass

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
                "date",
                transaction_data.get("start_date", datetime.now().strftime("%Y-%m-%d")),
            )
            self.description_field.value = transaction_data.get("description", "")
            self.amount_field.value = str(transaction_data.get("amount", ""))
            self.notes_field.value = transaction_data.get("notes", "")

            if self.transaction_type != "transfer" and transaction_data.get(
                "category_id"
            ):
                self.category_dropdown.value = str(transaction_data["category_id"])
                self._update_currency_from_category(str(transaction_data["category_id"]))

            if self.transaction_type == "transfer":
                if transaction_data.get("source_id"):
                    self.source_dropdown.value = str(transaction_data["source_id"])
                if transaction_data.get("dest_id"):
                    self.dest_dropdown.value = str(transaction_data["dest_id"])

            if hasattr(self, "recurring_switch") and (
                "frequency" in transaction_data or transaction_data.get("is_recurring")
            ):
                self.recurring_switch.value = True
                self.recurring_container.visible = True
                self.recurring_freq.value = str(
                    transaction_data.get("frequency", "monthly")
                )
                self.recurring_interval.value = str(
                    transaction_data.get("interval", "1")
                )
                if transaction_data.get("end_date"):
                    self.recurring_end_date.value = str(
                        transaction_data.get("end_date")
                    )

        type_map = {
            "income": translate("modal_new_income"),
            "expense": translate("modal_new_expense"),
            "transfer": translate("modal_new_transfer"),
        }
        title = type_map.get(self.transaction_type, translate("modal_new_transaction"))
        if transaction_data:
            title = translate("modal_edit_transaction")

        self.dialog = ft.AlertDialog(
            title=ft.Text(title, weight=ft.FontWeight.BOLD, color=PeadraTheme.text_secondary),
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
                ft.TextButton(translate("btn_cancel"), on_click=self._on_cancel_click),
                ft.ElevatedButton(
                    translate("btn_save"),
                    icon=ft.Icons.SAVE,
                    on_click=self._on_save_click,
                    bgcolor=PeadraTheme.primary_medium,
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
        transaction = self.transaction

        # Format date
        try:
            date_obj = datetime.strptime(transaction["date"], "%Y-%m-%d")
            date_str = date_obj.strftime("%d %B %Y")
        except ValueError:
            date_str = transaction["date"]

        # Determine colors and icon
        is_income = transaction["transaction_type"] == "income"
        is_expense = transaction["transaction_type"] == "expense"
        is_transfer = "transfer" in transaction["transaction_type"]

        if is_income:
            color = PeadraTheme.success
            icon = ft.Icons.ARROW_DOWNWARD
            amount_prefix = "+"
        elif is_expense:
            color = PeadraTheme.error
            icon = ft.Icons.ARROW_UPWARD
            amount_prefix = "-"
            # Fix display for expense to be positive value with - sign if desired,
            # currently amount is stored positive usually.
            amount_prefix = "- "
        else:  # Transfer
            color = PeadraTheme.transfer_color
            icon = ft.Icons.SWAP_HORIZ
            amount_prefix = ""

        tx_currency = transaction.get("category_currency") or transaction.get("currency") or get_default_currency()
        amount_txt = format_amount_with_conversion(
            transaction["amount"], tx_currency, get_default_currency()
        )
        if amount_prefix:
            amount_txt = f"{amount_prefix}{amount_txt}"

        # Category info
        full_category = transaction.get("category_name") or translate(
            "modal_uncategorized"
        )

        # Content controls
        content_controls = [
            ft.Container(
                content=ft.Column(
                    controls=[
                        ft.Icon(icon, size=40, color=color),
                        ft.Text(
                            amount_txt, size=30, weight=ft.FontWeight.BOLD, color=PeadraTheme.text_secondary
                        ),
                        ft.Text(date_str, size=14, color=PeadraTheme.text_secondary),
                    ],
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                ),
                alignment=ft.Alignment(0, 0),
                padding=ft.padding.only(bottom=20),
            ),
            ft.Divider(),
            ft.ListTile(
                leading=ft.Icon(ft.Icons.DESCRIPTION),
                title=ft.Text(
                    translate("modal_description_label"), size=12, color=PeadraTheme.text_secondary
                ),
                subtitle=ft.Text(
                    transaction["description"], size=16, weight=ft.FontWeight.W_500, color=PeadraTheme.text_secondary
                ),
            ),
            ft.ListTile(
                leading=ft.Icon(ft.Icons.CATEGORY),
                title=ft.Text(
                    translate("modal_category_label"), size=12, color=PeadraTheme.text_secondary
                ),
                subtitle=ft.Text(full_category, size=16, color=PeadraTheme.text_secondary),
            ),
        ]

        # Add Notes if present
        if transaction.get("notes"):
            content_controls.append(
                ft.ListTile(
                    leading=ft.Icon(ft.Icons.NOTE),
                    title=ft.Text(
                        translate("modal_notes_label"), size=12, color=PeadraTheme.text_secondary
                    ),
                    subtitle=ft.Text(transaction["notes"], size=16, color=PeadraTheme.text_secondary),
                )
            )

        self.dialog = ft.AlertDialog(
            title=ft.Text(translate("modal_transaction_details"), color=PeadraTheme.text_secondary),
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
                ft.TextButton(translate("modal_close"), on_click=self.close),
                ft.TextButton(
                    translate("btn_modify"),
                    icon=ft.Icons.EDIT,
                    on_click=self._on_edit_click,
                ),
                ft.TextButton(
                    translate("modal_delete"),
                    icon=ft.Icons.DELETE,
                    on_click=self._on_delete_click,
                    style=ft.ButtonStyle(color=PeadraTheme.delete_color),
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


class MergeDescriptionsModal:
    """Modal pour fusionner deux descriptions."""

    def __init__(
        self,
        page: ft.Page,
        descriptions: List[str],
        transaction_type: str,
        on_merge: Callable,
    ):
        self.page = page
        self.descriptions = sorted(descriptions)
        self.transaction_type = transaction_type
        self.on_merge = on_merge
        self.dialog = None
        self.source_dropdown = None
        self.target_dropdown = None

    def _on_merge_click(self, e):
        """Gère le clic sur le bouton Fusionner."""
        if not self.source_dropdown or not self.target_dropdown:
            return

        if not self.source_dropdown.value or not self.target_dropdown.value:
            snack = ft.SnackBar(
                ft.Text(translate("val_required")),
                bgcolor=ft.Colors.ERROR,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return

        source_val = self.source_dropdown.value
        target_val = self.target_dropdown.value

        if source_val == target_val:
            snack = ft.SnackBar(
                ft.Text(translate("val_invalid_operation")),
                bgcolor=ft.Colors.ERROR,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return

        self.close()

        if self.on_merge:
            self.on_merge(
                source=source_val,
                target=target_val,
            )

    def _on_cancel_click(self, e):
        """Gère le clic sur le bouton Annuler."""
        self.close()

    def show(self):
        """Affiche le modal."""
        options = [ft.dropdown.Option(d, d) for d in self.descriptions]

        self.source_dropdown = ft.Dropdown(
            label=translate("cat_merge_source"),
            width=350,
            options=options,
        )

        self.target_dropdown = ft.Dropdown(
            label=translate("cat_merge_target"),
            width=350,
            options=options,
        )

        self.dialog = ft.AlertDialog(
            title=ft.Text(
                translate("cat_merge_descriptions"),
                weight=ft.FontWeight.BOLD,
                color=PeadraTheme.text_secondary,
            ),
            content=ft.Container(
                content=ft.Column(
                    cast(
                        List[ft.Control],
                        [
                            ft.Text(
                                translate("cat_merge_hint"),
                                size=13,
                                color=PeadraTheme.text_secondary,
                            ),
                            ft.Divider(),
                            ft.Text(
                                translate("cat_merge_from"),
                                size=12,
                                weight=ft.FontWeight.W_600,
                                color=PeadraTheme.text_secondary,
                            ),
                            self.source_dropdown,
                            ft.Container(height=16),
                            ft.Text(
                                translate("cat_merge_to"),
                                size=12,
                                weight=ft.FontWeight.W_600,
                                color=PeadraTheme.text_secondary,
                            ),
                            self.target_dropdown,
                        ],
                    ),
                    spacing=12,
                    tight=True,
                ),
                width=400,
                padding=10,
            ),
            actions=[
                ft.TextButton(translate("btn_cancel"), on_click=self._on_cancel_click),
                ft.ElevatedButton(
                    translate("btn_merge"),
                    icon=ft.Icons.MERGE,
                    on_click=self._on_merge_click,
                    bgcolor=PeadraTheme.primary_medium,
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


class RenameDescriptionModal:
    """Modal pour renommer une description."""

    def __init__(
        self,
        page: ft.Page,
        descriptions: List[str],
        transaction_type: str,
        on_rename: Callable,
    ):
        self.page = page
        self.descriptions = sorted(descriptions)
        self.transaction_type = transaction_type
        self.on_rename = on_rename
        self.dialog = None
        self.description_dropdown = None
        self.new_name_field = None

    def _on_rename_click(self, e):
        """Gère le clic sur le bouton Renommer."""
        if not self.description_dropdown or not self.new_name_field:
            return

        if not self.description_dropdown.value or not self.new_name_field.value:
            snack = ft.SnackBar(
                ft.Text(translate("val_required")),
                bgcolor=ft.Colors.ERROR,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return

        old_name = self.description_dropdown.value
        new_name_raw = self.new_name_field.value

        if not new_name_raw:
            return

        new_name = new_name_raw.strip()

        if old_name.lower() == new_name.lower():
            snack = ft.SnackBar(
                ft.Text(translate("val_invalid_operation")),
                bgcolor=ft.Colors.ERROR,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return

        self.close()

        if self.on_rename:
            self.on_rename(
                old_description=old_name,
                new_description=new_name,
            )

    def _on_cancel_click(self, e):
        """Gère le clic sur le bouton Annuler."""
        self.close()

    def show(self):
        """Affiche le modal."""
        options = [ft.dropdown.Option(d, d) for d in self.descriptions]

        self.description_dropdown = ft.Dropdown(
            label=translate("cat_select_description"),
            width=350,
            options=options,
        )

        self.new_name_field = ft.TextField(
            label=translate("cat_new_name"),
            hint_text=translate("hint_description"),
            width=350,
        )

        self.dialog = ft.AlertDialog(
            title=ft.Text(
                translate("cat_rename_description"),
                weight=ft.FontWeight.BOLD,
                color=PeadraTheme.text_secondary,
            ),
            content=ft.Container(
                content=ft.Column(
                    cast(
                        List[ft.Control],
                        [
                            ft.Text(
                                translate("cat_rename_hint"),
                                size=13,
                                color=PeadraTheme.text_secondary,
                            ),
                            ft.Divider(),
                            ft.Text(
                                translate("cat_select_description_to_rename"),
                                size=12,
                                weight=ft.FontWeight.W_600,
                                color=PeadraTheme.text_secondary,
                            ),
                            self.description_dropdown,
                            ft.Container(height=16),
                            ft.Text(
                                translate("cat_new_name_label"),
                                size=12,
                                weight=ft.FontWeight.W_600,
                                color=PeadraTheme.text_secondary,
                            ),
                            self.new_name_field,
                        ],
                    ),
                    spacing=12,
                    tight=True,
                ),
                width=400,
                padding=10,
            ),
            actions=[
                ft.TextButton(translate("btn_cancel"), on_click=self._on_cancel_click),
                ft.ElevatedButton(
                    translate("btn_rename"),
                    icon=ft.Icons.EDIT,
                    on_click=self._on_rename_click,
                    bgcolor=PeadraTheme.primary_medium,
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

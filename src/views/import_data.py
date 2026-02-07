"""
Composant modal d'importation de données pour Peadra.
Permet d'importer des transactions depuis un fichier CSV via une boîte de dialogue.
"""

import flet as ft

# import flet_core as fct
from typing import Callable, Optional, List, Dict, Any
import csv
import codecs
import os
from datetime import datetime
from ..components.theme import PeadraTheme
from ..database.db_manager import db


class CustomFilePicker:
    """Sélecteur de fichiers personnalisé."""

    def __init__(
        self,
        page: ft.Page,
        on_select: Callable[[str], None],
        on_cancel: Callable[[], None],
        allowed_extensions: Optional[List[str]] = None,
    ):
        self.page = page
        self.on_select = on_select
        self.on_cancel = on_cancel
        self.allowed_extensions = [ext.lower() for ext in (allowed_extensions or [])]
        self.current_path = os.getcwd()

        self.path_text = ft.Text(value=self.current_path, size=12, color=ft.Colors.GREY)
        self.file_list = ft.ListView(expand=True, spacing=2)

        self.dialog = ft.AlertDialog(
            title=ft.Text("Select File"),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.Row(
                            [
                                ft.IconButton(
                                    icon=ft.Icons.ARROW_UPWARD,
                                    on_click=self._go_up,
                                    tooltip="Go up",
                                ),
                                ft.Container(
                                    content=self.path_text, expand=True, padding=5
                                ),
                            ],
                            alignment=ft.MainAxisAlignment.START,
                        ),
                        ft.Divider(height=1),
                        self.file_list,
                    ],
                    spacing=10,
                ),
                width=600,
                height=400,
                padding=10,
            ),
            actions=[ft.TextButton("Cancel", on_click=lambda _: self._cancel())],
        )

    def _cancel(self):
        """Handle cancel action to ensure dialog closes before callback."""
        self.dialog.open = False
        self.page.update()
        self.on_cancel()

    def open(self):
        self._refresh_file_list()
        self.page.show_dialog(self.dialog)
        self.page.update()

    def _refresh_file_list(self):
        self.path_text.value = self.current_path
        self.file_list.controls.clear()

        try:
            items = os.listdir(self.current_path)
            # Sort: folders first, then files
            folders = []
            files = []

            for item in items:
                full_path = os.path.join(self.current_path, item)
                if os.path.isdir(full_path):
                    folders.append(item)
                elif os.path.isfile(full_path):
                    files.append(item)

            folders.sort(key=str.lower)
            files.sort(key=str.lower)

            for folder in folders:
                self.file_list.controls.append(
                    ft.ListTile(
                        leading=ft.Icon(ft.Icons.FOLDER, color=ft.Colors.AMBER),
                        title=ft.Text(folder),
                        on_click=lambda e, p=folder: self._navigate(p),
                        dense=True,
                    )
                )

            for file in files:
                ext = os.path.splitext(file)[1][1:].lower()
                is_allowed = (
                    not self.allowed_extensions or ext in self.allowed_extensions
                )

                self.file_list.controls.append(
                    ft.ListTile(
                        leading=ft.Icon(
                            ft.Icons.INSERT_DRIVE_FILE,
                            color=ft.Colors.BLUE if is_allowed else ft.Colors.GREY,
                        ),
                        title=ft.Text(
                            file, color=None if is_allowed else ft.Colors.GREY
                        ),
                        on_click=lambda e, p=file: self._select_file(p)
                        if is_allowed
                        else None,
                        dense=True,
                        disabled=not is_allowed,
                        opacity=1.0 if is_allowed else 0.5,
                    )
                )

        except Exception as e:
            self.file_list.controls.append(ft.Text(f"Error: {e}", color=ft.Colors.RED))

        self.page.update()

    def _navigate(self, folder_name: str):
        self.current_path = os.path.join(self.current_path, folder_name)
        self._refresh_file_list()

    def _go_up(self, _):
        parent = os.path.dirname(self.current_path)
        if parent and parent != self.current_path:
            self.current_path = parent
            self._refresh_file_list()

    def _select_file(self, file_name: str):
        full_path = os.path.join(self.current_path, file_name)
        self.dialog.open = False
        self.page.update()
        self.on_select(full_path)


class ImportDialog:
    """Boîte de dialogue d'importation de données."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change

        # Custom File Picker setup
        self.custom_file_picker = CustomFilePicker(
            page=self.page,
            on_select=self._on_custom_file_selected,
            on_cancel=self._on_custom_picker_cancel,
            allowed_extensions=["csv"],
        )

        self.current_file_path: Optional[str] = None
        self.preview_data: List[Dict[str, Any]] = []
        self.parsed_transactions: List[Dict[str, Any]] = []

        # Account Selection Components
        self.selected_account_id: Optional[int] = None
        self.account_dropdown = ft.Dropdown(
            label="Target Account",
            width=300,
        )
        # attach handler after construction because Dropdown constructor may not accept on_change as a parameter
        setattr(self.account_dropdown, "on_change", self._on_account_change)
        self.new_account_name = ft.TextField(
            label="New Account Name",
            width=300,
            visible=False,
            on_change=self._validate_import_readiness,
        )
        self.account_container = ft.Column(
            [
                ft.Text("Account Selection", weight=ft.FontWeight.BOLD),
                self.account_dropdown,
                self.new_account_name,
            ]
        )

        # Mapping Components
        self.column_mappers: List[ft.Dropdown] = []
        self.csv_headers: List[str] = []

        # UI Components
        self.status_text = ft.Text("No file selected", color=ft.Colors.GREY)

        # Initialize with at least one column to avoid "ValueError" if accidentally shown
        self.preview_table = ft.DataTable(
            columns=[ft.DataColumn(label=ft.Text("Preview"))],
            rows=[],
            visible=False,
            heading_row_height=80,
        )

        self.import_btn = ft.ElevatedButton(
            "Confirm Import",
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._import_data,
            disabled=True,
            style=ft.ButtonStyle(
                bgcolor=PeadraTheme.PRIMARY_MEDIUM
                if is_dark
                else PeadraTheme.PRIMARY_LIGHT,
                color=ft.Colors.WHITE,
            ),
        )

        self.cancel_btn = ft.TextButton("Cancel", on_click=self._close_dialog)

        # Dialog
        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Import Transactions"),
            content=ft.Container(content=self._build_content(), width=700, padding=10),
            actions=[
                self.cancel_btn,
                self.import_btn,
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

    def _build_content(self) -> ft.Column:
        return ft.Column(
            [
                ft.Text(
                    "Select a CSV file to import your bank transactions.",
                    size=14,
                    color=ft.Colors.GREY,
                ),
                ft.Container(height=10),
                
                # File Selection
                ft.Row(
                    [
                        ft.ElevatedButton(
                            "Select File",
                            icon=ft.Icons.FOLDER_OPEN,
                            on_click=self._on_pick_files,
                        ),
                        ft.Container(width=10),
                        ft.Container(content=self.status_text, expand=True),
                    ],
                ),
                
                ft.Container(height=20),
                
                # Preview Area
                ft.Column(
                    [
                        ft.Text("Preview", weight=ft.FontWeight.BOLD),
                        ft.Container(
                            content=ft.Row(
                                [
                                    ft.Column(
                                        [self.preview_table],
                                        scroll=ft.ScrollMode.ADAPTIVE,
                                    )
                                ],
                                scroll=ft.ScrollMode.ADAPTIVE,
                            ),
                            height=200,  # Constrain height
                            border=ft.border.all(
                                1, ft.Colors.with_opacity(0.2, ft.Colors.GREY)
                            ),
                            border_radius=5,
                        ),
                    ]
                ),
                ft.Container(height=20),
                
                # Account Selection
                self.account_container,
                
                ft.Container(height=20),
                # Mapping Area removed - now integrated in Preview
            ],
            tight=True,
            scroll=ft.ScrollMode.AUTO,
        )

    def open(self):
        """Ouvre la boîte de dialogue."""
        self._load_accounts()
        self.page.show_dialog(self.dialog)
        self.page.update()

    def _load_accounts(self):
        """Charge la liste des comptes."""
        accounts = db.get_all_categories()
        options = [
            ft.dropdown.Option(key=str(acc["id"]), text=acc["name"]) for acc in accounts
        ]
        options.append(ft.dropdown.Option(key="new", text="+ Create New Account"))

        self.account_dropdown.options = options
        # Select first account by default if available and not set
        if accounts and not self.account_dropdown.value:
            self.account_dropdown.value = str(accounts[0]["id"])
            self.selected_account_id = accounts[0]["id"]

    def _on_account_change(self, e):
        """Gère le changement de compte."""
        val = self.account_dropdown.value
        if val == "new":
            self.new_account_name.visible = True
            self.selected_account_id = None
        else:
            self.new_account_name.visible = False
            self.selected_account_id = int(val) if val else None

        self.page.update()
        self._validate_import_readiness(None)

    def _validate_import_readiness(self, _):
        """Vérifie si tout est prêt pour l'import (compte + mapping)."""
        # Check Account
        account_ready = False
        if self.account_dropdown.value == "new":
            account_ready = bool(
                self.new_account_name.value and self.new_account_name.value.strip()
            )
        else:
            account_ready = self.account_dropdown.value is not None

        # Check Mapping
        mapping_ready = False
        if self.column_mappers:
            # Check if we have at least one Date, Description and Amount
            mapped_values = [dd.value for dd in self.column_mappers if dd.value]
            has_date = "Date" in mapped_values
            has_desc = "Description" in mapped_values
            has_amount = "Amount" in mapped_values
            mapping_ready = has_date and has_desc and has_amount

        # Only enable if file is loaded AND account valid AND mapping valid
        self.import_btn.disabled = not (
            self.preview_table.visible and account_ready and mapping_ready
        )
        self.page.update()

    def _close_dialog(self, e):
        """Ferme la boîte de dialogue."""
        self.dialog.open = False
        self.page.update()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
        # Update button color if needed
        if self.import_btn.style:
            self.import_btn.style.bgcolor = (
                PeadraTheme.PRIMARY_MEDIUM if is_dark else PeadraTheme.PRIMARY_LIGHT
            )
        self.page.update()

    def _on_pick_files(self, _):
        """Ouvre le sélecteur de fichiers personnalisé."""
        self.dialog.open = False
        self.page.update()
        self.custom_file_picker.open()

    def _on_custom_picker_cancel(self):
        """Callback quand le picker est annulé."""
        self.page.show_dialog(self.dialog)
        self.page.update()

    def _on_custom_file_selected(self, file_path: str):
        """Callback quand un fichier est choisi."""
        self.page.show_dialog(self.dialog)

        self.current_file_path = file_path
        self.status_text.value = os.path.basename(file_path)
        self.status_text.color = ft.Colors.ON_SURFACE
        self.status_text.update()

        self._parse_preview(file_path)
        self.dialog.update()

    def _parse_preview(self, file_path: str):
        """Lit le fichier CSV et prépare l'aperçu."""
        try:
            # We use a simple read first to infer dialect
            with open(file_path, "r", encoding="utf-8", newline="") as f:
                sample = f.read(2048)
                f.seek(0)
                try:
                    dialect = csv.Sniffer().sniff(sample)
                    has_header = csv.Sniffer().has_header(sample)
                except csv.Error:
                    # Fallback if sniffing fails
                    dialect = "excel"
                    has_header = True

                reader = csv.reader(f, dialect)
                header = next(reader) if has_header else None

                rows = []
                for i, row in enumerate(reader):
                    if i >= 5:
                        break
                    rows.append(row)

            # Build DataTable columns with Mapping Dropdowns
            columns = []
            self.column_mappers = []  # Reset mappers

            if header:
                for col in header:
                    columns.append(
                        ft.DataColumn(label=self._create_header_content(str(col)))
                    )
            elif rows:
                for i in range(len(rows[0])):
                    columns.append(
                        ft.DataColumn(label=self._create_header_content(f"Col {i + 1}"))
                    )
            else:
                # No data
                self.preview_table.visible = False
                return

            # Build DataTable rows
            dt_rows = []
            for row in rows:
                cells = [ft.DataCell(ft.Text(str(cell))) for cell in row]
                dt_rows.append(ft.DataRow(cells=cells))

            self.preview_table.columns = columns
            self.preview_table.rows = dt_rows
            self.preview_table.visible = True

            self.import_btn.disabled = True  # Wait for valid mapping
            self.import_btn.update()

            self._validate_import_readiness(None)  # Check initial state

            # Prepare config for later
            self.current_csv_config = {
                "path": file_path,
                "dialect": dialect,
                "has_header": has_header,
            }

        except Exception as ex:
            self.status_text.value = f"Error: {str(ex)}"
            self.status_text.color = PeadraTheme.ERROR
            self.import_btn.disabled = True
            self.preview_table.visible = False
            self.preview_table.visible = False
            # self.mapping_container.visible = False # Removed
            self.page.update()

    def _create_header_content(self, header_text: str) -> ft.Column:
        """Crée le contenu de l'en-tête avec le dropdown de mapping."""
        # Mapping options
        options = ["Unused", "Date", "Description", "Amount"]

        # Auto-select logic
        selected_val = "Unused"
        lower_header = header_text.lower()
        if "date" in lower_header or "time" in lower_header:
            selected_val = "Date"
        elif (
            "desc" in lower_header
            or "label" in lower_header
            or "libelle" in lower_header
            or "objet" in lower_header
        ):
            selected_val = "Description"
        elif (
            "amount" in lower_header
            or "value" in lower_header
            or "montant" in lower_header
            or "solde" in lower_header
        ):
            selected_val = "Amount"

        dd = ft.Dropdown(
            label=header_text,
            options=[ft.dropdown.Option(opt) for opt in options],
            value=selected_val,
            text_size=13,
            height=45,
            content_padding=10,
            width=140,
        )
        setattr(dd, "on_change", self._validate_import_readiness)
        self.column_mappers.append(dd)

        return ft.Column(
            controls=[ft.Container(content=dd, padding=ft.padding.only(top=5))]
        )

    def _setup_mapping_ui(self, columns: List[ft.DataColumn]):
        """Deprecated - Logic moved to _parse_preview and _create_header_content."""
        pass

    # Legacy method replaced by _validate_import_readiness
    def _validate_mapping(self, _):
        self._validate_import_readiness(_)

    def _prepare_transactions(self):
        """Lit tout le fichier et map les données vers le format DB."""
        if not hasattr(self, "current_csv_config"):
            return

        file_path = self.current_csv_config["path"]
        dialect = self.current_csv_config["dialect"]
        has_header = self.current_csv_config["has_header"]

        # Get mapping indices
        mapping: Dict[str, int] = {}

        for idx, dd in enumerate(self.column_mappers):
            val = dd.value
            if val == "Date":
                mapping["date"] = idx
            elif val == "Description":
                mapping["description"] = idx
            elif val == "Amount":
                mapping["amount"] = idx

        # Ensure we have all required mappings
        if len(mapping) < 3:
            print("Missing mapping configuration")
            return

        self.parsed_transactions = []
        try:
            with open(file_path, "r", encoding="utf-8", newline="") as f:
                reader = csv.reader(f, dialect)
                if has_header:
                    try:
                        next(reader)
                    except StopIteration:
                        pass

                for row in reader:
                    # Check if row has enough columns for our max index
                    max_idx = max(mapping.values())
                    if len(row) <= max_idx:
                        continue

                    try:
                        date_str = row[mapping["date"]]
                        desc = row[mapping["description"]]
                        amount_str = row[mapping["amount"]]

                        amount = float(
                            amount_str.replace("€", "")
                            .replace(",", ".")
                            .replace(" ", "")
                        )

                        t_type = "expense"
                        if amount > 0:
                            t_type = "income"
                        else:
                            amount = abs(amount)

                        self.parsed_transactions.append(
                            {
                                "date": date_str,
                                "description": desc,
                                "amount": amount,
                                "type": t_type,
                            }
                        )
                    except ValueError:
                        continue
        except Exception as e:
            print(f"Preparation error: {e}")

    def _import_data(self, _):
        """Insère les données dans la base."""
        self.import_btn.disabled = True
        self.import_btn.content = ft.Text("Processing...", color=ft.Colors.WHITE)
        self.page.update()

        # Handle New Account Creation
        if self.account_dropdown.value == "new":
            name = self.new_account_name.value
            # Basic defaults
            new_id = db.add_category(name, "#9E9E9E", "savings")
            if new_id and new_id > 0:
                self.selected_account_id = new_id
            else:
                self.status_text.value = "Error creating account"
                self.import_btn.content = ft.Text("Confirm Import")
                self.import_btn.disabled = False
                self.page.update()
                return

        # Parse now that we have mapping
        self._prepare_transactions()

        count = 0
        for t in self.parsed_transactions:
            try:
                # Try common formats
                date_iso = None
                for fmt in ["%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%Y-%m-%d %H:%M:%S"]:
                    try:
                        dt = datetime.strptime(t["date"], fmt)
                        date_iso = dt.strftime("%Y-%m-%d")
                        break
                    except ValueError:
                        continue

                if not date_iso:
                    # Fallback or skip? For now, use today if failed parsing
                    # date_iso = datetime.now().strftime("%Y-%m-%d")
                    continue  # Skip invalid dates

                db.add_transaction(
                    date=date_iso,
                    description=t["description"],
                    amount=t["amount"],
                    transaction_type=t["type"],
                    category_id=self.selected_account_id,
                )
                count += 1
            except Exception as e:
                print(f"Import error: {e}")

        self.dialog.open = False
        self.on_data_change()  # Signal refresh
        self.page.update()

        # Reset UI
        # Use content completely to avoid Pylance errors on text property
        self.import_btn.content = ft.Text("Confirm Import")
        # self.import_btn.text = "Confirm Import" # Avoid Pylance error

        # Close dialog and notify
        self._close_dialog(None)

        # Show snackbar via page overlay
        bg_col = PeadraTheme.SUCCESS
        snack = ft.SnackBar(
            content=ft.Text(
                f"Successfully imported {count} transactions!", color=ft.Colors.WHITE
            ),
            bgcolor=bg_col,
        )
        self.page.overlay.append(snack)
        snack.open = True

        self.on_data_change()
        self.page.update()

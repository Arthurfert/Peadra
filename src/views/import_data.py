"""
Composant modal d'importation de données pour Peadra.
Permet d'importer des transactions depuis un fichier CSV via une boîte de dialogue.
"""

import flet as ft
# import flet_core as fct
from typing import Callable, Optional, List, Dict, Any
import csv
import codecs
from datetime import datetime
from ..components.theme import PeadraTheme
from ..database.db_manager import db


class ImportDialog:
    """Boîte de dialogue d'importation de données."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        
        # File Picker setup (Added to overlay in __init__)
        self.file_picker = ft.FilePicker()
        self.page.overlay.append(self.file_picker)
        
        self.current_file_path: Optional[str] = None
        self.preview_data: List[Dict[str, Any]] = []
        self.parsed_transactions: List[Dict[str, Any]] = []
        
        # UI Components
        self.status_text = ft.Text("No file selected", color=ft.Colors.GREY)
        
        # Initialize with at least one column to avoid "ValueError" if accidentally shown
        self.preview_table = ft.DataTable(
            columns=[ft.DataColumn(label=ft.Text("Preview"))], 
            rows=[], 
            visible=False
        )
        
        self.import_btn = ft.ElevatedButton(
            "Confirm Import",
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._import_data,
            disabled=True,
            style=ft.ButtonStyle(
                bgcolor=PeadraTheme.PRIMARY_MEDIUM if is_dark else PeadraTheme.PRIMARY_LIGHT,
                color=ft.Colors.WHITE,
            )
        )
        
        self.cancel_btn = ft.TextButton("Cancel", on_click=self._close_dialog)

        # Dialog
        self.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Import Transactions"),
            content=ft.Container(
                content=self._build_content(),
                width=700,
                padding=10
            ),
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
                ft.Column([
                    ft.Text("Preview", weight=ft.FontWeight.BOLD),
                    ft.Container(
                        content=ft.Column(
                            [self.preview_table], 
                            scroll=ft.ScrollMode.ADAPTIVE
                        ),
                        height=200, # Constrain height
                        border=ft.border.all(1, ft.Colors.with_opacity(0.2, ft.Colors.GREY)),
                        border_radius=5,
                    )
                ]),
                
            ],
            tight=True,
            scroll=ft.ScrollMode.AUTO
        )

    def open(self):
        """Ouvre la boîte de dialogue."""
        self.page.show_dialog(self.dialog)

    def _close_dialog(self, e):
        """Ferme la boîte de dialogue."""
        self.dialog.open = False
        self.page.update()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
        # Update button color if needed
        if self.import_btn.style:
            self.import_btn.style.bgcolor = PeadraTheme.PRIMARY_MEDIUM if is_dark else PeadraTheme.PRIMARY_LIGHT
        self.page.update()

    async def _on_pick_files(self, _):
        """Ouvre le sélecteur de fichiers."""
        try:
            files = await self.file_picker.pick_files(
                allow_multiple=False,
                allowed_extensions=["csv", "txt"]
            )
            
            if files:
                # Mock event object to reuse existing handler logic
                class FilePickerResultEvent:
                    def __init__(self, f): self.files = f
                self._on_file_picked(FilePickerResultEvent(files))
        except Exception as e:
            print(f"File picker error: {e}")

    def _on_file_picked(self, e):
        """Callback après sélection du fichier."""       
        if not e.files:
            return

        file_path = e.files[0].path
        self.current_file_path = file_path
        self.status_text.value = e.files[0].name
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
                    dialect = 'excel'
                    has_header = True
                
                reader = csv.reader(f, dialect)
                header = next(reader) if has_header else None
                
                rows = []
                for i, row in enumerate(reader):
                    if i >= 5: break
                    rows.append(row)

            # Build DataTable columns
            columns = []
            if header:
                for col in header:
                    columns.append(ft.DataColumn(label=ft.Text(str(col))))
            elif rows:
                for i in range(len(rows[0])):
                    columns.append(ft.DataColumn(label=ft.Text(f"Col {i+1}")))
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
            
            self.import_btn.disabled = False
            
            # Store full data for processing
            self._prepare_transactions(file_path, dialect, has_header)
            
        except Exception as ex:
            self.status_text.value = f"Error: {str(ex)}"
            self.status_text.color = PeadraTheme.ERROR
            self.import_btn.disabled = True
            self.preview_table.visible = False

    def _prepare_transactions(self, file_path: str, dialect, has_header: bool):
        """Lit tout le fichier et map les données vers le format DB."""
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
                    if len(row) < 3: continue
                    try:
                        date_str = row[0]
                        desc = row[1]
                        amount_str = row[2]
                        
                        amount = float(amount_str.replace('€', '').replace(',', '.').replace(' ', ''))
                        
                        t_type = "expense"
                        if amount > 0:
                            t_type = "income"
                        else:
                            amount = abs(amount)
                        
                        self.parsed_transactions.append({
                            "date": date_str,
                            "description": desc,
                            "amount": amount,
                            "type": t_type
                        })
                    except ValueError:
                        continue
        except Exception as e:
            print(f"Preparation error: {e}")

    def _import_data(self, _):
        """Insère les données dans la base."""
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
                    date_iso = datetime.now().strftime("%Y-%m-%d")
                
                db.add_transaction(
                    date=date_iso,
                    description=t["description"],
                    amount=t["amount"],
                    transaction_type=t["type"],
                    category_id=None
                )
                count += 1
            except Exception as e:
                print(f"Import error: {e}")

        # Close dialog and notify
        self._close_dialog(None)
        
        # Show snackbar via page overlay
        bg_col = PeadraTheme.SUCCESS
        snack = ft.SnackBar(
            content=ft.Text(f"Successfully imported {count} transactions!", color=ft.Colors.WHITE),
            bgcolor=bg_col,
        )
        self.page.overlay.append(snack)
        snack.open = True
        
        self.on_data_change()
        self.page.update()

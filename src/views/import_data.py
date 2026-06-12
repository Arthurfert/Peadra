"""
Composant modal d'importation de données pour Peadra.
Permet d'importer des transactions depuis un fichier CSV via une boîte de dialogue.
"""

import logging

import flet as ft

# import flet_core as fct
from typing import Callable, Optional, List, Dict, Any
import csv
import os
import hashlib
from datetime import datetime
from ..components.theme import PeadraTheme

logger = logging.getLogger(__name__)
from ..database import db
from ..i18n import t

CURRENCY_SYMBOLS = ["€", "$", "£", "¥", "CHF", "CA$", "AU$", "R$", "MX$",
                    "NT$", "NZ$", "HK$", "SG$", "₩", "₽", "฿", "₫", "₪",
                    "₦", "₨", "₹", "zł", "Kč", "Ft", "kr", "R", "E£", "﷼",
                    "RM", "₱", "Rp", "CLP$", "DH", "TND", "MAD"]

DATE_FORMATS = [
    "%Y-%m-%d",
    "%Y-%m-%d %H:%M:%S",
    "%d/%m/%Y",
    "%d/%m/%Y %H:%M:%S",
    "%m/%d/%Y",
    "%m/%d/%Y %H:%M:%S",
    "%Y/%m/%d",
    "%d.%m.%Y",
    "%m.%d.%Y",
    "%Y.%m.%d",
    "%d-%m-%Y",
    "%m-%d-%Y",
    "%Y%m%d",
    "%d %m %Y",
    "%d/%m/%y",
    "%d.%m.%y",
]

MAPPING_DATE = "Date"
MAPPING_DESC = "Description"
MAPPING_AMOUNT = "Amount"
MAPPING_CREDIT = "Credit Amount"
MAPPING_DEBIT = "Debit Amount"
MAPPING_TYPE = "Type"
MAPPING_UNUSED = "Unused"

AMOUNT_FIELDS = {MAPPING_AMOUNT, MAPPING_CREDIT, MAPPING_DEBIT}

MAPPING_I18N = {
    MAPPING_UNUSED: "import_mapping_unused",
    MAPPING_DATE: "import_mapping_date",
    MAPPING_DESC: "import_mapping_description",
    MAPPING_AMOUNT: "import_mapping_amount",
    MAPPING_CREDIT: "import_mapping_credit",
    MAPPING_DEBIT: "import_mapping_debit",
    MAPPING_TYPE: "import_mapping_type",
}


def calculate_file_hash(file_path: str) -> str:
    """Calcule le hash SHA256 d'un fichier."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


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

        self.path_text = ft.Text(value=self.current_path, size=12, color=PeadraTheme.text_secondary)
        self.file_list = ft.ListView(expand=True, spacing=2)

        self.dialog = ft.AlertDialog(
            title=ft.Text(t("file_select_file"), color=PeadraTheme.text_secondary),
                content=ft.Container(
                    content=ft.Column(
                        [
                            ft.Row(
                                [
                                    ft.IconButton(
                                        icon=ft.Icons.ARROW_UPWARD,
                                        on_click=self._go_up,
                                        tooltip=t("param_file_go_up"),
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
            actions=[ft.TextButton(t("btn_cancel"), on_click=lambda _: self._cancel())],
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
                        title=ft.Text(folder, color=PeadraTheme.text_secondary),
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
                            color=PeadraTheme.add_color if is_allowed else PeadraTheme.placeholder_color,
                        ),
                        title=ft.Text(
                            file, color=PeadraTheme.text_secondary
                        ),
                        on_click=(
                            (lambda e, p=file: self._select_file(p))
                            if is_allowed
                            else None
                        ),
                        dense=True,
                        disabled=not is_allowed,
                        opacity=1.0 if is_allowed else 0.5,
                    )
                )

        except Exception as e:
            self.file_list.controls.append(
                ft.Text(f"{t('msg_error_file')}: {e}", color=PeadraTheme.text_secondary)
            )

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

        self.custom_file_picker = CustomFilePicker(
            page=self.page,
            on_select=self._on_custom_file_selected,
            on_cancel=self._on_custom_picker_cancel,
            allowed_extensions=["csv"],
        )

        self.current_file_path: Optional[str] = None
        self.current_file_hash: Optional[str] = None
        self.preview_data: List[Dict[str, Any]] = []
        self.parsed_transactions: List[Dict[str, Any]] = []

        self.selected_account_id: Optional[int] = None
        self.account_dropdown = ft.Dropdown(
            label=t("import_target_account"),
            width=300,
        )
        setattr(self.account_dropdown, "on_change", self._on_account_change)
        self.new_account_name = ft.TextField(
            label=t("import_new_account"),
            width=300,
            visible=False,
            on_change=self._validate_import_readiness,
        )
        self.account_container = ft.Column(
            [
                ft.Text(t("import_account_selection"), weight=ft.FontWeight.BOLD, color=PeadraTheme.text_secondary),
                self.account_dropdown,
                self.new_account_name,
            ]
        )

        self.column_mappers: List[ft.Dropdown] = []
        self.csv_headers: List[str] = []

        self.status_text = ft.Text(t("import_no_file"), color=PeadraTheme.text_secondary)

        self.preview_table = ft.DataTable(
            columns=[ft.DataColumn(label=ft.Text(t("import_preview"), color=PeadraTheme.text_secondary))],
            rows=[],
            visible=False,
            heading_row_height=80,
        )

        self.import_btn = ft.ElevatedButton(
            t("btn_confirm_import"),
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._import_data,
            disabled=True,
            style=ft.ButtonStyle(
                bgcolor=(
                    PeadraTheme.primary_medium if is_dark else PeadraTheme.primary_light
                ),
                color=ft.Colors.WHITE,
            ),
        )

        self.cancel_btn = ft.TextButton(t("btn_cancel"), on_click=self._close_dialog)

        self.mapping_help_opened = False
        self.mapping_help_dialog = ft.AlertDialog(
            title=ft.Text(t("import_mapping_help_title"), color=PeadraTheme.text_secondary),
            content=ft.Container(
                content=ft.Column(
                    [
                        ft.Text(f"• {t('import_mapping_help_date')}", color=PeadraTheme.text_secondary),
                        ft.Text(f"• {t('import_mapping_help_description')}", color=PeadraTheme.text_secondary),
                        ft.Text(f"• {t('import_mapping_help_amount')}", color=PeadraTheme.text_secondary),
                        ft.Text(f"• {t('import_mapping_help_credit')}", color=PeadraTheme.text_secondary),
                        ft.Text(f"• {t('import_mapping_help_debit')}", color=PeadraTheme.text_secondary),
                        ft.Text(f"• {t('import_mapping_help_type')}", color=PeadraTheme.text_secondary),
                        ft.Text(f"• {t('import_mapping_help_unused')}", color=PeadraTheme.text_secondary),
                        ft.Divider(height=15),
                        ft.Text(t("import_mapping_help_tip"), italic=True, size=12, color=PeadraTheme.placeholder_color),
                    ],
                    tight=True,
                    scroll=ft.ScrollMode.AUTO,
                ),
                width=400,
                padding=10,
            ),
            actions=[ft.TextButton(t("btn_close"), on_click=self._close_mapping_help)],
        )

        self.dialog = ft.AlertDialog(
            title=ft.Text(t("import_title"), color=PeadraTheme.text_secondary),
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
                    t("import_select_csv_desc"),
                    size=14,
                    color=PeadraTheme.text_secondary,
                ),
                ft.Container(height=10),
                ft.Row(
                    [
                        ft.ElevatedButton(
                            t("import_select_file_btn"),
                            icon=ft.Icons.FOLDER_OPEN,
                            on_click=self._on_pick_files,
                        ),
                        ft.Container(width=10),
                        ft.Container(content=self.status_text, expand=True),
                    ],
                ),
                ft.Container(height=20),
                ft.Column(
                    [
                        ft.Row(
                            [
                                ft.Text(t("import_preview"), weight=ft.FontWeight.BOLD, color=PeadraTheme.text_secondary),
                                ft.IconButton(
                                    icon=ft.Icons.INFO_OUTLINE,
                                    icon_size=16,
                                    icon_color=PeadraTheme.placeholder_color,
                                    on_click=self._show_mapping_help,
                                    tooltip=t("import_mapping_help_title"),
                                ),
                            ],
                            vertical_alignment=ft.CrossAxisAlignment.CENTER,
                        ),
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
                            height=200,
                            border=ft.border.all(
                                1, PeadraTheme.divider
                            ),
                            border_radius=5,
                        ),
                    ]
                ),
                ft.Container(height=20),
                self.account_container,
                ft.Container(height=20),
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
        options.append(
            ft.dropdown.Option(key="new", text=t("import_create_new_account"))
        )

        self.account_dropdown.options = options
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
        account_ready = False
        if self.account_dropdown.value == "new":
            account_ready = bool(
                self.new_account_name.value and self.new_account_name.value.strip()
            )
        else:
            account_ready = self.account_dropdown.value is not None

        mapping_ready = False
        if self.column_mappers:
            mapped_values = [dd.value for dd in self.column_mappers if dd.value]
            has_date = MAPPING_DATE in mapped_values
            has_desc = MAPPING_DESC in mapped_values
            has_amount = any(f in mapped_values for f in AMOUNT_FIELDS)
            mapping_ready = has_date and has_desc and has_amount

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
        if self.import_btn.style:
            self.import_btn.style.bgcolor = (
                PeadraTheme.primary_medium if is_dark else PeadraTheme.primary_light
            )
        self.page.update()

    def _show_mapping_help(self, e):
        self.page.show_dialog(self.mapping_help_dialog)
        self.page.update()

    def _close_mapping_help(self, e):
        self.mapping_help_dialog.open = False
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
        try:
            self.current_file_hash = calculate_file_hash(file_path)
            is_duplicate = db.is_file_imported(self.current_file_hash)
        except Exception as e:
            logger.error("Error checking file hash: %s", e)
            is_duplicate = False

        if is_duplicate:
            self._show_duplicate_warning(file_path)
            return

        self._proceed_with_file_selection(file_path)

    def _show_duplicate_warning(self, file_path: str):
        """Affiche un avertissement si le fichier a déjà été importé."""

        def on_continue(_):
            warning_dialog.open = False
            self.page.update()
            self._proceed_with_file_selection(file_path)

        def on_cancel(_):
            warning_dialog.open = False
            self.page.update()
            self.page.show_dialog(self.dialog)
            self.page.update()

        warning_dialog = ft.AlertDialog(
            title=ft.Text(t("import_duplicate_warning"), color=PeadraTheme.text_secondary),
            content=ft.Text(t("import_duplicate_content"), color=PeadraTheme.text_secondary),
            actions=[
                ft.TextButton(t("btn_cancel"), on_click=on_cancel),
                ft.TextButton(
                    t("import_anyway"),
                    on_click=on_continue,
                    style=ft.ButtonStyle(color=ft.Colors.ERROR),
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        self.page.show_dialog(warning_dialog)
        self.page.update()

    def _proceed_with_file_selection(self, file_path: str):
        """Continue la sélection de fichier après validation."""
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
            with open(file_path, "r", encoding="utf-8", newline="") as f:
                sample = f.read(2048)
                f.seek(0)
                try:
                    dialect = csv.Sniffer().sniff(sample)
                    has_header = csv.Sniffer().has_header(sample)
                except csv.Error:
                    dialect = "excel"
                    has_header = True

                reader = csv.reader(f, dialect)
                header = next(reader) if has_header else None

                rows = []
                for i, row in enumerate(reader):
                    if i >= 5:
                        break
                    rows.append(row)

            columns = []
            self.column_mappers = []

            if header:
                for col in header:
                    columns.append(
                        ft.DataColumn(label=self._create_header_content(str(col)))
                    )
            elif rows:
                for i in range(len(rows[0])):
                    columns.append(
                        ft.DataColumn(
                            label=self._create_header_content(
                                f"{t('import_col_header')} {i + 1}"
                            )
                        )
                    )
            else:
                self.preview_table.visible = False
                return

            dt_rows = []
            for row in rows:
                cells = [ft.DataCell(ft.Text(str(cell))) for cell in row]
                dt_rows.append(ft.DataRow(cells=cells))

            self.preview_table.columns = columns
            self.preview_table.rows = dt_rows
            self.preview_table.visible = True

            self.import_btn.disabled = True
            self.import_btn.update()

            self._validate_import_readiness(None)

            self.current_csv_config = {
                "path": file_path,
                "dialect": dialect,
                "has_header": has_header,
            }

        except Exception as ex:
            self.status_text.value = f"{t('msg_error')}: {str(ex)}"
            self.status_text.color = PeadraTheme.error
            self.import_btn.disabled = True
            self.preview_table.visible = False
            self.page.update()

    def _auto_detect_mapping(self, header_text: str) -> str:
        """Auto-détecte le mapping pour un en-tête donné."""
        lower = header_text.lower()

        if any(kw in lower for kw in ("date", "time", "jour", "datum", "fecha")):
            return MAPPING_DATE

        if any(kw in lower for kw in (
            "desc", "label", "libelle", "objet", "description",
            "narrative", "details", "détails", "memo", "merchant",
            "commerçant", "tiers", "beneficiary", "bénéficiaire",
            "payee", "nom", "name", "reason", "motif",
        )):
            return MAPPING_DESC

        if any(kw in lower for kw in (
            "credit", "crédit", "income", "inflow", "recette",
            "versement", "dépôt", "deposit", "montant crédit",
            "credit amount", "crédit montant", "montant crédité",
            "crédité", "credited", "montant crédit",
        )):
            return MAPPING_CREDIT

        if any(kw in lower for kw in (
            "debit", "débit", "expense", "outflow", "dépense",
            "retrait", "withdrawal", "prélèvement", "montant débit",
            "debit amount", "débit montant", "montant débité",
            "débité", "debited", "charge", "fee", "frais",
            "paiement", "payment", "montant débit",
        )):
            return MAPPING_DEBIT

        if any(kw in lower for kw in (
            "type", "transaction type", "nature", "operation",
            "opération", "cat", "category", "catégorie",
            "movement", "mouvement", "sens", "sign",
            "transaction", "kind",
        )):
            return MAPPING_TYPE

        if any(kw in lower for kw in (
            "amount", "value", "montant", "solde", "sum",
            "total", "prix", "price", "net", "gross", "brut",
        )):
            return MAPPING_AMOUNT

        return MAPPING_UNUSED

    def _create_header_content(self, header_text: str) -> ft.Column:
        """Crée le contenu de l'en-tête avec le dropdown de mapping."""
        options = [
            ft.dropdown.Option(key=val, text=t(key))
            for val, key in MAPPING_I18N.items()
        ]

        selected_val = self._auto_detect_mapping(header_text)

        dd = ft.Dropdown(
            label=header_text,
            options=options,
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

    def _parse_amount(self, raw: str) -> Optional[float]:
        """Parse un montant depuis une chaîne, gérant les formats européens et US."""
        if not raw or not raw.strip():
            return None
        s = raw.strip()

        for sym in CURRENCY_SYMBOLS:
            s = s.replace(sym, "")
        s = s.replace(" ", "").replace("\u00a0", "")

        if not s:
            return None

        negative = False
        if s.startswith("(") and s.endswith(")"):
            s = s[1:-1]
            negative = True
        if s.startswith("-"):
            negative = True
            s = s[1:]
        if s.startswith("+"):
            s = s[1:]

        has_comma = "," in s
        has_dot = "." in s

        if has_comma and has_dot:
            last_comma = s.rindex(",")
            last_dot = s.rindex(".")
            if last_comma > last_dot:
                s = s.replace(".", "").replace(",", ".")
            else:
                s = s.replace(",", "")
        elif has_comma:
            s = s.replace(",", ".")

        try:
            val = float(s)
            return -val if negative else val
        except ValueError:
            return None

    def _parse_type(self, raw: str) -> Optional[str]:
        """Détermine le type de transaction (income/expense) depuis une chaîne."""
        if not raw or not raw.strip():
            return None
        lower = raw.strip().lower()

        income_kw = (
            "credit", "crédit", "income", "revenu", "inflow",
            "deposit", "versement", "recette", "virement reçu",
            "c", "cr", "+", "1", "true",
        )
        expense_kw = (
            "debit", "débit", "expense", "dépense", "outflow",
            "withdrawal", "retrait", "prélèvement", "charge",
            "paiement", "achat", "virement émis", "d", "db",
            "-", "0", "false",
        )

        if lower in income_kw:
            return "income"
        if lower in expense_kw:
            return "expense"
        if lower.startswith("c") or lower.startswith("crédit") or lower.startswith("credit"):
            return "income"
        if lower.startswith("d") or lower.startswith("débit") or lower.startswith("debit"):
            return "expense"
        return None

    def _prepare_transactions(self):
        """Lit tout le fichier et map les données vers le format DB."""
        if not hasattr(self, "current_csv_config"):
            return

        file_path = self.current_csv_config["path"]
        dialect = self.current_csv_config["dialect"]
        has_header = self.current_csv_config["has_header"]

        mapping: Dict[str, int] = {}

        for idx, dd in enumerate(self.column_mappers):
            val = dd.value
            if val == MAPPING_DATE:
                mapping["date"] = idx
            elif val == MAPPING_DESC:
                mapping["description"] = idx
            elif val == MAPPING_AMOUNT:
                mapping["amount"] = idx
            elif val == MAPPING_CREDIT:
                mapping["credit"] = idx
            elif val == MAPPING_DEBIT:
                mapping["debit"] = idx
            elif val == MAPPING_TYPE:
                mapping["type"] = idx

        if "date" not in mapping or "description" not in mapping:
            logger.warning("Missing required mapping (date, description)")
            return
        has_any_amount = any(k in mapping for k in ("amount", "credit", "debit"))
        if not has_any_amount:
            logger.warning("Missing amount mapping")
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
                    max_idx = max(mapping.values())
                    if len(row) <= max_idx:
                        continue

                    try:
                        date_str = row[mapping["date"]]
                        desc = row[mapping["description"]]
                    except (IndexError, KeyError):
                        continue

                    amount = None
                    t_type = None

                    has_amount_col = "amount" in mapping
                    has_credit_col = "credit" in mapping
                    has_debit_col = "debit" in mapping
                    has_type_col = "type" in mapping

                    if has_amount_col and not has_credit_col and not has_debit_col:
                        raw_amount = self._parse_amount(row[mapping["amount"]])
                        if raw_amount is None:
                            continue
                        if raw_amount > 0:
                            t_type = "income"
                        else:
                            t_type = "expense"
                        amount = abs(raw_amount)

                    elif has_credit_col or has_debit_col:
                        credit_val = None
                        debit_val = None
                        if has_credit_col:
                            credit_val = self._parse_amount(row[mapping["credit"]])
                        if has_debit_col:
                            debit_val = self._parse_amount(row[mapping["debit"]])

                        if credit_val is not None and credit_val != 0:
                            amount = abs(credit_val)
                            t_type = "income" if not has_type_col else None
                        elif debit_val is not None and debit_val != 0:
                            amount = abs(debit_val)
                            t_type = "expense" if not has_type_col else None
                        else:
                            continue

                    elif has_type_col:
                        parsed_type = self._parse_type(row[mapping["type"]])
                        if parsed_type is None:
                            continue
                        t_type = parsed_type
                        if has_amount_col:
                            raw = self._parse_amount(row[mapping["amount"]])
                            if raw is None:
                                continue
                            amount = abs(raw)

                    if t_type is None and has_type_col:
                        parsed_type = self._parse_type(row[mapping["type"]])
                        if parsed_type:
                            t_type = parsed_type

                    if t_type is None:
                        if amount is None:
                            continue
                        t_type = "income" if amount > 0 else "expense"
                        amount = abs(amount)

                    if amount is None:
                        continue

                    self.parsed_transactions.append(
                        {
                            "date": date_str,
                            "description": desc,
                            "amount": amount,
                            "type": t_type,
                        }
                    )
        except Exception as e:
            logger.error("Preparation error: %s", e)

    def _import_data(self, _):
        """Insère les données dans la base."""
        self.import_btn.disabled = True
        self.import_btn.content = ft.Text(t("import_processing"), color=ft.Colors.WHITE)
        self.page.update()

        if self.account_dropdown.value == "new":
            name = self.new_account_name.value
            new_id = db.add_category(name, "#9E9E9E", "savings")
            if new_id and new_id > 0:
                self.selected_account_id = new_id
            else:
                self.status_text.value = t("import_error_account")
                self.import_btn.content = ft.Text(t("btn_confirm_import"))
                self.import_btn.disabled = False
                self.page.update()
                return

        self._prepare_transactions()

        count = 0
        for parsed_trans in self.parsed_transactions:
            try:
                date_iso = None
                for fmt in DATE_FORMATS:
                    try:
                        dt = datetime.strptime(parsed_trans["date"], fmt)
                        date_iso = dt.strftime("%Y-%m-%d")
                        break
                    except ValueError:
                        continue

                if not date_iso:
                    continue

                db.add_transaction(
                    date=date_iso,
                    description=parsed_trans["description"],
                    amount=parsed_trans["amount"],
                    transaction_type=parsed_trans["type"],
                    category_id=self.selected_account_id,
                )
                count += 1
            except Exception as e:
                logger.error("Import error: %s", e)

        if self.current_file_hash and self.current_file_path:
            db.log_imported_file(
                self.current_file_hash, os.path.basename(self.current_file_path)
            )

        self.dialog.open = False
        self.on_data_change()
        self.page.update()

        self.import_btn.content = ft.Text(t("btn_confirm_import"))

        self._close_dialog(None)

        bg_col = PeadraTheme.success
        snack = ft.SnackBar(
            content=ft.Text(
                t("import_success").format(count=count), color=ft.Colors.WHITE
            ),
            bgcolor=bg_col,
        )
        self.page.overlay.append(snack)
        snack.open = True

        self.on_data_change()
        self.page.update()

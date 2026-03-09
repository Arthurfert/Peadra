"""
Vue Paramètres pour Peadra.
Permet de configurer le thème, l'import/export et le mode de calcul mensuel.
"""

import flet as ft
from typing import Callable, Any, cast, List
from ..components.theme import PeadraTheme
from ..database import db


class ParametersView:
    """Vue des paramètres de l'application."""

    def __init__(
        self,
        page: ft.Page,
        is_dark: bool,
        on_data_change: Callable,
        on_toggle_theme: Callable,
        on_import: Callable,
        on_export: Callable,
    ):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.on_toggle_theme = on_toggle_theme
        self.on_import = on_import
        self.on_export = on_export
        # Charger le mode depuis la base de données
        self.month_mode = db.get_setting("month_mode", "strict") or "strict"

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit la vue."""
        pass

    def get_month_mode(self) -> str:
        """Retourne le mode de mois actuel."""
        return self.month_mode

    def _build_section_card(
        self, title: str, icon: Any, children: List[ft.Control]
    ) -> ft.Container:
        """Construit une carte de section de paramètres."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Icon(cast(Any, icon), color=PeadraTheme.ACCENT, size=24),
                            ft.Text(
                                title,
                                size=18,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        spacing=12,
                    ),
                    ft.Divider(
                        height=1,
                        color=ft.Colors.with_opacity(0.1, ft.Colors.ON_SURFACE),
                    ),
                    ft.Container(height=8),
                    *children,
                ],
                spacing=8,
            ),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            border=(
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_setting_row(
        self,
        label: str,
        description: str,
        control: ft.Control,
    ) -> ft.Container:
        """Construit une ligne de paramètre."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        return ft.Container(
            content=ft.Row(
                [
                    ft.Column(
                        [
                            ft.Text(
                                label,
                                size=15,
                                weight=ft.FontWeight.W_500,
                                color=text_color,
                            ),
                            ft.Text(
                                description,
                                size=12,
                                color=ft.Colors.GREY,
                            ),
                        ],
                        spacing=2,
                        expand=True,
                    ),
                    control,
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            padding=ft.padding.symmetric(vertical=8, horizontal=4),
        )

    def _on_theme_change(self, e):
        """Gère le changement de thème."""
        self.on_toggle_theme(e)

    def _on_month_mode_change(self, e):
        """Gère le changement de mode mois."""
        selected = list(e.control.selected)
        if selected:
            self.month_mode = selected[0]
            # Sauvegarder dans la base de données
            db.set_setting("month_mode", self.month_mode)
            self.on_data_change()

    def _on_export_json(self, e):
        """Lance l'export JSON."""
        self.on_export(e, "json")

    def _on_export_csv(self, e):
        """Lance l'export CSV."""
        self.on_export(e, "csv")

    def _on_import_csv(self, e):
        """Lance l'import CSV."""
        self.on_import()

    def build(self) -> ft.Container:
        """Construit la vue paramètres."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        # === Section Apparence ===
        theme_switch = ft.Switch(
            value=self.is_dark,
            active_color=PeadraTheme.ACCENT,
            on_change=self._on_theme_change,
        )

        appearance_section = self._build_section_card(
            "Appearance",
            ft.Icons.PALETTE_OUTLINED,
            [
                self._build_setting_row(
                    "Dark mode",
                    "Switch between light and dark theme.",
                    theme_switch,
                ),
            ],
        )

        # === Section Données ===
        import_btn = ft.ElevatedButton(
            content="Import CSV",
            icon=ft.Icons.UPLOAD_FILE,
            on_click=self._on_import_csv,
            style=ft.ButtonStyle(
                bgcolor=PeadraTheme.ACCENT,
                color=ft.Colors.WHITE,
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
            ),
        )

        export_json_btn = ft.OutlinedButton(
            content="Export JSON",
            icon=ft.Icons.DATA_OBJECT,
            on_click=self._on_export_json,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.ACCENT),
                color=PeadraTheme.ACCENT,
            ),
        )

        export_csv_btn = ft.OutlinedButton(
            content=ft.Row(
                [ft.Icon(ft.Icons.TABLE_CHART, size=18), ft.Text("Export CSV")],
                spacing=8,
            ),
            on_click=self._on_export_csv,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=20, vertical=12),
                shape=ft.RoundedRectangleBorder(radius=10),
                side=ft.BorderSide(1, PeadraTheme.ACCENT),
                color=PeadraTheme.ACCENT,
            ),
        )

        data_section = self._build_section_card(
            "Data",
            ft.Icons.STORAGE_OUTLINED,
            [
                self._build_setting_row(
                    "Import",
                    "Import transactions from a CSV file.",
                    import_btn,
                ),
                self._build_setting_row(
                    "Export",
                    "Export your data in JSON or CSV format.",
                    ft.Row([export_json_btn, export_csv_btn], spacing=10),
                ),
            ],
        )

        # === Section Graphiques ===
        month_mode_selector = ft.SegmentedButton(
            selected=[self.month_mode],
            on_change=self._on_month_mode_change,
            segments=[
                ft.Segment(
                    value="strict",
                    label=ft.Text("Calendar month"),
                    icon=ft.Icon(ft.Icons.CALENDAR_MONTH),
                ),
                ft.Segment(
                    value="rolling",
                    label=ft.Text("Rolling 30 days"),
                    icon=ft.Icon(ft.Icons.UPDATE),
                ),
            ],
            show_selected_icon=False,
            style=ft.ButtonStyle(
                padding=ft.padding.symmetric(horizontal=16, vertical=8),
            ),
        )

        charts_section = self._build_section_card(
            "Charts",
            ft.Icons.BAR_CHART_OUTLINED,
            [
                self._build_setting_row(
                    "Month calculation mode",
                    "Calendar month: Jan 1-31. Rolling: last 30 days from today.",
                    month_mode_selector,
                ),
            ],
        )

        # === Layout principal ===
        content = ft.Column(
            [
                ft.Container(
                    content=ft.Column(
                        [
                            ft.Text(
                                "Parameters",
                                size=32,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.Text(
                                "Customize your experience.",
                                size=16,
                                color=ft.Colors.GREY,
                            ),
                        ],
                        spacing=4,
                    ),
                    margin=ft.margin.only(bottom=20),
                ),
                appearance_section,
                ft.Container(height=12),
                data_section,
                ft.Container(height=12),
                charts_section,
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=0,
        )

        return ft.Container(
            content=content,
            padding=30,
            expand=True,
            alignment=ft.Alignment.TOP_RIGHT,
        )

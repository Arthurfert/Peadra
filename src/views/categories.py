"""
Vue Catégories pour Peadra.
Affiche les graphiques linéaires par catégories avec les plus importantes dépenses et revenus.
"""

import flet as ft
import flet_charts as fch
import math
from typing import Callable, List, Dict, Any, Optional, cast
from datetime import datetime, timedelta
from ..components.theme import PeadraTheme
from ..database import db
from ..i18n import t


class CategoriesView:
    """Vue des catégories avec line charts."""

    def __init__(
        self,
        page: ft.Page,
        is_dark: bool,
        on_data_change: Callable,
    ):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.chart_duration = 6
        self.content_container: Optional[ft.Container] = None
        self.category_monthly_data: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()

    def _load_data(self):
        """Charge les données des catégories."""
        self.currency = db.get_setting("currency", "€") or "€"
        
        # Récupérer les catégories les plus importantes
        now = datetime.now()
        num_months = int(self.chart_duration)
        start_date = (now - timedelta(days=num_months * 30)).strftime("%Y-%m-%d")
        end_date = now.strftime("%Y-%m-%d")
        
        # récupérer les descriptions les plus importantes (par montant)
        self.top_expenses = db.get_top_descriptions("expense", num_months)
        self.top_incomes = db.get_top_descriptions("income", num_months)

        # Récupérer les données mensuelles par description
        self.category_monthly_data = db.get_description_monthly_data(start_date, end_date)

    def build(self) -> ft.Container:
        """Construit la vue des catégories."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = (
            PeadraTheme.DARK_BG if self.is_dark else PeadraTheme.LIGHT_BG
        )
        
        # Titre principal
        title = ft.Text(
            t("nav_categories") if hasattr(t, "__call__") else "Catégories",
            size=32,
            weight=ft.FontWeight.BOLD,
            color=text_color,
        )
        
        # Contrôles de durée
        duration_controls = self._build_duration_controls()
        
        # Sections dépenses et revenus
        content_column = ft.Column(
            spacing=24,
            expand=True,
            scroll=ft.ScrollMode.AUTO,
        )
        
        # Section Dépenses (par description)
        if self.top_expenses:
            content_column.controls.append(
                self._build_category_section(
                    "Descriptions de dépenses les plus importantes",
                    self.top_expenses,
                    "#E53935",
                )
            )

            # Ajouter les charts pour les descriptions de dépenses
            for item in self.top_expenses[:3]:
                desc = str(item.get("description") or "").strip()
                chart = self._build_category_chart(desc, "expense")
                if chart:
                    content_column.controls.append(chart)
        
        # Section Revenus (par description)
        if self.top_incomes:
            content_column.controls.append(
                self._build_category_section(
                    "Descriptions de revenus les plus importantes",
                    self.top_incomes,
                    "#4CAF50",
                )
            )

            # Ajouter les charts pour les descriptions de revenus
            for item in self.top_incomes[:3]:
                desc = str(item.get("description") or "").strip()
                chart = self._build_category_chart(desc, "income")
                if chart:
                    content_column.controls.append(chart)
        
        # Exposer le container principal pour mise à jour ultérieure
        self.content_container = ft.Container(content=content_column, expand=True)

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row([title], alignment=ft.MainAxisAlignment.START),
                    duration_controls,
                    ft.Divider(),
                    self.content_container,
                ],
                spacing=20,
                expand=True,
            ),
            padding=24,
            bgcolor=bg_color,
            expand=True,
        )

    def _build_duration_controls(self) -> ft.Row:
        """Construit les contrôles de sélection de durée."""
        def on_duration_change(e):
            sel = list(e.control.selected)
            if not sel:
                return
            selected_duration = sel[0]
            try:
                self.chart_duration = int(selected_duration)
            except Exception:
                self.chart_duration = selected_duration
            self._load_data()
            if self.content_container is not None:
                # simple rafraîchissement de l'UI
                self.page.update()

        return ft.Row(
            cast(
                List[ft.Control],
                [
                    ft.Text("Période:", size=14, weight=ft.FontWeight.W_600),
                    ft.SegmentedButton(
                        segments=[
                            ft.Segment(value="3", label=ft.Text("3 mois")),
                            ft.Segment(value="6", label=ft.Text("6 mois")),
                            ft.Segment(value="12", label=ft.Text("1 an")),
                        ],
                        selected=[str(self.chart_duration)],
                        on_change=on_duration_change,
                        allow_empty_selection=False,
                    ),
                ],
            ),
            spacing=12,
            alignment=ft.MainAxisAlignment.START,
        )

    def _build_category_section(
        self, title: str, categories: List[Dict[str, Any]], color: str
    ) -> ft.Container:
        """Construit une section de catégories."""
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        items = []
        for idx, category in enumerate(categories, 1):
            items.append(
                ft.ListTile(
                    leading=ft.Container(
                        content=ft.Text(
                            str(idx),
                            color=ft.Colors.WHITE,
                            weight=ft.FontWeight.BOLD,
                            size=12,
                        ),
                        bgcolor=color,
                        padding=8,
                        border_radius=50,
                        alignment=ft.Alignment.CENTER,
                        width=32,
                        height=32,
                    ),
                    title=ft.Text(
                        (category.get("description") or "").capitalize(),
                        size=14,
                        weight=ft.FontWeight.W_500,
                        color=text_color,
                    ),
                    subtitle=ft.Text(
                        f"{category['count']} transactions",
                        size=12,
                        color=ft.Colors.GREY_500,
                    ),
                    trailing=ft.Text(
                        f"{category['total']:,.2f} {self.currency}",
                        size=14,
                        weight=ft.FontWeight.W_600,
                        color=color,
                    ),
                )
            )
        
        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(title, size=18, weight=ft.FontWeight.BOLD),
                    ft.Column(items, spacing=8),
                ],
                spacing=12,
            ),
            padding=20,
            bgcolor=bg_card,
            border_radius=16,
            border=(
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_category_chart(
        self, description_name: str, transaction_type: str
    ) -> Optional[ft.Container]:
        """Construit un line chart pour une description."""
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        if description_name not in self.category_monthly_data:
            return None

        category_data = self.category_monthly_data[description_name]
        
        # Récupérer les mois et les montants
        months = sorted(category_data.keys())
        if not months:
            return None
        
        # Préparer les données pour le graphique
        values = []
        month_labels = []
        
        for month_str in months:
            if transaction_type == "expense":
                value = category_data[month_str].get("expense", 0)
            else:
                value = category_data[month_str].get("income", 0)
            values.append(max(0, value))
            
            # Formater le label du mois
            try:
                dt = datetime.strptime(month_str, "%Y-%m")
                month_labels.append(dt.strftime("%b"))
            except:
                month_labels.append(month_str[-2:])
        
        if not values or all(v == 0 for v in values):
            return None
        
        # Déterminer la couleur
        line_color = "#E53935" if transaction_type == "expense" else "#4CAF50"
        
        # Créer les points du graphique via LineChartDataPoint
        points = [fch.LineChartDataPoint(i, float(v)) for i, v in enumerate(values)]

        max_y = max(values) * 1.1 if values else 100

        chart = fch.LineChart(
            data_series=[
                fch.LineChartData(
                    points=points,
                    stroke_width=3,
                    color=line_color,
                    curved=True,
                    rounded_stroke_cap=True,
                )
            ],
            border=ft.border.all(0, ft.Colors.TRANSPARENT),
            horizontal_grid_lines=fch.ChartGridLines(
                interval=max(1, int(max_y / 4)),
                color=ft.Colors.with_opacity(0.1, ft.Colors.GREY),
                width=1,
            ),
            vertical_grid_lines=fch.ChartGridLines(interval=1, color=ft.Colors.TRANSPARENT),
            left_axis=fch.ChartAxis(label_size=12, title_size=0, show_labels=True),
            bottom_axis=fch.ChartAxis(
                labels=[
                    fch.ChartAxisLabel(
                        value=i,
                        label=ft.Container(ft.Text(label, size=10, color=text_color), padding=4),
                    )
                    for i, label in enumerate(month_labels)
                ],
                label_size=10,
                show_labels=True,
            ),
            min_x=0,
            max_x=float(len(values) - 1) if len(values) > 1 else 1,
            min_y=0,
            max_y=max_y,
            expand=True,
            tooltip=fch.LineChartTooltip(bgcolor=PeadraTheme.SURFACE),
        )
        
        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(
                        f"{(description_name or '').capitalize()} - {'Dépenses' if transaction_type == 'expense' else 'Revenus'}",
                        size=14,
                        weight=ft.FontWeight.W_600,
                        color=text_color,
                    ),
                    ft.Container(
                        content=chart,
                        height=250,
                        padding=10,
                    ),
                ],
                spacing=12,
            ),
            padding=20,
            bgcolor=bg_card,
            border_radius=16,
            border=(
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

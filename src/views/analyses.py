"""
Vue Analyses pour Peadra.
Graphiques détaillés du patrimoine et des transactions.
"""
import flet as ft
from typing import Callable
from datetime import datetime, timedelta
from ..components.theme import PeadraTheme
from ..database.db_manager import db


class AnalysesView:
    """Vue des analyses avec graphiques."""
    
    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.selected_period = "12"  # mois
        self._load_data()
    
    def _load_data(self):
        """Charge les données pour les analyses."""
        self.patrimony_by_category = db.get_patrimony_by_category()
        self.total_patrimony = db.get_total_patrimony()
        self.patrimony_evolution = db.get_patrimony_evolution(int(self.selected_period))
        self.transactions = db.get_all_transactions()
        self.monthly_summary = db.get_monthly_summary()
        
        # Calculer les dépenses par catégorie
        self._calculate_expenses_by_category()
        
        # Calculer l'évolution mensuelle des transactions
        self._calculate_monthly_transactions()
    
    def _calculate_expenses_by_category(self):
        """Calcule les dépenses par catégorie."""
        expenses_by_cat = {}
        for tx in self.transactions:
            if tx["transaction_type"] == "expense":
                cat_name = tx.get("category_name", "Non catégorisé")
                if cat_name not in expenses_by_cat:
                    expenses_by_cat[cat_name] = {
                        "total": 0,
                        "icon": "",
                        "color": "#778DA9",
                    }
                expenses_by_cat[cat_name]["total"] += tx["amount"]
        
        self.expenses_by_category = list(expenses_by_cat.items())
        self.expenses_by_category.sort(key=lambda x: x[1]["total"], reverse=True)
    
    def _calculate_monthly_transactions(self):
        """Calcule les transactions par mois."""
        monthly_data = {}
        
        for tx in self.transactions:
            month = tx["date"][:7]  # YYYY-MM
            if month not in monthly_data:
                monthly_data[month] = {"income": 0, "expense": 0}
            
            if tx["transaction_type"] == "income":
                monthly_data[month]["income"] += tx["amount"]
            elif tx["transaction_type"] == "expense":
                monthly_data[month]["expense"] += tx["amount"]
        
        # Trier par mois
        sorted_months = sorted(monthly_data.keys())[-int(self.selected_period):]
        self.monthly_transactions = [(m, monthly_data[m]) for m in sorted_months]
    
    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
    
    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()
    
    def _on_period_change(self, e):
        """Gère le changement de période."""
        self.selected_period = e.control.value
        self._load_data()
        self.on_data_change()
    
    def _build_period_selector(self) -> ft.Container:
        """Construit le sélecteur de période."""
        return ft.Container(
            content=ft.Row(
                controls=[
                    ft.Text(
                        "Période :",
                        color=PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT,
                    ),
                    ft.Dropdown(
                        width=150,
                        value=self.selected_period,
                        options=[
                            ft.dropdown.Option("3", "3 mois"),
                            ft.dropdown.Option("6", "6 mois"),
                            ft.dropdown.Option("12", "12 mois"),
                            ft.dropdown.Option("24", "24 mois"),
                        ],
                        on_change=self._on_period_change,
                    ),
                ],
                spacing=12,
                alignment=ft.MainAxisAlignment.END,
            ),
            margin=ft.margin.only(bottom=20),
        )
    
    def _build_patrimony_pie_chart(self) -> ft.Container:
        """Construit le graphique circulaire du patrimoine."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        if self.total_patrimony <= 0:
            return self._build_empty_chart("Répartition du patrimoine", "Aucun actif enregistré")
        
        sections = []
        legend_items = []
        
        for cat in self.patrimony_by_category:
            if cat["total"] > 0:
                percentage = cat["total"] / self.total_patrimony * 100
                sections.append(
                    ft.PieChartSection(
                        value=cat["total"],
                        title=f"{percentage:.1f}%",
                        title_style=ft.TextStyle(
                            size=14,
                            color=ft.colors.WHITE,
                            weight=ft.FontWeight.BOLD,
                        ),
                        color=cat["color"],
                        radius=100,
                    )
                )
                legend_items.append(
                    ft.Row(
                        controls=[
                            ft.Container(
                                width=16,
                                height=16,
                                bgcolor=cat["color"],
                                border_radius=4,
                            ),
                            ft.Text(
                                cat['name'],
                                size=14,
                                color=text_color,
                            ),
                            ft.Text(
                                PeadraTheme.format_currency(cat["total"]),
                                size=14,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        spacing=12,
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    )
                )
        
        pie_chart = ft.PieChart(
            sections=sections,
            sections_space=3,
            center_space_radius=50,
            width=250,
            height=250,
        )
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        "Répartition du patrimoine",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=20, color="transparent"),
                    ft.Row(
                        controls=[
                            pie_chart,
                            ft.Column(
                                controls=legend_items,
                                spacing=16,
                                expand=True,
                            ),
                        ],
                        spacing=40,
                        alignment=ft.MainAxisAlignment.CENTER,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=24,
        )
    
    def _build_expenses_pie_chart(self) -> ft.Container:
        """Construit le graphique circulaire des dépenses."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        total_expenses = sum(data["total"] for _, data in self.expenses_by_category)
        
        if total_expenses <= 0:
            return self._build_empty_chart("Répartition des dépenses", "Aucune dépense enregistrée")
        
        # Couleurs pour les catégories de dépenses
        colors = ["#F44336", "#E91E63", "#9C27B0", "#673AB7", "#3F51B5", 
                  "#2196F3", "#00BCD4", "#009688", "#4CAF50", "#FF9800"]
        
        sections = []
        legend_items = []
        
        for idx, (cat_name, data) in enumerate(self.expenses_by_category[:10]):
            percentage = data["total"] / total_expenses * 100
            color = colors[idx % len(colors)]
            
            sections.append(
                ft.PieChartSection(
                    value=data["total"],
                    title=f"{percentage:.1f}%" if percentage >= 5 else "",
                    title_style=ft.TextStyle(
                        size=12,
                        color=ft.colors.WHITE,
                        weight=ft.FontWeight.BOLD,
                    ),
                    color=color,
                    radius=100,
                )
            )
            legend_items.append(
                ft.Row(
                    controls=[
                        ft.Container(
                            width=16,
                            height=16,
                            bgcolor=color,
                            border_radius=4,
                        ),
                        ft.Text(
                            f"{data['icon']} {cat_name}",
                            size=14,
                            color=text_color,
                            expand=True,
                        ),
                        ft.Text(
                            PeadraTheme.format_currency(data["total"]),
                            size=14,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                    ],
                    spacing=12,
                )
            )
        
        pie_chart = ft.PieChart(
            sections=sections,
            sections_space=2,
            center_space_radius=50,
            width=250,
            height=250,
        )
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        "💸 Répartition des dépenses",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=20, color="transparent"),
                    ft.Row(
                        controls=[
                            pie_chart,
                            ft.Column(
                                controls=legend_items,
                                spacing=12,
                                scroll=ft.ScrollMode.AUTO,
                                expand=True,
                            ),
                        ],
                        spacing=40,
                        alignment=ft.MainAxisAlignment.CENTER,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=24,
        )
    
    def _build_line_chart(self) -> ft.Container:
        """Construit le graphique linéaire de l'évolution du patrimoine."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        if not self.patrimony_evolution:
            return self._build_empty_chart(
                "Évolution du patrimoine",
                "Pas encore de données historiques"
            )
        
        # Préparer les données
        data_points = []
        labels = []
        max_value = 0
        
        for idx, item in enumerate(self.patrimony_evolution):
            value = item["total_value"] or 0
            max_value = max(max_value, value)
            data_points.append(
                ft.LineChartDataPoint(idx, value)
            )
            # Format du mois : Jan, Fév, etc.
            try:
                month_date = datetime.strptime(item["month"], "%Y-%m")
                labels.append(month_date.strftime("%b %y"))
            except:
                labels.append(item["month"])
        
        if max_value == 0:
            max_value = 100
        
        # Créer les axes
        bottom_axis_labels = []
        for idx, label in enumerate(labels):
            if len(labels) <= 6 or idx % 2 == 0:
                bottom_axis_labels.append(
                    ft.ChartAxisLabel(
                        value=idx,
                        label=ft.Text(label, size=10, color=secondary_color),
                    )
                )
        
        line_chart = ft.LineChart(
            data_series=[
                ft.LineChartData(
                    data_points=data_points,
                    stroke_width=3,
                    color=PeadraTheme.ACCENT,
                    curved=True,
                    stroke_cap_round=True,
                    below_line_gradient=ft.LinearGradient(
                        begin=ft.Alignment(0, -1),
                        end=ft.Alignment(0, 1),
                        colors=[
                            PeadraTheme.ACCENT + "60",
                            PeadraTheme.ACCENT + "00",
                        ],
                    ),
                ),
            ],
            border=ft.border.all(1, "rgba(119, 141, 169, 0.2)"),
            horizontal_grid_lines=ft.ChartGridLines(
                color="rgba(119, 141, 169, 0.1)",
                width=1,
            ),
            vertical_grid_lines=ft.ChartGridLines(
                color="rgba(119, 141, 169, 0.1)",
                width=1,
            ),
            left_axis=ft.ChartAxis(
                labels_size=60,
                labels=[
                    ft.ChartAxisLabel(
                        value=0,
                        label=ft.Text("0 €", size=10, color=secondary_color),
                    ),
                    ft.ChartAxisLabel(
                        value=max_value / 2,
                        label=ft.Text(
                            PeadraTheme.format_currency(max_value / 2),
                            size=10,
                            color=secondary_color,
                        ),
                    ),
                    ft.ChartAxisLabel(
                        value=max_value,
                        label=ft.Text(
                            PeadraTheme.format_currency(max_value),
                            size=10,
                            color=secondary_color,
                        ),
                    ),
                ],
            ),
            bottom_axis=ft.ChartAxis(
                labels=bottom_axis_labels,
                labels_size=30,
            ),
            min_y=0,
            max_y=max_value * 1.1,
            min_x=0,
            max_x=len(data_points) - 1 if data_points else 1,
            expand=True,
            height=300,
        )
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        "Évolution du patrimoine",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=20, color="transparent"),
                    line_chart,
                ],
            ),
            is_dark=self.is_dark,
            padding=24,
        )
    
    def _build_bar_chart(self) -> ft.Container:
        """Construit le graphique en barres revenus/dépenses."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        if not self.monthly_transactions:
            return self._build_empty_chart(
                "Revenus vs Dépenses",
                "Aucune transaction enregistrée"
            )
        
        # Préparer les données
        bar_groups = []
        max_value = 0
        labels = []
        
        for idx, (month, data) in enumerate(self.monthly_transactions):
            income = data["income"]
            expense = data["expense"]
            max_value = max(max_value, income, expense)
            
            bar_groups.append(
                ft.BarChartGroup(
                    x=idx,
                    bar_rods=[
                        ft.BarChartRod(
                            from_y=0,
                            to_y=income,
                            width=16,
                            color=PeadraTheme.SUCCESS,
                            border_radius=ft.border_radius.only(top_left=4, top_right=4),
                        ),
                        ft.BarChartRod(
                            from_y=0,
                            to_y=expense,
                            width=16,
                            color=PeadraTheme.ERROR,
                            border_radius=ft.border_radius.only(top_left=4, top_right=4),
                        ),
                    ],
                )
            )
            
            try:
                month_date = datetime.strptime(month, "%Y-%m")
                labels.append(month_date.strftime("%b"))
            except:
                labels.append(month[-2:])
        
        if max_value == 0:
            max_value = 100
        
        bar_chart = ft.BarChart(
            bar_groups=bar_groups,
            border=ft.border.all(1, "rgba(119, 141, 169, 0.2)"),
            horizontal_grid_lines=ft.ChartGridLines(
                color="rgba(119, 141, 169, 0.1)",
                width=1,
            ),
            left_axis=ft.ChartAxis(
                labels_size=60,
                labels=[
                    ft.ChartAxisLabel(
                        value=0,
                        label=ft.Text("0 €", size=10, color=secondary_color),
                    ),
                    ft.ChartAxisLabel(
                        value=max_value,
                        label=ft.Text(
                            PeadraTheme.format_currency(max_value),
                            size=10,
                            color=secondary_color,
                        ),
                    ),
                ],
            ),
            bottom_axis=ft.ChartAxis(
                labels=[
                    ft.ChartAxisLabel(
                        value=idx,
                        label=ft.Text(label, size=10, color=secondary_color),
                    )
                    for idx, label in enumerate(labels)
                ],
                labels_size=30,
            ),
            max_y=max_value * 1.1,
            expand=True,
            height=300,
        )
        
        # Légende
        legend = ft.Row(
            controls=[
                ft.Row(
                    controls=[
                        ft.Container(width=16, height=16, bgcolor=PeadraTheme.SUCCESS, border_radius=4),
                        ft.Text("Revenus", color=text_color),
                    ],
                    spacing=8,
                ),
                ft.Row(
                    controls=[
                        ft.Container(width=16, height=16, bgcolor=PeadraTheme.ERROR, border_radius=4),
                        ft.Text("Dépenses", color=text_color),
                    ],
                    spacing=8,
                ),
            ],
            spacing=24,
            alignment=ft.MainAxisAlignment.CENTER,
        )
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        "Revenus vs Dépenses",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=16, color="transparent"),
                    legend,
                    ft.Divider(height=16, color="transparent"),
                    bar_chart,
                ],
            ),
            is_dark=self.is_dark,
            padding=24,
        )
    
    def _build_empty_chart(self, title: str, message: str) -> ft.Container:
        """Construit un graphique vide."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        title,
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Container(
                        content=ft.Column(
                            controls=[
                                ft.Icon(
                                    ft.icons.INSERT_CHART_OUTLINED,
                                    size=48,
                                    color=secondary_color,
                                ),
                                ft.Text(
                                    message,
                                    color=secondary_color,
                                    italic=True,
                                ),
                            ],
                            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                            spacing=12,
                        ),
                        padding=40,
                        alignment=ft.Alignment(0, 0),
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=24,
        )
    
    def _build_summary_cards(self) -> ft.Container:
        """Construit les cartes de résumé."""
        total_income = sum(tx["amount"] for tx in self.transactions if tx["transaction_type"] == "income")
        total_expense = sum(tx["amount"] for tx in self.transactions if tx["transaction_type"] == "expense")
        savings_rate = ((total_income - total_expense) / total_income * 100) if total_income > 0 else 0
        
        return ft.Container(
            content=ft.Row(
                controls=[
                    PeadraTheme.stat_card(
                        title="Patrimoine total",
                        value=PeadraTheme.format_currency(self.total_patrimony),
                        icon=ft.icons.ACCOUNT_BALANCE_WALLET,
                        color=PeadraTheme.PRIMARY_MEDIUM,
                        is_dark=self.is_dark,
                    ),
                    PeadraTheme.stat_card(
                        title="Total revenus",
                        value=PeadraTheme.format_currency(total_income),
                        icon=ft.icons.TRENDING_UP,
                        color=PeadraTheme.SUCCESS,
                        is_dark=self.is_dark,
                    ),
                    PeadraTheme.stat_card(
                        title="Total dépenses",
                        value=PeadraTheme.format_currency(total_expense),
                        icon=ft.icons.TRENDING_DOWN,
                        color=PeadraTheme.ERROR,
                        is_dark=self.is_dark,
                    ),
                    PeadraTheme.stat_card(
                        title="Taux d'épargne",
                        value=f"{savings_rate:.1f}%",
                        icon=ft.icons.SAVINGS,
                        color=PeadraTheme.INFO,
                        is_dark=self.is_dark,
                    ),
                ],
                spacing=16,
                wrap=True,
            ),
            margin=ft.margin.only(bottom=20),
        )
    
    def build(self) -> ft.Container:
        """Construit la vue complète des analyses."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        return ft.Container(
            content=ft.Column(
                controls=[
                    # En-tête
                    ft.Row(
                        controls=[
                            ft.Text(
                                "Analyses",
                                size=28,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.Container(expand=True),
                            self._build_period_selector(),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Divider(height=24, color="transparent"),
                    # Cartes de résumé
                    self._build_summary_cards(),
                    # Graphique d'évolution
                    self._build_line_chart(),
                    ft.Divider(height=20, color="transparent"),
                    # Graphiques en ligne
                    ft.Row(
                        controls=[
                            ft.Container(
                                content=self._build_patrimony_pie_chart(),
                                expand=1,
                            ),
                            ft.Container(
                                content=self._build_expenses_pie_chart(),
                                expand=1,
                            ),
                        ],
                        spacing=20,
                    ),
                    ft.Divider(height=20, color="transparent"),
                    # Graphique en barres
                    self._build_bar_chart(),
                ],
                scroll=ft.ScrollMode.AUTO,
                expand=True,
            ),
            expand=True,
        )

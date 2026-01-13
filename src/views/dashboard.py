"""
Vue Tableau de bord pour Peadra.
Affiche un résumé visuel du patrimoine total.
"""

import flet as ft
from typing import Callable
from datetime import datetime, timedelta
import calendar
from ..components.theme import PeadraTheme
from ..database.db_manager import db


class DashboardView:
    """Vue du tableau de bord."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.touched_index = -1
        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()

    def _load_data(self):
        # Now reflects Bank Balance
        self.total_patrimony = db.get_total_patrimony()
        self.balance = db.get_balance()

        # Get current month summary
        now = datetime.now()
        current_summary = db.get_monthly_summary(now.year, now.month)
        self.monthly_income = current_summary.get("income", 0) or 0
        self.monthly_expenses = current_summary.get("expenses", 0) or 0
        self.monthly_savings = db.get_savings_total()

        # Previous month for trends
        prev_month = now.replace(day=1) - timedelta(days=1)
        prev_summary = db.get_monthly_summary(prev_month.year, prev_month.month)
        prev_income = prev_summary.get("income", 0) or 0
        prev_expenses = prev_summary.get("expenses", 0) or 0
        prev_savings = prev_summary.get("savings", 0) or 0
        prev_balance = prev_summary.get("balance", 0) or 0

        # Calculate trends
        def calc_trend(curr, prev):
            if not prev:
                return 0.0 if not curr else 100.0
            return ((curr - prev) / prev) * 100

        self.income_trend = calc_trend(self.monthly_income, prev_income)
        self.expenses_trend = calc_trend(self.monthly_expenses, prev_expenses)
        self.savings_trend = calc_trend(self.monthly_savings, prev_savings)
        self.balance_trend = calc_trend(self.balance, prev_balance)

        # Chart Data (Income vs Expenses) - Last 6 months
        self.chart_data = []
        for i in range(5, -1, -1):
            date_calc = now.replace(day=1)
            # Subtract i months
            year = date_calc.year
            month = date_calc.month - i
            while month <= 0:
                month += 12
                year -= 1

            s = db.get_monthly_summary(year, month)
            month_abbr = calendar.month_abbr[month]
            self.chart_data.append(
                {
                    "month": month_abbr,
                    "income": s.get("income", 0) or 0,
                    "expenses": s.get("expenses", 0) or 0,
                }
            )

        # Simplified category logic for Expenses logic
        start_date = now.strftime("%Y-%m-01")
        if now.month == 12:
            end_date = f"{now.year + 1}-01-01"
        else:
            end_date = f"{now.year}-{now.month + 1:02d}-01"

        txs = db.get_transactions_by_period(start_date, end_date)
        self.category_expenses = {}
        for t in txs:
            if t["transaction_type"] == "expense":
                desc = (t["description"] or "Autre").strip()
                self.category_expenses[desc] = (
                    self.category_expenses.get(desc, 0) + t["amount"]
                )

        # Account Distribution Data
        self.account_distribution = db.get_accounts_distribution()

    def _build_stat_card(
        self,
        title: str,
        value: float,
        trend: float,
        icon: str,
        icon_bg: str,
        icon_color: str,
        trend_semantic: str = "normal",
    ) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        is_positive = trend >= 0
        if trend_semantic == "reverse":
            is_good = not is_positive
        else:
            is_good = is_positive

        trend_color = PeadraTheme.SUCCESS if is_good else PeadraTheme.ERROR
        trend_icon = ft.icons.NORTH_EAST if is_good else ft.icons.SOUTH_EAST
        trend_text = f"{'+' if is_positive else ''}{trend:.1f}%"

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Container(
                                content=ft.Icon(icon, color=icon_color, size=24),
                                bgcolor=icon_bg,
                                padding=12,
                                border_radius=12,
                            ),
                            ft.Row(
                                [
                                    ft.Icon(trend_icon, color=trend_color, size=16),
                                    ft.Text(
                                        trend_text,
                                        color=trend_color,
                                        size=12,
                                        weight=ft.FontWeight.BOLD,
                                    ),
                                ],
                                spacing=4,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Container(height=12),
                    ft.Column(
                        [
                            ft.Text(title, size=14, color=ft.colors.GREY_500),
                            ft.Text(
                                f"€{value:,.2f}",
                                size=24,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        spacing=4,
                    ),
                ]
            ),
            padding=20,
            bgcolor=bg_card,
            border_radius=20,
            expand=True,
            border=(
                ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_income_expense_chart(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        dates = [d["month"] for d in self.chart_data]
        incomes = [d["income"] for d in self.chart_data]
        expenses = [d["expenses"] for d in self.chart_data]

        if not dates:
            return ft.Container()

        max_val = max(max(incomes + [0]), max(expenses + [0])) * 1.2
        if max_val == 0:
            max_val = 100

        def create_data_points(values):
            return [ft.LineChartDataPoint(i, float(v)) for i, v in enumerate(values)]

        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(
                        "Income vs Expenses",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Container(height=20),
                    ft.LineChart(
                        data_series=[
                            ft.LineChartData(
                                data_points=create_data_points(incomes),
                                stroke_width=3,
                                color="#4CAF50",  # Income Green
                                curved=True,
                                stroke_cap_round=True,
                                below_line_bgcolor=ft.colors.with_opacity(
                                    0.1, "#4CAF50"
                                ),
                            ),
                            ft.LineChartData(
                                data_points=create_data_points(expenses),
                                stroke_width=3,
                                color="#E53935",  # Expenses Red
                                curved=True,
                                stroke_cap_round=True,
                                below_line_bgcolor=ft.colors.with_opacity(
                                    0.1, "#E53935"
                                ),
                            ),
                        ],
                        border=ft.border.all(0, ft.colors.TRANSPARENT),
                        horizontal_grid_lines=ft.ChartGridLines(
                            interval=max_val / 4,
                            color=ft.colors.with_opacity(0.1, ft.colors.ON_SURFACE),
                            width=1,
                        ),
                        vertical_grid_lines=ft.ChartGridLines(
                            interval=1, color=ft.colors.TRANSPARENT
                        ),
                        left_axis=ft.ChartAxis(
                            labels_size=40, title_size=0, show_labels=True
                        ),
                        bottom_axis=ft.ChartAxis(
                            labels=[
                                ft.ChartAxisLabel(
                                    value=i,
                                    label=ft.Container(
                                        ft.Text(
                                            dates[i], size=10, color=ft.colors.GREY
                                        ),
                                        padding=10,
                                    ),
                                )
                                for i in range(len(dates))
                            ],
                            labels_size=40,
                            labels_interval=1,
                        ),
                        min_y=0,
                        max_y=max_val if max_val > 0 else 1000,
                        expand=True,
                        tooltip_bgcolor=PeadraTheme.SURFACE,
                    ),
                    ft.Row(
                        [
                            ft.Row(
                                [
                                    ft.Container(
                                        width=10,
                                        height=10,
                                        bgcolor="#4CAF50",
                                        border_radius=5,
                                    ),
                                    ft.Text("Income", color=ft.colors.GREY, size=12),
                                ]
                            ),
                            ft.Row(
                                [
                                    ft.Container(
                                        width=10,
                                        height=10,
                                        bgcolor="#E53935",
                                        border_radius=5,
                                    ),
                                    ft.Text("Expenses", color=ft.colors.GREY, size=12),
                                ]
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.CENTER,
                        spacing=20,
                    ),
                ],
            ),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            expand=True,
            border=(
                ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_category_chart(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        sorted_cats = sorted(
            self.category_expenses.items(), key=lambda x: x[1], reverse=True
        )[:5]

        if not sorted_cats:
            return ft.Container(
                content=ft.Column(
                    [
                        ft.Text(
                            "Expenses by Category",
                            size=18,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                        ft.Container(
                            content=ft.Text(
                                "No expenses this month", color=ft.colors.GREY
                            ),
                            alignment=ft.alignment.center,
                            expand=True,
                        ),
                    ]
                ),
                bgcolor=bg_card,
                padding=24,
                border_radius=20,
                expand=True,
                border=(
                    ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                    if not self.is_dark
                    else None
                ),
            )

        max_val = max([v for k, v in sorted_cats]) * 1.2
        if max_val == 0:
            max_val = 100

        rod_groups = []
        for i, (cat, val) in enumerate(sorted_cats):
            rod_groups.append(
                ft.BarChartGroup(
                    x=i,
                    bar_rods=[
                        ft.BarChartRod(
                            from_y=0,
                            to_y=float(val),
                            width=30,
                            color="#2979FF",
                            border_radius=ft.border_radius.vertical(top=6),
                        )
                    ],
                )
            )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(
                        "Top Monthly Expenses",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Container(height=20),
                    ft.BarChart(
                        bar_groups=rod_groups,
                        border=ft.border.all(0, ft.colors.TRANSPARENT),
                        left_axis=ft.ChartAxis(labels_size=40),
                        bottom_axis=ft.ChartAxis(
                            labels=[
                                ft.ChartAxisLabel(
                                    value=i,
                                    label=ft.Container(
                                        ft.Text(
                                            cat[:10], size=10, color=ft.colors.GREY
                                        ),
                                        padding=5,
                                    ),
                                )
                                for i, (cat, _) in enumerate(sorted_cats)
                            ],
                            labels_size=30,
                        ),
                        horizontal_grid_lines=ft.ChartGridLines(
                            interval=max_val / 5,
                            color=ft.colors.with_opacity(0.1, ft.colors.ON_SURFACE),
                            width=1,
                        ),
                        max_y=max_val,
                        expand=True,
                        tooltip_bgcolor=PeadraTheme.SURFACE,
                    ),
                ]
            ),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            expand=True,
            border=(
                ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_account_distribution_chart(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        # Filter out zero or negative balances for the pie chart
        data = [d for d in self.account_distribution if d["value"] > 0]

        # Colors for the chart
        colors = [
            ft.colors.BLUE,
            ft.colors.GREEN,
            ft.colors.ORANGE,
            ft.colors.PURPLE,
            ft.colors.RED,
            ft.colors.TEAL,
            ft.colors.CYAN,
        ]

        if not data:
            return ft.Container(
                content=ft.Column(
                    [
                        ft.Text(
                            "Assets distribution",
                            size=18,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                        ft.Container(
                            content=ft.Text(
                                "No balance to display", color=ft.colors.GREY
                            ),
                            alignment=ft.alignment.center,
                            expand=True,
                        ),
                    ]
                ),
                bgcolor=bg_card,
                padding=24,
                border_radius=20,
                expand=True,
                border=(
                    ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                    if not self.is_dark
                    else None
                ),
            )

        def on_pie_touch(e):
            idx = e.section_index if e.section_index is not None else -1
            self.touched_index = idx
            if hasattr(self, "pie_chart_container"):
                self.pie_chart_container.content = build_chart_content()
                self.pie_chart_container.update()

        def build_chart_content():
            sections = []
            for i, item in enumerate(data):
                color = colors[i % len(colors)]
                is_touched = i == self.touched_index
                radius = 50 if is_touched else 40

                # Show title (amount) only if touched
                title = f"{item['value']:.0f}€" if is_touched else ""

                sections.append(
                    ft.PieChartSection(
                        item["value"],
                        title=title,
                        title_style=ft.TextStyle(
                            size=14, color=ft.colors.WHITE, weight=ft.FontWeight.BOLD
                        ),
                        color=color,
                        radius=radius,
                        # No badges
                    )
                )

            chart = ft.PieChart(
                sections=sections,
                sections_space=5,
                center_space_radius=30,
                expand=True,
                on_chart_event=on_pie_touch,
            )

            # Legend
            legend_items = []
            for i, item in enumerate(data):
                color = colors[i % len(colors)]
                legend_items.append(
                    ft.Row(
                        [
                            ft.Container(
                                width=12, height=12, bgcolor=color, border_radius=6
                            ),
                            ft.Text(f"{item['name']}", color=ft.colors.GREY, size=12),
                        ],
                        spacing=5,
                    )
                )

            legend = ft.Column(legend_items, scroll=ft.ScrollMode.AUTO, spacing=10)

            return ft.Column(
                [
                    ft.Text(
                        "Assets distribution",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Container(height=20),
                    ft.Row(
                        [
                            ft.Container(chart, expand=True, height=200),
                            ft.Container(legend, width=150),
                        ],
                        alignment=ft.MainAxisAlignment.START,
                        vertical_alignment=ft.CrossAxisAlignment.START,
                    ),
                ]
            )

        self.pie_chart_container = ft.Container(
            content=build_chart_content(),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            expand=True,
            border=(
                ft.border.all(1, ft.colors.with_opacity(0.1, ft.colors.GREY))
                if not self.is_dark
                else None
            ),
        )
        return self.pie_chart_container

    def build(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        # Colors for cards
        if self.is_dark:
            blue_bg = ft.colors.with_opacity(0.2, "blue")
            green_bg = ft.colors.with_opacity(0.2, "green")
            red_bg = ft.colors.with_opacity(0.2, "red")
            purple_bg = ft.colors.with_opacity(0.2, "purple")
        else:
            blue_bg = ft.colors.BLUE_50
            green_bg = ft.colors.GREEN_50
            red_bg = ft.colors.RED_50
            purple_bg = ft.colors.PURPLE_50

        if self.is_dark:
            blue_bg = ft.colors.with_opacity(0.1, ft.colors.BLUE)
            green_bg = ft.colors.with_opacity(0.1, ft.colors.GREEN)
            red_bg = ft.colors.with_opacity(0.1, ft.colors.RED)
            purple_bg = ft.colors.with_opacity(0.1, ft.colors.PURPLE)
        else:
            blue_bg = ft.colors.BLUE_50
            green_bg = ft.colors.GREEN_50
            red_bg = ft.colors.RED_50
            purple_bg = ft.colors.PURPLE_50

        card_row = ft.Row(
            [
                self._build_stat_card(
                    "Current Balance",
                    self.balance,
                    self.balance_trend,
                    ft.icons.ACCOUNT_BALANCE_WALLET,
                    blue_bg,
                    ft.colors.BLUE,
                    "normal",
                ),
                self._build_stat_card(
                    "Income",
                    self.monthly_income,
                    self.income_trend,
                    ft.icons.TRENDING_UP,
                    green_bg,
                    ft.colors.GREEN,
                    "normal",
                ),
                self._build_stat_card(
                    "Expenses",
                    self.monthly_expenses,
                    self.expenses_trend,
                    ft.icons.TRENDING_DOWN,
                    red_bg,
                    ft.colors.RED,
                    "reverse",
                ),
                self._build_stat_card(
                    "Savings Outside",
                    self.monthly_savings,
                    self.savings_trend,
                    ft.icons.SAVINGS,
                    purple_bg,
                    ft.colors.PURPLE,
                    "normal",
                ),
            ],
            spacing=20,
        )

        charts_row_1 = ft.Container(
            content=self._build_income_expense_chart(),
            height=300,
        )

        charts_row_2 = ft.Container(
            content=ft.Row(
                [
                    ft.Container(content=self._build_category_chart(), expand=1),
                    ft.Container(
                        content=self._build_account_distribution_chart(), expand=1
                    ),
                ],
                spacing=20,
            ),
            height=300,
        )

        content = ft.Column(
            [
                ft.Container(
                    content=ft.Column(
                        [
                            ft.Text(
                                "Dashboard",
                                size=32,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.Text(
                                "Welcome back! Here's your financial overview.",
                                size=16,
                                color=ft.colors.GREY,
                            ),
                        ],
                        spacing=4,
                    ),
                    margin=ft.margin.only(bottom=20),
                ),
                card_row,
                ft.Container(height=20),
                charts_row_1,
                ft.Container(height=20),
                charts_row_2,
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=0,
        )

        return ft.Container(content=content, padding=30, expand=True)

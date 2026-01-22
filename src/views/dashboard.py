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
        self.touched_index_assets = -1
        self.touched_index_income = -1
        self.touched_index_expenses = -1
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

        # For Stocks (Savings/Balance), we compare Current Value vs Value at Start of Month (History)
        start_of_month_str = now.replace(day=1).strftime("%Y-%m-%d")
        prev_savings = db.get_history_savings(start_of_month_str)
        prev_balance = db.get_history_balance(start_of_month_str)

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

            # Calculate patrimony at the end of this month
            # End of month is the first day of next month
            if month == 12:
                end_date = f"{year + 1}-01-01"
            else:
                end_date = f"{year}-{month + 1:02d}-01"

            patrimony = db.get_history_patrimony(end_date)

            self.chart_data.append(
                {
                    "month": month_abbr,
                    "income": s.get("income", 0) or 0,
                    "expenses": s.get("expenses", 0) or 0,
                    "patrimony": patrimony,
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
        self.category_incomes = {}
        for t in txs:
            desc = (t["description"] or "Autre").strip()
            # Filter out transfers
            if desc.startswith("Transfer to ") or desc.startswith("Transfer from "):
                continue

            if t["transaction_type"] == "expense":
                self.category_expenses[desc] = (
                    self.category_expenses.get(desc, 0) + t["amount"]
                )
            elif t["transaction_type"] == "income":
                self.category_incomes[desc] = (
                    self.category_incomes.get(desc, 0) + t["amount"]
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
        patrimonies = [d["patrimony"] for d in self.chart_data]

        if not dates:
            return ft.Container()

        # Calculate ranges for scaling
        raw_max_patrimony = max(patrimonies) if patrimonies else 0
        raw_min_patrimony = min(patrimonies) if patrimonies else 0
        raw_max_bars = max(incomes + expenses + [0])

        # Dynamic scaling for patrimony line
        # We want the line to be clearly visible, so we don't start at 0 if values are high
        patrimony_spread = raw_max_patrimony - raw_min_patrimony
        if patrimony_spread == 0:
            patrimony_spread = raw_max_patrimony * 0.1 if raw_max_patrimony > 0 else 100

        # Add padding (20% above and below the range)
        padding = patrimony_spread * 0.5  # More padding to avoid "stuck at top" look
        min_y_patrimony = max(0, raw_min_patrimony - padding)

        # If the minimum is very close to zero compared to the max, might as well start at 0
        if min_y_patrimony < raw_max_patrimony * 0.1:
            min_y_patrimony = 0

        max_y_patrimony = raw_max_patrimony + padding

        # Buffer for flat lines
        if max_y_patrimony == min_y_patrimony:
            max_y_patrimony += 100

        # For bars, we keep 0 baseline and scale to occupy lower portion
        if raw_max_bars == 0:
            raw_max_bars = 100  # Avoid division by zero
        max_bars_scaled = raw_max_bars * 3

        # Create bar chart groups for income and expenses
        bar_groups = []
        for i in range(len(dates)):
            bar_groups.append(
                ft.BarChartGroup(
                    x=i,
                    bar_rods=[
                        ft.BarChartRod(
                            from_y=0,
                            to_y=float(incomes[i]),
                            width=15,
                            color="#4CAF50",
                            border_radius=ft.border_radius.vertical(top=4),
                        ),
                        ft.BarChartRod(
                            from_y=0,
                            to_y=float(expenses[i]),
                            width=15,
                            color="#E53935",
                            border_radius=ft.border_radius.vertical(top=4),
                        ),
                    ],
                    bars_space=4,
                )
            )

        # Create line chart data for patrimony
        def create_data_points(values):
            return [ft.LineChartDataPoint(i, float(v)) for i, v in enumerate(values)]

        # Build the chart with Stack to overlay line on bars
        chart_content = ft.Stack(
            [
                # Line chart layer (background) - uses patrimony scale with visible Y-axis
                ft.LineChart(
                    data_series=[
                        ft.LineChartData(
                            data_points=[
                                ft.LineChartDataPoint(i, float(v))
                                for i, v in enumerate(patrimonies)
                            ],
                            stroke_width=3,
                            color="#7E57C2",  # Purple for Balance
                            curved=True,
                            stroke_cap_round=True,
                        ),
                    ],
                    border=ft.border.all(0, ft.colors.TRANSPARENT),
                    horizontal_grid_lines=ft.ChartGridLines(
                        interval=(max_y_patrimony - min_y_patrimony) / 5,
                        color=ft.colors.with_opacity(0.1, ft.colors.ON_SURFACE),
                        width=1,
                    ),
                    vertical_grid_lines=ft.ChartGridLines(
                        interval=1, color=ft.colors.TRANSPARENT
                    ),
                    left_axis=ft.ChartAxis(
                        labels_size=40,
                        title_size=0,
                        show_labels=True,  # Show patrimony Y-axis
                    ),
                    bottom_axis=ft.ChartAxis(
                        labels=[
                            ft.ChartAxisLabel(
                                value=i,
                                label=ft.Container(
                                    ft.Text(dates[i], size=12, color=ft.colors.GREY),
                                    padding=ft.padding.only(top=20),
                                ),
                            )
                            for i in range(len(dates))
                        ],
                        labels_size=50,  # Space for labels below chart
                        show_labels=True,  # Show month labels on LineChart
                    ),
                    min_x=0,
                    max_x=len(dates) - 1,
                    min_y=min_y_patrimony,
                    max_y=max_y_patrimony,  # Line chart uses patrimony scale
                    expand=True,
                    tooltip_bgcolor=PeadraTheme.SURFACE,
                ),
                # Bar chart layer (foreground for hover) - wrapped in padding to align with 0
                ft.Container(
                    content=ft.BarChart(
                        bar_groups=bar_groups,
                        border=ft.border.all(0, ft.colors.TRANSPARENT),
                        left_axis=ft.ChartAxis(
                            labels_size=40,  # Match LineChart to align drawing areas
                            show_labels=False,
                        ),
                        bottom_axis=ft.ChartAxis(
                            labels_size=0,  # Reserve space but don't show labels
                            show_labels=False,
                        ),
                        horizontal_grid_lines=ft.ChartGridLines(
                            interval=max_bars_scaled / 5,
                            color=ft.colors.TRANSPARENT,
                            width=1,
                        ),
                        min_y=0,
                        max_y=max_bars_scaled,  # Scaled so bars stay at ~30% height
                        tooltip_bgcolor=PeadraTheme.SURFACE,
                        scale=ft.transform.Scale(
                            scale_x=(len(dates) / (len(dates) - 1))
                            if len(dates) > 1
                            else 1,
                            scale_y=1,
                        ),
                    ),
                    expand=True,
                    margin=ft.margin.only(bottom=50),  # Align with LineChart
                ),
            ],
            expand=True,
        )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Text(
                                "Cash Flow",
                                size=18,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.Container(expand=True),  # Spacer
                            # Legend moved to the right of the title
                            ft.Row(
                                [
                                    ft.Container(
                                        width=10,
                                        height=10,
                                        bgcolor="#7E57C2",
                                        border_radius=5,
                                    ),
                                    ft.Text(
                                        "Total Assets", color=ft.colors.GREY, size=12
                                    ),
                                    ft.Container(width=15),  # Spacing
                                    ft.Container(
                                        width=10,
                                        height=10,
                                        bgcolor="#4CAF50",
                                        border_radius=5,
                                    ),
                                    ft.Text("Inflows", color=ft.colors.GREY, size=12),
                                    ft.Container(width=15),  # Spacing
                                    ft.Container(
                                        width=10,
                                        height=10,
                                        bgcolor="#E53935",
                                        border_radius=5,
                                    ),
                                    ft.Text("Outflows", color=ft.colors.GREY, size=12),
                                ],
                                spacing=5,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Container(height=20),
                    chart_content,
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

    def _build_pie_chart(
        self,
        title: str,
        data_dict: dict,
        touched_index_attr_name: str,
        container_attr_name: str,
        empty_msg: str,
    ) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        valid_items = {k: v for k, v in data_dict.items() if v > 0}
        sorted_items = sorted(valid_items.items(), key=lambda x: x[1], reverse=True)

        if len(sorted_items) > 5:
            top_items = sorted_items[:5]
            other_value = (
                sum(item[1] for item in sorted_items[5:])
                if len(sorted_items) > 5
                else 0
            )

            data_points = [{"name": k, "value": v} for k, v in top_items]
            if other_value > 0:
                data_points.append({"name": "Autres", "value": other_value})
        else:
            data_points = [{"name": k, "value": v} for k, v in sorted_items]

        colors = [
            ft.colors.BLUE,
            ft.colors.GREEN,
            ft.colors.ORANGE,
            ft.colors.PURPLE,
            ft.colors.RED,
            ft.colors.TEAL,
            ft.colors.CYAN,
        ]

        if not data_points:
            return ft.Container(
                content=ft.Column(
                    [
                        ft.Text(
                            title,
                            size=18,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                        ft.Container(
                            content=ft.Text(empty_msg, color=ft.colors.GREY),
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
            setattr(self, touched_index_attr_name, idx)
            container = getattr(self, container_attr_name, None)
            if container:
                container.content = build_chart_content()
                container.update()

        def build_chart_content():
            touched_index = getattr(self, touched_index_attr_name, -1)
            sections = []
            for i, item in enumerate(data_points):
                color = colors[i % len(colors)]
                is_touched = i == touched_index
                radius = 50 if is_touched else 40

                # Show title (amount) only if touched
                section_title = f"{item['value']:.0f}€" if is_touched else ""

                sections.append(
                    ft.PieChartSection(
                        item["value"],
                        title=section_title,
                        title_style=ft.TextStyle(
                            size=14, color=ft.colors.WHITE, weight=ft.FontWeight.BOLD
                        ),
                        color=color,
                        radius=radius,
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
            for i, item in enumerate(data_points):
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

            legend = ft.Column(legend_items, scroll=ft.ScrollMode.AUTO, spacing=5)

            return ft.Column(
                [
                    ft.Text(
                        title,
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

        # Create the container and assign it to self so we can update it later
        chart_container = ft.Container(
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
        setattr(self, container_attr_name, chart_container)
        return chart_container

    def _build_category_chart(self) -> ft.Container:
        return self._build_pie_chart(
            "This Month Expenses",
            self.category_expenses,
            "touched_index_expenses",
            "expenses_chart_container",
            "No expenses this month",
        )

    def _build_income_distribution_chart(self) -> ft.Container:
        return self._build_pie_chart(
            "This Month Incomes",
            self.category_incomes,
            "touched_index_income",
            "income_chart_container",
            "No income this month",
        )

    def _build_account_distribution_chart(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        # Filter out zero or negative balances for the pie chart
        data = [d for d in self.account_distribution if d["value"] > 0]

        # Let's manual construct the dict
        data_dict = {d["name"]: d["value"] for d in data}

        return self._build_pie_chart(
            "Assets Distribution",
            data_dict,
            "touched_index_assets",
            "assets_chart_container",
            "No assets to display",
        )

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
            height=320,  # Reduced to give space for labels below
        )

        charts_row_2 = ft.Container(
            content=ft.Row(
                [
                    ft.Container(content=self._build_category_chart(), expand=1),
                    ft.Container(
                        content=self._build_income_distribution_chart(), expand=1
                    ),
                    ft.Container(
                        content=self._build_account_distribution_chart(), expand=1
                    ),
                ],
                spacing=20,
            ),
            # height=300, # Remove fixed height to accommodate dynamic content
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

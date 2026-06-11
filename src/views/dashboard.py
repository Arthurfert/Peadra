"""
Vue Tableau de bord pour Peadra.
Affiche un résumé visuel du patrimoine total.
"""

import flet as ft
import logging
import flet_charts as fch
import math
from typing import Callable, Union, Any, cast, List, Optional
from datetime import datetime, timedelta
from ..components.theme import PeadraTheme
from ..database import db
from ..i18n import t

logger = logging.getLogger(__name__)


class DashboardView:
    """Vue du tableau de bord."""

    def __init__(
        self,
        page: ft.Page,
        is_dark: bool,
        on_data_change: Callable,
        get_month_mode: Optional[Callable] = None,
    ):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.get_month_mode = get_month_mode or (lambda: "strict")
        self.touched_index_assets = -1
        self.touched_index_income = -1
        self.touched_index_expenses = -1
        self.chart_duration = 6
        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()

    def _update_chart_duration(self, duration: Union[int, str]):
        self.chart_duration = duration
        self.refresh()
        if hasattr(self, "chart_container_main"):
            self.chart_container_main.content = self._build_income_expense_chart()
            self.chart_container_main.update()
        if hasattr(self, "charts_row_2"):
            self.charts_row_2.content = ft.Row(
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
            )
            self.charts_row_2.update()

    def _get_month_bounds(self, year: int, month: int) -> tuple[str, str]:
        """Retourne les bornes inclusives d'un mois (YYYY-MM-DD)."""
        start_dt = datetime(year, month, 1)
        if month == 12:
            next_month_dt = datetime(year + 1, 1, 1)
        else:
            next_month_dt = datetime(year, month + 1, 1)
        end_dt = next_month_dt - timedelta(days=1)
        return start_dt.strftime("%Y-%m-%d"), end_dt.strftime("%Y-%m-%d")

    def _is_transfer_transaction(self, transaction: dict[str, Any]) -> bool:
        """Détecte les transferts, y compris les entrées legacy basées sur description."""
        tx_type = (transaction.get("transaction_type") or "").strip().lower()
        if tx_type == "transfer":
            return True

        desc = (transaction.get("description") or "").strip().lower()
        transfer_to = (t("trans_transfer_to") or "").strip().lower()
        transfer_from = (t("trans_transfer_from") or "").strip().lower()

        prefixes = ["transfer to ", "transfer from "]
        if transfer_to:
            prefixes.append(f"{transfer_to} ")
        if transfer_from:
            prefixes.append(f"{transfer_from} ")

        return any(desc.startswith(prefix) for prefix in prefixes)

    def _get_filtered_totals(
        self, start_date: str, end_date: str
    ) -> tuple[float, float]:
        """Somme revenus/dépenses d'une période en excluant les transferts."""
        txs = db.get_transactions_by_period(start_date, end_date)
        income = 0.0
        expenses = 0.0

        for transaction in txs:
            if self._is_transfer_transaction(transaction):
                continue

            tx_type = transaction.get("transaction_type")
            amount = float(transaction.get("amount") or 0)
            if tx_type == "income":
                income += amount
            elif tx_type == "expense":
                expenses += amount

        return income, expenses

    def _build_chart_data(self, start_year: int, start_month: int, num_months: int):
        """Construit les données du graphique mensuel à partir d'un seul lot de transactions."""
        month_labels = {
            1: "month_january",
            2: "month_february",
            3: "month_march",
            4: "month_april",
            5: "month_may",
            6: "month_june",
            7: "month_july",
            8: "month_august",
            9: "month_september",
            10: "month_october",
            11: "month_november",
            12: "month_december",
        }

        months = []
        year = start_year
        month = start_month
        for _ in range(num_months):
            months.append((year, month))
            month += 1
            if month > 12:
                month = 1
                year += 1

        if not months:
            return []

        last_year, last_month = months[-1]
        _, chart_end = self._get_month_bounds(last_year, last_month)
        chart_start = f"{months[0][0]}-{months[0][1]:02d}-01"

        chart_txs = db.get_transactions_by_period(chart_start, chart_end)
        chart_txs.sort(key=lambda tx: (tx.get("date") or "", tx.get("id") or 0))

        series = {
            (year, month): {"income": 0.0, "expenses": 0.0, "delta": 0.0}
            for year, month in months
        }

        for transaction in chart_txs:
            date_value = transaction.get("date") or ""
            if len(date_value) < 7:
                continue

            year = int(date_value[:4])
            month = int(date_value[5:7])
            bucket = series.get((year, month))
            if bucket is None:
                continue

            amount = float(transaction.get("amount") or 0)
            tx_type = (transaction.get("transaction_type") or "").strip().lower()

            if tx_type == "income":
                bucket["delta"] += amount
            elif tx_type == "expense":
                bucket["delta"] -= amount

            if self._is_transfer_transaction(transaction):
                continue

            if tx_type == "income":
                bucket["income"] += amount
            elif tx_type == "expense":
                bucket["expenses"] += amount

        patrimony = db.get_history_patrimony(chart_start)
        chart_data = []

        for year, month in months:
            bucket = series[(year, month)]
            patrimony += bucket["delta"]
            chart_data.append(
                {
                    "month_label": t(month_labels[month]).capitalize()[:3],
                    "income": bucket["income"],
                    "expenses": bucket["expenses"],
                    "patrimony": patrimony,
                }
            )

        return chart_data

    def _load_data(self):
        self.currency = db.get_setting("currency", "€") or "€"
        logger.debug("Dashboard data loaded")
        # Now reflects Bank Balance
        self.total_patrimony = db.get_total_patrimony()
        self.balance = db.get_balance()

        now = datetime.now()
        month_mode = self.get_month_mode()

        if month_mode == "rolling":
            # Rolling: last 30 days
            rolling_start_dt = now - timedelta(days=30)
            rolling_end_dt = now
            rolling_start = rolling_start_dt.strftime("%Y-%m-%d")
            rolling_end = rolling_end_dt.strftime("%Y-%m-%d")

            self.monthly_income, self.monthly_expenses = self._get_filtered_totals(
                rolling_start, rolling_end
            )
            self.monthly_savings = db.get_savings_total()

            # Previous period for trends: 30 days before the rolling window
            prev_end_dt = rolling_start_dt - timedelta(days=1)
            prev_start_dt = prev_end_dt - timedelta(days=30)
            prev_income, prev_expenses = self._get_filtered_totals(
                prev_start_dt.strftime("%Y-%m-%d"),
                prev_end_dt.strftime("%Y-%m-%d"),
            )

            month_category_start = rolling_start
            month_category_end = rolling_end
        else:
            # Strict: calendar month
            current_start, current_end = self._get_month_bounds(now.year, now.month)
            self.monthly_income, self.monthly_expenses = self._get_filtered_totals(
                current_start, current_end
            )
            self.monthly_savings = db.get_savings_total()

            # Previous month for trends
            prev_month = now.replace(day=1) - timedelta(days=1)
            prev_start, prev_end = self._get_month_bounds(
                prev_month.year, prev_month.month
            )
            prev_income, prev_expenses = self._get_filtered_totals(prev_start, prev_end)

            month_category_start = current_start
            month_category_end = current_end

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

        # Chart Data (Income vs Expenses)
        num_months = 6
        if self.chart_duration == "all":
            earliest_date = db.get_earliest_transaction_date()
            if earliest_date:
                start = datetime.strptime(earliest_date, "%Y-%m-%d")
                num_months = (
                    (now.year - start.year) * 12 + (now.month - start.month) + 1
                )
            else:
                num_months = 6
        else:
            num_months = int(self.chart_duration)

        if num_months < 1:
            num_months = 6

        start_year = now.year
        start_month = now.month - (num_months - 1)
        while start_month <= 0:
            start_month += 12
            start_year -= 1

        self.chart_data = self._build_chart_data(start_year, start_month, num_months)

        # Category dates: use month-mode when "1M" selected, otherwise chart duration
        if self.chart_duration == "1":
            category_start_date = month_category_start
            category_end_date = month_category_end
        else:
            category_start_date = f"{start_year}-{start_month:02d}-01"
            category_end_date = now.strftime("%Y-%m-%d")

        txs = db.get_transactions_by_period(category_start_date, category_end_date)
        self.category_expenses = {}
        self.category_incomes = {}
        for transaction in txs:
            if self._is_transfer_transaction(transaction):
                continue

            desc = (transaction["description"] or t("dash_other_category")).strip()

            if transaction["transaction_type"] == "expense":
                self.category_expenses[desc] = (
                    self.category_expenses.get(desc, 0) + transaction["amount"]
                )
            elif transaction["transaction_type"] == "income":
                self.category_incomes[desc] = (
                    self.category_incomes.get(desc, 0) + transaction["amount"]
                )

        # Account Distribution Data
        self.account_distribution = db.get_accounts_distribution()
        self.max_categories_pie = int(db.get_setting("max_categories_pie", "5") or "5")

    def _build_stat_card(
        self,
        title: str,
        value: float,
        trend: float,
        icon: Any,
        icon_bg: str,
        icon_color: str,
        trend_semantic: str = "normal",
    ) -> ft.Container:
        text_color = PeadraTheme.text
        bg_card = (
            PeadraTheme.surface
        )

        is_positive = trend > 0
        if trend_semantic == "reverse":
            is_good = not is_positive
        else:
            is_good = is_positive

        trend_color = PeadraTheme.success if is_good else PeadraTheme.error
        trend_icon = ft.Icons.NORTH_EAST if is_good else ft.Icons.SOUTH_EAST
        trend_text = f"{'+' if is_positive else ''}{trend:.1f}%"

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Container(
                                content=ft.Icon(
                                    cast(Any, icon), color=icon_color, size=24
                                ),
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
                            ft.Text(title, size=14, color=PeadraTheme.text_secondary),
                            ft.Text(
                                f"{value:,.2f} {self.currency}",
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
                ft.border.all(1, PeadraTheme.divider)
                if not self.is_dark
                else None
            ),
        )

    def _build_income_expense_chart(self) -> ft.Container:
        text_color = PeadraTheme.text
        bg_card = (
            PeadraTheme.surface
        )

        dates = [d["month_label"] for d in self.chart_data]
        incomes = [round(d["income"], 2) for d in self.chart_data]
        expenses = [round(d["expenses"], 2) for d in self.chart_data]
        patrimonies = [round(d["patrimony"], 2) for d in self.chart_data]

        if not dates:
            return ft.Container()

        # Calculate ranges for scaling
        raw_max_patrimony = max(patrimonies) if patrimonies else 0
        raw_min_patrimony = min(patrimonies) if patrimonies else 0
        raw_max_bars = max(incomes + expenses + [0])

        # Helper: round a value to a "nice" number (1, 2, 5 multiples of powers of 10)
        def nice_ceil(val):
            """Round up to the nearest nice number."""
            if val <= 0:
                return 0

            exp = math.floor(math.log10(val))
            base = 10**exp
            frac = val / base
            if frac <= 1:
                nice = 1
            elif frac <= 2:
                nice = 2
            elif frac <= 5:
                nice = 5
            else:
                nice = 10
            return nice * base

        # Dynamic scaling for patrimony line
        patrimony_spread = raw_max_patrimony - raw_min_patrimony
        if patrimony_spread == 0:
            patrimony_spread = (
                nice_ceil(raw_max_patrimony * 0.1) if raw_max_patrimony > 0 else 100
            )

        # Add padding (50% of spread above and below)
        padding = patrimony_spread * 0.5
        min_y_patrimony = max(0, raw_min_patrimony - padding)

        # If the minimum is very close to zero compared to the max, start at 0
        if min_y_patrimony < raw_max_patrimony * 0.1:
            min_y_patrimony = 0

        max_y_patrimony = raw_max_patrimony + padding

        # Buffer for flat lines
        if max_y_patrimony == min_y_patrimony:
            max_y_patrimony += 100

        # Snap min/max to nice round numbers so axis labels are clean (e.g. 0, 2K, 4K, 6K)
        y_range = max_y_patrimony - min_y_patrimony
        nice_interval = nice_ceil(y_range / 4)

        # Ensure nice_interval is at least 1 to prevent division by zero
        if nice_interval <= 0:
            nice_interval = 1

        min_y_patrimony = math.floor(min_y_patrimony / nice_interval) * nice_interval
        max_y_patrimony = math.ceil(max_y_patrimony / nice_interval) * nice_interval
        # Ensure at least the raw data fits
        if max_y_patrimony < raw_max_patrimony:
            max_y_patrimony += nice_interval

        # Bar chart Y-axis scaling
        if raw_max_bars == 0:
            raw_max_bars = 100
        nice_bar_interval = nice_ceil(raw_max_bars / 4) if raw_max_bars > 0 else 100
        if nice_bar_interval > 0:
            max_y_bars = math.ceil(raw_max_bars / nice_bar_interval) * nice_bar_interval
        else:
            max_y_bars = 100
        # Always add one interval of padding so bars never touch the top edge
        max_y_bars += nice_bar_interval

        # Dynamic bar width based on number of data points
        bar_width = max(4, min(15, 120 // max(1, len(dates))))
        bar_spacing = max(1, min(4, bar_width // 3))

        # Create bar chart groups for income and expenses
        bar_groups = []
        for i in range(len(dates)):
            bar_groups.append(
                fch.BarChartGroup(
                    x=i,
                    rods=[
                        fch.BarChartRod(
                            from_y=0,
                            to_y=float(incomes[i]),
                            width=bar_width,
                            color=PeadraTheme.chart_income,
                            border_radius=ft.border_radius.vertical(top=4),
                        ),
                        fch.BarChartRod(
                            from_y=0,
                            to_y=float(expenses[i]),
                            width=bar_width,
                            color=PeadraTheme.chart_expense,
                            border_radius=ft.border_radius.vertical(top=4),
                        ),
                    ],
                    spacing=bar_spacing,
                )
            )

        # Helper to build bottom axis labels
        def _make_bottom_labels():
            return [
                fch.ChartAxisLabel(
                    value=i,
                    label=cast(
                        Any,
                        ft.Container(
                            ft.Text(
                                (
                                    dates[i]
                                    if len(dates) <= 12
                                    or i % max(1, len(dates) // 6) == 0
                                    else ""
                                ),
                                size=12,
                                color=PeadraTheme.text_secondary,
                            ),
                            padding=ft.padding.only(top=10),
                        ),
                    ),
                )
                for i in range(len(dates))
            ]

        # --- Bar Chart Card (Inflows / Outflows) ---
        bar_chart_card = ft.Container(
            content=ft.Column(
                cast(
                    List[ft.Control],
                    [
                        ft.Row(
                            cast(
                                List[ft.Control],
                                [
                                    ft.Text(
                                        t("dash_inflows_outflows"),
                                        size=16,
                                        weight=ft.FontWeight.BOLD,
                                        color=text_color,
                                    ),
                                    ft.Row(
                                        cast(
                                            List[ft.Control],
                                            [
                                                ft.Container(
                                                    width=10,
                                                    height=10,
                                                    bgcolor=PeadraTheme.chart_income,
                                                    border_radius=5,
                                                ),
                                                ft.Text(
                                                    t("dash_inflows"),
                                                    color=PeadraTheme.text_secondary,
                                                    size=11,
                                                ),
                                                ft.Container(width=8),
                                                ft.Container(
                                                    width=10,
                                                    height=10,
                                                    bgcolor=PeadraTheme.chart_expense,
                                                    border_radius=5,
                                                ),
                                                ft.Text(
                                                    t("dash_outflows"),
                                                    color=PeadraTheme.text_secondary,
                                                    size=11,
                                                ),
                                            ],
                                        ),
                                        spacing=4,
                                    ),
                                ],
                            ),
                            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        ),
                        ft.Container(height=10),
                        ft.Container(
                            content=cast(
                                ft.Control,
                                fch.BarChart(
                                    groups=bar_groups,
                                    border=ft.border.all(0, ft.Colors.TRANSPARENT),
                                    left_axis=fch.ChartAxis(
                                        label_size=55,
                                        title_size=0,
                                        show_labels=True,
                                    ),
                                    bottom_axis=fch.ChartAxis(
                                        labels=_make_bottom_labels(),
                                        label_size=40,
                                        show_labels=True,
                                    ),
                                    horizontal_grid_lines=fch.ChartGridLines(
                                        interval=nice_bar_interval,
                                        color=PeadraTheme.divider,
                                        width=1,
                                    ),
                                    min_y=0,
                                    max_y=max_y_bars,
                                    tooltip=fch.BarChartTooltip(
                                        bgcolor=PeadraTheme.chart_tooltip_bg
                                    ),
                                    expand=True,
                                ),
                            ),
                            expand=True,
                        ),
                    ],
                ),
            ),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            expand=True,
            border=(
                ft.border.all(1, PeadraTheme.divider)
                if not self.is_dark
                else None
            ),
        )

        # --- Line Chart Card (Total Assets) ---
        line_chart_card = ft.Container(
            content=ft.Column(
                cast(
                    List[ft.Control],
                    [
                        ft.Row(
                            cast(
                                List[ft.Control],
                                [
                                    ft.Text(
                                        t("dash_total_assets"),
                                        size=16,
                                        weight=ft.FontWeight.BOLD,
                                        color=text_color,
                                    ),
                                    ft.Row(
                                        cast(
                                            List[ft.Control],
                                            [
                                                ft.Container(
                                                    width=10,
                                                    height=10,
                                                    bgcolor=PeadraTheme.chart_asset,
                                                    border_radius=5,
                                                ),
                                                ft.Text(
                                                    t("dash_total_assets"),
                                                    color=PeadraTheme.text_secondary,
                                                    size=11,
                                                ),
                                            ],
                                        ),
                                        spacing=4,
                                    ),
                                ],
                            ),
                            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        ),
                        ft.Container(height=10),
                        ft.Container(
                            content=cast(
                                ft.Control,
                                fch.LineChart(
                                    data_series=[
                                        fch.LineChartData(
                                            points=[
                                                fch.LineChartDataPoint(i, float(v))
                                                for i, v in enumerate(patrimonies)
                                            ],
                                            stroke_width=3,
                                            color=PeadraTheme.chart_asset,
                                            curved=True,
                                            rounded_stroke_cap=True,
                                        ),
                                    ],
                                    border=ft.border.all(0, ft.Colors.TRANSPARENT),
                                    horizontal_grid_lines=fch.ChartGridLines(
                                        interval=nice_interval,
                                        color=PeadraTheme.divider,
                                        width=1,
                                    ),
                                    vertical_grid_lines=fch.ChartGridLines(
                                        interval=1, color=ft.Colors.TRANSPARENT
                                    ),
                                    left_axis=fch.ChartAxis(
                                        label_size=55,
                                        title_size=0,
                                        show_labels=True,
                                    ),
                                    bottom_axis=fch.ChartAxis(
                                        labels=_make_bottom_labels(),
                                        label_size=50,
                                        show_labels=True,
                                    ),
                                    min_x=-0.5,
                                    max_x=len(dates) - 0.5,
                                    min_y=min_y_patrimony,
                                    max_y=max_y_patrimony,
                                    expand=True,
                                    tooltip=fch.LineChartTooltip(
                                        bgcolor=PeadraTheme.chart_tooltip_bg
                                    ),
                                ),
                            ),
                            expand=True,
                        ),
                    ],
                ),
            ),
            padding=24,
            bgcolor=bg_card,
            border_radius=20,
            expand=True,
            border=(
                ft.border.all(1, PeadraTheme.divider)
                if not self.is_dark
                else None
            ),
        )

        # Duration selector row
        duration_row = ft.Row(
            cast(
                List[ft.Control],
                [
                    ft.Text(
                        t("dash_cash_flow"),
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.SegmentedButton(
                        selected=[str(self.chart_duration)],
                        on_change=lambda e: self._update_chart_duration(
                            int(list(e.control.selected)[0])
                            if list(e.control.selected)[0].isdigit()
                            else list(e.control.selected)[0]
                        ),
                        segments=[
                            ft.Segment(value="1", label=ft.Text("1M")),
                            ft.Segment(value="3", label=ft.Text("3M")),
                            ft.Segment(value="6", label=ft.Text("6M")),
                            ft.Segment(value="12", label=ft.Text("1Y")),
                            ft.Segment(value="all", label=ft.Text(t("segment_all"))),
                        ],
                        show_selected_icon=False,
                        style=ft.ButtonStyle(
                            padding=ft.padding.symmetric(horizontal=10, vertical=0),
                        ),
                    ),
                ],
            ),
            spacing=20,
            alignment=ft.MainAxisAlignment.START,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        )

        return ft.Container(
            content=ft.Column(
                cast(
                    List[ft.Control],
                    [
                        duration_row,
                        ft.Container(height=10),
                        ft.Row(
                            [bar_chart_card, line_chart_card],
                            spacing=20,
                        ),
                    ],
                ),
            ),
            expand=True,
        )

    def _build_pie_chart(
        self,
        title: str,
        data_dict: dict,
        touched_index_attr_name: str,
        container_attr_name: str,
        empty_msg: str,
        name_to_color: Optional[dict[str, str]] = None,
        max_categories: int = 5,
    ) -> ft.Container:
        text_color = PeadraTheme.text
        bg_card = (
            PeadraTheme.surface
        )

        valid_items: dict[str, float] = {}
        for k, v in data_dict.items():
            if v > 0:
                key = k.capitalize()
                valid_items[key] = valid_items.get(key, 0.0) + v

        sorted_items = sorted(valid_items.items(), key=lambda x: x[1], reverse=True)

        if len(sorted_items) > max_categories:
            top_items = sorted_items[:max_categories]
            other_value = (
                sum(item[1] for item in sorted_items[max_categories:])
                if len(sorted_items) > max_categories
                else 0
            )

            data_points = [{"name": k, "value": v} for k, v in top_items]
            if other_value > 0:
                data_points.append({"name": t("dash_other"), "value": other_value})
        else:
            data_points = [{"name": k, "value": v} for k, v in sorted_items]

        DefaultColors = list(PeadraTheme.chart_palette)

        def _resolve_color(i: int, item_name: str) -> str:
            if name_to_color and item_name in name_to_color:
                return name_to_color[item_name]
            return DefaultColors[i % len(DefaultColors)]

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
                        cast(
                            ft.Control,
                            ft.Container(
                                content=ft.Text(empty_msg, color=PeadraTheme.text_secondary),
                                alignment=ft.Alignment.CENTER,
                                expand=True,
                            ),
                        ),
                    ]
                ),
                bgcolor=bg_card,
                padding=24,
                border_radius=20,
                expand=True,
                border=(
                    ft.border.all(1, PeadraTheme.divider)
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
                color = _resolve_color(i, item["name"])
                is_touched = i == touched_index
                radius = 50 if is_touched else 40

                # Show title (amount) only if touched
                section_title = (
                    f"{item['value']:.2f}{self.currency}" if is_touched else ""
                )

                sections.append(
                    fch.PieChartSection(
                        item["value"],
                        title=section_title,
                        title_style=ft.TextStyle(
                            size=14, color=PeadraTheme.pie_hover_text, weight=ft.FontWeight.BOLD
                        ),
                        color=color,
                        radius=radius,
                    )
                )

            chart = fch.PieChart(
                sections=sections,
                sections_space=5,
                center_space_radius=30,
                expand=True,
                on_event=on_pie_touch,
            )

            # Legend
            legend_items: list[ft.Control] = []
            for i, item in enumerate(data_points):
                color = _resolve_color(i, item["name"])
                legend_items.append(
                    ft.Row(
                        [
                            ft.Container(
                                width=12, height=12, bgcolor=color, border_radius=6
                            ),
                            ft.Text(f"{item['name']}", color=PeadraTheme.text_secondary, size=12),
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
                            ft.Container(
                                cast(ft.Control, chart), expand=True, height=200
                            ),
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
                ft.border.all(1, PeadraTheme.divider)
                if not self.is_dark
                else None
            ),
        )
        setattr(self, container_attr_name, chart_container)
        return chart_container

    def _build_category_chart(self) -> ft.Container:
        return self._build_pie_chart(
            t("dash_month_expenses"),
            self.category_expenses,
            "touched_index_expenses",
            "expenses_chart_container",
            t("dash_no_expenses"),
            max_categories=self.max_categories_pie,
        )

    def _build_income_distribution_chart(self) -> ft.Container:
        return self._build_pie_chart(
            t("dash_month_incomes"),
            self.category_incomes,
            "touched_index_income",
            "income_chart_container",
            t("dash_no_income"),
            max_categories=self.max_categories_pie,
        )

    def _build_account_distribution_chart(self) -> ft.Container:
        text_color = PeadraTheme.text
        bg_card = (
            PeadraTheme.surface
        )

        # Filter out zero or negative balances for the pie chart
        data = [d for d in self.account_distribution if d["value"] > 0]

        # Build color mapping from account data (capitalize to match _build_pie_chart behavior)
        name_to_color = {d["name"].capitalize(): d["color"] for d in data if d.get("color")}

        # Build the dict for the pie chart
        data_dict = {d["name"]: d["value"] for d in data}

        return self._build_pie_chart(
            t("dash_assets_distribution"),
            data_dict,
            "touched_index_assets",
            "assets_chart_container",
            t("dash_no_assets"),
            name_to_color=name_to_color,
            max_categories=self.max_categories_pie,
        )

    def build(self) -> ft.Container:
        text_color = PeadraTheme.text

        # Colors for cards
        green_bg = PeadraTheme.income_bg
        red_bg = PeadraTheme.expense_bg
        blue_bg = PeadraTheme.transfer_bg
        purple_bg = PeadraTheme.savings_bg

        card_row = ft.Row(
            [
                self._build_stat_card(
                    t("dash_bank_balance"),
                    self.balance,
                    self.balance_trend,
                    ft.Icons.ACCOUNT_BALANCE_WALLET,
                    blue_bg,
                    PeadraTheme.transfer_color,
                    "normal",
                ),
                self._build_stat_card(
                    t("trans_income"),
                    self.monthly_income,
                    self.income_trend,
                    ft.Icons.TRENDING_UP,
                    green_bg,
                    PeadraTheme.success,
                    "normal",
                ),
                self._build_stat_card(
                    t("trans_expense"),
                    self.monthly_expenses,
                    self.expenses_trend,
                    ft.Icons.TRENDING_DOWN,
                    red_bg,
                    PeadraTheme.error,
                    "reverse",
                ),
                self._build_stat_card(
                    t("dash_savings"),
                    self.monthly_savings,
                    self.savings_trend,
                    ft.Icons.SAVINGS,
                    purple_bg,
                    PeadraTheme.savings_icon,
                    "normal",
                ),
            ],
            spacing=20,
        )

        self.chart_container_main = ft.Container(
            content=self._build_income_expense_chart(),
            height=460,
        )
        charts_row_1 = self.chart_container_main

        self.charts_row_2 = ft.Container(
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
        )

        username = db.get_setting("user_name", "")
        welcome_text = (
            f"{t('dash_welcome')} {username}{t('dash_overview')}"
            if username
            else f"{t('dash_welcome')} {t('dash_overview')}"
        )

        content = ft.Column(
            [
                ft.Container(
                    content=ft.Column(
                        [
                            ft.Text(
                                t("dash_title"),
                                size=32,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.Text(
                                welcome_text,
                                size=16,
                                color=PeadraTheme.text_secondary,
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
                self.charts_row_2,
            ],
            scroll=ft.ScrollMode.AUTO,
            expand=True,
            spacing=0,
        )

        return ft.Container(
            content=content,
            padding=ft.padding.only(left=30, right=30, top=30, bottom=8),
            expand=True,
        )

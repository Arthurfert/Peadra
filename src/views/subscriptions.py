"""
Vue Subscriptions pour Peadra.
Permet de visualiser et gérer les transactions récurrentes / abonnements, avec un affichage calendrier.
"""

import flet as ft
from datetime import datetime, date, timedelta
from typing import Callable, List, Dict, Any
import calendar

from ..components.theme import PeadraTheme
from ..components.modals import TransactionModal, TransactionDetailsModal
from ..database.db_manager import db
from ..i18n import t


class SubscriptionsView:
    """Vue des abonnements et transactions récurrentes."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.recurring_transactions = []
        self.current_month = datetime.now()
        self._load_data()

    def update_theme(self, is_dark: bool):
        self.is_dark = is_dark

    def refresh(self):
        self._load_data()

    def _load_data(self):
        self.recurring_transactions = db.get_recurring_transactions(display_month=self.current_month.date())
        self.categories = db.get_all_categories()
        self.currency = db.get_setting("currency", "€") or "€"

    def _save_transaction(self, data: dict):
        """Met à jour une transaction récurrente."""
        if "id" in data:
            db.update_recurring_transaction(
                id=data["id"],
                description=data["description"],
                amount=data["amount"],
                transaction_type=data["transaction_type"],
                frequency=data.get("frequency", "monthly"),  # fallback par défaut
                start_date=data["date"],
                interval=data.get("interval", 1),
                category_id=data.get("category_id"),
                end_date=data.get("end_date"),
            )

            # Recalculer les prochaines échéances
            db.process_recurring_transactions()

            snack = ft.SnackBar(
                ft.Text(t("sub_update_success"), color=ft.Colors.WHITE),
                bgcolor=PeadraTheme.SUCCESS,
            )
            self.page.overlay.append(snack)
            snack.open = True

            self.on_data_change()
            self.refresh()
            self.page.update()
        else:
            # S'il s'agit d'une création depuis la vue (pas utilisé actuellement car le bouton plus est ailleurs)
            pass

    def _delete_transaction(self, id: int):
        """Désactive / Supprime une transaction récurrente."""
        conn = db._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE recurring_transactions SET active = 0 WHERE id = ?", (id,)
        )
        conn.commit()

        snack = ft.SnackBar(
            ft.Text(t("msg_subscription_deleted"), color=ft.Colors.WHITE),
            bgcolor=ft.Colors.GREEN,
        )
        self.page.overlay.append(snack)
        snack.open = True

        self.on_data_change()
        self.refresh()
        self.page.update()

    def _show_transaction_details(self, tx: Dict[str, Any], date_str: str):
        # Créer un dictionnaire de transaction classique pour le modal à partir de la transaction récurrente
        mock_tx = {
            "id": tx.get("id"),
            "date": date_str,
            "description": tx.get("description", "Recurring Transaction"),
            "amount": tx.get("amount", 0),
            "transaction_type": tx.get("transaction_type", "expense"),
            "category_name": tx.get("category_name", "Recurring"),
            "notes": f"Frequency : {tx.get('frequency', '')}\nStart Date : {tx.get('start_date', '')}\nNext Due Date : {tx.get('next_due_date', '')}",
        }

        def on_edit():
            """Ouvre le modal d'édition."""
            modal = TransactionModal(
                page=self.page,
                categories=self.categories,
                on_save=self._save_transaction,
                is_dark=self.is_dark,
                transaction_type=tx["transaction_type"],
            )
            modal.show(tx)

        def on_delete():
            self._delete_transaction(tx["id"])

        modal = TransactionDetailsModal(
            self.page, mock_tx, on_edit=on_edit, on_delete=on_delete
        )
        modal.show()

    def _prev_month(self, e):
        first_day = self.current_month.replace(day=1)
        prev_month = first_day - timedelta(days=1)
        self.current_month = prev_month
        self.refresh()
        if hasattr(self, "calendar_container"):
            self.calendar_container.content = self._build_calendar()
            self.calendar_container.update()
        else:
            self.page.update()

    def _next_month(self, e):
        days_in_month = calendar.monthrange(
            self.current_month.year, self.current_month.month
        )[1]
        last_day = self.current_month.replace(day=days_in_month)
        next_month = last_day + timedelta(days=1)
        self.current_month = next_month
        self.refresh()
        if hasattr(self, "calendar_container"):
            self.calendar_container.content = self._build_calendar()
            self.calendar_container.update()
        else:
            self.page.update()

    def _build_calendar(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        border_color = ft.Colors.with_opacity(0.1, text_color)

        month_name = self.current_month.strftime("%B %Y")

        header = ft.Row(
            [
                ft.IconButton(
                    ft.Icons.CHEVRON_LEFT,
                    on_click=self._prev_month,
                    icon_color=text_color,
                ),
                ft.Container(
                    content=ft.Text(
                        month_name, size=20, weight=ft.FontWeight.BOLD, color=text_color
                    ),
                    width=200,
                    alignment=ft.Alignment.CENTER,
                ),
                ft.IconButton(
                    ft.Icons.CHEVRON_RIGHT,
                    on_click=self._next_month,
                    icon_color=text_color,
                ),
            ],
            alignment=ft.MainAxisAlignment.CENTER,
        )

        days_of_week = [
            t("day_mon"),
            t("day_tue"),
            t("day_wed"),
            t("day_thu"),
            t("day_fri"),
            t("day_sat"),
            t("day_sun"),
        ]
        dow_row = ft.Row(
            [
                ft.Container(
                    content=ft.Text(
                        day,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                        text_align=ft.TextAlign.CENTER,
                    ),
                    expand=1,
                    alignment=ft.Alignment(0, 0),
                )
                for day in days_of_week
            ],
        )

        cal = calendar.monthcalendar(self.current_month.year, self.current_month.month)

        month_grid = ft.Column(spacing=2)

        for week in cal:
            week_row = ft.Row(spacing=2)
            for day in week:
                if day == 0:
                    day_container = ft.Container(
                        expand=1, height=80, bgcolor=ft.Colors.TRANSPARENT
                    )
                else:
                    date_obj = date(
                        self.current_month.year, self.current_month.month, day
                    )
                    today = datetime.now().date()

                    is_today = date_obj == today

                    # Find if any transaction falls on this day
                    day_txs = []
                    for tx in self.recurring_transactions:
                        try:
                            start_date = datetime.strptime(
                                tx["start_date"], "%Y-%m-%d"
                            ).date()
                            end_date = (
                                datetime.strptime(tx["end_date"], "%Y-%m-%d").date()
                                if tx.get("end_date")
                                else None
                            )
                            frequency = tx["frequency"]
                            interval = max(1, tx.get("interval", 1))

                            # Check if date_obj is in valid range
                            if date_obj < start_date or (
                                end_date and date_obj > end_date
                            ):
                                continue

                            # Calculate occurrences based on frequency
                            if frequency == "daily":
                                days_diff = (date_obj - start_date).days
                                if days_diff % interval == 0:
                                    day_txs.append(tx)

                            elif frequency == "weekly":
                                days_diff = (date_obj - start_date).days
                                if days_diff % (7 * interval) == 0:
                                    day_txs.append(tx)

                            elif frequency == "monthly":
                                # Check if same day of month
                                # Handle end of month edge cases (e.g. start on 31st)
                                is_due = False

                                # Exact day match
                                if date_obj.day == start_date.day:
                                    # Check interval
                                    months_diff = (
                                        (date_obj.year - start_date.year) * 12
                                        + date_obj.month
                                        - start_date.month
                                    )
                                    if months_diff % interval == 0:
                                        is_due = True

                                # Edge case: target is last day of month, but didn't match start_date.day
                                elif date_obj.day != start_date.day:
                                    # If start date was e.g. 31, and current month only has 30 days,
                                    # then it should trigger on the 30th
                                    days_in_current_month = calendar.monthrange(
                                        date_obj.year, date_obj.month
                                    )[1]
                                    if (
                                        date_obj.day == days_in_current_month
                                        and start_date.day > days_in_current_month
                                    ):
                                        months_diff = (
                                            (date_obj.year - start_date.year) * 12
                                            + date_obj.month
                                            - start_date.month
                                        )
                                        if months_diff % interval == 0:
                                            is_due = True

                                if is_due:
                                    day_txs.append(tx)

                            elif frequency == "yearly":
                                if (
                                    date_obj.month == start_date.month
                                    and date_obj.day == start_date.day
                                ):
                                    years_diff = date_obj.year - start_date.year
                                    if years_diff % interval == 0:
                                        day_txs.append(tx)
                                        # (Edge case for leap year Feb 29 omitted for simplicity, could be added similar to end of month)

                        except Exception as e:
                            pass

                    day_content: List[ft.Control] = [
                        ft.Text(
                            str(day),
                            color=PeadraTheme.ACCENT if is_today else text_color,
                            weight=ft.FontWeight.BOLD
                            if is_today
                            else ft.FontWeight.NORMAL,
                        )
                    ]

                    for tx in day_txs:
                        color = (
                            ft.Colors.RED_400
                            if tx["transaction_type"] == "expense"
                            else ft.Colors.GREEN_400
                        )
                        day_content.append(
                            ft.Container(
                                content=ft.Text(
                                    f"{tx['description']} ({tx['amount']} {self.currency})",
                                    size=10,
                                    color=ft.Colors.WHITE,
                                    no_wrap=True,
                                ),
                                bgcolor=color,
                                padding=2,
                                border_radius=4,
                                on_click=lambda e,
                                t=tx,
                                d=str(date_obj): self._show_transaction_details(t, d),
                            )
                        )

                    day_bg = (
                        ft.Colors.with_opacity(0.05, text_color)
                        if not is_today
                        else ft.Colors.with_opacity(0.1, PeadraTheme.ACCENT)
                    )

                    day_container = ft.Container(
                        content=ft.Column(day_content, spacing=2),
                        expand=1,
                        height=80,
                        bgcolor=day_bg,
                        border_radius=4,
                        padding=4,
                        alignment=ft.Alignment(-1, -1),
                    )
                week_row.controls.append(day_container)
            month_grid.controls.append(week_row)

        return ft.Container(
            content=ft.Column([header, dow_row, month_grid], spacing=10),
            padding=20,
            bgcolor=bg_color,
            border_radius=16,
        )

    @staticmethod
    def calculate_projection(
        tx: Dict[str, Any], today: date
    ) -> tuple[float, str, bool]:
        """Calcule la projection financière d'une transaction récurrente pour l'année en cours."""
        year = today.year
        start_of_year = date(year, 1, 1)
        end_of_year = date(year, 12, 31)

        # Définir le début de la projection
        start_limit = start_of_year
        start_date_str = tx.get("start_date")
        if start_date_str:
            try:
                start_date = datetime.strptime(start_date_str, "%Y-%m-%d").date()
                start_limit = max(start_of_year, start_date)
            except ValueError:
                pass

        # Définir la fin de la projection
        end_date_str = tx.get("end_date")
        end_limit = end_of_year
        is_total_projection = False

        if end_date_str:
            try:
                end_date = datetime.strptime(end_date_str, "%Y-%m-%d").date()
                if end_date < start_limit:
                    return (
                        0.0,
                        "",
                        False,
                    )  # Date de fin déjà passée avant le début du calcul
                if end_date <= end_of_year:
                    end_limit = end_date
                    is_total_projection = True
            except ValueError:
                pass

        days = max(0, (end_limit - start_limit).days + 1)
        amount = tx.get("amount", 0.0)
        freq = tx.get("frequency", "monthly")
        interval = max(1, tx.get("interval", 1))

        # Approximation du nombre d'occurrences
        if freq == "daily":
            occ = days / interval
        elif freq == "weekly":
            occ = days / (7 * interval)
        elif freq == "monthly":
            months_diff = (end_limit.year - start_limit.year) * 12 + (
                end_limit.month - start_limit.month
            )
            occ = (months_diff + 1) / interval
        elif freq == "yearly":
            years_diff = end_limit.year - start_limit.year
            occ = (years_diff + 1) / interval
        else:
            occ = 0

        yearly_total = amount * occ
        projection_label = (
            t("sub_total_projection")
            if is_total_projection
            else t("sub_projection_year").format(year=year)
        )

        return yearly_total, projection_label, True

    def _build_list(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )

        grid_items = []
        today = datetime.now().date()

        for tx in self.recurring_transactions:
            color = (
                ft.Colors.RED_400
                if tx["transaction_type"] == "expense"
                else ft.Colors.GREEN_400
            )
            card_bg = ft.Colors.with_opacity(0.05, color)

            yearly_total, projection_label, is_valid = self.calculate_projection(
                tx, today
            )

            if not is_valid:
                continue

            card = ft.Container(
                content=ft.Column(
                    [
                        ft.Row(
                            [
                                ft.Icon(ft.Icons.REPEAT, color=color, size=20),
                                ft.Text(
                                    tx["description"],
                                    color=text_color,
                                    weight=ft.FontWeight.BOLD,
                                    size=16,
                                    expand=True,
                                    no_wrap=True,
                                ),
                            ],
                            alignment=ft.MainAxisAlignment.START,
                        ),
                        ft.Text(
                            f"{tx.get('amount', 0.0):.2f} {self.currency}",
                            color=color,
                            weight=ft.FontWeight.BOLD,
                            size=24,
                        ),
                        ft.Text(
                            f"{projection_label}: {yearly_total:.2f} {self.currency}",
                            color=ft.Colors.with_opacity(0.7, text_color),
                            size=11,
                            italic=True,
                        ),
                        ft.Text(
                            f"{t('sub_frequency_next')} {tx.get('next_due_date', '')}",
                            color=ft.Colors.with_opacity(0.5, text_color),
                            size=10,
                        ),
                    ],
                    spacing=5,
                ),
                padding=20,
                bgcolor=card_bg,
                border_radius=16,
                border=ft.border.all(1, ft.Colors.with_opacity(0.1, color)),
                col={"xs": 12, "sm": 6, "md": 4, "lg": 3},
                on_click=lambda e, t=tx: self._show_transaction_details(
                    t, t.get("next_due_date", "")
                ),
            )
            grid_items.append(card)

        if not grid_items:
            grid_items.append(
                ft.Text(
                    t("sub_no_recurring"),
                    color=ft.Colors.with_opacity(0.5, text_color),
                )
            )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(
                        t("sub_all_subscriptions"),
                        size=20,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.ResponsiveRow(grid_items, run_spacing=15),
                ],
                spacing=15,
            ),
            padding=20,
            bgcolor=bg_color,
            border_radius=16,
            expand=True,
        )

    def build(self) -> ft.Container:
        """Construit l'interface de la vue."""

        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        self.calendar_container = ft.Container(content=self._build_calendar())
        self.list_container = ft.Container(content=self._build_list())

        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(
                        t("sub_page_title"),
                        size=28,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    self.calendar_container,
                    self.list_container,
                ],
                spacing=20,
                scroll=ft.ScrollMode.AUTO,
            ),
            padding=30,
            expand=True,
        )

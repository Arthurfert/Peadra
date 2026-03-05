"""
Vue Subscriptions pour Peadra.
Permet de visualiser et gérer les transactions récurrentes / abonnements, avec un affichage calendrier.
"""

import flet as ft
from datetime import datetime, date, timedelta
from typing import Callable, List, Dict, Any
import calendar

from ..components.theme import PeadraTheme
from ..database.db_manager import db


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
        self.recurring_transactions = db.get_recurring_transactions()
        
    def _prev_month(self, e):
        first_day = self.current_month.replace(day=1)
        prev_month = first_day - timedelta(days=1)
        self.current_month = prev_month
        self.refresh()
        if hasattr(self, 'calendar_container'):
            self.calendar_container.content = self._build_calendar()
            self.calendar_container.update()
        else:
            self.page.update()

    def _next_month(self, e):
        days_in_month = calendar.monthrange(self.current_month.year, self.current_month.month)[1]
        last_day = self.current_month.replace(day=days_in_month)
        next_month = last_day + timedelta(days=1)
        self.current_month = next_month
        self.refresh()
        if hasattr(self, 'calendar_container'):
            self.calendar_container.content = self._build_calendar()
            self.calendar_container.update()
        else:
            self.page.update()

    def _build_calendar(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        border_color = ft.Colors.with_opacity(0.1, text_color)
        
        month_name = self.current_month.strftime("%B %Y")
        
        header = ft.Row(
            [
                ft.IconButton(ft.Icons.CHEVRON_LEFT, on_click=self._prev_month, icon_color=text_color),
                ft.Text(month_name, size=20, weight=ft.FontWeight.BOLD, color=text_color),
                ft.IconButton(ft.Icons.CHEVRON_RIGHT, on_click=self._next_month, icon_color=text_color),
            ],
            alignment=ft.MainAxisAlignment.CENTER
        )
        
        days_of_week = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        dow_row = ft.Row(
            [ft.Container(
                content=ft.Text(day, weight=ft.FontWeight.BOLD, color=text_color, text_align=ft.TextAlign.CENTER),
                expand=1,
                alignment=ft.Alignment(0, 0)
            ) for day in days_of_week],
        )

        cal = calendar.monthcalendar(self.current_month.year, self.current_month.month)
        
        month_grid = ft.Column(spacing=2)
        
        for week in cal:
            week_row = ft.Row(spacing=2)
            for day in week:
                if day == 0:
                    day_container = ft.Container(expand=1, height=80, bgcolor=ft.Colors.TRANSPARENT)
                else:
                    date_obj = date(self.current_month.year, self.current_month.month, day)
                    today = datetime.now().date()
                    
                    is_today = date_obj == today
                    
                    # Find if any transaction falls on this day
                    day_txs = []
                    for tx in self.recurring_transactions:
                        try:
                            start_date = datetime.strptime(tx['start_date'], "%Y-%m-%d").date()
                            end_date = datetime.strptime(tx['end_date'], "%Y-%m-%d").date() if tx.get('end_date') else None
                            frequency = tx['frequency']
                            interval = tx.get('interval', 1)
                            
                            # Check if date_obj is in valid range
                            if date_obj < start_date or (end_date and date_obj > end_date):
                                continue

                            # Calculate occurrences based on frequency
                            if frequency == 'daily':
                                days_diff = (date_obj - start_date).days
                                if days_diff % interval == 0:
                                    day_txs.append(tx)
                                    
                            elif frequency == 'weekly':
                                days_diff = (date_obj - start_date).days
                                if days_diff % (7 * interval) == 0:
                                    day_txs.append(tx)
                                    
                            elif frequency == 'monthly':
                                # Check if same day of month
                                # Handle end of month edge cases (e.g. start on 31st)
                                is_due = False
                                
                                # Exact day match
                                if date_obj.day == start_date.day:
                                    # Check interval
                                    months_diff = (date_obj.year - start_date.year) * 12 + date_obj.month - start_date.month
                                    if months_diff % interval == 0:
                                        is_due = True
                                        
                                # Edge case: target is last day of month, but didn't match start_date.day
                                elif date_obj.day != start_date.day:
                                    # If start date was e.g. 31, and current month only has 30 days, 
                                    # then it should trigger on the 30th
                                    days_in_current_month = calendar.monthrange(date_obj.year, date_obj.month)[1]
                                    if date_obj.day == days_in_current_month and start_date.day > days_in_current_month:
                                        months_diff = (date_obj.year - start_date.year) * 12 + date_obj.month - start_date.month
                                        if months_diff % interval == 0:
                                            is_due = True

                                if is_due:
                                    day_txs.append(tx)

                            elif frequency == 'yearly':
                                if date_obj.month == start_date.month and date_obj.day == start_date.day:
                                    years_diff = date_obj.year - start_date.year
                                    if years_diff % interval == 0:
                                        day_txs.append(tx)
                                        # (Edge case for leap year Feb 29 omitted for simplicity, could be added similar to end of month)

                        except Exception as e:
                            pass
                            
                    day_content: List[ft.Control] = [ft.Text(str(day), color=PeadraTheme.ACCENT if is_today else text_color, weight=ft.FontWeight.BOLD if is_today else ft.FontWeight.NORMAL)]
                    
                    for tx in day_txs:
                        color = ft.Colors.RED_400 if tx['transaction_type'] == 'expense' else ft.Colors.GREEN_400
                        day_content.append(
                            ft.Container(
                                content=ft.Text(f"{tx['description']} ({tx['amount']} €)", size=10, color=ft.Colors.WHITE, no_wrap=True),
                                bgcolor=color,
                                padding=2,
                                border_radius=4,
                            )
                        )
                        
                    day_bg = ft.Colors.with_opacity(0.05, text_color) if not is_today else ft.Colors.with_opacity(0.1, PeadraTheme.ACCENT)
                    
                    day_container = ft.Container(
                        content=ft.Column(day_content, spacing=2),
                        expand=1,
                        height=80,
                        bgcolor=day_bg,
                        border_radius=4,
                        padding=4,
                        alignment=ft.Alignment(-1, -1)
                    )
                week_row.controls.append(day_container)
            month_grid.controls.append(week_row)

        return ft.Container(
            content=ft.Column([header, dow_row, month_grid], spacing=10),
            padding=20,
            bgcolor=bg_color,
            border_radius=16,
        )

    def _build_list(self) -> ft.Container:
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        
        list_items = []
        for tx in self.recurring_transactions:
            color = ft.Colors.RED_400 if tx['transaction_type'] == 'expense' else ft.Colors.GREEN_400
            list_items.append(
                ft.ListTile(
                    leading=ft.Icon(ft.Icons.REPEAT, color=color),
                    title=ft.Text(tx['description'], color=text_color, weight=ft.FontWeight.BOLD),
                    subtitle=ft.Text(f"Next due: {tx['next_due_date']} - Frequency: {tx['frequency']}", color=ft.Colors.with_opacity(0.7, text_color)),
                    trailing=ft.Text(f"€{tx['amount']:.2f}", color=color, weight=ft.FontWeight.BOLD, size=16),
                )
            )
            
        if not list_items:
            list_items.append(ft.Text("No recurring transactions found.", color=ft.Colors.with_opacity(0.5, text_color)))

        return ft.Container(
            content=ft.Column([
                ft.Text("All Subscriptions", size=20, weight=ft.FontWeight.BOLD, color=text_color),
                *list_items
            ], spacing=10),
            padding=20,
            bgcolor=bg_color,
            border_radius=16,
            expand=True
        )

    def build(self) -> ft.Container:
        """Construit l'interface de la vue."""
        
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        self.calendar_container = ft.Container(content=self._build_calendar())
        self.list_container = ft.Container(content=self._build_list())
        
        return ft.Container(
            content=ft.Column(
                [
                    ft.Text("Subscriptions & Recurring", size=28, weight=ft.FontWeight.BOLD, color=text_color),
                    self.calendar_container,
                    self.list_container
                ],
                spacing=20,
                scroll=ft.ScrollMode.AUTO,
            ),
            padding=30,
            expand=True,
        )

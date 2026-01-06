"""
Module de navigation pour Peadra.
Barre latérale NavigationRail.
"""

import flet as ft
from typing import Callable
from .theme import PeadraTheme
from ..database.db_manager import db


class NavigationRailComponent:
    """Composant de navigation latérale."""

    def __init__(self, on_change: Callable, is_dark: bool = True):
        self.on_change = on_change
        self.is_dark = is_dark
        self.selected_index = 0

    def _on_navigation_change(self, index: int):
        """Gère le changement de navigation."""
        self.selected_index = index
        if self.on_change:
            self.on_change(self.selected_index)

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def build(self) -> ft.Container:
        """Construit le composant Navigation (Sidebar)."""
        bg_color = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        accent_color = (
            PeadraTheme.ACCENT if self.is_dark else PeadraTheme.PRIMARY_MEDIUM
        )

        # Récupérer le solde actuel
        balance = db.get_total_patrimony()

        def nav_item(icon_off, icon_on, label, index):
            is_selected = self.selected_index == index

            # Couleurs
            if self.is_dark:
                item_bg = (
                    PeadraTheme.PRIMARY_MEDIUM if is_selected else ft.colors.TRANSPARENT
                )
                item_icon = ft.colors.WHITE if is_selected else text_color
                item_text = ft.colors.WHITE if is_selected else text_color
            else:
                item_bg = "#E3F2FD" if is_selected else ft.colors.TRANSPARENT
                item_icon = "#1976D2" if is_selected else text_color
                item_text = "#1976D2" if is_selected else text_color

            return ft.Container(
                content=ft.Row(
                    [
                        ft.Icon(
                            icon_on if is_selected else icon_off,
                            color=item_icon,
                            size=24,
                        ),
                        ft.Text(
                            label,
                            color=item_text,
                            weight=(
                                ft.FontWeight.W_600
                                if is_selected
                                else ft.FontWeight.NORMAL
                            ),
                            size=16,
                        ),
                    ],
                    spacing=12,
                ),
                padding=ft.padding.symmetric(horizontal=16, vertical=12),
                border_radius=8,
                bgcolor=item_bg,
                on_click=lambda _: self._on_navigation_change(index),
                animate=ft.animation.Animation(200, ft.AnimationCurve.EASE_OUT),
            )

        return ft.Container(
            width=280,
            bgcolor=bg_color,
            padding=24,
            content=ft.Column(
                [
                    # Logo
                    ft.Container(
                        content=ft.Row(
                            [
                                ft.Container(
                                    content=ft.Icon(
                                        ft.icons.ACCOUNT_BALANCE_WALLET,
                                        color=ft.colors.WHITE,
                                        size=24,
                                    ),
                                    bgcolor="#1976D2",
                                    padding=8,
                                    border_radius=8,
                                ),
                                ft.Text(
                                    "Peadra",
                                    size=24,
                                    weight=ft.FontWeight.BOLD,
                                    color=text_color,
                                ),
                            ],
                            spacing=12,
                            alignment=ft.MainAxisAlignment.START,
                        ),
                        margin=ft.margin.only(bottom=40),
                    ),
                    # Navigation Items
                    ft.Column(
                        [
                            nav_item(
                                ft.icons.GRID_VIEW,
                                ft.icons.GRID_VIEW_ROUNDED,
                                "Dashboard",
                                0,
                            ),
                            nav_item(
                                ft.icons.RECEIPT_LONG_OUTLINED,
                                ft.icons.RECEIPT_LONG,
                                "Transactions",
                                1,
                            ),
                        ],
                        spacing=8,
                    ),
                    ft.Container(expand=True),
                    # Current Balance Card
                    ft.Container(
                        content=ft.Column(
                            [
                                ft.Text(
                                    "Current Balance", size=14, color=ft.colors.GREY_500
                                ),
                                ft.Text(
                                    f"€{balance:,.2f}",
                                    size=24,
                                    weight=ft.FontWeight.BOLD,
                                    color=text_color,
                                ),
                            ],
                            spacing=4,
                        ),
                        bgcolor=ft.colors.with_opacity(0.05, text_color),
                        padding=20,
                        border_radius=16,
                    ),
                ],
                spacing=0,
            ),
        )

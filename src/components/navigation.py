"""
Module de navigation pour Peadra.
Barre latérale NavigationRail.
"""
import flet as ft
from typing import Callable, Optional
from .theme import PeadraTheme


class NavigationRailComponent:
    """Composant de navigation latérale."""
    
    def __init__(self, on_change: Callable, is_dark: bool = True):
        self.on_change = on_change
        self.is_dark = is_dark
        self.selected_index = 0
    
    def _on_navigation_change(self, e):
        """Gère le changement de navigation."""
        self.selected_index = e.control.selected_index
        if self.on_change:
            self.on_change(self.selected_index)
    
    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
    
    def build(self) -> ft.NavigationRail:
        """Construit le composant NavigationRail."""
        bg_color = PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        indicator_color = PeadraTheme.ACCENT if self.is_dark else PeadraTheme.PRIMARY_MEDIUM
        
        return ft.NavigationRail(
            selected_index=self.selected_index,
            label_type=ft.NavigationRailLabelType.ALL,
            min_width=80,
            min_extended_width=200,
            bgcolor=bg_color,
            indicator_color=indicator_color,
            group_alignment=-0.9,
            destinations=[
                ft.NavigationRailDestination(
                    icon=ft.icons.DASHBOARD_OUTLINED,
                    selected_icon=ft.icons.DASHBOARD,
                    label="Tableau de bord",
                ),
                ft.NavigationRailDestination(
                    icon=ft.icons.RECEIPT_LONG_OUTLINED,
                    selected_icon=ft.icons.RECEIPT_LONG,
                    label="Transactions",
                ),
                ft.NavigationRailDestination(
                    icon=ft.icons.ANALYTICS_OUTLINED,
                    selected_icon=ft.icons.ANALYTICS,
                    label="Analyses",
                ),
                ft.NavigationRailDestination(
                    icon=ft.icons.ACCOUNT_BALANCE_WALLET_OUTLINED,
                    selected_icon=ft.icons.ACCOUNT_BALANCE_WALLET,
                    label="Actifs",
                ),
            ],
            on_change=self._on_navigation_change,
        )

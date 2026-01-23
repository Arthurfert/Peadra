"""
Module de gestion des thèmes pour Peadra.
Design Glassmorphism avec palette Armorique (bleus profonds et gris ardoise).
"""

import flet as ft
from typing import Optional, Any, List


class PeadraTheme:
    """Gestionnaire de thèmes pour l'application Peadra."""

    # Couleurs principales - Palette Armorique
    PRIMARY_DARK = "#081019"  # Bleu nuit profond
    PRIMARY_MEDIUM = "#161F31"  # Bleu marine
    PRIMARY_LIGHT = "#54687E"  # Bleu gris
    ACCENT = "#6FA4E8"  # Bleu ardoise
    SURFACE = "#E0E1DD"  # Gris clair

    # Couleurs pour le mode clair
    LIGHT_BG = "#FFFFFF"
    LIGHT_SURFACE = "#E8E7F0"
    LIGHT_TEXT = "#181F2D"
    LIGHT_TEXT_SECONDARY = "#2D4056"

    # Couleurs pour le mode sombre
    DARK_BG = "#0D1B2A"
    DARK_SURFACE = "#1B263B"
    DARK_TEXT = "#E0E1DD"
    DARK_TEXT_SECONDARY = "#778DA9"

    # Couleurs d'accent pour les catégories
    CASH_COLOR = "#4CAF50"  # Vert
    IMMO_COLOR = "#FF9800"  # Orange
    BOURSE_COLOR = "#2196F3"  # Bleu

    # Couleurs fonctionnelles
    SUCCESS = "#4CAF50"
    WARNING = "#FFC107"
    ERROR = "#F44336"
    INFO = "#2196F3"

    # Glassmorphism properties
    GLASS_BLUR = 10
    GLASS_OPACITY_LIGHT = 0.7
    GLASS_OPACITY_DARK = 0.3

    @staticmethod
    def get_light_theme() -> ft.Theme:
        """Retourne le thème clair."""
        return ft.Theme(
            color_scheme_seed=PeadraTheme.PRIMARY_MEDIUM,
            color_scheme=ft.ColorScheme(
                primary=PeadraTheme.PRIMARY_MEDIUM,
                on_primary=ft.Colors.WHITE,
                secondary=PeadraTheme.ACCENT,
                on_secondary=ft.Colors.WHITE,
                surface=PeadraTheme.LIGHT_SURFACE,
                on_surface=PeadraTheme.LIGHT_TEXT,
                error=PeadraTheme.ERROR,
                on_error=ft.Colors.WHITE,
            ),
            font_family="Segoe UI",
            use_material3=True,
        )

    @staticmethod
    def get_dark_theme() -> ft.Theme:
        """Retourne le thème sombre."""
        return ft.Theme(
            color_scheme_seed=PeadraTheme.PRIMARY_DARK,
            color_scheme=ft.ColorScheme(
                primary=PeadraTheme.ACCENT,
                on_primary=PeadraTheme.DARK_BG,
                secondary=PeadraTheme.PRIMARY_LIGHT,
                on_secondary=ft.Colors.WHITE,
                surface=PeadraTheme.DARK_SURFACE,
                on_surface=PeadraTheme.DARK_TEXT,
                error=PeadraTheme.ERROR,
                on_error=ft.Colors.WHITE,
            ),
            font_family="Segoe UI",
            use_material3=True,
        )

    @staticmethod
    def glass_container(
        content: ft.Control,
        is_dark: bool = True,
        padding: int = 20,
        border_radius: int = 16,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> ft.Container:
        """Crée un conteneur avec effet Glassmorphism."""
        if is_dark:
            bg_color = ft.Colors.with_opacity(PeadraTheme.GLASS_OPACITY_DARK, "#1B263B")
            border_color = ft.Colors.with_opacity(0.3, "#778DA9")
        else:
            bg_color = ft.Colors.with_opacity(
                PeadraTheme.GLASS_OPACITY_LIGHT, "#FFFFFF"
            )
            border_color = ft.Colors.with_opacity(0.1, "#1B263B")

        return ft.Container(
            content=content,
            padding=padding,
            border_radius=border_radius,
            width=width,
            height=height,
            bgcolor=bg_color,
            border=ft.border.all(1, border_color),
            shadow=ft.BoxShadow(
                spread_radius=0,
                blur_radius=20,
                color=ft.Colors.with_opacity(0.1, "#000000"),
                offset=ft.Offset(0, 4),
            ),
        )

    @staticmethod
    def card(
        content: ft.Control,
        is_dark: bool = True,
        padding: int = 16,
        border_radius: int = 12,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> ft.Container:
        """Crée une carte stylisée."""
        if is_dark:
            bg_color = PeadraTheme.DARK_SURFACE
            border_color = "rgba(119, 141, 169, 0.2)"
        else:
            bg_color = PeadraTheme.LIGHT_SURFACE
            border_color = "rgba(27, 38, 59, 0.1)"

        return ft.Container(
            content=content,
            padding=padding,
            border_radius=border_radius,
            width=width,
            height=height,
            bgcolor=bg_color,
            border=ft.border.all(1, border_color),
            shadow=ft.BoxShadow(
                spread_radius=0,
                blur_radius=8,
                color="rgba(0, 0, 0, 0.15)",
                offset=ft.Offset(0, 2),
            ),
        )

    @staticmethod
    def stat_card(
        title: str,
        value: str,
        icon: Any,
        color: str,
        is_dark: bool = True,
        trend: Optional[str] = None,
        trend_positive: bool = True,
    ) -> ft.Container:
        """Crée une carte de statistique."""
        text_color = PeadraTheme.DARK_TEXT if is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = (
            PeadraTheme.DARK_TEXT_SECONDARY
            if is_dark
            else PeadraTheme.LIGHT_TEXT_SECONDARY
        )

        trend_content = []
        if trend:
            trend_color = PeadraTheme.SUCCESS if trend_positive else PeadraTheme.ERROR
            trend_icon = ft.Icons.NORTH_EAST if trend_positive else ft.Icons.SOUTH_EAST
            trend_content = [
                ft.Row(
                    controls=[
                        ft.Icon(trend_icon, size=14, color=trend_color),
                        ft.Text(
                            trend,
                            size=12,
                            color=trend_color,
                            weight=ft.FontWeight.W_500,
                        ),
                    ],
                    spacing=4,
                )
            ]

        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Container(
                                content=ft.Icon(
                                    icon,
                                    size=24,
                                    color=ft.Colors.WHITE,
                                ),
                                bgcolor=color,
                                border_radius=8,
                                padding=8,
                            ),
                            ft.Text(
                                title,
                                size=14,
                                color=secondary_color,
                                weight=ft.FontWeight.W_500,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.START,
                        spacing=12,
                    ),
                    ft.Text(
                        value, size=28, color=text_color, weight=ft.FontWeight.BOLD
                    ),
                ]
                + trend_content,
                spacing=8,
            ),
            is_dark=is_dark,
            padding=20,
        )

    @staticmethod
    def format_currency(amount: float, currency: str = "€") -> str:
        """Formate un montant en devise."""
        if amount >= 0:
            return f"{amount:,.2f} {currency}".replace(",", " ").replace(".", ",")
        else:
            return f"-{abs(amount):,.2f} {currency}".replace(",", " ").replace(".", ",")

    @staticmethod
    def gradient_background(is_dark: bool = True) -> ft.LinearGradient:
        """Retourne un dégradé pour le fond."""
        if is_dark:
            return ft.LinearGradient(
                begin=ft.Alignment(-1, -1),
                end=ft.Alignment(1, 1),
                colors=[PeadraTheme.PRIMARY_DARK, PeadraTheme.PRIMARY_MEDIUM],
            )
        else:
            return ft.LinearGradient(
                begin=ft.Alignment(-1, -1),
                end=ft.Alignment(1, 1),
                colors=[PeadraTheme.LIGHT_BG, "#E8EDF2"],
            )

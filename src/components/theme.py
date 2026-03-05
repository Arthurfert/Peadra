"""
Module de gestion des thèmes pour Peadra.
Design Glassmorphism avec palette Armorique (bleus profonds et gris ardoise).
"""

import flet as ft
from typing import Optional, Any


class PeadraTheme:
    """Gestionnaire de thèmes pour l'application Peadra."""

    # Couleurs principales - Palette Armorique
    PRIMARY_DARK = "#081019"  # Bleu nuit profond
    PRIMARY_MEDIUM = "#161F31"  # Bleu marine
    PRIMARY_LIGHT = "#54687E"  # Bleu gris
    ACCENT = "#6FA4E8"  # Bleu ardoise
    SURFACE = "#E9E6DC"  # Gris clair

    # Couleurs pour le mode clair
    LIGHT_BG = "#F0F4FF"
    LIGHT_SURFACE = "#F5FAFF"
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
        return ft.Theme(  # type: ignore[call-arg]
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
        return ft.Theme(  # type: ignore[call-arg]
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

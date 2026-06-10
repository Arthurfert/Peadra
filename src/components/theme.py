"""
Module de gestion des thèmes pour Peadra.
Design Glassmorphism avec palette Armorique (bleus profonds et gris ardoise).
"""

import flet as ft
from typing import Optional, Any
from dataclasses import dataclass


@dataclass
class ThemeColors:
    name: str
    bg: str
    surface: str
    text: str
    text_secondary: str
    primary_dark: str
    primary_medium: str
    primary_light: str
    accent: str
    success: str
    warning: str
    error: str
    info: str
    chart_tooltip_bg: str
    glass_blur: int = 10
    glass_opacity: float = 0.3


class _ThemeMeta(type):
    def __getattr__(cls, name):
        try:
            return getattr(cls.THEMES[cls.current_theme], name)
        except KeyError:
            raise AttributeError(
                f"Unknown theme '{cls.current_theme}'. "
                f"Available: {list(cls.THEMES.keys())}"
            )
        except AttributeError:
            raise AttributeError(f"'{cls.__name__}' has no attribute '{name}'")


class PeadraTheme(metaclass=_ThemeMeta):
    current_theme: str = "dark"

    THEMES: dict[str, ThemeColors] = {
        "light": ThemeColors(
            name="light",
            bg="#F0F4FF",
            surface="#F5FAFF",
            text="#181F2D",
            text_secondary="#2D4056",
            primary_dark="#081019",
            primary_medium="#161F31",
            primary_light="#54687E",
            accent="#6FA4E8",
            success="#4CAF50",
            warning="#FFC107",
            error="#F44336",
            info="#2196F3",
            chart_tooltip_bg="#E3F2FD",
            glass_blur=10,
            glass_opacity=0.7,
        ),
        "dark": ThemeColors(
            name="dark",
            bg="#0D1B2A",
            surface="#1B263B",
            text="#E0E1DD",
            text_secondary="#778DA9",
            primary_dark="#081019",
            primary_medium="#161F31",
            primary_light="#54687E",
            accent="#6FA4E8",
            success="#4CAF50",
            warning="#FFC107",
            error="#F44336",
            info="#2196F3",
            chart_tooltip_bg="#0D1B2A",
            glass_blur=10,
            glass_opacity=0.3,
        ),
    }

    @classmethod
    def set_theme(cls, name: str) -> None:
        if name not in cls.THEMES:
            raise ValueError(
                f"Unknown theme: '{name}'. "
                f"Available: {list(cls.THEMES.keys())}"
            )
        cls.current_theme = name

    @staticmethod
    def get_light_theme() -> ft.Theme:
        colors = PeadraTheme.THEMES["light"]
        return ft.Theme(
            color_scheme_seed=colors.primary_medium,
            color_scheme=ft.ColorScheme(
                primary=colors.primary_medium,
                on_primary=ft.Colors.WHITE,
                secondary=colors.accent,
                on_secondary=ft.Colors.WHITE,
                surface=colors.surface,
                on_surface=colors.text,
                error=colors.error,
                on_error=ft.Colors.WHITE,
            ),
            font_family="Segoe UI",
            use_material3=True,
        )

    @staticmethod
    def get_dark_theme() -> ft.Theme:
        colors = PeadraTheme.THEMES["dark"]
        return ft.Theme(
            color_scheme_seed=colors.primary_dark,
            color_scheme=ft.ColorScheme(
                primary=colors.accent,
                on_primary=colors.bg,
                secondary=colors.primary_light,
                on_secondary=ft.Colors.WHITE,
                surface=colors.surface,
                on_surface=colors.text,
                error=colors.error,
                on_error=ft.Colors.WHITE,
            ),
            font_family="Segoe UI",
            use_material3=True,
        )

    @staticmethod
    def get_flet_theme() -> ft.Theme:
        colors = PeadraTheme.THEMES[PeadraTheme.current_theme]
        is_dark = PeadraTheme.current_theme != "light"
        if is_dark:
            return ft.Theme(
                color_scheme_seed=colors.primary_dark,
                color_scheme=ft.ColorScheme(
                    primary=colors.accent,
                    on_primary=colors.bg,
                    secondary=colors.primary_light,
                    on_secondary=ft.Colors.WHITE,
                    surface=colors.surface,
                    on_surface=colors.text,
                    error=colors.error,
                    on_error=ft.Colors.WHITE,
                ),
                font_family="Segoe UI",
                use_material3=True,
            )
        return ft.Theme(
            color_scheme_seed=colors.primary_medium,
            color_scheme=ft.ColorScheme(
                primary=colors.primary_medium,
                on_primary=ft.Colors.WHITE,
                secondary=colors.accent,
                on_secondary=ft.Colors.WHITE,
                surface=colors.surface,
                on_surface=colors.text,
                error=colors.error,
                on_error=ft.Colors.WHITE,
            ),
            font_family="Segoe UI",
            use_material3=True,
        )

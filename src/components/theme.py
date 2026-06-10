"""
Module de gestion des thèmes pour Peadra.
Design Glassmorphism avec palette Armorique (bleus profonds et gris ardoise).
"""

import flet as ft
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
    border_color: str
    divider: str
    nav_selected_bg: str
    nav_selected_fg: str
    transfer_color: str
    income_bg: str
    expense_bg: str
    transfer_bg: str
    income_icon: str
    expense_icon: str
    transfer_icon: str
    delete_color: str
    add_color: str
    placeholder_color: str
    chart_income: str
    chart_expense: str
    chart_asset: str
    chart_asset_bg: str
    chart_palette: tuple


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
            bg="#F0F4FF",                     # page background
            surface="#e3f8fc",                # cards, containers, sidebar, header
            text="#181F2D",                   # primary text
            text_secondary="#1b4a54",         # secondary text, chart grid lines
            primary_dark="#081019",           # Flet color_scheme_seed (dark)
            primary_medium="#161F31",         # Flet primary, modal buttons, nav selected bg (dark)
            primary_light="#54687E",          # login focus border, import button (light)
            accent="#3B6FB4",                 # buttons, icons, borders, Flet secondary
            success="#4CAF50",                # income amounts, positive trends, snackbars
            warning="#FFC107",                # warning indicators
            error="#F44336",                  # expense amounts, negative trends, error snackbars
            info="#2196F3",                   # info indicators
            chart_tooltip_bg="#E3F2FD",       # chart tooltip background
            border_color="#cbcbcb",           # card/container borders
            divider="#e0e0e0",                # section separators, subtle borders
            nav_selected_bg="#E3F2FD",        # navigation active item background
            nav_selected_fg="#1976D2",        # navigation active item text/icon
            transfer_color="#2196F3",         # transfer transaction icon color
            income_bg="#A5D6A7",              # income row background (soft green)
            expense_bg="#EF9A9A",             # expense row background (soft red)
            transfer_bg="#90CAF9",            # transfer row background (soft blue)
            income_icon="#E8F5E9",            # income icon
            expense_icon="#FFEBEE",           # expense icon
            transfer_icon="#E3F2FD",          # transfer icon
            delete_color="#F44336",           # delete/cancel buttons
            add_color="#1976D2",              # add/create buttons, allowed file types
            placeholder_color="#9E9E9E",      # secondary labels, empty state text, GREY text
            chart_income="#4CAF50",           # income bar/legend color
            chart_expense="#E53935",          # expense bar/legend color
            chart_asset="#7E57C2",            # asset/stat card icon (purple)
            chart_asset_bg="#F3E5F5",         # asset stat card background
            chart_palette=("#4CAF50", "#2196F3", "#FF9800", "#9C27B0", "#F44336", "#009688", "#00BCD4"),  # category donut chart palette
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
            accent="#3B6FB4",
            success="#4CAF50",
            warning="#FFC107",
            error="#F44336",
            info="#2196F3",
            chart_tooltip_bg="#0D1B2A",
            border_color="#cbcbcb",
            divider="#e0e0e0",
            nav_selected_bg="#161F31",
            nav_selected_fg="#FFFFFF",
            transfer_color="#42A5F5",
            income_bg="#81C784",
            expense_bg="#E57373",
            transfer_bg="#64B5F6",
            income_icon="#2E7D32",
            expense_icon="#C62828",
            transfer_icon="#1565C0",
            delete_color="#EF5350",
            add_color="#42A5F5",
            placeholder_color="#9E9E9E",
            chart_income="#4CAF50",
            chart_expense="#E53935",
            chart_asset="#7E57C2",
            chart_asset_bg="#F3E5F5",
            chart_palette=("#4CAF50", "#2196F3", "#FF9800", "#9C27B0", "#F44336", "#009688", "#00BCD4"),
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

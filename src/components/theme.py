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
    savings_bg: str
    savings_icon: str
    pie_hover_text: str
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
    LIGHT_THEMES: frozenset = frozenset({"light", "summer"})

    THEMES: dict[str, ThemeColors] = {
        "light": ThemeColors(
            name="light",
            bg="#f8fafc",                     # page background (Slate 50)
            surface="#ffffff",                # cards, containers, sidebar, header (Pure White)
            text="#0f172a",                   # primary text (Slate 900)
            text_secondary="#475569",         # secondary text, chart grid lines (Slate 600)
            primary_dark="#0f172a",           # Flet color_scheme_seed (dark)
            primary_medium="#1e293b",         # Flet primary, modal buttons, nav selected bg (dark)
            primary_light="#64748b",          # login focus border, import button (light)
            accent="#4f46e5",                 # buttons, icons, borders, Flet secondary (Indigo 600)
            success="#10b981",                # income amounts, positive trends, snackbars
            warning="#f59e0b",                # warning indicators
            error="#ef4444",                  # expense amounts, negative trends, error snackbars
            info="#3b82f6",                   # info indicators
            chart_tooltip_bg="#ffffff",       # chart tooltip background
            border_color="#e2e8f0",           # card/container borders (Slate 200)
            divider="#f1f5f9",                # section separators, subtle borders (Slate 100)
            nav_selected_bg="#e0e7ff",        # navigation active item background (Indigo 100)
            nav_selected_fg="#4f46e5",        # navigation active item text/icon (Indigo 600)
            transfer_color="#2563eb",         # transfer transaction icon color
            income_bg="#d1fae5",              # income row background (soft green)
            expense_bg="#fee2e2",             # expense row background (soft red)
            transfer_bg="#dbeafe",            # transfer row background (soft blue)
            income_icon="#059669",            # income icon
            expense_icon="#dc2626",           # expense icon
            transfer_icon="#1d4ed8",          # transfer icon
            delete_color="#e11d48",           # delete/cancel buttons
            add_color="#2563eb",              # add/create buttons, allowed file types
            placeholder_color="#94a3b8",      # secondary labels, empty state text, GREY text
            chart_income="#10b981",           # income bar/legend color
            chart_expense="#ef4444",          # expense bar/legend color
            chart_asset="#7c3aed",            # asset/stat card icon (purple)
            chart_asset_bg="#f3e8ff",         # asset stat card background
            savings_bg="#f3e8ff",             # savings stat card background
            savings_icon="#7c3aed",           # savings stat card icon
            pie_hover_text="#0f172a",         # pie chart touch/hover label text
            chart_palette=("#10b981", "#3b82f6", "#f59e0b", "#8b5cf6", "#ef4444", "#06b6d4", "#ec4899"),  # category donut chart palette
        ),
        "dark": ThemeColors(
            name="dark",
            bg="#0f172a",                     # page background (Slate 900)
            surface="#1e293b",                # cards, containers, sidebar, header (Slate 800)
            text="#f8fafc",                   # primary text (Slate 50)
            text_secondary="#94a3b8",         # secondary text, chart grid lines (Slate 400)
            primary_dark="#0b0f19",           # Flet color_scheme_seed (dark)
            primary_medium="#131c2c",         # Flet primary, modal buttons, nav selected bg (dark)
            primary_light="#1e293b",          # login focus border, import button (light)
            accent="#5f51f7",                 # buttons, icons, borders, Flet secondary (Violet 500)
            success="#10b981",                # income amounts, positive trends, snackbars
            warning="#f59e0b",                # warning indicators
            error="#ef4444",                  # expense amounts, negative trends, error snackbars
            info="#3b82f6",                   # info indicators
            chart_tooltip_bg="#1e293b",       # chart tooltip background
            border_color="#334155",           # card/container borders (Slate 700)
            divider="#334155",                # section separators, subtle borders
            nav_selected_bg="#334155",        # navigation active item background (Slate 700)
            nav_selected_fg="#ffffff",        # navigation active item text/icon
            transfer_color="#60a5fa",         # transfer transaction icon color
            income_bg="#064e3b",              # income row background (deep soft green)
            expense_bg="#7f1d1d",             # expense row background (deep soft red)
            transfer_bg="#1e3a8a",            # transfer row background (deep soft blue)
            income_icon="#10b981",            # income icon
            expense_icon="#ef4444",           # expense icon
            transfer_icon="#60a5fa",          # transfer icon
            delete_color="#f43f5e",           # delete/cancel buttons
            add_color="#3b82f6",              # add/create buttons, allowed file types
            placeholder_color="#64748b",      # secondary labels, empty state text, GREY text
            chart_income="#10b981",           # income bar/legend color
            chart_expense="#ef4444",          # expense bar/legend color
            chart_asset="#8b5cf6",            # asset/stat card icon (purple)
            chart_asset_bg="#2e1065",         # asset stat card background
            savings_bg="#2e1065",             # savings stat card background
            savings_icon="#a78bfa",           # savings stat card icon
            pie_hover_text="#ffffff",         # pie chart touch/hover label text
            chart_palette=("#10b981", "#3b82f6", "#f59e0b", "#8b5cf6", "#ef4444", "#06b6d4", "#ec4899"),
        ),
        "autumn": ThemeColors(
            name="autumn",
            bg="#000022",                     # Prussian Blue - page background
            surface="#12123a",                # Dark indigo - cards, containers, sidebar, header
            text="#fbf5f3",                   # Snow - primary text
            text_secondary="#c4b5b0",         # Warm muted Snow - secondary text
            primary_dark="#000015",           # Deepest navy - Flet color_scheme_seed
            primary_medium="#000022",         # Prussian Blue - Flet primary
            primary_light="#1a1a5e",          # Lighter indigo - login focus border
            accent="#e28413",                 # Amber Earth - Flet secondary (main accent)
            success="#10b981",                # Emerald - income amounts
            warning="#e28413",                # Amber Earth - warning indicators
            error="#c42847",                  # Intense Cherry - errors
            info="#4a6fa5",                   # Muted blue - info indicators
            chart_tooltip_bg="#1a1a5e",       # Lighter indigo - chart tooltip background
            border_color="#222255",           # Subtle blue border
            divider="#1a1a4e",                # Section separators
            nav_selected_bg="#222255",        # Navigation active item background
            nav_selected_fg="#fbf5f3",        # Snow - navigation active item text/icon
            transfer_color="#e28413",         # Amber Earth - transfer icon color
            income_bg="#0a2e1a",              # Dark green - income row background
            expense_bg="#3a0a1a",             # Dark raspberry - expense row background
            transfer_bg="#0f0f3d",            # Dark blue - transfer row background
            income_icon="#10b981",            # Emerald - income icon
            expense_icon="#de3c4b",           # Raspberry - expense icon
            transfer_icon="#e28413",          # Amber Earth - transfer icon
            delete_color="#c42847",           # Intense Cherry - delete/cancel buttons
            add_color="#e28413",              # Amber Earth - add/create buttons
            placeholder_color="#6b6b8a",      # Muted gray-blue - secondary labels
            chart_income="#10b981",           # Emerald - income bar/legend
            chart_expense="#de3c4b",          # Raspberry - expense bar/legend
            chart_asset="#e28413",            # Amber Earth - asset/stat card icon
            chart_asset_bg="#2a1a05",         # Dark warm - asset stat card background
            savings_bg="#2a1a05",             # Dark warm - savings stat card background
            savings_icon="#e28413",           # Amber Earth - savings stat card icon
            pie_hover_text="#fbf5f3",         # Snow - pie chart hover label
            chart_palette=("#e28413", "#de3c4b", "#c42847", "#fbf5f3", "#10b981", "#4a6fa5", "#8b5cf6"),
        ),
        "summer": ThemeColors(
            name="summer",
            bg="#fcfbe7",                     # Light Sand - page background
            surface="#f9f9f9",                # Bright Snow - cards, containers, sidebar, header
            text="#1a2a4a",                   # Deep navy - primary text
            text_secondary="#1c3d5e",         # Muted sky blue - secondary text
            primary_dark="#0a2a4a",           # Deep sky - Flet color_scheme_seed
            primary_medium="#2a6a9a",         # Medium blue - Flet primary
            primary_light="#5aa9e6",          # Cool Sky - login focus border
            accent="#5aa9e6",                 # Cool Sky - Flet secondary (main accent)
            success="#10b981",                # Emerald - income amounts
            warning="#ffca0a",                # Bright Amber - warning indicators
            error="#e74c3c",                  # Red - errors
            info="#5aa9e6",                   # Cool Sky - info indicators
            chart_tooltip_bg="#ffffff",       # White - chart tooltip background
            border_color="#b8d2e1",           # Subtle sky blue border
            divider="#becbd1",                # Subtle sky blue divider
            nav_selected_bg="#d0e8ff",        # Soft blue - nav selected bg
            nav_selected_fg="#1a3a5a",        # Dark navy - nav selected text
            transfer_color="#5aa9e6",         # Cool Sky - transfer icon color
            income_bg="#d1fae5",              # Soft green - income row background
            expense_bg="#ffe0e0",             # Soft coral - expense row background
            transfer_bg="#d0ecff",            # Soft sky blue - transfer row background
            income_icon="#10b981",            # Emerald - income icon
            expense_icon="#e74c3c",           # Red - expense icon
            transfer_icon="#5aa9e6",          # Cool Sky - transfer icon
            delete_color="#e74c3c",           # Red - delete/cancel buttons
            add_color="#5aa9e6",              # Cool Sky - add/create buttons
            placeholder_color="#7192a8",      # Muted sky - secondary labels
            chart_income="#10b981",           # Emerald - income bar/legend
            chart_expense="#e74c3c",          # Red - expense bar/legend
            chart_asset="#ffca0a",            # Bright Amber - asset/stat card icon
            chart_asset_bg="#fff8e0",         # Warm cream - asset stat card background
            savings_bg="#fff8e0",             # Warm cream - savings stat card background
            savings_icon="#ffe45e",           # Royal Gold - savings stat card icon
            pie_hover_text="#1a2a4a",         # Deep navy - pie chart hover label
            chart_palette=("#5aa9e6", "#7fc8f8", "#ffe45e", "#ffca0a", "#10b981", "#e74c3c", "#8b5cf6"),
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
        is_dark = PeadraTheme.current_theme not in PeadraTheme.LIGHT_THEMES
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

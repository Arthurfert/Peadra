import flet as ft
from src.components.theme import PeadraTheme, ThemeColors

HEX_FIELDS = [
    "bg", "surface", "text", "text_secondary",
    "primary_dark", "primary_medium", "primary_light", "accent",
    "success", "warning", "error", "info",
    "chart_tooltip_bg",
    "chart_income", "chart_expense", "chart_asset",
    "nav_selected_bg", "nav_selected_fg",
    "income_icon", "expense_icon", "transfer_icon",
    "income_bg", "expense_bg", "transfer_bg", "chart_asset_bg",
    "savings_bg", "savings_icon", "pie_hover_text",
    "delete_color", "add_color", "placeholder_color",
    "border_color", "divider",
]


def test_theme_colors_start_with_hash():
    for name, colors in PeadraTheme.THEMES.items():
        for attr in HEX_FIELDS:
            value = getattr(colors, attr)
            assert value.startswith("#"), f"{name}.{attr} = {value!r} does not start with #"


def test_get_light_theme():
    theme = PeadraTheme.get_light_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.use_material3 is True
    assert theme.color_scheme is not None
    assert theme.color_scheme.primary == PeadraTheme.THEMES["light"].primary_medium


def test_get_dark_theme():
    theme = PeadraTheme.get_dark_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.use_material3 is True


def test_set_theme():
    PeadraTheme.set_theme("light")
    assert PeadraTheme.current_theme == "light"
    assert PeadraTheme.bg == PeadraTheme.THEMES["light"].bg
    assert PeadraTheme.surface == PeadraTheme.THEMES["light"].surface
    assert PeadraTheme.text == PeadraTheme.THEMES["light"].text

    PeadraTheme.set_theme("dark")
    assert PeadraTheme.current_theme == "dark"
    assert PeadraTheme.bg == PeadraTheme.THEMES["dark"].bg
    assert PeadraTheme.surface == PeadraTheme.THEMES["dark"].surface
    assert PeadraTheme.text == PeadraTheme.THEMES["dark"].text

    PeadraTheme.set_theme("autumn")
    assert PeadraTheme.current_theme == "autumn"
    assert PeadraTheme.bg == PeadraTheme.THEMES["autumn"].bg
    assert PeadraTheme.surface == PeadraTheme.THEMES["autumn"].surface
    assert PeadraTheme.text == PeadraTheme.THEMES["autumn"].text

    PeadraTheme.set_theme("summer")
    assert PeadraTheme.current_theme == "summer"
    assert PeadraTheme.bg == PeadraTheme.THEMES["summer"].bg
    assert PeadraTheme.surface == PeadraTheme.THEMES["summer"].surface
    assert PeadraTheme.text == PeadraTheme.THEMES["summer"].text


def test_get_flet_theme():
    PeadraTheme.set_theme("light")
    theme = PeadraTheme.get_flet_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.color_scheme is not None

    PeadraTheme.set_theme("dark")
    theme = PeadraTheme.get_flet_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.color_scheme is not None

    PeadraTheme.set_theme("autumn")
    theme = PeadraTheme.get_flet_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.color_scheme is not None

    PeadraTheme.set_theme("summer")
    theme = PeadraTheme.get_flet_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.color_scheme is not None


def test_color_accessors():
    PeadraTheme.set_theme("dark")
    for attr in HEX_FIELDS:
        val = getattr(PeadraTheme, attr)
        assert val.startswith("#"), f"{attr} = {val!r}"


def test_themes_available():
    assert "light" in PeadraTheme.THEMES
    assert "dark" in PeadraTheme.THEMES
    assert "autumn" in PeadraTheme.THEMES
    assert "summer" in PeadraTheme.THEMES
    assert len(PeadraTheme.THEMES) >= 4


def test_theme_colors_dataclass():
    colors = PeadraTheme.THEMES["dark"]
    assert isinstance(colors, ThemeColors)
    assert colors.name == "dark"

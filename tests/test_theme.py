import flet as ft
from src.components.theme import PeadraTheme, ThemeColors


def test_theme_colors_start_with_hash():
    for name, colors in PeadraTheme.THEMES.items():
        for attr in [
            "bg", "surface", "text", "text_secondary",
            "primary_dark", "primary_medium", "primary_light", "accent",
            "success", "warning", "error", "info"
        ]:
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


def test_get_flet_theme():
    PeadraTheme.set_theme("light")
    theme = PeadraTheme.get_flet_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.color_scheme is not None

    PeadraTheme.set_theme("dark")
    theme = PeadraTheme.get_flet_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.color_scheme is not None


def test_color_accessors():
    PeadraTheme.set_theme("dark")
    assert PeadraTheme.bg.startswith("#")
    assert PeadraTheme.surface.startswith("#")
    assert PeadraTheme.text.startswith("#")
    assert PeadraTheme.accent.startswith("#")
    assert PeadraTheme.success.startswith("#")
    assert PeadraTheme.error.startswith("#")


def test_themes_available():
    assert "light" in PeadraTheme.THEMES
    assert "dark" in PeadraTheme.THEMES
    assert len(PeadraTheme.THEMES) >= 2


def test_theme_colors_dataclass():
    colors = PeadraTheme.THEMES["dark"]
    assert isinstance(colors, ThemeColors)
    assert colors.name == "dark"

import flet as ft
from src.components.theme import PeadraTheme


def test_theme_constants():
    """Test que les constantes de couleur sont définies."""
    assert PeadraTheme.PRIMARY_DARK.startswith("#")
    assert PeadraTheme.PRIMARY_MEDIUM.startswith("#")
    assert PeadraTheme.PRIMARY_LIGHT.startswith("#")
    assert PeadraTheme.ACCENT.startswith("#")
    assert PeadraTheme.SURFACE.startswith("#")


def test_get_light_theme():
    """Test la génération du thème clair."""
    theme = PeadraTheme.get_light_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.use_material3 is True
    assert theme.color_scheme is not None
    assert theme.color_scheme.primary == PeadraTheme.PRIMARY_MEDIUM


def test_get_dark_theme():
    """Test la génération du thème sombre."""
    theme = PeadraTheme.get_dark_theme()
    assert isinstance(theme, ft.Theme)
    assert theme.use_material3 is True
    # Note: Depending on implementation, check specific properties
    # Based on reading, it should be similar to light theme test

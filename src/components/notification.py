"""
Système de notifications modernes pour Peadra.
Affiche des toasts élégants en bas à droite de l'écran avec un design épuré.
"""

import threading
import time
import flet as ft
from src.components.theme import PeadraTheme

class ModernNotification(ft.Container):
    def __init__(self, page: ft.Page, message: str, type: str = "info", duration: int = 4000):
        self.target_page = page
        self.message = message
        self.type = type
        self.duration = duration

        # Mapping des types aux couleurs et icônes
        if type == "success":
            border_color = PeadraTheme.success
            bg_color = PeadraTheme.income_bg
            icon = ft.Icons.CHECK_CIRCLE_OUTLINE
            icon_color = PeadraTheme.success
        elif type == "error":
            border_color = PeadraTheme.error
            bg_color = PeadraTheme.expense_bg
            icon = ft.Icons.ERROR_OUTLINE
            icon_color = PeadraTheme.error
        elif type == "warning":
            border_color = PeadraTheme.warning
            bg_color = PeadraTheme.warning + "22" if len(PeadraTheme.warning) == 7 else PeadraTheme.warning
            icon = ft.Icons.WARNING_AMBER_OUTLINED
            icon_color = PeadraTheme.warning
        else:  # info
            border_color = PeadraTheme.info
            bg_color = PeadraTheme.transfer_bg
            icon = ft.Icons.INFO_OUTLINE
            icon_color = PeadraTheme.info

        # Construction du contenu du Toast
        content_row = ft.Row(
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
            controls=[
                ft.Row(
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    controls=[
                        ft.Icon(icon, color=icon_color, size=20),
                        ft.Container(width=5),
                        ft.Container(
                            content=ft.Text(
                                message,
                                color=PeadraTheme.text,
                                size=13,
                                weight=ft.FontWeight.W_500,
                            ),
                            width=220,
                        )
                    ]
                ),
                ft.IconButton(
                    icon=ft.Icons.CLOSE,
                    icon_color=PeadraTheme.text_secondary,
                    icon_size=16,
                    on_click=self.dismiss,
                    padding=0,
                )
            ]
        )

        super().__init__(
            content=content_row,
            bgcolor=bg_color,
            border=ft.border.all(1.5, border_color),
            border_radius=10,
            padding=ft.padding.only(left=12, right=8, top=10, bottom=10),
            width=320,
            bottom=20,
            right=20,
            shadow=ft.BoxShadow(
                spread_radius=1,
                blur_radius=15,
                color=ft.Colors.with_opacity(0.1, "#000000"),
                offset=ft.Offset(0, 5)
            ),
            # Animation initiale (cachée et décalée vers la droite)
            opacity=0,
            offset=ft.Offset(1.2, 0),
            animate_opacity=300,
            animate_offset=300,
        )

    def show(self):
        # Fermer et retirer les notifications existantes pour éviter la superposition
        active_notifications = [c for c in self.target_page.overlay if isinstance(c, ModernNotification)]
        for notif in active_notifications:
            notif.dismiss_now()

        self.is_dismissing = False
        self.target_page.overlay.append(self)
        self.target_page.update()
        
        # Animer l'apparition
        self.opacity = 1
        self.offset = ft.Offset(0, 0)
        self.target_page.update()

        # Démarrer le minuteur de fermeture automatique via run_thread
        if self.duration > 0:
            self.target_page.run_thread(self._auto_dismiss_run)

    def _auto_dismiss_run(self):
        time.sleep(self.duration / 1000.0)
        if not getattr(self, "is_dismissing", False):
            self.dismiss()

    def dismiss(self, e=None):
        if getattr(self, "is_dismissing", False):
            return
        self.is_dismissing = True
        self.target_page.run_thread(self._run_dismiss)

    def _run_dismiss(self):
        self.opacity = 0
        self.offset = ft.Offset(1.2, 0)
        try:
            self.target_page.update()
            time.sleep(0.3)
            self.dismiss_now()
        except Exception:
            pass

    def dismiss_now(self):
        self.is_dismissing = True
        if self in self.target_page.overlay:
            try:
                self.target_page.overlay.remove(self)
                self.target_page.update()
            except Exception:
                pass


def show_notification(page: ft.Page, message: str, type: str = "info", duration: int = 4000):
    """Affiche une notification moderne et élégante."""
    notification = ModernNotification(page, message, type, duration)
    notification.show()

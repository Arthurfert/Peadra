"""
Vue Catégories pour Peadra.
Affiche des cartes compactes par catégorie avec une tendance mensuelle.
"""

import flet as ft
import flet_charts as fch
from typing import Callable, List, Dict, Any, Optional, cast
from datetime import datetime
from ..components.theme import PeadraTheme
from ..components.modals import MergeDescriptionsModal, RenameDescriptionModal
from ..database import db
from ..i18n import t


class CategoriesView:
    """Vue des catégories avec petites cartes et sparkline."""

    MONTH_KEYS = {
        1: "month_january",
        2: "month_february",
        3: "month_march",
        4: "month_april",
        5: "month_may",
        6: "month_june",
        7: "month_july",
        8: "month_august",
        9: "month_september",
        10: "month_october",
        11: "month_november",
        12: "month_december",
    }

    def __init__(
        self,
        page: ft.Page,
        is_dark: bool,
        on_data_change: Callable,
    ):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.chart_duration = 6
        self.content_container: Optional[ft.Container] = None
        self.category_monthly_data: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self.visible_counts: Dict[str, int] = {"expense": 4, "income": 4}
        self.merge_modal: Optional[MergeDescriptionsModal] = None
        self.rename_modal: Optional[RenameDescriptionModal] = None
        self.current_transaction_type: Optional[str] = None
        self._load_data()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()
        if self.content_container is not None:
            self.content_container.content = self._build_content_column()
            try:
                self.content_container.update()
            except RuntimeError:
                # Le control n'est pas attaché à une page (vue non affichée) —
                # ignorer la mise à jour graphique.
                pass

    def _get_period_month_keys(self) -> List[str]:
        """Retourne les mois de la période sélectionnée au format YYYY-MM."""
        num_months = max(1, int(self.chart_duration))
        now = datetime.now()
        year = now.year
        month = now.month
        month_keys: List[str] = []

        for _ in range(num_months):
            month_keys.append(f"{year:04d}-{month:02d}")
            month -= 1
            if month == 0:
                month = 12
                year -= 1

        month_keys.reverse()
        return month_keys

    def _format_description(self, description_name: str) -> str:
        """Retourne un libellé lisible pour une description."""
        clean_name = (description_name or "").strip()
        if not clean_name or clean_name.lower() == "uncategorized":
            fallback = t("dash_other_category")
            return fallback if fallback != "dash_other_category" else "Autre"
        return clean_name[:1].upper() + clean_name[1:]

    def _format_currency(self, amount: float) -> str:
        """Formate un montant avec la devise courante."""
        return f"{amount:,.2f} {self.currency}"

    def _get_month_label(self, month_str: str) -> str:
        """Retourne un libellé de mois traduit et abrégé."""
        try:
            month_number = int(month_str[5:7])
            month_name = t(self.MONTH_KEYS[month_number])
            return str(month_name).capitalize()[:3]
        except Exception:
            return month_str[-2:]

    def _load_data(self):
        """Charge les données des catégories."""
        self.currency = db.get_setting("currency", "€") or "€"
        month_keys = self._get_period_month_keys()
        if month_keys:
            start_date = f"{month_keys[0]}-01"
        else:
            start_date = datetime.now().strftime("%Y-%m-01")
        end_date = datetime.now().strftime("%Y-%m-%d")

        self.top_expenses = db.get_top_descriptions("expense", len(month_keys), limit=0)
        self.top_incomes = db.get_top_descriptions("income", len(month_keys), limit=0)
        self.category_monthly_data = db.get_description_monthly_data(
            start_date, end_date
        )

    def _build_content_column(self) -> ft.Column:
        """Construit le contenu principal de la vue."""
        content_column = ft.Column(
            spacing=24,
            expand=True,
            scroll=ft.ScrollMode.AUTO,
        )

        if self.top_expenses:
            content_column.controls.append(
                self._build_category_section(
                    t("cat_top_expenses"),
                    self.top_expenses,
                    "#E53935",
                    "expense",
                )
            )

        if self.top_incomes:
            content_column.controls.append(
                self._build_category_section(
                    t("cat_top_incomes"),
                    self.top_incomes,
                    "#4CAF50",
                    "income",
                )
            )

        if not content_column.controls:
            content_column.controls.append(
                ft.Container(
                    content=ft.Text(
                        t("cat_no_data_period"),
                        size=14,
                        color=PeadraTheme.DARK_TEXT
                        if self.is_dark
                        else PeadraTheme.LIGHT_TEXT,
                    ),
                    padding=20,
                    border_radius=16,
                    bgcolor=PeadraTheme.DARK_SURFACE
                    if self.is_dark
                    else PeadraTheme.LIGHT_SURFACE,
                )
            )

        return content_column

    def build(self) -> ft.Container:
        """Construit la vue des catégories."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        bg_color = PeadraTheme.DARK_BG if self.is_dark else PeadraTheme.LIGHT_BG

        # Titre principal
        title = ft.Text(
            t("nav_categories"),
            size=32,
            weight=ft.FontWeight.BOLD,
            color=text_color,
        )

        # Contrôles de durée
        duration_controls = self._build_duration_controls()

        content_column = self._build_content_column()

        # Exposer le container principal pour mise à jour ultérieure
        self.content_container = ft.Container(content=content_column, expand=True)

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row([title], alignment=ft.MainAxisAlignment.START),
                    duration_controls,
                    ft.Divider(),
                    self.content_container,
                ],
                spacing=20,
                expand=True,
            ),
            padding=24,
            bgcolor=bg_color,
            expand=True,
        )

    def _build_duration_controls(self) -> ft.Row:
        """Construit les contrôles de sélection de durée."""

        def on_duration_change(e):
            sel = list(e.control.selected)
            if not sel:
                return
            selected_duration = sel[0]
            try:
                self.chart_duration = int(selected_duration)
            except Exception:
                self.chart_duration = selected_duration
            self.refresh()
            self.page.update()

        return ft.Row(
            cast(
                List[ft.Control],
                [
                    ft.Text(t("cat_period_label"), size=14, weight=ft.FontWeight.W_600),
                    ft.Container(
                        content=ft.SegmentedButton(
                            segments=[
                                ft.Segment(value="3", label=ft.Text(t("cat_3_months"))),
                                ft.Segment(value="6", label=ft.Text(t("cat_6_months"))),
                                ft.Segment(value="12", label=ft.Text(t("cat_12_months"))),
                            ],
                            selected=[str(self.chart_duration)],
                            on_change=on_duration_change,
                            allow_empty_selection=False,
                        ),
                        width=350,
                    ),
                ],
            ),
            spacing=12,
            alignment=ft.MainAxisAlignment.START,
        )

    def _build_category_section(
        self,
        title: str,
        categories: List[Dict[str, Any]],
        color: str,
        transaction_type: str,
    ) -> ft.Container:
        """Construit une section de cartes de catégories avec chargement incrémental."""
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        visible_count = self.visible_counts.get(transaction_type, 4)
        max_cards = min(visible_count, len(categories))

        cards = []
        for category in categories[:max_cards]:
            card = self._build_category_card(category, color, transaction_type)
            if card:
                cards.append(card)

        def on_load_more(e):
            self.visible_counts[transaction_type] = (
                self.visible_counts.get(transaction_type, 4) + 4
            )
            if self.content_container is not None:
                self.content_container.content = self._build_content_column()
                try:
                    self.content_container.update()
                except RuntimeError:
                    pass
            self.page.update()

        def on_load_all(e):
            self.visible_counts[transaction_type] = len(categories)
            if self.content_container is not None:
                self.content_container.content = self._build_content_column()
                try:
                    self.content_container.update()
                except RuntimeError:
                    pass
            self.page.update()

        def on_merge_click(e):
            self._show_merge_modal(transaction_type)

        def on_rename_click(e):
            self._show_rename_modal(transaction_type)

        # Construire les contrôles (titre + boutons)
        title_row_controls: List[ft.Control] = [
            ft.Text(title, size=18, weight=ft.FontWeight.BOLD, color=text_color)
        ]

        # Ajouter les boutons d'action
        action_buttons = [
            ft.TextButton(
                t("btn_merge"),
                icon=ft.Icons.MERGE,
                on_click=on_merge_click,
                style=ft.ButtonStyle(color=color),
            ),
            ft.TextButton(
                t("btn_rename"),
                icon=ft.Icons.EDIT,
                on_click=on_rename_click,
                style=ft.ButtonStyle(color=color),
            ),
        ]

        # Ajouter les boutons Load more/Load all si nécessaire
        if len(categories) > visible_count:
            action_buttons.extend(
                [
                    ft.TextButton(
                        t("btn_load_more"),
                        on_click=on_load_more,
                        style=ft.ButtonStyle(color=color),
                    ),
                    ft.TextButton(
                        t("btn_load_all"),
                        on_click=on_load_all,
                        style=ft.ButtonStyle(color=color),
                    ),
                ]
            )

        if action_buttons:
            button_row = ft.Row(cast(List[ft.Control], action_buttons), spacing=8)
            title_row_controls.append(button_row)

        return ft.Container(
            content=ft.Column(
                cast(
                    List[ft.Control],
                    [
                        ft.Row(
                            title_row_controls,
                            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        ),
                        ft.ResponsiveRow(cards, run_spacing=12),
                    ],
                ),
                spacing=12,
            ),
            padding=20,
            bgcolor=bg_card,
            border_radius=16,
            border=(
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _build_category_card(
        self, category: Dict[str, Any], color: str, transaction_type: str
    ) -> Optional[ft.Container]:
        """Construit une petite carte de catégorie avec son sparkline."""
        bg_card = (
            PeadraTheme.DARK_SURFACE if self.is_dark else PeadraTheme.LIGHT_SURFACE
        )
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        description_name = str(category.get("description") or "").strip()
        if description_name not in self.category_monthly_data:
            return None

        category_data = self.category_monthly_data[description_name]

        months = self._get_period_month_keys()
        values = []
        month_labels = []

        for month_str in months:
            month_entry = category_data.get(
                month_str, {"income": 0, "expense": 0, "total": 0}
            )
            if transaction_type == "expense":
                value = month_entry.get("expense", 0)
            else:
                value = month_entry.get("income", 0)
            values.append(max(0, value))

            try:
                month_labels.append(self._get_month_label(month_str))
            except Exception:
                month_labels.append(month_str[-2:])

        if not values or all(v == 0 for v in values):
            return None

        total = float(category.get("total") or sum(values))
        count = int(category.get("count") or 0)
        average_monthly = total / len(months) if months else total

        points = [fch.LineChartDataPoint(i, float(v)) for i, v in enumerate(values)]

        max_y = max(values) * 1.1 if values else 100
        label_indexes = {0, len(months) - 1}
        if len(months) > 3:
            label_indexes.add(len(months) // 2)

        chart = fch.LineChart(
            data_series=[
                fch.LineChartData(
                    points=points,
                    stroke_width=2,
                    color=color,
                    curved=True,
                    rounded_stroke_cap=True,
                )
            ],
            border=ft.border.all(0, ft.Colors.TRANSPARENT),
            horizontal_grid_lines=fch.ChartGridLines(
                interval=max(1, int(max_y / 3)),
                color=ft.Colors.with_opacity(0.1, ft.Colors.GREY),
                width=1,
            ),
            vertical_grid_lines=fch.ChartGridLines(
                interval=1, color=ft.Colors.TRANSPARENT
            ),
            left_axis=fch.ChartAxis(label_size=0, title_size=0, show_labels=False),
            bottom_axis=fch.ChartAxis(
                labels=[
                    fch.ChartAxisLabel(
                        value=i,
                        label=ft.Container(
                            ft.Text(label, size=10, color=text_color), padding=4
                        ),
                    )
                    for i, label in enumerate(month_labels)
                    if i in label_indexes
                ],
                label_size=8,
                show_labels=True,
            ),
            min_x=0,
            max_x=float(len(values) - 1) if len(values) > 1 else 1,
            min_y=0,
            max_y=max_y,
            expand=True,
            tooltip=fch.LineChartTooltip(bgcolor=PeadraTheme.SURFACE),
        )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Text(
                                self._format_description(description_name),
                                size=14,
                                weight=ft.FontWeight.W_700,
                                color=text_color,
                                expand=True,
                                no_wrap=True,
                                overflow=ft.TextOverflow.ELLIPSIS,
                            ),
                            ft.Container(
                                content=ft.Column(
                                    [
                                        ft.Text(
                                            t("cat_avg_per_month"),
                                            size=12,
                                            color=color,
                                        ),
                                        ft.Text(
                                            self._format_currency(average_monthly),
                                            size=14,
                                            weight=ft.FontWeight.BOLD,
                                            color=color,
                                        ),
                                    ],
                                    spacing=0,
                                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                ),
                                padding=ft.padding.symmetric(horizontal=8, vertical=4),
                                border_radius=999,
                                bgcolor=ft.Colors.with_opacity(0.08, color),
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Text(
                        t("cat_transactions_count").format(count=count),
                        size=11,
                        color=ft.Colors.GREY_500,
                    ),
                    ft.Container(
                        content=chart,
                        height=100,
                        padding=ft.padding.only(top=4),
                    ),
                ],
                spacing=12,
            ),
            col={"xs": 12, "sm": 6, "md": 4, "lg": 3},
            padding=20,
            bgcolor=bg_card,
            border_radius=16,
            border=(
                ft.border.all(1, ft.Colors.with_opacity(0.1, ft.Colors.GREY))
                if not self.is_dark
                else None
            ),
        )

    def _show_merge_modal(self, transaction_type: str):
        """Affiche le modal de fusion de descriptions."""
        self.current_transaction_type = transaction_type
        descriptions = db.get_all_unique_descriptions(transaction_type)

        if len(descriptions) < 2:
            snack = ft.SnackBar(
                ft.Text(t("cat_need_at_least_two_descriptions")),
                bgcolor=ft.Colors.WARNING,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return

        self.merge_modal = MergeDescriptionsModal(
            page=self.page,
            descriptions=descriptions,
            transaction_type=transaction_type,
            on_merge=self._on_merge_descriptions,
        )
        self.merge_modal.show()

    def _show_rename_modal(self, transaction_type: str):
        """Affiche le modal de renommage de description."""
        self.current_transaction_type = transaction_type
        descriptions = db.get_all_unique_descriptions(transaction_type)

        if not descriptions:
            snack = ft.SnackBar(
                ft.Text(t("cat_no_descriptions")),
                bgcolor=ft.Colors.WARNING,
            )
            self.page.overlay.append(snack)
            snack.open = True
            self.page.update()
            return

        self.rename_modal = RenameDescriptionModal(
            page=self.page,
            descriptions=descriptions,
            transaction_type=transaction_type,
            on_rename=self._on_rename_description,
        )
        self.rename_modal.show()

    def _on_merge_descriptions(self, source: str, target: str):
        """Callback pour la fusion de descriptions."""
        try:
            success = db.merge_descriptions(source, target)

            if success:
                snack = ft.SnackBar(
                    ft.Text(
                        t("cat_merge_success").format(source=source, target=target)
                    ),
                    bgcolor=ft.Colors.GREEN,
                )
                # Rafraîchir les données et l'affichage
                self.refresh()
                if self.on_data_change:
                    self.on_data_change()
            else:
                snack = ft.SnackBar(
                    ft.Text(t("cat_merge_failed")),
                    bgcolor=ft.Colors.ERROR,
                )
        except Exception as e:
            snack = ft.SnackBar(
                ft.Text(f"Erreur: {str(e)}"),
                bgcolor=ft.Colors.ERROR,
            )

        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

    def _on_rename_description(self, old_description: str, new_description: str):
        """Callback pour le renommage de description."""
        try:
            success = db.rename_description(old_description, new_description)

            if success:
                snack = ft.SnackBar(
                    ft.Text(
                        t("cat_rename_success").format(
                            old=old_description, new=new_description
                        )
                    ),
                    bgcolor=ft.Colors.GREEN,
                )
                # Rafraîchir les données et l'affichage
                self.refresh()
                if self.on_data_change:
                    self.on_data_change()
            else:
                snack = ft.SnackBar(
                    ft.Text(t("cat_rename_failed")),
                    bgcolor=ft.Colors.ERROR,
                )
        except Exception as e:
            snack = ft.SnackBar(
                ft.Text(f"Erreur: {str(e)}"),
                bgcolor=ft.Colors.ERROR,
            )

        self.page.overlay.append(snack)
        snack.open = True
        self.page.update()

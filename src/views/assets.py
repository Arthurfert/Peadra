"""
Vue Actifs pour Peadra.
Gestion des actifs du patrimoine.
"""

import flet as ft
from typing import Callable
from ..components.theme import PeadraTheme
from ..components.modals import AssetModal
from ..database.db_manager import db


class AssetsView:
    """Vue de gestion des actifs."""

    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self.selected_category = "all"
        self.search_query = ""
        self._load_data()

    def _load_data(self):
        """Charge les données des actifs."""
        self.assets = db.get_all_assets()
        self.categories = db.get_all_categories()
        self.patrimony_by_category = db.get_patrimony_by_category()
        self.total_patrimony = db.get_total_patrimony()

    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark

    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()

    def _on_add_asset(self, e):
        """Ouvre le modal pour ajouter un actif."""
        modal = AssetModal(
            page=self.page,
            categories=self.categories,
            on_save=self._save_asset,
            is_dark=self.is_dark,
        )
        modal.show()

    def _on_edit_asset(self, asset: dict):
        """Ouvre le modal pour éditer un actif."""
        modal = AssetModal(
            page=self.page,
            categories=self.categories,
            on_save=self._update_asset,
            is_dark=self.is_dark,
        )
        modal.show(asset)

    def _save_asset(self, data: dict):
        """Enregistre un nouvel actif."""
        db.add_asset(
            name=data["name"],
            category_id=data["category_id"],
            current_value=data["current_value"],
            purchase_value=data.get("purchase_value"),
            purchase_date=data.get("purchase_date"),
            notes=data.get("notes"),
        )
        self._show_snackbar("Actif ajouté avec succès")
        self.on_data_change()

    def _update_asset(self, data: dict):
        """Met à jour un actif existant."""
        asset_id = data.get("id")
        if asset_id:
            # Mettre à jour la valeur
            db.update_asset_value(asset_id, data["current_value"])
            self._show_snackbar("Actif mis à jour")
            self.on_data_change()

    def _on_delete_asset(self, asset_id: int):
        """Supprime un actif après confirmation."""

        def confirm_delete(e):
            dialog.open = False
            self.page.update()
            db.delete_asset(asset_id)
            self._show_snackbar("Actif supprimé")
            self.on_data_change()

        def cancel_delete(e):
            dialog.open = False
            self.page.update()

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Confirmer la suppression"),
            content=ft.Text("Êtes-vous sûr de vouloir supprimer cet actif ?"),
            actions=[
                ft.TextButton("Annuler", on_click=cancel_delete),
                ft.ElevatedButton(
                    "Supprimer",
                    bgcolor=PeadraTheme.ERROR,
                    color=ft.colors.WHITE,
                    on_click=confirm_delete,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _on_update_value(self, asset: dict):
        """Affiche un dialog pour mettre à jour la valeur d'un actif."""
        value_field = ft.TextField(
            label="Nouvelle valeur (€)",
            value=str(asset["current_value"]),
            keyboard_type=ft.KeyboardType.NUMBER,
            autofocus=True,
            width=200,
        )

        def save_value(e):
            try:
                value_str = value_field.value or "0"
                new_value = float(value_str)
                dialog.open = False
                self.page.update()
                db.update_asset_value(asset["id"], new_value)
                self._show_snackbar("Valeur mise à jour")
                self.on_data_change()
            except ValueError:
                value_field.error_text = "Valeur invalide"
                self.page.update()

        def cancel(e):
            dialog.open = False
            self.page.update()

        dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text(f"Mettre à jour : {asset['name']}"),
            content=ft.Container(
                content=value_field,
                padding=ft.padding.only(top=10),
            ),
            actions=[
                ft.TextButton("Annuler", on_click=cancel),
                ft.ElevatedButton(
                    "Enregistrer",
                    bgcolor=PeadraTheme.PRIMARY_MEDIUM,
                    color=ft.colors.WHITE,
                    on_click=save_value,
                ),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )

        self.page.overlay.append(dialog)
        dialog.open = True
        self.page.update()

    def _show_snackbar(self, message: str, success: bool = True):
        """Affiche une notification."""
        color = PeadraTheme.SUCCESS if success else PeadraTheme.ERROR
        snackbar = ft.SnackBar(
            content=ft.Text(message, color=ft.colors.WHITE),
            bgcolor=color,
            duration=2000,
        )
        self.page.overlay.append(snackbar)
        snackbar.open = True
        self.page.update()

    def _filter_assets(self) -> list:
        """Filtre les actifs selon les critères."""
        filtered = self.assets

        # Filtre par catégorie
        if self.selected_category != "all":
            filtered = [
                a for a in filtered if str(a["category_id"]) == self.selected_category
            ]

        # Filtre par recherche
        if self.search_query:
            query = self.search_query.lower()
            filtered = [
                a
                for a in filtered
                if query in a["name"].lower()
                or (a.get("notes") and query in a["notes"].lower())
            ]

        return filtered

    def _on_category_filter_change(self, e):
        """Gère le changement de filtre par catégorie."""
        self.selected_category = e.control.value
        self.on_data_change()

    def _on_search_change(self, e):
        """Gère le changement de recherche."""
        self.search_query = e.control.value
        self.on_data_change()

    def _build_summary_cards(self) -> ft.Container:
        """Construit les cartes de résumé par catégorie."""
        cards = []

        icons_map = {
            "Cash": ft.icons.ACCOUNT_BALANCE,
            "Immobilier": ft.icons.HOME,
            "Bourse": ft.icons.TRENDING_UP,
        }

        for cat in self.patrimony_by_category:
            icon = icons_map.get(cat["name"], ft.icons.CATEGORY)
            percentage = (
                (cat["total"] / self.total_patrimony * 100)
                if self.total_patrimony > 0
                else 0
            )

            card = PeadraTheme.stat_card(
                title=cat["name"],
                value=PeadraTheme.format_currency(cat["total"]),
                icon=icon,
                color=cat["color"],
                is_dark=self.is_dark,
                trend=f"{percentage:.1f}%",
                trend_positive=True,
            )
            cards.append(card)

        # Ajouter la carte total
        cards.insert(
            0,
            PeadraTheme.stat_card(
                title="Total",
                value=PeadraTheme.format_currency(self.total_patrimony),
                icon=ft.icons.ACCOUNT_BALANCE_WALLET,
                color=PeadraTheme.PRIMARY_MEDIUM,
                is_dark=self.is_dark,
            ),
        )

        return ft.Container(
            content=ft.Row(
                controls=cards,
                spacing=16,
                wrap=True,
            ),
            margin=ft.margin.only(bottom=20),
        )

    def _build_toolbar(self) -> ft.Container:
        """Construit la barre d'outils."""
        category_options = [ft.dropdown.Option("all", "Toutes les catégories")]
        for cat in self.categories:
            category_options.append(ft.dropdown.Option(str(cat["id"]), cat["name"]))

        return ft.Container(
            content=ft.Row(
                controls=[
                    # Barre de recherche
                    ft.TextField(
                        hint_text="Rechercher un actif...",
                        prefix_icon=ft.icons.SEARCH,
                        width=300,
                        border_radius=8,
                        on_change=self._on_search_change,
                        value=self.search_query,
                    ),
                    # Filtre par catégorie
                    ft.Dropdown(
                        label="Catégorie",
                        width=200,
                        value=self.selected_category,
                        options=category_options,
                        on_change=self._on_category_filter_change,
                    ),
                    # Spacer
                    ft.Container(expand=True),
                    # Bouton ajouter
                    ft.ElevatedButton(
                        "Nouvel actif",
                        icon=ft.icons.ADD,
                        bgcolor=PeadraTheme.PRIMARY_MEDIUM,
                        color=ft.colors.WHITE,
                        height=45,
                        on_click=self._on_add_asset,
                    ),
                ],
                alignment=ft.MainAxisAlignment.START,
                spacing=16,
            ),
            margin=ft.margin.only(bottom=20),
        )

    def _build_asset_card(self, asset: dict) -> ft.Container:
        """Construit une carte pour un actif."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = (
            PeadraTheme.DARK_TEXT_SECONDARY
            if self.is_dark
            else PeadraTheme.LIGHT_TEXT_SECONDARY
        )

        # Calcul de la plus-value si valeur d'achat disponible
        gain_content = []
        if asset.get("purchase_value") and asset["purchase_value"] > 0:
            gain = asset["current_value"] - asset["purchase_value"]
            gain_percentage = (gain / asset["purchase_value"]) * 100
            gain_color = PeadraTheme.SUCCESS if gain >= 0 else PeadraTheme.ERROR
            gain_prefix = "+" if gain >= 0 else ""

            gain_content = [
                ft.Row(
                    controls=[
                        ft.Icon(
                            (
                                ft.icons.TRENDING_UP
                                if gain >= 0
                                else ft.icons.TRENDING_DOWN
                            ),
                            size=16,
                            color=gain_color,
                        ),
                        ft.Text(
                            f"{gain_prefix}{PeadraTheme.format_currency(gain)} ({gain_prefix}{gain_percentage:.1f}%)",
                            size=13,
                            color=gain_color,
                            weight=ft.FontWeight.W_500,
                        ),
                    ],
                    spacing=4,
                ),
            ]

        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    # En-tête avec catégorie
                    ft.Row(
                        controls=[
                            ft.Container(
                                content=ft.Icon(
                                    ft.icons.ACCOUNT_BALANCE_WALLET,
                                    size=24,
                                    color=asset.get("category_color", "#778DA9"),
                                ),
                                bgcolor=asset.get("category_color", "#778DA9") + "20",
                                border_radius=8,
                                padding=8,
                            ),
                            ft.Column(
                                controls=[
                                    ft.Text(
                                        asset["name"],
                                        size=16,
                                        weight=ft.FontWeight.BOLD,
                                        color=text_color,
                                    ),
                                    ft.Text(
                                        asset.get("category_name", ""),
                                        size=12,
                                        color=secondary_color,
                                    ),
                                ],
                                spacing=2,
                                expand=True,
                            ),
                            # Menu actions
                            ft.PopupMenuButton(
                                icon=ft.icons.MORE_VERT,
                                items=[
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            controls=[
                                                ft.Icon(ft.icons.UPDATE, size=18),
                                                ft.Text("Mettre à jour la valeur"),
                                            ],
                                            spacing=8,
                                        ),
                                        on_click=lambda e, a=asset: self._on_update_value(
                                            a
                                        ),
                                    ),
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            controls=[
                                                ft.Icon(ft.icons.EDIT, size=18),
                                                ft.Text("Modifier"),
                                            ],
                                            spacing=8,
                                        ),
                                        on_click=lambda e, a=asset: self._on_edit_asset(
                                            a
                                        ),
                                    ),
                                    ft.PopupMenuItem(),  # Divider
                                    ft.PopupMenuItem(
                                        content=ft.Row(
                                            controls=[
                                                ft.Icon(ft.icons.DELETE, size=18),
                                                ft.Text("Supprimer"),
                                            ],
                                            spacing=8,
                                        ),
                                        on_click=lambda e, id=asset[
                                            "id"
                                        ]: self._on_delete_asset(id),
                                    ),
                                ],
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.START,
                    ),
                    ft.Divider(height=16, color="transparent"),
                    # Valeur actuelle
                    ft.Text(
                        PeadraTheme.format_currency(asset["current_value"]),
                        size=28,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    # Plus-value
                    *gain_content,
                    ft.Divider(height=12, color="transparent"),
                    # Informations supplémentaires
                    ft.Row(
                        controls=[
                            ft.Column(
                                controls=[
                                    ft.Text(
                                        "Valeur d'achat", size=11, color=secondary_color
                                    ),
                                    ft.Text(
                                        (
                                            PeadraTheme.format_currency(
                                                asset["purchase_value"]
                                            )
                                            if asset.get("purchase_value")
                                            else "-"
                                        ),
                                        size=13,
                                        color=text_color,
                                    ),
                                ],
                                spacing=2,
                            ),
                            ft.Column(
                                controls=[
                                    ft.Text(
                                        "Date d'achat", size=11, color=secondary_color
                                    ),
                                    ft.Text(
                                        asset.get("purchase_date") or "-",
                                        size=13,
                                        color=text_color,
                                    ),
                                ],
                                spacing=2,
                            ),
                        ],
                        spacing=24,
                    ),
                    # Notes
                    (
                        ft.Container(
                            content=ft.Text(
                                asset.get("notes") or "",
                                size=12,
                                color=secondary_color,
                                italic=True,
                                max_lines=2,
                                overflow=ft.TextOverflow.ELLIPSIS,
                            ),
                            margin=ft.margin.only(top=8),
                        )
                        if asset.get("notes")
                        else ft.Container()
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=20,
            width=350,
        )

    def _build_assets_grid(self) -> ft.Container:
        """Construit la grille des actifs."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = (
            PeadraTheme.DARK_TEXT_SECONDARY
            if self.is_dark
            else PeadraTheme.LIGHT_TEXT_SECONDARY
        )

        filtered_assets = self._filter_assets()

        if not filtered_assets:
            return PeadraTheme.card(
                content=ft.Container(
                    content=ft.Column(
                        controls=[
                            ft.Icon(
                                ft.icons.ACCOUNT_BALANCE_WALLET_OUTLINED,
                                size=64,
                                color=secondary_color,
                            ),
                            ft.Text(
                                "Aucun actif",
                                size=18,
                                color=secondary_color,
                            ),
                            ft.Text(
                                "Cliquez sur 'Nouvel actif' pour ajouter votre premier actif",
                                size=14,
                                color=secondary_color,
                            ),
                        ],
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        spacing=12,
                    ),
                    padding=60,
                    alignment=ft.Alignment(0, 0),
                ),
                is_dark=self.is_dark,
            )

        # Grouper par catégorie
        assets_by_category = {}
        for asset in filtered_assets:
            cat_name = asset.get("category_name", "Autre")
            if cat_name not in assets_by_category:
                assets_by_category[cat_name] = []
            assets_by_category[cat_name].append(asset)

        category_sections = []
        for cat_name, assets in assets_by_category.items():
            # Titre de la catégorie
            category_sections.append(
                ft.Container(
                    content=ft.Text(
                        cat_name,
                        size=20,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    margin=ft.margin.only(top=20, bottom=12),
                )
            )

            # Grille des actifs de cette catégorie
            asset_cards = [self._build_asset_card(asset) for asset in assets]
            category_sections.append(
                ft.Row(
                    controls=asset_cards,
                    wrap=True,
                    spacing=16,
                    run_spacing=16,
                )
            )

        return ft.Container(
            content=ft.Column(
                controls=category_sections,
                spacing=8,
            ),
        )

    def build(self) -> ft.Container:
        """Construit la vue complète des actifs."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT

        return ft.Container(
            content=ft.Column(
                controls=[
                    # Titre
                    ft.Text(
                        "Actifs",
                        size=28,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=24, color="transparent"),
                    # Cartes de résumé
                    self._build_summary_cards(),
                    # Barre d'outils
                    self._build_toolbar(),
                    # Grille des actifs
                    self._build_assets_grid(),
                ],
                scroll=ft.ScrollMode.AUTO,
                expand=True,
            ),
            expand=True,
        )

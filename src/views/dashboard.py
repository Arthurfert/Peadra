"""
Vue Tableau de bord pour Peadra.
Affiche un résumé visuel du patrimoine total.
"""
import flet as ft
from typing import Callable
from ..components.theme import PeadraTheme
from ..database.db_manager import db


class DashboardView:
    """Vue du tableau de bord."""
    
    def __init__(self, page: ft.Page, is_dark: bool, on_data_change: Callable):
        self.page = page
        self.is_dark = is_dark
        self.on_data_change = on_data_change
        self._load_data()
    
    def _load_data(self):
        """Charge les données du tableau de bord."""
        self.total_patrimony = db.get_total_patrimony()
        self.patrimony_by_category = db.get_patrimony_by_category()
        self.monthly_summary = db.get_monthly_summary()
        self.recent_transactions = db.get_all_transactions(limit=5)
        self.assets = db.get_all_assets()
    
    def update_theme(self, is_dark: bool):
        """Met à jour le thème."""
        self.is_dark = is_dark
    
    def refresh(self):
        """Rafraîchit les données."""
        self._load_data()
    
    def _build_patrimony_card(self) -> ft.Container:
        """Construit la carte du patrimoine total."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        return PeadraTheme.glass_container(
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Icon(
                                ft.icons.ACCOUNT_BALANCE_WALLET,
                                size=40,
                                color=PeadraTheme.ACCENT,
                            ),
                            ft.Column(
                                controls=[
                                    ft.Text(
                                        "Patrimoine Total",
                                        size=16,
                                        color=PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY,
                                    ),
                                    ft.Text(
                                        PeadraTheme.format_currency(self.total_patrimony),
                                        size=36,
                                        weight=ft.FontWeight.BOLD,
                                        color=text_color,
                                    ),
                                ],
                                spacing=4,
                            ),
                        ],
                        spacing=20,
                        alignment=ft.MainAxisAlignment.START,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=24,
        )
    
    def _build_category_cards(self) -> ft.Row:
        """Construit les cartes par catégorie."""
        cards = []
        
        icons_map = {
            "Cash": ft.icons.ACCOUNT_BALANCE,
            "Immobilier": ft.icons.HOME,
            "Bourse": ft.icons.TRENDING_UP,
        }
        
        for cat in self.patrimony_by_category:
            icon = icons_map.get(cat["name"], ft.icons.CATEGORY)
            
            # Calcul du pourcentage
            percentage = (cat["total"] / self.total_patrimony * 100) if self.total_patrimony > 0 else 0
            
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
        
        return ft.Row(
            controls=cards,
            spacing=16,
            wrap=True,
        )
    
    def _build_monthly_summary_card(self) -> ft.Container:
        """Construit la carte du résumé mensuel."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        income = self.monthly_summary.get("income", 0)
        expenses = self.monthly_summary.get("expenses", 0)
        balance = self.monthly_summary.get("balance", 0)
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        "Résumé du mois",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=20, color="transparent"),
                    ft.Row(
                        controls=[
                            ft.Column(
                                controls=[
                                    ft.Text("Revenus", size=14, color=secondary_color),
                                    ft.Text(
                                        PeadraTheme.format_currency(income),
                                        size=20,
                                        weight=ft.FontWeight.BOLD,
                                        color=PeadraTheme.SUCCESS,
                                    ),
                                ],
                                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                expand=True,
                            ),
                            ft.VerticalDivider(width=1, color=secondary_color),
                            ft.Column(
                                controls=[
                                    ft.Text("Dépenses", size=14, color=secondary_color),
                                    ft.Text(
                                        PeadraTheme.format_currency(expenses),
                                        size=20,
                                        weight=ft.FontWeight.BOLD,
                                        color=PeadraTheme.ERROR,
                                    ),
                                ],
                                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                expand=True,
                            ),
                            ft.VerticalDivider(width=1, color=secondary_color),
                            ft.Column(
                                controls=[
                                    ft.Text("Solde", size=14, color=secondary_color),
                                    ft.Text(
                                        PeadraTheme.format_currency(balance),
                                        size=20,
                                        weight=ft.FontWeight.BOLD,
                                        color=PeadraTheme.SUCCESS if balance >= 0 else PeadraTheme.ERROR,
                                    ),
                                ],
                                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                                expand=True,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_EVENLY,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=20,
        )
    
    def _build_recent_transactions(self) -> ft.Container:
        """Construit la liste des transactions récentes."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        transaction_rows = []
        
        if not self.recent_transactions:
            transaction_rows.append(
                ft.Container(
                    content=ft.Text(
                        "Aucune transaction récente",
                        color=secondary_color,
                        italic=True,
                    ),
                    padding=20,
                    alignment=ft.Alignment(0, 0),
                )
            )
        else:
            for tx in self.recent_transactions:
                is_expense = tx["transaction_type"] == "expense"
                amount_color = PeadraTheme.ERROR if is_expense else PeadraTheme.SUCCESS
                amount_prefix = "-" if is_expense else "+"
                
                row = ft.Container(
                    content=ft.Row(
                        controls=[
                            ft.Container(
                                content=ft.Icon(
                                    ft.icons.RECEIPT_LONG,
                                    size=20,
                                    color=PeadraTheme.ACCENT,
                                ),
                                bgcolor="rgba(119, 141, 169, 0.1)",
                                border_radius=8,
                                padding=8,
                            ),
                            ft.Column(
                                controls=[
                                    ft.Text(
                                        tx["description"],
                                        size=14,
                                        weight=ft.FontWeight.W_500,
                                        color=text_color,
                                    ),
                                    ft.Text(
                                        tx["date"],
                                        size=12,
                                        color=secondary_color,
                                    ),
                                ],
                                spacing=2,
                                expand=True,
                            ),
                            ft.Text(
                                f"{amount_prefix}{PeadraTheme.format_currency(tx['amount'])}",
                                size=14,
                                weight=ft.FontWeight.BOLD,
                                color=amount_color,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    padding=ft.padding.symmetric(vertical=8),
                )
                transaction_rows.append(row)
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Text(
                                "Transactions récentes",
                                size=18,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.TextButton(
                                "Voir tout",
                                on_click=lambda e: None,  # Navigation vers transactions
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Divider(height=16, color="transparent"),
                    ft.Column(
                        controls=transaction_rows,
                        spacing=4,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=20,
        )
    
    def _build_assets_summary(self) -> ft.Container:
        """Construit le résumé des actifs."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        secondary_color = PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY
        
        asset_rows = []
        
        if not self.assets:
            asset_rows.append(
                ft.Container(
                    content=ft.Text(
                        "Aucun actif enregistré",
                        color=secondary_color,
                        italic=True,
                    ),
                    padding=20,
                    alignment=ft.Alignment(0, 0),
                )
            )
        else:
            for asset in self.assets[:5]:
                row = ft.Container(
                    content=ft.Row(
                        controls=[
                            ft.Container(
                                content=ft.Icon(
                                    ft.icons.ACCOUNT_BALANCE_WALLET,
                                    size=20,
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
                                        size=14,
                                        weight=ft.FontWeight.W_500,
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
                            ft.Text(
                                PeadraTheme.format_currency(asset["current_value"]),
                                size=14,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    padding=ft.padding.symmetric(vertical=8),
                )
                asset_rows.append(row)
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Row(
                        controls=[
                            ft.Text(
                                "Mes actifs",
                                size=18,
                                weight=ft.FontWeight.BOLD,
                                color=text_color,
                            ),
                            ft.TextButton(
                                "Voir tout",
                                on_click=lambda e: None,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Divider(height=16, color="transparent"),
                    ft.Column(
                        controls=asset_rows,
                        spacing=4,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=20,
        )
    
    def _build_pie_chart(self) -> ft.Container:
        """Construit le graphique en camembert de la répartition."""
        text_color = PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT
        
        if self.total_patrimony <= 0:
            return PeadraTheme.card(
                content=ft.Column(
                    controls=[
                        ft.Text(
                            "Répartition du patrimoine",
                            size=18,
                            weight=ft.FontWeight.BOLD,
                            color=text_color,
                        ),
                        ft.Container(
                            content=ft.Text(
                                "Ajoutez des actifs pour voir la répartition",
                                color=PeadraTheme.DARK_TEXT_SECONDARY if self.is_dark else PeadraTheme.LIGHT_TEXT_SECONDARY,
                                italic=True,
                            ),
                            padding=40,
                            alignment=ft.Alignment(0, 0),
                        ),
                    ],
                ),
                is_dark=self.is_dark,
                padding=20,
            )
        
        # Créer les sections du pie chart
        sections = []
        legend_items = []
        
        for cat in self.patrimony_by_category:
            if cat["total"] > 0:
                percentage = cat["total"] / self.total_patrimony * 100
                sections.append(
                    ft.PieChartSection(
                        value=cat["total"],
                        title=f"{percentage:.1f}%",
                        title_style=ft.TextStyle(
                            size=12,
                            color=ft.colors.WHITE,
                            weight=ft.FontWeight.BOLD,
                        ),
                        color=cat["color"],
                        radius=80,
                    )
                )
                legend_items.append(
                    ft.Row(
                        controls=[
                            ft.Container(
                                width=12,
                                height=12,
                                bgcolor=cat["color"],
                                border_radius=2,
                            ),
                            ft.Text(
                                cat['name'],
                                size=13,
                                color=text_color,
                            ),
                        ],
                        spacing=8,
                    )
                )
        
        pie_chart = ft.PieChart(
            sections=sections,
            sections_space=2,
            center_space_radius=40,
            width=200,
            height=200,
        )
        
        return PeadraTheme.card(
            content=ft.Column(
                controls=[
                    ft.Text(
                        "Répartition du patrimoine",
                        size=18,
                        weight=ft.FontWeight.BOLD,
                        color=text_color,
                    ),
                    ft.Divider(height=16, color="transparent"),
                    ft.Row(
                        controls=[
                            pie_chart,
                            ft.Column(
                                controls=legend_items,
                                spacing=12,
                            ),
                        ],
                        alignment=ft.MainAxisAlignment.CENTER,
                        spacing=40,
                    ),
                ],
            ),
            is_dark=self.is_dark,
            padding=20,
        )
    
    def build(self) -> ft.Container:
        """Construit la vue complète du tableau de bord."""
        return ft.Container(
            content=ft.Column(
                controls=[
                    # Titre de la page
                    ft.Text(
                        "Tableau de bord",
                        size=28,
                        weight=ft.FontWeight.BOLD,
                        color=PeadraTheme.DARK_TEXT if self.is_dark else PeadraTheme.LIGHT_TEXT,
                    ),
                    ft.Divider(height=24, color="transparent"),
                    # Carte patrimoine total
                    self._build_patrimony_card(),
                    ft.Divider(height=20, color="transparent"),
                    # Cartes par catégorie
                    self._build_category_cards(),
                    ft.Divider(height=20, color="transparent"),
                    # Résumé mensuel
                    self._build_monthly_summary_card(),
                    ft.Divider(height=20, color="transparent"),
                    # Ligne avec graphique et transactions/actifs
                    ft.Row(
                        controls=[
                            ft.Container(
                                content=self._build_pie_chart(),
                                expand=1,
                            ),
                            ft.Container(
                                content=ft.Column(
                                    controls=[
                                        self._build_recent_transactions(),
                                        self._build_assets_summary(),
                                    ],
                                    spacing=16,
                                ),
                                expand=1,
                            ),
                        ],
                        spacing=20,
                        vertical_alignment=ft.CrossAxisAlignment.START,
                    ),
                ],
                scroll=ft.ScrollMode.AUTO,
                expand=True,
            ),
            expand=True,
        )

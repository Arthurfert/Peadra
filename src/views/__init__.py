"""
Module des vues pour Peadra.
"""
from .dashboard import DashboardView
from .transactions import TransactionsView
from .analyses import AnalysesView
from .assets import AssetsView

__all__ = ["DashboardView", "TransactionsView", "AnalysesView", "AssetsView"]

"""
Module des vues pour Peadra.
"""

from .dashboard import DashboardView
from .transactions import TransactionsView
from .accounts import AccountsView
from .parameters import ParametersView
from .import_data import ImportDialog

__all__ = ["DashboardView", "TransactionsView", "AccountsView", "ParametersView", "ImportDialog"]

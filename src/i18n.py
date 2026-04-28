"""
Module de gestion de l'internationalisation (i18n) pour Peadra.
Gère les traductions multilingues de l'application.
"""

from typing import Dict, Any


class Translator:
    """Gestionnaire de traductions pour l'application Peadra."""

    # Dictionnaires de traductions
    TRANSLATIONS: Dict[str, Dict[str, Any]] = {
        "en": {
            # Navigation
            "nav_dashboard": "Dashboard",
            "nav_transactions": "Transactions",
            "nav_accounts": "Accounts",
            "nav_subscriptions": "Subscriptions",
            "nav_parameters": "Settings",
            # Login
            "login_title": "Peadra",
            "login_subtitle": "Financial Asset Tracker",
            "login_username": "Username",
            "login_user": "User",
            "login_password": "Password",
            "login_confirm_password": "Confirm Password",
            "login_signup": "Sign Up",
            "login_signin": "Log In",
            "login_create_account": "Create a new account",
            "login_connect_account": "Connect to an existing account",
            # Common
            "btn_save": "Save",
            "btn_cancel": "Cancel",
            "btn_delete": "Delete",
            "btn_add": "Add",
            "btn_edit": "Edit",
            "btn_logout": "Logout",
            "btn_import": "Import",
            # Dashboard
            "dash_total_assets": "Total Assets",
            "dash_monthly_income": "Monthly Income",
            "dash_monthly_expenses": "Monthly Expenses",
            "dash_net_worth": "Net Worth",
            # Transactions
            "trans_title": "Transactions",
            "trans_add_transaction": "Add Transaction",
            "trans_date": "Date",
            "trans_amount": "Amount",
            "trans_category": "Category",
            "trans_description": "Description",
            "trans_account": "Account",
            "trans_type": "Type",
            "trans_income": "Income",
            "trans_expense": "Expense",
            # Accounts
            "acc_title": "Accounts",
            "acc_add_account": "Add Account",
            "acc_name": "Name",
            "acc_type": "Type",
            "acc_balance": "Balance",
            "acc_checking": "Checking",
            "acc_savings": "Savings",
            # Subscriptions
            "sub_title": "Subscriptions",
            "sub_add_subscription": "Add Subscription",
            "sub_name": "Name",
            "sub_amount": "Amount",
            "sub_frequency": "Frequency",
            "sub_monthly": "Monthly",
            "sub_yearly": "Yearly",
            # Parameters
            "param_title": "Settings",
            "param_theme": "Theme",
            "param_theme_dark": "Dark",
            "param_theme_light": "Light",
            "param_language": "Language",
            "param_language_en": "English",
            "param_language_fr": "Français",
            "param_account_settings": "Account Settings",
            "param_change_password": "Change Password",
            "param_old_password": "Old Password",
            "param_new_password": "New Password",
            # Messages
            "msg_error": "Error",
            "msg_success": "Success",
            "msg_confirm_delete": "Are you sure you want to delete this?",
            "msg_invalid_input": "Invalid input",
            "msg_password_mismatch": "Passwords do not match",
            "msg_user_exists": "User already exists",
        },
        "fr": {
            # Navigation
            "nav_dashboard": "Tableau de bord",
            "nav_transactions": "Transactions",
            "nav_accounts": "Comptes",
            "nav_subscriptions": "Abonnements",
            "nav_parameters": "Paramètres",
            # Login
            "login_title": "Peadra",
            "login_subtitle": "Gestionnaire de Patrimoine Financier",
            "login_username": "Nom d'utilisateur",
            "login_user": "Utilisateur",
            "login_password": "Mot de passe",
            "login_confirm_password": "Confirmer le mot de passe",
            "login_signup": "S'inscrire",
            "login_signin": "Se connecter",
            "login_create_account": "Créer un nouveau compte",
            "login_connect_account": "Se connecter à un compte existant",
            # Common
            "btn_save": "Enregistrer",
            "btn_cancel": "Annuler",
            "btn_delete": "Supprimer",
            "btn_add": "Ajouter",
            "btn_edit": "Modifier",
            "btn_logout": "Déconnexion",
            "btn_import": "Importer",
            # Dashboard
            "dash_total_assets": "Actif total",
            "dash_monthly_income": "Revenu mensuel",
            "dash_monthly_expenses": "Dépenses mensuelles",
            "dash_net_worth": "Valeur nette",
            # Transactions
            "trans_title": "Transactions",
            "trans_add_transaction": "Ajouter une transaction",
            "trans_date": "Date",
            "trans_amount": "Montant",
            "trans_category": "Catégorie",
            "trans_description": "Description",
            "trans_account": "Compte",
            "trans_type": "Type",
            "trans_income": "Revenu",
            "trans_expense": "Dépense",
            # Accounts
            "acc_title": "Comptes",
            "acc_add_account": "Ajouter un compte",
            "acc_name": "Nom",
            "acc_type": "Type",
            "acc_balance": "Solde",
            "acc_checking": "Courant",
            "acc_savings": "Épargne",
            # Subscriptions
            "sub_title": "Abonnements",
            "sub_add_subscription": "Ajouter un abonnement",
            "sub_name": "Nom",
            "sub_amount": "Montant",
            "sub_frequency": "Fréquence",
            "sub_monthly": "Mensuel",
            "sub_yearly": "Annuel",
            # Parameters
            "param_title": "Paramètres",
            "param_theme": "Thème",
            "param_theme_dark": "Sombre",
            "param_theme_light": "Clair",
            "param_language": "Langue",
            "param_language_en": "English",
            "param_language_fr": "Français",
            "param_account_settings": "Paramètres du compte",
            "param_change_password": "Changer le mot de passe",
            "param_old_password": "Ancien mot de passe",
            "param_new_password": "Nouveau mot de passe",
            # Messages
            "msg_error": "Erreur",
            "msg_success": "Succès",
            "msg_confirm_delete": "Êtes-vous sûr de vouloir supprimer ceci ?",
            "msg_invalid_input": "Entrée invalide",
            "msg_password_mismatch": "Les mots de passe ne correspondent pas",
            "msg_user_exists": "L'utilisateur existe déjà",
        },
    }

    def __init__(self, language: str = "en"):
        """
        Initialise le traducteur.

        Args:
            language: Code de la langue ('en' ou 'fr')
        """
        self.language = language if language in self.TRANSLATIONS else "en"

    def set_language(self, language: str) -> None:
        """Définit la langue active."""
        if language in self.TRANSLATIONS:
            self.language = language

    def get_language(self) -> str:
        """Retourne la langue active."""
        return self.language

    def get_available_languages(self) -> Dict[str, str]:
        """Retourne les langues disponibles avec leurs labels."""
        return {
            "en": self.t("param_language_en"),
            "fr": self.t("param_language_fr"),
        }

    def t(self, key: str, **kwargs) -> str:
        """
        Traduit une clé de traduction.

        Args:
            key: Clé de traduction
            **kwargs: Arguments de formatage (pas encore utilisés)

        Returns:
            Texte traduit ou la clé si non trouvée
        """
        translations = self.TRANSLATIONS.get(self.language, {})
        return translations.get(key, key)


# Instance globale du traducteur
translator: Translator = Translator("en")


def get_translator() -> Translator:
    """Retourne l'instance globale du traducteur."""
    return translator


def set_language(language: str) -> None:
    """Définit la langue globale."""
    translator.set_language(language)


def t(key: str) -> str:
    """Fonction raccourcie pour traduire une clé."""
    return translator.t(key)

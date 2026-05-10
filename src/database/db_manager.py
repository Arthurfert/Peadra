"""
Module de gestion de la base de données SQLite pour Peadra.
"""

import os
import sys
import sqlite3
import json
import csv
import hashlib
from datetime import datetime, date, timedelta
from typing import List, Optional, Dict, Any


def get_app_dir() -> str:
    """Retourne le dossier du projet en dev, ou le dossier de l'exécutable en prod."""
    executable_name = os.path.basename(sys.executable).lower()
    if executable_name in ["python.exe", "python", "python3.exe", "python3"]:
        # Mode développement (flet run ou python main.py)
        # Retourne à la racine du projet qui contient src/ et main.py
        current = os.path.abspath(os.path.dirname(__file__))
        return os.path.dirname(os.path.dirname(current))
    else:
        # Mode production (exécutable packagé via flet build)
        return os.path.dirname(sys.executable)


class PasswordManager:
    """Gestionnaire de mots de passe avec hachage sécurisé."""

    @staticmethod
    def hash_password(password: str) -> str:
        """Hache un mot de passe avec SHA-256."""
        return hashlib.sha256(password.encode()).hexdigest()

    @staticmethod
    def verify_password(password: str, password_hash: str) -> bool:
        """Vérifie un mot de passe contre son hash."""
        return PasswordManager.hash_password(password) == password_hash


class DatabaseManager:
    """Gestionnaire de base de données SQLite."""

    def __init__(self, db_path: str | None = None, user_id: Optional[int] = None):
        if db_path is None:
            # Enregistrer la base de données dans le dossier de l'application
            db_path = os.path.join(get_app_dir(), "peadra.db")
        self.db_path = db_path
        self.user_id = user_id  # ID de l'utilisateur actuel
        self.connection: Optional[sqlite3.Connection] = None
        self._setting_cache: Dict[tuple[Optional[int], str], str] = {}
        self._app_setting_cache: Dict[str, str] = {}
        self._init_database()

    def _get_connection(self) -> sqlite3.Connection:
        """Obtient une connexion à la base de données."""
        if self.connection is None:
            self.connection = sqlite3.connect(self.db_path, check_same_thread=False)
            self.connection.row_factory = sqlite3.Row
        return self.connection

    def _init_database(self):
        """Initialise les tables de la base de données."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Table des utilisateurs
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """
        )

        # Table des catégories
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'savings' CHECK(type IN ('checking', 'savings')),
                color TEXT DEFAULT '#1976D2',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, name),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """
        )

        # Table des transactions
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                date DATE NOT NULL,
                description TEXT NOT NULL,
                amount REAL NOT NULL,
                transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
                category_id INTEGER,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (category_id) REFERENCES categories(id)
            )
        """
        )

        # Table des fichiers importés
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS imported_files (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                file_hash TEXT NOT NULL,
                filename TEXT,
                imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, file_hash),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """
        )

        # Table des paramètres
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS settings (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                key TEXT NOT NULL,
                value TEXT,
                UNIQUE(user_id, key),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """
        )

        # Table des transactions récurrentes
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS recurring_transactions (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                description TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
                frequency TEXT NOT NULL CHECK(frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
                interval INTEGER DEFAULT 1,
                start_date DATE NOT NULL,
                next_due_date DATE NOT NULL,
                end_date DATE,
                last_generated DATE,
                active BOOLEAN DEFAULT 1,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (category_id) REFERENCES categories(id)
            )
        """
        )

        conn.commit()

        # Appliquer les migrations si nécessaire
        self._apply_migrations()

        # Insérer les catégories par défaut si elles n'existent pas
        if self.user_id is not None:
            self._insert_default_categories()

    def _apply_migrations(self):
        """Applique les migrations nécessaires pour mettre à jour la base de données existante."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Vérifier si les colonnes user_id existent
        try:
            cursor.execute("SELECT user_id FROM categories LIMIT 1")
        except Exception:
            # Les colonnes user_id n'existent pas, faire la migration
            print("Migration: Ajout des colonnes user_id...")

            # Créer un utilisateur par défaut pour les données existantes
            try:
                cursor.execute(
                    "INSERT INTO users (username, password_hash) VALUES (?, ?)",
                    ("default_user", PasswordManager.hash_password("password")),
                )
                conn.commit()
                default_user_id = cursor.lastrowid
            except sqlite3.IntegrityError:
                # L'utilisateur par défaut existe déjà
                cursor.execute(
                    "SELECT id FROM users WHERE username = ?", ("default_user",)
                )
                result = cursor.fetchone()
                default_user_id = result[0] if result else 1

            # Ajouter la colonne user_id à categories
            try:
                cursor.execute(
                    "ALTER TABLE categories ADD COLUMN user_id INTEGER DEFAULT ?",
                    (default_user_id,),
                )
                # Ajouter la constraint NOT NULL et UNIQUE après migration
                conn.commit()
            except Exception as e:
                print(f"Note: Categories may already have user_id column: {e}")

            # Ajouter la colonne user_id à transactions
            try:
                cursor.execute(
                    "ALTER TABLE transactions ADD COLUMN user_id INTEGER DEFAULT ?",
                    (default_user_id,),
                )
                conn.commit()
            except Exception as e:
                print(f"Note: Transactions may already have user_id column: {e}")

            # Ajouter la colonne user_id à imported_files
            try:
                cursor.execute(
                    "ALTER TABLE imported_files ADD COLUMN user_id INTEGER DEFAULT ?",
                    (default_user_id,),
                )
                conn.commit()
            except Exception as e:
                print(f"Note: Imported_files may already have user_id column: {e}")

            # Ajouter la colonne user_id à settings
            try:
                cursor.execute(
                    "ALTER TABLE settings ADD COLUMN user_id INTEGER DEFAULT ?",
                    (default_user_id,),
                )
                conn.commit()
            except Exception as e:
                print(f"Note: Settings may already have user_id column: {e}")

            # Ajouter la colonne user_id à recurring_transactions
            try:
                cursor.execute(
                    "ALTER TABLE recurring_transactions ADD COLUMN user_id INTEGER DEFAULT ?",
                    (default_user_id,),
                )
                conn.commit()
            except Exception as e:
                print(
                    f"Note: Recurring_transactions may already have user_id column: {e}"
                )

            print("Migration complétée!")

    def _insert_default_categories(self):
        """Insère les catégories par défaut pour l'utilisateur actuel."""
        conn = self._get_connection()
        cursor = conn.cursor()

        if self.user_id is None:
            return

        # Vérifier s'il y a déjà des catégories pour cet utilisateur
        cursor.execute(
            "SELECT COUNT(*) FROM categories WHERE user_id = ?", (self.user_id,)
        )
        count = cursor.fetchone()[0]

        if count > 0:
            return

        default_categories = [
            ("Checking Account", "#4CAF50", "checking"),
            ("Savings Account A", "#2196F3", "savings"),
            ("Savings Account B", "#009688", "savings"),
        ]

        for name, color, acc_type in default_categories:
            cursor.execute(
                "INSERT INTO categories (user_id, name, color, type) VALUES (?, ?, ?, ?)",
                (self.user_id, name, color, acc_type),
            )

        conn.commit()

    # ==================== AUTHENTIFICATION ====================

    def user_exists(self, username: str) -> bool:
        """Vérifie si un nom d'utilisateur existe déjà."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id FROM users WHERE username = ?",
            (username,),
        )
        return cursor.fetchone() is not None

    def register_user(self, username: str, password: str) -> bool:
        """Crée un nouvel utilisateur.

        Raises:
            ValueError: Si le nom d'utilisateur existe déjà ou est invalide.
        """
        if not username or not password:
            raise ValueError("Username and password are required.")

        if self.user_exists(username):
            raise ValueError(f"Username '{username}' already exists.")

        password_hash = PasswordManager.hash_password(password)
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute(
                "INSERT INTO users (username, password_hash) VALUES (?, ?)",
                (username, password_hash),
            )
            conn.commit()
            return True
        except sqlite3.IntegrityError as e:
            raise ValueError(f"Failed to register user: {str(e)}")

    def authenticate_user(self, username: str, password: str) -> Optional[int]:
        """Authentifie un utilisateur et retourne son ID, ou None si échoué."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id, password_hash FROM users WHERE username = ?", (username,)
        )
        row = cursor.fetchone()

        if row is None:
            return None

        user_id, password_hash = row[0], row[1]

        if PasswordManager.verify_password(password, password_hash):
            return user_id
        return None

    def get_all_usernames(self) -> List[str]:
        """Récupère la liste de tous les noms d'utilisateurs."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT username FROM users ORDER BY username")
        return [row[0] for row in cursor.fetchall()]

    def get_current_username(self) -> str:
        """Récupère le username de l'utilisateur actuel."""
        if not self.user_id:
            return ""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT username FROM users WHERE id = ?", (self.user_id,))
        row = cursor.fetchone()
        return row[0] if row else ""

    def update_username(self, new_username: str) -> bool:
        """Met à jour le username de l'utilisateur actuel.

        Args:
            new_username: Le nouveau nom d'utilisateur

        Returns:
            True si la mise à jour réussit

        Raises:
            ValueError: Si le nouveau username existe déjà ou si aucun utilisateur n'est défini
        """
        if not self.user_id:
            raise ValueError("No user is currently set.")

        if not new_username or not new_username.strip():
            raise ValueError("Username cannot be empty.")

        new_username = new_username.strip()

        # Vérifier que le nouveau username n'existe pas
        if self.user_exists(new_username):
            raise ValueError(f"Username '{new_username}' already exists.")

        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute(
                "UPDATE users SET username = ? WHERE id = ?",
                (new_username, self.user_id),
            )
            conn.commit()
            return True
        except sqlite3.IntegrityError as e:
            raise ValueError(f"Failed to update username: {str(e)}")

    def set_current_user(self, user_id: int):
        """Définit l'utilisateur courant."""
        self.user_id = user_id
        # Créer les catégories par défaut si nécessaire
        self._insert_default_categories()

    # ==================== CATÉGORIES ====================

    def get_all_categories(self) -> List[Dict[str, Any]]:
        """Récupère toutes les catégories de l'utilisateur."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM categories WHERE user_id = ? ORDER BY name", (self.user_id,)
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_categories_with_balances(self) -> List[Dict[str, Any]]:
        """Récupère toutes les catégories avec leur solde actuel."""
        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT c.*,
                   COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                     WHEN t.transaction_type = 'expense' THEN -t.amount
                                     ELSE 0 END), 0) AS balance
            FROM categories c
            LEFT JOIN transactions t ON t.category_id = c.id AND t.user_id = ?
            WHERE c.user_id = ?
            GROUP BY c.id
            ORDER BY c.name
            """,
            (self.user_id, self.user_id),
        )
        return [dict(row) for row in cursor.fetchall()]

    def merge_categories(self, source_id: int, target_id: int) -> bool:
        """Fusionne la catégorie source vers la cible puis supprime la source."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Vérifier que les deux catégories appartiennent à l'utilisateur actuel
        cursor.execute(
            "SELECT user_id FROM categories WHERE id = ? OR id = ?",
            (source_id, target_id),
        )
        rows = cursor.fetchall()
        if len(rows) != 2 or any(row[0] != self.user_id for row in rows):
            return False

        # Déplacer les transactions
        cursor.execute(
            "UPDATE transactions SET category_id = ? WHERE category_id = ?",
            (target_id, source_id),
        )

        # Supprimer la catégorie source
        cursor.execute("DELETE FROM categories WHERE id = ?", (source_id,))

        conn.commit()
        return True

    def add_category(self, name: str, color: str, account_type: str = "savings") -> int:
        """Ajoute une nouvelle catégorie (compte)."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "INSERT INTO categories (user_id, name, color, type) VALUES (?, ?, ?, ?)",
                (self.user_id, name, color, account_type),
            )
            conn.commit()
            return cursor.lastrowid or 0
        except sqlite3.IntegrityError:
            # Le nom existe déjà
            return -1

    def update_category(
        self,
        category_id: int,
        name: str,
        color: str,
        account_type: Optional[str] = None,
    ) -> bool:
        """Met à jour une catégorie."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Vérifier que la catégorie appartient à l'utilisateur actuel
        cursor.execute(
            "SELECT name FROM categories WHERE id = ? AND user_id = ?",
            (category_id, self.user_id),
        )
        row = cursor.fetchone()
        if not row:
            return False
        old_name = row[0]

        try:
            if account_type:
                cursor.execute(
                    "UPDATE categories SET name = ?, color = ?, type = ? WHERE id = ? AND user_id = ?",
                    (name, color, account_type, category_id, self.user_id),
                )
            else:
                cursor.execute(
                    "UPDATE categories SET name = ?, color = ? WHERE id = ? AND user_id = ?",
                    (name, color, category_id, self.user_id),
                )

            rows_affected = cursor.rowcount

            # Mettre à jour les descriptions de transactions si le nom a changé
            if rows_affected > 0 and old_name != name:
                # Update 'Transfer to ...'
                cursor.execute(
                    "UPDATE transactions SET description = ? WHERE description = ? AND user_id = ?",
                    (f"Transfer to {name}", f"Transfer to {old_name}", self.user_id),
                )
                # Update 'Transfer from ...'
                cursor.execute(
                    "UPDATE transactions SET description = ? WHERE description = ? AND user_id = ?",
                    (
                        f"Transfer from {name}",
                        f"Transfer from {old_name}",
                        self.user_id,
                    ),
                )

            conn.commit()
            return rows_affected > 0
        except sqlite3.IntegrityError:
            return False

    def delete_category(
        self, category_id: int, delete_transactions: bool = False
    ) -> bool:
        """
        Supprime une catégorie.
        :param category_id: ID de la catégorie à supprimer.
        :param delete_transactions: Si True, supprime aussi les transactions associées. Sinon, met category_id à NULL.
        """
        conn = self._get_connection()
        cursor = conn.cursor()

        # Vérifier que la catégorie appartient à l'utilisateur actuel
        cursor.execute(
            "SELECT id FROM categories WHERE id = ? AND user_id = ?",
            (category_id, self.user_id),
        )
        if not cursor.fetchone():
            return False

        if delete_transactions:
            cursor.execute(
                "DELETE FROM transactions WHERE category_id = ? AND user_id = ?",
                (category_id, self.user_id),
            )
        else:
            cursor.execute(
                "UPDATE transactions SET category_id = NULL WHERE category_id = ? AND user_id = ?",
                (category_id, self.user_id),
            )

        cursor.execute(
            "DELETE FROM categories WHERE id = ? AND user_id = ?",
            (category_id, self.user_id),
        )
        conn.commit()
        return cursor.rowcount > 0

    # ==================== TRANSACTIONS ====================

    def add_transaction(
        self,
        date: str,
        description: str,
        amount: float,
        transaction_type: str,
        category_id: Optional[int] = None,
        notes: Optional[str] = None,
    ) -> int:
        """Ajoute une nouvelle transaction."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO transactions (user_id, date, description, amount, transaction_type,
                                      category_id, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
            (
                self.user_id,
                date,
                description,
                amount,
                transaction_type,
                category_id,
                notes,
            ),
        )
        conn.commit()
        return cursor.lastrowid or 0

    # ==================== TRANSACTIONS RÉCURRENTES ====================

    def update_recurring_transaction(
        self,
        id: int,
        description: str,
        amount: float,
        transaction_type: str,
        frequency: str,
        start_date: str,
        interval: int = 1,
        category_id: Optional[int] = None,
        end_date: Optional[str] = None,
    ) -> bool:
        """Met à jour une transaction récurrente existante."""
        conn = self._get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute(
                """
                UPDATE recurring_transactions 
                SET description = ?, amount = ?, transaction_type = ?, frequency = ?,
                    start_date = ?, interval = ?, category_id = ?, end_date = ?
                WHERE id = ? AND user_id = ?
                """,
                (
                    description,
                    amount,
                    transaction_type,
                    frequency,
                    start_date,
                    interval,
                    category_id,
                    end_date,
                    id,
                    self.user_id,
                ),
            )
            conn.commit()
            return cursor.rowcount > 0
        except sqlite3.Error as e:
            print(f"Database error during update_recurring_transaction: {e}")
            return False

    def add_recurring_transaction(
        self,
        description: str,
        amount: float,
        transaction_type: str,
        frequency: str,
        start_date: str,
        interval: int = 1,
        category_id: Optional[int] = None,
        end_date: Optional[str] = None,
        next_due_date: Optional[str] = None,
    ) -> int:
        """Ajoute une transaction récurrente."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Le premier next_due_date par défaut est la start_date s'il n'est pas fourni
        if next_due_date is None:
            next_due_date = start_date

        cursor.execute(
            """
            INSERT INTO recurring_transactions (
                user_id, description, amount, transaction_type, frequency, 
                interval, start_date, next_due_date, end_date, category_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                self.user_id,
                description,
                amount,
                transaction_type,
                frequency,
                interval,
                start_date,
                next_due_date,
                end_date,
                category_id,
            ),
        )
        conn.commit()
        return cursor.lastrowid or 0

    def get_recurring_transactions(self, display_month: Optional[date] = None) -> List[Dict[str, Any]]:
        """
        Récupère les transactions récurrentes de l'utilisateur.
        
        Si display_month est fourni, inclut aussi les transactions inactives qui s'appliquent 
        au mois spécifié (pour afficher les anciennes transactions récurrentes dans le calendrier).
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        
        if display_month is None:
            # Mode par défaut : charger seulement les transactions actives
            query = """
                SELECT r.*, c.name as category_name, c.color as category_color
                FROM recurring_transactions r
                LEFT JOIN categories c ON r.category_id = c.id
                WHERE r.active = 1 AND r.user_id = ?
            """
            cursor.execute(query, (self.user_id,))
        else:
            # Mode calendrier : charger les transactions applicables au mois
            # Incluure les transactions inactives qui s'appliquent à ce mois
            query = """
                SELECT r.*, c.name as category_name, c.color as category_color
                FROM recurring_transactions r
                LEFT JOIN categories c ON r.category_id = c.id
                WHERE r.user_id = ? AND (
                    r.active = 1 OR 
                    (r.end_date IS NOT NULL AND r.end_date >= ?)
                )
            """
            # Utiliser le premier jour du mois comme date de comparaison
            first_day_of_month = display_month.replace(day=1)
            cursor.execute(query, (self.user_id, first_day_of_month.isoformat()))
        
        return [dict(row) for row in cursor.fetchall()]

    def process_recurring_transactions(self):
        """
        Vérifie et génère les transactions dues de l'utilisateur actuel.
        À appeler au démarrage de l'application.
        """
        conn = self._get_connection()
        cursor = conn.cursor()

        today = date.today()
        today_str = today.isoformat()

        # Récupérer les transactions actives dues (next_due_date <= today)
        cursor.execute(
            """
            SELECT * FROM recurring_transactions 
            WHERE active = 1 AND next_due_date <= ? AND user_id = ?
            """,
            (today_str, self.user_id),
        )

        due_transactions = [dict(row) for row in cursor.fetchall()]

        for rt in due_transactions:
            # Récupérer la date actuelle de traitement pour cette règle
            current_next_due_str = rt["next_due_date"]
            current_next_due = datetime.strptime(
                current_next_due_str, "%Y-%m-%d"
            ).date()

            # Boucle tant que la transaction est due
            while current_next_due <= today:
                # Vérifier la date de fin
                if rt["end_date"]:
                    end_date = datetime.strptime(rt["end_date"], "%Y-%m-%d").date()
                    if current_next_due > end_date:
                        # Désactiver la transaction si la date de fin est dépassée
                        cursor.execute(
                            "UPDATE recurring_transactions SET active = 0 WHERE id = ?",
                            (rt["id"],),
                        )
                        break  # Sortir du while pour passer à la règle suivante

                # Créer la transaction réelle
                self.add_transaction(
                    date=current_next_due.isoformat(),
                    description=rt["description"],
                    amount=rt["amount"],
                    transaction_type=rt["transaction_type"],
                    category_id=rt["category_id"],
                    notes=f"Frequency : {rt['frequency']}\nStart Date : {rt['start_date']}\nNext Due Date : {rt['next_due_date']}",
                )

                # Calculer la prochaine date
                next_date = self._calculate_next_date(
                    current_next_due, rt["frequency"], rt["interval"]
                )
                next_date_str = next_date.isoformat()

                # Mettre à jour la règle pour la prochaine itération ou la fin
                cursor.execute(
                    """
                    UPDATE recurring_transactions 
                    SET last_generated = ?, next_due_date = ? 
                    WHERE id = ?
                    """,
                    (current_next_due.isoformat(), next_date_str, rt["id"]),
                )

                # Avancer la date pour la prochaine boucle while
                current_next_due = next_date

        conn.commit()

    def _calculate_next_date(
        self, current_date: date, frequency: str, interval: int
    ) -> date:
        """Calcule la prochaine date pour une récurrence."""
        if frequency == "daily":
            return current_date + timedelta(days=interval)
        elif frequency == "weekly":
            return current_date + timedelta(weeks=interval)
        elif frequency == "monthly":
            # Ajouter des mois est complexe à cause des nombres de jours variables
            # Approche simple : le même jour du mois suivant
            new_month = current_date.month + interval
            new_year = current_date.year + (new_month - 1) // 12
            new_month = (new_month - 1) % 12 + 1

            # Gérer le cas où le jour n'existe pas dans le nouveau mois (ex: 31 jan -> fév)
            last_day_of_month = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            if new_year % 4 == 0 and (new_year % 100 != 0 or new_year % 400 == 0):
                last_day_of_month[2] = 29

            new_day = min(current_date.day, last_day_of_month[new_month])
            return date(new_year, new_month, new_day)

        elif frequency == "yearly":
            try:
                return current_date.replace(year=current_date.year + interval)
            except ValueError:
                # Gérer le 29 février -> 28 février
                return current_date.replace(
                    year=current_date.year + interval, month=2, day=28
                )

        return current_date  # Fallback

    def update_transaction(self, transaction_id: int, **kwargs) -> bool:
        """Met à jour une transaction existante."""
        if not kwargs:
            return False

        allowed_fields = {
            "date",
            "description",
            "amount",
            "transaction_type",
            "category_id",
            "notes",
        }
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}

        if not updates:
            return False

        updates["updated_at"] = datetime.now().isoformat()

        set_clause = ", ".join([f"{k} = ?" for k in updates.keys()])
        values = list(updates.values()) + [transaction_id, self.user_id]

        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            f"UPDATE transactions SET {set_clause} WHERE id = ? AND user_id = ?", values
        )
        conn.commit()
        return cursor.rowcount > 0

    def delete_transaction(self, transaction_id: int) -> bool:
        """Supprime une transaction."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM transactions WHERE id = ? AND user_id = ?",
            (transaction_id, self.user_id),
        )
        conn.commit()
        return cursor.rowcount > 0

    def get_all_transactions(
        self,
        limit: Optional[int] = None,
        offset: int = 0,
        search_query: str = "",
        category_ids: Optional[set[int]] = None,
    ) -> List[Dict[str, Any]]:
        """Récupère toutes les transactions de l'utilisateur."""
        conn = self._get_connection()
        cursor = conn.cursor()
        query = """
            SELECT t.*, c.name as category_name, c.color as category_color
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.user_id = ?
        """
        params: list[int | str | None] = [self.user_id]

        if search_query:
            query += " AND (LOWER(t.description) LIKE ? OR LOWER(c.name) LIKE ?)"
            sq = f"%{search_query.lower()}%"
            params.extend([sq, sq])

        if category_ids:
            valid_ids = [
                cat for cat in category_ids if cat and str(cat).lower() != "none"
            ]
            if valid_ids:
                placeholders = ",".join("?" for _ in valid_ids)
                query += f" AND t.category_id IN ({placeholders})"
                params.extend(valid_ids)

        query += " ORDER BY t.date DESC, t.id DESC"

        if limit is not None:
            query += " LIMIT ? OFFSET ?"
            params.extend([limit, offset])

        cursor.execute(query, tuple(params))
        return [dict(row) for row in cursor.fetchall()]

    def get_transactions_by_period(
        self, start_date: str, end_date: str
    ) -> List[Dict[str, Any]]:
        """Récupère les transactions sur une période."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT t.*, c.name as category_name, c.color as category_color
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.date BETWEEN ? AND ? AND t.user_id = ?
            ORDER BY t.date DESC
        """,
            (start_date, end_date, self.user_id),
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_unique_descriptions(
        self, transaction_type: str = "expense", search_term: str = ""
    ) -> List[str]:
        """Récupère les descriptions uniques pour un type de transaction.
        
        Args:
            transaction_type: Type de transaction ('expense', 'income')
            search_term: Terme de recherche pour filtrer les descriptions
            
        Returns:
            Liste des descriptions uniques triées alphabétiquement
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        
        query = """
            SELECT DISTINCT LOWER(t.description) as description
            FROM transactions t
            WHERE t.user_id = ? AND t.transaction_type = ?
        """
        params: list[int | str | None] = [self.user_id, transaction_type]
        
        if search_term:
            query += " AND LOWER(t.description) LIKE ?"
            params.append(f"%{search_term.lower()}%")
        
        query += " ORDER BY t.description ASC"
        
        cursor.execute(query, tuple(params))
        return [row[0] for row in cursor.fetchall() if row[0]]

    def get_earliest_transaction_date(self) -> Optional[str]:
        """Récupère la date de la première transaction."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT MIN(date) FROM transactions WHERE user_id = ?", (self.user_id,)
        )
        row = cursor.fetchone()
        return row[0] if row else None

    # ==================== STATISTIQUES ====================

    def get_savings_total(self) -> float:
        """Calcule le total de l'épargne (tout ce qui n'est pas Compte Courant)."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                  WHEN t.transaction_type = 'expense' THEN -t.amount 
                                  ELSE 0 END), 0)
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE c.type = 'savings' AND t.user_id = ?
        """,
            (self.user_id,),
        )
        result = cursor.fetchone()
        return result[0] if result else 0.0

    def get_total_patrimony(self) -> float:
        """Calcule le solde total"""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                  WHEN t.transaction_type = 'expense' THEN -t.amount 
                                  ELSE 0 END), 0)
            FROM transactions t
            WHERE t.user_id = ?
        """,
            (self.user_id,),
        )
        result = cursor.fetchone()
        return result[0] if result else 0.0

    def get_balance(self) -> float:
        """Calcule le solde total du compte courant"""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                  WHEN t.transaction_type = 'expense' THEN -t.amount 
                                  ELSE 0 END), 0)
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE c.type = 'checking' AND t.user_id = ?
        """,
            (self.user_id,),
        )
        result = cursor.fetchone()
        return result[0] if result else 0.0

    def get_history_patrimony(self, date_limit: str) -> float:
        """Calcule le patrimoine total jusqu'à une date donnée (exclusive)."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                  WHEN t.transaction_type = 'expense' THEN -t.amount 
                                  ELSE 0 END), 0)
            FROM transactions t
            WHERE t.date < ? AND t.user_id = ?
        """,
            (date_limit, self.user_id),
        )
        result = cursor.fetchone()
        return result[0] if result else 0.0

    def get_history_savings(self, date_limit: str) -> float:
        """Calcule le total de l'épargne jusqu'à une date donnée (exclusive)."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                  WHEN t.transaction_type = 'expense' THEN -t.amount 
                                  ELSE 0 END), 0)
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.date < ? AND c.type = 'savings' AND t.user_id = ?
        """,
            (date_limit, self.user_id),
        )
        result = cursor.fetchone()
        return result[0] if result else 0.0

    def get_history_balance(self, date_limit: str) -> float:
        """Calcule le solde du compte courant jusqu'à une date donnée (exclusive)."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                  WHEN t.transaction_type = 'expense' THEN -t.amount 
                                  ELSE 0 END), 0)
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.date < ? AND c.type = 'checking' AND t.user_id = ?
        """,
            (date_limit, self.user_id),
        )
        result = cursor.fetchone()
        return result[0] if result else 0.0

    def get_monthly_summary(
        self, year: Optional[int] = None, month: Optional[int] = None
    ) -> Dict[str, float]:
        """Récupère le résumé mensuel des transactions (Uniquement flux Compte Courant)."""
        if year is None:
            year = datetime.now().year
        if month is None:
            month = datetime.now().month

        start_date = f"{year}-{month:02d}-01"
        if month == 12:
            end_date = f"{year + 1}-01-01"
        else:
            end_date = f"{year}-{month + 1:02d}-01"

        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
                COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE (t.date >= ? AND t.date < ?) AND (c.type = 'checking' OR t.category_id IS NULL) AND t.user_id = ?
        """,
            (start_date, end_date, self.user_id),
        )

        row = cursor.fetchone()
        return {"income": row[0], "expenses": row[1], "balance": row[0] - row[1]}

    def get_accounts_distribution(self) -> List[Dict[str, Any]]:
        """Calcule la répartition des soldes par compte."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT c.name,
                   COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                     WHEN t.transaction_type = 'expense' THEN -t.amount
                                     ELSE 0 END), 0) AS balance
            FROM categories c
            LEFT JOIN transactions t ON t.category_id = c.id AND t.user_id = ?
            WHERE c.user_id = ?
            GROUP BY c.id
            ORDER BY c.name
            """,
            (self.user_id, self.user_id),
        )
        return [{"name": row[0], "value": row[1]} for row in cursor.fetchall()]

    def get_description_monthly_data(
        self, start_date: str, end_date: str
    ) -> Dict[str, Dict[str, Dict[str, Any]]]:
        """Récupère les données mensuelles agrégées par description (dépenses et revenus, exclut transferts).

        Args:
            start_date: Date de début (YYYY-MM-DD)
            end_date: Date de fin (YYYY-MM-DD)

        Returns:
            Dict avec descriptions comme clé et dictionnaire mois -> {'income','expense','total'}
        """
        conn = self._get_connection()
        cursor = conn.cursor()

        query = """
            SELECT 
                LOWER(COALESCE(t.description, 'Uncategorized')) as desc,
                strftime('%Y-%m', t.date) as month,
                t.transaction_type,
                SUM(t.amount) as total
            FROM transactions t
            WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?
            GROUP BY desc, strftime('%Y-%m', t.date), t.transaction_type
            ORDER BY desc, month
        """

        cursor.execute(query, (start_date, end_date, self.user_id))
        rows = cursor.fetchall()

        result: Dict[str, Dict[str, Dict[str, Any]]] = {}
        for row in rows:
            desc = row[0] or "uncategorized"
            month = row[1]
            transaction_type = row[2]
            total = row[3]

            # Exclure les transferts
            if self._is_transfer_description(desc):
                continue

            if desc not in result:
                result[desc] = {}

            if month not in result[desc]:
                result[desc][month] = {"income": 0, "expense": 0, "total": 0}

            if transaction_type == "income":
                result[desc][month]["income"] += total
            elif transaction_type == "expense":
                result[desc][month]["expense"] += total

            result[desc][month]["total"] += total

        return result

    def get_top_descriptions(
        self, transaction_type: str = "expense", num_months: int = 6, limit: int = 5
    ) -> List[Dict[str, Any]]:
        """Récupère les descriptions triées par dépenses ou revenus (exclut les transferts).

        Args:
            transaction_type: Type de transaction ('expense' ou 'income', exclut 'transfer')
            num_months: Nombre de mois à considérer
            limit: Nombre maximal de résultats (0 = pas de limite)

        Returns:
            Liste des descriptions triées par montant total
        """
        conn = self._get_connection()
        cursor = conn.cursor()

        now = datetime.now()
        start_date = (now - timedelta(days=num_months * 30)).strftime("%Y-%m-%d")
        end_date = now.strftime("%Y-%m-%d")

        query = """
            SELECT 
                LOWER(COALESCE(t.description, 'Uncategorized')) as desc,
                SUM(t.amount) as total,
                COUNT(t.id) as count
            FROM transactions t
            WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
            GROUP BY desc
            ORDER BY total DESC
        """
        
        cursor.execute(query, (transaction_type, start_date, end_date, self.user_id))
        rows = cursor.fetchall()

        # Filtrer les transferts et appliquer la limite
        results = []
        for row in rows:
            desc = row[0] or "Uncategorized"
            # Exclure les transferts basés sur la description
            if not self._is_transfer_description(desc):
                results.append({"description": desc, "total": row[1], "count": row[2]})
                if limit > 0 and len(results) >= limit:
                    break

        return results

    def _is_transfer_description(self, description: str) -> bool:
        """Détecte si une description est un transfert basé sur les patterns de description."""
        from ..i18n import t
        
        desc = (description or "").strip().lower()
        transfer_to = (t("trans_transfer_to") or "").strip().lower()
        transfer_from = (t("trans_transfer_from") or "").strip().lower()

        prefixes = ["transfer to ", "transfer from "]
        if transfer_to:
            prefixes.append(f"{transfer_to} ")
        if transfer_from:
            prefixes.append(f"{transfer_from} ")

        return any(desc.startswith(prefix) for prefix in prefixes)

    def get_rolling_summary(self, days: int = 30) -> Dict[str, float]:
        """Récupère le résumé des transactions des N derniers jours (Compte Courant)."""
        from datetime import timedelta

        end_date = datetime.now().strftime("%Y-%m-%d")
        start_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
                COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE (t.date >= ? AND t.date <= ?) AND (c.type = 'checking' OR t.category_id IS NULL) AND t.user_id = ?
        """,
            (start_date, end_date, self.user_id),
        )

        row = cursor.fetchone()
        return {"income": row[0], "expenses": row[1], "balance": row[0] - row[1]}

    # ==================== EXPORT ====================

    def export_to_json(self, filepath: str) -> bool:
        """Exporte toutes les données de l'utilisateur en JSON."""
        try:
            data = {
                "categories": self.get_all_categories(),
                "transactions": self.get_all_transactions(),
                "exported_at": datetime.now().isoformat(),
            }

            with open(filepath, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"Erreur export JSON: {e}")
            return False

    def export_to_csv(self, filepath: str, data_type: str = "transactions") -> bool:
        """Exporte les données de l'utilisateur en CSV."""
        try:
            if data_type == "transactions":
                data = self.get_all_transactions()
            else:
                return False

            if not data:
                return False

            with open(filepath, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=data[0].keys())
                writer.writeheader()
                writer.writerows(data)
            return True
        except Exception as e:
            print(f"Erreur export CSV: {e}")
            return False

    # ==================== IMPORTS ====================

    def is_file_imported(self, file_hash: str) -> bool:
        """Vérifie si un fichier a déjà été importé par l'utilisateur."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT COUNT(*) FROM imported_files WHERE file_hash = ? AND user_id = ?",
            (file_hash, self.user_id),
        )
        return cursor.fetchone()[0] > 0

    def log_imported_file(self, file_hash: str, filename: str):
        """Enregistre un fichier importé."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)",
                (self.user_id, file_hash, filename),
            )
            conn.commit()
        except Exception as e:
            print(f"Erreur enregistrement import: {str(e)}")

    # ==================== SETTINGS ====================

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        """Récupère un paramètre depuis la base de données."""
        cache_key = (self.user_id, key)
        if cache_key in self._setting_cache:
            return self._setting_cache[cache_key]

        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT value FROM settings WHERE key = ? AND user_id = ?",
            (key, self.user_id),
        )
        result = cursor.fetchone()
        if result:
            value = result[0]
            self._setting_cache[cache_key] = value
            return value
        return default

    def set_setting(self, key: str, value: str):
        """Enregistre un paramètre dans la base de données."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)",
                (self.user_id, key, value),
            )
            conn.commit()
            self._setting_cache[(self.user_id, key)] = value
        except Exception as e:
            print(f"Erreur sauvegarde paramètre {key}: {str(e)}")

    def get_app_setting(self, key: str, default: str | None = None) -> str | None:
        """Récupère un paramètre global de l'application (user_id = 0).
        
        Args:
            key: Clé du paramètre
            default: Valeur par défaut si non trouvée
            
        Returns:
            Valeur du paramètre ou la valeur par défaut
        """
        if key in self._app_setting_cache:
            return self._app_setting_cache[key]

        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT value FROM settings WHERE key = ? AND user_id = ?",
            (key, 0),
        )
        result = cursor.fetchone()
        if result:
            value = result[0]
            self._app_setting_cache[key] = value
            return value
        return default

    def set_app_setting(self, key: str, value: str):
        """Enregistre un paramètre global de l'application (user_id = 0).
        
        Args:
            key: Clé du paramètre
            value: Valeur du paramètre
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            # Avant de sauvegarder, il faut s'assurer que user_id = 0 existe
            # On va directement insérer/remplacer
            cursor.execute(
                "INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)",
                (0, key, value),
            )
            conn.commit()
            self._app_setting_cache[key] = value
        except Exception as e:
            print(f"Erreur sauvegarde paramètre global {key}: {str(e)}")

    def merge_descriptions(self, source_description: str, target_description: str) -> bool:
        """Fusionne deux descriptions en renommant toutes les transactions avec la description source vers la cible.
        
        Args:
            source_description: Description à fusionner (sera renommée)
            target_description: Description cible (vers laquelle fusionner)
            
        Returns:
            True si la fusion a été successful, False sinon
        """
        if not source_description or not target_description:
            return False
            
        source_description = source_description.strip()
        target_description = target_description.strip()

        # Éviter de fusionner une description avec elle-même, mais autoriser les changements de casse
        if source_description == target_description:
            return False
            
        conn = self._get_connection()
        cursor = conn.cursor()
        
        try:
            # Mettre à jour toutes les transactions avec la description source
            cursor.execute(
                "UPDATE transactions SET description = ? WHERE description = ? AND user_id = ?",
                (target_description, source_description, self.user_id),
            )
            
            conn.commit()
            return cursor.rowcount > 0
        except Exception as e:
            print(f"Erreur lors de la fusion des descriptions: {str(e)}")
            return False

    def rename_description(self, old_description: str, new_description: str) -> bool:
        """Renomme une description en mettant à jour toutes les transactions associées.
        
        Args:
            old_description: Ancienne description
            new_description: Nouvelle description
            
        Returns:
            True si le renomage a été successful, False sinon
        """
        if not old_description or not new_description:
            return False
            
        old_description = old_description.strip()
        new_description = new_description.strip()

        # Éviter le renommage sans changement réel, mais autoriser les variations de casse
        if old_description == new_description:
            return False
            
        conn = self._get_connection()
        cursor = conn.cursor()
        
        try:
            # Mettre à jour toutes les transactions avec l'ancienne description
            cursor.execute(
                "UPDATE transactions SET description = ? WHERE description = ? AND user_id = ?",
                (new_description, old_description, self.user_id),
            )
            
            conn.commit()
            return cursor.rowcount > 0
        except Exception as e:
            print(f"Erreur lors du renomage de la description: {str(e)}")
            return False

    def get_all_unique_descriptions(self, transaction_type: Optional[str] = None) -> List[str]:
        """Récupère toutes les descriptions uniques, optionnellement filtrées par type de transaction.
        
        Args:
            transaction_type: Type de transaction ("income", "expense", ou None pour tous)
            
        Returns:
            Liste des descriptions uniques triées
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        
        if transaction_type:
            cursor.execute(
                "SELECT DISTINCT description FROM transactions WHERE user_id = ? AND transaction_type = ? ORDER BY description",
                (self.user_id, transaction_type),
            )
        else:
            cursor.execute(
                "SELECT DISTINCT description FROM transactions WHERE user_id = ? ORDER BY description",
                (self.user_id,),
            )
        
        return [
            row[0]
            for row in cursor.fetchall()
            if row[0] and not self._is_transfer_description(row[0])
        ]

    def delete_user_account(self, password: str) -> bool:
        """Supprime le compte utilisateur actuel après vérification du mot de passe.
        
        Args:
            password: Le mot de passe de l'utilisateur pour confirmation
            
        Returns:
            True si la suppression réussit, False sinon
        """
        if not self.user_id:
            return False
        
        conn = self._get_connection()
        cursor = conn.cursor()
        
        # Récupérer le hash du mot de passe de l'utilisateur
        cursor.execute(
            "SELECT password_hash FROM users WHERE id = ?",
            (self.user_id,)
        )
        row = cursor.fetchone()
        
        if not row:
            return False
        
        password_hash = row[0]
        
        # Vérifier le mot de passe
        if not PasswordManager.verify_password(password, password_hash):
            return False
        
        try:
            # Supprimer les transactions
            cursor.execute(
                "DELETE FROM transactions WHERE user_id = ?",
                (self.user_id,)
            )
            
            # Supprimer les catégories
            cursor.execute(
                "DELETE FROM categories WHERE user_id = ?",
                (self.user_id,)
            )
            
            # Supprimer les fichiers importés
            cursor.execute(
                "DELETE FROM imported_files WHERE user_id = ?",
                (self.user_id,)
            )
            
            # Supprimer les paramètres
            cursor.execute(
                "DELETE FROM settings WHERE user_id = ?",
                (self.user_id,)
            )
            
            # Supprimer les transactions récurrentes
            cursor.execute(
                "DELETE FROM recurring_transactions WHERE user_id = ?",
                (self.user_id,)
            )
            
            # Supprimer l'utilisateur
            cursor.execute(
                "DELETE FROM users WHERE id = ?",
                (self.user_id,)
            )
            
            conn.commit()
            return True
            
        except Exception as e:
            print(f"Erreur lors de la suppression du compte: {str(e)}")
            return False

    def close(self):
        """Ferme la connexion à la base de données."""
        if self.connection:
            try:
                self.connection.close()
            except Exception as e:
                print(f"Warning: Error closing database connection: {e}")
            finally:
                self.connection = None


# Instance globale du gestionnaire de base de données
db = DatabaseManager()

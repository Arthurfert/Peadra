"""
Module de gestion de la base de données SQLite pour Peadra.
"""

import sqlite3
import json
import csv
from datetime import datetime
from typing import List, Optional, Dict, Any


class DatabaseManager:
    """Gestionnaire de base de données SQLite."""

    def __init__(self, db_path: str = "peadra.db"):
        self.db_path = db_path
        self.connection: Optional[sqlite3.Connection] = None
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

        # Table des catégories
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                type TEXT NOT NULL DEFAULT 'savings' CHECK(type IN ('checking', 'savings')),
                color TEXT DEFAULT '#1976D2',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """
        )

        # Table des transactions
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY,
                date DATE NOT NULL,
                description TEXT NOT NULL,
                amount REAL NOT NULL,
                transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
                category_id INTEGER,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id)
            )
        """
        )

        conn.commit()

        # Insérer les catégories par défaut si elles n'existent pas
        self._insert_default_categories()

    def _insert_default_categories(self):
        """Insère les catégories par défaut uniquement si aucune catégorie n'existe."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Vérifier s'il y a déjà des catégories
        cursor.execute("SELECT COUNT(*) FROM categories")
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
                "INSERT INTO categories (name, color, type) VALUES (?, ?, ?)",
                (name, color, acc_type),
            )

        conn.commit()

    # ==================== CATÉGORIES ====================

    def get_all_categories(self) -> List[Dict[str, Any]]:
        """Récupère toutes les catégories."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM categories ORDER BY name")
        return [dict(row) for row in cursor.fetchall()]

    def get_categories_with_balances(self) -> List[Dict[str, Any]]:
        """Récupère toutes les catégories avec leur solde actuel."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Récupérer toutes les catégories
        cursor.execute("SELECT * FROM categories ORDER BY name")
        categories = [dict(row) for row in cursor.fetchall()]

        result = []
        for cat in categories:
            # Calculer le solde pour chaque catégorie
            cursor.execute(
                """
                SELECT 
                    COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount 
                                      WHEN transaction_type = 'expense' THEN -amount 
                                      ELSE 0 END), 0)
                FROM transactions 
                WHERE category_id = ?
                """,
                (cat["id"],),
            )
            balance = cursor.fetchone()[0]
            cat["balance"] = balance
            result.append(cat)

        return result

    def get_category_id_by_name(self, name: str) -> Optional[int]:
        """Récupère l'ID d'une catégorie par son nom."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM categories WHERE name = ?", (name,))
        row = cursor.fetchone()
        return row[0] if row else None

    def merge_categories(self, source_id: int, target_id: int) -> bool:
        """Fusionne la catégorie source vers la cible puis supprime la source."""
        conn = self._get_connection()
        cursor = conn.cursor()

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
                "INSERT INTO categories (name, color, type) VALUES (?, ?, ?)",
                (name, color, account_type),
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
        try:
            if account_type:
                cursor.execute(
                    "UPDATE categories SET name = ?, color = ?, type = ? WHERE id = ?",
                    (name, color, account_type, category_id),
                )
            else:
                cursor.execute(
                    "UPDATE categories SET name = ?, color = ? WHERE id = ?",
                    (name, color, category_id),
                )
            conn.commit()
            return cursor.rowcount > 0
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

        if delete_transactions:
            cursor.execute(
                "DELETE FROM transactions WHERE category_id = ?", (category_id,)
            )
        else:
            cursor.execute(
                "UPDATE transactions SET category_id = NULL WHERE category_id = ?",
                (category_id,),
            )

        cursor.execute("DELETE FROM categories WHERE id = ?", (category_id,))
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
            INSERT INTO transactions (date, description, amount, transaction_type,
                                      category_id, notes)
            VALUES (?, ?, ?, ?, ?, ?)
        """,
            (
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
        values = list(updates.values()) + [transaction_id]

        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(f"UPDATE transactions SET {set_clause} WHERE id = ?", values)
        conn.commit()
        return cursor.rowcount > 0

    def delete_transaction(self, transaction_id: int) -> bool:
        """Supprime une transaction."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM transactions WHERE id = ?", (transaction_id,))
        conn.commit()
        return cursor.rowcount > 0

    def get_all_transactions(
        self, limit: Optional[int] = None, offset: int = 0
    ) -> List[Dict[str, Any]]:
        """Récupère toutes les transactions."""
        conn = self._get_connection()
        cursor = conn.cursor()
        query = """
            SELECT t.*, c.name as category_name, c.color as category_color
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            ORDER BY t.date DESC, t.id DESC
        """
        if limit:
            query += f" LIMIT {limit} OFFSET {offset}"
        cursor.execute(query)
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
            WHERE t.date BETWEEN ? AND ?
            ORDER BY t.date DESC
        """,
            (start_date, end_date),
        )
        return [dict(row) for row in cursor.fetchall()]

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
            WHERE c.type = 'savings'
        """
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
        """
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
            WHERE c.type = 'checking'
        """
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
            WHERE t.date < ?
        """,
            (date_limit,),
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
            WHERE t.date < ? AND c.type = 'savings'
        """,
            (date_limit,),
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
            WHERE t.date < ? AND c.type = 'checking'
        """,
            (date_limit,),
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
            WHERE (t.date >= ? AND t.date < ?) AND (c.type = 'checking' OR t.category_id IS NULL)
        """,
            (start_date, end_date),
        )

        row = cursor.fetchone()
        return {"income": row[0], "expenses": row[1], "balance": row[0] - row[1]}

    def get_accounts_distribution(self) -> List[Dict[str, Any]]:
        """Calcule la répartition des soldes par compte."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Récupérer les ID des comptes (categories)
        cursor.execute("SELECT id, name FROM categories")
        accounts = cursor.fetchall()

        distribution = []
        for acc_id, acc_name in accounts:
            cursor.execute(
                """
                SELECT 
                    COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount 
                                      WHEN t.transaction_type = 'expense' THEN -t.amount 
                                      ELSE 0 END), 0)
                FROM transactions t
                WHERE t.category_id = ?
                """,
                (acc_id,),
            )
            result = cursor.fetchone()
            balance = result[0] if result else 0.0

            distribution.append({"name": acc_name, "value": balance})

        return distribution

    # ==================== EXPORT ====================

    def export_to_json(self, filepath: str) -> bool:
        """Exporte toutes les données en JSON."""
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
        """Exporte les données en CSV."""
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

    def close(self):
        """Ferme la connexion à la base de données."""
        if self.connection:
            self.connection.close()
            self.connection = None


# Instance globale du gestionnaire de base de données
db = DatabaseManager()

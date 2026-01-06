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

        # Table des catégories parentes
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                icon TEXT DEFAULT '',
                color TEXT DEFAULT '#1976D2',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """
        )

        # Table des sous-catégories
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS subcategories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                category_id INTEGER NOT NULL,
                icon TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
            )
        """
        )

        # Table des transactions
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date DATE NOT NULL,
                description TEXT NOT NULL,
                amount REAL NOT NULL,
                transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
                category_id INTEGER,
                subcategory_id INTEGER,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id),
                FOREIGN KEY (subcategory_id) REFERENCES subcategories(id)
            )
        """
        )

        # Table des actifs (patrimoine)
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS assets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                category_id INTEGER NOT NULL,
                current_value REAL NOT NULL DEFAULT 0,
                purchase_value REAL,
                purchase_date DATE,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id)
            )
        """
        )

        # Table historique des valeurs des actifs
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS asset_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                asset_id INTEGER NOT NULL,
                value REAL NOT NULL,
                recorded_at DATE NOT NULL,
                FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
            )
        """
        )

        conn.commit()

        # Insérer les catégories par défaut si elles n'existent pas
        self._insert_default_categories()

    def _insert_default_categories(self):
        """Insère les catégories par défaut."""
        default_categories = [
            ("Cash", "", "#4CAF50"),
            ("Immobilier", "", "#FF9800"),
            ("Bourse", "", "#2196F3"),
        ]

        default_subcategories = {
            "Cash": [
                ("Compte courant", ""),
                ("Livret A", ""),
                ("Livret Épargne", ""),
                ("Espèces", ""),
            ],
            "Immobilier": [
                ("Résidence principale", ""),
                ("Investissement locatif", ""),
                ("SCPI", ""),
            ],
            "Bourse": [
                ("Actions", ""),
                ("ETF", ""),
                ("Obligations", ""),
                ("Crypto", ""),
                ("PEA", ""),
            ],
        }

        conn = self._get_connection()
        cursor = conn.cursor()

        for name, icon, color in default_categories:
            cursor.execute(
                "INSERT OR IGNORE INTO categories (name, icon, color) VALUES (?, ?, ?)",
                (name, icon, color),
            )

            # Récupérer l'ID de la catégorie
            cursor.execute("SELECT id FROM categories WHERE name = ?", (name,))
            row = cursor.fetchone()
            if row:
                category_id = row[0]
                for sub_name, sub_icon in default_subcategories.get(name, []):
                    cursor.execute(
                        "INSERT OR IGNORE INTO subcategories (name, category_id, icon) VALUES (?, ?, ?)",
                        (sub_name, category_id, sub_icon),
                    )

        conn.commit()

    # ==================== CATÉGORIES ====================

    def get_all_categories(self) -> List[Dict[str, Any]]:
        """Récupère toutes les catégories."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM categories ORDER BY name")
        return [dict(row) for row in cursor.fetchall()]

    def get_subcategories(self, category_id: int) -> List[Dict[str, Any]]:
        """Récupère les sous-catégories d'une catégorie."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM subcategories WHERE category_id = ? ORDER BY name",
            (category_id,),
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_all_subcategories(self) -> List[Dict[str, Any]]:
        """Récupère toutes les sous-catégories avec leur catégorie parente."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT s.*, c.name as category_name, c.icon as category_icon, c.color as category_color
            FROM subcategories s
            JOIN categories c ON s.category_id = c.id
            ORDER BY c.name, s.name
        """
        )
        return [dict(row) for row in cursor.fetchall()]

    # ==================== TRANSACTIONS ====================

    def add_transaction(
        self,
        date: str,
        description: str,
        amount: float,
        transaction_type: str,
        category_id: Optional[int] = None,
        subcategory_id: Optional[int] = None,
        notes: Optional[str] = None,
    ) -> int:
        """Ajoute une nouvelle transaction."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO transactions (date, description, amount, transaction_type,
                                      category_id, subcategory_id, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
            (
                date,
                description,
                amount,
                transaction_type,
                category_id,
                subcategory_id,
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
            "subcategory_id",
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
            SELECT t.*, c.name as category_name, c.icon as category_icon,
                   s.name as subcategory_name, s.icon as subcategory_icon
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            LEFT JOIN subcategories s ON t.subcategory_id = s.id
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
            SELECT t.*, c.name as category_name, c.icon as category_icon,
                   s.name as subcategory_name, s.icon as subcategory_icon
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            LEFT JOIN subcategories s ON t.subcategory_id = s.id
            WHERE t.date BETWEEN ? AND ?
            ORDER BY t.date DESC
        """,
            (start_date, end_date),
        )
        return [dict(row) for row in cursor.fetchall()]

    # ==================== STATISTIQUES ====================

    def get_total_patrimony(self) -> float:
        """Calcule le patrimoine total (somme des transactions)."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT 
                COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount 
                                  WHEN transaction_type = 'expense' THEN -amount 
                                  ELSE 0 END), 0)
            FROM transactions
        """
        )
        return cursor.fetchone()[0]

    def get_monthly_summary(
        self, year: Optional[int] = None, month: Optional[int] = None
    ) -> Dict[str, float]:
        """Récupère le résumé mensuel des transactions."""
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
                COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) as income,
                COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) as expenses
            FROM transactions
            WHERE date >= ? AND date < ?
        """,
            (start_date, end_date),
        )

        row = cursor.fetchone()
        return {"income": row[0], "expenses": row[1], "balance": row[0] - row[1]}

    # ==================== EXPORT ====================

    def export_to_json(self, filepath: str) -> bool:
        """Exporte toutes les données en JSON."""
        try:
            data = {
                "categories": self.get_all_categories(),
                "subcategories": self.get_all_subcategories(),
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

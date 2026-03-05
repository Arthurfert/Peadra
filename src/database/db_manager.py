"""
Module de gestion de la base de données SQLite pour Peadra.
"""

import sqlite3
import json
import csv
from datetime import datetime, date, timedelta
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

        # Table des fichiers importés
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS imported_files (
                id INTEGER PRIMARY KEY,
                file_hash TEXT NOT NULL,
                filename TEXT,
                imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """
        )

        # Table des paramètres
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """
        )

        # Table des transactions récurrentes
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS recurring_transactions (
                id INTEGER PRIMARY KEY,
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

        cursor.execute(
            """
            SELECT c.*,
                   COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                     WHEN t.transaction_type = 'expense' THEN -t.amount
                                     ELSE 0 END), 0) AS balance
            FROM categories c
            LEFT JOIN transactions t ON t.category_id = c.id
            GROUP BY c.id
            ORDER BY c.name
            """
        )
        return [dict(row) for row in cursor.fetchall()]

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

        # 1. Get old name
        cursor.execute("SELECT name FROM categories WHERE id = ?", (category_id,))
        row = cursor.fetchone()
        if not row:
            return False
        old_name = row[0]

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

            rows_affected = cursor.rowcount

            # 2. Update transaction descriptions if name changed
            if rows_affected > 0 and old_name != name:
                # Update 'Transfer to ...'
                cursor.execute(
                    "UPDATE transactions SET description = ? WHERE description = ?",
                    (f"Transfer to {name}", f"Transfer to {old_name}"),
                )
                # Update 'Transfer from ...'
                cursor.execute(
                    "UPDATE transactions SET description = ? WHERE description = ?",
                    (f"Transfer from {name}", f"Transfer from {old_name}"),
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

    # ==================== TRANSACTIONS RÉCURRENTES ====================

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
    ) -> int:
        """Ajoute une transaction récurrente."""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        # Le premier next_due_date est la start_date
        next_due_date = start_date
        
        cursor.execute(
            """
            INSERT INTO recurring_transactions (
                description, amount, transaction_type, frequency, 
                interval, start_date, next_due_date, end_date, category_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
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

    def get_recurring_transactions(self) -> List[Dict[str, Any]]:
        """Récupère toutes les transactions récurrentes."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM recurring_transactions WHERE active = 1")
        return [dict(row) for row in cursor.fetchall()]
    
    def process_recurring_transactions(self):
        """
        Vérifie et génère les transactions dues.
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
            WHERE active = 1 AND next_due_date <= ?
            """, 
            (today_str,)
        )
        
        due_transactions = [dict(row) for row in cursor.fetchall()]
        
        for rt in due_transactions:
            # Récupérer la date actuelle de traitement pour cette règle
            current_next_due_str = rt['next_due_date']
            current_next_due = datetime.strptime(current_next_due_str, '%Y-%m-%d').date()
            
            # Boucle tant que la transaction est due
            while current_next_due <= today:
                # Vérifier la date de fin
                if rt['end_date']:
                    end_date = datetime.strptime(rt['end_date'], '%Y-%m-%d').date()
                    if current_next_due > end_date:
                        # Désactiver la transaction si la date de fin est dépassée
                        cursor.execute(
                            "UPDATE recurring_transactions SET active = 0 WHERE id = ?", 
                            (rt['id'],)
                        )
                        break # Sortir du while pour passer à la règle suivante
                
                # Créer la transaction réelle
                self.add_transaction(
                    date=current_next_due.isoformat(),
                    description=rt['description'],
                    amount=rt['amount'],
                    transaction_type=rt['transaction_type'],
                    category_id=rt['category_id'],
                    notes=f"Recurring: {rt['frequency']} (Rule #{rt['id']})"
                )
                
                # Calculer la prochaine date
                next_date = self._calculate_next_date(current_next_due, rt['frequency'], rt['interval'])
                next_date_str = next_date.isoformat()
                
                # Mettre à jour la règle pour la prochaine itération ou la fin
                cursor.execute(
                    """
                    UPDATE recurring_transactions 
                    SET last_generated = ?, next_due_date = ? 
                    WHERE id = ?
                    """,
                    (current_next_due.isoformat(), next_date_str, rt['id'])
                )
                
                # Avancer la date pour la prochaine boucle while
                current_next_due = next_date
            
        conn.commit()

    def _calculate_next_date(self, current_date: date, frequency: str, interval: int) -> date:
        """Calcule la prochaine date pour une récurrence."""
        if frequency == 'daily':
            return current_date + timedelta(days=interval)
        elif frequency == 'weekly':
            return current_date + timedelta(weeks=interval)
        elif frequency == 'monthly':
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
            
        elif frequency == 'yearly':
            try:
                return current_date.replace(year=current_date.year + interval)
            except ValueError:
                # Gérer le 29 février -> 28 février
                return current_date.replace(year=current_date.year + interval, month=2, day=28)
        
        return current_date # Fallback

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
        self,
        limit: Optional[int] = None,
        offset: int = 0,
        search_query: str = "",
        category_ids: Optional[set] = None,
    ) -> List[Dict[str, Any]]:
        """Récupère toutes les transactions."""
        conn = self._get_connection()
        cursor = conn.cursor()
        query = """
            SELECT t.*, c.name as category_name, c.color as category_color
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE 1=1
        """
        params = []

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
            WHERE t.date BETWEEN ? AND ?
            ORDER BY t.date DESC
        """,
            (start_date, end_date),
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_earliest_transaction_date(self) -> Optional[str]:
        """Récupère la date de la première transaction."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT MIN(date) FROM transactions")
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
            WHERE (t.date >= ? AND t.date <= ?) AND (c.type = 'checking' OR t.category_id IS NULL)
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

    # ==================== IMPORTS ====================

    def is_file_imported(self, file_hash: str) -> bool:
        """Vérifie si un fichier a déjà été importé."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT COUNT(*) FROM imported_files WHERE file_hash = ?", (file_hash,)
        )
        return cursor.fetchone()[0] > 0

    def log_imported_file(self, file_hash: str, filename: str):
        """Enregistre un fichier importé."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "INSERT INTO imported_files (file_hash, filename) VALUES (?, ?)",
                (file_hash, filename),
            )
            conn.commit()
        except Exception as e:
            print(f"Erreur enregistrement import: {str(e)}")

    # ==================== SETTINGS ====================

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        """Récupère un paramètre depuis la base de données."""
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM settings WHERE key = ?", (key,))
        result = cursor.fetchone()
        return result[0] if result else default

    def set_setting(self, key: str, value: str):
        """Enregistre un paramètre dans la base de données."""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                (key, value),
            )
            conn.commit()
        except Exception as e:
            print(f"Erreur sauvegarde paramètre {key}: {str(e)}")

    def close(self):
        """Ferme la connexion à la base de données."""
        if self.connection:
            self.connection.close()
            self.connection = None


# Instance globale du gestionnaire de base de données
db = DatabaseManager()

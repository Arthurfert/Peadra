"""
Tests complets pour le gestionnaire de base de données (DatabaseManager).
Regroupe les tests d'initialisation, CRUD, statistiques et fonctionnalités avancées.
"""

import pytest
import json
from datetime import datetime


# ==========================================
# Tests d'initialisation et de structure
# ==========================================

def test_database_initialization(db_manager):
    """Test que la base de données est correctement initialisée et que les tables existent."""
    conn = db_manager._get_connection()
    cursor = conn.cursor()

    # Vérifier que les tables existent
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]

    expected_tables = [
        "categories",
        "transactions",
    ]
    for table in expected_tables:
        assert table in tables, f"La table {table} devrait exister"


def test_default_categories_exist(db_manager):
    """Test que les catégories par défaut sont créées à l'initialisation."""
    conn = db_manager._get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM categories")
    count = cursor.fetchone()[0]
    assert count > 0, "Il devrait y avoir des catégories par défaut"


def test_migration_legacy_constraint_handled(db_manager):
    """Test que nous pouvons insérer le type 'checking' (vérifie que la migration/init autorise ce type)."""
    # Si la logique d'init de la DB échouait ou gardait les anciennes contraintes, cela échouerait avec IntegrityError
    try:
        db_manager.add_category("Test Checking", "#000", "checking")
    except Exception as e:
        pytest.fail(f"Impossible d'ajouter un compte de type 'checking' : {e}")


# ==========================================
# Tests CRUD Transactions
# ==========================================

def test_transaction_crud(db_manager):
    """Test des opérations CRUD (Create, Read, Update, Delete) pour les transactions."""
    # 1. Create
    tx_id = db_manager.add_transaction(
        date="2023-01-01",
        description="Test Transaction",
        amount=100.0,
        transaction_type="expense",
        category_id=1,
        notes="Test notes",
    )
    assert tx_id > 0

    # 2. Read
    transactions = db_manager.get_all_transactions()
    assert len(transactions) == 1
    assert transactions[0]["description"] == "Test Transaction"
    assert transactions[0]["amount"] == 100.0

    # 3. Update
    success = db_manager.update_transaction(
        tx_id, amount=150.0, description="Updated Transaction"
    )
    assert success is True

    updated_tx = db_manager.get_all_transactions()[0]
    assert updated_tx["amount"] == 150.0
    assert updated_tx["description"] == "Updated Transaction"

    # 4. Delete
    success = db_manager.delete_transaction(tx_id)
    assert success is True

    transactions = db_manager.get_all_transactions()
    assert len(transactions) == 0


def test_get_transactions_by_period(db_manager):
    """Test du filtrage des transactions par période."""
    # Ajouter des transactions avec différentes dates
    db_manager.add_transaction("2023-01-01", "T1", 10, "expense")
    db_manager.add_transaction("2023-01-15", "T2", 20, "expense")
    db_manager.add_transaction("2023-02-01", "T3", 30, "expense")

    # Filtrer pour Janvier
    jan_txs = db_manager.get_transactions_by_period("2023-01-01", "2023-01-31")
    assert len(jan_txs) == 2
    descriptions = [t["description"] for t in jan_txs]
    assert "T1" in descriptions
    assert "T2" in descriptions
    assert "T3" not in descriptions


# ==========================================
# Tests Catégories et Logique Métier
# ==========================================

def test_categories(db_manager):
    """Test de la récupération des catégories."""
    cats = db_manager.get_all_categories()
    assert len(cats) > 0

    # Vérifier la structure
    cat = cats[0]
    assert "id" in cat
    assert "name" in cat
    assert "color" in cat


def test_account_discrimination(db_manager):
    """Test que les comptes 'checking' et 'savings' sont correctement distingués dans les calculs."""
    
    # 1. Créer des comptes de test spécifiques
    checking_id = db_manager.add_category("My Checking", "#000000", account_type="checking")
    savings_id = db_manager.add_category("My Savings", "#FFFFFF", account_type="savings")
    
    assert checking_id > 0
    assert savings_id > 0
    
    # 2. Ajouter des transactions
    # +1000 sur Checking
    db_manager.add_transaction("2023-01-01", "Income Checking", 1000.0, "income", category_id=checking_id)
    # +5000 sur Savings
    db_manager.add_transaction("2023-01-01", "Income Savings", 5000.0, "income", category_id=savings_id)
    
    # 3. Vérifier la répartition
    
    # get_balance() doit retourner SEULEMENT la somme des comptes checking
    # Note: Le compte par défaut "Compte courant" est aussi checking, mais vide ici.
    balance = db_manager.get_balance()
    assert balance == 1000.0, f"Attendu 1000.0 pour le solde checking, reçu {balance}"
    
    # get_savings_total() doit retourner SEULEMENT la somme des comptes savings
    savings = db_manager.get_savings_total()
    assert savings == 5000.0, f"Attendu 5000.0 pour le total épargne, reçu {savings}"
    
    # get_total_patrimony() doit TOUT retourner (1000 + 5000 = 6000)
    total = db_manager.get_total_patrimony()
    assert total == 6000.0, f"Attendu 6000.0 pour le patrimoine total, reçu {total}"


def test_rename_category_propagates_to_transactions(db_manager):
    """Test que renommer une catégorie met à jour les descriptions de virement 'Transfer to/from'."""
    
    # 1. Setup
    cat_id = db_manager.add_category("Old Name", "#F00", "checking")
    
    # Créer des transactions avec des descriptions de virement
    t1_id = db_manager.add_transaction("2023-01-01", "Transfer to Old Name", 100.0, "expense", category_id=cat_id)
    t2_id = db_manager.add_transaction("2023-01-01", "Transfer from Old Name", 100.0, "income", category_id=cat_id)
    t3_id = db_manager.add_transaction("2023-01-01", "Unrelated Transaction", 50.0, "expense", category_id=cat_id)
    
    # 2. Action: Renommer la catégorie
    success = db_manager.update_category(cat_id, "New Name", "#0F0", "checking")
    assert success is True
    
    # 3. Validation
    txs = db_manager.get_all_transactions()
    
    t1 = next(t for t in txs if t["id"] == t1_id)
    t2 = next(t for t in txs if t["id"] == t2_id)
    t3 = next(t for t in txs if t["id"] == t3_id)
    
    assert t1["description"] == "Transfer to New Name", "La description aurait dû être mise à jour"
    assert t2["description"] == "Transfer from New Name", "La description aurait dû être mise à jour"
    assert t3["description"] == "Unrelated Transaction", "La description non liée ne devrait pas changer"


# ==========================================
# Tests Statistiques
# ==========================================

def test_statistics(db_manager):
    """Test du calcul global des statistiques (patrimoine)."""
    # 1. Income: +1000
    db_manager.add_transaction("2023-01-01", "Salary", 1000.0, "income")

    # 2. Expense: -200
    db_manager.add_transaction("2023-01-02", "Groceries", 200.0, "expense")

    # 3. Income: +500
    db_manager.add_transaction("2023-01-03", "Bonus", 500.0, "income")

    # Calcul Patrimoine Total: 1000 - 200 + 500 = 1300
    total = db_manager.get_total_patrimony()
    assert total == 1300.0


def test_monthly_summary(db_manager):
    """Test du calcul du résumé mensuel (uniquement flux Compte Courant)."""
    # Obtenir année et mois courants
    now = datetime.now()
    year, month = now.year, now.month

    # Ajouter revenu
    db_manager.add_transaction(f"{year}-{month:02d}-05", "Salary", 2000.0, "income")
    # Ajouter dépense
    db_manager.add_transaction(f"{year}-{month:02d}-10", "Rent", 800.0, "expense")

    summary = db_manager.get_monthly_summary(year, month)
    assert summary["income"] == 2000.0
    assert summary["expenses"] == 800.0
    assert summary["balance"] == 1200.0


# ==========================================
# Tests Export
# ==========================================

def test_export_json(db_manager, tmp_path):
    """Test de l'export des données en JSON."""
    # Ajouter des données
    db_manager.add_transaction("2023-01-01", "Test", 100, "expense")

    export_file = tmp_path / "export.json"
    success = db_manager.export_to_json(str(export_file))

    assert success is True
    assert export_file.exists()

    with open(export_file, "r", encoding="utf-8") as f:
        data = json.load(f)
        assert "transactions" in data
        assert len(data["transactions"]) == 1


def test_export_csv(db_manager, tmp_path):
    """Test de l'export des données en CSV."""
    # Ajouter des données
    db_manager.add_transaction("2023-01-01", "Test", 100, "expense")

    export_file = tmp_path / "export.csv"
    success = db_manager.export_to_csv(str(export_file), "transactions")

    assert success is True
    assert export_file.exists()

    with open(export_file, "r", encoding="utf-8") as f:
        content = f.read()
        assert "Test" in content

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
        "imported_files",
        "settings",
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


def test_get_all_transactions_pagination_and_filtering(db_manager):
    """Test de la pagination et du filtrage des transactions dans get_all_transactions."""
    # Ajouter des données variées
    cat1_id = db_manager.add_category("Groceries", "#CCC", "checking")
    cat2_id = db_manager.add_category("Salary Cat", "#DDD", "saving")

    db_manager.add_transaction(
        "2023-01-01", "Supermarket", 50, "expense", category_id=cat1_id
    )
    db_manager.add_transaction(
        "2023-01-02", "Bakery store", 10, "expense", category_id=cat1_id
    )
    db_manager.add_transaction(
        "2023-01-03", "Monthly Salary", 2000, "income", category_id=cat2_id
    )
    db_manager.add_transaction(
        "2023-01-04", "Gym membership", 30, "expense", category_id=cat1_id
    )

    # 1. Test Limit & Offset
    txs = db_manager.get_all_transactions(limit=2, offset=1)
    assert len(txs) == 2
    # L'ordre par défaut est date DESC, id DESC.
    # Les dates: 04, 03, 02, 01.
    # Offset 1 prend le 2e élément (03) et le 3e (02)
    assert txs[0]["description"] == "Monthly Salary"
    assert txs[1]["description"] == "Bakery store"

    # 2. Test Search Query (sur description "market" ou "salary")
    txs = db_manager.get_all_transactions(search_query="market")
    assert len(txs) == 1
    assert txs[0]["description"] == "Supermarket"

    # 3. Test Filtrage par catégories
    txs = db_manager.get_all_transactions(category_ids={str(cat2_id)})
    assert len(txs) == 1
    assert txs[0]["description"] == "Monthly Salary"

    # 4. Test combiné (catégories + recherche qui ne correspond pas)
    txs = db_manager.get_all_transactions(
        category_ids={str(cat2_id)}, search_query="super"
    )
    assert len(txs) == 0


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
    checking_id = db_manager.add_category(
        "My Checking", "#000000", account_type="checking"
    )
    savings_id = db_manager.add_category(
        "My Savings", "#FFFFFF", account_type="savings"
    )

    assert checking_id > 0
    assert savings_id > 0

    # 2. Ajouter des transactions
    # +1000 sur Checking
    db_manager.add_transaction(
        "2023-01-01", "Income Checking", 1000.0, "income", category_id=checking_id
    )
    # +5000 sur Savings
    db_manager.add_transaction(
        "2023-01-01", "Income Savings", 5000.0, "income", category_id=savings_id
    )

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


def test_accounts_distribution(db_manager):
    """Test que la répartition des comptes retourne les soldes attendus."""
    checking_id = db_manager.add_category(
        "Distribution Checking", "#111111", account_type="checking"
    )
    savings_id = db_manager.add_category(
        "Distribution Savings", "#222222", account_type="savings"
    )

    db_manager.add_transaction(
        "2023-01-01",
        "Checking income",
        1200.0,
        "income",
        category_id=checking_id,
    )
    db_manager.add_transaction(
        "2023-01-02",
        "Checking expense",
        450.0,
        "expense",
        category_id=checking_id,
    )
    db_manager.add_transaction(
        "2023-01-03",
        "Savings income",
        3000.0,
        "income",
        category_id=savings_id,
    )

    distribution = db_manager.get_accounts_distribution()
    balances = {item["name"]: item["value"] for item in distribution}

    assert balances["Distribution Checking"] == 750.0
    assert balances["Distribution Savings"] == 3000.0


def test_rename_category_propagates_to_transactions(db_manager):
    """Test que renommer une catégorie met à jour les descriptions de virement 'Transfer to/from'."""

    # 1. Setup
    cat_id = db_manager.add_category("Old Name", "#F00", "checking")

    # Créer des transactions avec des descriptions de virement
    t1_id = db_manager.add_transaction(
        "2023-01-01", "Transfer to Old Name", 100.0, "expense", category_id=cat_id
    )
    t2_id = db_manager.add_transaction(
        "2023-01-01", "Transfer from Old Name", 100.0, "income", category_id=cat_id
    )
    t3_id = db_manager.add_transaction(
        "2023-01-01", "Unrelated Transaction", 50.0, "expense", category_id=cat_id
    )

    # 2. Action: Renommer la catégorie
    success = db_manager.update_category(cat_id, "New Name", "#0F0", "checking")
    assert success is True

    # 3. Validation
    txs = db_manager.get_all_transactions()

    t1 = next(t for t in txs if t["id"] == t1_id)
    t2 = next(t for t in txs if t["id"] == t2_id)
    t3 = next(t for t in txs if t["id"] == t3_id)

    assert t1["description"] == "Transfer to New Name", (
        "La description aurait dû être mise à jour"
    )
    assert t2["description"] == "Transfer from New Name", (
        "La description aurait dû être mise à jour"
    )
    assert t3["description"] == "Unrelated Transaction", (
        "La description non liée ne devrait pas changer"
    )


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


# ==========================================
# Tests Imported Files
# ==========================================


def test_imported_files_management(db_manager):
    """Test de la gestion des fichiers importés (enregistrement et vérification)."""
    file_hash = "abcdef1234567890"
    filename = "test_import.csv"

    # Vérifier que le fichier n'est pas encore importé
    assert db_manager.is_file_imported(file_hash) is False

    # Enregistrer le fichier
    db_manager.log_imported_file(file_hash, filename)

    # Vérifier que le fichier est maintenant considéré comme importé
    assert db_manager.is_file_imported(file_hash) is True

    # Vérifier qu'un autre hash n'est pas importé
    assert db_manager.is_file_imported("otherhash") is False


# ==========================================
# Tests Settings
# ==========================================


def test_settings_management(db_manager):
    """Test de la gestion des paramètres (get et set)."""
    # 1. Get default value for non-existent setting
    val = db_manager.get_setting("non_existent_key", default="default_value")
    assert val == "default_value"

    # 2. Set new setting
    db_manager.set_setting("theme_mode", "dark")

    # 3. Get existing setting
    val = db_manager.get_setting("theme_mode")
    assert val == "dark"

    # 4. Update existing setting
    db_manager.set_setting("theme_mode", "light")
    val = db_manager.get_setting("theme_mode")
    assert val == "light"

    # 5. Check another setting
    db_manager.set_setting("month_mode", "rolling")
    val = db_manager.get_setting("month_mode")
    assert val == "rolling"

    # 6. App Password Hash
    db_manager.set_setting("app_password_hash", "123hash456")
    val = db_manager.get_setting("app_password_hash")
    assert val == "123hash456"

    # 7. User Name
    db_manager.set_setting("user_name", "Jean")
    val = db_manager.get_setting("user_name")
    assert val == "Jean"


# ==========================================
# Tests Transactions Récurrentes
# ==========================================


def test_get_recurring_transactions_without_display_month(db_manager):
    """Test que get_recurring_transactions() sans paramètre retourne seulement les transactions actives."""
    from datetime import date
    
    # Ajouter une transaction récurrente active
    active_id = db_manager.add_recurring_transaction(
        description="Active Subscription",
        amount=50.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2026-01-01",
        interval=1,
    )
    
    # Ajouter une transaction récurrente inactive avec end_date dans le futur
    inactive_id = db_manager.add_recurring_transaction(
        description="Inactive Subscription",
        amount=30.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2025-01-01",
        end_date="2026-02-28",  # Ends in the past
        interval=1,
    )
    
    # Marquer la deuxième comme inactive
    conn = db_manager._get_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_id,))
    conn.commit()
    
    # Appel sans display_month : devrait retourner uniquement les transactions actives
    result = db_manager.get_recurring_transactions()
    
    assert len(result) == 1
    assert result[0]["id"] == active_id
    assert result[0]["description"] == "Active Subscription"


def test_get_recurring_transactions_with_display_month_current(db_manager):
    """Test que get_recurring_transactions(display_month) retourne les transactions applicables au mois."""
    from datetime import date
    
    # Ajouter une transaction récurrente active
    active_id = db_manager.add_recurring_transaction(
        description="Active Subscription",
        amount=50.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2026-01-01",
        interval=1,
    )
    
    # Ajouter une transaction récurrente inactive avec end_date en avril 2026
    inactive_april_id = db_manager.add_recurring_transaction(
        description="Old Subscription (April)",
        amount=30.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2025-01-01",
        end_date="2026-04-30",
        interval=1,
    )
    
    # Marquer comme inactive
    conn = db_manager._get_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_april_id,))
    conn.commit()
    
    # Appel avec display_month=avril 2026
    april_2026 = date(2026, 4, 1)
    result = db_manager.get_recurring_transactions(display_month=april_2026)
    
    # Devrait retourner : active + inactive qui s'applique en avril
    assert len(result) == 2
    descriptions = [t["description"] for t in result]
    assert "Active Subscription" in descriptions
    assert "Old Subscription (April)" in descriptions


def test_get_recurring_transactions_with_display_month_past_terminated(db_manager):
    """Test que les transactions terminées avant le mois ne sont pas retournées."""
    from datetime import date
    
    # Ajouter une transaction récurrente active
    active_id = db_manager.add_recurring_transaction(
        description="Active Subscription",
        amount=50.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2026-01-01",
        interval=1,
    )
    
    # Ajouter une transaction récurrente inactive avec end_date en février 2026
    inactive_feb_id = db_manager.add_recurring_transaction(
        description="Old Subscription (Feb)",
        amount=30.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2025-01-01",
        end_date="2026-02-28",  # Ends February
        interval=1,
    )
    
    # Marquer comme inactive
    conn = db_manager._get_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_feb_id,))
    conn.commit()
    
    # Appel avec display_month=avril 2026 (après février)
    april_2026 = date(2026, 4, 1)
    result = db_manager.get_recurring_transactions(display_month=april_2026)
    
    # Devrait retourner seulement la transaction active (pas la février)
    assert len(result) == 1
    assert result[0]["id"] == active_id


def test_get_recurring_transactions_with_display_month_old_past(db_manager):
    """Test que les transactions applicables à un mois ancien sont retournées même si terminées."""
    from datetime import date
    
    # Ajouter une transaction récurrente active
    active_id = db_manager.add_recurring_transaction(
        description="Active Subscription",
        amount=50.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2026-01-01",
        interval=1,
    )
    
    # Ajouter une transaction récurrente inactive avec end_date en février 2026
    inactive_feb_id = db_manager.add_recurring_transaction(
        description="Old Subscription (Feb)",
        amount=30.0,
        transaction_type="expense",
        frequency="monthly",
        start_date="2025-01-01",
        end_date="2026-02-28",
        interval=1,
    )
    
    # Marquer comme inactive
    conn = db_manager._get_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_feb_id,))
    conn.commit()
    
    # Appel avec display_month=février 2026 (au moment où elle se termine)
    feb_2026 = date(2026, 2, 1)
    result = db_manager.get_recurring_transactions(display_month=feb_2026)
    
    # Devrait retourner : active + inactive qui s'applique en février
    assert len(result) == 2
    descriptions = [t["description"] for t in result]
    assert "Active Subscription" in descriptions
    assert "Old Subscription (Feb)" in descriptions


def test_recurring_transaction_crud(db_manager):
    """Test des opérations CRUD pour les transactions récurrentes."""
    from datetime import date
    
    # 1. Create
    tx_id = db_manager.add_recurring_transaction(
        description="Netflix",
        amount=12.99,
        transaction_type="expense",
        frequency="monthly",
        start_date="2026-01-01",
        interval=1,
        category_id=1,
    )
    assert tx_id > 0
    
    # 2. Read
    result = db_manager.get_recurring_transactions()
    assert len(result) == 1
    assert result[0]["description"] == "Netflix"
    
    # 3. Update
    success = db_manager.update_recurring_transaction(
        id=tx_id,
        description="Netflix Updated",
        amount=15.99,
        transaction_type="expense",
        frequency="monthly",
        start_date="2026-01-01",
        interval=1,
    )
    assert success is True
    
    result = db_manager.get_recurring_transactions()
    assert result[0]["description"] == "Netflix Updated"
    assert result[0]["amount"] == 15.99

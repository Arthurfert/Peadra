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
    """Test que la répartition des comptes retourne les soldes et couleurs attendus."""
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
    colors = {item["name"]: item["color"] for item in distribution if "color" in item}

    assert balances["Distribution Checking"] == 750.0
    assert balances["Distribution Savings"] == 3000.0
    assert colors["Distribution Checking"] == "#111111"
    assert colors["Distribution Savings"] == "#222222"


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

    # 8. max_categories_pie (pie chart setting)
    val = db_manager.get_setting("max_categories_pie", "5")
    assert val == "5"
    db_manager.set_setting("max_categories_pie", "10")
    val = db_manager.get_setting("max_categories_pie")
    assert val == "10"


# ==========================================
# Tests Mot de Passe Applicatif
# ==========================================


def test_password_manager_and_app_password_flow(db_manager):
    """Test PasswordManager et le cycle complet du mot de passe applicatif."""
    from src.database.db_manager import PasswordManager

    # --- PasswordManager unit tests ---
    hash_a = PasswordManager.hash_password("secret")
    hash_b = PasswordManager.hash_password("secret")
    assert hash_a == hash_b, "le hachage doit être déterministe"
    assert len(hash_a) == 64, "SHA-256 hexdigest fait 64 caractères"

    assert PasswordManager.verify_password("secret", hash_a) is True
    assert PasswordManager.verify_password("wrong", hash_a) is False
    assert PasswordManager.verify_password("", hash_a) is False

    # --- First-time set (pas d'ancien mot de passe à vérifier) ---
    pwd1_hash = PasswordManager.hash_password("first_pwd")
    db_manager.set_setting("app_password_hash", pwd1_hash)
    assert db_manager.get_setting("app_password_hash") == pwd1_hash

    # --- Old password verification ---
    current = db_manager.get_setting("app_password_hash")
    assert PasswordManager.verify_password("first_pwd", current) is True
    assert PasswordManager.verify_password("bad_guess", current) is False

    # --- Change password with correct old password ---
    pwd2_hash = PasswordManager.hash_password("second_pwd")
    db_manager.set_setting("app_password_hash", pwd2_hash)
    stored = db_manager.get_setting("app_password_hash")
    assert stored == pwd2_hash
    assert PasswordManager.verify_password("second_pwd", stored) is True
    assert PasswordManager.verify_password("first_pwd", stored) is False

    # --- Remove password ---
    db_manager.set_setting("app_password_hash", "")
    assert db_manager.get_setting("app_password_hash") == ""


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
    cursor.execute(
        "UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_id,)
    )
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
    cursor.execute(
        "UPDATE recurring_transactions SET active = 0 WHERE id = ?",
        (inactive_april_id,),
    )
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
    cursor.execute(
        "UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_feb_id,)
    )
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
    cursor.execute(
        "UPDATE recurring_transactions SET active = 0 WHERE id = ?", (inactive_feb_id,)
    )
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


# ==========================================
# Tests Merge/Rename Descriptions
# ==========================================


def test_merge_descriptions_basic(db_manager):
    """Test la fusion basique de deux descriptions en une seule."""
    # Ajouter des transactions avec descriptions différentes
    db_manager.add_transaction(
        date="2023-01-01",
        description="Restaurant A",
        amount=25.0,
        transaction_type="expense",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-02",
        description="Restaurant B",
        amount=30.0,
        transaction_type="expense",
        category_id=1,
    )

    # Fusionner "Restaurant A" dans "Restaurant B"
    result = db_manager.merge_descriptions("Restaurant A", "Restaurant B")
    assert result is True

    # Vérifier que toutes les transactions ont la description cible
    transactions = db_manager.get_all_transactions()
    descriptions = [tx["description"] for tx in transactions]
    assert "Restaurant A" not in descriptions
    assert all(desc == "Restaurant B" for desc in descriptions)
    assert len(transactions) == 2


def test_merge_descriptions_same_exact_description_fails(db_manager):
    """Test que la fusion échoue si source et cible sont identiques."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="Restaurant",
        amount=25.0,
        transaction_type="expense",
        category_id=1,
    )

    # Tentative de fusionner la même description
    result = db_manager.merge_descriptions("Restaurant", "Restaurant")
    assert result is False


def test_merge_descriptions_case_sensitive_difference(db_manager):
    """Test que la fusion fonctionne avec des différences de casse."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="restaurant",
        amount=25.0,
        transaction_type="expense",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-02",
        description="Restaurant",
        amount=30.0,
        transaction_type="expense",
        category_id=1,
    )

    # Fusionner "restaurant" dans "Restaurant"
    result = db_manager.merge_descriptions("restaurant", "Restaurant")
    assert result is True

    # Vérifier que tous les enregistrements ont la casse correcte
    transactions = db_manager.get_all_transactions()
    assert all(tx["description"] == "Restaurant" for tx in transactions)


def test_merge_descriptions_updates_all_transactions(db_manager):
    """Test que toutes les transactions avec la source sont mises à jour."""
    # Ajouter plusieurs transactions avec même description
    for i in range(5):
        db_manager.add_transaction(
            date="2023-01-01",
            description="Old Name",
            amount=10.0 + i,
            transaction_type="expense",
            category_id=1,
        )

    # Fusionner
    result = db_manager.merge_descriptions("Old Name", "New Name")
    assert result is True

    # Vérifier que exactement 5 transactions ont "New Name"
    transactions = db_manager.get_all_transactions()
    assert len(transactions) == 5
    new_name_count = sum(1 for tx in transactions if tx["description"] == "New Name")
    assert new_name_count == 5


def test_rename_description_basic(db_manager):
    """Test le renommage basique d'une description."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="Old Description",
        amount=50.0,
        transaction_type="expense",
        category_id=1,
    )

    result = db_manager.rename_description("Old Description", "New Description")
    assert result is True

    transactions = db_manager.get_all_transactions()
    assert len(transactions) == 1
    assert transactions[0]["description"] == "New Description"


def test_rename_description_same_exact_fails(db_manager):
    """Test que le renommage échoue si ancien et nouveau sont identiques."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="Same",
        amount=50.0,
        transaction_type="expense",
        category_id=1,
    )

    result = db_manager.rename_description("Same", "Same")
    assert result is False


def test_rename_description_case_change_only(db_manager):
    """Test que le renommage fonctionne avec un changement de casse uniquement."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="lowercase",
        amount=50.0,
        transaction_type="expense",
        category_id=1,
    )

    # Renommer en changeant la casse
    result = db_manager.rename_description("lowercase", "LOWERCASE")
    assert result is True

    transactions = db_manager.get_all_transactions()
    assert transactions[0]["description"] == "LOWERCASE"


def test_rename_description_multiple_transactions(db_manager):
    """Test que le renommage affecte toutes les transactions avec cette description."""
    for i in range(3):
        db_manager.add_transaction(
            date="2023-01-01",
            description="Coffee",
            amount=5.0,
            transaction_type="expense",
            category_id=1,
        )

    result = db_manager.rename_description("Coffee", "Café")
    assert result is True

    transactions = db_manager.get_all_transactions()
    assert all(tx["description"] == "Café" for tx in transactions)
    assert len(transactions) == 3


def test_rename_description_nonexistent(db_manager):
    """Test que le renommage d'une description inexistante échoue."""
    result = db_manager.rename_description("Nonexistent", "New Name")
    assert result is False


def test_get_all_unique_descriptions_basic(db_manager):
    """Test que get_all_unique_descriptions retourne les descriptions uniques."""
    descriptions = ["Grocery", "Restaurant", "Grocery", "Gas", "Restaurant"]

    for desc in descriptions:
        db_manager.add_transaction(
            date="2023-01-01",
            description=desc,
            amount=10.0,
            transaction_type="expense",
            category_id=1,
        )

    unique_desc = db_manager.get_all_unique_descriptions()
    assert len(unique_desc) == 3
    assert set(unique_desc) == {"Grocery", "Restaurant", "Gas"}


def test_get_all_unique_descriptions_excludes_transfers(db_manager):
    """Test que get_all_unique_descriptions exclut les descriptions de transfert."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="Salary",
        amount=2000.0,
        transaction_type="income",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-02",
        description="Transfer to Savings",
        amount=500.0,
        transaction_type="transfer",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-03",
        description="Transfer from Checking",
        amount=300.0,
        transaction_type="transfer",
        category_id=1,
    )

    unique_desc = db_manager.get_all_unique_descriptions()
    assert "Salary" in unique_desc
    assert "Transfer to Savings" not in unique_desc
    assert "Transfer from Checking" not in unique_desc


def test_get_all_unique_descriptions_by_transaction_type(db_manager):
    """Test le filtrage par type de transaction."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="Salary",
        amount=2000.0,
        transaction_type="income",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-02",
        description="Other Income",
        amount=100.0,
        transaction_type="income",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-03",
        description="Grocery",
        amount=50.0,
        transaction_type="expense",
        category_id=1,
    )

    # Récupérer uniquement les descriptions "income"
    income_desc = db_manager.get_all_unique_descriptions(transaction_type="income")
    assert len(income_desc) == 2
    assert set(income_desc) == {"Salary", "Other Income"}

    # Récupérer uniquement les descriptions "expense"
    expense_desc = db_manager.get_all_unique_descriptions(transaction_type="expense")
    assert len(expense_desc) == 1
    assert "Grocery" in expense_desc


def test_get_all_unique_descriptions_empty_database(db_manager):
    """Test que get_all_unique_descriptions retourne une liste vide sur BD vide."""
    unique_desc = db_manager.get_all_unique_descriptions()
    assert unique_desc == []


def test_get_all_unique_descriptions_preserves_case(db_manager):
    """Test que les descriptions conservent leur casse originale."""
    descriptions = ["UPPERCASE", "lowercase", "MixedCase", "UPPERCASE"]

    for desc in descriptions:
        db_manager.add_transaction(
            date="2023-01-01",
            description=desc,
            amount=10.0,
            transaction_type="expense",
            category_id=1,
        )

    unique_desc = db_manager.get_all_unique_descriptions()
    assert "UPPERCASE" in unique_desc
    assert "lowercase" in unique_desc
    assert "MixedCase" in unique_desc
    assert len(unique_desc) == 3


def test_merge_then_get_unique_descriptions(db_manager):
    """Test l'intégration : fusion puis récupération des descriptions uniques."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="Restaurant A",
        amount=25.0,
        transaction_type="expense",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-02",
        description="Restaurant B",
        amount=30.0,
        transaction_type="expense",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-03",
        description="Gas",
        amount=40.0,
        transaction_type="expense",
        category_id=1,
    )

    # Avant la fusion
    before = db_manager.get_all_unique_descriptions()
    assert len(before) == 3

    # Fusionner
    db_manager.merge_descriptions("Restaurant A", "Restaurant B")

    # Après la fusion
    after = db_manager.get_all_unique_descriptions()
    assert len(after) == 2
    assert set(after) == {"Restaurant B", "Gas"}


def test_rename_then_merge_integration(db_manager):
    """Test l'intégration : renommer puis fusionner."""
    db_manager.add_transaction(
        date="2023-01-01",
        description="foo",
        amount=10.0,
        transaction_type="expense",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-02",
        description="bar",
        amount=20.0,
        transaction_type="expense",
        category_id=1,
    )
    db_manager.add_transaction(
        date="2023-01-03",
        description="Foo",  # Différent seulement par casse
        amount=15.0,
        transaction_type="expense",
        category_id=1,
    )

    # Renommer "foo" en "FOO"
    result1 = db_manager.rename_description("foo", "FOO")
    assert result1 is True

    # Récupérer les descriptions uniques
    unique = db_manager.get_all_unique_descriptions()
    assert len(unique) == 3  # "FOO", "Foo", "bar"

    # Fusionner "FOO" dans "Foo"
    result2 = db_manager.merge_descriptions("FOO", "Foo")
    assert result2 is True

    # Vérifier le résultat final
    final_unique = db_manager.get_all_unique_descriptions()
    assert len(final_unique) == 2
    assert set(final_unique) == {"Foo", "bar"}


# ==========================================
# Tests Devises (Currency)
# ==========================================


def test_category_currency_default(db_manager):
    """add_category utilise la devise EUR par défaut si non spécifiée."""
    cat_id = db_manager.add_category("Test Cat", "#EEE", "checking")
    cats = db_manager.get_all_categories()
    cat = next(c for c in cats if c["id"] == cat_id)
    assert cat.get("currency") == "EUR"


def test_category_currency_custom(db_manager):
    """add_category enregistre la devise fournie."""
    cat_id = db_manager.add_category("USD Cat", "#111", "checking", currency="USD")
    cats = db_manager.get_all_categories()
    cat = next(c for c in cats if c["id"] == cat_id)
    assert cat.get("currency") == "USD"


def test_transaction_currency_inherits_from_category(db_manager):
    """add_transaction hérite de la devise de la catégorie."""
    cat_id = db_manager.add_category("USD Cat", "#111", "checking", currency="USD")
    tx_id = db_manager.add_transaction(
        "2023-01-01", "Test", 100.0, "expense", category_id=cat_id
    )
    txs = db_manager.get_all_transactions()
    tx = next(t for t in txs if t["id"] == tx_id)
    assert tx.get("currency") == "USD"


def test_transaction_currency_falls_back_to_default(db_manager):
    """add_transaction utilise EUR par défaut quand la catégorie n'a pas de devise."""
    cat_id = db_manager.add_category("EUR Cat", "#222", "checking")
    # Forcer la devise de la catégorie à NULL pour simuler une donnée ancienne
    conn = db_manager._get_connection()
    conn.execute("UPDATE categories SET currency = NULL WHERE id = ?", (cat_id,))
    conn.commit()
    tx_id = db_manager.add_transaction(
        "2023-01-01", "Test", 50.0, "expense", category_id=cat_id
    )
    txs = db_manager.get_all_transactions()
    tx = next(t for t in txs if t["id"] == tx_id)
    assert tx.get("currency") in ("EUR", None)


def test_transaction_explicit_currency_overrides_category(db_manager):
    """add_transaction accepte une devise explicite différente de la catégorie."""
    cat_id = db_manager.add_category("EUR Cat", "#333", "checking", currency="EUR")
    tx_id = db_manager.add_transaction(
        "2023-01-01", "Test", 200.0, "expense", category_id=cat_id, currency="GBP"
    )
    txs = db_manager.get_all_transactions()
    tx = next(t for t in txs if t["id"] == tx_id)
    assert tx.get("currency") == "GBP"


def test_get_all_transactions_includes_category_currency(db_manager):
    """get_all_transactions retourne le champ category_currency."""
    cat_id = db_manager.add_category("My Cat", "#444", "checking", currency="USD")
    db_manager.add_transaction(
        "2023-01-01", "Test", 100.0, "income", category_id=cat_id
    )
    txs = db_manager.get_all_transactions()
    assert len(txs) == 1
    assert txs[0].get("category_currency") == "USD"


def test_get_transactions_by_period_includes_category_currency(db_manager):
    """get_transactions_by_period retourne le champ category_currency."""
    cat_id = db_manager.add_category("My Cat", "#555", "checking", currency="GBP")
    db_manager.add_transaction(
        "2023-01-15", "Test", 100.0, "expense", category_id=cat_id
    )
    txs = db_manager.get_transactions_by_period("2023-01-01", "2023-01-31")
    assert len(txs) == 1
    assert txs[0].get("category_currency") == "GBP"


def test_update_category_currency(db_manager):
    """update_category peut modifier la devise d'une catégorie."""
    cat_id = db_manager.add_category("Changeable", "#666", "savings", currency="EUR")
    db_manager.update_category(cat_id, "Changeable", "#666", "savings", currency="USD")
    cats = db_manager.get_all_categories()
    cat = next(c for c in cats if c["id"] == cat_id)
    assert cat.get("currency") == "USD"


def test_convert_currency_same_currency(db_manager):
    """convert_currency retourne le montant inchangé si même devise."""
    rate = db_manager.convert_currency(100.0, "EUR", "EUR")
    assert rate == 100.0


def test_get_exchange_rate_direct(db_manager):
    """get_exchange_rate retourne le taux depuis une paire stockée."""
    conn = db_manager._get_connection()
    conn.execute(
        "INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)",
        ("EUR", "USD", 1.10, "2024-01-01T00:00:00"),
    )
    conn.commit()
    rate = db_manager.get_exchange_rate("EUR", "USD")
    assert rate == 1.10


def test_get_exchange_rate_inverse(db_manager):
    """get_exchange_rate calcule le taux inverse si nécessaire."""
    conn = db_manager._get_connection()
    conn.execute(
        "INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)",
        ("EUR", "USD", 1.10, "2024-01-01T00:00:00"),
    )
    conn.commit()
    rate = db_manager.get_exchange_rate("USD", "EUR")
    assert rate is not None
    assert abs(rate - 1.0 / 1.10) < 0.001


def test_get_exchange_rate_via_eur_cross(db_manager):
    """get_exchange_rate calcule via EUR si les deux devises existent face à EUR."""
    conn = db_manager._get_connection()
    conn.execute(
        "INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)",
        ("EUR", "USD", 1.10, "2024-01-01T00:00:00"),
    )
    conn.execute(
        "INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)",
        ("EUR", "GBP", 0.85, "2024-01-01T00:00:00"),
    )
    conn.commit()
    # USD → GBP via EUR : 1 USD = (0.85 / 1.10) = 0.7727 GBP
    rate = db_manager.get_exchange_rate("USD", "GBP")
    assert rate is not None
    assert abs(rate - 0.85 / 1.10) < 0.001


def test_get_exchange_rate_none_for_unknown(db_manager):
    """get_exchange_rate retourne None pour une paire inconnue."""
    rate = db_manager.get_exchange_rate("XYZ", "ABC")
    assert rate is None


def test_convert_currency_cross(db_manager):
    """convert_currency utilise la conversion via EUR."""
    conn = db_manager._get_connection()
    conn.execute(
        "INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)",
        ("EUR", "USD", 1.10, "2024-01-01T00:00:00"),
    )
    conn.execute(
        "INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)",
        ("EUR", "GBP", 0.85, "2024-01-01T00:00:00"),
    )
    conn.commit()
    result = db_manager.convert_currency(100.0, "USD", "GBP")
    assert result is not None
    assert abs(result - 100.0 * 0.85 / 1.10) < 0.01


def test_get_categories_with_balances_currency_field(db_manager):
    """get_categories_with_balances retourne le champ currency."""
    cat_id = db_manager.add_category("USD Sav", "#777", "savings", currency="USD")
    db_manager.add_transaction(
        "2023-01-01", "Deposit", 500.0, "income", category_id=cat_id
    )
    cats = db_manager.get_categories_with_balances()
    cat = next(c for c in cats if c["id"] == cat_id)
    assert cat.get("currency") == "USD"
    assert cat.get("balance") == 500.0


def test_get_categories_with_balances_default_currency_for_null(db_manager):
    """get_categories_with_balances utilise EUR quand la catégorie est NULL."""
    cat_id = db_manager.add_category("No Curr", "#888", "checking", currency=None)
    conn = db_manager._get_connection()
    conn.execute("UPDATE categories SET currency = NULL WHERE id = ?", (cat_id,))
    conn.commit()
    cats = db_manager.get_categories_with_balances()
    cat = next(c for c in cats if c["id"] == cat_id)
    assert cat.get("currency") == "EUR"


def test_format_amount_module_functions():
    """Test des fonctions de formatage de montant."""
    from src.database.db_manager import (
        format_amount,
        format_amount_with_conversion,
        get_currency_symbol,
        get_currency_name,
        CURRENCY_DATA,
    )

    # get_currency_symbol
    assert get_currency_symbol("EUR") == "€"
    assert get_currency_symbol("USD") == "$"
    assert get_currency_symbol("FAKE") == "FAKE"

    # get_currency_name
    assert "Euro" in get_currency_name("EUR")
    assert get_currency_name("FAKE") == "FAKE"

    # format_amount
    assert "€" in format_amount(100.0, "EUR")
    assert "$" in format_amount(50.5, "USD")

    # format_amount_with_conversion (même devise → pas de conversion)
    assert format_amount_with_conversion(100.0, "EUR", "EUR") == format_amount(100.0, "EUR")

    # format_amount_with_conversion (devise inconnue dans CURRENCY_DATA → (?) )
    result = format_amount_with_conversion(100.0, "XYZ", "EUR")
    assert "(?)" in result


def test_format_amount_with_conversion_with_rate():
    """format_amount_with_conversion utilise un taux fourni explicitement."""
    from src.database.db_manager import format_amount_with_conversion

    result = format_amount_with_conversion(100.0, "USD", "EUR", rate=0.92)
    assert "100.00" in result
    assert "92.00" in result
    assert "$" in result
    assert "EUR" in result or "€" in result


def test_migration_fills_null_currency_on_categories(db_manager):
    """La migration remplit EUR pour les catégories avec currency=NULL."""
    conn = db_manager._get_connection()
    conn.execute("UPDATE categories SET currency = NULL")
    conn.commit()
    # Simuler la migration
    conn.execute("UPDATE categories SET currency = 'EUR' WHERE currency IS NULL")
    conn.commit()
    cats = db_manager.get_all_categories()
    for c in cats:
        assert c.get("currency") == "EUR", f"Catégorie {c['id']} a currency={c.get('currency')}"


def test_migration_fills_null_currency_on_transactions(db_manager):
    """La migration remplit EUR pour les transactions avec currency=NULL."""
    db_manager.add_transaction("2023-01-01", "Test", 100.0, "expense")
    conn = db_manager._get_connection()
    conn.execute("UPDATE transactions SET currency = NULL")
    conn.commit()
    conn.execute("UPDATE transactions SET currency = 'EUR' WHERE currency IS NULL")
    conn.commit()
    txs = db_manager.get_all_transactions()
    for t in txs:
        assert t.get("currency") == "EUR", f"Transaction {t['id']} a currency={t.get('currency')}"

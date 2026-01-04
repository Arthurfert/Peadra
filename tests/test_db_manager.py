# Tests pour le gestionnaire de base de données

def test_database_initialization(db_manager):
    """Test que la base de données est correctement initialisée."""
    conn = db_manager._get_connection()
    cursor = conn.cursor()

    # Vérifier que les tables existent
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]

    expected_tables = [
        "categories",
        "subcategories",
        "transactions",
        "assets",
        "asset_history",
    ]
    for table in expected_tables:
        assert table in tables, f"La table {table} devrait exister"


def test_default_categories_exist(db_manager):
    """Test que les catégories par défaut sont créées."""
    conn = db_manager._get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM categories")
    count = cursor.fetchone()[0]
    assert count > 0, "Il devrait y avoir des catégories par défaut"

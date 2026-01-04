from datetime import datetime
import json


def test_transaction_crud(db_manager):
    """Test CRUD operations for transactions."""
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
    """Test filtering transactions by date period."""
    # Add transactions with different dates
    db_manager.add_transaction("2023-01-01", "T1", 10, "expense")
    db_manager.add_transaction("2023-01-15", "T2", 20, "expense")
    db_manager.add_transaction("2023-02-01", "T3", 30, "expense")

    # Filter for January
    jan_txs = db_manager.get_transactions_by_period("2023-01-01", "2023-01-31")
    assert len(jan_txs) == 2
    descriptions = [t["description"] for t in jan_txs]
    assert "T1" in descriptions
    assert "T2" in descriptions
    assert "T3" not in descriptions


def test_asset_crud(db_manager):
    """Test CRUD operations for assets."""
    # 1. Create
    asset_id = db_manager.add_asset(
        name="Test Asset",
        category_id=1,
        current_value=1000.0,
        purchase_value=900.0,
        purchase_date="2022-01-01",
    )
    assert asset_id > 0

    # 2. Read
    assets = db_manager.get_all_assets()
    assert len(assets) == 1
    assert assets[0]["name"] == "Test Asset"
    assert assets[0]["current_value"] == 1000.0

    # Check history was created
    history = db_manager.get_asset_history(asset_id)
    assert len(history) == 1
    assert history[0]["value"] == 1000.0

    # 3. Update Value
    success = db_manager.update_asset_value(asset_id, 1100.0)
    assert success is True

    assets = db_manager.get_all_assets()
    assert assets[0]["current_value"] == 1100.0

    # Check history was updated
    history = db_manager.get_asset_history(asset_id)
    assert len(history) == 2
    assert history[1]["value"] == 1100.0

    # 4. Delete
    success = db_manager.delete_asset(asset_id)
    assert success is True

    assets = db_manager.get_all_assets()
    assert len(assets) == 0


def test_statistics(db_manager):
    """Test statistics calculation."""
    # Setup data
    # Asset 1: 1000
    db_manager.add_asset("Asset 1", 1, 1000.0)
    # Asset 2: 2000
    db_manager.add_asset("Asset 2", 1, 2000.0)

    # Total Patrimony
    total = db_manager.get_total_patrimony()
    assert total == 3000.0

    # Patrimony by Category
    by_cat = db_manager.get_patrimony_by_category()
    # Find the category with id 1 (Cash usually)
    cat_stat = next((c for c in by_cat if c["id"] == 1), None)
    assert cat_stat is not None
    assert cat_stat["total"] == 3000.0


def test_categories_and_subcategories(db_manager):
    """Test retrieval of categories and subcategories."""
    cats = db_manager.get_all_categories()
    assert len(cats) > 0

    # Pick the first category
    first_cat_id = cats[0]["id"]

    subcats = db_manager.get_subcategories(first_cat_id)
    # We expect some default subcategories
    assert isinstance(subcats, list)

    all_subcats = db_manager.get_all_subcategories()
    assert len(all_subcats) > 0
    assert "category_name" in all_subcats[0]


def test_monthly_summary(db_manager):
    """Test monthly summary calculation."""
    # Get current year and month
    now = datetime.now()
    year, month = now.year, now.month

    # Add income
    db_manager.add_transaction(f"{year}-{month:02d}-05", "Salary", 2000.0, "income")
    # Add expense
    db_manager.add_transaction(f"{year}-{month:02d}-10", "Rent", 800.0, "expense")

    summary = db_manager.get_monthly_summary(year, month)
    assert summary["income"] == 2000.0
    assert summary["expenses"] == 800.0
    assert summary["balance"] == 1200.0


def test_export_json(db_manager, tmp_path):
    """Test exporting data to JSON."""
    # Add some data
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
    """Test exporting data to CSV."""
    # Add some data
    db_manager.add_transaction("2023-01-01", "Test", 100, "expense")

    export_file = tmp_path / "export.csv"
    success = db_manager.export_to_csv(str(export_file), "transactions")

    assert success is True
    assert export_file.exists()

    with open(export_file, "r", encoding="utf-8") as f:
        content = f.read()
        assert "Test" in content

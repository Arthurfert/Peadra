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


def test_statistics(db_manager):
    """Test statistics calculation."""
    # Setup data using transactions (income adds, expense subtracts)

    # 1. Income: +1000
    db_manager.add_transaction("2023-01-01", "Salary", 1000.0, "income")

    # 2. Expense: -200
    db_manager.add_transaction("2023-01-02", "Groceries", 200.0, "expense")

    # 3. Income: +500
    db_manager.add_transaction("2023-01-03", "Bonus", 500.0, "income")

    # Total Patrimony calculation: 1000 - 200 + 500 = 1300
    total = db_manager.get_total_patrimony()
    assert total == 1300.0


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

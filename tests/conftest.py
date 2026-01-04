import pytest
from src.database.db_manager import DatabaseManager

@pytest.fixture
def db_manager(tmp_path):
    """Fixture pour créer une base de données temporaire pour les tests."""
    # Utiliser un fichier temporaire dans le répertoire tmp_path fourni par pytest
    db_file = tmp_path / "test_peadra.db"
    manager = DatabaseManager(db_path=str(db_file))
    yield manager
    # Le nettoyage est géré automatiquement par tmp_path, 
    # mais on ferme la connexion explicitement
    if manager.connection:
        manager.connection.close()

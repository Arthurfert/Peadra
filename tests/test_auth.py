#!/usr/bin/env python3
"""
Script de test pour vérifier le système d'authentification multi-comptes.
"""

import sys
import os

# Ajouter le répertoire racine au chemin
sys.path.insert(0, os.path.dirname(__file__))

from src.database.db_manager import db, PasswordManager


def test_auth_system():
    """Test du système d'authentification."""
    print("=" * 60)
    print("Test du système d'authentification Peadra")
    print("=" * 60)

    # Test 1: Enregistrement d'un nouvel utilisateur
    print("\n1. Test d'enregistrement...")
    success = db.register_user("test_user", "password123")
    print(f"   Enregistrement: {'✓ Succès' if success else '✗ Échoué'}")

    # Test 2: Essayer d'enregistrer le même utilisateur
    print("\n2. Test de doublon...")
    duplicate = db.register_user("test_user", "password123")
    print(f"   Rejet du doublon: {'✓ Succès' if not duplicate else '✗ Échoué'}")

    # Test 3: Authentification correcte
    print("\n3. Test d'authentification correcte...")
    user_id = db.authenticate_user("test_user", "password123")
    print(f"   Authentification réussie: {'✓ Succès' if user_id else '✗ Échoué'}")
    if user_id:
        print(f"   User ID: {user_id}")

    # Initialiser les variables
    cat_id = 0
    trans_id = 0

    # Test 4: Authentification incorrecte
    print("\n4. Test d'authentification incorrecte...")
    wrong_auth = db.authenticate_user("test_user", "wrongpassword")
    print(
        f"   Rejet du mauvais mot de passe: {'✓ Succès' if wrong_auth is None else '✗ Échoué'}"
    )

    # Test 5: Définir l'utilisateur courant
    print("\n5. Test de définition de l'utilisateur courant...")
    if user_id:
        db.set_current_user(user_id)
        print(
            f"   Utilisateur courant: {'✓ Succès' if db.user_id == user_id else '✗ Échoué'}"
        )

    # Test 6: Créer une catégorie pour l'utilisateur
    print("\n6. Test de création de catégorie...")
    if user_id:
        cat_id = db.add_category("Mon Compte", "#FF0000")
        print(f"   Création de catégorie: {'✓ Succès' if cat_id > 0 else '✗ Échoué'}")
        if cat_id > 0:
            print(f"   Category ID: {cat_id}")

    # Test 7: Ajouter une transaction
    print("\n7. Test d'ajout de transaction...")
    if user_id and cat_id > 0:
        trans_id = db.add_transaction(
            date="2024-01-15",
            description="Test transaction",
            amount=100.00,
            transaction_type="income",
            category_id=cat_id,
        )
        print(
            f"   Création de transaction: {'✓ Succès' if trans_id > 0 else '✗ Échoué'}"
        )
        if trans_id > 0:
            print(f"   Transaction ID: {trans_id}")

    # Test 8: Récupérer les catégories
    print("\n8. Test de récupération des catégories...")
    categories = db.get_all_categories()
    print(f"   Catégories trouvées: {len(categories)}")
    for cat in categories:
        print(f"     - {cat['name']} (ID: {cat['id']})")

    # Test 9: Récupérer les transactions
    print("\n9. Test de récupération des transactions...")
    transactions = db.get_all_transactions()
    print(f"   Transactions trouvées: {len(transactions)}")
    for trans in transactions:
        print(
            f"     - {trans['description']}: {trans['amount']} (Type: {trans['transaction_type']})"
        )

    # Test 10: Créer un autre utilisateur
    print("\n10. Test de création d'un deuxième utilisateur...")
    success2 = db.register_user("autre_user", "motdepasse456")
    print(
        f"    Enregistrement du 2e utilisateur: {'✓ Succès' if success2 else '✗ Échoué'}"
    )

    # Test 11: Vérifier que les données sont isolées
    print("\n11. Test d'isolation des données...")
    user_id2 = db.authenticate_user("autre_user", "motdepasse456")
    if user_id2:
        db.set_current_user(user_id2)
        categories2 = db.get_all_categories()
        print(f"    Catégories du 2e utilisateur: {len(categories2)}")
        print(
            f"    Isolation correcte: {'✓ Succès' if len(categories2) <= 3 else '✗ Échoué'}"
        )

    # Test 12: Récupérer la liste des utilisateurs
    print("\n12. Test de récupération des utilisateurs...")
    usernames = db.get_all_usernames()
    print(f"    Utilisateurs trouvés: {len(usernames)}")
    for username in usernames:
        print(f"      - {username}")

    print("\n" + "=" * 60)
    print("Tests complétés!")
    print("=" * 60)


if __name__ == "__main__":
    test_auth_system()

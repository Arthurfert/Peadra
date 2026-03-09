from datetime import date
import pytest
from src.views.subscriptions import SubscriptionsView

class TestSubscriptionsViewProjections:

    def test_calculate_projection_monthly_full_year(self):
        """Test pour une transaction existant sur toute l'année (pas de date de fin ou fin > fin d'année, début < début d'année)."""
        tx = {
            "amount": 20.0,
            "frequency": "monthly",
            "interval": 1,
            "start_date": "2025-01-01",  # A commencé l'année dernière
            # pas de end_date
        }
        today = date(2026, 3, 6)
        
        yearly_total, label, is_valid = SubscriptionsView.calculate_projection(tx, today)
        
        assert is_valid is True
        assert label == "Projection 2026"
        assert yearly_total == 240.0

    def test_calculate_projection_monthly_starts_february(self):
        """Test pour une transaction mensuelle qui commence en février de l'année en cours (11 mois)."""
        tx = {
            "amount": 20.0,
            "frequency": "monthly",
            "interval": 1,
            "start_date": "2026-02-15",
        }
        today = date(2026, 3, 6)
        
        yearly_total, label, is_valid = SubscriptionsView.calculate_projection(tx, today)
        
        assert is_valid is True
        assert label == "Projection 2026"
        # 11 mois allant de février à décembre
        assert yearly_total == 220.0

    def test_calculate_projection_total_before_end_of_year(self):
        """Test avec une date de fin avant la fin de l'année en cours."""
        tx = {
            "amount": 10.0,
            "frequency": "monthly",
            "interval": 1,
            "start_date": "2026-01-01",
            "end_date": "2026-06-30"
        }
        today = date(2026, 3, 6)
        
        yearly_total, label, is_valid = SubscriptionsView.calculate_projection(tx, today)
        
        assert is_valid is True
        assert label == "Total projection"
        # De janvier à juin -> 6 mois * 10€ = 60€
        assert yearly_total == 60.0

    def test_calculate_projection_already_ended(self):
        """Test avec une date de fin qui s'est produite l'année précédente."""
        tx = {
            "amount": 50.0,
            "frequency": "monthly",
            "interval": 1,
            "start_date": "2024-01-01",
            "end_date": "2025-12-31" # Fini l'an dernier
        }
        today = date(2026, 3, 6)
        
        yearly_total, label, is_valid = SubscriptionsView.calculate_projection(tx, today)
        
        assert is_valid is False
        assert yearly_total == 0.0

    def test_calculate_projection_weekly_interval(self):
        """Test pour un versement périodique mais de type 'weekly' avec interval>1 (ex toutes les 2 semaines)."""
        tx = {
            "amount": 5.0,
            "frequency": "weekly",
            "interval": 2, # Toutes les 2 semaines
            "start_date": "2026-01-01",
        }
        today = date(2026, 3, 6)
        
        yearly_total, label, is_valid = SubscriptionsView.calculate_projection(tx, today)
        
        assert is_valid is True
        assert label == "Projection 2026"
        # (365 jours / (7 * 2)) * 5€ = approx 26 occurrences = 130.35
        # 365 / 14 = 26.0714 -> 26.0714 * 5 = 130.357
        assert round(yearly_total, 2) == 130.36

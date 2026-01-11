# Peadra

A personal wealth management application built with Python and Flet.

>**🚧 Early phase of the project 🚧**\
The app is partially translated (some parts still in french for the moment)\
More features and UI/UX improvements to come

## Overview

Peadra (*“wealth” in Breton*) is a desktop application designed to help you track and manage your personal finances in a simple and transparent way.

The project has recently been simplified to focus on the essentials: managing your bank transactions, tracking your daily budget, and managing your cash savings.

## Features

### Dashboard
- **Financial overview**: Instantly view your *Current Balance* (Checking Account) and your *Savings* (savings accounts).
- **Flow tracking**: Interactive graphs showing the monthly evolution of your income vs. expenses.
- **Top Expenses**: Instant view of the month's biggest expense items.

### Transaction Management
- **New intuitive selector**: Choose between *Expense*, *Income*, or *Transfer* via a modern, colorful interface.
- **Automated Transfers**: A transfer between two accounts automatically creates the two corresponding entries (debit/credit) to keep your balances up to date.
- **Filters & Search**: Quickly find your transactions by description or account category.
- **Color Coding**: Immediate visual identification of transaction types.

## Installation

### Prerequisites
- Python 3.10 ou supérieur
- pip (Python package manager)

### Setup

1. Clonez le dépôt :
```bash
git clone https://github.com/yourusername/Peadra.git
cd Peadra
```

2. Créez un environnement virtuel (recommandé) :
```bash
python -m venv venv
source venv/bin/activate  # Sur Windows: venv\Scripts\activate
```

3. Installez les dépendances :
```bash
pip install -r requirements.txt
```

4. Lancez l'application :
```bash
python main.py
```

## Project Structure

```
Peadra/
├── main.py                 # Point d'entrée de l'application
├── requirements.txt        # Dépendances Python
└── src/
    ├── components/        # Composants UI réutilisables (Modals, Navigation, Thème)
    ├── database/          # Couche d'accès aux données (SQLite)
    └── views/             # Vues de l'application (Dashboard, Transactions)
```

## Technologies

- **Python 3.10+**
- **Flet** - Framework UI moderne basé sur Flutter
- **SQLite** - Base de données locale pour la persistance et la vie privée

## Usage

### Add a Transfer
1. Go to the “Transactions” tab.
2. Click on “Add Transaction.”
3. Select “Transfer.”
4. Choose the source and destination accounts. The balance of both accounts will be updated.

### Exporting Data
1. Click on the download icon in the header.
2. Export your transactions in CSV or JSON format for your own analysis.

## Default configuration

The application automatically initializes the accounts:
- **Bank**: Checking account, Livret A savings account, LDDS savings account.
- **Daily**: Groceries, Rent, Subscriptions, etc.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments

- Built with [Flet](https://flet.dev/) - A framework for building interactive multi-platform applications in Python

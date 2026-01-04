# Peadra

A personal wealth management application built with Python and Flet.

>**🚧 Early phase of the project 🚧**\
The app is in French only *for the moment*.\
More features and UI/UX improvements to come

## Overview

Peadra (*"wealth" in Breton*) is a desktop application designed to help you track and manage your personal finances and assets.

It provides a comprehensive view of your patrimony across different asset categories (cash, real estate, stocks) and allows you to record and analyze your financial transactions.

## Features

### Dashboard
- Overview of total patrimony
- Asset distribution by category with visual charts
- Monthly income/expense summary
- Recent transactions list
- Quick access to all asset categories

### Transaction Management
- Record income, expenses, and transfers
- Categorize transactions with customizable categories and subcategories
- Search and filter transactions by type, category, or description
- Edit and delete existing transactions
- View transaction history with detailed information

### Asset Tracking
- Track assets across multiple categories (Cash, Real Estate, Stocks)
- Record purchase value and date for gain/loss calculations
- Update asset values over time with history tracking
- Filter assets by category
- View performance metrics and trends

### Analytics
- Patrimony distribution pie charts
- Patrimony evolution over time (line charts)
- Income vs. Expenses comparison (bar charts)
- Expense breakdown by category
- Customizable time period selection (3, 6, 12, 24 months)

### Additional Features
- Dark and light theme support
- Export data to JSON or CSV formats
- Glassmorphism-inspired modern UI design
- SQLite database for local data storage
- Responsive layout with navigation rail

## Installation

### Prerequisites
- Python 3.8 or higher
- pip (Python package manager)

### Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/Peadra.git
cd Peadra
```

2. Create a virtual environment (recommended):
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Run the application:
```bash
python main.py
```

## Project Structure

```
Peadra/
├── main.py                 # Application entry point
├── requirements.txt        # Python dependencies
├── LICENSE                 # MIT License
├── README.md              # This file
└── src/
    ├── __init__.py
    ├── components/        # Reusable UI components
    │   ├── __init__.py
    │   ├── modals.py      # Transaction and Asset modals
    │   ├── navigation.py  # Navigation rail component
    │   └── theme.py       # Theme configuration and styling
    ├── database/          # Database layer
    │   ├── __init__.py
    │   └── db_manager.py  # SQLite database manager
    └── views/             # Application views
        ├── __init__.py
        ├── dashboard.py   # Dashboard view
        ├── transactions.py # Transactions management view
        ├── analyses.py    # Analytics and charts view
        └── assets.py      # Assets management view
```

## Technologies

- **Python 3.8+** - Programming language
- **Flet 0.24.1** - Cross-platform UI framework based on Flutter
- **SQLite** - Local database for data persistence

## Usage

### Adding a Transaction
1. Navigate to the "Transactions" tab
2. Click "Nouvelle transaction" (New transaction)
3. Fill in the date, description, amount, type, and category
4. Click "Enregistrer" (Save)

### Adding an Asset
1. Navigate to the "Actifs" (Assets) tab
2. Click "Nouvel actif" (New asset)
3. Enter the asset name, category, current value, and optional purchase information
4. Click "Enregistrer" (Save)

### Viewing Analytics
1. Navigate to the "Analyses" tab
2. Select the desired time period from the dropdown
3. View patrimony distribution, evolution, and expense breakdowns

### Exporting Data
1. Click the download icon in the header
2. Choose between JSON or CSV export format
3. Files are saved to the "exports" folder

## Configuration

### Default Categories
The application comes with three default categories:
- **Cash** - Bank accounts, savings, cash
- **Immobilier** (Real Estate) - Properties, REITs
- **Bourse** (Stocks) - Stocks, ETFs, bonds, crypto

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

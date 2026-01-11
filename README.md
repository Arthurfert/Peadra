# Peadra

A personal wealth management application built with Python and Flet.

>**🚧 Early phase of the project 🚧**\
More features and UI/UX improvements to come

## Overview

Peadra (*"wealth" in Breton*) is a desktop application designed to help you track and manage your personal finances and assets.

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
- Python 3.8 ou supérieur
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
```

## Technologies

- **Python 3.8+** - Programming language
- **Flet 0.24.1** - Cross-platform UI framework based on Flutter
- **SQLite** - Local database for data persistence

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

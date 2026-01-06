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
- **Financial overview**: Instantly view your *Bank Balance* (Checking Account), your *Total Assets*, and your *Savings* (everything that is not in your checking account).
- **Flow vs. Stock Logic**: 
    - The income/expense graph focuses on your daily budget (excludes savings transfers so as not to skew the stats).
    - The “Savings” card represents accumulated stock (savings accounts, stock market, real estate, crypto).
- **Interactive graphs**: Monthly tracking of income and expenses.

### Transaction Management
- **Unified view**: A single list to manage all your transactions, whether daily expenses or investments.
- **Advanced filters**: Quickly filter by asset category (checking account, savings accounts, stocks, crypto, real estate) using dedicated dialog boxes.
- **Instant Search**: Find any transaction by description, amount, or category.
- **Visual Color Coding**: Each asset type has its own visual identity (pastel palette) for quick reading.

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

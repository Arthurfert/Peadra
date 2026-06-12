<div align="center">
  <img src="./assets/Peadra-logo.png" alt="Peadra's logo" style="height:200px;margin:0;">
</div>

## Screenshots

|                 Dashboard                 |                  Transactions                  |
| :---------------------------------------: | :--------------------------------------------: |
| ![Peadra dashboard](assets/Dashboard.jpg) | ![Peadra transaction](assets/transactions.jpg) |

|                  Accounts                 |                   Subscriptions                  |
| :---------------------------------------: | :----------------------------------------------: |
| ![Peadra Accounts](assets/Accounts.jpg)   | ![Peadra Subscription](assets/Subscriptions.jpg) |

## Overview

Peadra ("*wealth*" in Breton) is a secure, privacy-focused desktop application designed to streamline personal finance and asset management.

Built as a modern, local-first alternative to cumbersome spreadsheets, Peadra gives you complete control over your financial data without connecting to external banking systems.

## Features

**Portfolio & Asset Management**  
> **Comprehensive Overview:** Track your current balance, asset distribution, and financial evolution over time.  
> **Category Insights:** Organize transactions into categories with the ability to dynamically rename, merge, and restructure them.  
> **Subscription Tracking:** Monitor recurring transactions and active subscriptions at a glance.  

**Account & Transaction Management**  
> **Full Operations & Multi-Currency:** Easily add, modify, or delete transactions (expense, revenue, transfer), in any currency.  
> **Multi-Account Support:** Manage multiple distinct accounts with independent tracking.  
> **Multi-User Authentication:** Secure access control for different users on the same device.  

**Data Control & System**  
> **Local & Secure:** Powered by a local SQLite database. Your financial data never leaves your machine.  
> **Flexible Data Portability:** Seamlessly import data via CSV files, and export your history in both JSON and CSV formats.  
> **Seamless Maintenance:** Stay up to date effortlessly with built-in, in-app updates.  

**Supported languages:** English, French.

> ...and many more features [to come](TODO.md) !

## Install

Download the executable file (**Windows & Linux**) on the release section on your right !

> [!NOTE]
> The database will be automatically created next to the executable.

For developers or MacOS users, please refer to [the install tutorial](./INSTALLATION.md).  

## Technologies

- User Interface : **Flet** (*A powerful Python framework built on Flutter for native desktop experiences*)
- Core Backend : **Python** (*Version 3.10 or higher required for building*)
- Database : **SQLite** (*Lightweight, robust, and 100% local storage*)

## Project Structure

```
Peadra/
├── main.py                   # Application entry point
├── requirements.txt          # Python dependencies
├── LICENSE                   # GNU-GPL License
├── README.md                 # This file
└── src/
    ├── __init__.py
    ├── i18n.py               # Translation
    ├── logger.py             # Logging (help resolve issues)
    ├── update_manager.py     # App updater engine
    ├── version.py            # Store Peadra's current version
    ├── components/           # Reusable UI components
    │   ├── __init__.py
    │   ├── modals.py         # Transaction and Asset modals
    │   ├── navigation.py     # Navigation rail component
    │   └── theme.py          # Theme configuration and styling
    ├── database/             # Database layer
    │   ├── __init__.py
    │   └── db_manager.py     # SQLite database manager
    └── views/                # Application views
        ├── __init__.py
        ├── accounts.py       # Accounts view
        ├── categories.py     # Categories view
        ├── dashboard.py      # Dashboard view
        ├── import_data.py    # Import data view
        ├── login.py          # Login view (at startup)
        ├── parameters.py     # Parameters view
        ├── subscriptions.py  # Subscriptions & recurring transactions view
        └── transactions.py   # Transactions management view
```

> [!NOTE]
> To learn more about how Peadra works under the hood, please have a look to the [deep wiki documentation](https://deepwiki.com/Arthurfert/Peadra) !

## License

This project is licensed under the GNU-GPL License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Flet](https://flet.dev/) - A framework for building interactive multi-platform applications in Python

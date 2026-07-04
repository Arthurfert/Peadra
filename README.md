<div align="center">
  <img src="./assets/Peadra-logo.png" alt="Peadra's logo" style="height:200px;margin:0;">
</div>

## Screenshots

|                 Dashboard                 |                  Transactions                  |
| :---------------------------------------: | :--------------------------------------------: |
| ![Peadra dashboard](assets/Dashboard.png) | ![Peadra transaction](assets/Transactions.png) |

|                  Accounts                 |                 Subscriptions               |
| :---------------------------------------: | :-----------------------------------------: |
| ![Peadra Accounts](assets/Accounts.png)   | ![Peadra Categories](assets/Categories.png) |

## Overview

Peadra ("*wealth*" in Breton) is a secure, privacy-focused cross-platform application designed to streamline personal finance and asset management.

Built with **Flutter & Dart**, it runs natively on **Linux and Windows** - *Android, iOS and MacOS support will arrive*.  
Your financial data stays 100% local.  
Track your assets, manage transactions across multiple accounts and currencies, and keep full control of your finances.

## Features

**Portfolio & Asset Management**
- **Comprehensive Overview:** Track your current balance, asset distribution, and financial evolution over time.
- **Interactive Charts:** Bar charts, pie charts, and line charts for visual insights into spending patterns and trends.
- **Category Insights:** Organize transactions into categories with the ability to dynamically rename, merge, and restructure them.
- **Subscription Tracking:** Monitor recurring transactions and active subscriptions at a glance.

**Account & Transaction Management**
- **Full Operations & Multi-Currency:** Easily add, modify, or delete transactions (expense, income, transfer), in any of 36 supported currencies with automatic exchange rate conversion.
- **Multi-Account Support:** Manage multiple distinct accounts with independent tracking and color coding.
- **Multi-User Authentication:** Secure access control for different users on the same device, with SHA-256 password hashing.
- **Smart Autocomplete:** Transaction descriptions are auto-suggested from your history as you type.

**Data Control & System**
- **Local & Secure:** Powered by a local SQLite database. Your financial data never leaves your machine.
- **Flexible Data Portability:** Seamlessly import data via CSV files with automatic column detection and dialect parsing, and export your history in both JSON and CSV formats.
- **Responsive Design:** Adaptive layout that works beautifully on phones, tablets, and desktops.
- **Theming:** Four built-in themes - Light, Dark, Autumn, and Summer.

**Supported platforms:** Android, iOS, Linux, Windows, macOS. (UI is fully ready for desktop only but mobile is coming)  
**Supported languages:** English, French.

> ...and many more features [to come](TODO.md) !

## Install

To install the app, please download your designated installer in the `Release` section.

> [!NOTE]
> For **Windows users**, you will need to download and install the `peadra.cer` file (certificates for windows to trust Peadra).

For developper's setup instructions, see [INSTALLATION.md](./INSTALLATION.md).

## Technologies

- **UI Framework:** [Flutter](https://flutter.dev/) - Google's cross-platform UI toolkit for natively compiled apps
- **Language:** [Dart](https://dart.dev/) (version 3.5+)
- **Database:** [sqflite](https://pub.dev/packages/sqflite) - SQLite for Flutter

## Project Structure

```
Peadra/
├── pubspec.yaml                # Flutter/Dart dependencies
├── lib/
│   ├── main.dart               # App entry point
│   ├── database/
│   │   └── database_manager.dart  # SQLite database layer
│   ├── models/                 # Data models (User, Account, Transaction, etc.)
│   ├── services/               # Auth, currency, import, export, update
│   ├── providers/              # State management (Provider)
│   ├── views/                  # App screens (dashboard, transactions, etc.)
│   ├── components/             # Reusable widgets, modals, charts
│   ├── responsive/             # Layout breakpoints (phone/tablet/desktop)
│   ├── i18n/                   # Translations (EN/FR)
│   └── utils/                  # Constants, formatters
├── android/                    # Android platform files
├── ios/                        # iOS platform files
├── linux/                      # Linux platform files
├── windows/                    # Windows platform files
├── macos/                      # macOS platform files
└── assets/                     # Images, icons
```

## License

This project is licensed under the GNU-GPL License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Flutter](https://flutter.dev/) — Google's UI toolkit for building natively compiled applications

# Installation

## Prerequisites

- **Flutter SDK 3.5+** - [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Dart SDK** - Included with Flutter
- Platform-specific tools:

| Platform | Requirements |
| -------- | ------------ |
| Android  | Android Studio (or VS Code with Android extensions), Android SDK |
| iOS      | Xcode (macOS only), CocoaPods |
| Linux    | `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev` |
| Windows  | Visual Studio 2022+ with "Desktop Development in C++" workload |
| macOS    | Xcode, CocoaPods |

Verify your setup:
```bash
flutter doctor
```

## Setup

1. Clone the repository:
```bash
git clone https://github.com/Arthurfert/Peadra.git
cd Peadra
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run in development mode (auto-detects connected device/emulator):
```bash
flutter run
```

Or specify a platform explicitly:
```bash
flutter run -d linux
flutter run -d chrome
flutter run -d <device-id>   # for mobile
```

## Build

### Android
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

For app bundle (Play Store):
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```
Then archive and deploy via Xcode.

### Linux
```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

### Windows
```bash
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

### macOS
```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/
```

## Database

The SQLite database is created automatically on first launch:
- **Mobile:** App documents directory (managed by OS)
- **Desktop:** `~/.Peadra/peadra.db` (Linux/macOS) or `%USERPROFILE%\.Peadra\peadra.db` (Windows)

No manual setup or migrations required, tables are created via `CREATE TABLE IF NOT EXISTS`.

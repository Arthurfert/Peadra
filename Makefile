.PHONY: help run build-apk build-ios build-linux build-windows build-macos clean test

# Detect OS
ifeq ($(OS),Windows_NT)
    DETECTED_OS = windows
    DETECTED_OS_NAME = Windows
else
    DETECTED_OS = linux
    DETECTED_OS_NAME = Linux
endif

APP_NAME = Peadra

help:
	@echo "Peadra Makefile"
	@echo "=========================="
	@echo "Detected OS: $(DETECTED_OS_NAME)"
	@echo ""
	@echo "Available targets:"
	@echo "  make run             - Run the app in development mode"
	@echo "  make build-linux     - Build for Linux (release)"
	@echo "  make build-windows   - Build for Windows (release)"
	@echo "  make build-macos     - Build for macOS (release)"
	@echo "  make build-apk       - Build Android APK (release)"
	@echo "  make build-ios       - Build for iOS (release)"
	@echo "  make clean           - Remove build directories"
	@echo "  make test            - Run tests"
	@echo "  make doctor          - Check Flutter environment"
	@echo "  make help            - Show this help message"

run:
	@echo "Running $(APP_NAME) in development mode..."
	flutter run

build-linux:
	@echo "Building $(APP_NAME) for Linux..."
	flutter build linux --release

build-windows:
	@echo "Building $(APP_NAME) for Windows..."
	flutter build windows --release

build-macos:
	@echo "Building $(APP_NAME) for macOS..."
	flutter build macos --release

build-apk:
	@echo "Building $(APP_NAME) Android APK..."
	flutter build apk --release

build-ios:
	@echo "Building $(APP_NAME) for iOS..."
	flutter build ios --release

clean:
	@echo "Cleaning build artifacts..."
	flutter clean
	@echo "Cleanup complete"

test:
	@echo "Running tests..."
	flutter test

doctor:
	@echo "Checking Flutter environment..."
	flutter doctor

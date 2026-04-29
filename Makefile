.PHONY: help pack clean run test install

# Detect OS
ifeq ($(OS),Windows_NT)
    DETECTED_OS = windows
    DETECTED_OS_NAME = Windows
else
    DETECTED_OS = linux
    DETECTED_OS_NAME = Linux
endif

# Variables
APP_NAME = Peadra
ICON_WINDOWS = assets/icon.ico
ICON_LINUX = assets/icon.png
ICON_PATH = $(if $(filter windows,$(DETECTED_OS)),$(ICON_WINDOWS),$(ICON_LINUX))
MAIN_FILE = main.py
ASSETS_DIR = assets

help:
	@echo "Peadra Packaging Makefile"
	@echo "=========================="
	@echo "Detected OS: $(DETECTED_OS_NAME)"
	@echo ""
	@echo "Available targets:"
	@echo "  make pack        - Package the app (auto-detects OS and icon)"
	@echo "  make pack-windows - Force Windows packaging with .ico icon"
	@echo "  make pack-linux   - Force Linux packaging with .png icon"
	@echo "  make run         - Run the app in development mode"
	@echo "  make clean       - Remove build and dist directories"
	@echo "  make test        - Run tests"
	@echo "  make install     - Install dependencies"
	@echo "  make install-dev - Install development dependencies"
	@echo "  make help        - Show this help message"

pack:
	@echo "Packaging $(APP_NAME) for $(DETECTED_OS_NAME) with icon $(ICON_PATH)..."
	flet pack -i $(ICON_PATH) -n $(APP_NAME) $(MAIN_FILE) \
		--add-data "$(ASSETS_DIR):$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard_Light.jpg:$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard.jpg:$(ASSETS_DIR)"
	@echo "Packaging complete for $(DETECTED_OS_NAME)"

pack-windows:
	@echo "Packaging $(APP_NAME) for Windows with icon $(ICON_WINDOWS)..."
	flet pack -i $(ICON_WINDOWS) -n $(APP_NAME) $(MAIN_FILE) \
		--add-data "$(ASSETS_DIR):$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard_Light.jpg:$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard.jpg:$(ASSETS_DIR)"
	@echo "Windows packaging complete"

pack-linux:
	@echo "Packaging $(APP_NAME) for Linux with icon $(ICON_LINUX)..."
	flet pack -i $(ICON_LINUX) -n $(APP_NAME) $(MAIN_FILE) \
		--add-data "$(ASSETS_DIR):$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard_Light.jpg:$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard.jpg:$(ASSETS_DIR)"
	@echo "Linux packaging complete"

run:
	@echo "Running $(APP_NAME) in development mode..."
	python $(MAIN_FILE)

clean:
	@echo "Cleaning build artifacts..."
	@if exist build rmdir /s /q build
	@if exist dist rmdir /s /q dist
	@if exist __pycache__ rmdir /s /q __pycache__
	@if exist .pytest_cache rmdir /s /q .pytest_cache
	@if exist *.spec del *.spec
	@echo "Cleanup complete"

test:
	@echo "Running tests..."
	pytest tests/ -v

install:
	@echo "Installing dependencies..."
	pip install -r requirements.txt
	@echo "Dependencies installed"

install-dev:
	@echo "Installing development dependencies..."
	pip install -r requirements-dev.txt
	@echo "Development dependencies installed"
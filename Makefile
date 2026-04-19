.PHONY: help pack clean run test install

# Variables
APP_NAME = Peadra
ICON_PATH = assets/icon.ico
MAIN_FILE = main.py
ASSETS_DIR = assets

help:
	@echo "Peadra Packaging Makefile"
	@echo "=========================="
	@echo ""
	@echo "Available targets:"
	@echo "  make pack        - Package the app into standalone executable"
	@echo "  make run         - Run the app in development mode"
	@echo "  make clean       - Remove build and dist directories"
	@echo "  make test        - Run tests"
	@echo "  make install     - Install dependencies"
	@echo "  make install-dev - Install development dependencies"
	@echo "  make help        - Show this help message"

pack:
	@echo "Packaging $(APP_NAME) application..."
	flet pack -i $(ICON_PATH) -n $(APP_NAME) $(MAIN_FILE) \
		--add-data "$(ASSETS_DIR):$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard_Light.jpg:$(ASSETS_DIR)" \
		--add-data "$(ASSETS_DIR)/Dashboard.jpg:$(ASSETS_DIR)"
	@echo "Packaging complete"

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
.PHONY: help install install-deps test test-verbose test-custom clean report open

help:
	@echo "URL Filtering Test Harness — available targets:"
	@echo ""
	@echo "  install             Install all dependencies and make scripts executable"
	@echo "  install-deps        Install runtime dependencies only (curl, jq)"
	@echo ""
	@echo "  test                Run URL filtering tests (cross-platform)"
	@echo "  test-verbose        Run tests with verbose output"
	@echo "  test-custom         Run with custom config: make test-custom CONFIG=urls.json TIMEOUT=15"
	@echo ""
	@echo "  report              Open the latest test report in browser"
	@echo "  clean               Remove test outputs (logs, reports)"
	@echo ""
	@echo "  help                Show this help message"
	@echo ""

# ── Dependency detection ─────────────────────────────────────────────────────

UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)
	OS := macos
else ifeq ($(UNAME),Linux)
	OS := linux
else ifeq ($(OS),Windows_NT)
	OS := windows
else
	OS := unknown
endif

# ── Installation ─────────────────────────────────────────────────────────────

install: install-deps
	@echo "Making scripts executable..."
ifeq ($(OS),windows)
	@echo "Windows detected — PowerShell scripts are ready to use"
	@powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" || true
else
	@chmod +x test-url-filtering.sh
	@echo "✓ test-url-filtering.sh is now executable"
endif
	@echo ""
	@echo "Installation complete! Run 'make test' to get started."

install-deps:
	@echo "Checking dependencies..."
ifeq ($(OS),windows)
	@powershell -Command "if (-not (Get-Command curl -ErrorAction SilentlyContinue)) { Write-Host 'Warning: curl not found. Windows 10+ has curl built-in.'; Exit 1 }" || true
	@echo "✓ Windows detected — curl is built-in"
else ifeq ($(OS),macos)
	@echo "Installing dependencies via Homebrew..."
	@command -v brew >/dev/null 2>&1 || { echo "Error: Homebrew not found. Install from https://brew.sh"; exit 1; }
	@brew install -q curl jq 2>/dev/null || (brew upgrade -q curl jq 2>/dev/null || true)
	@echo "✓ curl and jq are installed"
else ifeq ($(OS),linux)
	@echo "Installing dependencies via package manager..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update -qq && sudo apt-get install -y -qq curl jq > /dev/null 2>&1; \
	elif command -v yum >/dev/null 2>&1; then \
		sudo yum install -y -q curl jq > /dev/null 2>&1; \
	elif command -v pacman >/dev/null 2>&1; then \
		sudo pacman -S --noconfirm curl jq > /dev/null 2>&1; \
	else \
		echo "Warning: Could not detect package manager (apt, yum, pacman)"; \
		echo "Please install 'curl' and 'jq' manually"; \
		exit 1; \
	fi
	@echo "✓ curl and jq are installed"
else
	@echo "Warning: Unknown OS type. Please install curl and jq manually."
	@exit 1
endif

# ── Testing ──────────────────────────────────────────────────────────────────

# Determine which script to run
ifeq ($(OS),windows)
	TEST_SCRIPT := Test-URLFiltering.ps1
	TEST_CMD := powershell -NoProfile -ExecutionPolicy Bypass -File $(TEST_SCRIPT)
else
	TEST_SCRIPT := test-url-filtering.sh
	TEST_CMD := ./$(TEST_SCRIPT)
endif

CONFIG ?= urls.json
TIMEOUT ?= 10

test: install-deps
	@echo "Running URL filtering tests..."
	@echo ""
ifeq ($(OS),windows)
	@$(TEST_CMD)
else
	@$(TEST_CMD) --config $(CONFIG) --timeout $(TIMEOUT)
endif

test-verbose: install-deps
	@echo "Running tests with verbose output..."
	@echo ""
ifeq ($(OS),windows)
	@$(TEST_CMD) -Verbose
else
	@$(TEST_CMD) --config $(CONFIG) --timeout $(TIMEOUT) --verbose
endif

test-custom: install-deps
	@echo "Running tests with custom parameters..."
	@echo "  Config: $(CONFIG)"
	@echo "  Timeout: $(TIMEOUT) seconds"
	@echo ""
ifeq ($(OS),windows)
	@$(TEST_CMD) -ConfigPath $(CONFIG) -TimeoutSeconds $(TIMEOUT)
else
	@$(TEST_CMD) --config $(CONFIG) --timeout $(TIMEOUT)
endif

# ── Output management ────────────────────────────────────────────────────────

REPORT_FILE := filter-report.html
LOG_FILE := test-results.log

report:
	@if [ -f "$(REPORT_FILE)" ]; then \
		echo "Opening test report..."; \
		if command -v xdg-open >/dev/null 2>&1; then \
			xdg-open "$(REPORT_FILE)"; \
		elif command -v open >/dev/null 2>&1; then \
			open "$(REPORT_FILE)"; \
		else \
			powershell -Command "Start-Process '$(REPORT_FILE)'"; \
		fi; \
	else \
		echo "Error: Report file not found. Run 'make test' first."; \
		exit 1; \
	fi

clean:
	@echo "Cleaning test outputs..."
	@rm -f $(REPORT_FILE) $(LOG_FILE)
	@echo "✓ Cleaned: $(REPORT_FILE) $(LOG_FILE)"

# ── Utility ──────────────────────────────────────────────────────────────────

.DEFAULT_GOAL := help

.PHONY: $(MAKECMDGOALS)

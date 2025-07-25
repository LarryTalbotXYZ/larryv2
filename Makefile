# Larry Talbot Makefile
# Simplified commands for building, testing, and deploying

# Default target
.PHONY: help
help:
	@echo "Larry Talbot - Sui Blockchain Protocol"
	@echo ""
	@echo "Available commands:"
	@echo "  build     - Build the Move package"
	@echo "  test      - Run all tests"
	@echo "  deploy    - Deploy to testnet"
	@echo "  clean     - Clean build artifacts"
	@echo "  docs      - Generate documentation"
	@echo "  check     - Check code formatting"
	@echo "  help      - Show this help message"

# Build the package
.PHONY: build
build:
	@echo "Building Larry Talbot package..."
	sui move build

# Run tests
.PHONY: test
test:
	@echo "Running tests..."
	sui move test

# Run tests with coverage
.PHONY: test-coverage
test-coverage:
	@echo "Running tests with coverage..."
	sui move test --coverage

# Deploy to testnet
.PHONY: deploy
deploy:
	@echo "Deploying to testnet..."
	./scripts/deploy.sh

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf build
	rm -f publish_output.json
	rm -f deployment_info.json

# Check code formatting
.PHONY: check
check:
	@echo "Checking code formatting..."
	sui move check

# Generate documentation
.PHONY: docs
docs:
	@echo "Generating documentation..."
	@echo "Documentation is available in the docs/ directory"

# Install dependencies (if needed)
.PHONY: install
install:
	@echo "Installing dependencies..."
	@echo "Ensure you have Sui CLI tools installed"

# Verify installation
.PHONY: verify
verify:
	@echo "Verifying installation..."
	@sui --version
	@echo "Sui CLI is installed and working"

# Run security checks (placeholder)
.PHONY: security
security:
	@echo "Running security checks..."
	@echo "Manual security review recommended"

# List all objects (after deployment)
.PHONY: list-objects
list-objects:
	@echo "Listing protocol objects..."
	@test -f deployment_info.json && cat deployment_info.json || echo "Deployment info not found. Please deploy first."

# Show package info
.PHONY: info
info:
	@echo "Larry Talbot Protocol Information"
	@echo "================================"
	@echo "Package: larry_talbot"
	@echo "Version: 1.0.0"
	@echo "Network: Sui Blockchain"
	@echo "Token: LARRY (9 decimals)"
	@echo "Max Supply: 1,000,000,000"

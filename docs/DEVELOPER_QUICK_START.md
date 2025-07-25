# Larry Talbot Developer Quick Start

Get up and running with the Larry Talbot protocol on Sui blockchain quickly.

## Prerequisites

### Install Sui Tools
```bash
# Install Sui CLI (follow official documentation)
# https://docs.sui.io/devnet/build/install

# Verify installation
sui --version
```

### Setup Wallet
1. Install Sui Wallet browser extension
2. Create or import wallet
3. Get SUI tokens from faucet (testnet)

## Project Structure

```
larry_talbot/
├── Move.toml              # Package configuration
├── sources/               # Move source files
│   ├── larry_token.move   # LARRY token implementation
│   ├── admin.move         # Admin controls
│   ├── events.move        # Event system
│   ├── math.move          # Mathematical operations
│   ├── trading.move       # Buy/sell functionality
│   ├── lending.move       # Lending protocol
│   ├── liquidation.move   # Liquidation system
│   └── larry.move         # Main protocol
├── tests/                 # Test files
│   └── larry_test.move    # Unit tests
├── scripts/               # Deployment scripts
│   └── deploy.sh          # Deployment script
├── docs/                  # Documentation
├── README.md              # Project overview
└── Makefile              # Build commands
```

## Quick Start Commands

### Build the Project
```bash
# Using make
make build

# Or directly
sui move build
```

### Run Tests
```bash
# Run all tests
make test

# Run with coverage
make test-coverage

# Or directly
sui move test
```

### Deploy to Testnet
```bash
# Using make
make deploy

# Or directly
./scripts/deploy.sh
```

### Clean Build Artifacts
```bash
make clean
```

## Development Workflow

### 1. Clone and Setup
```bash
# Clone the repository
git clone <repository-url>
cd larry-on-sui

# Build the project
make build
```

### 2. Run Tests
```bash
# Ensure everything works
make test
```

### 3. Modify Code
- Edit files in `sources/` directory
- Follow existing patterns and conventions
- Add tests for new functionality

### 4. Test Changes
```bash
# Run specific tests
sui move test <test_name>

# Run all tests
make test
```

### 5. Deploy
```bash
# Deploy to testnet
make deploy
```

## Key Modules Overview

### larry_token.move
- Native SUI coin implementation
- Minting and burning capabilities
- Maximum supply enforcement

### admin.move
- Protocol configuration
- Fee management
- Access control

### trading.move
- Buy/sell functionality
- Vault management
- Fee collection

### lending.move
- Loan creation and management
- Collateral handling
- Leverage trading

## Common Development Tasks

### Adding a New Feature
1. Identify the appropriate module
2. Add new functions following existing patterns
3. Create corresponding tests
4. Update documentation
5. Test thoroughly

### Modifying Protocol Parameters
1. Update constants in relevant modules
2. Adjust validation logic if needed
3. Update tests
4. Update documentation

### Adding New Events
1. Define event struct in `events.move`
2. Add emission function in `events.move`
3. Call from appropriate modules
4. Document new events

## Testing

### Unit Tests
Located in `tests/larry_test.move`:
```bash
# Run specific test
sui move test test_protocol_initialization

# Run all tests
sui move test
```

### Test Structure
```move
#[test]
fun test_function_name() {
    // Setup test scenario
    let scenario = Scenario::new();
    
    // Execute function under test
    // ...
    
    // Verify results
    assert!(condition, error_code);
}
```

## Deployment

### Testnet Deployment
```bash
# Ensure you're on testnet
sui client switch --env testnet

# Check your address
sui client active-address

# Deploy
make deploy
```

### Mainnet Deployment
```bash
# Switch to mainnet
sui client switch --env mainnet

# Update deploy script network setting
# Then deploy
make deploy
```

## Best Practices

### Code Organization
1. Keep functions focused and small
2. Use descriptive names
3. Follow module separation principles
4. Add comments for complex logic

### Security
1. Always validate inputs
2. Use capability-based access control
3. Test edge cases
4. Review for common vulnerabilities

### Performance
1. Minimize object mutations
2. Use efficient data structures
3. Avoid unnecessary computations
4. Leverage Sui's parallelization

## Troubleshooting

### Common Issues

1. **Build Errors**
   ```bash
   # Clean and rebuild
   make clean
   make build
   ```

2. **Test Failures**
   ```bash
   # Run specific test with verbose output
   sui move test <test_name> --verbose
   ```

3. **Deployment Issues**
   ```bash
   # Check gas balance
   sui client gas
   
   # Verify network
   sui client active-env
   ```

### Getting Help
1. Check error messages carefully
2. Review documentation
3. Run tests to isolate issues
4. Consult Sui documentation for Move-specific issues

## Next Steps

1. **Explore the codebase** - Review each module
2. **Run the tests** - Understand current functionality
3. **Deploy to testnet** - Test in a live environment
4. **Extend the protocol** - Add new features
5. **Contribute** - Submit improvements

## Resources

- [Sui Documentation](https://docs.sui.io)
- [Move Language](https://move-language.github.io/move/)
- [Sui Framework](https://github.com/MystenLabs/sui/tree/main/crates/sui-framework)
- [Sui Discord](https://discord.gg/sui)

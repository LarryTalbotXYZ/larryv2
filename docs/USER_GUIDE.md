# Larry Talbot User Guide

This guide explains how to interact with the Larry Talbot protocol on the Sui blockchain.

## Table of Contents
1. [Getting Started](#getting-started)
2. [Token Information](#token-information)
3. [Trading Operations](#trading-operations)
4. [Lending Operations](#lending-operations)
5. [Admin Functions](#admin-functions)
6. [Protocol Parameters](#protocol-parameters)

## Getting Started

### Prerequisites
- Sui Wallet (Sui Wallet extension or compatible wallet)
- SUI tokens for gas fees
- Understanding of DeFi concepts

### Contract Addresses
After deployment, you'll need these object addresses:
- Protocol Object: Main protocol state
- Protocol Caps Object: Administrative capabilities
- LARRY Token: Native Sui coin object

## Token Information

### LARRY Token Details
- Name: LARRY TALBOT
- Symbol: LARRY
- Decimals: 9 (same as SUI)
- Max Supply: 1,000,000,000 LARRY
- Type: Native Sui coin

### Token Features
- Burnable: Yes
- Mintable: Yes (admin only)
- Transferable: Yes

## Trading Operations

### Buying LARRY Tokens
To buy LARRY tokens with SUI:

1. Ensure the protocol is started
2. Prepare SUI coins for the transaction
3. Call the `trading::buy` function with:
   - Vault object
   - Config object
   - LARRY mint capability
   - LARRY treasury capability
   - Fee address
   - SUI coins to spend
   - Transaction context

### Selling LARRY Tokens
To sell LARRY tokens for SUI:

1. Ensure the protocol is started
2. Prepare LARRY coins for the transaction
3. Call the `trading::sell` function with:
   - Vault object
   - Config object
   - LARRY burn capability
   - LARRY treasury capability
   - Fee address
   - LARRY coins to sell
   - Transaction context

### Price Calculation
The price of LARRY is determined by the formula:
`Price = (SUI Balance) / (LARRY Supply)`

Fees are applied to trades:
- Buy Fee: 0.1% (configurable)
- Sell Fee: 0.1% (configurable)
- Team Fee: 0.05% (5% of trade value)

## Lending Operations

### Leverage Trading
To use leverage trading:

1. Ensure the protocol is started
2. Prepare SUI coins for the transaction
3. Call the `lending::leverage` function with:
   - Vault object
   - Config object
   - Loan statistics object
   - LARRY mint capability
   - LARRY treasury capability
   - Fee address
   - SUI coins to use
   - Number of days (1-365)
   - Clock object
   - Transaction context

### Borrowing SUI
To borrow SUI with LARRY collateral:

1. Ensure the protocol is started
2. Prepare LARRY coins as collateral
3. Call the `lending::borrow` function with:
   - Vault object
   - Config object
   - Loan statistics object
   - Fee address
   - LARRY coins for collateral
   - Amount of SUI to borrow
   - Number of days (1-365)
   - Clock object
   - Transaction context

### Closing Positions
To close a loan position:

1. Repay the borrowed SUI amount
2. Call the `lending::close_position` function with:
   - Vault object
   - Loan statistics object
   - LARRY burn capability
   - SUI coins for repayment
   - Clock object
   - Transaction context

### Loan Information
Loans are stored as dynamic fields on user accounts, with:
- Collateral amount (LARRY)
- Borrowed amount (SUI)
- End date (timestamp)
- Duration (days)

## Admin Functions

### Protocol Initialization
Only the deployer can initialize the protocol:

1. Set the fee address
2. Call `larry::team_start` with exactly 0.001 SUI
3. This mints 1000 LARRY tokens and burns 1% (10 LARRY)

### Fee Management
Admin can adjust fees:
- Buy Fee: 0.04% to 0.25%
- Sell Fee: 0.04% to 0.25%
- Leverage Fee: 0% to 2.5%

### Protocol Control
Admin can:
- Start/stop the protocol
- Transfer admin capability
- Update fee address

## Protocol Parameters

### Fee Structure
| Fee Type | Default | Range | Description |
|----------|---------|-------|-------------|
| Buy Fee | 0.1% | 0.04% - 0.25% | Applied to LARRY purchases |
| Sell Fee | 0.1% | 0.04% - 0.25% | Applied to LARRY sales |
| Leverage Fee | 1% | 0% - 2.5% | Applied to leverage trades |
| Team Fee | 0.05% | Fixed | 5% of trade value to team |

### Lending Parameters
| Parameter | Value | Description |
|-----------|-------|-------------|
| Collateralization | 101% | Minimum collateral ratio |
| Max Duration | 365 days | Maximum loan duration |
| Interest Rate | 3.9% + 0.1% | Annual rate plus base fee |

### Liquidation Parameters
| Parameter | Value | Description |
|-----------|-------|-------------|
| Liquidation Schedule | Daily | Loans processed daily |
| Liquidation Time | Midnight | Processing at UTC midnight |
| Collateral Handling | Burn | Collateral burned on liquidation |

## Security Features

### Access Control
- Capability-based security model
- Admin functions protected by AdminCap
- Token operations protected by mint/burn caps

### Transaction Safety
- Atomic transaction blocks prevent partial updates
- Comprehensive input validation
- Safe math operations through Sui's math library

### Liquidation Protection
- Daily liquidation processing
- Accurate time tracking with Clock object
- Automatic cleanup of expired loans

## Best Practices

### For Traders
1. Always check current fees before trading
2. Monitor price movements for optimal entry/exit
3. Keep sufficient SUI for gas fees
4. Understand fee structure impact on returns

### For Lenders
1. Maintain adequate collateralization ratios
2. Monitor loan expiration dates
3. Understand interest rate calculations
4. Plan for position closure before expiration

### For Admins
1. Regularly monitor protocol health
2. Adjust fees based on market conditions
3. Ensure fee address is secure
4. Maintain adequate gas for admin operations

## Troubleshooting

### Common Issues
1. **Insufficient Gas**: Ensure adequate SUI balance
2. **Protocol Not Started**: Call team_start first
3. **Invalid Fee Address**: Set fee address before starting
4. **Loan Expired**: Close or extend before expiration

### Error Codes
| Code | Meaning | Solution |
|------|---------|----------|
| 0 | Protocol not started | Call team_start |
| 1 | Invalid loan duration | Use 1-365 days |
| 2 | Insufficient fee amount | Check minimum requirements |
| 3 | Insufficient collateral | Provide more LARRY collateral |

## Support

For issues with the Larry Talbot protocol:
1. Check transaction logs for error details
2. Verify all parameters are within valid ranges
3. Ensure sufficient gas for transactions
4. Contact the development team for persistent issues

## Audits and Security

This protocol has been designed with security best practices:
- Comprehensive input validation
- Capability-based access control
- Atomic transaction operations
- Safe mathematical operations
- Regular security reviews recommended

Always verify contract addresses and object IDs before interacting with the protocol.

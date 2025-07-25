#!/bin/bash

# Larry Talbot Deployment Script for Sui Blockchain

echo "=== Larry Talbot Deployment Script ==="
echo "Starting deployment process..."

# Check if Sui CLI is installed
if ! command -v sui &> /dev/null
then
    echo "Error: Sui CLI is not installed. Please install it first."
    exit 1
fi

# Check current network
NETWORK="testnet"  # Change to "mainnet" for mainnet deployment
echo "Deploying to $NETWORK"

# Build the package
echo "Building Move package..."
sui move build
if [ $? -ne 0 ]; then
    echo "Error: Build failed"
    exit 1
fi

# Run tests
echo "Running tests..."
sui move test
if [ $? -ne 0 ]; then
    echo "Error: Tests failed"
    exit 1
fi

# Get active address
ACTIVE_ADDRESS=$(sui client active-address)
echo "Active address: $ACTIVE_ADDRESS"

# Check balance
echo "Checking balance..."
sui client gas --json | jq '.[] | select(.balance > 1000000000) | .balance' > /dev/null
if [ $? -ne 0 ]; then
    echo "Warning: Low gas balance. Please ensure you have sufficient SUI tokens."
fi

# Publish the package
echo "Publishing package..."
sui client publish --gas-budget 2000000000 --json > publish_output.json

if [ $? -ne 0 ]; then
    echo "Error: Publish failed"
    cat publish_output.json
    exit 1
fi

# Extract package ID
PACKAGE_ID=$(jq -r '.objectChanges[] | select(.type == "published") | .packageId' publish_output.json)
echo "Package published successfully!"
echo "Package ID: $PACKAGE_ID"

# Extract important object IDs
echo "Extracting object IDs..."
PROTOCOL_OBJECT=$(jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Protocol"))) | .objectId' publish_output.json)
PROTOCOL_CAPS_OBJECT=$(jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("ProtocolCaps"))) | .objectId' publish_output.json)

echo "Protocol Object: $PROTOCOL_OBJECT"
echo "Protocol Caps Object: $PROTOCOL_CAPS_OBJECT"

# Save deployment info
echo "Saving deployment information..."
cat > deployment_info.json << EOF
{
  "package_id": "$PACKAGE_ID",
  "protocol_object": "$PROTOCOL_OBJECT",
  "protocol_caps_object": "$PROTOCOL_CAPS_OBJECT",
  "network": "$NETWORK",
  "deployed_by": "$ACTIVE_ADDRESS",
  "deployment_time": "$(date -u)"
}
EOF

echo "Deployment completed successfully!"
echo "Package ID: $PACKAGE_ID"
echo "Deployment info saved to deployment_info.json"

# Cleanup
rm publish_output.json

echo ""
echo "Next steps:"
echo "1. Fund the vault with initial SUI liquidity"
echo "2. Set the fee address using the admin capability"
echo "3. Call team_start to initialize the protocol"
echo "4. Begin trading and lending operations"

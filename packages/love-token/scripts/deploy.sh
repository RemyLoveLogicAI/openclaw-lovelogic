#!/usr/bin/env bash
set -euo pipefail

# Deploy LOVE token to Base (or any EVM chain)
# Requires: forge (Foundry) installed
# Usage: ./scripts/deploy.sh --network base

NETWORK="${2:-base}"

echo "Deploying LOVE token to $NETWORK..."
echo ""

# Wallet addresses for initial allocations — UPDATE THESE before deploying
TEAM_WALLET="${TEAM_WALLET:-0x0000000000000000000000000000000000000001}"
TREASURY_WALLET="${TREASURY_WALLET:-0x0000000000000000000000000000000000000002}"
LIQUIDITY_WALLET="${LIQUIDITY_WALLET:-0x0000000000000000000000000000000000000003}"
COMMUNITY_WALLET="${COMMUNITY_WALLET:-0x0000000000000000000000000000000000000004}"
PARTNERSHIP_WALLET="${PARTNERSHIP_WALLET:-0x0000000000000000000000000000000000000005}"

forge script contracts/LOVE.sol:LOVE \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  --constructor-args \
    "$TEAM_WALLET" \
    "$TREASURY_WALLET" \
    "$LIQUIDITY_WALLET" \
    "$COMMUNITY_WALLET" \
    "$PARTNERSHIP_WALLET" \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY"

echo ""
echo "LOVE token deployed!"
echo "Verify on Basescan: https://basescan.org/address/<CONTRACT_ADDRESS>"

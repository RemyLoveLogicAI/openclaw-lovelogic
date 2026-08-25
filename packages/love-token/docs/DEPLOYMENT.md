# $LOVE Token — Mainnet Deployment Guide

## Prerequisites

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```bash
cd packages/love-token
forge install OpenZeppelin/openzeppelin-contracts --no-git
forge install foundry-rs/forge-std --no-git
```

3. Prepare 6 wallet addresses:
   - **Deployer** (needs ETH on Base for gas)
   - **Team wallet** (receives 150M LOVE)
   - **Treasury wallet** (receives 200M LOVE, veLOVE-governed)
   - **Liquidity wallet** (receives 100M LOVE for DEX LP)
   - **Community wallet** (receives 100M LOVE for airdrops)
   - **Partnership wallet** (receives 50M LOVE)

4. Get Base RPC URL:
   - Public: `https://mainnet.base.org`
   - Or use Alchemy/Infura Base endpoint for reliability

5. Get Basescan API key for verification:
   - https://basescan.org/myapikey

## Deployment Steps

### Step 1: Deploy LOVE Token

```bash
export RPC_URL="https://mainnet.base.org"
export PRIVATE_KEY="0xYOUR_DEPLOYER_PRIVATE_KEY"
export TEAM="0xTEAM_WALLET"
export TREASURY="0xTREASURY_WALLET"
export LIQUIDITY="0xLIQUIDITY_WALLET"
export COMMUNITY="0xCOMMUNITY_WALLET"
export PARTNERSHIP="0xPARTNERSHIP_WALLET"
export ETHERSCAN_KEY="YOUR_BASESCAN_API_KEY"

forge create contracts/LOVE.sol:LOVE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $TEAM $TREASURY $LIQUIDITY $COMMUNITY $PARTNERSHIP \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

**Record the LOVE contract address.**

### Step 2: Deploy AgentRegistry

```bash
export LOVE_ADDR="0xLOVE_CONTRACT_ADDRESS_FROM_STEP_1"

forge create contracts/AgentRegistry.sol:AgentRegistry \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $LOVE_ADDR \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

**Record the AgentRegistry address.**

### Step 3: Deploy PnLOracle

```bash
export REGISTRY_ADDR="0xREGISTRY_ADDRESS_FROM_STEP_2"
export ORCHESTRATOR="0xSAK_ORCHESTRATOR_WALLET"

forge create contracts/PnLOracle.sol:PnLOracle \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $LOVE_ADDR $REGISTRY_ADDR $ORCHESTRATOR \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

**Record the PnLOracle address.**

### Step 4: Deploy veLOVE

```bash
forge create contracts/veLOVE.sol:veLOVE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $LOVE_ADDR \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

**Record the veLOVE address.**

### Step 5: Wire Contracts Together

```bash
export ORACLE_ADDR="0xORACLE_ADDRESS_FROM_STEP_3"
export VELOVE_ADDR="0xVELOVE_ADDRESS_FROM_STEP_4"

cast send $LOVE_ADDR "setAgentRegistry(address)" $REGISTRY_ADDR \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

cast send $LOVE_ADDR "setPnLOracle(address)" $ORACLE_ADDR \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

cast send $LOVE_ADDR "setVeLOVE(address)" $VELOVE_ADDR \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Step 6: Verify on Basescan

```bash
# All contracts should auto-verify with --verify flag
# If not, manually verify:
forge verify-contract $LOVE_ADDR contracts/LOVE.sol:LOVE \
  --chain base --etherscan-api-key $ETHERSCAN_KEY \
  --constructor-args $TEAM $TREASURY $LIQUIDITY $COMMUNITY $PARTNERSHIP

forge verify-contract $REGISTRY_ADDR contracts/AgentRegistry.sol:AgentRegistry \
  --chain base --etherscan-api-key $ETHERSCAN_KEY \
  --constructor-args $LOVE_ADDR

forge verify-contract $ORACLE_ADDR contracts/PnLOracle.sol:PnLOracle \
  --chain base --etherscan-api-key $ETHERSCAN_KEY \
  --constructor-args $LOVE_ADDR $REGISTRY_ADDR $ORCHESTRATOR

forge verify-contract $VELOVE_ADDR contracts/veLOVE.sol:veLOVE \
  --chain base --etherscan-api-key $ETHERSCAN_KEY \
  --constructor-args $LOVE_ADDR
```

## Post-Deployment

### Register First Agent
```bash
cast send $REGISTRY_ADDR "registerAgent(address,bytes32)" \
  0xAGENT_WALLET \
  $(cast keccak "sak:agent:001") \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Verify Token on Basescan
1. Go to https://basescan.org/address/$LOVE_ADDR
2. Click "Contract" → "Verify and Publish"
3. Source type: Solidity (Single file)
4. Compiler: 0.8.24
5. Optimization: Yes (200 runs)

### Add to MetaMask
- Token address: $LOVE_ADDR
- Symbol: LOVE
- Decimals: 18
- Network: Base

## Contract Addresses (fill after deployment)

| Contract | Address |
|----------|---------|
| LOVE | 0x... |
| AgentRegistry | 0x... |
| PnLOracle | 0x... |
| veLOVE | 0x... |

## Security Checklist Before Deploying

- [ ] All 3 high-severity audit findings fixed (timelock, slashBps cap, treasury address)
- [ ] External audit completed
- [ ] Deployer wallet has sufficient ETH on Base (~0.05 ETH for all 4 deploys + wiring)
- [ ] All 5 allocation wallets are fresh, dedicated addresses
- [ ] Orchestrator wallet is separate from deployer
- [ ] Private keys are in a hardware wallet, not a hot wallet
- [ ] Tested deployment on Base Sepolia first

**DO NOT deploy to mainnet without fixing the 3 high-severity findings first.**

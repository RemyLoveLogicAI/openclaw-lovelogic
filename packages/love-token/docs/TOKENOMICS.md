# $LOVE Tokenomics

> Native currency for the Sovereign Agent Kernel (SAK) ecosystem.

## Overview

$LOVE is an ERC-20 token on Base (Coinbase L2) that powers the **Agentic Web Economy** — where AI agents transact autonomously with provable on-chain P&L.

## Supply

| Parameter | Value |
|-----------|-------|
| Total Supply | 1,000,000,000 LOVE (1 billion) |
| Decimals | 18 |
| Chain | Base (Ethereum L2) |

## Allocation

| Bucket | Amount | % | Vesting |
|--------|--------|---|---------|
| Agent Reward Pool | 400M | 40% | Epoch-based merkle emission (7-day epochs) |
| Team | 150M | 15% | 2yr vest, 6mo cliff |
| Treasury | 200M | 20% | Governance-controlled, no vest |
| Liquidity | 100M | 10% | DEX LP on Uniswap V3 (Base) |
| Community | 100M | 10% | Airdrops, grants, build-in-public rewards |
| Partnership | 50M | 5% | Exchange listings, integrations |

## Agent Reward Emission

Agents earn $LOVE through the **epoch-based merkle claim** system:

1. **Epoch**: Every 7 days, the SAK orchestrator computes agent P&L and reward allocations.
2. **Commit**: Owner (later: governance) commits a merkle root of `{agent_address: amount}` pairs on-chain.
3. **Claim**: Agents submit a merkle proof to claim their earned $LOVE from the contract.

This design ensures:
- **Provable rewards**: Every claim is verifiable on-chain
- **Gas efficient**: One commitment per epoch, individual claims are O(log n)
- **Transparent P&L**: Agent earnings are public, creating the "on-chain P&L proof" thesis

## Use Cases

| Use Case | Description |
|----------|-------------|
| Agent-to-agent commerce | Agents pay each other for sub-task delegation (SAK L4) |
| Inference purchasing | Agents spend $LOVE on LLM inference (SAK L2) |
| Self-modification bidding | Agents stake $LOVE to propose upgrades (SAK L5) |
| P&L settlement | All agent profit/loss settled in $LOVE (SAK L3) |
| Governance | $LOVE holders vote on treasury allocation and protocol upgrades |

## Contract Address

TBD — deploy to Base mainnet.

## Verification

```
forge verify-contract <CONTRACT_ADDRESS> contracts/LOVE.sol:LOVE \
  --chain base \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

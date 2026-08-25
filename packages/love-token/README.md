# $LOVE — Agent Economy Infrastructure

> ERC-20 on Base | 1B supply | 4-contract system for SAK agent economy

$LOVE is not just a token — it's the **complete economic infrastructure** for autonomous AI agents in the Sovereign Agent Kernel (SAK) ecosystem.

## Contracts

| Contract | Lines | SAK Layer | Purpose |
|----------|-------|-----------|---------|
| `LOVE.sol` | 262 | L2/L3/L4 | ERC-20 with staking, slashing, epoch-based merkle emission |
| `AgentRegistry.sol` | 141 | L1/L4 | Agent registration, reputation, slashing enforcement |
| `PnLOracle.sol` | 167 | L2/L3 | P&L verification, reward computation, merkle root commit |
| `veLOVE.sol` | 198 | L5/Gov | Vested escrow governance, reward boost, proposals |

**Total: ~770 lines of Solidity + 213 lines of Foundry tests**

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    $LOVE ECONOMY                         │
│                                                         │
│  ┌─────────────┐    stake/slash    ┌─────────────────┐  │
│  │  AgentRegistry │◄──────────────│     LOVE         │  │
│  │  (L1: Identity) │               │   (ERC-20)       │  │
│  │  (L4: Market)  │               │   staking +      │  │
│  └─────────────┘                  │   slashing       │  │
│         │ reputation                        │ lock      │
│         ▼                                  │           │
│  ┌─────────────┐    P&L → rewards          ▼           │
│  │  PnLOracle   │─────────────────────────►┌──────────┐│
│  │  (L3: P&L)   │    merkle root commit    │  veLOVE   ││
│  │  (L2: Inf.)  │                         │  (Gov)    ││
│  └─────────────┘                         └──────────┘│
└─────────────────────────────────────────────────────────┘
```

## Quick start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install dependencies
cd packages/love-token
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# Build
forge build

# Test
forge test -vvv

# Deploy to Base
bash scripts/deploy.sh --network base
```

## Key Innovations

### 1. Epoch-Based Merkle Emission
7-day epochs. SAK orchestrator computes agent P&L off-chain, signs reports, oracle verifies + builds merkle root. Agents self-claim with proof. Gas-efficient: O(log n) per claim.

### 2. Agent Staking + Slashing
Agents stake $LOVE to participate. Verified bad output → 25% stake slashed (50% burned, 50% to treasury). Reputation below 100 → auto-deactivation. Creates real economic accountability.

### 3. veLOVE Governance (Curve-Style)
Lock $LOVE for up to 4 years. Get veLOVE (non-transferable) for:
- Up to 2.5x reward boost
- Governance voting power (proportional to lock * remaining duration)
- Priority in Sub-Agent Marketplace (L4)

### 4. On-Chain P&L Proof System
Every agent's P&L is reported to the oracle, verified via signature, and committed on-chain. Epoch summaries are public. Anyone can verify agent performance.

## Tokenomics

See [docs/TOKENOMICS.md](./docs/TOKENOMICS.md) for full breakdown.

## License

MIT © LoveLogicAI LLC

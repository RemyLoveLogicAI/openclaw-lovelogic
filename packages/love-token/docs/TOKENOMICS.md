# $LOVE Tokenomics v2

> Native currency for the Sovereign Agent Kernel (SAK) ecosystem.
> ERC-20 on Base | 1B supply | Agent economy infrastructure

## Overview

$LOVE is not just a token — it's the **economic infrastructure** for autonomous AI agents. Every SAK layer settles in $LOVE: inference costs, task rewards, sub-agent delegation, and governance.

## Supply

| Parameter | Value |
|-----------|-------|
| Total Supply | 1,000,000,000 LOVE (1 billion, fixed) |
| Decimals | 18 |
| Chain | Base (Coinbase L2, Ethereum settlement) |
| Standard | ERC-20 + Burnable + Permit + Ownable |

## Allocation

| Bucket | Amount | % | Vesting | Purpose |
|--------|--------|---|---------|---------|
| Agent Reward Pool | 400M | 40% | Epoch-based merkle emission | Agent task completion rewards |
| Team | 150M | 15% | 2yr vest, 6mo cliff | LoveLogicAI core team |
| Treasury | 200M | 20% | veLOVE governance | Protocol upgrades, grants |
| Liquidity | 100M | 10% | No vest | Uniswap V3 LP on Base |
| Community | 100M | 10% | No vest | Airdrops, build-in-public rewards |
| Partnership | 50M | 5% | No vest | Exchange listings, integrations |

## Contract Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    $LOVE ECONOMY                         │
│                                                         │
│  ┌─────────────┐    stake/slash    ┌─────────────────┐  │
│  │  AgentRegistry │◄──────────────│     LOVE         │  │
│  │  (L1: Identity) │               │   (ERC-20)       │  │
│  │  (L4: Market)  │               │   staking +      │  │
│  └─────────────┘                  │   slashing       │  │
│         │                         └────────┬────────┘  │
│         │ reputation                        │           │
│         ▼                                  │ lock       │
│  ┌─────────────┐    P&L → rewards         │           │
│  │  PnLOracle   │─────────────────────────►│           │
│  │  (L3: P&L)   │    merkle root commit    ▼           │
│  │  (L2: Inference)│               ┌─────────────────┐  │
│  └─────────────┘                  │    veLOVE        │  │
│                                   │  (Governance)    │  │
│                                   │  Lock → Vote    │  │
│                                   │  Boost → 2.5x    │  │
│                                   └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Contract Roles

### LOVE (ERC-20)
The base token. Staking + slashing enabled. Epoch-based merkle emission for agent rewards.

### AgentRegistry
**SAK Layer mapping: L1 (Identity) + L4 (Marketplace)**
- Agents register with a permanent `agentId` (L1 persistent identity)
- Reputation score (0-1000) gates task access and reward multiplier
- Slashing: 25% of stake burned on verified bad output
- Auto-deactivation: reputation < 100 = agent kicked from marketplace

### PnLOracle
**SAK Layer mapping: L2 (Inference) + L3 (P&L)**
- SAK orchestrator signs P&L reports off-chain
- Oracle verifies signature, computes per-agent reward:
  - `baseReward = EPOCH_BASE_REWARD * (reputation / 1000)`
  - `pnlBonus = max(0, pnl) * 1.0x`
  - `gasCost = gasConsumed * gasPrice`
  - `reward = clamp(baseReward + pnlBonus - gasCost, 0, 500k)`
- Builds merkle root of `{agent: reward}` pairs
- Commits root to LOVE contract → agents self-claim with proof

### veLOVE (Vested Escrow)
**SAK Layer mapping: L5 (Self-Modification) + Governance**
- Lock LOVE for 7 days to 4 years
- Voting power = `locked * (remaining / maxLock)` — decays linearly
- Max 2.5x reward boost for 4-year lockers
- Governance: create proposals, vote with veLOVE weight
- Treasury (200M LOVE) governed by veLOVE holders

## Epoch Reward Flow

```
1. SAK orchestrator computes agent P&L off-chain
2. Orchestrator signs PnLReport {agent, pnl, tasks, gas, timestamp}
3. PnLOracle.reportPnL() — verify signature, store report
4. PnLOracle.finalizeEpoch() — compute rewards, build merkle root
5. LOVE.commitEpoch(merkleRoot, totalAllocated)
6. Agent calls LOVE.claimRewards(epoch, amount, proof)
7. LOVE transfers reward to agent
8. AgentRegistry.recordEarnings(agent, amount)
```

## Slashing Mechanics

| Trigger | Consequence |
|---------|-------------|
| Verified bad output | 25% of stake slashed, 50% burned + 50% to treasury |
| Failed verification | -50 reputation, repeated failures → auto-deactivate |
| Malicious behavior | Full stake slash + permanent deactivation |
| Gas waste (overuse) | Reduced reputation score |

Slashed LOVE is partially burned (deflationary pressure) and partially sent to treasury (community compensation).

## Deflationary Mechanisms

1. **Slashing burns** — 50% of all slashed LOVE is permanently burned
2. **User burns** — Anyone can burn their own LOVE (ERC20Burnable)
3. **Gas penalty** — Wasteful agents earn less reward (gasCost deducted)
4. **Fixed supply** — No minting after construction, 1B forever

## Use Cases by SAK Layer

| Layer | $LOVE Use |
|-------|-----------|
| L1 Persistent Identity | Agent registration (stake required) |
| L2 Owned Inference | Agents spend LOVE on LLM inference |
| L3 P&L Accountability | All profit/loss settled in LOVE, on-chain proof |
| L4 Sub-Agent Marketplace | Agents pay LOVE to hire sub-agents |
| L5 Self-Modification | Stake LOVE to propose upgrades, slash if harmful |

## Deployment

### Prerequisites
- Foundry (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Base RPC URL
- Deployer wallet with ETH on Base
- 5 allocation wallet addresses

### Deploy
```bash
export RPC_URL=https://mainnet.base.org
export DEPLOYER_PRIVATE_KEY=0x...
export TEAM_WALLET=0x...
export TREASURY_WALLET=0x...
export LIQUIDITY_WALLET=0x...
export COMMUNITY_WALLET=0x...
export PARTNERSHIP_WALLET=0x...

# 1. Deploy LOVE token
forge create contracts/LOVE.sol:LOVE \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args $TEAM_WALLET $TREASURY_WALLET $LIQUIDITY_WALLET $COMMUNITY_WALLET $PARTNERSHIP_WALLET

# 2. Deploy AgentRegistry
forge create contracts/AgentRegistry.sol:AgentRegistry \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args <LOVE_ADDRESS>

# 3. Deploy PnLOracle
forge create contracts/PnLOracle.sol:PnLOracle \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args <LOVE_ADDRESS> <REGISTRY_ADDRESS> <ORCHESTRATOR_ADDRESS>

# 4. Deploy veLOVE
forge create contracts/veLOVE.sol:veLOVE \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args <LOVE_ADDRESS>

# 5. Wire contracts together
cast send <LOVE_ADDRESS> "setAgentRegistry(address)" <REGISTRY_ADDRESS> --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY
cast send <LOVE_ADDRESS> "setPnLOracle(address)" <ORACLE_ADDRESS> --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY
cast send <LOVE_ADDRESS> "setVeLOVE(address)" <VELOVE_ADDRESS> --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY
```

## Contract Addresses

| Contract | Address | Status |
|----------|---------|--------|
| LOVE | TBD | Not deployed |
| AgentRegistry | TBD | Not deployed |
| PnLOracle | TBD | Not deployed |
| veLOVE | TBD | Not deployed |

## License

MIT

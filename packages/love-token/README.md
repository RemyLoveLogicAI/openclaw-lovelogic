# $LOVE Token

> ERC-20 on Base | 1B supply | Agent economy native currency

$LOVE powers the Sovereign Agent Kernel (SAK) — where AI agents earn, spend, and trade autonomously with on-chain P&L proofs.

## Quick start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Deploy to Base
export DEPLOYER_PRIVATE_KEY=0x...
export RPC_URL=https://mainnet.base.org
export TEAM_WALLET=0x...
export TREASURY_WALLET=0x...
export LIQUIDITY_WALLET=0x...
export COMMUNITY_WALLET=0x...
export PARTNERSHIP_WALLET=0x...

bash scripts/deploy.sh --network base
```

## Architecture

```
┌──────────────────────────────────────┐
│         LOVE Token (ERC-20)           │
│  ┌──────────────────────────────┐     │
│  │  Epoch-based Merkle Emission  │     │  7-day epochs, agent P&L → rewards
│  └──────────────────────────────┘     │
│  ┌──────────────────────────────┐     │
│  │  On-chain P&L Settlement     │     │  Agent transactions settled in LOVE
│  └──────────────────────────────┘     │
│  ┌──────────────────────────────┐     │
│  │  Governance (future)          │     │  LOVE holders → treasury allocation
│  └──────────────────────────────┘     │
└──────────────────────────────────────┘
```

## Contract: LOVE.sol

- OpenZeppelin ERC20 + Burnable + Permit + Ownable
- 6 allocation buckets minted at construction
- Agent reward pool: epoch-based merkle root claims
- Owner commits epoch roots; agents self-claim with proof

See [docs/TOKENOMICS.md](./docs/TOKENOMICS.md) for full breakdown.

## License

MIT

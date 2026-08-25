# openclaw-lovelogic

> LoveLogicAI's downstream layer for [OpenClaw](https://github.com/openclaw/openclaw) — consent-native memory kernel, deployment config, agent skills, and the $LOVE token.

## What this is

OpenClaw (384k+ stars) is a personal AI assistant platform. This repo is **not a fork** — it's a downstream system that builds on top of OpenClaw as an npm dependency.

### Packages

| Package | Description |
|---------|-------------|
| `@openclaw-lovelogic/memory-kernel` | Consent-native persistent memory architecture with provable vector purge. Consent-lease model → MemoryKernel → Verifier. |
| `@openclaw-lovelogic/deploy-config` | Deployment configuration templates for Vercel, Cloudflare Workers, and Docker. |
| `@openclaw-lovelogic/love-token` | $LOVE — ERC-20 on Base. Native currency for SAK agent economy. Epoch-based merkle emission. |

## Architecture

```
openclaw/openclaw (platform, npm dependency)
        │
        ▼
┌─────────────────────────────────────────────┐
│    openclaw-lovelogic                        │
│  ┌──────────────────────────────────┐        │
│  │   memory-kernel                   │        │  ConsentGrant → Kernel → Verifier
│  │   (L2 Owned Inference)            │        │  Provable purge on lease revocation
│  └──────────────────────────────────┘        │
│  ┌──────────────────────────────────┐        │
│  │   love-token                      │        │  ERC-20 on Base
│  │   (L3 P&L + L4 Marketplace)       │        │  Epoch-based agent reward emission
│  └──────────────────────────────────┘        │
│  ┌──────────────────────────────────┐        │
│  │   deploy-config                   │        │  Vercel / Cloudflare / Docker templates
│  └──────────────────────────────────┘        │
└─────────────────────────────────────────────┘
```

## Key concept: consent-lease memory

Every memory is governed by a **consent lease**. Revoking the lease doesn't just hide the memory — it **purges the vector**, so the system's semantic behavior measurably diverges from its pre-revocation state.

```
consent-lease revocation → vector purge → semantic divergence
```

## Key concept: $LOVE agent economy

$LOVE is the native currency for SAK's agent-to-agent commerce:

```
agent completes task → earns LOVE (epoch emission)
agent needs inference → spends LOVE on L2 inference
agent delegates sub-task → pays LOVE to sub-agent (L4)
agent P&L settled → on-chain proof in LOVE (L3)
```

## Usage

```bash
# Install
pnpm install

# Run tests
pnpm test

# Build contracts (requires Foundry)
cd packages/love-token && forge build
```

## Relationship to LoveLogicAI stack

- **SAK (Sovereign Agent Kernel)** — economic kernel, $LOVE is the settlement layer
- **AgentOS** — governance kernel, uses consent-lease for capability tokens
- **MCP Super-Server** — voice/tool layer, connects via the memory-kernel API
- **PixelHQ ULTRA** — mission control HUD, visualizes memory state + $LOVE flows

## License

MIT

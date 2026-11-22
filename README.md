# openclaw-lovelogic

> LoveLogicAI's downstream layer for [OpenClaw](https://github.com/openclaw/openclaw) — consent-native memory kernel, deployment config, agent skills, and the $LOVE agent economy.

## What this is

OpenClaw (384k+ stars) is a personal AI assistant platform. This repo is **not a fork** — it's a downstream system that builds on top of OpenClaw as an npm dependency.

### Packages

| Package | Description |
|---------|-------------|
| `@openclaw-lovelogic/memory-kernel` | Consent-native persistent memory with provable vector purge |
| `@openclaw-lovelogic/deploy-config` | Deployment templates for Vercel, Cloudflare, Docker |
| `@openclaw-lovelogic/love-token` | $LOVE — ERC-20 on Base + AgentRegistry + PnLOracle + veLOVE governance |

## $LOVE Economy Architecture

```
openclaw/openclaw (platform, npm dependency)
        │
        ▼
┌─────────────────────────────────────────────┐
│    openclaw-lovelogic                        │
│                                             │
│  memory-kernel          love-token           │
│  (L2 Inference)         ┌──────────────┐    │
│                         │  LOVE (ERC-20) │   │
│                         │  + staking    │   │
│                         │  + slashing   │   │
│                         └──────┬───────┘    │
│                                │             │
│                   ┌────────────┼──────────┐  │
│                   │            │          │  │
│              AgentRegistry  PnLOracle  veLOVE│
│              (L1/L4)       (L2/L3)    (L5)  │
│              identity      P&L→rewards  gov  │
│              reputation   merkle      boost │
│              slashing      oracle     vote  │
│                                             │
│  deploy-config (Vercel/CF/Docker)           │
└─────────────────────────────────────────────┘
```

## Usage

```bash
pnpm install
pnpm test

# Smart contracts
cd packages/love-token
forge install
forge build
forge test -vvv
```

## Deploy (Cloudflare Workers)

The Worker lives in `packages/worker` (entry `src/index.ts`, config `wrangler.toml`). It exports the
default `fetch` handler and the `MemoryStore` Durable Object (binding `MEMORY`), a persistent,
consent-gated version of `MemoryKernel`.

```bash
pnpm install
pnpm --filter @openclaw-lovelogic/worker build   # wrangler deploy --dry-run
pnpm --filter @openclaw-lovelogic/worker dev     # local dev server
```

`.github/workflows/deploy.yml` deploys on every push to `main` that touches the Worker (or on manual
dispatch). Add these repository secrets first: `CLOUDFLARE_API_TOKEN` (a token with
"Edit Cloudflare Workers" permissions) and `CLOUDFLARE_ACCOUNT_ID`.

## Relationship to LoveLogicAI stack

- **SAK** — $LOVE is the settlement layer for all 5 sovereignty layers
- **AgentOS** — governance kernel uses consent-lease for capability tokens
- **MCP Super-Server** — voice/tool layer connects via memory-kernel API
- **PixelHQ ULTRA** — HUD visualizes memory state + $LOVE flows

## License

MIT

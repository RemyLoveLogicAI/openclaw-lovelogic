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
consent-gated version of `MemoryKernel`. `src/memory-store.ts` defines the `MemoryStoreApi` interface
with an in-memory backend (tests) and a Durable Object storage backend (production); `src/router.ts`
holds the HTTP routes.

```bash
pnpm install
pnpm --filter @openclaw-lovelogic/worker typecheck
pnpm --filter @openclaw-lovelogic/worker test    # vitest, runs under Node
pnpm --filter @openclaw-lovelogic/worker build   # wrangler deploy --dry-run --outdir dist
pnpm --filter @openclaw-lovelogic/worker dev     # local dev server
```

`.github/workflows/deploy.yml` runs typecheck, tests and `wrangler deploy --dry-run` on every PR to
`main`. On push to `main` (Worker paths) or manual dispatch it deploys with `cloudflare/wrangler-action`,
but only when the repository secrets `CLOUDFLARE_API_TOKEN` (a token with "Edit Cloudflare Workers"
permission) and `CLOUDFLARE_ACCOUNT_ID` exist; otherwise the deploy job skips with a notice.
The Durable Object binding needs no resource ID; if you add KV later, put the real namespace ID from
`wrangler kv namespace create` in `wrangler.toml`.

## Relationship to LoveLogicAI stack

- **SAK** — $LOVE is the settlement layer for all 5 sovereignty layers
- **AgentOS** — governance kernel uses consent-lease for capability tokens
- **MCP Super-Server** — voice/tool layer connects via memory-kernel API
- **PixelHQ ULTRA** — HUD visualizes memory state + $LOVE flows

## License

MIT

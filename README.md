# openclaw-lovelogic

> LoveLogicAI's downstream layer for [OpenClaw](https://github.com/openclaw/openclaw) — consent-native memory kernel, deployment config, and agent skills.

## What this is

OpenClaw (384k+ stars) is a personal AI assistant platform. This repo is **not a fork** — it's a downstream system that builds on top of OpenClaw as an npm dependency.

### Packages

| Package | Description |
|---------|-------------|
| `@openclaw-lovelogic/memory-kernel` | Consent-native persistent memory architecture with provable vector purge. Consent-lease model → MemoryKernel → Verifier. |
| `@openclaw-lovelogic/deploy-config` | Deployment configuration templates for Vercel, Cloudflare Workers, and Docker. |

## Architecture

```
openclaw/openclaw (platform, npm dependency)
        │
        ▼
┌─────────────────────────────────┐
│    openclaw-lovelogic            │
│  ┌─────────────────────────┐    │
│  │   memory-kernel          │    │  ConsentGrant → Kernel → Verifier
│  │   (L2 Owned Inference)   │    │  Provable purge on lease revocation
│  └─────────────────────────┘    │
│  ┌─────────────────────────┐    │
│  │   deploy-config          │    │  Vercel / Cloudflare / Docker templates
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

## Key concept: consent-lease memory

Every memory is governed by a **consent lease**. Revoking the lease doesn't just hide the memory — it **purges the vector**, so the system's semantic behavior measurably diverges from its pre-revocation state.

```
consent-lease revocation → vector purge → semantic divergence
```

Before revocation: `semanticDistance(original, retrieved) = 0`
After revocation + purge: `semanticDistance = ∞` (maximal divergence)

## Usage

```bash
# Install
pnpm install

# Run tests
pnpm test

# Type check
pnpm typecheck
```

## Memory Kernel

```typescript
import { MemoryKernel, issueGrant, verify } from "@openclaw-lovelogic/memory-kernel";

// Issue a consent lease
const grant = await issueGrant("persona:alice/memory:childhood-home", "agent:1", "read", 3600000);

// Store a memory under the lease
const kernel = new MemoryKernel();
kernel.store(grant.resourceId, [0.9, 0.1, 0.42, 0.05], grant);

// Verify consent before retrieval
if (await verify(grant)) {
  const memory = kernel.retrieve(grant.resourceId);
}

// Revoke → purge → provable forgetting
revokeGrant(grant);
kernel.purge(grant.resourceId);
// semanticDistance now = ∞
```

## Relationship to LoveLogicAI stack

- **SAK (Sovereign Agent Kernel)** — economic kernel, this is the L2 Owned Inference layer
- **AgentOS** — governance kernel, uses consent-lease for capability tokens
- **MCP Super-Server** — voice/tool layer, connects via the memory-kernel API
- **PixelHQ ULTRA** — mission control HUD, visualizes memory state

## License

MIT

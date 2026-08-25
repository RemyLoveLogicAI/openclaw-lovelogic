# Contributing to openclaw-lovelogic

## Git Workflow

```
main          ────────► production (protected, requires CI + review)
  └─ develop  ────────► integration branch
       └─ feat/*  ────► feature branches
       └─ fix/*   ────► bugfix branches
       └─ docs/*  ────► documentation
```

### Rules
1. Never commit directly to `main` or `develop`
2. All changes via PR — CI must pass (TypeScript + Foundry tests)
3. Contract changes require 2 reviewers
4. Non-contract changes require 1 reviewer
5. Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`

### Commit format
```
type(scope): description

[optional body]
```

Examples:
- `feat(love-token): add veLOVE governance contract`
- `fix(memory-kernel): correct semantic distance for empty vectors`
- `test(contracts): add slashing edge case tests`

## Development Setup

```bash
# Clone
git clone https://github.com/RemyLoveLogicAI/openclaw-lovelogic.git
cd openclaw-lovelogic

# Install
pnpm install

# For contract work
cd packages/love-token
forge install
forge build
forge test -vvv
```

## Security

- Report security issues to security@lovelogic.ai
- NEVER commit private keys, mnemonics, or .env files
- All contract changes trigger Slither + Mythril scans in CI
- Critical findings block merge automatically

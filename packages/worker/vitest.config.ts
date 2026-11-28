import { defineConfig } from "vitest/config";

// Unit tests run under Node against src/memory-store.ts and src/router.ts,
// which do not import `cloudflare:workers`.
export default defineConfig({
  test: { include: ["test/**/*.test.ts"], environment: "node" },
});

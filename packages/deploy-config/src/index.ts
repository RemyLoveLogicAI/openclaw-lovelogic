export const VERSION = "0.1.0";

export interface DeployConfig {
  name: string;
  platform: "vercel" | "cloudflare" | "local" | "supabase";
  env: Record<string, string>;
  regions?: string[];
  healthCheck?: string;
}

export function validateConfig(config: DeployConfig): string[] {
  const errors: string[] = [];
  if (!config.name) errors.push("name is required");
  if (!config.platform) errors.push("platform is required");
  if (!config.env?.OPENCLAW_API_KEY) errors.push("OPENCLAW_API_KEY is required in env");
  return errors;
}

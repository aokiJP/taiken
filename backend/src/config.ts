// 設定の読み込みと検証。本番 (NODE_ENV=production) では危険な設定を起動時に拒否する (fail fast)。
import type { LogLevel } from './support/logger.ts';

export const APP_VERSION = '1.1.0';

export type Provider = 'anthropic' | 'mock';
export type Environment = 'development' | 'production' | 'test';

export interface Config {
  readonly env: Environment;
  readonly host: string;
  readonly port: number;
  readonly provider: Provider;
  readonly anthropic: {
    readonly apiKey: string;
    readonly baseUrl: string;
    readonly models: { readonly experience: string; readonly chat: string; readonly research: string };
    readonly timeoutMs: number;
    readonly maxRetries: number;
  };
  readonly webSearch: {
    readonly enabled: boolean;
    readonly toolType: string;
    readonly maxUsesPerRequest: number;
  };
  readonly budget: {
    readonly dailyRequests: number;
    readonly dailyTokens: number;
    readonly dailyWebSearches: number;
    readonly timeZone: string;
  };
  readonly clientTokens: readonly string[];
  readonly rateLimit: { readonly burst: number; readonly perMinute: number };
  readonly maxConcurrentAi: number;
  readonly maxBodyBytes: number;
  readonly requestDeadlineMs: number;
  readonly fallbackToMock: boolean;
  readonly dataDir: string | null;
  readonly logLevel: LogLevel;
}

export class ConfigError extends Error {
  readonly problems: readonly string[];
  constructor(problems: string[]) {
    super(`設定に問題があります:\n- ${problems.join('\n- ')}`);
    this.name = 'ConfigError';
    this.problems = problems;
  }
}

export const MIN_TOKEN_LENGTH = 32;

type Env = Record<string, string | undefined>;

function intIn(env: Env, key: string, fallback: number, min: number, max: number, problems: string[]): number {
  const raw = env[key];
  if (raw === undefined || raw.trim() === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < min || n > max) {
    problems.push(`${key} は ${min}〜${max} の整数にしてください (現在: ${raw})`);
    return fallback;
  }
  return n;
}

function bool(env: Env, key: string, fallback: boolean, problems: string[]): boolean {
  const raw = env[key]?.trim().toLowerCase();
  if (raw === undefined || raw === '') return fallback;
  if (['true', '1', 'yes'].includes(raw)) return true;
  if (['false', '0', 'no'].includes(raw)) return false;
  problems.push(`${key} は true / false にしてください (現在: ${raw})`);
  return fallback;
}

function isValidTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export interface LoadedConfig {
  config: Config;
  warnings: string[];
}

export function loadConfig(env: Env = process.env): LoadedConfig {
  const problems: string[] = [];
  const warnings: string[] = [];

  const envName = (env.NODE_ENV ?? 'development') as Environment;
  if (!['development', 'production', 'test'].includes(envName)) {
    problems.push(`NODE_ENV は development / production / test のいずれかにしてください`);
  }
  const production = envName === 'production';

  const apiKey = env.ANTHROPIC_API_KEY?.trim() ?? '';
  const requested = (env.AI_PROVIDER?.trim().toLowerCase() || 'anthropic') as Provider;
  if (requested !== 'anthropic' && requested !== 'mock') {
    problems.push(`AI_PROVIDER は anthropic / mock のいずれかにしてください`);
  }
  let provider: Provider = requested === 'mock' ? 'mock' : 'anthropic';
  if (provider === 'anthropic' && !apiKey) {
    if (production) {
      problems.push('本番では ANTHROPIC_API_KEY が必須です (モックで動かす場合は AI_PROVIDER=mock を明示してください)');
    } else {
      provider = 'mock';
      warnings.push('ANTHROPIC_API_KEY が未設定のため、モック生成で起動します');
    }
  }

  const clientTokens = (env.CLIENT_TOKENS ?? '')
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean);
  const weak = clientTokens.filter((t) => t.length < MIN_TOKEN_LENGTH);
  if (weak.length) {
    const msg = `CLIENT_TOKENS に ${MIN_TOKEN_LENGTH} 文字未満のトークンがあります (npm run token で生成できます)`;
    if (production) problems.push(msg);
    else warnings.push(msg);
  }
  if (!clientTokens.length) {
    if (production) problems.push('本番では CLIENT_TOKENS が必須です');
    else warnings.push('CLIENT_TOKENS が未設定のため、認証なしで起動します (ローカル開発専用)');
  }

  const budgetTz = env.BUDGET_TIME_ZONE?.trim() || 'Asia/Tokyo';
  if (!isValidTimeZone(budgetTz)) problems.push(`BUDGET_TIME_ZONE が不正です: ${budgetTz}`);

  const logLevel = (env.LOG_LEVEL?.trim() || 'info') as LogLevel;
  if (!['debug', 'info', 'warn', 'error'].includes(logLevel)) problems.push('LOG_LEVEL は debug / info / warn / error');

  const config: Config = Object.freeze({
    env: envName,
    host: env.HOST?.trim() || '0.0.0.0',
    port: intIn(env, 'PORT', 8787, 1, 65535, problems),
    provider,
    anthropic: Object.freeze({
      apiKey,
      baseUrl: (env.ANTHROPIC_BASE_URL?.trim() || 'https://api.anthropic.com').replace(/\/+$/, ''),
      models: Object.freeze({
        experience: env.AI_MODEL_EXPERIENCE?.trim() || 'claude-sonnet-5-5',
        chat: env.AI_MODEL_CHAT?.trim() || 'claude-haiku-5-5',
        research: env.AI_MODEL_RESEARCH?.trim() || 'claude-haiku-5-5',
      }),
      timeoutMs: intIn(env, 'AI_TIMEOUT_MS', 30_000, 1_000, 120_000, problems),
      maxRetries: intIn(env, 'AI_MAX_RETRIES', 2, 0, 5, problems),
    }),
    webSearch: Object.freeze({
      enabled: bool(env, 'WEB_SEARCH_ENABLED', false, problems),
      toolType: env.WEB_SEARCH_TOOL_TYPE?.trim() || 'web_search_20250305',
      maxUsesPerRequest: intIn(env, 'WEB_SEARCH_MAX_USES', 2, 1, 5, problems),
    }),
    budget: Object.freeze({
      dailyRequests: intIn(env, 'DAILY_AI_REQUEST_LIMIT', 200, 1, 100_000, problems),
      dailyTokens: intIn(env, 'DAILY_AI_TOKEN_LIMIT', 500_000, 1_000, 100_000_000, problems),
      dailyWebSearches: intIn(env, 'DAILY_WEB_SEARCH_LIMIT', 20, 0, 10_000, problems),
      timeZone: budgetTz,
    }),
    clientTokens: Object.freeze(clientTokens),
    rateLimit: Object.freeze({
      burst: intIn(env, 'RATE_LIMIT_BURST', 10, 1, 1000, problems),
      perMinute: intIn(env, 'RATE_LIMIT_PER_MINUTE', 20, 1, 10_000, problems),
    }),
    maxConcurrentAi: intIn(env, 'MAX_CONCURRENT_AI', 4, 1, 64, problems),
    maxBodyBytes: intIn(env, 'MAX_BODY_BYTES', 32_768, 1_024, 1_048_576, problems),
    requestDeadlineMs: intIn(env, 'REQUEST_DEADLINE_MS', 50_000, 5_000, 300_000, problems),
    fallbackToMock: bool(env, 'FALLBACK_TO_MOCK', true, problems),
    dataDir: env.DATA_DIR?.trim() || null,
    logLevel,
  });

  if (config.webSearch.enabled && provider === 'mock') {
    warnings.push('WEB_SEARCH_ENABLED=true ですが、モック生成のため検索は行いません');
  }

  if (problems.length) throw new ConfigError(problems);
  return { config, warnings };
}

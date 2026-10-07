// 起動: 設定検証 → 依存関係の組み立て → HTTPサーバー開始 → シグナルで安全に停止
import { join } from 'node:path';
import { AnthropicClient } from './ai/anthropicClient.ts';
import { createAnthropicProvider } from './ai/anthropic.ts';
import { createMockProvider } from './ai/mock.ts';
import { APP_VERSION, ConfigError, loadConfig } from './config.ts';
import { createEngine } from './engine/engine.ts';
import { createApp } from './http/server.ts';
import { FileUsageStore, UsageBudget } from './support/budget.ts';
import { ConcurrencyGate } from './support/concurrency.ts';
import { createLogger } from './support/logger.ts';
import { CircuitBreaker } from './support/resilience.ts';

async function main(): Promise<void> {
  let loaded;
  try {
    loaded = loadConfig();
  } catch (error) {
    if (error instanceof ConfigError) {
      process.stderr.write(`${error.message}\n`);
      process.exit(78); // EX_CONFIG
    }
    throw error;
  }
  const { config, warnings } = loaded;
  const logger = createLogger({ level: config.logLevel, base: { service: 'taiken-backend', version: APP_VERSION } });
  for (const w of warnings) logger.warn('config.warning', { detail: w });

  const budget = await UsageBudget.create({
    limits: config.budget,
    timeZone: config.budget.timeZone,
    store: config.dataDir ? new FileUsageStore(join(config.dataDir, 'usage.json')) : null,
    logger,
  });

  const mock = createMockProvider();
  const provider =
    config.provider === 'anthropic'
      ? createAnthropicProvider({
          client: new AnthropicClient({
            apiKey: config.anthropic.apiKey,
            baseUrl: config.anthropic.baseUrl,
            timeoutMs: config.anthropic.timeoutMs,
            maxRetries: config.anthropic.maxRetries,
            logger,
          }),
          models: config.anthropic.models,
          webSearch: { toolType: config.webSearch.toolType, maxUses: config.webSearch.maxUsesPerRequest },
        })
      : mock;

  const engine = createEngine({
    provider,
    fallback: config.fallbackToMock ? mock : null,
    budget,
    breaker: new CircuitBreaker({ failureThreshold: 3, cooldownMs: 60_000 }),
    gate: new ConcurrencyGate(config.maxConcurrentAi),
    webSearchEnabled: config.webSearch.enabled,
    logger,
  });

  const server = createApp({ config, engine, budget, logger });
  server.listen(config.port, config.host, () => {
    logger.info('server.started', {
      host: config.host,
      port: config.port,
      env: config.env,
      provider: provider.name,
      web_search: config.webSearch.enabled,
      auth: config.clientTokens.length > 0,
    });
  });

  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) return;
    stopping = true;
    logger.info('server.stopping', { signal });
    // 新規接続を止め、処理中のリクエストを待つ。待ちすぎたら強制終了
    const force = setTimeout(() => {
      logger.warn('server.forced_exit');
      process.exit(1);
    }, 15_000);
    force.unref();
    server.close(async () => {
      await budget.flush();
      logger.info('server.stopped');
      process.exit(0);
    });
    server.closeIdleConnections();
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('unhandledRejection', (reason) => {
    logger.error('process.unhandled_rejection', { error: (reason as Error)?.name ?? 'unknown' });
  });
}

await main();

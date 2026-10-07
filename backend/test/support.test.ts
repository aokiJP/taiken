import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { ConfigError, loadConfig, MIN_TOKEN_LENGTH } from '../src/config.ts';
import { RateLimiter } from '../src/http/rateLimit.ts';
import { dateKey, FileUsageStore, nextMidnight, UsageBudget } from '../src/support/budget.ts';
import { ConcurrencyGate } from '../src/support/concurrency.ts';
import { createLogger, redact } from '../src/support/logger.ts';
import { CircuitBreaker, retry, sleep } from '../src/support/resilience.ts';
import { generousLimits, MemoryUsageStore } from './helpers.ts';

const strongToken = 'x'.repeat(MIN_TOKEN_LENGTH);

// ---- config ----

test('設定: 開発ではキーが無ければモックに落とし、警告を出す', () => {
  const { config, warnings } = loadConfig({});
  assert.equal(config.provider, 'mock');
  assert.ok(warnings.some((w) => w.includes('ANTHROPIC_API_KEY')));
  assert.equal(config.anthropic.models.experience, 'claude-sonnet-5-5');
});

test('設定: 本番では APIキー・十分に長いトークンが必須', () => {
  assert.throws(() => loadConfig({ NODE_ENV: 'production' }), (e) => e instanceof ConfigError && e.problems.length === 2);
  assert.throws(() => loadConfig({ NODE_ENV: 'production', ANTHROPIC_API_KEY: 'k', CLIENT_TOKENS: 'short' }), ConfigError);
  const { config } = loadConfig({ NODE_ENV: 'production', ANTHROPIC_API_KEY: 'k', CLIENT_TOKENS: `${strongToken}, ${strongToken}y` });
  assert.equal(config.provider, 'anthropic');
  assert.equal(config.clientTokens.length, 2);
  // 本番でも明示すればモックで動かせる
  assert.equal(loadConfig({ NODE_ENV: 'production', AI_PROVIDER: 'mock', CLIENT_TOKENS: strongToken }).config.provider, 'mock');
});

test('設定: 範囲外・不正な値はまとめて報告する', () => {
  assert.throws(
    () => loadConfig({ PORT: '99999', WEB_SEARCH_ENABLED: 'maybe', BUDGET_TIME_ZONE: 'Nowhere/City', LOG_LEVEL: 'loud', AI_PROVIDER: 'other', NODE_ENV: 'staging' }),
    (e) => e instanceof ConfigError && e.problems.length === 6,
  );
});

test('設定: 末尾のスラッシュを除き、真偽値の表記ゆれを受け付ける', () => {
  const { config, warnings } = loadConfig({ ANTHROPIC_BASE_URL: 'https://proxy.example/', WEB_SEARCH_ENABLED: 'yes', AI_PROVIDER: 'mock' });
  assert.equal(config.anthropic.baseUrl, 'https://proxy.example');
  assert.equal(config.webSearch.enabled, true);
  assert.ok(warnings.some((w) => w.includes('WEB_SEARCH')));
});

// ---- logger ----

test('ログ: JSON Lines で出力し、内容に関わるキーは伏せる', () => {
  const lines: string[] = [];
  const log = createLogger({ level: 'info', write: (l) => lines.push(l), now: () => new Date(0), base: { service: 's' } });
  log.debug('hidden');
  log.child({ request_id: 'r1' }).info('hello', { token: 'secret', title: '歯医者', status: 200, skip: undefined });
  assert.equal(lines.length, 1);
  assert.deepEqual(JSON.parse(lines[0]!), {
    ts: '1970-01-01T00:00:00.000Z',
    level: 'info',
    msg: 'hello',
    service: 's',
    request_id: 'r1',
    token: '[redacted]',
    title: '[redacted]',
    status: 200,
  });
  assert.deepEqual(redact({ api_key: 'k' }), { api_key: '[redacted]' });
});

// ---- resilience ----

test('retry: 指数バックオフで再試行し、対象外のエラーは即座に投げる', async () => {
  const waits: number[] = [];
  let n = 0;
  const out = await retry(async () => (++n < 3 ? Promise.reject(new Error('x')) : 'ok'), {
    retries: 3,
    baseDelayMs: 100,
    maxDelayMs: 150,
    shouldRetry: () => true,
    sleep: async (ms) => void waits.push(ms),
    random: () => 0,
  });
  assert.equal(out, 'ok');
  assert.deepEqual(waits, [50, 75]); // 100*0.5, min(150,200)*0.5
  await assert.rejects(retry(async () => Promise.reject(new Error('fatal')), { retries: 3, baseDelayMs: 1, maxDelayMs: 1, shouldRetry: () => false }), /fatal/);
});

test('sleep: 中断で即座に終わる', async () => {
  const c = new AbortController();
  const p = sleep(10_000, c.signal);
  c.abort(new Error('stop'));
  await assert.rejects(p, /stop/);
  const already = new AbortController();
  already.abort(new Error('pre'));
  await assert.rejects(sleep(10, already.signal), /pre/);
  await sleep(1);
});

test('遮断器: 閾値で open → cooldown 後に1件だけ試す → 成功で closed / 失敗で再び open', () => {
  let now = 0;
  const b = new CircuitBreaker({ failureThreshold: 2, cooldownMs: 1000, now: () => now });
  b.recordFailure();
  assert.equal(b.state, 'closed');
  b.recordFailure();
  assert.equal(b.tryAcquire(), false);
  now = 1000;
  assert.equal(b.state, 'half_open');
  assert.equal(b.tryAcquire(), true);
  assert.equal(b.tryAcquire(), false);
  b.recordFailure();
  assert.equal(b.state, 'open');
  now = 2500;
  assert.equal(b.tryAcquire(), true);
  b.recordSuccess();
  assert.equal(b.state, 'closed');
});

// ---- concurrency / rate limit ----

test('同時実行ゲート: 上限で断り、解放は二重に数えない', () => {
  const g = new ConcurrencyGate(1);
  const release = g.tryAcquire();
  assert.ok(release);
  assert.equal(g.tryAcquire(), null);
  release();
  release();
  assert.equal(g.active, 0);
});

test('レート制御: バースト分は通し、時間とともに回復する。キーごとに独立', () => {
  let now = 0;
  const rl = new RateLimiter({ burst: 2, perMinute: 60, now: () => now });
  assert.equal(rl.take('a').allowed, true);
  assert.equal(rl.take('a').allowed, true);
  const denied = rl.take('a');
  assert.equal(denied.allowed, false);
  assert.equal(denied.retryAfterSeconds, 1);
  assert.equal(rl.take('b').allowed, true);
  now = 1000;
  assert.equal(rl.take('a').allowed, true);
});

test('レート制御: キーが増えすぎたら満タンのバケットから捨てる', () => {
  let now = 0;
  const rl = new RateLimiter({ burst: 1, perMinute: 60, now: () => now, maxKeys: 2 });
  rl.take('a');
  rl.take('b');
  now = 5000;
  assert.equal(rl.take('c').allowed, true);
  assert.equal(rl.take('a').allowed, true);
});

// ---- budget ----

test('予算: 日付はタイムゾーン基準で切り替わり、次の0時を返す', async () => {
  let now = new Date('2026-10-08T14:59:00Z'); // JST 23:59
  const store = new MemoryUsageStore();
  const budget = await UsageBudget.create({ limits: { ...generousLimits, dailyRequests: 2 }, timeZone: 'Asia/Tokyo', now: () => now, store });
  budget.record({ inputTokens: 10, outputTokens: 5, webSearches: 1 });
  budget.record({ inputTokens: 10, outputTokens: 5, webSearches: 0 });
  assert.equal(budget.canUseAi(), false);
  assert.deepEqual(budget.remaining(), { requests: 0, tokens: 10_000_000 - 30, webSearches: 99, resetsAt: '2026-10-09T00:00:00+09:00' });
  await budget.flush();
  assert.deepEqual(store.snapshot, { date: '2026-10-08', requests: 2, tokens: 30, webSearches: 1 });

  now = new Date('2026-10-08T15:00:00Z'); // JST 翌0時
  assert.equal(budget.canUseAi(), true);
  assert.equal(budget.remaining().requests, 2);
});

test('予算: トークン上限・検索上限', async () => {
  const now = () => new Date('2026-10-08T00:00:00Z');
  const budget = await UsageBudget.create({ limits: { dailyRequests: 10, dailyTokens: 1000, dailyWebSearches: 1 }, timeZone: 'UTC', now });
  assert.equal(budget.canUseWebSearch(), true);
  budget.record({ inputTokens: 0, outputTokens: 0, webSearches: 1 });
  assert.equal(budget.canUseWebSearch(), false);
  budget.record({ inputTokens: 900, outputTokens: 100, webSearches: 0 });
  assert.equal(budget.canUseAi(), false);
  assert.equal(budget.remaining().resetsAt, '2026-10-09T00:00:00+00:00');
});

test('予算: ファイルに保存し、再起動後も同じ日の使用量を引き継ぐ。壊れたファイルは無視', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'taiken-'));
  try {
    const path = join(dir, 'nested', 'usage.json');
    const now = () => new Date('2026-10-08T03:00:00Z');
    const a = await UsageBudget.create({ limits: generousLimits, timeZone: 'Asia/Tokyo', now, store: new FileUsageStore(path) });
    a.record({ inputTokens: 7, outputTokens: 3, webSearches: 0 });
    await a.flush();
    assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), { date: '2026-10-08', requests: 1, tokens: 10, webSearches: 0 });

    const b = await UsageBudget.create({ limits: generousLimits, timeZone: 'Asia/Tokyo', now, store: new FileUsageStore(path) });
    assert.equal(b.remaining().requests, generousLimits.dailyRequests - 1);

    await writeFile(path, '{"date":1}');
    assert.equal(await new FileUsageStore(path).load(), null);
    await writeFile(path, 'not json');
    const c = await UsageBudget.create({ limits: generousLimits, timeZone: 'Asia/Tokyo', now, store: new FileUsageStore(path) });
    assert.equal(c.remaining().requests, generousLimits.dailyRequests);
    assert.equal(await new FileUsageStore(join(dir, 'missing.json')).load(), null);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('予算: 保存に失敗しても処理は止めない', async () => {
  const failing = { load: async () => null, save: async () => Promise.reject(new Error('disk full')) };
  const budget = await UsageBudget.create({ limits: generousLimits, timeZone: 'UTC', store: failing });
  budget.record({ inputTokens: 1, outputTokens: 1, webSearches: 0 });
  await budget.flush();
  assert.equal(budget.remaining().requests, generousLimits.dailyRequests - 1);
});

test('日付キーと次の0時 (夏時間のある地域でも日付が正しい)', () => {
  assert.equal(dateKey(new Date('2026-03-08T12:00:00Z'), 'America/New_York'), '2026-03-08');
  assert.equal(nextMidnight(new Date('2026-03-07T12:00:00Z'), 'America/New_York'), '2026-03-08T00:00:00-05:00');
});

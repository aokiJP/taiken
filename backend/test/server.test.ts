import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { after, before, test } from 'node:test';
import { UpstreamError } from '../src/ai/anthropicClient.ts';
import { createMockProvider } from '../src/ai/mock.ts';
import { loadConfig, MIN_TOKEN_LENGTH } from '../src/config.ts';
import { createEngine, UnavailableError, type Engine } from '../src/engine/engine.ts';
import { createApp, tokenMatches } from '../src/http/server.ts';
import { ConcurrencyGate } from '../src/support/concurrency.ts';
import { silentLogger } from '../src/support/logger.ts';
import { CircuitBreaker } from '../src/support/resilience.ts';
import { contractErrors, fixture, makeBudget } from './helpers.ts';

const tokenA = 'a'.repeat(MIN_TOKEN_LENGTH);
const tokenB = 'b'.repeat(MIN_TOKEN_LENGTH);

async function start(engineOverride?: Partial<Engine>, env: Record<string, string> = {}) {
  const { config } = loadConfig({
    AI_PROVIDER: 'mock',
    CLIENT_TOKENS: `${tokenA},${tokenB}`,
    RATE_LIMIT_BURST: '5',
    RATE_LIMIT_PER_MINUTE: '1',
    MAX_BODY_BYTES: '4096',
    ...env,
  });
  const budget = await makeBudget();
  const base = createEngine({
    provider: createMockProvider(),
    fallback: null,
    budget,
    breaker: new CircuitBreaker({ failureThreshold: 3, cooldownMs: 1000 }),
    gate: new ConcurrencyGate(2),
    webSearchEnabled: false,
    logger: silentLogger,
  });
  const server = createApp({ config, engine: { ...base, ...engineOverride }, budget, logger: silentLogger });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { server, url, close: () => new Promise<void>((r) => server.close(() => r())) };
}

let app: Awaited<ReturnType<typeof start>>;
before(async () => {
  app = await start();
});
after(() => app.close());

const post = (path: string, body: unknown, token: string | null = tokenA, init: { raw?: boolean; headers?: Record<string, string>; base?: string } = {}) =>
  fetch(`${init.base ?? app.url}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...init.headers },
    body: init.raw ? String(body) : JSON.stringify(body),
  });

test('GET /health は認証なしで最小限の情報だけ返す', async () => {
  const res = await fetch(`${app.url}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual(body, { status: 'ok' });
  assert.deepEqual(contractErrors('Health', body), []);
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(res.headers.get('cache-control'), 'no-store');
});

test('GET /v1/status は認証が必要で、契約どおりの形', async () => {
  assert.equal((await fetch(`${app.url}/v1/status`)).status, 401);
  const res = await fetch(`${app.url}/v1/status`, { headers: { authorization: `Bearer ${tokenB}` } });
  const body = (await res.json()) as { provider: string; features: { web_search: boolean } };
  assert.deepEqual(contractErrors('StatusResponse', body), []);
  assert.equal(body.provider, 'mock');
  assert.equal(body.features.web_search, false);
});

test('POST /v1/experience: 契約どおりの体験を返し、リクエストIDを返す', async () => {
  const res = await post('/v1/experience', fixture('experience_request.sample.json'), tokenA, { headers: { 'x-request-id': 'test-req-0001' } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('x-request-id'), 'test-req-0001');
  const body = await res.json();
  assert.deepEqual(contractErrors('ExperienceResponse', body), []);
});

test('POST /v1/chat: 契約どおりの返答', async () => {
  const res = await post('/v1/chat', fixture('chat_request.sample.json'), tokenB);
  assert.equal(res.status, 200);
  assert.deepEqual(contractErrors('ChatResponse', await res.json()), []);
});

test('不正なリクエストIDは採用せず、新しく振る', async () => {
  const res = await fetch(`${app.url}/health`, { headers: { 'x-request-id': 'bad id!' } });
  assert.match(res.headers.get('x-request-id') ?? '', /^$|^[0-9a-f-]{36}$/);
});

test('トークンが無い/違うと401 (エラー形式は契約どおり)', async () => {
  for (const token of [null, 'wrong', `${tokenA}x`]) {
    const res = await post('/v1/experience', fixture('experience_request.sample.json'), token);
    assert.equal(res.status, 401);
    assert.equal(res.headers.get('www-authenticate'), 'Bearer');
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'unauthorized');
    assert.deepEqual(contractErrors('ErrorResponse', body), []);
  }
});

test('不正な入力は400、Content-Type違いは415、大きすぎる本文は413', async () => {
  assert.equal((await post('/v1/experience', '{oops', tokenA, { raw: true })).status, 400);
  assert.equal((await post('/v1/experience', { foo: 1 })).status, 400);
  assert.equal((await post('/v1/experience', {}, tokenA, { headers: { 'content-type': 'text/plain' } })).status, 415);
  assert.equal((await post('/v1/experience', { current_time: 'x', pad: 'a'.repeat(10_000) })).status, 413);
});

test('存在しないパスは404、メソッド違いは405 (Allow ヘッダ付き)', async () => {
  assert.equal((await post('/v1/nothing', {})).status, 404);
  const res = await fetch(`${app.url}/v1/experience`, { headers: { authorization: `Bearer ${tokenA}` } });
  assert.equal(res.status, 405);
  assert.equal(res.headers.get('allow'), 'POST');
});

test('レート制御で429 と retry-after (トークンごとに独立)', async () => {
  const own = await start(undefined, { RATE_LIMIT_BURST: '2' });
  try {
    const statuses = [];
    for (let i = 0; i < 3; i++) statuses.push((await post('/v1/chat', fixture('chat_request.sample.json'), tokenA, { base: own.url })).status);
    assert.deepEqual(statuses, [200, 200, 429]);
    const last = await post('/v1/chat', fixture('chat_request.sample.json'), tokenA, { base: own.url });
    assert.ok(Number(last.headers.get('retry-after')) > 0);
    const body = await last.json();
    assert.deepEqual(contractErrors('ErrorResponse', body), []);
    assert.equal((await post('/v1/chat', fixture('chat_request.sample.json'), tokenB, { base: own.url })).status, 200);
  } finally {
    await own.close();
  }
});

test('AIが使えず代替生成も無いときは503、混雑なら busy', async () => {
  const down = await start({
    generateExperience: async () => Promise.reject(new UnavailableError('upstream_error')),
    chat: async () => Promise.reject(new UnavailableError('busy')),
  });
  try {
    const a = await post('/v1/experience', fixture('experience_request.sample.json'), tokenA, { base: down.url });
    assert.equal(a.status, 503);
    assert.equal(((await a.json()) as { error: { code: string } }).error.code, 'upstream_unavailable');
    const b = await post('/v1/chat', fixture('chat_request.sample.json'), tokenA, { base: down.url });
    assert.equal(((await b.json()) as { error: { code: string } }).error.code, 'busy');
  } finally {
    await down.close();
  }
});

test('想定外のエラーは中身を出さずに500、上流エラーは503', async () => {
  const broken = await start({
    generateExperience: async () => Promise.reject(new Error('secret internal detail')),
    chat: async () => Promise.reject(new UpstreamError('x', { kind: 'network' })),
  });
  try {
    const res = await post('/v1/experience', fixture('experience_request.sample.json'), tokenA, { base: broken.url });
    assert.equal(res.status, 500);
    assert.doesNotMatch(await res.text(), /secret/);
    assert.equal((await post('/v1/chat', fixture('chat_request.sample.json'), tokenA, { base: broken.url })).status, 503);
  } finally {
    await broken.close();
  }
});

test('APIキーやトークンはどのレスポンスにも含まれない', async () => {
  const res = await post('/v1/experience', fixture('experience_request.sample.json'));
  const text = await res.text();
  assert.doesNotMatch(text, /sk-|api[_-]?key|aaaaaaaa/i);
});

test('トークン比較は登録済みのどれとでも一致を判定する', () => {
  assert.equal(tokenMatches(tokenB, [tokenA, tokenB]), true);
  assert.equal(tokenMatches('', [tokenA]), false);
});

test('認証なし設定 (開発) ではインストールIDでレート制御する', async () => {
  const open = await start(undefined, { CLIENT_TOKENS: '', RATE_LIMIT_BURST: '1' });
  try {
    const h = { 'x-install-id': 'device-1' };
    assert.equal((await post('/v1/chat', fixture('chat_request.sample.json'), null, { base: open.url, headers: h })).status, 200);
    assert.equal((await post('/v1/chat', fixture('chat_request.sample.json'), null, { base: open.url, headers: h })).status, 429);
    assert.equal((await post('/v1/chat', fixture('chat_request.sample.json'), null, { base: open.url, headers: { 'x-install-id': 'device-2' } })).status, 200);
  } finally {
    await open.close();
  }
});

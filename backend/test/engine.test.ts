import assert from 'node:assert/strict';
import { test } from 'node:test';
import { UpstreamError } from '../src/ai/anthropicClient.ts';
import { createMockProvider } from '../src/ai/mock.ts';
import type { AiProvider } from '../src/ai/provider.ts';
import { UnavailableError } from '../src/engine/engine.ts';
import { applyNotificationPolicy, localHour } from '../src/engine/notificationPolicy.ts';
import { sanitizeChatRequest, sanitizeExperienceRequest } from '../src/engine/sanitize.ts';
import { normalizeExperienceResult } from '../src/engine/schema.ts';
import { ConcurrencyGate } from '../src/support/concurrency.ts';
import { CircuitBreaker } from '../src/support/resilience.ts';
import { fixture, makeBudget, makeEngine, signal } from './helpers.ts';

const mock = createMockProvider();
const ctx = () => sanitizeExperienceRequest(fixture('experience_request.sample.json'));
const goodRaw = () => fixture('experience_response.sample.json');
const usage = { inputTokens: 100, outputTokens: 50, webSearches: 0 };

function ai(overrides: Partial<AiProvider>): AiProvider {
  return {
    name: 'anthropic',
    generateExperience: async (_c, _r, o) => {
      o.onUsage(usage);
      return goodRaw();
    },
    chat: async () => fixture('chat_response.sample.json'),
    ...overrides,
  };
}

const upstream = () => new UpstreamError('down', { kind: 'http', status: 500, retryable: true });

test('AIが正常なら source=ai、使用量を予算に記録する', async () => {
  const budget = await makeBudget();
  const engine = await makeEngine({ provider: ai({}), budget });
  const out = await engine.generateExperience(ctx(), { signal: signal() });
  assert.equal(out.source, 'ai');
  assert.equal(out.fallback_reason, null);
  assert.equal(budget.remaining().tokens, 10_000_000 - 150);
});

test('出力が壊れていたら invalid_output で代替生成', async () => {
  const engine = await makeEngine({ provider: ai({ generateExperience: async () => ({ situation: 'x' }) }), fallback: mock });
  const out = await engine.generateExperience(ctx(), { signal: signal() });
  assert.equal(out.source, 'fallback');
  assert.equal(out.fallback_reason, 'invalid_output');
});

test('危険な提案は unsafe_output で捨てる', async () => {
  const raw = goodRaw() as { experience: { invitation: string } };
  raw.experience.invitation = '今夜は徹夜で課題を終わらせてみませんか？';
  const engine = await makeEngine({ provider: ai({ generateExperience: async () => raw }), fallback: mock });
  const out = await engine.generateExperience(ctx(), { signal: signal() });
  assert.equal(out.fallback_reason, 'unsafe_output');
  assert.doesNotMatch(out.experience.invitation, /徹夜/);
});

test('予算切れならAIを呼ばずに budget_exceeded', async () => {
  let called = 0;
  const budget = await makeBudget({ dailyRequests: 1 });
  budget.record(usage);
  const engine = await makeEngine({
    provider: ai({ generateExperience: async () => (called++, goodRaw()) }),
    fallback: mock,
    budget,
  });
  const out = await engine.generateExperience(ctx(), { signal: signal() });
  assert.equal(called, 0);
  assert.equal(out.fallback_reason, 'budget_exceeded');
});

test('上流の連続失敗で遮断器が開き、以降は呼ばずに circuit_open', async () => {
  let called = 0;
  const breaker = new CircuitBreaker({ failureThreshold: 2, cooldownMs: 60_000 });
  const engine = await makeEngine({
    provider: ai({ generateExperience: async () => (called++, Promise.reject(upstream())) }),
    fallback: mock,
    breaker,
  });
  const reasons = [];
  for (let i = 0; i < 3; i++) reasons.push((await engine.generateExperience(ctx(), { signal: signal() })).fallback_reason);
  assert.deepEqual(reasons, ['upstream_error', 'upstream_error', 'circuit_open']);
  assert.equal(called, 2);
});

test('壊れた出力は上流の故障ではないので遮断器を開かない', async () => {
  const breaker = new CircuitBreaker({ failureThreshold: 1, cooldownMs: 60_000 });
  const engine = await makeEngine({ provider: ai({ generateExperience: async () => ({}) }), fallback: mock, breaker });
  await engine.generateExperience(ctx(), { signal: signal() });
  assert.equal(breaker.state, 'closed');
});

test('同時実行数の上限を超えたら busy', async () => {
  const gate = new ConcurrencyGate(1);
  const hold = gate.tryAcquire();
  const engine = await makeEngine({ provider: ai({}), fallback: mock, gate });
  assert.equal((await engine.generateExperience(ctx(), { signal: signal() })).fallback_reason, 'busy');
  hold?.();
  assert.equal(gate.active, 0);
});

test('代替生成が無効なら UnavailableError', async () => {
  const engine = await makeEngine({ provider: ai({ generateExperience: async () => Promise.reject(upstream()) }) });
  await assert.rejects(engine.generateExperience(ctx(), { signal: signal() }), UnavailableError);
});

test('クライアントの中断は代替生成せずそのまま伝え、遮断器も開かない', async () => {
  const breaker = new CircuitBreaker({ failureThreshold: 1, cooldownMs: 60_000 });
  const aborted = new UpstreamError('aborted', { kind: 'aborted' });
  const engine = await makeEngine({ provider: ai({ generateExperience: async () => Promise.reject(aborted) }), fallback: mock, breaker });
  await assert.rejects(engine.generateExperience(ctx(), { signal: signal() }), UpstreamError);
  assert.equal(breaker.state, 'closed');
});

test('Web検索: 許可・機能有効・予算ありのときだけ下調べし、参照を付ける', async () => {
  let researched = 0;
  let passed: unknown = undefined;
  const provider = ai({
    research: async (_c, o) => {
      researched++;
      o.onUsage({ inputTokens: 10, outputTokens: 10, webSearches: 1 });
      return { summary: '夕方から雨の予報', references: [{ title: '天気', url: 'https://weather.example' }], searches: 1 };
    },
    generateExperience: async (_c, research) => {
      passed = research;
      return goodRaw();
    },
  });
  const budget = await makeBudget();
  const on = await makeEngine({ provider, webSearchEnabled: true, budget });
  const out = await on.generateExperience(ctx(), { signal: signal() });
  assert.equal(researched, 1);
  assert.deepEqual(out.references, [{ title: '天気', url: 'https://weather.example' }]);
  assert.equal((passed as { summary: string }).summary, '夕方から雨の予報');
  assert.equal(budget.remaining().webSearches, 99);

  const off = await makeEngine({ provider, webSearchEnabled: false });
  await off.generateExperience(ctx(), { signal: signal() });
  const notAllowed = await makeEngine({ provider, webSearchEnabled: true });
  await notAllowed.generateExperience({ ...ctx(), allow_web_search: false }, { signal: signal() });
  const noBudget = await makeEngine({ provider, webSearchEnabled: true, budget: await makeBudget({ dailyWebSearches: 0 }) });
  await noBudget.generateExperience(ctx(), { signal: signal() });
  assert.equal(researched, 1);
});

test('Web検索の失敗は致命的ではなく、外部情報なしで続ける', async () => {
  const provider = ai({ research: async () => Promise.reject(upstream()) });
  const engine = await makeEngine({ provider, webSearchEnabled: true });
  const out = await engine.generateExperience(ctx(), { signal: signal() });
  assert.equal(out.source, 'ai');
  assert.deepEqual(out.references, []);
});

test('チャット: 苦痛のサインがあれば AI の判断に関わらず needs_care にし、提案を外す', async () => {
  const engine = await makeEngine({ provider: ai({}) });
  const out = await engine.chat(
    sanitizeChatRequest({ current_time: '2026-10-08T21:00:00+09:00', messages: [{ role: 'user', text: 'もう消えたい' }] }),
    { signal: signal() },
  );
  assert.equal(out.needs_care, true);
  assert.equal(out.experience, null);
});

test('チャット: モックは苦痛のサインに相談先の案内で応える', async () => {
  const engine = await makeEngine({ provider: mock });
  const out = await engine.chat(
    sanitizeChatRequest({ current_time: '2026-10-08T21:00:00+09:00', messages: [{ role: 'user', text: '死にたい' }] }),
    { signal: signal() },
  );
  assert.equal(out.needs_care, true);
  assert.match(out.reply, /相談/);
});

test('チャット: 失敗時は代替生成', async () => {
  const engine = await makeEngine({ provider: ai({ chat: async () => Promise.reject(upstream()) }), fallback: mock });
  const out = await engine.chat(sanitizeChatRequest(fixture('chat_request.sample.json')), { signal: signal() });
  assert.equal(out.source, 'fallback');
  assert.equal(out.fallback_reason, 'upstream_error');
});

test('モック: 予定も会話も無くても体験を返す / 別の提案では違う体験 / 疲れているだけなら提案しない', async () => {
  const engine = await makeEngine({ provider: mock });
  const empty = await engine.generateExperience(sanitizeExperienceRequest({ current_time: '2026-10-08T12:00:00+09:00' }), { signal: signal() });
  assert.ok(empty.experience.invitation.endsWith('？'));

  const first = await engine.generateExperience(ctx(), { signal: signal() });
  const second = await engine.generateExperience({ ...ctx(), exclude_titles: [first.experience.title] }, { signal: signal() });
  assert.notEqual(second.experience.title, first.experience.title);

  const tired = await engine.chat(
    sanitizeChatRequest({ current_time: '2026-10-08T21:00:00+09:00', messages: [{ role: 'user', text: '疲れた' }] }),
    { signal: signal() },
  );
  assert.equal(tired.suggest_experience, false);
});

test('通知ポリシー: 深夜・低確信度・断りが続く・代替生成のときは通知しない', () => {
  const withNotify = { ...normalizeExperienceResult(goodRaw(), 'ai'), should_notify: true, notification: { title: 't', body: 'b' } };
  const c = ctx();
  assert.equal(applyNotificationPolicy(withNotify, c).should_notify, true);
  assert.equal(applyNotificationPolicy(withNotify, { ...c, current_time: '2026-10-08T23:30:00+09:00' }).should_notify, false);
  assert.equal(applyNotificationPolicy(withNotify, { ...c, current_time: '2026-10-08T07:59:00+09:00' }).should_notify, false);
  assert.equal(applyNotificationPolicy({ ...withNotify, confidence: 0.3 }, c).should_notify, false);
  assert.equal(applyNotificationPolicy({ ...withNotify, source: 'fallback' }, c).should_notify, false);
  const declined = { ...c, recent_experiences: [1, 2].map((i) => ({ title: `${i}`, theme: null, reaction: 'declined' as const, rating: null, date: null })) };
  assert.equal(applyNotificationPolicy(withNotify, declined).should_notify, false);
  assert.equal(localHour('garbage'), 12);
});

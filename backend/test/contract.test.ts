import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createMockProvider } from '../src/ai/mock.ts';
import { normalizeChatResult, normalizeExperienceResult } from '../src/engine/schema.ts';
import { sanitizeChatRequest, sanitizeExperienceRequest } from '../src/engine/sanitize.ts';
import { contractErrors, fixture, makeEngine, signal } from './helpers.ts';

const FIXTURES: Array<[string, string]> = [
  ['experience_request.sample.json', 'ExperienceRequest'],
  ['experience_response.sample.json', 'ExperienceResponse'],
  ['chat_request.sample.json', 'ChatRequest'],
  ['chat_response.sample.json', 'ChatResponse'],
  ['status_response.sample.json', 'StatusResponse'],
  ['error_response.sample.json', 'ErrorResponse'],
];

for (const [file, schema] of FIXTURES) {
  test(`フィクスチャ ${file} は OpenAPI の ${schema} に一致する`, () => {
    assert.deepEqual(contractErrors(schema, fixture(file)), []);
  });
}

test('バリデータ自体が契約違反を検出できる', () => {
  const bad = { ...fixture('experience_response.sample.json'), extra: 1, confidence: 2 };
  delete (bad as Record<string, unknown>).source;
  const errs = contractErrors('ExperienceResponse', bad);
  assert.ok(errs.some((e) => e.includes('extra')));
  assert.ok(errs.some((e) => e.includes('confidence')));
  assert.ok(errs.some((e) => e.includes('source')));
});

test('リクエストのフィクスチャは入力の正規化を通しても変わらない', () => {
  assert.deepEqual(sanitizeExperienceRequest(fixture('experience_request.sample.json')), fixture('experience_request.sample.json'));
  assert.deepEqual(sanitizeChatRequest(fixture('chat_request.sample.json')), fixture('chat_request.sample.json'));
});

test('レスポンスのフィクスチャは出力の正規化を通しても変わらない', () => {
  assert.deepEqual(normalizeExperienceResult(fixture('experience_response.sample.json'), 'ai'), fixture('experience_response.sample.json'));
  assert.deepEqual(normalizeChatResult(fixture('chat_response.sample.json'), 'ai'), fixture('chat_response.sample.json'));
});

test('エンジンの実際の出力も契約に一致する (体験・会話・代替生成)', async () => {
  const engine = await makeEngine({ provider: createMockProvider() });
  const exp = await engine.generateExperience(sanitizeExperienceRequest(fixture('experience_request.sample.json')), { signal: signal() });
  assert.deepEqual(contractErrors('ExperienceResponse', exp), []);

  const chat = await engine.chat(sanitizeChatRequest(fixture('chat_request.sample.json')), { signal: signal() });
  assert.deepEqual(contractErrors('ChatResponse', chat), []);
  assert.equal(chat.suggest_experience, true);

  const failing = await makeEngine({
    provider: { ...createMockProvider(), name: 'anthropic', generateExperience: async () => ({}) },
    fallback: createMockProvider(),
  });
  const fb = await failing.generateExperience(sanitizeExperienceRequest(fixture('experience_request.sample.json')), { signal: signal() });
  assert.equal(fb.source, 'fallback');
  assert.deepEqual(contractErrors('ExperienceResponse', fb), []);
});

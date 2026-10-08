import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createAnthropicProvider, extractResearch, webSearchTool } from '../src/ai/anthropic.ts';
import { AnthropicClient, parseRetryAfter, UpstreamError } from '../src/ai/anthropicClient.ts';
import { sanitizeChatRequest, sanitizeExperienceRequest } from '../src/engine/sanitize.ts';
import type { Usage } from '../src/engine/types.ts';
import { fakeFetch, fixture, json, signal, toolResponse } from './helpers.ts';

const sleeps: number[] = [];
const noSleep = async (ms: number) => void sleeps.push(ms);

function client(fetch: typeof globalThis.fetch, maxRetries = 2, timeoutMs = 1000) {
  return new AnthropicClient({ apiKey: 'sk-test', baseUrl: 'https://api.example', timeoutMs, maxRetries, fetch, sleep: noSleep, random: () => 1 });
}

function provider(fetch: typeof globalThis.fetch) {
  return createAnthropicProvider({
    client: client(fetch),
    models: { experience: 'model-exp', chat: 'model-chat', research: 'model-research' },
    webSearch: { toolType: 'web_search_20250305', maxUses: 2 },
  });
}

const ctx = () => sanitizeExperienceRequest(fixture('experience_request.sample.json'));
const collect = () => {
  const usages: Usage[] = [];
  return { usages, opts: { signal: signal(), onUsage: (u: Usage) => usages.push(u) } };
};

test('体験生成: tool use を強制し、構造化結果と使用量を取り出す', async () => {
  const fetch = fakeFetch(() => toolResponse('propose_experience', { hello: 1 }));
  const { usages, opts } = collect();
  const out = await provider(fetch).generateExperience(ctx(), null, opts);
  assert.deepEqual(out, { hello: 1 });
  assert.deepEqual(usages, [{ inputTokens: 100, outputTokens: 50, webSearches: 0 }]);

  const call = fetch.calls[0]!;
  assert.equal(call.url, 'https://api.example/v1/messages');
  const headers = call.init.headers as Record<string, string>;
  assert.equal(headers['x-api-key'], 'sk-test');
  assert.equal(headers['anthropic-version'], '2023-06-01');
  assert.deepEqual(call.body.tool_choice, { type: 'tool', name: 'propose_experience' });
  assert.equal(call.body.model, 'model-exp');
  assert.match(String(call.body.system), /体験生成AI/);
  // ユーザーデータはタグで囲み、座標などは含めない
  const content = String((call.body.messages as Array<{ content: string }>)[0]?.content);
  assert.match(content, /<user_data>/);
  assert.doesNotMatch(content, /allow_web_search/);
});

test('会話: 同じ役割の連続をまとめ、assistant 始まりを補い、会話用モデルを使う', async () => {
  const fetch = fakeFetch(() => toolResponse('chat_reply', { reply: 'x' }));
  await provider(fetch).chat(
    sanitizeChatRequest({
      current_time: '2026-10-08T18:00:00+09:00',
      messages: [
        { role: 'assistant', text: 'こんにちは' },
        { role: 'user', text: 'a' },
        { role: 'user', text: 'b' },
      ],
    }),
    collect().opts,
  );
  const body = fetch.calls[0]!.body;
  const messages = body.messages as Array<{ role: string; content: string }>;
  assert.deepEqual(messages.map((m) => m.role), ['user', 'assistant', 'user']);
  assert.match(messages.at(-1)!.content, /<context_data>.*\n\na\nb$/s);
  assert.equal(body.model, 'model-chat');
});

test('5xx/429 は再試行し、Retry-After を尊重する', async () => {
  sleeps.length = 0;
  const fetch = fakeFetch(
    () => json({}, 529),
    () => json({}, 429, { 'retry-after': '3' }),
    () => toolResponse('propose_experience', { ok: true }),
  );
  const out = await provider(fetch).generateExperience(ctx(), null, collect().opts);
  assert.deepEqual(out, { ok: true });
  assert.equal(fetch.calls.length, 3);
  assert.deepEqual(sleeps, [500, 3000]);
});

test('4xx (429以外) は再試行しない', async () => {
  const fetch = fakeFetch(() => json({ error: 'bad' }, 400));
  await assert.rejects(
    provider(fetch).generateExperience(ctx(), null, collect().opts),
    (e) => e instanceof UpstreamError && e.status === 400 && !e.retryable,
  );
  assert.equal(fetch.calls.length, 1);
});

test('再試行回数を使い切ったら最後のエラーを返す', async () => {
  const fetch = fakeFetch(() => json({}, 500));
  await assert.rejects(client(fetch, 1).createMessage({ model: 'm', max_tokens: 1, system: '', messages: [] }, signal()), UpstreamError);
  assert.equal(fetch.calls.length, 2);
});

test('ネットワーク断・タイムアウト・中断を区別する', async () => {
  const down = fakeFetch(() => {
    throw new TypeError('fetch failed');
  });
  await assert.rejects(client(down, 0).createMessage({ model: 'm', max_tokens: 1, system: '', messages: [] }, signal()), (e) => e instanceof UpstreamError && e.kind === 'network');

  // AbortSignal.timeout のタイマーはイベントループを保持しないため、テスト中だけ別のタイマーで保持する
  const keepAlive = setTimeout(() => {}, 1000);
  const slow = fakeFetch(
    (call) =>
      new Promise<Response>((_, reject) => {
        call.init.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
      }),
  );
  await assert.rejects(client(slow, 0, 20).createMessage({ model: 'm', max_tokens: 1, system: '', messages: [] }, signal()), (e) => e instanceof UpstreamError && e.kind === 'timeout');

  const controller = new AbortController();
  controller.abort();
  await assert.rejects(client(slow, 2).createMessage({ model: 'm', max_tokens: 1, system: '', messages: [] }, controller.signal), (e) => e instanceof UpstreamError && e.kind === 'aborted');
  clearTimeout(keepAlive);
});

test('応答の形が違えば invalid_response、tool_use が無ければエラー', async () => {
  const notJson = fakeFetch(() => new Response('<html>', { status: 200 }));
  await assert.rejects(client(notJson, 0).createMessage({ model: 'm', max_tokens: 1, system: '', messages: [] }, signal()), (e) => e instanceof UpstreamError && e.kind === 'invalid_response');
  const noContent = fakeFetch(() => json({ hello: 1 }));
  await assert.rejects(client(noContent, 0).createMessage({ model: 'm', max_tokens: 1, system: '', messages: [] }, signal()), (e) => e instanceof UpstreamError && e.kind === 'invalid_response');
  const textOnly = fakeFetch(() => json({ content: [{ type: 'text', text: 'hi' }], usage: {} }));
  await assert.rejects(provider(textOnly).generateExperience(ctx(), null, collect().opts), UpstreamError);
});

test('Retry-After は秒数と日付の両方を解釈する', () => {
  assert.equal(parseRetryAfter('2'), 2000);
  assert.equal(parseRetryAfter(new Date(10_000).toUTCString(), 4_000), 6_000);
  assert.equal(parseRetryAfter('soon'), null);
  assert.equal(parseRetryAfter(null), null);
});

test('下調べ: 地域を user_location に渡し、検索しなければ null', async () => {
  const fetch = fakeFetch(() => json({ content: [{ type: 'text', text: 'NO_SEARCH_NEEDED' }], stop_reason: 'end_turn', usage: { input_tokens: 5, output_tokens: 2 } }));
  const { usages, opts } = collect();
  const out = await provider(fetch).research!(ctx(), opts);
  assert.equal(out, null);
  assert.equal(usages.length, 1);
  const body = fetch.calls[0]!.body;
  assert.equal(body.model, 'model-research');
  assert.deepEqual((body.tools as unknown[])[0], {
    type: 'web_search_20250305',
    name: 'web_search',
    max_uses: 2,
    user_location: { type: 'approximate', timezone: 'Asia/Tokyo', city: '堺市', region: '大阪府', country: 'JP' },
  });
  // 下調べには発言や予定のタイトルを渡さない
  const content = String((body.messages as Array<{ content: string }>)[0]?.content);
  assert.doesNotMatch(content, /数学の課題|疲れた/);
});

test('下調べ: pause_turn は受け取った内容を返して続け、引用を参照として取り出す', async () => {
  const first = {
    content: [
      { type: 'server_tool_use', id: 'srvtoolu_1', name: 'web_search', input: { query: '堺市 天気' } },
      { type: 'web_search_tool_result', tool_use_id: 'srvtoolu_1', content: [{ type: 'web_search_result', url: 'https://r.example', title: 'R' }] },
    ],
    stop_reason: 'pause_turn',
    usage: { input_tokens: 50, output_tokens: 10, server_tool_use: { web_search_requests: 1 } },
  };
  const second = {
    content: [{ type: 'text', text: '夕方から雨の予報です。', citations: [{ type: 'web_search_result_location', url: 'https://w.example', title: '天気予報' }] }],
    stop_reason: 'end_turn',
    usage: { input_tokens: 80, output_tokens: 20 },
  };
  const fetch = fakeFetch(() => json(first), () => json(second));
  const { usages, opts } = collect();
  const out = await provider(fetch).research!(ctx(), opts);
  assert.deepEqual(out, { summary: '夕方から雨の予報です。', references: [{ title: '天気予報', url: 'https://w.example' }], searches: 1 });
  assert.equal(usages.length, 2);
  const continued = fetch.calls[1]!.body.messages as Array<{ role: string; content: unknown }>;
  assert.equal(continued.at(-1)?.role, 'assistant');
  assert.deepEqual(continued.at(-1)?.content, first.content);
});

test('引用が無ければ検索結果の上位を参照にする / 地域なしでもタイムゾーンは渡す', () => {
  const r = extractResearch([
    { type: 'web_search_tool_result', content: [{ url: 'https://x.example', title: 'X' }] },
    { type: 'text', text: '要約' },
  ]);
  assert.deepEqual(r, { summary: '要約', references: [{ title: 'X', url: 'https://x.example' }] });
  const tool = webSearchTool({ ...ctx(), area: null }, 't', 1);
  assert.deepEqual(tool.user_location, { type: 'approximate', timezone: 'Asia/Tokyo' });
});

test('体験生成: 気分と体験の樹をデータとして渡し、振り返りの問いと要素を必須にする', async () => {
  const fetch = fakeFetch(() => toolResponse('propose_experience', { ok: true }));
  await provider(fetch).generateExperience(ctx(), null, collect().opts);
  const body = fetch.calls[0]!.body;
  const content = String((body.messages as Array<{ content: string }>)[0]?.content);
  const data = JSON.parse(content.split('<user_data>')[1]!.split('</user_data>')[0]!) as Record<string, unknown>;
  assert.equal(data.mood, 'tired');
  assert.equal(data.season, undefined);
  assert.deepEqual((data.tree as { lived: Array<{ id: string }> }).lived.map((l) => l.id), ['meal-first-bite', 'commute-sounds']);
  const tool = (body.tools as Array<{ input_schema: { properties: { experience: { required: string[] } } } }>)[0]!;
  assert.ok(tool.input_schema.properties.experience.required.includes('reflection_question'));
  assert.ok(tool.input_schema.properties.experience.required.includes('elements'));
  assert.match(String(body.system), /reflection_question/);
  assert.match(String(body.system), /grows_from/);
  assert.doesNotMatch(String(body.system), /七十二候/);
});

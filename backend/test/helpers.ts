import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { AiProvider } from '../src/ai/provider.ts';
import { createEngine, type EngineDependencies } from '../src/engine/engine.ts';
import { UsageBudget, type BudgetLimits, type UsageSnapshot, type UsageStore } from '../src/support/budget.ts';
import { ConcurrencyGate } from '../src/support/concurrency.ts';
import { silentLogger } from '../src/support/logger.ts';
import { CircuitBreaker } from '../src/support/resilience.ts';

const contractsDir = new URL('../../contracts/', import.meta.url);

export function fixture<T = Record<string, unknown>>(name: string): T {
  return JSON.parse(readFileSync(fileURLToPath(new URL(name, contractsDir)), 'utf8')) as T;
}

// ---- contracts/openapi.json のスキーマで値を検証する最小のバリデータ ----
// 対応: $ref, anyOf, type (配列可), enum, pattern, properties, required, additionalProperties:false, items, minItems, maxItems, minimum, maximum

type Schema = Record<string, unknown>;
const openapi = fixture<{ components: { schemas: Record<string, Schema> } }>('openapi.json');

function typeOf(v: unknown): string {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (typeof v === 'number') return Number.isInteger(v) ? 'integer' : 'number';
  return typeof v;
}

function check(schema: Schema, value: unknown, path: string, out: string[]): void {
  if (typeof schema.$ref === 'string') {
    const name = schema.$ref.replace('#/components/schemas/', '');
    const target = openapi.components.schemas[name];
    if (!target) return void out.push(`${path}: unknown $ref ${schema.$ref}`);
    return check(target, value, path, out);
  }
  if (Array.isArray(schema.anyOf)) {
    const ok = (schema.anyOf as Schema[]).some((s) => {
      const errs: string[] = [];
      check(s, value, path, errs);
      return errs.length === 0;
    });
    if (!ok) out.push(`${path}: anyOf に一致しません (${JSON.stringify(value)?.slice(0, 80)})`);
    return;
  }
  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? (schema.type as string[]) : [schema.type as string];
    const actual = typeOf(value);
    const ok = types.includes(actual) || (actual === 'integer' && types.includes('number'));
    if (!ok) return void out.push(`${path}: 型が ${types.join('|')} ではなく ${actual}`);
  }
  if (Array.isArray(schema.enum) && !schema.enum.includes(value)) out.push(`${path}: ${JSON.stringify(value)} は enum 外`);
  if (typeof value === 'string' && typeof schema.pattern === 'string' && !new RegExp(schema.pattern).test(value)) {
    out.push(`${path}: ${JSON.stringify(value)} は pattern に合いません`);
  }
  if (Array.isArray(value)) {
    if (typeof schema.minItems === 'number' && value.length < schema.minItems) out.push(`${path}: minItems 未満`);
    if (typeof schema.maxItems === 'number' && value.length > schema.maxItems) out.push(`${path}: maxItems 超過`);
  }
  if (typeof value === 'number') {
    if (typeof schema.minimum === 'number' && value < schema.minimum) out.push(`${path}: minimum 未満`);
    if (typeof schema.maximum === 'number' && value > schema.maximum) out.push(`${path}: maximum 超過`);
  }
  if (typeOf(value) === 'object') {
    const obj = value as Record<string, unknown>;
    const props = (schema.properties ?? {}) as Record<string, Schema>;
    for (const key of (schema.required ?? []) as string[]) if (!(key in obj)) out.push(`${path}.${key}: 必須です`);
    for (const [key, v] of Object.entries(obj)) {
      const p = props[key];
      if (p) check(p, v, `${path}.${key}`, out);
      else if (schema.additionalProperties === false) out.push(`${path}.${key}: 契約に無いキーです`);
    }
  }
  if (Array.isArray(value) && schema.items) value.forEach((v, i) => check(schema.items as Schema, v, `${path}[${i}]`, out));
}

export function contractErrors(schemaName: string, value: unknown): string[] {
  const out: string[] = [];
  check({ $ref: `#/components/schemas/${schemaName}` }, value, schemaName, out);
  return out;
}

// ---- テスト用の部品 ----

export class MemoryUsageStore implements UsageStore {
  snapshot: UsageSnapshot | null = null;
  saves = 0;
  async load() {
    return this.snapshot;
  }
  async save(s: UsageSnapshot) {
    this.saves += 1;
    this.snapshot = { ...s };
  }
}

export const generousLimits: BudgetLimits = { dailyRequests: 1000, dailyTokens: 10_000_000, dailyWebSearches: 100 };

export async function makeBudget(limits: Partial<BudgetLimits> = {}, now = () => new Date('2026-10-08T09:00:00Z')) {
  return UsageBudget.create({ limits: { ...generousLimits, ...limits }, timeZone: 'Asia/Tokyo', now });
}

export async function makeEngine(overrides: Partial<EngineDependencies> & { provider: AiProvider }) {
  return createEngine({
    fallback: null,
    budget: await makeBudget(),
    breaker: new CircuitBreaker({ failureThreshold: 3, cooldownMs: 60_000 }),
    gate: new ConcurrencyGate(4),
    webSearchEnabled: false,
    logger: silentLogger,
    ...overrides,
  });
}

export const signal = () => new AbortController().signal;

export interface FakeCall {
  url: string;
  init: RequestInit;
  body: Record<string, unknown>;
}

/** fetch の代わり。responder が返した値 (Response か throw) を順番に返す */
export function fakeFetch(...responders: Array<(call: FakeCall) => Response | Promise<Response>>) {
  const calls: FakeCall[] = [];
  const fn = (async (url: string | URL | Request, init?: RequestInit) => {
    const call: FakeCall = { url: String(url), init: init ?? {}, body: JSON.parse(String(init?.body ?? '{}')) };
    calls.push(call);
    const responder = responders[Math.min(calls.length - 1, responders.length - 1)];
    if (!responder) throw new Error('no responder');
    return responder(call);
  }) as typeof fetch & { calls: FakeCall[] };
  fn.calls = calls;
  return fn;
}

export const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...headers } });

export const toolResponse = (name: string, input: unknown, usage = { input_tokens: 100, output_tokens: 50 }) =>
  json({ content: [{ type: 'tool_use', id: 'toolu_1', name, input }], stop_reason: 'tool_use', usage });

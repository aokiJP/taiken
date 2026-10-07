// 体験生成の中心。予算・遮断器・同時実行数を確認してからAIを呼び、
// 出力を正規化・安全確認し、使えないときはモックの代替生成に切り替える。
import { UpstreamError } from '../ai/anthropicClient.ts';
import type { AiProvider, CallOptions } from '../ai/provider.ts';
import type { UsageBudget } from '../support/budget.ts';
import type { ConcurrencyGate } from '../support/concurrency.ts';
import { silentLogger, type Logger } from '../support/logger.ts';
import type { CircuitBreaker } from '../support/resilience.ts';
import { applyNotificationPolicy } from './notificationPolicy.ts';
import { detectCareNeed, findSafetyIssue } from './safety.ts';
import { normalizeChatResult, normalizeExperienceResult, SchemaError } from './schema.ts';
import type {
  ChatContext,
  ChatResult,
  ExperienceContext,
  ExperienceResult,
  FallbackReason,
  ResearchResult,
  Usage,
} from './types.ts';

/** AIが使えず、代替生成もできない (FALLBACK_TO_MOCK=false) ときに投げる */
export class UnavailableError extends Error {
  readonly reason: FallbackReason;
  constructor(reason: FallbackReason) {
    super(`AIを利用できません (${reason})`);
    this.name = 'UnavailableError';
    this.reason = reason;
  }
}

class UnsafeOutputError extends Error {
  constructor(label: string) {
    super(`安全基準に合わない提案: ${label}`);
    this.name = 'UnsafeOutputError';
  }
}

export interface EngineDependencies {
  provider: AiProvider;
  /** 代替生成器 (通常はモック)。null ならエラーを返す */
  fallback: AiProvider | null;
  budget: UsageBudget;
  breaker: CircuitBreaker;
  gate: ConcurrencyGate;
  webSearchEnabled: boolean;
  logger?: Logger;
}

export interface RequestOptions {
  signal: AbortSignal;
  logger?: Logger;
}

export interface Engine {
  generateExperience(ctx: ExperienceContext, options: RequestOptions): Promise<ExperienceResult>;
  chat(ctx: ChatContext, options: RequestOptions): Promise<ChatResult>;
}

function reasonOf(error: unknown): FallbackReason {
  if (error instanceof UnsafeOutputError) return 'unsafe_output';
  if (error instanceof SchemaError) return 'invalid_output';
  return 'upstream_error';
}

export function createEngine(deps: EngineDependencies): Engine {
  const baseLogger = deps.logger ?? silentLogger;
  const isMock = deps.provider.name === 'mock';

  const callOptions = (signal: AbortSignal): CallOptions => ({
    signal,
    onUsage: (usage: Usage) => deps.budget.record(usage),
  });

  /** AIを呼んでよいか。だめなら理由を返す。よければ解放関数を返す */
  function admit(): { release: () => void } | { reason: FallbackReason } {
    if (!deps.budget.canUseAi()) return { reason: 'budget_exceeded' };
    const release = deps.gate.tryAcquire();
    if (!release) return { reason: 'busy' };
    if (!deps.breaker.tryAcquire()) {
      release();
      return { reason: 'circuit_open' };
    }
    return { release };
  }

  async function run<T extends { source: string; fallback_reason: FallbackReason | null }>(
    kind: 'experience' | 'chat',
    primary: () => Promise<T>,
    fallback: () => Promise<T>,
    options: RequestOptions,
  ): Promise<T> {
    const log = options.logger ?? baseLogger;
    if (isMock) return primary();

    const admission = admit();
    let reason: FallbackReason;
    if ('release' in admission) {
      try {
        const result = await primary();
        deps.breaker.recordSuccess();
        return result;
      } catch (error) {
        if (error instanceof UpstreamError && error.kind === 'aborted') {
          deps.breaker.recordSuccess(); // クライアント側の中断は上流の故障ではない
          throw error;
        }
        // 上流が応答した (=生きている) 場合は遮断器を開かない
        if (error instanceof UpstreamError) deps.breaker.recordFailure();
        else deps.breaker.recordSuccess();
        reason = reasonOf(error);
        log.warn('engine.primary_failed', { kind, reason, error: (error as Error).name });
      } finally {
        admission.release();
      }
    } else {
      reason = admission.reason;
      log.warn('engine.skipped_ai', { kind, reason });
    }

    if (!deps.fallback) throw new UnavailableError(reason);
    const result = await fallback();
    return { ...result, source: 'fallback', fallback_reason: reason };
  }

  async function research(ctx: ExperienceContext, options: RequestOptions): Promise<ResearchResult | null> {
    if (!ctx.allow_web_search || !deps.webSearchEnabled || !deps.provider.research) return null;
    if (!deps.budget.canUseWebSearch()) return null;
    try {
      const result = await deps.provider.research(ctx, callOptions(options.signal));
      (options.logger ?? baseLogger).info('engine.research', { searches: result?.searches ?? 0 });
      return result;
    } catch (error) {
      // 下調べの失敗は致命的ではない。外部情報なしで体験生成を続ける
      if (error instanceof UpstreamError && error.kind === 'aborted') throw error;
      (options.logger ?? baseLogger).warn('engine.research_failed', { error: (error as Error).name });
      return null;
    }
  }

  async function produceExperience(provider: AiProvider, ctx: ExperienceContext, options: RequestOptions, withResearch: boolean) {
    const found = withResearch ? await research(ctx, options) : null;
    const raw = await provider.generateExperience(ctx, found, callOptions(options.signal));
    const result = normalizeExperienceResult(raw, provider.name === 'mock' ? 'mock' : 'ai');
    const issue = findSafetyIssue(result.experience);
    if (issue) throw new UnsafeOutputError(issue);
    return { ...result, references: found?.references ?? [] };
  }

  async function produceChat(provider: AiProvider, ctx: ChatContext, options: RequestOptions) {
    const raw = await provider.chat(ctx, callOptions(options.signal));
    const result = normalizeChatResult(raw, provider.name === 'mock' ? 'mock' : 'ai');
    if (result.experience) {
      const issue = findSafetyIssue(result.experience);
      if (issue) throw new UnsafeOutputError(issue);
    }
    return result;
  }

  return {
    async generateExperience(ctx, options) {
      const result = await run(
        'experience',
        () => produceExperience(deps.provider, ctx, options, true),
        () => produceExperience(deps.fallback as AiProvider, ctx, options, false),
        options,
      );
      return applyNotificationPolicy(result, ctx);
    },

    async chat(ctx, options) {
      const result = await run(
        'chat',
        () => produceChat(deps.provider, ctx, options),
        () => produceChat(deps.fallback as AiProvider, ctx, options),
        options,
      );
      // AIの判断に加えて、直近の発言を機械的にも確認する。苦痛のサインがあれば体験の提案は出さない
      const recentUserTexts = ctx.messages.filter((m) => m.role === 'user').slice(-3).map((m) => m.text);
      if (result.needs_care || detectCareNeed(recentUserTexts)) {
        return { ...result, needs_care: true, suggest_experience: false, experience: null };
      }
      return result;
    },
  };
}

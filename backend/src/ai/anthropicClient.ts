// Anthropic Messages API の薄いクライアント。タイムアウト・再試行・エラー分類をここに閉じ込める。
// APIキーはこのモジュールの外へ出さず、エラー本文 (入力内容を含み得る) もログに残さない。
import { retry, type Sleep } from '../support/resilience.ts';
import { silentLogger, type Logger } from '../support/logger.ts';

export type UpstreamErrorKind = 'timeout' | 'network' | 'http' | 'invalid_response' | 'aborted';

export class UpstreamError extends Error {
  readonly kind: UpstreamErrorKind;
  readonly status: number | null;
  readonly retryable: boolean;
  readonly retryAfterMs: number | null;

  constructor(
    message: string,
    init: { kind: UpstreamErrorKind; status?: number | null; retryable?: boolean; retryAfterMs?: number | null },
  ) {
    super(message);
    this.name = 'UpstreamError';
    this.kind = init.kind;
    this.status = init.status ?? null;
    this.retryable = init.retryable ?? false;
    this.retryAfterMs = init.retryAfterMs ?? null;
  }
}

export interface ContentBlock {
  type: string;
  [key: string]: unknown;
}

export interface MessageResponse {
  content: ContentBlock[];
  stop_reason: string | null;
  usage: {
    input_tokens?: number;
    output_tokens?: number;
    server_tool_use?: { web_search_requests?: number };
  };
}

export interface MessageRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: { role: 'user' | 'assistant'; content: string | ContentBlock[] }[];
  tools?: Record<string, unknown>[];
  tool_choice?: Record<string, unknown>;
}

export interface AnthropicClientOptions {
  apiKey: string;
  baseUrl: string;
  timeoutMs: number;
  maxRetries: number;
  fetch?: typeof fetch;
  sleep?: Sleep;
  random?: () => number;
  logger?: Logger;
}

export function parseRetryAfter(value: string | null, now = Date.now()): number | null {
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return Math.round(seconds * 1000);
  const at = Date.parse(value);
  return Number.isNaN(at) ? null : Math.max(0, at - now);
}

const API_VERSION = '2023-06-01';

export class AnthropicClient {
  readonly #options: AnthropicClientOptions;
  readonly #fetch: typeof fetch;
  readonly #logger: Logger;

  constructor(options: AnthropicClientOptions) {
    this.#options = options;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#logger = options.logger ?? silentLogger;
  }

  async createMessage(body: MessageRequest, signal: AbortSignal): Promise<MessageResponse> {
    return retry((attempt) => this.#once(body, signal, attempt), {
      retries: this.#options.maxRetries,
      baseDelayMs: 500,
      maxDelayMs: 8_000,
      shouldRetry: (e) => e instanceof UpstreamError && e.retryable,
      retryAfterMs: (e) => (e instanceof UpstreamError ? e.retryAfterMs : null),
      signal,
      ...(this.#options.sleep ? { sleep: this.#options.sleep } : {}),
      ...(this.#options.random ? { random: this.#options.random } : {}),
      onRetry: (attempt, delayMs, e) =>
        this.#logger.warn('ai.retry', {
          attempt,
          delay_ms: delayMs,
          kind: e instanceof UpstreamError ? e.kind : 'unknown',
          status: e instanceof UpstreamError ? e.status : null,
        }),
    });
  }

  async #once(body: MessageRequest, outer: AbortSignal, attempt: number): Promise<MessageResponse> {
    if (outer.aborted) throw new UpstreamError('リクエストが中断されました', { kind: 'aborted' });
    const timeout = AbortSignal.timeout(this.#options.timeoutMs);
    const signal = AbortSignal.any([outer, timeout]);
    const started = Date.now();

    let res: Response;
    try {
      res = await this.#fetch(`${this.#options.baseUrl}/v1/messages`, {
        method: 'POST',
        signal,
        headers: {
          'content-type': 'application/json',
          'x-api-key': this.#options.apiKey,
          'anthropic-version': API_VERSION,
        },
        body: JSON.stringify(body),
      });
    } catch {
      if (outer.aborted) throw new UpstreamError('リクエストが中断されました', { kind: 'aborted' });
      if (timeout.aborted) throw new UpstreamError('AI APIがタイムアウトしました', { kind: 'timeout', retryable: true });
      throw new UpstreamError('AI APIに接続できません', { kind: 'network', retryable: true });
    }

    this.#logger.debug('ai.response', { model: body.model, status: res.status, attempt, ms: Date.now() - started });

    if (!res.ok) {
      // 本文は読み捨てる (入力内容が含まれ得るため、ログにも残さない)
      await res.body?.cancel().catch(() => {});
      const retryable = res.status === 408 || res.status === 409 || res.status === 429 || res.status >= 500;
      throw new UpstreamError(`AI APIがエラーを返しました (${res.status})`, {
        kind: 'http',
        status: res.status,
        retryable,
        retryAfterMs: parseRetryAfter(res.headers.get('retry-after')),
      });
    }

    let data: unknown;
    try {
      data = await res.json();
    } catch {
      throw new UpstreamError('AI APIの応答を読み取れません', { kind: 'invalid_response' });
    }
    if (typeof data !== 'object' || data === null || !Array.isArray((data as MessageResponse).content)) {
      throw new UpstreamError('AI APIの応答形式が想定と違います', { kind: 'invalid_response' });
    }
    const msg = data as Partial<MessageResponse>;
    return {
      content: msg.content as ContentBlock[],
      stop_reason: typeof msg.stop_reason === 'string' ? msg.stop_reason : null,
      usage: typeof msg.usage === 'object' && msg.usage !== null ? msg.usage : {},
    };
  }
}

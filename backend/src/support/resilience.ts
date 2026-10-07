// 再試行 (指数バックオフ + ジッター) とサーキットブレーカー。

export type Sleep = (ms: number, signal?: AbortSignal) => Promise<void>;

export const sleep: Sleep = (ms, signal) =>
  new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal?.reason);
    };
    signal?.addEventListener('abort', onAbort, { once: true });
  });

export interface RetryOptions {
  /** 最初の試行を含まない再試行回数 */
  retries: number;
  baseDelayMs: number;
  maxDelayMs: number;
  shouldRetry: (error: unknown) => boolean;
  /** エラーが待ち時間を指定している場合 (Retry-After) はそれを優先する */
  retryAfterMs?: (error: unknown) => number | null;
  sleep?: Sleep;
  random?: () => number;
  signal?: AbortSignal;
  onRetry?: (attempt: number, delayMs: number, error: unknown) => void;
}

export async function retry<T>(fn: (attempt: number) => Promise<T>, options: RetryOptions): Promise<T> {
  const wait = options.sleep ?? sleep;
  const random = options.random ?? Math.random;
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn(attempt);
    } catch (error) {
      if (attempt >= options.retries || !options.shouldRetry(error) || options.signal?.aborted) throw error;
      const hinted = options.retryAfterMs?.(error) ?? null;
      const exp = Math.min(options.maxDelayMs, options.baseDelayMs * 2 ** attempt);
      // full jitter: 0.5〜1.0倍 (同時再試行の集中を避ける)
      const delay = hinted !== null ? Math.min(options.maxDelayMs, hinted) : Math.round(exp * (0.5 + random() / 2));
      options.onRetry?.(attempt + 1, delay, error);
      await wait(delay, options.signal);
    }
  }
}

export type BreakerState = 'closed' | 'open' | 'half_open';

export interface CircuitBreakerOptions {
  failureThreshold: number;
  cooldownMs: number;
  now?: () => number;
}

/**
 * 上流 (AI API) が落ちているときに呼び続けないための遮断器。
 * 連続失敗が閾値に達すると open になり、cooldown の間は即座に失敗させる (=フォールバックへ)。
 * cooldown 後は1回だけ試し (half_open)、成功すれば closed に戻る。
 */
export class CircuitBreaker {
  #failures = 0;
  #openedAt = 0;
  #state: BreakerState = 'closed';
  #probeInFlight = false;
  readonly #options: Required<CircuitBreakerOptions>;

  constructor(options: CircuitBreakerOptions) {
    this.#options = { now: () => Date.now(), ...options };
  }

  get state(): BreakerState {
    if (this.#state === 'open' && this.#options.now() - this.#openedAt >= this.#options.cooldownMs) {
      this.#state = 'half_open';
    }
    return this.#state;
  }

  /** 今呼んでよいか。half_open では1件だけ通す */
  tryAcquire(): boolean {
    const s = this.state;
    if (s === 'closed') return true;
    if (s === 'half_open' && !this.#probeInFlight) {
      this.#probeInFlight = true;
      return true;
    }
    return false;
  }

  recordSuccess(): void {
    this.#failures = 0;
    this.#state = 'closed';
    this.#probeInFlight = false;
  }

  recordFailure(): void {
    this.#probeInFlight = false;
    this.#failures += 1;
    if (this.#state === 'half_open' || this.#failures >= this.#options.failureThreshold) {
      this.#state = 'open';
      this.#openedAt = this.#options.now();
    }
  }
}

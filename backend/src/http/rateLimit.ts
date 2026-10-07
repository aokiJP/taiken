// トークンバケット方式のレート制御 (単一プロセス向け)。
// 個人利用なので1インスタンス前提。複数インスタンスにする場合はRedis等の共有ストアへ置き換える。

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds: number;
}

interface Bucket {
  tokens: number;
  updatedAt: number;
}

export class RateLimiter {
  readonly #burst: number;
  readonly #refillPerMs: number;
  readonly #now: () => number;
  readonly #buckets = new Map<string, Bucket>();
  readonly #maxKeys: number;

  constructor(options: { burst: number; perMinute: number; now?: () => number; maxKeys?: number }) {
    this.#burst = options.burst;
    this.#refillPerMs = options.perMinute / 60_000;
    this.#now = options.now ?? (() => Date.now());
    this.#maxKeys = options.maxKeys ?? 10_000;
  }

  take(key: string): RateLimitResult {
    const now = this.#now();
    let bucket = this.#buckets.get(key);
    if (!bucket) {
      if (this.#buckets.size >= this.#maxKeys) this.#evictFull(now);
      bucket = { tokens: this.#burst, updatedAt: now };
      this.#buckets.set(key, bucket);
    }
    bucket.tokens = Math.min(this.#burst, bucket.tokens + (now - bucket.updatedAt) * this.#refillPerMs);
    bucket.updatedAt = now;

    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return { allowed: true, retryAfterSeconds: 0 };
    }
    return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((1 - bucket.tokens) / this.#refillPerMs / 1000)) };
  }

  // 満タンに戻ったバケットは消しても挙動が変わらないので、メモリを空ける
  #evictFull(now: number): void {
    for (const [key, b] of this.#buckets) {
      if (b.tokens + (now - b.updatedAt) * this.#refillPerMs >= this.#burst) this.#buckets.delete(key);
    }
  }
}

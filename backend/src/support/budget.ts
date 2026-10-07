// 1日あたりのAI利用量の上限。個人利用で「気づいたら請求が膨らんでいた」を防ぐ。
// 上限に達したらAIを呼ばず、モックの代替生成に切り替える (アプリは動き続ける)。
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { Usage } from '../engine/types.ts';
import { silentLogger, type Logger } from './logger.ts';

export interface BudgetLimits {
  dailyRequests: number;
  dailyTokens: number;
  dailyWebSearches: number;
}

export interface UsageSnapshot {
  date: string;
  requests: number;
  tokens: number;
  webSearches: number;
}

export interface UsageStore {
  load(): Promise<UsageSnapshot | null>;
  save(snapshot: UsageSnapshot): Promise<void>;
}

export interface BudgetRemaining {
  requests: number;
  tokens: number;
  webSearches: number;
  resetsAt: string;
}

export function dateKey(date: Date, timeZone: string): string {
  // en-CA は YYYY-MM-DD 形式
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

function utcOffset(date: Date, timeZone: string): string {
  const part = new Intl.DateTimeFormat('en-US', { timeZone, timeZoneName: 'longOffset' })
    .formatToParts(date)
    .find((p) => p.type === 'timeZoneName')?.value;
  const m = part ? /GMT([+-]\d{2}:\d{2})/.exec(part) : null;
  return m?.[1] ?? '+00:00';
}

const offsetMinutes = (offset: string): number => {
  const sign = offset.startsWith('-') ? -1 : 1;
  const [h, m] = offset.slice(1).split(':').map(Number) as [number, number];
  return sign * (h * 60 + m);
};

/** 指定タイムゾーンでの「次の0時」(ISO 8601, オフセット付き)。夏時間の切り替わり日も考慮する */
export function nextMidnight(date: Date, timeZone: string): string {
  const [y, m, d] = dateKey(date, timeZone).split('-').map(Number) as [number, number, number];
  const midnightUtc = Date.UTC(y, m - 1, d + 1);
  // 翌日正午のオフセットで仮の瞬間を求め、その瞬間のオフセットで確定する
  const guess = offsetMinutes(utcOffset(new Date(midnightUtc + 12 * 3_600_000), timeZone));
  const offset = utcOffset(new Date(midnightUtc - guess * 60_000), timeZone);
  return `${new Date(midnightUtc).toISOString().slice(0, 10)}T00:00:00${offset}`;
}

export class UsageBudget {
  readonly #limits: BudgetLimits;
  readonly #timeZone: string;
  readonly #now: () => Date;
  readonly #store: UsageStore | null;
  readonly #logger: Logger;
  #usage: UsageSnapshot;
  #pendingSave: Promise<void> = Promise.resolve();

  private constructor(limits: BudgetLimits, timeZone: string, now: () => Date, store: UsageStore | null, logger: Logger, initial: UsageSnapshot | null) {
    this.#limits = limits;
    this.#timeZone = timeZone;
    this.#now = now;
    this.#store = store;
    this.#logger = logger;
    this.#usage = initial ?? this.#empty();
  }

  static async create(options: {
    limits: BudgetLimits;
    timeZone: string;
    now?: () => Date;
    store?: UsageStore | null;
    logger?: Logger;
  }): Promise<UsageBudget> {
    const logger = options.logger ?? silentLogger;
    let initial: UsageSnapshot | null = null;
    try {
      initial = (await options.store?.load()) ?? null;
    } catch (error) {
      logger.warn('budget.load_failed', { error: (error as Error).name });
    }
    return new UsageBudget(options.limits, options.timeZone, options.now ?? (() => new Date()), options.store ?? null, logger, initial);
  }

  #empty(): UsageSnapshot {
    return { date: dateKey(this.#now(), this.#timeZone), requests: 0, tokens: 0, webSearches: 0 };
  }

  #current(): UsageSnapshot {
    const today = dateKey(this.#now(), this.#timeZone);
    if (this.#usage.date !== today) this.#usage = this.#empty();
    return this.#usage;
  }

  canUseAi(): boolean {
    const u = this.#current();
    return u.requests < this.#limits.dailyRequests && u.tokens < this.#limits.dailyTokens;
  }

  canUseWebSearch(): boolean {
    return this.canUseAi() && this.#current().webSearches < this.#limits.dailyWebSearches;
  }

  record(usage: Usage): void {
    const u = this.#current();
    u.requests += 1;
    u.tokens += Math.max(0, usage.inputTokens) + Math.max(0, usage.outputTokens);
    u.webSearches += Math.max(0, usage.webSearches);
    this.#persist();
  }

  remaining(): BudgetRemaining {
    const u = this.#current();
    return {
      requests: Math.max(0, this.#limits.dailyRequests - u.requests),
      tokens: Math.max(0, this.#limits.dailyTokens - u.tokens),
      webSearches: Math.max(0, this.#limits.dailyWebSearches - u.webSearches),
      resetsAt: nextMidnight(this.#now(), this.#timeZone),
    };
  }

  /** テスト・シャットダウン用: 保留中の保存を待つ */
  flush(): Promise<void> {
    return this.#pendingSave;
  }

  #persist(): void {
    if (!this.#store) return;
    const snapshot = { ...this.#usage };
    const store = this.#store;
    // 書き込みを直列化して、古い値で上書きしないようにする
    this.#pendingSave = this.#pendingSave
      .then(() => store.save(snapshot))
      .catch((error: unknown) => this.#logger.warn('budget.save_failed', { error: (error as Error).name }));
  }
}

/** DATA_DIR/usage.json に保存する。一時ファイルに書いてから rename するので、途中で落ちても壊れない */
export class FileUsageStore implements UsageStore {
  readonly #path: string;
  constructor(path: string) {
    this.#path = path;
  }

  async load(): Promise<UsageSnapshot | null> {
    try {
      const data: unknown = JSON.parse(await readFile(this.#path, 'utf8'));
      if (
        typeof data === 'object' && data !== null &&
        typeof (data as UsageSnapshot).date === 'string' &&
        Number.isFinite((data as UsageSnapshot).requests) &&
        Number.isFinite((data as UsageSnapshot).tokens) &&
        Number.isFinite((data as UsageSnapshot).webSearches)
      ) {
        const d = data as UsageSnapshot;
        return { date: d.date, requests: d.requests, tokens: d.tokens, webSearches: d.webSearches };
      }
      return null;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw error;
    }
  }

  async save(snapshot: UsageSnapshot): Promise<void> {
    await mkdir(dirname(this.#path), { recursive: true });
    const tmp = `${this.#path}.${process.pid}.tmp`;
    await writeFile(tmp, JSON.stringify(snapshot), { mode: 0o600 });
    await rename(tmp, this.#path);
  }
}

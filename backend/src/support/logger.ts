// 構造化ログ (JSON Lines)。
// 方針: ユーザーの内容 (予定・発言・体験文) は一切ログに出さない。
// 出してよいのは、ID・ステータス・所要時間・エラーの種類・件数などのメタデータだけ。

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';
export type LogFields = Record<string, string | number | boolean | null | undefined>;

const ORDER: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

// 万一これらのキーが渡されても値は出力しない
const REDACTED_KEYS = /token|key|secret|authorization|password|text|message_body|title|invitation|content/i;

export interface Logger {
  debug(msg: string, fields?: LogFields): void;
  info(msg: string, fields?: LogFields): void;
  warn(msg: string, fields?: LogFields): void;
  error(msg: string, fields?: LogFields): void;
  child(fields: LogFields): Logger;
}

export interface LoggerOptions {
  level?: LogLevel;
  base?: LogFields;
  write?: (line: string) => void;
  now?: () => Date;
}

export function redact(fields: LogFields): LogFields {
  const out: LogFields = {};
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined) continue;
    out[k] = REDACTED_KEYS.test(k) ? '[redacted]' : v;
  }
  return out;
}

export function createLogger(options: LoggerOptions = {}): Logger {
  const min = ORDER[options.level ?? 'info'];
  const write = options.write ?? ((line: string) => process.stdout.write(`${line}\n`));
  const now = options.now ?? (() => new Date());
  const base = options.base ?? {};

  const emit = (level: LogLevel, msg: string, fields: LogFields = {}) => {
    if (ORDER[level] < min) return;
    write(JSON.stringify({ ts: now().toISOString(), level, msg, ...redact({ ...base, ...fields }) }));
  };

  return {
    debug: (m, f) => emit('debug', m, f),
    info: (m, f) => emit('info', m, f),
    warn: (m, f) => emit('warn', m, f),
    error: (m, f) => emit('error', m, f),
    child: (fields) => createLogger({ ...options, base: { ...base, ...fields } }),
  };
}

export const silentLogger: Logger = {
  debug() {},
  info() {},
  warn() {},
  error() {},
  child() {
    return silentLogger;
  },
};

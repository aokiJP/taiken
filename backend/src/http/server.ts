import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import { UpstreamError } from '../ai/anthropicClient.ts';
import { APP_VERSION, type Config } from '../config.ts';
import { UnavailableError, type Engine } from '../engine/engine.ts';
import { InputError, sanitizeChatRequest, sanitizeExperienceRequest } from '../engine/sanitize.ts';
import type { UsageBudget } from '../support/budget.ts';
import type { Logger } from '../support/logger.ts';
import { errors, HttpError } from './errors.ts';
import { RateLimiter } from './rateLimit.ts';

export interface ServerDependencies {
  config: Config;
  engine: Engine;
  budget: UsageBudget;
  logger: Logger;
}

interface RequestState {
  id: string;
  signal: AbortSignal;
  logger: Logger;
  /** アクセスログに残す追加情報 (内容は含めない) */
  meta: Record<string, string | number | boolean | null>;
}

type Handler = (req: IncomingMessage, state: RequestState) => Promise<unknown>;

interface Route {
  method: 'GET' | 'POST';
  auth: boolean;
  handler: Handler;
}

const REQUEST_ID = /^[A-Za-z0-9._-]{8,64}$/;
const digest = (value: string) => createHash('sha256').update(value).digest();

export function tokenMatches(given: string, accepted: readonly string[]): boolean {
  const g = digest(given);
  // 全トークンと比較してから結果を返す (一致位置による時間差を出さない)
  let ok = false;
  for (const token of accepted) ok = timingSafeEqual(g, digest(token)) || ok;
  return ok;
}

async function readJson(req: IncomingMessage, maxBytes: number): Promise<unknown> {
  const type = req.headers['content-type'] ?? '';
  if (!/^application\/json(\s*;|$)/i.test(type)) throw errors.unsupportedMediaType();
  const declared = Number(req.headers['content-length']);
  if (Number.isFinite(declared) && declared > maxBytes) throw errors.payloadTooLarge();

  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    const buf = chunk as Buffer;
    size += buf.length;
    if (size > maxBytes) throw errors.payloadTooLarge();
    chunks.push(buf);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw errors.badRequest('JSONを解釈できません。');
  }
}

export function createApp(deps: ServerDependencies): http.Server {
  const { config, engine, budget } = deps;
  const limiter = new RateLimiter(config.rateLimit);

  const securityHeaders: Record<string, string> = {
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'content-security-policy': "default-src 'none'; frame-ancestors 'none'",
    ...(config.env === 'production' ? { 'strict-transport-security': 'max-age=31536000' } : {}),
  };

  const routes: Record<string, Route> = {
    '/health': { method: 'GET', auth: false, handler: async () => ({ status: 'ok' }) },
    '/v1/status': {
      method: 'GET',
      auth: true,
      handler: async () => {
        const r = budget.remaining();
        return {
          status: 'ok',
          version: APP_VERSION,
          provider: config.provider,
          features: { web_search: config.provider === 'anthropic' && config.webSearch.enabled },
          budget: {
            requests_remaining: r.requests,
            tokens_remaining: r.tokens,
            web_searches_remaining: r.webSearches,
            resets_at: r.resetsAt,
          },
        };
      },
    },
    '/v1/experience': {
      method: 'POST',
      auth: true,
      handler: async (req, state) => {
        const ctx = sanitizeExperienceRequest(await readJson(req, config.maxBodyBytes));
        const result = await engine.generateExperience(ctx, { signal: state.signal, logger: state.logger });
        state.meta.source = result.source;
        state.meta.fallback_reason = result.fallback_reason;
        state.meta.notify = result.should_notify;
        state.meta.references = result.references.length;
        return result;
      },
    },
    '/v1/chat': {
      method: 'POST',
      auth: true,
      handler: async (req, state) => {
        const ctx = sanitizeChatRequest(await readJson(req, config.maxBodyBytes));
        const result = await engine.chat(ctx, { signal: state.signal, logger: state.logger });
        state.meta.source = result.source;
        state.meta.fallback_reason = result.fallback_reason;
        state.meta.needs_care = result.needs_care;
        return result;
      },
    },
  };

  function send(res: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}) {
    if (res.headersSent || res.destroyed) return;
    const payload = JSON.stringify(body);
    res.writeHead(status, {
      ...securityHeaders,
      'content-type': 'application/json; charset=utf-8',
      'content-length': String(Buffer.byteLength(payload)),
      ...headers,
    });
    res.end(payload);
  }

  function toHttpError(error: unknown, state: RequestState): HttpError {
    if (error instanceof HttpError) return error;
    if (error instanceof InputError) return errors.badRequest(error.message);
    if (error instanceof UnavailableError) {
      return error.reason === 'busy'
        ? new HttpError(503, 'busy', '混み合っています。少し時間をおいてから試してください。', { retryAfterSeconds: 5 })
        : errors.unavailable();
    }
    if (error instanceof UpstreamError) return errors.unavailable();
    state.logger.error('http.unhandled', { error: (error as Error)?.name ?? 'unknown' });
    return errors.internal();
  }

  const server = http.createServer(async (req, res) => {
    const started = performance.now();
    const incomingId = req.headers['x-request-id'];
    const id = typeof incomingId === 'string' && REQUEST_ID.test(incomingId) ? incomingId : randomUUID();
    const path = (req.url ?? '/').split('?')[0] ?? '/';

    // 締め切り、またはクライアント切断で処理を打ち切る
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(new Error('deadline')), config.requestDeadlineMs);
    res.on('close', () => {
      clearTimeout(deadline);
      if (!res.writableFinished) controller.abort(new Error('client_closed'));
    });

    const state: RequestState = {
      id,
      signal: controller.signal,
      logger: deps.logger.child({ request_id: id }),
      meta: {},
    };

    try {
      const route = routes[path];
      if (!route) throw errors.notFound();
      if (req.method !== route.method) throw errors.methodNotAllowed([route.method]);

      if (route.auth) {
        const auth = req.headers.authorization ?? '';
        const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
        if (config.clientTokens.length && !tokenMatches(token, config.clientTokens)) throw errors.unauthorized();

        // 識別キーにトークンそのものは使わない (メモリ上にも平文を残さない)
        const installId = req.headers['x-install-id'];
        const key = token
          ? `t:${digest(token).toString('hex').slice(0, 16)}`
          : typeof installId === 'string' && installId
            ? `i:${installId.slice(0, 64)}`
            : `a:${req.socket.remoteAddress ?? 'unknown'}`;
        const rl = limiter.take(key);
        if (!rl.allowed) throw errors.rateLimited(rl.retryAfterSeconds);
      }

      const body = await route.handler(req, state);
      send(res, 200, body, { 'x-request-id': id });
    } catch (error) {
      const httpError = toHttpError(error, state);
      send(
        res,
        httpError.status,
        {
          error: {
            code: httpError.code,
            message: httpError.message,
            ...(httpError.retryAfterSeconds ? { retry_after_seconds: httpError.retryAfterSeconds } : {}),
            request_id: id,
          },
        },
        {
          'x-request-id': id,
          ...httpError.headers,
          ...(httpError.retryAfterSeconds ? { 'retry-after': String(httpError.retryAfterSeconds) } : {}),
        },
      );
    } finally {
      clearTimeout(deadline);
      // 個人の内容は残さない。メソッド・パス・ステータス・時間・生成元のみ。
      state.logger.info('http.request', {
        method: req.method ?? '',
        path: path in routes ? path : '(unknown)',
        status: res.statusCode,
        ms: Math.round(performance.now() - started),
        ...state.meta,
      });
    }
  });

  server.requestTimeout = config.requestDeadlineMs + 10_000;
  server.headersTimeout = 15_000;
  server.keepAliveTimeout = 5_000;
  return server;
}

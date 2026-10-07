export type ErrorCode =
  | 'bad_request'
  | 'unauthorized'
  | 'not_found'
  | 'method_not_allowed'
  | 'payload_too_large'
  | 'unsupported_media_type'
  | 'rate_limited'
  | 'busy'
  | 'upstream_unavailable'
  | 'internal';

export class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly retryAfterSeconds: number | null;
  readonly headers: Record<string, string>;

  constructor(
    status: number,
    code: ErrorCode,
    message: string,
    init: { retryAfterSeconds?: number; headers?: Record<string, string> } = {},
  ) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
    this.retryAfterSeconds = init.retryAfterSeconds ?? null;
    this.headers = init.headers ?? {};
  }
}

export const errors = {
  badRequest: (message: string) => new HttpError(400, 'bad_request', message),
  unauthorized: () => new HttpError(401, 'unauthorized', '認証に失敗しました。', { headers: { 'www-authenticate': 'Bearer' } }),
  notFound: () => new HttpError(404, 'not_found', '存在しないエンドポイントです。'),
  methodNotAllowed: (allow: string[]) =>
    new HttpError(405, 'method_not_allowed', '許可されていないメソッドです。', { headers: { allow: allow.join(', ') } }),
  payloadTooLarge: () => new HttpError(413, 'payload_too_large', 'リクエストが大きすぎます。'),
  unsupportedMediaType: () => new HttpError(415, 'unsupported_media_type', 'Content-Type は application/json にしてください。'),
  rateLimited: (retryAfterSeconds: number) =>
    new HttpError(429, 'rate_limited', 'リクエストが多すぎます。少し時間をおいてから試してください。', { retryAfterSeconds }),
  unavailable: (retryAfterSeconds = 30) =>
    new HttpError(503, 'upstream_unavailable', '今は体験を生成できません。少し時間をおいてから試してください。', {
      retryAfterSeconds,
    }),
  internal: () => new HttpError(500, 'internal', 'サーバーでエラーが発生しました。'),
};

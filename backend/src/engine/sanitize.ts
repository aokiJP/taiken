// iOSから届いた入力を「許可リスト方式」で組み立て直す。
// 未知のフィールドはAIへ渡さない (プライバシー原則: 送る必要がないものは送らない)。
import { ELEMENT_IDS } from '../content/library.ts';
import type {
  Area,
  CalendarItem,
  ChatContext,
  ChatTurn,
  Element,
  ExperienceContext,
  ExperienceRef,
  FeedbackSignal,
  Mood,
  Rating,
  Reaction,
  TreeContext,
} from './types.ts';

export class InputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InputError';
  }
}

export const LIMITS = Object.freeze({
  calendarItems: 20,
  titleChars: 80,
  messages: 12,
  messageChars: 500,
  experiences: 10,
  feedback: 20,
  excludeTitles: 10,
  areaChars: 40,
  treeLived: 12,
  treeBuds: 16,
});

/** 体験の樹の上の体験の id (英小文字・数字・ハイフン)。それ以外は捨てる */
export const NODE_ID = /^[a-z0-9][a-z0-9-]{0,63}$/;

const RATINGS: ReadonlySet<string> = new Set(['positive', 'neutral', 'negative']);
const REACTIONS: ReadonlySet<string> = new Set(['accepted', 'alternative', 'declined', 'completed']);
const MOODS: ReadonlySet<string> = new Set(['tired', 'bored', 'focus', 'refresh']);

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);

// 制御文字を除き、長すぎる文字列は切り詰める
export function cleanText(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  if (!trimmed) return null;
  const chars = Array.from(trimmed); // サロゲートペアを壊さない
  return chars.length > max ? `${chars.slice(0, max).join('')}…` : trimmed;
}

function isoDate(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 40) return null;
  return Number.isNaN(Date.parse(value)) ? null : value;
}

function timeZone(value: unknown): string {
  const tz = cleanText(value, 64);
  if (!tz) return 'UTC';
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz;
  } catch {
    return 'UTC';
  }
}

function base(body: unknown) {
  if (!isObject(body)) throw new InputError('リクエスト本文はJSONオブジェクトである必要があります。');
  const current = isoDate(body.current_time);
  if (!current) throw new InputError('current_time (ISO 8601) が必要です。');
  return {
    body,
    ctx: {
      current_time: current,
      time_zone: timeZone(body.time_zone),
      locale: cleanText(body.locale, 16) ?? 'ja-JP',
    },
  };
}

export function sanitizeCalendar(items: unknown): CalendarItem[] {
  const out: CalendarItem[] = [];
  for (const item of list(items).slice(0, LIMITS.calendarItems)) {
    if (!isObject(item)) continue;
    const start = isoDate(item.start);
    if (!start) continue;
    out.push({
      // タイトル送信をユーザーが拒否している場合、iOSは null を送る
      title: cleanText(item.title, LIMITS.titleChars),
      start,
      end: isoDate(item.end),
      is_all_day: item.is_all_day === true,
      day: item.day === 'tomorrow' ? 'tomorrow' : 'today',
    });
  }
  return out;
}

function sanitizeRef(item: unknown): ExperienceRef | null {
  if (!isObject(item)) return null;
  const title = cleanText(item.title, LIMITS.titleChars);
  if (!title) return null;
  return {
    title,
    theme: cleanText(item.theme, 40),
    reaction: typeof item.reaction === 'string' && REACTIONS.has(item.reaction) ? (item.reaction as Reaction) : null,
    rating: typeof item.rating === 'string' && RATINGS.has(item.rating) ? (item.rating as Rating) : null,
    date: cleanText(item.date, 32),
  };
}

function sanitizeFeedback(item: unknown): FeedbackSignal | null {
  if (!isObject(item)) return null;
  const tag = cleanText(item.tag, 40);
  if (!tag || typeof item.rating !== 'string' || !RATINGS.has(item.rating)) return null;
  const w = typeof item.weight === 'number' && Number.isFinite(item.weight) ? Math.min(1, Math.max(0, item.weight)) : 1;
  return { tag, rating: item.rating as Rating, weight: w };
}

function sanitizeArea(value: unknown): Area | null {
  if (!isObject(value)) return null;
  const country = typeof value.country_code === 'string' && /^[A-Z]{2}$/.test(value.country_code) ? value.country_code : null;
  const area: Area = {
    locality: cleanText(value.locality, LIMITS.areaChars),
    administrative_area: cleanText(value.administrative_area, LIMITS.areaChars),
    country_code: country,
  };
  return area.locality || area.administrative_area || area.country_code ? area : null;
}

export function sanitizeElements(value: unknown, max = 3): Element[] {
  const out: Element[] = [];
  for (const item of list(value)) {
    if (typeof item === 'string' && ELEMENT_IDS.has(item) && !out.includes(item as Element)) out.push(item as Element);
    if (out.length >= max) break;
  }
  return out;
}

const nodeId = (value: unknown): string | null => (typeof value === 'string' && NODE_ID.test(value) ? value : null);

/** 体験の樹のいま。id の形でないもの・知らない要素は捨て、名前は短く切る (中身はAIへのデータとしてだけ使う) */
function sanitizeTree(value: unknown): TreeContext | null {
  if (!isObject(value)) return null;
  const lived: TreeContext['lived'] = [];
  const seen = new Set<string>();
  for (const item of list(value.lived)) {
    if (!isObject(item)) continue;
    const id = nodeId(item.id);
    const title = cleanText(item.title, LIMITS.titleChars);
    if (!id || !title || seen.has(id)) continue;
    seen.add(id);
    lived.push({ id, title, elements: sanitizeElements(item.elements) });
    if (lived.length >= LIMITS.treeLived) break;
  }
  const buds: string[] = [];
  for (const item of list(value.buds)) {
    const id = nodeId(item);
    if (id && !buds.includes(id)) buds.push(id);
    if (buds.length >= LIMITS.treeBuds) break;
  }
  return lived.length || buds.length ? { lived, buds } : null;
}

export function sanitizeExperienceRequest(input: unknown): ExperienceContext {
  const { body, ctx } = base(input);
  return {
    ...ctx,
    calendar_context: sanitizeCalendar(body.calendar_context),
    recent_user_messages: list(body.recent_user_messages)
      .map((m) => cleanText(m, LIMITS.messageChars))
      .filter((m): m is string => m !== null)
      .slice(-LIMITS.messages),
    recent_experiences: list(body.recent_experiences)
      .map(sanitizeRef)
      .filter((r): r is ExperienceRef => r !== null)
      .slice(0, LIMITS.experiences),
    user_feedback: list(body.user_feedback)
      .map(sanitizeFeedback)
      .filter((f): f is FeedbackSignal => f !== null)
      .slice(0, LIMITS.feedback),
    exclude_titles: list(body.exclude_titles)
      .map((t) => cleanText(t, LIMITS.titleChars))
      .filter((t): t is string => t !== null)
      .slice(0, LIMITS.excludeTitles),
    area: sanitizeArea(body.area),
    allow_web_search: body.allow_web_search === true,
    mood: typeof body.mood === 'string' && MOODS.has(body.mood) ? (body.mood as Mood) : null,
    // 3.0.0 で季節 (season) は廃止。古いアプリから届いても使わない
    tree: sanitizeTree(body.tree),
  };
}

export function sanitizeChatRequest(input: unknown): ChatContext {
  const { body, ctx } = base(input);
  const messages: ChatTurn[] = [];
  for (const m of list(body.messages)) {
    if (!isObject(m) || (m.role !== 'user' && m.role !== 'assistant')) continue;
    const text = cleanText(m.text, LIMITS.messageChars);
    if (text) messages.push({ role: m.role, text });
  }
  const recent = messages.slice(-LIMITS.messages);
  if (!recent.length || recent.at(-1)?.role !== 'user') {
    throw new InputError('messages の最後はユーザーの発言である必要があります。');
  }
  return {
    ...ctx,
    messages: recent,
    calendar_context: sanitizeCalendar(body.calendar_context),
    current_experience: sanitizeRef(body.current_experience),
  };
}

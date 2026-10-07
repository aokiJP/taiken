// AIに返させるJSONの形 (tool use の input_schema) と、返ってきた値を型安全に正規化する関数。
// AIの自由文をUIロジックに使わないため、ここを通らないものはiOSへ返さない。
import type {
  Basis,
  ChatResult,
  Difficulty,
  Experience,
  ExperienceResult,
  Observation,
  Reference,
  Source,
} from './types.ts';

export const BASIS: readonly Basis[] = ['calendar', 'stated', 'inferred'];
export const DIFFICULTY: readonly Difficulty[] = ['low', 'medium', 'high'];
export const EXPERIENCE_TAGS = [
  'new_perspective',
  'question',
  'small_challenge',
  'observation',
  'sensory',
  'reflection',
  'social',
  'creative',
  'competitive',
  'short',
  'long_duration',
] as const;

const observationSchema = {
  type: 'object',
  properties: {
    text: { type: 'string', description: '観察内容。推測の場合は「〜かもしれない」の形で書く' },
    basis: {
      type: 'string',
      enum: BASIS,
      description: 'calendar=予定に書かれた事実, stated=ユーザーが言った事実, inferred=あなたの推測',
    },
  },
  required: ['text', 'basis'],
} as const;

const experienceSchema = {
  type: 'object',
  properties: {
    title: { type: 'string', description: '体験の短い名前 (20文字以内)' },
    perspective: { type: 'string', description: 'その行動をどんな別の意味・視点で捉えるか' },
    invitation: {
      type: 'string',
      description: 'ユーザーへの誘いかけ。命令ではなく「〜してみませんか？」の形。具体的な手順や時刻は指定しない',
    },
    reason: { type: 'string', description: 'なぜ今この提案なのか。推測は推測として書く' },
    difficulty: { type: 'string', enum: DIFFICULTY },
    tags: { type: 'array', items: { type: 'string', enum: EXPERIENCE_TAGS }, maxItems: 4 },
  },
  required: ['title', 'perspective', 'invitation', 'reason', 'difficulty', 'tags'],
} as const;

export interface ToolDefinition {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

export const EXPERIENCE_TOOL: ToolDefinition = {
  name: 'propose_experience',
  description: 'ユーザーの日常の状況を整理し、体験への変換案を1つ返す',
  input_schema: {
    type: 'object',
    properties: {
      situation: {
        type: 'object',
        properties: {
          summary: { type: 'string', description: '今の状況の短い要約。断定できないことは断定しない' },
          observations: { type: 'array', items: observationSchema, maxItems: 6 },
        },
        required: ['summary', 'observations'],
      },
      detected_actions: {
        type: 'array',
        maxItems: 5,
        items: {
          type: 'object',
          properties: { label: { type: 'string' }, basis: { type: 'string', enum: BASIS } },
          required: ['label', 'basis'],
        },
      },
      possible_obligations: {
        type: 'array',
        maxItems: 5,
        items: {
          type: 'object',
          properties: {
            label: { type: 'string', description: '「〜の可能性」の形で書く' },
            likelihood: { type: 'number', minimum: 0, maximum: 1 },
          },
          required: ['label', 'likelihood'],
        },
      },
      experience_opportunities: { type: 'array', items: { type: 'string' }, maxItems: 5 },
      is_obligation: { type: 'boolean', description: '提案の元になった行動が義務・作業的なものか' },
      confidence: { type: 'number', minimum: 0, maximum: 1, description: '状況理解の確からしさ' },
      experience: experienceSchema,
      should_notify: { type: 'boolean', description: '今、通知してまで伝える価値があるか' },
      notification: {
        type: 'object',
        properties: { title: { type: 'string' }, body: { type: 'string' } },
        required: ['title', 'body'],
      },
    },
    required: [
      'situation',
      'detected_actions',
      'possible_obligations',
      'experience_opportunities',
      'is_obligation',
      'confidence',
      'experience',
      'should_notify',
    ],
  },
};

export const CHAT_TOOL: ToolDefinition = {
  name: 'chat_reply',
  description: 'ユーザーへの返答と、会話から分かったこと',
  input_schema: {
    type: 'object',
    properties: {
      reply: { type: 'string', description: 'ユーザーへの自然な返答。短めに。心理状態を断定しない' },
      observations: { type: 'array', items: observationSchema, maxItems: 4 },
      needs_care: {
        type: 'boolean',
        description: 'ユーザーが深刻な苦痛・自分を傷つける考え・危険を口にしている場合だけ true',
      },
      suggest_experience: {
        type: 'boolean',
        description: '会話の流れで体験を提案するのが自然な場合のみ true。needs_care が true なら必ず false',
      },
      experience: experienceSchema,
    },
    required: ['reply', 'observations', 'needs_care', 'suggest_experience'],
  },
};

export class SchemaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SchemaError';
  }
}

type Json = Record<string, unknown>;
const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const text = (v: unknown, max = 400): string | null =>
  typeof v === 'string' && v.trim() ? Array.from(v.trim()).slice(0, max).join('') : null;
const clamp01 = (v: unknown): number | null =>
  typeof v === 'number' && Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : null;
const basisOf = (v: unknown): Basis => (BASIS.includes(v as Basis) ? (v as Basis) : 'inferred');
const TAGS: ReadonlySet<string> = new Set(EXPERIENCE_TAGS);

function observation(o: unknown): Observation | null {
  if (!isObject(o)) return null;
  const t = text(o.text, 200);
  // 不明な basis は推測扱いに倒す (推測を事実として扱わない)
  return t ? { text: t, basis: basisOf(o.basis) } : null;
}

export function normalizeExperience(e: unknown): Experience {
  if (!isObject(e)) throw new SchemaError('experience がありません');
  const title = text(e.title, 40);
  const perspective = text(e.perspective);
  const invitation = text(e.invitation);
  const reason = text(e.reason);
  if (!title || !perspective || !invitation || !reason) throw new SchemaError('experience に空の項目があります');
  const tags = [...new Set(list(e.tags).filter((t): t is string => typeof t === 'string' && TAGS.has(t)))];
  return {
    title,
    perspective,
    invitation,
    reason,
    difficulty: DIFFICULTY.includes(e.difficulty as Difficulty) ? (e.difficulty as Difficulty) : 'low',
    tags: tags.slice(0, 4),
  };
}

export function normalizeReferences(refs: unknown): Reference[] {
  const seen = new Set<string>();
  const out: Reference[] = [];
  for (const r of list(refs)) {
    if (!isObject(r)) continue;
    const url = typeof r.url === 'string' && /^https?:\/\//.test(r.url) ? r.url.slice(0, 500) : null;
    if (!url || seen.has(url)) continue;
    seen.add(url);
    out.push({ title: text(r.title, 120) ?? url, url });
    if (out.length >= 3) break;
  }
  return out;
}

export function normalizeExperienceResult(raw: unknown, source: Source): ExperienceResult {
  if (!isObject(raw)) throw new SchemaError('結果がオブジェクトではありません');
  const situation = isObject(raw.situation) ? raw.situation : {};
  const n = isObject(raw.notification) ? raw.notification : {};
  const nTitle = text(n.title, 60);
  const nBody = text(n.body, 160);
  const notification = raw.should_notify === true && nTitle && nBody ? { title: nTitle, body: nBody } : null;

  return {
    situation: {
      summary: text(situation.summary, 300) ?? '',
      observations: list(situation.observations)
        .map(observation)
        .filter((o): o is Observation => o !== null)
        .slice(0, 6),
    },
    detected_actions: list(raw.detected_actions)
      .map((a) => {
        if (!isObject(a)) return null;
        const label = text(a.label, 100);
        return label ? { label, basis: basisOf(a.basis) } : null;
      })
      .filter((a): a is { label: string; basis: Basis } => a !== null)
      .slice(0, 5),
    possible_obligations: list(raw.possible_obligations)
      .map((o) => {
        if (!isObject(o)) return null;
        const label = text(o.label, 100);
        return label ? { label, likelihood: clamp01(o.likelihood) ?? 0.5 } : null;
      })
      .filter((o): o is { label: string; likelihood: number } => o !== null)
      .slice(0, 5),
    experience_opportunities: list(raw.experience_opportunities)
      .map((s) => text(s, 120))
      .filter((s): s is string => s !== null)
      .slice(0, 5),
    is_obligation: raw.is_obligation === true,
    confidence: clamp01(raw.confidence) ?? 0.5,
    experience: normalizeExperience(raw.experience),
    should_notify: notification !== null,
    notification,
    references: normalizeReferences(raw.references),
    source,
    fallback_reason: null,
  };
}

export function normalizeChatResult(raw: unknown, source: Source): ChatResult {
  if (!isObject(raw)) throw new SchemaError('結果がオブジェクトではありません');
  const reply = text(raw.reply, 800);
  if (!reply) throw new SchemaError('reply が空です');
  const needsCare = raw.needs_care === true;
  let experience: Experience | null = null;
  if (!needsCare && raw.suggest_experience === true && raw.experience !== undefined) {
    try {
      experience = normalizeExperience(raw.experience);
    } catch {
      experience = null;
    }
  }
  return {
    reply,
    observations: list(raw.observations)
      .map(observation)
      .filter((o): o is Observation => o !== null)
      .slice(0, 4),
    suggest_experience: experience !== null,
    experience,
    needs_care: needsCare,
    source,
    fallback_reason: null,
  };
}

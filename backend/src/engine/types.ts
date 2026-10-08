// Backend内部で使う型。JSONのキー名 (snake_case) は契約 (contracts/openapi.json) と一致させる。

export type Basis = 'calendar' | 'stated' | 'inferred';
export type Rating = 'positive' | 'neutral' | 'negative';
export type Reaction = 'accepted' | 'alternative' | 'declined' | 'completed';
export type Difficulty = 'low' | 'medium' | 'high';
/** ユーザーがその場で選んだ気分 (自己申告) */
export type Mood = 'tired' | 'bored' | 'focus' | 'refresh';
export type Source = 'ai' | 'mock' | 'fallback';
export type FallbackReason =
  | 'budget_exceeded'
  | 'upstream_error'
  | 'invalid_output'
  | 'unsafe_output'
  | 'circuit_open'
  | 'busy';

export interface CalendarItem {
  title: string | null;
  start: string;
  end: string | null;
  is_all_day: boolean;
  day: 'today' | 'tomorrow';
}

export interface ExperienceRef {
  title: string;
  theme: string | null;
  reaction: Reaction | null;
  rating: Rating | null;
  date: string | null;
}

export interface FeedbackSignal {
  tag: string;
  rating: Rating;
  weight: number;
}

export interface Area {
  locality: string | null;
  administrative_area: string | null;
  country_code: string | null;
}

/** 体験の要素 */
export type Element = 'see' | 'hear' | 'smell' | 'taste' | 'touch' | 'move' | 'pause' | 'think' | 'word' | 'people';

/** 体験の樹のいま (iOS が体験帳から計算する。体験帳を使う許可があるときだけ届く) */
export interface TreeContext {
  /** 灯った体験 (最近のものから) */
  lived: { id: string; title: string; elements: Element[] }[];
  /** 芽 (灯った体験からつながっている、まだやっていない体験の id) */
  buds: string[];
}

interface BaseContext {
  current_time: string;
  time_zone: string;
  locale: string;
}

export interface ExperienceContext extends BaseContext {
  calendar_context: CalendarItem[];
  recent_user_messages: string[];
  recent_experiences: ExperienceRef[];
  user_feedback: FeedbackSignal[];
  exclude_titles: string[];
  area: Area | null;
  allow_web_search: boolean;
  mood: Mood | null;
  tree: TreeContext | null;
}

export interface ChatTurn {
  role: 'user' | 'assistant';
  text: string;
}

export interface ChatContext extends BaseContext {
  messages: ChatTurn[];
  calendar_context: CalendarItem[];
  current_experience: ExperienceRef | null;
}

export interface Observation {
  text: string;
  basis: Basis;
}

export interface Experience {
  title: string;
  perspective: string;
  invitation: string;
  reason: string;
  difficulty: Difficulty;
  tags: string[];
  /** 体験のあとに思い返すための問い */
  reflection_question: string | null;
  /** 体験ライブラリから選んだときの id (AIが新しく作った体験は null) */
  node_id: string | null;
  /** 要素 (先頭が主な要素) */
  elements: Element[];
  /** この体験が伸びている、灯った体験の id (tree.lived にあるものだけ) */
  grows_from: string | null;
}

export interface Reference {
  title: string;
  url: string;
}

export interface ExperienceResult {
  situation: { summary: string; observations: Observation[] };
  detected_actions: { label: string; basis: Basis }[];
  possible_obligations: { label: string; likelihood: number }[];
  experience_opportunities: string[];
  is_obligation: boolean;
  confidence: number;
  experience: Experience;
  should_notify: boolean;
  notification: { title: string; body: string } | null;
  references: Reference[];
  source: Source;
  fallback_reason: FallbackReason | null;
}

export interface ChatResult {
  reply: string;
  observations: Observation[];
  suggest_experience: boolean;
  experience: Experience | null;
  needs_care: boolean;
  source: Source;
  fallback_reason: FallbackReason | null;
}

/** Web検索の段で得た外部情報。体験生成の段に「データ」として渡す */
export interface ResearchResult {
  summary: string;
  references: Reference[];
  searches: number;
}

/** AIの1回の呼び出しで消費した量 (予算管理用) */
export interface Usage {
  inputTokens: number;
  outputTokens: number;
  webSearches: number;
}

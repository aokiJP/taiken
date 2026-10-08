// 体験ライブラリ・要素・テーマ・気分 (contracts/content.ja.json のコピー。テストで一致を確認する)。
// 体験の選び方の仕様は contracts/tools/selection_reference.py で、iOS (LibrarySelector.swift) と同じ結果を返す。
// モック生成と、AIが使えないときの代替生成に使う。
import { readFileSync } from 'node:fs';
import type { Element, FeedbackSignal, Mood, TreeContext } from '../engine/types.ts';

export type TimeOfDay = 'dawn' | 'morning' | 'daytime' | 'evening' | 'night' | 'lateNight';

export interface Link {
  to: string;
  kind: 'deepen' | 'widen' | 'cross';
}

export interface LibraryExperience {
  id: string;
  title: string;
  perspective: string;
  invitation: string;
  reflection_question: string;
  tags: string[];
  themes: string[];
  moods: string[];
  times: string[];
  effort: 'low' | 'medium';
  elements: Element[];
  opens: Link[];
}

export interface ElementEntry {
  id: Element;
  glyph: string;
  label: string;
  hint: string;
  root: string;
  keywords: string[];
}

interface Keyworded {
  id: string;
  label: string;
  keywords: string[];
}

export interface Content {
  version: number;
  elements: ElementEntry[];
  themes: Keyworded[];
  moods: Keyworded[];
  experiences: LibraryExperience[];
}

export const CONTENT_URL = new URL('./content.ja.json', import.meta.url);
export const CONTENT: Content = JSON.parse(readFileSync(CONTENT_URL, 'utf8')) as Content;

export const ELEMENT_IDS: ReadonlySet<string> = new Set(CONTENT.elements.map((e) => e.id));
const BY_ID: ReadonlyMap<string, LibraryExperience> = new Map(CONTENT.experiences.map((e) => [e.id, e]));
const ROOTS: ReadonlySet<string> = new Set(CONTENT.elements.map((e) => e.root));

const SPECIFIC_THEMES: ReadonlySet<string> = new Set(['study', 'work', 'commute', 'meal', 'housework', 'shopping', 'people', 'body']);
/** 芽に足す点数 */
const BUD_BONUS = 1.5;

export const TIME_LABELS: Record<TimeOfDay, string> = {
  dawn: '夜明け',
  morning: '朝',
  daytime: '昼',
  evening: '夕方',
  night: '夜',
  lateNight: '深夜',
};

/** 時間帯の境界は iOS と同じ */
export function timeOfDayOf(hour: number): TimeOfDay {
  if (hour >= 4 && hour < 6) return 'dawn';
  if (hour >= 6 && hour < 10) return 'morning';
  if (hour >= 10 && hour < 16) return 'daytime';
  if (hour >= 16 && hour < 19) return 'evening';
  if (hour >= 19 && hour < 24) return 'night';
  return 'lateNight';
}

/** FNV-1a (32bit)。iOS と同じ値になる */
export function fnv1a(text: string): number {
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

export function jitter(id: string, day: number): number {
  return ((fnv1a(`${id}#${day}`) % 1000) / 1000) * 0.9;
}

/** "2026-10-08..." の日付部分 (その土地の日付) を 1970-01-01 からの日数にする */
export function dayNumberOf(isoLocal: string): number {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(isoLocal);
  if (!m) return Math.floor(Date.now() / 86_400_000);
  return Math.floor(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) / 86_400_000);
}

export function experienceById(id: string | null | undefined): LibraryExperience | undefined {
  return id ? BY_ID.get(id) : undefined;
}

export function isRoot(id: string): boolean {
  return ROOTS.has(id);
}

export function elementLabel(id: string): string | undefined {
  return CONTENT.elements.find((e) => e.id === id)?.label;
}

export function detectThemes(texts: readonly string[], content: Content = CONTENT): Set<string> {
  const found = new Set<string>();
  for (const theme of content.themes) {
    if (theme.keywords.some((k) => texts.some((t) => t.includes(k)))) found.add(theme.id);
  }
  return found;
}

export function detectMood(texts: readonly string[], content: Content = CONTENT): Mood | null {
  for (const mood of content.moods) {
    if (mood.keywords.some((k) => texts.some((t) => t.includes(k)))) return mood.id as Mood;
  }
  return null;
}

export interface SelectionInput {
  day: number;
  timeOfDay: TimeOfDay;
  eventTitle: string | null;
  messages: readonly string[];
  mood: Mood | null;
  feedback: readonly FeedbackSignal[];
  recentTitles: readonly string[];
  excludeTitles: readonly string[];
  /** 体験の樹の芽 (少しだけ前に出す) */
  buds: readonly string[];
}

export interface Choice {
  experience: LibraryExperience;
  themesFromEvent: Set<string>;
  themesFromMessages: Set<string>;
  mood: Mood | null;
  moodWasChosen: boolean;
  isBud: boolean;
}

export function choose(input: SelectionInput, content: Content = CONTENT): Choice {
  const fromEvent = detectThemes(input.eventTitle ? [input.eventTitle] : [], content);
  const fromMessages = detectThemes(input.messages, content);
  const detected = new Set([...fromEvent, ...fromMessages]);
  const mood = input.mood ?? detectMood(input.messages, content);
  const tod = input.timeOfDay;
  const timeTheme = tod === 'dawn' || tod === 'morning' ? 'morning' : tod === 'night' || tod === 'lateNight' ? 'night' : null;
  const recent = new Set(input.recentTitles);
  const exclude = new Set(input.excludeTitles);
  const buds = new Set(input.buds);

  const eligible = (e: LibraryExperience, useExclude: boolean) => {
    if (useExclude && exclude.has(e.title)) return false;
    if (e.times.length && !e.times.includes(tod)) return false;
    return true;
  };

  const score = (e: LibraryExperience) => {
    let s = 0;
    if (e.themes.some((t) => detected.has(t))) s += 4;
    else if (e.themes.every((t) => SPECIFIC_THEMES.has(t))) s -= 2;
    if (mood && e.moods.includes(mood)) s += 2.5;
    if (timeTheme && e.themes.includes(timeTheme)) s += 1.5;
    if (buds.has(e.id)) s += BUD_BONUS;
    for (const tag of e.tags) {
      for (const f of input.feedback) {
        if (f.tag !== tag) continue;
        const factor = f.rating === 'positive' ? 1 : f.rating === 'negative' ? -1.5 : 0;
        s += factor * f.weight;
      }
    }
    if (recent.has(e.title)) s -= 3;
    if (mood === 'tired' && e.effort === 'medium') s -= 2;
    s += jitter(e.id, input.day);
    return s;
  };

  let candidates = content.experiences.filter((e) => eligible(e, true));
  if (!candidates.length) candidates = content.experiences.filter((e) => eligible(e, false));
  if (!candidates.length) candidates = content.experiences;

  let best = candidates[0] as LibraryExperience;
  let bestScore = Number.NEGATIVE_INFINITY;
  for (const candidate of candidates) {
    const s = score(candidate);
    if (s > bestScore) {
      best = candidate;
      bestScore = s;
    }
  }
  return {
    experience: best,
    themesFromEvent: fromEvent,
    themesFromMessages: fromMessages,
    mood,
    moodWasChosen: input.mood !== null,
    isBud: buds.has(best.id),
  };
}

/** 選んだ体験が伸びている、灯った体験 (樹のいまの「灯った体験」の順に、つながりを探す) */
export function parentOf(picked: LibraryExperience, tree: TreeContext | null): { id: string; title: string } | null {
  if (!tree) return null;
  for (const lived of tree.lived) {
    if (experienceById(lived.id)?.opens.some((link) => link.to === picked.id)) return { id: lived.id, title: lived.title };
  }
  return null;
}

const MOOD_LABELS: Record<Mood, string> = { tired: '疲れぎみ', bored: 'ひま', focus: '集中したい', refresh: '気分転換' };
const MOOD_REASONS: Record<Mood, string> = {
  tired: '負担の少ないものを選びました。',
  bored: '小さな遊び心のあるものを選びました。',
  focus: '取り組んでいることを、少し違う角度から見るものにしました。',
  refresh: '感覚や視点を少し切り替えるものを選びました。',
};

export function moodLabel(mood: Mood): string {
  return MOOD_LABELS[mood];
}

const intersects = (a: readonly string[], b: Set<string>) => a.some((x) => b.has(x));

/** 何を手がかりに選んだかを正直に書く (iOS の端末内の提案と同じ書き方) */
export function reasonFor(choice: Choice, eventTitle: string | null, hasEvent: boolean, parent: { title: string } | null): string {
  if (choice.moodWasChosen && choice.mood) return `「${MOOD_LABELS[choice.mood]}」とのことなので、${MOOD_REASONS[choice.mood]}`;
  if (hasEvent && intersects(choice.experience.themes, choice.themesFromEvent)) {
    return eventTitle ? `「${eventTitle}」の予定があるので、その時間の見方を少し変える提案にしました。` : 'このあとの予定に合わせて選びました。';
  }
  if (choice.mood === 'tired') return '疲れていると話していたので、負担の少ないものを選びました。';
  if (intersects(choice.experience.themes, choice.themesFromMessages)) return '話していたことから選びました。';
  if (choice.isBud) {
    if (parent) return `前に記した「${parent.title}」の先にある体験です。`;
    const element = choice.experience.elements[0];
    const label = element ? elementLabel(element) : undefined;
    if (isRoot(choice.experience.id) && label) return `「${label}」の根にある、いちばん小さなかたちの体験です。`;
    return 'あなたの体験の樹の、芽のひとつです。';
  }
  return '特別な予定がなくても、いつもの時間の中に体験は見つけられます。';
}

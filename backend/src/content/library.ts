// 七十二候・テーマ・気分・体験ライブラリ (contracts/content.ja.json のコピー。テストで一致を確認する)。
// 体験の選び方の仕様は contracts/tools/selection_reference.py で、iOS (LibrarySelector.swift) と同じ結果を返す。
// モック生成と、AIが使えないときの代替生成に使う。
import { readFileSync } from 'node:fs';
import type { FeedbackSignal, Mood, SeasonContext } from '../engine/types.ts';

export type TimeOfDay = 'dawn' | 'morning' | 'daytime' | 'evening' | 'night' | 'lateNight';

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
  solar_terms: number[];
}

interface Keyworded {
  id: string;
  label: string;
  keywords: string[];
}

export interface Content {
  version: number;
  solar_terms: { name: string; reading: string }[];
  micro_seasons: { name: string; reading: string; meaning: string }[];
  themes: Keyworded[];
  moods: Keyworded[];
  experiences: LibraryExperience[];
}

export const CONTENT_URL = new URL('./content.ja.json', import.meta.url);
export const CONTENT: Content = JSON.parse(readFileSync(CONTENT_URL, 'utf8')) as Content;

const SPECIFIC_THEMES: ReadonlySet<string> = new Set(['study', 'work', 'commute', 'meal', 'housework', 'shopping', 'people', 'body']);

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

export function solarTermIndex(name: string | null | undefined, content: Content = CONTENT): number | null {
  if (!name) return null;
  const i = content.solar_terms.findIndex((t) => t.name === name);
  return i >= 0 ? i : null;
}

/** 七十二候の名前から、正しい節気と意味を引く (クライアントの文言はそのまま使わない) */
export function canonicalSeason(microSeason: string, content: Content = CONTENT): SeasonContext | null {
  const i = content.micro_seasons.findIndex((m) => m.name === microSeason);
  const entry = content.micro_seasons[i];
  const term = content.solar_terms[Math.floor(i / 3)];
  if (i < 0 || !entry || !term) return null;
  return { solar_term: term.name, micro_season: entry.name, meaning: entry.meaning };
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
  solarTerm: number | null;
  eventTitle: string | null;
  messages: readonly string[];
  mood: Mood | null;
  feedback: readonly FeedbackSignal[];
  recentTitles: readonly string[];
  excludeTitles: readonly string[];
}

export interface Choice {
  experience: LibraryExperience;
  themesFromEvent: Set<string>;
  themesFromMessages: Set<string>;
  mood: Mood | null;
  moodWasChosen: boolean;
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

  const eligible = (e: LibraryExperience, useExclude: boolean) => {
    if (useExclude && exclude.has(e.title)) return false;
    if (e.solar_terms.length && (input.solarTerm === null || !e.solar_terms.includes(input.solarTerm))) return false;
    if (e.times.length && !e.times.includes(tod)) return false;
    return true;
  };

  const score = (e: LibraryExperience) => {
    let s = 0;
    if (e.themes.some((t) => detected.has(t))) s += 4;
    else if (e.themes.every((t) => SPECIFIC_THEMES.has(t))) s -= 2;
    if (mood && e.moods.includes(mood)) s += 2.5;
    if (e.solar_terms.length) s += 3;
    if (timeTheme && e.themes.includes(timeTheme)) s += 1.5;
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
  return { experience: best, themesFromEvent: fromEvent, themesFromMessages: fromMessages, mood, moodWasChosen: input.mood !== null };
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
export function reasonFor(choice: Choice, eventTitle: string | null, hasEvent: boolean, solarTerm: string | null): string {
  if (choice.moodWasChosen && choice.mood) return `「${MOOD_LABELS[choice.mood]}」とのことなので、${MOOD_REASONS[choice.mood]}`;
  if (hasEvent && intersects(choice.experience.themes, choice.themesFromEvent)) {
    return eventTitle ? `「${eventTitle}」の予定があるので、その時間の見方を少し変える提案にしました。` : 'このあとの予定に合わせて選びました。';
  }
  if (choice.mood === 'tired') return '疲れていると話していたので、負担の少ないものを選びました。';
  if (intersects(choice.experience.themes, choice.themesFromMessages)) return '話していたことから選びました。';
  if (choice.experience.solar_terms.length && solarTerm) return `今は「${solarTerm}」の頃。季節の小さな変化に目を向ける提案です。`;
  return '特別な予定がなくても、いつもの時間の中に体験は見つけられます。';
}

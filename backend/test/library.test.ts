import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  canonicalSeason,
  choose,
  CONTENT,
  CONTENT_URL,
  dayNumberOf,
  detectMood,
  detectThemes,
  fnv1a,
  jitter,
  reasonFor,
  solarTermIndex,
  timeOfDayOf,
  type TimeOfDay,
} from '../src/content/library.ts';
import { findSafetyIssue } from '../src/engine/safety.ts';
import { EXPERIENCE_TAGS } from '../src/engine/schema.ts';
import type { FeedbackSignal, Mood } from '../src/engine/types.ts';

const contracts = new URL('../../contracts/', import.meta.url);

test('同梱の内容は contracts/content.ja.json (iOS と共通の正) と同じ', () => {
  const bundled = readFileSync(CONTENT_URL);
  const canonical = readFileSync(new URL('content.ja.json', contracts));
  assert.ok(bundled.equals(canonical), 'contracts/tools/sync.sh でコピーしてください');
});

test('体験ライブラリの形と安全性 (iOS と同じ確認)', () => {
  assert.equal(CONTENT.version, 1);
  assert.equal(CONTENT.solar_terms.length, 24);
  assert.equal(CONTENT.micro_seasons.length, 72);
  assert.equal(new Set(CONTENT.micro_seasons.map((m) => m.name)).size, 72);
  assert.ok(CONTENT.experiences.length >= 70);
  assert.equal(new Set(CONTENT.experiences.map((e) => e.id)).size, CONTENT.experiences.length);
  assert.equal(new Set(CONTENT.experiences.map((e) => e.title)).size, CONTENT.experiences.length);

  const tags = new Set<string>(EXPERIENCE_TAGS);
  const themes = new Set(CONTENT.themes.map((t) => t.id));
  const times = new Set(['dawn', 'morning', 'daytime', 'evening', 'night', 'lateNight']);
  const moods = new Set(['tired', 'bored', 'focus', 'refresh']);
  for (const e of CONTENT.experiences) {
    assert.match(e.invitation, /ませんか？/, e.id);
    assert.ok(e.reflection_question.endsWith('？') && Array.from(e.reflection_question).length <= 30, e.id);
    assert.ok(e.tags.length >= 1 && e.tags.length <= 4 && e.tags.every((t) => tags.has(t)), e.id);
    assert.ok(e.themes.length > 0 && e.themes.every((t) => themes.has(t)), e.id);
    assert.ok(e.moods.every((m) => moods.has(m)), e.id);
    assert.ok(e.times.every((t) => times.has(t)), e.id);
    assert.ok(e.effort === 'low' || e.effort === 'medium', e.id);
    assert.ok(e.solar_terms.every((t) => t >= 0 && t < 24), e.id);
    assert.equal(findSafetyIssue({ ...e, reason: '', difficulty: 'low' }), null, `${e.id} は安全確認に引っかからない`);
  }
  // 二十四節気それぞれに季節の体験がちょうど1つ
  assert.deepEqual(CONTENT.experiences.flatMap((e) => e.solar_terms).sort((a, b) => a - b), Array.from({ length: 24 }, (_, i) => i));
});

interface SelectionCase {
  name: string;
  date: string;
  time_of_day: TimeOfDay;
  solar_term: number;
  event_title: string | null;
  messages: string[];
  mood: Mood | null;
  feedback: FeedbackSignal[];
  recent_titles: string[];
  exclude_titles: string[];
  expected: string;
}

test('選び方は contracts/selection_cases.json (iOS と共通) と同じ結果になる', () => {
  const { cases } = JSON.parse(readFileSync(new URL('selection_cases.json', contracts), 'utf8')) as { cases: SelectionCase[] };
  assert.ok(cases.length >= 10);
  for (const c of cases) {
    const got = choose({
      day: dayNumberOf(c.date),
      timeOfDay: c.time_of_day,
      solarTerm: c.solar_term,
      eventTitle: c.event_title,
      messages: c.messages,
      mood: c.mood,
      feedback: c.feedback,
      recentTitles: c.recent_titles,
      excludeTitles: c.exclude_titles,
    });
    assert.equal(got.experience.id, c.expected, c.name);
  }
});

test('ハッシュ・日数・時間帯は iOS と同じ', () => {
  assert.equal(fnv1a('a'), 0xe40c292c);
  assert.equal(fnv1a(''), 0x811c9dc5);
  assert.equal(dayNumberOf('2026-10-08T18:10:00+09:00'), 20734);
  assert.equal(dayNumberOf('2026-10-09T00:30:00+09:00'), 20735);
  assert.ok(Number.isInteger(dayNumberOf('garbage')));
  const j = jitter('season-kanro', 20734);
  assert.ok(j >= 0 && j < 0.9);
  const expected: Array<[number, TimeOfDay]> = [
    [0, 'lateNight'], [3, 'lateNight'], [4, 'dawn'], [6, 'morning'], [10, 'daytime'], [16, 'evening'], [19, 'night'], [23, 'night'],
  ];
  for (const [hour, tod] of expected) assert.equal(timeOfDayOf(hour), tod, `${hour}時`);
});

test('言葉から予定の種類と気分を読む', () => {
  assert.deepEqual([...detectThemes(['これから会議。ちょっと疲れた'])], ['work']);
  assert.equal(detectMood(['これから会議。ちょっと疲れた']), 'tired');
  assert.equal(detectMood(['暇だなあ']), 'bored');
  assert.deepEqual([...detectThemes(['友達と食事会'])].sort(), ['meal', 'people']);
  assert.equal(detectMood(['こんにちは']), null);
});

test('七十二候はクライアントの文言を使わず、正しい節気と意味に置き換える', () => {
  assert.deepEqual(canonicalSeason('鴻雁来'), { solar_term: '寒露', micro_season: '鴻雁来', meaning: '雁が北から渡ってくる頃' });
  assert.deepEqual(canonicalSeason('東風解凍')?.solar_term, '立春');
  assert.equal(canonicalSeason('存在しない候'), null);
  assert.equal(solarTermIndex('寒露'), 16);
  assert.equal(solarTermIndex('まぼろし'), null);
  assert.equal(solarTermIndex(null), null);
});

test('季節の体験はその節気のときだけ、時間帯に合わない体験は選ばない', () => {
  for (let term = 0; term < 24; term++) {
    const got = choose({ day: 20734, timeOfDay: 'daytime', solarTerm: term, eventTitle: null, messages: [], mood: null, feedback: [], recentTitles: [], excludeTitles: [] });
    assert.ok(got.experience.solar_terms.length === 0 || got.experience.solar_terms.includes(term), `${term}: ${got.experience.id}`);
  }
  for (let day = 20700; day < 20760; day++) {
    const got = choose({ day, timeOfDay: 'lateNight', solarTerm: 16, eventTitle: null, messages: [], mood: null, feedback: [], recentTitles: [], excludeTitles: [] });
    assert.ok(got.experience.times.length === 0 || got.experience.times.includes('lateNight'), got.experience.id);
  }
});

test('提案理由は、何を手がかりにしたかを正直に書く', () => {
  const base = { day: 20734, timeOfDay: 'evening' as const, solarTerm: 16, messages: [] as string[], feedback: [], recentTitles: [], excludeTitles: [] };
  const byMood = choose({ ...base, eventTitle: null, mood: 'tired' });
  assert.match(reasonFor(byMood, null, false, '寒露'), /^「疲れぎみ」とのことなので/);
  const byEvent = choose({ ...base, eventTitle: '数学の課題', mood: null });
  assert.equal(reasonFor(byEvent, '数学の課題', true, '寒露'), '「数学の課題」の予定があるので、その時間の見方を少し変える提案にしました。');
  assert.equal(reasonFor(byEvent, null, true, '寒露'), 'このあとの予定に合わせて選びました。');
  const seasonal = choose({ ...base, eventTitle: null, mood: null });
  assert.equal(reasonFor(seasonal, null, false, '寒露'), '今は「寒露」の頃。季節の小さな変化に目を向ける提案です。');
  const tiredWords = choose({ ...base, solarTerm: null, eventTitle: null, mood: null, messages: ['疲れた'] });
  assert.equal(reasonFor(tiredWords, null, false, null), '疲れていると話していたので、負担の少ないものを選びました。');
  const talked = choose({ ...base, solarTerm: null, eventTitle: null, mood: null, messages: ['これから掃除'] });
  assert.equal(reasonFor(talked, null, false, null), '話していたことから選びました。');
  const plain = choose({ ...base, solarTerm: null, eventTitle: null, mood: null });
  assert.equal(reasonFor(plain, null, false, null), '特別な予定がなくても、いつもの時間の中に体験は見つけられます。');
});

test('全部除外されても何かは選ぶ (除外を外して選び直す)', () => {
  const all = CONTENT.experiences.map((e) => e.title);
  const got = choose({ day: 20734, timeOfDay: 'evening', solarTerm: 16, eventTitle: null, messages: [], mood: null, feedback: [], recentTitles: [], excludeTitles: all });
  assert.ok(got.experience.title);
  const none = choose(
    { day: 20734, timeOfDay: 'evening', solarTerm: null, eventTitle: null, messages: [], mood: null, feedback: [], recentTitles: [], excludeTitles: [] },
    { ...CONTENT, experiences: CONTENT.experiences.filter((e) => e.solar_terms.length > 0).slice(0, 1) },
  );
  assert.ok(none.experience.solar_terms.length > 0, '候補が一つも合わなくても止まらない');
});

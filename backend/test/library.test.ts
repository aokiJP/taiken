import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  choose,
  CONTENT,
  CONTENT_URL,
  dayNumberOf,
  detectMood,
  detectThemes,
  elementLabel,
  experienceById,
  fnv1a,
  isRoot,
  jitter,
  parentOf,
  reasonFor,
  timeOfDayOf,
  type TimeOfDay,
} from '../src/content/library.ts';
import { findSafetyIssue } from '../src/engine/safety.ts';
import { EXPERIENCE_TAGS } from '../src/engine/schema.ts';
import type { FeedbackSignal, Mood } from '../src/engine/types.ts';

const contracts = new URL('../../contracts/', import.meta.url);
const quiet = { messages: [] as string[], feedback: [] as FeedbackSignal[], recentTitles: [] as string[], excludeTitles: [] as string[], buds: [] as string[] };

test('同梱の内容は contracts/content.ja.json (iOS と共通の正) と同じ', () => {
  const bundled = readFileSync(CONTENT_URL);
  const canonical = readFileSync(new URL('content.ja.json', contracts));
  assert.ok(bundled.equals(canonical), 'contracts/tools/sync.sh でコピーしてください');
});

test('体験ライブラリの形と安全性 (iOS と同じ確認)', () => {
  assert.equal(CONTENT.version, 2);
  assert.ok(CONTENT.experiences.length >= 90);
  assert.equal(new Set(CONTENT.experiences.map((e) => e.id)).size, CONTENT.experiences.length);
  assert.equal(new Set(CONTENT.experiences.map((e) => e.title)).size, CONTENT.experiences.length);

  const tags = new Set<string>(EXPERIENCE_TAGS);
  const themes = new Set(CONTENT.themes.map((t) => t.id));
  const times = new Set(['dawn', 'morning', 'daytime', 'evening', 'night', 'lateNight']);
  const moods = new Set(['tired', 'bored', 'focus', 'refresh']);
  const elements = new Set<string>(CONTENT.elements.map((e) => e.id));
  const ids = new Set(CONTENT.experiences.map((e) => e.id));
  for (const e of CONTENT.experiences) {
    assert.match(e.invitation, /ませんか？/, e.id);
    assert.ok(e.reflection_question.endsWith('？') && Array.from(e.reflection_question).length <= 30, e.id);
    assert.ok(e.tags.length >= 1 && e.tags.length <= 4 && e.tags.every((t) => tags.has(t)), e.id);
    assert.ok(e.themes.length > 0 && e.themes.every((t) => themes.has(t)), e.id);
    assert.ok(e.moods.every((m) => moods.has(m)), e.id);
    assert.ok(e.times.every((t) => times.has(t)), e.id);
    assert.ok(e.effort === 'low' || e.effort === 'medium', e.id);
    assert.ok(e.elements.length >= 1 && e.elements.length <= 3 && e.elements.every((x) => elements.has(x)), e.id);
    assert.ok(e.opens.every((l) => ids.has(l.to) && l.to !== e.id), e.id);
    assert.doesNotMatch(e.title + e.invitation + e.perspective, /季節|節気|七十二候/, `${e.id} は季節の言葉を使わない`);
    const experience = { ...e, reason: '', difficulty: 'low' as const, node_id: e.id, grows_from: null };
    assert.equal(findSafetyIssue(experience), null, `${e.id} は安全確認に引っかからない`);
  }
});

test('10の要素それぞれに、ひと文字の印と根がある', () => {
  assert.deepEqual(CONTENT.elements.map((e) => e.glyph), ['見', '聴', '香', '味', '触', '動', '休', '考', '言', '人']);
  for (const element of CONTENT.elements) {
    const root = experienceById(element.root);
    assert.ok(root, element.id);
    assert.equal(root.elements[0], element.id);
    assert.ok(isRoot(element.root));
  }
  assert.equal(elementLabel('taste'), '味わう');
  assert.equal(elementLabel('nope'), undefined);
  assert.equal(experienceById(null), undefined);
});

interface SelectionCase {
  name: string;
  date: string;
  time_of_day: TimeOfDay;
  event_title: string | null;
  messages: string[];
  mood: Mood | null;
  feedback: FeedbackSignal[];
  recent_titles: string[];
  exclude_titles: string[];
  buds: string[];
  expected: string;
}

test('選び方は contracts/selection_cases.json (iOS と共通) と同じ結果になる', () => {
  const { cases } = JSON.parse(readFileSync(new URL('selection_cases.json', contracts), 'utf8')) as { cases: SelectionCase[] };
  assert.ok(cases.length >= 10);
  for (const c of cases) {
    const got = choose({
      day: dayNumberOf(c.date),
      timeOfDay: c.time_of_day,
      eventTitle: c.event_title,
      messages: c.messages,
      mood: c.mood,
      feedback: c.feedback,
      recentTitles: c.recent_titles,
      excludeTitles: c.exclude_titles,
      buds: c.buds,
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
  const j = jitter('rest-far', 20734);
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

test('時間帯に合わない体験は選ばない', () => {
  for (let day = 20700; day < 20760; day++) {
    const got = choose({ day, timeOfDay: 'lateNight', eventTitle: null, mood: null, ...quiet });
    assert.ok(got.experience.times.length === 0 || got.experience.times.includes('lateNight'), got.experience.id);
  }
});

test('手がかりの無い日は芽から。予定に合う体験は芽より前に出る', () => {
  const buds = ['hear-far', 'hear-music-one', 'hear-silence', 'root-touch', 'taste-water'];
  for (let day = 20700; day < 20730; day++) {
    const free = choose({ day, timeOfDay: 'daytime', eventTitle: null, mood: null, ...quiet, buds });
    assert.ok(free.isBud, free.experience.id);
    const busy = choose({ day, timeOfDay: 'daytime', eventTitle: '数学の課題', mood: null, ...quiet, buds });
    assert.ok(busy.experience.themes.includes('study'), busy.experience.id);
  }
});

test('芽が伸びている、灯った体験を探す (樹のいまの順に)', () => {
  const texture = experienceById('meal-texture');
  assert.ok(texture);
  const tree = {
    lived: [
      { id: 'w-abc', title: '自分で編んだ体験', elements: [] },
      { id: 'meal-first-bite', title: 'ひと口目の観察', elements: ['taste' as const] },
    ],
    buds: ['meal-texture'],
  };
  assert.deepEqual(parentOf(texture, tree), { id: 'meal-first-bite', title: 'ひと口目の観察' });
  assert.equal(parentOf(texture, null), null);
  assert.equal(parentOf(texture, { lived: [], buds: [] }), null);
});

test('提案理由は、何を手がかりにしたかを正直に書く', () => {
  const base = { day: 20734, timeOfDay: 'evening' as const, ...quiet };
  const byMood = choose({ ...base, eventTitle: null, mood: 'tired' });
  assert.match(reasonFor(byMood, null, false, null), /^「疲れぎみ」とのことなので/);
  const byEvent = choose({ ...base, eventTitle: '数学の課題', mood: null });
  assert.equal(reasonFor(byEvent, '数学の課題', true, null), '「数学の課題」の予定があるので、その時間の見方を少し変える提案にしました。');
  assert.equal(reasonFor(byEvent, null, true, null), 'このあとの予定に合わせて選びました。');
  const tiredWords = choose({ ...base, eventTitle: null, mood: null, messages: ['疲れた'] });
  assert.equal(reasonFor(tiredWords, null, false, null), '疲れていると話していたので、負担の少ないものを選びました。');
  const talked = choose({ ...base, eventTitle: null, mood: null, messages: ['これから掃除'] });
  assert.equal(reasonFor(talked, null, false, null), '話していたことから選びました。');
  const plain = choose({ ...base, eventTitle: null, mood: null });
  assert.equal(reasonFor(plain, null, false, null), '特別な予定がなくても、いつもの時間の中に体験は見つけられます。');

  const daytime = { ...base, timeOfDay: 'daytime' as const };
  const bud = choose({ ...daytime, eventTitle: null, mood: null, buds: ['taste-water'] });
  assert.equal(bud.experience.id, 'taste-water');
  assert.equal(reasonFor(bud, null, false, { title: 'ひと口目の観察' }), '前に記した「ひと口目の観察」の先にある体験です。');
  assert.equal(reasonFor(bud, null, false, null), 'あなたの体験の樹の、芽のひとつです。');
  const root = choose({ ...daytime, eventTitle: null, mood: null, buds: ['root-see'] });
  assert.equal(reasonFor(root, null, false, null), '「見る」の根にある、いちばん小さなかたちの体験です。');
});

test('全部除外されても何かは選ぶ (除外を外して選び直す)', () => {
  const all = CONTENT.experiences.map((e) => e.title);
  const got = choose({ day: 20734, timeOfDay: 'evening', eventTitle: null, mood: null, ...quiet, excludeTitles: all });
  assert.ok(got.experience.title);
  const onlyNight = CONTENT.experiences.filter((e) => e.times.length > 0 && !e.times.includes('daytime')).slice(0, 1);
  const none = choose({ day: 20734, timeOfDay: 'daytime', eventTitle: null, mood: null, ...quiet }, { ...CONTENT, experiences: onlyNight });
  assert.equal(none.experience.id, onlyNight[0]?.id, '候補が一つも合わなくても止まらない');
});

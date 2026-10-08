import assert from 'node:assert/strict';
import { test } from 'node:test';
import { detectCareNeed, findSafetyIssue } from '../src/engine/safety.ts';
import { normalizeChatResult, normalizeExperience, normalizeExperienceResult, normalizeReferences, SchemaError } from '../src/engine/schema.ts';
import type { Experience } from '../src/engine/types.ts';
import { fixture } from './helpers.ts';

const good = () => fixture('experience_response.sample.json');

test('不明な basis は inferred として扱う (推測を事実にしない)', () => {
  const raw = { ...good(), situation: { summary: 's', observations: [{ text: 'たぶん眠い', basis: 'fact' }] } };
  assert.equal(normalizeExperienceResult(raw, 'ai').situation.observations[0]?.basis, 'inferred');
});

test('confidence と likelihood は 0〜1 に丸め、欠けていれば 0.5', () => {
  const raw = { ...good(), confidence: 7, possible_obligations: [{ label: 'x', likelihood: -3 }, { label: 'y' }] };
  const out = normalizeExperienceResult(raw, 'ai');
  assert.equal(out.confidence, 1);
  assert.deepEqual(out.possible_obligations.map((o) => o.likelihood), [0, 0.5]);
});

test('should_notify=true でも通知文が欠けていれば通知しない', () => {
  const out = normalizeExperienceResult({ ...good(), should_notify: true, notification: { title: '', body: '' } }, 'ai');
  assert.equal(out.should_notify, false);
  assert.equal(out.notification, null);
});

test('experience の必須項目が空なら SchemaError', () => {
  assert.throws(() => normalizeExperience({ title: 't', perspective: '', invitation: 'i', reason: 'r' }), SchemaError);
  assert.throws(() => normalizeExperience(null), SchemaError);
  assert.throws(() => normalizeExperienceResult('x', 'ai'), SchemaError);
});

test('未知のタグ・重複タグは捨て、難易度の不正値は low', () => {
  const e = normalizeExperience({ title: 't', perspective: 'p', invitation: 'i', reason: 'r', difficulty: 'extreme', tags: ['short', 'short', 'hack'] });
  assert.deepEqual(e.tags, ['short']);
  assert.equal(e.difficulty, 'low');
});

test('参照URLは http(s) のみ・重複除去・最大3件', () => {
  const refs = normalizeReferences([
    { url: 'javascript:alert(1)', title: 'x' },
    { url: 'https://a.example', title: 'A' },
    { url: 'https://a.example', title: 'A2' },
    { url: 'https://b.example' },
    { url: 'https://c.example', title: 'C' },
    { url: 'https://d.example', title: 'D' },
  ]);
  assert.deepEqual(refs, [
    { title: 'A', url: 'https://a.example' },
    { title: 'https://b.example', url: 'https://b.example' },
    { title: 'C', url: 'https://c.example' },
  ]);
});

test('チャット: needs_care のときは体験を付けない', () => {
  const raw = { reply: 'r', observations: [], needs_care: true, suggest_experience: true, experience: good().experience };
  const out = normalizeChatResult(raw, 'ai');
  assert.equal(out.needs_care, true);
  assert.equal(out.experience, null);
  assert.equal(out.suggest_experience, false);
});

test('チャット: 壊れた experience は捨てて返答だけ返す、reply が空ならエラー', () => {
  const out = normalizeChatResult({ reply: 'r', suggest_experience: true, experience: { title: '' } }, 'ai');
  assert.equal(out.experience, null);
  assert.throws(() => normalizeChatResult({ reply: ' ' }, 'ai'), SchemaError);
});

test('危険な提案を検出する', () => {
  const base = good().experience as unknown as Experience;
  for (const phrase of ['今夜は徹夜でやってみませんか？', '朝食を抜いてみませんか？', '運転しながら観察してみませんか？']) {
    assert.ok(findSafetyIssue({ ...base, invitation: phrase }), phrase);
  }
  assert.equal(findSafetyIssue(good().experience as never), null);
  assert.equal(findSafetyIssue(null), null);
});

test('強い苦痛のサインを検出する (誤検出しにくい普通の言葉は拾わない)', () => {
  assert.equal(detectCareNeed(['もう消えたい']), true);
  assert.equal(detectCareNeed(['リスカしそう']), true);
  assert.equal(detectCareNeed(['今日は疲れた', '宿題が面倒']), false);
});

test('振り返りの問い: 欠けていれば null、長すぎれば切り詰め、安全確認の対象にもする', () => {
  const base = { title: 't', perspective: 'p', invitation: 'i', reason: 'r', difficulty: 'low', tags: [] };
  assert.equal(normalizeExperience(base).reflection_question, null);
  assert.equal(normalizeExperience({ ...base, reflection_question: '  何が見えましたか？  ' }).reflection_question, '何が見えましたか？');
  assert.equal(Array.from(normalizeExperience({ ...base, reflection_question: 'あ'.repeat(200) }).reflection_question ?? '').length, 80);
  const experience = normalizeExperience({ ...base, reflection_question: '限界まで走れましたか？' });
  assert.equal(findSafetyIssue(experience), '心身への過度な負担');
});

test('体験の樹の上の位置: ライブラリだと名乗るのは名前が同じときだけ・伸びた先は届いた樹の中だけ', () => {
  const base = { title: 'ひと口目の観察', perspective: 'p', invitation: 'i', reason: 'r', difficulty: 'low', tags: [] };
  const library = normalizeExperience({ ...base, node_id: 'meal-first-bite', elements: [] });
  assert.equal(library.node_id, 'meal-first-bite');
  assert.deepEqual(library.elements, ['taste'], '要素が無ければライブラリの要素');

  const pretender = normalizeExperience({ ...base, title: '別の体験', node_id: 'meal-first-bite', elements: ['see', 'nope', 'see', 'hear', 'move', 'word'] });
  assert.equal(pretender.node_id, null);
  assert.deepEqual(pretender.elements, ['see', 'hear', 'move']);

  const lived = new Set(['root-hear']);
  assert.equal(normalizeExperience({ ...base, grows_from: 'root-hear' }, { livedIds: lived }).grows_from, 'root-hear');
  assert.equal(normalizeExperience({ ...base, grows_from: 'root-see' }, { livedIds: lived }).grows_from, null);
  assert.equal(normalizeExperience({ ...base, grows_from: 'root-hear' }).grows_from, null);
  assert.equal(normalizeExperience({ ...base, grows_from: '' }, { livedIds: lived }).grows_from, null);
});

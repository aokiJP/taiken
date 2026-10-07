// 指示書 §11 原則5 の最終防衛線と、強い苦痛のサインの検出。
// 主な防御はシステムプロンプトだが、明らかに危険な提案がUIへ届かないよう機械的にも確認する。
import type { Experience } from './types.ts';

const RISK_PATTERNS: ReadonlyArray<readonly [RegExp, string]> = [
  [/徹夜|寝ないで|睡眠を削|夜更かしして/, '睡眠を削る'],
  [/断食|絶食|(食事|朝食|昼食|夕食|朝ごはん|昼ごはん|晩ごはん|ご飯|ごはん)を抜|何も食べず|食べないで/, '食事を抜く'],
  [/運転中|運転しながら|歩きスマホ|自転車.{0,6}(片手|スマホ)/, '移動中の危険行為'],
  [/飲酒|お酒を飲|酔っ/, '飲酒'],
  [/無断で|勝手に入|立入禁止|盗|万引/, '違法・迷惑行為'],
  [/線路|屋上の端|高い所から|崖/, '危険な場所'],
  [/自分を傷つけ|痛みを感じ|限界まで|倒れるまで/, '心身への過度な負担'],
];

export function findSafetyIssue(experience: Experience | null | undefined): string | null {
  if (!experience) return null;
  const body = `${experience.title} ${experience.perspective} ${experience.invitation}`;
  for (const [pattern, label] of RISK_PATTERNS) if (pattern.test(body)) return label;
  return null;
}

// AIの判断 (needs_care) を補う機械的な検出。見逃しを減らす目的なので、広めに拾う。
const CARE_PATTERNS: readonly RegExp[] = [
  /死にたい|しにたい|死のう|消えたい|きえたい|いなくなりたい|生きていたくない|生きるのがつらい|生きてる意味/,
  /自殺|自死|自傷|リスカ|リストカット|首をつ|飛び降り|オーバードーズ|OD(し|する|した)/i,
  /殺したい|ころしたい/,
];

export function detectCareNeed(texts: readonly string[]): boolean {
  return texts.some((t) => CARE_PATTERNS.some((p) => p.test(t)));
}

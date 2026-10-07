// AI APIキーが無くても、AIが使えないときでもアプリ全体を動かせるルールベースの生成器。
// 本番のAIと同じ「生の結果」を返し、同じ正規化を通す。
import { detectCareNeed } from '../engine/safety.ts';
import type { ChatContext, ExperienceContext } from '../engine/types.ts';
import type { AiProvider } from './provider.ts';

interface Idea {
  title: string;
  perspective: string;
  invitation: string;
  tags: string[];
}

const THEMES: ReadonlyArray<{ theme: string; words: string[] }> = [
  { theme: '勉強', words: ['課題', '宿題', '勉強', '授業', '試験', 'テスト', 'レポート', '講義', '復習', '予習'] },
  { theme: '仕事', words: ['会議', 'ミーティング', 'MTG', '打ち合わせ', '仕事', '作業', '資料', '締切', 'レビュー'] },
  { theme: '移動', words: ['移動', '通勤', '通学', '電車', 'バス', '出発', '空港', '駅'] },
  { theme: '食事', words: ['ランチ', '昼食', '夕食', '朝食', 'ごはん', 'ご飯', '食事', 'ディナー'] },
  { theme: '家事', words: ['掃除', '洗濯', '片付け', '料理', '家事', 'ゴミ'] },
  { theme: '買い物', words: ['買い物', 'スーパー', '買い出し'] },
  { theme: '人との会話', words: ['電話', '面談', '飲み会', '友達', '家族', '会う'] },
];

const IDEAS: Record<string, Idea[]> = {
  勉強: [
    {
      title: 'つまずきの観察',
      perspective: '「終わらせる作業」ではなく、自分がどこで手を止めるかを観察する時間として見てみる。',
      invitation: '今日の勉強で、いちばん手が止まった瞬間を1つだけ覚えておいてみませんか？',
      tags: ['new_perspective', 'observation', 'short'],
    },
    {
      title: '昨日の自分への問い',
      perspective: '量をこなすことより、昨日の自分が分からなかったことを1つ見つける時間として捉える。',
      invitation: '今日は「昨日の自分なら分からなかったこと」を1つ探す気持ちで取り組んでみませんか？',
      tags: ['question', 'reflection'],
    },
  ],
  仕事: [
    {
      title: '一つの問いを持ち込む',
      perspective: '予定をこなす場ではなく、ひとつの疑問の答えを探しに行く場として見てみる。',
      invitation: 'この予定に「今日これだけは知りたい」という問いを1つだけ持って臨んでみませんか？',
      tags: ['question', 'new_perspective'],
    },
  ],
  移動: [
    {
      title: '移動の中の変化',
      perspective: '移動を「空白の時間」ではなく、いつもと違うものを見つける時間として捉える。',
      invitation: '次の移動で、昨日までは気づかなかったものを1つ見つけてみませんか？',
      tags: ['observation', 'sensory', 'short'],
    },
  ],
  食事: [
    {
      title: 'ひと口目の観察',
      perspective: '食事を「済ませるもの」ではなく、味や食感に気づく時間として見てみる。',
      invitation: '次の食事で、ひと口目にどんな味がしたかを少しだけ意識してみませんか？',
      tags: ['sensory', 'short'],
    },
  ],
  家事: [
    {
      title: 'ビフォーアフターを見る',
      perspective: '家事を「やらされること」ではなく、空間が変わっていく様子を見る時間として捉える。',
      invitation: '家事のあと、始める前と何が変わったかを一度だけ眺めてみませんか？',
      tags: ['observation', 'reflection', 'short'],
    },
  ],
  買い物: [
    {
      title: 'いつもと違う棚',
      perspective: '買い物を用事の消化ではなく、普段通らない場所を知る機会として見てみる。',
      invitation: '次の買い物で、いつもは見ない棚を一つだけ覗いてみませんか？',
      tags: ['new_perspective', 'small_challenge', 'short'],
    },
  ],
  人との会話: [
    {
      title: '一つの質問',
      perspective: '会話を情報交換ではなく、相手について新しく知る機会として捉える。',
      invitation: '次に話す人に、まだ聞いたことのない質問を1つしてみませんか？',
      tags: ['social', 'question'],
    },
  ],
  日常: [
    {
      title: 'いつもの中の違い',
      perspective: '何気ない時間を、昨日との小さな違いを見つける時間として捉える。',
      invitation: '今日のどこかで、昨日とは少し違うことを1つ見つけてみませんか？',
      tags: ['observation', 'short'],
    },
    {
      title: '手を止める一瞬',
      perspective: '次から次へ進む一日の中に、自分が何を感じているかに気づく間をつくる。',
      invitation: '次の切り替わりの前に、今の自分の感覚を一度だけ確かめてみませんか？',
      tags: ['reflection', 'short'],
    },
  ],
};

const TIRED_WORDS = ['疲れ', 'しんどい', 'だるい', '眠い', 'ねむい', '面倒', 'めんどう', 'めんどくさ'];

export const CARE_REPLY =
  '話してくれてありがとうございます。とてもつらい気持ちを抱えているのかもしれません。' +
  'ひとりで抱え込まずに、信頼できる人や専門の相談窓口に今の気持ちを話してみてください。下に相談先の案内を表示しています。';

function detectTheme(text: string | null | undefined): string | null {
  if (!text) return null;
  return THEMES.find((t) => t.words.some((w) => text.includes(w)))?.theme ?? null;
}

function pickIdea(theme: string, exclude: readonly string[], seed: number): Idea {
  const all = [...(IDEAS[theme] ?? []), ...(IDEAS['日常'] ?? [])];
  const pool = all.filter((i) => !exclude.includes(i.title));
  const candidates = pool.length ? pool : all;
  return candidates[seed % candidates.length] as Idea;
}

function hourOf(iso: string): number {
  const m = /T(\d{2}):/.exec(iso);
  return m?.[1] ? Number(m[1]) : 12;
}

export function createMockProvider(): AiProvider {
  return {
    name: 'mock',

    async generateExperience(ctx: ExperienceContext) {
      const now = Date.parse(ctx.current_time);
      const next = ctx.calendar_context
        .filter((e) => !e.is_all_day && Date.parse(e.end ?? e.start) >= now)
        .sort((a, b) => Date.parse(a.start) - Date.parse(b.start))[0];
      const said = ctx.recent_user_messages.join(' ');
      const tired = TIRED_WORDS.some((w) => said.includes(w));
      const theme = detectTheme(next?.title) ?? detectTheme(said) ?? '日常';
      const idea = pickIdea(theme, ctx.exclude_titles, ctx.exclude_titles.length);

      const observations: { text: string; basis: string }[] = [];
      const actions: { label: string; basis: string }[] = [];
      if (next) {
        const label = next.title ? `「${next.title}」の予定` : '内容不明の予定';
        observations.push({ text: `${next.start.slice(11, 16)}から${label}がある`, basis: 'calendar' });
        actions.push({ label: next.title ?? '予定', basis: 'calendar' });
      }
      if (tired) {
        observations.push({ text: '疲れや面倒さを口にしていた', basis: 'stated' });
        observations.push({ text: '今日は負担の少ない提案が合うかもしれない', basis: 'inferred' });
      }

      const minutesUntil = next ? (Date.parse(next.start) - now) / 60_000 : Number.POSITIVE_INFINITY;
      const hour = hourOf(ctx.current_time);
      const goodTiming = minutesUntil > 5 && minutesUntil <= 30 && hour >= 8 && hour < 22;

      return {
        situation: {
          summary: next ? `${next.title ? `「${next.title}」` : '予定'}が控えている時間帯。` : '目立った予定は見当たらない時間帯。',
          observations,
        },
        detected_actions: actions,
        possible_obligations:
          theme === '日常' ? [] : [{ label: `${theme}に取り組む必要がある可能性`, likelihood: next ? 0.6 : 0.4 }],
        experience_opportunities: [idea.perspective],
        is_obligation: ['勉強', '仕事', '家事'].includes(theme),
        confidence: next ? 0.6 : 0.35,
        experience: {
          ...idea,
          reason: tired
            ? '疲れていると話していたので、量ではなく小さな気づきに向けた提案にしました。'
            : next
              ? 'これからの予定を、少し違う視点で迎えられるかもしれないため。'
              : '特別な予定がなくても、いつもの時間の中に体験は見つけられるため。',
          difficulty: 'low',
        },
        should_notify: goodTiming,
        notification: goodTiming ? { title: 'もうすぐの予定に、ひとつの視点を', body: idea.invitation } : undefined,
      };
    },

    async chat(ctx: ChatContext) {
      const last = ctx.messages.at(-1)?.text ?? '';
      const observations = [{ text: last.length > 60 ? `${last.slice(0, 60)}…` : last, basis: 'stated' }];

      if (detectCareNeed([last])) {
        return { reply: CARE_REPLY, observations: [], needs_care: true, suggest_experience: false };
      }

      const tired = TIRED_WORDS.some((w) => last.includes(w));
      const theme = detectTheme(last);
      const wantsIdea = theme !== null || /暇|何か|なにか|何したら|どうしよう/.test(last);

      if (!wantsIdea) {
        return {
          reply: tired
            ? 'そうなんですね。今は無理に何かしなくても大丈夫です。少し休んでからでも、また話しかけてください。'
            : '聞かせてくれてありがとうございます。今日はこのあと、何か予定していることはありますか？',
          observations,
          needs_care: false,
          suggest_experience: false,
        };
      }
      const idea = pickIdea(theme ?? '日常', [], 0);
      return {
        reply: 'よければ、それを少し違う角度から見る提案をしてみますね。合わなければ流してください。',
        observations,
        needs_care: false,
        suggest_experience: true,
        experience: { ...idea, reason: '会話の中で話していたことから、小さく試せる視点を選びました。', difficulty: 'low' },
      };
    },
  };
}

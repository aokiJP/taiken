// AI APIキーが無くても、AIが使えないときでもアプリ全体を動かせる生成器。
// 体験ライブラリ (contracts/content.ja.json) から、予定・気分・時間帯・季節・最近の反応に合うものを選ぶ。
// iOS の端末内の提案と同じ選び方をし、本番のAIと同じ「生の結果」を返して同じ正規化を通す。
import {
  choose,
  dayNumberOf,
  detectMood,
  detectThemes,
  fnv1a,
  moodLabel,
  parentOf,
  reasonFor,
  TIME_LABELS,
  timeOfDayOf,
} from '../content/library.ts';
import { localHour } from '../engine/notificationPolicy.ts';
import { detectCareNeed } from '../engine/safety.ts';
import type { ChatContext, ExperienceContext } from '../engine/types.ts';
import type { AiProvider } from './provider.ts';

export const CARE_REPLY =
  '話してくれてありがとうございます。とてもつらい気持ちを抱えているのかもしれません。' +
  'ひとりで抱え込まずに、信頼できる人や専門の相談窓口に今の気持ちを話してみてください。下に相談先の案内を表示しています。';

export const TIRED_REPLIES = [
  'そうなんですね。今は無理に何かしなくても大丈夫です。気が向いたら「何か提案して」と声をかけてください。',
  'おつかれさまです。休むのも、立派な過ごし方です。また話したくなったら、いつでもどうぞ。',
];
export const LISTENING_REPLIES = [
  '聞かせてくれてありがとうございます。このあと、何か予定していることはありますか？',
  'なるほど。今日はこのあと、どんな時間になりそうですか？',
  'そうなんですね。よければ、もう少し聞かせてください。',
];
export const IDEA_REPLIES = [
  'それなら、いつもの時間を少し違う角度から見る提案をひとつ。合わなければ流してください。',
  'こんな見方はどうでしょう。気が向いたらで大丈夫です。',
];
const ASKING = /暇|ひま|何か|なにか|何したら|何しよう|どうしよう|提案|おすすめ|アイデア|退屈/;
const OBLIGATIONS: Record<string, string> = { study: '勉強', work: '仕事', housework: '家事' };

const clockText = (iso: string) => iso.slice(11, 16);

export function createMockProvider(): AiProvider {
  return {
    name: 'mock',

    async generateExperience(ctx: ExperienceContext) {
      const now = Date.parse(ctx.current_time);
      const next = ctx.calendar_context
        .filter((e) => !e.is_all_day && e.day === 'today' && Date.parse(e.end ?? e.start) >= now)
        .sort((a, b) => Date.parse(a.start) - Date.parse(b.start))[0];
      const hour = localHour(ctx.current_time);
      const tod = timeOfDayOf(hour);

      const choice = choose({
        day: dayNumberOf(ctx.current_time),
        timeOfDay: tod,
        eventTitle: next?.title ?? null,
        messages: ctx.recent_user_messages,
        mood: ctx.mood,
        feedback: ctx.user_feedback,
        recentTitles: ctx.recent_experiences.map((e) => e.title),
        excludeTitles: ctx.exclude_titles,
        buds: ctx.tree?.buds ?? [],
      });
      const picked = choice.experience;
      const parent = parentOf(picked, ctx.tree);

      const observations: { text: string; basis: string }[] = [];
      const actions: { label: string; basis: string }[] = [];
      if (next) {
        const label = next.title ? `「${next.title}」の予定` : '内容不明の予定';
        observations.push({ text: `${clockText(next.start)}から${label}がある`, basis: 'calendar' });
        actions.push({ label: next.title ?? '予定', basis: 'calendar' });
      }
      if (ctx.mood) {
        observations.push({ text: `いまの気分に「${moodLabel(ctx.mood)}」を選んでいた`, basis: 'stated' });
      } else if (choice.mood === 'tired') {
        observations.push({ text: '疲れや面倒さを口にしていた', basis: 'stated' });
        observations.push({ text: '今日は負担の少ない提案が合うかもしれない', basis: 'inferred' });
      }
      if (parent) observations.push({ text: `体験帳に「${parent.title}」が記されている`, basis: 'stated' });

      const obligation = [...choice.themesFromEvent].find((t) => t in OBLIGATIONS);
      const minutesUntil = next ? (Date.parse(next.start) - now) / 60_000 : Number.POSITIVE_INFINITY;
      const goodTiming = minutesUntil > 5 && minutesUntil <= 30 && hour >= 8 && hour < 22;
      const part = TIME_LABELS[tod];

      return {
        situation: {
          summary: next
            ? next.title
              ? `「${next.title}」が控えている${part}。`
              : `予定が控えている${part}。`
            : `目立った予定は見当たらない${part}。`,
          observations,
        },
        detected_actions: actions,
        possible_obligations: obligation ? [{ label: `${OBLIGATIONS[obligation]}に取り組む必要がある可能性`, likelihood: 0.6 }] : [],
        experience_opportunities: [picked.perspective],
        is_obligation: obligation !== undefined,
        confidence: next ? 0.6 : 0.4,
        experience: {
          title: picked.title,
          perspective: picked.perspective,
          invitation: picked.invitation,
          reason: reasonFor(choice, next?.title ?? null, next !== undefined, parent),
          difficulty: picked.effort,
          tags: picked.tags,
          reflection_question: picked.reflection_question,
          node_id: picked.id,
          elements: picked.elements,
          grows_from: parent?.id ?? null,
        },
        should_notify: goodTiming,
        notification: goodTiming ? { title: 'もうすぐの予定に、ひとつの視点を', body: picked.invitation } : undefined,
      };
    },

    async chat(ctx: ChatContext) {
      const userTexts = ctx.messages.filter((m) => m.role === 'user').map((m) => m.text);
      const last = userTexts.at(-1) ?? '';
      if (detectCareNeed(userTexts.slice(-3))) {
        return { reply: CARE_REPLY, observations: [], needs_care: true, suggest_experience: false };
      }

      const observations = [{ text: last.length > 60 ? `${last.slice(0, 60)}…` : last, basis: 'stated' }];
      const mood = detectMood([last]);
      const themes = detectThemes([last]);
      const pick = fnv1a(last) % 997;

      if (themes.size === 0 && !ASKING.test(last)) {
        const pool = mood === 'tired' ? TIRED_REPLIES : LISTENING_REPLIES;
        return { reply: pool[pick % pool.length], observations, needs_care: false, suggest_experience: false };
      }

      const now = Date.parse(ctx.current_time);
      const next = ctx.calendar_context.find((e) => !e.is_all_day && e.day === 'today' && Date.parse(e.end ?? e.start) >= now);
      const choice = choose({
        day: dayNumberOf(ctx.current_time),
        timeOfDay: timeOfDayOf(localHour(ctx.current_time)),
        eventTitle: themes.size === 0 ? (next?.title ?? null) : null,
        messages: [last],
        mood,
        feedback: [],
        recentTitles: [],
        excludeTitles: ctx.current_experience ? [ctx.current_experience.title] : [],
        buds: [],
      });
      const picked = choice.experience;
      return {
        reply: IDEA_REPLIES[pick % IDEA_REPLIES.length],
        observations,
        needs_care: false,
        suggest_experience: true,
        experience: {
          title: picked.title,
          perspective: picked.perspective,
          invitation: picked.invitation,
          reason: '会話の中で話していたことから、小さく試せる視点を選びました。',
          difficulty: picked.effort,
          tags: picked.tags,
          reflection_question: picked.reflection_question,
          node_id: picked.id,
          elements: picked.elements,
          grows_from: null,
        },
      };
    },
  };
}

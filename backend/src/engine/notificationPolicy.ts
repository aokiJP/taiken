// 指示書 §12: 「価値がある AND 今が適切 AND 負担をかけない」ときだけ通知する。
// AIの判断に加えて、サーバー側でも決定的なルールで絞る。iOS側にもユーザー設定による最終判断がある。
import type { ExperienceContext, ExperienceResult } from './types.ts';

export const NOTIFY_POLICY = Object.freeze({
  minConfidence: 0.55,
  quietStartHour: 22,
  quietEndHour: 8,
  maxRecentDeclines: 2,
});

export type NotifyPolicy = typeof NOTIFY_POLICY;

/** iOSは端末のタイムゾーン付きISO文字列を送るので、文字列の時刻部分がローカル時刻 */
export function localHour(iso: string): number {
  const m = /T(\d{2}):/.exec(iso);
  return m?.[1] ? Number(m[1]) : 12;
}

export function applyNotificationPolicy(
  result: ExperienceResult,
  ctx: ExperienceContext,
  policy: NotifyPolicy = NOTIFY_POLICY,
): ExperienceResult {
  if (!result.should_notify) return result;
  const hour = localHour(ctx.current_time);
  const quiet = hour >= policy.quietStartHour || hour < policy.quietEndHour;
  const declines = ctx.recent_experiences.filter((e) => e.reaction === 'declined').length;
  const allowed =
    result.source !== 'fallback' && // 代替生成では通知しない

    result.confidence >= policy.minConfidence &&
    !quiet &&
    declines < policy.maxRecentDeclines;
  return allowed ? result : { ...result, should_notify: false, notification: null };
}

import type { ChatContext, ExperienceContext, ResearchResult, Usage } from '../engine/types.ts';

export interface CallOptions {
  signal: AbortSignal;
  /** AI API が実際に消費した量を通知する (予算管理用) */
  onUsage: (usage: Usage) => void;
}

/**
 * AIの呼び出し口。戻り値は「生の構造化結果」で、必ずエンジン側の正規化を通してから使う。
 */
export interface AiProvider {
  readonly name: 'anthropic' | 'mock';
  generateExperience(ctx: ExperienceContext, research: ResearchResult | null, options: CallOptions): Promise<unknown>;
  chat(ctx: ChatContext, options: CallOptions): Promise<unknown>;
  /** 外部情報が必要か判断し、必要なら検索して要約する。不要なら null */
  research?(ctx: ExperienceContext, options: CallOptions): Promise<ResearchResult | null>;
}

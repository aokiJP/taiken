// Anthropic Messages API を使う体験生成。
// - 体験生成・会話: tool use を強制し、構造化JSONだけを受け取る
// - 下調べ: 必要なときだけ web_search サーバーツールを使い、要約と参照URLだけを取り出す
import { CHAT_TOOL, EXPERIENCE_TOOL, normalizeReferences, type ToolDefinition } from '../engine/schema.ts';
import { cleanText } from '../engine/sanitize.ts';
import type { ExperienceContext, Reference, Usage } from '../engine/types.ts';
import {
  CHAT_SYSTEM_PROMPT,
  EXPERIENCE_SYSTEM_PROMPT,
  NO_SEARCH_MARKER,
  RESEARCH_SYSTEM_PROMPT,
  chatContextNote,
  experienceUserMessage,
  researchUserMessage,
} from '../prompts.ts';
import { UpstreamError, type AnthropicClient, type ContentBlock, type MessageRequest, type MessageResponse } from './anthropicClient.ts';
import type { AiProvider, CallOptions } from './provider.ts';

export interface AnthropicProviderOptions {
  client: AnthropicClient;
  models: { experience: string; chat: string; research: string };
  webSearch: { toolType: string; maxUses: number };
}

export function usageOf(res: MessageResponse): Usage {
  return {
    inputTokens: res.usage.input_tokens ?? 0,
    outputTokens: res.usage.output_tokens ?? 0,
    webSearches: res.usage.server_tool_use?.web_search_requests ?? 0,
  };
}

function toolInput(res: MessageResponse, tool: ToolDefinition): unknown {
  const block = res.content.find((b) => b.type === 'tool_use' && b.name === tool.name);
  if (!block) throw new UpstreamError('AI APIの応答に構造化結果がありません', { kind: 'invalid_response' });
  return block.input;
}

export function webSearchTool(ctx: ExperienceContext, toolType: string, maxUses: number): Record<string, unknown> {
  const location: Record<string, string> = { type: 'approximate', timezone: ctx.time_zone };
  if (ctx.area?.locality) location.city = ctx.area.locality;
  if (ctx.area?.administrative_area) location.region = ctx.area.administrative_area;
  if (ctx.area?.country_code) location.country = ctx.area.country_code;
  return { type: toolType, name: 'web_search', max_uses: maxUses, user_location: location };
}

/** 応答から本文テキストと引用元を取り出す */
export function extractResearch(contents: ContentBlock[]): { summary: string; references: Reference[] } {
  const texts: string[] = [];
  const cited: unknown[] = [];
  const results: unknown[] = [];
  for (const block of contents) {
    if (block.type === 'text' && typeof block.text === 'string') {
      texts.push(block.text);
      if (Array.isArray(block.citations)) cited.push(...block.citations);
    } else if (block.type === 'web_search_tool_result' && Array.isArray(block.content)) {
      results.push(...block.content);
    }
  }
  const summary = cleanText(texts.join('').replace(NO_SEARCH_MARKER, ''), 600) ?? '';
  // 本文で実際に引用されたものを優先し、無ければ検索結果の上位を使う
  const references = normalizeReferences(cited.length ? cited : results);
  return { summary, references };
}

export function createAnthropicProvider(options: AnthropicProviderOptions): AiProvider {
  const { client, models, webSearch } = options;

  async function forcedTool(
    request: Omit<MessageRequest, 'tools' | 'tool_choice'>,
    tool: ToolDefinition,
    call: CallOptions,
  ): Promise<unknown> {
    const res = await client.createMessage(
      { ...request, tools: [tool as unknown as Record<string, unknown>], tool_choice: { type: 'tool', name: tool.name } },
      call.signal,
    );
    call.onUsage(usageOf(res));
    return toolInput(res, tool);
  }

  return {
    name: 'anthropic',

    generateExperience(ctx, research, call) {
      return forcedTool(
        {
          model: models.experience,
          max_tokens: 1500,
          system: EXPERIENCE_SYSTEM_PROMPT,
          messages: [{ role: 'user', content: experienceUserMessage(ctx, research) }],
        },
        EXPERIENCE_TOOL,
        call,
      );
    },

    chat(ctx, call) {
      // 会話は user/assistant が交互である必要があるため、連続する同じ役割をまとめる
      const turns: { role: 'user' | 'assistant'; content: string }[] = [];
      for (const m of ctx.messages) {
        const last = turns.at(-1);
        if (last && last.role === m.role) last.content += `\n${m.text}`;
        else turns.push({ role: m.role, content: m.text });
      }
      if (turns[0]?.role === 'assistant') turns.unshift({ role: 'user', content: '(会話開始)' });
      const final = turns.at(-1);
      if (final) final.content = `${chatContextNote(ctx)}\n\n${final.content}`;

      return forcedTool({ model: models.chat, max_tokens: 1000, system: CHAT_SYSTEM_PROMPT, messages: turns }, CHAT_TOOL, call);
    },

    async research(ctx, call) {
      const messages: MessageRequest['messages'] = [{ role: 'user', content: researchUserMessage(ctx) }];
      const collected: ContentBlock[] = [];
      let searches = 0;

      // pause_turn の場合は、受け取った内容をそのまま返して続きを依頼する (最大2回)
      for (let round = 0; round < 3; round++) {
        const res = await client.createMessage(
          {
            model: models.research,
            max_tokens: 800,
            system: RESEARCH_SYSTEM_PROMPT,
            messages,
            tools: [webSearchTool(ctx, webSearch.toolType, webSearch.maxUses)],
          },
          call.signal,
        );
        const usage = usageOf(res);
        call.onUsage(usage);
        searches += usage.webSearches;
        collected.push(...res.content);
        if (res.stop_reason !== 'pause_turn') break;
        messages.push({ role: 'assistant', content: res.content });
      }

      const { summary, references } = extractResearch(collected);
      if (searches === 0 || !summary) return null;
      return { summary, references, searches };
    },
  };
}

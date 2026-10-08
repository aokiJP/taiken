import SwiftUI
import TaikenCore

/// 話す (指示書 §7)。静かな話し相手。会話は端末にも保存しない。
/// 休みたい・聞いてほしいだけのときは提案しない。強いつらさのサインがあれば、その場に相談先を出す。
struct ChatView: View {
    @Bindable var model: ChatViewModel
    let engine: ProposalEngine

    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.messages) { message in
                            MessageRow(
                                message: message,
                                adopt: {
                                    model.adopt(message)
                                    dismiss()
                                },
                                dismissSuggestion: { model.dismissSuggestion(message) },
                                retry: { Task { await model.retry(message) } }
                            )
                            .id(message.id)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
                        }
                        if model.isSending {
                            TypingRow()
                                .id(Self.typingID)
                                .transition(.opacity)
                        }
                        if model.showsQuickReplies {
                            FlowLayout(spacing: 8) {
                                ForEach(ChatViewModel.quickReplies, id: \.self) { text in
                                    Button(text) { Task { await model.send(quickReply: text) } }
                                        .buttonStyle(ChipButtonStyle())
                                }
                            }
                            .padding(.leading, 36)
                            .transition(.opacity)
                        }
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(Palette.ink2)
                                .padding(.leading, 36)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: model.messages.count)
                    .animation(.easeOut(duration: 0.2), value: model.isSending)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) {
                    guard let last = model.messages.last?.id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: model.isSending) {
                    guard model.isSending else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo(Self.typingID, anchor: .bottom) }
                }
            }
            .background(Palette.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("話す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("最初から") { model.reset() }
                        .tint(Palette.ink)
                        .disabled(model.isSending || model.showsQuickReplies)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CloseToolbarButton()
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .onAppear {
            // 開いた時刻に合ったあいさつにする (まだ何も話していないときだけ)
            if model.showsQuickReplies, model.draft.isEmpty { model.reset() }
        }
        // 返事が届いたときだけ、軽く知らせる
        .sensoryFeedback(.impact(weight: .light), trigger: model.messages.last(where: { $0.role == .assistant })?.id)
    }

    private static let typingID = "typing"

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("いまの気分や、これからのこと", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .accessibilityIdentifier("chat.input")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.onShu)
                        .frame(width: 42, height: 42)
                        .background(Palette.shu, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .opacity(model.canSend ? 1 : 0.35)
                .accessibilityLabel("送る")
            }
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(Palette.ink3)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Palette.paper.opacity(0.96))
    }

    private var footnote: String {
        ["会話はこの端末にも保存されません。", engine.chatNote].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - 1行ぶん

private struct MessageRow: View {
    let message: ChatMessage
    let adopt: @MainActor () -> Void
    let dismissSuggestion: @MainActor () -> Void
    let retry: @MainActor () -> Void

    var body: some View {
        switch message.role {
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                SealView(character: "体", size: 26, style: .outlined, rotation: -4)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 12) {
                    Text(message.text)
                        .font(.callout)
                        .lineSpacing(5)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if message.needsCare {
                        SupportCard()
                    }
                    if let suggestion = message.suggestion {
                        SuggestionCard(
                            experience: suggestion, handled: message.suggestionHandled,
                            adopt: adopt, dismiss: dismissSuggestion
                        )
                    }
                }
                Spacer(minLength: 28)
            }
        case .user:
            HStack {
                Spacer(minLength: 56)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.text)
                        .font(.callout)
                        .lineSpacing(4)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Palette.shuSoft,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18,
                                style: .continuous
                            )
                        )
                        .opacity(message.failed ? 0.55 : 1)
                        .textSelection(.enabled)
                    if message.failed {
                        Button(action: retry) {
                            Label("届きませんでした — もう一度送る", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .tint(Palette.shu)
                    }
                }
            }
        }
    }
}

/// 会話の流れで出てきた体験の提案
private struct SuggestionCard: View {
    let experience: Experience
    let handled: Bool
    let adopt: @MainActor () -> Void
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(experience.invitation)
                .font(Typeface.mincho(16))
                .lineSpacing(5)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Signature(title: experience.title)
            if !handled {
                HStack(spacing: 8) {
                    Button("やってみる", action: adopt)
                        .buttonStyle(ShuButtonStyle(compact: true))
                    Button("今はいい", action: dismiss)
                        .buttonStyle(QuietButtonStyle(compact: true))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .opacity(handled ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.25), value: handled)
    }
}

/// 返事を考えているあいだの、三つの点
private struct TypingRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SealView(character: "体", size: 26, style: .outlined, rotation: -4)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    PhaseAnimator([false, true]) { on in
                        Circle()
                            .fill(Palette.ink3)
                            .frame(width: 6, height: 6)
                            .offset(y: on ? -3 : 1)
                            .opacity(on ? 1 : 0.45)
                    } animation: { _ in
                        reduceMotion ? nil : .easeInOut(duration: 0.5).delay(Double(index) * 0.15)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("返事を考えています")
    }
}

#Preview {
    ChatView(model: AppDependencies.preview().chat, engine: .library)
}

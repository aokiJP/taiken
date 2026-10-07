import SwiftUI
import TaikenCore

struct ChatView: View {
    @Bindable var model: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.showsCareResources {
                            SupportCard()
                        }
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
                        }
                        if model.isSending {
                            ProgressView()
                                .padding(.leading, 8)
                                .id("typing")
                        }
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) {
                    guard let last = model.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: model.isSending) {
                    if model.isSending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("最初から") { model.reset() }
                        .disabled(model.isSending)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("いまの気分や、これからのこと", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                    .submitLabel(.send)
                    .onSubmit { Task { await model.send() } }

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(!model.canSend)
                .accessibilityLabel("送信")
            }
            Text("会話はこの端末にも保存されません。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let adopt: @MainActor () -> Void
    let dismissSuggestion: @MainActor () -> Void
    let retry: @MainActor () -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                .opacity(message.failed ? 0.6 : 1)

            if message.failed {
                Button("もう一度送る", systemImage: "arrow.clockwise", action: retry)
                    .font(.caption)
            }

            if let suggestion = message.suggestion {
                SuggestionCard(experience: suggestion, handled: message.suggestionHandled, adopt: adopt, dismiss: dismissSuggestion)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct SuggestionCard: View {
    let experience: Experience
    let handled: Bool
    let adopt: @MainActor () -> Void
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(experience.title)
                .font(.subheadline.weight(.semibold))
            Text(experience.invitation)
                .font(.system(.callout, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if !handled {
                HStack {
                    Button("やってみる", action: adopt)
                        .buttonStyle(.borderedProminent)
                    Button("今はいい", action: dismiss)
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: 300, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .opacity(handled ? 0.6 : 1)
    }
}

#Preview {
    ChatView(model: AppDependencies.preview().chat)
}

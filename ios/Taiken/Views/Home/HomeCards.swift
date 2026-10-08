import SwiftUI
import TaikenCore

// MARK: - 眺めているあいだ

/// 提案を待つあいだ: 朱の三つの雫と、移り変わる一行
struct LoadingCard: View {
    @State private var line = 0
    private let lines = ["いつもの一日を眺めています…", "予定のすき間を探しています…", "視点をひとつ選んでいます…"]

    var body: some View {
        PaperCard {
            VStack(spacing: 16) {
                InkDrops()
                Text(lines[line % lines.count])
                    .font(Typeface.mincho(15))
                    .foregroundStyle(Palette.ink2)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: line)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                line += 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("体験を選んでいます")
    }
}

struct InkDrops: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3, id: \.self) { index in
                PhaseAnimator([false, true]) { on in
                    Circle()
                        .fill(Palette.shu)
                        .frame(width: 9, height: 9)
                        .scaleEffect(on ? 1 : 0.55)
                        .opacity(on ? 1 : 0.35)
                } animation: { _ in
                    reduceMotion ? nil : .easeInOut(duration: 0.6).delay(Double(index) * 0.18)
                }
            }
        }
    }
}

// MARK: - 今日の体験

struct ProposalCard: View {
    let response: ExperienceResponse
    let isLoading: Bool
    let tryIt: @MainActor () -> Void
    let another: @MainActor () -> Void
    let notNow: @MainActor () -> Void
    let showInsight: @MainActor () -> Void
    @State private var showsReason = false

    private var experience: Experience { response.experience }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Eyebrow(text: "今日の体験")
                    if let source = sourceLabel {
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(Palette.ink2)
                            .background(Palette.line, in: Capsule())
                    }
                    Spacer()
                    Button(action: showInsight) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(Palette.ink3)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(response.source.isGenerative ? "AIが見たこと" : "提案の手がかり")
                }

                Text(experience.invitation)
                    .font(.invitation)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .inkReveal(delay: 0.05)

                Signature(title: experience.title)
                    .padding(.top, 14)
                    .inkReveal(delay: 0.28)

                Text(experience.perspective)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .inkReveal(delay: 0.42)

                DisclosureGroup(isExpanded: $showsReason) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(experience.reason)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        let labels = ExperienceTag.displayLabels(experience.tags)
                        if !labels.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(labels, id: \.self) { label in
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.ink2)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("なぜ今？")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
                .tint(Palette.ink3)
                .padding(.top, 12)

                VStack(spacing: 10) {
                    Button("やってみる", action: tryIt)
                        .buttonStyle(ShuButtonStyle())
                    HStack(spacing: 10) {
                        Button(action: another) {
                            HStack(spacing: 6) {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "shuffle")
                                }
                                Text("別の視点")
                            }
                        }
                        .buttonStyle(QuietButtonStyle())
                        Button("今はやらない", action: notNow)
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.top, 16)
                .disabled(isLoading)
            }
        }
        .opacity(isLoading ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }

    /// AIが生成したものではないときだけ、出所を小さく添える
    private var sourceLabel: String? {
        switch response.source {
        case .local, .fallback: "体験ライブラリ"
        case .onDevice: "端末内のAI"
        case .ai, .mock: nil
        }
    }
}

// MARK: - 体験中

struct ActiveCard: View {
    let entry: HistoryEntry
    let finish: @MainActor () -> Void
    let abandon: @MainActor () -> Void
    let presenceChanged: @MainActor (Bool) -> Void
    @AppStorage(PresenceKey.enabled) private var presenceEnabled = true
    @State private var confirmsAbandon = false

    var body: some View {
        PaperCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    SealView(character: entry.sealCharacter, size: 22, style: .filled, rotation: -6)
                    Eyebrow(text: "体験中", color: Palette.shu)
                    Spacer()
                    Text("\(entry.createdAt.formatted(date: .omitted, time: .shortened))に始めました")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }

                Text(entry.invitation)
                    .font(.invitation)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Signature(title: entry.title)
                    .padding(.top, 14)

                if let question = entry.reflectionQuestion {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("終わったら、思い出してみてください")
                            .font(.caption2)
                            .tracking(1)
                            .foregroundStyle(Palette.ink3)
                        Text(question)
                            .font(.question)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.shuSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.top, 16)
                }

                Toggle(isOn: $presenceEnabled) {
                    Text("ロック画面に置いておく")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                .tint(Palette.toggle)
                .padding(.top, 14)
                .onChange(of: presenceEnabled) { _, enabled in presenceChanged(enabled) }

                VStack(spacing: 6) {
                    Button(action: finish) {
                        Text("終えた — 記す")
                    }
                    .buttonStyle(ShuButtonStyle())
                    Button("この体験をやめる") { confirmsAbandon = true }
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 8)
                }
                .padding(.top, 16)
            }
        }
        .confirmationDialog("この体験をやめますか？", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("やめる", role: .destructive, action: abandon)
        } message: {
            Text("評価はせずに終わります。体験帳には残りません。")
        }
    }
}

// MARK: - 記したところ

/// 印が押される瞬間。重さのある動きと触覚で、終えたことを確かめる
struct CompletedCard: View {
    let entry: HistoryEntry
    let season: MicroSeason
    let another: @MainActor () -> Void
    let openJournal: @MainActor () -> Void
    @State private var stamped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PaperCard {
            VStack(spacing: 0) {
                SealView(character: entry.sealCharacter, size: 96, style: .filled, rotation: stamped ? -6 : -16)
                    .scaleEffect(stamped ? 1 : 2.1)
                    .opacity(stamped ? 1 : 0)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                Text("体験帳に記しました")
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 18)
                Text("\(entry.title) · \(season.name)の頃")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 6)
                if let note = entry.note {
                    Text("「\(note)」")
                        .font(Typeface.mincho(15))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                Text("次の体験は、気が向いたときに。")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Button("もうひとつ受け取る", action: another)
                        .buttonStyle(QuietButtonStyle())
                    Button("体験帳をひらく", action: openJournal)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 8)
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.55)) {
                stamped = true
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - ひと休み

struct RestingCard: View {
    var title = "今は、ひと休み。"
    var message: String?
    var actionTitle = "今すぐ受け取る"
    var until: Date?
    let wake: @MainActor () -> Void

    init(until: Date, wake: @escaping @MainActor () -> Void) {
        self.until = until
        self.wake = wake
    }

    init(title: String, message: String, actionTitle: String, wake: @escaping @MainActor () -> Void) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.wake = wake
    }

    var body: some View {
        PaperCard {
            VStack(spacing: 0) {
                if until != nil {
                    SealView(character: "休", size: 60, style: .ghost, rotation: 0)
                        .padding(.top, 6)
                }
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 14)
                Text(detail)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Button(actionTitle, action: wake)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var detail: String {
        if let message { return message }
        guard let until else { return "" }
        return "断っても、何も減りません。\n次の提案は \(until.formatted(date: .omitted, time: .shortened)) ごろに用意しておきます。"
    }
}

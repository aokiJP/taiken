import SwiftUI
import TaikenCore

struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
}

/// 事実と推測を見た目で区別する (指示書 §7, §9)
struct SituationNoteRow: View {
    let note: SituationNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(note.basis.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(note.basis.isFact ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12), in: .capsule)
            Text(note.text)
                .font(.footnote)
                .italic(!note.basis.isFact)
                .foregroundStyle(note.basis.isFact ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 強いつらさのサインがあったときの相談先の案内
struct SupportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ひとりで抱えないでください", systemImage: "heart.text.square")
                .font(.subheadline.weight(.semibold))
            Text(SupportResources.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(destination: SupportResources.url) {
                Label(SupportResources.title, systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

extension Basis {
    var label: String {
        switch self {
        case .calendar: "予定"
        case .stated: "あなたの言葉"
        case .inferred: "推測"
        }
    }
}

extension Rating {
    var symbolName: String {
        switch self {
        case .positive: "hand.thumbsup"
        case .neutral: "minus.circle"
        case .negative: "hand.thumbsdown"
        }
    }
}

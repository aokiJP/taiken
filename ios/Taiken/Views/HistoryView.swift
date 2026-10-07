import SwiftUI
import TaikenCore

/// 体験履歴と最近の傾向 (指示書 §15, §16)。傾向は「最近こういう反応が多い」の表現にとどめる。
struct HistoryView: View {
    let model: HistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                if !model.trends.isEmpty {
                    Section {
                        ForEach(model.trends) { trend in
                            Label(trend.sentence, systemImage: icon(for: trend.direction))
                                .font(.footnote)
                        }
                    } header: {
                        Text("最近の傾向")
                    } footer: {
                        Text("最近の反応から計算した目安です。あなたがどんな人かを決めつけるものではなく、古い反応ほど影響は小さくなります。")
                    }
                }

                if model.isEmpty {
                    ContentUnavailableView("まだ体験はありません", systemImage: "sparkles", description: Text("Homeで「やってみる」を選ぶと、ここに残ります。"))
                }

                ForEach(model.sections) { section in
                    Section(section.day.formatted(.dateTime.month().day().weekday())) {
                        ForEach(section.entries) { entry in
                            HistoryRow(entry: entry)
                        }
                        .onDelete { offsets in
                            for index in offsets { model.delete(section.entries[index]) }
                            refreshExport()
                        }
                    }
                }

                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("体験の履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("書き出す", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                model.reload()
                refreshExport()
            }
            .onDisappear(perform: removeExport)
        }
    }

    private func icon(for direction: PreferenceTrends.Direction) -> String {
        switch direction {
        case .positive: "arrow.up.right"
        case .negative: "arrow.down.right"
        case .mixed: "arrow.left.and.right"
        }
    }

    /// 履歴をJSONファイルにして共有できるようにする (一時フォルダ・閉じたら消す)
    private func refreshExport() {
        removeExport()
        guard let data = try? model.exportJSON() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("taiken-history.json")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private func removeExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.rating?.emoji ?? (entry.status == .active ? "…" : "・"))
                Text(entry.title).font(.callout.weight(.semibold))
                Spacer()
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.invitation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let note = entry.note {
                Text("「\(note)」")
                    .font(.footnote)
            }
            if !entry.tags.isEmpty {
                Text(entry.tags.map(ExperienceTag.label).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

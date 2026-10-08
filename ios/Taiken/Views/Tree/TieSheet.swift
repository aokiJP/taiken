import SwiftUI
import TaikenCore

/// 結ぶ: 灯った体験どうしを、朱の糸で結ぶ。何が響き合ったかを、ひとことだけ添えられる。
/// ライブラリのつながりとは別の、自分だけのつながり。
struct TieSheet: View {
    let model: TreeViewModel
    let nodeID: String

    @State private var partner: String?
    @State private var note = ""
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private static let noteLimit = 40

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let node = model.node(nodeID) {
                        Text("「\(node.title)」と響き合った体験を選んでください。灯った体験どうしを結べます。")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let candidates = filteredCandidates
                    if model.tieCandidates(for: nodeID).isEmpty {
                        LinedBox {
                            Text("結べる灯った体験が、まだほかにありません。別の体験を記すと、ここに並びます。")
                                .font(.footnote)
                                .foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            MiniHead("結ぶ相手")
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Palette.ink3)
                                TextField("名前で探す", text: $query)
                                    .font(.callout)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Palette.wash, in: Capsule())
                            ForEach(candidates) { candidate in
                                Button {
                                    partner = candidate.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: partner == candidate.id ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(partner == candidate.id ? Palette.shu : Palette.ink3)
                                        SealView(character: model.tree.glyph(of: candidate), size: 24, style: .outlined, rotation: -4)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.title)
                                                .font(.experienceTitle)
                                                .foregroundStyle(Palette.ink)
                                            Text(model.caption(of: candidate.id))
                                                .font(.caption)
                                                .foregroundStyle(Palette.ink3)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(partner == candidate.id ? .isSelected : [])
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                MiniHead("何が響き合ったか（なくてもよい）")
                                Spacer()
                                Text("\(note.count)/\(Self.noteLimit)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.ink3)
                            }
                            TextField("例: どちらも、思ったより長く見ていた", text: $note, axis: .vertical)
                                .font(Typeface.mincho(16))
                                .lineLimit(1...3)
                                .padding(14)
                                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                                .onChange(of: note) { _, value in
                                    if value.count > Self.noteLimit { note = String(value.prefix(Self.noteLimit)) }
                                }
                        }

                        Button("結ぶ", action: save)
                            .buttonStyle(ShuButtonStyle())
                            .disabled(partner == nil)
                            .accessibilityHint(partner == nil ? "先に、結ぶ相手を選んでください" : "朱の糸で結びます")
                        Text("結びは、あなたの樹にだけ残ります。あとから、体験のページでほどけます。")
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                    }
                }
                .padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("結ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .sensoryFeedback(.selection, trigger: partner)
    }

    private var filteredCandidates: [TreeNode] {
        let all = model.tieCandidates(for: nodeID)
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return all }
        return all.filter { $0.title.contains(words) }
    }

    private func save() {
        guard let partner else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.tie(nodeID, partner, note: trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}

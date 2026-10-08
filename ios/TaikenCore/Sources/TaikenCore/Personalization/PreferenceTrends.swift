import Foundation

/// 過去の反応から「最近こういう反応が多い」という傾向を計算する (指示書 §16)。
/// 固定的な性格分類はしない: 古い反応ほど重みを小さくし (半減期)、十分な材料が無いタグは出さない。
public enum PreferenceTrends {
    public static let defaultHalfLife: TimeInterval = 14 * 86_400

    public enum Direction: String, Sendable, Equatable {
        case positive
        case negative
        case mixed
    }

    public struct TagScore: Sendable, Equatable {
        public let tag: String
        /// -1 (合わない) 〜 1 (合う)
        public let score: Double
        /// 判断材料の量 (時間で減衰した件数)
        public let evidence: Double

        public var direction: Direction {
            if score >= 0.2 { return .positive }
            if score <= -0.2 { return .negative }
            return .mixed
        }
    }

    public struct Summary: Sendable, Equatable, Identifiable {
        public var id: String { tag }
        public let tag: String
        public let label: String
        public let direction: Direction

        public var sentence: String {
            switch direction {
            case .positive: "「\(label)」のある体験は、最近よく響いています"
            case .negative: "「\(label)」のある体験は、最近は合わないことが多めです"
            case .mixed: "「\(label)」のある体験は、日によって半々のようです"
            }
        }
    }

    /// 1件の反応の値。評価があればそれを、無ければ選び方 (やってみた/断った) を弱めに使う
    static func value(of entry: HistoryEntry) -> Double? {
        switch entry.status {
        case .completed: entry.rating?.value ?? 0.25
        case .active: 0.25
        case .declined: -0.5
        case .skipped: -0.25
        }
    }

    public static func scores(from entries: [HistoryEntry], now: Date, halfLife: TimeInterval = defaultHalfLife) -> [TagScore] {
        var weighted: [String: (sum: Double, weight: Double)] = [:]
        for entry in entries {
            guard let value = value(of: entry) else { continue }
            let age = max(0, now.timeIntervalSince(entry.finishedAt ?? entry.createdAt))
            let w = pow(0.5, age / halfLife)
            for tag in Set(entry.tags) {
                let current = weighted[tag] ?? (0, 0)
                weighted[tag] = (current.sum + w * value, current.weight + w)
            }
        }
        return weighted
            .map { TagScore(tag: $0.key, score: $0.value.weight > 0 ? $0.value.sum / $0.value.weight : 0, evidence: $0.value.weight) }
            .sorted { $0.evidence == $1.evidence ? $0.tag < $1.tag : $0.evidence > $1.evidence }
    }

    /// AIへ渡す傾向。材料が少ないものと、はっきりしないものは渡さない
    public static func signals(from entries: [HistoryEntry], now: Date, minimumEvidence: Double = 1.5, limit: Int = 12) -> [FeedbackSignal] {
        scores(from: entries, now: now)
            .filter { $0.evidence >= minimumEvidence && $0.direction != .mixed }
            .prefix(limit)
            .map { score in
                let confidence = min(1, score.evidence / 3)
                let weight = (abs(score.score) * confidence * 100).rounded() / 100
                return FeedbackSignal(tag: score.tag, rating: score.score > 0 ? .positive : .negative, weight: weight)
            }
    }

    /// 履歴画面に出す、人が読める傾向
    public static func summaries(from entries: [HistoryEntry], now: Date, limit: Int = 5) -> [Summary] {
        scores(from: entries, now: now)
            .filter { $0.evidence >= 1.5 }
            .prefix(limit)
            .map { Summary(tag: $0.tag, label: ExperienceTag.label($0.tag), direction: $0.direction) }
    }
}

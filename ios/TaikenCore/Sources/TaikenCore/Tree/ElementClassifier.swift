import Foundation

public typealias ExperienceElement = TaikenContent.Element

/// 要素が分からない体験 (AIが作った体験・3.0 より前の記録) の要素を、名前と文から推し量る。
/// 推測なので、AIが要素を付けてきたときや、ライブラリの体験のときはそちらを使う。
public struct ElementClassifier: Sendable {
    public let content: TaikenContent

    public init(content: TaikenContent = .shared) {
        self.content = content
    }

    /// 1〜3個の要素 (先頭が主な要素)。手がかりが無ければタグから、それも無ければ「見る」
    public func classify(title: String, invitation: String, perspective: String, tags: [String]) -> [String] {
        var scores: [(id: String, score: Int, order: Int)] = []
        for (order, element) in content.elements.enumerated() {
            var score = 0
            for keyword in element.keywords where !keyword.isEmpty {
                score += 2 * occurrences(of: keyword, in: title)
                score += occurrences(of: keyword, in: invitation)
                score += occurrences(of: keyword, in: perspective)
            }
            if score > 0 { scores.append((element.id, score, order)) }
        }
        scores.sort { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
        if let top = scores.first {
            let threshold = max(2, (top.score + 2) / 3)
            let rest = scores.dropFirst().filter { $0.score >= threshold }.prefix(2).map(\.id)
            return [top.id] + rest
        }
        return [fallback(tags: tags)]
    }

    /// 自分で記す言葉から、触れた要素を推し量る (1〜3個)。手がかりが無ければ空 (自分で選んでもらう)
    public func suggest(for text: String) -> [String] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return [] }
        let hasClue = content.elements.contains { element in
            element.keywords.contains { !$0.isEmpty && words.contains($0) }
        }
        return hasClue ? classify(title: words, invitation: "", perspective: "", tags: []) : []
    }

    func fallback(tags: [String]) -> String {
        let byTag: [(String, String)] = [
            ("social", "people"), ("creative", "word"), ("question", "think"), ("reflection", "think"),
            ("small_challenge", "move"), ("sensory", "touch"), ("observation", "see"), ("new_perspective", "see"),
        ]
        for (tag, element) in byTag where tags.contains(tag) && content.element(element) != nil {
            return element
        }
        return content.elements.first?.id ?? "see"
    }

    private func occurrences(of keyword: String, in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: keyword, range: range) {
            count += 1
            range = found.upperBound..<text.endIndex
        }
        return count
    }

    // MARK: - 印

    /// 主な要素の字。要素が無ければ「体」
    public static func glyph(for elements: [String], content: TaikenContent = .shared) -> String {
        elements.lazy.compactMap { content.element($0)?.glyph }.first ?? "体"
    }

    /// 体験の要素 (付いていればそれを、無ければライブラリから、それも無ければ推し量る)
    public static func elements(of experience: Experience, content: TaikenContent = .shared) -> [String] {
        let known = content.knownElements(experience.elements)
        if !known.isEmpty { return Array(known.prefix(3)) }
        if let id = experience.nodeID, let item = content.experience(id) { return item.elements }
        if let item = content.experience(titled: experience.title) { return item.elements }
        return ElementClassifier(content: content).classify(
            title: experience.title, invitation: experience.invitation, perspective: experience.perspective, tags: experience.tags
        )
    }
}

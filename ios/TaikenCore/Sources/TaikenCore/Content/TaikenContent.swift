import Foundation

/// 七十二候・テーマ・気分・体験ライブラリ。
/// 正は contracts/content.ja.json で、iOS と Backend が同じ内容のコピーを持つ (テストで一致を確認する)。
public struct TaikenContent: Decodable, Sendable {
    public struct SolarTerm: Decodable, Sendable, Hashable {
        public let name: String
        public let reading: String
    }

    public struct MicroSeasonEntry: Decodable, Sendable, Hashable {
        public let name: String
        public let reading: String
        public let meaning: String
    }

    public struct Theme: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let label: String
        public let keywords: [String]
    }

    public struct MoodEntry: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let label: String
        public let keywords: [String]
    }

    /// ライブラリの体験1件
    public struct LibraryExperience: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let perspective: String
        public let invitation: String
        public let reflectionQuestion: String
        public let tags: [String]
        /// study / work / commute ... / rest / morning / night / outdoors / general
        public let themes: [String]
        public let moods: [String]
        /// 空ならいつでも
        public let times: [String]
        /// low / medium
        public let effort: String
        /// 空なら季節を問わない。値は二十四節気の番号 (0 = 立春)
        public let solarTerms: [Int]

        public var isSeasonal: Bool { !solarTerms.isEmpty }
    }

    public let version: Int
    public let solarTerms: [SolarTerm]
    public let microSeasons: [MicroSeasonEntry]
    public let themes: [Theme]
    public let moods: [MoodEntry]
    public let experiences: [LibraryExperience]

    /// アプリ全体で使う内容。読み込めなければ最小限の内容で動き続ける
    public static let shared: TaikenContent = load()

    public static func decode(_ data: Data) throws -> TaikenContent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TaikenContent.self, from: data)
    }

    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "content.ja", withExtension: "json")
    }

    static func load() -> TaikenContent {
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url),
              let content = try? decode(data),
              content.isWellFormed
        else { return minimal }
        return content
    }

    /// 季節の表が欠けていると日付から引けないため、形を確かめる
    public var isWellFormed: Bool {
        solarTerms.count == 24 && microSeasons.count == 72 && !experiences.isEmpty
    }

    public func theme(_ id: String) -> Theme? { themes.first { $0.id == id } }

    /// リソースが壊れていたときの最小限の内容 (アプリを止めないため)
    static let minimal: TaikenContent = {
        let term = SolarTerm(name: "季節", reading: "きせつ")
        let season = MicroSeasonEntry(name: "今日", reading: "きょう", meaning: "いつもの一日")
        let everyday = LibraryExperience(
            id: "daily-difference", title: "いつもの中の違い",
            perspective: "何気ない時間を、昨日との小さな違いを見つける時間として捉える。",
            invitation: "今日のどこかで、昨日とは少し違うことをひとつ見つけてみませんか？",
            reflectionQuestion: "どんな違いが見つかりましたか？",
            tags: ["observation", "short"], themes: ["general"], moods: [], times: [], effort: "low", solarTerms: []
        )
        return TaikenContent(
            version: 0,
            solarTerms: Array(repeating: term, count: 24),
            microSeasons: Array(repeating: season, count: 72),
            themes: [],
            moods: [],
            experiences: [everyday]
        )
    }()
}

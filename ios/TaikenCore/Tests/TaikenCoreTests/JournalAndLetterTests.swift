import Foundation
import XCTest
@testable import TaikenCore

@MainActor
final class JournalTests: XCTestCase {
    private func entry(_ title: String, _ day: String, status: HistoryEntry.Status = .completed, tags: [String] = ["observation"]) -> HistoryEntry {
        HistoryEntry(createdAt: tokyoDate(day, hour: 12), title: title, theme: nil, invitation: "i", perspective: "p", tags: tags, status: status, rating: status == .completed ? .positive : nil)
    }

    func testMonthGridMarksDaysWithExperiences() async {
        let repo = InMemoryHistoryRepository([
            entry("今日", "2026-10-08"),
            entry("十月一日", "2026-10-01"),
            entry("九月末", "2026-09-30"),
            entry("断った", "2026-10-08", status: .declined),
        ])
        let model = HistoryViewModel(history: repo, calendar: tokyoCalendar, now: { referenceDate })
        model.reload()

        XCTAssertEqual(model.stats.lived, 3)
        XCTAssertEqual(model.stats.thisMonth, 2)
        XCTAssertFalse(model.stats.elements.isEmpty)

        let grid = model.monthGrid()
        XCTAssertEqual(grid.count, 35)
        XCTAssertEqual(grid.first?.date, tokyoDate("2026-09-27"), "2026年10月1日は木曜日。日曜はじまり")
        let today = grid.first { $0.isToday }
        XCTAssertEqual(today?.day, 8)
        XCTAssertEqual(today?.entries.map(\.title), ["今日"])
        let lastOfSeptember = grid.first { $0.date == tokyoDate("2026-09-30") }
        XCTAssertEqual(lastOfSeptember?.isInMonth, false)
        XCTAssertEqual(lastOfSeptember?.entries.count, 1)
    }

    func testMonthNavigationStopsAtThisMonth() async {
        let model = HistoryViewModel(history: InMemoryHistoryRepository(), calendar: tokyoCalendar, now: { referenceDate })
        XCTAssertFalse(model.canShowNextMonth)
        model.showNextMonth()
        XCTAssertEqual(model.displayedMonth, tokyoDate("2026-10-01"))
        model.showPreviousMonth()
        XCTAssertEqual(model.displayedMonth, tokyoDate("2026-09-01"))
        XCTAssertTrue(model.canShowNextMonth)
        model.showCurrentMonth()
        XCTAssertEqual(model.displayedMonth, tokyoDate("2026-10-01"))
    }

    func testShowsEveryLivedExperienceByDefault() async {
        let repo = InMemoryHistoryRepository([entry("最近", "2026-10-07"), entry("春のこと", "2026-04-01")])
        let model = HistoryViewModel(history: repo, calendar: tokyoCalendar, now: { referenceDate })
        model.reload()
        XCTAssertEqual(model.sections.flatMap { $0.entries.map(\.title) }, ["最近", "春のこと"])
    }

    /// 印は、体験の主な要素の字。要素が記録に無い古い記録は、ライブラリか文から推し量る
    func testSealCharactersComeFromElements() async {
        XCTAssertEqual(livedEntry("meal-first-bite").sealCharacter, "味")
        XCTAssertEqual(livedEntry("people-listen").sealCharacter, "人")
        // 3.0 より前の記録 (要素が無い) でも、ライブラリと同じ名前なら同じ印
        let old = HistoryEntry(createdAt: referenceDate, title: "いちばん小さな音", theme: nil, invitation: "i", perspective: "p", tags: ["sensory"], status: .completed)
        XCTAssertEqual(old.sealCharacter, "聴")
        // ライブラリに無い体験は、名前と文から
        let found = HistoryEntry(createdAt: referenceDate, title: "雨の匂いを探す", theme: nil, invitation: "外に出たら、雨の匂いを探してみませんか？", perspective: "p", tags: [], status: .completed)
        XCTAssertEqual(found.sealCharacter, "香")
        XCTAssertEqual(ElementClassifier.glyph(for: []), "体")
        XCTAssertEqual(ExperienceTag.displayLabels(["short", "observation", "short", "hack"]), ["短い時間", "観察"])
    }

    func testExportIncludesTheGarden() async throws {
        let repo = InMemoryHistoryRepository([livedEntry("meal-first-bite")])
        let store = InMemoryGardenStore()
        let trees = TreeSource(history: repo, store: store, now: { referenceDate })
        try trees.weave(WeaveDraft(title: "湯気を見る", ability: "湯気の形で、温度が分かる。", practice: "湯気の形を見てみる", elements: ["see"]))
        let model = HistoryViewModel(history: repo, calendar: tokyoCalendar, now: { referenceDate }, trees: trees)
        let json = try jsonObject(model.exportJSON())
        let garden = try XCTUnwrap(json["garden"] as? NSDictionary)
        XCTAssertEqual((garden["nodes"] as? [NSDictionary])?.first?["title"] as? String, "湯気を見る")
        XCTAssertEqual((json["entries"] as? [NSDictionary])?.first?["node_id"] as? String, "meal-first-bite")
        XCTAssertFalse(model.vaultFiles().isEmpty)
    }

    func testShowsRanksAndWhatEachRecordGrew() async throws {
        let own = selfEntry("窓の外をじっと眺めた", ["see"])
        let repo = InMemoryHistoryRepository([own, livedEntry("rest-far"), livedEntry("root-see")])
        let trees = TreeSource(history: repo, store: InMemoryGardenStore(Garden(learned: learned(["see-tomeru"]))), calendar: tokyoCalendar, now: { referenceDate })
        trees.link(entry: own.id, skills: ["see-tomeru"])
        let model = HistoryViewModel(history: repo, calendar: tokyoCalendar, now: { referenceDate }, trees: trees)
        model.reload()
        XCTAssertEqual(model.progress.count, 10)
        XCTAssertEqual(model.progress.first?.rank, 2, "見るは、三つの体験で二段")
        XCTAssertEqual(model.learnedCount, 1)
        XCTAssertEqual(model.stats.selfRecorded, 1)
        XCTAssertEqual(model.skills(of: own).map(\.id), ["see-tomeru"])
        XCTAssertEqual(model.treeFocus(of: own), "see-tomeru")
        XCTAssertEqual(model.treeFocus(of: livedEntry("people-listen")), ExperienceTree.rootID("people"))
        model.delete(own)
        XCTAssertTrue(trees.garden.uses.isEmpty, "記録を消すと、技との結びも外れる")
    }

    func testSampleJournalUsesLibraryEntries() async {
        let samples = HistoryEntry.sampleJournal(now: referenceDate, calendar: tokyoCalendar)
        XCTAssertEqual(samples.count, 8)
        XCTAssertTrue(samples.allSatisfy { $0.status == .completed && $0.reflectionQuestion != nil })
    }
}

final class DailyLetterTests: XCTestCase {
    private let enabled = DailyLetterPreferences(enabled: true, hour: 8, minute: 0)

    func testPlansTheComingMornings() {
        let letters = DailyLetter.plan(now: referenceDate, preferences: enabled, engagedToday: false, calendar: tokyoCalendar)
        // 今日の8時は過ぎているので、明日から6日分
        XCTAssertEqual(letters.count, 6)
        XCTAssertEqual(letters.first?.identifier, "letter-2026-10-09")
        XCTAssertEqual(letters.first?.fireDate, tokyoDate("2026-10-09", hour: 8))
        XCTAssertEqual(letters.first?.title, "今日の体験")
        XCTAssertTrue(DailyLetter.bodies.contains(letters.first?.body ?? ""))
        XCTAssertEqual(Set(letters.map(\.identifier)).count, letters.count)
        // 季節のことは書かない
        XCTAssertFalse(letters.contains { $0.body.contains("季節") || $0.title.contains("・") })
    }

    func testSkipsTodayWhenAlreadyOpened() {
        let sevenAM = tokyoDate("2026-10-08", hour: 7)
        let fresh = DailyLetter.plan(now: sevenAM, preferences: enabled, engagedToday: false, calendar: tokyoCalendar)
        XCTAssertEqual(fresh.first?.identifier, "letter-2026-10-08")
        XCTAssertEqual(fresh.count, 7)
        let engaged = DailyLetter.plan(now: sevenAM, preferences: enabled, engagedToday: true, calendar: tokyoCalendar)
        XCTAssertEqual(engaged.first?.identifier, "letter-2026-10-09")
    }

    func testDisabledOrOutOfRange() {
        XCTAssertTrue(DailyLetter.plan(now: referenceDate, preferences: DailyLetterPreferences(), engagedToday: false, calendar: tokyoCalendar).isEmpty)
        XCTAssertEqual(DailyLetterPreferences(enabled: true, hour: 30, minute: -5).normalized, DailyLetterPreferences(enabled: true, hour: 23, minute: 0))
    }
}

final class RequestPreviewTests: XCTestCase {
    func testDescribesEverythingThatWillBeSent() throws {
        let request = try APICoding.decoder().decode(ExperienceRequest.self, from: Fixtures.data("experience_request.sample"))
        let sections = RequestPreview.sections(for: request)
        let byTitle = Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0.items) })
        XCTAssertEqual(byTitle["時刻"], ["2026-10-08 18:10 (Asia/Tokyo)"])
        XCTAssertNil(byTitle["季節"])
        XCTAssertEqual(byTitle["いまの気分"], ["疲れぎみ"])
        XCTAssertEqual(byTitle["技の樹"], ["記した体験: ひと口目の観察、三つの音", "技の稽古: 食感をことばに、最後のひと口、自分の足音"])
        XCTAssertEqual(byTitle["予定"], ["今日 19:00〜 数学の課題", "明日 09:00〜 (タイトルは送りません)"])
        XCTAssertEqual(byTitle["最近の発言"], ["「今日ちょっと疲れた」"])
        XCTAssertEqual(byTitle["最近の体験"], ["通学路の音を数える — やってみた · 響いた"])
        XCTAssertEqual(byTitle["反応の傾向"], ["新しい視点: 良い反応が多め (強さ 0.80)", "長い時間: 合わないことが多め (強さ 0.50)"])
        XCTAssertEqual(byTitle["おおよその地域"], ["堺市 (大阪府)"])
        XCTAssertEqual(byTitle["Web検索"], ["必要なときだけ使ってよい"])

        // 表示している JSON は実際に送るものと同じ
        let shown = try jsonObject(Data(RequestPreview.json(for: request).utf8))
        XCTAssertEqual(shown, try Fixtures.object("experience_request.sample"))
    }

    func testSaysWhenNothingIsSent() {
        let request = ExperienceRequest(
            currentTime: "2026-10-08T18:10:00+09:00", timeZone: "Asia/Tokyo", locale: "ja-JP", calendarContext: [],
            recentUserMessages: [], recentExperiences: [], userFeedback: [], excludeTitles: [], area: nil, allowWebSearch: false
        )
        let byTitle = Dictionary(uniqueKeysWithValues: RequestPreview.sections(for: request).map { ($0.title, $0.items) })
        XCTAssertEqual(byTitle["予定"], [RequestPreview.notSent])
        XCTAssertEqual(byTitle["おおよその地域"], [RequestPreview.notSent])
        XCTAssertEqual(byTitle["いまの気分"], ["選んでいません"])
        XCTAssertEqual(byTitle["技の樹"], [RequestPreview.notSent])
        XCTAssertEqual(byTitle["Web検索"], ["使わない"])
    }

    /// 送る項目を増やしたら、確認画面にも表示を足す
    func testCoversEveryRequestField() throws {
        let request = try APICoding.decoder().decode(ExperienceRequest.self, from: Fixtures.data("experience_request.sample"))
        let fields = Set(Mirror(reflecting: request).children.compactMap(\.label))
        XCTAssertEqual(fields, [
            "currentTime", "timeZone", "locale", "calendarContext", "recentUserMessages", "recentExperiences",
            "userFeedback", "excludeTitles", "area", "allowWebSearch", "mood", "tree",
        ], "ExperienceRequest に項目を足したら RequestPreview.sections にも表示を足してください")
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testStoresOnlyWhenContentChanges() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WidgetSnapshotTests-\(UUID().uuidString)"))
        let store = WidgetSnapshotStore(defaults: defaults)
        let first = WidgetSnapshot.sample(now: referenceDate)
        XCTAssertTrue(store.save(first))
        var later = first
        later.updatedAt = referenceDate.addingTimeInterval(60)
        XCTAssertFalse(store.save(later), "更新時刻だけの違いでは描き直さない")
        var changed = first
        changed.kind = .active
        XCTAssertTrue(store.save(changed))
        XCTAssertEqual(store.load()?.kind, .active)
        store.clear()
        XCTAssertNil(store.load())
    }
}

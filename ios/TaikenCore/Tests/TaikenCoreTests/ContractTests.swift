import Foundation
import XCTest
@testable import TaikenCore

/// contracts/*.json (Backendのテストと同じファイル) を読んで、型が契約どおりか確かめる。
final class ContractTests: XCTestCase {
    func testDecodesExperienceResponse() throws {
        let response = try APICoding.decoder().decode(ExperienceResponse.self, from: Fixtures.data("experience_response.sample"))
        XCTAssertEqual(response.experience.title, "つまずきの観察")
        XCTAssertEqual(response.situation.observations.map(\.basis), [.calendar, .stated, .inferred])
        XCTAssertEqual(response.experience.difficulty, .low)
        XCTAssertEqual(response.experience.reflectionQuestion, "手が止まったとき、何が引っかかっていましたか？")
        XCTAssertNil(response.notification)
        XCTAssertEqual(response.references, [])
        XCTAssertNil(response.fallbackReason)
        XCTAssertEqual(response.source, .ai)
    }

    func testDecodesChatResponse() throws {
        let response = try APICoding.decoder().decode(ChatResponse.self, from: Fixtures.data("chat_response.sample"))
        XCTAssertTrue(response.suggestExperience)
        XCTAssertNotNil(response.experience?.reflectionQuestion)
        XCTAssertFalse(response.needsCare)
    }

    func testDecodesStatusAndError() throws {
        let status = try APICoding.decoder().decode(ServiceStatus.self, from: Fixtures.data("status_response.sample"))
        XCTAssertTrue(status.features.webSearch)
        XCTAssertEqual(status.budget.requestsRemaining, 180)
        let body = try APICoding.decoder().decode(APIErrorBody.self, from: Fixtures.data("error_response.sample"))
        XCTAssertEqual(body.error.code, "rate_limited")
        XCTAssertEqual(body.error.retryAfterSeconds, 30)
        XCTAssertNotNil(body.error.requestId)
    }

    /// iOSが送るJSONが、Backendが期待する形 (フィクスチャ) と完全に同じになる
    func testExperienceRequestRoundTrip() throws {
        let data = try Fixtures.data("experience_request.sample")
        let request = try APICoding.decoder().decode(ExperienceRequest.self, from: data)
        XCTAssertEqual(request.mood, .tired)
        XCTAssertEqual(request.season, SeasonContext(solarTerm: "寒露", microSeason: "鴻雁来", meaning: "雁が北から渡ってくる頃"))
        XCTAssertEqual(try jsonObject(APICoding.encoder().encode(request)), try jsonObject(data))
    }

    /// 気分を選んでいないときは mood キーを送らない (契約では省略可)
    func testOmitsMoodWhenNotChosen() throws {
        let request = try APICoding.decoder().decode(ExperienceRequest.self, from: Fixtures.data("experience_request.sample"))
        let withoutMood = ExperienceRequest(
            currentTime: request.currentTime, timeZone: request.timeZone, locale: request.locale,
            calendarContext: request.calendarContext, recentUserMessages: [], recentExperiences: [], userFeedback: [],
            excludeTitles: [], area: nil, allowWebSearch: false, mood: nil, season: request.season
        )
        let json = try jsonObject(APICoding.encoder().encode(withoutMood))
        XCTAssertNil(json["mood"])
        XCTAssertNotNil(json["season"])
    }

    /// OpenAPI に書いた気分の値と、iOS の Mood が一致する
    func testMoodValuesMatchContract() throws {
        let api = try Fixtures.object("openapi")
        let schemas = (api["components"] as? NSDictionary)?["schemas"] as? NSDictionary
        let values = (schemas?["Mood"] as? NSDictionary)?["enum"] as? [String]
        XCTAssertEqual(values, Mood.allCases.map(\.rawValue))
    }

    func testChatRequestRoundTrip() throws {
        let data = try Fixtures.data("chat_request.sample")
        let request = try APICoding.decoder().decode(ChatRequest.self, from: data)
        let encoded = try jsonObject(APICoding.encoder().encode(request)).mutableCopy() as! NSMutableDictionary
        let expected = try jsonObject(data).mutableCopy() as! NSMutableDictionary
        // nil の current_experience はキーごと省略される (Backendは欠落を null と同じに扱う)
        encoded.removeObject(forKey: "current_experience")
        expected.removeObject(forKey: "current_experience")
        XCTAssertEqual(encoded, expected)
    }

    func testUnknownValuesFallBackToSafeSide() throws {
        let note = try APICoding.decoder().decode(SituationNote.self, from: Data(#"{"text":"眠そう","basis":"something_new"}"#.utf8))
        XCTAssertEqual(note.basis, .inferred)
        let reason = try APICoding.decoder().decode(FallbackReason.self, from: Data(#""new_reason""#.utf8))
        XCTAssertEqual(reason, .unknown)
    }

    /// 古いBackend (新しいフィールドが無い) の応答も読める
    func testDecodesOlderResponsesWithoutNewFields() throws {
        let old = try Fixtures.object("experience_response.sample").mutableCopy() as! NSMutableDictionary
        old.removeObject(forKey: "references")
        old.removeObject(forKey: "fallback_reason")
        let oldExperience = (old["experience"] as! NSDictionary).mutableCopy() as! NSMutableDictionary
        oldExperience.removeObject(forKey: "reflection_question")
        old["experience"] = oldExperience
        let response = try APICoding.decoder().decode(ExperienceResponse.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(response.references, [])
        XCTAssertNil(response.experience.reflectionQuestion)

        let oldChat = try Fixtures.object("chat_response.sample").mutableCopy() as! NSMutableDictionary
        oldChat.removeObject(forKey: "needs_care")
        XCTAssertFalse(try APICoding.decoder().decode(ChatResponse.self, from: JSONSerialization.data(withJSONObject: oldChat)).needsCare)
    }

    /// needs_care のときは、サーバーが体験を付けていても表示しない
    func testCareResponseDropsExperience() throws {
        let care = try Fixtures.object("chat_response.sample").mutableCopy() as! NSMutableDictionary
        care["needs_care"] = true
        let response = try APICoding.decoder().decode(ChatResponse.self, from: JSONSerialization.data(withJSONObject: care))
        XCTAssertNil(response.experience)
        XCTAssertFalse(response.suggestExperience)
    }

    /// 通知文が無いのに should_notify=true でも通知扱いにしない
    func testNotifyRequiresContent() throws {
        let raw = try Fixtures.object("experience_response.sample").mutableCopy() as! NSMutableDictionary
        raw["should_notify"] = true
        let response = try APICoding.decoder().decode(ExperienceResponse.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertFalse(response.shouldNotify)
    }

    func testReferenceOnlyOpensHTTP() {
        XCTAssertNotNil(Reference(title: "a", url: "https://example.com").safeURL)
        XCTAssertNil(Reference(title: "a", url: "javascript:alert(1)").safeURL)
    }
}

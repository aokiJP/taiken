import XCTest

/// 体験の流れを、実際の画面で最初から最後までたどる (シミュレータ)。
/// 受け取る → 手がかりを見る → 季節を見る → やってみる → 思い返して記す → 印 → 体験帳 → 記録 → 話す → 設定
///
/// - アプリは `-UITesting` で、端末の状態に左右されない組み立てで起動する (メモリ上の保存先・見本の予定・体験ライブラリ)
/// - 各場面のスクリーンショットを、環境変数 `TAIKEN_SCREENSHOTS` のフォルダ (xcodebuild には
///   `TEST_RUNNER_TAIKEN_SCREENSHOTS` で渡す) と、テスト結果の添付の両方に残す
@MainActor
final class ExperienceFlowUITests: XCTestCase {
    func testOnboardingLeadsToFirstExperience() {
        continueAfterFailure = false
        let app = launch(onboarded: false, seedJournal: false)

        let start = app.buttons["はじめる"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        pause(1.6)
        snap("00a-onboarding-welcome")

        start.tap()
        let next = app.buttons["つぎへ"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        pause(0.9)
        snap("00b-onboarding-stance")

        next.tap()
        let begin = app.buttons["最初の体験を受け取る"].firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        pause(0.9)
        snap("00c-onboarding-permissions")

        // UIテストでは見本のカレンダー (許可済み) を使うので、システムの許可ダイアログは出ない
        begin.tap()
        XCTAssertTrue(app.buttons["やってみる"].firstMatch.waitForExistence(timeout: 15))
    }

    func testExperienceLoop() {
        continueAfterFailure = false
        let app = launch(onboarded: true, seedJournal: true)

        // 受け取る
        let tryIt = app.buttons["やってみる"].firstMatch
        XCTAssertTrue(tryIt.waitForExistence(timeout: 15))
        pause(1.4)
        snap("01-home-proposal")

        // 提案の手がかり (事実と推測・次に渡す内容)
        let insight = app.buttons.matching(NSPredicate(format: "label IN %@", ["提案の手がかり", "AIが見たこと"])).firstMatch
        XCTAssertTrue(insight.waitForExistence(timeout: 5))
        insight.tap()
        let closeInsight = app.buttons["閉じる"].firstMatch
        XCTAssertTrue(closeInsight.waitForExistence(timeout: 5))
        pause(0.9)
        snap("02-insight")
        closeInsight.tap()
        pause(0.8)

        // 七十二候
        let tanzaku = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "七十二候")).firstMatch
        XCTAssertTrue(tanzaku.waitForExistence(timeout: 5))
        tanzaku.tap()
        let closeSeason = app.buttons["閉じる"].firstMatch
        XCTAssertTrue(closeSeason.waitForExistence(timeout: 5))
        pause(1.0)
        snap("03-season")
        closeSeason.tap()
        pause(0.8)

        // やってみる
        XCTAssertTrue(tryIt.waitForExistence(timeout: 5))
        tryIt.tap()
        let finish = app.buttons["終えた — 記す"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 8))
        pause(1.2)
        snap("04-active")

        // 思い返して記す
        finish.tap()
        let resonated = app.buttons["響いた"].firstMatch
        XCTAssertTrue(resonated.waitForExistence(timeout: 5))
        resonated.tap()
        let note = app.descendants(matching: .any).matching(identifier: "reflection.note").firstMatch
        if note.waitForExistence(timeout: 3) {
            note.tap()
            note.typeText("思ったより、音が多かった")
        }
        pause(0.6)
        snap("05-reflection")
        let record = app.buttons["記す"].firstMatch
        XCTAssertTrue(record.isEnabled)
        record.tap()

        // 印 (シートが閉じてから押される)
        let openJournal = app.buttons["体験帳をひらく"].firstMatch
        XCTAssertTrue(openJournal.waitForExistence(timeout: 10))
        pause(1.6)
        snap("06-stamped")

        // 体験帳
        openJournal.tap()
        XCTAssertTrue(app.staticTexts["体験帳"].firstMatch.waitForExistence(timeout: 8))
        pause(1.2)
        snap("07-journal-ring")
        app.swipeUp()
        pause(0.9)
        snap("08-journal-calendar")
        app.swipeUp()
        pause(0.9)
        snap("09-journal-entries")

        // 記録の詳細
        let entry = app.descendants(matching: .any).matching(identifier: "journal.entry").firstMatch
        if entry.waitForExistence(timeout: 4) {
            entry.tap()
            pause(1.4)
            snap("10-entry")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(0.8)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 話す
        let talk = app.buttons["話しかける"].firstMatch
        XCTAssertTrue(talk.waitForExistence(timeout: 8))
        talk.tap()
        let ask = app.buttons["何か提案して"].firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 8))
        pause(0.8)
        snap("11-chat")
        ask.tap()
        XCTAssertTrue(app.buttons["今はいい"].firstMatch.waitForExistence(timeout: 10))
        pause(1.0)
        snap("12-chat-suggestion")
        app.buttons["閉じる"].firstMatch.tap()

        // 設定
        let settings = app.buttons["設定"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let done = app.buttons["完了"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        pause(0.9)
        snap("13-settings")
        done.tap()
    }

    // MARK: - 部品

    private func launch(onboarded: Bool, seedJournal: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        // `-キー 値` は UserDefaults の引数ドメインになる (はじめの案内を見終えたか・言語と地域)
        app.launchArguments = [
            "-UITesting",
            "-onboarding.completed", onboarded ? "YES" : "NO",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        if seedJournal { app.launchArguments.append("-UITestSeedJournal") }
        // 空の時間帯をそろえるためのタイムゾーン (CI から TEST_RUNNER_TAIKEN_TZ で渡す)
        let zone = ProcessInfo.processInfo.environment["TAIKEN_TZ"] ?? ""
        app.launchEnvironment["TZ"] = zone.isEmpty ? "Asia/Tokyo" : zone
        app.launch()
        return app
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let path = ProcessInfo.processInfo.environment["TAIKEN_SCREENSHOTS"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

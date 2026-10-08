import XCTest

/// 体験の流れを、実際の画面で最初から最後までたどる (シミュレータ)。
/// 受け取る → 手がかりを見る → 体験の樹 (一覧・体験のページ・編む) → やってみる → 思い返して記す → 印 → 樹に灯る
/// → 体験帳 → 記録 → 話す → 設定
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
        pause(0.9)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "やった体験が")).firstMatch.waitForExistence(timeout: 5))
        snap("00c-onboarding-tree")

        app.buttons["つぎへ"].firstMatch.tap()
        let begin = app.buttons["最初の体験を受け取る"].firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        pause(0.9)
        snap("00d-onboarding-permissions")

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

        // 体験の樹 (ホームの見出しの小さな樹から)
        let openTree = app.buttons["体験の樹をひらく"].firstMatch
        XCTAssertTrue(openTree.waitForExistence(timeout: 5))
        openTree.tap()
        let weave = app.buttons["体験を編む"].firstMatch
        XCTAssertTrue(weave.waitForExistence(timeout: 8))
        pause(1.6)
        snap("03-tree")

        // 一覧と、体験のページ
        let listMode = app.buttons["一覧"].firstMatch
        if listMode.waitForExistence(timeout: 4) {
            listMode.tap()
            pause(1.0)
            snap("03b-tree-list")
            let row = app.descendants(matching: .any).matching(identifier: "tree.row").firstMatch
            if row.waitForExistence(timeout: 4) {
                row.tap()
                let startHere = app.buttons.matching(NSPredicate(format: "label IN %@", ["これをやってみる", "もう一度やってみる"])).firstMatch
                XCTAssertTrue(startHere.waitForExistence(timeout: 6))
                pause(1.0)
                snap("03c-node-page")
                app.buttons["閉じる"].firstMatch.tap()
                pause(0.8)
            }
            app.buttons["樹"].firstMatch.tap()
            pause(0.6)
        }

        // 体験を編む
        weave.tap()
        let plant = app.buttons["樹に植える"].firstMatch
        XCTAssertTrue(plant.waitForExistence(timeout: 6))
        pause(0.8)
        snap("03d-weave")
        app.buttons["閉じる"].firstMatch.tap()
        pause(0.8)

        // ホームへ戻る
        app.navigationBars.buttons.element(boundBy: 0).tap()
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

        // 印 (シートが閉じてから押される) と、その先に出た芽
        let openJournal = app.buttons["体験帳をひらく"].firstMatch
        XCTAssertTrue(openJournal.waitForExistence(timeout: 10))
        pause(1.8)
        snap("06-stamped")

        // 樹に灯ったところ
        let seeOnTree = app.buttons["樹で見る"].firstMatch
        if seeOnTree.waitForExistence(timeout: 4) {
            seeOnTree.tap()
            pause(1.8)
            snap("06b-tree-lit")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(0.8)
        }

        // 体験帳
        XCTAssertTrue(openJournal.waitForExistence(timeout: 8))
        openJournal.tap()
        XCTAssertTrue(app.staticTexts["体験帳"].firstMatch.waitForExistence(timeout: 8))
        pause(1.2)
        snap("07-journal")
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
        // `-キー 値` は UserDefaults の引数ドメインになる (言語と地域・はじめの案内を見終えたか)。
        // 案内から試すときは引数で NO を固定せず (見終えた印を書けなくなる)、アプリに消してもらう
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += onboarded ? ["-onboarding.completed", "YES"] : ["-UITestResetOnboarding"]
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

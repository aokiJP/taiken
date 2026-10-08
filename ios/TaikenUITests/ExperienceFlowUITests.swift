import XCTest

/// 体験の流れを、実際の画面で最初から最後までたどる (シミュレータ)。
/// ホーム (自分の樹) → 体験を記す → 印と経験 → きっかけをもらう → 手がかり → 技の樹 (芽・一覧・技のページ・伸ばす・編む)
/// → やってみる → 思い返して記す → 印 → 体験帳 → 記録 → 話す → 設定
///
/// - アプリは `-UITesting` で、端末の状態に左右されない組み立てで起動する (メモリ上の保存先・見本の予定・体験ライブラリ)
/// - 各場面のスクリーンショットを、環境変数 `TAIKEN_SCREENSHOTS` のフォルダ (xcodebuild には
///   `TEST_RUNNER_TAIKEN_SCREENSHOTS` で渡す) と、テスト結果の添付の両方に残す
@MainActor
final class ExperienceFlowUITests: XCTestCase {
    func testOnboardingLeadsToHome() {
        continueAfterFailure = false
        let app = launch(onboarded: false, seedJournal: false)

        let next = app.buttons["つぎへ"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        pause(1.6)
        snap("00a-onboarding-welcome")

        next.tap()
        XCTAssertTrue(app.buttons["つぎへ"].firstMatch.waitForExistence(timeout: 5))
        pause(0.9)
        snap("00b-onboarding-stance")

        app.buttons["つぎへ"].firstMatch.tap()
        pause(0.9)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "生きた体験が")).firstMatch.waitForExistence(timeout: 5))
        snap("00c-onboarding-tree")

        app.buttons["つぎへ"].firstMatch.tap()
        let begin = app.buttons["はじめる"].firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        pause(0.9)
        snap("00d-onboarding-permissions")

        // UIテストでは見本のカレンダー (許可済み) を使うので、システムの許可ダイアログは出ない
        begin.tap()
        XCTAssertTrue(app.buttons["体験を記す"].firstMatch.waitForExistence(timeout: 15), "ホームの真ん中は「体験を記す」")
        XCTAssertFalse(app.buttons["やってみる"].firstMatch.exists, "きっかけは、求めるまで出ない")
    }

    func testExperienceLoop() {
        continueAfterFailure = false
        let app = launch(onboarded: true, seedJournal: true)

        // ホーム: 自分の樹のいまと「体験を記す」(きっかけは、まだ出ていない)
        let record = app.buttons["体験を記す"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["やってみる"].firstMatch.exists)
        pause(1.4)
        snap("01-home")

        // 体験を記す (自分で見つけた体験)
        record.tap()
        let text = app.descendants(matching: .any).matching(identifier: "record.text").firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 6))
        text.tap()
        text.typeText("焼きたての匂いに、足が止まった")
        let save = app.buttons.matching(identifier: "record.save").firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        pause(0.8)
        snap("02-record")
        XCTAssertTrue(save.isEnabled, "言葉から要素を推し量り、記せる")
        save.tap()

        // 印と、経験が積もったところ
        let closeCompleted = app.buttons.matching(identifier: "completed.close").firstMatch
        XCTAssertTrue(closeCompleted.waitForExistence(timeout: 10))
        pause(1.8)
        snap("03-recorded")
        closeCompleted.tap()
        pause(0.8)

        // きっかけをもらう (求めたときだけ)
        let prompt = app.buttons.matching(identifier: "home.prompt").firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 6))
        prompt.tap()
        let tryIt = app.buttons["やってみる"].firstMatch
        XCTAssertTrue(tryIt.waitForExistence(timeout: 15))
        pause(1.4)
        snap("04-home-prompt")

        // きっかけの手がかり (事実と推測・次に渡す内容)
        let insight = app.buttons.matching(NSPredicate(format: "label IN %@", ["きっかけの手がかり", "AIが見たこと"])).firstMatch
        XCTAssertTrue(insight.waitForExistence(timeout: 5))
        insight.tap()
        let closeInsight = app.buttons["閉じる"].firstMatch
        XCTAssertTrue(closeInsight.waitForExistence(timeout: 5))
        pause(0.9)
        snap("05-insight")
        closeInsight.tap()
        pause(0.8)

        // 技の樹 (ホームの見出しの小さな樹から)
        let openTree = app.buttons["技の樹をひらく"].firstMatch
        XCTAssertTrue(openTree.waitForExistence(timeout: 5))
        openTree.tap()
        let weave = app.buttons.matching(identifier: "tree.weave").firstMatch
        XCTAssertTrue(weave.waitForExistence(timeout: 8))
        pause(1.6)
        snap("06-tree")

        // 芽の出ている要素へ寄る
        let sprouts = app.buttons.matching(identifier: "tree.sprouts").firstMatch
        if sprouts.waitForExistence(timeout: 3) {
            sprouts.tap()
            pause(1.4)
            snap("06b-tree-sprouts")
        }

        // 一覧と、技のページ。芽を使って伸ばす
        let listMode = app.buttons["一覧"].firstMatch
        if listMode.waitForExistence(timeout: 4) {
            listMode.tap()
            pause(1.0)
            snap("07-tree-list")
            let growable = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "tree.row", "伸ばせる")).firstMatch
            let row = growable.waitForExistence(timeout: 4)
                ? growable : app.descendants(matching: .any).matching(identifier: "tree.row").firstMatch
            if row.waitForExistence(timeout: 4) {
                row.tap()
                pause(1.0)
                snap("08-node-page")
                let learn = app.buttons.matching(identifier: "node.learn").firstMatch
                if learn.waitForExistence(timeout: 3) {
                    learn.tap()
                    let confirm = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "芽を使って伸ばす")).firstMatch
                    XCTAssertTrue(confirm.waitForExistence(timeout: 4))
                    confirm.tap()
                    pause(1.4)
                    snap("09-learned")
                }
                app.buttons["閉じる"].firstMatch.tap()
                pause(0.8)
            }
            app.buttons["樹"].firstMatch.tap()
            pause(1.0)
            snap("10-tree-after")
        }

        // 技を編む
        if weave.waitForExistence(timeout: 4) {
            weave.tap()
            let plant = app.buttons["樹に植える"].firstMatch
            XCTAssertTrue(plant.waitForExistence(timeout: 6))
            pause(0.8)
            snap("11-weave")
            app.buttons["閉じる"].firstMatch.tap()
            pause(0.8)
        }

        // ホームへ戻る
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(0.8)

        // やってみる
        XCTAssertTrue(tryIt.waitForExistence(timeout: 5))
        tryIt.tap()
        let finish = app.buttons["終えた — 記す"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 8))
        pause(1.2)
        snap("12-active")

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
        snap("13-reflection")
        let recordReflection = app.buttons.matching(identifier: "reflection.record").firstMatch
        XCTAssertTrue(recordReflection.waitForExistence(timeout: 4))
        XCTAssertTrue(recordReflection.isEnabled)
        recordReflection.tap()

        // 印 (シートが閉じてから押される) と、樹の伸び
        let openJournal = app.buttons["体験帳をひらく"].firstMatch
        XCTAssertTrue(openJournal.waitForExistence(timeout: 10))
        pause(1.8)
        snap("14-stamped")

        let seeOnTree = app.buttons.matching(identifier: "completed.tree").firstMatch
        if seeOnTree.waitForExistence(timeout: 4) {
            seeOnTree.tap()
            pause(1.8)
            snap("15-tree-grown")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(0.8)
        }

        // 体験帳
        XCTAssertTrue(openJournal.waitForExistence(timeout: 8))
        openJournal.tap()
        XCTAssertTrue(app.staticTexts["体験帳"].firstMatch.waitForExistence(timeout: 8))
        pause(1.2)
        snap("16-journal")
        app.swipeUp()
        pause(0.9)
        snap("17-journal-calendar")
        app.swipeUp()
        pause(0.9)
        snap("18-journal-entries")

        // 記録の詳細
        let entry = app.descendants(matching: .any).matching(identifier: "journal.entry").firstMatch
        if entry.waitForExistence(timeout: 4) {
            entry.tap()
            pause(1.4)
            snap("19-entry")
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
        snap("20-chat")
        ask.tap()
        XCTAssertTrue(app.buttons["今はいい"].firstMatch.waitForExistence(timeout: 10))
        pause(1.0)
        snap("21-chat-suggestion")
        app.buttons["閉じる"].firstMatch.tap()

        // 設定
        let settings = app.buttons["設定"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let done = app.buttons["完了"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        pause(0.9)
        snap("22-settings")
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

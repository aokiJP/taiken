import SwiftUI
import TaikenCore
import UIKit
import UniformTypeIdentifiers

/// 設定 (指示書 §19: 情報の種類ごとに許可・拒否できる)。
/// どのしくみがきっかけをつくっているか、次に何を渡すのかを、いつでも確かめられるようにする
struct SettingsView: View {
    let dependencies: AppDependencies
    @Bindable private var model: SettingsViewModel
    private let engineState: EngineState

    @AppStorage(ConsentKey.useCalendar) private var useCalendar = true
    @AppStorage(ConsentKey.sendEventTitles) private var sendEventTitles = true
    @AppStorage(ConsentKey.useChatContext) private var useChatContext = true
    @AppStorage(ConsentKey.useHistory) private var useHistory = true
    @AppStorage(ConsentKey.useLocation) private var useLocation = false
    @AppStorage(ConsentKey.allowWebSearch) private var allowWebSearch = false
    @AppStorage(PresenceKey.enabled) private var presenceEnabled = true
    @AppStorage(OnboardingKey.completed) private var onboardingCompleted = false

    @State private var confirmsDeletion = false
    @State private var exportData: Data?
    @State private var vaultFiles: [VaultExporter.File] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        model = dependencies.settings
        engineState = dependencies.engineState
    }

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                consentSection
                notificationSection
                presenceSection
                calendarSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.toggle)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await model.onAppear()
                exportData = try? dependencies.history.exportJSON()
                vaultFiles = dependencies.history.vaultFiles()
            }
            .confirmationDialog("体験帳と端末内のデータをすべて削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    dependencies.deleteAllLocalData()
                    exportData = nil
                    vaultFiles = []
                }
            } message: {
                Text("押した印とひとこと、身についた技・編んだ技・結んだ糸が、すべて消えます。接続先・情報の許可・通知の設定は残ります。")
            }
        }
        .presentationBackground(Palette.paper)
    }

    // MARK: - きっかけのしくみ

    private var engineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(engineState.engine.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(engineState.engine.detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            NavigationLink {
                ConnectionSettingsView(model: model)
            } label: {
                LabeledContent("自分のサーバー", value: model.isConfigured ? "接続中" : "未設定")
            }
        } header: {
            Text("きっかけのしくみ")
        } footer: {
            Text(engineFooter)
        }
    }

    private var engineFooter: String {
        switch engineState.engine {
        case .server:
            "接続を解除すると、端末内のしくみ (Apple Intelligence または体験ライブラリ) に戻ります。サーバーに繋がらないときも、端末内できっかけを選びます。"
        case .onDevice:
            "サーバーに接続しなくても使えます。端末内のAIの出力にも、サーバーと同じ安全確認をかけています。"
        case .library:
            "サーバーに接続しなくても、端末内の体験ライブラリ (技の樹の稽古) で使えます。iOS 26 以降の対応機種で Apple Intelligence をオンにすると、端末内のAIがきっかけをつくります。"
        }
    }

    // MARK: - 渡す情報

    private var consentSection: some View {
        Section {
            Toggle("予定をきっかけに使う", isOn: $useCalendar)
            Toggle("予定のタイトルも使う", isOn: $sendEventTitles)
                .disabled(!useCalendar)
            Toggle("最近の会話をきっかけに使う", isOn: $useChatContext)
            Toggle("体験帳と反応をきっかけに使う", isOn: $useHistory)
            Toggle("おおよその地域を使う", isOn: $useLocation)
                .onChange(of: useLocation) { _, enabled in
                    guard enabled else { return }
                    Task {
                        let state = await dependencies.locationProvider.requestAccess()
                        if state != .granted { useLocation = false }
                    }
                }
            Toggle("必要なときだけWeb検索する", isOn: $allowWebSearch)
            NavigationLink {
                RequestPreviewView(engine: engineState.engine, load: { await dependencies.previewRequest() })
            } label: {
                Label("次に渡す内容を確かめる", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("きっかけに使う情報")
        } footer: {
            Text("予定は今日と明日の時間とタイトルだけを使い、メモ・場所・参加者は読み取りません。地域は市区町村名だけで、座標は使いません。Web検索はサーバー接続時に、天気など外部の情報が本当に必要なときだけ行い、検索語に予定のタイトルや発言は含めません。技の樹 (記したライブラリの体験の名前と要素、身についた技の稽古) は「体験帳と反応をきっかけに使う」がオンのときだけ使います。自分で見つけて記した体験と、ひとことは送りません。会話は保存しません。")
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            Toggle("朝の便り", isOn: Binding(
                get: { model.dailyLetter.enabled },
                set: { enabled in Task { await model.setDailyLetterEnabled(enabled) } }
            ))
            if model.dailyLetter.enabled {
                DatePicker("届く時刻", selection: letterTime, displayedComponents: .hourAndMinute)
            }
            Toggle("ちょうどよい時に知らせる", isOn: Binding(
                get: { model.notificationPreferences.enabled },
                set: { enabled in Task { await model.setNotificationsEnabled(enabled) } }
            ))
            if model.notificationPreferences.enabled {
                Picker("知らせない時間の開始", selection: preferenceBinding(\.quietStartHour)) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                Picker("知らせない時間の終了", selection: preferenceBinding(\.quietEndHour)) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                Stepper("1日に多くても \(model.notificationPreferences.maxPerDay) 回", value: preferenceBinding(\.maxPerDay), in: 1...5)
                Stepper("間隔は \(model.notificationPreferences.minimumIntervalHours) 時間以上", value: preferenceBinding(\.minimumIntervalHours), in: 1...12)
            }
            if let message = model.notificationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                Button("iOSの設定を開く") { openSettingsApp() }
            }
        } header: {
            Text("通知")
        } footer: {
            Text("どちらも、オンにしたときだけ届きます (はじめはオフ)。朝の便りは、決まった時刻に一度だけ、きっかけをひとつ届けます。その日すでに体験に触れていれば届きません。「ちょうどよい時に知らせる」は、ときどき裏側で状況を確かめ、今がよいタイミングで負担にならないときだけ知らせます。どちらも音は鳴らしません。")
        }
    }

    private var letterTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.dailyLetter.hour, minute: model.dailyLetter.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.updateDailyLetterTime(hour: parts.hour ?? 8, minute: parts.minute ?? 0)
            }
        )
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<NotificationPreferences, Int>) -> Binding<Int> {
        Binding(
            get: { model.notificationPreferences[keyPath: keyPath] },
            set: { value in
                var prefs = model.notificationPreferences
                prefs[keyPath: keyPath] = value
                model.updateNotificationPreferences(prefs)
            }
        )
    }

    // MARK: - ロック画面

    private var presenceSection: some View {
        Section {
            Toggle("体験中はロック画面に置いておく", isOn: $presenceEnabled)
                .onChange(of: presenceEnabled) { _, enabled in
                    dependencies.home.presenceSettingChanged(enabled: enabled)
                }
        } header: {
            Text("ロック画面とウィジェット")
        } footer: {
            Text("体験中だけ、誘いかけと問いをロック画面と Dynamic Island に置きます。終えたら・やめたら、すぐに消えます。ロック画面は他の人の目にも入るので、気になるときはオフにしてください。ウィジェットは、自分で追加したときだけ表示されます。")
        }
    }

    // MARK: - カレンダー

    @ViewBuilder
    private var calendarSection: some View {
        Section("カレンダーへのアクセス") {
            switch dependencies.home.calendarAccess {
            case .granted:
                LabeledContent("状態", value: "許可済み")
            case .notDetermined:
                Button("カレンダーへのアクセスを許可") { Task { await dependencies.home.requestCalendarAccess() } }
            case .denied:
                Button("iOSの設定でカレンダーを許可") { openSettingsApp() }
            }
        }
    }

    // MARK: - データ

    private var dataSection: some View {
        Section {
            if !vaultFiles.isEmpty {
                ShareLink(
                    item: TreeVaultExport(files: vaultFiles),
                    preview: SharePreview("技の樹（Markdown）", image: Image(systemName: "point.3.connected.trianglepath.dotted"))
                ) {
                    Label("技の樹を書き出す（Markdown）", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            if let exportData {
                ShareLink(
                    item: JournalExport(data: exportData),
                    preview: SharePreview("体験帳（JSON）", image: Image(systemName: "doc.text"))
                ) {
                    Label("体験帳を書き出す（JSON）", systemImage: "square.and.arrow.up")
                }
            }
            Button("体験帳と端末内のデータを削除", role: .destructive) { confirmsDeletion = true }
                .foregroundStyle(Palette.shu)
        } header: {
            Text("端末内のデータ")
        } footer: {
            Text("体験帳と技の樹 (身についた技・編んだ技・結んだ糸) は、この端末の中だけにあります。iCloud にも送りません。Markdown で書き出すと、要素・技・記録のページが [[リンク]] でつながったフォルダになり、Obsidian などのノートアプリで樹のまま開けます。サーバーに接続しているときも、サーバーは会話や予定を保存せず、1日の利用量の数字だけを記録します。")
        }
    }

    // MARK: - このアプリについて

    private var aboutSection: some View {
        Section {
            LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
            Button("はじめの案内をもう一度見る") {
                dismiss()
                onboardingCompleted = false
            }
            Link(destination: SupportResources.url) {
                Label(SupportResources.title, systemImage: "heart.text.square")
            }
        } header: {
            Text("このアプリについて")
        } footer: {
            Text("体験は、AIが出す課題ではありません。自分で生きて、自分で記すものです。AIは、求めたときにきっかけをひとつ差し出すだけ。やるかどうか、どう感じるかは、いつもあなたが決めます。")
        }
    }

    private func openSettingsApp() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

// MARK: - 自分のサーバー

/// 接続先 (自分で用意した Backend)。AIのAPIキーはサーバーにだけ置き、アプリには入れない
struct ConnectionSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var confirmsDisconnect = false

    var body: some View {
        Form {
            Section {
                TextField("https://", text: $model.baseURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                SecureField(model.hasSavedToken ? "トークン（保存済み・変えるときだけ入力）" : "トークン", text: $model.tokenText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await model.saveAndTestConnection() }
                } label: {
                    HStack {
                        Text("保存して接続を確かめる")
                        if model.connectionState == .testing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.connectionState == .testing)

                if let message = model.validationMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.shu)
                }
                status
            } header: {
                Text("接続先")
            } footer: {
                Text("AIのAPIキーはサーバーにだけ置き、このアプリには入れません。トークンはこの端末のキーチェーンに保存され、iCloud やバックアップで他の端末には移りません。接続できない設定は保存しません。")
            }

            if model.isConfigured {
                Section {
                    Button("接続を解除", role: .destructive) { confirmsDisconnect = true }
                        .foregroundStyle(Palette.shu)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("自分のサーバー")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("接続を解除しますか？", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button("解除", role: .destructive) { model.disconnect() }
        } message: {
            Text("保存したトークンも削除し、端末内のしくみに戻ります。")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.connectionState {
        case .idle:
            if model.isConfigured {
                Button("接続を確かめる") { Task { await model.testSavedConnection() } }
            } else {
                Label("未設定: 端末内できっかけを選んでいます", systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
        case .testing:
            EmptyView()
        case .connected(let status):
            VStack(alignment: .leading, spacing: 4) {
                Label("接続できました（v\(status.version) · \(status.provider == "mock" ? "開発用モック" : "AI")）", systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.ink)
                Text("今日の残り: きっかけ \(status.budget.requestsRemaining)回 · Web検索 \(status.budget.webSearchesRemaining)回")
                    .foregroundStyle(Palette.ink2)
                if !status.features.webSearch {
                    Text("サーバー側でWeb検索は無効です")
                        .foregroundStyle(Palette.ink2)
                }
            }
            .font(.footnote)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon")
                .font(.footnote)
                .foregroundStyle(Palette.shu)
        }
    }
}

// MARK: - 技の樹の書き出し

/// 技の樹の Markdown 保管庫。共有するときに初めて、フォルダを書いて zip にまとめる
struct TreeVaultExport: Transferable {
    let files: [VaultExporter.File]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { export in
            SentTransferredFile(try VaultArchive.make(files: export.files))
        }
        .suggestedFileName("taiken-tree.zip")
    }
}

enum VaultArchive {
    /// 一時フォルダに Markdown を書き、iOS のファイル連携 (NSFileCoordinator) で zip にする
    static func make(files: [VaultExporter.File]) throws -> URL {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
        let folder = base.appendingPathComponent(VaultExporter.folderName, isDirectory: true)
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        try VaultExporter.write(files, to: folder)

        let destination = base.appendingPathComponent("taiken-tree.zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try manager.copyItem(at: zipped, to: destination)
            } catch {
                copyError = error
            }
        }
        try? manager.removeItem(at: folder)
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }
}

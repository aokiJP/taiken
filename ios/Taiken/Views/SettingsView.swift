import SwiftUI
import TaikenCore
import UIKit

/// 設定 (指示書 §19: 情報の種類ごとに許可・拒否できる)
struct SettingsView: View {
    let dependencies: AppDependencies
    @Bindable private var model: SettingsViewModel

    @AppStorage(ConsentKey.useCalendar) private var useCalendar = true
    @AppStorage(ConsentKey.sendEventTitles) private var sendEventTitles = true
    @AppStorage(ConsentKey.useChatContext) private var useChatContext = true
    @AppStorage(ConsentKey.useHistory) private var useHistory = true
    @AppStorage(ConsentKey.useLocation) private var useLocation = false
    @AppStorage(ConsentKey.allowWebSearch) private var allowWebSearch = false

    @State private var confirmsDeletion = false
    @State private var confirmsDisconnect = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        model = dependencies.settings
    }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                consentSection
                notificationSection
                calendarSection
                dataSection
                aboutSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .task { await model.onAppear() }
            .confirmationDialog("体験の履歴と端末内のデータをすべて削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("削除", role: .destructive) { dependencies.deleteAllLocalData() }
            } message: {
                Text("接続先とトークン、情報の許可の設定は残ります。")
            }
            .confirmationDialog("接続を解除しますか？", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
                Button("解除", role: .destructive) { model.disconnect() }
            } message: {
                Text("保存したトークンも削除し、端末内の簡易モードに戻ります。")
            }
        }
    }

    // MARK: - 接続

    private var connectionSection: some View {
        Section {
            TextField("https://", text: $model.baseURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
            SecureField(model.hasSavedToken ? "トークン (保存済み・変更時のみ入力)" : "トークン", text: $model.tokenText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task { await model.saveAndTestConnection() }
            } label: {
                HStack {
                    Text("保存して接続テスト")
                    if model.connectionState == .testing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.connectionState == .testing)

            if let message = model.validationMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            connectionStatus

            if model.isConfigured {
                Button("接続を解除", role: .destructive) { confirmsDisconnect = true }
            }
        } header: {
            Text("接続先 (自分のBackend)")
        } footer: {
            Text("AIのAPIキーはBackendにだけ置き、このアプリには入れません。トークンはこの端末のキーチェーンに保存され、iCloudやバックアップで他の端末には移りません。")
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch model.connectionState {
        case .idle:
            if model.isConfigured {
                Button("接続テスト") { Task { await model.testSavedConnection() } }
            } else {
                Label("未設定: 端末内の簡易提案で動いています", systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .testing:
            EmptyView()
        case .connected(let status):
            VStack(alignment: .leading, spacing: 4) {
                Label("接続できました (v\(status.version) / \(status.provider == "mock" ? "モック" : "AI"))", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("今日の残り: リクエスト \(status.budget.requestsRemaining)回 · Web検索 \(status.budget.webSearchesRemaining)回")
                    .foregroundStyle(.secondary)
                if !status.features.webSearch {
                    Text("Backend側でWeb検索は無効です")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    // MARK: - 許可

    private var consentSection: some View {
        Section {
            Toggle("予定を体験づくりに使う", isOn: $useCalendar)
            Toggle("予定のタイトルも送る", isOn: $sendEventTitles)
                .disabled(!useCalendar)
            Toggle("最近の会話を提案に使う", isOn: $useChatContext)
            Toggle("体験の履歴と評価を提案に使う", isOn: $useHistory)
            Toggle("おおよその地域を使う", isOn: $useLocation)
                .onChange(of: useLocation) { _, enabled in
                    guard enabled else { return }
                    Task {
                        let state = await dependencies.locationProvider.requestAccess()
                        if state != .granted { useLocation = false }
                    }
                }
            Toggle("必要なときだけWeb検索する", isOn: $allowWebSearch)
        } header: {
            Text("AIに渡す情報")
        } footer: {
            Text("予定は今日と明日の時間とタイトルだけを送り、メモ・場所・参加者は読み取りません。地域は市区町村名だけで、座標は送りません。Web検索は天気など外部の情報が本当に必要なときだけ行い、検索語に予定のタイトルや発言は含めません。会話は端末に保存しません。")
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            Toggle("体験の提案を通知する", isOn: Binding(
                get: { model.notificationPreferences.enabled },
                set: { enabled in Task { await model.setNotificationsEnabled(enabled) } }
            ))
            if model.notificationPreferences.enabled {
                Picker("通知しない時間の開始", selection: preferenceBinding(\.quietStartHour)) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                Picker("通知しない時間の終了", selection: preferenceBinding(\.quietEndHour)) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                Stepper("1日に最大 \(model.notificationPreferences.maxPerDay) 回", value: preferenceBinding(\.maxPerDay), in: 1...5)
                Stepper("間隔は \(model.notificationPreferences.minimumIntervalHours) 時間以上", value: preferenceBinding(\.minimumIntervalHours), in: 1...12)
            }
            if let message = model.notificationMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("iOSの設定を開く") { openSettingsApp() }
            }
        } header: {
            Text("通知")
        } footer: {
            Text("ときどき裏側で状況を確かめ、提案する価値があり、今がよいタイミングで、負担にならないときだけ通知します。体験中・設定した時間帯・上限回数を超えるときは通知しません。")
        }
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
            Button("体験の履歴と端末内のデータを削除", role: .destructive) { confirmsDeletion = true }
        } header: {
            Text("端末内のデータ")
        } footer: {
            Text("履歴は「体験の履歴」画面からJSONで書き出せます。Backendは会話や予定を保存せず、1日の利用量の数字だけを記録します。")
        }
    }

    private var aboutSection: some View {
        Section("このアプリについて") {
            LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
            LabeledContent("動作モード", value: dependencies.isLocalMode ? "端末内の簡易モード" : "Backend接続")
        }
    }

    private func openSettingsApp() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

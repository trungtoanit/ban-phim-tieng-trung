//
//  Ban_Phim_Tieng_TrungApp.swift
//  Ban Phim Tieng Trung
//
//  Created by MAC on 14/09/2026.
//

import SwiftUI

@main
struct Ban_Phim_Tieng_TrungApp: App {
    @State private var openedFromKeyboard = false
    /// Tính năng đang mở trên màn hình chính; nil là đang ở màn hình chính.
    @State private var tab: AppTab?
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(StreakStore.goalKey, store: SharedSettings.store)
    private var dailyGoal = StreakStore.defaultGoal

    init() {
        StreakStore.raiseGoalIfNeeded()
        // Đã đăng nhập thì mở đồng bộ iCloud ngay từ đầu, để mở app là thấy tiến độ máy khác.
        if AccountStore.shared.isSignedIn { CloudSync.shared.start() }
        NaturalSpeaker.hasOpenAIVoice = { OpenAISettings.hasAPIKey }
        NaturalSpeaker.openAISpeech = { text, languageCode in
            try await OpenAIClient.speech(text: text, languageCode: languageCode)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(tab: $tab, openedFromKeyboard: openedFromKeyboard)
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(1)
                }
            }
            .onOpenURL { url in
                guard url.scheme == AppGroup.urlScheme else { return }
                // Bàn phím mở app để bật micro: vào thẳng, không bắt chờ màn chào.
                showSplash = false
                openedFromKeyboard = true
                tab = .keyboard
                VoiceEngine.shared.activate()
            }
            // Icon ngoài màn hình chính đi theo tâm trạng gấu trúc.
            .onChange(of: scenePhase) { phase in
                if phase == .active { MascotIcon.sync() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .streakChanged)) { _ in
                MascotIcon.sync()
            }
            .onChange(of: dailyGoal) { _ in MascotIcon.sync() }
        }
    }
}

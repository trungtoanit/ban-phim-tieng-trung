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
    @ObservedObject private var web = WebAccountStore.shared
    /// Bấm "Để sau" ở màn đăng nhập: không hỏi lại tới lần mở app sau.
    @State private var loginSkipped = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(StreakStore.goalKey, store: SharedSettings.store)
    private var dailyGoal = StreakStore.defaultGoal

    init() {
        StreakStore.raiseGoalIfNeeded()
        // Nút trong ScrollView (màn hình chính, danh sách) mặc định đợi ~150 ms để phân biệt chạm với
        // cuộn rồi mới hiện trạng thái nhấn, nên bấm thấy trễ. Tắt đợi: nhấn là lún ngay như màn hình
        // chính iPhone; bắt đầu kéo thì scroll view vẫn huỷ chạm và cuộn bình thường.
        UIScrollView.appearance().delaysContentTouches = false
        // Đã đăng nhập thì mở đồng bộ iCloud ngay từ đầu, để mở app là thấy tiến độ máy khác.
        if AccountStore.shared.isSignedIn { CloudSync.shared.start() }
        // Đã đăng nhập website: dùng giọng đọc của máy chủ giống trang web (không cần khoá riêng).
        NaturalSpeaker.hasOpenAIVoice = { WebAccountStore.shared.isSignedIn || OpenAISettings.hasAPIKey }
        NaturalSpeaker.openAISpeech = { text, languageCode in
            if WebAccountStore.shared.isSignedIn {
                return try await WebSpeechAPI.speech(text: text, languageCode: languageCode)
            }
            return try await OpenAIClient.speech(text: text, languageCode: languageCode)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(tab: $tab, openedFromKeyboard: openedFromKeyboard)
                // Chưa đăng nhập website thì mời đăng nhập ngay sau màn chào (mở từ bàn phím thì bỏ qua).
                if !showSplash, !web.isSignedIn, !loginSkipped, !openedFromKeyboard {
                    WebLoginView { withAnimation(.easeOut(duration: 0.25)) { loginSkipped = true } }
                        .transition(.opacity)
                        .zIndex(1)
                }
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(2)
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
            // Vừa đăng nhập xong (màn đăng nhập hay form trong tính năng nào): về trang chủ.
            // Đăng xuất (trong Hồ sơ / tường) cũng về trang chủ, để màn mời đăng nhập ở trên không bị
            // tính năng đang phủ toàn màn hình che mất.
            .onChange(of: web.user?.id) { _ in
                guard !openedFromKeyboard else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { tab = nil }
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

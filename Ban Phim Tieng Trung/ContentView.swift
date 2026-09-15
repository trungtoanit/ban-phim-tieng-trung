//
//  ContentView.swift
//  Ban Phim Tieng Trung
//
//  Created by MAC on 14/09/2026.
//

import SwiftUI

enum AppTab: Hashable {
    case practice
    case conversation
    case vocabulary
    case sounds
    case mistakes
    case keyboard
    case about
    case interpreter
}

struct ContentView: View {
    /// Tính năng đang mở; nil là đang ở màn hình chính.
    @Binding var tab: AppTab?
    var openedFromKeyboard = false
    /// Tổng số lỗi phát âm, hiện thành số đỏ trên icon Sửa lỗi.
    @StateObject private var mistakes = MistakeStore()
    /// Số câu còn phải đọc hôm nay, hiện thành số đỏ trên icon Hội thoại; đủ mục tiêu thì ẩn.
    @State private var streak = StreakStore.summary()
    @State private var iconFrames = IconFrameRegistry()
    /// Tính năng đã phủ kín màn hình: tạm ẩn màn hình chính để không phải vẽ nó phía sau.
    @State private var homeHidden = false
    @AppStorage(StreakStore.goalKey, store: SharedSettings.store)
    private var dailyGoal = StreakStore.defaultGoal
    @Environment(\.scenePhase) private var scenePhase

    private var badges: [AppTab: Int] {
        [.conversation: streak.remaining, .mistakes: mistakes.mistakes.count]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HomeScreenView(badges: badges, streak: streak, frames: iconFrames) { app in
                    tab = app
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(homeHidden ? 0 : 1)
                .allowsHitTesting(!homeHidden)

                if let open = tab {
                    feature(open)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .environment(\.goHome) { tab = nil }
                        .background(Color(.systemGroupedBackground).ignoresSafeArea())
                        // Mở ra phóng từ đúng icon vừa chạm, đóng lại thu về icon đó.
                        .transition(.scale(scale: 0.06, anchor: anchor(for: open, in: geo)).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: tab)
        }
        .onChange(of: tab) { open in
            if open == nil {
                // Hiện lại ngay (không hiệu ứng) để tính năng thu về đúng icon trên màn hình chính.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { homeHidden = false }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    if tab != nil { homeHidden = true }
                }
            }
        }
        .tint(Color(red: 0.86, green: 0.17, blue: 0.16))
        // Bàn phím ghi lỗi từ tiến trình khác, không báo sang được: quay lại app thì đếm lại.
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            mistakes.reload()
            // Mở lại app sang ngày mới thì đếm lại từ đầu mục tiêu.
            refreshStreak()
        }
        // Nhật ký câu nói có thể được ghi từ luồng âm thanh: nhận về luồng chính rồi mới cập nhật.
        .onReceive(NotificationCenter.default.publisher(for: .streakChanged).receive(on: DispatchQueue.main)) { _ in
            refreshStreak()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            refreshStreak()
        }
        .onChange(of: dailyGoal) { _ in refreshStreak() }
    }

    @ViewBuilder
    private func feature(_ app: AppTab) -> some View {
        switch app {
        case .practice: PracticeView()
        case .conversation: ConversationTopicsView()
        case .vocabulary: VocabularyTabView()
        case .sounds: SoundsTabView()
        case .mistakes: MistakesTabView()
        case .keyboard: KeyboardHomeView(openedFromKeyboard: openedFromKeyboard)
        case .about: AboutView()
        case .interpreter: InterpreterView()
        }
    }

    /// Tâm của icon tính theo tỉ lệ khung màn hình; không có icon (mở từ bàn phím) thì phóng từ giữa.
    private func anchor(for app: AppTab, in geo: GeometryProxy) -> UnitPoint {
        guard let frame = iconFrames.frames[app], geo.size.width > 0, geo.size.height > 0 else { return .center }
        let origin = geo.frame(in: .global).origin
        return UnitPoint(x: (frame.midX - origin.x) / geo.size.width, y: (frame.midY - origin.y) / geo.size.height)
    }

    private func refreshStreak() {
        streak = StreakStore.summary()
    }
}

struct KeyboardHomeView: View {
    var openedFromKeyboard = false

    @ObservedObject private var engine = VoiceEngine.shared
    @AppStorage(VoiceEngine.scriptKey) private var script = ChineseScript.simplified.rawValue
    @AppStorage(VoiceEngine.keepAliveKey) private var keepAliveMinutes = 15
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false
    @AppStorage(SharedSettings.politeKey, store: SharedSettings.store) private var polite = false
    @State private var testText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                if openedFromKeyboard && engine.state.sessionActive {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Micro đã sẵn sàng!")
                                    .font(.headline)
                                Text("Nhấn « ◀ » ở góc trên bên trái màn hình để quay lại ứng dụng nhắn tin, rồi nhấn 🎙 trên bàn phím để nói.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                micSection
                setupSection
                optionsSection

                Section("Thử ngay") {
                    TextField("Chạm vào đây rồi chuyển sang Bàn Phím Trung 🌐", text: $testText, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !engine.history.isEmpty {
                    Section("Gần đây") {
                        ForEach(engine.history) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                RubyText(words: item.words, hanziSize: 20, showHanViet: showHanViet)
                                if item.source != item.chinese {
                                    Text(item.source).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Text("Giọng nói được nhận dạng bằng dịch vụ của Apple; câu tiếng Việt được gửi tới Google Dịch để chuyển sang tiếng Trung. Micro chỉ ghi khi bạn nhấn 🎙 trên bàn phím.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bàn Phím Trung")
            .homeBackButton()
        }
    }

    private var micSection: some View {
        Section("Micro") {
            HStack(spacing: 14) {
                LiveMicIcon(active: engine.state.sessionActive)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(engine.state.sessionActive ? "Micro đang bật cho bàn phím" : "Micro đang tắt")
                            .font(.headline)
                        if engine.state.sessionActive {
                            LiveBadge()
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: engine.state.sessionActive)
                    Text(engine.state.sessionActive
                         ? "Tự tắt sau \(keepAliveMinutes) phút không dùng"
                         : "Bàn phím sẽ tự mở app này khi cần bật micro")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(engine.state.sessionActive ? "Tắt micro" : "Bật micro ngay") {
                if engine.state.sessionActive {
                    engine.deactivate()
                } else {
                    engine.activate()
                }
            }

            if engine.state.phase == .error, !engine.state.errorMessage.isEmpty {
                Text(engine.state.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var setupSection: some View {
        Section("Cài bàn phím (1 lần)") {
            step(1, "Nhấn nút bên dưới để mở Cài đặt → Bàn phím.")
            step(2, "Bật “Bàn Phím Trung” và “Cho phép truy cập đầy đủ” (cần để bàn phím nói chuyện với app).")
            step(3, "Trong Zalo, Messenger, WeChat… nhấn giữ 🌐 để chọn Bàn Phím Trung.")
            step(4, "Nhấn 🎙 lần đầu: app mở ra để bật micro → nhấn « ◀ » quay lại → nhấn 🎙 và nói.")

            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        }
    }

    private var optionsSection: some View {
        Section("Tuỳ chọn") {
            Picker("Chữ Hán", selection: $script) {
                ForEach(ChineseScript.allCases) { script in
                    Text(script.label).tag(script.rawValue)
                }
            }
            Picker("Giữ micro bật", selection: $keepAliveMinutes) {
                ForEach([5, 15, 30, 60], id: \.self) { minutes in
                    Text("\(minutes) phút").tag(minutes)
                }
            }
            Toggle("Hiện âm Hán Việt dưới chữ Hán", isOn: $showHanViet)
            Toggle("Dịch lịch sự (您, 请…)", isOn: $polite)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.red))
            Text(text)
                .font(.subheadline)
        }
    }
}

/// Biểu tượng micro: đang bật thì có vòng sóng lan ra và nhịp thở nhẹ, tắt thì xám đứng yên.
private struct LiveMicIcon: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            if active {
                RecordingHalo(color: .green, size: 40)
            }
            Circle()
                .fill(active ? Color.green.opacity(0.16) : Color(.tertiarySystemFill))
                .frame(width: 44, height: 44)
                .scaleEffect(active && breathe ? 1.08 : 1)
            Image(systemName: active ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(active ? .green : .secondary)
                .scaleEffect(active && breathe ? 1.12 : 1)
                .contentTransition(.opacity)
        }
        .frame(width: 52, height: 52)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: active)
        .onAppear(perform: restart)
        .onChange(of: active) { _ in restart() }
        .onDisappear { breathe = false }
        .accessibilityHidden(true)
    }

    private func restart() {
        breathe = false
        guard active, !reduceMotion else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// Nhãn "● TRỰC TIẾP" nhấp nháy cạnh tiêu đề khi micro đang bật.
private struct LiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .opacity(blink ? 0.25 : 1)
            Text("TRỰC TIẾP")
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.green))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { blink = true }
        }
        .accessibilityLabel("Đang bật")
    }
}

#Preview {
    ContentView(tab: .constant(nil))
}

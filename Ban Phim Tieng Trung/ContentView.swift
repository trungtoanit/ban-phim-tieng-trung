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
    case sounds
    case mistakes
    case keyboard
}

struct ContentView: View {
    @Binding var tab: AppTab
    var openedFromKeyboard = false
    /// Tổng số lỗi phát âm, hiện thành số đỏ trên tab Sửa lỗi.
    @StateObject private var mistakes = MistakeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            PracticeView()
                .tabItem { Label("Luyện nói", systemImage: "text.bubble.fill") }
                .tag(AppTab.practice)
            ConversationTopicsView()
                .tabItem { Label("Hội thoại", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.conversation)
            SoundsTabView()
                .tabItem { Label("Phát âm", systemImage: "character.book.closed.fill") }
                .tag(AppTab.sounds)
            MistakesTabView()
                .tabItem { Label("Sửa lỗi", systemImage: "exclamationmark.bubble.fill") }
                .badge(mistakes.mistakes.count)
                .tag(AppTab.mistakes)
            KeyboardHomeView(openedFromKeyboard: openedFromKeyboard)
                .tabItem { Label("Bàn phím", systemImage: "keyboard") }
                .tag(AppTab.keyboard)
        }
        .tint(Color(red: 0.86, green: 0.17, blue: 0.16))
        // Bàn phím ghi lỗi từ tiến trình khác, không báo sang được: quay lại app thì đếm lại.
        .onChange(of: scenePhase) { phase in
            if phase == .active { mistakes.reload() }
        }
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
        }
    }

    private var micSection: some View {
        Section("Micro") {
            HStack(spacing: 12) {
                Image(systemName: engine.state.sessionActive ? "mic.fill" : "mic.slash.fill")
                    .font(.title2)
                    .foregroundStyle(engine.state.sessionActive ? .green : .secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.state.sessionActive ? "Micro đang bật cho bàn phím" : "Micro đang tắt")
                        .font(.headline)
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

#Preview {
    ContentView(tab: .constant(.practice))
}

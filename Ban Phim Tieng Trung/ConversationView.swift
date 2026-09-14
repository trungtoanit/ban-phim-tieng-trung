//
//  ConversationView.swift
//  Ban Phim Tieng Trung
//

import SwiftUI

private let brandRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct ConversationTopicsView: View {
    @StateObject private var store = ScenarioStore()
    @AppStorage(OpenAISettings.levelKey) private var level = ConversationLevel.beginner.rawValue
    @State private var hasKey = OpenAISettings.hasAPIKey
    @State private var showSettings = false
    @State private var customTopic = ""
    @State private var customScenario: Scenario?

    private func startCustom(_ title: String) {
        store.addCustom(title)
        customTopic = ""
        customScenario = .custom(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if hasKey {
                        Label("Đã kết nối OpenAI · \(OpenAISettings.model)", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Kết nối OpenAI để bắt đầu (nhập khoá API)", systemImage: "key.fill")
                        }
                    }
                    Picker("Trình độ", selection: $level) {
                        ForEach(ConversationLevel.allCases) { level in
                            Text(level.label).tag(level.rawValue)
                        }
                    }
                } footer: {
                    Text("AI nhập vai theo tình huống, bạn nói tiếng Trung tự do. Mỗi câu AI đều có chữ Hán và pinyin, kèm góp ý cho câu bạn nói.")
                }

                Section {
                    HStack {
                        TextField("Ví dụ: phỏng vấn xin việc, đi khám răng…", text: $customTopic)
                            .submitLabel(.go)
                            .onSubmit { startCustom(customTopic) }
                        Button("Bắt đầu") { startCustom(customTopic) }
                            .disabled(customTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(store.customTitles, id: \.self) { title in
                        Button {
                            startCustom(title)
                        } label: {
                            HStack(spacing: 12) {
                                Text("🧑")
                                    .font(.system(size: 26))
                                Text(title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: store.removeCustom)
                } header: {
                    Text("Tình huống của bạn")
                } footer: {
                    if !store.customTitles.isEmpty {
                        Text("Được lưu trên máy. Vuốt sang trái để xoá.")
                    }
                }

                ForEach(store.topics, id: \.self) { topic in
                    Section(topic) {
                        ForEach(store.scenarios(in: topic)) { scenario in
                            NavigationLink {
                                ConversationView(scenario: scenario)
                            } label: {
                                row(scenario)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hội thoại AI")
            .toolbar {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Cài đặt OpenAI")
            }
            .navigationDestination(isPresented: Binding(
                get: { customScenario != nil },
                set: { if !$0 { customScenario = nil } }
            )) {
                if let customScenario {
                    ConversationView(scenario: customScenario)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { hasKey = OpenAISettings.hasAPIKey }) {
                OpenAISettingsView()
            }
        }
    }

    private func row(_ scenario: Scenario) -> some View {
        HStack(spacing: 12) {
            Text(scenario.partnerEmoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                    .font(.headline)
                Text("Nói chuyện với \(scenario.partnerRole.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ConversationView: View {
    @StateObject private var session: AIConversationSession
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false
    @State private var selectedWord: SelectedWord?
    @State private var draft = ""
    @State private var showSettings = false

    init(scenario: Scenario) {
        _session = StateObject(wrappedValue: AIConversationSession(scenario: scenario))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                        ForEach(session.messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        if session.isThinking {
                            thinkingBubble
                                .id("thinking")
                        }
                        if let error = session.errorMessage {
                            errorCard(error)
                                .id("error")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages) { _ in scrollToBottom(proxy) }
                .onChange(of: session.isThinking) { _ in scrollToBottom(proxy) }
            }
            Divider()
            bottomPanel
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                session.start()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Bắt đầu lại")
        }
        .onAppear {
            if !session.hasStarted { session.start() }
        }
        .onDisappear {
            session.stop()
        }
        .sheet(item: $selectedWord) { selection in
            WordDetailSheet(word: selection.word)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showSettings, onDismiss: { session.retry() }) {
            OpenAISettingsView()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if session.isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = session.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Tin nhắn

    private var header: some View {
        VStack(spacing: 4) {
            Text(session.scenario.partnerEmoji)
                .font(.system(size: 40))
            Text("Bạn là \(session.scenario.userRole.lowercased()), nói chuyện với \(session.scenario.partnerRole.lowercased())")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func bubble(_ message: AIConversationSession.Message) -> some View {
        switch message.speaker {
        case .partner:
            HStack(alignment: .top, spacing: 8) {
                Text(session.scenario.partnerEmoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 6) {
                    ruby(message.line, size: 22)
                    HStack(alignment: .top) {
                        Text(message.line.vi)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        speakButton(message.line)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                Spacer(minLength: 24)
            }
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .leading, spacing: 8) {
                    if ChineseText.containsHan(message.line.zh) {
                        ruby(message.line, size: 20)
                        if !message.line.vi.isEmpty {
                            Text(message.line.vi)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(message.line.zh)
                    }
                    if let feedback = message.feedback {
                        Label(feedback, systemImage: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let corrected = message.corrected {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nói tự nhiên hơn:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                            HStack(alignment: .top) {
                                ruby(corrected, size: 18)
                                Spacer(minLength: 4)
                                speakButton(corrected)
                            }
                            if !corrected.vi.isEmpty {
                                Text(corrected.vi)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.08)))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(brandRed.opacity(0.12)))
            }
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            Text(session.scenario.partnerEmoji)
                .font(.system(size: 28))
            HStack(spacing: 8) {
                ProgressView()
                Text("\(session.scenario.partnerRole) đang trả lời…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            Spacer()
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
            HStack {
                if session.canRetry {
                    Button("Thử lại") { session.retry() }
                        .buttonStyle(.bordered)
                }
                if !OpenAISettings.hasAPIKey || error.contains("Khoá") || error.contains("model") {
                    Button("Cài đặt OpenAI") { showSettings = true }
                        .buttonStyle(.bordered)
                }
            }
            .tint(brandRed)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
    }

    private func ruby(_ line: ChatLine, size: CGFloat) -> some View {
        RubyText(words: line.words, hanziSize: size, showHanViet: showHanViet) {
            selectedWord = SelectedWord(word: $0)
        }
    }

    private func speakButton(_ line: ChatLine) -> some View {
        Button {
            session.speak(line)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(brandRed)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Khu vực trả lời

    private var bottomPanel: some View {
        HStack(spacing: 8) {
            // Một dòng để phím ↵ của bàn phím gửi luôn tin nhắn.
            TextField("Nhập hoặc nói bằng bàn phím (tiếng Trung / tiếng Việt)…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit(sendDraft)
            Button(action: sendDraft) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(brandRed)
            }
            .disabled(session.isThinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Gửi")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func sendDraft() {
        session.send(text: draft)
        draft = ""
    }
}

struct OpenAISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OpenAISettings.modelKey) private var model = OpenAISettings.defaultModel
    @AppStorage(OpenAISettings.voiceKey) private var voice = OpenAISettings.defaultVoice
    @State private var keyInput = ""
    @State private var hasKey = OpenAISettings.hasAPIKey
    @State private var testResult: String?
    @State private var isTesting = false

    private struct Ping: Decodable { let ok: Bool }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasKey {
                        Label("Đã lưu khoá API trong Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    SecureField(hasKey ? "Nhập khoá mới để thay" : "sk-…", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Lưu khoá") {
                        if OpenAISettings.saveAPIKey(keyInput) {
                            keyInput = ""
                            hasKey = true
                            testResult = nil
                        }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button("Xoá khoá", role: .destructive) {
                            OpenAISettings.deleteAPIKey()
                            hasKey = false
                        }
                    }
                } header: {
                    Text("Khoá API OpenAI")
                } footer: {
                    Text("Tạo khoá tại platform.openai.com/api-keys. Khoá chỉ lưu trên máy này (Keychain) và chỉ gửi tới OpenAI. Chi phí tính vào tài khoản OpenAI của bạn.")
                }

                Section {
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("Chọn nhanh model") {
                        ForEach(OpenAISettings.suggestedModels, id: \.self) { name in
                            Button(name) { model = name }
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("gpt-5.6-luna rẻ và nhanh, đủ cho hội thoại ngắn. gpt-5.6-terra thông minh hơn nhưng đắt hơn.")
                }

                Section {
                    Picker("Giọng", selection: $voice) {
                        ForEach(OpenAISettings.voices, id: \.self) { name in
                            Text(name.capitalized).tag(name)
                        }
                    }
                    Button {
                        NaturalSpeaker.chinese.speak("你好！很高兴认识你，我们用中文聊聊天吧。", preferOpenAI: true)
                    } label: {
                        Label("Nghe thử giọng tiếng Trung", systemImage: "play.circle.fill")
                    }
                    .disabled(!hasKey)
                } header: {
                    Text("Giọng đọc OpenAI")
                } footer: {
                    Text("Màn hình hội thoại dùng giọng \(OpenAISettings.speechModel) của OpenAI (tự nhiên hơn, có tính phí nhỏ). Lỗi mạng sẽ tự chuyển sang giọng Google.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Kiểm tra kết nối")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!hasKey || isTesting)
                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("✅") ? .green : .red)
                    }
                } footer: {
                    Text("Nội dung gửi tới OpenAI: tình huống hội thoại và chữ bạn nói (đã chuyển thành văn bản). Âm thanh giọng nói không được gửi đi.")
                }
            }
            .navigationTitle("Kết nối OpenAI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["ok": ["type": "boolean"]],
            "required": ["ok"],
            "additionalProperties": false,
        ]
        Task {
            do {
                _ = try await OpenAIClient.respond(
                    instructions: "Reply with {\"ok\": true}.", messages: [.init(role: .user, content: "ping")],
                    schemaName: "ping", schema: schema, as: Ping.self
                )
                await MainActor.run { testResult = "✅ Kết nối thành công với \(OpenAISettings.model)"; isTesting = false }
            } catch {
                await MainActor.run { testResult = "❌ \(error.localizedDescription)"; isTesting = false }
            }
        }
    }
}

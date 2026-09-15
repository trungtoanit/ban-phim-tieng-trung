//
//  ConversationView.swift
//  Ban Phim Tieng Trung
//

import Foundation
import SwiftUI

private let brandRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct ConversationTopicsView: View {
    @StateObject private var store = ScenarioStore()
    @AppStorage("conversationRealtime") private var realtime = false
    @AppStorage(StreakStore.goalKey, store: SharedSettings.store)
    private var dailyGoal = StreakStore.defaultGoal
    @State private var hasKey = OpenAISettings.hasAPIKey
    @State private var showSettings = false
    @State private var showStreak = false
    @State private var milestone: Int?
    @State private var customTopic = ""
    @FocusState private var topicFocused: Bool
    @State private var customScenario: Scenario?
    @State private var streak = StreakStore.summary()
    /// Chỉ mừng mốc khi đang thật sự đứng ở màn hình này.
    @State private var isVisible = false

    private func startCustom(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bấm Go trên bàn phím khi ô còn trống thì thôi, đừng mở một tình huống không tên.
        guard !trimmed.isEmpty else { return }
        store.addCustom(trimmed)
        customTopic = ""
        topicFocused = false
        customScenario = .custom(trimmed)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    streakCard
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))

                if !hasKey {
                    Section {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Kết nối OpenAI để bắt đầu (nhập khoá API)", systemImage: "key.fill")
                        }
                    }
                }

                Section {
                    newTopicCard
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                if !store.customTitles.isEmpty {
                    Section {
                        ForEach(store.customTitles, id: \.self) { title in
                            Button {
                                startCustom(title)
                            } label: {
                                HStack(spacing: 0) {
                                    let info = store.info(forCustom: title)
                                    scenarioRow(id: Scenario.custom(title).id,
                                                emoji: info.emoji,
                                                title: title,
                                                subtitle: info.caption)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onDelete(perform: store.removeCustom)
                    } header: {
                        Label("Tình huống của bạn", systemImage: "list.bullet")
                    } footer: {
                        Text("Được lưu trên máy. Nói đủ \(ScenarioStore.targetSentences) câu thì tình huống tự xoá khi thoát ra. Vuốt sang trái để xoá ngay.")
                    }
                }
            }
            .onAppear {
                isVisible = true
                store.refreshStats()
                store.isListVisible = true
                store.describeMissingCustom()
                refreshStreak()
                StreakReminder.reschedule()
            }
            .onDisappear {
                isVisible = false
                store.isListVisible = false
            }
            .alert(completedTitle, isPresented: Binding(
                get: { !store.completedCustom.isEmpty },
                set: { if !$0 { store.completedCustom = [] } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Bạn đã nói đủ \(ScenarioStore.targetSentences) câu nên tình huống được xoá khỏi danh sách. Muốn luyện tiếp thì gõ lại tên tình huống.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .streakChanged)) { _ in
                let wasDone = streak.doneToday
                refreshStreak()
                // Vừa đạt mục tiêu: huỷ lời nhắc của hôm nay.
                if streak.doneToday != wasDone { StreakReminder.reschedule() }
            }
            .onChange(of: dailyGoal) { _ in
                streak = StreakStore.summary()
                StreakReminder.reschedule()
            }
            .navigationTitle("Hội thoại AI")
            .homeBackButton()
            .toolbar {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Cài đặt")
            }
            .sheet(isPresented: $showStreak) {
                StreakDetailView()
            }
            .sheet(item: Binding(
                get: { milestone.map { MilestoneBadge(days: $0) } },
                set: { _ in milestone = nil }
            )) { badge in
                MilestoneView(days: badge.days)
                    .presentationDetents([.height(380)])
            }
            .navigationDestination(isPresented: Binding(
                get: { customScenario != nil },
                set: { if !$0 { customScenario = nil } }
            )) {
                if let customScenario {
                    if realtime {
                        RealtimeConversationView(scenario: customScenario)
                    } else {
                        ConversationView(scenario: customScenario)
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { hasKey = OpenAISettings.hasAPIKey }) {
                OpenAISettingsView()
            }
        }
    }

    /// Ô nhập chủ đề mới: thẻ riêng, viền rõ, nút đỏ — trước đây nằm lẫn như một dòng trong danh sách.
    private var newTopicCard: some View {
        let isEmpty = customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            Label("Hôm nay muốn nói về chủ đề gì?", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .foregroundStyle(topicFocused ? brandRed : .secondary)
                TextField("Phỏng vấn xin việc, đi khám răng…", text: $customTopic)
                    .font(.body)
                    .focused($topicFocused)
                    .submitLabel(.go)
                    .onSubmit { startCustom(customTopic) }
                if !isEmpty {
                    Button {
                        customTopic = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Xoá chữ đã gõ")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(topicFocused ? brandRed : Color(.separator), lineWidth: topicFocused ? 1.5 : 1))
            .contentShape(Rectangle())
            .onTapGesture { topicFocused = true }

            Button {
                startCustom(customTopic)
            } label: {
                Label("Bắt đầu nói", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(brandRed.opacity(isEmpty ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)

            if store.customTitles.isEmpty {
                Text("Mỗi tình huống cần nói đủ \(ScenarioStore.targetSentences) câu; đủ rồi thì thoát ra là tình huống tự xoá.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .animation(.easeInOut(duration: 0.15), value: topicFocused)
    }

    private var completedTitle: String {
        let done = store.completedCustom
        guard done.count == 1, let first = done.first else { return "Hoàn thành \(done.count) tình huống 🎉" }
        return "Hoàn thành “\(first.title)” 🎉"
    }

    private var todayLine: String {
        let time = streak.today.seconds >= 60 ? " · \(Self.duration(streak.today.seconds))" : ""
        if streak.doneToday {
            return "Xong mục tiêu hôm nay — \(streak.today.sentences) câu\(time) 👏"
        }
        if streak.activeToday {
            return "Đã giữ chuỗi hôm nay 🔥 \(streak.today.sentences)/\(streak.goal) câu\(time), còn \(streak.remaining) câu để xong mục tiêu."
        }
        return "Hôm nay \(streak.today.sentences)/\(streak.goal) câu\(time) — nói thêm \(streak.toKeepStreak) câu để giữ chuỗi."
    }

    private func refreshStreak() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            streak = StreakStore.summary()
        }
        // Chuỗi có thể nhích lên trong lúc người học đang nói dở ở màn hình khác, hoặc lúc
        // đang mở sheet — mừng ngay lúc đó là phủ lên việc họ đang làm. Đợi về đây đã.
        guard isVisible, milestone == nil, !showStreak, !showSettings, store.completedCustom.isEmpty,
              let pending = StreakStore.pendingMilestone(streak: streak.streak) else { return }
        // Ghi nhận ngay, không đợi lúc đóng: app bị tắt giữa chừng thì cũng không mừng lại.
        StreakStore.markCelebrated(pending)
        milestone = pending
    }

    /// Thẻ chuỗi: con số to, tiến độ hôm nay, và cả tuần này. Chạm để xem lịch tháng.
    private var streakCard: some View {
        Button {
            showStreak = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    FlameView(size: 26, isLit: streak.streak > 0)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak.streak)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text(streak.streak == 1 ? "ngày" : "ngày liên tiếp")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    MascotView(mood: MascotMood(streak), size: 46)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                weekRow

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: streak.progress)
                        .tint(streak.doneToday ? .green : brandRed)
                    Text(todayLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if streak.usedGrace {
                        Label("Đang dùng một ngày nghỉ bù — hôm nay nói là mạch nối lại.",
                              systemImage: "snowflake")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(streak.week.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 6) {
                    Text(Self.weekdayLabels[index])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(day.isToday ? brandRed : .secondary)
                    StreakDayMark(day: day, size: 30)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static let weekdayLabels = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) giây" }
        let minutes = total / 60
        guard minutes >= 60 else { return "\(minutes) phút" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60) giờ" : "\(minutes / 60) giờ \(remainder) phút"
    }

    /// Một dòng tình huống: mặt cười trong vòng tròn, tên, rồi mấy chỉ số nhỏ.
    /// Tình huống vừa nói gần đây nhất có vòng sóng đỏ và nhãn "Đang học".
    private func scenarioRow(id: Int, emoji: String, title: String, subtitle: String) -> some View {
        let stat = store.stats[id]
        let isRecent = store.recentID == id
        return HStack(spacing: 13) {
            ZStack {
                if isRecent {
                    RecordingHalo(color: brandRed, size: 46)
                }
                Circle()
                    .fill(isRecent ? brandRed.opacity(0.14) : Color(.secondarySystemFill))
                    .frame(width: 44, height: 44)
                Text(emoji)
                    .font(.system(size: 24))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isRecent {
                        Text("Đang học")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(brandRed))
                    }
                }

                // Chú thích luôn hiện, kể cả khi đã nói: nhìn là biết tình huống này nói về gì.
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let stat {
                    HStack(spacing: 12) {
                        chip("text.bubble.fill", "\(stat.sentences)/\(ScenarioStore.targetSentences) câu")
                        if stat.seconds >= 60 {
                            chip("clock.fill", Self.duration(stat.seconds))
                        }
                        if !stat.finished {
                            chip("pause.circle.fill", "đang dở", tint: brandRed)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
    }

    private func chip(_ icon: String, _ text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
    }
}

struct ConversationView: View {
    @StateObject private var session: AIConversationSession
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false
    @State private var selectedWord: SelectedWord?
    @State private var draft = ""
    /// Những câu AI mà người học đã bấm xem gợi ý.
    @State private var revealedHints: Set<UUID> = []
    @State private var savedCount = 0
    @State private var confirmRestart = false
    @State private var showSettings = false
    /// Chế độ rảnh tay toàn màn hình kiểu ChatGPT Voice.
    @State private var voiceMode = false

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
                        if session.needsResumeChoice {
                            Text("Bạn dừng ở đây")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 2)
                                .id("resume")
                        }
                        if session.isFinished {
                            summaryCard
                                .id("summary")
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
                .onChange(of: session.isFinished) { _ in
                    guard session.isFinished else { return }
                    withAnimation { proxy.scrollTo("summary", anchor: .bottom) }
                }
            }
            if session.needsResumeChoice {
                Divider()
                resumeBar
            } else if !session.isFinished {
                Divider()
                bottomPanel
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $voiceMode) {
            VoiceModeView(session: session)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    voiceMode = true
                } label: {
                    Image(systemName: "waveform.circle.fill")
                }
                .accessibilityLabel("Chế độ rảnh tay")
                Button {
                    session.finish()
                } label: {
                    Image(systemName: "flag.checkered")
                }
                .accessibilityLabel("Kết thúc và xem tổng kết")
                .disabled(session.messages.isEmpty || session.needsResumeChoice)
                Button {
                    if session.messages.isEmpty {
                        session.start()
                    } else {
                        confirmRestart = true
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Bắt đầu lại")
            }
        }
        .onAppear {
            session.prepare()
        }
        .onDisappear {
            session.stop()
        }
        .wordPopup($selectedWord)
        .sheet(isPresented: $showSettings, onDismiss: { session.retry() }) {
            OpenAISettingsView()
        }
        .confirmationDialog("Bỏ đoạn đang nói?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Bỏ và nói lại từ đầu", role: .destructive) {
                savedCount = 0
                session.start()
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            let turns = session.needsResumeChoice ? session.savedTurns : session.summary.spokenTurns
            Text("\(turns) lượt bạn đã nói trong đoạn này sẽ mất.")
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if session.needsResumeChoice {
                proxy.scrollTo("resume", anchor: .bottom)
            } else if session.isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = session.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    /// Vào lại tình huống đã nói dở. Đoạn cũ hiện sẵn phía trên, ở đây chỉ còn một việc
    /// tự nhiên là nói tiếp; mở đoạn mới vẫn có nhưng là hành động phụ và có hỏi lại.
    private var resumeBar: some View {
        VStack(spacing: 10) {
            if let pending = session.pendingLine {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                    Text(pending.vi.isEmpty ? "Bạn hội thoại đang chờ bạn trả lời" : "Đang chờ bạn trả lời: \(pending.vi)")
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                session.resume()
            } label: {
                Label("Nói tiếp — đã đi được \(session.savedTurns) lượt", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(brandRed)

            Button("Bỏ đoạn này, nói lại từ đầu") {
                confirmRestart = true
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    /// Tổng kết buổi nói: nói được bao nhiêu, câu nào nên mang sang luyện lại.
    private var summaryCard: some View {
        let summary = session.summary
        return VStack(alignment: .leading, spacing: 12) {
            Label("Tổng kết buổi nói", systemImage: "list.bullet.rectangle")
                .font(.headline)
            Text("Bạn đã nói \(summary.spokenTurns) lượt, trong đó \(summary.cleanTurns) lượt máy nghe rõ ngay từ lần đầu.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !summary.keepers.isEmpty {
                Divider()
                Text("Câu nên nhớ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(summary.keepers.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top) {
                            ruby(line, size: 15)
                            Spacer(minLength: 4)
                            speakButton(line)
                        }
                        if !line.vi.isEmpty {
                            Text(line.vi)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    savedCount = session.saveToPractice()
                } label: {
                    Label(session.savedToPractice
                          ? "Đã thêm \(savedCount) câu vào Luyện nói"
                          : "Thêm \(summary.keepers.count) câu vào Luyện nói",
                          systemImage: session.savedToPractice ? "checkmark.circle.fill" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(session.savedToPractice)
            }

            HStack(spacing: 10) {
                Button {
                    session.keepTalking()
                } label: {
                    Text("Nói tiếp").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    savedCount = 0
                    session.start()
                } label: {
                    Text("Đoạn mới").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .tint(brandRed)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Tin nhắn

    private var header: some View {
        VStack(spacing: 4) {
            Text(session.scenario.partnerEmoji)
                .font(.system(size: 34))
            Text("Bạn là \(session.scenario.userRole.lowercased()), nói chuyện với \(session.scenario.partnerRole.lowercased())")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !session.needsResumeChoice {
                Text(session.handsFree ? "Rảnh tay: AI nói xong là micro tự mở, cứ nói tiếp." : "Bấm micro rồi nói tiếng Trung.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
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
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 6) {
                    ruby(message.line, size: 19)
                    HStack(alignment: .top) {
                        Text(message.line.vi)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        speakButton(message.line, thenListen: session.messages.last?.id == message.id)
                    }
                    // Chỉ gợi ý cho câu mới nhất; gợi ý của lượt cũ không còn hợp cảnh.
                    if session.messages.last?.id == message.id, !message.hints.isEmpty {
                        hintSection(message)
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
                        ruby(message.line, size: 17)
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
                    if !message.flaggedWords.isEmpty || message.retried {
                        pronunciationCard(message)
                    }
                    if let corrected = message.corrected {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nói tự nhiên hơn:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                            HStack(alignment: .top) {
                                ruby(corrected, size: 16)
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

    /// Chấm phát âm: chỗ máy nghe không chắc thường đúng là chỗ đọc chưa tới.
    @ViewBuilder
    private func pronunciationCard(_ message: AIConversationSession.Message) -> some View {
        let drilling = session.drillingID == message.id
        VStack(alignment: .leading, spacing: 6) {
            if message.retried {
                Label("Lần này máy nghe ra rồi 👏", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("Máy nghe chưa chắc: \(message.flaggedWords.map { RubyText.splitPunctuation($0.zh).core }.joined(separator: " "))")
                    .font(.caption)
                    .foregroundStyle(.red)
                HStack(spacing: 8) {
                    Button {
                        session.speakSample(message.line.zh)
                    } label: {
                        Label("Nghe mẫu", systemImage: "speaker.wave.2.fill")
                    }
                    .tint(brandRed)
                    Button {
                        session.drill(message.id)
                    } label: {
                        Label(drilling ? "Đang nghe…" : "Nói lại", systemImage: drilling ? "stop.fill" : "mic.fill")
                    }
                    .tint(drilling ? .red : brandRed)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                if drilling {
                    LiveTranscriptView(text: session.transcript,
                                       placeholder: "Đọc lại câu trên…",
                                       tint: brandRed,
                                       hanziSize: 17)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(message.retried ? Color.green.opacity(0.08) : Color.red.opacity(0.07)))
    }

    /// Bí thì xem vài câu có thể nói tiếp — nghe thử rồi tự nói lại bằng miệng mình.
    @ViewBuilder
    private func hintSection(_ message: AIConversationSession.Message) -> some View {
        if revealedHints.contains(message.id) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bạn có thể nói:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(message.hints.enumerated()), id: \.offset) { _, hint in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top) {
                            ruby(hint, size: 15)
                            Spacer(minLength: 4)
                            speakButton(hint)
                        }
                        if !hint.vi.isEmpty {
                            Text(hint.vi)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
        } else {
            Button {
                revealedHints.insert(message.id)
            } label: {
                Label("Bí quá, gợi ý đi", systemImage: "lightbulb.fill")
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
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

    private func speakButton(_ line: ChatLine, thenListen: Bool = false) -> some View {
        Button {
            session.speak(line, thenListen: thenListen)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(brandRed)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Khu vực trả lời

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if session.isListeningForReply {
                listeningStrip
            }
            if session.isTextMode {
                textRow
            } else {
                micRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.18), value: session.isListeningForReply)
    }

    /// Chữ đang nghe được, hiện ngay để người học biết máy có bắt được giọng mình không.
    private var listeningStrip: some View {
        LiveTranscriptView(text: session.transcript,
                           placeholder: "Đang nghe… hãy nói bằng tiếng Trung",
                           tint: brandRed,
                           hanziSize: 20)
    }

    private var micRow: some View {
        HStack(spacing: 12) {
            Button {
                session.isTextMode = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Gõ chữ thay vì nói")

            Spacer(minLength: 0)
            micButton
            Spacer(minLength: 0)

            Button {
                session.handsFree.toggle()
                if session.handsFree { session.listen() }
            } label: {
                Image(systemName: "infinity")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(session.handsFree ? brandRed : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(session.handsFree ? brandRed.opacity(0.14) : Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(session.handsFree ? "Tắt chế độ rảnh tay" : "Bật chế độ rảnh tay")
        }
    }

    private var micButton: some View {
        Button {
            session.toggleMic()
        } label: {
            ZStack {
                if session.isListeningForReply {
                    Circle()
                        .fill(brandRed.opacity(0.22))
                        .frame(width: 72 + CGFloat(session.micLevel) * 36, height: 72 + CGFloat(session.micLevel) * 36)
                        .animation(.easeOut(duration: 0.12), value: session.micLevel)
                }
                Circle()
                    .fill(session.isThinking ? Color.gray.opacity(0.5) : brandRed)
                    .frame(width: 72, height: 72)
                Image(systemName: session.isListeningForReply ? "stop.fill" : "mic.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 116, height: 80)
        }
        .buttonStyle(.borderless)
        .disabled(session.isThinking)
        .accessibilityLabel(session.isListeningForReply ? "Nói xong" : "Bấm để nói")
    }

    private var textRow: some View {
        HStack(spacing: 8) {
            Button {
                session.isTextMode = false
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(brandRed))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Quay lại nói bằng micro")

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
    }

    private func sendDraft() {
        session.send(text: draft)
        draft = ""
    }
}

struct OpenAISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OpenAISettings.modelKey) private var model = OpenAISettings.defaultModel
    @AppStorage(OpenAISettings.fastModelKey) private var fastModel = OpenAISettings.defaultFastModel
    @AppStorage(OpenAISettings.voiceKey) private var voice = OpenAISettings.defaultVoice
    @AppStorage(OpenAISettings.realtimeModelKey) private var realtimeModel = OpenAISettings.defaultRealtimeModel
    @AppStorage(OpenAISettings.levelKey) private var level = ConversationLevel.beginner.rawValue
    @AppStorage(OpenAISettings.realtimeSpeedKey) private var realtimeSpeed = RealtimeSpeed.slower.rawValue
    @AppStorage("conversationRealtime") private var realtime = false
    @AppStorage(SharedSettings.speechPaceKey, store: SharedSettings.store)
    private var speechPace = SpeechPace.normal.rawValue
    @State private var keyInput = ""
    @State private var hasKey = OpenAISettings.hasAPIKey
    @State private var testResult: String?
    @State private var isTesting = false

    private struct Ping: Decodable { let ok: Bool }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Trình độ", selection: $level) {
                        ForEach(ConversationLevel.allCases) { item in
                            Text(item.label).tag(item.rawValue)
                        }
                    }
                    Picker("Chờ khi bạn ngừng nói", selection: $speechPace) {
                        ForEach(SpeechPace.allCases) { pace in
                            Text(pace.label).tag(pace.rawValue)
                        }
                    }
                    Text(SpeechPace(rawValue: speechPace)?.detail ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Hội thoại")
                }

                Section {
                    Toggle("Nói trực tiếp (thử nghiệm)", isOn: $realtime)
                    if realtime {
                        Picker("Tốc độ AI nói", selection: $realtimeSpeed) {
                            ForEach(RealtimeSpeed.allCases) { speed in
                                Text(speed.label).tag(speed.rawValue)
                            }
                        }
                        LabeledContent("Model nói trực tiếp") {
                            TextField("Model", text: $realtimeModel)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } footer: {
                    Text("Nói trực tiếp: giọng bạn đi thẳng lên model, không qua bước chuyển thành chữ — AI nghe được cả thanh điệu thật và bạn nói chen vào lúc nào cũng được. Đổi lại không có góp ý từng câu và tốn phí cao hơn nhiều. Nên cắm tai nghe để micro không thu lại tiếng loa.")
                }

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
                    LabeledContent("Câu nói") {
                        TextField("Model", text: $fastModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Menu("Chọn nhanh model cho câu nói") {
                        ForEach(OpenAISettings.suggestedModels, id: \.self) { name in
                            Button(name) { fastModel = name }
                        }
                    }
                    LabeledContent("Pinyin & góp ý") {
                        TextField("Model", text: $model)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Menu("Chọn nhanh model cho pinyin & góp ý") {
                        ForEach(OpenAISettings.suggestedModels, id: \.self) { name in
                            Button(name) { model = name }
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Mỗi lượt gọi hai bước: bước đầu chỉ xin câu nói nên nghe được tiếng gần như ngay, bước sau mới điền pinyin, góp ý và gợi ý. Câu nói nên để model nhanh nhất (gpt-5.6-luna); phần pinyin & góp ý có thể để model thông minh hơn (gpt-5.6-terra) mà không làm chậm lúc nói.")
                }

                Section {
                    Picker("Giọng", selection: $voice) {
                        ForEach(OpenAISettings.voices, id: \.self) { name in
                            Text(OpenAISettings.supportsRealtime(voice: name)
                                 ? name.capitalized
                                 : "\(name.capitalized) (chỉ giọng đọc)")
                                .tag(name)
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
                    Text("Màn hình hội thoại dùng giọng \(OpenAISettings.speechModel) của OpenAI (tự nhiên hơn, có tính phí nhỏ). Lỗi mạng sẽ tự chuyển sang giọng Google. Chế độ nói trực tiếp không nhận mọi giọng: chọn giọng “chỉ giọng đọc” thì nó tự dùng \(OpenAISettings.defaultVoice).")
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


// MARK: - Nói trực tiếp

/// Màn hình nói chuyện trực tiếp bằng giọng: không có ô nhập, không có nút gửi,
/// chỉ có nghe và nói — và ngắt lời được như nói chuyện với người.
struct RealtimeConversationView: View {
    @StateObject private var session: RealtimeConversation
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false
    @State private var selectedWord: SelectedWord?
    @State private var showSettings = false

    init(scenario: Scenario) {
        _session = StateObject(wrappedValue: RealtimeConversation(scenario: scenario))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                        ForEach(session.lines) { line in
                            bubble(line)
                                .id(line.id)
                        }
                        if case let .failed(message) = session.phase {
                            errorCard(message)
                                .id("error")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: session.lines) { _ in
                    guard let last = session.lines.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            bottomPanel
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .wordPopup($selectedWord)
        .sheet(isPresented: $showSettings) {
            OpenAISettingsView()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(session.scenario.partnerEmoji)
                .font(.system(size: 40))
            Text("Bạn là \(session.scenario.userRole.lowercased()), nói chuyện với \(session.scenario.partnerRole.lowercased())")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Nói trực tiếp: cứ nói, không cần bấm gì. Muốn chen ngang thì cứ nói đè lên.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func bubble(_ line: RealtimeConversation.Line) -> some View {
        switch line.speaker {
        case .partner:
            HStack(alignment: .top, spacing: 8) {
                Text(session.scenario.partnerEmoji)
                    .font(.system(size: 28))
                content(line, size: 22)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground)))
                Spacer(minLength: 24)
            }
        case .user:
            HStack {
                Spacer(minLength: 40)
                content(line, size: 20)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(brandRed.opacity(0.12)))
            }
        }
    }

    private func content(_ line: RealtimeConversation.Line, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if line.words.isEmpty {
                Text(line.text)
                    .font(.system(size: size))
            } else {
                RubyText(words: line.words, hanziSize: size, showHanViet: showHanViet) {
                    selectedWord = SelectedWord(word: $0)
                }
            }
            if !line.isFinal {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
            HStack {
                Button("Thử lại") { session.start() }
                    .buttonStyle(.bordered)
                Button("Cài đặt OpenAI") { showSettings = true }
                    .buttonStyle(.bordered)
            }
            .tint(brandRed)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
    }

    // MARK: Khu vực điều khiển

    private var statusText: String {
        switch session.phase {
        case .idle: "Bấm để bắt đầu nói chuyện"
        case .connecting: "Đang kết nối…"
        case .listening: "Đang nghe — cứ nói tiếng Trung"
        case .hearing: "Bạn đang nói…"
        case .speaking: "\(session.scenario.partnerRole) đang nói — nói chen vào cũng được"
        case .failed: "Đã dừng"
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if session.phase.isLive || session.phase == .connecting {
                    session.stop()
                } else {
                    session.start()
                }
            } label: {
                ZStack {
                    if session.phase == .hearing {
                        Circle()
                            .fill(brandRed.opacity(0.22))
                            .frame(width: 72 + CGFloat(session.micLevel) * 36, height: 72 + CGFloat(session.micLevel) * 36)
                            .animation(.easeOut(duration: 0.12), value: session.micLevel)
                    }
                    Circle()
                        .fill(session.phase.isLive ? brandRed : Color.gray.opacity(0.6))
                        .frame(width: 72, height: 72)
                    if session.phase == .connecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: session.phase.isLive ? "stop.fill" : "waveform")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 116, height: 80)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(session.phase.isLive ? "Dừng nói chuyện" : "Bắt đầu nói chuyện")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }
}


// MARK: - Chữ đang nghe được

/// Hiện lời vừa nghe được ngay lúc nói: tách theo từ/cụm từ và kèm pinyin,
/// để người học soi được máy nghe ra âm nào chứ không chỉ một dòng chữ Hán liền mạch.
private struct LiveTranscriptView: View {
    let text: String
    let placeholder: String
    let tint: Color
    var hanziSize: CGFloat = 20
    /// Nói dài thì chỉ giữ phần đuôi để dải chữ không đẩy nút micro xuống.
    private let maxWords = 16

    @State private var words: [PinyinWord] = []
    @State private var source = ""

    var body: some View {
        Group {
            if words.isEmpty {
                Text(text.isEmpty ? placeholder : text)
                    .font(.callout)
                    .foregroundStyle(text.isEmpty ? Color.secondary : tint)
                    .lineLimit(2)
            } else {
                RubyText(words: words,
                         hanziSize: hanziSize,
                         hanziWeight: .semibold,
                         pinyinColor: tint.opacity(0.7),
                         hanziColor: tint,
                         showHanViet: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.12), value: words.count)
        .onAppear { rebuild(text) }
        .onChange(of: text) { rebuild($0) }
    }

    private func rebuild(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != source else { return }
        source = trimmed
        guard ChineseText.containsHan(trimmed) else {
            words = []
            return
        }
        let all = ChineseText.words(for: trimmed)
        words = all.count > maxWords ? Array(all.suffix(maxWords)) : all
    }
}

// MARK: - Chuỗi ngày luyện nói

/// Một ô ngày trên lịch: lửa khi đạt, vòng rỗng khi chưa, mờ với ngày chưa tới.
struct StreakDayMark: View {
    let day: StreakStore.DayStatus
    var size: CGFloat = 30
    var showsNumber = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var fill: Color {
        if day.done { return .orange }
        if day.isFuture { return Color(.quaternarySystemFill) }
        return Color(.tertiarySystemFill)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: size, height: size)
                .scaleEffect(pulse ? 1.07 : 1)
            if day.isToday {
                Circle()
                    .strokeBorder(brandRed, lineWidth: 2)
                    .frame(width: size + 5, height: size + 5)
            }
            if showsNumber {
                Text("\(day.number)")
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(day.done ? .white : (day.isFuture ? Color.secondary : Color.primary))
            } else if day.done {
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
            // Ngôi sao nhỏ: hôm đó còn xong cả mục tiêu ngày, không chỉ giữ chuỗi.
            if day.goalMet, !day.isFuture {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.2), radius: 1)
                    .offset(x: size * 0.36, y: -size * 0.36)
            }
        }
        .frame(width: size + 6, height: size + 6)
        .opacity(day.isFuture ? 0.5 : 1)
        .onAppear {
            // Chỉ ô hôm nay mới thở; cả lịch cùng nhấp nháy thì rối mắt.
            guard day.isToday, day.done, !reduceMotion else { return }
            pulse = false
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .onDisappear { pulse = false }
    }
}

/// Xem lại cả chặng đã đi, và đặt thói quen: mục tiêu mỗi ngày, giờ nhắc.
struct StreakDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StreakStore.goalKey, store: SharedSettings.store)
    private var dailyGoal = StreakStore.defaultGoal
    @State private var summary = StreakStore.summary()
    @State private var month = Date()
    @State private var grid = StreakStore.MonthGrid(title: "", cells: [], canGoForward: false)
    @State private var reminderOn = StreakReminder.isOn
    @State private var reminderTime = StreakReminder.time
    @State private var reminderDenied = false
    @State private var iconFollowsMood = MascotIcon.followsMood

    private func shiftMonth(_ value: Int) {
        guard let next = StreakStore.calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = next
        grid = StreakStore.monthGrid(containing: next)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                Section {
                    calendar
                }

                Section {
                    Picker("Mục tiêu mỗi ngày", selection: $dailyGoal) {
                        ForEach(StreakStore.goalChoices, id: \.self) { choice in
                            Text("\(choice) câu").tag(choice)
                        }
                    }
                    Toggle("Nhắc tôi luyện nói", isOn: $reminderOn)
                    if reminderOn {
                        DatePicker("Giờ nhắc", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                    if reminderDenied {
                        Text("Chưa bật được thông báo. Vào Cài đặt → Bàn Phím Trung → Thông báo để cho phép.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Toggle("Icon app đổi theo tâm trạng", isOn: $iconFollowsMood)
                } header: {
                    Text("Thói quen")
                } footer: {
                    Text("Mỗi ngày nói từ \(StreakStore.streakMinimum) câu là chuỗi được tính 🔥; đạt cả mục tiêu ngày thì có thêm ngôi sao ⭐. Lỡ một ngày thì chuỗi vẫn giữ, nghỉ hai ngày liền mới bắt đầu lại — một hôm bận không phải là cớ để bỏ hẳn. Câu bạn nói ở cả Hội thoại AI lẫn Luyện nói đều được tính.\n\nIcon gấu trúc ngoài màn hình chính chỉ đổi được lúc app đang mở, và iOS sẽ báo mỗi lần đổi.")
                }
            }
            .navigationTitle("Chuỗi ngày")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .onAppear {
                summary = StreakStore.summary()
                grid = StreakStore.monthGrid(containing: month)
            }
            .onChange(of: dailyGoal) { _ in
                summary = StreakStore.summary()
                grid = StreakStore.monthGrid(containing: month)
                StreakReminder.reschedule()
            }
            .onChange(of: reminderOn) { on in
                guard on else { return StreakReminder.disable() }
                StreakReminder.enable { granted in
                    reminderDenied = !granted
                    if !granted { reminderOn = false }
                }
            }
            .onChange(of: reminderTime) { time in
                StreakReminder.time = time
                StreakReminder.reschedule()
            }
            .onChange(of: iconFollowsMood) { on in
                MascotIcon.followsMood = on
                MascotIcon.sync()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            MascotBubble(summary: summary)
                .padding(.bottom, 6)
            HStack(spacing: 12) {
                FlameView(size: 50, isLit: summary.streak > 0, showsGlow: true)
                Text("\(summary.streak)")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
            }
            Text(summary.streak == 1 ? "ngày" : "ngày liên tiếp")
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                stat("Tốt nhất", "\(summary.best)")
                Divider().frame(height: 34)
                stat("Tổng số ngày", "\(summary.totalDays)")
                Divider().frame(height: 34)
                stat("Hôm nay", "\(summary.today.sentences) câu")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var calendar: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(grid.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!grid.canGoForward)
            }
            .tint(brandRed)

            HStack(spacing: 0) {
                ForEach(ConversationTopicsView.weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(grid.cells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        StreakDayMark(day: cell, size: 32, showsNumber: true)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MilestoneBadge: Identifiable {
    let days: Int
    var id: Int { days }
}

/// Ăn mừng khi chạm mốc. Ngắn thôi, mừng xong là quay lại nói tiếp.
struct MilestoneView: View {
    let days: Int
    @Environment(\.dismiss) private var dismiss
    @State private var popped = false

    private var message: String {
        switch days {
        case ..<7: "Ba ngày đầu là khó nhất. Qua rồi."
        case ..<14: "Một tuần liền. Đủ để thành nếp."
        case ..<30: "Hai tuần. Giờ nói đã đỡ ngượng miệng hơn rồi đúng không?"
        case ..<50: "Một tháng nói mỗi ngày. Ít người đi được tới đây."
        case ..<100: "Năm mươi ngày. Đây không còn là cố gắng nữa, là thói quen rồi."
        default: "Con số này nói thay bạn rồi."
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                SparkBurst()
                FlameView(size: 66, showsGlow: true)
                    .scaleEffect(popped ? 1 : 0.3)
                    .opacity(popped ? 1 : 0)
            }
            .frame(height: 110)
            Text("\(days) ngày liên tiếp")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                dismiss()
            } label: {
                Text("Nói tiếp thôi")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(brandRed)
            .padding(.horizontal, 28)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { popped = true }
        }
    }
}


/// Ngọn lửa chuỗi ngày: liếm lên nhè nhẹ và không bao giờ đứng im khi chuỗi còn cháy.
/// Co giãn lệch trục (hẹp ngang, cao dọc) và neo ở đáy nên giống lửa hơn là phóng to thu nhỏ.
struct FlameView: View {
    var size: CGFloat = 28
    /// Chuỗi đã đứt thì để lửa tắt: xám và đứng im.
    var isLit = true
    var showsGlow = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flicker = false

    private var flameGradient: LinearGradient {
        LinearGradient(
            colors: isLit
                ? [Color(red: 1, green: 0.80, blue: 0.22), Color(red: 0.97, green: 0.42, blue: 0.08)]
                : [Color.secondary, Color.secondary],
            startPoint: .bottom, endPoint: .top
        )
    }

    var body: some View {
        ZStack {
            if showsGlow, isLit {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.orange.opacity(0.40), Color.orange.opacity(0)],
                        center: .center, startRadius: 0, endRadius: size
                    ))
                    .frame(width: size * 2.6, height: size * 2.6)
                    .scaleEffect(flicker ? 1.10 : 0.88)
                    .opacity(flicker ? 0.95 : 0.5)
            }
            Image(systemName: "flame.fill")
                .font(.system(size: size))
                .foregroundStyle(flameGradient)
                .scaleEffect(x: flicker ? 0.94 : 1.05, y: flicker ? 1.08 : 0.95, anchor: .bottom)
                .rotationEffect(.degrees(flicker ? -2.5 : 2.5), anchor: .bottom)
        }
        .frame(width: size * 1.15, height: size * 1.3)
        .onAppear { startFlicker() }
        .onDisappear { flicker = false }
        .onChange(of: isLit) { _ in startFlicker() }
    }

    private func startFlicker() {
        guard isLit, !reduceMotion else {
            flicker = false
            return
        }
        // Đặt lại trước rồi bật ở nhịp sau: nếu flicker đang là true (animation cũ đã bị huỷ
        // lúc view ẩn đi) thì gán true lần nữa không đổi giá trị, SwiftUI sẽ không chạy gì.
        flicker = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                flicker = true
            }
        }
    }
}

/// Tia lửa bắn ra khi chạm mốc. Chạy một lần rồi tắt.
struct SparkBurst: View {
    var count = 12
    var radius: CGFloat = 95

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.orange : Color.yellow)
                    .frame(width: 7, height: 7)
                    .offset(x: go ? cos(angle) * radius : 0, y: go ? sin(angle) * radius : 0)
                    .scaleEffect(go ? 0.3 : 1)
                    .opacity(go ? 0 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.1)) { go = true }
        }
        .allowsHitTesting(false)
    }
}

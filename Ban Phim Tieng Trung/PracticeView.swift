//
//  PracticeView.swift
//  Ban Phim Tieng Trung
//

import SwiftUI

private let brandRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct PracticeView: View {
    @StateObject private var store = PhraseStore()
    @StateObject private var listener = PracticeListener()
    @AppStorage("hideChinese") private var hideChinese = false
    @AppStorage("autoNextPhrase") private var autoNext = true
    @AppStorage("readVietnameseOnNext") private var readVietnamese = true
    @State private var category: String?
    @State private var search = ""
    @State private var revealed: Set<Int> = []
    /// Nảy một nhịp khi thuộc thêm một câu.
    @State private var countPop = false
    /// Nảy một nhịp khi chuỗi câu đúng dài thêm.
    @State private var comboPop = false
    @State private var comboWork: DispatchWorkItem?
    @State private var lastMastered = 0
    @State private var popWork: DispatchWorkItem?
    @State private var showVoiceSettings = false
    @State private var selectedWord: SelectedWord?
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false
    @AppStorage(SharedSettings.speechPaceKey, store: SharedSettings.store)
    private var speechPace = SpeechPace.normal.rawValue

    /// Câu trong mục đang chọn.
    private var groupPhrases: [Phrase] {
        store.phrases.filter { category == nil || $0.category == category }
    }

    /// Vòng hiện tại: số lần đọc đúng ít nhất trong mục đang chọn.
    private var round: Int { store.round(of: groupPhrases) }

    /// Chỉ hiện những câu đang ở vòng hiện tại, xáo ngẫu nhiên. Đọc đúng một câu là câu đó
    /// lên vòng sau và biến khỏi danh sách; hết cả mục thì cả mục cùng lên vòng mới.
    /// Khi đang tìm kiếm thì hiện mọi câu khớp, vì lúc đó người dùng đang tra chứ không luyện.
    private var visiblePhrases: [Phrase] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.isEmpty else {
            return groupPhrases.filter { phrase in
                phrase.vi.lowercased().contains(query)
                    || phrase.zh.contains(query)
                    || phrase.pinyin.lowercased().contains(query)
            }
        }
        let level = round
        return groupPhrases
            .filter { store.correctCount($0.id) == level }
            .sorted { store.shuffleKey($0.id, round: level) < store.shuffleKey($1.id, round: level) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        progressHeader
                        categoryChips
                            .listRowInsets(EdgeInsets())
                    }

                    let phrases = visiblePhrases
                    if phrases.isEmpty {
                        Section {
                            emptyState
                        }
                    } else {
                        Section {
                            ForEach(phrases) { phrase in
                                row(for: phrase)
                                    .id(phrase.id)
                                    .swipeActions {
                                        if store.isSaved(phrase) {
                                            Button("Xoá", role: .destructive) {
                                                withAnimation { store.deleteSaved(phrase) }
                                            }
                                        }
                                    }
                            }
                        } header: {
                            Text(search.isEmpty
                                 ? "Vòng \(round + 1) · \(phrases.count) câu"
                                 : "\(phrases.count) câu khớp")
                        } footer: {
                            Text("Nhấn 🎙 rồi đọc câu tiếng Trung. Đọc đúng thì câu sẽ được chuyển sang mục “Đã thuộc”\(autoNext ? " và tự ghi âm câu tiếp theo" : "").")
                        }
                    }
                }
                .onAppear {
                    store.reloadSaved()
                    lastMastered = store.masteredCount
                    listener.onCorrect = { phrase in
                        handleCorrect(phrase, proxy: proxy)
                    }
                }
                .onChange(of: listener.combo) { combo in
                    guard combo >= 2 else { return }
                    comboWork?.cancel()
                    // Chạm mốc thì nảy mạnh và lâu hơn một nhịp bình thường.
                    let milestone = listener.comboMilestone > 0
                    withAnimation(.spring(response: 0.3, dampingFraction: milestone ? 0.35 : 0.5)) {
                        comboPop = true
                    }
                    if milestone {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    let work = DispatchWorkItem {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { comboPop = false }
                    }
                    comboWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + (milestone ? 1.1 : 0.6), execute: work)
                }
                .onChange(of: store.masteredCount) { count in
                    defer { lastMastered = count }
                    // "Học lại" làm số tụt xuống — lúc đó đừng nảy lên ăn mừng.
                    guard count > lastMastered else { return }
                    popWork?.cancel()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.4)) { countPop = true }
                    let work = DispatchWorkItem {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { countPop = false }
                    }
                    popWork = work
                    // Để lâu hơn một nhịp: nảy xong rồi tắt ngay thì chưa kịp thấy gì.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
                }
            }
            .searchable(text: $search, prompt: "Tìm câu (Việt, 中文, pinyin)")
            .navigationTitle("Luyện nói")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Section("Hiển thị") {
                            // Lưu dạng "ẩn" để giữ nguyên cài đặt cũ của người dùng, chỉ đổi cách hỏi.
                            Toggle("Luôn hiện chữ Hán và pinyin", isOn: Binding(
                                get: { !hideChinese },
                                set: { hideChinese = !$0 }
                            ))
                            Toggle("Hiện âm Hán Việt", isOn: $showHanViet)
                        }
                        Section("Luyện tập") {
                            Toggle("Tự ghi âm câu tiếp theo", isOn: $autoNext)
                            Toggle("Đọc nghĩa tiếng Việt khi chuyển câu", isOn: $readVietnamese)
                                .disabled(!autoNext)
                        }
                        Picker("Chờ khi bạn ngừng nói", selection: $speechPace) {
                            ForEach(SpeechPace.allCases) { pace in
                                Text(pace.label).tag(pace.rawValue)
                            }
                        }
                        Button {
                            showVoiceSettings = true
                        } label: {
                            Label("Giọng đọc…", systemImage: "person.wave.2")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    NavigationLink {
                        MasteredView(store: store)
                    } label: {
                        Image(systemName: "checkmark.seal")
                    }
                }
            }
            .alert("Không thể ghi âm", isPresented: Binding(
                get: { listener.errorMessage != nil },
                set: { if !$0 { listener.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(listener.errorMessage ?? "")
            }
        }
        .wordPopup($selectedWord)
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsView()
        }
        .onDisappear {
            listener.cancel()
        }
    }

    /// Câu đúng: chờ 1 giây cho người dùng thấy dấu ✓, ẩn câu, đọc nghĩa tiếng Việt câu kế tiếp rồi ghi âm.
    private func handleCorrect(_ phrase: Phrase, proxy: ScrollViewProxy) {
        let phrases = visiblePhrases
        let next = phrases.firstIndex(of: phrase)
            .flatMap { index in phrases.indices.contains(index + 1) ? phrases[index + 1] : nil }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation { store.markCorrect(phrase) }
            listener.clearOutcome(for: phrase)

            guard autoNext, let next, listener.activeID == nil else { return }
            withAnimation { proxy.scrollTo(next.id, anchor: .center) }
            let startRecording = {
                guard listener.activeID == nil, store.correctCount(next.id) == round else { return }
                listener.toggle(next)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard readVietnamese else { return startRecording() }
                listener.speakVietnamese(next) {
                    // Chờ loa tắt hẳn để micro không thu lại tiếng đọc.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: startRecording)
                }
            }
        }
    }

    private func row(for phrase: Phrase) -> some View {
        PhraseRow(
            phrase: phrase,
            showChinese: !hideChinese || revealed.contains(phrase.id) || listener.outcomes[phrase.id] != nil,
            isActive: listener.activeID == phrase.id,
            transcript: listener.transcript,
            level: listener.level,
            liveWords: listener.activeID == phrase.id ? listener.liveWords : [],
            outcome: listener.outcomes[phrase.id],
            readProgress: listener.readingID == phrase.id ? listener.readingProgress : nil,
            onReveal: { revealed.insert(phrase.id) },
            onSpeak: { listener.speak(phrase) },
            onMic: { listener.toggle(phrase) },
            onRead: { listener.readAloud(phrase) },
            showHanViet: showHanViet,
            onTapWord: { selectedWord = SelectedWord(word: $0) }
        )
    }

    private var progressHeader: some View {
        let total = store.phrases.count
        let done = store.masteredCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // Hiệu ứng để ở overlay chứ không bọc ZStack: overlay không chiếm chỗ nên
                // chữ vẫn giữ đường chân, và phần phóng to không bị hàng của List cắt mất.
                Text("\(done)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(countPop ? brandRed : .primary)
                    .scaleEffect(countPop ? 1.35 : 1)
                    .shadow(color: brandRed.opacity(countPop ? 0.4 : 0), radius: 10)
                    .overlay {
                        if countPop {
                            SparkBurst(count: 8, radius: 26)
                        }
                    }
                    .overlay(alignment: .top) {
                        if countPop {
                            Text("+1")
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(.green)
                                .offset(y: -18)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.4).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 8)
                    .zIndex(1)
                Text("/ \(total) câu đã thuộc")
                    .foregroundStyle(.secondary)
                Spacer()
                if round >= 1, search.isEmpty {
                    Text("Vòng \(round + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(brandRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(brandRed.opacity(0.12)))
                }
                if listener.combo >= 2 {
                    comboBadge
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                if total > 0 {
                    Text("\(Int((Double(done) / Double(total) * 100).rounded()))%")
                        .font(.headline)
                        .foregroundStyle(brandRed)
                        .contentTransition(.numericText())
                }
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(brandRed)
                .animation(.easeOut(duration: 0.5), value: done)
        }
        // Chừa sẵn chỗ trên dưới cho lúc con số phóng to và tia lửa bung ra.
        .padding(.vertical, 12)
        .animation(.spring(response: 0.34, dampingFraction: 0.6), value: listener.combo)
    }

    /// Huy hiệu chuỗi câu đúng liên tiếp. Càng dài màu càng "nóng".
    private var comboBadge: some View {
        let combo = listener.combo
        let color: Color = combo >= 20 ? .purple : (combo >= 10 ? .red : (combo >= 5 ? .orange : .yellow))
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.caption2)
            Text("\(combo) câu liền")
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.gradient))
        .scaleEffect(comboPop ? 1.22 : 1)
        .shadow(color: color.opacity(comboPop ? 0.55 : 0), radius: 8)
        .overlay {
            if comboPop, listener.comboMilestone > 0 {
                SparkBurst(count: 10, radius: 34)
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tất cả", count: store.remainingCount(in: nil), selected: category == nil) {
                    category = nil
                }
                ForEach(store.categories, id: \.self) { name in
                    chip(name, count: store.remainingCount(in: name), selected: category == name) {
                        category = name
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? brandRed : Color(.secondarySystemFill)))
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.borderless)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(search.isEmpty ? "🎉" : "🔍")
                .font(.system(size: 44))
            Text(search.isEmpty
                 ? "Xong vòng này rồi! Chọn mục khác, hoặc quay lại đây để vào vòng tiếp theo."
                 : "Không tìm thấy câu phù hợp")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct PhraseRow: View {
    let phrase: Phrase
    let showChinese: Bool
    let isActive: Bool
    let transcript: String
    let level: Float
    /// Câu mẫu đã tô màu theo những gì máy nghe được tới lúc này (chỉ khi đang ghi âm).
    let liveWords: [PinyinWord]
    let outcome: PracticeListener.Outcome?
    /// Đang đọc tiếng Việt dòng này: đã đọc tới ký tự thứ mấy. nil là không đọc.
    let readProgress: Int?
    let onReveal: () -> Void
    let onSpeak: () -> Void
    let onMic: () -> Void
    let onRead: () -> Void
    let showHanViet: Bool
    let onTapWord: (PinyinWord) -> Void

    /// Tiếng Việt, tô đậm phần đã đọc tới.
    private var vietnamese: Text {
        guard let readProgress else {
            return Text(phrase.vi).foregroundColor(.secondary)
        }
        let chars = Array(phrase.vi)
        let cut = min(max(readProgress, 0), chars.count)
        guard cut > 0 else { return Text(phrase.vi).foregroundColor(.secondary) }
        return Text(String(chars[..<cut])).fontWeight(.bold).foregroundColor(.primary)
            + Text(String(chars[cut...])).foregroundColor(.secondary)
    }

    /// Đang đọc: tô theo thời gian thực. Đọc xong mà sai: tô những từ thiếu hoặc khác.
    private var displayWords: [PinyinWord] {
        if isActive, !liveWords.isEmpty { return liveWords }
        guard case let .wrong(heard) = outcome, !heard.isEmpty else { return phrase.words }
        return PhraseMatcher.flagMissedWords(heard: heard, words: phrase.words)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                vietnamese
                    .font(.subheadline)

                if showChinese {
                    RubyText(words: displayWords, hanziSize: 21, showHanViet: showHanViet,
                             showsCorrect: isActive, onTapWord: onTapWord)
                        .animation(.easeOut(duration: 0.18), value: displayWords)
                } else {
                    Button("Hiện chữ Hán", action: onReveal)
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }

                feedback
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Chạm vào dòng để nghe câu tiếng Việt; chạm vào một từ chữ Hán vẫn mở nghĩa như cũ.
            .onTapGesture(perform: onRead)

            VStack(spacing: 10) {
                Button(action: onSpeak) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 15))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.borderless)

                Button(action: onMic) {
                    ZStack {
                        if isActive {
                            RecordingHalo(color: brandRed, size: 46)
                            Circle()
                                .fill(brandRed.opacity(0.25))
                                .frame(width: 44 + CGFloat(level) * 16, height: 44 + CGFloat(level) * 16)
                                .animation(.easeOut(duration: 0.12), value: level)
                        }
                        Circle()
                            .fill(outcome == .correct ? Color.green : brandRed)
                            .frame(width: 44, height: 44)
                        Image(systemName: outcome == .correct ? "checkmark" : (isActive ? "stop.fill" : "mic.fill"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 60, height: 52)
                }
                .buttonStyle(.borderless)
                .disabled(outcome == .correct)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var feedback: some View {
        if isActive {
            Text(transcript.isEmpty ? "Đang nghe… hãy đọc câu này" : transcript)
                .font(.callout)
                .foregroundStyle(brandRed)
        } else if let outcome {
            switch outcome {
            case .correct:
                Label("Chính xác!", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            case .wrong(let heard):
                Label(heard.isEmpty ? "Chưa nghe thấy gì, thử lại nhé" : "Bạn nói: \(heard) — thử lại nhé",
                      systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct MasteredView: View {
    @ObservedObject var store: PhraseStore
    @State private var confirmReset = false

    var body: some View {
        let items = store.phrases.filter { store.mastered.contains($0.id) }
        List {
            if items.isEmpty {
                Text("Chưa có câu nào. Đọc đúng một câu trong mục Luyện nói là câu đó xuất hiện ở đây.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { phrase in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        RubyText(words: phrase.words, hanziSize: 18, hanziWeight: .semibold)
                        Text(phrase.vi).font(.caption)
                    }
                    Spacer(minLength: 8)
                    Text("×\(store.correctCount(phrase.id))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Học lại") {
                        withAnimation { store.unmaster(phrase) }
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle("Đã đọc đúng (\(items.count))")
        .toolbar {
            if !items.isEmpty {
                Button("Học lại tất cả") { confirmReset = true }
            }
        }
        .confirmationDialog("Đưa tất cả \(items.count) câu về danh sách luyện nói?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Học lại tất cả", role: .destructive) {
                withAnimation { store.resetAll() }
            }
        }
    }
}

/// Vòng sóng lan ra khi đang ghi âm, cho biết máy thật sự đang nghe.
struct RecordingHalo: View {
    var color: Color
    var size: CGFloat = 46

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.45), lineWidth: 2)
                    .frame(width: size, height: size)
                    .scaleEffect(animate ? 1.9 : 0.95)
                    .opacity(animate ? 0 : 0.85)
                    .animation(
                        .easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.75),
                        value: animate
                    )
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
        // Cuộn ô ra khỏi màn hình là animation bị huỷ; không đặt lại thì lúc cuộn về
        // trạng thái vẫn là true, SwiftUI không thấy gì đổi và vòng sóng đứng im.
        .onDisappear { animate = false }
        .allowsHitTesting(false)
    }
}

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
    @State private var showVoiceSettings = false
    @State private var selectedWord: SelectedWord?
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false

    private var visiblePhrases: [Phrase] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.phrases.filter { phrase in
            guard !store.mastered.contains(phrase.id) else { return false }
            guard category == nil || phrase.category == category else { return false }
            guard !query.isEmpty else { return true }
            return phrase.vi.lowercased().contains(query)
                || phrase.zh.contains(query)
                || phrase.pinyin.lowercased().contains(query)
        }
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
                            Text("\(phrases.count) câu cần luyện")
                        } footer: {
                            Text("Nhấn 🎙 rồi đọc câu tiếng Trung. Đọc đúng thì câu sẽ được chuyển sang mục “Đã thuộc”\(autoNext ? " và tự ghi âm câu tiếp theo" : "").")
                        }
                    }
                }
                .onAppear {
                    store.reloadSaved()
                    listener.onCorrect = { phrase in
                        handleCorrect(phrase, proxy: proxy)
                    }
                }
            }
            .searchable(text: $search, prompt: "Tìm câu (Việt, 中文, pinyin)")
            .navigationTitle("Luyện nói")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Toggle("Tự ghi âm câu tiếp theo", isOn: $autoNext)
                        Toggle("Đọc nghĩa tiếng Việt khi chuyển câu", isOn: $readVietnamese)
                            .disabled(!autoNext)
                        Button {
                            showVoiceSettings = true
                        } label: {
                            Label("Giọng đọc…", systemImage: "person.wave.2")
                        }
                        Toggle("Ẩn chữ Hán (thử thách)", isOn: $hideChinese)
                        Toggle("Hiện âm Hán Việt", isOn: $showHanViet)
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
        .sheet(item: $selectedWord) { selection in
            WordDetailSheet(word: selection.word)
                .presentationDetents([.height(300)])
        }
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
            withAnimation { store.markMastered(phrase) }
            listener.clearOutcome(for: phrase)

            guard autoNext, let next, listener.activeID == nil else { return }
            withAnimation { proxy.scrollTo(next.id, anchor: .center) }
            let startRecording = {
                guard listener.activeID == nil, !store.mastered.contains(next.id) else { return }
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
            outcome: listener.outcomes[phrase.id],
            onReveal: { revealed.insert(phrase.id) },
            onSpeak: { listener.speak(phrase) },
            onMic: { listener.toggle(phrase) },
            showHanViet: showHanViet,
            onTapWord: { selectedWord = SelectedWord(word: $0) }
        )
    }

    private var progressHeader: some View {
        let total = store.phrases.count
        let done = store.masteredCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(done)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("/ \(total) câu đã thuộc")
                    .foregroundStyle(.secondary)
                Spacer()
                if total > 0 {
                    Text("\(Int((Double(done) / Double(total) * 100).rounded()))%")
                        .font(.headline)
                        .foregroundStyle(brandRed)
                }
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(brandRed)
        }
        .padding(.vertical, 4)
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
            Text(search.isEmpty ? "Bạn đã thuộc hết các câu trong mục này!" : "Không tìm thấy câu phù hợp")
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
    let outcome: PracticeListener.Outcome?
    let onReveal: () -> Void
    let onSpeak: () -> Void
    let onMic: () -> Void
    let showHanViet: Bool
    let onTapWord: (PinyinWord) -> Void

    /// Khi đọc sai: tô cam những từ bị thiếu hoặc đọc khác.
    private var displayWords: [PinyinWord] {
        guard case let .wrong(heard) = outcome, !heard.isEmpty else { return phrase.words }
        return PhraseMatcher.flagMissedWords(heard: heard, words: phrase.words)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(phrase.vi)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showChinese {
                    RubyText(words: displayWords, hanziSize: 21, showHanViet: showHanViet, onTapWord: onTapWord)
                } else {
                    Button("Hiện chữ Hán", action: onReveal)
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }

                feedback
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                Label("Chính xác! Đã thuộc", systemImage: "checkmark.circle.fill")
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
                Text("Chưa có câu nào. Đọc đúng một câu trong mục Luyện nói để đánh dấu đã thuộc.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { phrase in
                VStack(alignment: .leading, spacing: 2) {
                    RubyText(words: phrase.words, hanziSize: 18, hanziWeight: .semibold)
                    Text(phrase.vi).font(.caption)
                }
                .swipeActions {
                    Button("Học lại") {
                        withAnimation { store.unmaster(phrase) }
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle("Đã thuộc (\(items.count))")
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

struct SelectedWord: Identifiable {
    let id = UUID()
    let word: PinyinWord
}

/// Chạm vào một từ: nghe phát âm, xem pinyin, âm Hán Việt và nghĩa.
struct WordDetailSheet: View {
    let word: PinyinWord
    @State private var meaning: String?

    private var text: String {
        RubyText.splitPunctuation(word.zh).core
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(word.py.trimmingCharacters(in: .punctuationCharacters))
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 52, weight: .semibold))
            if let hv = word.hv {
                Text("Hán Việt: \(hv)")
                    .font(.callout)
                    .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.2))
            }
            Text(meaning ?? "Đang tra nghĩa…")
                .font(.body)
                .foregroundStyle(meaning == nil ? .secondary : .primary)
                .multilineTextAlignment(.center)
            Button {
                NaturalSpeaker.chinese.speak(text)
            } label: {
                Label("Nghe lại", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(brandRed)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .task {
            NaturalSpeaker.chinese.speak(text)
            let result = try? await Translator.translate(text, from: "zh-CN", to: "vi")
            meaning = result ?? "Không tra được nghĩa — kiểm tra kết nối mạng."
        }
    }
}

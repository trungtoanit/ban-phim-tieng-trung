//
//  WordPopup.swift
//  Chạm vào chữ Hán: bật một thẻ nhỏ (chữ Hán, pinyin, nghĩa). Nút "Chi tiết" mở trang
//  giải thích do OpenAI soạn: cách đọc gần giống tiếng Việt, từng chữ, ví dụ.
//

import SwiftUI

private let accentRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct SelectedWord: Identifiable {
    let id = UUID()
    let word: PinyinWord
}

extension View {
    /// Hiện thẻ nhỏ khi có từ được chọn; bấm ra ngoài để đóng.
    func wordPopup(_ selection: Binding<SelectedWord?>) -> some View {
        modifier(WordPopupModifier(selection: selection))
    }
}

private struct WordPopupModifier: ViewModifier {
    @Binding var selection: SelectedWord?
    @State private var detail: SelectedWord?

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if selection != nil {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .onTapGesture { selection = nil }
                            .transition(.opacity)
                    }
                    if let current = selection {
                        WordPopupCard(
                            word: current.word,
                            onDetail: {
                                selection = nil
                                detail = current
                            },
                            onClose: { selection = nil }
                        )
                        .id(current.id)
                        .padding(.horizontal, 28)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.7).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: selection?.id)
            }
            .sheet(item: $detail) { selected in
                WordInsightView(word: selected.word)
            }
    }
}

private struct WordPopupCard: View {
    let word: PinyinWord
    let onDetail: () -> Void
    let onClose: () -> Void

    @State private var meaning: String?
    @State private var appeared = false

    private var text: String { RubyText.splitPunctuation(word.zh).core }

    var body: some View {
        VStack(spacing: 8) {
            Text(word.py.trimmingCharacters(in: .punctuationCharacters))
                .font(.title3.weight(.medium))
                .foregroundStyle(accentRed)
            Text(text)
                .font(.system(size: 46, weight: .semibold))
                .scaleEffect(appeared ? 1 : 0.8)
            if let hv = word.hv {
                Text("Hán Việt: \(hv)")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.2))
            }
            Text(meaning ?? "Đang tra nghĩa…")
                .font(.body)
                .foregroundStyle(meaning == nil ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: meaning)

            HStack(spacing: 10) {
                Button {
                    NaturalSpeaker.chinese.speak(text)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.headline)
                        .foregroundStyle(accentRed)
                        .frame(width: 46, height: 44)
                        .background(Circle().fill(accentRed.opacity(0.12)))
                }
                .accessibilityLabel("Nghe lại")

                Button(action: onDetail) {
                    Label("Chi tiết", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(accentRed))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: 330)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .accessibilityLabel("Đóng")
        }
        .task {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { appeared = true }
            NaturalSpeaker.chinese.speak(text)
            // Từ đã xem chi tiết thì lấy luôn nghĩa đã lưu, khỏi tra mạng.
            if let saved = WordInsightCache.get(text) {
                meaning = saved.meaning
                return
            }
            let result = try? await Translator.translate(text, from: "zh-CN", to: "vi")
            meaning = result ?? "Không tra được nghĩa — kiểm tra kết nối mạng."
        }
    }
}

// MARK: - Trang chi tiết (OpenAI)

struct WordInsight: Codable, Equatable {
    struct Syllable: Codable, Equatable {
        let hanzi: String
        let pinyin: String
        let soundsLike: String
        let tip: String
    }

    struct Example: Codable, Equatable {
        let zh: String
        let pinyin: String
        let vi: String
    }

    let hanzi: String
    let pinyin: String
    let hanViet: String
    let meaning: String
    let wordType: String
    let soundsLike: String
    let syllables: [Syllable]
    let examples: [Example]
    let note: String

    static let schema: [String: Any] = {
        let string: [String: Any] = ["type": "string"]
        let syllable: [String: Any] = [
            "type": "object",
            "properties": ["hanzi": string, "pinyin": string, "soundsLike": string, "tip": string],
            "required": ["hanzi", "pinyin", "soundsLike", "tip"],
            "additionalProperties": false,
        ]
        let example: [String: Any] = [
            "type": "object",
            "properties": ["zh": string, "pinyin": string, "vi": string],
            "required": ["zh", "pinyin", "vi"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "hanzi": string, "pinyin": string, "hanViet": string, "meaning": string,
                "wordType": string, "soundsLike": string,
                "syllables": ["type": "array", "items": syllable],
                "examples": ["type": "array", "items": example],
                "note": string,
            ],
            "required": ["hanzi", "pinyin", "hanViet", "meaning", "wordType", "soundsLike", "syllables", "examples", "note"],
            "additionalProperties": false,
        ]
    }()

    static let instructions = """
    You are a Mandarin Chinese teacher for Vietnamese speakers. The user sends one Chinese word or short phrase. Explain it for a beginner. Every explanatory field is written in Vietnamese.
    - "hanzi": the word in Simplified Chinese, exactly as given.
    - "pinyin": Hanyu Pinyin with tone marks, syllables of the word written together.
    - "hanViet": the Sino-Vietnamese reading in lowercase (e.g. "công tác"); empty string if there is none.
    - "meaning": short Vietnamese meaning(s), most common first, separated by "; ".
    - "wordType": part of speech in Vietnamese (danh từ, động từ, tính từ, phó từ, trợ từ, cụm từ…).
    - "soundsLike": how the whole word roughly sounds, written with Vietnamese spelling and tone marks so a Vietnamese speaker can imitate it, e.g. 工作 → "cung chua", 谢谢 → "xiê xiê". It is only an approximation.
    - "syllables": one item per Chinese character: "hanzi", "pinyin" (with tone mark), "soundsLike" (Vietnamese-spelling approximation of that syllable), "tip" (one short Vietnamese sentence on what Vietnamese speakers get wrong here: aspiration, retroflex zh/ch/sh/r, ü, -n vs -ng, or the tone contour).
    - "examples": exactly three short, natural example sentences in Simplified Chinese using the word, suited to a beginner, each with "pinyin" (tone marks) and "vi" (Vietnamese translation).
    - "note": one short Vietnamese note on usage or a common confusion; empty string if nothing useful.
    Phonetic facts to keep tips accurate: b, d, g, j, zh, z are unaspirated; p, t, k, q, ch, c are aspirated; f sounds like Vietnamese "ph"; h is close to Vietnamese "kh"; x is like Vietnamese "x" with the tongue tip down; zh, ch, sh, r curl the tongue tip up; z, c, s keep it flat; ü has no Vietnamese equivalent (tongue as "i", lips rounded); -ng endings like Vietnamese "-ng"/"-nh", -n like "-n". Only mention aspiration for initials that actually have it.
    """
}

/// Kết quả AI đã soạn, lưu thành file trên máy: mở lại cùng từ là hiện ngay, không gọi OpenAI nữa.
enum WordInsightCache {
    private struct Entry: Codable {
        let insight: WordInsight
        var savedAt: Date
    }

    private static let limit = 1000
    private static var memory: [String: Entry]?

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("word-insights.json")
    }

    private static func load() -> [String: Entry] {
        if let memory { return memory }
        var map: [String: Entry] = [:]
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            map = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        }
        // Bản trước lưu trong UserDefaults: chuyển sang file một lần rồi xoá.
        if let old = UserDefaults.standard.dictionary(forKey: "wordInsightCache") as? [String: Data] {
            for (text, data) in old where map[text] == nil {
                if let insight = try? JSONDecoder().decode(WordInsight.self, from: data) {
                    map[text] = Entry(insight: insight, savedAt: Date())
                }
            }
            UserDefaults.standard.removeObject(forKey: "wordInsightCache")
            save(map)
        }
        memory = map
        return map
    }

    private static func save(_ map: [String: Entry]) {
        memory = map
        guard let fileURL, let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func get(_ text: String) -> WordInsight? {
        load()[text]?.insight
    }

    static func set(_ insight: WordInsight, for text: String) {
        var map = load()
        map[text] = Entry(insight: insight, savedAt: Date())
        if map.count > limit {
            // Bỏ những từ tra lâu nhất.
            for key in map.sorted(by: { $0.value.savedAt < $1.value.savedAt }).prefix(map.count - limit).map(\.key) {
                map.removeValue(forKey: key)
            }
        }
        save(map)
    }
}

struct WordInsightView: View {
    let word: PinyinWord

    @Environment(\.dismiss) private var dismiss
    @State private var insight: WordInsight?
    /// Đang hiện bản đã lưu trên máy (không gọi OpenAI lần này).
    @State private var fromCache = false
    @State private var forceRefresh = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var loadID = UUID()
    @StateObject private var mistakes = MistakeStore()

    init(word: PinyinWord) {
        self.word = word
        // Đọc bản đã lưu ngay lúc dựng màn hình, để không nháy vòng "đang tải" dù chỉ một nhịp.
        let saved = WordInsightCache.get(RubyText.splitPunctuation(word.zh).core)
        _insight = State(initialValue: saved)
        _fromCache = State(initialValue: saved != nil)
    }

    private var text: String { RubyText.splitPunctuation(word.zh).core }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let insight {
                        content(insight)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    } else {
                        loadingCard
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: insight)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chi tiết từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
                if insight != nil, OpenAISettings.hasAPIKey {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            forceRefresh = true
                            insight = nil
                            loadID = UUID()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Nhờ AI soạn lại")
                    }
                }
            }
            .navigationDestination(for: SoundGuide.self) { guide in
                SoundDetailView(guide: guide, log: mistakes)
            }
            .navigationDestination(for: MistakeDrill.self) { drill in
                PronunciationDrillView(drill: drill)
            }
            .task(id: loadID) { await load() }
            .sheet(isPresented: $showSettings, onDismiss: { loadID = UUID() }) {
                OpenAISettingsView()
            }
        }
    }

    private func load() async {
        errorMessage = nil
        if !forceRefresh, let cached = WordInsightCache.get(text) {
            insight = cached
            fromCache = true
            return
        }
        forceRefresh = false
        guard OpenAISettings.hasAPIKey else {
            errorMessage = "Cần khoá OpenAI để soạn phần giải thích chi tiết."
            return
        }
        do {
            let result = try await OpenAIClient.respond(
                instructions: WordInsight.instructions,
                messages: [.init(role: .user, content: text)],
                schemaName: "word_insight", schema: WordInsight.schema, as: WordInsight.self
            )
            WordInsightCache.set(result, for: text)
            insight = result
            fromCache = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(insight?.pinyin ?? word.py.trimmingCharacters(in: .punctuationCharacters))
                .font(.title2.weight(.medium))
                .foregroundStyle(accentRed)
            Text(text)
                .font(.system(size: 60, weight: .semibold))
            if let hv = insight.map(\.hanViet).flatMap({ $0.isEmpty ? nil : $0 }) ?? word.hv {
                Text("Hán Việt: \(hv)")
                    .font(.callout)
                    .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.2))
            }
            Button {
                NaturalSpeaker.chinese.speak(text, preferOpenAI: true)
            } label: {
                Label("Nghe", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accentRed.opacity(0.12)))
                    .foregroundStyle(accentRed)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            if fromCache {
                Label("Đã lưu trên máy", systemImage: "checkmark.icloud")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func content(_ insight: WordInsight) -> some View {
        card("Nghĩa tiếng Việt", icon: "character.book.closed") {
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.meaning)
                    .font(.title3.weight(.semibold))
                if !insight.wordType.isEmpty {
                    Text(insight.wordType)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }

        card("Cách phát âm gần giống tiếng Việt", icon: "waveform") {
            VStack(alignment: .leading, spacing: 12) {
                Text("≈ \(insight.soundsLike)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(accentRed)
                ForEach(Array(insight.syllables.enumerated()), id: \.offset) { _, syllable in
                    syllableRow(syllable)
                }
                Text("Chỉ là cách đọc gần đúng — nghe giọng mẫu để bắt đúng thanh điệu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !insight.examples.isEmpty {
            card("Ví dụ", icon: "text.quote") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(insight.examples.enumerated()), id: \.offset) { index, example in
                        if index > 0 { Divider() }
                        Button {
                            NaturalSpeaker.chinese.speak(example.zh, preferOpenAI: true)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    RubyText(words: ChineseText.words(for: example.zh), hanziSize: 22)
                                    Text(example.vi)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(accentRed)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        if !insight.note.isEmpty {
            card("Lưu ý", icon: "lightbulb") {
                Text(insight.note)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func syllableRow(_ syllable: WordInsight.Syllable) -> some View {
        let parsed = PinyinSyllable(syllable.pinyin)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(syllable.hanzi)
                    .font(.system(size: 28, weight: .semibold))
                Text(syllable.pinyin)
                    .font(.headline)
                    .foregroundStyle(accentRed)
                Text("≈ \(syllable.soundsLike)")
                    .font(.headline)
                Spacer()
                Button {
                    NaturalSpeaker.chinese.speak(syllable.hanzi)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(accentRed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nghe \(syllable.hanzi)")
            }
            if !syllable.tip.isEmpty {
                Text(syllable.tip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Chạm để mở bài học đúng thanh mẫu, vận mẫu, thanh điệu của chữ này.
            if let parsed {
                HStack(spacing: 6) {
                    soundChip(.initial, key: parsed.initial)
                    soundChip(.final, key: parsed.final)
                    soundChip(.tone, key: String(parsed.tone))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGroupedBackground)))
    }

    @ViewBuilder
    private func soundChip(_ kind: SoundGuide.Kind, key: String) -> some View {
        if let guide = PinyinGuide.guide(kind, key: key) {
            NavigationLink(value: guide) {
                Text(kind == .tone ? guide.symbol : "\(kind.label) \(guide.key.isEmpty ? "∅" : guide.key)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accentRed.opacity(0.1)))
                    .foregroundStyle(accentRed)
            }
            .buttonStyle(.plain)
        }
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Đang nhờ AI soạn cách đọc và ví dụ…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
            HStack {
                if !OpenAISettings.hasAPIKey {
                    Button("Nhập khoá OpenAI") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Thử lại") { loadID = UUID() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .tint(accentRed)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }
}

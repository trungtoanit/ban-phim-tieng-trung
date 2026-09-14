//
//  ConversationModel.swift
//  Ban Phim Tieng Trung
//
//  Hội thoại theo chủ đề với AI (OpenAI): AI nhập vai, người học nói tiếng Trung,
//  AI trả lời kèm pinyin từng từ, góp ý và gợi ý câu tiếp theo.
//

import UIKit

struct Scenario: Codable, Identifiable, Hashable {
    let id: Int
    let topic: String
    let title: String
    let partnerRole: String
    let partnerEmoji: String
    let userRole: String

    static func custom(_ description: String) -> Scenario {
        Scenario(id: -abs(description.hashValue % 1_000_000) - 1, topic: "Tự chọn", title: description,
                 partnerRole: "Người bạn Trung Quốc", partnerEmoji: "🧑", userRole: "Người học tiếng Trung")
    }
}

enum ConversationLevel: String, CaseIterable, Identifiable {
    case beginner, intermediate, advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beginner: "Mới bắt đầu (HSK 1–2)"
        case .intermediate: "Trung cấp (HSK 3–4)"
        case .advanced: "Nâng cao (HSK 5–6)"
        }
    }

    var promptDescription: String {
        switch self {
        case .beginner: "beginner (HSK 1–2): very simple, common words, short sentences"
        case .intermediate: "intermediate (HSK 3–4): everyday vocabulary, natural sentences"
        case .advanced: "advanced (HSK 5–6): rich natural expressions and idioms where fitting"
        }
    }
}

final class ScenarioStore: ObservableObject {
    private static let customKey = "customScenarios"

    let scenarios: [Scenario]
    let topics: [String]
    /// Tình huống người dùng tự tạo, lưu trên máy (mới nhất ở đầu).
    @Published private(set) var customTitles: [String]

    init() {
        if let url = Bundle.main.url(forResource: "scenarios", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Scenario].self, from: data) {
            scenarios = list
        } else {
            scenarios = []
        }
        var seen = Set<String>()
        topics = scenarios.compactMap { seen.insert($0.topic).inserted ? $0.topic : nil }
        customTitles = UserDefaults.standard.stringArray(forKey: Self.customKey) ?? []
    }

    func scenarios(in topic: String) -> [Scenario] {
        scenarios.filter { $0.topic == topic }
    }

    func addCustom(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customTitles.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        customTitles.insert(trimmed, at: 0)
        customTitles = Array(customTitles.prefix(50))
        UserDefaults.standard.set(customTitles, forKey: Self.customKey)
    }

    func removeCustom(at offsets: IndexSet) {
        customTitles.remove(atOffsets: offsets)
        UserDefaults.standard.set(customTitles, forKey: Self.customKey)
    }
}

/// Một câu tiếng Trung hiển thị kèm pinyin từng từ.
struct ChatLine: Equatable {
    let zh: String
    let vi: String
    var words: [PinyinWord]
}

// MARK: - Định dạng phản hồi của AI

private struct AIWord: Decodable {
    let zh: String
    let py: String
}

private struct AILine: Decodable {
    let zh: String
    let vi: String
    let words: [AIWord]

    /// Dùng pinyin AI tách sẵn nếu khớp đúng câu, không thì tự chuyển.
    var chatLine: ChatLine {
        let text = zh.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = words.map(\.zh).joined().filter { !$0.isWhitespace }
        let aiWordsMatch = !words.isEmpty && joined == text.filter { !$0.isWhitespace }
            && words.allSatisfy { !$0.py.trimmingCharacters(in: .whitespaces).isEmpty || !ChineseText.containsHan($0.zh) }
        let pinyinWords = aiWordsMatch
            ? words.map { PinyinWord(zh: $0.zh, py: $0.py, hv: ChineseText.hanViet(forWord: $0.zh, pinyin: $0.py)) }
            : ChineseText.words(for: text)
        return ChatLine(zh: text, vi: vi, words: pinyinWords)
    }
}

private struct AITurn: Decodable {
    let learner: AILine
    let reply: AILine
    let feedback: String
    let corrected: AILine

    static let schema: [String: Any] = {
        let word: [String: Any] = [
            "type": "object",
            "properties": ["zh": ["type": "string"], "py": ["type": "string"]],
            "required": ["zh", "py"],
            "additionalProperties": false,
        ]
        let line: [String: Any] = [
            "type": "object",
            "properties": [
                "zh": ["type": "string"],
                "vi": ["type": "string"],
                "words": ["type": "array", "items": word],
            ],
            "required": ["zh", "vi", "words"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "learner": line,
                "reply": line,
                "feedback": ["type": "string"],
                "corrected": line,
            ],
            "required": ["learner", "reply", "feedback", "corrected"],
            "additionalProperties": false,
        ]
    }()
}

// MARK: - Phiên hội thoại

final class AIConversationSession: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Speaker { case partner, user }
        let id = UUID()
        let speaker: Speaker
        var line: ChatLine
        /// Góp ý của AI cho câu người dùng vừa nói.
        var feedback: String?
        var corrected: ChatLine?
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isThinking = false
    @Published private(set) var canRetry = false
    @Published var errorMessage: String?

    let scenario: Scenario
    private var history: [OpenAIClient.Message] = []
    private var requestToken: UUID?

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    var hasStarted: Bool { !messages.isEmpty || isThinking }

    func start() {
        stop()
        messages = []
        history = []
        errorMessage = nil
        requestReply()
    }

    func stop() {
        requestToken = nil
        isThinking = false
        NaturalSpeaker.all.forEach { $0.stop() }
    }

    /// Gửi câu người dùng nhập (gõ, hoặc nói bằng bàn phím Bàn Phím Trung), tiếng Trung hoặc tiếng Việt.
    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        let line = ChineseText.containsHan(trimmed)
            ? ChatLine(zh: trimmed, vi: "", words: ChineseText.words(for: trimmed))
            : ChatLine(zh: trimmed, vi: "", words: [PinyinWord(zh: trimmed, py: "")])
        appendUser(line, spoken: trimmed)
    }

    func speak(_ line: ChatLine) {
        NaturalSpeaker.chinese.speak(line.zh, preferOpenAI: true)
    }

    func retry() {
        guard canRetry else { return }
        requestReply()
    }

    private func appendUser(_ line: ChatLine, spoken: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        messages.append(Message(speaker: .user, line: line))
        history.append(.init(role: .user, content: spoken))
        requestReply()
    }

    private func requestReply() {
        let token = UUID()
        requestToken = token
        isThinking = true
        canRetry = false
        errorMessage = nil

        let input: [OpenAIClient.Message] = history.isEmpty
            ? [.init(role: .user, content: "(Bắt đầu cuộc trò chuyện: hãy nói câu mở đầu trong vai của bạn.)")]
            : history
        let instructions = prompt()

        Task {
            do {
                let turn = try await OpenAIClient.respond(
                    instructions: instructions, messages: input,
                    schemaName: "conversation_turn", schema: AITurn.schema, as: AITurn.self
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestToken == token else { return }
                    self.apply(turn)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestToken == token else { return }
                    self.isThinking = false
                    self.canRetry = true
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func apply(_ turn: AITurn) {
        isThinking = false

        if let index = messages.lastIndex(where: { $0.speaker == .user }), messages.last?.speaker == .user {
            // Pinyin và nghĩa câu người dùng do AI tách (chính xác hơn bộ chuyển trên máy).
            let learner = turn.learner.chatLine
            if !learner.zh.isEmpty, learner.zh.filter(\.isLetter) == messages[index].line.zh.filter(\.isLetter) {
                messages[index].line = learner
            }
            let feedback = turn.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
            messages[index].feedback = feedback.isEmpty ? nil : feedback
            if !turn.corrected.zh.trimmingCharacters(in: .whitespaces).isEmpty,
               turn.corrected.zh.filter(\.isLetter) != messages[index].line.zh.filter(\.isLetter) {
                messages[index].corrected = turn.corrected.chatLine
            }
        }

        let reply = turn.reply.chatLine
        messages.append(Message(speaker: .partner, line: reply))
        history.append(.init(role: .assistant, content: reply.zh))
        NaturalSpeaker.chinese.speak(reply.zh, preferOpenAI: true)
    }

    private func prompt() -> String {
        let level = ConversationLevel(rawValue: UserDefaults.standard.string(forKey: OpenAISettings.levelKey) ?? "") ?? .beginner
        return """
        You are role-playing a spoken conversation to help a Vietnamese learner practise Mandarin Chinese.
        Scenario: "\(scenario.title)" (topic: \(scenario.topic)). You play: \(scenario.partnerRole). The learner plays: \(scenario.userRole).
        Learner level: \(level.promptDescription).

        Rules:
        - Stay in character. Speak natural, colloquial Mainland Mandarin in Simplified Chinese, the way a real person talks. Keep each reply short (1–2 sentences, at most 30 Chinese characters) and usually end with a question or prompt so the learner has something to answer. Move the scenario forward naturally.
        - Never use Arabic numerals or Latin letters in Chinese text; write numbers in Chinese characters.
        - The learner's messages come from speech recognition, so they may contain wrong homophones or missing words. Infer the most likely intended meaning and respond to that. If the learner writes in Vietnamese, respond in character in Chinese.
        - "learner": the learner's LAST message copied exactly as written (zh), with its Vietnamese translation (vi) and words. For the opening line, or if the last message contains no Chinese, set zh and vi to empty strings and words to an empty array.
        - "reply": your next line; "vi": its natural Vietnamese translation.
        - "feedback": one short, encouraging sentence in Vietnamese about the learner's LAST message (grammar, word choice, or a likely pronunciation/tone problem if recognition produced an odd word). Use an empty string for the opening line or when the message was already natural and correct.
        - "corrected": if the learner's last message was wrong, unnatural, or in Vietnamese, give the natural Chinese sentence they should say (with Vietnamese translation and words). Otherwise set zh and vi to empty strings and words to an empty array.
        - "words" (for every Chinese line): split the Chinese text into words in order. Each item has the exact characters ("zh", with punctuation attached to the preceding word) and Hanyu Pinyin with tone marks ("py": syllables of one word written together, tone sandhi applied to 不 and 一, neutral tones unmarked). Concatenating all "zh" values must reproduce the Chinese text exactly.
        """
    }
}

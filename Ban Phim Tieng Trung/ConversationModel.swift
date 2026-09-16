//
//  ConversationModel.swift
//  Ban Phim Tieng Trung
//
//  Hội thoại theo chủ đề với AI (OpenAI): AI nhập vai, người học nói tiếng Trung,
//  AI trả lời kèm pinyin từng từ, góp ý và gợi ý câu tiếp theo.
//

import AVFoundation
import Combine
import UIKit
import UserNotifications

struct Scenario: Codable, Identifiable, Hashable {
    let id: Int
    let topic: String
    let title: String
    let partnerRole: String
    let partnerEmoji: String
    let userRole: String

    static func custom(_ description: String) -> Scenario {
        // hashValue của String đổi theo từng lần chạy app, nên đoạn hội thoại đã lưu sẽ
        // không bao giờ tìm lại được. Dùng FNV-1a để id gắn chặt với nội dung tình huống.
        var hash: UInt32 = 2_166_136_261
        for byte in Array(description.utf8) {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Scenario(id: -Int(hash % 1_000_000) - 1, topic: "Tự chọn", title: description,
                        partnerRole: "Người bạn Trung Quốc", partnerEmoji: "🧑", userRole: "Người học tiếng Trung")
    }
}

enum ConversationSettings {
    static let handsFreeKey = "conversationHandsFree"

    /// Rảnh tay: sau khi AI đọc xong, micro tự mở để người học nói tiếp. Mặc định bật.
    static var handsFree: Bool {
        get { UserDefaults.standard.object(forKey: handsFreeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: handsFreeKey) }
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

/// Emoji và một dòng chú thích cho tình huống người dùng tự gõ.
struct CustomTopicInfo: Codable, Equatable {
    let emoji: String
    let caption: String

    static let placeholder = CustomTopicInfo(emoji: "💬", caption: "Tình huống bạn tự tạo")

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "emoji": ["type": "string"],
            "caption": ["type": "string"],
        ],
        "required": ["emoji", "caption"],
        "additionalProperties": false,
    ]

    static let instructions = """
    The user is a Vietnamese learner of Chinese. They typed a topic or situation (in Vietnamese) they want to practise in a spoken conversation with a Chinese partner. Label it for a list:
    - "emoji": exactly ONE emoji that best pictures the topic (e.g. coffee topic → ☕, children → 👶, weather → ⛅). Not a generic face unless the topic is about a person.
    - "caption": one short Vietnamese line, at most 8 words, saying what the learner will talk about and with whom, e.g. "Kể chuyện con cái với bạn Trung Quốc". No trailing period, no quotes, no Chinese characters.
    """

    /// Model đôi khi trả kèm chữ hay nhiều emoji: chỉ giữ ký tự emoji đầu tiên.
    var cleaned: CustomTopicInfo? {
        guard let first = emoji.first(where: { character in
            character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }
        }) else { return nil }
        let text = caption
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。\"“”"))
        guard !text.isEmpty, !ChineseText.containsHan(text) else { return nil }
        return CustomTopicInfo(emoji: String(first), caption: text)
    }
}

final class ScenarioStore: ObservableObject {
    static let customKey = "customScenarios"
    private static let customInfoKey = "customScenarioInfo"
    /// Mỗi tình huống cần nói đủ bấy nhiêu câu mới tính là xong.
    static let targetSentences = 50

    /// Tình huống người dùng tự tạo, lưu trên máy (mới nhất ở đầu).
    @Published private(set) var customTitles: [String]
    /// Emoji và chú thích AI đặt cho từng tình huống tự tạo, theo tên tình huống.
    @Published private(set) var customInfo: [String: CustomTopicInfo]
    /// Những tình huống đang chờ AI đặt nhãn, để khỏi gửi trùng.
    private var describing = Set<String>()
    /// Tình huống tự tạo vừa đủ câu và đã được xoá, để màn hình báo cho người học.
    @Published var completedCustom: [(title: String, sentences: Int)] = []
    /// Danh sách đang hiện (không có màn hội thoại nào đè lên). Chỉ lúc này mới xoá
    /// tình huống đã xong, để không rút mất tình huống người học vẫn đang nói dở.
    var isListVisible = false {
        didSet { if isListVisible { removeCompletedCustom() } }
    }
    /// Thành tích từng tình huống: id tình huống → số câu đã nói và thời gian.
    @Published private(set) var stats: [Int: ConversationArchive.Stat] = [:]
    /// Tình huống tự tạo vừa nói gần đây nhất.
    var recentID: Int? {
        // Kho lưu có thể còn đoạn của các tình huống có sẵn trước đây; chúng không còn trong danh sách.
        let ids = Set(customTitles.map { Scenario.custom($0).id })
        return stats.filter { ids.contains($0.key) }.max { $0.value.updatedAt < $1.value.updatedAt }?.key
    }

    private var archiveObserver: NSObjectProtocol?

    init() {
        customTitles = UserDefaults.standard.stringArray(forKey: Self.customKey) ?? []
        customInfo = UserDefaults.standard.data(forKey: Self.customInfoKey)
            .flatMap { try? JSONDecoder().decode([String: CustomTopicInfo].self, from: $0) } ?? [:]
        stats = ConversationArchive.stats()

        // onDisappear của màn hội thoại có thể chạy sau onAppear của danh sách,
        // nên đừng chỉ trông vào onAppear để nạp lại.
        archiveObserver = NotificationCenter.default.addObserver(
            forName: .conversationArchiveChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshStats()
            // Màn hội thoại lưu lần cuối lúc đóng, có khi sau khi danh sách đã hiện lại.
            self?.removeCompletedCustom()
        }
    }

    deinit {
        if let archiveObserver {
            NotificationCenter.default.removeObserver(archiveObserver)
        }
    }

    func refreshStats() {
        stats = ConversationArchive.stats()
    }

    func addCustom(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customTitles.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        customTitles.insert(trimmed, at: 0)
        customTitles = Array(customTitles.prefix(50))
        UserDefaults.standard.set(customTitles, forKey: Self.customKey)
        describe(trimmed)
    }

    func isCompleted(_ id: Int) -> Bool {
        (stats[id]?.sentences ?? 0) >= Self.targetSentences
    }

    /// Thoát ra mà tình huống tự tạo đã đủ câu thì xoá hẳn, kể cả đoạn hội thoại đã lưu —
    /// để lại thì gõ lại đúng tên đó sẽ bị xoá ngay lần thoát sau.
    func removeCompletedCustom() {
        guard isListVisible else { return }
        let done = customTitles.compactMap { title -> (title: String, sentences: Int)? in
            let id = Scenario.custom(title).id
            return isCompleted(id) ? (title, stats[id]?.sentences ?? 0) : nil
        }
        guard !done.isEmpty else { return }
        let titles = Set(done.map(\.title))
        customTitles.removeAll { titles.contains($0) }
        UserDefaults.standard.set(customTitles, forKey: Self.customKey)
        saveCustomInfo()
        ConversationArchive.removeAll(for: done.map { Scenario.custom($0.title) })
        completedCustom = done
    }

    func info(forCustom title: String) -> CustomTopicInfo {
        customInfo[title] ?? .placeholder
    }

    /// Đặt nhãn bù cho tình huống tạo từ trước, hoặc lần trước mất mạng.
    func describeMissingCustom() {
        customTitles.filter { customInfo[$0] == nil }.forEach(describe)
    }

    private func describe(_ title: String) {
        guard customInfo[title] == nil, OpenAISettings.hasAPIKey, describing.insert(title).inserted else { return }
        Task {
            let info = try? await OpenAIClient.respond(
                instructions: CustomTopicInfo.instructions,
                messages: [.init(role: .user, content: title)],
                schemaName: "topic_label", schema: CustomTopicInfo.schema, as: CustomTopicInfo.self,
                model: OpenAISettings.fastModel
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.describing.remove(title)
                // Không được thì để nguyên, lần mở danh sách sau thử lại.
                guard let info = info?.cleaned, self.customTitles.contains(title) else { return }
                self.customInfo[title] = info
                self.saveCustomInfo()
            }
        }
    }

    private func saveCustomInfo() {
        // Chỉ giữ nhãn của tình huống còn trong danh sách.
        customInfo = customInfo.filter { customTitles.contains($0.key) }
        UserDefaults.standard.set(try? JSONEncoder().encode(customInfo), forKey: Self.customInfoKey)
    }

    func removeCustom(at offsets: IndexSet) {
        for title in offsets.map({ customTitles[$0] }) {
            ConversationArchive.removeAll(for: .custom(title))
        }
        customTitles.remove(atOffsets: offsets)
        UserDefaults.standard.set(customTitles, forKey: Self.customKey)
        saveCustomInfo()
        refreshStats()
    }
}

/// Một câu tiếng Trung hiển thị kèm pinyin từng từ.
struct ChatLine: Codable, Equatable {
    let zh: String
    /// Vá được sau khi bước 2 trả về bản dịch đúng câu.
    var vi: String
    var words: [PinyinWord]
}

/// Chấm phát âm dựa trên độ chắc chắn của bộ nhận dạng: chỗ máy nghe không ra
/// thường đúng là chỗ người học đọc sai âm hoặc sai thanh điệu.
enum PronunciationScore {
    /// Dưới ngưỡng này coi như máy nghe không chắc.
    static let threshold: Float = 0.45
    /// Quá tỉ lệ này thì nhiều khả năng do ồn hoặc micro, không phải lỗi phát âm — bỏ chấm
    /// để người học không thấy cả câu đỏ rực rồi nản.
    static let maxFlaggedRatio = 0.6

    /// Gắn cờ những từ máy nghe không chắc. Trả về nil khi không chấm được.
    static func flag(words: [PinyinWord], segments: [SpeechCapture.HeardSegment]) -> [PinyinWord]? {
        var chars: [(char: Character, score: Float)] = []
        for segment in segments {
            for char in segment.text where char.isLetter {
                chars.append((char, segment.confidence))
            }
        }
        guard chars.contains(where: { $0.score > 0 }) else { return nil }

        var flagged = words
        var cursor = 0
        var scored = 0
        var low = 0
        for (position, word) in words.enumerated() {
            var worst: Float?
            for char in word.zh where char.isLetter {
                // Lệch một chữ là cách tách không khớp lời nghe được: bỏ chấm cho chắc.
                guard cursor < chars.count, chars[cursor].char == char else { return nil }
                worst = min(worst ?? chars[cursor].score, chars[cursor].score)
                cursor += 1
            }
            guard let worst else { continue }
            scored += 1
            let isLow = worst < threshold
            if isLow { low += 1 }
            flagged[position].flagged = isLow
        }
        guard scored > 0, cursor == chars.count else { return nil }
        guard Double(low) / Double(scored) <= maxFlaggedRatio else { return nil }
        return flagged
    }
}

// MARK: - Định dạng phản hồi của AI

private struct AIWord: Decodable {
    let zh: String
    let py: String

    static let schema: [String: Any] = [
        "type": "object",
        "properties": ["zh": ["type": "string"], "py": ["type": "string"]],
        "required": ["zh", "py"],
        "additionalProperties": false,
    ]
}

/// AI thỉnh thoảng trả lại nguyên câu tiếng Trung ở ô "vi". Thà để trống rồi dịch bù
/// còn hơn hiện chữ Hán ở chỗ đáng lẽ là nghĩa tiếng Việt.
private func vietnameseOnly(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return ChineseText.containsHan(trimmed) ? "" : trimmed
}

private struct AILine: Decodable {
    let zh: String
    let vi: String
    let words: [AIWord]

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "zh": ["type": "string"],
            "vi": ["type": "string"],
            "words": ["type": "array", "items": AIWord.schema],
        ],
        "required": ["zh", "vi", "words"],
        "additionalProperties": false,
    ]

    /// Dùng pinyin AI tách sẵn nếu khớp đúng câu, không thì tự chuyển.
    var chatLine: ChatLine {
        let text = zh.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = words.map(\.zh).joined().filter { !$0.isWhitespace }
        let aiWordsMatch = !words.isEmpty && joined == text.filter { !$0.isWhitespace }
            && words.allSatisfy { !$0.py.trimmingCharacters(in: .whitespaces).isEmpty || !ChineseText.containsHan($0.zh) }
        let pinyinWords = aiWordsMatch
            ? words.map { PinyinWord(zh: $0.zh, py: $0.py, hv: ChineseText.hanViet(forWord: $0.zh, pinyin: $0.py)) }
            : ChineseText.words(for: text)
        return ChatLine(zh: text, vi: vietnameseOnly(vi), words: pinyinWords)
    }
}

/// Bước 1 — chỉ câu trả lời, để phát tiếng sớm nhất có thể.
private struct AIReply: Decodable {
    let zh: String
    let vi: String

    static let schema: [String: Any] = [
        "type": "object",
        "properties": ["zh": ["type": "string"], "vi": ["type": "string"]],
        "required": ["zh", "vi"],
        "additionalProperties": false,
    ]
}

/// Bước 2 — pinyin, góp ý, câu sửa, gợi ý: điền vào trong lúc loa đang đọc câu trả lời.
private struct AIDetail: Decodable {
    let replyWords: [AIWord]
    /// Bản dịch câu vừa nói, dùng để vá khi bước nhanh trả về sai câu.
    let replyVi: String
    let learner: AILine
    let feedback: String
    let corrected: AILine
    let hints: [AILine]

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "replyWords": ["type": "array", "items": AIWord.schema],
            "replyVi": ["type": "string"],
            "learner": AILine.schema,
            "feedback": ["type": "string"],
            "corrected": AILine.schema,
            "hints": ["type": "array", "items": AILine.schema],
        ],
        "required": ["replyWords", "replyVi", "learner", "feedback", "corrected", "hints"],
        "additionalProperties": false,
    ]
}

/// Nhắc luyện nói vào giờ người dùng chọn. Đặt lịch từng ngày một (không lặp vô hạn)
/// để ngày nào đã đạt mục tiêu thì bỏ qua, khỏi nhắc người đang học chăm.
enum StreakReminder {
    static let enabledKey = "streakReminderOn"
    static let hourKey = "streakReminderHour"
    static let minuteKey = "streakReminderMinute"

    private static let idPrefix = "streak-reminder-"
    /// Đặt trước bấy nhiêu ngày; mỗi lần mở app lại đặt tiếp.
    private static let daysAhead = 30

    private static var store: UserDefaults { SharedSettings.store }

    static var isOn: Bool {
        get { store.bool(forKey: enabledKey) }
        set { store.set(newValue, forKey: enabledKey) }
    }

    static var hour: Int {
        get { store.object(forKey: hourKey) as? Int ?? 8 }
        set { store.set(newValue, forKey: hourKey) }
    }

    static var minute: Int {
        get { store.object(forKey: minuteKey) as? Int ?? 0 }
        set { store.set(newValue, forKey: minuteKey) }
    }

    /// Giờ nhắc dưới dạng Date, cho DatePicker.
    static var time: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = components.hour ?? 8
            minute = components.minute ?? 0
        }
    }

    /// Xin quyền rồi bật. `completion` trả về việc người dùng có đồng ý không.
    static func enable(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                isOn = granted
                reschedule()
                completion(granted)
            }
        }
    }

    static func disable() {
        isOn = false
        reschedule()
    }

    /// Xoá lịch cũ rồi đặt lại. Gọi mỗi khi đổi giờ, đổi mục tiêu, hoặc vừa nói xong.
    /// Mã thông báo tính được từ ngày nên tự dựng danh sách, khỏi hỏi hệ thống —
    /// tránh cảnh closure nền chạy trễ rồi đặt lịch lại sau khi người dùng đã tắt.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let ids = (-1...daysAhead).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: Date()).map { idPrefix + StreakStore.dayKey($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard isOn else { return }
        schedule(center)
    }

    private static func schedule(_ center: UNUserNotificationCenter) {
        guard isOn else { return }
        let calendar = Calendar.current
        let doneToday = StreakStore.summary().doneToday

        let content = UNMutableNotificationContent()
        content.title = "Luyện nói tiếng Trung"
        content.body = "Mở Hội thoại AI nói vài câu nhé, năm phút là đủ giữ nhịp."
        content.sound = .default

        for offset in 0..<daysAhead {
            // Hôm nay nói đủ rồi thì thôi.
            if offset == 0, doneToday { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let fire = calendar.date(from: components), fire > Date() else { continue }

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: idPrefix + StreakStore.dayKey(fire), content: content, trigger: trigger
            )
            center.add(request)
        }
    }
}

extension Notification.Name {
    /// Kho hội thoại vừa đổi, màn chọn tình huống nạp lại thành tích.
    static let conversationArchiveChanged = Notification.Name("conversationArchiveChanged")
}

/// Lưu các đoạn hội thoại đang dở để lần sau vào lại tình huống còn nói tiếp được.
enum ConversationArchive {
    struct Saved: Codable {
        struct Turn: Codable {
            var role: String
            var content: String
        }

        var messages: [AIConversationSession.Message]
        var history: [Turn]
        var updatedAt: Date
        /// Thêm sau nên để optional: file cũ không có khoá này vẫn đọc được.
        var goal: String?
        var goalReached: Bool?
        /// Tổng thời gian đã ngồi nói ở tình huống này.
        var seconds: TimeInterval?
        /// Người học đã bấm cờ kết thúc phiên hay còn đang dở.
        var finished: Bool?
        /// Số câu đã nói, cho chế độ nói trực tiếp — chế độ đó không giữ lại lời thoại.
        var sentences: Int?

        var spokenTurns: Int { messages.filter { $0.speaker == .user }.count }

        /// Số câu tiếng Trung người học thực sự nói ra.
        var spokenSentences: Int {
            if let sentences { return sentences }
            return messages.filter { $0.speaker == .user && ChineseText.containsHan($0.line.zh) }.count
        }
    }

    /// Thành tích của một tình huống, hiện ở màn chọn tình huống.
    struct Stat {
        var sentences: Int
        var seconds: TimeInterval
        var finished: Bool
        /// Lần cuối nói ở tình huống này, để biết cái nào đang học dở gần đây nhất.
        var updatedAt: Date
    }

    /// Giữ lại bấy nhiêu đoạn gần nhất, cũ hơn thì bỏ. Mỗi tình huống có thể chiếm hai chỗ:
    /// một cho hội thoại theo lượt, một cho chế độ nói trực tiếp.
    private static let limit = 60

    /// Chế độ nói trực tiếp lưu riêng, để không đè lên đoạn hội thoại theo lượt đang dở.
    private static func key(_ scenario: Scenario, realtime: Bool) -> String {
        realtime ? "rt-\(scenario.id)" : String(scenario.id)
    }

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.json")
    }

    private static func load() -> [String: Saved] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: Saved].self, from: data)
        else { return [:] }
        return map
    }

    private static func write(_ map: [String: Saved]) {
        var map = map
        if map.count > limit {
            let keep = map.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(limit)
            map = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let fileURL, let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .conversationArchiveChanged, object: nil)
    }

    static func saved(for scenario: Scenario) -> Saved? {
        load()[key(scenario, realtime: false)]
    }

    static func save(_ saved: Saved, for scenario: Scenario) {
        var map = load()
        map[key(scenario, realtime: false)] = saved
        write(map)
    }

    /// Thành tích tích luỹ của chế độ nói trực tiếp ở tình huống này.
    static func realtime(for scenario: Scenario) -> Saved? {
        load()[key(scenario, realtime: true)]
    }

    static func saveRealtime(_ saved: Saved, for scenario: Scenario) {
        var map = load()
        map[key(scenario, realtime: true)] = saved
        write(map)
    }

    /// Chỉ xoá đoạn hội thoại theo lượt; thời gian đã nói trực tiếp vẫn giữ.
    static func remove(for scenario: Scenario) {
        var map = load()
        map.removeValue(forKey: key(scenario, realtime: false))
        write(map)
    }

    /// Xoá sạch mọi thứ của tình huống (dùng khi người dùng xoá tình huống tự tạo).
    static func removeAll(for scenario: Scenario) {
        removeAll(for: [scenario])
    }

    static func removeAll(for scenarios: [Scenario]) {
        var map = load()
        for scenario in scenarios {
            map.removeValue(forKey: key(scenario, realtime: false))
            map.removeValue(forKey: key(scenario, realtime: true))
        }
        write(map)
    }

    /// Đã nói bao nhiêu câu và bao nhiêu thời gian ở từng tình huống,
    /// cộng cả hội thoại theo lượt lẫn chế độ nói trực tiếp.
    static func stats() -> [Int: Stat] {
        var result: [Int: Stat] = [:]
        for (key, saved) in load() {
            let isRealtime = key.hasPrefix("rt-")
            guard let id = Int(isRealtime ? String(key.dropFirst(3)) : key) else { continue }
            let sentences = saved.spokenSentences
            let seconds = saved.seconds ?? 0
            guard sentences > 0 || seconds > 0 else { continue }
            var stat = result[id] ?? Stat(sentences: 0, seconds: 0, finished: true, updatedAt: .distantPast)
            stat.sentences += sentences
            stat.seconds += seconds
            stat.updatedAt = max(stat.updatedAt, saved.updatedAt)
            // Chỉ đoạn theo lượt mới có trạng thái dở dang; nói trực tiếp luôn coi là xong.
            if !(saved.finished ?? false) { stat.finished = false }
            result[id] = stat
        }
        return result
    }
}

// MARK: - Phiên hội thoại

final class AIConversationSession: ObservableObject {
    struct Message: Codable, Identifiable, Equatable {
        enum Speaker: String, Codable { case partner, user }
        var id = UUID()
        let speaker: Speaker
        var line: ChatLine
        /// Góp ý của AI cho câu người dùng vừa nói.
        var feedback: String?
        var corrected: ChatLine?
        /// Kết quả nhận dạng theo đoạn, giữ lại để chấm lại sau khi AI tách từ chuẩn hơn.
        var heard: [SpeechCapture.HeardSegment] = []
        /// Người học đã đọc lại câu này và lần này máy nghe ra.
        var retried = false
        /// Vài câu người học có thể nói tiếp sau câu này của AI.
        var hints: [ChatLine] = []
        /// Người học nói bằng tiếng Việt vì chưa biết diễn đạt — `corrected` là câu tiếng Trung được chỉ.
        var askedInVietnamese = false

        /// Những từ máy nghe không chắc — thường là chỗ phát âm chưa tới.
        var flaggedWords: [PinyinWord] { line.words.filter { $0.flagged == true } }
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isThinking = false
    @Published private(set) var canRetry = false
    @Published var errorMessage: String?

    /// Rảnh tay: micro tự bật lại ngay khi AI đọc xong, người học không phải chạm máy.
    @Published var handsFree = ConversationSettings.handsFree {
        didSet { ConversationSettings.handsFree = handsFree }
    }

    /// Người học tạm chuyển sang gõ chữ thay vì nói.
    @Published var isTextMode = false {
        didSet { if isTextMode { capture.cancel() } }
    }

    /// Đang đọc lại một câu cũ để sửa phát âm (không phải nói câu mới cho AI).
    @Published private(set) var drillingID: UUID?
    /// Có đoạn đang dở, đang chờ người học chọn nói tiếp hay bắt đầu lại.
    @Published private(set) var needsResumeChoice = false
    /// Đang xem thẻ tổng kết, tạm dừng vòng rảnh tay.
    @Published private(set) var isFinished = false
    /// Đã bấm thêm câu của phiên này vào mục Luyện nói.
    @Published private(set) var savedToPractice = false
    /// Số lượt người học đã nói trong đoạn đang dở.
    @Published private(set) var savedTurns = 0

    /// Micro đang mở để nghe người học nói tiếng Việt (nhờ chỉ cách nói).
    @Published private(set) var isAskingInVietnamese = false

    var isListening: Bool { capture.isListening }
    /// Micro đang mở để nói câu mới với AI (không tính lúc đọc lại câu cũ).
    var isListeningForReply: Bool { capture.isListening && drillingID == nil }
    var transcript: String { capture.transcript }
    var micLevel: Float { capture.level }

    let scenario: Scenario
    private var history: [OpenAIClient.Message] = []
    private var requestToken: UUID?
    /// Những câu đang chờ dịch bù, để không gọi bộ dịch hai lần cho cùng một câu.
    private var translating: Set<String> = []
    private let capture = SpeechCapture()
    private var captureObserver: AnyCancellable?
    private var saved: ConversationArchive.Saved?
    /// Tổng thời gian đã ngồi nói ở tình huống này.
    private var elapsed: TimeInterval = 0
    /// Mốc tính giờ; nil là đồng hồ đang dừng (đang chờ chọn nói tiếp, hoặc đã rời màn hình).
    private var clockStart: Date?
    /// Mở màn hình rồi bỏ đó thì đừng tính là thời gian luyện.
    private static let maxIdleChunk: TimeInterval = 120
    private var clockPausedByBackground = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(scenario: Scenario) {
        self.scenario = scenario
        captureObserver = capture.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        capture.onError = { [weak self] message in
            guard let self else { return }
            // Thiếu quyền micro: chuyển sang gõ chữ, vòng lặp rảnh tay cũng dừng theo.
            self.isTextMode = true
            self.errorMessage = message
        }
        observeLifecycle()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// App xuống nền thì dừng đồng hồ, nếu không thời gian luyện sẽ tính cả lúc bạn làm việc khác.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.clockStart != nil else { return }
            self.accumulateTime()
            self.clockStart = nil
            self.clockPausedByBackground = true
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.clockPausedByBackground else { return }
            self.clockPausedByBackground = false
            self.clockStart = Date()
        })
    }

    var hasStarted: Bool { !messages.isEmpty || isThinking }

    /// Vào màn hình: có đoạn dở thì dựng lại ngay cho thấy, không thì mở lời luôn.
    func prepare() {
        guard !hasStarted, !needsResumeChoice else { return }
        guard let saved = ConversationArchive.saved(for: scenario), !saved.messages.isEmpty else {
            return start()
        }
        self.saved = saved
        savedTurns = saved.spokenTurns
        elapsed = saved.seconds ?? 0
        isFinished = false
        // Hiện luôn đoạn cũ thay vì màn hình trống: nhìn thấy câu bạn hội thoại đang chờ
        // mình trả lời thì nói tiếp mới là việc tự nhiên. Chưa đọc, chưa mở micro.
        messages = saved.messages
        history = saved.history.map {
            .init(role: $0.role == OpenAIClient.Message.Role.assistant.rawValue ? .assistant : .user,
                  content: $0.content)
        }
        needsResumeChoice = true
    }

    /// Nói tiếp đoạn cũ: đọc lại câu cuối để bắt nhịp rồi mở micro như thường.
    func resume() {
        guard needsResumeChoice else { return }
        needsResumeChoice = false
        errorMessage = nil
        clockStart = Date()
        if let last = messages.last, last.speaker == .partner {
            NaturalSpeaker.chinese.speak(last.line.zh, preferOpenAI: true) { [weak self] in
                self?.listenAfterReply()
            }
        } else {
            // Lần trước thoát giữa chừng, chưa kịp nhận câu trả lời.
            requestReply()
        }
    }

    /// Câu bạn hội thoại đang chờ mình trả lời, để hiện trên thẻ nói tiếp.
    var pendingLine: ChatLine? {
        guard let last = messages.last, last.speaker == .partner else { return nil }
        return last.line
    }

    func start() {
        stop()
        messages = []
        history = []
        errorMessage = nil
        needsResumeChoice = false
        isFinished = false
        savedToPractice = false
        saved = nil
        savedTurns = 0
        elapsed = 0
        clockStart = Date()
        ConversationArchive.remove(for: scenario)
        requestReply()
    }

    /// Cộng dồn thời gian từ mốc trước đến giờ, rồi đặt lại mốc.
    private func accumulateTime() {
        guard let clockStart else { return }
        let chunk = min(Date().timeIntervalSince(clockStart), Self.maxIdleChunk)
        elapsed += chunk
        self.clockStart = Date()
        StreakStore.addSeconds(chunk)
    }

    /// Ghi lại đoạn đang nói để lần sau mở lên còn tiếp được.
    private func persist() {
        guard !messages.isEmpty else { return }
        accumulateTime()
        let turns = history.map { ConversationArchive.Saved.Turn(role: $0.role.rawValue, content: $0.content) }
        ConversationArchive.save(
            .init(messages: messages, history: turns, updatedAt: Date(),
                  goal: nil, goalReached: nil, seconds: elapsed, finished: isFinished),
            for: scenario
        )
    }

    func stop() {
        requestToken = nil
        isThinking = false
        drillingID = nil
        capture.cancel()
        NaturalSpeaker.all.forEach { $0.stop() }
        // Rời màn hình: chốt giờ lại, nếu không lần sau mở lên sẽ tính cả lúc app đóng.
        persist()
        clockStart = nil
    }

    // MARK: - Nói

    /// Bấm micro: đang nghe thì chốt câu, chưa nghe thì bắt đầu nghe.
    func toggleMic() {
        if drillingID != nil {
            // Đang đọc lại câu cũ: bỏ dở, quay về nói tiếp với AI.
            capture.cancel()
            drillingID = nil
            return
        }
        if capture.isListening {
            capture.finish()
        } else {
            // Cho phép ngắt lời: AI đang đọc mà bấm micro thì loa im ngay.
            NaturalSpeaker.all.forEach { $0.stop() }
            listen()
        }
    }

    /// Mở micro cho người học nói tự do (hội thoại không có câu mẫu để so).
    func listen() {
        guard !isThinking, !isTextMode, !capture.isListening, drillingID == nil,
              !needsResumeChoice, !isFinished else { return }
        // Đang đọc dở thì để đọc xong, tránh micro thu lại tiếng của AI.
        guard !NaturalSpeaker.chinese.isSpeaking else { return }
        errorMessage = nil
        finishVietnameseListening()
        // Khoảng chờ theo cài đặt "chờ khi bạn ngừng nói" của người dùng.
        capture.start(targets: []) { [weak self] heard in
            guard let self else { return }
            let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            // Không nghe được gì: dừng vòng lặp để người học chủ động bấm lại.
            guard !text.isEmpty else { return }
            self.send(text: text, heard: self.capture.segments, source: .spoken)
        }
    }

    func stopListening() {
        capture.cancel()
        finishVietnameseListening()
    }

    // MARK: - Chưa biết nói thì cứ nói tiếng Việt

    /// Nghe người học nói tiếng Việt, rồi chỉ cho họ câu tiếng Trung tương ứng (đọc to luôn).
    func askInVietnamese() {
        guard !isThinking, drillingID == nil, !needsResumeChoice, !isFinished else { return }
        if capture.isListening {
            capture.finish()
            return
        }
        NaturalSpeaker.all.forEach { $0.stop() }
        errorMessage = nil
        isAskingInVietnamese = true
        capture.localeIdentifier = "vi-VN"
        capture.start(targets: []) { [weak self] heard in
            guard let self else { return }
            self.finishVietnameseListening()
            let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self.coach(vietnamese: text)
        }
    }

    private func finishVietnameseListening() {
        isAskingInVietnamese = false
        capture.localeIdentifier = "zh-CN"
    }

    /// Hỏi AI: câu tiếng Việt này thì nói tiếng Trung thế nào trong tình huống đang nói dở.
    func coach(vietnamese: String) {
        let text = vietnamese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }

        var message = Message(speaker: .user, line: ChatLine(zh: text, vi: "", words: [PinyinWord(zh: text, py: "")]))
        message.askedInVietnamese = true
        messages.append(message)
        let messageID = message.id

        let token = UUID()
        requestToken = token
        isThinking = true
        canRetry = false
        errorMessage = nil

        let instructions = basePrompt() + """
        The learner does not know how to say something in Chinese yet. They said it in Vietnamese: "\(text)".
        Do NOT continue the conversation and do NOT answer them. Teach them the sentence instead:
        - "zh": the natural Chinese sentence they should say right now in this scenario, at their level, short (at most 20 Chinese characters).
        - "vi": the Vietnamese meaning of that Chinese sentence.
        - "words": split "zh" into words in order; each item has the exact characters ("zh", punctuation attached to the preceding word) and its Hanyu Pinyin with tone marks ("py").
        """
        let input = history + [.init(role: .user, content: "(Người học chưa biết nói câu này bằng tiếng Trung: \"\(text)\")")]

        Task {
            do {
                let line = try await OpenAIClient.respond(
                    instructions: instructions, messages: input,
                    schemaName: "coach_line", schema: AILine.schema, as: AILine.self
                )
                await MainActor.run { [weak self] in
                    guard let self, self.requestToken == token else { return }
                    self.isThinking = false
                    let suggestion = line.chatLine
                    guard !suggestion.zh.isEmpty, let index = self.messages.firstIndex(where: { $0.id == messageID }) else { return }
                    self.messages[index].corrected = suggestion
                    self.persist()
                    // Chỉ cách nói bằng giọng, xong mở micro để người học nói theo.
                    self.speak(suggestion, thenListen: self.handsFree)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.requestToken == token else { return }
                    self.isThinking = false
                    self.canRetry = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Câu đến từ đâu — chỉ câu nói ra mới tính vào chuỗi ngày luyện nói.
    enum InputSource { case spoken, typed }

    /// Gửi câu người dùng nhập (gõ, hoặc nói bằng bàn phím Bàn Phím Trung), tiếng Trung hoặc tiếng Việt.
    func send(text: String, heard: [SpeechCapture.HeardSegment] = [], source: InputSource = .typed) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        let line = ChineseText.containsHan(trimmed)
            ? ChatLine(zh: trimmed, vi: "", words: ChineseText.words(for: trimmed))
            : ChatLine(zh: trimmed, vi: "", words: [PinyinWord(zh: trimmed, py: "")])
        appendUser(line, spoken: trimmed, heard: heard, source: source)
    }

    /// `thenListen`: nghe xong thì mở lại micro. Chỉ đúng với câu mới nhất của AI —
    /// nghe lại một gợi ý hay câu sửa thì không được tự mở micro rồi gửi đi lung tung.
    func speak(_ line: ChatLine, thenListen: Bool = false) {
        // Tắt micro trước, nếu không loa và micro tranh nhau audio session.
        capture.cancel()
        NaturalSpeaker.chinese.speak(line.zh, preferOpenAI: true) { [weak self] in
            guard thenListen else { return }
            self?.listenAfterReply()
        }
    }

    func retry() {
        guard canRetry else { return }
        requestReply()
    }

    private func appendUser(_ line: ChatLine, spoken: String, heard: [SpeechCapture.HeardSegment],
                            source: InputSource) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var message = Message(speaker: .user, line: line)
        message.heard = heard
        if let flagged = PronunciationScore.flag(words: line.words, segments: heard) {
            message.line.words = flagged
        }
        if source == .spoken {
            Self.recordUnclear(message)
        }
        messages.append(message)
        history.append(.init(role: .user, content: spoken))
        if source == .spoken, ChineseText.containsHan(line.zh) { StreakStore.addSentence() }
        persist()
        requestReply()
    }

    // MARK: - Tổng kết

    struct Summary {
        /// Số lượt người học đã nói.
        var spokenTurns = 0
        /// Số lượt máy nghe rõ ngay từ lần đầu.
        var cleanTurns = 0
        /// Những câu đáng mang sang mục Luyện nói: ưu tiên câu AI sửa cho tự nhiên hơn.
        var keepers: [ChatLine] = []
    }

    var summary: Summary {
        var result = Summary()
        var seen = Set<String>()
        for message in messages where message.speaker == .user {
            guard ChineseText.containsHan(message.line.zh) else { continue }
            result.spokenTurns += 1
            if message.flaggedWords.isEmpty { result.cleanTurns += 1 }
            // Câu AI sửa đáng nhớ hơn câu mình nói sai; không có thì giữ chính câu mình nói đúng.
            let keeper = message.corrected ?? message.line
            guard !keeper.zh.isEmpty, seen.insert(keeper.zh).inserted else { continue }
            result.keepers.append(keeper)
        }
        result.keepers = Array(result.keepers.suffix(8))
        return result
    }

    /// Kết thúc phiên và mở thẻ tổng kết (người học chủ động bấm).
    func finish() {
        capture.cancel()
        drillingID = nil
        NaturalSpeaker.all.forEach { $0.stop() }
        isFinished = true
        persist()
        clockStart = nil
    }

    /// Đóng thẻ tổng kết, nói tiếp đoạn đang dở.
    func keepTalking() {
        isFinished = false
        clockStart = Date()
        if handsFree { listen() }
    }

    /// Chuyển những câu đáng nhớ của phiên sang mục Luyện nói.
    @discardableResult
    func saveToPractice() -> Int {
        let lines = summary.keepers
        for line in lines where !line.zh.isEmpty {
            SharedStore.savePhrase(zh: line.zh, vi: line.vi, words: line.words)
        }
        savedToPractice = true
        return lines.count
    }

    // MARK: - Đọc lại để sửa phát âm

    /// Đọc mẫu câu cho người học nghe lại; không nối tiếp vòng rảnh tay vì đang ở chế độ xem lại.
    func speakSample(_ zh: String) {
        guard !zh.isEmpty else { return }
        capture.cancel()
        drillingID = nil
        NaturalSpeaker.chinese.speak(zh, preferOpenAI: true)
    }

    /// Đọc lại chính câu mình vừa nói để sửa phát âm. Không gửi gì cho AI.
    func drill(_ messageID: UUID) {
        if drillingID == messageID {
            capture.finish()
            return
        }
        capture.cancel()
        drillingID = nil
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        let target = message.line.zh
        guard !target.isEmpty, ChineseText.containsHan(target) else { return }
        NaturalSpeaker.all.forEach { $0.stop() }
        drillingID = messageID
        capture.start(targets: [target]) { [weak self] heard in
            guard let self else { return }
            self.drillingID = nil
            let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let index = self.messages.firstIndex(where: { $0.id == messageID }) else { return }
            let correct = PhraseMatcher.isFullyCorrect(heard: text, words: message.line.words)
            UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
            PronunciationLog.record(PronunciationAnalyzer.mistakes(target: target, heard: text, source: .conversation))
            guard correct else {
                // Vẫn chưa ra: chấm lại theo lần đọc mới để chỗ đỏ bám sát lỗi hiện tại.
                let segments = self.capture.segments
                if let flagged = PronunciationScore.flag(words: self.messages[index].line.words, segments: segments) {
                    self.messages[index].line.words = flagged
                }
                return
            }
            self.messages[index].retried = true
            self.messages[index].line.words = self.messages[index].line.words.map {
                var word = $0
                word.flagged = false
                return word
            }
            self.persist()
        }
    }

    /// Chữ máy nghe không chắc trong câu người học nói. Mỗi câu một context: chấm lại thì thay, không cộng dồn.
    private static func recordUnclear(_ message: Message) {
        PronunciationLog.record(
            PronunciationAnalyzer.unclear(words: message.line.words, sentence: message.line.zh,
                                          source: .conversation, context: message.id.uuidString),
            replacingContext: message.id.uuidString
        )
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
        let base = basePrompt()
        // Biết trước id để bước 2 điền pinyin và gợi ý vào đúng câu, không phải chờ bước 1 xong.
        let replyID = UUID()
        // Bước 2 điền vào đúng hai tin nhắn này, kể cả khi người học đã nói sang lượt khác.
        let learnerID = messages.last(where: { $0.speaker == .user })?.id

        Task {
            do {
                // Bước 1: chỉ câu nói — ngắn nên về nhanh, phát tiếng được gần như tức thì.
                let reply = try await OpenAIClient.respond(
                    instructions: base + Self.replyRules, messages: input,
                    schemaName: "conversation_reply", schema: AIReply.schema, as: AIReply.self,
                    model: OpenAISettings.fastModel
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestToken == token else { return }
                    self.applyReply(reply, id: replyID)
                }

                // Bước 2: pinyin, góp ý, câu sửa, gợi ý — chạy trong lúc loa đang đọc.
                let detail = try await OpenAIClient.respond(
                    instructions: base + Self.detailRules(reply: reply.zh), messages: input,
                    schemaName: "conversation_detail", schema: AIDetail.schema, as: AIDetail.self
                )
                DispatchQueue.main.async { [weak self] in
                    // Cố ý không so requestToken: ở chế độ rảnh tay người học thường nói câu
                    // tiếp theo trước khi bước 2 về, chặn ở đây là mất hết pinyin và góp ý.
                    self?.applyDetail(detail, replyID: replyID, learnerID: learnerID)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestToken == token else { return }
                    // Bước 2 hỏng thì hội thoại vẫn chạy, chỉ thiếu pinyin và góp ý — không báo lỗi.
                    guard self.isThinking else { return }
                    self.isThinking = false
                    self.canRetry = true
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Bước 1: hiện câu trả lời và đọc ngay, pinyin tạm dùng bộ chuyển trên máy.
    private func applyReply(_ reply: AIReply, id: UUID) {
        isThinking = false
        let zh = reply.zh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zh.isEmpty else {
            // Không có gì để đọc: báo ra, nếu không màn hình đứng im mà không có nút thử lại.
            canRetry = true
            errorMessage = "AI chưa trả lời được câu này. Hãy thử lại."
            return
        }

        let line = ChatLine(zh: zh, vi: vietnameseOnly(reply.vi), words: ChineseText.words(for: zh))
        messages.append(Message(id: id, speaker: .partner, line: line))
        history.append(.init(role: .assistant, content: zh))
        persist()
        // Bước 2 thường vá lại nghĩa; nếu nó hỏng hoặc về muộn thì dịch bù để câu không bị trống nghĩa.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.fillMissingVietnamese(id)
        }
        NaturalSpeaker.chinese.speak(zh, preferOpenAI: true) { [weak self] in
            self?.listenAfterReply()
        }
    }

    /// Chỗ có thể thiếu nghĩa tiếng Việt trong một tin nhắn.
    private enum ViSlot {
        case line
        case corrected
        case hint(Int)

        var key: String {
            switch self {
            case .line: "line"
            case .corrected: "corrected"
            case let .hint(index): "hint\(index)"
            }
        }
    }

    private func chatLine(_ slot: ViSlot, in message: Message) -> ChatLine? {
        switch slot {
        case .line: return message.line
        case .corrected: return message.corrected
        case let .hint(index): return index < message.hints.count ? message.hints[index] : nil
        }
    }

    private func setVietnamese(_ text: String, for slot: ViSlot, at index: Int) {
        switch slot {
        case .line: messages[index].line.vi = text
        case .corrected: messages[index].corrected?.vi = text
        case let .hint(hint):
            guard hint < messages[index].hints.count else { return }
            messages[index].hints[hint].vi = text
        }
    }

    /// Câu nào chưa có nghĩa tiếng Việt thì dịch bù bằng bộ dịch ngoài: người học nhìn
    /// một câu tiếng Trung mà không có nghĩa bên dưới thì coi như câu đó mất trắng.
    /// Dịch cả câu sửa lẫn câu gợi ý — gợi ý mà không hiểu nghĩa thì không dám nói.
    private func fillMissingVietnamese(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        var slots: [ViSlot] = [.line, .corrected]
        slots += message.hints.indices.map { ViSlot.hint($0) }
        for slot in slots {
            translate(slot, of: id)
        }
    }

    private func translate(_ slot: ViSlot, of id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              let line = chatLine(slot, in: messages[index]),
              line.vi.isEmpty, ChineseText.containsHan(line.zh) else { return }
        let token = "\(id)-\(slot.key)"
        guard !translating.contains(token) else { return }
        translating.insert(token)
        let zh = line.zh
        Task {
            let result = try? await Translator.translate(zh, from: "zh-CN", to: "vi")
            let vi = vietnameseOnly(result ?? "")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.translating.remove(token)
                guard !vi.isEmpty,
                      let index = self.messages.firstIndex(where: { $0.id == id }),
                      let line = self.chatLine(slot, in: self.messages[index]),
                      line.vi.isEmpty, line.zh == zh else { return }
                self.setVietnamese(vi, for: slot, at: index)
                self.persist()
            }
        }
    }

    /// Bước 2: điền pinyin chuẩn, góp ý cho câu người học, câu sửa và gợi ý.
    private func applyDetail(_ detail: AIDetail, replyID: UUID, learnerID: UUID?) {
        if let learnerID, let index = messages.firstIndex(where: { $0.id == learnerID }) {
            // Pinyin và nghĩa câu người dùng do AI tách (chính xác hơn bộ chuyển trên máy).
            let learner = detail.learner.chatLine
            if !learner.zh.isEmpty, learner.zh.filter(\.isLetter) == messages[index].line.zh.filter(\.isLetter) {
                messages[index].line = learner
            }
            // AI tách từ chuẩn hơn, nên chấm lại phát âm theo cách tách mới.
            if !messages[index].retried,
               let flagged = PronunciationScore.flag(words: messages[index].line.words,
                                                     segments: messages[index].heard) {
                messages[index].line.words = flagged
                Self.recordUnclear(messages[index])
            }
            let feedback = detail.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
            messages[index].feedback = feedback.isEmpty ? nil : feedback
            if !detail.corrected.zh.trimmingCharacters(in: .whitespaces).isEmpty,
               detail.corrected.zh.filter(\.isLetter) != messages[index].line.zh.filter(\.isLetter) {
                messages[index].corrected = detail.corrected.chatLine
            }
        }

        if let index = messages.firstIndex(where: { $0.id == replyID }) {
            let zh = messages[index].line.zh
            // Bước nhanh thỉnh thoảng trả nguyên chữ Hán, hoặc dịch nhầm câu của lượt trước.
            // Bước sau được đưa đúng câu cần dịch và dùng model khá hơn, nên ưu tiên bản của nó.
            let fixed = vietnameseOnly(detail.replyVi)
            if !fixed.isEmpty {
                messages[index].line.vi = fixed
            }
            let joined = detail.replyWords.map(\.zh).joined().filter { !$0.isWhitespace }
            if !detail.replyWords.isEmpty, joined == zh.filter({ !$0.isWhitespace }) {
                messages[index].line.words = detail.replyWords.map {
                    PinyinWord(zh: $0.zh, py: $0.py, hv: ChineseText.hanViet(forWord: $0.zh, pinyin: $0.py))
                }
            }
            messages[index].hints = detail.hints.map(\.chatLine).filter { !$0.zh.isEmpty }
        }
        fillMissingVietnamese(replyID)
        if let learnerID { fillMissingVietnamese(learnerID) }
        persist()
    }

    /// Vòng lặp rảnh tay: AI đọc xong là micro tự mở, hội thoại chạy liên tục bằng giọng nói.
    private func listenAfterReply(attempt: Int = 0) {
        // Lúc định mở micro, lượt trước có thể còn đang chờ hoặc loa còn đang đọc.
        // Thử lại vài lần, nếu không vòng rảnh tay sẽ chết im lặng mà người dùng không biết.
        guard handsFree, !isTextMode, !isFinished, attempt < 12 else { return }
        // Chờ loa tắt hẳn để micro không thu lại tiếng của AI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.capture.isListening else { return }
            // Còn vướng (lượt trước chưa về, loa còn đang đọc) thì hẹn lại chứ đừng bỏ luôn.
            guard !self.isThinking, !NaturalSpeaker.chinese.isSpeaking else {
                return self.listenAfterReply(attempt: attempt + 1)
            }
            self.listen()
        }
    }

    private func basePrompt() -> String {
        let level = ConversationLevel(rawValue: UserDefaults.standard.string(forKey: OpenAISettings.levelKey) ?? "") ?? .beginner
        return """
        You are role-playing a spoken conversation to help a Vietnamese learner practise Mandarin Chinese.
        Scenario: "\(scenario.title)" (topic: \(scenario.topic)). You play: \(scenario.partnerRole). The learner plays: \(scenario.userRole).
        Learner level: \(level.promptDescription).

        - Stay in character. Speak natural, colloquial Mainland Mandarin in Simplified Chinese, the way a real person talks. Keep each reply short (1–2 sentences, at most 30 Chinese characters) and usually end with a question or prompt so the learner has something to answer. Move the scenario forward naturally.
        - Keep the conversation flowing for as long as the learner wants to talk. Never say goodbye, wrap up, or treat the scenario as finished. When a thread runs out, react to what the learner said and bring up a new, related angle of the same topic.
        - Never use Arabic numerals or Latin letters in Chinese text; write numbers in Chinese characters.
        - The learner's messages come from speech recognition, so they may contain wrong homophones or missing words. Infer the most likely intended meaning and respond to that. If the learner writes in Vietnamese, respond in character in Chinese.

        """
    }

    /// Bước 1: chỉ xin câu nói, để người học nghe được tiếng sớm nhất có thể.
    private static let replyRules = """
    Return ONLY your character's next line, nothing else:
    - "zh": the line you are saying now, in Simplified Chinese.
    - "vi": the Vietnamese translation of the exact sentence you just wrote in "zh" — not of any earlier message in the conversation. It MUST be written in Vietnamese, using the Vietnamese alphabet. Never leave "vi" empty, and never copy the Chinese sentence or any Chinese character into it.
    """

    /// Bước 2: xin phần học liệu cho lượt vừa rồi, câu nói đã chốt nên không được đổi.
    private static func detailRules(reply: String) -> String {
        """
        Your character's next line has already been decided and said out loud: "\(reply)". Do not change it. Return the study material for this turn.
        - "replyWords": that line split into words (see the "words" rule below).
        - "replyVi": the Vietnamese translation of that exact line, and of nothing else. Write it in Vietnamese, using the Vietnamese alphabet — never copy the Chinese sentence or any Chinese character into it.
        - "learner": the learner's LAST message copied exactly as written (zh), with its Vietnamese translation (vi) and words. For the opening line, or if the last message contains no Chinese, set zh and vi to empty strings and words to an empty array.
        - "feedback": one short, encouraging sentence in Vietnamese about the learner's LAST message (grammar, word choice, or a likely pronunciation/tone problem if recognition produced an odd word). Use an empty string for the opening line or when the message was already natural and correct.
        - "corrected": if the learner's last message was wrong, unnatural, or in Vietnamese, give the natural Chinese sentence they should say (with Vietnamese translation and words). Otherwise set zh and vi to empty strings and words to an empty array.
        - "hints": two or three SHORT, clearly different things the learner could say next in this scenario, at their level, each with its natural Vietnamese translation and words. Write them as the learner (their role), not as your character. Always give hints, including for the opening line.
        - Every "vi" field in this response is Vietnamese prose, never Chinese characters.
        - "words" (for every Chinese line): split the Chinese text into words in order. Each item has the exact characters ("zh", with punctuation attached to the preceding word) and Hanyu Pinyin with tone marks ("py": syllables of one word written together, tone sandhi applied to 不 and 一, neutral tones unmarked). Concatenating all "zh" values must reproduce the Chinese text exactly.
        """
    }
}


// MARK: - Nói trực tiếp (OpenAI Realtime)

/// Hội thoại bằng giọng nói trực tiếp: tiếng của người học đi thẳng lên model, không qua
/// bước chuyển thành chữ. Model nghe được cả ngữ điệu lẫn thanh điệu thật, và ngắt lời được
/// như nói chuyện với người. Đắt hơn chế độ theo lượt, nên để người dùng tự chọn.
final class RealtimeConversation: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        /// Đang mở micro chờ người học nói.
        case listening
        /// Người học đang nói.
        case hearing
        /// Bạn hội thoại đang nói.
        case speaking
        case failed(String)

        var isLive: Bool {
            switch self {
            case .listening, .hearing, .speaking: true
            default: false
            }
        }
    }

    struct Line: Identifiable, Equatable {
        enum Speaker { case partner, user }
        let id: String
        var speaker: Speaker
        var text: String
        var isFinal: Bool
        var words: [PinyinWord] = []
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lines: [Line] = []
    @Published private(set) var micLevel: Float = 0

    let scenario: Scenario

    private var socket: URLSessionWebSocketTask?
    /// Phiên riêng có delegate, để đọc được lý do thật khi máy chủ từ chối bắt tay.
    private var socketSession: URLSession?
    /// Mình chủ động ngắt: đừng báo lỗi "cancelled" của chính mình ra màn hình.
    private var isStopping = false
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var tapInstalled = false
    private var playerAttached = false
    private var sessionConfigured = false
    /// Tổng thời gian đã nói trực tiếp ở tình huống này, cộng dồn qua các buổi.
    private var elapsed: TimeInterval = 0
    private var clockStart: Date?
    /// Số câu đã nói ở những buổi trước.
    private var baseSentences = 0
    private var clockPausedByBackground = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// Mở màn hình rồi bỏ đó thì đừng tính là thời gian luyện.
    private static let maxIdleChunk: TimeInterval = 120
    /// Chuyển mẫu và gửi lên mạng chạy ở đây, không làm trên luồng render audio.
    private let audioQueue = DispatchQueue(label: "hihi.banphimtrung.realtime.audio", qos: .userInitiated)

    /// Realtime nhận và trả PCM 16 bit, một kênh, 24 kHz.
    private let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    init(scenario: Scenario) {
        self.scenario = scenario
        super.init()
        observeLifecycle()
    }

    deinit {
        socket?.cancel(with: .goingAway, reason: nil)
        socketSession?.invalidateAndCancel()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// App xuống nền thì dừng đồng hồ, nếu không thời gian luyện sẽ tính cả lúc bạn làm việc khác.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.clockStart != nil else { return }
            self.persist()
            self.clockStart = nil
            self.clockPausedByBackground = true
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.clockPausedByBackground else { return }
            self.clockPausedByBackground = false
            if self.phase.isLive { self.clockStart = Date() }
        })
    }

    // MARK: Vòng đời

    func start() {
        guard !phase.isLive, phase != .connecting else { return }
        guard OpenAISettings.apiKey != nil else {
            phase = .failed(OpenAIClient.ClientError.missingKey.localizedDescription)
            return
        }
        phase = .connecting
        isStopping = false
        lines = []
        // Cộng tiếp vào thành tích của những buổi trước ở cùng tình huống.
        let prior = ConversationArchive.realtime(for: scenario)
        elapsed = prior?.seconds ?? 0
        baseSentences = prior?.spokenSentences ?? 0
        clockStart = nil
        NaturalSpeaker.all.forEach { $0.stop() }

        VoiceEngine.requestPermissions { [weak self] error in
            guard let self else { return }
            if let error {
                self.phase = .failed(error)
                return
            }
            // Tạm tắt phiên micro của bàn phím để app dùng micro.
            if VoiceEngine.shared.state.sessionActive {
                VoiceEngine.shared.deactivate()
            }
            do {
                try self.startAudio()
                self.connect()
            } catch {
                self.stop()
                self.phase = .failed("Không bật được micro: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        isStopping = true
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        socketSession?.invalidateAndCancel()
        socketSession = nil
        sessionConfigured = false
        stopAudio()
        persist()
        clockStart = nil
        if phase.isLive || phase == .connecting { phase = .idle }
    }

    // MARK: Thành tích

    /// Số câu tiếng Trung người học đã nói trong buổi này.
    private var spokenThisSession: Int {
        lines.filter { $0.speaker == .user && $0.isFinal && ChineseText.containsHan($0.text) }.count
    }

    /// Ghi số câu và thời gian để hiện ở màn chọn tình huống.
    /// Không lưu lời thoại: chế độ này không có chức năng nói tiếp đoạn cũ.
    private func persist() {
        if let clockStart {
            let chunk = min(Date().timeIntervalSince(clockStart), Self.maxIdleChunk)
            elapsed += chunk
            self.clockStart = Date()
            StreakStore.addSeconds(chunk)
        }
        let total = baseSentences + spokenThisSession
        guard total > 0 || elapsed >= 1 else { return }
        ConversationArchive.saveRealtime(
            .init(messages: [], history: [], updatedAt: Date(), goal: nil, goalReached: nil,
                  seconds: elapsed, finished: true, sentences: total),
            for: scenario
        )
    }

    // MARK: Âm thanh

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        // .voiceChat là chế độ dành cho thoại hai chiều; phần khử vọng thật sự nằm ở
        // setVoiceProcessingEnabled bên dưới.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        // Đặt mode .voiceChat mới chỉ là chọn chế độ cho audio session. Muốn AVAudioEngine
        // thật sự lọc tiếng loa ra khỏi micro thì phải bật voice processing trên node.
        // Không có bước này, micro thu lại giọng của chính bạn hội thoại, máy chủ tưởng
        // người học đang nói, rồi AI trả lời chính nó — đúng cái vòng lặp vừa gặp.
        try? input.setVoiceProcessingEnabled(true)
        try? engine.outputNode.setVoiceProcessingEnabled(true)

        // Đọc format SAU khi bật voice processing: bật xong định dạng đổi.
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "Realtime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy micro"])
        }
        converter = AVAudioConverter(from: inputFormat, to: wireFormat)

        engine.attach(player)
        playerAttached = true
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            // Buffer của tap chỉ sống trong lúc gọi, nên phải chép trước khi đẩy sang hàng đợi khác.
            guard let self, let copy = Self.copy(buffer) else { return }
            self.audioQueue.async { self.handleInput(copy) }
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
        player.play()
    }

    private func stopAudio() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        if playerAttached {
            engine.detach(player)
            playerAttached = false
        }
        converter = nil
        micLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Chép buffer của tap sang bộ nhớ của mình để xử lý ngoài luồng render audio.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(buffer.format.channelCount) {
            memcpy(target[channel], source[channel], bytes)
        }
        return copy
    }

    private func handleInput(_ buffer: AVAudioPCMBuffer) {
        guard let converter, sessionConfigured else { return }

        // Mức âm để vẽ vòng sóng.
        if let channel = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                sum += channel[index] * channel[index]
            }
            let rms = sqrt(sum / Float(max(Int(buffer.frameLength), 1)))
            let level = min(1, rms * 12)
            DispatchQueue.main.async { [weak self] in self?.micLevel = level }
        }

        let ratio = wireFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let converted = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, converted.frameLength > 0,
              let samples = converted.int16ChannelData else { return }

        let data = Data(bytes: samples[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
        send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
    }

    private func play(base64: String) {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        let frames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: Int16.self).baseAddress,
                  let target = buffer.floatChannelData?[0] else { return }
            for index in 0..<Int(frames) {
                target[index] = Float(source[index]) / 32_768
            }
        }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Người học chen ngang: bỏ hết tiếng còn trong hàng đợi để câu cũ im ngay.
    private func flushPlayback() {
        guard player.isPlaying else { return }
        player.stop()
        player.play()
    }

    // MARK: Kết nối

    private func connect() {
        guard let key = OpenAISettings.apiKey,
              let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(OpenAISettings.realtimeModel)")
        else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        // Phiên riêng có delegate: URLSession chỉ báo "cancelled" khi bắt tay hỏng,
        // phải qua delegate mới biết máy chủ trả mã gì.
        let socketSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.socketSession = socketSession
        let socket = socketSession.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        receive()
        configureSession()
    }

    private func configureSession() {
        let level = ConversationLevel(rawValue: UserDefaults.standard.string(forKey: OpenAISettings.levelKey) ?? "") ?? .beginner
        let instructions = """
        You are role-playing a spoken conversation to help a Vietnamese learner practise Mandarin Chinese.
        Scenario: "\(scenario.title)" (topic: \(scenario.topic)). You play: \(scenario.partnerRole). The learner plays: \(scenario.userRole).
        Learner level: \(level.promptDescription).

        - Speak ONLY Mandarin Chinese, natural and colloquial, with a standard Mainland accent. Never speak Vietnamese or English.
        - Articulate clearly, with accurate tones, so a learner can follow. The speaking rate is already set for you — do not rush, and do not slow down further.
        - Stay in character. Keep every turn short: one or two sentences, and usually end with a question so the learner has something to answer.
        - Keep the conversation flowing for as long as the learner wants to talk. Never say goodbye, wrap up, or treat the scenario as finished; when a thread runs out, bring up a new, related angle of the same topic.
        - The learner is a beginner and will make mistakes and long pauses. Be patient and encouraging, never switch to another language to help.
        - If the learner says something unclear or wrong, say it back the natural way in Chinese as part of your reply, then carry on.
        - Open the conversation yourself with a short line in character.
        """

        let pcm: [String: Any] = ["type": "audio/pcm", "rate": 24_000]
        send([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "instructions": instructions,
                "audio": [
                    "input": [
                        "format": pcm,
                        "transcription": ["model": "gpt-4o-transcribe", "language": "zh"],
                        "turn_detection": [
                            "type": "server_vad",
                            // Cao hơn mặc định một nhịp để tiếng vọng còn sót không bị
                            // tưởng là người học nói. 0,625 = 5/8, biểu diễn đúng trong nhị phân.
                            "threshold": 0.625,
                            "prefix_padding_ms": 300,
                            // Theo cài đặt "chờ khi bạn ngừng nói" của người dùng.
                            "silence_duration_ms": SharedSettings.speechPace.vadSilenceMs,
                        ],
                    ],
                    "output": [
                        "format": pcm,
                        "voice": OpenAISettings.realtimeVoice,
                        "speed": OpenAISettings.realtimeSpeed.value,
                    ],
                ],
            ],
        ])
        sessionConfigured = true
        send(["type": "response.create"])
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .connecting else { return }
            // Bắt đầu tính giờ từ lúc thật sự nói chuyện được, không tính lúc đang kết nối.
            self.clockStart = Date()
            self.phase = .listening
        }
    }

    private func send(_ event: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8)
        else { return }
        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async { self?.fail(error.localizedDescription) }
        }
    }

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                // Lý do thật đến từ delegate; ở đây chỉ bỏ qua tiếng vọng của việc tự ngắt.
                guard (error as NSError).code != NSURLErrorCancelled else { return }
                DispatchQueue.main.async { self.fail(error.localizedDescription) }
            case let .success(message):
                switch message {
                case let .string(text):
                    self.handle(text)
                case let .data(data):
                    self.handle(String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
                self.receive()
            }
        }
    }

    private func fail(_ message: String) {
        guard !isStopping, phase != .idle else { return }
        stop()
        phase = .failed(message)
    }

    /// Máy chủ từ chối ngay lúc bắt tay: nói rõ phải sửa gì.
    private func handshakeMessage(status: Int) -> String {
        switch status {
        case 401:
            "Khoá OpenAI không hợp lệ hoặc không dùng được cho Realtime (401). Nhập lại khoá ở Cài đặt OpenAI."
        case 403:
            "Tài khoản OpenAI chưa được phép dùng Realtime (403). Kiểm tra quyền của khoá API."
        case 404:
            "Không tìm thấy model “\(OpenAISettings.realtimeModel)” (404). Đổi model nói trực tiếp trong Cài đặt OpenAI."
        case 429:
            "OpenAI báo hết hạn mức hoặc gọi quá nhanh (429). Kiểm tra số dư rồi thử lại."
        default:
            "Máy chủ từ chối kết nối (\(status))."
        }
    }

    // MARK: Sự kiện từ máy chủ

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else { return }

        switch type {
        case "response.output_audio.delta", "response.audio.delta":
            if let audio = event["delta"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.play(base64: audio)
                    if self?.phase == .listening || self?.phase == .hearing { self?.phase = .speaking }
                }
            }

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            if let delta = event["delta"] as? String, let id = event["item_id"] as? String {
                DispatchQueue.main.async { [weak self] in self?.append(delta, to: id, speaker: .partner) }
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let id = event["item_id"] as? String {
                DispatchQueue.main.async { [weak self] in self?.finalize(id, text: event["transcript"] as? String) }
            }

        case "conversation.item.input_audio_transcription.completed",
             "conversation.item.input_audio_transcription.done":
            if let id = event["item_id"] as? String, let transcript = event["transcript"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.append(transcript, to: id, speaker: .user)
                    self?.finalize(id, text: transcript)
                }
            }

        case "input_audio_buffer.speech_started":
            DispatchQueue.main.async { [weak self] in
                // Người học chen ngang: cắt tiếng đang phát cho giống nói chuyện thật.
                self?.flushPlayback()
                self?.phase = .hearing
            }

        case "input_audio_buffer.speech_stopped":
            DispatchQueue.main.async { [weak self] in
                if self?.phase == .hearing { self?.phase = .listening }
            }

        case "response.done":
            DispatchQueue.main.async { [weak self] in
                if self?.phase == .speaking { self?.phase = .listening }
            }

        case "error":
            let message = ((event["error"] as? [String: Any])?["message"] as? String) ?? "Lỗi không xác định"
            DispatchQueue.main.async { [weak self] in self?.fail("OpenAI Realtime: \(message)") }

        default:
            break
        }
    }

    private func append(_ delta: String, to id: String, speaker: Line.Speaker) {
        if let index = lines.firstIndex(where: { $0.id == id }) {
            guard !lines[index].isFinal else { return }
            lines[index].text += delta
        } else {
            lines.append(Line(id: id, speaker: speaker, text: delta, isFinal: false))
        }
    }

    private func finalize(_ id: String, text: String?) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        // Máy chủ có thể gửi cả hai tên sự kiện cho cùng một câu; chốt một lần thôi,
        // nếu không streak sẽ đếm câu đó hai lần.
        guard !lines[index].isFinal else { return }

        if let text, !text.isEmpty { lines[index].text = text }
        lines[index].isFinal = true
        let final = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        lines[index].text = final
        // Pinyin chuyển ngay trên máy, không phải chờ thêm lượt gọi nào.
        lines[index].words = ChineseText.containsHan(final) ? ChineseText.words(for: final) : []

        guard lines[index].speaker == .user else { return }
        if ChineseText.containsHan(final) { StreakStore.addSentence() }
        persist()
    }
}

extension RealtimeConversation: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        fail(text.isEmpty
             ? "Máy chủ đóng kết nối (mã \(closeCode.rawValue))."
             : "Máy chủ đóng kết nối: \(text)")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Bắt tay hỏng thì URLSession chỉ nói "cancelled"; mã HTTP mới là thứ cần biết.
        if let response = task.response as? HTTPURLResponse, response.statusCode != 101 {
            fail(handshakeMessage(status: response.statusCode))
            return
        }
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        fail(error.localizedDescription)
    }
}

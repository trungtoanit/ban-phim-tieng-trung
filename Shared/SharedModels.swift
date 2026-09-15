//
//  SharedModels.swift
//  Dùng chung giữa app chính và bàn phím.
//

import Foundation

enum AppGroup {
    static let identifier = "group.hihi.Ban-Phim-Tieng-Trung"
    static let urlScheme = "banphimtrung"
    static let activationURL = URL(string: "banphimtrung://activate")!

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

enum DarwinName {
    /// Bàn phím -> app: có lệnh mới (bắt đầu / dừng / huỷ ghi âm).
    static let command = "hihi.banphimtrung.command"
    /// App -> bàn phím: trạng thái ghi âm / kết quả thay đổi.
    static let state = "hihi.banphimtrung.state"
}

enum VoiceMode: String, Codable, CaseIterable, Identifiable {
    case vietnamese
    case chinese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vietnamese: "VI → 中"
        case .chinese: "中文"
        }
    }

    var spokenLanguageName: String {
        switch self {
        case .vietnamese: "tiếng Việt"
        case .chinese: "tiếng Trung"
        }
    }

    /// Mã ngôn ngữ nguồn để dịch; nil khi nói thẳng tiếng Trung.
    var sourceLanguageCode: String? {
        switch self {
        case .vietnamese: "vi"
        case .chinese: nil
        }
    }

    func speechLocaleID(script: ChineseScript) -> String {
        switch self {
        case .vietnamese: "vi-VN"
        case .chinese: script.speechLocaleID
        }
    }
}

enum ChineseScript: String, CaseIterable, Identifiable {
    case simplified
    case traditional

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simplified: "Giản thể (简体)"
        case .traditional: "Phồn thể (繁體)"
        }
    }

    var translateCode: String {
        switch self {
        case .simplified: "zh-CN"
        case .traditional: "zh-TW"
        }
    }

    var speechLocaleID: String { translateCode }
}

struct VoiceCommand: Codable {
    enum Action: String, Codable {
        case start, stop, cancel
    }

    var requestID: UUID
    var action: Action
    var mode: VoiceMode
    var sentAt: Date
    /// Dịch theo giọng lịch sự (您) thay vì thân mật (你).
    var polite: Bool? = nil
}

/// Một từ tiếng Trung kèm pinyin tương ứng, dùng để hiển thị pinyin thẳng hàng trên chữ Hán.
struct PinyinWord: Codable, Equatable, Hashable {
    var zh: String
    var py: String
    /// Âm Hán Việt, ví dụ 处理 → "xử lý".
    var hv: String? = nil
    /// Từ đọc chưa đúng / máy nghe không chắc chắn.
    var flagged: Bool? = nil
    /// Những chữ máy còn nghe thành ở vị trí này (ví dụ 再 thay vì 在).
    var alternatives: [String]? = nil
}

/// Câu người dùng bấm ⭐ lưu từ bàn phím, hiện trong mục luyện nói của app.
struct SavedPhrase: Codable, Identifiable, Equatable {
    var id: Int
    var zh: String
    var vi: String
    var words: [PinyinWord]
    var savedAt: Date
}

/// Máy chờ bao lâu sau khi bạn ngừng nói rồi mới chốt câu. Người mới học hay ngắc ngứ
/// giữa chừng, chờ ngắn quá là câu bị cắt ngang khi chưa nói xong.
enum SpeechPace: String, CaseIterable, Identifiable, Codable {
    case quick, normal, relaxed, patient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Nhanh"
        case .normal: "Vừa"
        case .relaxed: "Thong thả"
        case .patient: "Rất thong thả"
        }
    }

    var detail: String {
        switch self {
        case .quick: "Chốt câu sau 1,5 giây im lặng — hợp khi bạn đã nói trôi."
        case .normal: "Chốt câu sau 2,5 giây im lặng."
        case .relaxed: "Chốt câu sau 4 giây im lặng — có thời gian nghĩ giữa câu."
        case .patient: "Chốt câu sau 6 giây im lặng — thoải mái ngắc ngứ, không bị cắt ngang."
        }
    }

    /// Im lặng bao lâu thì coi như đã nói xong.
    var pause: TimeInterval {
        switch self {
        case .quick: 1.5
        case .normal: 2.5
        case .relaxed: 4
        case .patient: 6
        }
    }

    /// Chờ bao lâu cho câu đầu, khi chưa nghe được chữ nào.
    var firstPause: TimeInterval {
        switch self {
        case .quick: 7
        case .normal: 12
        case .relaxed: 20
        case .patient: 30
        }
    }

    /// Cho chế độ nói trực tiếp: máy chủ chỉ nhận khoảng chờ vừa phải.
    var vadSilenceMs: Int { Int(min(pause, 4) * 1_000) }
}


extension Notification.Name {
    /// Nhật ký luyện nói vừa đổi, màn hình nạp lại chuỗi ngày.
    static let streakChanged = Notification.Name("streakChanged")
}

/// Nhật ký luyện nói theo ngày, để đếm chuỗi ngày nói liên tiếp.
/// Tính cả câu nói ở Hội thoại AI lẫn câu đọc đúng ở Luyện nói.
enum StreakStore {
    struct Day: Codable, Equatable {
        var sentences = 0
        var seconds: TimeInterval = 0
        /// Mục tiêu đang đặt trong chính ngày đó. Nhờ vậy hạ mục tiêu hôm nay
        /// không biến những ngày cũ chưa đạt thành đã đạt.
        var goal: Int?

        init(sentences: Int = 0, seconds: TimeInterval = 0, goal: Int? = nil) {
            self.sentences = sentences
            self.seconds = seconds
            self.goal = goal
        }

        /// Tự viết để thêm khoá mới sau này không làm hỏng nhật ký đã lưu.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sentences = try container.decodeIfPresent(Int.self, forKey: .sentences) ?? 0
            seconds = try container.decodeIfPresent(TimeInterval.self, forKey: .seconds) ?? 0
            goal = try container.decodeIfPresent(Int.self, forKey: .goal)
        }
    }

    /// Một ngày trên lịch: đã đạt mục tiêu chưa, có phải hôm nay không.
    struct DayStatus: Equatable, Identifiable {
        var key: String
        var date: Date
        var number: Int
        var sentences: Int
        /// Nói đủ mức tối thiểu: ngày này được tính vào chuỗi.
        var done: Bool
        /// Nói đủ cả mục tiêu ngày.
        var goalMet: Bool
        var isToday: Bool
        var isFuture: Bool

        var id: String { key }
    }

    struct MonthGrid: Equatable {
        var title: String
        /// Bảy cột, thứ Hai trước. Ô nil là chỗ trống đầu/cuối tháng.
        var cells: [DayStatus?]
        var canGoForward: Bool
    }

    struct Summary: Equatable {
        var goal: Int
        var today: Day
        /// Số ngày thực sự có luyện trong mạch hiện tại.
        var streak: Int
        var best: Int
        /// Tuần này, thứ Hai đến Chủ nhật.
        var week: [DayStatus]
        /// Mạch hiện tại đang phải nhờ một ngày nghỉ bù.
        var usedGrace: Bool
        /// Tổng số ngày đã được tính vào chuỗi.
        var totalDays: Int

        /// Hôm nay đã nói đủ mức tối thiểu, chuỗi đã được tính.
        var activeToday: Bool { today.sentences >= StreakStore.streakMinimum }
        /// Còn bấy nhiêu câu nữa để hôm nay được tính vào chuỗi.
        var toKeepStreak: Int { max(StreakStore.streakMinimum - today.sentences, 0) }
        var doneToday: Bool { today.sentences >= goal }
        var remaining: Int { max(goal - today.sentences, 0) }
        var progress: Double { goal > 0 ? min(Double(today.sentences) / Double(goal), 1) : 1 }
    }

    /// Các mốc đáng ăn mừng.
    static let milestones = [3, 7, 14, 30, 50, 100, 150, 200, 365]
    private static let celebratedKey = "celebratedMilestone"

    /// Mốc mới vừa chạm tới mà chưa ăn mừng, nil là chưa có gì để mừng.
    static func pendingMilestone(streak: Int) -> Int? {
        var celebrated = store.integer(forKey: celebratedKey)
        if streak < celebrated {
            // Mạch đứt rồi gây dựng lại: mở khoá để những mốc cũ được mừng lần nữa —
            // đó đúng là lúc người học cần được động viên nhất.
            celebrated = milestones.last { $0 <= streak } ?? 0
            store.set(celebrated, forKey: celebratedKey)
        }
        // Mừng lần lượt từng mốc, không nhảy cóc khi chuỗi vọt lên.
        return milestones.first { $0 > celebrated && $0 <= streak }
    }

    static func markCelebrated(_ milestone: Int) {
        store.set(max(milestone, store.integer(forKey: celebratedKey)), forKey: celebratedKey)
    }

    /// Nói đủ bấy nhiêu câu trong ngày là ngày đó được tính vào chuỗi. Mục tiêu ngày là chuyện
    /// riêng: chuỗi chỉ đòi một chút mỗi ngày, để ngày bận vẫn giữ được nhịp.
    static let streakMinimum = 5

    static let goalKey = "dailyGoalSentences"
    static let defaultGoal = 100
    static let goalChoices = [30, 50, 100, 150]
    private static let goalRaisedKey = "dailyGoalRaisedTo100"

    /// Mục tiêu cũ (5–30 câu) quá thấp so với nhịp mới 100 câu/ngày: nâng lên một lần.
    /// Sau đó người dùng vẫn tự chỉnh được trong màn Chuỗi ngày.
    static func raiseGoalIfNeeded() {
        guard !store.bool(forKey: goalRaisedKey) else { return }
        store.set(true, forKey: goalRaisedKey)
        if store.integer(forKey: goalKey) < defaultGoal {
            goal = defaultGoal
        }
    }

    private static let logKey = "dailyLog"
    private static let bestKey = "bestStreak"
    /// Giữ nhật ký bấy nhiêu ngày gần nhất.
    private static let keepDays = 400

    private static var store: UserDefaults { SharedSettings.store }
    /// SwiftUI dựng lại View rất nhiều lần; nhớ tạm theo ngày để khỏi giải mã nhật ký mỗi lần.
    private static var cache: (day: String, goal: Int, summary: Summary)?

    static var goal: Int {
        get {
            let stored = store.integer(forKey: goalKey)
            return stored > 0 ? stored : defaultGoal
        }
        set {
            store.set(max(newValue, 1), forKey: goalKey)
            cache = nil
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Khoá của một ngày theo múi giờ máy — "ngày" phải là ngày của người dùng.
    static func dayKey(_ date: Date) -> String { formatter.string(from: date) }

    /// Lịch bắt đầu từ thứ Hai, cho khớp cách người Việt đọc tuần. Ghim lịch Gregorian
    /// để luôn cùng hệ với khoá ngày "yyyy-MM-dd", máy đặt lịch nào cũng vậy.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    private static func status(_ date: Date, goal: Int, log: [String: Day], today: Date) -> DayStatus {
        let calendar = self.calendar
        let key = dayKey(date)
        let record = log[key]
        let todayKey = dayKey(today)
        let target = key == todayKey ? goal : (record?.goal ?? defaultGoal)
        return DayStatus(
            key: key,
            date: date,
            number: calendar.component(.day, from: date),
            sentences: record?.sentences ?? 0,
            done: (record?.sentences ?? 0) >= streakMinimum,
            goalMet: (record?.sentences ?? 0) >= target,
            isToday: key == todayKey,
            isFuture: date > today
        )
    }

    /// Lịch một tháng để xem lại cả chặng đã đi.
    static func monthGrid(containing date: Date) -> MonthGrid {
        let calendar = self.calendar
        let log = load()
        let goal = self.goal
        let today = calendar.startOfDay(for: Date())

        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            return MonthGrid(title: "", cells: [], canGoForward: false)
        }
        let first = interval.start

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "'Tháng' M, yyyy"

        // Thứ Hai = 0 … Chủ nhật = 6.
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        var cells: [DayStatus?] = Array(repeating: nil, count: leading)

        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            cells.append(status(day, goal: goal, log: log, today: today))
        }

        let canGoForward = interval.end <= today
        return MonthGrid(title: formatter.string(from: first), cells: cells, canGoForward: canGoForward)
    }

    private static func load() -> [String: Day] {
        guard let data = store.data(forKey: logKey),
              let map = try? JSONDecoder().decode([String: Day].self, from: data)
        else { return [:] }
        return map
    }

    private static func save(_ map: [String: Day]) {
        var map = map
        if map.count > keepDays {
            let keep = Set(map.keys.sorted().suffix(keepDays))
            map = map.filter { keep.contains($0.key) }
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        store.set(data, forKey: logKey)
        cache = nil
        let current = streak(log: map)
        if current > store.integer(forKey: bestKey) {
            store.set(current, forKey: bestKey)
        }
        NotificationCenter.default.post(name: .streakChanged, object: nil)
    }

    /// Người học vừa nói xong một câu tiếng Trung.
    static func addSentence(_ count: Int = 1) {
        guard count > 0 else { return }
        var map = load()
        let key = dayKey(Date())
        var day = map[key] ?? Day()
        day.sentences += count
        day.goal = goal
        map[key] = day
        save(map)
    }

    static func addSeconds(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        var map = load()
        let key = dayKey(Date())
        var day = map[key] ?? Day()
        day.seconds += seconds
        if day.goal == nil { day.goal = goal }
        map[key] = day
        save(map)
    }

    /// Số ngày có luyện (đủ `streakMinimum` câu) trong mạch hiện tại. Lỡ một ngày thì mạch vẫn sống,
    /// nghỉ hai ngày liền mới tính là đứt — để lỡ một hôm không thành cớ bỏ hẳn.
    static func streak(log: [String: Day]? = nil) -> Int {
        let map = log ?? load()
        let calendar = Calendar.current
        func done(_ date: Date) -> Bool {
            (map[dayKey(date)]?.sentences ?? 0) >= streakMinimum
        }

        var day = calendar.startOfDay(for: Date())
        if !done(day) {
            // Hôm nay chưa đạt thì chưa tính là lỡ: ngày còn chưa hết.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        var count = 0
        var gap = 0
        for _ in 0..<keepDays {
            if done(day) {
                count += 1
                gap = 0
            } else {
                gap += 1
                if gap >= 2 { break }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func summary() -> Summary {
        let today = dayKey(Date())
        let goal = self.goal
        // Khoá nhớ tạm gồm cả mục tiêu: màn hình ghi mục tiêu thẳng qua @AppStorage,
        // không đi qua setter nên không có ai xoá nhớ tạm hộ.
        if let cache, cache.day == today, cache.goal == goal { return cache.summary }
        let map = load()
        let calendar = self.calendar
        let startOfToday = calendar.startOfDay(for: Date())

        // Tuần này, thứ Hai đến Chủ nhật.
        var week: [DayStatus] = []
        if let interval = calendar.dateInterval(of: .weekOfYear, for: startOfToday) {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { continue }
                week.append(status(day, goal: goal, log: map, today: startOfToday))
            }
        }

        let totalDays = map.values.filter { $0.sentences >= streakMinimum }.count

        // Đang nhờ ngày nghỉ bù: mạch còn sống nhưng hôm qua đã nghỉ và hôm nay chưa nói —
        // tức là hôm nay không nói nữa thì đứt.
        let count = streak(log: map)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
        let activeToday = (map[today]?.sentences ?? 0) >= streakMinimum
        let activeYesterday = yesterday.map { (map[dayKey($0)]?.sentences ?? 0) >= streakMinimum } ?? false

        let summary = Summary(
            goal: goal,
            today: map[today] ?? Day(),
            streak: count,
            best: store.integer(forKey: bestKey),
            week: week,
            usedGrace: count > 0 && !activeToday && !activeYesterday,
            totalDays: totalDays
        )
        cache = (today, goal, summary)
        return summary
    }
}

/// Cài đặt dùng chung giữa app và bàn phím (App Group).
enum SharedSettings {
    static let showHanVietKey = "showHanViet"
    static let politeKey = "politeRegister"
    static let speechPaceKey = "speechPace"
    static let pendingVoiceStartKey = "pendingVoiceStart"
    static let keyboardVoiceModeKey = "keyboardVoiceMode"
    static let keyboardReadingSelectedKey = "keyboardReadingSelected"
    static let keyboardLastReadingKey = "keyboardLastReading"

    /// Tin nhắn đã copy được đọc gần nhất trên bàn phím, để mở lại bàn phím vẫn thấy.
    struct LastReading: Codable {
        let message: String
        let meaning: String
        let failed: Bool
    }

    static var store: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static var showHanViet: Bool {
        get { store.object(forKey: showHanVietKey) as? Bool ?? false }
        set { store.set(newValue, forKey: showHanVietKey) }
    }

    static var polite: Bool {
        get { store.object(forKey: politeKey) as? Bool ?? false }
        set {
            store.set(newValue, forKey: politeKey)
            store.synchronize()
        }
    }

    /// Người dùng chạm micro lúc app chưa sẵn sàng. Lưu lại ý định đó để khi app bật
    /// micro xong và họ quay về bàn phím thì ghi âm chạy luôn, khỏi phải chạm lần nữa.
    /// Phải để ở App Group chứ không giữ trong bộ nhớ: bàn phím hay bị iOS dẹp khi
    /// người dùng rời khỏi app đang gõ.
    static var pendingVoiceStart: Date? {
        get { store.object(forKey: pendingVoiceStartKey) as? Date }
        set { store.set(newValue, forKey: pendingVoiceStartKey) }
    }

    // Nút người dùng chọn trên thanh bàn phím, nhớ cho lần mở sau. Ghi xuống đĩa ngay vì
    // iOS có thể dẹp tiến trình bàn phím bất cứ lúc nào, trước khi UserDefaults kịp tự lưu.

    static var keyboardVoiceMode: VoiceMode? {
        get { store.string(forKey: keyboardVoiceModeKey).flatMap(VoiceMode.init(rawValue:)) }
        set {
            store.set(newValue?.rawValue, forKey: keyboardVoiceModeKey)
            store.synchronize()
        }
    }

    static var keyboardReadingSelected: Bool {
        get { store.bool(forKey: keyboardReadingSelectedKey) }
        set {
            store.set(newValue, forKey: keyboardReadingSelectedKey)
            store.synchronize()
        }
    }

    static var keyboardLastReading: LastReading? {
        get { store.data(forKey: keyboardLastReadingKey).flatMap { try? JSONDecoder().decode(LastReading.self, from: $0) } }
        set {
            store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: keyboardLastReadingKey)
            store.synchronize()
        }
    }

    static var speechPace: SpeechPace {
        get { SpeechPace(rawValue: store.string(forKey: speechPaceKey) ?? "") ?? .normal }
        set { store.set(newValue.rawValue, forKey: speechPaceKey) }
    }
}

struct VoiceState: Codable, Equatable {
    enum Phase: String, Codable {
        case idle, listening, processing, result, error
    }

    /// App chính đang giữ micro mở để bàn phím dùng.
    var sessionActive = false
    var heartbeat = Date.distantPast
    var requestID: UUID?
    var phase: Phase = .idle
    var mode: VoiceMode = .vietnamese
    var partialText = ""
    var sourceText = ""
    var chineseText = ""
    var pinyin = ""
    var pinyinWords: [PinyinWord] = []
    /// Dịch trực tiếp trong lúc đang nói: tiếng Trung tạm (chế độ VI→中) và pinyin từng từ.
    var liveChinese = ""
    var liveWords: [PinyinWord] = []
    /// Chế độ 中文: nghĩa tiếng Việt của câu tiếng Trung máy nghe được (tạm khi đang nói, và bản cuối),
    /// để người học biết mình nói đúng ý chưa và người đọc sẽ hiểu thế nào.
    var liveMeaning = ""
    var meaning = ""
    var errorMessage = ""
    var level: Float = 0

    var isAlive: Bool {
        sessionActive && Date().timeIntervalSince(heartbeat) < 4
    }
}

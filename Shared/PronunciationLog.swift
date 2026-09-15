//
//  PronunciationLog.swift
//  Ghi lại chỗ người học đọc sai ở mọi màn hình (luyện nói, hội thoại, bàn phím) và tách lỗi
//  thành thanh mẫu, vận mẫu, thanh điệu. Dùng chung giữa app và bàn phím qua App Group.
//

import Foundation

/// Một âm tiết pinyin tách thành ba phần.
struct PinyinSyllable: Equatable {
    /// Thanh mẫu; rỗng khi âm tiết không có phụ âm đầu (a, ai, yi, wu…).
    let initial: String
    /// Vận mẫu dạng đầy đủ: iou, uei, uen, ü… (không phải dạng viết tắt iu, ui, un, u sau j q x).
    let final: String
    /// 1–4; 5 là thanh nhẹ.
    let tone: Int

    static let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                           "j", "q", "x", "r", "z", "c", "s"]
    /// Sau các thanh mẫu này, "i" là âm ư đầu lưỡi chứ không phải i.
    static let apicalInitials: Set<String> = ["zh", "ch", "sh", "r", "z", "c", "s"]
    static let finals: Set<String> = [
        "a", "o", "e", "i", "-i", "u", "ü", "er", "ê",
        "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong",
        "ia", "ie", "iao", "iou", "ian", "in", "iang", "ing", "iong",
        "ua", "uo", "uai", "uei", "uan", "uen", "uang", "ueng",
        "üe", "üan", "ün",
    ]

    private static let marks: [Character: (Character, Int)] = [
        "ā": ("a", 1), "á": ("a", 2), "ǎ": ("a", 3), "à": ("a", 4),
        "ō": ("o", 1), "ó": ("o", 2), "ǒ": ("o", 3), "ò": ("o", 4),
        "ē": ("e", 1), "é": ("e", 2), "ě": ("e", 3), "è": ("e", 4),
        "ī": ("i", 1), "í": ("i", 2), "ǐ": ("i", 3), "ì": ("i", 4),
        "ū": ("u", 1), "ú": ("u", 2), "ǔ": ("u", 3), "ù": ("u", 4),
        "ǖ": ("ü", 1), "ǘ": ("ü", 2), "ǚ": ("ü", 3), "ǜ": ("ü", 4), "ü": ("ü", 0), "v": ("ü", 0),
    ]

    init?(_ text: String) {
        var base = ""
        var tone = 5
        for char in text.lowercased() {
            if let (plain, mark) = Self.marks[char] {
                base.append(plain)
                if mark > 0 { tone = mark }
            } else if char.isLetter, char.isASCII {
                base.append(char)
            }
        }
        guard !base.isEmpty else { return nil }

        var initial = ""
        var rest = base
        if let found = Self.initials.first(where: { base.hasPrefix($0) }) {
            initial = found
            rest = String(base.dropFirst(found.count))
        } else if base.hasPrefix("y") {
            // y, w chỉ là cách viết: yi → i, ya → ia, yu → ü, wu → u, wa → ua…
            let after = base.dropFirst()
            if after.hasPrefix("u") {
                rest = "ü" + after.dropFirst()
            } else if after.hasPrefix("i") {
                rest = String(after)
            } else {
                rest = "i" + after
            }
        } else if base.hasPrefix("w") {
            let after = base.dropFirst()
            rest = after.hasPrefix("u") ? String(after) : "u" + after
        }

        if ["j", "q", "x"].contains(initial), rest.hasPrefix("u") {
            rest = "ü" + rest.dropFirst()
        }
        switch rest {
        case "iu": rest = "iou"
        case "ui": rest = "uei"
        case "un": rest = "uen"
        case "ue": rest = "üe"
        default: break
        }
        if rest == "i", Self.apicalInitials.contains(initial) { rest = "-i" }
        guard Self.finals.contains(rest) else { return nil }

        self.initial = initial
        self.final = rest
        self.tone = tone
    }
}

enum PronunciationPart: String, Codable, CaseIterable, Hashable {
    case initial, final, tone

    var label: String {
        switch self {
        case .initial: "Thanh mẫu"
        case .final: "Vận mẫu"
        case .tone: "Thanh điệu"
        }
    }
}

/// Một lần đọc sai được ghi lại.
struct PronunciationMistake: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case practice, conversation, keyboard, drill

        var label: String {
            switch self {
            case .practice: "Luyện nói"
            case .conversation: "Hội thoại"
            case .keyboard: "Bàn phím"
            case .drill: "Luyện phát âm"
            }
        }
    }

    var id = UUID()
    var date = Date()
    var source: Source
    /// Nhóm các lỗi của cùng một lần chấm, để chấm lại thì thay chứ không cộng dồn.
    var context: String?
    /// Chữ (hoặc từ, với lỗi chưa rõ) lẽ ra phải đọc.
    var zh: String
    /// Pinyin có dấu của `zh`.
    var expected: String
    /// Chữ máy nghe thành; nil khi máy chỉ báo không chắc mà không nghe ra chữ khác.
    var heardZh: String?
    var heard: String?
    /// Những phần đọc sai. Rỗng cùng `heard == nil` là lỗi chưa rõ phần nào.
    var parts: [PronunciationPart]
    /// Câu chứa chữ này, để người học nhớ lại ngữ cảnh.
    var sentence: String

    var isUnclear: Bool { heard == nil }
    var expectedSyllable: PinyinSyllable? { PinyinSyllable(expected) }
    var heardSyllable: PinyinSyllable? { heard.flatMap(PinyinSyllable.init) }
}

extension Notification.Name {
    static let pronunciationLogChanged = Notification.Name("pronunciationLogChanged")
}

enum PronunciationLog {
    private static let fileName = "pronunciation-mistakes.json"
    /// Giữ bấy nhiêu lỗi gần nhất.
    private static let limit = 800

    private static var fileURL: URL? {
        (AppGroup.containerURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)?
            .appendingPathComponent(fileName)
    }

    static func all() -> [PronunciationMistake] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([PronunciationMistake].self, from: data)
        else { return [] }
        return list
    }

    /// Ghi thêm lỗi. Có `context` thì bỏ những lỗi cũ cùng context trước — chấm lại một câu
    /// (ví dụ khi AI tách từ chuẩn hơn) không được đếm cùng một lỗi hai lần.
    static func record(_ mistakes: [PronunciationMistake], replacingContext context: String? = nil) {
        guard !mistakes.isEmpty || context != nil else { return }
        update { list in
            if let context { list.removeAll { $0.context == context } }
            list.append(contentsOf: mistakes)
        }
    }

    static func update(_ change: (inout [PronunciationMistake]) -> Void) {
        var list = all()
        change(&list)
        if list.count > limit { list = Array(list.suffix(limit)) }
        if let fileURL, let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
        let post = { NotificationCenter.default.post(name: .pronunciationLogChanged, object: nil) }
        Thread.isMainThread ? post() : DispatchQueue.main.async(execute: post)
    }
}

enum PronunciationAnalyzer {
    /// So câu mẫu với câu máy nghe được: chữ nào bị nghe thành chữ khác thì so pinyin hai chữ
    /// để biết sai thanh mẫu, vận mẫu hay thanh điệu. Chữ đọc thiếu không tính — thường là
    /// người học dừng giữa chừng, không phải đọc sai.
    static func mistakes(target: String, heard: String, source: PronunciationMistake.Source,
                         context: String? = nil) -> [PronunciationMistake] {
        guard let pairs = align(target: target, heard: heard) else { return [] }
        return pairs.compactMap { pair in
            guard let got = pair.heard, got.char != pair.expected.char,
                  let parts = differences(pair.expected.syllable, got.syllable) else { return nil }
            return PronunciationMistake(
                source: source, context: context, zh: pair.expected.char, expected: pair.expected.syllable,
                heardZh: got.char, heard: got.syllable, parts: parts, sentence: target
            )
        }
    }

    /// Luyện lại một lỗi: chữ đó phải được nghe ra đúng — cùng chữ, hoặc chữ đồng âm cùng thanh điệu.
    /// Chặt hơn chấm câu thông thường: 买 nghe thành 卖 (khác thanh) là chưa đạt.
    static func readsCorrectly(_ zh: String, in target: String, heard: String) -> Bool {
        guard let pairs = align(target: target, heard: heard) else { return false }
        let chars = zh.filter { ChineseText.containsHan(String($0)) }.map(String.init)
        guard !chars.isEmpty else { return false }
        let expectedChars = pairs.map(\.expected.char)
        // Vị trí của chữ cần luyện trong từ; không tìm thấy thì chấm cả từ.
        var positions = Array(expectedChars.indices)
        if chars.count <= expectedChars.count {
            for start in 0...(expectedChars.count - chars.count)
            where Array(expectedChars[start..<start + chars.count]) == chars {
                positions = Array(start..<start + chars.count)
                break
            }
        }
        return positions.allSatisfy { index in
            guard let got = pairs[index].heard else { return false }
            return got.char == pairs[index].expected.char || sameSyllable(pairs[index].expected.syllable, got.syllable)
        }
    }

    private static func sameSyllable(_ a: String, _ b: String) -> Bool {
        guard let x = PinyinSyllable(a), let y = PinyinSyllable(b) else { return false }
        return x.initial == y.initial && x.final == y.final && (x.tone == 5 || x.tone == y.tone)
    }

    /// Ghép từng chữ câu mẫu với chữ máy nghe được ở cùng vị trí (nil nếu không ghép được).
    /// Chữ trùng nhau làm mốc; giữa hai mốc, đoạn lệch hai bên dài bằng nhau thì ghép 1-1.
    private static func align(target: String, heard: String)
        -> [(expected: (char: String, syllable: String), heard: (char: String, syllable: String)?)]? {
        let latest = PhraseMatcher.lastAttempt(heard: heard, target: target)
        let expected = ChineseText.syllables(for: PhraseMatcher.normalize(target))
        let spoken = ChineseText.syllables(for: PhraseMatcher.normalize(latest))
        guard !expected.isEmpty, !spoken.isEmpty else { return nil }

        let anchors = commonChars(expected.map(\.char), spoken.map(\.char))
        // Nghe ra câu khác hẳn (đọc nhầm câu, hoặc máy đoán bừa): đừng ghép bậy thành lỗi.
        guard anchors.count * 2 >= expected.count || expected.count <= 2 else { return nil }

        var matched = [Int?](repeating: nil, count: expected.count)
        var i = 0, j = 0
        for (anchorI, anchorJ) in anchors + [(expected.count, spoken.count)] {
            if anchorI - i == anchorJ - j {
                for k in 0..<(anchorI - i) { matched[i + k] = j + k }
            }
            if anchorI < expected.count { matched[anchorI] = anchorJ }
            i = anchorI + 1
            j = anchorJ + 1
        }
        return expected.indices.map { index in
            (expected[index], matched[index].map { spoken[$0] })
        }
    }

    /// Những từ máy gắn cờ không chắc mà không nghe ra chữ nào khác: chưa rõ sai phần nào.
    static func unclear(words: [PinyinWord], sentence: String, source: PronunciationMistake.Source,
                        context: String? = nil) -> [PronunciationMistake] {
        words.compactMap { word in
            guard word.flagged == true else { return nil }
            let zh = word.zh.filter { ChineseText.containsHan(String($0)) }
            guard !zh.isEmpty else { return nil }
            let pinyin = ChineseText.syllables(for: zh).map(\.syllable).joined(separator: " ")
            return PronunciationMistake(source: source, context: context, zh: zh, expected: pinyin,
                                        parts: [], sentence: sentence)
        }
    }

    /// Phần nào khác nhau giữa hai âm tiết. nil khi không có gì để ghi: giống nhau (他/她),
    /// không đọc được pinyin, hoặc khác cả ba phần — lúc đó là một chữ khác hẳn chứ không phải đọc sai.
    static func differences(_ expected: String, _ heard: String) -> [PronunciationPart]? {
        guard let want = PinyinSyllable(expected), let got = PinyinSyllable(heard) else { return nil }
        var parts: [PronunciationPart] = []
        if want.initial != got.initial { parts.append(.initial) }
        if want.final != got.final { parts.append(.final) }
        // Thanh nhẹ của câu mẫu đọc sao cũng được.
        if want.tone != 5, want.tone != got.tone { parts.append(.tone) }
        guard !parts.isEmpty, parts.count < 3 else { return nil }
        return parts
    }

    /// Các cặp vị trí khớp chữ theo dãy con chung dài nhất, tăng dần.
    private static func commonChars(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}

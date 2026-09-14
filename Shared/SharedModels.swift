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

/// Cài đặt dùng chung giữa app và bàn phím (App Group).
enum SharedSettings {
    static let showHanVietKey = "showHanViet"
    static let politeKey = "politeRegister"

    static var store: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static var showHanViet: Bool {
        get { store.object(forKey: showHanVietKey) as? Bool ?? false }
        set { store.set(newValue, forKey: showHanVietKey) }
    }

    static var polite: Bool {
        get { store.object(forKey: politeKey) as? Bool ?? false }
        set { store.set(newValue, forKey: politeKey) }
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
    var errorMessage = ""
    var level: Float = 0

    var isAlive: Bool {
        sessionActive && Date().timeIntervalSince(heartbeat) < 4
    }
}

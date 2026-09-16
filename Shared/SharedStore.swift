//
//  SharedStore.swift
//  Trao đổi dữ liệu giữa app và bàn phím qua App Group + Darwin notification.
//

import Foundation

enum SharedStore {
    private static let stateFile = "voice-state.json"
    private static let commandFile = "voice-command.json"
    private static let savedFile = "saved-phrases.json"
    static let firstSavedPhraseID = 1_000_000

    static func readState() -> VoiceState {
        read(VoiceState.self, from: stateFile) ?? VoiceState()
    }

    static func writeState(_ state: VoiceState) {
        write(state, to: stateFile)
        DarwinNotifier.post(DarwinName.state)
    }

    static func readCommand() -> VoiceCommand? {
        read(VoiceCommand.self, from: commandFile)
    }

    static func sendCommand(_ command: VoiceCommand) {
        write(command, to: commandFile)
        DarwinNotifier.post(DarwinName.command)
    }

    static func savedPhrases() -> [SavedPhrase] {
        read([SavedPhrase].self, from: savedFile) ?? []
    }

    @discardableResult
    static func savePhrase(zh: String, vi: String, words: [PinyinWord]) -> SavedPhrase {
        var list = savedPhrases()
        if let existing = list.first(where: { $0.zh == zh }) { return existing }
        let phrase = SavedPhrase(
            id: max(firstSavedPhraseID, (list.map(\.id).max() ?? firstSavedPhraseID)) + 1,
            zh: zh, vi: vi,
            words: words.map { PinyinWord(zh: $0.zh, py: $0.py, hv: $0.hv) },
            savedAt: Date()
        )
        list.append(phrase)
        write(list, to: savedFile)
        return phrase
    }

    /// Ghi lại toàn bộ danh sách sau khi gộp dữ liệu từ iCloud.
    static func replaceSavedPhrases(_ phrases: [SavedPhrase]) {
        write(phrases, to: savedFile)
    }

    static func deleteSavedPhrase(id: Int) {
        write(savedPhrases().filter { $0.id != id }, to: savedFile)
    }

    private static func fileURL(_ name: String) -> URL? {
        AppGroup.containerURL?.appendingPathComponent(name)
    }

    private static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to name: String) {
        guard let url = fileURL(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Thông báo liên tiến trình (app <-> keyboard extension).
final class DarwinNotifier {
    static let shared = DarwinNotifier()

    private var handlers: [String: () -> Void] = [:]
    private let center = CFNotificationCenterGetDarwinNotifyCenter()

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true
        )
    }

    func observe(_ name: String, handler: @escaping () -> Void) {
        removeObserver(name)
        handlers[name] = handler
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
            let key = name.rawValue as String
            DispatchQueue.main.async { notifier.handlers[key]?() }
        }, name as CFString, nil, .deliverImmediately)
    }

    func removeObserver(_ name: String) {
        guard handlers.removeValue(forKey: name) != nil else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(name as CFString), nil)
    }
}

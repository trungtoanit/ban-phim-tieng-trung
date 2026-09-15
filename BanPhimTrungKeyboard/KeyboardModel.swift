//
//  KeyboardModel.swift
//  BanPhimTrungKeyboard
//

import SwiftUI
import UIKit

struct QuickReply: Codable, Hashable {
    var zh: String
    var vi: String
}

/// Gợi ý trả lời nhanh khi tin nhắn nhận được giống một câu trong bộ 1000 câu.
final class QuickReplyStore {
    static let shared = QuickReplyStore()

    private struct Entry: Decodable {
        let zh: String
        let replies: [QuickReply]
    }

    private let lock = NSLock()
    private var entries: [(entry: Entry, key: PhraseMatcher.Key)]?

    private func loadEntries() -> [(entry: Entry, key: PhraseMatcher.Key)] {
        lock.lock()
        defer { lock.unlock() }
        if let entries { return entries }
        var loaded: [(entry: Entry, key: PhraseMatcher.Key)] = []
        if let url = Bundle.main.url(forResource: "replies", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            loaded = list.map { ($0, PhraseMatcher.key($0.zh)) }
        }
        entries = loaded
        return loaded
    }

    /// Gọi ở luồng nền: lần đầu phải tính pinyin cho toàn bộ câu mẫu.
    func replies(for message: String) -> [QuickReply] {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40 else { return [] }
        let messageKey = PhraseMatcher.key(text)
        var best: (score: Double, replies: [QuickReply])?
        for (entry, key) in loadEntries() where abs(entry.zh.count - text.count) <= max(4, text.count / 2) {
            let score = PhraseMatcher.similarity(messageKey, key)
            if score >= 0.7, score > (best?.score ?? 0) {
                best = (score, entry.replies)
            }
        }
        return best?.replies ?? []
    }
}

final class KeyboardModel: ObservableObject {
    enum Display: Equatable {
        case needsFullAccess
        case needsActivation
        case openingApp
        case ready
        /// `live`: tiếng Trung (kèm pinyin) hiện ngay trong lúc đang nói.
        case listening(text: String, level: Float, live: [PinyinWord])
        case processing(text: String, live: [PinyinWord])
        case result(words: [PinyinWord], chinese: String, source: String)
        case error(String)
        /// Tin nhắn tiếng Trung đã copy: pinyin + nghĩa (nil khi đang dịch) + gợi ý trả lời.
        case reading(words: [PinyinWord], meaning: String?, failed: Bool, replies: [QuickReply])
        case translatingTyped(source: String)
    }

    struct WordDetail: Equatable {
        var word: PinyinWord
        var meaning: String?
        /// Nghĩa tiếng Việt của từng chữ máy còn nghe thành, để người học biết mình vừa nói ra nghĩa gì.
        var alternativeMeanings: [String: String] = [:]
        /// Vị trí từ trong câu vừa chèn, có khi sửa được bằng phương án khác.
        var index: Int?
    }

    private struct ReadingInfo: Equatable {
        var words: [PinyinWord]
        var message: String
        var meaning: String?
        var failed = false
        var replies: [QuickReply] = []
    }

    /// Nội dung tạm che khung giọng nói: đọc tin đã copy, dịch chữ đã gõ, thông báo.
    private enum Panel: Equatable {
        case reading(ReadingInfo)
        case typing(source: String)
        case typed(words: [PinyinWord], chinese: String, source: String)
        case message(String)
    }

    @Published private(set) var state = VoiceState()
    @Published private(set) var appAlive = false
    @Published private(set) var canUndo = false
    @Published private(set) var isOpeningApp = false
    @Published private(set) var clipboardHasNew = false
    @Published private(set) var savedChinese: Set<String> = []
    @Published private(set) var wordDetail: WordDetail?
    @Published private var panel: Panel?
    /// Câu giọng nói sau khi người dùng sửa từ bị đánh dấu đỏ.
    @Published private var correctedWords: [PinyinWord]?
    @Published var hasFullAccess = true
    @Published var needsGlobeKey = true
    @Published var showHanViet = SharedSettings.showHanViet
    @Published var polite = SharedSettings.polite {
        didSet { SharedSettings.polite = polite }
    }
    @Published var mode: VoiceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "voiceMode") }
    }

    weak var controller: KeyboardViewController?

    private var activeRequestID: UUID?
    private var insertedRequestID: UUID?
    /// Chữ vừa chèn và chữ đã bị thay thế (khi dịch chữ đã gõ) để hoàn tác.
    private var lastInserted = ""
    private var lastReplaced = ""
    private var timer: Timer?
    private var panelToken: UUID?
    private var wordToken: UUID?
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var lastPasteboardChange = UIPasteboard.general.changeCount

    init() {
        mode = VoiceMode(rawValue: UserDefaults.standard.string(forKey: "voiceMode") ?? "") ?? .vietnamese
    }

    var display: Display {
        guard hasFullAccess else { return .needsFullAccess }

        switch panel {
        case let .reading(info):
            return .reading(words: info.words, meaning: info.meaning, failed: info.failed, replies: info.replies)
        case let .typing(source):
            return .translatingTyped(source: source)
        case let .typed(words, chinese, source):
            return .result(words: words, chinese: chinese, source: source)
        case let .message(text):
            return .error(text)
        case nil:
            break
        }

        if let requestID = state.requestID, requestID == activeRequestID {
            let busy = state.phase == .listening || state.phase == .processing
            if busy && !appAlive {
                return .error("Mất kết nối với app. Nhấn 🎙 để bật lại micro.")
            }
            switch state.phase {
            case .listening:
                return .listening(text: state.partialText, level: state.level, live: state.liveWords)
            case .processing:
                return .processing(text: state.partialText, live: state.liveWords)
            case .result:
                let words = correctedWords ?? state.pinyinWords
                return .result(words: words, chinese: words.map(\.zh).joined(), source: state.sourceText)
            case .error:
                return .error(state.errorMessage)
            case .idle:
                break
            }
        }
        if appAlive { return .ready }
        return isOpeningApp ? .openingApp : .needsActivation
    }

    /// Câu đang hiện có thể lưu ⭐: (chữ Hán, nghĩa tiếng Việt, từng từ).
    private var saveable: (zh: String, vi: String, words: [PinyinWord])? {
        switch panel {
        case let .reading(info):
            return (info.message, info.failed ? "" : info.meaning ?? "", info.words)
        case let .typed(words, chinese, source):
            return (chinese, source, words)
        case .typing, .message:
            return nil
        case nil:
            guard case let .result(words, chinese, source) = display else { return nil }
            return (chinese, source == chinese ? "" : source, words)
        }
    }

    var canSave: Bool { saveable != nil }

    /// Đọc to câu tiếng Trung đang hiện để nghe thử trước khi gửi.
    func speakCurrent() {
        guard let zh = saveable?.zh, !zh.isEmpty else { return }
        haptic.impactOccurred()
        NaturalSpeaker.chinese.speak(zh)
    }

    var isCurrentSaved: Bool {
        guard let zh = saveable?.zh else { return false }
        return savedChinese.contains(zh)
    }

    // MARK: - Vòng đời

    func start() {
        showHanViet = SharedSettings.showHanViet
        if polite != SharedSettings.polite { polite = SharedSettings.polite }
        savedChinese = Set(SharedStore.savedPhrases().map(\.zh))

        DarwinNotifier.shared.observe(DarwinName.state) { [weak self] in
            self?.refresh()
        }
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        if let requestID = activeRequestID, state.requestID == requestID, state.phase == .listening {
            send(.cancel, requestID: requestID)
        }
        activeRequestID = nil
        closePanels()
        timer?.invalidate()
        timer = nil
        DarwinNotifier.shared.removeObserver(DarwinName.state)
    }

    private func refresh() {
        guard hasFullAccess else { return }
        let newState = SharedStore.readState()
        if newState != state { state = newState }
        let alive = newState.isAlive
        if alive != appAlive { appAlive = alive }
        if alive { resumePendingStart() }

        // changeCount không đọc nội dung clipboard nên không làm iOS hiện thông báo dán.
        let pasteboard = UIPasteboard.general
        if pasteboard.changeCount != lastPasteboardChange, pasteboard.hasStrings, !clipboardHasNew {
            clipboardHasNew = true
        }

        if newState.phase == .result,
           let requestID = newState.requestID,
           requestID == activeRequestID,
           insertedRequestID != requestID,
           !newState.chineseText.isEmpty {
            insertedRequestID = requestID
            correctedWords = nil
            controller?.insert(newState.chineseText)
            lastInserted = newState.chineseText
            lastReplaced = ""
            canUndo = true
            haptic.impactOccurred()
        }
    }

    // MARK: - Giọng nói

    func micTapped() {
        guard hasFullAccess else { return }
        haptic.impactOccurred()
        closePanels()
        correctedWords = nil

        guard appAlive else {
            // Nhớ ý định này lại: mở app xong quay về đây là ghi âm luôn.
            SharedSettings.pendingVoiceStart = Date()
            isOpeningApp = true
            controller?.openContainingApp()
            return
        }

        if case .listening = display, let requestID = activeRequestID {
            send(.stop, requestID: requestID)
        } else if case .processing = display {
            return
        } else {
            beginListening()
        }
    }

    private func beginListening() {
        let requestID = UUID()
        activeRequestID = requestID
        send(.start, requestID: requestID)
    }

    /// Micro đã sẵn sàng: nếu trước đó người dùng chạm micro mà phải đi mở app thì nối lại
    /// đúng việc họ định làm, thay vì bắt chạm thêm lần nữa.
    private func resumePendingStart() {
        isOpeningApp = false
        guard let pending = SharedSettings.pendingVoiceStart else { return }
        SharedSettings.pendingVoiceStart = nil

        // Để lâu quá thì người dùng đã quên chuyện này rồi, tự mở micro chỉ làm họ giật mình.
        guard Date().timeIntervalSince(pending) < 120 else { return }
        // Đang bận dở việc gì thì đừng chen ngang.
        switch display {
        case .ready:
            haptic.impactOccurred()
            beginListening()
        default:
            return
        }
    }

    func select(_ newMode: VoiceMode) {
        mode = newMode
    }

    private func send(_ action: VoiceCommand.Action, requestID: UUID) {
        SharedStore.sendCommand(VoiceCommand(requestID: requestID, action: action, mode: mode, sentAt: Date(), polite: polite))
    }

    // MARK: - Hiểu tin nhắn đã copy

    func readClipboard() {
        guard hasFullAccess else { return }
        haptic.impactOccurred()
        closePanels()

        let pasteboard = UIPasteboard.general
        lastPasteboardChange = pasteboard.changeCount
        clipboardHasNew = false

        let text = (pasteboard.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            panel = .message("Chưa có tin nào được copy. Nhấn giữ tin nhắn tiếng Trung → Sao chép, rồi nhấn 📋 lần nữa.")
            return
        }
        guard ChineseText.containsHan(text) else {
            panel = .message("Nội dung đã copy không có chữ Hán.")
            return
        }

        let message = String(text.prefix(300))
        let token = UUID()
        panelToken = token
        panel = .reading(ReadingInfo(words: ChineseText.words(for: message), message: message))

        Task {
            let meaning = try? await Translator.translate(message, from: "zh-CN", to: "vi")
            DispatchQueue.main.async { [weak self] in
                self?.updateReading(token: token) { info in
                    info.meaning = meaning ?? "Không dịch được nghĩa — kiểm tra kết nối mạng."
                    info.failed = meaning == nil
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let replies = QuickReplyStore.shared.replies(for: message)
            DispatchQueue.main.async {
                self?.updateReading(token: token) { $0.replies = replies }
            }
        }
    }

    private func updateReading(token: UUID, _ change: (inout ReadingInfo) -> Void) {
        guard panelToken == token, case var .reading(info) = panel else { return }
        change(&info)
        panel = .reading(info)
    }

    func insertReply(_ reply: QuickReply) {
        guard let controller else { return }
        controller.insert(reply.zh)
        lastInserted = reply.zh
        lastReplaced = ""
        canUndo = true
        haptic.impactOccurred()
    }

    // MARK: - Dịch chữ tiếng Việt đã gõ

    func translateTyped() {
        guard hasFullAccess, let controller else { return }
        haptic.impactOccurred()
        closePanels()

        let original = controller.textBeforeCursor
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            panel = .message("Hãy gõ tiếng Việt vào ô chat trước (bằng bàn phím tiếng Việt), rồi chuyển sang Bàn Phím Trung và nhấn “Dịch chữ gõ”.")
            return
        }
        guard !ChineseText.containsHan(source) else {
            panel = .message("Ô chat đã có chữ Hán. Nút này dùng để dịch phần tiếng Việt vừa gõ.")
            return
        }

        let token = UUID()
        panelToken = token
        panel = .typing(source: source)
        let polite = self.polite

        Task {
            // `let` để closure gửi về luồng chính không bắt biến có thể đổi (lỗi trong Swift 6).
            let translated: String?
            let failure: String?
            do {
                translated = try await Translator.translate(source, from: "vi", to: "zh-CN")
                failure = nil
            } catch {
                // Nói rõ máy chủ trả gì, nếu không lần nào hỏng cũng chỉ biết đổ cho mạng.
                translated = nil
                failure = error.localizedDescription
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panelToken == token else { return }
                guard let translated else {
                    self.panel = .message("Không dịch được — \(failure ?? "kiểm tra kết nối mạng").")
                    return
                }
                // Chỉ thay khi nội dung ô chat vẫn như lúc bắt đầu dịch.
                guard controller.textBeforeCursor == original else {
                    self.panel = .message("Nội dung ô chat đã thay đổi, hãy nhấn “Dịch chữ gõ” lại.")
                    return
                }
                let chinese = ChineseRegister.apply(translated, polite: polite)
                for _ in original { controller.deleteBackward() }
                controller.insert(chinese)
                self.lastInserted = chinese
                self.lastReplaced = original
                self.canUndo = true
                self.panel = .typed(words: ChineseText.words(for: chinese), chinese: chinese, source: source)
                self.haptic.impactOccurred()
            }
        }
    }

    // MARK: - Chạm vào từ

    func showWord(_ word: PinyinWord) {
        let text = RubyText.splitPunctuation(word.zh).core
        guard !text.isEmpty else { return }
        NaturalSpeaker.chinese.speak(text)
        var index: Int?
        if panel == nil, case let .result(words, _, _) = display, word.flagged == true,
           !(word.alternatives ?? []).isEmpty {
            index = words.firstIndex(of: word)
        }
        wordDetail = WordDetail(word: word, index: index)

        let token = UUID()
        wordToken = token
        Task {
            let meaning = try? await Translator.translate(text, from: "zh-CN", to: "vi")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wordToken == token else { return }
                self.wordDetail?.meaning = meaning ?? "Không tra được nghĩa — kiểm tra kết nối mạng."
            }
        }
        for alternative in (word.alternatives ?? []).prefix(3) {
            Task {
                let meaning = try? await Translator.translate(alternative, from: "zh-CN", to: "vi")
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.wordToken == token, let meaning else { return }
                    self.wordDetail?.alternativeMeanings[alternative] = meaning
                }
            }
        }
    }

    /// Thay từ bị đánh dấu đỏ trong câu vừa chèn bằng chữ đúng ý người dùng.
    func replaceWord(with replacement: String) {
        guard let controller, let index = wordDetail?.index,
              case let .result(currentWords, chinese, _) = display, index < currentWords.count
        else { return }
        guard chinese == lastInserted, controller.textBeforeCursor.hasSuffix(lastInserted) else {
            closeWord()
            panel = .message("Câu trong ô chat đã thay đổi nên không sửa tự động được. Hãy sửa tay chữ màu đỏ.")
            return
        }

        var words = currentWords
        let original = words[index]
        let parts = RubyText.splitPunctuation(original.zh)
        let offset = words[..<index].reduce(0) { $0 + $1.zh.count }
        let charactersAfter = chinese.count - offset - parts.core.count

        controller.moveCursor(by: -charactersAfter)
        for _ in parts.core { controller.deleteBackward() }
        controller.insert(replacement)
        controller.moveCursor(by: charactersAfter)

        let converted = ChineseText.words(for: replacement)
        var pinyin = converted.map(\.py).joined()
        if index > 0, let first = pinyin.first { pinyin = first.lowercased() + pinyin.dropFirst() }
        let trailingPunctuation = String(original.py.reversed().prefix { $0.isPunctuation }.reversed())
        let hanViet = converted.compactMap(\.hv).joined(separator: " ")
        words[index] = PinyinWord(zh: replacement + parts.trailing, py: pinyin + trailingPunctuation,
                                  hv: hanViet.isEmpty ? nil : hanViet)

        // Người dùng chọn lại chữ đúng ý: máy đã nghe thành chữ khác, tức là biết chính xác sai ở đâu.
        let core = parts.core
        let heardSentence = chinese
        PronunciationLog.update { list in
            list.removeAll { $0.source == .keyboard && $0.isUnclear && $0.zh == core && $0.sentence == heardSentence }
            list.append(contentsOf: PronunciationAnalyzer.mistakes(target: replacement, heard: core, source: .keyboard)
                .map { mistake in
                    var mistake = mistake
                    mistake.sentence = heardSentence
                    return mistake
                })
        }

        correctedWords = words
        lastInserted = words.map(\.zh).joined()
        lastReplaced = ""
        canUndo = true
        haptic.impactOccurred()
        closeWord()
    }

    func speakWord() {
        guard let word = wordDetail?.word else { return }
        NaturalSpeaker.chinese.speak(RubyText.splitPunctuation(word.zh).core)
    }

    func closeWord() {
        wordToken = nil
        wordDetail = nil
        NaturalSpeaker.chinese.stop()
    }

    func closePanels() {
        panelToken = nil
        panel = nil
        closeWord()
    }

    // MARK: - Lưu câu

    func saveCurrent() {
        guard let item = saveable, !savedChinese.contains(item.zh) else { return }
        haptic.impactOccurred()
        savedChinese.insert(item.zh)

        guard item.vi.isEmpty else {
            SharedStore.savePhrase(zh: item.zh, vi: item.vi, words: item.words)
            return
        }
        Task {
            let meaning = try? await Translator.translate(item.zh, from: "zh-CN", to: "vi")
            DispatchQueue.main.async {
                SharedStore.savePhrase(zh: item.zh, vi: meaning ?? "", words: item.words)
            }
        }
    }

    // MARK: - Phím

    func insert(_ text: String) {
        controller?.insert(text)
        canUndo = false
    }

    func deleteBackward() {
        controller?.deleteBackward()
        canUndo = false
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func undo() {
        guard canUndo, let controller else { return }
        let before = controller.textBeforeCursor
        if before.hasSuffix(lastInserted) || before.isEmpty {
            for _ in lastInserted { controller.deleteBackward() }
            if !lastReplaced.isEmpty { controller.insert(lastReplaced) }
        }
        canUndo = false
        lastInserted = ""
        lastReplaced = ""
    }
}

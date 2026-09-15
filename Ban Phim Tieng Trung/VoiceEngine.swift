//
//  VoiceEngine.swift
//  Ban Phim Tieng Trung
//
//  iOS không cho keyboard extension dùng micro, nên app chính giữ micro mở
//  (chế độ nền "audio") và nhận lệnh ghi âm từ bàn phím qua App Group.
//

import AVFoundation
import Speech
import UIKit

struct HistoryItem: Identifiable {
    let id = UUID()
    let source: String
    let chinese: String
    let words: [PinyinWord]
}

/// Nhận buffer âm thanh trên luồng audio và chuyển cho yêu cầu nhận dạng hiện tại.
final class AudioTapSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var lastLevelTime: CFAbsoluteTime = 0
    var onLevel: ((Float) -> Void)?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        guard let request else { return }
        request.append(buffer)

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelTime > 0.1 else { return }
        lastLevelTime = now
        onLevel?(Self.level(of: buffer))
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 0.000_01))
        return max(0, min(1, (decibels + 50) / 45))
    }
}

final class VoiceEngine: ObservableObject {
    static let shared = VoiceEngine()
    static let keepAliveKey = "keepAliveMinutes"
    static let scriptKey = "chineseScript"

    @Published private(set) var state = VoiceState()
    @Published private(set) var history: [HistoryItem] = []

    private let audioEngine = AVAudioEngine()
    private let sink = AudioTapSink()
    private var tapInstalled = false
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    /// Mỗi ký tự (không tính khoảng trắng) của câu nghe được: máy có kém chắc chắn không.
    private var latestUncertain: [Bool] = []
    private var latestAlternatives: [String] = []
    private var liveWork: DispatchWorkItem?
    /// Câu tiếng Việt (hoặc tiếng Trung) đã được dịch trực tiếp gần nhất.
    private var liveSource = ""
    private var liveInFlight = false
    /// Câu tiếng Việt ứng với `state.liveChinese` đang hiện (có thể cũ hơn `liveSource` khi yêu cầu mới chưa về).
    private var liveTranslatedSource = ""
    private var polite = false
    private var finalizedRequestID: UUID?
    private var lastCommandKey = ""
    private var heartbeatTimer: Timer?
    private var lastActivity = Date()
    private var observers: [NSObjectProtocol] = []

    private var keepAliveSeconds: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: Self.keepAliveKey)
        return TimeInterval((minutes > 0 ? minutes : 15) * 60)
    }

    private var script: ChineseScript {
        ChineseScript(rawValue: UserDefaults.standard.string(forKey: Self.scriptKey) ?? "") ?? .simplified
    }

    private init() {
        NaturalSpeaker.isMicSessionActive = { VoiceEngine.shared.state.sessionActive }
        sink.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.updateLevel(level) }
        }
        DarwinNotifier.shared.observe(DarwinName.command) { [weak self] in
            self?.handleCommand()
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began,
                  self?.state.sessionActive == true
            else { return }
            self?.deactivate(reason: "Micro bị gián đoạn (cuộc gọi, Siri…). Nhấn 🎙 để bật lại.")
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.deactivate()
        })

        SharedStore.writeState(state)
    }

    // MARK: - Phiên micro

    func activate() {
        lastActivity = Date()
        if state.sessionActive && audioEngine.isRunning { return }

        Self.requestPermissions { [weak self] error in
            guard let self else { return }
            if let error {
                self.showError(error)
                return
            }
            do {
                try self.startAudio()
                self.state.sessionActive = true
                self.state.phase = .idle
                self.state.requestID = nil
                self.state.errorMessage = ""
                self.state.heartbeat = Date()
                self.startHeartbeat()
                self.publish()
            } catch {
                self.deactivate(reason: "Không bật được micro: \(error.localizedDescription)")
            }
        }
    }

    func deactivate(reason: String? = nil) {
        resetRecognition()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        state.sessionActive = false
        state.level = 0
        if let reason {
            state.phase = .error
            state.errorMessage = reason
        } else {
            state.phase = .idle
            state.requestID = nil
        }
        publish()
    }

    static func requestPermissions(_ completion: @escaping (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion("Chưa cấp quyền Nhận dạng giọng nói. Hãy bật trong Cài đặt.")
                    return
                }
                let handler: (Bool) -> Void = { granted in
                    DispatchQueue.main.async {
                        completion(granted ? nil : "Chưa cấp quyền Micro. Hãy bật trong Cài đặt.")
                    }
                }
                if #available(iOS 17.0, *) {
                    AVAudioApplication.requestRecordPermission(completionHandler: handler)
                } else {
                    AVAudioSession.sharedInstance().requestRecordPermission(handler)
                }
            }
        }
    }

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        try installTap()
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func installTap() throws {
        let input = audioEngine.inputNode
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "VoiceEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy micro"])
        }
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.handle(buffer)
        }
        tapInstalled = true
    }

    private func restartAfterConfigurationChange() {
        guard state.sessionActive else { return }
        do {
            try installTap()
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            deactivate(reason: "Micro bị ngắt. Nhấn 🎙 trên bàn phím để bật lại.")
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func tick() {
        guard state.sessionActive else { return }
        let busy = state.phase == .listening || state.phase == .processing
        if !busy && Date().timeIntervalSince(lastActivity) > keepAliveSeconds {
            deactivate()
            return
        }
        if !audioEngine.isRunning {
            deactivate(reason: "Micro đã dừng. Nhấn 🎙 để bật lại.")
            return
        }
        state.heartbeat = Date()
        publish()
    }

    // MARK: - Lệnh từ bàn phím

    private func handleCommand() {
        guard let command = SharedStore.readCommand(),
              Date().timeIntervalSince(command.sentAt) < 15
        else { return }
        let key = "\(command.requestID.uuidString)-\(command.action.rawValue)"
        guard key != lastCommandKey else { return }
        lastCommandKey = key
        lastActivity = Date()

        switch command.action {
        case .start:
            polite = command.polite ?? false
            startListening(requestID: command.requestID, mode: command.mode)
        case .stop:
            if command.requestID == state.requestID { stopListening() }
        case .cancel:
            if command.requestID == state.requestID { cancelListening() }
        }
    }

    private func startListening(requestID: UUID, mode: VoiceMode) {
        resetRecognition()
        state.requestID = requestID
        state.mode = mode
        state.partialText = ""
        state.liveChinese = ""
        state.liveWords = []
        state.sourceText = ""
        state.chineseText = ""
        state.pinyin = ""
        state.pinyinWords = []
        state.errorMessage = ""
        state.level = 0

        guard state.sessionActive, audioEngine.isRunning else {
            deactivate(reason: "Micro chưa bật. Nhấn 🎙 để mở app và bật micro.")
            return
        }

        let localeID = mode.speechLocaleID(script: script)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            showError("Nhận dạng \(mode.spokenLanguageName) đang không khả dụng. Kiểm tra mạng rồi thử lại.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        self.recognizer = recognizer
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognition(result: result, error: error, requestID: requestID)
            }
        }
        sink.setRequest(request)
        state.phase = .listening
        publish()

        // Apple giới hạn ~1 phút cho mỗi lần nhận dạng.
        DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [weak self] in
            guard let self, self.state.requestID == requestID, self.state.phase == .listening else { return }
            self.stopListening()
        }
    }

    private func stopListening() {
        guard state.phase == .listening, let requestID = state.requestID else { return }
        sink.setRequest(nil)
        recognitionRequest?.endAudio()
        state.phase = .processing
        state.level = 0
        publish()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.state.requestID == requestID, self.finalizedRequestID != requestID else { return }
            self.finish(text: self.latestTranscript, requestID: requestID)
        }
    }

    private func cancelListening() {
        resetRecognition()
        state.phase = .idle
        state.requestID = nil
        state.partialText = ""
        state.liveChinese = ""
        state.liveWords = []
        state.level = 0
        publish()
    }

    private func resetRecognition() {
        sink.setRequest(nil)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        latestTranscript = ""
        latestUncertain = []
        latestAlternatives = []
        liveWork?.cancel()
        liveWork = nil
        liveSource = ""
        liveInFlight = false
        liveTranslatedSource = ""
    }

    // MARK: - Dịch trực tiếp

    /// Chờ một chút sau mỗi lần nghe thêm chữ rồi mới dịch, để không gửi yêu cầu cho từng âm tiết.
    private func scheduleLiveTranslation(requestID: UUID) {
        liveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.translateLive(requestID: requestID)
        }
        liveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func translateLive(requestID: UUID) {
        guard state.requestID == requestID, state.phase == .listening else { return }
        let source = state.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source != liveSource else { return }

        // Nói thẳng tiếng Trung: chỉ cần hiện pinyin, không phải dịch.
        guard let sourceCode = state.mode.sourceLanguageCode else {
            liveSource = source
            state.liveWords = ChineseText.words(for: source)
            publish()
            return
        }
        // Mỗi lúc chỉ một yêu cầu; xong sẽ tự dịch lại nếu người dùng đã nói thêm.
        guard !liveInFlight else { return }
        liveInFlight = true
        liveSource = source

        let liveTarget = script.translateCode
        let livePolite = polite
        Task {
            let translated = try? await Translator.translate(source, from: sourceCode, to: liveTarget)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.liveInFlight = false
                guard self.state.requestID == requestID,
                      self.state.phase == .listening || self.state.phase == .processing,
                      self.state.chineseText.isEmpty
                else { return }
                if let translated {
                    let text = ChineseRegister.apply(translated, polite: livePolite)
                    self.state.liveChinese = text
                    self.state.liveWords = ChineseText.words(for: text)
                    self.liveTranslatedSource = source
                    self.publish()
                }
                if self.state.phase == .listening {
                    self.translateLive(requestID: requestID)
                }
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, requestID: UUID) {
        guard requestID == state.requestID, finalizedRequestID != requestID else { return }

        if let result {
            latestTranscript = result.bestTranscription.formattedString
            if result.isFinal {
                latestUncertain = Self.uncertainCharacters(in: result.bestTranscription)
                latestAlternatives = result.transcriptions.dropFirst().prefix(4).map(\.formattedString)
            }
            if state.phase == .listening, state.partialText != latestTranscript {
                state.partialText = latestTranscript
                publish()
                scheduleLiveTranslation(requestID: requestID)
            }
            if result.isFinal {
                finish(text: latestTranscript, requestID: requestID)
            }
        } else if error != nil, state.phase == .listening || state.phase == .processing {
            finish(text: latestTranscript, requestID: requestID)
        }
    }

    private func finish(text: String, requestID: UUID) {
        guard finalizedRequestID != requestID else { return }
        finalizedRequestID = requestID
        sink.setRequest(nil)
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        lastActivity = Date()

        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            showError("Không nghe rõ giọng nói, hãy thử lại.", requestID: requestID)
            return
        }

        state.sourceText = source
        state.partialText = source
        state.phase = .processing
        state.level = 0
        publish()

        guard let sourceCode = state.mode.sourceLanguageCode else {
            deliver(chinese: source, requestID: requestID, uncertain: latestUncertain, alternatives: latestAlternatives)
            return
        }
        // Câu cuối trùng câu vừa dịch trực tiếp: chèn luôn, khỏi chờ dịch lại.
        if source == liveTranslatedSource, !state.liveChinese.isEmpty {
            deliver(chinese: state.liveChinese, requestID: requestID)
            return
        }
        let target = script.translateCode
        let polite = self.polite
        Task {
            let chinese = try? await Translator.translate(source, from: sourceCode, to: target)
            DispatchQueue.main.async { [weak self] in
                if let chinese {
                    self?.deliver(chinese: ChineseRegister.apply(chinese, polite: polite), requestID: requestID)
                } else {
                    self?.showError("Không dịch được — kiểm tra kết nối mạng.", requestID: requestID)
                }
            }
        }
    }

    /// Chấm phát âm ở chế độ 中文: đoạn nào máy nhận dạng với độ tin cậy thấp thì đánh dấu.
    private static func uncertainCharacters(in transcription: SFTranscription) -> [Bool] {
        let text = transcription.formattedString as NSString
        var flags = Array(repeating: false, count: text.length)
        for segment in transcription.segments where segment.confidence > 0 && segment.confidence < 0.5 {
            let range = segment.substringRange
            for offset in range.location..<min(range.location + range.length, flags.count) {
                flags[offset] = true
            }
        }
        var result: [Bool] = []
        var offset = 0
        for char in transcription.formattedString {
            let length = String(char).utf16.count
            if !char.isWhitespace {
                result.append(flags[offset..<min(offset + length, flags.count)].contains(true))
            }
            offset += length
        }
        return result
    }

    private func deliver(chinese: String, requestID: UUID, uncertain: [Bool] = [], alternatives: [String] = []) {
        guard requestID == state.requestID else { return }
        state.chineseText = chinese
        state.liveChinese = ""
        state.liveWords = []
        state.pinyinWords = ChineseText.words(for: chinese)
        if uncertain.contains(true) {
            var index = 0
            for w in state.pinyinWords.indices {
                for char in state.pinyinWords[w].zh where !char.isWhitespace {
                    if index < uncertain.count, uncertain[index] { state.pinyinWords[w].flagged = true }
                    index += 1
                }
            }
        }
        if !alternatives.isEmpty {
            state.pinyinWords = PhraseMatcher.markAlternatives(words: state.pinyinWords, alternatives: alternatives)
        }
        if state.pinyinWords.contains(where: { $0.flagged == true }) {
            PronunciationLog.record(PronunciationAnalyzer.unclear(
                words: state.pinyinWords, sentence: chinese, source: .keyboard, context: requestID.uuidString
            ))
        }
        state.pinyin = state.pinyinWords.map(\.py).joined(separator: " ")
        state.phase = .result
        lastActivity = Date()
        publish()

        history.insert(HistoryItem(source: state.sourceText, chinese: chinese, words: state.pinyinWords), at: 0)
        if history.count > 20 { history.removeLast() }
    }

    private func showError(_ message: String, requestID: UUID? = nil) {
        if let requestID, requestID != state.requestID { return }
        sink.setRequest(nil)
        state.phase = .error
        state.errorMessage = message
        state.level = 0
        publish()
    }

    private func updateLevel(_ level: Float) {
        guard state.phase == .listening else { return }
        state.level = level
        publish()
    }

    private func publish() {
        SharedStore.writeState(state)
    }
}

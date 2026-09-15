//
//  NaturalSpeaker.swift
//  Ban Phim Tieng Trung
//
//  Đọc tiếng Việt / tiếng Trung bằng giọng tự nhiên nhất có sẵn: giọng Nâng cao/Cao cấp đã tải
//  trên máy, nếu không có thì dùng giọng Google (cần mạng), lỗi mạng thì quay về giọng của máy.
//

import AVFoundation

final class NaturalSpeaker: NSObject, ObservableObject {
    struct Language {
        /// Tiền tố mã ngôn ngữ của giọng trên máy ("vi", "zh-CN").
        let voicePrefix: String
        let googleCode: String
        let storageKey: String
        let title: String
        let sample: String
        let defaultSpeed: Double
        let settingsLanguageName: String
    }

    static let vietnamese = NaturalSpeaker(language: Language(
        voicePrefix: "vi",
        googleCode: "vi",
        storageKey: "vietnamese",
        title: "Tiếng Việt",
        sample: "Xin chào, mình sẽ đọc nghĩa tiếng Việt để bạn luyện nói nhé.",
        defaultSpeed: 0.9,
        settingsLanguageName: "Tiếng Việt"
    ))

    static let chinese = NaturalSpeaker(language: Language(
        voicePrefix: "zh-CN",
        googleCode: "zh-CN",
        storageKey: "chinese",
        title: "Tiếng Trung",
        sample: "你好，我们一起练习说中文吧。",
        defaultSpeed: 0.85,
        settingsLanguageName: "Tiếng Trung (Trung Quốc đại lục)"
    ))

    static var all: [NaturalSpeaker] { [vietnamese, chinese] }

    /// App gán hàm này để không đụng audio session khi đang giữ micro cho bàn phím.
    static var isMicSessionActive: () -> Bool = { false }

    static let automaticID = ""
    static let googleID = "google"
    static let openAIID = "openai"

    /// App gán: tạo giọng đọc bằng OpenAI (văn bản, mã ngôn ngữ) → dữ liệu MP3. Bàn phím không có.
    static var openAISpeech: ((_ text: String, _ languageCode: String) async throws -> Data)?
    static var hasOpenAIVoice: () -> Bool = { false }
    static let defaultPitch: Double = 1.0

    let language: Language
    var voiceKey: String { "\(language.storageKey)VoiceID" }
    var speedKey: String { "\(language.storageKey)VoiceSpeed" }
    var pitchKey: String { "\(language.storageKey)VoicePitch" }

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var utterance: AVSpeechUtterance?
    private var completion: (() -> Void)?
    /// Đọc tới ký tự thứ mấy trong câu, để tô đậm theo lời đọc.
    private var progressHandler: ((Int) -> Void)?
    private var progressTimer: Timer?
    private var spokenCount = 0
    private var generation = 0
    private var audioCache: [String: Data] = [:]

    private init(language: Language) {
        self.language = language
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Giọng

    var installedVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.voicePrefix) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    /// Giọng Nâng cao / Cao cấp người dùng đã tải trong Cài đặt.
    var bestDownloadedVoice: AVSpeechSynthesisVoice? {
        installedVoices.first { $0.quality != .default }
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "Cao cấp"
        case .enhanced: "Nâng cao"
        default: "Cơ bản"
        }
    }

    /// Giọng thực sự được dùng cho lựa chọn hiện tại.
    func resolvedID(for selectedID: String) -> String {
        if selectedID == Self.googleID { return Self.googleID }
        if selectedID == Self.openAIID {
            return Self.hasOpenAIVoice() ? Self.openAIID : (bestDownloadedVoice?.identifier ?? Self.googleID)
        }
        if !selectedID.isEmpty, AVSpeechSynthesisVoice(identifier: selectedID) != nil { return selectedID }
        return bestDownloadedVoice?.identifier ?? Self.googleID
    }

    func displayName(for id: String) -> String {
        if id == Self.googleID { return "Google" }
        if id == Self.openAIID { return "OpenAI" }
        guard let voice = AVSpeechSynthesisVoice(identifier: id) else { return "Giọng của máy" }
        return "\(voice.name) (\(Self.qualityLabel(voice)))"
    }

    private var speed: Float {
        Float(UserDefaults.standard.object(forKey: speedKey) as? Double ?? language.defaultSpeed)
    }

    private var pitch: Float {
        Float(UserDefaults.standard.object(forKey: pitchKey) as? Double ?? Self.defaultPitch)
    }

    // MARK: - Đọc

    /// `completion` chỉ chạy khi đọc xong trọn vẹn, không chạy nếu bị `stop()`.
    /// `preferOpenAI`: dùng giọng OpenAI nếu đã có khoá (màn hình hội thoại AI).
    /// `progress` nhận số ký tự đã đọc xong, để màn hình tô đậm dần theo lời đọc.
    func speak(_ text: String, preferOpenAI: Bool = false,
               progress: ((Int) -> Void)? = nil, completion: (() -> Void)? = nil) {
        for other in Self.all where other !== self {
            other.stop()
        }
        stop()
        generation += 1
        self.completion = completion
        progressHandler = progress
        spokenCount = text.count
        activateSession()

        let id = preferOpenAI && Self.hasOpenAIVoice()
            ? Self.openAIID
            : resolvedID(for: UserDefaults.standard.string(forKey: voiceKey) ?? Self.automaticID)
        if id == Self.openAIID {
            speakWithOpenAI(text, generation: generation)
        } else if id == Self.googleID {
            speakWithGoogle(text, generation: generation)
        } else {
            speakWithSystem(text, voice: AVSpeechSynthesisVoice(identifier: id))
        }
    }

    /// Đang đọc, hoặc đang tải giọng để đọc.
    var isSpeaking: Bool {
        player != nil || utterance != nil || completion != nil
    }

    func stop() {
        let wasSpeaking = isSpeaking
        generation += 1
        completion = nil
        progressHandler = nil
        progressTimer?.invalidate()
        progressTimer = nil
        utterance = nil
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if wasSpeaking {
            deactivateSession()
        }
    }

    private func speakWithSystem(_ text: String, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? bestDownloadedVoice ?? AVSpeechSynthesisVoice(language: language.voicePrefix)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speed
        utterance.pitchMultiplier = pitch
        self.utterance = utterance
        synthesizer.speak(utterance)
    }

    private func speakWithGoogle(_ text: String, generation: Int) {
        if let data = audioCache[text] {
            play(data, fallbackText: text)
            return
        }

        var components = URLComponents(string: "https://translate.google.com/translate_tts")!
        components.queryItems = [
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "client", value: "tw-ob"),
            URLQueryItem(name: "tl", value: language.googleCode),
            URLQueryItem(name: "q", value: text),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 6
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                if let data, !data.isEmpty, (response as? HTTPURLResponse)?.statusCode == 200 {
                    self.audioCache[text] = data
                    self.play(data, fallbackText: text)
                } else {
                    self.speakWithSystem(text, voice: nil)
                }
            }
        }.resume()
    }

    private func speakWithOpenAI(_ text: String, generation: Int) {
        let cacheKey = "openai|\(text)"
        if let data = audioCache[cacheKey] {
            play(data, fallbackText: text, rate: 1)
            return
        }
        guard let synthesize = Self.openAISpeech else {
            speakWithGoogle(text, generation: generation)
            return
        }
        let languageCode = language.googleCode
        Task {
            let data = try? await synthesize(text, languageCode)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.generation else { return }
                if let data, !data.isEmpty {
                    self.audioCache[cacheKey] = data
                    self.play(data, fallbackText: text, rate: 1)
                } else {
                    // Lỗi mạng / khoá: dùng giọng Google thay thế.
                    self.speakWithGoogle(text, generation: generation)
                }
            }
        }
    }

    private func play(_ data: Data, fallbackText: String, rate: Float? = nil) {
        guard let player = try? AVAudioPlayer(data: data) else {
            speakWithSystem(fallbackText, voice: nil)
            return
        }
        player.enableRate = true
        player.rate = rate ?? speed
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        player.play()
        startProgressTimer()
    }

    private func finish() {
        player = nil
        utterance = nil
        progressTimer?.invalidate()
        progressTimer = nil
        // Báo đã đọc trọn câu trước khi đóng, để chữ được tô đậm hết.
        progressHandler?(spokenCount)
        progressHandler = nil
        let done = completion
        completion = nil
        deactivateSession()
        done?()
    }

    /// Giọng thu sẵn (Google, OpenAI) không báo đọc tới đâu, nên suy ra theo thời gian phát.
    private func startProgressTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            guard self.progressHandler != nil, self.spokenCount > 0 else { return }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let player = self.player, player.duration > 0 else { return }
                let ratio = min(max(player.currentTime / player.duration, 0), 1)
                self.progressHandler?(Int((Double(self.spokenCount) * ratio).rounded()))
            }
            RunLoop.main.add(timer, forMode: .common)
            self.progressTimer = timer
        }
    }

    // MARK: - Audio session

    /// Không đụng vào session khi app đang giữ micro cho bàn phím.
    private func activateSession() {
        guard !Self.isMicSessionActive() else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateSession() {
        guard !Self.isMicSessionActive() else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension NaturalSpeaker: AVSpeechSynthesizerDelegate {
    /// Giọng của máy báo đúng đoạn chữ đang đọc, khỏi phải suy ra theo thời gian.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard utterance === self.utterance else { return }
            self.progressHandler?(characterRange.location + characterRange.length)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard utterance === self.utterance else { return }
            self.finish()
        }
    }
}

extension NaturalSpeaker: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard player === self.player else { return }
            self.finish()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            guard player === self.player else { return }
            self.finish()
        }
    }
}

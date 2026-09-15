//
//  SpeechCapture.swift
//  Ban Phim Tieng Trung
//
//  Nghe người dùng đọc tiếng Trung trong app (luyện nói, hội thoại): bật micro, nhận dạng,
//  tự dừng khi đọc đúng một câu mẫu hoặc khi im lặng.
//

import AVFoundation
import Speech
import UIKit

final class SpeechCapture: ObservableObject {
    /// Một đoạn máy nghe được kèm độ chắc chắn của bộ nhận dạng.
    struct HeardSegment: Codable, Equatable {
        let text: String
        /// 0–1: máy càng nghe không chắc thì càng thấp. 0 nghĩa là máy không chấm đoạn này.
        let confidence: Float
    }

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var level: Float = 0
    /// Kết quả cuối tách theo đoạn, dùng để chấm phát âm.
    @Published private(set) var segments: [HeardSegment] = []
    /// Người học thật sự phát ra tiếng trong bao lâu (giây), tính từ đầu đến cuối đoạn nghe được.
    @Published private(set) var spokenDuration: TimeInterval = 0

    /// Lỗi quyền micro / nhận dạng.
    var onError: ((String) -> Void)?
    /// Chữ nghe được vừa đổi (kể cả kết quả tạm), để chấm ngay trong lúc người học còn đang đọc.
    var onTranscript: ((String) -> Void)?

    /// Ngôn ngữ nhận dạng; mặc định tiếng Trung phổ thông. Phiên dịch hội thoại đổi theo người nói.
    var localeIdentifier = "zh-CN"

    private let audioEngine = AVAudioEngine()
    private let sink = AudioTapSink()
    private var tapInstalled = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var targets: [String] = []
    /// Thời gian chờ trước khi tự dừng: lần đầu (chưa nói gì) và sau mỗi lần nghe thêm chữ.
    private var firstPause: TimeInterval = SpeechPace.normal.firstPause
    private var pause: TimeInterval = SpeechPace.normal.pause
    private var completion: ((String) -> Void)?
    private var stopWork: DispatchWorkItem?
    private var generation = 0
    private var backgroundObserver: NSObjectProtocol?

    init() {
        sink.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.level = level }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cancel()
        }
    }

    /// Bắt đầu nghe. `completion` nhận câu nghe được khi dừng (đọc khớp một câu mẫu, im lặng, hoặc gọi `finish()`).
    /// `firstPause` / `pause`: bỏ trống thì theo cài đặt "chờ khi bạn ngừng nói" của người dùng.
    func start(targets: [String], firstPause: TimeInterval? = nil, pause: TimeInterval? = nil,
               completion: @escaping (String) -> Void) {
        cancel()
        let pace = SharedSettings.speechPace
        self.firstPause = firstPause ?? pace.firstPause
        self.pause = pause ?? pace.pause
        generation += 1
        let current = generation
        NaturalSpeaker.all.forEach { $0.stop() }

        VoiceEngine.requestPermissions { [weak self] error in
            guard let self, self.generation == current else { return }
            if let error {
                self.onError?(error)
                return
            }
            // Tạm tắt phiên micro của bàn phím để app dùng micro.
            if VoiceEngine.shared.state.sessionActive {
                VoiceEngine.shared.deactivate()
            }
            do {
                try self.begin(targets: targets, completion: completion)
            } catch {
                self.stopAudio()
                self.onError?("Không bật được micro: \(error.localizedDescription)")
            }
        }
    }

    /// Người dùng nhấn dừng: chờ kết quả cuối rồi trả về.
    func finish() {
        guard isListening else { return }
        stopWork?.cancel()
        sink.setRequest(nil)
        request?.endAudio()
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.generation == current else { return }
            self.complete()
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    /// Dừng mà không trả kết quả.
    func cancel() {
        generation += 1
        completion = nil
        stopAudio()
        // Xoá luôn chữ cũ, nếu không lần nghe sau sẽ hiện lại câu của lần trước.
        transcript = ""
        segments = []
        spokenDuration = 0
    }

    private func begin(targets: [String], completion: @escaping (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            onError?(localeIdentifier.hasPrefix("zh")
                     ? "Nhận dạng tiếng Trung đang không khả dụng. Kiểm tra kết nối mạng."
                     : "Nhận dạng giọng nói cho ngôn ngữ này đang không khả dụng. Kiểm tra kết nối mạng.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        // Mặc định iOS tắt hết tiếng hệ thống và rung khi app đang thu micro — mà đó đúng là
        // lúc cần báo cho người học biết họ vừa đọc đúng một từ.
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "SpeechCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy micro"])
        }
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.handle(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Cố ý KHÔNG đặt contextualStrings = targets. Làm vậy là mách trước đáp án cho bộ
        // nhận dạng: nó sẽ thiên về việc trả ra đúng câu mẫu kể cả khi người học mới đọc
        // được một nửa, rồi câu đó được chấm đúng. Một bài kiểm tra phát âm thì phải nghe
        // xem người ta nói gì, chứ không phải nghe cái mình đang mong đợi.

        self.recognizer = recognizer
        self.request = request
        self.targets = targets
        self.completion = completion
        transcript = ""
        segments = []
        spokenDuration = 0
        isListening = true
        sink.setRequest(request)

        let current = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.handle(result: result, error: error)
            }
        }
        scheduleAutoStop(after: firstPause)
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isListening else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            // Máy hay gửi lại đúng chuỗi cũ; chấm lại cả câu mỗi lần như vậy là phí.
            if text != transcript {
                transcript = text
                onTranscript?(text)
            }
            let heard = result.bestTranscription.segments.map {
                HeardSegment(text: $0.substring, confidence: $0.confidence)
            }
            // Kết quả tạm luôn có điểm 0; chỉ ghi đè khi có điểm thật để không mất bản đã chấm.
            if segments.isEmpty || heard.contains(where: { $0.confidence > 0 }) {
                segments = heard
            }
            if let last = result.bestTranscription.segments.last {
                spokenDuration = last.timestamp + last.duration
            }
            let matched = targets.contains { PhraseMatcher.isCorrect(heard: transcript, target: $0) }
            if result.isFinal || matched {
                complete()
            } else {
                scheduleAutoStop(after: pause)
            }
        } else if error != nil {
            complete()
        }
    }

    private func scheduleAutoStop(after seconds: TimeInterval) {
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func complete() {
        guard isListening else { return }
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = completion
        completion = nil
        generation += 1
        stopAudio()
        done?(heard)
    }

    private func stopAudio() {
        stopWork?.cancel()
        stopWork = nil
        sink.setRequest(nil)
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        if isListening {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        isListening = false
        level = 0
    }
}

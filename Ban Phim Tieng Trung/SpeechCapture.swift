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
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var level: Float = 0

    /// Lỗi quyền micro / nhận dạng.
    var onError: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let sink = AudioTapSink()
    private var tapInstalled = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var targets: [String] = []
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
    func start(targets: [String], completion: @escaping (String) -> Void) {
        cancel()
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

    /// Dừng mà không trả kết quả.
    func cancel() {
        generation += 1
        completion = nil
        stopAudio()
    }

    private func begin(targets: [String], completion: @escaping (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            onError?("Nhận dạng tiếng Trung đang không khả dụng. Kiểm tra kết nối mạng.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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
        request.contextualStrings = targets

        self.recognizer = recognizer
        self.request = request
        self.targets = targets
        self.completion = completion
        transcript = ""
        isListening = true
        sink.setRequest(request)

        let current = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.handle(result: result, error: error)
            }
        }
        scheduleAutoStop(after: 7)
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isListening else { return }
        if let result {
            transcript = result.bestTranscription.formattedString
            let matched = targets.contains { PhraseMatcher.isCorrect(heard: transcript, target: $0) }
            if result.isFinal || matched {
                complete()
            } else {
                scheduleAutoStop(after: 1.8)
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

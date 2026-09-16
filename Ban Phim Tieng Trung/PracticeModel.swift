//
//  PracticeModel.swift
//  Ban Phim Tieng Trung
//
//  Luyện nói 1000 câu giao tiếp: đọc đúng bằng giọng nói thì câu được đánh dấu đã thuộc.
//

import AVFoundation
import Combine
import UIKit

struct Phrase: Codable, Identifiable, Hashable {
    let id: Int
    let category: String
    let zh: String
    let pinyin: String
    let vi: String
    let words: [PinyinWord]
}

final class PhraseStore: ObservableObject {
    static let masteredKey = "masteredPhraseIDs"
    static let countsKey = "phraseCorrectCounts"
    static let savedCategory = "⭐ Đã lưu"

    @Published private(set) var phrases: [Phrase] = []
    @Published private(set) var categories: [String] = []
    /// Mỗi câu đã đọc đúng bao nhiêu lần.
    @Published private(set) var counts: [Int: Int]

    /// Những câu đã đọc đúng ít nhất một lần.
    var mastered: Set<Int> {
        Set(counts.compactMap { $0.value > 0 ? $0.key : nil })
    }

    func correctCount(_ id: Int) -> Int { counts[id] ?? 0 }

    private let builtInPhrases: [Phrase]
    private let builtInCategories: [String]
    private var activeObserver: NSObjectProtocol?
    private var mergeObserver: NSObjectProtocol?

    init() {
        if let url = Bundle.main.url(forResource: "phrases", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Phrase].self, from: data) {
            builtInPhrases = list
        } else {
            builtInPhrases = []
        }
        var seen = Set<String>()
        builtInCategories = builtInPhrases.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
        if UserDefaults.standard.dictionary(forKey: Self.countsKey) != nil {
            counts = Self.loadCounts()
        } else {
            // Chuyển dữ liệu cũ: đã thuộc = đã đọc đúng một lần.
            let old = UserDefaults.standard.array(forKey: Self.masteredKey) as? [Int] ?? []
            counts = Dictionary(uniqueKeysWithValues: old.map { ($0, 1) })
        }
        reloadSaved()

        mergeObserver = NotificationCenter.default.addObserver(
            forName: .cloudSyncMerged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.counts = Self.loadCounts()
            self.reloadSaved()
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadSaved()
        }
    }

    /// Nạp lại các câu người dùng bấm ⭐ lưu từ bàn phím.
    func reloadSaved() {
        let saved = SharedStore.savedPhrases().reversed().map { item in
            Phrase(
                id: item.id,
                category: Self.savedCategory,
                zh: item.zh,
                pinyin: item.words.map(\.py).joined(separator: " "),
                vi: item.vi,
                words: item.words
            )
        }
        let newPhrases = saved + builtInPhrases
        if newPhrases != phrases { phrases = newPhrases }
        let newCategories = (saved.isEmpty ? [] : [Self.savedCategory]) + builtInCategories
        if newCategories != categories { categories = newCategories }
    }

    func isSaved(_ phrase: Phrase) -> Bool {
        phrase.id > SharedStore.firstSavedPhraseID
    }

    func deleteSaved(_ phrase: Phrase) {
        SharedStore.deleteSavedPhrase(id: phrase.id)
        counts[phrase.id] = nil
        save()
        reloadSaved()
    }

    var masteredCount: Int {
        phrases.reduce(0) { $0 + (correctCount($1.id) > 0 ? 1 : 0) }
    }

    /// Vòng hiện tại của một nhóm câu: số lần đọc đúng ít nhất trong nhóm.
    /// Chỉ những câu đang ở mức này mới hiện ra, nên học xong vòng nào là cả nhóm lên vòng sau.
    func round(of group: [Phrase]) -> Int {
        group.map { correctCount($0.id) }.min() ?? 0
    }

    /// Thứ tự xáo trộn ổn định trong một vòng: cùng một vòng thì thứ tự không đổi
    /// (danh sách không nhảy loạn mỗi lần dựng lại), sang vòng mới thì xáo lại.
    func shuffleKey(_ id: Int, round: Int) -> UInt64 {
        var value = UInt64(bitPattern: Int64(id &* 2_654_435_761)) ^ UInt64(bitPattern: Int64(round &* 40_503))
        value = (value ^ (value >> 33)) &* 0xFF51AFD7ED558CCD
        value = (value ^ (value >> 33)) &* 0xC4CEB9FE1A85EC53
        return value ^ (value >> 33)
    }

    /// Số câu còn phải đọc trong vòng hiện tại của nhóm.
    func remainingCount(in category: String?) -> Int {
        let group = phrases.filter { category == nil || $0.category == category }
        let level = round(of: group)
        return group.reduce(0) { $0 + (correctCount($1.id) == level ? 1 : 0) }
    }

    /// Đọc đúng thêm một lần.
    func markCorrect(_ phrase: Phrase) {
        counts[phrase.id, default: 0] += 1
        save()
    }

    func unmaster(_ phrase: Phrase) {
        counts[phrase.id] = 0
        save()
    }

    func resetAll() {
        counts.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(Self.store(counts), forKey: Self.countsKey)
    }

    /// Số lần đọc đúng của từng câu, lưu dưới dạng khoá chữ để hợp với UserDefaults.
    static func loadCounts() -> [Int: Int] {
        let stored = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    static func store(_ counts: [Int: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: counts.map { (String($0.key), $0.value) })
    }
}

// MARK: - Nghe người dùng đọc

final class PracticeListener: ObservableObject {
    enum Outcome: Equatable {
        case correct
        case wrong(heard: String)
    }

    @Published private(set) var activeID: Int?
    @Published private(set) var outcomes: [Int: Outcome] = [:]
    @Published var errorMessage: String?
    /// Câu mẫu đang đọc, đã tô màu theo những gì máy nghe được tới lúc này.
    @Published private(set) var liveWords: [PinyinWord] = []
    /// Số câu đọc đúng liên tiếp. Đọc sai một câu là về 0.
    @Published private(set) var combo = 0
    /// Chuỗi dài nhất trong buổi này.
    @Published private(set) var bestCombo = 0
    /// Vừa chạm một mốc chuỗi đáng ăn mừng (3, 5, 10, 20…).
    @Published private(set) var comboMilestone = 0

    /// Dòng đang được đọc tiếng Việt, và đã đọc tới ký tự thứ mấy.
    @Published private(set) var readingID: Int?
    @Published private(set) var readingProgress = 0

    private var activePhrase: Phrase?
    private var correctSoFar = 0

    var onCorrect: ((Phrase) -> Void)?

    var transcript: String { capture.transcript }
    var level: Float { capture.level }

    private let capture = SpeechCapture()
    private var captureObserver: AnyCancellable?

    init() {
        captureObserver = capture.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        capture.onError = { [weak self] message in
            self?.cancel()
            self?.errorMessage = message
        }
        capture.onTranscript = { [weak self] text in
            self?.updateLive(text)
        }
    }

    /// Chấm từng từ ngay trong lúc đọc: xanh là đã đúng, đỏ là đọc qua rồi mà không khớp.
    private func updateLive(_ text: String) {
        guard let phrase = activePhrase, activeID == phrase.id else { return }
        let words = PhraseMatcher.progress(heard: text, words: phrase.words)
        let correct = words.reduce(into: 0) { $0 += ($1.flagged == false ? 1 : 0) }
        if correct > correctSoFar {
            // Thêm một từ đúng: rung nhẹ cho biết đang đi đúng hướng.
            Self.tick()
            // Chỉ tiến, không lùi: máy liên tục sửa lại kết quả tạm (好 → 号 → 好),
            // nếu để số này tụt xuống thì cùng một từ sẽ kêu đi kêu lại.
            correctSoFar = correct
        }
        liveWords = words
    }

    private static let selection = UISelectionFeedbackGenerator()

    /// Thêm một từ đúng: chỉ rung nhẹ. Tiếng để dành cho lúc đọc trọn câu —
    /// kêu ở từng từ thì nghe rối và mất hết ý nghĩa của tiếng báo hoàn thành.
    private static func tick() {
        selection.selectionChanged()
    }

    /// Đọc trọn câu đúng: hai nốt đi lên cho ra dáng một tiếng chuông nhỏ.
    /// Chuỗi càng dài nốt càng cao — nghe là biết mình đang đi liền mạch, khỏi cần nhìn.
    private static func chimeSuccess(combo: Int) {
        let step = Double(min(max(combo - 1, 0), 8))
        let base = 1318.5 * pow(2, step / 12)
        Chime.play(frequency: base, duration: 0.13)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Quãng năm phía trên: hai nốt nghe ra một tiếng chuông chứ không phải hai tiếng bíp.
            Chime.play(frequency: base * 1.5, duration: 0.22)
        }
    }

    /// Mốc chuỗi đáng ăn mừng.
    private static let comboMilestones = [3, 5, 10, 20, 30, 50]

    func toggle(_ phrase: Phrase) {
        if activeID == phrase.id {
            capture.finish()
        } else {
            start(phrase)
        }
    }

    func cancel() {
        capture.cancel()
        activeID = nil
        activePhrase = nil
        liveWords = []
        correctSoFar = 0
        readingID = nil
        readingProgress = 0
        NaturalSpeaker.all.forEach { $0.stop() }
    }

    /// Chạm vào một dòng: đọc câu tiếng Việt của dòng đó, tô đậm dần theo lời đọc.
    /// Chạm lần nữa vào dòng đang đọc thì dừng.
    func readAloud(_ phrase: Phrase) {
        guard readingID != phrase.id else { return cancel() }
        cancel()
        readingID = phrase.id
        readingProgress = 0
        NaturalSpeaker.vietnamese.speak(phrase.vi, progress: { [weak self] count in
            guard let self, self.readingID == phrase.id else { return }
            self.readingProgress = count
        }, completion: { [weak self] in
            guard let self, self.readingID == phrase.id else { return }
            self.readingID = nil
            self.readingProgress = 0
        })
    }

    func clearOutcome(for phrase: Phrase) {
        outcomes[phrase.id] = nil
    }

    func speak(_ phrase: Phrase) {
        cancel()
        NaturalSpeaker.chinese.speak(phrase.zh)
    }

    /// Đọc nghĩa tiếng Việt; `completion` chỉ chạy khi đọc xong trọn vẹn (không bị ngắt).
    func speakVietnamese(_ phrase: Phrase, completion: @escaping () -> Void) {
        if activeID != nil { cancel() }
        NaturalSpeaker.vietnamese.speak(phrase.vi, completion: completion)
    }

    private func start(_ phrase: Phrase) {
        readingID = nil
        readingProgress = 0
        outcomes[phrase.id] = nil
        activeID = phrase.id
        activePhrase = phrase
        liveWords = phrase.words
        correctSoFar = 0
        Self.selection.prepare()
        capture.start(targets: [phrase.zh]) { [weak self] heard in
            guard let self, self.activeID == phrase.id else { return }
            self.activeID = nil
            self.activePhrase = nil
            self.liveWords = []
            self.correctSoFar = 0
            // Phải khớp từng từ, không phải "gần giống là được".
            // Kèm một chốt về thời lượng: bộ nhận dạng đôi khi "đoán nốt" phần chưa đọc,
            // mà đọc sáu chữ trong nửa giây thì chắc chắn là chưa đọc hết.
            let syllables = phrase.zh.filter(\.isLetter).count
            let spokenLongEnough = self.capture.spokenDuration <= 0
                || self.capture.spokenDuration >= Double(syllables) * 0.12
            let correct = spokenLongEnough
                && PhraseMatcher.isFullyCorrect(heard: heard, words: phrase.words)
            // Hiện đúng lần đọc cuối, không hiện cả chuỗi gộp mấy lần đọc lại.
            let latest = PhraseMatcher.lastAttempt(heard: heard, target: phrase.zh)
            self.outcomes[phrase.id] = correct ? .correct : .wrong(heard: latest)
            // Kể cả khi tính là đúng: chữ đồng âm khác thanh (买/卖) vẫn được cho qua nhưng là lỗi thanh điệu.
            PronunciationLog.record(PronunciationAnalyzer.mistakes(target: phrase.zh, heard: heard, source: .practice))
            UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
            guard correct else {
                self.combo = 0
                return
            }
            self.combo += 1
            self.bestCombo = max(self.bestCombo, self.combo)
            self.comboMilestone = Self.comboMilestones.contains(self.combo) ? self.combo : 0
            Self.chimeSuccess(combo: self.combo)
            StreakStore.addSentence()
            self.onCorrect?(phrase)
        }
    }
}

/// Tiếng chuông ngắn tự tổng hợp trong bộ nhớ.
///
/// Không dùng tiếng hệ thống (`AudioServices…`) vì iOS tắt hẳn kênh đó khi app đang thu
/// micro — đúng lúc duy nhất cần nó. Cũng không nhúng file vào bundle để khỏi phải sửa
/// `project.pbxproj`. Phát qua chính phiên âm thanh của app nên vẫn nghe được lúc đang ghi âm;
/// nốt cao và tắt nhanh nên bộ nhận dạng không nhầm thành tiếng nói.
enum Chime {
    /// Phải giữ tham chiếu: thả ra là tiếng tắt giữa chừng.
    private static var player: AVAudioPlayer?

    static func play(frequency: Double, duration: Double = 0.12) {
        guard let data = wav(frequency: frequency, duration: duration) else { return }
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = 0.55
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // Không kêu được thì thôi, rung vẫn báo đủ.
        }
    }

    private static func wav(frequency: Double, duration: Double) -> Data? {
        let sampleRate = 44_100.0
        let frames = Int(duration * sampleRate)
        guard frames > 0 else { return nil }

        var samples = Data(capacity: frames * 2)
        for index in 0..<frames {
            let time = Double(index) / sampleRate
            // Tắt dần thật nhanh: nghe như gõ chuông chứ không phải tiếng bíp kéo dài.
            let envelope = exp(-time * 26)
            let value = sin(2 * .pi * frequency * time) * envelope
            let sample = Int16(max(-1, min(1, value)) * 32_767)
            withUnsafeBytes(of: sample.littleEndian) { samples.append(contentsOf: $0) }
        }

        var file = Data()
        func append(_ text: String) { file.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) } }

        append("RIFF")
        append32(UInt32(36 + samples.count))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)                              // PCM
        append16(1)                              // một kênh
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate) * 2)         // byte mỗi giây
        append16(2)                              // byte mỗi khung
        append16(16)                             // bit mỗi mẫu
        append("data")
        append32(UInt32(samples.count))
        file.append(samples)
        return file
    }
}

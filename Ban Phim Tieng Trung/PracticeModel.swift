//
//  PracticeModel.swift
//  Ban Phim Tieng Trung
//
//  Luyện nói 1000 câu giao tiếp: đọc đúng bằng giọng nói thì câu được đánh dấu đã thuộc.
//

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
    private static let masteredKey = "masteredPhraseIDs"
    static let savedCategory = "⭐ Đã lưu"

    @Published private(set) var phrases: [Phrase] = []
    @Published private(set) var categories: [String] = []
    @Published private(set) var mastered: Set<Int>

    private let builtInPhrases: [Phrase]
    private let builtInCategories: [String]
    private var activeObserver: NSObjectProtocol?

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
        mastered = Set(UserDefaults.standard.array(forKey: Self.masteredKey) as? [Int] ?? [])
        reloadSaved()

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
        mastered.remove(phrase.id)
        save()
        reloadSaved()
    }

    var masteredCount: Int {
        phrases.reduce(0) { $0 + (mastered.contains($1.id) ? 1 : 0) }
    }

    func remainingCount(in category: String?) -> Int {
        phrases.reduce(0) { count, phrase in
            let matches = category == nil || phrase.category == category
            return count + (matches && !mastered.contains(phrase.id) ? 1 : 0)
        }
    }

    func markMastered(_ phrase: Phrase) {
        mastered.insert(phrase.id)
        save()
    }

    func unmaster(_ phrase: Phrase) {
        mastered.remove(phrase.id)
        save()
    }

    func resetAll() {
        mastered.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(mastered), forKey: Self.masteredKey)
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
            self?.activeID = nil
            self?.errorMessage = message
        }
    }

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
        NaturalSpeaker.all.forEach { $0.stop() }
    }

    func clearOutcome(for phrase: Phrase) {
        outcomes[phrase.id] = nil
    }

    func speak(_ phrase: Phrase) {
        if activeID != nil { cancel() }
        NaturalSpeaker.chinese.speak(phrase.zh)
    }

    /// Đọc nghĩa tiếng Việt; `completion` chỉ chạy khi đọc xong trọn vẹn (không bị ngắt).
    func speakVietnamese(_ phrase: Phrase, completion: @escaping () -> Void) {
        if activeID != nil { cancel() }
        NaturalSpeaker.vietnamese.speak(phrase.vi, completion: completion)
    }

    private func start(_ phrase: Phrase) {
        outcomes[phrase.id] = nil
        activeID = phrase.id
        capture.start(targets: [phrase.zh]) { [weak self] heard in
            guard let self, self.activeID == phrase.id else { return }
            self.activeID = nil
            let correct = PhraseMatcher.isCorrect(heard: heard, target: phrase.zh)
            self.outcomes[phrase.id] = correct ? .correct : .wrong(heard: heard)
            UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
            if correct { self.onCorrect?(phrase) }
        }
    }
}

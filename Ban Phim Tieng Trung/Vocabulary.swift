//
//  Vocabulary.swift
//  Từ vựng người học tự thêm (chạm chữ Hán → "+ Từ vựng") và trò nối cặp chữ Hán – nghĩa.
//
//  Học theo LẶP LẠI NGẮT QUÃNG (giống app/vocab.php trên web): mỗi từ có một bậc (`correct`, 0…8)
//  và một hạn ôn `dueAt`. Nối đúng → lên 1 bậc, hạn ôn giãn ra theo `VocabularyStore.steps`
//  (10 phút → 1 giờ → 1 ngày → 3 → 7 → 16 → 35 → 90 ngày); nối nhầm → lùi 2 bậc, ôn lại sau 10 phút.
//  Qua `target` bậc là "đã thuộc" nhưng vẫn còn hạn ôn để khỏi quên. Mỗi lúc chỉ học dở tối đa
//  `activeMax` từ, từ mới xếp hàng chờ tới lượt.
//

import Combine
import SwiftUI

private let accentRed = Color(red: 0.86, green: 0.17, blue: 0.16)
private let correctGreen = Color(red: 0.13, green: 0.62, blue: 0.3)

struct VocabWord: Codable, Identifiable, Hashable {
    var zh: String
    var py: String
    var vi: String
    var hv: String?
    /// Bậc lặp lại ngắt quãng (0…`VocabularyStore.maxStage`).
    var correct = 0
    var addedAt = Date()
    var lastPracticed: Date?
    /// Hạn ôn kế tiếp; `nil` = chưa hẹn (đến hạn ngay).
    var dueAt: Date?

    var id: String { zh }
    var isLearned: Bool { correct >= VocabularyStore.target }
    /// Đã bắt đầu học (khác với từ mới còn xếp hàng chờ tới lượt).
    var isStarted: Bool { correct > 0 }
    /// Đến hạn ôn lại (từ chưa bắt đầu không tính — còn chờ chỗ trống).
    var isDue: Bool { isStarted && (dueAt ?? .distantPast) <= Date() }
}

final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()
    /// Qua bấy nhiêu bậc (ôn đúng đúng hạn) là thuộc.
    static let target = 6
    /// Bậc cao nhất — ôn lại mỗi 90 ngày.
    static let maxStage = 8
    /// Số từ "đang học dở" tối đa cùng lúc; từ mới chờ tới lượt.
    static let activeMax = 20
    /// Hạn ôn sau khi lên bậc 1…8, tính bằng PHÚT.
    static let steps = [10, 60, 1440, 4320, 10080, 23040, 50400, 129600]
    /// Số cặp mỗi vòng.
    static let roundSize = 5
    /// Số cặp tối thiểu mỗi vòng (ít ô quá thì đoán được ngay).
    static let roundMin = 3

    /// "10 phút nữa", "3 ngày nữa"… Quá hạn hoặc chưa hẹn thì trả về chuỗi rỗng.
    static func dueText(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) phút nữa" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours) giờ nữa" }
        let days = Int((Double(hours) / 24).rounded())
        return days < 30 ? "\(days) ngày nữa" : "\(Int((Double(days) / 30).rounded())) tháng nữa"
    }

    /// Hạn ôn sau khi lên bậc `stage`.
    static func nextDue(stage: Int, from now: Date = Date()) -> Date {
        now.addingTimeInterval(Double(steps[min(max(stage, 1), steps.count) - 1]) * 60)
    }

    @Published private(set) var words: [VocabWord] = []

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("vocabulary.json")
    }

    private init() {
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([VocabWord].self, from: data) {
            words = list
        }
        // Mở app / vừa đăng nhập website: đồng bộ từ vựng với máy chủ.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.accountObserver = WebAccountStore.shared.$user
                .map { $0?.id }
                .removeDuplicates()
                .sink { [weak self] id in
                    guard id != nil else { return }
                    Task { await self?.syncWithServer() }
                }
        }
    }

    private var accountObserver: AnyCancellable?
    /// Tăng mỗi lần từ vựng trên máy đổi, để biết có thay đổi trong lúc đang đồng bộ không.
    private var localVersion = 0
    private var syncing = false

    /// Đang học dở (đã bắt đầu, chưa thuộc).
    var learning: [VocabWord] {
        words.filter { !$0.isLearned && $0.isStarted }.sorted { $0.addedAt > $1.addedAt }
    }

    /// Từ mới còn xếp hàng: chỉ vào học khi còn chỗ trong `activeMax`.
    var queued: [VocabWord] {
        words.filter { !$0.isStarted }.sorted { $0.addedAt > $1.addedAt }
    }

    /// Bài ôn hôm nay = từ đến hạn + số từ mới được phép nạp.
    var dueWords: [VocabWord] {
        words.filter(\.isDue).sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
    }

    var newAllowed: Int { max(0, min(queued.count, Self.activeMax - learning.count)) }
    var sessionCount: Int { dueWords.count + newAllowed }

    /// Khi nào có từ tiếp theo đến hạn (để báo "xong bài hôm nay").
    var nextDueAt: Date? {
        words.filter { $0.isStarted && !$0.isDue }.compactMap(\.dueAt).min()
    }

    var learned: [VocabWord] {
        words.filter(\.isLearned).sorted { ($0.lastPracticed ?? $0.addedAt) > ($1.lastPracticed ?? $1.addedAt) }
    }

    func contains(_ zh: String) -> Bool {
        words.contains { $0.zh == zh }
    }

    enum AddResult { case added, restarted }

    /// Thêm từ. Từ đã có (kể cả đã thuộc) thì cập nhật nghĩa và học lại từ 0.
    @discardableResult
    func add(zh: String, py: String, vi: String, hv: String?) -> AddResult {
        let entry = VocabWord(zh: zh, py: py, vi: Self.shortMeaning(vi), hv: hv)
        let result: AddResult
        if let index = words.firstIndex(where: { $0.zh == zh }) {
            words[index] = entry
            result = .restarted
        } else {
            words.append(entry)
            result = .added
        }
        save()
        if WebAccountStore.shared.isSignedIn {
            Task {
                do {
                    try await VocabAPI.post(["action": "add", "zh": zh, "py": py, "vi": entry.vi, "hv": hv ?? ""])
                } catch {
                    // Thêm lại = học lại từ 0: phải báo máy chủ, nếu không lần đồng bộ sau giữ số đúng cũ.
                    if result == .restarted { await MainActor.run { self.queue(.restart, zh) } }
                }
            }
        }
        return result
    }

    /// Nối đúng: lên 1 bậc và hẹn hạn ôn xa hơn. Kết quả cả vòng gửi lên máy chủ bằng `recordRound`.
    func recordCorrect(_ zh: String) {
        guard let index = words.firstIndex(where: { $0.zh == zh }) else { return }
        let stage = min(words[index].correct + 1, Self.maxStage)
        words[index].correct = stage
        words[index].dueAt = Self.nextDue(stage: stage)
        words[index].lastPracticed = Date()
        save()
    }

    /// Nối nhầm: lùi 2 bậc và ôn lại sau 10 phút (từ đã thuộc cũng quay về nhóm đang học).
    func recordMissed(_ zh: String) {
        guard let index = words.firstIndex(where: { $0.zh == zh }) else { return }
        words[index].correct = max(0, words[index].correct - 2)
        words[index].dueAt = Self.nextDue(stage: 1)
        words[index].lastPracticed = Date()
        save()
    }

    /// Hết một vòng nối từ: gửi từ đúng / nhầm lên máy chủ (mất mạng thì lần đồng bộ sau gửi số đúng).
    func recordRound(correct: [String], missed: [String]) {
        for zh in missed where !correct.contains(zh) { recordMissed(zh) }
        guard WebAccountStore.shared.isSignedIn, !(correct.isEmpty && missed.isEmpty) else { return }
        Task { try? await VocabAPI.post(["action": "record", "correct": correct, "missed": missed]) }
    }

    func restart(_ zh: String) {
        guard let index = words.firstIndex(where: { $0.zh == zh }) else { return }
        words[index].correct = 0
        words[index].dueAt = nil
        save()
        pushOrQueue(.restart, zh)
    }

    func remove(_ zh: String) {
        words.removeAll { $0.zh == zh }
        save()
        pushOrQueue(.remove, zh)
    }

    // MARK: - Đồng bộ với website (api/vocab.php)

    private enum PendingKind: String { case restart, remove }

    private var pendingKey: String? {
        WebAccountStore.shared.user.map { "vocabPending.\($0.id)" }
    }

    /// Việc học lại / xoá chưa gửi được (mất mạng), gửi trước lần đồng bộ sau.
    private var pending: [[String: String]] {
        get {
            guard let pendingKey else { return [] }
            return UserDefaults.standard.array(forKey: pendingKey) as? [[String: String]] ?? []
        }
        set {
            guard let pendingKey else { return }
            UserDefaults.standard.set(newValue, forKey: pendingKey)
        }
    }

    private func queue(_ kind: PendingKind, _ zh: String) {
        var list = pending.filter { $0["zh"] != zh || $0["kind"] != kind.rawValue }
        if kind == .remove { list.removeAll { $0["zh"] == zh } }
        list.append(["kind": kind.rawValue, "zh": zh])
        pending = list
    }

    private func pushOrQueue(_ kind: PendingKind, _ zh: String) {
        guard WebAccountStore.shared.isSignedIn else { return }
        Task {
            do {
                try await VocabAPI.post(["action": kind.rawValue, "zh": zh])
            } catch {
                await MainActor.run { self.queue(kind, zh) }
            }
        }
    }

    /// Gửi việc còn chờ, gửi toàn bộ từ trên máy (máy chủ gộp: giữ số đúng cao hơn, ngày thêm sớm hơn,
    /// lần luyện muộn hơn) rồi lấy danh sách chung về. Lỗi mạng thì giữ nguyên trên máy, lần sau thử lại.
    @MainActor
    func syncWithServer() async {
        guard WebAccountStore.shared.isSignedIn, !syncing else { return }
        syncing = true
        defer { syncing = false }

        for item in pending {
            guard let kind = item["kind"], let zh = item["zh"] else { continue }
            do {
                try await VocabAPI.post(["action": kind, "zh": zh])
                pending = pending.filter { $0 != item }
            } catch {
                return
            }
        }

        let version = localVersion
        let payload: [[String: Any]] = words.map { word in
            var item: [String: Any] = [
                "zh": word.zh, "py": word.py, "vi": word.vi, "hv": word.hv ?? "",
                "correct": word.correct, "addedAt": VocabAPI.iso.string(from: word.addedAt),
            ]
            if let practiced = word.lastPracticed { item["lastPracticed"] = VocabAPI.iso.string(from: practiced) }
            if let due = word.dueAt { item["dueAt"] = VocabAPI.iso.string(from: due) }
            return item
        }
        guard let serverWords = try? await VocabAPI.sync(payload) else { return }
        if version == localVersion {
            // Máy chủ đã gộp đủ từ trên máy: lấy danh sách chung làm chuẩn (có cả từ thêm trên web).
            words = serverWords
            persist()
        } else {
            // Trên máy vừa đổi trong lúc đồng bộ: chỉ gộp thêm, lần sau đồng bộ lại.
            merge(serverWords)
        }
    }

    /// Chọn từ cho một vòng: TỪ ĐẾN HẠN ÔN trước, còn chỗ thì nạp thêm từ mới (không quá `activeMax`
    /// từ đang học dở). `early` = ôn sớm khi đã hết bài hôm nay.
    func nextRound(early: Bool = false) -> [VocabWord] {
        var picked = Array(dueWords.prefix(Self.roundSize))
        let slots = min(Self.roundSize - picked.count, newAllowed)
        if slots > 0 { picked += queued.prefix(slots) }
        // Ít ô quá thì đoán được ngay: mượn thêm từ sắp đến hạn cho đủ ô (ôn sớm thì lấy hẳn 1 vòng)
        let need = picked.isEmpty ? (early ? Self.roundSize : 0) : Self.roundMin
        if picked.count < need {
            let soon = words.filter { word in !picked.contains { $0.zh == word.zh } }
                .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
            picked += soon.prefix(need - picked.count)
        }
        return picked.shuffled()
    }

    /// Nghĩa ngắn cho ô nối: lấy nghĩa đầu tiên, bỏ phần giải thích dài.
    static func shortMeaning(_ text: String) -> String {
        let first = text.split(whereSeparator: { ";；\n".contains($0) }).first.map(String.init) ?? text
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    /// Gộp từ vựng từ iCloud: giữ số lần nối đúng cao hơn, ngày thêm sớm hơn.
    func merge(_ incoming: [VocabWord]) {
        var byZh = Dictionary(grouping: words, by: \.zh).compactMapValues(\.first)
        var changed = false
        for word in incoming {
            guard var current = byZh[word.zh] else {
                byZh[word.zh] = word
                changed = true
                continue
            }
            if word.correct > current.correct { current.correct = word.correct; changed = true }
            if word.addedAt < current.addedAt { current.addedAt = word.addedAt; changed = true }
            // Hạn ôn: lấy cái sớm hơn (chưa hẹn = đến hạn ngay)
            if current.dueAt != nil, word.dueAt == nil || word.dueAt! < current.dueAt! {
                current.dueAt = word.dueAt
                changed = true
            }
            if let practiced = word.lastPracticed, practiced > (current.lastPracticed ?? .distantPast) {
                current.lastPracticed = practiced
                changed = true
            }
            byZh[word.zh] = current
        }
        guard changed else { return }
        words = byZh.values.sorted { $0.addedAt < $1.addedAt }
        save()
    }

    private func save() {
        localVersion += 1
        persist()
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(words) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Tab từ vựng

struct VocabularyTabView: View {
    @ObservedObject private var store = VocabularyStore.shared
    @State private var playing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

                if store.words.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(accentRed)
                            Text("Chưa có từ nào")
                                .font(.headline)
                            Text("Chạm vào chữ Hán ở Luyện nói hoặc Hội thoại, rồi bấm \"+ Từ vựng\" để thêm vào đây.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                if !store.learning.isEmpty {
                    Section {
                        ForEach(store.learning) { word in
                            VocabRow(word: word)
                                .swipeActions {
                                    Button("Xoá", role: .destructive) { withAnimation { store.remove(word.zh) } }
                                }
                        }
                    } header: {
                        Text("Đang học · \(store.learning.count)")
                    } footer: {
                        Text("Nối đúng thì lần ôn sau giãn ra: 10 phút → 1 giờ → 1 ngày → 3 → 7 → 16 ngày. Vuốt sang trái để xoá.")
                    }
                }

                if !store.queued.isEmpty {
                    Section {
                        ForEach(store.queued) { word in
                            VocabRow(word: word)
                                .swipeActions {
                                    Button("Xoá", role: .destructive) { withAnimation { store.remove(word.zh) } }
                                }
                        }
                    } header: {
                        Text("Chờ tới lượt · \(store.queued.count)")
                    } footer: {
                        Text("Mỗi lúc chỉ học dở tối đa \(VocabularyStore.activeMax) từ — học xong từ nào thì từ ở đây vào thay.")
                    }
                }

                if !store.learned.isEmpty {
                    Section {
                        ForEach(store.learned) { word in
                            VocabRow(word: word)
                                .swipeActions {
                                    Button("Xoá", role: .destructive) { withAnimation { store.remove(word.zh) } }
                                    Button("Học lại") { withAnimation { store.restart(word.zh) } }
                                        .tint(.orange)
                                }
                        }
                    } header: {
                        Text("Đã thuộc · \(store.learned.count)")
                    } footer: {
                        Text("Vẫn ôn lại sau 35 rồi 90 ngày — nhầm lần nào thì từ đó quay về nhóm đang học.")
                    }
                }
            }
            .navigationTitle("Từ vựng")
            .homeBackButton()
            .task { await store.syncWithServer() }
            .refreshable { await store.syncWithServer() }
            .fullScreenCover(isPresented: $playing) {
                MatchingGameView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                stat("\(store.sessionCount)", "Cần ôn", accentRed)
                Divider().frame(height: 36)
                stat("\(store.learning.count)", "Đang học", .primary)
                Divider().frame(height: 36)
                stat("\(store.learned.count)", "Đã thuộc", correctGreen)
            }
            Button {
                playing = true
            } label: {
                Label(playTitle, systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentRed.opacity(store.words.isEmpty ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(store.words.isEmpty)
            Text(playHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var playTitle: String {
        if store.words.isEmpty { return "Chưa có từ để luyện" }
        return store.sessionCount > 0 ? "Ôn hôm nay · \(store.sessionCount) từ" : "Xong bài hôm nay · ôn sớm?"
    }

    private var playHint: String {
        guard !store.words.isEmpty else { return "Chạm chữ Hán ở Luyện nói hoặc Hội thoại để thêm từ." }
        if store.sessionCount > 0 {
            let fresh = store.newAllowed > 0 ? " · \(store.newAllowed) từ mới" : ""
            return "\(store.dueWords.count) từ đến hạn\(fresh)"
        }
        let left = VocabularyStore.dueText(store.nextDueAt)
        return left.isEmpty ? "Thêm từ mới để học tiếp, hoặc ôn sớm cho chắc."
                            : "Từ tiếp theo đến hạn \(left). Vẫn có thể ôn sớm."
    }

    private func stat(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VocabRow: View {
    let word: VocabWord

    /// "Từ mới" / "Đến hạn ôn" / "Ôn 3 ngày nữa" — cho thấy lịch lặp lại ngắt quãng.
    private var dueLabel: String {
        guard word.isStarted else { return "Từ mới · chờ tới lượt" }
        let left = VocabularyStore.dueText(word.dueAt)
        if left.isEmpty { return "Đến hạn ôn" }
        return word.isLearned ? "Ôn lại \(left)" : "Ôn \(left)"
    }

    private var dueColor: Color {
        word.isDue ? accentRed : .secondary
    }

    var body: some View {
        Button {
            NaturalSpeaker.chinese.speak(word.zh)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(word.zh)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(word.py)
                            .font(.subheadline)
                            .foregroundStyle(accentRed)
                    }
                    Text(word.vi)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(dueLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(dueColor)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemFill), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(word.correct) / CGFloat(VocabularyStore.target))
                        .stroke(word.isLearned ? correctGreen : accentRed, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if word.isLearned {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(correctGreen)
                    } else {
                        Text("\(word.correct)")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                .frame(width: 38, height: 38)
                .accessibilityLabel("\(word.correct) trên \(VocabularyStore.target) lần")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trò nối cặp

struct MatchingGameView: View {
    private enum Side { case left, right }

    private struct Tile: Identifiable, Equatable {
        let word: VocabWord
        var id: String { word.zh }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = VocabularyStore.shared

    @State private var round: [VocabWord] = []
    @State private var rightOrder: [VocabWord] = []
    @State private var selectedLeft: String?
    @State private var selectedRight: String?
    @State private var matched: Set<String> = []
    /// Từ đã bị nối nhầm trong vòng này: nối đúng sau đó không được tính.
    @State private var missed: Set<String> = []
    @State private var wrongPair: (String, String)?
    @State private var shake = 0
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var counted: [String] = []
    @State private var newlyLearned: [VocabWord] = []
    @State private var finished = false
    /// Cặp vừa nối đúng: loé xanh một nhịp rồi mới mờ đi.
    @State private var justMatched: String?

    private static let violet = Color(red: 0.62, green: 0.45, blue: 1)

    var body: some View {
        ZStack {
            VividWallpaper()

            if finished {
                resultView
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else if round.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.green)
                    Text("Xong bài hôm nay 🎉")
                        .font(.headline)
                    Text(VocabularyStore.dueText(store.nextDueAt).isEmpty
                         ? "Thêm từ mới từ Hội thoại để học tiếp nhé."
                         : "Từ tiếp theo đến hạn \(VocabularyStore.dueText(store.nextDueAt)).")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                    Button { dismiss() } label: {
                        Text("Đóng")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .glassCapsule(tint: .white.opacity(0.08))
                    }
                    .buttonStyle(PressableStyle())
                }
                .foregroundStyle(.white)
            } else {
                gameView
            }
        }
        .environment(\.colorScheme, .dark)
        // Hết bài hôm nay mà vẫn mở trò chơi = người học muốn ôn sớm
        .onAppear { startRound(early: store.sessionCount == 0) }
    }

    private var gameView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassCapsule(tint: .white.opacity(0.06))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Thoát")

                progressBar

                Text("\(matched.count)/\(round.count)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nối chữ Hán với nghĩa")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Chạm một chữ Hán, rồi chạm nghĩa đúng của nó.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(combo > 0 ? .orange : .white.opacity(0.5))
                    .scaleEffect(combo > 0 ? 1.15 : 1)
                Text("Liên tiếp x\(combo)")
                    .contentTransition(.numericText())
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassCapsule(tint: combo > 0 ? Color.orange.opacity(0.25) : .white.opacity(0.05))
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: combo)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(round) { word in tile(word, side: .left) }
                }
                VStack(spacing: 12) {
                    ForEach(rightOrder) { word in tile(word, side: .right) }
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = round.isEmpty ? 0 : CGFloat(matched.count) / CGFloat(round.count)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.35, blue: 0.4), Self.violet],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 14 : 0))
                    .shadow(color: .orange.opacity(0.6), radius: 6)
            }
        }
        .frame(height: 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: matched.count)
    }

    private func tile(_ word: VocabWord, side: Side) -> some View {
        let isMatched = matched.contains(word.zh)
        let isFlashing = justMatched == word.zh
        let isSelected = (side == .left ? selectedLeft : selectedRight) == word.zh
        let isWrong = wrongPair.map { side == .left ? $0.0 == word.zh : $0.1 == word.zh } ?? false
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let glow: Color = isWrong ? .red : (isFlashing ? .green : Self.violet)

        return Button {
            tap(word, side: side)
        } label: {
            VStack(spacing: 3) {
                if side == .left {
                    Text(word.zh)
                        .font(.system(size: 28, weight: .semibold))
                    Text(word.py)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Text(word.vi)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, 8)
            .glassCard(cornerRadius: 20, tint: isFlashing ? Color.green.opacity(0.35)
                                              : isWrong ? Color.red.opacity(0.35)
                                              : isSelected ? Self.violet.opacity(0.35) : .white.opacity(0.04))
            .overlay {
                if isSelected || isWrong || isFlashing {
                    shape.strokeBorder(
                        LinearGradient(colors: [glow, glow.opacity(0.4), .white.opacity(0.8)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2.5
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if isMatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .green)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: glow.opacity(isSelected || isWrong || isFlashing ? 0.55 : 0), radius: 14)
            .opacity(isMatched && !isFlashing ? 0.35 : 1)
            .scaleEffect(isFlashing ? 1.06 : (isSelected ? 1.04 : (isMatched ? 0.96 : 1)))
            .modifier(TileShake(shakes: isWrong ? CGFloat(shake) : 0))
        }
        .buttonStyle(PressableStyle())
        .disabled(isMatched)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFlashing)
        .animation(.easeOut(duration: 0.35), value: isMatched)
    }

    private func tap(_ word: VocabWord, side: Side) {
        wrongPair = nil
        switch side {
        case .left:
            selectedLeft = selectedLeft == word.zh ? nil : word.zh
            NaturalSpeaker.chinese.speak(word.zh)
        case .right:
            selectedRight = selectedRight == word.zh ? nil : word.zh
        }
        guard let left = selectedLeft, let right = selectedRight else {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }

        if left == right {
            matched.insert(left)
            justMatched = left
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if justMatched == left { justMatched = nil }
            }
            combo += 1
            bestCombo = max(bestCombo, combo)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Chime.play(frequency: 1318.5 * pow(2, Double(min(combo - 1, 8)) / 12), duration: 0.12)
            if !missed.contains(left), let before = store.words.first(where: { $0.zh == left }) {
                store.recordCorrect(left)
                counted.append(left)
                if !before.isLearned, before.correct + 1 >= VocabularyStore.target {
                    newlyLearned.append(before)
                }
            }
            selectedLeft = nil
            selectedRight = nil
            if matched.count == round.count {
                store.recordRound(correct: counted, missed: Array(missed.subtracting(counted)))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { finished = true }
                }
            }
        } else {
            missed.insert(left)
            missed.insert(right)
            combo = 0
            wrongPair = (left, right)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.default) { shake += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if wrongPair?.0 == left, wrongPair?.1 == right {
                    withAnimation { wrongPair = nil }
                }
            }
            selectedLeft = nil
            selectedRight = nil
        }
    }

    /// Vòng sau gặp lại từ này lúc nào (thay cho "+1" cũ).
    private func resultNote(_ word: VocabWord, current: VocabWord?) -> String {
        guard counted.contains(word.zh) else { return "nhầm · ôn lại sau 10 phút" }
        let left = VocabularyStore.dueText(current?.dueAt)
        return left.isEmpty ? "lên bậc" : "ôn \(left)"
    }

    private func startRound(early: Bool = false) {
        let words = store.nextRound(early: early)
        round = words
        rightOrder = words.shuffled()
        if words.count > 1 {
            while rightOrder.map(\.zh) == words.map(\.zh) { rightOrder.shuffle() }
        }
        selectedLeft = nil
        selectedRight = nil
        matched = []
        missed = []
        wrongPair = nil
        justMatched = nil
        combo = 0
        counted = []
        newlyLearned = []
        finished = false
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ZStack {
                SparkBurst(count: 18, radius: 130)
                MascotView(mood: .happy, size: 110)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            }
            .frame(height: 150)
            Text(missed.isEmpty ? "Hoàn hảo! 🎯" : "Xong vòng! 🎉")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Text("Nối đúng ngay \(counted.count)/\(round.count) từ · liên tiếp tốt nhất x\(bestCombo)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(round) { word in
                    let current = store.words.first { $0.zh == word.zh }
                    let progress = CGFloat(current?.correct ?? 0) / CGFloat(VocabularyStore.target)
                    HStack(spacing: 10) {
                        Text(word.zh)
                            .font(.headline)
                        Text(word.vi)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        Spacer()
                        Text(resultNote(word, current: current))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(counted.contains(word.zh) ? .green : Color(red: 1, green: 0.45, blue: 0.45))
                        ZStack {
                            Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(progress >= 1 ? Color.green : .white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(current?.correct ?? 0)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                        }
                        .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 22, tint: .white.opacity(0.05))

            if !newlyLearned.isEmpty {
                Label("Đã thuộc: " + newlyLearned.map(\.zh).joined(separator: ", "), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(tint: Color.green.opacity(0.2))
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                if !store.words.isEmpty {
                    Button {
                        let early = store.sessionCount == 0
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { startRound(early: early) }
                    } label: {
                        Label(store.sessionCount > 0 ? "Vòng tiếp → còn \(store.sessionCount) từ" : "Ôn sớm tiếp",
                              systemImage: "arrow.right")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule().fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.3, blue: 0.4)],
                                                              startPoint: .leading, endPoint: .trailing))
                            )
                            .shadow(color: .orange.opacity(0.45), radius: 12, y: 5)
                    }
                    .buttonStyle(PressableStyle())
                }
                Button { dismiss() } label: {
                    Text("Xong")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassCapsule(tint: .white.opacity(0.06))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(24)
    }
}

private struct TileShake: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(shakes * .pi * 4), y: 0))
    }
}

// MARK: - Nút thêm từ vựng

/// Nút tròn "+ Từ vựng" dùng trong popup chữ Hán và trang chi tiết.
struct AddVocabularyButton: View {
    let zh: String
    let py: String
    let hv: String?
    /// Nil khi chưa có nghĩa (đang tra hoặc tra lỗi): chưa cho thêm.
    let meaning: String?
    var compact = true

    @ObservedObject private var store = VocabularyStore.shared
    @State private var justAdded: VocabularyStore.AddResult?

    var body: some View {
        let exists = store.contains(zh)
        Button {
            guard let meaning else { return }
            let result = store.add(zh: zh, py: py, vi: meaning, hv: hv)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { justAdded = result }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { justAdded = nil }
            }
        } label: {
            if compact {
                Image(systemName: justAdded != nil || exists ? "bookmark.fill" : "bookmark")
                    .font(.headline)
                    .foregroundStyle(accentRed)
                    .frame(width: 46, height: 44)
                    .background(Circle().fill(accentRed.opacity(0.12)))
                    .scaleEffect(justAdded != nil ? 1.15 : 1)
            } else {
                Label(exists ? "Học lại từ đầu" : "Thêm từ vựng", systemImage: exists ? "arrow.counterclockwise" : "bookmark")
            }
        }
        .buttonStyle(.plain)
        .disabled(meaning == nil)
        .opacity(meaning == nil ? 0.4 : 1)
        .accessibilityLabel(exists ? "Thêm lại vào từ vựng, học lại từ đầu" : "Thêm vào từ vựng")
        .overlay(alignment: .top) {
            if let justAdded {
                Text(justAdded == .added ? "Đã thêm vào từ vựng" : "Học lại từ 0/\(VocabularyStore.target)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .offset(y: -40)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - API từ vựng của website

enum VocabAPI {
    static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    /// Ngày máy chủ trả "yyyy-MM-dd HH:mm:ss" theo giờ Việt Nam.
    private static let serverDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private struct ServerWord: Decodable {
        let zh: String
        let py: String?
        let vi: String?
        let hv: String?
        let correct: Int?
        let addedAt: String?
        let lastPracticed: String?
        let dueAt: String?
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
        let login: Bool?
        let words: [ServerWord]?
    }

    private static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return serverDate.date(from: text) ?? iso.date(from: text)
    }

    static func sync(_ words: [[String: Any]]) async throws -> [VocabWord] {
        let envelope = try await request(["action": "sync", "words": words])
        guard let list = envelope.words else { throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi.") }
        return list.map { item in
            var word = VocabWord(zh: item.zh, py: item.py ?? "", vi: item.vi ?? "",
                                 hv: (item.hv?.isEmpty ?? true) ? nil : item.hv)
            word.correct = min(max(0, item.correct ?? 0), VocabularyStore.maxStage)
            word.addedAt = date(item.addedAt) ?? Date()
            word.lastPracticed = date(item.lastPracticed)
            word.dueAt = date(item.dueAt)
            return word
        }
    }

    static func post(_ body: [String: Any]) async throws {
        _ = try await request(body)
    }

    private static func request(_ body: [String: Any]) async throws -> Envelope {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Chưa đăng nhập website.", needsLogin: true)
        }
        var request = URLRequest(url: WebBackend.baseURL.appendingPathComponent("api/vocab.php"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi.")
        }
        guard envelope.ok else {
            throw WebBackendError(message: envelope.error ?? "Có lỗi xảy ra.", needsLogin: envelope.login == true)
        }
        return envelope
    }
}

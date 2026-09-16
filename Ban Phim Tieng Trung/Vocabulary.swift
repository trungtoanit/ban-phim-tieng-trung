//
//  Vocabulary.swift
//  Từ vựng người học tự thêm (chạm chữ Hán → "+ Từ vựng") và trò nối cặp chữ Hán – nghĩa.
//  Mỗi từ phải nối đúng 15 lần mới tính là thuộc; thêm lại một từ thì học lại từ 0.
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
    /// Số lần nối đúng (0…`VocabularyStore.target`).
    var correct = 0
    var addedAt = Date()
    var lastPracticed: Date?

    var id: String { zh }
    var isLearned: Bool { correct >= VocabularyStore.target }
}

final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()
    /// Nối đúng bấy nhiêu lần mới tính là thuộc.
    static let target = 15
    /// Số cặp mỗi vòng.
    static let roundSize = 5

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

    var learning: [VocabWord] {
        words.filter { !$0.isLearned }.sorted { $0.addedAt > $1.addedAt }
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

    /// Cộng 1 lần đúng trên máy; kết quả cả vòng gửi lên máy chủ bằng `recordRound`.
    func recordCorrect(_ zh: String) {
        guard let index = words.firstIndex(where: { $0.zh == zh }) else { return }
        words[index].correct = min(words[index].correct + 1, Self.target)
        words[index].lastPracticed = Date()
        save()
    }

    /// Hết một vòng nối từ: gửi từ đúng / nhầm lên máy chủ (mất mạng thì lần đồng bộ sau gửi số đúng).
    func recordRound(correct: [String], missed: [String]) {
        let now = Date()
        for zh in missed {
            if let index = words.firstIndex(where: { $0.zh == zh }) { words[index].lastPracticed = now }
        }
        if !missed.isEmpty { save() }
        guard WebAccountStore.shared.isSignedIn, !(correct.isEmpty && missed.isEmpty) else { return }
        Task { try? await VocabAPI.post(["action": "record", "correct": correct, "missed": missed]) }
    }

    func restart(_ zh: String) {
        guard let index = words.firstIndex(where: { $0.zh == zh }) else { return }
        words[index].correct = 0
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

    /// Chọn từ cho một vòng: từ ít lần đúng và lâu chưa luyện trước.
    func nextRound() -> [VocabWord] {
        Array(learning
            .sorted { ($0.correct, $0.lastPracticed ?? .distantPast) < ($1.correct, $1.lastPracticed ?? .distantPast) }
            .prefix(Self.roundSize))
            .shuffled()
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
                        Text("Nối đúng \(VocabularyStore.target) lần là thuộc. Vuốt sang trái để xoá.")
                    }
                }

                if !store.learned.isEmpty {
                    Section("Đã thuộc · \(store.learned.count)") {
                        ForEach(store.learned) { word in
                            VocabRow(word: word)
                                .swipeActions {
                                    Button("Xoá", role: .destructive) { withAnimation { store.remove(word.zh) } }
                                    Button("Học lại") { withAnimation { store.restart(word.zh) } }
                                        .tint(.orange)
                                }
                        }
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
                stat("\(store.learning.count)", "Đang học", accentRed)
                Divider().frame(height: 36)
                stat("\(store.learned.count)", "Đã thuộc", correctGreen)
                Divider().frame(height: 36)
                stat("\(store.words.count)", "Tổng số", .primary)
            }
            Button {
                playing = true
            } label: {
                Label(store.learning.isEmpty ? "Chưa có từ để luyện" : "Luyện nối từ", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentRed.opacity(store.learning.isEmpty ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(store.learning.isEmpty)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
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
                    Text("Bạn đã thuộc hết từ đang học")
                        .font(.headline)
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
        .onAppear(perform: startRound)
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

    private func startRound() {
        let words = store.nextRound()
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
                        Text(counted.contains(word.zh) ? "+1" : "nhầm")
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
                if !store.learning.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { startRound() }
                    } label: {
                        Label("Vòng tiếp theo", systemImage: "arrow.right")
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
            word.correct = min(max(0, item.correct ?? 0), VocabularyStore.target)
            word.addedAt = date(item.addedAt) ?? Date()
            word.lastPracticed = date(item.lastPracticed)
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

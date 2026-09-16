//
//  CloudSync.swift
//  Đồng bộ tiến độ học qua iCloud của chính người dùng (NSUbiquitousKeyValueStore):
//  câu đã thuộc, câu đã lưu, từ vựng, tình huống tự tạo, nhật ký chuỗi ngày.
//
//  Gộp chứ không ghi đè: mỗi máy có thể học tiếp khi offline, gặp nhau thì lấy phần nhiều hơn.
//  Không có máy chủ riêng, dữ liệu nằm trong iCloud của người dùng.
//

import SwiftUI

struct CloudSnapshot: Codable {
    var updatedAt = Date()
    /// Mỗi câu luyện nói đã đọc đúng bao nhiêu lần.
    var phraseCounts: [String: Int] = [:]
    var savedPhrases: [SavedPhrase] = []
    var vocabulary: [VocabWord] = []
    var customScenarios: [String] = []
    var dailyLog: [String: StreakStore.Day] = [:]
    var bestStreak = 0
}

final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    static let enabledKey = "iCloudSyncEnabled"
    private static let snapshotKey = "progressSnapshot"
    private static let lastSyncedKey = "iCloudLastSynced"

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSynced: Date?
    @Published var errorMessage: String?

    /// Người dùng bật/tắt đồng bộ; mặc định bật khi đã đăng nhập.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue { syncNow() }
        }
    }

    private let cloud = NSUbiquitousKeyValueStore.default
    private var observers: [NSObjectProtocol] = []

    private init() {
        lastSynced = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
    }

    /// Gọi lúc app khởi động: nghe thay đổi từ máy khác và đồng bộ mỗi lần mở app.
    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            self?.pullAndMerge()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncNow()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.push()
        })
        syncNow()
    }

    /// Kéo dữ liệu trên iCloud về, gộp với máy này rồi đẩy bản đã gộp lên.
    func syncNow() {
        guard canSync else { return }
        isSyncing = true
        cloud.synchronize()
        pullAndMerge()
        push()
        isSyncing = false
        lastSynced = Date()
        UserDefaults.standard.set(lastSynced, forKey: Self.lastSyncedKey)
    }

    private var canSync: Bool {
        AccountStore.shared.isSignedIn && isEnabled && FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Đọc / ghi

    private func pullAndMerge() {
        guard canSync,
              let data = cloud.data(forKey: Self.snapshotKey),
              let remote = try? JSONDecoder().decode(CloudSnapshot.self, from: data)
        else { return }
        Self.merge(remote)
    }

    private func push() {
        guard canSync, let data = try? JSONEncoder().encode(Self.localSnapshot()) else { return }
        // Giới hạn mỗi khoá là 1 MB; vượt thì bỏ qua để iCloud không im lặng nuốt dữ liệu.
        guard data.count < 900_000 else {
            errorMessage = "Dữ liệu học đã vượt dung lượng đồng bộ iCloud (1 MB)."
            return
        }
        cloud.set(data, forKey: Self.snapshotKey)
        cloud.synchronize()
    }

    // MARK: - Máy này

    static func localSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            updatedAt: Date(),
            phraseCounts: UserDefaults.standard.dictionary(forKey: PhraseStore.countsKey) as? [String: Int] ?? [:],
            savedPhrases: SharedStore.savedPhrases(),
            vocabulary: VocabularyStore.shared.words,
            customScenarios: UserDefaults.standard.stringArray(forKey: ScenarioStore.customKey) ?? [],
            dailyLog: StreakStore.logSnapshot,
            bestStreak: StreakStore.best
        )
    }

    /// Gộp bản trên iCloud vào máy này: giữ phần học được nhiều hơn của cả hai bên.
    static func merge(_ remote: CloudSnapshot) {
        // Câu luyện nói: mỗi câu lấy số lần đọc đúng cao hơn.
        var counts = UserDefaults.standard.dictionary(forKey: PhraseStore.countsKey) as? [String: Int] ?? [:]
        var countsChanged = false
        for (id, value) in remote.phraseCounts where value > (counts[id] ?? 0) {
            counts[id] = value
            countsChanged = true
        }
        if countsChanged {
            UserDefaults.standard.set(counts, forKey: PhraseStore.countsKey)
        }

        // Câu đã lưu: theo chữ Hán, giữ bản lưu sớm hơn.
        var savedByZh = Dictionary(grouping: SharedStore.savedPhrases(), by: \.zh).compactMapValues(\.first)
        var addedPhrase = false
        for phrase in remote.savedPhrases where savedByZh[phrase.zh] == nil {
            savedByZh[phrase.zh] = phrase
            addedPhrase = true
        }
        if addedPhrase {
            SharedStore.replaceSavedPhrases(savedByZh.values.sorted { $0.savedAt < $1.savedAt })
        }

        VocabularyStore.shared.merge(remote.vocabulary)

        // Tình huống tự tạo: máy này trước, rồi thêm cái mới của máy kia.
        var scenarios = UserDefaults.standard.stringArray(forKey: ScenarioStore.customKey) ?? []
        for title in remote.customScenarios where !scenarios.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
            scenarios.append(title)
        }
        UserDefaults.standard.set(Array(scenarios.prefix(50)), forKey: ScenarioStore.customKey)

        StreakStore.merge(log: remote.dailyLog, best: remote.bestStreak)

        NotificationCenter.default.post(name: .cloudSyncMerged, object: nil)
    }
}

extension Notification.Name {
    /// Vừa gộp dữ liệu từ iCloud: màn hình đang mở nên đọc lại số liệu.
    static let cloudSyncMerged = Notification.Name("cloudSyncMerged")
}

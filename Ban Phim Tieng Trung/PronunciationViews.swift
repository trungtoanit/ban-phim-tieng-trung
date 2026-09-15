//
//  PronunciationViews.swift
//  Tab "Học phát âm" (21 thanh mẫu, 36 vận mẫu, 4 thanh điệu) và tab "Sửa lỗi" gom những chỗ
//  người học đọc sai ở mọi màn hình theo thanh mẫu, vận mẫu, thanh điệu.
//

import SwiftUI

private let accentRed = Color(red: 0.86, green: 0.17, blue: 0.16)

// MARK: - Dữ liệu lỗi

/// Lỗi đã ghi, gom theo từng âm để hiện ở hai tab.
final class MistakeStore: ObservableObject {
    struct SoundStat: Identifiable {
        let kind: SoundGuide.Kind
        let key: String
        let mistakes: [PronunciationMistake]
        /// Âm máy nghe thành, nhiều nhất trước.
        let confusions: [(key: String, count: Int)]

        var id: String { "\(kind.rawValue)-\(key)" }
        var count: Int { mistakes.count }
    }

    @Published private(set) var mistakes: [PronunciationMistake] = []
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .pronunciationLogChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Bàn phím ghi lỗi từ tiến trình khác, không bắn thông báo sang được: mở tab thì đọc lại.
    func reload() {
        mistakes = PronunciationLog.all().sorted { $0.date > $1.date }
    }

    var unclear: [PronunciationMistake] { mistakes.filter(\.isUnclear) }

    /// Một chữ/từ và mọi lần đọc sai của nó.
    struct WordStat: Identifiable {
        let zh: String
        let mistakes: [PronunciationMistake]

        var id: String { zh }
        var count: Int { mistakes.count }
        /// Cách đọc đúng hay gặp nhất (chữ nhiều âm có thể có hơn một).
        var expected: String {
            Dictionary(grouping: mistakes, by: \.expected).max { $0.value.count < $1.value.count }?.key ?? ""
        }
        var lastDate: Date { mistakes.map(\.date).max() ?? .distantPast }

        /// Số lần sai theo từng phần; lỗi chưa rõ đếm riêng.
        var partCounts: [(label: String, count: Int)] {
            var result: [(String, Int)] = []
            for part in PronunciationPart.allCases {
                let count = mistakes.filter { $0.parts.contains(part) }.count
                if count > 0 { result.append((part.label, count)) }
            }
            let unclear = mistakes.filter(\.isUnclear).count
            if unclear > 0 { result.append(("Chưa rõ", unclear)) }
            return result
        }

        /// Một lần ghi cho mỗi kiểu sai khác nhau, để luyện lần lượt từng kiểu.
        var drillQueue: [PronunciationMistake] {
            var seen = Set<String>()
            return mistakes.filter { seen.insert("\($0.expected)|\($0.heardZh ?? "?")").inserted }
        }
    }

    /// Chữ/từ hay đọc sai nhất: mỗi lần sai đếm một, nhiều nhất ở trên.
    var wordStats: [WordStat] {
        Dictionary(grouping: mistakes, by: \.zh)
            .map { WordStat(zh: $0.key, mistakes: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.lastDate > $1.lastDate }
    }

    func stats(_ kind: SoundGuide.Kind) -> [SoundStat] {
        var grouped: [String: [PronunciationMistake]] = [:]
        var heardCounts: [String: [String: Int]] = [:]
        for mistake in mistakes where mistake.parts.contains(kind.part) {
            guard let expected = mistake.expectedSyllable, let heard = mistake.heardSyllable else { continue }
            let key = PinyinGuide.key(kind, of: expected)
            grouped[key, default: []].append(mistake)
            heardCounts[key, default: [:]][PinyinGuide.key(kind, of: heard), default: 0] += 1
        }
        return grouped.map { key, list in
            let confusions = (heardCounts[key] ?? [:])
                .map { (key: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            return SoundStat(kind: kind, key: key, mistakes: list, confusions: confusions)
        }
        .sorted { $0.count > $1.count }
    }

    func stat(_ kind: SoundGuide.Kind, key: String) -> SoundStat? {
        stats(kind).first { $0.key == key }
    }

    func count(_ kind: SoundGuide.Kind, key: String) -> Int {
        stat(kind, key: key)?.count ?? 0
    }

    /// Đã luyện xong một âm: bỏ phần lỗi đó khỏi các lần ghi. Lần ghi nào không còn lỗi gì thì xoá.
    func resolve(_ kind: SoundGuide.Kind, key: String) {
        PronunciationLog.update { list in
            for index in list.indices where list[index].parts.contains(kind.part) {
                guard let expected = list[index].expectedSyllable,
                      PinyinGuide.key(kind, of: expected) == key else { continue }
                list[index].parts.removeAll { $0 == kind.part }
            }
            list.removeAll { !$0.isUnclear && $0.parts.isEmpty }
        }
    }

    func delete(_ ids: Set<UUID>) {
        PronunciationLog.update { $0.removeAll { ids.contains($0.id) } }
    }

    func deleteAll() {
        PronunciationLog.update { $0.removeAll() }
    }
}

// MARK: - Tab học phát âm

struct SoundsTabView: View {
    @StateObject private var log = MistakeStore()
    @State private var kind: SoundGuide.Kind = .final

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Loại âm", selection: $kind) {
                        Text("Thanh mẫu").tag(SoundGuide.Kind.initial)
                        Text("Vận mẫu").tag(SoundGuide.Kind.final)
                        Text("Thanh điệu").tag(SoundGuide.Kind.tone)
                    }
                    .pickerStyle(.segmented)

                    Text(intro)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if kind == .tone {
                        toneSection
                    } else {
                        ForEach(PinyinGuide.groups(kind), id: \.name) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.name.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                                    ForEach(group.guides) { guide in
                                        NavigationLink(value: guide) {
                                            SoundCell(guide: guide, mistakes: log.count(guide.kind, key: guide.key))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Học phát âm")
            .navigationDestination(for: SoundGuide.self) { guide in
                SoundDetailView(guide: guide, log: log)
            }
            .navigationDestination(for: MistakeDrill.self) { drill in
                PronunciationDrillView(drill: drill)
            }
            .onAppear { log.reload() }
        }
    }

    private var intro: String {
        switch kind {
        case .initial: "21 thanh mẫu (phụ âm đầu). Chú ý các cặp chỉ khác nhau ở luồng hơi: b–p, d–t, g–k, j–q, zh–ch, z–c."
        case .final: "36 vận mẫu (phần vần). Chạm vào từng vần để xem cách đọc, nghe ví dụ và những lần bạn đọc sai."
        case .tone: "4 thanh điệu và thanh nhẹ. Cùng một âm \"ma\" mà đổi thanh là đổi nghĩa: mẹ, tê, ngựa, mắng."
        }
    }

    private var toneSection: some View {
        VStack(spacing: 12) {
            ForEach(PinyinGuide.tones + [PinyinGuide.neutralTone]) { guide in
                NavigationLink(value: guide) {
                    HStack(spacing: 14) {
                        ToneContourView(tone: guide.key)
                            .frame(width: 58, height: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(guide.symbol)
                                .font(.headline)
                            Text(guide.group)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(guide.examples.map { "\($0.zh) \($0.py)" }.joined(separator: "  ·  "))
                                .font(.subheadline)
                        }
                        Spacer()
                        let count = log.count(.tone, key: guide.key)
                        if count > 0 { MistakeBadge(count: count) }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }

            ToneQuizView()
        }
    }
}

private struct SoundCell: View {
    let guide: SoundGuide
    let mistakes: Int

    /// Cách viết tắt khi đứng sau phụ âm.
    private static let written = ["iou": "iu", "uei": "ui", "uen": "un"]

    var body: some View {
        VStack(spacing: 4) {
            Text(guide.key)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(accentRed)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let short = Self.written[guide.key] {
                Text("viết \(short)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let example = guide.examples.first {
                Text("\(example.zh) \(example.py)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .overlay(alignment: .topTrailing) {
            if mistakes > 0 {
                MistakeBadge(count: mistakes)
                    .offset(x: 4, y: -6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(mistakes > 0 ? "Đã đọc sai \(mistakes) lần" : "")
    }
}

private struct MistakeBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(accentRed))
    }
}

/// Đường cao độ của thanh điệu trên thang 5 bậc.
struct ToneContourView: View {
    let tone: String
    var color: Color = accentRed

    var body: some View {
        Canvas { context, size in
            let levels = PinyinGuide.contour(tone: tone)
            func point(_ index: Int) -> CGPoint {
                let x = levels.count > 1 ? size.width * 0.12 + size.width * 0.76 * CGFloat(index) / CGFloat(levels.count - 1) : size.width / 2
                let y = size.height * (1 - CGFloat(levels[index] - 1) / 4) * 0.8 + size.height * 0.1
                return CGPoint(x: x, y: y)
            }
            for step in 0...4 {
                let y = size.height * 0.1 + size.height * 0.8 * CGFloat(step) / 4
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                               with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            }
            var path = Path()
            path.move(to: point(0))
            if levels.count > 2 {
                for index in 1..<levels.count {
                    let previous = point(index - 1), current = point(index)
                    path.addQuadCurve(to: current, control: CGPoint(x: (previous.x + current.x) / 2, y: index == 1 ? current.y : previous.y))
                }
            } else if levels.count == 2 {
                path.addLine(to: point(1))
            } else {
                path.addLine(to: CGPoint(x: point(0).x + 1, y: point(0).y))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Luyện nghe thanh điệu

private struct ToneQuizView: View {
    private struct Question: Equatable {
        let zh: String
        let py: String
        let tone: Int
    }

    private static let sets: [[(String, String)]] = [
        [("妈", "mā"), ("麻", "má"), ("马", "mǎ"), ("骂", "mà")],
        [("八", "bā"), ("拔", "bá"), ("把", "bǎ"), ("爸", "bà")],
        [("汤", "tāng"), ("糖", "táng"), ("躺", "tǎng"), ("烫", "tàng")],
        [("衣", "yī"), ("姨", "yí"), ("椅", "yǐ"), ("意", "yì")],
        [("通", "tōng"), ("同", "tóng"), ("统", "tǒng"), ("痛", "tòng")],
    ]

    @State private var question = Self.random()
    @State private var answer: Int?
    @State private var correct = 0
    @State private var total = 0

    private static func random(excluding previous: Question? = nil) -> Question {
        while true {
            let set = sets.randomElement()!
            let tone = Int.random(in: 1...4)
            let item = set[tone - 1]
            let next = Question(zh: item.0, py: item.1, tone: tone)
            if next != previous { return next }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Luyện nghe thanh điệu", systemImage: "ear")
                    .font(.headline)
                Spacer()
                if total > 0 {
                    Text("\(correct)/\(total)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text("Nghe chữ rồi chọn thanh điệu bạn nghe được.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                NaturalSpeaker.chinese.speak(question.zh)
            } label: {
                Label(answer == nil ? "Nghe" : "Nghe lại", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accentRed))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { tone in
                    Button {
                        guard answer == nil else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { answer = tone }
                        total += 1
                        if tone == question.tone { correct += 1 }
                        UINotificationFeedbackGenerator().notificationOccurred(tone == question.tone ? .success : .error)
                    } label: {
                        VStack(spacing: 4) {
                            ToneContourView(tone: String(tone), color: tint(for: tone))
                                .frame(height: 26)
                            Text("Thanh \(tone)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint(for: tone))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(tint(for: tone).opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let answer {
                HStack {
                    Image(systemName: answer == question.tone ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(answer == question.tone ? .green : accentRed)
                    Text("\(question.zh)  \(question.py) — thanh \(question.tone)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Câu tiếp") {
                        withAnimation { self.answer = nil }
                        question = Self.random(excluding: question)
                        NaturalSpeaker.chinese.speak(question.zh)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(accentRed)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func tint(for tone: Int) -> Color {
        guard let answer else { return .primary }
        if tone == question.tone { return .green }
        return tone == answer ? accentRed : .secondary
    }
}

// MARK: - Chi tiết một âm

struct SoundDetailView: View {
    let guide: SoundGuide
    @ObservedObject var log: MistakeStore
    @State private var confirmResolve = false

    var body: some View {
        let stat = log.stat(guide.kind, key: guide.key)
        List {
            Section {
                VStack(spacing: 8) {
                    if guide.kind == .tone {
                        ToneContourView(tone: guide.key)
                            .frame(width: 120, height: 80)
                    }
                    Text(guide.symbol)
                        .font(.system(size: guide.kind == .tone ? 30 : 52, weight: .bold, design: .rounded))
                        .foregroundStyle(accentRed)
                    Text("\(guide.kind.label) · \(guide.group)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            let drill = PinyinGuide.toneDrill(for: guide)
            if !drill.isEmpty {
                Section {
                    ToneDrillCard(items: drill)
                } header: {
                    Text(drill.count == 4 ? "Luyện 4 thanh điệu" : "Luyện thanh điệu")
                } footer: {
                    Text("Chạm micro rồi đọc từng chữ. Micro tự mở lại cho tới khi bạn đọc đúng hết các thanh.")
                }
            }

            Section("Cách đọc") {
                Label {
                    Text(guide.tip)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(accentRed)
                }
            }

            Section("Ví dụ") {
                ForEach(guide.examples, id: \.self) { example in
                    Button {
                        NaturalSpeaker.chinese.speak(example.zh)
                    } label: {
                        HStack(spacing: 14) {
                            Text(example.zh)
                                .font(.system(size: 30))
                                .foregroundStyle(.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example.py)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(example.vi)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(accentRed)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let stat {
                Section {
                    ForEach(stat.confusions, id: \.key) { confusion in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Hay đọc thành")
                                    .foregroundStyle(.secondary)
                                Text(PinyinGuide.label(guide.kind, key: confusion.key))
                                    .font(.headline)
                                    .foregroundStyle(accentRed)
                                Spacer()
                                Text("\(confusion.count) lần")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if let tip = PinyinGuide.pairTip(guide.kind, guide.key, confusion.key) {
                                Label(tip, systemImage: "lightbulb.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Bạn đã đọc sai \(stat.count) lần")
                }

                Section {
                    let recent = Array(stat.mistakes.prefix(10))
                    ForEach(Array(recent.enumerated()), id: \.element.id) { offset, mistake in
                        NavigationLink(value: MistakeDrill(queue: recent, index: offset)) {
                            MistakeRow(mistake: mistake)
                        }
                    }
                } header: {
                    Text("Những lần gần đây")
                } footer: {
                    Text("Chạm vào một lần để luyện lại. Đọc đúng thì lỗi tự xoá.")
                }

                Section {
                    Button {
                        confirmResolve = true
                    } label: {
                        Label("Đã luyện xong âm này", systemImage: "checkmark.seal.fill")
                    }
                    .tint(.green)
                } footer: {
                    Text("Xoá các lỗi \(guide.symbol) khỏi danh sách sửa lỗi. Lần sau đọc sai sẽ được ghi lại từ đầu.")
                }
            }
        }
        .navigationTitle(guide.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Xoá lỗi \(guide.symbol)?", isPresented: $confirmResolve, titleVisibility: .visible) {
            Button("Xoá khỏi danh sách lỗi", role: .destructive) {
                log.resolve(guide.kind, key: guide.key)
            }
            Button("Huỷ", role: .cancel) {}
        }
    }
}

private struct MistakeRow: View {
    let mistake: PronunciationMistake

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                syllable(mistake.zh, mistake.expected, color: .green)
                if let heardZh = mistake.heardZh, let heard = mistake.heard {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    syllable(heardZh, heard, color: accentRed)
                }
                Spacer()
            }
            if !mistake.parts.isEmpty {
                Text(mistake.parts.map(\.label).joined(separator: " · "))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentRed)
            }
            Text(mistake.sentence)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(mistake.source.label) · \(Self.relative.localizedString(for: mistake.date, relativeTo: Date()))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func syllable(_ zh: String, _ pinyin: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(zh)
                .font(.title2)
                .foregroundStyle(.primary)
            Text(pinyin)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Tab sửa lỗi

struct MistakesTabView: View {
    private enum Filter: Hashable {
        case words
        case sound(SoundGuide.Kind)
    }

    @StateObject private var log = MistakeStore()
    @State private var filter: Filter = .words
    @State private var confirmClear = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Loại lỗi", selection: $filter) {
                        Text("Từ hay sai").tag(Filter.words)
                        Text("Thanh mẫu").tag(Filter.sound(.initial))
                        Text("Vận mẫu").tag(Filter.sound(.final))
                        Text("Thanh điệu").tag(Filter.sound(.tone))
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } footer: {
                    Text(footer)
                }

                switch filter {
                case let .sound(kind):
                    let stats = log.stats(kind)
                    if stats.isEmpty {
                        emptyState
                    } else {
                        Section {
                            ForEach(stats) { stat in
                                NavigationLink(value: guide(for: stat)) {
                                    StatRow(stat: stat)
                                }
                            }
                        }
                    }
                case .words:
                    let words = log.wordStats
                    if words.isEmpty {
                        emptyState
                    } else {
                        Section {
                            // Học lại cả loạt: mỗi từ một lượt, từ sai nhiều nhất trước.
                            NavigationLink(value: MistakeDrill(queue: words.prefix(20).compactMap(\.drillQueue.first), index: 0)) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Học lại \(min(words.count, 20)) từ hay sai")
                                            .font(.headline)
                                        Text("Đọc đúng từ nào thì từ đó được xoá khỏi danh sách.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "graduationcap.fill")
                                        .foregroundStyle(accentRed)
                                }
                            }
                        }
                        Section {
                            ForEach(Array(words.enumerated()), id: \.element.id) { rank, word in
                                NavigationLink(value: MistakeDrill(queue: word.drillQueue, index: 0)) {
                                    WordStatRow(word: word, rank: rank + 1)
                                }
                            }
                            .onDelete { offsets in
                                log.delete(Set(offsets.flatMap { words[$0].mistakes.map(\.id) }))
                            }
                        } footer: {
                            Text("Mỗi lần đọc sai được đếm một lần. Chạm vào từ để luyện lại; vuốt sang trái để xoá.")
                        }
                    }
                }
            }
            .navigationTitle("Sửa lỗi phát âm")
            .navigationDestination(for: SoundGuide.self) { guide in
                SoundDetailView(guide: guide, log: log)
            }
            .navigationDestination(for: MistakeDrill.self) { drill in
                PronunciationDrillView(drill: drill)
            }
            .toolbar {
                if !log.mistakes.isEmpty {
                    Menu {
                        Button("Xoá tất cả lỗi", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Tuỳ chọn")
                }
            }
            .confirmationDialog("Xoá toàn bộ lỗi đã ghi?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Xoá tất cả", role: .destructive) { log.deleteAll() }
                Button("Huỷ", role: .cancel) {}
            }
            .onAppear {
                log.reload()
                focusOnMistakes()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { log.reload() }
            }
            // Có lỗi mới, hoặc vừa sửa hết lỗi của mục đang xem: chuyển sang mục còn lỗi.
            .onChange(of: log.mistakes) { _ in focusOnMistakes() }
        }
    }

    private static let filters: [Filter] = [.words, .sound(.initial), .sound(.final), .sound(.tone)]

    private func hasMistakes(_ filter: Filter) -> Bool {
        switch filter {
        case .words: !log.mistakes.isEmpty
        case let .sound(kind): !log.stats(kind).isEmpty
        }
    }

    /// Mục đang xem trống mà mục khác có lỗi thì mở mục có lỗi đầu tiên — số đỏ trên tab
    /// báo có lỗi thì vào là phải thấy lỗi ngay.
    private func focusOnMistakes() {
        guard !hasMistakes(filter), let first = Self.filters.first(where: hasMistakes) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { filter = first }
    }

    private var footer: String {
        switch filter {
        case .sound(.initial): "Phụ âm đầu bạn đọc sai, nhiều nhất ở trên. Chạm vào để xem cách sửa."
        case .sound(.final): "Phần vần bạn đọc sai, nhiều nhất ở trên. Chạm vào để xem cách sửa."
        case .sound(.tone): "Thanh điệu bạn đọc sai, nhiều nhất ở trên. Chạm vào để xem cách sửa."
        case .words: "Chữ và từ bạn hay đọc sai nhất, gồm cả những chữ máy nghe không chắc."
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Chưa có lỗi nào ở mục này")
                    .font(.headline)
                Text("Luyện nói, hội thoại hay nói qua bàn phím — chỗ nào máy nghe ra chữ khác sẽ được ghi lại ở đây kèm cách sửa.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func guide(for stat: MistakeStore.SoundStat) -> SoundGuide {
        PinyinGuide.guide(stat.kind, key: stat.key)
            ?? SoundGuide(kind: stat.kind, key: stat.key, symbol: PinyinGuide.label(stat.kind, key: stat.key),
                          group: stat.kind.label, tip: "Nghe lại các ví dụ bên dưới và đọc chậm theo.",
                          examples: [], isExtra: true)
    }
}

private struct WordStatRow: View {
    let word: MistakeStore.WordStat
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(rank <= 3 ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(rank <= 3 ? accentRed : Color(.tertiarySystemFill)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.zh)
                        .font(.system(size: 28, weight: .semibold))
                    Text(word.expected)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Text(word.partCounts.map { "\($0.label) \($0.count)" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("\(word.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(accentRed)
                Text("lần")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatRow: View {
    let stat: MistakeStore.SoundStat

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if stat.kind == .tone {
                    ToneContourView(tone: stat.key)
                        .frame(width: 44, height: 34)
                } else {
                    Text(stat.key.isEmpty ? "∅" : stat.key)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(accentRed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 56, height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accentRed.opacity(0.1)))

            VStack(alignment: .leading, spacing: 3) {
                // Ô bên trái đã có ký hiệu âm; tiêu đề nói âm đó thuộc nhóm nào.
                Text(stat.kind == .tone
                     ? PinyinGuide.label(.tone, key: stat.key)
                     : PinyinGuide.guide(stat.kind, key: stat.key)?.group ?? stat.kind.label)
                    .font(.headline)
                Text("Hay đọc thành: " + stat.confusions.prefix(3)
                    .map { "\(PinyinGuide.label(stat.kind, key: $0.key)) (\($0.count))" }
                    .joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(stat.count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accentRed)
        }
        .padding(.vertical, 2)
    }
}

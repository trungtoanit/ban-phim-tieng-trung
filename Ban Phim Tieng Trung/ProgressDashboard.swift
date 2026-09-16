//
//  ProgressDashboard.swift
//  "📈 Tiếng Trung của bạn tiến bộ thế nào" trên tường: so sánh lúc mới học với gần đây,
//  biểu đồ theo tuần (Swift Charts), kho chữ Hán, giờ hay luyện, lỗi hay gặp / đã khắc phục.
//  Dữ liệu: api/social.php?action=progress&id=.
//

import Charts
import SwiftUI

// MARK: - Dữ liệu

struct LearningProgress: Decodable {
    struct Weeks: Decodable {
        var labels: [String] = []
        var sentences: [Double?] = []
        var cleanRate: [Double?] = []
        var accuracy: [Double?] = []
        var cpm: [Double?] = []
        var chars: [Double?] = []

        enum CodingKeys: String, CodingKey { case labels, sentences, cleanRate, accuracy, cpm, chars }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            labels = (try? c.decodeIfPresent([String].self, forKey: .labels)) ?? []
            sentences = (try? c.decodeIfPresent([Double?].self, forKey: .sentences)) ?? []
            cleanRate = (try? c.decodeIfPresent([Double?].self, forKey: .cleanRate)) ?? []
            accuracy = (try? c.decodeIfPresent([Double?].self, forKey: .accuracy)) ?? []
            cpm = (try? c.decodeIfPresent([Double?].self, forKey: .cpm)) ?? []
            chars = (try? c.decodeIfPresent([Double?].self, forKey: .chars)) ?? []
        }
    }

    /// Lúc mới học (20 lần đầu) hoặc gần đây (20 lần cuối).
    struct Window: Decodable {
        var accuracy: Double?
        var cpm: Double?
        var length: Double?
        var count = 0
        var cleanRate: Double?

        enum CodingKeys: String, CodingKey { case accuracy, cpm, length, count, cleanRate }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accuracy = try? c.decodeIfPresent(Double.self, forKey: .accuracy)
            cpm = try? c.decodeIfPresent(Double.self, forKey: .cpm)
            length = try? c.decodeIfPresent(Double.self, forKey: .length)
            count = Int((try? c.decodeIfPresent(Double.self, forKey: .count)) ?? 0)
            cleanRate = try? c.decodeIfPresent(Double.self, forKey: .cleanRate)
        }
    }

    struct Mistake: Decodable, Hashable {
        var expected = ""
        var heard = ""
        var times = 0

        enum CodingKeys: String, CodingKey { case expected, heard, times }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            expected = (try? c.decodeIfPresent(String.self, forKey: .expected)) ?? ""
            heard = (try? c.decodeIfPresent(String.self, forKey: .heard)) ?? ""
            times = Int((try? c.decodeIfPresent(Double.self, forKey: .times)) ?? 0)
        }
    }

    var weeks = Weeks()
    var first = Window()
    var recent = Window()
    var charsUsed = 0
    var sentences = 0
    var hours: [Int] = []
    var mistakes: [Mistake] = []
    var fixed: [Mistake] = []
    var isMe = false

    enum CodingKeys: String, CodingKey { case weeks, first, recent, charsUsed, sentences, hours, mistakes, fixed, isMe }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeks = (try? c.decodeIfPresent(Weeks.self, forKey: .weeks)) ?? Weeks()
        first = (try? c.decodeIfPresent(Window.self, forKey: .first)) ?? Window()
        recent = (try? c.decodeIfPresent(Window.self, forKey: .recent)) ?? Window()
        charsUsed = Int((try? c.decodeIfPresent(Double.self, forKey: .charsUsed)) ?? 0)
        sentences = Int((try? c.decodeIfPresent(Double.self, forKey: .sentences)) ?? 0)
        hours = ((try? c.decodeIfPresent([Double?].self, forKey: .hours)) ?? []).map { Int($0 ?? 0) }
        mistakes = (try? c.decodeIfPresent([Mistake].self, forKey: .mistakes)) ?? []
        fixed = (try? c.decodeIfPresent([Mistake].self, forKey: .fixed)) ?? []
        isMe = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
    }
}

enum ProgressAPI {
    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
        let login: Bool?
        let progress: LearningProgress?
    }

    static func progress(userId: Int) async throws -> LearningProgress {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Hãy đăng nhập để xem tiến bộ.", needsLogin: true)
        }
        var components = URLComponents(url: WebBackend.baseURL.appendingPathComponent("api/social.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: "progress"), URLQueryItem(name: "id", value: String(userId))]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.")
        }
        if envelope.login == true {
            throw WebBackendError(message: envelope.error ?? "Phiên đăng nhập đã hết.", needsLogin: true)
        }
        guard envelope.ok, let progress = envelope.progress else {
            throw WebBackendError(message: envelope.error ?? "Chưa tải được tiến bộ.")
        }
        return progress
    }
}

// MARK: - Mục trên tường

struct WallProgressSection: View {
    let userID: Int
    let isMe: Bool
    let name: String
    /// Giữ ở view cha để đổi tab không phải tải lại.
    @Binding var progress: LearningProgress?
    var onTapWord: ((PinyinWord) -> Void)?

    @State private var failed = false
    /// Lỗi đang mở "Cách khắc phục".
    @State private var fixing: MistakeFixRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isMe ? "📈 Tiếng Trung của bạn tiến bộ thế nào" : "📈 Tiếng Trung của \(name) tiến bộ thế nào")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let progress {
                ComparisonCards(progress: progress, userID: userID, isMe: isMe, name: name)
                if hasWeeklySpeech(progress) { accuracySpeedChart(progress) }
                sentencesChart(progress)
                charsChart(progress)
                hoursChart(progress)
                if isMe || progress.isMe {
                    mistakesCard(progress)
                }
            } else if failed {
                Text("Chưa tải được biểu đồ tiến bộ.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }
        .sheet(item: $fixing) { request in
            MistakeFixView(request: request) { word in
                tapWord(word)
            }
        }
        .task(id: userID) {
            guard progress == nil else { return }
            do {
                progress = try await ProgressAPI.progress(userId: userID)
            } catch is CancellationError {
            } catch {
                failed = progress == nil
            }
        }
    }

    // MARK: Biểu đồ

    private struct WeekPoint: Identifiable {
        let index: Int
        let label: String
        let value: Double
        let series: String
        var id: String { "\(series)-\(index)" }
    }

    private func hasWeeklySpeech(_ p: LearningProgress) -> Bool {
        p.weeks.accuracy.contains { $0 != nil } || p.weeks.cpm.contains { $0 != nil }
    }

    private func label(_ p: LearningProgress, _ i: Int) -> String {
        p.weeks.labels.indices.contains(i) ? p.weeks.labels[i] : "\(i + 1)"
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
    }

    private func accuracySpeedChart(_ p: LearningProgress) -> some View {
        var points: [WeekPoint] = []
        for (i, v) in p.weeks.accuracy.enumerated() {
            if let v { points.append(WeekPoint(index: i, label: label(p, i), value: v, series: "Đọc đúng %")) }
        }
        for (i, v) in p.weeks.cpm.enumerated() {
            if let v { points.append(WeekPoint(index: i, label: label(p, i), value: v, series: "Chữ/phút")) }
        }
        return chartCard("Độ chính xác & tốc độ theo tuần") {
            AnimatedChart(reduceMotion: reduceMotion) { grow in
                Chart(points) { point in
                    AreaMark(x: .value("Tuần", point.label), y: .value("Giá trị", point.value * grow),
                             series: .value("Chỉ số", point.series))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Chỉ số", point.series))
                        .opacity(0.15)
                    LineMark(x: .value("Tuần", point.label), y: .value("Giá trị", point.value * grow),
                             series: .value("Chỉ số", point.series))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Chỉ số", point.series))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .symbol(Circle())
                        .symbolSize(24)
                }
                .chartForegroundStyleScale(["Đọc đúng %": Color(red: 0.13, green: 0.62, blue: 0.35), "Chữ/phút": socialRed])
                .chartXScale(domain: p.weeks.labels.isEmpty ? points.map(\.label) : p.weeks.labels)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                .frame(height: 190)
            }
        }
    }

    private func sentencesChart(_ p: LearningProgress) -> some View {
        let points = p.weeks.sentences.enumerated().map {
            WeekPoint(index: $0.offset, label: label(p, $0.offset), value: $0.element ?? 0, series: "Câu")
        }
        return chartCard("Số câu mỗi tuần") {
            AnimatedChart(reduceMotion: reduceMotion) { grow in
                Chart(points) { point in
                    BarMark(x: .value("Tuần", point.label), y: .value("Câu", point.value * grow))
                        .cornerRadius(6)
                        .foregroundStyle(LinearGradient(colors: [socialRed, Color(red: 1, green: 0.55, blue: 0.3)],
                                                        startPoint: .bottom, endPoint: .top))
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                .frame(height: 160)
            }
        }
    }

    private func charsChart(_ p: LearningProgress) -> some View {
        let points = p.weeks.chars.enumerated().map {
            WeekPoint(index: $0.offset, label: label(p, $0.offset), value: $0.element ?? 0, series: "Chữ")
        }
        let gold = Color(red: 0.9, green: 0.62, blue: 0.1)
        return chartCard("Kho chữ Hán") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("🀄")
                    .font(.system(size: 30))
                CountUpNumber(value: Double(p.charsUsed), reduceMotion: reduceMotion)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(gold)
                Text("chữ Hán")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if points.contains(where: { $0.value > 0 }) {
                AnimatedChart(reduceMotion: reduceMotion) { grow in
                    Chart(points) { point in
                        AreaMark(x: .value("Tuần", point.label), y: .value("Chữ", point.value * grow))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [gold.opacity(0.55), gold.opacity(0.05)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Tuần", point.label), y: .value("Chữ", point.value * grow))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(gold)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                    .frame(height: 140)
                }
            }
        }
    }

    @ViewBuilder
    private func hoursChart(_ p: LearningProgress) -> some View {
        let hours = p.hours.count == 24 ? p.hours : Array(repeating: 0, count: 24)
        if let peak = hours.indices.max(by: { hours[$0] < hours[$1] }), hours[peak] > 0 {
            chartCard("Giờ bạn hay luyện") {
                HStack(spacing: 6) {
                    Text(Self.peakTitle(peak))
                        .font(.subheadline.weight(.bold))
                    Text("· hay luyện nhất lúc \(peak)h")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                AnimatedChart(reduceMotion: reduceMotion) { grow in
                    Chart(Array(hours.enumerated()), id: \.offset) { item in
                        BarMark(x: .value("Giờ", item.offset), y: .value("Câu", Double(item.element) * grow), width: .ratio(0.7))
                            .cornerRadius(3)
                            .foregroundStyle(item.offset == peak ? socialRed : socialRed.opacity(0.25))
                    }
                    .chartXScale(domain: -0.5...23.5)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                            AxisGridLine()
                            AxisValueLabel { Text("\(value.as(Int.self) ?? 0)h") }
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 120)
                }
            }
        }
    }

    static func peakTitle(_ hour: Int) -> String {
        switch hour {
        case 4..<10: return "🌅 Chim sớm"
        case 10..<17: return "☀️ Buổi trưa"
        case 17..<21: return "🌆 Buổi tối"
        default: return "🌙 Cú đêm"
        }
    }

    // MARK: Lỗi hay gặp / đã khắc phục

    @ViewBuilder
    private func mistakesCard(_ p: LearningProgress) -> some View {
        if !p.mistakes.isEmpty || !p.fixed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !p.mistakes.isEmpty {
                    Text("🎯 Lỗi hay gặp")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(p.mistakes, id: \.self) { mistake in
                            mistakeChip(mistake)
                        }
                    }
                }
                if !p.fixed.isEmpty {
                    Text("✅ Đã khắc phục")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Array(p.fixed.enumerated()), id: \.offset) { index, item in
                            FixedChip(item: item, delay: Double(index) * 0.12, reduceMotion: reduceMotion) {
                                tapWord(item.expected)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private func pinyin(_ text: String) -> String {
        ChineseText.containsHan(text) ? ChineseText.words(for: text).map(\.py).joined(separator: " ") : ""
    }

    private func tapWord(_ text: String) {
        guard let onTapWord, ChineseText.containsHan(text) else { return }
        let words = ChineseText.words(for: text)
        if words.count == 1, let word = words.first {
            onTapWord(word)
        } else {
            onTapWord(PinyinWord(zh: text, py: words.map(\.py).joined(separator: " ")))
        }
    }

    private func mistakeChip(_ mistake: LearningProgress.Mistake) -> some View {
        Button {
            fixing = MistakeFixRequest(expected: mistake.expected, heard: mistake.heard, times: mistake.times)
        } label: {
            HStack(spacing: 6) {
                VStack(spacing: 0) {
                    Text(pinyin(mistake.expected))
                        .font(.system(size: 10))
                        .foregroundStyle(RubyText.pinyinBlue)
                    Text(mistake.expected)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text("←")
                    .foregroundStyle(.secondary)
                Text(mistake.heard.isEmpty ? "?" : mistake.heard)
                    .font(.system(size: 16))
                    .foregroundStyle(socialRed)
                    .strikethrough(true, color: socialRed.opacity(0.6))
                Text("×\(mistake.times)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(socialRed.opacity(0.08)))
            .overlay(Capsule().strokeBorder(socialRed.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Đọc \(mistake.expected) thành \(mistake.heard), \(mistake.times) lần")
        .accessibilityHint("Xem cách khắc phục")
    }
}

// MARK: - Trước → Bây giờ

private struct ComparisonCards: View {
    let progress: LearningProgress
    let userID: Int
    let isMe: Bool
    let name: String

    /// Thẻ vừa chạm: mở trang phân tích chi tiết.
    @State private var detail: MetricDetailRequest?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Metric: Identifiable {
        let id: String
        let title: String
        let unit: String
        let before: Double?
        let now: Double?
        /// Chỉ số phần trăm: chênh lệch tính bằng điểm; còn lại tính %.
        let isPercent: Bool
        let decimals: Int

        var change: Double? {
            guard let before, let now else { return nil }
            if isPercent { return now - before }
            guard before > 0 else { return nil }
            return (now - before) / before * 100
        }

        /// Mức cải thiện tương đối để chọn banner.
        var relativeGain: Double? {
            guard let before, let now, before > 0 else { return nil }
            return (now - before) / before * 100
        }
    }

    private var metrics: [Metric] {
        [
            Metric(id: "accuracy", title: "Đọc đúng", unit: "%", before: progress.first.accuracy, now: progress.recent.accuracy,
                   isPercent: true, decimals: 0),
            Metric(id: "cpm", title: "Tốc độ", unit: "chữ/phút", before: progress.first.cpm, now: progress.recent.cpm,
                   isPercent: false, decimals: 0),
            Metric(id: "length", title: "Độ dài câu", unit: "chữ", before: progress.first.length, now: progress.recent.length,
                   isPercent: false, decimals: 1),
            Metric(id: "clean", title: "Câu chuẩn", unit: "%", before: progress.first.cleanRate, now: progress.recent.cleanRate,
                   isPercent: true, decimals: 0),
        ]
    }

    private var bestGain: (Metric, Double)? {
        guard progress.recent.count >= 5 else { return nil }
        return metrics.compactMap { m in m.relativeGain.map { (m, $0) } }
            .filter { $0.1 >= 5 }
            .max { $0.1 < $1.1 }
    }

    private func bannerText(_ metric: Metric, _ gain: Double) -> String {
        let who = isMe ? "Bạn" : name
        let pct = Int(gain.rounded())
        switch metric.id {
        case "accuracy": return "🎉 \(who) đọc đúng hơn \(pct)%!"
        case "cpm": return "🎉 \(who) nói nhanh hơn \(pct)%!"
        case "length": return "🎉 Câu của \(isMe ? "bạn" : name) dài hơn \(pct)%!"
        default: return "🎉 Câu chuẩn nhiều hơn \(pct)%!"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if progress.recent.count < 5 {
                HStack(spacing: 10) {
                    Text("🌱").font(.title2)
                    Text(isMe
                         ? "Luyện nói thêm vài câu (ít nhất 5 lần đọc) để thấy mình tiến bộ thế nào nhé!"
                         : "\(name) mới luyện ít, chưa đủ dữ liệu để so sánh.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(onlineGreen.opacity(0.1)))
            }
            if let (metric, gain) = bestGain {
                CelebrationBanner(text: bannerText(metric, gain), reduceMotion: reduceMotion)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(metrics) { metric in
                    Button {
                        if let kind = ProgressMetric(cardID: metric.id) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            detail = MetricDetailRequest(metric: kind, userID: userID, isMe: isMe, name: name)
                        }
                    } label: {
                        MetricCard(metric: metric, reduceMotion: reduceMotion)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                                    .padding(10)
                            }
                    }
                    .buttonStyle(MetricCardPressStyle())
                    .accessibilityHint("Xem phân tích chi tiết")
                }
            }
        }
        .sheet(item: $detail) { request in
            MetricDetailView(request: request)
        }
    }
}

private struct MetricCard: View {
    let metric: ComparisonCards.Metric
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let now = metric.now {
                    CountUpNumber(value: now, decimals: metric.decimals, reduceMotion: reduceMotion)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                } else {
                    Text("–").font(.system(size: 26, weight: .heavy, design: .rounded))
                }
                Text(metric.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text("Trước: \(metric.before.map { Self.format($0, metric.decimals) } ?? "–")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let change = metric.change, abs(change) >= 0.5 {
                    let up = change > 0
                    Text("\(up ? "▲" : "▼") \(Self.format(abs(change), 0))\(metric.isPercent ? "đ" : "%")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(up ? Color(red: 0.1, green: 0.55, blue: 0.25) : socialRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((up ? onlineGreen : socialRed).opacity(0.14)))
                        .accessibilityLabel(up ? "tăng \(Self.format(abs(change), 0))" : "giảm \(Self.format(abs(change), 0))")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
    }

    static func format(_ value: Double, _ decimals: Int) -> String {
        decimals == 0 ? String(Int(value.rounded())) : String(format: "%.\(decimals)f", value)
    }
}

// MARK: - Thành phần hoạt ảnh

/// Số đếm lên từ 0 khi xuất hiện.
struct CountUpNumber: View {
    let value: Double
    var decimals = 0
    let reduceMotion: Bool

    @State private var shown: Double = 0

    var body: some View {
        CountingText(value: shown, decimals: decimals)
            .onAppear { animate() }
            .onChange(of: value) { _ in animate() }
    }

    private func animate() {
        if reduceMotion {
            shown = value
        } else {
            withAnimation(.easeOut(duration: 1.1)) { shown = value }
        }
    }
}

private struct CountingText: View, Animatable {
    var value: Double
    let decimals: Int

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(decimals == 0 ? String(Int(value.rounded())) : String(format: "%.\(decimals)f", value))
            .monospacedDigit()
    }
}

/// Biểu đồ "mọc" từ 0 lên khi xuất hiện.
struct AnimatedChart<Content: View>: View {
    let reduceMotion: Bool
    @ViewBuilder let content: (Double) -> Content

    @State private var grow: Double = 0

    var body: some View {
        content(grow)
            .onAppear {
                if reduceMotion {
                    grow = 1
                } else {
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) { grow = 1 }
                }
            }
    }
}

/// Banner chúc mừng kèm pháo giấy bay một lần.
private struct CelebrationBanner: View {
    let text: String
    let reduceMotion: Bool

    @State private var start = Date()
    @State private var appeared = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [socialRed, Color(red: 1, green: 0.55, blue: 0.2)], startPoint: .leading, endPoint: .trailing))
            )
            .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSince(start)
                        if t < 2.2 {
                            Canvas { context, size in
                                drawConfetti(t: t, context: context, size: size)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                start = Date()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
            }
    }

    private static let colors: [Color] = [.yellow, .white, .orange, .green, .pink]

    private func drawConfetti(t: Double, context: GraphicsContext, size: CGSize) {
        for i in 0..<28 {
            let seed: Double = Double((i * 7919) % 1000) / 1000
            let seed2: Double = Double((i * 104_729) % 1000) / 1000
            let angle: Double = -Double.pi * (0.1 + 0.8 * seed)
            let speed: Double = 90 + 120 * seed2
            let x: CGFloat = size.width * CGFloat(0.2 + 0.6 * seed2) + CGFloat(cos(angle) * speed * t)
            let y: CGFloat = size.height / 2 + CGFloat(sin(angle) * speed * t + 160 * t * t)
            var ctx = context
            ctx.opacity = max(0, 1 - t / 2.2)
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: .radians(t * (3 + 6 * seed)))
            let w: CGFloat = 4 + CGFloat(seed * 4)
            ctx.fill(Path(CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)),
                     with: .color(Self.colors[i % Self.colors.count]))
        }
    }
}

/// Chip "đã khắc phục" với dấu ✓ nảy lên.
private struct FixedChip: View {
    let item: LearningProgress.Mistake
    let delay: Double
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var checked = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(onlineGreen)
                    .scaleEffect(checked ? 1 : 0.2)
                    .opacity(checked ? 1 : 0)
                Text(item.expected)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                if item.times > 0 {
                    Text("từng sai ×\(item.times)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(onlineGreen.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .onAppear {
            if reduceMotion {
                checked = true
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.2 + delay)) { checked = true }
            }
        }
        .accessibilityLabel("Đã khắc phục \(item.expected)")
    }
}

/// Thẻ chỉ số bấm được: thu nhỏ nhẹ khi nhấn.
private struct MetricCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

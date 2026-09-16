//
//  MetricDetail.swift
//  Chạm một thẻ "Trước → Bây giờ": trang phân tích sâu một chỉ số (đọc đúng, tốc độ, độ dài câu, câu chuẩn).
//  Dữ liệu: api/social.php?action=progress_detail&id=&metric=.
//

import Charts
import SwiftUI

// MARK: - Chỉ số

enum ProgressMetric: String, Identifiable {
    case accuracy, speed, length, clean

    var id: String { rawValue }

    /// Id thẻ ở bảng "Trước → Bây giờ".
    init?(cardID: String) {
        switch cardID {
        case "accuracy": self = .accuracy
        case "cpm": self = .speed
        case "length": self = .length
        case "clean": self = .clean
        default: return nil
        }
    }

    var emoji: String {
        switch self {
        case .accuracy: return "🎯"
        case .speed: return "⚡"
        case .length: return "📏"
        case .clean: return "✨"
        }
    }

    var title: String {
        switch self {
        case .accuracy: return "Đọc đúng"
        case .speed: return "Tốc độ nói"
        case .length: return "Độ dài câu"
        case .clean: return "Câu chuẩn"
        }
    }

    var unit: String {
        switch self {
        case .accuracy, .clean: return "%"
        case .speed: return "chữ/phút"
        case .length: return "chữ/câu"
        }
    }

    var decimals: Int { self == .length ? 1 : 0 }

    var note: String? {
        switch self {
        case .speed: return "Người bản xứ nói khoảng 200–300 chữ/phút."
        case .accuracy: return "Tỉ lệ chữ máy nghe đúng khi bạn đọc câu mẫu."
        case .length: return "Số chữ Hán trung bình trong mỗi câu bạn nói."
        case .clean: return "Tỉ lệ câu nói ra không cần sửa lại."
        }
    }

    var tips: [String] {
        switch self {
        case .accuracy:
            return ["Nghe mẫu 2–3 lần rồi mới đọc, chú ý thanh điệu từng chữ.",
                    "Đọc chậm, rõ từng âm tiết trước khi tăng tốc.",
                    "Luyện lại những chữ trong mục \"Lỗi hay gặp\" mỗi ngày."]
        case .speed:
            return ["Đọc theo cụm từ thay vì từng chữ một.",
                    "Bật chế độ rảnh tay để nói liên tục, không ngắt quãng.",
                    "Nhại lại (shadowing) câu mẫu ngay sau khi nghe."]
        case .length:
            return ["Nối hai ý bằng 因为…所以…, 但是, 然后.",
                    "Thêm thời gian, địa điểm, cảm xúc vào câu: 我昨天在家很开心.",
                    "Nếu bí, nói tiếng Việt bằng nút VI rồi nhại lại câu dài hơn."]
        case .clean:
            return ["Xem lại câu đã được sửa và nói lại đúng ngay.",
                    "Dùng những mẫu câu đã nói chuẩn làm khung cho câu mới.",
                    "Đừng ngại câu ngắn: chuẩn trước, dài sau."]
        }
    }

    func format(_ value: Double) -> String {
        decimals == 0 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    /// Độ lệch chuẩn → nhãn độ ổn định.
    func consistencyLabel(_ std: Double) -> String {
        let (good, ok): (Double, Double)
        switch self {
        case .accuracy, .clean: (good, ok) = (8, 15)
        case .speed: (good, ok) = (15, 35)
        case .length: (good, ok) = (1.5, 3)
        }
        if std < good { return "Rất ổn định" }
        if std < ok { return "Khá ổn định" }
        return "Còn dao động"
    }
}

// MARK: - Dữ liệu

struct MetricDetail: Decodable {
    struct Summary: Decodable {
        var first, recent, best, average, median, thisWeek, prevWeek, percentile, community, consistency: Double?

        enum CodingKeys: String, CodingKey {
            case first, recent, best, average, median, thisWeek, prevWeek, percentile, community, consistency
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func d(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
            first = d(.first); recent = d(.recent); best = d(.best); average = d(.average); median = d(.median)
            thisWeek = d(.thisWeek); prevWeek = d(.prevWeek); percentile = d(.percentile)
            community = d(.community); consistency = d(.consistency)
        }
    }

    struct CurvePoint: Decodable, Identifiable {
        var index = 0
        var value = 0.0
        var id: Int { index }

        enum CodingKeys: String, CodingKey { case index, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            index = Int((try? c.decodeIfPresent(Double.self, forKey: .index)) ?? 0)
            value = (try? c.decodeIfPresent(Double.self, forKey: .value)) ?? 0
        }
    }

    struct Day: Decodable, Identifiable {
        var day = ""
        var value: Double?
        var count = 0
        var id: String { day }
        var date: Date { SocialFormat.dayParser.date(from: day) ?? Date() }

        enum CodingKeys: String, CodingKey { case day, value, count }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
            value = (try? c.decodeIfPresent(Double.self, forKey: .value)) ?? nil
            count = Int((try? c.decodeIfPresent(Double.self, forKey: .count)) ?? 0)
        }
    }

    struct Bucket: Decodable, Identifiable {
        var label = ""
        var count = 0
        var id: String { label }

        enum CodingKeys: String, CodingKey { case label, count }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
            count = Int((try? c.decodeIfPresent(Double.self, forKey: .count)) ?? 0)
        }
    }

    struct Example: Decodable, Hashable {
        var text = ""
        var value = 0.0
        var at = ""
        var corrected: String?

        enum CodingKeys: String, CodingKey { case text, value, at, corrected }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
            value = (try? c.decodeIfPresent(Double.self, forKey: .value)) ?? 0
            at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
            corrected = (try? c.decodeIfPresent(String.self, forKey: .corrected)) ?? nil
        }
    }

    struct Examples: Decodable {
        var best: [Example] = []
        var worst: [Example] = []

        enum CodingKeys: String, CodingKey { case best, worst }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            best = (try? c.decodeIfPresent([Example].self, forKey: .best)) ?? []
            worst = (try? c.decodeIfPresent([Example].self, forKey: .worst)) ?? []
        }
    }

    var count = 0
    var summary = Summary()
    var curve: [CurvePoint] = []
    var daily: [Day] = []
    var histogram: [Bucket] = []
    var examples = Examples()
    var isMe = false

    enum CodingKeys: String, CodingKey { case count, summary, curve, daily, histogram, examples, isMe }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = Int((try? c.decodeIfPresent(Double.self, forKey: .count)) ?? 0)
        summary = (try? c.decodeIfPresent(Summary.self, forKey: .summary)) ?? Summary()
        curve = (try? c.decodeIfPresent([CurvePoint].self, forKey: .curve)) ?? []
        daily = (try? c.decodeIfPresent([Day].self, forKey: .daily)) ?? []
        histogram = (try? c.decodeIfPresent([Bucket].self, forKey: .histogram)) ?? []
        examples = (try? c.decodeIfPresent(Examples.self, forKey: .examples)) ?? Examples()
        isMe = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
    }
}

extension ProgressAPI {
    private struct DetailEnvelope: Decodable {
        let ok: Bool
        let error: String?
        let detail: MetricDetail?
    }

    static func detail(userId: Int, metric: ProgressMetric) async throws -> MetricDetail {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Hãy đăng nhập để xem tiến bộ.", needsLogin: true)
        }
        var components = URLComponents(url: WebBackend.baseURL.appendingPathComponent("api/social.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: "progress_detail"),
                                 URLQueryItem(name: "id", value: String(userId)),
                                 URLQueryItem(name: "metric", value: metric.rawValue)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.timeoutInterval = 25
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let envelope = try? JSONDecoder().decode(DetailEnvelope.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.")
        }
        guard envelope.ok, let detail = envelope.detail else {
            throw WebBackendError(message: envelope.error ?? "Chưa tải được phân tích.")
        }
        return detail
    }
}

// MARK: - Màn chi tiết

struct MetricDetailRequest: Identifiable {
    let metric: ProgressMetric
    let userID: Int
    let isMe: Bool
    let name: String
    var id: String { "\(userID)-\(metric.rawValue)" }
}

struct MetricDetailView: View {
    let request: MetricDetailRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: MetricDetail?
    @State private var errorMessage: String?
    @State private var selectedWord: SelectedWord?

    private var metric: ProgressMetric { request.metric }
    private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let detail {
                        if detail.count == 0 {
                            emptyCard
                        } else {
                            summaryTiles(detail)
                            gauge(detail)
                            curveChart(detail)
                            dailyChart(detail)
                            distribution(detail)
                            if request.isMe || detail.isMe { examples(detail) }
                        }
                        tipsCard
                    } else if let errorMessage {
                        VStack(spacing: 10) {
                            Text(errorMessage).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Thử lại") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 30)
                    } else {
                        ProgressView().padding(.top, 40)
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("\(metric.emoji) \(metric.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .wordPopup($selectedWord)
            .task { await load() }
            .refreshable { await load() }
        }
        .tint(socialRed)
    }

    private func load() async {
        errorMessage = nil
        do {
            detail = try await ProgressAPI.detail(userId: request.userID, metric: metric)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Đầu trang

    private var header: some View {
        VStack(spacing: 6) {
            Text(metric.emoji).font(.system(size: 44))
            Text("\(metric.title) (\(metric.unit))")
                .font(.title3.weight(.bold))
            Text(request.isMe ? "Của bạn" : "Của \(request.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = metric.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let count = detail?.count, count > 0 {
                Text("Dựa trên \(count) lần")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Text("🌱").font(.largeTitle)
            Text(request.isMe ? "Chưa có dữ liệu. Luyện nói vài câu rồi quay lại xem nhé!" : "\(request.name) chưa có dữ liệu cho chỉ số này.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: Ô tổng kết

    private func summaryTiles(_ d: MetricDetail) -> some View {
        let s = d.summary
        return VStack(spacing: 10) {
            if let first = s.first, let recent = s.recent {
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("Lúc mới học").font(.caption).foregroundStyle(.secondary)
                        Text(metric.format(first))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(socialRed)
                    VStack(spacing: 2) {
                        Text("Gần đây").font(.caption).foregroundStyle(.secondary)
                        CountUpNumber(value: recent, decimals: metric.decimals, reduceMotion: reduceMotion)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                        deltaPill(recent - first, relativeTo: first)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(14)
                .background(card.fill(Color(.secondarySystemGroupedBackground)))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if let best = s.best { tile("🏆 Tốt nhất", best) }
                if let average = s.average { tile("Trung bình", average) }
                if let median = s.median { tile("Trung vị", median) }
                if let thisWeek = s.thisWeek {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tuần này").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        CountUpNumber(value: thisWeek, decimals: metric.decimals, reduceMotion: reduceMotion)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                        if let prev = s.prevWeek {
                            HStack(spacing: 4) {
                                Text("Tuần trước \(metric.format(prev))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                deltaPill(thisWeek - prev, relativeTo: prev)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(card.fill(Color(.secondarySystemGroupedBackground)))
                }
                if let std = s.consistency {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Độ ổn định").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(metric.consistencyLabel(std))
                            .font(.headline)
                        Text("Độ lệch ±\(metric.format(std)) (30 lần gần nhất)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(card.fill(Color(.secondarySystemGroupedBackground)))
                }
            }
        }
    }

    private func tile(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                CountUpNumber(value: value, decimals: metric.decimals, reduceMotion: reduceMotion)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Text(metric.unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func deltaPill(_ change: Double, relativeTo base: Double) -> some View {
        if abs(change) >= 0.05 {
            let up = change > 0
            let text: String = metric.unit == "%"
                ? "\(metric.format(abs(change))) điểm"
                : (base > 0 ? "\(Int((abs(change) / base * 100).rounded()))%" : metric.format(abs(change)))
            Text("\(up ? "▲" : "▼") \(text)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(up ? Color(red: 0.1, green: 0.55, blue: 0.25) : socialRed)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill((up ? onlineGreen : socialRed).opacity(0.14)))
        }
    }

    // MARK: Đồng hồ so với cộng đồng

    @ViewBuilder
    private func gauge(_ d: MetricDetail) -> some View {
        if let percentile = d.summary.percentile {
            VStack(spacing: 8) {
                SemicircleGauge(fraction: min(1, max(0, percentile / 100)), reduceMotion: reduceMotion)
                    .frame(height: 110)
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            CountUpNumber(value: percentile, reduceMotion: reduceMotion)
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                            Text("%").font(.headline)
                        }
                    }
                Text(request.isMe ? "Bạn hơn \(Int(percentile))% người học" : "\(request.name) hơn \(Int(percentile))% người học")
                    .font(.subheadline.weight(.semibold))
                if let community = d.summary.community {
                    Text("Trung bình cộng đồng (30 ngày): \(metric.format(community)) \(metric.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    // MARK: Biểu đồ

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func curveChart(_ d: MetricDetail) -> some View {
        if d.curve.count >= 2 {
            chartCard("Đường cải thiện") {
                Text("Trung bình trượt 10 câu, từ câu đầu tiên đến gần nhất")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                AnimatedChart(reduceMotion: reduceMotion) { grow in
                    Chart {
                        ForEach(d.curve) { point in
                            AreaMark(x: .value("Câu", point.index), y: .value(metric.title, point.value * grow))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(LinearGradient(colors: [socialRed.opacity(0.3), socialRed.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Câu", point.index), y: .value(metric.title, point.value * grow))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(socialRed)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                        if let first = d.summary.first {
                            RuleMark(y: .value("Lúc mới học", first * grow))
                                .foregroundStyle(.gray)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Lúc mới học").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        if let recent = d.summary.recent {
                            RuleMark(y: .value("Gần đây", recent * grow))
                                .foregroundStyle(onlineGreen)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("Gần đây").font(.caption2).foregroundStyle(onlineGreen)
                                }
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
    }

    @ViewBuilder
    private func dailyChart(_ d: MetricDetail) -> some View {
        if d.daily.contains(where: { $0.count > 0 }) {
            let maxCount = Double(d.daily.map(\.count).max() ?? 1)
            let maxValue = d.daily.compactMap(\.value).max() ?? 1
            // Số lần (cột) vẽ theo thang giá trị để hai lớp chung một trục.
            let scale = maxCount > 0 ? maxValue / maxCount : 1
            chartCard("60 ngày gần nhất") {
                HStack(spacing: 12) {
                    Label("Số lần", systemImage: "square.fill").foregroundStyle(socialRed.opacity(0.35))
                    Label(metric.title, systemImage: "circle.fill").foregroundStyle(socialRed)
                }
                .font(.caption2)
                AnimatedChart(reduceMotion: reduceMotion) { grow in
                    Chart {
                        ForEach(d.daily) { day in
                            BarMark(x: .value("Ngày", day.date, unit: .day), y: .value("Số lần", Double(day.count) * scale * grow))
                                .foregroundStyle(socialRed.opacity(0.25))
                        }
                        ForEach(d.daily.filter { $0.value != nil }) { day in
                            LineMark(x: .value("Ngày", day.date, unit: .day), y: .value(metric.title, (day.value ?? 0) * grow))
                                .foregroundStyle(socialRed)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Ngày", day.date, unit: .day), y: .value(metric.title, (day.value ?? 0) * grow))
                                .foregroundStyle(socialRed)
                                .symbolSize(14)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    @ViewBuilder
    private func distribution(_ d: MetricDetail) -> some View {
        if d.histogram.contains(where: { $0.count > 0 }) {
            chartCard("Phân bố") {
                if metric == .clean, #available(iOS 17.0, *) {
                    DonutChart(buckets: d.histogram, reduceMotion: reduceMotion)
                } else {
                    AnimatedChart(reduceMotion: reduceMotion) { grow in
                        Chart(d.histogram) { bucket in
                            BarMark(x: .value("Khoảng", bucket.label), y: .value("Số lần", Double(bucket.count) * grow))
                                .cornerRadius(6)
                                .foregroundStyle(LinearGradient(colors: [socialRed, Color(red: 1, green: 0.55, blue: 0.3)],
                                                                startPoint: .bottom, endPoint: .top))
                                .annotation(position: .top) {
                                    if grow > 0.95 {
                                        Text("\(bucket.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                    }
                                }
                        }
                        .frame(height: 170)
                    }
                }
            }
        }
    }

    // MARK: Ví dụ (tường của mình)

    @ViewBuilder
    private func examples(_ d: MetricDetail) -> some View {
        if !d.examples.best.isEmpty {
            exampleList("🌟 Câu tốt nhất", d.examples.best, good: true)
        }
        if !d.examples.worst.isEmpty {
            exampleList("💪 Cần luyện thêm", d.examples.worst, good: false)
        }
    }

    private func exampleList(_ title: String, _ items: [MetricDetail.Example], good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        if ChineseText.containsHan(item.text) {
                            RubyText(words: ChineseText.words(for: item.text), hanziSize: 18) { word in
                                selectedWord = SelectedWord(word: word)
                            }
                        } else {
                            Text(item.text).font(.body)
                        }
                        Spacer(minLength: 4)
                        if metric != .clean {
                            Text("\(metric.format(item.value))\(metric.unit == "%" ? "%" : "")")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(good ? Color(red: 0.1, green: 0.55, blue: 0.25) : socialRed)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill((good ? onlineGreen : socialRed).opacity(0.14)))
                        }
                    }
                    if let corrected = item.corrected, !corrected.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text("→")
                                .font(.headline)
                                .foregroundStyle(Color(red: 0.1, green: 0.55, blue: 0.25))
                            if ChineseText.containsHan(corrected) {
                                RubyText(words: ChineseText.words(for: corrected), hanziSize: 17,
                                         hanziColor: Color(red: 0.1, green: 0.55, blue: 0.25)) { word in
                                    selectedWord = SelectedWord(word: word)
                                }
                            } else {
                                Text(corrected).foregroundStyle(Color(red: 0.1, green: 0.55, blue: 0.25))
                            }
                        }
                    }
                    if !item.at.isEmpty {
                        Text(SocialFormat.time(item.at))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: Mẹo

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 Mẹo cải thiện").font(.subheadline.weight(.semibold))
            ForEach(metric.tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(socialRed)
                    Text(tip)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.fill(socialRed.opacity(0.07)))
    }
}

// MARK: - Thành phần

/// Nửa vòng tròn tô dần tới phần trăm.
private struct SemicircleGauge: View {
    let fraction: Double
    let reduceMotion: Bool

    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            let lineWidth: CGFloat = 16
            let radius: CGFloat = min(geo.size.width / 2, geo.size.height) - lineWidth / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - 2)
            ZStack {
                arc(center: center, radius: radius)
                    .stroke(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                arc(center: center, radius: radius)
                    .trim(from: 0, to: shown)
                    .stroke(AngularGradient(colors: [.orange, socialRed, onlineGreen], center: .center,
                                            startAngle: .degrees(180), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .onAppear {
            if reduceMotion {
                shown = fraction
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.15)) { shown = fraction }
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return path
    }
}

@available(iOS 17.0, *)
private struct DonutChart: View {
    let buckets: [MetricDetail.Bucket]
    let reduceMotion: Bool

    @State private var grow: Double = 0

    var body: some View {
        let total = max(1, buckets.map(\.count).reduce(0, +))
        Chart(buckets) { bucket in
            SectorMark(angle: .value("Số lần", Double(bucket.count) * max(0.001, grow)),
                       innerRadius: .ratio(0.62), angularInset: 2)
                .cornerRadius(5)
                .foregroundStyle(by: .value("Loại", bucket.label))
        }
        .chartForegroundStyleScale(["Nói chuẩn": onlineGreen, "Cần sửa": socialRed])
        .chartBackground { _ in
            let clean = buckets.first { $0.label == "Nói chuẩn" }?.count ?? 0
            VStack(spacing: 0) {
                Text("\(Int((Double(clean) / Double(total) * 100).rounded()))%")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text("nói chuẩn").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(height: 200)
        .onAppear {
            if reduceMotion {
                grow = 1
            } else {
                withAnimation(.easeOut(duration: 0.9)) { grow = 1 }
            }
        }
    }
}

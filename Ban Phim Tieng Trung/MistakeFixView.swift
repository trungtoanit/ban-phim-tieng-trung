//
//  MistakeFixView.swift
//  "🛠️ Cách khắc phục" một lỗi phát âm (chạm chip "Lỗi hay gặp" trên tường):
//  so pinyin từng âm tiết (thanh mẫu / vận mẫu / thanh điệu / đồng âm), mẹo sửa, cách đọc gần giống,
//  nghe mẫu và thử đọc lại. Cùng logic và lời văn với assets/mistake-fix.js của website.
//

import SwiftUI

// MARK: - Phân tích

enum MistakeAnalysis {
    struct Syllable {
        let char: String
        let py: String
        let initial: String
        /// Vận mẫu không dấu, dạng viết như pinyin-pro (iu, ui, un…).
        let final: String
        /// 1–4, 0 là thanh nhẹ.
        let tone: Int
    }

    enum Kind: String, CaseIterable, Identifiable {
        case initial, final, tone, length, homophone

        var id: String { rawValue }

        var label: String {
            switch self {
            case .initial: return "Thanh mẫu"
            case .final: return "Vận mẫu"
            case .tone: return "Thanh điệu"
            case .length: return "Khác số âm tiết"
            case .homophone: return "Đồng âm"
            }
        }

        var colors: (background: Color, foreground: Color) {
            switch self {
            case .initial: return (Color(red: 0.99, green: 0.93, blue: 0.92), Color(red: 0.75, green: 0.22, blue: 0.17))
            case .final: return (Color(red: 1, green: 0.96, blue: 0.84), Color(red: 0.6, green: 0.42, blue: 0))
            case .tone: return (Color(red: 0.94, green: 0.91, blue: 1), Color(red: 0.42, green: 0.25, blue: 0.84))
            case .length: return (Color(.tertiarySystemFill), Color(.secondaryLabel))
            case .homophone: return (Color(red: 0.87, green: 0.96, blue: 1), Color(red: 0.08, green: 0.47, blue: 0.66))
            }
        }
    }

    struct Item {
        let expected: Syllable
        let heard: Syllable
        var initial: Bool { heard.initial != expected.initial }
        var final: Bool { heard.final != expected.final }
        var tone: Bool { heard.tone != expected.tone }
        var isWrong: Bool { initial || final || tone }
    }

    struct Result {
        let heard: [Syllable]
        let expected: [Syllable]
        let kinds: [Kind]
        let items: [Item]
    }

    static func syllables(of text: String) -> [Syllable] {
        ChineseText.syllables(for: text).map { char, py in
            guard let parsed = PinyinSyllable(py) else {
                return Syllable(char: char, py: py, initial: "", final: "", tone: 0)
            }
            return Syllable(char: char, py: py, initial: parsed.initial, final: shortFinal(parsed.final),
                            tone: parsed.tone == 5 ? 0 : parsed.tone)
        }
    }

    /// Dạng đầy đủ (iou, uei, uen, -i) → dạng viết thường gặp (iu, ui, un, i).
    private static func shortFinal(_ final: String) -> String {
        switch final {
        case "iou": return "iu"
        case "uei": return "ui"
        case "uen": return "un"
        case "-i": return "i"
        default: return final
        }
    }

    static func analyse(heard: String, expected: String) -> Result {
        let a = syllables(of: heard)
        let b = syllables(of: expected)
        var kinds: [Kind] = []
        var items: [Item] = []
        func add(_ kind: Kind) { if !kinds.contains(kind) { kinds.append(kind) } }
        if !a.isEmpty, !b.isEmpty, a.count != b.count {
            add(.length)
        } else {
            for (i, y) in b.enumerated() where i < a.count {
                let item = Item(expected: y, heard: a[i])
                if item.initial { add(.initial) }
                if item.final { add(.final) }
                if item.tone { add(.tone) }
                items.append(item)
            }
            if kinds.isEmpty, !a.isEmpty { add(.homophone) }
        }
        return Result(heard: a, expected: b, kinds: kinds, items: items)
    }

    // MARK: Mẹo (giống website)

    static let tones: [Int: (name: String, detail: String)] = [
        1: ("Thanh 1", "ngang, cao và giữ đều (như kéo dài “aaa” ở giọng cao)"),
        2: ("Thanh 2", "đi lên từ giữa lên cao (giống dấu sắc, như hỏi lại “hả?”)"),
        3: ("Thanh 3", "xuống thấp rồi hơi lên (giống dấu hỏi kéo dài); trong câu thường chỉ đọc phần thấp"),
        4: ("Thanh 4", "rơi mạnh từ cao xuống thấp, dứt khoát (như quát “đi!”)"),
        0: ("Thanh nhẹ", "đọc ngắn, nhẹ, không nhấn"),
    ]

    static let toneContrast: [String: String] = [
        "3>4": "Bạn đang uốn xuống-lên (thanh 3). Thanh 4 chỉ đi một chiều: rơi thẳng xuống, ngắn và dứt khoát.",
        "4>3": "Bạn rơi xuống dứt khoát (thanh 4). Thanh 3 phải xuống thấp và giữ trầm, không nhấn mạnh.",
        "2>3": "Bạn đi lên (thanh 2). Thanh 3 bắt đầu bằng việc hạ giọng xuống thấp trước.",
        "3>2": "Bạn hạ giọng trước (thanh 3). Thanh 2 đi lên ngay từ đầu, giống dấu sắc.",
        "1>4": "Bạn giữ ngang (thanh 1). Thanh 4 bắt đầu cao rồi rơi mạnh xuống.",
        "4>1": "Bạn rơi xuống (thanh 4). Thanh 1 giữ cao và phẳng tới hết.",
        "1>2": "Bạn giữ ngang (thanh 1). Thanh 2 phải đi lên như hỏi lại.",
        "2>1": "Bạn đi lên (thanh 2). Thanh 1 bắt đầu cao sẵn và giữ phẳng.",
        "2>4": "Bạn đi lên (thanh 2). Thanh 4 ngược lại: rơi xuống.",
        "4>2": "Bạn rơi xuống (thanh 4). Thanh 2 ngược lại: đi lên.",
        "1>3": "Bạn giữ cao (thanh 1). Thanh 3 hạ giọng thật thấp.",
        "3>1": "Bạn hạ thấp (thanh 3). Thanh 1 giữ cao và phẳng.",
    ]

    static let initialTips: [String: String] = [
        "zh": "zh: cong đầu lưỡi lên chạm vòm miệng trên (như “tr” nặng), không bật hơi.",
        "ch": "ch: cong lưỡi như zh nhưng bật mạnh hơi ra (đưa tay trước miệng thấy gió).",
        "sh": "sh: cong đầu lưỡi lên, để hơi xì ra (như “s” nặng của miền Bắc).",
        "r": "r: cong lưỡi như sh nhưng rung cổ họng, gần “r” nhẹ — không đọc thành “l” hay “d”.",
        "z": "z: lưỡi phẳng chạm sau răng trên, đọc gần “ch” nhẹ, không bật hơi.",
        "c": "c: lưỡi phẳng như z nhưng bật mạnh hơi (“tsh”).",
        "s": "s: lưỡi phẳng sau răng, như “x” tiếng Việt.",
        "j": "j: mặt lưỡi áp vòm, gần “ch” tiếng Việt, môi hơi dẹt, không bật hơi.",
        "q": "q: như j nhưng bật mạnh hơi (“ch” bật hơi).",
        "x": "x: đầu lưỡi hạ sau răng dưới, mặt lưỡi gần vòm — như “x” nhưng mỏng hơn.",
        "b": "b: đọc gần “p” không bật hơi (không rung như “b” tiếng Việt).",
        "p": "p: “p” bật mạnh hơi ra.",
        "d": "d: đọc như “t” không bật hơi (không phải “d/z” tiếng Việt).",
        "t": "t: “th” bật mạnh hơi.",
        "g": "g: đọc như “c/k” không bật hơi.",
        "k": "k: “kh” bật hơi mạnh ra từ cuống lưỡi.",
        "h": "h: gần “kh” tiếng Việt, xát nhẹ ở cuống lưỡi.",
        "f": "f: như “ph” tiếng Việt.",
        "l": "l: như “l” tiếng Việt, đầu lưỡi chạm lợi trên.",
        "n": "n: như “n” tiếng Việt — đừng lẫn với “l”.",
        "m": "m: như “m” tiếng Việt.",
    ]

    /// Giữ đúng thứ tự như website: khoá đầu tiên khớp (bằng hoặc là đuôi) được dùng.
    static let finalTips: [(key: String, tip: String)] = [
        ("ang", "-ang: mở miệng to, kết thúc bằng “ng” (miệng không khép) — khác -an (lưỡi chạm lợi)."),
        ("an", "-an: kết thúc bằng “n”, đầu lưỡi chạm lợi trên — khác -ang."),
        ("eng", "-eng: “âng” — kết thúc “ng”, khác -en (“ân”)."),
        ("en", "-en: “ân” — kết thúc bằng “n”, khác -eng."),
        ("ing", "-ing: “inh” — kết thúc “ng”, khác -in."),
        ("in", "-in: “in” — kết thúc bằng “n”, khác -ing (“inh”)."),
        ("ong", "-ong: “ung” tròn môi, kết thúc ng."),
        ("ian", "-ian: đọc “iên” (không phải “ian”)."),
        ("iang", "-iang: “i-ang”, mở miệng rộng, kết thúc ng."),
        ("ü", "ü: môi tròn như “u” nhưng lưỡi đặt như “i” — nói “i” rồi chu môi lại."),
        ("u", "u: “u” tròn môi rõ ràng."),
        ("e", "e: gần “ơ” hơi lùi về sau cổ, không phải “e” tiếng Việt."),
        ("ou", "-ou: “âu”."),
        ("ao", "-ao: “ao”, mở miệng rộng."),
        ("ai", "-ai: “ai”."),
        ("ei", "-ei: “ây”."),
        ("uo", "-uo: “ua” tròn môi (“uô”)."),
        ("ie", "-ie: “iê”."),
        ("i", "i: “i”; sau zh/ch/sh/r/z/c/s đọc gần “ư”."),
        ("iu", "-iu: “iêu” ngắn (“i-âu”)."),
        ("ui", "-ui: “uây”."),
        ("un", "-un: “uân”."),
        ("a", "a: “a” mở miệng rộng."),
        ("o", "o: “ua/ô” tròn môi."),
    ]

    struct Step: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    static func steps(_ r: Result) -> [Step] {
        var steps: [Step] = []
        if r.kinds.contains(.length) {
            steps.append(Step(
                title: "Bạn nói \(r.heard.count) âm tiết nhưng câu chuẩn có \(r.expected.count) (\(r.expected.map(\.py).joined(separator: " "))).",
                detail: "Đọc chậm từng chữ một, tách rõ từng âm tiết rồi mới nối lại. Đừng nuốt âm hay thêm âm."))
        }
        if r.kinds.contains(.homophone) {
            steps.append(Step(
                title: "Cùng cách đọc “\(r.expected.map(\.py).joined(separator: " "))” — phát âm của bạn có thể đã đúng.",
                detail: "Máy nhận nhầm sang chữ đồng âm. Hãy nói cả cụm từ / cả câu có ngữ cảnh, rõ ràng và đủ thanh điệu để máy chọn đúng chữ."))
        }
        for item in r.items where item.isWrong {
            let x = item.heard, y = item.expected
            var parts: [String] = []
            if item.initial { parts.append("phụ âm đầu \(x.initial.isEmpty ? "∅" : x.initial) → \(y.initial.isEmpty ? "∅" : y.initial)") }
            if item.final { parts.append("vần \(x.final) → \(y.final)") }
            if item.tone { parts.append("\(tones[x.tone]?.name ?? "\(x.tone)") → \(tones[y.tone]?.name ?? "\(y.tone)")") }
            var tips: [String] = []
            if item.initial, let tip = initialTips[y.initial] { tips.append(tip) }
            if item.final, let tip = finalTips.first(where: { y.final == $0.key || y.final.hasSuffix($0.key) })?.tip {
                tips.append(tip)
            }
            if item.tone {
                var text = toneContrast["\(x.tone)>\(y.tone)"] ?? ""
                if let tone = tones[y.tone] { text += " \(tone.name): \(tone.detail)." }
                tips.append(text.trimmingCharacters(in: .whitespaces))
            }
            steps.append(Step(title: "\(y.char) (\(y.py)) bị đọc thành \(x.char) (\(x.py)): sai \(parts.joined(separator: ", ")).",
                              detail: tips.joined(separator: " ")))
        }
        steps.append(Step(title: "Luyện 3 bước:",
                          detail: "① Nghe mẫu 2 lần (một lần chậm). ② Đọc to từng chữ theo pinyin, chú ý thanh điệu. ③ Bấm “Thử đọc” — đạt 3 lần liên tiếp là nhớ lâu."))
        return steps
    }
}

// MARK: - Màn cách khắc phục

struct MistakeFixRequest: Identifiable {
    let id = UUID()
    let expected: String
    let heard: String
    let times: Int
}

struct MistakeFixView: View {
    let request: MistakeFixRequest
    /// Mở thẻ nghĩa (word popup) sau khi đóng màn này.
    var onShowMeaning: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var capture = SpeechCapture()
    @State private var insight: WordInsight?
    @State private var insightState = InsightState.loading
    @State private var passes = 0
    @State private var feedback: Feedback?
    @State private var popResult = false

    private enum InsightState { case loading, loaded, hidden }

    private struct Feedback: Equatable {
        let ok: Bool
        let text: String
    }

    private var analysis: MistakeAnalysis.Result {
        MistakeAnalysis.analyse(heard: request.heard, expected: request.expected)
    }

    private let green = Color(red: 0.08, green: 0.42, blue: 0.23)
    private let section = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        let result = analysis
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if request.times > 0 {
                        Text("Bạn đã đọc sai \(request.times) lần")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    compare(result)
                    kindChips(result)
                    diagnosis(result)
                    soundsLike
                    practice
                    Button {
                        let word = request.expected
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onShowMeaning?(word) }
                    } label: {
                        Text("📖 Xem nghĩa & thêm từ vựng")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(socialRed)
                            .background(section.strokeBorder(socialRed.opacity(0.5), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("🛠️ Cách khắc phục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .tint(socialRed)
        .task {
            NaturalSpeaker.chinese.speak(request.expected, preferOpenAI: true)
            await loadInsight()
        }
        .onDisappear {
            capture.cancel()
            NaturalSpeaker.chinese.stop()
        }
    }

    // MARK: So sánh

    private func compare(_ r: MistakeAnalysis.Result) -> some View {
        HStack(alignment: .center, spacing: 8) {
            wordBox(label: "Máy nghe ra", text: request.heard, syllables: r.heard, bad: true)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
            wordBox(label: "Cần đọc", text: request.expected, syllables: r.expected, bad: false)
        }
    }

    private func wordBox(label: String, text: String, syllables: [MistakeAnalysis.Syllable], bad: Bool) -> some View {
        let color = bad ? socialRed : green
        let items: [(char: String, py: String)] = syllables.isEmpty
            ? text.map { (String($0), "") }
            : syllables.map { ($0.char, $0.py) }
        return VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(color.opacity(0.8))
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 0) {
                        Text(item.py)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RubyText.pinyinBlue)
                            .frame(minHeight: 16)
                        Text(item.char)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(color)
                            .strikethrough(bad, color: color)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(section.fill(color.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text), \(items.map(\.py).joined(separator: " "))")
    }

    private func kindChips(_ r: MistakeAnalysis.Result) -> some View {
        HStack(spacing: 6) {
            ForEach(r.kinds) { kind in
                Text(kind.label)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(kind.colors.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(kind.colors.background))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Chẩn đoán

    private func diagnosis(_ r: MistakeAnalysis.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔍 Chẩn đoán & cách sửa").font(.headline)
            ForEach(Array(MistakeAnalysis.steps(r).enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(socialRed))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(section.fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: Đọc gần giống (kho từ chung)

    @ViewBuilder
    private var soundsLike: some View {
        if insightState != .hidden {
            VStack(alignment: .leading, spacing: 8) {
                Text("🗣️ Đọc gần giống").font(.headline)
                if let insight {
                    if !insight.soundsLike.isEmpty {
                        Text("≈ “\(insight.soundsLike)”")
                            .font(.title3.weight(.heavy))
                    }
                    ForEach(Array(insight.syllables.enumerated()), id: \.offset) { _, syllable in
                        (Text("\(syllable.hanzi) \(syllable.pinyin)").fontWeight(.bold)
                         + Text(syllable.soundsLike.isEmpty ? "" : " ≈ \(syllable.soundsLike)")
                         + Text(syllable.tip.isEmpty ? "" : " — \(syllable.tip)").foregroundColor(.secondary))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !insight.meaning.isEmpty {
                        Text("Nghĩa: \(insight.meaning)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Chỉ là cách đọc gần đúng — nghe giọng mẫu để bắt đúng thanh điệu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Đang tra…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(section.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private func loadInsight() async {
        if let cached = WordInsightCache.get(request.expected) {
            insight = cached
            insightState = .loaded
            return
        }
        guard WebAccountStore.shared.isSignedIn,
              let result = try? await SharedWordAPI.lookup(request.expected) else {
            insightState = .hidden
            return
        }
        WordInsightCache.set(result, for: request.expected)
        insight = result
        insightState = .loaded
    }

    // MARK: Luyện ngay

    private var practice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎙️ Luyện ngay").font(.headline)
            HStack(spacing: 8) {
                practiceButton("🔊 Nghe mẫu", filled: false) {
                    capture.cancel()
                    NaturalSpeaker.chinese.speak(request.expected, preferOpenAI: true)
                }
                practiceButton("🐢 Nghe chậm", filled: false) {
                    capture.cancel()
                    NaturalSpeaker.chinese.speak(request.expected, preferOpenAI: true, rate: 0.7)
                }
            }
            practiceButton(capture.isListening ? "👂 Đang nghe… (chạm để dừng)" : "🎙️ Thử đọc", filled: true) {
                tryReading()
            }
            if capture.isListening, !capture.transcript.isEmpty {
                Text(capture.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let feedback {
                Text(feedback.text)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(feedback.ok ? green : socialRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(popResult && !reduceMotion ? 1.05 : 1)
            } else {
                Text("Đọc: \(request.expected)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < passes ? Color(red: 0.13, green: 0.77, blue: 0.37) : Color(.tertiarySystemFill))
                        .frame(width: 12, height: 12)
                        .scaleEffect(i < passes && !reduceMotion ? 1.15 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: passes)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Đạt \(passes) trên 3 lần")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(section.fill(Color(.secondarySystemGroupedBackground)))
    }

    private func practiceButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(filled ? .white : socialRed)
                .background {
                    if filled {
                        section.fill(socialRed)
                    } else {
                        section.fill(socialRed.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func tryReading() {
        if capture.isListening {
            capture.finish()
            return
        }
        NaturalSpeaker.all.forEach { $0.stop() }
        feedback = nil
        capture.localeIdentifier = "zh-CN"
        capture.onError = { message in
            DispatchQueue.main.async { feedback = Feedback(ok: false, text: message) }
        }
        capture.start(targets: []) { heard in
            DispatchQueue.main.async { grade(heard) }
        }
    }

    private func grade(_ heard: String) {
        let said = heard.filter { !$0.isWhitespace && !"，。！？,.!?、".contains($0) }
        let expected = request.expected
        if !said.isEmpty, said.contains(expected) {
            passes += 1
            if passes >= 3 {
                feedback = Feedback(ok: true, text: "🎉 Chuẩn 3 lần liên tiếp! Bạn đã sửa được “\(expected)”.")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                feedback = Feedback(ok: true, text: "✅ Chuẩn rồi! (\(passes)/3)")
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if !reduceMotion {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { popResult = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { popResult = false }
                }
            }
        } else {
            passes = 0
            let again = MistakeAnalysis.analyse(heard: said, expected: expected)
            let why = again.kinds.isEmpty ? "" : " — sai " + again.kinds.map { $0.label.lowercased() }.joined(separator: ", ")
            feedback = Feedback(ok: false, text: "Máy nghe ra “\(said.isEmpty ? "…" : said)”\(why). Nghe mẫu rồi thử lại nhé.")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}

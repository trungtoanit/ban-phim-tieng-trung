//
//  PronunciationDrillView.swift
//  Luyện lại một lỗi phát âm: nghe mẫu, xem đúng–sai đặt cạnh nhau, đọc cách sửa, rồi đọc vào micro.
//  Đọc đúng thì lỗi tự xoá và hiện màn chúc mừng.
//

import SwiftUI

private let accentRed = Color(red: 0.86, green: 0.17, blue: 0.16)
private let correctGreen = Color(red: 0.13, green: 0.62, blue: 0.3)

/// Mở màn luyện ở lỗi thứ `index` của `queue`; luyện xong có thể đi tiếp các lỗi sau.
struct MistakeDrill: Hashable {
    let queue: [PronunciationMistake]
    let index: Int
}

struct PronunciationDrillView: View {
    private enum Feedback: Equatable {
        case wrong(heard: String, detail: String)
        case nothingHeard
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var capture = SpeechCapture()

    @State private var queue: [PronunciationMistake]
    @State private var index: Int
    @State private var attempts = 0
    @State private var feedback: Feedback?
    @State private var shake = 0
    @State private var celebrating = false
    @State private var fixedCount = 0
    @State private var errorMessage: String?

    init(drill: MistakeDrill) {
        _queue = State(initialValue: drill.queue)
        _index = State(initialValue: min(max(drill.index, 0), max(drill.queue.count - 1, 0)))
    }

    private var mistake: PronunciationMistake? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// Đọc cả từ chứa chữ sai (秋天 thay vì 秋): máy nhận dạng chữ đứng một mình rất kém,
    /// hay đoán thành một chữ đồng âm bất kỳ.
    private var target: String {
        guard let mistake else { return "" }
        let word = ChineseText.words(for: mistake.sentence)
            .map { RubyText.splitPunctuation($0.zh).core }
            .first { $0.contains(mistake.zh) && $0.count <= 4 }
        return word ?? mistake.zh
    }

    var body: some View {
        ZStack {
            if let mistake {
                ScrollView {
                    VStack(spacing: 14) {
                        if queue.count > 1 { progressHeader }
                        targetCard(mistake)
                        if !mistake.isUnclear { comparisonCard(mistake) }
                        howToCard(mistake)
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGroupedBackground))
                .safeAreaInset(edge: .bottom) { recordPanel }
            }

            if celebrating, let mistake {
                CelebrationOverlay(
                    mistake: mistake,
                    attempts: attempts,
                    remaining: queue.count - index - 1,
                    onNext: next,
                    onDone: { dismiss() }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .navigationTitle("Luyện sửa lỗi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(celebrating ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            capture.onError = { message in errorMessage = message }
        }
        .onDisappear { capture.cancel() }
        .alert("Không thể ghi âm", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Thẻ nội dung

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lỗi \(index + 1)/\(queue.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if fixedCount > 0 {
                    Label("Đã sửa \(fixedCount)", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(correctGreen)
                }
            }
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .tint(accentRed)
        }
    }

    private func targetCard(_ mistake: PronunciationMistake) -> some View {
        VStack(spacing: 10) {
            Text("Đọc to từ này")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(ChineseText.syllables(for: target).enumerated()), id: \.offset) { _, item in
                    let isFocus = mistake.zh.contains(item.char)
                    VStack(spacing: 2) {
                        Text(item.syllable)
                            .font(.title3.weight(isFocus ? .bold : .regular))
                            .foregroundStyle(isFocus ? correctGreen : .secondary)
                        Text(item.char)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isFocus ? correctGreen.opacity(0.12) : .clear)
                            )
                    }
                }
            }
            HStack(spacing: 10) {
                listenButton("Nghe cả từ", systemImage: "speaker.wave.2.fill") {
                    NaturalSpeaker.chinese.speak(target, preferOpenAI: true)
                }
                if target != mistake.zh {
                    listenButton("Nghe \(mistake.zh)", systemImage: "speaker.wave.1.fill") {
                        NaturalSpeaker.chinese.speak(mistake.zh, preferOpenAI: true)
                    }
                }
            }
            Text(mistake.sentence)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(card)
        .modifier(ShakeEffect(shakes: CGFloat(shake)))
        .animation(.default, value: shake)
    }

    private func comparisonCard(_ mistake: PronunciationMistake) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bạn từng đọc thành", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                syllableBox(title: "Cần đọc", zh: mistake.zh, pinyin: mistake.expected, color: correctGreen,
                            syllable: mistake.expectedSyllable, parts: mistake.parts)
                Image(systemName: "arrow.left")
                    .foregroundStyle(.tertiary)
                syllableBox(title: "Máy nghe thành", zh: mistake.heardZh ?? "?", pinyin: mistake.heard ?? "",
                            color: accentRed, syllable: mistake.heardSyllable, parts: mistake.parts)
            }
            HStack(spacing: 6) {
                ForEach(mistake.parts, id: \.self) { part in
                    Text("Sai \(part.label.lowercased())")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accentRed.opacity(0.12)))
                        .foregroundStyle(accentRed)
                }
            }
        }
        .padding(16)
        .background(card)
    }

    private func syllableBox(title: String, zh: String, pinyin: String, color: Color,
                             syllable: PinyinSyllable?, parts: [PronunciationPart]) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(zh)
                .font(.system(size: 38, weight: .semibold))
            Text(pinyin)
                .font(.headline)
                .foregroundStyle(color)
            if let syllable {
                // Tách âm tiết, tô đậm đúng phần bị sai.
                HStack(spacing: 4) {
                    partTag(syllable.initial.isEmpty ? "∅" : syllable.initial, highlighted: parts.contains(.initial), color: color)
                    partTag(syllable.final, highlighted: parts.contains(.final), color: color)
                }
                if parts.contains(.tone) {
                    ToneContourView(tone: String(syllable.tone), color: color)
                        .frame(width: 60, height: 36)
                    Text(syllable.tone == 5 ? "Thanh nhẹ" : "Thanh \(syllable.tone)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
            Button {
                NaturalSpeaker.chinese.speak(zh, preferOpenAI: true)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nghe \(zh)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.08)))
    }

    private func partTag(_ text: String, highlighted: Bool, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(highlighted ? .bold : .regular))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(highlighted ? color.opacity(0.2) : Color(.tertiarySystemFill)))
            .foregroundStyle(highlighted ? color : .secondary)
    }

    @ViewBuilder
    private func howToCard(_ mistake: PronunciationMistake) -> some View {
        let tips = Self.tips(for: mistake)
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label("Cách sửa", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(Array(tips.enumerated()), id: \.offset) { offset, tip in
                    if offset > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(tip.title)
                                .font(.headline)
                                .foregroundStyle(correctGreen)
                            Text(tip.kind)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(tip.body)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let pair = tip.pair {
                            Text(pair)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(card)
        }
    }

    private struct Tip {
        let title: String
        let kind: String
        let body: String
        let pair: String?
    }

    /// Mẹo cho đúng những phần bị sai; lỗi chưa rõ thì đưa cả ba phần của âm tiết.
    private static func tips(for mistake: PronunciationMistake) -> [Tip] {
        let syllables = ChineseText.syllables(for: mistake.zh).compactMap { PinyinSyllable($0.syllable) }
        guard let expected = mistake.expectedSyllable ?? syllables.first else { return [] }
        let heard = mistake.heardSyllable
        let parts: [PronunciationPart] = mistake.parts.isEmpty ? PronunciationPart.allCases : mistake.parts
        return parts.compactMap { part in
            let kind: SoundGuide.Kind = part == .initial ? .initial : part == .final ? .final : .tone
            let key = PinyinGuide.key(kind, of: expected)
            guard let guide = PinyinGuide.guide(kind, key: key) else { return nil }
            let pair = heard.flatMap { PinyinGuide.pairTip(kind, key, PinyinGuide.key(kind, of: $0)) }
            return Tip(title: guide.symbol, kind: kind.label, body: guide.tip, pair: pair)
        }
    }

    // MARK: - Ghi âm

    private var recordPanel: some View {
        VStack(spacing: 10) {
            Group {
                if capture.isListening {
                    Text(capture.transcript.isEmpty ? "Đang nghe… đọc \(target)" : capture.transcript)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(capture.transcript.isEmpty ? .secondary : .primary)
                } else if let feedback {
                    feedbackView(feedback)
                } else {
                    Text("Nghe mẫu vài lần, rồi chạm micro và đọc \(target)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .animation(.easeInOut(duration: 0.2), value: feedback)

            ZStack {
                if capture.isListening {
                    RecordingHalo(color: accentRed, size: 78)
                }
                Circle()
                    .fill(accentRed.opacity(0.18))
                    .frame(width: 78, height: 78)
                    .scaleEffect(capture.isListening ? 1 + CGFloat(min(capture.level, 1)) * 0.45 : 1)
                    .animation(.easeOut(duration: 0.1), value: capture.level)
                Button(action: toggleRecording) {
                    Image(systemName: capture.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(accentRed))
                        .shadow(color: accentRed.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(capture.isListening ? "Dừng" : "Bắt đầu đọc")
            }
            .frame(height: 96)

            if attempts > 0 {
                Text("Lần thử \(attempts)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func feedbackView(_ feedback: Feedback) -> some View {
        switch feedback {
        case .nothingHeard:
            Label("Máy chưa nghe thấy gì. Đọc to và rõ hơn nhé.", systemImage: "ear.trianglebadge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case let .wrong(heard, detail):
            VStack(spacing: 3) {
                Text("Chưa đúng — máy nghe thành \(heard)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentRed)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggleRecording() {
        if capture.isListening {
            capture.finish()
            return
        }
        guard let mistake else { return }
        feedback = nil
        let target = target
        capture.start(targets: [target]) { heard in
            evaluate(heard: heard, mistake: mistake, target: target)
        }
    }

    private func evaluate(heard: String, mistake: PronunciationMistake, target: String) {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            feedback = .nothingHeard
            return
        }
        attempts += 1
        if PronunciationAnalyzer.readsCorrectly(mistake.zh, in: target, heard: text) {
            succeed(mistake)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            shake += 1
            let latest = PhraseMatcher.lastAttempt(heard: text, target: target)
            let found = PronunciationAnalyzer.mistakes(target: target, heard: latest, source: .drill)
                .first { mistake.zh.contains($0.zh) }
            // Mỗi lần đọc sai đều đếm: chữ nào luyện mãi chưa ra thì leo lên đầu danh sách từ hay sai.
            var counted = found ?? PronunciationMistake(source: .drill, zh: mistake.zh, expected: mistake.expected,
                                                        parts: [], sentence: mistake.sentence)
            counted.sentence = mistake.sentence
            PronunciationLog.record([counted])
            let detail: String
            if let found {
                let parts = found.parts.map { $0.label.lowercased() }.joined(separator: " và ")
                detail = "\(found.zh) → \(found.heardZh ?? "") \(found.heard ?? ""): sai \(parts). Xem lại phần cách sửa."
            } else {
                detail = "Nghe mẫu thêm một lần rồi đọc chậm, rõ từng chữ."
            }
            feedback = .wrong(heard: latest, detail: detail)
        }
    }

    private func succeed(_ mistake: PronunciationMistake) {
        // Đọc đúng rồi: xoá mọi lần ghi cùng chữ, cùng cách đọc — đó là cùng một lỗi.
        PronunciationLog.update { list in
            list.removeAll { $0.id == mistake.id || ($0.zh == mistake.zh && $0.expected == mistake.expected) }
        }
        fixedCount += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Chime.play(frequency: 1318.5, duration: 0.13)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Chime.play(frequency: 1975.5, duration: 0.24)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { celebrating = true }
    }

    private func next() {
        guard let fixed = mistake else { return dismiss() }
        // Bỏ qua những lỗi vừa bị xoá cùng lúc (cùng chữ, cùng cách đọc).
        var nextIndex = index + 1
        while queue.indices.contains(nextIndex),
              queue[nextIndex].zh == fixed.zh, queue[nextIndex].expected == fixed.expected {
            nextIndex += 1
        }
        guard queue.indices.contains(nextIndex) else { return dismiss() }
        withAnimation(.easeInOut) {
            celebrating = false
            index = nextIndex
            attempts = 0
            feedback = nil
        }
    }

    // MARK: - Tiện ích

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private func listenButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(accentRed.opacity(0.12)))
                .foregroundStyle(accentRed)
        }
        .buttonStyle(.plain)
    }
}

/// Lắc ngang khi đọc sai.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}

// MARK: - Màn chúc mừng

private struct CelebrationOverlay: View {
    let mistake: PronunciationMistake
    let attempts: Int
    let remaining: Int
    let onNext: () -> Void
    let onDone: () -> Void

    @State private var popped = false

    private var praise: String {
        switch attempts {
        case ...1: "Đúng ngay lần đầu! 🎯"
        case 2...3: "Chính xác! 🎉"
        default: "Kiên trì quá, đúng rồi! 💪"
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    SparkBurst(count: 18, radius: 140)
                    SparkBurst(count: 12, radius: 90)
                    MascotView(mood: .happy, size: 130)
                        .scaleEffect(popped ? 1 : 0.3)
                        .opacity(popped ? 1 : 0)
                }
                .frame(height: 190)

                Text(praise)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .scaleEffect(popped ? 1 : 0.7)
                    .opacity(popped ? 1 : 0)

                VStack(spacing: 6) {
                    Text("Bạn đã đọc đúng")
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(mistake.zh)
                            .font(.system(size: 48, weight: .semibold))
                        Text(mistake.expected)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(correctGreen)
                    }
                    Label("Đã xoá khỏi danh sách lỗi", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(correctGreen)
                        .padding(.top, 2)
                }
                .opacity(popped ? 1 : 0)
                .offset(y: popped ? 0 : 20)

                Spacer()

                VStack(spacing: 10) {
                    if remaining > 0 {
                        Button(action: onNext) {
                            Text("Luyện lỗi tiếp theo (còn \(remaining))")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accentRed))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onDone) {
                        Text(remaining > 0 ? "Để sau" : "Xong")
                            .font(.headline)
                            .foregroundStyle(remaining > 0 ? accentRed : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(remaining > 0 ? accentRed.opacity(0.12) : accentRed))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.05)) { popped = true }
        }
    }
}

// MARK: - Luyện thanh điệu của một âm

/// Đọc lần lượt cùng một âm tiết ở từng thanh (妈 麻 马 骂). Micro tự mở lại sau mỗi lần đọc
/// cho tới khi đạt đủ các thanh, rồi chấm điểm theo số lần phải thử.
struct ToneDrillCard: View {
    let items: [PinyinGuide.ToneDrillItem]

    private enum Feedback: Equatable {
        case correct(String)
        case wrong(String)
        case silent
    }

    @StateObject private var capture = SpeechCapture()
    @State private var current = 0
    /// Chữ thứ mấy → đã phải đọc bao nhiêu lần mới đạt.
    @State private var passed: [Int: Int] = [:]
    @State private var attempts = 0
    @State private var feedback: Feedback?
    /// Đang trong vòng thu âm liên tục (người học chưa bấm dừng).
    @State private var looping = false
    @State private var errorMessage: String?
    @State private var loopToken = UUID()
    /// Đang đọc mẫu cả dãy: chữ thứ mấy, lượt thứ mấy.
    @State private var playingIndex: Int?
    @State private var playRound = 0
    @State private var playToken = UUID()

    /// Vào màn là đọc mẫu cả dãy bấy nhiêu lượt, để tai quen cao độ trước khi tự đọc.
    private static let demoRounds = 3

    private var finished: Bool { !items.isEmpty && passed.count == items.count }

    /// Đạt ngay lần đầu 100 điểm, mỗi lần thử thêm trừ 25, thấp nhất 25.
    private var score: Int {
        guard !passed.isEmpty else { return 0 }
        let points = passed.values.map { max(100 - 25 * ($0 - 1), 25) }
        return points.reduce(0, +) / points.count
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    tile(index, item)
                }
            }

            if finished {
                resultView
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if items.indices.contains(current) {
                practiceView(items[current])
            }
        }
        .padding(.vertical, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: passed)
        .animation(.easeInOut(duration: 0.2), value: feedback)
        .onAppear {
            capture.onError = { message in stopLoop(); errorMessage = message }
            // Đợi màn hình chuyển xong rồi mới đọc, không thì tiếng bị cắt đầu.
            let token = UUID()
            playToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard playToken == token, !looping else { return }
                playDemo()
            }
        }
        .onDisappear {
            stopDemo()
            stopLoop()
        }
        .alert("Không thể ghi âm", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func tile(_ index: Int, _ item: PinyinGuide.ToneDrillItem) -> some View {
        let isDone = passed[index] != nil
        let isPlaying = playingIndex == index
        let isCurrent = (index == current && !finished && playingIndex == nil) || isPlaying
        let color: Color = isDone ? correctGreen : (isCurrent ? accentRed : .secondary)
        return Button {
            guard !capture.isListening else { return }
            stopDemo()
            current = index
            feedback = nil
            attempts = 0
            NaturalSpeaker.chinese.speak(item.zh)
        } label: {
            VStack(spacing: 3) {
                ToneContourView(tone: String(item.tone), color: color)
                    .frame(height: 20)
                Text(item.zh)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.py)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : (isDone ? "checkmark.circle.fill" : "circle"))
                    .font(.caption)
                    .foregroundStyle(isPlaying ? accentRed : (isDone ? correctGreen : Color(.tertiaryLabel)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDone ? correctGreen.opacity(0.1) : Color(.tertiarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isCurrent ? accentRed : .clear, lineWidth: 2))
            .scaleEffect(isPlaying ? 1.08 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPlaying)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.zh) \(item.py), thanh \(item.tone)\(isDone ? ", đã đạt" : "")")
    }

    private func practiceView(_ item: PinyinGuide.ToneDrillItem) -> some View {
        VStack(spacing: 10) {
            Button {
                playingIndex == nil ? playDemo() : stopDemo()
            } label: {
                Label(playingIndex == nil
                      ? "Nghe \(items.count) thanh × \(Self.demoRounds)"
                      : "Đang đọc mẫu · lượt \(playRound)/\(Self.demoRounds) — chạm để dừng",
                      systemImage: playingIndex == nil ? "play.circle.fill" : "stop.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(accentRed.opacity(0.12)))
                    .foregroundStyle(accentRed)
            }
            .buttonStyle(.plain)
            .disabled(looping)

            Group {
                switch feedback {
                case let .correct(text):
                    Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(correctGreen)
                case let .wrong(text):
                    Label(text, systemImage: "xmark.circle.fill").foregroundStyle(accentRed)
                case .silent:
                    Label("Chưa nghe thấy gì — chạm micro và đọc to hơn nhé.", systemImage: "ear")
                        .foregroundStyle(.orange)
                case nil where playingIndex != nil:
                    Text("Nghe kỹ giọng lên xuống theo đường cao độ trên mỗi ô.")
                        .foregroundStyle(.secondary)
                case nil:
                    Text(capture.isListening
                         ? (capture.transcript.isEmpty ? "Đang nghe… đọc \(item.zh) \(item.py)" : capture.transcript)
                         : "Nghe mẫu rồi chạm micro, đọc \(item.zh) \(item.py) (thanh \(item.tone)).")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .frame(minHeight: 40)

            HStack(spacing: 22) {
                Button {
                    stopLoop()
                    stopDemo()
                    NaturalSpeaker.chinese.speak(item.zh)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(accentRed)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(accentRed.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nghe mẫu \(item.zh)")

                ZStack {
                    if capture.isListening {
                        RecordingHalo(color: accentRed, size: 64)
                    }
                    Button {
                        looping ? stopLoop() : startLoop()
                    } label: {
                        Image(systemName: looping ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(accentRed))
                            .scaleEffect(capture.isListening ? 1 + CGFloat(min(capture.level, 1)) * 0.15 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(looping ? "Dừng luyện" : "Bắt đầu luyện")
                }
                .frame(width: 80, height: 80)

                Text("\(passed.count)/\(items.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50)
            }

            if looping {
                Text("Micro tự mở lại sau mỗi lần đọc cho tới khi đạt đủ các thanh.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { star in
                    Image(systemName: star < stars ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .font(.title2)
                }
            }
            Text("\(score) điểm")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(correctGreen)
            Text(score == 100 ? "Đọc đúng cả \(items.count) thanh ngay lần đầu!" : "Đã đạt đủ \(items.count) thanh. Luyện lại để đạt điểm cao hơn.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                passed = [:]
                current = 0
                attempts = 0
                feedback = nil
            } label: {
                Label("Luyện lại", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accentRed.opacity(0.12)))
                    .foregroundStyle(accentRed)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var stars: Int { score >= 90 ? 3 : score >= 60 ? 2 : 1 }

    // MARK: - Vòng thu âm

    private func startLoop() {
        guard !finished else { return }
        stopDemo()
        looping = true
        listen()
    }

    // MARK: - Đọc mẫu cả dãy

    private func playDemo() {
        stopLoop()
        let token = UUID()
        playToken = token
        playStep(round: 1, index: 0, token: token)
    }

    private func stopDemo() {
        playToken = UUID()
        if playingIndex != nil { NaturalSpeaker.chinese.stop() }
        playingIndex = nil
        playRound = 0
    }

    /// Đọc từng chữ nối nhau: xong chữ này mới sang chữ sau, hết dãy thì sang lượt mới.
    private func playStep(round: Int, index: Int, token: UUID) {
        guard playToken == token else { return }
        guard items.indices.contains(index) else {
            guard round < Self.demoRounds else {
                playingIndex = nil
                playRound = 0
                return
            }
            playingIndex = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                playStep(round: round + 1, index: 0, token: token)
            }
            return
        }
        playRound = round
        playingIndex = index
        NaturalSpeaker.chinese.speak(items[index].zh) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                playStep(round: round, index: index + 1, token: token)
            }
        }
    }

    private func stopLoop() {
        looping = false
        loopToken = UUID()
        capture.cancel()
    }

    private func listen() {
        guard looping, items.indices.contains(current) else { return }
        let index = current
        let item = items[index]
        let token = UUID()
        loopToken = token
        if feedback == .silent { feedback = nil }
        // Âm tiết ngắn: chờ ngắn để vòng luyện nhanh, không bắt người học đợi.
        capture.start(targets: [item.zh], firstPause: 5, pause: 0.9) { heard in
            guard loopToken == token else { return }
            evaluate(heard, index: index, item: item)
        }
    }

    private func evaluate(_ heard: String, index: Int, item: PinyinGuide.ToneDrillItem) {
        let han = heard.filter { ChineseText.containsHan(String($0)) }
        guard !han.isEmpty else {
            // Im lặng: dừng vòng, không để micro mở mãi.
            looping = false
            feedback = .silent
            return
        }
        attempts += 1
        // Lấy chữ cuối cùng máy nghe được, đọc theo ngữ cảnh của cả đoạn.
        let last = ChineseText.syllables(for: String(han)).last
        let heardSyllable = last.flatMap { PinyinSyllable($0.syllable) }
        let target = PinyinSyllable(item.py)
        let ok = last?.char == item.zh || (heardSyllable != nil && heardSyllable == target)

        if ok {
            PronunciationLog.update { list in
                list.removeAll { $0.zh == item.zh && $0.expected == item.py }
            }
            passed[index] = attempts
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Chime.play(frequency: 1318.5 * pow(2, Double(passed.count - 1) / 12 * 2), duration: 0.16)
            feedback = .correct(attempts == 1 ? "Chuẩn! \(item.zh) \(item.py)" : "Đạt rồi sau \(attempts) lần!")
            attempts = 0
            if let next = items.indices.first(where: { passed[$0] == nil }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    guard looping else { return }
                    current = next
                    feedback = nil
                    listen()
                }
            } else {
                looping = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    Chime.play(frequency: 1975.5, duration: 0.26)
                }
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if let last, let parts = PronunciationAnalyzer.differences(item.py, last.syllable) {
                PronunciationLog.record([PronunciationMistake(
                    source: .drill, zh: item.zh, expected: item.py, heardZh: last.char, heard: last.syllable,
                    parts: parts, sentence: items.map(\.zh).joined(separator: " ")
                )])
            }
            let heardText = last.map { "\($0.char) \($0.syllable)" } ?? String(han)
            let hint: String
            if let heardSyllable, let target, heardSyllable.initial == target.initial, heardSyllable.final == target.final {
                hint = heardSyllable.tone == 5 ? "đọc nhẹ quá, cần thanh \(target.tone)" : "ra thanh \(heardSyllable.tone), cần thanh \(target.tone)"
            } else {
                hint = "sai âm"
            }
            feedback = .wrong("Máy nghe thành \(heardText) — \(hint). Đọc lại nhé!")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                guard looping, current == index else { return }
                listen()
            }
        }
    }
}

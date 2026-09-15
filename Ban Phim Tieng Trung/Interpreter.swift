//
//  Interpreter.swift
//  Phiên dịch hội thoại trực tiếp như Google Dịch: hai người, mỗi người một ngôn ngữ và một nút micro.
//  Nói xong là dịch sang ngôn ngữ người kia và đọc to. Chế độ đối diện chia đôi màn hình,
//  nửa trên xoay ngược cho người ngồi bên kia bàn.
//

import Combine
import SwiftUI

struct InterpreterLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let flag: String
    /// Mã nhận dạng giọng nói.
    let locale: String
    /// Mã dịch của Google.
    let google: String

    var speaker: NaturalSpeaker {
        switch id {
        case "vi": .vietnamese
        case "en": .english
        case "ja": .japanese
        case "ko": .korean
        default: .chinese
        }
    }

    var isChinese: Bool { id == "zh" }

    static let all: [InterpreterLanguage] = [
        .init(id: "vi", name: "Tiếng Việt", flag: "🇻🇳", locale: "vi-VN", google: "vi"),
        .init(id: "zh", name: "中文", flag: "🇨🇳", locale: "zh-CN", google: "zh-CN"),
        .init(id: "en", name: "English", flag: "🇺🇸", locale: "en-US", google: "en"),
        .init(id: "ja", name: "日本語", flag: "🇯🇵", locale: "ja-JP", google: "ja"),
        .init(id: "ko", name: "한국어", flag: "🇰🇷", locale: "ko-KR", google: "ko"),
    ]

    static func find(_ id: String) -> InterpreterLanguage {
        all.first { $0.id == id } ?? all[0]
    }

    /// Lời nhắc bấm micro, viết bằng chính ngôn ngữ đó để người kia đọc được.
    var tapToSpeak: String {
        switch id {
        case "vi": "Chạm để nói"
        case "zh": "点击说话"
        case "en": "Tap to speak"
        case "ja": "タップして話す"
        case "ko": "눌러서 말하기"
        default: "Tap to speak"
        }
    }

    var listening: String {
        switch id {
        case "vi": "Đang nghe…"
        case "zh": "正在听…"
        case "en": "Listening…"
        case "ja": "聞いています…"
        case "ko": "듣고 있어요…"
        default: "Listening…"
        }
    }
}

final class InterpreterSession: ObservableObject {
    enum Side { case a, b }

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let side: Side
        let source: String
        let sourceLanguage: InterpreterLanguage
        let targetLanguage: InterpreterLanguage
        var translation: String?
        var failed = false
    }

    /// Nhớ cặp ngôn ngữ cho lần mở sau.
    @Published var languageA: InterpreterLanguage {
        didSet { UserDefaults.standard.set(languageA.id, forKey: "interpreterLanguageA") }
    }
    @Published var languageB: InterpreterLanguage {
        didSet { UserDefaults.standard.set(languageB.id, forKey: "interpreterLanguageB") }
    }
    @Published private(set) var turns: [Turn] = []
    @Published private(set) var listeningSide: Side?
    @Published var errorMessage: String?
    /// Rảnh tay: dịch và đọc xong thì tự mở micro cho người kia, im lặng thì chờ tiếp.
    @Published var handsFree = UserDefaults.standard.bool(forKey: "interpreterHandsFree") {
        didSet {
            UserDefaults.standard.set(handsFree, forKey: "interpreterHandsFree")
            if handsFree {
                if listeningSide == nil { listen(nextSide) }
            } else {
                loopToken = UUID()
            }
        }
    }
    /// Người tới lượt nói trong vòng rảnh tay.
    @Published private(set) var nextSide: Side = .a

    private let capture = SpeechCapture()
    private var captureObserver: AnyCancellable?
    /// Đổi mỗi khi dừng hẳn: các việc hẹn giờ của vòng rảnh tay cũ tự bỏ.
    private var loopToken = UUID()

    var transcript: String { capture.transcript }
    var level: Float { capture.level }

    init() {
        languageA = InterpreterLanguage.find(UserDefaults.standard.string(forKey: "interpreterLanguageA") ?? "vi")
        languageB = InterpreterLanguage.find(UserDefaults.standard.string(forKey: "interpreterLanguageB") ?? "zh")
        captureObserver = capture.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        capture.onError = { [weak self] message in
            self?.listeningSide = nil
            self?.errorMessage = message
        }
    }

    func language(_ side: Side) -> InterpreterLanguage { side == .a ? languageA : languageB }

    /// Chạm micro của một người: đang nghe người đó thì chốt câu, không thì chuyển sang nghe người đó.
    func toggle(_ side: Side) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if listeningSide == side {
            capture.finish()
            return
        }
        listen(side)
    }

    /// Mở micro theo ngôn ngữ của một người.
    private func listen(_ side: Side) {
        capture.cancel()
        NaturalSpeaker.all.forEach { $0.stop() }
        let token = UUID()
        loopToken = token
        nextSide = side
        capture.localeIdentifier = language(side).locale
        listeningSide = side
        capture.start(targets: []) { [weak self] heard in
            guard let self, self.loopToken == token else { return }
            self.listeningSide = nil
            let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                // Im lặng: rảnh tay thì chờ tiếp đúng người đang tới lượt.
                self.continueLoop(with: side, token: token, delay: 0.4)
                return
            }
            self.translate(text, from: side, token: token)
        }
    }

    private func continueLoop(with side: Side, token: UUID, delay: TimeInterval) {
        guard handsFree else { return }
        nextSide = side
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.handsFree, self.loopToken == token, self.listeningSide == nil,
                  self.errorMessage == nil else { return }
            self.listen(side)
        }
    }

    func stop() {
        loopToken = UUID()
        capture.cancel()
        listeningSide = nil
        NaturalSpeaker.all.forEach { $0.stop() }
    }

    /// Vào lại màn hình: rảnh tay đang bật thì mở micro luôn.
    func resume() {
        if handsFree, listeningSide == nil { listen(nextSide) }
    }

    func swapLanguages() {
        stop()
        let a = languageA
        languageA = languageB
        languageB = a
        resume()
    }

    func clear() {
        stop()
        turns = []
    }

    func replay(_ turn: Turn) {
        guard let translation = turn.translation else { return }
        capture.cancel()
        listeningSide = nil
        turn.targetLanguage.speaker.speak(translation)
    }

    private func translate(_ text: String, from side: Side, token: UUID) {
        let source = language(side)
        let target = language(side == .a ? .b : .a)
        let turn = Turn(side: side, source: text, sourceLanguage: source, targetLanguage: target)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { turns.append(turn) }

        let other: Side = side == .a ? .b : .a
        // Rảnh tay: tới lượt người kia ngay từ lúc bắt đầu dịch.
        if handsFree { nextSide = other }

        guard source.id != target.id else {
            finish(turn.id, translation: text, token: token)
            return
        }
        Task {
            let result = try? await Translator.translate(text, from: source.google, to: target.google)
            await MainActor.run {
                if let result {
                    self.finish(turn.id, translation: result, token: token)
                } else if let index = self.turns.firstIndex(where: { $0.id == turn.id }) {
                    self.turns[index].failed = true
                    // Dịch hỏng: để người vừa nói nói lại.
                    self.continueLoop(with: side, token: token, delay: 0.8)
                }
            }
        }
    }

    private func finish(_ id: UUID, translation: String, token: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.25)) { turns[index].translation = translation }
        let turn = turns[index]
        let other: Side = turn.side == .a ? .b : .a
        // Đọc to bản dịch cho người kia nghe, trừ khi ai đó đã bắt đầu nói tiếp.
        guard listeningSide == nil, loopToken == token else { return }
        turn.targetLanguage.speaker.speak(translation) { [weak self] in
            // Đọc xong mới mở micro, để micro không thu lại tiếng loa.
            self?.continueLoop(with: other, token: token, delay: 0.3)
        }
    }
}

// MARK: - Màn hình

struct InterpreterView: View {
    @StateObject private var session = InterpreterSession()
    @State private var faceToFace = false

    private static let colorA = Color(red: 0.86, green: 0.17, blue: 0.16)
    private static let colorB = Color(red: 0.12, green: 0.44, blue: 0.94)

    var body: some View {
        NavigationStack {
            Group {
                if faceToFace {
                    faceToFaceView
                        .transition(.opacity)
                } else {
                    conversationView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: faceToFace)
            .navigationTitle("Phiên dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(faceToFace ? .hidden : .automatic, for: .navigationBar)
            .homeBackButton()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !session.turns.isEmpty {
                        Button {
                            session.clear()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Xoá cuộc trò chuyện")
                    }
                    Button {
                        faceToFace = true
                    } label: {
                        Image(systemName: "rectangle.split.1x2")
                    }
                    .accessibilityLabel("Chế độ đối diện")
                }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                session.resume()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                session.stop()
            }
            .alert("Không thể nghe", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.errorMessage ?? "")
            }
        }
    }

    // MARK: Chế độ thường

    private var conversationView: some View {
        VStack(spacing: 0) {
            languageBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
            handsFreeBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if session.turns.isEmpty && session.listeningSide == nil {
                            emptyState
                        }
                        ForEach(session.turns) { turn in
                            turnBubble(turn)
                                .id(turn.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if let side = session.listeningSide {
                            liveCard(side)
                                .id("live")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.turns) { _ in
                    withAnimation { proxy.scrollTo(session.turns.last?.id, anchor: .bottom) }
                }
                .onChange(of: session.transcript) { _ in
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }

            HStack(spacing: 18) {
                micButton(.a, size: 84)
                micButton(.b, size: 84)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var languageBar: some View {
        HStack(spacing: 10) {
            languageMenu(.a)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { session.swapLanguages() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Đổi chiều ngôn ngữ")
            languageMenu(.b)
        }
    }

    private func languageMenu(_ side: InterpreterSession.Side) -> some View {
        let current = session.language(side)
        return Menu {
            ForEach(InterpreterLanguage.all) { language in
                Button {
                    session.stop()
                    if side == .a { session.languageA = language } else { session.languageB = language }
                } label: {
                    if language.id == current.id {
                        Label("\(language.flag) \(language.name)", systemImage: "checkmark")
                    } else {
                        Text("\(language.flag) \(language.name)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(current.flag)
                Text(current.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(side == .a ? Self.colorA : Self.colorB)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var handsFreeBar: some View {
        HStack(spacing: 10) {
            handsFreeToggle
            Text(session.handsFree
                 ? "Tới lượt \(session.language(session.nextSide).flag) \(session.language(session.nextSide).name) — dịch xong micro tự mở cho người kia."
                 : "Bật để hai người nói luân phiên, không cần chạm micro.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: session.nextSide)
        }
    }

    private var handsFreeToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { session.handsFree.toggle() }
        } label: {
            Label("Rảnh tay", systemImage: session.handsFree ? "infinity.circle.fill" : "infinity")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(session.handsFree ? Color.green : Color(.secondarySystemGroupedBackground)))
                .foregroundStyle(session.handsFree ? .white : .primary)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(session.handsFree ? "Tắt chế độ rảnh tay" : "Bật chế độ rảnh tay")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(Self.colorB.opacity(0.8))
                .padding(.top, 40)
            Text("Chạm micro của người đang nói")
                .font(.headline)
            Text("App nghe, dịch sang ngôn ngữ người kia và đọc to bản dịch. Dùng chế độ đối diện khi hai người ngồi đối diện nhau.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private func turnBubble(_ turn: InterpreterSession.Turn) -> some View {
        let color = turn.side == .a ? Self.colorA : Self.colorB
        return HStack {
            if turn.side == .b { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(turn.sourceLanguage.flag) \(turn.sourceLanguage.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(turn.targetLanguage.flag) \(turn.targetLanguage.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                textBlock(turn.source, language: turn.sourceLanguage, size: 15, secondary: true)
                if let translation = turn.translation {
                    HStack(alignment: .top) {
                        textBlock(translation, language: turn.targetLanguage, size: 21, secondary: false)
                        Spacer(minLength: 6)
                        Button {
                            session.replay(turn)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Đọc lại bản dịch")
                    }
                } else if turn.failed {
                    Label("Không dịch được — kiểm tra kết nối mạng.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.opacity(0.1)))
            if turn.side == .a { Spacer(minLength: 36) }
        }
    }

    /// Tiếng Trung hiện kèm pinyin để người học nhìn được cách đọc.
    @ViewBuilder
    private func textBlock(_ text: String, language: InterpreterLanguage, size: CGFloat, secondary: Bool) -> some View {
        if language.isChinese {
            RubyText(words: ChineseText.words(for: text), hanziSize: size,
                     hanziColor: secondary ? .secondary : .primary)
        } else {
            Text(text)
                .font(.system(size: size, weight: secondary ? .regular : .semibold))
                .foregroundStyle(secondary ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func liveCard(_ side: InterpreterSession.Side) -> some View {
        let language = session.language(side)
        let color = side == .a ? Self.colorA : Self.colorB
        return VStack(alignment: .leading, spacing: 6) {
            Label(session.handsFree ? "Rảnh tay · \(language.flag) \(language.listening)" : "\(language.flag) \(language.listening)",
                  systemImage: session.handsFree ? "infinity" : "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(session.transcript.isEmpty ? "…" : session.transcript)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    private func micButton(_ side: InterpreterSession.Side, size: CGFloat) -> some View {
        let language = session.language(side)
        let color = side == .a ? Self.colorA : Self.colorB
        let active = session.listeningSide == side
        return Button {
            session.toggle(side)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if active {
                        RecordingHalo(color: color, size: size)
                    }
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .scaleEffect(active ? 1 + CGFloat(min(session.level, 1)) * 0.12 : 1)
                        .shadow(color: color.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: active ? "stop.fill" : "mic.fill")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size + 16, height: size + 16)
                Text("\(language.flag) \(language.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(active ? "Dừng nghe \(language.name)" : "Nói bằng \(language.name)")
    }

    // MARK: Chế độ đối diện

    private var faceToFaceView: some View {
        VStack(spacing: 0) {
            facePanel(.b)
                .rotationEffect(.degrees(180))
            HStack(spacing: 14) {
                Button {
                    faceToFace = false
                } label: {
                    Label("Thoát", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(.systemBackground)))
                }
                handsFreeToggle
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { session.swapLanguages() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(.systemBackground)))
                }
                .accessibilityLabel("Đổi chiều ngôn ngữ")
            }
            .foregroundStyle(.primary)
            .buttonStyle(PressableStyle())
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            facePanel(.a)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Nửa màn hình của một người: câu mới nhất viết bằng ngôn ngữ của người đó, và nút micro gần họ.
    private func facePanel(_ side: InterpreterSession.Side) -> some View {
        let language = session.language(side)
        let color = side == .a ? Self.colorA : Self.colorB
        let last = session.turns.last
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("\(language.flag) \(language.name)")
                    .font(.headline)
                    .foregroundStyle(color)
                if session.handsFree, session.nextSide == side {
                    Text(session.listeningSide == side ? "●" : "…")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
                Spacer()
                if let last, last.side != side, last.translation != nil {
                    Button {
                        session.replay(last)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if session.listeningSide == side {
                        Text(session.transcript.isEmpty ? language.listening : session.transcript)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(session.transcript.isEmpty ? .secondary : .primary)
                    } else if let last {
                        if last.side == side {
                            // Câu mình vừa nói, nhỏ hơn.
                            textBlock(last.source, language: language, size: 20, secondary: true)
                        } else if let translation = last.translation {
                            textBlock(translation, language: language, size: 30, secondary: false)
                        } else if last.failed {
                            Text("⚠️").font(.largeTitle)
                        } else {
                            ProgressView()
                        }
                    } else {
                        Text(language.tapToSpeak)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: session.turns)
            }

            micButton(side, size: 74)
                .padding(.bottom, side == .a ? 24 : 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(0.08))
        .background(Color(.systemBackground))
    }
}

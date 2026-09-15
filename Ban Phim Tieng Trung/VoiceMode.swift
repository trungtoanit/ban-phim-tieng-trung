//
//  VoiceMode.swift
//  Chế độ rảnh tay kiểu ChatGPT Voice: màn hình đen, quả cầu mây chuyển động theo trạng thái
//  (nghe, nghĩ, nói), phụ đề bật tắt được, ô nhắn bằng chữ, nút tắt micro và nút thoát.
//  Chạy trên chính phiên hội thoại theo lượt: AI nói xong là micro tự mở lại.
//

import SwiftUI

struct VoiceModeView: View {
    @ObservedObject var session: AIConversationSession

    private enum Status: Equatable { case listening, thinking, speaking, muted, idle }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("voiceModeCaptions") private var showCaptions = true
    @State private var muted = false
    @State private var draft = ""
    @State private var showHints = false
    @State private var showSettings = false
    @State private var previousHandsFree = true
    @State private var idleSince: Date?
    @FocusState private var typing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let status = currentStatus
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 12)
                    if showCaptions { captions(status) }
                    Spacer(minLength: 12)
                    VoiceOrb(status: orbState(status), level: CGFloat(min(session.micLevel, 1)),
                             time: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
                        .frame(width: 230, height: 230)
                        .onTapGesture { toggleMute() }
                        .accessibilityLabel(statusText(status))
                    Text(statusText(status))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 22)
                        .animation(.easeInOut(duration: 0.2), value: status)
                    Spacer(minLength: 12)
                    bottomBar
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
            .onChange(of: status) { keepLoopAlive($0) }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear(perform: enter)
        .onDisappear(perform: leave)
        .sheet(isPresented: $showHints) { hintsSheet }
        .sheet(isPresented: $showSettings) { OpenAISettingsView() }
    }

    // MARK: - Trạng thái

    private var currentStatus: Status {
        if muted { return .muted }
        if session.isThinking { return .thinking }
        if NaturalSpeaker.chinese.isSpeaking { return .speaking }
        if session.isListeningForReply { return .listening }
        return .idle
    }

    private func orbState(_ status: Status) -> VoiceOrb.State {
        switch status {
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .speaking
        case .muted: .muted
        case .idle: .thinking
        }
    }

    private func statusText(_ status: Status) -> String {
        switch status {
        case .listening: session.transcript.isEmpty ? "Đang nghe… cứ nói tiếng Trung" : "Đang nghe…"
        case .thinking: "Đang nghĩ…"
        case .speaking: "Chạm quả cầu để tắt micro"
        case .muted: "Micro đang tắt · chạm để bật"
        case .idle: "Đang chuẩn bị…"
        }
    }

    private func enter() {
        previousHandsFree = session.handsFree
        session.handsFree = true
        session.isTextMode = false
        if session.needsResumeChoice {
            session.resume()
        } else if session.messages.isEmpty {
            session.start()
        } else {
            session.listen()
        }
    }

    private func leave() {
        session.stopListening()
        session.handsFree = previousHandsFree
    }

    /// Như ChatGPT: không có gì đang diễn ra thì tự mở lại micro, kể cả sau một lúc im lặng.
    private func keepLoopAlive(_ status: Status) {
        guard status == .idle else {
            idleSince = nil
            return
        }
        let mark = Date()
        idleSince = mark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard idleSince == mark, currentStatus == .idle, !typing, !showHints, !showSettings else { return }
            session.listen()
        }
    }

    private func toggleMute() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        muted.toggle()
        if muted {
            session.handsFree = false
            session.stopListening()
        } else {
            session.handsFree = true
            NaturalSpeaker.all.forEach { $0.stop() }
            session.listen()
        }
    }

    // MARK: - Phần trên

    private var topBar: some View {
        HStack {
            circleButton(showCaptions ? "text.alignleft" : "text.badge.xmark", label: showCaptions ? "Ẩn phụ đề" : "Hiện phụ đề") {
                withAnimation(.easeInOut(duration: 0.25)) { showCaptions.toggle() }
            }
            Spacer()
            VStack(spacing: 2) {
                Text(session.scenario.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Chế độ rảnh tay")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            circleButton("slider.horizontal.3", label: "Cài đặt giọng nói") { showSettings = true }
        }
        .padding(.top, 6)
    }

    /// Phụ đề: câu AI vừa nói (chữ Hán, pinyin, nghĩa) và câu bạn đang nói.
    @ViewBuilder
    private func captions(_ status: Status) -> some View {
        VStack(spacing: 14) {
            if let last = session.messages.last(where: { $0.speaker == .partner }) {
                VStack(spacing: 6) {
                    RubyText(words: last.line.words, hanziSize: 22, pinyinColor: .white.opacity(0.6), hanziColor: .white)
                    if !last.line.vi.isEmpty {
                        Text(last.line.vi)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                .id(last.id)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if status == .listening, !session.transcript.isEmpty {
                Text(session.transcript)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(red: 0.7, green: 0.78, blue: 1))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: session.messages.count)
    }

    // MARK: - Phần dưới

    private var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showHints = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Gợi ý câu trả lời")

                TextField("", text: $draft, prompt: Text("Nhắn bằng chữ…").foregroundColor(.white.opacity(0.45)))
                    .foregroundStyle(.white)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                    .onChange(of: typing) { focused in
                        if focused { session.stopListening() }
                    }

                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Gửi")
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.62, blue: 1))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Capsule().fill(Color(white: 0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))

            Button(action: toggleMute) {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(muted ? .red : .white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color(white: 0.12)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            }
            .accessibilityLabel(muted ? "Bật micro" : "Tắt micro")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(.white))
            }
            .accessibilityLabel("Thoát chế độ rảnh tay")
        }
        .buttonStyle(PressableStyle())
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        typing = false
        NaturalSpeaker.all.forEach { $0.stop() }
        session.stopListening()
        session.send(text: text)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color(white: 0.12)))
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Gợi ý

    private var hintsSheet: some View {
        NavigationStack {
            List {
                let hints = session.messages.last(where: { $0.speaker == .partner })?.hints ?? []
                if hints.isEmpty {
                    Text("Chưa có gợi ý cho câu này.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                            Button {
                                showHints = false
                                session.speak(hint)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    RubyText(words: hint.words, hanziSize: 20)
                                    if !hint.vi.isEmpty {
                                        Text(hint.vi)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("Chạm để nghe mẫu, rồi tự nói lại câu đó.")
                    }
                }
            }
            .navigationTitle("Bí quá, gợi ý đi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showHints = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Quả cầu

/// Quả cầu mây xanh: các mảng mây trôi bên trong, to nhỏ theo giọng người nói và nhịp AI nói.
struct VoiceOrb: View {
    enum State: Equatable { case listening, thinking, speaking, muted }

    let status: State
    let level: CGFloat
    let time: TimeInterval
    var reduceMotion = false

    var body: some View {
        let t = reduceMotion ? 0 : time
        Canvas { context, size in
            let side = min(size.width, size.height)
            let scale = orbScale(t)
            let radius = side / 2 * scale
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

            var ctx = context
            ctx.clip(to: circle)
            ctx.fill(circle, with: .linearGradient(
                Gradient(colors: [Color(red: 0.42, green: 0.52, blue: 1), Color(red: 0.7, green: 0.78, blue: 1), Color(red: 0.8, green: 0.85, blue: 1)]),
                startPoint: CGPoint(x: center.x, y: center.y - radius),
                endPoint: CGPoint(x: center.x, y: center.y + radius)
            ))

            // Mây trôi: vài mảng trắng nhoè, tốc độ theo trạng thái.
            let speed: Double = switch status {
            case .speaking: 1.6
            case .listening: 0.9
            case .thinking: 0.5
            case .muted: 0.15
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: radius * 0.22))
                for index in 0..<6 {
                    let phase = t * speed + Double(index) * 1.7
                    let x = center.x + cos(phase * 0.7 + Double(index)) * radius * 0.45
                    let y = center.y + sin(phase * 0.5 + Double(index) * 2) * radius * 0.35 - radius * 0.1
                    let w = radius * (0.9 + 0.25 * sin(phase))
                    let h = radius * (0.35 + 0.1 * cos(phase * 1.3))
                    let white = index.isMultiple(of: 2)
                    layer.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
                               with: .color(white ? .white.opacity(0.85) : Color(red: 0.55, green: 0.62, blue: 1).opacity(0.7)))
                }
            }
            // Ánh sáng viền trên.
            ctx.fill(circle, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.25), .clear]),
                center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.45),
                startRadius: 0, endRadius: radius * 0.9
            ))
        }
        .opacity(status == .muted ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.3), value: status)
    }

    private func orbScale(_ t: TimeInterval) -> CGFloat {
        switch status {
        case .listening: 0.86 + level * 0.28 + CGFloat(sin(t * 2.2)) * 0.015
        case .speaking: 0.9 + CGFloat(abs(sin(t * 5.3)) * 0.07 + abs(sin(t * 3.1)) * 0.04)
        case .thinking: 0.84 + CGFloat(sin(t * 1.6)) * 0.03
        case .muted: 0.78
        }
    }
}

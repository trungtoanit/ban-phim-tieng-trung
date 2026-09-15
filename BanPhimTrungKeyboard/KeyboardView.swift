//
//  KeyboardView.swift
//  BanPhimTrungKeyboard
//

import SwiftUI
import UIKit

enum KeyColors {
    static let brand = Color(red: 0.86, green: 0.17, blue: 0.16)
    static let key = dynamic(light: .white, dark: UIColor(white: 0.42, alpha: 1))
    static let special = dynamic(light: UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1), dark: UIColor(white: 0.27, alpha: 1))
    static let pressed = dynamic(light: UIColor(white: 0.82, alpha: 1), dark: UIColor(white: 0.55, alpha: 1))
    static let card = dynamic(light: UIColor(white: 1, alpha: 0.8), dark: UIColor(white: 1, alpha: 0.1))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            modeBar
            previewCard
            controlRow
            bottomRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // MARK: - Thanh trên cùng

    private var modeBar: some View {
        HStack(spacing: 5) {
            ForEach(VoiceMode.allCases) { mode in
                chip(mode.label, selected: model.mode == mode && !model.readingSelected) { model.select(mode) }
            }
            clipboardButton
            chip(model.polite ? "您 Lịch sự" : "你 Thân mật", selected: false, outlined: model.polite) {
                model.polite.toggle()
            }
            Spacer(minLength: 2)
            Circle()
                .fill(model.appAlive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .accessibilityLabel(model.appAlive ? "Micro bật" : "Micro tắt")
        }
        .frame(height: 30)
    }

    private func chip(_ title: String, selected: Bool, outlined: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    Capsule().fill(selected ? KeyColors.brand : (outlined ? KeyColors.brand.opacity(0.15) : KeyColors.special))
                )
                .foregroundColor(selected ? .white : (outlined ? KeyColors.brand : .primary))
        }
        .buttonStyle(.plain)
    }

    private var clipboardButton: some View {
        Button {
            model.readClipboard()
        } label: {
            Text("📋 Hiểu tin")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    Capsule().fill(model.readingSelected ? KeyColors.brand : Color.clear)
                        .overlay(Capsule().strokeBorder(KeyColors.brand, lineWidth: 1.5))
                )
                .foregroundColor(model.readingSelected ? .white : KeyColors.brand)
                .overlay(alignment: .topTrailing) {
                    if model.clipboardHasNew {
                        Circle()
                            .fill(KeyColors.brand)
                            .frame(width: 9, height: 9)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Khung xem trước

    private var previewCard: some View {
        Group {
            if let detail = model.wordDetail {
                wordDetailView(detail)
            } else {
                previewContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KeyColors.card))
    }

    @ViewBuilder
    private var previewContent: some View {
        switch model.display {
        case .needsFullAccess:
            message("lock.fill", "Hãy bật “Cho phép truy cập đầy đủ”: Cài đặt → Cài đặt chung → Bàn phím → Bàn phím → Bàn Phím Trung.", tint: .orange)
        case .needsActivation:
            message("mic.badge.plus", "Nhấn 🎙 để bật micro (app sẽ mở ra 1 lần). Sau đó nhấn « ◀ » góc trên trái để quay lại đây.")
        case .openingApp:
            message("arrow.up.forward.app", "Đang mở app… Nếu app không tự mở, hãy mở “Bàn Phím Trung” và nhấn “Bật micro ngay”.")
        case .ready:
            message("waveform", "Nhấn 🎙 và nói \(model.mode.spokenLanguageName). Copy tin tiếng Trung rồi nhấn 📋 để hiểu nghĩa. Chạm vào từ để nghe phát âm.")
        case let .listening(text, level, live):
            HStack(alignment: .top, spacing: 10) {
                LevelBars(level: level)
                    .padding(.top, 4)
                liveTranscript(text: text, live: live)
            }
        case let .processing(text, live):
            if live.isEmpty {
                progress(model.mode == .chinese ? "Đang xử lý…" : "Đang dịch sang tiếng Trung…", text)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView()
                        .padding(.top, 4)
                    liveTranscript(text: text, live: live)
                }
            }
        case let .translatingTyped(source):
            progress("Đang dịch chữ đã gõ…", source)
        case let .result(words, chinese, source):
            cardWithActions(close: nil) {
                ruby(words)
                if let meaning = model.spokenChineseMeaning {
                    meaningLine(meaning.isEmpty ? nil : meaning)
                } else if source != chinese {
                    Text(source)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                if words.contains(where: { $0.flagged == true }) {
                    Text("Chữ màu đỏ: máy nghe chưa chắc. Chạm vào để xem máy còn nghe thành gì và sửa.")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
        case let .reading(words, meaning, failed, replies):
            cardWithActions(close: model.dismissPanel) {
                ruby(words)
                if let meaning {
                    Text(meaning)
                        .font(.system(size: 14))
                        .foregroundColor(failed ? .orange : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Đang dịch nghĩa…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                if !replies.isEmpty {
                    replyChips(replies)
                }
            }
        case let .error(text):
            HStack(alignment: .top) {
                message("exclamationmark.triangle.fill", text, tint: .orange)
                Spacer(minLength: 0)
                closeButton(model.dismissPanel)
            }
        }
    }

    /// Nghĩa tiếng Việt của câu tiếng Trung vừa nói.
    @ViewBuilder
    private func meaningLine(_ meaning: String?) -> some View {
        if let meaning {
            Text(meaning)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Đang dịch…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    /// Vừa nói vừa hiện: tiếng Việt máy đang nghe (nhỏ) và tiếng Trung dịch tạm kèm pinyin (lớn).
    private func liveTranscript(text: String, live: [PinyinWord]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if text.isEmpty {
                        Text("Đang nghe… hãy nói \(model.mode.spokenLanguageName)")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    } else if live.isEmpty || model.mode != .chinese {
                        Text(text)
                            .font(.system(size: live.isEmpty ? 15 : 12))
                            .foregroundColor(live.isEmpty ? .primary : .secondary)
                    }
                    if !live.isEmpty {
                        RubyText(
                            words: live,
                            hanziSize: rubySize(for: live.map(\.zh).joined()),
                            pinyinColor: .secondary,
                            showHanViet: model.showHanViet
                        )
                        .opacity(0.85)
                    }
                    if !model.liveMeaning.isEmpty {
                        meaningLine(model.liveMeaning)
                            .opacity(0.85)
                    }
                    Color.clear.frame(height: 1).id("live-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: live) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("live-bottom", anchor: .bottom) }
            }
        }
    }

    private func ruby(_ words: [PinyinWord]) -> some View {
        RubyText(
            words: words,
            hanziSize: rubySize(for: words.map(\.zh).joined()),
            showHanViet: model.showHanViet,
            onTapWord: model.showWord
        )
    }

    private func cardWithActions<Content: View>(close: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            VStack(spacing: 8) {
                if let close {
                    closeButton(close)
                }
                if model.canSave {
                    Button {
                        model.speakCurrent()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(KeyColors.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Nghe thử câu tiếng Trung trước khi gửi")
                    Button {
                        model.saveCurrent()
                    } label: {
                        Image(systemName: model.isCurrentSaved ? "star.fill" : "star")
                            .font(.system(size: 19))
                            .foregroundColor(model.isCurrentSaved ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lưu câu để luyện nói")
                }
            }
        }
    }

    private func replyChips(_ replies: [QuickReply]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trả lời nhanh")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(replies, id: \.self) { reply in
                        Button {
                            model.insertReply(reply)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reply.zh)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(reply.vi)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8).fill(KeyColors.key))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func wordDetailView(_ detail: KeyboardModel.WordDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(RubyText.splitPunctuation(detail.word.zh).core)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(detail.word.flagged == true ? .red : .primary)
                        Text(detail.word.py.trimmingCharacters(in: .punctuationCharacters))
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    if let hv = detail.word.hv {
                        Text("Hán Việt: \(hv)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.55, green: 0.35, blue: 0.2))
                    }
                    Text(detail.meaning.map { "Nghĩa: \($0)" } ?? "Đang tra nghĩa…")
                        .font(.system(size: 14))
                        .foregroundColor(detail.meaning == nil ? .secondary : .primary)
                    if detail.word.flagged == true {
                        pronunciationHint(detail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 10) {
                closeButton(model.closeWord)
                Button(action: model.speakWord) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(KeyColors.brand)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Giải thích bằng tiếng Việt: máy nghe khác ở thanh điệu, phụ âm đầu hay vần, và cách đọc lại.
    @ViewBuilder
    private func pronunciationHint(_ detail: KeyboardModel.WordDetail) -> some View {
        let heard = RubyText.splitPunctuation(detail.word.zh).core
        let alternatives = Array((detail.word.alternatives ?? []).prefix(3))

        if alternatives.isEmpty {
            explanationView(MistakeExplainer.explainUnclear(heard))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Máy nghe chưa chắc. Nếu ý bạn là:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                ForEach(alternatives, id: \.self) { alternative in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Button {
                                model.replaceWord(with: alternative)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(alternative)
                                        .font(.system(size: 17, weight: .semibold))
                                    if detail.index != nil {
                                        Image(systemName: "arrow.2.squarepath")
                                            .font(.system(size: 11))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 7).fill(KeyColors.key))
                                .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(detail.index == nil)
                            .accessibilityLabel("Sửa thành \(alternative)")

                            if let meaning = detail.alternativeMeanings[alternative] {
                                Text(meaning)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        explanationView(MistakeExplainer.explain(intended: alternative, heard: heard))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func explanationView(_ explanation: MistakeExplanation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(explanation.summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(explanation.isHomophone ? .green : .red)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(explanation.points, id: \.self) { point in
                Text("• \(point)")
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func progress(_ title: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 14))
                    .lineLimit(2)
            }
        }
    }

    /// Câu dài thì thu nhỏ chữ để vừa khung xem trước.
    private func rubySize(for chinese: String) -> CGFloat {
        switch chinese.count {
        case ..<11: 20
        case ..<17: 17
        case ..<24: 15
        default: 13
        }
    }

    private func message(_ icon: String, _ text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Phím

    private var controlRow: some View {
        ZStack {
            HStack(spacing: 6) {
                if model.needsGlobeKey {
                    KeyButton(systemImage: "globe", special: true) { model.nextKeyboard() }
                        .frame(width: 48)
                }
                KeyButton(systemImage: "arrow.uturn.backward", title: "Hoàn tác", special: true) { model.undo() }
                    .frame(width: 58)
                    .disabled(!model.canUndo)
                Spacer()
                RepeatKey(systemImage: "delete.left") { model.deleteBackward() }
                    .frame(width: 58)
                KeyButton(systemImage: "return", special: true) { model.insert("\n") }
                    .frame(width: 48)
            }
            MicButton(display: model.display) { model.micTapped() }
        }
        .frame(height: 64)
    }

    private var bottomRow: some View {
        HStack(spacing: 5) {
            ForEach(["，", "。", "？", "！"], id: \.self) { mark in
                KeyButton(title: mark) { model.insert(mark) }
                    .frame(width: 34)
            }
            KeyButton(title: "dấu cách") { model.insert(" ") }
            KeyButton(systemImage: "character.book.closed", title: "Dịch chữ gõ", special: true) { model.translateTyped() }
                .frame(width: 84)
        }
        .frame(height: 42)
    }
}

// MARK: - Thành phần

struct MicButton: View {
    let display: KeyboardModel.Display
    let action: () -> Void

    private var level: Float? {
        if case let .listening(_, level, _) = display { return level }
        return nil
    }

    private var isProcessing: Bool {
        if case .processing = display { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let level {
                    Circle()
                        .fill(KeyColors.brand.opacity(0.25))
                        .frame(width: 62 + CGFloat(level) * 24, height: 62 + CGFloat(level) * 24)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                Circle()
                    .fill(KeyColors.brand)
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                if isProcessing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: level == nil ? "mic.fill" : "stop.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 88, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct LevelBars: View {
    let level: Float
    private let weights: [CGFloat] = [0.45, 0.75, 1, 0.75, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(KeyColors.brand)
                    .frame(width: 4, height: 6 + 26 * CGFloat(level) * weights[index])
            }
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

struct KeyStyle: ButtonStyle {
    var special = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary.opacity(isEnabled ? 1 : 0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? KeyColors.pressed : (special ? KeyColors.special : KeyColors.key))
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            )
    }
}

struct KeyButton: View {
    var systemImage: String?
    var title: String?
    var special = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyLabel(systemImage: systemImage, title: title)
        }
        .buttonStyle(KeyStyle(special: special))
    }
}

struct KeyLabel: View {
    var systemImage: String?
    var title: String?

    var body: some View {
        VStack(spacing: 1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
            }
            if let title {
                Text(title)
                    .font(.system(size: systemImage == nil ? 17 : 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// Phím giữ để lặp lại (xoá liên tục).
struct RepeatKey: View {
    let systemImage: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        KeyLabel(systemImage: systemImage)
            .foregroundColor(.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPressed ? KeyColors.pressed : KeyColors.special)
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        timer?.invalidate()
                        timer = nil
                    }
            )
    }
}

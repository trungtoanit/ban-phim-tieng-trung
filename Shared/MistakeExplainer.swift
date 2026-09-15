//
//  MistakeExplainer.swift
//  Giải thích bằng tiếng Việt vì sao máy nghe khác ý người học: khác thanh điệu, phụ âm đầu
//  hay vần — kèm mẹo đọc lấy từ PinyinGuide. Dùng chung giữa app và bàn phím.
//

import Foundation

struct MistakeExplanation: Equatable {
    /// Câu tóm tắt, ví dụ "买 mǎi và 卖 mài chỉ khác thanh điệu."
    let summary: String
    /// Từng điểm khác nhau kèm cách sửa.
    let points: [String]
    /// Hai cách đọc giống hệt nhau: người học đọc đúng, máy chỉ chọn nhầm chữ.
    let isHomophone: Bool
}

enum MistakeExplainer {
    /// So chữ người học định nói (`intended`) với chữ máy nghe được (`heard`).
    static func explain(intended: String, heard: String) -> MistakeExplanation {
        let wanted = ChineseText.syllables(for: intended)
        let got = ChineseText.syllables(for: heard)
        let wantedPinyin = wanted.map(\.syllable).joined()
        let gotPinyin = got.map(\.syllable).joined()

        guard !wanted.isEmpty, !got.isEmpty else {
            return MistakeExplanation(summary: "Máy nghe thành \(heard) thay vì \(intended).", points: [], isHomophone: false)
        }

        if wantedPinyin.lowercased() == gotPinyin.lowercased() {
            return MistakeExplanation(
                summary: "\(intended) và \(heard) đọc giống hệt nhau (\(wantedPinyin)).",
                points: ["Bạn phát âm đúng rồi — máy chỉ chọn nhầm chữ đồng âm. Chọn chữ đúng ý để sửa."],
                isHomophone: true
            )
        }

        // Cùng số chữ: so từng chữ một. Khác số chữ: máy nghe thiếu hoặc thừa âm.
        guard wanted.count == got.count else {
            let missing = wanted.count > got.count
            return MistakeExplanation(
                summary: "Bạn định nói \(intended) (\(wantedPinyin)), máy nghe thành \(heard) (\(gotPinyin)).",
                points: [missing
                    ? "Máy nghe thiếu âm — có thể bạn đọc lướt hoặc nuốt chữ. Đọc chậm, tách rõ từng chữ."
                    : "Máy nghe thừa âm — có thể một chữ bị kéo dài thành hai. Đọc gọn, liền mạch hơn."],
                isHomophone: false
            )
        }

        var points: [String] = []
        var differingParts = Set<PronunciationPart>()
        var differingCount = 0
        for (want, heardChar) in zip(wanted, got) where want.syllable.lowercased() != heardChar.syllable.lowercased() {
            guard let expected = PinyinSyllable(want.syllable), let actual = PinyinSyllable(heardChar.syllable) else {
                points.append("\(want.char) đọc là \(want.syllable), máy nghe thành \(heardChar.char) \(heardChar.syllable).")
                continue
            }
            let prefix = wanted.count > 1 ? "Chữ \(want.char) (\(want.syllable)): " : ""
            differingCount += [expected.initial != actual.initial, expected.final != actual.final, expected.tone != actual.tone]
                .filter { $0 }.count

            if expected.initial != actual.initial {
                differingParts.insert(.initial)
                points.append(prefix + describe(.initial, expected: expected.initial, heard: actual.initial))
            }
            if expected.final != actual.final {
                differingParts.insert(.final)
                points.append(prefix + describe(.final, expected: expected.final, heard: actual.final))
            }
            if expected.tone != actual.tone {
                differingParts.insert(.tone)
                points.append(prefix + describe(.tone, expected: String(expected.tone), heard: String(actual.tone)))
            }
        }

        // Gần như mọi phần đều khác: máy nghe ra một từ khác hẳn, liệt kê từng lỗi chỉ gây rối.
        if differingCount > wanted.count * 2 {
            return MistakeExplanation(
                summary: "Bạn định nói \(intended) (\(wantedPinyin)), máy nghe ra một từ khác hẳn: \(heard) (\(gotPinyin)).",
                points: ["Máy chưa nhận ra từ này. Nhấn 🔊 nghe mẫu, rồi đọc chậm và rõ từng chữ: \(wanted.map { "\($0.char) \($0.syllable)" }.joined(separator: ", "))."],
                isHomophone: false
            )
        }

        let partNames = PronunciationPart.allCases
            .filter(differingParts.contains)
            .map { $0 == .initial ? "phụ âm đầu" : ($0 == .final ? "vần" : "thanh điệu") }
        let summary = partNames.isEmpty
            ? "Bạn định nói \(intended) (\(wantedPinyin)), máy nghe thành \(heard) (\(gotPinyin))."
            : "Bạn định nói \(intended) (\(wantedPinyin)), máy nghe thành \(heard) (\(gotPinyin)) — khác ở \(partNames.joined(separator: ", "))."
        return MistakeExplanation(summary: summary, points: Array(points.prefix(3)), isHomophone: false)
    }

    /// Máy chỉ báo không chắc, không nghe ra chữ khác: nhắc cách đọc thanh điệu và âm khó của chữ đó.
    static func explainUnclear(_ text: String) -> MistakeExplanation {
        let syllables = ChineseText.syllables(for: text)
        var points: [String] = []
        var seenTones = Set<Int>()
        for item in syllables {
            guard let syllable = PinyinSyllable(item.syllable) else { continue }
            if !seenTones.contains(syllable.tone) {
                seenTones.insert(syllable.tone)
                let guide = syllable.tone == 5 ? PinyinGuide.neutralTone : PinyinGuide.guide(.tone, key: String(syllable.tone))
                if let guide {
                    points.append("\(item.char) \(item.syllable) — \(toneName(guide)): \(guide.tip)")
                }
            }
            // Âm người Việt hay đọc sai: uốn lưỡi, bật hơi, ü.
            if ["zh", "ch", "sh", "r", "z", "c", "q", "p", "t", "k"].contains(syllable.initial),
               let guide = PinyinGuide.guide(.initial, key: syllable.initial) {
                points.append("Âm \(guide.symbol) trong \(item.syllable): \(guide.tip)")
            } else if syllable.final.contains("ü"), let guide = PinyinGuide.guide(.final, key: syllable.final) {
                points.append("Vần \(guide.symbol) trong \(item.syllable): \(guide.tip)")
            }
        }
        let pinyin = syllables.map(\.syllable).joined()
        return MistakeExplanation(
            summary: "Máy nghe chưa chắc chữ \(text)\(pinyin.isEmpty ? "" : " (\(pinyin))") — thường do thanh điệu hoặc âm đầu chưa rõ.",
            points: Array(points.prefix(3)),
            isHomophone: false
        )
    }

    private static func describe(_ part: PronunciationPart, expected: String, heard: String) -> String {
        let kind: SoundGuide.Kind = part == .initial ? .initial : (part == .final ? .final : .tone)
        let expectedLabel = label(kind, expected)
        let heardLabel = label(kind, heard)
        let partName = part == .initial ? "Phụ âm đầu" : (part == .final ? "Vần" : "Thanh điệu")

        var text = "\(partName): cần \(expectedLabel), máy nghe ra \(heardLabel)."
        if let tip = PinyinGuide.pairTip(kind, expected, heard) {
            text += " \(tip)"
        } else if let guide = guide(kind, expected) {
            text += " Cách đọc \(expectedLabel): \(guide.tip)"
        }
        return text
    }

    /// "Thanh 3 ˇ (xuống thấp rồi lên)" — bỏ số cao độ (214) cho dễ đọc.
    private static func toneName(_ guide: SoundGuide) -> String {
        let symbol = guide.symbol.replacingOccurrences(of: "  ", with: " ")
        let group = guide.group.replacingOccurrences(of: #"\s*\(\d+\)"#, with: "", options: .regularExpression)
        return "\(symbol) (\(group.lowercased()))"
    }

    private static func guide(_ kind: SoundGuide.Kind, _ key: String) -> SoundGuide? {
        kind == .tone && key == "5" ? PinyinGuide.neutralTone : PinyinGuide.guide(kind, key: key)
    }

    private static func label(_ kind: SoundGuide.Kind, _ key: String) -> String {
        switch kind {
        case .tone:
            guard let guide = guide(.tone, key) else { return "thanh \(key)" }
            return toneName(guide)
        case .initial:
            return key.isEmpty ? "không có phụ âm đầu" : "“\(PinyinGuide.label(.initial, key: key))”"
        case .final:
            return "“\(PinyinGuide.label(.final, key: key))”"
        }
    }
}

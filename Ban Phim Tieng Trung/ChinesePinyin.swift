//
//  ChinesePinyin.swift
//  Ban Phim Tieng Trung
//
//  Chuyển câu tiếng Trung thành pinyin theo từng từ. Bộ chuyển của iOS đọc từng chữ riêng lẻ
//  (谢谢 → xièxiè, 一下 → yīxià), nên ở đây tách từ, tra từ điển rồi áp dụng quy tắc biến điệu.
//

import Foundation
import NaturalLanguage

enum ChineseText {
    static func containsHan(_ text: String) -> Bool {
        text.contains(where: isHan)
    }

    static func pinyin(for text: String) -> String {
        words(for: text).map(\.py).joined(separator: " ")
    }

    static func words(for text: String) -> [PinyinWord] {
        var units: [Unit] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = text

        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            attachGap(text[cursor..<range.lowerBound], to: &units)
            units.append(unit(for: String(text[range])))
            cursor = range.upperBound
            return true
        }
        attachGap(text[cursor...], to: &units)

        mergeErhua(&units)
        applyContextRules(&units)
        applyToneSandhi(&units)

        // Viết hoa chữ đầu câu.
        var capitalizeNext = true
        return units.map { unit in
            var py = unit.pinyin
            if capitalizeNext, let first = py.first {
                py = first.uppercased() + py.dropFirst()
            }
            if !py.isEmpty || !unit.trailing.isEmpty {
                capitalizeNext = py.isEmpty ? capitalizeNext : unit.trailing.contains(where: { "。？！.?!".contains($0) })
            }
            return PinyinWord(zh: unit.zh + unit.trailing, py: py + asciiPunctuation(unit.trailing), hv: hanViet(for: unit))
        }
    }

    // MARK: - Đơn vị từ

    private struct Unit {
        var zh: String
        /// Một âm tiết cho mỗi ký tự trong `zh`; rỗng khi không phải chữ Hán.
        var syllables: [String]
        var trailing = ""
        var literal: String?

        var pinyin: String {
            if let literal { return literal }
            var result = ""
            for syllable in syllables where !syllable.isEmpty {
                if !result.isEmpty, let first = syllable.first, "aoeāáǎàōóǒòēéěè".contains(first) {
                    result += "'"
                }
                result += syllable
            }
            return result
        }
    }

    private static func unit(for token: String) -> Unit {
        guard token.contains(where: isHan) else {
            return Unit(zh: token, syllables: [], literal: token)
        }
        let chars = token.map(String.init)

        if chars.count == 1, let particle = particles[token] {
            return Unit(zh: token, syllables: [particle])
        }
        if let known = dictionary[token], known.count == chars.count {
            return Unit(zh: token, syllables: known)
        }

        // Tách tiếp thành các từ có trong từ điển (khớp dài nhất), phần còn lại đọc từng chữ.
        var syllables: [String] = []
        var index = 0
        while index < chars.count {
            var matched = false
            for length in stride(from: min(4, chars.count - index), through: 2, by: -1) {
                let word = chars[index..<index + length].joined()
                if let known = dictionary[word], known.count == length {
                    syllables += known
                    index += length
                    matched = true
                    break
                }
            }
            if !matched {
                let char = chars[index]
                syllables.append(dictionary[char]?.first ?? transliterate(char))
                index += 1
            }
        }
        return Unit(zh: token, syllables: syllables)
    }

    private static func attachGap(_ gap: Substring, to units: inout [Unit]) {
        let punctuation = gap.filter { !$0.isWhitespace }
        guard !punctuation.isEmpty else { return }
        if units.isEmpty {
            units.append(Unit(zh: "", syllables: [], trailing: String(punctuation), literal: ""))
        } else {
            units[units.count - 1].trailing += punctuation
        }
    }

    // MARK: - Hán Việt

    private static func hanViet(for unit: Unit) -> String? {
        guard unit.literal == nil else { return nil }
        var readings: [String] = []
        for (index, char) in unit.zh.map(String.init).enumerated() {
            let syllable = index < unit.syllables.count ? unit.syllables[index] : ""
            // Bỏ 儿 khi đã gộp âm (点儿 → diǎnr) và trợ từ đọc nhẹ (了, 的, 吗…).
            if char == "儿", syllable.isEmpty { continue }
            if particles[char] != nil, tone(of: syllable) == 0 { continue }
            if let reading = hanVietReading(char, syllable: syllable) {
                readings.append(reading)
            }
        }
        return readings.isEmpty ? nil : readings.joined(separator: " ")
    }

    /// Âm Hán Việt cho một từ khi chỉ có pinyin cả từ (ví dụ từ do AI tách): tách âm tiết theo từng chữ nếu được.
    static func hanViet(forWord zh: String, pinyin: String) -> String? {
        let chars = zh.filter(isHan).map(String.init)
        guard !chars.isEmpty else { return nil }
        let known = dictionary[chars.joined()]
        var readings: [String] = []
        for (index, char) in chars.enumerated() {
            let syllable = known.flatMap { index < $0.count ? $0[index] : nil } ?? ""
            if char == "儿", index > 0, known != nil, syllable.isEmpty { continue }
            if particles[char] != nil, chars.count == 1, tone(of: pinyin) == 0 { continue }
            if let reading = hanVietReading(char, syllable: syllable) {
                readings.append(reading)
            }
        }
        return readings.isEmpty ? nil : readings.joined(separator: " ")
    }

    /// Chọn âm Hán Việt theo pinyin của chữ (行 xíng → hành, háng → hàng).
    static func hanVietReading(_ char: String, syllable: String) -> String? {
        guard let readings = hanVietDictionary[char], let first = readings.first, first.count == 2 else { return nil }
        // Khóa có dấu thanh (好 hào → hiếu) được ưu tiên trước khóa không dấu.
        var toned = syllable.lowercased()
        if toned.count > 2, toned.hasSuffix("r"), toned != "er" { toned.removeLast() }
        if let exact = readings.first(where: { $0.count == 2 && $0[0] == toned }) { return exact[1] }

        var key = syllable.replacingOccurrences(of: "ü", with: "v")
        key = (key.applyingTransform(.stripDiacritics, reverse: false) ?? key).lowercased()
        if key.count > 2, key.hasSuffix("r"), key != "er" { key.removeLast() }
        return readings.first { $0.count == 2 && $0[0] == key }?[1] ?? first[1]
    }

    // MARK: - Quy tắc

    /// 点 + 儿 → diǎnr (trừ các từ mà 儿 đọc rõ như 儿子, 女儿).
    private static func mergeErhua(_ units: inout [Unit]) {
        var index = 0
        while index < units.count {
            var unit = units[index]
            let chars = unit.zh.map(String.init)
            for (i, char) in chars.enumerated() where char == "儿" && i > 0 && unit.syllables.count == chars.count {
                let pair = chars[i - 1] + char
                if erhuaExceptions.contains(pair) || unit.syllables[i].isEmpty { continue }
                unit.syllables[i - 1] += "r"
                unit.syllables[i] = ""
            }
            units[index] = unit

            if unit.zh == "儿", index > 0,
               units[index - 1].literal == nil, units[index - 1].trailing.isEmpty,
               let lastChar = units[index - 1].zh.last,
               !erhuaExceptions.contains(String(lastChar) + "儿") {
                var previous = units[index - 1]
                previous.zh += "儿"
                previous.syllables[previous.syllables.count - 1] += "r"
                previous.syllables.append("")
                previous.trailing = unit.trailing
                units[index - 1] = previous
                units.remove(at: index)
                continue
            }
            index += 1
        }
    }

    /// 我得走 → děi (得 đứng sau đại từ nghĩa là "phải").
    private static func applyContextRules(_ units: inout [Unit]) {
        for index in units.indices.dropFirst() where units[index].zh == "得" && units[index - 1].trailing.isEmpty {
            if pronouns.contains(units[index - 1].zh) {
                units[index].syllables = ["děi"]
            }
        }
    }

    /// 不 + thanh 4 → bú; 一 + thanh 4 → yí, + thanh 1/2/3 → yì (trừ khi là số đếm, số thứ tự).
    private static func applyToneSandhi(_ units: inout [Unit]) {
        var positions: [(unit: Int, char: Int, zh: String)] = []
        for (u, unit) in units.enumerated() where unit.literal == nil {
            for (c, char) in unit.zh.map(String.init).enumerated() where c < unit.syllables.count && !unit.syllables[c].isEmpty {
                positions.append((u, c, char))
            }
        }

        for (k, position) in positions.enumerated() {
            let syllable = units[position.unit].syllables[position.char]
            guard k + 1 < positions.count else { continue }
            let next = positions[k + 1]
            let nextSyllable = units[next.unit].syllables[next.char]
            let nextTone = next.zh == "个" ? 4 : tone(of: nextSyllable)

            let previous = k > 0 ? positions[k - 1].zh : ""

            if position.zh == "不", syllable == "bù", previous == next.zh {
                // 是不是, 要不要: 不 đọc nhẹ.
                units[position.unit].syllables[position.char] = "bu"
            } else if position.zh == "不", syllable == "bù", nextTone == 4 {
                units[position.unit].syllables[position.char] = "bú"
            } else if position.zh == "一", syllable == "yī" {
                let endsWord = position.char == units[position.unit].zh.count - 1 && units[position.unit].zh.count > 1
                let countsDigits = numberChars.contains(next.zh) && !["百", "千", "万"].contains(next.zh)
                guard !numberChars.contains(previous), !countsDigits, previous != "第", !endsWord else { continue }
                if nextTone == 4 {
                    units[position.unit].syllables[position.char] = "yí"
                } else if (1...3).contains(nextTone) {
                    units[position.unit].syllables[position.char] = "yì"
                }
            }
        }
    }

    private static func tone(of syllable: String) -> Int {
        for char in syllable {
            if "āōēīūǖ".contains(char) { return 1 }
            if "áóéíúǘ".contains(char) { return 2 }
            if "ǎǒěǐǔǚ".contains(char) { return 3 }
            if "àòèìùǜ".contains(char) { return 4 }
        }
        return 0
    }

    private static func transliterate(_ char: String) -> String {
        let latin = char.applyingTransform(.mandarinToLatin, reverse: false) ?? char
        return latin.trimmingCharacters(in: .whitespaces)
    }

    private static func isHan(_ char: Character) -> Bool {
        char.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    private static func asciiPunctuation(_ text: String) -> String {
        let map: [Character: String] = ["，": ",", "。": ".", "？": "?", "！": "!", "、": ",", "：": ":", "；": ";",
                                        "“": "\"", "”": "\"", "（": "(", "）": ")", "…": "…", "～": "~"]
        return text.map { map[$0] ?? String($0) }.joined()
    }

    // MARK: - Dữ liệu

    private static let particles: [String: String] = [
        "了": "le", "的": "de", "得": "de", "着": "zhe", "个": "ge", "吗": "ma", "呢": "ne", "吧": "ba",
        "啊": "a", "么": "me", "啦": "la", "嘛": "ma", "呀": "ya", "哦": "o", "呗": "bei", "嘞": "lei",
        "喂": "wéi",
    ]

    private static let pronouns: Set<String> = ["我", "你", "您", "他", "她", "我们", "你们", "他们", "她们", "咱们", "大家", "咱"]

    private static let erhuaExceptions: Set<String> = ["儿儿", "女儿", "婴儿", "幼儿", "孤儿", "健儿", "男儿", "少儿", "胎儿", "宠儿"]
    private static let numberChars: Set<String> = ["零", "一", "二", "两", "三", "四", "五", "六", "七", "八", "九", "十", "百", "千", "万", "亿"]

    static var dictionaryURL = Bundle.main.url(forResource: "pinyin-dict", withExtension: "json")
    static var hanVietURL = Bundle.main.url(forResource: "hanviet", withExtension: "json")

    /// 字 → [[pinyin không dấu, âm Hán Việt]], cách đọc thông dụng nhất đứng đầu.
    private static let hanVietDictionary: [String: [[String]]] = {
        guard let url = hanVietURL,
              let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: [[String]]].self, from: data)
        else { return [:] }
        return dictionary
    }()

    private static let dictionary: [String: [String]] = {
        guard let url = dictionaryURL,
              let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return dictionary
    }()
}

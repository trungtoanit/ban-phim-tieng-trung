//
//  PhraseMatcher.swift
//  So khớp câu nói tiếng Trung (dùng cho luyện nói và gợi ý trả lời).
//

import Foundation

enum PhraseMatcher {
    static func isCorrect(heard: String, target: String) -> Bool {
        let heardText = normalize(heard)
        let targetText = normalize(target)
        guard !heardText.isEmpty, !targetText.isEmpty else { return false }
        if heardText == targetText { return true }
        if similarity(Array(heardText), Array(targetText)) >= 0.85 { return true }

        // Chấp nhận chữ đồng âm (他/她, 在/再…) khi phát âm giống hệt.
        let heardPinyin = tonelessPinyin(heardText)
        let targetPinyin = tonelessPinyin(targetText)
        guard !heardPinyin.isEmpty, !targetPinyin.isEmpty else { return false }
        return similarity(Array(heardPinyin), Array(targetPinyin)) >= 0.9
    }

    /// Dạng đã chuẩn hoá của một câu, tính trước để so khớp nhanh với nhiều câu.
    struct Key {
        fileprivate let chars: [Character]
        fileprivate let pinyin: [Character]
    }

    static func key(_ text: String) -> Key {
        let normalized = normalize(text)
        return Key(chars: Array(normalized), pinyin: Array(tonelessPinyin(normalized)))
    }

    /// Độ giống nhau 0…1 (lấy mức cao hơn giữa so chữ và so pinyin không dấu).
    static func similarity(_ a: Key, _ b: Key) -> Double {
        guard !a.chars.isEmpty, !b.chars.isEmpty else { return 0 }
        return max(similarity(a.chars, b.chars), similarity(a.pinyin, b.pinyin))
    }

    /// Chấm phát âm: so câu máy nghe tốt nhất với các phương án khác của máy.
    /// Từ nào các phương án không khớp nhau thì đánh dấu, kèm chữ máy còn nghe thành.
    static func markAlternatives(words: [PinyinWord], alternatives: [String]) -> [PinyinWord] {
        // 儿 hay bị máy bỏ qua (点儿 → 点) nên không tính là khác.
        func comparable(_ char: Character) -> Bool { char.isLetter && char != "儿" }
        let best = words.flatMap { word in word.zh.filter(comparable) }
        guard !best.isEmpty else { return words }
        var result = words

        for alternative in alternatives {
            let alt = Array(alternative.filter(comparable))
            // Bỏ qua phương án khác hẳn câu chính (máy đoán lung tung).
            guard !alt.isEmpty, alt != best, similarity(best, alt) >= 0.5 else { continue }
            let mapping = matches(best, alt)

            // Chữ của phương án ứng với từng vị trí: khớp thì lấy luôn, đoạn thay thế cùng độ dài thì ghép 1-1,
            // đoạn khác độ dài thì gắn cả đoạn vào vị trí đầu.
            var aligned = [String](repeating: "", count: best.count)
            var i = 0
            var previous = -1
            while i < best.count {
                if let j = mapping[i] {
                    aligned[i] = String(alt[j])
                    previous = j
                    i += 1
                    continue
                }
                var k = i
                while k < best.count, mapping[k] == nil { k += 1 }
                let next = k < best.count ? mapping[k]! : alt.count
                let run = previous + 1 < next ? Array(alt[(previous + 1)..<next]) : []
                if run.count == k - i {
                    for t in 0..<run.count { aligned[i + t] = String(run[t]) }
                } else {
                    aligned[i] = String(run)
                }
                i = k
            }

            var start = 0
            for (index, word) in words.enumerated() {
                let count = word.zh.filter(comparable).count
                let end = start + count
                defer { start = end }
                guard count > 0, (start..<end).contains(where: { mapping[$0] == nil }) else { continue }

                result[index].flagged = true
                let candidate = aligned[start..<end].joined()
                let core = String(word.zh.filter(comparable))
                if !candidate.isEmpty, candidate != core, candidate.count <= count + 2,
                   !(result[index].alternatives ?? []).contains(candidate) {
                    result[index].alternatives = (result[index].alternatives ?? []) + [candidate]
                }
            }
        }
        return result
    }

    /// Dãy con chung dài nhất: vị trí trong `b` khớp với từng ký tự của `a` (nil nếu không khớp).
    private static func matches(_ a: [Character], _ b: [Character]) -> [Int?] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result = [Int?](repeating: nil, count: n)
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                result[i] = j
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    /// Đánh dấu những từ trong câu mẫu mà người dùng đọc thiếu hoặc sai (so từng chữ, chấp nhận đồng âm).
    static func flagMissedWords(heard: String, words: [PinyinWord]) -> [PinyinWord] {
        let heardChars = Array(normalize(heard)).map(String.init)
        var targetChars: [(char: String, word: Int)] = []
        for (index, word) in words.enumerated() {
            for char in normalize(word.zh) {
                targetChars.append((String(char), index))
            }
        }
        guard !targetChars.isEmpty else { return words }

        func same(_ x: String, _ y: String) -> Bool {
            x == y || (!tonelessPinyin(x).isEmpty && tonelessPinyin(x) == tonelessPinyin(y))
        }

        // Dãy con chung dài nhất giữa câu nghe được và câu mẫu.
        let n = heardChars.count, m = targetChars.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 {
            for i in 1...n {
                for j in 1...m {
                    table[i][j] = same(heardChars[i - 1], targetChars[j - 1].char)
                        ? table[i - 1][j - 1] + 1
                        : max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        var matched = Array(repeating: false, count: m)
        var i = n, j = m
        while i > 0, j > 0 {
            if same(heardChars[i - 1], targetChars[j - 1].char), table[i][j] == table[i - 1][j - 1] + 1 {
                matched[j - 1] = true
                i -= 1
                j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        var result = words
        for (k, target) in targetChars.enumerated() where !matched[k] {
            result[target.word].flagged = true
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        let withNumbers = replaceDigits(in: text)
        return String(withNumbers.lowercased().filter { $0.isLetter })
            .replacingOccurrences(of: "儿", with: "")
            .replacingOccurrences(of: "两", with: "二")
    }

    private static func tonelessPinyin(_ text: String) -> String {
        let latin = text.applyingTransform(.mandarinToLatin, reverse: false) ?? ""
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return String(plain.lowercased().filter { $0.isLetter })
    }

    private static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(longest)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Nhận dạng giọng nói hay trả về chữ số ("3点"), còn dữ liệu viết bằng chữ Hán ("三点").
    private static func replaceDigits(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\d+") else { return text }
        var result = text
        let range = NSRange(result.startIndex..., in: result)
        for match in regex.matches(in: result, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let digits = String(result[swiftRange])
            result.replaceSubrange(swiftRange, with: chineseNumber(digits))
        }
        return result
    }

    private static func chineseNumber(_ digits: String) -> String {
        let names = Array("零一二三四五六七八九")
        guard digits.count <= 4, let value = Int(digits) else {
            return String(digits.compactMap { $0.wholeNumberValue.map { names[$0] } })
        }
        if value < 10 { return String(names[value]) }
        if value < 20 { return "十" + (value % 10 == 0 ? "" : String(names[value % 10])) }

        let units = ["千", "百", "十", ""]
        let parts = [value / 1000, value / 100 % 10, value / 10 % 10, value % 10]
        var result = ""
        var pendingZero = false
        for (index, digit) in parts.enumerated() {
            if digit == 0 {
                pendingZero = !result.isEmpty
                continue
            }
            if pendingZero { result.append("零") }
            pendingZero = false
            result += String(names[digit]) + units[index]
        }
        return result
    }
}

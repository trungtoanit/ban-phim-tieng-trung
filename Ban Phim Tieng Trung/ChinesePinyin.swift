//
//  ChinesePinyin.swift
//  Ban Phim Tieng Trung
//
//  Chuyển câu tiếng Trung thành pinyin theo từng từ. Bộ chuyển của iOS đọc từng chữ riêng lẻ
//  (谢谢 → xièxiè, 一下 → yīxià), nên ở đây tách từ, tra từ điển rồi áp dụng quy tắc biến điệu.
//
//  Tách từ kiểu jieba: chọn cách tách có tổng xác suất từ lớn nhất theo lexicon.txt
//  (tần suất jieba + pinyin CC-CEDICT, dựng bằng Tools/build_lexicon.py). NLTokenizer của iOS
//  hay dính chữ sai (口语得 → 口|语得, 不一定 → 不一|定) nên không dùng nữa.
//

import Foundation

enum ChineseText {
    static func containsHan(_ text: String) -> Bool {
        text.contains(where: isHan)
    }

    static func pinyin(for text: String) -> String {
        words(for: text).map(\.py).joined(separator: " ")
    }

    /// Âm tiết của từng chữ Hán theo đúng thứ tự trong câu, đã áp dụng biến điệu 一/不.
    /// Dùng để so từng chữ câu mẫu với chữ máy nghe được.
    static func syllables(for text: String) -> [(char: String, syllable: String)] {
        units(for: text).flatMap { unit -> [(char: String, syllable: String)] in
            guard unit.literal == nil else { return [] }
            return zip(unit.zh.map(String.init), unit.syllables).compactMap { char, syllable in
                guard let first = char.first, isHan(first), !syllable.isEmpty else { return nil }
                return (char, syllable)
            }
        }
    }

    static func words(for text: String) -> [PinyinWord] {
        let units = units(for: text)

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

    private static func units(for text: String) -> [Unit] {
        var units: [Unit] = []
        var pendingPrefix: String?
        let chars = Array(text)

        var index = 0
        while index < chars.count {
            var end = index + 1
            if isHan(chars[index]) {
                while end < chars.count, isHan(chars[end]) { end += 1 }
                for word in segment(chars[index..<end].map(String.init)) {
                    // 两个人: 个 là lượng từ của số đứng trước, không phải từ 个人 "cá nhân".
                    if word == "个人", let last = units.last?.zh.last, units.last?.trailing.isEmpty == true,
                       numberChars.contains(String(last)) || "几这那哪每".contains(last) {
                        units += [unit(for: "个"), unit(for: "人")]
                    } else if word == "没收", chars[index..<end].map(String.init).joined().contains("没收到") {
                        // 没收到钱: "chưa nhận được", không phải 没收 "tịch thu".
                        units.append(unit(for: "没"))
                        pendingPrefix = "收"
                    } else if let prefix = pendingPrefix {
                        pendingPrefix = nil
                        units += segment((prefix + word).map(String.init)).map(unit(for:))
                    } else {
                        units.append(unit(for: word))
                    }
                }
                if let prefix = pendingPrefix {
                    units.append(unit(for: prefix))
                    pendingPrefix = nil
                }
            } else if isWordChar(chars[index]) {
                // Chữ Latin / số giữ nguyên cả cụm, kể cả 3.5 hay 10:30.
                while end < chars.count, isWordChar(chars[end])
                        || (end + 1 < chars.count && ".,:".contains(chars[end])
                            && chars[end - 1].isNumber && chars[end + 1].isNumber) {
                    end += 1
                }
                let literal = String(chars[index..<end])
                units.append(Unit(zh: literal, syllables: [], literal: literal))
            } else {
                while end < chars.count, !isHan(chars[end]), !isWordChar(chars[end]) { end += 1 }
                attachGap(String(chars[index..<end]), to: &units)
            }
            index = end
        }

        mergeErhua(&units)
        mergeReduplicatedVerbs(&units)
        applyContextRules(&units)
        applyToneSandhi(&units)
        return units
    }

    private static func isWordChar(_ char: Character) -> Bool {
        !isHan(char) && (char.isLetter || char.isNumber)
    }

    /// Tách một đoạn toàn chữ Hán thành từ: quy hoạch động chọn cách tách có tổng log xác suất
    /// lớn nhất (như jieba). Chữ lạ không có trong từ điển đứng riêng với xác suất thấp nhất.
    static func segment(_ chars: [String]) -> [String] {
        let lexicon = self.lexicon
        let count = chars.count
        guard count > 1 else { return chars }

        // best[i]: điểm tốt nhất cho phần từ chữ i đến hết; length[i]: độ dài từ bắt đầu tại i.
        var best = [Float](repeating: 0, count: count + 1)
        var length = [Int](repeating: 1, count: count + 1)
        for start in stride(from: count - 1, through: 0, by: -1) {
            best[start] = -.infinity
            var word = ""
            for size in 1...min(lexicon.maxLength, count - start) {
                word += chars[start + size - 1]
                let score: Float
                if let entry = lexicon.entries[word] {
                    score = entry.logFrequency
                } else if size == 1 {
                    score = lexicon.unknownLogFrequency
                } else {
                    continue
                }
                // >= để khi bằng điểm thì ưu tiên từ dài hơn.
                if score + best[start + size] >= best[start] {
                    best[start] = score + best[start + size]
                    length[start] = size
                }
            }
        }

        var words: [String] = []
        var start = 0
        while start < count {
            words.append(chars[start..<start + length[start]].joined())
            start += length[start]
        }
        return words
    }

    // MARK: - Đơn vị từ

    private struct Unit {
        var zh: String
        /// Một âm tiết cho mỗi ký tự trong `zh`; rỗng khi không phải chữ Hán.
        var syllables: [String]
        var trailing = ""
        var literal: String?
        /// Từ loại theo jieba (v động từ, a tính từ, n danh từ, r đại từ, m số từ…), rỗng nếu không rõ.
        var pos = ""

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
        let entry = lexicon.entries[token]
        let pos = entry?.pos ?? ""

        if chars.count == 1, let particle = particles[token] {
            return Unit(zh: token, syllables: [particle], pos: pos)
        }
        // Từ điển riêng của app (dựng theo câu mẫu) được ưu tiên hơn CC-CEDICT.
        if let known = dictionary[token], known.count == chars.count {
            return Unit(zh: token, syllables: known, pos: pos)
        }
        if chars.count > 1, let pinyin = entry?.pinyin {
            let syllables = pinyin.split(separator: " ").map(String.init)
            if syllables.count == chars.count {
                var unit = Unit(zh: token, syllables: syllables, pos: pos)
                // Phần đầu / đuôi có trong từ điển riêng thì theo từ điển riêng (到时候 → shíhou).
                for size in stride(from: chars.count - 1, through: 2, by: -1) {
                    if let known = dictionary[chars.suffix(size).joined()], known.count == size {
                        unit.syllables.replaceSubrange(chars.count - size..<chars.count, with: known)
                        break
                    }
                }
                for size in stride(from: chars.count - 1, through: 2, by: -1) {
                    if let known = dictionary[chars.prefix(size).joined()], known.count == size {
                        unit.syllables.replaceSubrange(0..<size, with: known)
                        break
                    }
                }
                return unit
            }
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
        return Unit(zh: token, syllables: syllables, pos: pos)
    }

    private static func attachGap(_ gap: String, to units: inout [Unit]) {
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

    /// 说说, 试试, 尝尝: động từ một chữ lặp lại gộp thành một từ, chữ sau đọc nhẹ.
    private static func mergeReduplicatedVerbs(_ units: inout [Unit]) {
        var index = units.count - 1
        while index > 0 {
            let first = units[index - 1], second = units[index]
            if first.zh.count == 1, first.zh == second.zh, first.trailing.isEmpty, first.literal == nil,
               isVerb(first), first.syllables.count == 1, second.syllables.count == 1 {
                units[index - 1].zh += second.zh
                units[index - 1].syllables.append(neutralTone(second.syllables[0]))
                units[index - 1].trailing = second.trailing
                units.remove(at: index)
            }
            index -= 1
        }
    }

    /// Chữ đa âm đọc theo ngữ cảnh: bổ ngữ khả năng (吃不了 chī bu liǎo, 睡不着 shuì bu zháo),
    /// 得 "phải" (今天得加班 děi), 过 sau động từ (去过 guo), 还 "trả" (还你 huán)…
    private static func applyContextRules(_ units: inout [Unit]) {
        applyPotentialComplements(&units)

        for index in units.indices where units[index].literal == nil && units[index].syllables.count == 1 {
            // Chỉ xét từ đứng cạnh trong cùng một vế câu (không cách bởi dấu câu).
            let previous = index > 0 && units[index - 1].literal == nil && units[index - 1].trailing.isEmpty
                ? units[index - 1] : nil
            let next = index + 1 < units.count && units[index + 1].literal == nil && units[index].trailing.isEmpty
                ? units[index + 1] : nil
            let previousZh = previous?.zh ?? ""
            let nextZh = next?.zh ?? ""
            let previousLast = previousZh.last.map(String.init) ?? ""

            var reading: String?
            switch units[index].zh {
            case "得":
                if nextZh.hasPrefix("了") || nextZh.hasPrefix("到") || next == nil || isParticle(next) {
                    break
                }
                if pronouns.contains(previousZh) {
                    reading = "děi"
                } else if let previous, isPredicate(previous) || previous.pos.isEmpty || previousLast == "儿" {
                    break  // 跑得快, 高兴得跳起来: trợ từ kết cấu
                } else if next.map(isVerb) == true || ["多", "先", "早", "快", "赶紧", "马上", "好好", "一", "再"].contains(where: nextZh.hasPrefix) {
                    reading = "děi"
                }
            case "过":
                if let previous, isVerb(previous), !modalVerbs.contains(previousZh), previousLast != "不" {
                    reading = "guo"
                }
            case "上":
                // 叫上他, 日历上: bổ ngữ / phương vị từ đọc nhẹ.
                if let previous, !modalVerbs.contains(previousZh), !["没", "不", "别"].contains(previousZh),
                   isVerb(previous) || previous.pos.hasPrefix("n") || previous.pos == "t" {
                    reading = "shang"
                }
            case "还":
                if pronouns.contains(nextZh) || ["钱", "书", "给", "回"].contains(where: nextZh.hasPrefix)
                    || next == nil || isParticle(next) {
                    reading = "huán"
                }
            case "只":
                if numberChars.contains(previousLast) || ["几", "这", "那", "哪", "每", "半"].contains(previousLast)
                    || (previousZh == "有" && next?.pos.hasPrefix("n") == true) {
                    reading = "zhī"
                }
            case "长":
                if ["得", "了", "大", "高", "胖", "出", "满", "成"].contains(where: nextZh.hasPrefix) {
                    reading = "zhǎng"
                } else if degreeWords.contains(previousZh) || next == nil || isParticle(next)
                            || ["时间", "期", "度", "久", "远"].contains(where: nextZh.hasPrefix) {
                    reading = "cháng"
                }
            case "干":
                if ["什么", "啥", "活", "吗", "嘛", "完", "得"].contains(where: nextZh.hasPrefix) {
                    reading = "gàn"
                } else if degreeWords.contains(previousZh) || ["晒", "擦", "吹", "晾", "烤", "烘"].contains(previousLast)
                            || next == nil || isParticle(next) {
                    reading = "gān"
                }
            case "量":
                if ["一", "体温", "血压", "身高", "体重", "尺寸", "腰围"].contains(where: nextZh.hasPrefix)
                    || ["给", "帮", "先", "再", "去", "来", "要"].contains(previousZh) {
                    reading = "liáng"
                }
            case "弹":
                reading = "tán"
            case "假":
                if ["个", "请", "放", "休", "病", "事", "年", "婚", "产", "暑", "寒", "长", "天"].contains(previousLast) {
                    reading = "jià"
                }
            case "吐":
                if ["想", "要", "又", "快", "会", "就", "都", "直", "老"].contains(previousZh) || nextZh.hasPrefix("了") {
                    reading = "tù"
                }
            case "宿":
                if numberChars.contains(previousLast) || ["几", "半"].contains(previousLast) {
                    reading = "xiǔ"
                }
            default:
                break
            }
            if let reading {
                units[index].syllables = [reading]
            }
        }
    }

    /// Động từ + 不/得 + bổ ngữ: 不 đọc nhẹ (吃不了 chī bu liǎo, 买不起 mǎi bu qǐ),
    /// 了 → liǎo, 着 → zháo. Cũng áp dụng cho từ ba chữ có 不 ở giữa (受不了, 对不起, 差不多).
    private static func applyPotentialComplements(_ units: inout [Unit]) {
        for index in units.indices where units[index].literal == nil {
            let unit = units[index]
            if unit.zh.count == 3, unit.syllables.count == 3, Array(unit.zh)[1] == "不",
               unit.syllables[1] == "bù", !["要不然", "要不得"].contains(unit.zh) {
                units[index].syllables[1] = "bu"
            }

            guard index > 0, units[index - 1].literal == nil, units[index - 1].trailing.isEmpty else { continue }
            let verb = units[index - 1]

            // 打|不通, 吃|不了: 不 và bổ ngữ đã dính thành một từ.
            if unit.zh.count == 2, unit.zh.hasPrefix("不"), unit.syllables.count == 2,
               let complementChar = unit.zh.last, strongComplements.contains(complementChar),
               isVerb(verb), !modalVerbs.contains(verb.zh), !speechVerbs.contains(verb.zh) {
                units[index].syllables[0] = "bu"
                if complementChar == "了" { units[index].syllables[1] = "liǎo" }
                if complementChar == "着" { units[index].syllables[1] = "zháo" }
                continue
            }

            guard index + 1 < units.count, ["不", "得"].contains(unit.zh),
                  units[index + 1].literal == nil, unit.trailing.isEmpty
            else { continue }
            let complement = units[index + 1]
            guard let first = complement.zh.first, !complement.syllables.isEmpty,
                  isVerb(verb) || verb.pos.hasPrefix("a"),
                  !modalVerbs.contains(verb.zh), !speechVerbs.contains(verb.zh), verb.zh != complement.zh
            else { continue }

            if unit.zh == "不" {
                // Bổ ngữ kiêm động từ chính (去, 来, 好…) chỉ tính khi động từ trước là một chữ,
                // tránh 说不去 hiểu thành "nói không đi".
                guard strongComplements.contains(first)
                        || (weakComplements.contains(first) && verb.zh.count == 1) else { continue }
                units[index].syllables = ["bu"]
            } else if !["了", "着"].contains(String(first)) {
                continue  // 跑得快: 得 kết cấu, giữ nguyên
            }

            switch first {
            case "了": units[index + 1].syllables[0] = "liǎo"
            case "着": units[index + 1].syllables[0] = "zháo"
            default: break
            }
        }
    }

    private static func isVerb(_ unit: Unit) -> Bool {
        unit.pos.hasPrefix("v")
    }

    /// Vị ngữ (động từ, tính từ, thành ngữ…) đứng trước 得 kết cấu.
    private static func isPredicate(_ unit: Unit) -> Bool {
        ["v", "a", "b", "z", "i", "l"].contains(where: unit.pos.hasPrefix)
    }

    private static func isParticle(_ unit: Unit?) -> Bool {
        guard let unit else { return false }
        return ["了", "呢", "吧", "吗", "啊", "呀", "嘛", "的"].contains(unit.zh)
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

            if ["不", "一"].contains(position.zh), ["bù", "yī"].contains(syllable), previous == next.zh {
                // 是不是, 要不要, 看一看: 不/一 đọc nhẹ.
                units[position.unit].syllables[position.char] = position.zh == "不" ? "bu" : "yi"
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

    private static func neutralTone(_ syllable: String) -> String {
        let plain: [Character: Character] = [
            "ā": "a", "á": "a", "ǎ": "a", "à": "a", "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
            "ē": "e", "é": "e", "ě": "e", "è": "e", "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
            "ū": "u", "ú": "u", "ǔ": "u", "ù": "u", "ǖ": "ü", "ǘ": "ü", "ǚ": "ü", "ǜ": "ü",
        ]
        return String(syllable.map { plain[$0] ?? $0 })
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

    /// Trợ động từ / động từ năng nguyện: đứng trước động từ chính chứ không mang bổ ngữ (想上厕所, 要过马路).
    private static let modalVerbs: Set<String> = [
        "想", "要", "会", "能", "可以", "该", "应该", "得", "愿意", "打算", "准备", "敢", "肯", "喜欢", "开始",
        "是", "有", "觉得", "希望", "需要", "必须", "可能",
    ]
    /// Động từ nói / sai khiến: "说不去" là "nói không đi", không phải bổ ngữ khả năng.
    private static let speechVerbs: Set<String> = ["说", "让", "叫", "请", "告诉", "问"]
    private static let degreeWords: Set<String> = [
        "很", "太", "好", "真", "挺", "最", "更", "不", "没", "多", "这么", "那么", "特别", "非常", "比较", "有点", "有点儿",
    ]
    /// Chữ hầu như chỉ làm bổ ngữ khả năng sau "V不".
    private static let strongComplements: Set<Character> = ["了", "起", "动", "完", "到", "见", "着", "住", "懂", "清", "惯", "掉", "通", "倒", "及"]
    /// Chữ vừa làm bổ ngữ vừa làm động từ chính.
    private static let weakComplements: Set<Character> = ["开", "下", "上", "来", "去", "出", "过", "会", "好", "成", "走", "进", "回", "定"]

    private static let erhuaExceptions: Set<String> = ["儿儿", "女儿", "婴儿", "幼儿", "孤儿", "健儿", "男儿", "少儿", "胎儿", "宠儿"]
    private static let numberChars: Set<String> = ["零", "一", "二", "两", "三", "四", "五", "六", "七", "八", "九", "十", "百", "千", "万", "亿"]

    static var dictionaryURL = Bundle.main.url(forResource: "pinyin-dict", withExtension: "json")
    static var hanVietURL = Bundle.main.url(forResource: "hanviet", withExtension: "json")
    static var lexiconURL = Bundle.main.url(forResource: "lexicon", withExtension: "txt")

    private struct LexiconEntry {
        var logFrequency: Float
        var pos: String
        /// Pinyin có dấu của từ nhiều chữ (cách nhau bằng dấu cách); nil với chữ đơn.
        var pinyin: String?
    }

    private struct Lexicon {
        var entries: [String: LexiconEntry] = [:]
        var maxLength = 1
        var unknownLogFrequency: Float = -30
    }

    /// lexicon.txt: dòng đầu "#total<TAB>tổng tần suất", sau đó mỗi dòng "từ<TAB>tần suất<TAB>từ loại<TAB>pinyin".
    /// Đọc thẳng vào một từ điển (không qua bản trung gian) vì bàn phím bị iOS giới hạn bộ nhớ.
    private static let lexicon: Lexicon = {
        var lexicon = Lexicon()
        guard let url = lexiconURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return lexicon }

        var logTotal: Float = 0
        lexicon.entries.reserveCapacity(70_000)
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2, let frequency = Float(fields[1]) else { continue }
            if fields[0] == "#total" {
                logTotal = log(max(frequency, 1))
                continue
            }
            guard fields.count >= 3 else { continue }
            let word = String(fields[0])
            lexicon.entries[word] = LexiconEntry(
                logFrequency: log(max(frequency, 1)) - logTotal,
                pos: String(fields[2]),
                pinyin: fields.count > 3 && !fields[3].isEmpty ? String(fields[3]) : nil
            )
            lexicon.maxLength = max(lexicon.maxLength, word.count)
        }
        // Chữ lạ: hiếm hơn cả từ hiếm nhất, để không chen vào giữa các từ đã biết.
        lexicon.unknownLogFrequency = -logTotal - 1
        return lexicon
    }()

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

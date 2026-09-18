// Kiểm tra hồi quy cho bộ tách từ + pinyin (ChinesePinyin.swift), chạy trên Mac:
//
//     swiftc -O -o /tmp/pinyin_check Tools/pinyin_check/main.swift "Ban Phim Tieng Trung/ChinesePinyin.swift" \
//         && /tmp/pinyin_check "Ban Phim Tieng Trung"
//
// In các câu mẫu kỳ vọng bị sai, rồi số câu trong phrases.json có pinyin khác dữ liệu câu mẫu
// (dữ liệu này do AI tạo, có chỗ lệch, nên chỉ dùng để so trước / sau khi sửa).

import Foundation

struct PinyinWord: Codable, Equatable, Hashable {
    var zh: String
    var py: String
    var hv: String? = nil
    var flagged: Bool? = nil
    var alternatives: [String]? = nil
}

let base = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Ban Phim Tieng Trung"
ChineseText.dictionaryURL = URL(fileURLWithPath: base + "/pinyin-dict.json")
ChineseText.hanVietURL = URL(fileURLWithPath: base + "/hanviet.json")
ChineseText.lexiconURL = URL(fileURLWithPath: base + "/lexicon.txt")

/// Câu → các từ mong đợi dạng "chữ/pinyin" (bỏ dấu câu, pinyin viết thường).
let expectations: [(String, String)] = [
    ("口语得多练。", "口语/kǒuyǔ 得/děi 多/duō 练/liàn"),
    ("懒得理你。", "懒得/lǎnde 理/lǐ 你/nǐ"),
    ("不一定。", "不/bù 一定/yídìng"),
    ("我会说一点儿。", "我/wǒ 会/huì 说/shuō 一点儿/yìdiǎnr"),
    ("我家有只猫。", "我/wǒ 家/jiā 有/yǒu 只/zhī 猫/māo"),
    ("你们这儿有什么招牌菜？", "你们/nǐmen 这儿/zhèr 有/yǒu 什么/shénme 招牌/zhāopai 菜/cài"),
    ("两个人有位子吗？", "两/liǎng 个/ge 人/rén 有/yǒu 位子/wèizi 吗/ma"),
    ("我受不了了！", "我/wǒ 受不了/shòubuliǎo 了/le"),
    ("我睡不着。", "我/wǒ 睡/shuì 不/bu 着/zháo"),
    ("我吃不了辣。", "我/wǒ 吃/chī 不/bu 了/liǎo 辣/là"),
    ("电话打不通。", "电话/diànhuà 打/dǎ 不通/butōng"),
    ("他跑得很快。", "他/tā 跑/pǎo 得/de 很/hěn 快/kuài"),
    ("今天得加班。", "今天/jīntiān 得/děi 加班/jiābān"),
    ("钱我明天还你。", "钱/qián 我/wǒ 明天/míngtiān 还/huán 你/nǐ"),
    ("上次的钱还没还呢。", "上次/shàngcì 的/de 钱/qián 还/hái 没/méi 还/huán 呢/ne"),
    ("大概要多长时间？", "大概/dàgài 要/yào 多/duō 长/cháng 时间/shíjiān"),
    ("北京的冬天特别干。", "北京/běijīng 的/de 冬天/dōngtiān 特别/tèbié 干/gān"),
    ("量一下体温吧。", "量/liáng 一下/yíxià 体温/tǐwēn 吧/ba"),
    ("你会弹吉他吗？", "你/nǐ 会/huì 弹/tán 吉他/jítā 吗/ma"),
    ("我明天请个假。", "我/wǒ 明天/míngtiān 请/qǐng 个/ge 假/jià"),
    ("聚一聚吧。", "聚/jù 一/yi 聚/jù 吧/ba"),
    ("我想上厕所。", "我/wǒ 想/xiǎng 上/shàng 厕所/cèsuǒ"),
    ("叫上他一块儿来。", "叫/jiào 上/shang 他/tā 一块儿/yíkuàir 来/lái"),
    ("我吃过饭了。", "我/wǒ 吃/chī 过/guo 饭/fàn 了/le"),
    ("你尝尝这个。", "你/nǐ 尝尝/chángchang 这个/zhège"),
    ("没收到钱啊。", "没/méi 收到/shōudào 钱/qián 啊/a"),
    ("家里没网了。", "家里/jiāli 没/méi 网/wǎng 了/le"),
    ("你穿着挺好看的。", "你/nǐ 穿着/chuānzhe 挺/tǐng 好看/hǎokàn 的/de"),
    ("3.5公斤OK吗？", "3.5/3.5 公斤/gōngjīn OK/ok 吗/ma"),
]

func strip(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: "，。？！、：；“”（）…～,.?!:;\"()~ "))
}
func render(_ words: [PinyinWord]) -> String {
    words.map { strip($0.zh) + "/" + strip($0.py).lowercased().replacingOccurrences(of: "'", with: "") }
        .filter { $0 != "/" }
        .joined(separator: " ")
}

var failures = 0
for (sentence, expected) in expectations {
    let got = render(ChineseText.words(for: sentence))
    if got != expected {
        failures += 1
        print("✗ \(sentence)\n    mong đợi: \(expected)\n    nhận được: \(got)")
    }
}
print("Câu kỳ vọng: \(expectations.count - failures)/\(expectations.count) đúng")

struct Word: Codable { let zh: String; let py: String }
struct Phrase: Codable { let zh: String; let words: [Word] }
if let data = try? Data(contentsOf: URL(fileURLWithPath: base + "/phrases.json")),
   let phrases = try? JSONDecoder().decode([Phrase].self, from: data) {
    let differing = phrases.filter { phrase in
        let ours = render(ChineseText.words(for: phrase.zh)).split(separator: " ").map { $0.split(separator: "/").last ?? "" }.joined()
        let theirs = phrase.words.map { strip($0.py).lowercased().replacingOccurrences(of: "'", with: "") }.joined()
        return ours != theirs
    }
    print("phrases.json: \(differing.count)/\(phrases.count) câu có pinyin khác dữ liệu mẫu")
}

exit(failures == 0 ? 0 : 1)

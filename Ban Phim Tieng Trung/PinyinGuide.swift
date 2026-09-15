//
//  PinyinGuide.swift
//  Bảng thanh mẫu, 36 vận mẫu, 4 thanh điệu kèm cách đọc so với tiếng Việt,
//  dùng cho tab học phát âm và phần hướng dẫn sửa lỗi.
//

import Foundation

struct SoundGuide: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case initial, final, tone

        var label: String {
            switch self {
            case .initial: "Thanh mẫu"
            case .final: "Vận mẫu"
            case .tone: "Thanh điệu"
            }
        }

        var part: PronunciationPart {
            switch self {
            case .initial: .initial
            case .final: .final
            case .tone: .tone
            }
        }
    }

    struct Example: Hashable {
        let zh: String
        let py: String
        let vi: String
    }

    let kind: Kind
    /// Khoá so với `PinyinSyllable`: "sh", "iou", "3", "" (không có thanh mẫu).
    let key: String
    /// Cách hiển thị: "sh", "iou (iu)", "Thanh 3".
    let symbol: String
    let group: String
    /// Cách đặt lưỡi, môi, hơi — so với âm gần nhất trong tiếng Việt.
    let tip: String
    let examples: [Example]
    /// Không nằm trong bảng học (−i, ê, không có thanh mẫu) nhưng vẫn cần để giải thích lỗi.
    var isExtra = false

    var id: String { "\(kind.rawValue)-\(key)" }
}

enum PinyinGuide {
    private static func ex(_ zh: String, _ py: String, _ vi: String) -> SoundGuide.Example {
        .init(zh: zh, py: py, vi: vi)
    }

    // MARK: - Thanh mẫu

    static let initials: [SoundGuide] = [
        .init(kind: .initial, key: "b", symbol: "b", group: "Âm môi",
              tip: "Hai môi khép rồi mở ra, không bật hơi. Nghe gần \"p\" nhẹ, không phải \"b\" nặng của tiếng Việt. Để tờ giấy trước miệng: giấy gần như không động.",
              examples: [ex("爸", "bà", "bố"), ex("包", "bāo", "bao, túi")]),
        .init(kind: .initial, key: "p", symbol: "p", group: "Âm môi",
              tip: "Giống b nhưng bật mạnh một luồng hơi khi mở môi — tờ giấy trước miệng phải rung. Tiếng Việt không có âm này, đừng đọc thành \"ph\".",
              examples: [ex("怕", "pà", "sợ"), ex("朋", "péng", "bạn")]),
        .init(kind: .initial, key: "m", symbol: "m", group: "Âm môi",
              tip: "Như \"m\" tiếng Việt.",
              examples: [ex("妈", "mā", "mẹ"), ex("猫", "māo", "mèo")]),
        .init(kind: .initial, key: "f", symbol: "f", group: "Âm môi",
              tip: "Như \"ph\" tiếng Việt: răng trên chạm nhẹ môi dưới, hơi đi qua khe.",
              examples: [ex("饭", "fàn", "cơm"), ex("飞", "fēi", "bay")]),
        .init(kind: .initial, key: "d", symbol: "d", group: "Âm đầu lưỡi",
              tip: "Đầu lưỡi chạm chân răng trên, không bật hơi — gần \"t\" tiếng Việt. Không đọc thành \"đ\".",
              examples: [ex("大", "dà", "to"), ex("冬", "dōng", "mùa đông")]),
        .init(kind: .initial, key: "t", symbol: "t", group: "Âm đầu lưỡi",
              tip: "Như d nhưng bật hơi mạnh — gần \"th\" tiếng Việt.",
              examples: [ex("他", "tā", "anh ấy"), ex("天", "tiān", "trời, ngày")]),
        .init(kind: .initial, key: "n", symbol: "n", group: "Âm đầu lưỡi",
              tip: "Như \"n\" tiếng Việt: đầu lưỡi chặn chân răng trên, hơi thoát qua mũi. Bịt mũi lại mà không đọc được là đúng.",
              examples: [ex("你", "nǐ", "bạn"), ex("男", "nán", "nam")]),
        .init(kind: .initial, key: "l", symbol: "l", group: "Âm đầu lưỡi",
              tip: "Như \"l\" tiếng Việt: đầu lưỡi chạm chân răng trên, hơi đi ra hai bên lưỡi, không qua mũi.",
              examples: [ex("来", "lái", "đến"), ex("冷", "lěng", "lạnh")]),
        .init(kind: .initial, key: "g", symbol: "g", group: "Âm cuống lưỡi",
              tip: "Cuống lưỡi chạm ngạc mềm rồi bật ra, không bật hơi — gần \"c/k\" tiếng Việt. Không đọc thành \"g\" rung của tiếng Việt.",
              examples: [ex("哥", "gē", "anh trai"), ex("高", "gāo", "cao")]),
        .init(kind: .initial, key: "k", symbol: "k", group: "Âm cuống lưỡi",
              tip: "Như g nhưng bật hơi mạnh: \"k\" có một luồng hơi phía sau. Không phải \"kh\".",
              examples: [ex("看", "kàn", "xem"), ex("快", "kuài", "nhanh")]),
        .init(kind: .initial, key: "h", symbol: "h", group: "Âm cuống lưỡi",
              tip: "Cuống lưỡi nâng gần ngạc mềm, hơi cọ xát ra — gần \"kh\" tiếng Việt nhưng nhẹ hơn, không phải \"h\" thở ra.",
              examples: [ex("好", "hǎo", "tốt"), ex("喝", "hē", "uống")]),
        .init(kind: .initial, key: "j", symbol: "j", group: "Âm mặt lưỡi",
              tip: "Đầu lưỡi tì răng dưới, mặt lưỡi áp vào ngạc cứng, môi dẹt, không bật hơi — gần \"ch\" tiếng Việt. Chỉ đi với i và ü.",
              examples: [ex("家", "jiā", "nhà"), ex("九", "jiǔ", "chín")]),
        .init(kind: .initial, key: "q", symbol: "q", group: "Âm mặt lưỡi",
              tip: "Vị trí như j nhưng bật hơi mạnh — \"ch\" có thêm luồng hơi. Không đọc thành \"k\" hay \"qu\".",
              examples: [ex("七", "qī", "bảy"), ex("钱", "qián", "tiền")]),
        .init(kind: .initial, key: "x", symbol: "x", group: "Âm mặt lưỡi",
              tip: "Đầu lưỡi tì răng dưới, mặt lưỡi gần ngạc cứng, môi dẹt như đang cười, hơi xát ra — gần \"x\" tiếng Việt nhưng mềm hơn.",
              examples: [ex("小", "xiǎo", "nhỏ"), ex("谢", "xiè", "cảm ơn")]),
        .init(kind: .initial, key: "zh", symbol: "zh", group: "Âm uốn lưỡi",
              tip: "Cong đầu lưỡi lên chạm phần ngạc sau chân răng, không bật hơi — gần \"tr\" uốn lưỡi của tiếng Việt.",
              examples: [ex("这", "zhè", "này"), ex("中", "zhōng", "giữa, Trung")]),
        .init(kind: .initial, key: "ch", symbol: "ch", group: "Âm uốn lưỡi",
              tip: "Vị trí như zh nhưng bật hơi mạnh — \"tr\" uốn lưỡi có thêm luồng hơi.",
              examples: [ex("吃", "chī", "ăn"), ex("茶", "chá", "trà")]),
        .init(kind: .initial, key: "sh", symbol: "sh", group: "Âm uốn lưỡi",
              tip: "Cong đầu lưỡi lên gần ngạc (không chạm), hơi xát qua khe — gần \"s\" uốn lưỡi (sông, sữa). Đừng đọc phẳng thành \"x\".",
              examples: [ex("是", "shì", "là"), ex("书", "shū", "sách")]),
        .init(kind: .initial, key: "r", symbol: "r", group: "Âm uốn lưỡi",
              tip: "Lưỡi cong như sh nhưng dây thanh rung, hơi xát nhẹ — không rung đầu lưỡi, cũng không đọc thành \"d/gi\" hay \"l\".",
              examples: [ex("人", "rén", "người"), ex("热", "rè", "nóng")]),
        .init(kind: .initial, key: "z", symbol: "z", group: "Âm đầu lưỡi trước",
              tip: "Đầu lưỡi thẳng, tì sau răng trên, chặn rồi xát ra, không bật hơi — như \"ts\" nhẹ. Không uốn lưỡi.",
              examples: [ex("在", "zài", "ở"), ex("走", "zǒu", "đi")]),
        .init(kind: .initial, key: "c", symbol: "c", group: "Âm đầu lưỡi trước",
              tip: "Như z nhưng bật hơi mạnh — \"ts\" có luồng hơi. Không đọc thành \"k\".",
              examples: [ex("菜", "cài", "rau, món ăn"), ex("从", "cóng", "từ")]),
        .init(kind: .initial, key: "s", symbol: "s", group: "Âm đầu lưỡi trước",
              tip: "Đầu lưỡi thẳng gần răng trên, hơi xát ra — như \"x\" tiếng Việt. Không uốn lưỡi.",
              examples: [ex("三", "sān", "ba"), ex("四", "sì", "bốn")]),
    ]

    // MARK: - Vận mẫu (36)

    static let finals: [SoundGuide] = [
        .init(kind: .final, key: "a", symbol: "a", group: "Vận mẫu đơn",
              tip: "Mở miệng rộng, như \"a\" tiếng Việt.",
              examples: [ex("八", "bā", "tám"), ex("他", "tā", "anh ấy")]),
        .init(kind: .final, key: "o", symbol: "o", group: "Vận mẫu đơn",
              tip: "Tròn môi như \"ô\", thường nghe như \"uô\" ngắn (bō ≈ \"buô\"). Chỉ đi sau b, p, m, f.",
              examples: [ex("波", "bō", "sóng"), ex("摸", "mō", "sờ")]),
        .init(kind: .final, key: "e", symbol: "e", group: "Vận mẫu đơn",
              tip: "Không tròn môi, miệng hơi mở, lưỡi lùi về sau — gần \"ơ\" chuyển nhẹ sang \"ưa\" (hē ≈ \"khưa\"). Không phải \"e\" tiếng Việt.",
              examples: [ex("喝", "hē", "uống"), ex("饿", "è", "đói")]),
        .init(kind: .final, key: "i", symbol: "i", group: "Vận mẫu đơn",
              tip: "Như \"i\" tiếng Việt, môi dẹt. Riêng sau zh, ch, sh, r, z, c, s thì không đọc \"i\" mà giữ lưỡi ở vị trí phụ âm và kéo thành \"ư\" (shì ≈ \"sư\", sì ≈ \"xư\").",
              examples: [ex("一", "yī", "một"), ex("米", "mǐ", "gạo")]),
        .init(kind: .final, key: "u", symbol: "u", group: "Vận mẫu đơn",
              tip: "Chúm tròn môi, như \"u\" tiếng Việt.",
              examples: [ex("五", "wǔ", "năm"), ex("书", "shū", "sách")]),
        .init(kind: .final, key: "ü", symbol: "ü", group: "Vận mẫu đơn",
              tip: "Đặt lưỡi như đọc \"i\" rồi chúm tròn môi như \"u\", giữ nguyên lưỡi. Tiếng Việt không có âm này. Sau j, q, x, y viết là u nhưng vẫn đọc ü.",
              examples: [ex("鱼", "yú", "cá"), ex("女", "nǚ", "nữ")]),
        .init(kind: .final, key: "ai", symbol: "ai", group: "Vận mẫu kép",
              tip: "Như \"ai\" tiếng Việt.",
              examples: [ex("爱", "ài", "yêu"), ex("来", "lái", "đến")]),
        .init(kind: .final, key: "ei", symbol: "ei", group: "Vận mẫu kép",
              tip: "Như \"ây\" tiếng Việt (gần \"êi\").",
              examples: [ex("北", "běi", "bắc"), ex("给", "gěi", "cho")]),
        .init(kind: .final, key: "ao", symbol: "ao", group: "Vận mẫu kép",
              tip: "Như \"ao\" tiếng Việt.",
              examples: [ex("好", "hǎo", "tốt"), ex("高", "gāo", "cao")]),
        .init(kind: .final, key: "ou", symbol: "ou", group: "Vận mẫu kép",
              tip: "Như \"âu\" tiếng Việt.",
              examples: [ex("走", "zǒu", "đi"), ex("手", "shǒu", "tay")]),
        .init(kind: .final, key: "an", symbol: "an", group: "Vận mẫu mũi",
              tip: "Như \"an\" tiếng Việt, kết thúc bằng đầu lưỡi chạm chân răng trên (-n).",
              examples: [ex("看", "kàn", "xem"), ex("三", "sān", "ba")]),
        .init(kind: .final, key: "en", symbol: "en", group: "Vận mẫu mũi",
              tip: "Như \"ân\" tiếng Việt, kết thúc -n.",
              examples: [ex("人", "rén", "người"), ex("门", "mén", "cửa")]),
        .init(kind: .final, key: "ang", symbol: "ang", group: "Vận mẫu mũi",
              tip: "Như \"ang\" tiếng Việt, kết thúc -ng ở cuống lưỡi, miệng vẫn mở.",
              examples: [ex("忙", "máng", "bận"), ex("汤", "tāng", "canh")]),
        .init(kind: .final, key: "eng", symbol: "eng", group: "Vận mẫu mũi",
              tip: "Như \"âng\" tiếng Việt, kết thúc -ng.",
              examples: [ex("冷", "lěng", "lạnh"), ex("朋", "péng", "bạn")]),
        .init(kind: .final, key: "ong", symbol: "ong", group: "Vận mẫu mũi",
              tip: "Tròn môi, như \"ung\" tiếng Việt (không phải \"ong\").",
              examples: [ex("红", "hóng", "đỏ"), ex("中", "zhōng", "giữa")]),
        .init(kind: .final, key: "er", symbol: "er", group: "Vận mẫu uốn lưỡi",
              tip: "Đọc \"ơ\" rồi cong đầu lưỡi lên ngay — như \"ơ\" có \"r\" ở cuối.",
              examples: [ex("二", "èr", "hai"), ex("儿", "ér", "con")]),
        .init(kind: .final, key: "ia", symbol: "ia", group: "Bắt đầu bằng i",
              tip: "\"i\" lướt nhanh sang \"a\", đọc liền một hơi (jiā ≈ \"chi-a\").",
              examples: [ex("家", "jiā", "nhà"), ex("下", "xià", "dưới")]),
        .init(kind: .final, key: "ie", symbol: "ie", group: "Bắt đầu bằng i",
              tip: "Như \"iê\" tiếng Việt (xiè ≈ \"xiê\").",
              examples: [ex("谢", "xiè", "cảm ơn"), ex("姐", "jiě", "chị")]),
        .init(kind: .final, key: "iao", symbol: "iao", group: "Bắt đầu bằng i",
              tip: "\"i\" lướt sang \"ao\" liền một hơi (xiǎo ≈ \"xi-ảo\").",
              examples: [ex("小", "xiǎo", "nhỏ"), ex("叫", "jiào", "gọi")]),
        .init(kind: .final, key: "iou", symbol: "iou (iu)", group: "Bắt đầu bằng i",
              tip: "Sau phụ âm viết là iu nhưng đọc như \"iêu\" tiếng Việt (liù ≈ \"liêu\").",
              examples: [ex("九", "jiǔ", "chín"), ex("六", "liù", "sáu")]),
        .init(kind: .final, key: "ian", symbol: "ian", group: "Bắt đầu bằng i",
              tip: "Đọc gần \"iên\" tiếng Việt, không phải \"i-an\" (tiān ≈ \"thiên\").",
              examples: [ex("天", "tiān", "trời"), ex("钱", "qián", "tiền")]),
        .init(kind: .final, key: "in", symbol: "in", group: "Bắt đầu bằng i",
              tip: "Như \"in\" tiếng Việt, kết thúc -n.",
              examples: [ex("今", "jīn", "nay"), ex("新", "xīn", "mới")]),
        .init(kind: .final, key: "iang", symbol: "iang", group: "Bắt đầu bằng i",
              tip: "\"i\" lướt sang \"ang\" (xiǎng ≈ \"xi-ảng\"), kết thúc -ng.",
              examples: [ex("想", "xiǎng", "muốn, nghĩ"), ex("两", "liǎng", "hai")]),
        .init(kind: .final, key: "ing", symbol: "ing", group: "Bắt đầu bằng i",
              tip: "Như \"inh\" tiếng Việt, kết thúc -ng.",
              examples: [ex("听", "tīng", "nghe"), ex("星", "xīng", "sao")]),
        .init(kind: .final, key: "iong", symbol: "iong", group: "Bắt đầu bằng i",
              tip: "\"i\" lướt sang \"ung\" tròn môi (xióng ≈ \"xi-úng\").",
              examples: [ex("熊", "xióng", "gấu"), ex("用", "yòng", "dùng")]),
        .init(kind: .final, key: "ua", symbol: "ua", group: "Bắt đầu bằng u",
              tip: "Như \"oa\" tiếng Việt.",
              examples: [ex("花", "huā", "hoa"), ex("瓜", "guā", "dưa")]),
        .init(kind: .final, key: "uo", symbol: "uo", group: "Bắt đầu bằng u",
              tip: "Như \"uô\" tiếng Việt (duō ≈ \"tuô\").",
              examples: [ex("多", "duō", "nhiều"), ex("国", "guó", "nước")]),
        .init(kind: .final, key: "uai", symbol: "uai", group: "Bắt đầu bằng u",
              tip: "Như \"oai\" tiếng Việt.",
              examples: [ex("快", "kuài", "nhanh"), ex("外", "wài", "ngoài")]),
        .init(kind: .final, key: "uei", symbol: "uei (ui)", group: "Bắt đầu bằng u",
              tip: "Sau phụ âm viết là ui nhưng đọc như \"uây\" (duì ≈ \"tuây\").",
              examples: [ex("对", "duì", "đúng"), ex("水", "shuǐ", "nước")]),
        .init(kind: .final, key: "uan", symbol: "uan", group: "Bắt đầu bằng u",
              tip: "Như \"oan\" tiếng Việt.",
              examples: [ex("晚", "wǎn", "muộn, tối"), ex("换", "huàn", "đổi")]),
        .init(kind: .final, key: "uen", symbol: "uen (un)", group: "Bắt đầu bằng u",
              tip: "Sau phụ âm viết là un nhưng đọc như \"uân\" (chūn ≈ \"truân\").",
              examples: [ex("问", "wèn", "hỏi"), ex("春", "chūn", "mùa xuân")]),
        .init(kind: .final, key: "uang", symbol: "uang", group: "Bắt đầu bằng u",
              tip: "Như \"oang\" tiếng Việt.",
              examples: [ex("黄", "huáng", "vàng"), ex("床", "chuáng", "giường")]),
        .init(kind: .final, key: "ueng", symbol: "ueng", group: "Bắt đầu bằng u",
              tip: "Như \"uâng\"; chỉ gặp trong âm tiết weng.",
              examples: [ex("翁", "wēng", "ông lão"), ex("瓮", "wèng", "vò, chum")]),
        .init(kind: .final, key: "üe", symbol: "üe", group: "Bắt đầu bằng ü",
              tip: "Chúm môi đọc ü rồi lướt sang \"ê\" (xué ≈ \"xuê\" môi tròn).",
              examples: [ex("月", "yuè", "trăng, tháng"), ex("学", "xué", "học")]),
        .init(kind: .final, key: "üan", symbol: "üan", group: "Bắt đầu bằng ü",
              tip: "ü lướt sang \"an\", nghe gần \"uyên\" tiếng Việt (yuǎn ≈ \"uyển\").",
              examples: [ex("远", "yuǎn", "xa"), ex("选", "xuǎn", "chọn")]),
        .init(kind: .final, key: "ün", symbol: "ün", group: "Bắt đầu bằng ü",
              tip: "Chúm môi đọc ü rồi kết thúc -n, gần \"uyn\" (jūn ≈ \"chuyn\").",
              examples: [ex("云", "yún", "mây"), ex("军", "jūn", "quân")]),
    ]

    // MARK: - Thanh điệu

    static let tones: [SoundGuide] = [
        .init(kind: .tone, key: "1", symbol: "Thanh 1  ˉ", group: "Cao, bằng (55)",
              tip: "Giữ giọng cao và đều từ đầu tới cuối như ngân một nốt nhạc — cao hơn thanh ngang tiếng Việt. Đừng để giọng tụt ở cuối.",
              examples: [ex("妈", "mā", "mẹ"), ex("八", "bā", "tám"), ex("天", "tiān", "trời")]),
        .init(kind: .tone, key: "2", symbol: "Thanh 2  ˊ", group: "Đi lên (35)",
              tip: "Bắt đầu ở giữa rồi đi thẳng lên cao, như khi hỏi lại \"Hả?\". Gần thanh sắc nhưng lên từ từ, không gắt và không hạ xuống trước.",
              examples: [ex("麻", "má", "tê"), ex("拔", "bá", "nhổ"), ex("来", "lái", "đến")]),
        .init(kind: .tone, key: "3", symbol: "Thanh 3  ˇ", group: "Xuống thấp rồi lên (214)",
              tip: "Hạ giọng xuống thật thấp rồi hơi nâng lên, gần thanh hỏi. Trong câu thường chỉ đọc nửa đầu (xuống thấp và dừng). Hai thanh 3 đứng liền nhau thì chữ trước đọc thành thanh 2: 你好 → ní hǎo.",
              examples: [ex("马", "mǎ", "ngựa"), ex("把", "bǎ", "cầm"), ex("好", "hǎo", "tốt")]),
        .init(kind: .tone, key: "4", symbol: "Thanh 4  ˋ", group: "Rơi mạnh (51)",
              tip: "Bắt đầu cao rồi rơi nhanh, dứt khoát xuống thấp như khi ra lệnh. Gần thanh huyền nhưng bắt đầu cao hơn và mạnh hơn nhiều, không phải thanh nặng.",
              examples: [ex("骂", "mà", "mắng"), ex("爸", "bà", "bố"), ex("去", "qù", "đi")]),
    ]

    static let neutralTone = SoundGuide(
        kind: .tone, key: "5", symbol: "Thanh nhẹ", group: "Ngắn, nhẹ",
        tip: "Không đánh dấu thanh. Đọc ngắn và nhẹ, cao độ theo chữ đứng trước: 吗, 呢, 了, chữ thứ hai của 妈妈.",
        examples: [ex("吗", "ma", "không? (từ hỏi)"), ex("的", "de", "của")], isExtra: true
    )

    /// Không có trong bảng học nhưng lỗi có thể rơi vào.
    static let extras: [SoundGuide] = [
        .init(kind: .initial, key: "", symbol: "∅", group: "Không có thanh mẫu",
              tip: "Âm tiết bắt đầu thẳng bằng nguyên âm (a, e, ai, và các âm viết với y, w như yi, wu, yu). Mở miệng vào luôn nguyên âm, không thêm phụ âm nào phía trước.",
              examples: [ex("爱", "ài", "yêu"), ex("我", "wǒ", "tôi")], isExtra: true),
        .init(kind: .final, key: "-i", symbol: "-i (zhi, ci…)", group: "Vận mẫu đơn",
              tip: "Chữ i sau zh, ch, sh, r, z, c, s không đọc là \"i\". Giữ lưỡi đúng vị trí của phụ âm rồi kéo dài thành \"ư\": zhī ≈ \"trư\", shì ≈ \"sư\" (uốn lưỡi), zì ≈ \"chư\", sì ≈ \"xư\" (lưỡi thẳng).",
              examples: [ex("吃", "chī", "ăn"), ex("四", "sì", "bốn")], isExtra: true),
        .init(kind: .final, key: "ê", symbol: "ê", group: "Vận mẫu đơn",
              tip: "Như \"ê\" tiếng Việt; hầu như chỉ gặp trong ie và üe.",
              examples: [ex("欸", "ê", "này (gọi)")], isExtra: true),
        neutralTone,
    ]

    static func guides(_ kind: SoundGuide.Kind) -> [SoundGuide] {
        switch kind {
        case .initial: initials
        case .final: finals
        case .tone: tones
        }
    }

    static func guide(_ kind: SoundGuide.Kind, key: String) -> SoundGuide? {
        (guides(kind) + extras).first { $0.kind == kind && $0.key == key }
    }

    /// Nhóm theo thứ tự xuất hiện.
    static func groups(_ kind: SoundGuide.Kind) -> [(name: String, guides: [SoundGuide])] {
        var order: [String] = []
        var map: [String: [SoundGuide]] = [:]
        for guide in guides(kind) {
            if map[guide.group] == nil { order.append(guide.group) }
            map[guide.group, default: []].append(guide)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// Khoá của phần `kind` trong một âm tiết.
    static func key(_ kind: SoundGuide.Kind, of syllable: PinyinSyllable) -> String {
        switch kind {
        case .initial: syllable.initial
        case .final: syllable.final
        case .tone: String(syllable.tone)
        }
    }

    /// Đường cao độ trên thang 1–5, để vẽ thanh điệu.
    static func contour(tone: String) -> [Double] {
        switch tone {
        case "1": [5, 5]
        case "2": [3, 5]
        case "3": [2, 1, 1.4, 4]
        case "4": [5, 1]
        default: [3, 3]
        }
    }

    // MARK: - Cặp hay nhầm

    private static func pairKey(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "|")
    }

    private static let pairTips: [String: String] = [
        // Thanh mẫu
        pairKey("b", "p"): "b và p cùng vị trí môi, chỉ khác luồng hơi: b không bật hơi, p bật hơi mạnh. Để tay trước miệng để kiểm tra.",
        pairKey("d", "t"): "d không bật hơi (như \"t\" tiếng Việt), t bật hơi (như \"th\").",
        pairKey("g", "k"): "g không bật hơi, k bật hơi. Cả hai đều chặn ở cuống lưỡi.",
        pairKey("j", "q"): "j không bật hơi, q bật hơi mạnh. Vị trí lưỡi giống nhau.",
        pairKey("zh", "ch"): "zh không bật hơi, ch bật hơi. Cả hai đều cong lưỡi.",
        pairKey("z", "c"): "z không bật hơi, c bật hơi. Cả hai lưỡi thẳng.",
        pairKey("n", "l"): "n cho hơi qua mũi, l cho hơi qua hai bên lưỡi. Bịt mũi: đọc n sẽ bị nghẹt, đọc l thì không.",
        pairKey("zh", "z"): "zh cong đầu lưỡi lên ngạc, z để lưỡi thẳng sau răng trên. Đọc zh thấy lưỡi lùi vào trong.",
        pairKey("ch", "c"): "ch cong lưỡi, c lưỡi thẳng; cả hai đều bật hơi.",
        pairKey("sh", "s"): "sh cong lưỡi (\"s\" trong \"sông\"), s lưỡi thẳng (\"x\" trong \"xa\"). Người Việt hay đọc cả hai thành \"x\".",
        pairKey("zh", "j"): "zh cong đầu lưỡi lên, j áp mặt lưỡi và tì đầu lưỡi xuống răng dưới. j chỉ đi với i, ü.",
        pairKey("ch", "q"): "ch cong đầu lưỡi lên, q tì đầu lưỡi xuống răng dưới; cả hai đều bật hơi.",
        pairKey("sh", "x"): "sh cong đầu lưỡi lên, x tì đầu lưỡi xuống răng dưới và môi dẹt.",
        pairKey("r", "l"): "r cong lưỡi và xát nhẹ, không chạm ngạc; l chạm đầu lưỡi vào chân răng.",
        pairKey("r", ""): "r cần cong lưỡi và xát nhẹ ở đầu âm tiết, đừng bỏ mất hoặc đọc thành \"d/gi\".",
        pairKey("h", "k"): "h xát nhẹ ở cuống lưỡi, không chặn hơi; k chặn hẳn rồi bật ra.",
        pairKey("f", "h"): "f dùng răng trên và môi dưới, h xát ở cuống lưỡi.",
        pairKey("x", "s"): "x tì đầu lưỡi xuống răng dưới, mặt lưỡi nâng lên; s để đầu lưỡi gần răng trên.",
        pairKey("j", "z"): "j dùng mặt lưỡi áp ngạc cứng, z dùng đầu lưỡi sau răng trên.",
        pairKey("q", "c"): "q dùng mặt lưỡi, c dùng đầu lưỡi; cả hai đều bật hơi.",
        // Vận mẫu
        pairKey("an", "ang"): "an kết thúc bằng đầu lưỡi chạm chân răng (-n), ang kết thúc ở cuống lưỡi (-ng) và miệng vẫn mở. Kéo dài âm cuối để nghe rõ.",
        pairKey("en", "eng"): "en như \"ân\" (-n), eng như \"âng\" (-ng).",
        pairKey("in", "ing"): "in như \"in\" (-n), ing như \"inh\" (-ng).",
        pairKey("ian", "iang"): "ian đọc gần \"iên\", iang đọc \"i-ang\" với -ng ở cuối.",
        pairKey("uan", "uang"): "uan như \"oan\" (-n), uang như \"oang\" (-ng).",
        pairKey("eng", "ong"): "eng không tròn môi (\"âng\"), ong tròn môi (\"ung\").",
        pairKey("ü", "u"): "u chỉ chúm môi; ü giữ lưỡi như đọc \"i\" rồi mới chúm môi. Đọc \"i\" rồi từ từ tròn môi lại để ra ü.",
        pairKey("ü", "i"): "i môi dẹt, ü cùng vị trí lưỡi nhưng môi tròn.",
        pairKey("üe", "ie"): "üe chúm môi ngay từ đầu, ie môi dẹt.",
        pairKey("üan", "ian"): "üan tròn môi (gần \"uyên\"), ian môi dẹt (gần \"iên\").",
        pairKey("ün", "in"): "ün tròn môi, in môi dẹt.",
        pairKey("ün", "uen"): "ün đọc từ ü (lưỡi như i, môi tròn), uen (un) đọc \"uân\".",
        pairKey("e", "o"): "e không tròn môi (gần \"ơ\"), o tròn môi (\"ô\").",
        pairKey("e", "a"): "e miệng hơi mở và lưỡi lùi (gần \"ơ\"), a mở rộng miệng.",
        pairKey("ou", "uo"): "ou là \"âu\", uo là \"uô\" — ngược thứ tự nhau.",
        pairKey("ei", "ai"): "ei là \"ây\", ai là \"ai\".",
        pairKey("iou", "ou"): "iou (iu) có \"i\" lướt ở đầu, đọc gần \"iêu\"; ou là \"âu\".",
        pairKey("uei", "ei"): "uei (ui) có \"u\" tròn môi ở đầu, đọc \"uây\".",
        pairKey("-i", "i"): "Sau zh, ch, sh, r, z, c, s thì i đọc là \"ư\"; sau các phụ âm khác mới đọc là \"i\".",
        pairKey("er", "e"): "er phải cong đầu lưỡi lên ở cuối, e thì không.",
        pairKey("ong", "ang"): "ong tròn môi (\"ung\"), ang mở rộng miệng.",
        // Thanh điệu
        pairKey("1", "2"): "Thanh 1 giữ cao và bằng; thanh 2 bắt đầu thấp hơn rồi đi lên. Đọc thanh 1 thì đừng để giọng nhích lên ở cuối.",
        pairKey("1", "4"): "Thanh 1 giữ cao bằng; thanh 4 bắt đầu cao rồi rơi mạnh. Đọc thanh 1 thì giữ hơi đều đến hết chữ.",
        pairKey("2", "3"): "Hay nhầm nhất. Thanh 2 đi thẳng lên; thanh 3 phải xuống thấp trước. Hai thanh 3 liền nhau thì chữ đầu đọc thành thanh 2 là đúng.",
        pairKey("2", "4"): "Thanh 2 đi lên như hỏi lại, thanh 4 rơi xuống như ra lệnh — hai hướng ngược nhau.",
        pairKey("3", "4"): "Thanh 3 bắt đầu thấp và trầm; thanh 4 bắt đầu cao rồi rơi. Đọc thanh 3 thì hạ giọng xuống trước.",
        pairKey("1", "3"): "Thanh 1 cao đều; thanh 3 xuống thấp. Hai thanh ở hai đầu cao độ.",
    ]

    /// Mẹo phân biệt hai âm hay bị đọc lẫn.
    static func pairTip(_ kind: SoundGuide.Kind, _ expected: String, _ heard: String) -> String? {
        pairTips[pairKey(expected, heard)]
    }

    static func label(_ kind: SoundGuide.Kind, key: String) -> String {
        guide(kind, key: key)?.symbol ?? (key.isEmpty ? "∅" : key)
    }
}

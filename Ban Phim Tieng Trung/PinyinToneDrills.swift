//
//  PinyinToneDrills.swift
//  Bộ chữ luyện thanh điệu cho từng thanh mẫu, vận mẫu: cùng một âm tiết đổi thanh (妈 麻 马 骂).
//  Chọn tay chữ thông dụng, tránh chữ nhiều cách đọc; âm nào không đủ chữ quen thì chỉ 2–3 thanh.
//

extension PinyinGuide {
    struct ToneDrillItem: Hashable {
        let tone: Int
        let zh: String
        let py: String
    }

    /// Khoá "initial-b", "final-ang"; "tone" là bộ dùng chung cho các thanh điệu.
    static let toneDrills: [String: [ToneDrillItem]] = [
        "initial-b": [.init(tone: 1, zh: "八", py: "bā"), .init(tone: 2, zh: "拔", py: "bá"), .init(tone: 3, zh: "把", py: "bǎ"), .init(tone: 4, zh: "爸", py: "bà")],
        "initial-p": [.init(tone: 1, zh: "抛", py: "pāo"), .init(tone: 2, zh: "袍", py: "páo"), .init(tone: 3, zh: "跑", py: "pǎo"), .init(tone: 4, zh: "泡", py: "pào")],
        "initial-m": [.init(tone: 1, zh: "妈", py: "mā"), .init(tone: 2, zh: "麻", py: "má"), .init(tone: 3, zh: "马", py: "mǎ"), .init(tone: 4, zh: "骂", py: "mà")],
        "initial-f": [.init(tone: 1, zh: "方", py: "fāng"), .init(tone: 2, zh: "房", py: "fáng"), .init(tone: 3, zh: "访", py: "fǎng"), .init(tone: 4, zh: "放", py: "fàng")],
        "initial-d": [.init(tone: 1, zh: "搭", py: "dā"), .init(tone: 2, zh: "答", py: "dá"), .init(tone: 3, zh: "打", py: "dǎ"), .init(tone: 4, zh: "大", py: "dà")],
        "initial-t": [.init(tone: 1, zh: "踢", py: "tī"), .init(tone: 2, zh: "提", py: "tí"), .init(tone: 3, zh: "体", py: "tǐ"), .init(tone: 4, zh: "替", py: "tì")],
        "initial-n": [.init(tone: 1, zh: "妮", py: "nī"), .init(tone: 2, zh: "泥", py: "ní"), .init(tone: 3, zh: "你", py: "nǐ"), .init(tone: 4, zh: "腻", py: "nì")],
        "initial-l": [.init(tone: 1, zh: "溜", py: "liū"), .init(tone: 2, zh: "流", py: "liú"), .init(tone: 3, zh: "柳", py: "liǔ"), .init(tone: 4, zh: "六", py: "liù")],
        "initial-g": [.init(tone: 1, zh: "锅", py: "guō"), .init(tone: 2, zh: "国", py: "guó"), .init(tone: 3, zh: "果", py: "guǒ"), .init(tone: 4, zh: "过", py: "guò")],
        "initial-k": [.init(tone: 1, zh: "科", py: "kē"), .init(tone: 3, zh: "可", py: "kě"), .init(tone: 4, zh: "课", py: "kè")],
        "initial-h": [.init(tone: 1, zh: "挥", py: "huī"), .init(tone: 2, zh: "回", py: "huí"), .init(tone: 3, zh: "毁", py: "huǐ"), .init(tone: 4, zh: "会", py: "huì")],
        "initial-j": [.init(tone: 1, zh: "鸡", py: "jī"), .init(tone: 2, zh: "急", py: "jí"), .init(tone: 3, zh: "挤", py: "jǐ"), .init(tone: 4, zh: "记", py: "jì")],
        "initial-q": [.init(tone: 1, zh: "七", py: "qī"), .init(tone: 2, zh: "骑", py: "qí"), .init(tone: 3, zh: "起", py: "qǐ"), .init(tone: 4, zh: "气", py: "qì")],
        "initial-x": [.init(tone: 1, zh: "西", py: "xī"), .init(tone: 2, zh: "习", py: "xí"), .init(tone: 3, zh: "洗", py: "xǐ"), .init(tone: 4, zh: "细", py: "xì")],
        "initial-zh": [.init(tone: 1, zh: "知", py: "zhī"), .init(tone: 2, zh: "直", py: "zhí"), .init(tone: 3, zh: "纸", py: "zhǐ"), .init(tone: 4, zh: "至", py: "zhì")],
        "initial-ch": [.init(tone: 1, zh: "吃", py: "chī"), .init(tone: 2, zh: "迟", py: "chí"), .init(tone: 3, zh: "尺", py: "chǐ"), .init(tone: 4, zh: "翅", py: "chì")],
        "initial-sh": [.init(tone: 1, zh: "诗", py: "shī"), .init(tone: 2, zh: "十", py: "shí"), .init(tone: 3, zh: "使", py: "shǐ"), .init(tone: 4, zh: "是", py: "shì")],
        "initial-r": [.init(tone: 2, zh: "人", py: "rén"), .init(tone: 3, zh: "忍", py: "rěn"), .init(tone: 4, zh: "认", py: "rèn")],
        "initial-z": [.init(tone: 1, zh: "资", py: "zī"), .init(tone: 3, zh: "子", py: "zǐ"), .init(tone: 4, zh: "字", py: "zì")],
        "initial-c": [.init(tone: 1, zh: "猜", py: "cāi"), .init(tone: 2, zh: "才", py: "cái"), .init(tone: 3, zh: "彩", py: "cǎi"), .init(tone: 4, zh: "菜", py: "cài")],
        "initial-s": [.init(tone: 1, zh: "丝", py: "sī"), .init(tone: 3, zh: "死", py: "sǐ"), .init(tone: 4, zh: "四", py: "sì")],
        "final-a": [.init(tone: 1, zh: "妈", py: "mā"), .init(tone: 2, zh: "麻", py: "má"), .init(tone: 3, zh: "马", py: "mǎ"), .init(tone: 4, zh: "骂", py: "mà")],
        "final-o": [.init(tone: 1, zh: "坡", py: "pō"), .init(tone: 2, zh: "婆", py: "pó"), .init(tone: 4, zh: "破", py: "pò")],
        "final-e": [.init(tone: 1, zh: "喝", py: "hē"), .init(tone: 2, zh: "河", py: "hé"), .init(tone: 4, zh: "贺", py: "hè")],
        "final-i": [.init(tone: 1, zh: "衣", py: "yī"), .init(tone: 2, zh: "姨", py: "yí"), .init(tone: 3, zh: "椅", py: "yǐ"), .init(tone: 4, zh: "意", py: "yì")],
        "final-u": [.init(tone: 1, zh: "屋", py: "wū"), .init(tone: 2, zh: "无", py: "wú"), .init(tone: 3, zh: "五", py: "wǔ"), .init(tone: 4, zh: "物", py: "wù")],
        "final-ü": [.init(tone: 1, zh: "居", py: "jū"), .init(tone: 2, zh: "局", py: "jú"), .init(tone: 3, zh: "举", py: "jǔ"), .init(tone: 4, zh: "句", py: "jù")],
        "final-ai": [.init(tone: 1, zh: "猜", py: "cāi"), .init(tone: 2, zh: "才", py: "cái"), .init(tone: 3, zh: "彩", py: "cǎi"), .init(tone: 4, zh: "菜", py: "cài")],
        "final-ei": [.init(tone: 1, zh: "飞", py: "fēi"), .init(tone: 2, zh: "肥", py: "féi"), .init(tone: 3, zh: "匪", py: "fěi"), .init(tone: 4, zh: "费", py: "fèi")],
        "final-ao": [.init(tone: 1, zh: "抛", py: "pāo"), .init(tone: 2, zh: "袍", py: "páo"), .init(tone: 3, zh: "跑", py: "pǎo"), .init(tone: 4, zh: "泡", py: "pào")],
        "final-ou": [.init(tone: 1, zh: "抽", py: "chōu"), .init(tone: 2, zh: "愁", py: "chóu"), .init(tone: 3, zh: "丑", py: "chǒu"), .init(tone: 4, zh: "臭", py: "chòu")],
        "final-an": [.init(tone: 1, zh: "帆", py: "fān"), .init(tone: 2, zh: "烦", py: "fán"), .init(tone: 3, zh: "反", py: "fǎn"), .init(tone: 4, zh: "饭", py: "fàn")],
        "final-en": [.init(tone: 1, zh: "分", py: "fēn"), .init(tone: 2, zh: "坟", py: "fén"), .init(tone: 3, zh: "粉", py: "fěn"), .init(tone: 4, zh: "份", py: "fèn")],
        "final-ang": [.init(tone: 1, zh: "汤", py: "tāng"), .init(tone: 2, zh: "糖", py: "táng"), .init(tone: 3, zh: "躺", py: "tǎng"), .init(tone: 4, zh: "烫", py: "tàng")],
        "final-eng": [.init(tone: 1, zh: "烹", py: "pēng"), .init(tone: 2, zh: "朋", py: "péng"), .init(tone: 3, zh: "捧", py: "pěng"), .init(tone: 4, zh: "碰", py: "pèng")],
        "final-ong": [.init(tone: 1, zh: "通", py: "tōng"), .init(tone: 2, zh: "同", py: "tóng"), .init(tone: 3, zh: "桶", py: "tǒng"), .init(tone: 4, zh: "痛", py: "tòng")],
        "final-er": [.init(tone: 2, zh: "儿", py: "ér"), .init(tone: 3, zh: "耳", py: "ěr"), .init(tone: 4, zh: "二", py: "èr")],
        "final-ia": [.init(tone: 1, zh: "鸭", py: "yā"), .init(tone: 2, zh: "牙", py: "yá"), .init(tone: 3, zh: "雅", py: "yǎ"), .init(tone: 4, zh: "亚", py: "yà")],
        "final-ie": [.init(tone: 1, zh: "接", py: "jiē"), .init(tone: 2, zh: "节", py: "jié"), .init(tone: 3, zh: "姐", py: "jiě"), .init(tone: 4, zh: "借", py: "jiè")],
        "final-iao": [.init(tone: 1, zh: "腰", py: "yāo"), .init(tone: 2, zh: "摇", py: "yáo"), .init(tone: 3, zh: "咬", py: "yǎo"), .init(tone: 4, zh: "要", py: "yào")],
        "final-iou": [.init(tone: 1, zh: "优", py: "yōu"), .init(tone: 2, zh: "油", py: "yóu"), .init(tone: 3, zh: "有", py: "yǒu"), .init(tone: 4, zh: "右", py: "yòu")],
        "final-ian": [.init(tone: 1, zh: "烟", py: "yān"), .init(tone: 2, zh: "盐", py: "yán"), .init(tone: 3, zh: "眼", py: "yǎn"), .init(tone: 4, zh: "验", py: "yàn")],
        "final-in": [.init(tone: 1, zh: "音", py: "yīn"), .init(tone: 2, zh: "银", py: "yín"), .init(tone: 3, zh: "引", py: "yǐn"), .init(tone: 4, zh: "印", py: "yìn")],
        "final-iang": [.init(tone: 1, zh: "香", py: "xiāng"), .init(tone: 2, zh: "详", py: "xiáng"), .init(tone: 3, zh: "想", py: "xiǎng"), .init(tone: 4, zh: "向", py: "xiàng")],
        "final-ing": [.init(tone: 1, zh: "英", py: "yīng"), .init(tone: 2, zh: "迎", py: "yíng"), .init(tone: 3, zh: "影", py: "yǐng"), .init(tone: 4, zh: "硬", py: "yìng")],
        "final-iong": [.init(tone: 1, zh: "拥", py: "yōng"), .init(tone: 3, zh: "永", py: "yǒng"), .init(tone: 4, zh: "用", py: "yòng")],
        "final-ua": [.init(tone: 1, zh: "挖", py: "wā"), .init(tone: 2, zh: "娃", py: "wá"), .init(tone: 3, zh: "瓦", py: "wǎ"), .init(tone: 4, zh: "袜", py: "wà")],
        "final-uo": [.init(tone: 1, zh: "多", py: "duō"), .init(tone: 2, zh: "夺", py: "duó"), .init(tone: 3, zh: "朵", py: "duǒ"), .init(tone: 4, zh: "剁", py: "duò")],
        "final-uai": [.init(tone: 1, zh: "乖", py: "guāi"), .init(tone: 3, zh: "拐", py: "guǎi"), .init(tone: 4, zh: "怪", py: "guài")],
        "final-uei": [.init(tone: 1, zh: "威", py: "wēi"), .init(tone: 2, zh: "围", py: "wéi"), .init(tone: 3, zh: "伟", py: "wěi"), .init(tone: 4, zh: "位", py: "wèi")],
        "final-uan": [.init(tone: 1, zh: "弯", py: "wān"), .init(tone: 2, zh: "完", py: "wán"), .init(tone: 3, zh: "晚", py: "wǎn"), .init(tone: 4, zh: "万", py: "wàn")],
        "final-uen": [.init(tone: 1, zh: "温", py: "wēn"), .init(tone: 2, zh: "文", py: "wén"), .init(tone: 3, zh: "稳", py: "wěn"), .init(tone: 4, zh: "问", py: "wèn")],
        "final-uang": [.init(tone: 1, zh: "汪", py: "wāng"), .init(tone: 2, zh: "王", py: "wáng"), .init(tone: 3, zh: "往", py: "wǎng"), .init(tone: 4, zh: "忘", py: "wàng")],
        "final-ueng": [.init(tone: 1, zh: "翁", py: "wēng"), .init(tone: 4, zh: "瓮", py: "wèng")],
        "final-üe": [.init(tone: 1, zh: "靴", py: "xuē"), .init(tone: 2, zh: "学", py: "xué"), .init(tone: 3, zh: "雪", py: "xuě")],
        "final-üan": [.init(tone: 1, zh: "冤", py: "yuān"), .init(tone: 2, zh: "元", py: "yuán"), .init(tone: 3, zh: "远", py: "yuǎn"), .init(tone: 4, zh: "愿", py: "yuàn")],
        "final-ün": [.init(tone: 2, zh: "云", py: "yún"), .init(tone: 3, zh: "允", py: "yǔn"), .init(tone: 4, zh: "运", py: "yùn")],
        "tone": [.init(tone: 1, zh: "妈", py: "mā"), .init(tone: 2, zh: "麻", py: "má"), .init(tone: 3, zh: "马", py: "mǎ"), .init(tone: 4, zh: "骂", py: "mà")],
    ]

    static func toneDrill(for guide: SoundGuide) -> [ToneDrillItem] {
        guide.kind == .tone ? toneDrills["tone"] ?? [] : toneDrills["\(guide.kind.rawValue)-\(guide.key)"] ?? []
    }
}

//
//  SocialAPI.swift
//  Bạn bè (theo dõi nhau, bảng xếp hạng tuần) và phòng chat công khai — gọi api/social.php của website.
//

import Foundation
import UIKit

/// Một ngày trên lịch 5 tuần của tường.
struct WallDay: Codable, Hashable {
    let day: String
    var sentences: Int = 0

    enum CodingKeys: String, CodingKey { case day, sentences }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        sentences = try c.decodeIfPresent(Int.self, forKey: .sentences) ?? 0
    }
}

/// Thành tích kiểu Duolingo.
struct WallBadge: Codable, Hashable, Identifiable {
    let key: String
    let emoji: String
    let title: String
    let detail: String
    var progress: Int = 0
    var target: Int = 1
    var done: Bool = false

    var id: String { key }

    enum CodingKeys: String, CodingKey { case key, emoji, title, detail, progress, target, done }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? title
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🏅"
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        target = max(1, try c.decodeIfPresent(Int.self, forKey: .target) ?? 1)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? (progress >= target)
    }
}

/// Tình huống hội thoại gần đây trên tường.
struct WallTopic: Codable, Hashable {
    /// Id hội thoại trên website (để mở lại bài từ tường của mình).
    var id: Int?
    let title: String
    let emoji: String
    var userTurns: Int = 0
    var target: Int = 50
    var updatedAt: String?

    enum CodingKeys: String, CodingKey { case id, title, emoji, userTurns, target, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "💬"
        userTurns = try c.decodeIfPresent(Int.self, forKey: .userTurns) ?? 0
        target = max(1, try c.decodeIfPresent(Int.self, forKey: .target) ?? 50)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

/// Phòng chat do người đó tạo (dạng rút gọn trên tường).
struct WallRoom: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let emoji: String

    enum CodingKeys: String, CodingKey { case id, name, emoji }

    init(id: Int, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Phòng #\(id)"
        let icon = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        emoji = icon.isEmpty ? "💬" : icon
    }
}

/// Hồ sơ công khai của một người học (không bao giờ có email).
struct SocialUser: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var username: String?
    var avatar: String?
    /// Giới thiệu ngắn (≤160 ký tự), có thể rỗng.
    var bio: String?
    var weekSentences: Int = 0
    var todaySentences: Int = 0
    var totalSentences: Int = 0
    var streak: Int = 0
    var isMe: Bool = false
    var following: Bool = false
    var followsMe: Bool = false
    /// Đang mở web/app trong 2 phút qua.
    var online: Bool = false
    var lastSeenAt: String?
    /// Chỉ có khi xem hồ sơ (action=profile).
    var followersCount: Int?
    var followingCount: Int?
    var joinedAt: String?
    // Tường (chỉ có khi xem hồ sơ)
    var bestStreak: Int?
    var activeDays: Int?
    var accuracy: Double?
    var avgCpm: Int?
    var topicsCount: Int?
    var topicsCompleted: Int?
    var calendar: [WallDay] = []
    var badges: [WallBadge] = []
    var recentTopics: [WallTopic] = []
    var rooms: [WallRoom] = []
    /// Huân chương tuần đã nhận (mọi user) và lịch sử trao (chỉ hồ sơ).
    var medals: Medals?
    var awards: [WeeklyAward] = []

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var handle: String? { username.map { "@\($0)" } }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey {
        case id, name, username, avatar, bio, weekSentences, todaySentences, totalSentences, streak
        case isMe, following, followsMe, online, lastSeenAt, followersCount, followingCount, joinedAt
        case bestStreak, activeDays, accuracy, avgCpm, topicsCount, topicsCompleted
        case calendar, badges, recentTopics, rooms, medals, awards
    }

    /// Chép tên, username, ảnh đại diện, giới thiệu từ hồ sơ máy chủ vừa trả về (sửa hồ sơ).
    mutating func applyProfile(from other: SocialUser) {
        name = other.name
        username = other.username
        avatar = other.avatar
        if let bio = other.bio { self.bio = bio }
    }

    /// Hồ sơ tạm từ thông tin rút gọn (tác giả tin nhắn, thành viên phòng); tường tải thêm từ máy chủ.
    init(id: Int, name: String, username: String?, avatar: String?, online: Bool = false) {
        self.id = id
        self.name = name
        self.username = username
        self.avatar = avatar
        self.online = online
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Người học #\(id)"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        bio = try? c.decodeIfPresent(String.self, forKey: .bio)
        weekSentences = try c.decodeIfPresent(Int.self, forKey: .weekSentences) ?? 0
        todaySentences = try c.decodeIfPresent(Int.self, forKey: .todaySentences) ?? 0
        totalSentences = try c.decodeIfPresent(Int.self, forKey: .totalSentences) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        isMe = try c.decodeIfPresent(Bool.self, forKey: .isMe) ?? false
        following = try c.decodeIfPresent(Bool.self, forKey: .following) ?? false
        followsMe = try c.decodeIfPresent(Bool.self, forKey: .followsMe) ?? false
        online = (try? c.decodeIfPresent(Bool.self, forKey: .online)) ?? false
        lastSeenAt = try? c.decodeIfPresent(String.self, forKey: .lastSeenAt)
        followersCount = try c.decodeIfPresent(Int.self, forKey: .followersCount)
        followingCount = try c.decodeIfPresent(Int.self, forKey: .followingCount)
        joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAt)
        bestStreak = try? c.decodeIfPresent(Int.self, forKey: .bestStreak)
        activeDays = try? c.decodeIfPresent(Int.self, forKey: .activeDays)
        accuracy = try? c.decodeIfPresent(Double.self, forKey: .accuracy)
        avgCpm = try? c.decodeIfPresent(Int.self, forKey: .avgCpm)
        topicsCount = try? c.decodeIfPresent(Int.self, forKey: .topicsCount)
        topicsCompleted = try? c.decodeIfPresent(Int.self, forKey: .topicsCompleted)
        calendar = (try? c.decodeIfPresent([WallDay].self, forKey: .calendar)) ?? []
        badges = (try? c.decodeIfPresent([WallBadge].self, forKey: .badges)) ?? []
        recentTopics = (try? c.decodeIfPresent([WallTopic].self, forKey: .recentTopics)) ?? []
        rooms = (try? c.decodeIfPresent([WallRoom].self, forKey: .rooms)) ?? []
        medals = try? c.decodeIfPresent(Medals.self, forKey: .medals)
        awards = (try? c.decodeIfPresent([WeeklyAward].self, forKey: .awards)) ?? []
    }
}

/// Dữ liệu trang Bạn bè.
struct FriendsPayload: Codable {
    var me: SocialUser?
    var following: [SocialUser]
    var followers: [SocialUser]
    var suggestions: [SocialUser]
    var leaderboard: [SocialUser]

    static let empty = FriendsPayload(me: nil, following: [], followers: [], suggestions: [], leaderboard: [])
}

struct ChatRoom: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var description: String
    var emoji: String
    let ownerId: Int
    var ownerName: String
    var memberCount: Int
    var messageCount: Int
    var lastMessage: String?
    var lastMessageAt: String?
    var joined: Bool
    var isOwner: Bool
    var createdAt: String
    /// Số người đang mở phòng (hỏi tin trong 20 giây qua). Máy chủ cũ không có thì 0.
    var onlineCount: Int = 0
    /// Chủ phòng (máy chủ cũ không có thì dựng từ ownerId/ownerName).
    var owner: RoomMessage.User?
    /// Thành viên: chủ phòng đầu tiên, rồi người đang online (≤5 ở danh sách, ≤50 trong phòng).
    var members: [RoomMember] = []

    enum CodingKeys: String, CodingKey {
        case id, name, description, emoji, ownerId, ownerName, memberCount, messageCount
        case lastMessage, lastMessageAt, joined, isOwner, createdAt, onlineCount, owner, members
    }

    /// Phòng tạm khi mở từ tường (chỉ biết id, tên, biểu tượng); dữ liệu đầy đủ tải khi vào phòng.
    init(placeholder: WallRoom, ownerId: Int = 0, ownerName: String = "") {
        id = placeholder.id
        name = placeholder.name
        description = ""
        emoji = placeholder.emoji
        self.ownerId = ownerId
        self.ownerName = ownerName
        memberCount = 0
        messageCount = 0
        joined = false
        isOwner = false
        createdAt = ""
    }

    /// Thành viên sắp xếp: chủ phòng đầu tiên, rồi người đang online.
    var sortedMembers: [RoomMember] {
        members.enumerated().sorted { a, b in
            if a.element.isOwner != b.element.isOwner { return a.element.isOwner }
            if a.element.online != b.element.online { return a.element.online }
            return a.offset < b.offset
        }.map(\.element)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "💬"
        ownerId = try c.decode(Int.self, forKey: .ownerId)
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName) ?? ""
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageAt = try c.decodeIfPresent(String.self, forKey: .lastMessageAt)
        joined = try c.decodeIfPresent(Bool.self, forKey: .joined) ?? false
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        onlineCount = try c.decodeIfPresent(Int.self, forKey: .onlineCount) ?? 0
        owner = try? c.decodeIfPresent(RoomMessage.User.self, forKey: .owner)
        members = (try? c.decodeIfPresent([RoomMember].self, forKey: .members)) ?? []
    }
}

/// Thành viên phòng chat.
struct RoomMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let username: String?
    let avatar: String?
    var isOwner: Bool = false
    /// Đang trong phòng (hỏi tin trong 20 giây qua).
    var online: Bool = false

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var socialUser: SocialUser { SocialUser(id: id, name: name, username: username, avatar: avatar, online: online) }

    var medals: Medals?

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, isOwner, online, medals }

    init(id: Int, name: String, username: String?, avatar: String?, isOwner: Bool = false, online: Bool = false) {
        self.id = id
        self.name = name
        self.username = username
        self.avatar = avatar
        self.isOwner = isOwner
        self.online = online
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Người học #\(id)"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        isOwner = (try? c.decodeIfPresent(Bool.self, forKey: .isOwner)) ?? false
        online = (try? c.decodeIfPresent(Bool.self, forKey: .online)) ?? false
        medals = try? c.decodeIfPresent(Medals.self, forKey: .medals)
    }
}

struct RoomMessage: Codable, Identifiable, Hashable {
    struct User: Codable, Hashable {
        let id: Int
        let name: String
        let username: String?
        let avatar: String?
        var medals: Medals? = nil

        var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
        var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
        func socialUser(online: Bool = false) -> SocialUser {
            SocialUser(id: id, name: name, username: username, avatar: avatar, online: online)
        }
    }

    let id: Int
    let text: String
    let createdAt: String
    let mine: Bool
    let user: User
    /// Ảnh đính kèm (tin có ảnh thì `text` có thể rỗng).
    var image: SocialImage?
    /// Tin này trả lời tin nào (trích dẫn ngắn).
    var replyTo: ReplyRef?
    /// Tin tặng quà (chữ rỗng).
    var gift: RoomGift?
    /// Tin hệ thống: ai đó vào / rời phòng.
    var system: SystemInfo?

    struct SystemInfo: Codable, Hashable {
        /// "join" | "leave"
        var type: String = ""
        var text: String = ""

        var isJoin: Bool { type == "join" }

        enum CodingKeys: String, CodingKey { case type, text }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        }
    }

    /// Trích dẫn tin được trả lời.
    struct ReplyRef: Codable, Hashable {
        let id: Int
        var userId: Int = 0
        var name: String = ""
        var text: String = ""
        var hasImage = false
        var deleted = false

        enum CodingKeys: String, CodingKey { case id, userId, name, text, hasImage, deleted }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            userId = (try? c.decodeIfPresent(Int.self, forKey: .userId)) ?? 0
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
            hasImage = (try? c.decodeIfPresent(Bool.self, forKey: .hasImage)) ?? false
            deleted = (try? c.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false
        }
    }

    enum CodingKeys: String, CodingKey { case id, text, createdAt, mine, user, image, replyTo, gift, system }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        user = try c.decode(User.self, forKey: .user)
        image = try? c.decodeIfPresent(SocialImage.self, forKey: .image)
        replyTo = try? c.decodeIfPresent(ReplyRef.self, forKey: .replyTo)
        gift = try? c.decodeIfPresent(RoomGift.self, forKey: .gift)
        system = try? c.decodeIfPresent(SystemInfo.self, forKey: .system)
    }
}

// MARK: - Huân chương tuần

/// Số huân chương đã nhận.
struct Medals: Codable, Hashable {
    var gold = 0
    var silver = 0
    var bronze = 0

    var total: Int { gold + silver + bronze }

    enum CodingKeys: String, CodingKey { case gold, silver, bronze }

    init(gold: Int = 0, silver: Int = 0, bronze: Int = 0) {
        self.gold = gold
        self.silver = silver
        self.bronze = bronze
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gold = (try? c.decodeIfPresent(Int.self, forKey: .gold)) ?? 0
        silver = (try? c.decodeIfPresent(Int.self, forKey: .silver)) ?? 0
        bronze = (try? c.decodeIfPresent(Int.self, forKey: .bronze)) ?? 0
    }
}

/// Một lần được trao huân chương (trên tường).
struct WeeklyAward: Codable, Hashable {
    let weekStart: String
    var weekEnd: String = ""
    var rank: Int = 3
    var medal: String = "🏅"
    var sentences: Int = 0

    enum CodingKeys: String, CodingKey { case weekStart, weekEnd, rank, medal, sentences }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try c.decode(String.self, forKey: .weekStart)
        weekEnd = (try? c.decodeIfPresent(String.self, forKey: .weekEnd)) ?? ""
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 3
        medal = (try? c.decodeIfPresent(String.self, forKey: .medal)) ?? ["🥇", "🥈", "🥉"][max(0, min(2, rank - 1))]
        sentences = (try? c.decodeIfPresent(Int.self, forKey: .sentences)) ?? 0
    }
}

/// Người đạt top 3 của một tuần.
struct AwardWinner: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let username: String?
    let avatar: String?
    var rank: Int = 3
    var medal: String = "🏅"
    var sentences: Int = 0
    var isMe = false
    var medals: Medals?

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var socialUser: SocialUser { SocialUser(id: id, name: name, username: username, avatar: avatar) }

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, rank, medal, sentences, isMe, medals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Người học #\(id)"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 3
        medal = (try? c.decodeIfPresent(String.self, forKey: .medal)) ?? ["🥇", "🥈", "🥉"][max(0, min(2, rank - 1))]
        sentences = (try? c.decodeIfPresent(Int.self, forKey: .sentences)) ?? 0
        isMe = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
        medals = try? c.decodeIfPresent(Medals.self, forKey: .medals)
    }
}

struct AwardWeek: Codable, Hashable, Identifiable {
    let weekStart: String
    var weekEnd: String = ""
    var winners: [AwardWinner] = []

    var id: String { weekStart }

    enum CodingKeys: String, CodingKey { case weekStart, weekEnd, winners }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try c.decode(String.self, forKey: .weekStart)
        weekEnd = (try? c.decodeIfPresent(String.self, forKey: .weekEnd)) ?? ""
        winners = ((try? c.decodeIfPresent([AwardWinner].self, forKey: .winners)) ?? []).sorted { $0.rank < $1.rank }
    }
}

// MARK: - Quà tặng (miễn phí)

enum GiftTier: String, Codable, Hashable {
    case small, medium, big, epic

    init(raw: String?) {
        self = GiftTier(rawValue: raw ?? "") ?? .small
    }
}

/// Một món trong danh mục quà.
struct GiftItem: Codable, Hashable, Identifiable {
    let key: String
    let emoji: String
    let name: String
    var tier: GiftTier = .small

    var id: String { key }

    enum CodingKeys: String, CodingKey { case key, emoji, name, tier }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🎁"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? key
        tier = GiftTier(raw: try? c.decodeIfPresent(String.self, forKey: .tier))
    }
}

/// Quà gắn trên tin nhắn.
struct RoomGift: Codable, Hashable {
    let key: String
    let emoji: String
    let name: String
    var tier: GiftTier = .small
    var count: Int = 1
    /// Người nhận; nil = cả phòng.
    var to: RoomMessage.User?

    enum CodingKeys: String, CodingKey { case key, emoji, name, tier, count, to }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🎁"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Quà"
        tier = GiftTier(raw: try? c.decodeIfPresent(String.self, forKey: .tier))
        count = max(1, (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 1)
        to = try? c.decodeIfPresent(RoomMessage.User.self, forKey: .to)
    }
}

/// Một dòng bảng xếp hạng quà trong phòng.
struct GiftTopUser: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let username: String?
    let avatar: String?
    var total: Int = 0

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var socialUser: SocialUser { SocialUser(id: id, name: name, username: username, avatar: avatar) }

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Người học #\(id)"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
    }
}

/// Ảnh trên máy chủ (đã thu về JPEG ≤ 1600px) kèm kích thước để giữ đúng tỉ lệ khi đang tải.
struct SocialImage: Codable, Hashable, Identifiable {
    let url: String
    var width: Int = 0
    var height: Int = 0

    var id: String { url }
    var imageURL: URL? { URL(string: url) }
    /// Rộng / cao; thiếu kích thước thì coi như ảnh vuông.
    var aspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    enum CodingKeys: String, CodingKey { case url, width, height }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        width = (try? c.decodeIfPresent(Int.self, forKey: .width)) ?? 0
        height = (try? c.decodeIfPresent(Int.self, forKey: .height)) ?? 0
    }
}

/// Một trang tin nhắn của phòng (mới hơn `after` hoặc cũ hơn `before`).
struct RoomPage {
    let room: ChatRoom
    let messages: [RoomMessage]
    let deletedIds: [Int]
    let hasMore: Bool
    /// Những người đang trong phòng (người xem đứng đầu). nil nếu máy chủ chưa hỗ trợ.
    let online: [RoomMessage.User]?
    /// Người khác đang gõ (trong 5 giây qua). nil nếu máy chủ chưa hỗ trợ.
    var typing: [RoomMessage.User]? = nil
}

/// Số người đang trong phòng chat: tổng (không trùng) và theo từng phòng.
struct RoomsOnline {
    let total: Int
    let rooms: [Int: Int]
}

/// Một dòng trong "Top luyện nói tuần này" (action=week_top) — giống thẻ ở cột phải trang Hội thoại trên web.
struct WeekTopEntry: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let username: String?
    let avatar: String?
    var rank = 0
    var medal: String?
    var sentences = 0
    /// Câu nói chuẩn (AI không phải sửa).
    var clean = 0
    var isMe = false

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, rank, medal, sentences, clean, isMe }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Người học #\(id)"
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? nil
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar)) ?? nil
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 0
        medal = (try? c.decodeIfPresent(String.self, forKey: .medal)) ?? nil
        sentences = (try? c.decodeIfPresent(Int.self, forKey: .sentences)) ?? 0
        clean = (try? c.decodeIfPresent(Int.self, forKey: .clean)) ?? 0
        isMe = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
    }
}

/// Bảng xếp hạng luyện nói tuần này: top 10 + hạng của mình nếu ngoài top.
struct WeekTop: Decodable, Hashable {
    var top: [WeekTopEntry] = []
    var me: WeekTopEntry?
    /// Số người đã nói ít nhất 1 câu trong tuần.
    var total = 0

    enum CodingKeys: String, CodingKey { case top, me, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        top = (try? c.decodeIfPresent([WeekTopEntry].self, forKey: .top)) ?? []
        me = (try? c.decodeIfPresent(WeekTopEntry.self, forKey: .me)) ?? nil
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
    }

    /// Mình đang ngoài top: cần hiện thêm dòng của mình ở cuối.
    var meOutsideTop: WeekTopEntry? {
        guard let me, !top.contains(where: \.isMe) else { return nil }
        return me
    }
}

enum SocialAPI {
    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
        let login: Bool?
        // Bạn bè
        let me: SocialUser?
        let following: [SocialUser]?
        let followers: [SocialUser]?
        let suggestions: [SocialUser]?
        let leaderboard: [SocialUser]?
        let users: [SocialUser]?
        let user: SocialUser?
        // Phòng chat
        let rooms: [ChatRoom]?
        let room: ChatRoom?
        let messages: [RoomMessage]?
        let deletedIds: [Int]?
        let hasMore: Bool?
        let message: RoomMessage?
        let online: [RoomMessage.User]?
        let typing: [RoomMessage.User]?
        // Dịch
        let zh: String?
        let vi: String?
        // Bảng tin
        let posts: [FeedPost]?
        let post: FeedPost?
        let comments: [PostComment]?
        let comment: PostComment?
        let likeCount: Int?
        let liked: Bool?
        // Quà
        let gifts: [GiftItem]?
        let senders: [GiftTopUser]?
        // Bảng vàng
        let weeks: [AwardWeek]?
        let receivers: [GiftTopUser]?
    }

    /// Phần chung của mọi phản hồi, đọc trước để báo lỗi / hết phiên.
    private struct Status: Decodable {
        let ok: Bool
        let error: String?
        let login: Bool?
    }

    /// action=online: `rooms` là bảng {"roomId": n}, khác kiểu với danh sách phòng.
    private struct OnlineEnvelope: Decodable {
        let total: Int?
        let rooms: [String: Int]?
    }

    // MARK: Bạn bè

    static func friends() async throws -> FriendsPayload {
        let e = try await call("friends", method: "GET")
        return FriendsPayload(me: e.me, following: e.following ?? [], followers: e.followers ?? [],
                              suggestions: e.suggestions ?? [], leaderboard: e.leaderboard ?? [])
    }

    static func search(_ query: String) async throws -> [SocialUser] {
        try await call("search", ["q": query], method: "GET").users ?? []
    }

    static func profile(id: Int) async throws -> SocialUser {
        guard let user = try await call("profile", ["id": id], method: "GET").user else { throw missing }
        return user
    }

    static func follow(userId: Int) async throws -> SocialUser {
        guard let user = try await call("follow", ["userId": userId]).user else { throw missing }
        return user
    }

    static func unfollow(userId: Int) async throws -> SocialUser {
        guard let user = try await call("unfollow", ["userId": userId]).user else { throw missing }
        return user
    }

    // MARK: Sửa hồ sơ

    /// Đổi tên hiển thị, tên đăng nhập (bỏ trống thì giữ nguyên) và giới thiệu.
    static func updateProfile(name: String, username: String?, bio: String) async throws -> SocialUser {
        var params: [String: Any] = ["name": name, "bio": bio]
        if let username, !username.isEmpty { params["username"] = username }
        guard let user = try await call("profile_update", params).user else { throw missing }
        return user
    }

    /// Tải ảnh đại diện (JPEG); máy chủ cắt vuông 400px.
    static func uploadAvatar(jpeg: Data, progress: ((Double) -> Void)? = nil) async throws -> SocialUser {
        let e = try await multipart("avatar_upload", fields: [:],
                                    files: [UploadFile(field: "avatar", filename: "avatar.jpg", mimeType: "image/jpeg", data: jpeg)],
                                    progress: progress)
        guard let user = e.user else { throw missing }
        return user
    }

    static func removeAvatar() async throws -> SocialUser {
        guard let user = try await call("avatar_remove").user else { throw missing }
        return user
    }

    // MARK: Phòng chat

    static func rooms(query: String = "") async throws -> [ChatRoom] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return try await call("rooms", q.isEmpty ? [:] : ["q": q], method: "GET").rooms ?? []
    }

    static func room(id: Int, after: Int = 0, before: Int = 0) async throws -> RoomPage {
        var params: [String: Any] = ["id": id]
        if after > 0 { params["after"] = after }
        if before > 0 { params["before"] = before }
        let e = try await call("room", params, method: "GET")
        guard let room = e.room else { throw missing }
        return RoomPage(room: room, messages: e.messages ?? [], deletedIds: e.deletedIds ?? [], hasMore: e.hasMore ?? false, online: e.online,
                        typing: e.typing)
    }

    /// Tổng số người đang trong phòng chat (mọi phòng).
    static func online() async throws -> RoomsOnline {
        let data = try await request("online", method: "GET")
        let e = (try? JSONDecoder().decode(OnlineEnvelope.self, from: data))
        var rooms: [Int: Int] = [:]
        for (key, value) in e?.rooms ?? [:] {
            if let id = Int(key) { rooms[id] = value }
        }
        return RoomsOnline(total: e?.total ?? 0, rooms: rooms)
    }

    /// Báo đang gõ / thôi gõ (không cần đợi kết quả).
    static func roomTyping(id: Int, typing: Bool) async {
        _ = try? await request("room_typing", ["id": id, "typing": typing])
    }

    /// Rời màn phòng: bỏ trạng thái đang online ngay thay vì đợi 20 giây.
    static func roomAway(id: Int) async throws {
        _ = try await request("room_away", ["id": id])
    }

    static func createRoom(name: String, description: String, emoji: String) async throws -> ChatRoom {
        guard let room = try await call("room_create", ["name": name, "description": description, "emoji": emoji]).room else { throw missing }
        return room
    }

    static func join(roomId: Int) async throws -> ChatRoom {
        guard let room = try await call("room_join", ["id": roomId]).room else { throw missing }
        return room
    }

    static func leave(roomId: Int) async throws -> ChatRoom {
        guard let room = try await call("room_leave", ["id": roomId]).room else { throw missing }
        return room
    }

    static func deleteRoom(id: Int) async throws {
        _ = try await call("room_delete", ["id": id])
    }

    static func send(roomId: Int, text: String, replyTo: Int? = nil) async throws -> RoomMessage {
        var params: [String: Any] = ["id": roomId, "text": text]
        if let replyTo { params["replyTo"] = replyTo }
        guard let message = try await call("room_send", params).message else { throw missing }
        return message
    }

    static func deleteMessage(id: Int) async throws {
        _ = try await call("message_delete", ["messageId": id])
    }

    /// Gửi ảnh (JPEG đã nén) vào phòng, kèm chữ nếu có.
    static func sendImage(roomId: Int, text: String, jpeg: Data, replyTo: Int? = nil,
                          progress: ((Double) -> Void)? = nil) async throws -> RoomMessage {
        var fields = ["id": String(roomId), "text": text]
        if let replyTo { fields["replyTo"] = String(replyTo) }
        let e = try await multipart("room_send", fields: fields,
                                    files: [UploadFile(field: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: jpeg)],
                                    progress: progress)
        guard let message = e.message else { throw missing }
        return message
    }

    // MARK: Bảng vàng

    /// Top 3 các tuần gần nhất (tuần mới nhất trước).
    /// Top luyện nói tuần này (mọi người học, tính như huy chương tuần).
    static func weekTop() async throws -> WeekTop {
        let data = try await request("week_top", method: "GET")
        guard let top = try? JSONDecoder().decode(WeekTop.self, from: data) else { throw missing }
        return top
    }

    static func awards(weeks: Int = 8) async throws -> [AwardWeek] {
        try await call("awards", ["weeks": weeks], method: "GET").weeks ?? []
    }

    // MARK: Quà tặng

    private static var giftCache: [GiftItem]?

    /// Danh mục quà (lưu tạm trong lúc app mở).
    static func gifts() async throws -> [GiftItem] {
        if let giftCache, !giftCache.isEmpty { return giftCache }
        let list = try await call("gifts", method: "GET").gifts ?? []
        giftCache = list
        return list
    }

    /// Tặng quà trong phòng; `to` nil = cả phòng; `count` 1…99.
    static func sendGift(roomId: Int, gift: String, to: Int?, count: Int) async throws -> RoomMessage {
        var params: [String: Any] = ["id": roomId, "gift": gift, "count": max(1, min(99, count))]
        if let to { params["to"] = to }
        guard let message = try await call("room_gift", params).message else { throw missing }
        return message
    }

    static func giftTop(roomId: Int) async throws -> (senders: [GiftTopUser], receivers: [GiftTopUser]) {
        let e = try await call("gift_top", ["id": roomId], method: "GET")
        return (e.senders ?? [], e.receivers ?? [])
    }

    // MARK: Bảng tin

    struct FeedPage {
        let posts: [FeedPost]
        let hasMore: Bool
    }

    /// Bảng tin: mình + người mình theo dõi; `all` = Khám phá (mọi người).
    static func feed(all: Bool, before: Int = 0) async throws -> FeedPage {
        var params: [String: Any] = [:]
        if all { params["scope"] = "all" }
        if before > 0 { params["before"] = before }
        let e = try await call("feed", params, method: "GET")
        return FeedPage(posts: e.posts ?? [], hasMore: e.hasMore ?? false)
    }

    /// Bài đăng trên tường của một người.
    static func posts(userId: Int, before: Int = 0) async throws -> FeedPage {
        var params: [String: Any] = ["userId": userId]
        if before > 0 { params["before"] = before }
        let e = try await call("posts", params, method: "GET")
        return FeedPage(posts: e.posts ?? [], hasMore: e.hasMore ?? false)
    }

    static func createPost(text: String, image: Data?, audio: UploadFile?, musicURL: String, roomId: Int?,
                           progress: ((Double) -> Void)? = nil) async throws -> FeedPost {
        var fields = ["text": text]
        if !musicURL.isEmpty { fields["musicUrl"] = musicURL }
        if let roomId { fields["roomId"] = String(roomId) }
        var files: [UploadFile] = []
        if let image { files.append(UploadFile(field: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: image)) }
        if let audio { files.append(audio) }
        guard let post = try await multipart("post_create", fields: fields, files: files, progress: progress).post else { throw missing }
        return post
    }

    static func deletePost(id: Int) async throws {
        _ = try await request("post_delete", ["id": id])
    }

    /// Thích / bỏ thích; trả về số lượt thích mới.
    static func like(postId: Int, _ like: Bool) async throws -> (count: Int, liked: Bool) {
        let e = try await call(like ? "post_like" : "post_unlike", ["id": postId])
        return (e.likeCount ?? 0, e.liked ?? like)
    }

    static func comments(postId: Int) async throws -> [PostComment] {
        try await call("comments", ["id": postId], method: "GET").comments ?? []
    }

    static func comment(postId: Int, text: String) async throws -> PostComment {
        guard let comment = try await call("comment", ["id": postId, "text": text]).comment else { throw missing }
        return comment
    }

    static func deleteComment(id: Int) async throws {
        _ = try await request("comment_delete", ["commentId": id])
    }

    /// Phòng đang có người online / mình đã tham gia, để chia sẻ lên bảng tin.
    static func liveRooms() async throws -> [ChatRoom] {
        try await call("rooms_live", method: "GET").rooms ?? []
    }

    // MARK: Dịch (nói tiếng Việt trong phòng chat)

    /// Dịch câu sang tiếng Trung để người học xác nhận trước khi gửi vào phòng.
    /// `to` = "zh": câu tiếng Trung (máy chủ trả `zh`); `to` = "vi": nghĩa tiếng Việt (máy chủ trả `vi`).
    static func translate(text: String, to language: String = "zh") async throws -> String {
        let e = try await call("translate", ["text": text, "to": language])
        let result = ((language == "vi" ? e.vi : e.zh) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw WebBackendError(message: language == "vi" ? "Chưa dịch được tin này. Hãy thử lại." : "Chưa dịch được câu này. Hãy thử nói lại.")
        }
        return result
    }

    // MARK: Gọi máy chủ

    private static var missing: WebBackendError { WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.") }

    private static func call(_ action: String, _ payload: [String: Any] = [:], method: String = "POST") async throws -> Envelope {
        let data = try await request(action, payload, method: method)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.")
        }
        return envelope
    }

    /// Gửi yêu cầu, kiểm tra ok / hết phiên, trả về dữ liệu thô để từng action tự đọc.
    private static var endpoint: URL { WebBackend.baseURL.appendingPathComponent("api/social.php") }

    private static func request(_ action: String, _ payload: [String: Any] = [:], method: String = "POST") async throws -> Data {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Hãy đăng nhập để dùng Bạn bè và Phòng chat.", needsLogin: true)
        }
        var request: URLRequest
        if method == "GET" {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "action", value: action)]
                + payload.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            request = URLRequest(url: components.url!)
        } else {
            request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body = payload
            body["action"] = action
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Hosting có thể bỏ mất header Authorization; máy chủ đọc thêm header này.
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.timeoutInterval = 20

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw WebBackendError(message: "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.")
        }
        return try validate(data)
    }

    /// Một file gửi kèm (ảnh, nhạc).
    struct UploadFile {
        let field: String
        let filename: String
        let mimeType: String
        let data: Data
    }

    /// Gửi multipart/form-data (ảnh phòng chat, bài đăng có ảnh / nhạc), báo tiến độ tải lên 0–1.
    private static func multipart(_ action: String, fields: [String: String], files: [UploadFile],
                                  progress: ((Double) -> Void)? = nil) async throws -> Envelope {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Hãy đăng nhập để dùng Bạn bè và Phòng chat.", needsLogin: true)
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        var allFields = fields
        allFields["action"] = action
        for (name, value) in allFields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        for file in files {
            let safeName = file.filename.replacingOccurrences(of: "\"", with: "")
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(safeName)\"\r\n")
            append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.timeoutInterval = 120

        let data: Data
        do {
            let delegate = UploadProgressDelegate(onProgress: progress)
            (data, _) = try await URLSession.shared.upload(for: request, from: body, delegate: delegate)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw WebBackendError(message: "Không tải lên được. Kiểm tra mạng rồi thử lại.")
        }
        let checked = try validate(data)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: checked) else { throw missing }
        return envelope
    }

    /// Kiểm tra ok / hết phiên của phản hồi.
    private static func validate(_ data: Data) throws -> Data {
        guard let envelope = try? JSONDecoder().decode(Status.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.")
        }
        if envelope.login == true {
            WebAccountStore.shared.sessionExpired()
            throw WebBackendError(message: envelope.error ?? "Phiên đăng nhập đã hết.", needsLogin: true)
        }
        guard envelope.ok else {
            throw WebBackendError(message: envelope.error ?? "Có lỗi xảy ra. Hãy thử lại.")
        }
        return data
    }
}

/// Báo tiến độ tải lên của một yêu cầu.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: ((Double) -> Void)?

    init(onProgress: ((Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let onProgress, totalBytesExpectedToSend > 0 else { return }
        let value = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        DispatchQueue.main.async { onProgress(value) }
    }
}

// MARK: - Bảng tin

/// Người đăng bài / bình luận.
struct FeedUser: Codable, Hashable {
    let id: Int
    let name: String
    let username: String?
    let avatar: String?
    var online: Bool = false
    var medals: Medals?

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var socialUser: SocialUser { SocialUser(id: id, name: name, username: username, avatar: avatar, online: online) }

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, online, medals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Người học #\(id)"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        online = (try? c.decodeIfPresent(Bool.self, forKey: .online)) ?? false
        medals = try? c.decodeIfPresent(Medals.self, forKey: .medals)
    }
}

struct PostComment: Codable, Identifiable, Hashable {
    let id: Int
    let text: String
    let createdAt: String
    let mine: Bool
    let user: FeedUser

    enum CodingKeys: String, CodingKey { case id, text, createdAt, mine, user }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        user = try c.decode(FeedUser.self, forKey: .user)
    }
}

struct FeedPost: Codable, Identifiable, Hashable {
    struct Audio: Codable, Hashable {
        let url: String
        var name: String?
    }

    struct Link: Codable, Hashable {
        let url: String
        var provider: String?
    }

    let id: Int
    let kind: String
    let text: String
    let createdAt: String
    let mine: Bool
    let user: FeedUser
    var image: SocialImage?
    var audio: Audio?
    var link: Link?
    var room: ChatRoom?
    var likeCount: Int = 0
    var commentCount: Int = 0
    var liked: Bool = false
    var comments: [PostComment] = []

    enum CodingKeys: String, CodingKey {
        case id, kind, text, createdAt, mine, user, image, audio, link, room, likeCount, commentCount, liked, comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "status"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        user = try c.decode(FeedUser.self, forKey: .user)
        image = try? c.decodeIfPresent(SocialImage.self, forKey: .image)
        audio = try? c.decodeIfPresent(Audio.self, forKey: .audio)
        link = try? c.decodeIfPresent(Link.self, forKey: .link)
        room = try? c.decodeIfPresent(ChatRoom.self, forKey: .room)
        likeCount = (try? c.decodeIfPresent(Int.self, forKey: .likeCount)) ?? 0
        commentCount = (try? c.decodeIfPresent(Int.self, forKey: .commentCount)) ?? 0
        liked = (try? c.decodeIfPresent(Bool.self, forKey: .liked)) ?? false
        comments = (try? c.decodeIfPresent([PostComment].self, forKey: .comments)) ?? []
    }
}

// MARK: - Tiện ích hiển thị

enum SocialFormat {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return parser.date(from: text)
    }

    /// "Đang online" hoặc "Hoạt động 5 phút / 3 giờ / 2 ngày trước".
    static func presence(online: Bool, lastSeenAt: String?) -> String? {
        if online { return "Đang online" }
        guard let date = date(lastSeenAt) else { return nil }
        let seconds = max(0, Date().timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "Hoạt động vừa xong" }
        if minutes < 60 { return "Hoạt động \(minutes) phút trước" }
        let hours = minutes / 60
        if hours < 24 { return "Hoạt động \(hours) giờ trước" }
        let days = hours / 24
        if days < 30 { return "Hoạt động \(days) ngày trước" }
        let months = days / 30
        return months < 12 ? "Hoạt động \(months) tháng trước" : "Hoạt động \(months / 12) năm trước"
    }

    /// "Tham gia tháng 9/2025".
    static func joined(_ text: String?) -> String? {
        guard let date = date(text) ?? dayParser.date(from: String((text ?? "").prefix(10))) else { return nil }
        let parts = Calendar.current.dateComponents([.month, .year], from: date)
        guard let month = parts.month, let year = parts.year else { return nil }
        return "Tham gia tháng \(month)/\(year)"
    }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "Tuần 07/09 – 13/09" (từ ngày "yyyy-MM-dd").
    static func week(start: String, end: String) -> String {
        func short(_ day: String) -> String {
            let parts = day.prefix(10).split(separator: "-")
            return parts.count == 3 ? "\(parts[2])/\(parts[1])" : day
        }
        return end.isEmpty ? "Tuần \(short(start))" : "Tuần \(short(start)) – \(short(end))"
    }

    /// "Vừa xong", "5 phút", "3 giờ", "2 ngày", xa hơn thì "12/09/2025".
    static func ago(_ text: String?) -> String {
        guard let date = date(text) else { return "" }
        let minutes = Int(max(0, Date().timeIntervalSince(date)) / 60)
        if minutes < 1 { return "Vừa xong" }
        if minutes < 60 { return "\(minutes) phút" }
        if minutes < 24 * 60 { return "\(minutes / 60) giờ" }
        if minutes < 7 * 24 * 60 { return "\(minutes / 1440) ngày" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    /// "14:05" nếu hôm nay, "Hôm qua 14:05", còn lại "12/09 14:05".
    static func time(_ text: String?) -> String {
        guard let date = date(text) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            f.dateFormat = "HH:mm"
            return "Hôm qua " + f.string(from: date)
        }
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: date)
    }
}

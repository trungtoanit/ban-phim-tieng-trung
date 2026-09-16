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
    let title: String
    let emoji: String
    var userTurns: Int = 0
    var target: Int = 50
    var updatedAt: String?

    enum CodingKeys: String, CodingKey { case title, emoji, userTurns, target, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
    let name: String
    let username: String?
    let avatar: String?
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

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var handle: String? { username.map { "@\($0)" } }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey {
        case id, name, username, avatar, weekSentences, todaySentences, totalSentences, streak
        case isMe, following, followsMe, online, lastSeenAt, followersCount, followingCount, joinedAt
        case bestStreak, activeDays, accuracy, avgCpm, topicsCount, topicsCompleted
        case calendar, badges, recentTopics, rooms
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

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, isOwner, online }

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
    }
}

struct RoomMessage: Codable, Identifiable, Hashable {
    struct User: Codable, Hashable {
        let id: Int
        let name: String
        let username: String?
        let avatar: String?

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

    enum CodingKeys: String, CodingKey { case id, text, createdAt, mine, user, image }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        user = try c.decode(User.self, forKey: .user)
        image = try? c.decodeIfPresent(SocialImage.self, forKey: .image)
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
}

/// Số người đang trong phòng chat: tổng (không trùng) và theo từng phòng.
struct RoomsOnline {
    let total: Int
    let rooms: [Int: Int]
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
        // Dịch
        let zh: String?
        // Bảng tin
        let posts: [FeedPost]?
        let post: FeedPost?
        let comments: [PostComment]?
        let comment: PostComment?
        let likeCount: Int?
        let liked: Bool?
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
        return RoomPage(room: room, messages: e.messages ?? [], deletedIds: e.deletedIds ?? [], hasMore: e.hasMore ?? false, online: e.online)
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

    static func send(roomId: Int, text: String) async throws -> RoomMessage {
        guard let message = try await call("room_send", ["id": roomId, "text": text]).message else { throw missing }
        return message
    }

    static func deleteMessage(id: Int) async throws {
        _ = try await call("message_delete", ["messageId": id])
    }

    /// Gửi ảnh (JPEG đã nén) vào phòng, kèm chữ nếu có.
    static func sendImage(roomId: Int, text: String, jpeg: Data, progress: ((Double) -> Void)? = nil) async throws -> RoomMessage {
        let e = try await multipart("room_send", fields: ["id": String(roomId), "text": text],
                                    files: [UploadFile(field: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: jpeg)],
                                    progress: progress)
        guard let message = e.message else { throw missing }
        return message
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
    static func translate(text: String, to language: String = "zh") async throws -> String {
        let zh = try await call("translate", ["text": text, "to": language]).zh?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !zh.isEmpty else { throw WebBackendError(message: "Chưa dịch được câu này. Hãy thử nói lại.") }
        return zh
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

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var socialUser: SocialUser { SocialUser(id: id, name: name, username: username, avatar: avatar, online: online) }

    enum CodingKeys: String, CodingKey { case id, name, username, avatar, online }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Người học #\(id)"
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        online = (try? c.decodeIfPresent(Bool.self, forKey: .online)) ?? false
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

//
//  SocialAPI.swift
//  Bạn bè (theo dõi nhau, bảng xếp hạng tuần) và phòng chat công khai — gọi api/social.php của website.
//

import Foundation

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
    /// Chỉ có khi xem hồ sơ (action=profile).
    var followersCount: Int?
    var followingCount: Int?
    var joinedAt: String?

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var handle: String? { username.map { "@\($0)" } }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey {
        case id, name, username, avatar, weekSentences, todaySentences, totalSentences, streak
        case isMe, following, followsMe, followersCount, followingCount, joinedAt
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
        followersCount = try c.decodeIfPresent(Int.self, forKey: .followersCount)
        followingCount = try c.decodeIfPresent(Int.self, forKey: .followingCount)
        joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAt)
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

    enum CodingKeys: String, CodingKey {
        case id, name, description, emoji, ownerId, ownerName, memberCount, messageCount
        case lastMessage, lastMessageAt, joined, isOwner, createdAt, onlineCount
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
    }

    let id: Int
    let text: String
    let createdAt: String
    let mine: Bool
    let user: User
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
    private static func request(_ action: String, _ payload: [String: Any] = [:], method: String = "POST") async throws -> Data {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Hãy đăng nhập để dùng Bạn bè và Phòng chat.", needsLogin: true)
        }
        let endpoint = WebBackend.baseURL.appendingPathComponent("api/social.php")
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

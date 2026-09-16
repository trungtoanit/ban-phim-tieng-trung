//
//  ChatRoomsView.swift
//  Phòng chat công khai kiểu HelloTalk: ai cũng tạo được phòng, vào phòng nói chuyện bằng tiếng Trung.
//  Dùng chung dữ liệu với phong-chat.php của website (api/social.php). Tin mới được hỏi lại mỗi 3 giây.
//

import Combine
import PhotosUI
import SwiftUI

struct ChatRoomsView: View {
    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        if web.isSignedIn {
            RoomsListView()
        } else {
            NavigationStack {
                SocialSignInCard(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    title: "Trò chuyện cùng mọi người",
                    message: "Cần tài khoản để vào phòng chat, tạo phòng riêng và luyện gõ tiếng Trung với người học khác."
                )
                .navigationTitle("Phòng chat")
                .homeBackButton()
            }
        }
    }
}

// MARK: - Danh sách phòng

@MainActor
final class RoomsListModel: ObservableObject {
    @Published var rooms: [ChatRoom] = []
    @Published var loaded = false
    @Published var errorMessage: String?
    /// Tổng số người đang trong phòng chat (mọi phòng).
    @Published var onlineTotal = 0

    var joined: [ChatRoom] { rooms.filter(\.joined) }
    var explore: [ChatRoom] { rooms.filter { !$0.joined } }

    /// `silent`: làm mới ngầm định kỳ, lỗi mạng tạm thời thì không báo.
    func load(query: String = "", silent: Bool = false) async {
        do {
            rooms = try await SocialAPI.rooms(query: query)
            loaded = true
        } catch is CancellationError {
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func loadOnline() async {
        guard let online = try? await SocialAPI.online() else { return }
        onlineTotal = online.total
    }

    /// Cập nhật một phòng vừa đổi (tham gia / rời / tin mới) mà không tải lại cả danh sách.
    func update(_ room: ChatRoom) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else {
            rooms.insert(room, at: 0)
        }
    }

    func remove(id: Int) {
        rooms.removeAll { $0.id == id }
    }
}

private struct RoomsListView: View {
    @StateObject private var model = RoomsListModel()
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.onlineTotal > 0 {
                    Section {
                        HStack(spacing: 8) {
                            OnlineDot(size: 9)
                            Text("\(model.onlineTotal) người đang trong phòng chat")
                                .font(.subheadline.weight(.medium))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if model.loaded, model.rooms.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Text("💬").font(.largeTitle)
                            Text(query.isEmpty ? "Chưa có phòng nào. Tạo phòng đầu tiên nhé!" : "Không tìm thấy phòng nào.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }
                if !model.joined.isEmpty {
                    Section("Phòng của bạn") {
                        ForEach(model.joined) { room in
                            NavigationLink(value: room) { RoomRow(room: room) }
                        }
                    }
                }
                if !model.explore.isEmpty {
                    Section("Khám phá") {
                        ForEach(model.explore) { room in
                            NavigationLink(value: room) { RoomRow(room: room) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if !model.loaded && model.errorMessage == nil {
                    ProgressView("Đang tải…")
                }
            }
            .navigationTitle("Phòng chat")
            .homeBackButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityLabel("Tạo phòng")
                }
            }
            .searchable(text: $query, prompt: "Tìm phòng")
            .task(id: query) {
                // Lần đầu tải ngay; khi gõ tìm thì đợi 300ms.
                if model.loaded {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                }
                await model.load(query: query)
            }
            // Số người đang online thay đổi liên tục: làm mới danh sách + tổng mỗi 10 giây khi đang xem.
            .task(id: query) {
                await model.loadOnline()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { break }
                    await model.load(query: query, silent: true)
                    await model.loadOnline()
                }
            }
            .refreshable {
                await model.load(query: query)
                await model.loadOnline()
            }
            .navigationDestination(for: ChatRoom.self) { room in
                RoomChatView(room: room,
                             onUpdate: { model.update($0) },
                             onDeleted: { model.remove(id: room.id) })
            }
            .navigationDestination(for: SocialUser.self) { user in
                SocialProfileView(user: user)
            }
            .roomDestinations(onUpdate: { model.update($0) }, onDeleted: { model.remove(id: $0) })
            .sheet(isPresented: $creating) {
                CreateRoomSheet { room in
                    model.update(room)
                    path.append(room)
                }
            }
            .alert("Có lỗi", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .tint(socialRed)
    }
}

private struct RoomRow: View {
    let room: ChatRoom

    private let ring = Color(.secondarySystemGroupedBackground)

    /// Chủ phòng: lấy trong danh sách thành viên, không có thì dựng từ `room.owner`.
    private var owner: RoomMember? {
        if let member = room.members.first(where: { $0.isOwner || $0.id == room.ownerId }) { return member }
        if let o = room.owner {
            return RoomMember(id: o.id, name: o.name, username: o.username, avatar: o.avatar, isOwner: true)
        }
        guard room.ownerId > 0, !room.ownerName.isEmpty else { return nil }
        return RoomMember(id: room.ownerId, name: room.ownerName, username: nil, avatar: nil, isOwner: true)
    }

    /// Người tham gia, không tính chủ phòng.
    private var participants: [RoomMember] {
        room.sortedMembers.filter { !$0.isOwner && $0.id != room.ownerId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoomEmoji(emoji: room.emoji, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(room.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if room.isOwner {
                            Text("Chủ phòng")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(socialRed)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(socialRed.opacity(0.12)))
                        }
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if let time = room.lastMessageAt, !SocialFormat.time(time).isEmpty {
                    Text(SocialFormat.time(time))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            bottomRow
        }
        .padding(.vertical, 2)
    }

    // MARK: Hàng dưới: chủ phòng (trái) · người tham gia (phải)

    private var bottomRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if let owner {
                HStack(spacing: 7) {
                    SocialAvatar(url: owner.avatarURL, initial: owner.initial, size: 26, online: owner.online, ring: ring)
                        .overlay(alignment: .top) {
                            Text("👑")
                                .font(.system(size: 11))
                                .offset(y: -10)
                        }
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(owner.name)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("Chủ phòng")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.8, green: 0.58, blue: 0.05))
                    }
                }
                .layoutPriority(0)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Chủ phòng \(owner.name)")
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                if !participants.isEmpty {
                    RoomMemberStack(members: participants, total: max(0, room.memberCount - 1))
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(room.memberCount > 1 ? "\(room.memberCount - 1) người tham gia" : "Chưa ai tham gia")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if room.onlineCount > 0 {
                        HStack(spacing: 3) {
                            OnlineDot(size: 6)
                            Text("\(room.onlineCount) online")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(onlineGreen)
                    }
                }
                .fixedSize()
            }
            .layoutPriority(1)
        }
    }

    private var preview: String {
        if let last = room.lastMessage {
            // Tin cuối chỉ có ảnh (chữ rỗng).
            return last.isEmpty ? "📷 Ảnh / 🎁 Quà tặng" : last
        }
        return room.description.isEmpty ? "Chưa có tin nhắn" : room.description
    }
}

/// Chồng ảnh đại diện người tham gia (tối đa 4, chấm xanh người đang online, "+N").
/// Mỗi ảnh có viền màu nền; ảnh trước nằm trên ảnh sau để chấm online ở góc phải không bị che.
private struct RoomMemberStack: View {
    let members: [RoomMember]
    let total: Int
    var size: CGFloat = 24
    var maxShown = 4

    private let ring = Color(.secondarySystemGroupedBackground)

    var body: some View {
        let shown = Array(members.prefix(maxShown))
        HStack(spacing: -size * 0.28) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, member in
                SocialAvatar(url: member.avatarURL, initial: member.initial, size: size, online: member.online, ring: ring)
                    .padding(2)
                    .background(Circle().fill(ring))
                    .zIndex(Double(shown.count - index))
            }
            if total > shown.count {
                Text("+\(total - shown.count)")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(minWidth: size, minHeight: size)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                    .padding(2)
                    .background(Capsule().fill(ring))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) người tham gia")
    }
}

// MARK: - Điều hướng dùng chung (phòng từ tường, danh sách thành viên)

struct RoomMembersRoute: Hashable {
    let room: ChatRoom
    var typingIDs: Set<Int> = []
}

extension View {
    /// Mở phòng từ tường (`WallRoom`) và trang thành viên phòng. Gắn ở gốc mỗi NavigationStack.
    func roomDestinations(onUpdate: @escaping (ChatRoom) -> Void = { _ in },
                          onDeleted: @escaping (Int) -> Void = { _ in }) -> some View {
        self
            .navigationDestination(for: WallRoom.self) { wallRoom in
                RoomChatView(room: ChatRoom(placeholder: wallRoom), onUpdate: onUpdate, onDeleted: { onDeleted(wallRoom.id) })
            }
            .navigationDestination(for: RoomMembersRoute.self) { route in
                RoomMembersView(room: route.room, typingIDs: route.typingIDs)
            }
    }
}

/// Toàn bộ thành viên phòng: chủ phòng 👑 đầu tiên, người đang online có chấm xanh. Chạm để xem tường.
struct RoomMembersView: View {
    @State private var room: ChatRoom
    let typingIDs: Set<Int>

    init(room: ChatRoom, typingIDs: Set<Int> = []) {
        _room = State(initialValue: room)
        self.typingIDs = typingIDs
    }

    private var members: [RoomMember] {
        var list = room.sortedMembers
        // Máy chủ cũ chưa gửi danh sách: ít nhất hiện chủ phòng.
        if list.isEmpty, room.ownerId > 0 {
            list = [RoomMember(id: room.ownerId, name: room.owner?.name ?? room.ownerName,
                               username: room.owner?.username, avatar: room.owner?.avatar, isOwner: true)]
        }
        return list
    }

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    NavigationLink(value: member.socialUser) {
                        HStack(spacing: 12) {
                            SocialAvatar(url: member.avatarURL, initial: member.initial, size: 42, online: member.online,
                                         ring: Color(.secondarySystemGroupedBackground))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(member.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    if member.isOwner { Text("👑").font(.caption) }
                                }
                                HStack(spacing: 6) {
                                    if member.isOwner {
                                        Text("Chủ phòng")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(socialRed)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(socialRed.opacity(0.12)))
                                    }
                                    if typingIDs.contains(member.id) {
                                        Text("đang gõ…")
                                            .font(.caption.italic())
                                            .foregroundStyle(onlineGreen)
                                    } else if member.online {
                                        Text("đang online")
                                            .font(.caption)
                                            .foregroundStyle(onlineGreen)
                                    } else if let username = member.username {
                                        Text("@\(username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text("Thành viên (\(max(room.memberCount, members.count)))")
            } footer: {
                if room.memberCount > members.count {
                    Text("Đang hiện \(members.count)/\(room.memberCount) thành viên.")
                }
            }
            GiftTopSection(roomID: room.id)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(room.emoji) \(room.name)")
        .navigationBarTitleDisplayMode(.inline)
        .tint(socialRed)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        // after = rất lớn: chỉ lấy thông tin phòng + thành viên, không kéo tin nhắn.
        if let page = try? await SocialAPI.room(id: room.id, after: Int(Int32.max)) {
            room = page.room
        }
    }
}

private struct RoomEmoji: View {
    let emoji: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji.isEmpty ? "💬" : emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(socialRed.opacity(0.1))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Tạo phòng

private struct CreateRoomSheet: View {
    let onCreated: (ChatRoom) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var emoji = "💬"
    @State private var saving = false
    @State private var errorMessage: String?

    private static let emojis = ["💬", "🇨🇳", "📚", "🎧", "🍜", "✈️", "💼", "🎮", "🎬", "🏮", "🐼", "☕️"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { (3...60).contains(trimmedName.count) && description.count <= 200 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên phòng (vd: Luyện HSK 3)", text: $name)
                        .onChange(of: name) { value in
                            if value.count > 60 { name = String(value.prefix(60)) }
                        }
                } header: {
                    Text("Tên phòng")
                } footer: {
                    Text("\(trimmedName.count)/60 · ít nhất 3 ký tự")
                }

                Section {
                    TextField("Phòng này để làm gì?", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: description) { value in
                            if value.count > 200 { description = String(value.prefix(200)) }
                        }
                } header: {
                    Text("Mô tả")
                } footer: {
                    Text("\(description.count)/200")
                }

                Section("Biểu tượng") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(Self.emojis, id: \.self) { item in
                            Button {
                                emoji = item
                            } label: {
                                Text(item)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(emoji == item ? socialRed.opacity(0.15) : Color(.tertiarySystemFill))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(emoji == item ? socialRed : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tạo phòng mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Tạo") { Task { await create() } }
                            .disabled(!valid)
                    }
                }
            }
        }
        .tint(socialRed)
    }

    private func create() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let room = try await SocialAPI.createRoom(name: trimmedName,
                                                      description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                                      emoji: emoji)
            dismiss()
            onCreated(room)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Màn chat trong phòng

@MainActor
final class RoomChatModel: ObservableObject {
    @Published var room: ChatRoom
    @Published var messages: [RoomMessage] = []
    @Published var hasMore = false
    @Published var loaded = false
    @Published var loadingOlder = false
    @Published var sending = false
    @Published var errorMessage: String?
    /// Phòng đã bị chủ phòng xoá.
    @Published var gone = false
    /// Những người đang trong phòng (mình đứng đầu).
    @Published var online: [RoomMessage.User] = []

    /// Số người đang online: ưu tiên danh sách, máy chủ cũ không có thì dùng onlineCount.
    var onlineCount: Int { max(room.onlineCount, online.count) }

    /// Id những người đang trong phòng (danh sách online + thành viên có chấm xanh).
    var onlineIDs: Set<Int> {
        Set(online.map(\.id)).union(room.members.filter(\.online).map(\.id))
    }

    /// Pinyin của từng tin (tách từ tốn thời gian, không tính lại mỗi lần vẽ).
    private var wordsCache: [Int: [PinyinWord]] = [:]

    static let maxLength = 500

    init(room: ChatRoom) {
        self.room = room
    }

    func words(for message: RoomMessage) -> [PinyinWord]? {
        if let cached = wordsCache[message.id] { return cached }
        guard ChineseText.containsHan(message.text) else { return nil }
        let words = ChineseText.words(for: message.text)
        wordsCache[message.id] = words
        return words
    }

    // MARK: Quà

    /// Quà mới đến (mình vừa tặng, hoặc người khác tặng khi đang mở phòng) → phát hiệu ứng.
    let giftArrived = PassthroughSubject<RoomMessage, Never>()
    private var giftEffectShown = Set<Int>()

    private func announceGifts(_ fresh: [RoomMessage]) {
        for message in fresh where message.gift != nil && !giftEffectShown.contains(message.id) {
            giftEffectShown.insert(message.id)
            giftArrived.send(message)
        }
    }

    /// Mình vừa tặng quà: thêm vào danh sách và phát hiệu ứng ngay.
    func receiveSentGift(_ message: RoomMessage) {
        let fresh = merge([message])
        announceGifts(fresh)
        if !room.joined {
            room.joined = true
            room.memberCount += 1
        }
        room.lastMessageAt = message.createdAt
    }

    // MARK: Dịch tin

    /// Nghĩa tiếng Việt đã dịch (theo id tin) và những tin đang hiện bản dịch.
    @Published var translations: [Int: String] = [:]
    @Published var shownTranslations: Set<Int> = []
    @Published var translatingIDs: Set<Int> = []

    /// Bấm "Dịch": chưa có thì dịch rồi hiện; đang hiện thì ẩn.
    func toggleTranslation(_ message: RoomMessage) {
        if shownTranslations.contains(message.id) {
            shownTranslations.remove(message.id)
            return
        }
        shownTranslations.insert(message.id)
        guard translations[message.id] == nil, !translatingIDs.contains(message.id) else { return }
        translatingIDs.insert(message.id)
        Task {
            defer { translatingIDs.remove(message.id) }
            do {
                translations[message.id] = try await SocialAPI.translate(text: message.text, to: "vi")
            } catch {
                shownTranslations.remove(message.id)
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: Đang gõ

    /// Những người khác đang gõ.
    @Published var typing: [RoomMessage.User] = []
    var typingIDs: Set<Int> { Set(typing.map(\.id)) }
    private var lastTypingSent: Date?

    /// Gọi khi ô gõ có chữ và đang thay đổi: báo máy chủ tối đa 2,5 giây một lần.
    func userIsTyping() {
        if let last = lastTypingSent, Date().timeIntervalSince(last) < 2.5 { return }
        lastTypingSent = Date()
        let id = room.id
        Task { await SocialAPI.roomTyping(id: id, typing: true) }
    }

    /// Ô gõ trống / rời màn hình: báo thôi gõ (chỉ khi trước đó đã báo đang gõ).
    func userStoppedTyping() {
        guard lastTypingSent != nil else { return }
        lastTypingSent = nil
        let id = room.id
        Task { await SocialAPI.roomTyping(id: id, typing: false) }
    }

    func load() async {
        do {
            let page = try await SocialAPI.room(id: room.id)
            room = page.room
            if let people = page.online { online = people }
            if let people = page.typing { typing = people }
            // Quà trong lịch sử không phát hiệu ứng.
            giftEffectShown.formUnion(page.messages.filter { $0.gift != nil }.map(\.id))
            messages = page.messages
            hasMore = page.hasMore
            loaded = true
        } catch is CancellationError {
        } catch {
            if (error as? WebBackendError)?.message.contains("không còn") == true { gone = true }
            errorMessage = error.localizedDescription
        }
    }

    /// Hỏi tin mới hơn tin cuối đang có; bỏ những tin đã bị xoá.
    func poll() async {
        guard loaded else {
            await load()
            return
        }
        do {
            let page = try await SocialAPI.room(id: room.id, after: messages.last?.id ?? 0)
            room = page.room
            if let people = page.online, people != online { online = people }
            if let people = page.typing, people != typing { typing = people }
            announceGifts(merge(page.messages))
            if !page.deletedIds.isEmpty {
                let deleted = Set(page.deletedIds)
                if messages.contains(where: { deleted.contains($0.id) }) {
                    messages.removeAll { deleted.contains($0.id) }
                }
            }
        } catch is CancellationError {
        } catch {
            // Lỗi mạng tạm thời: lần hỏi sau thử lại. Phòng bị xoá thì báo ra ngoài.
            if (error as? WebBackendError)?.message.contains("không còn") == true { gone = true }
        }
    }

    /// Tìm tin gốc để cuộn tới: chưa có thì tải thêm tin cũ vài lần. Trả về false nếu quá cũ / đã xoá.
    func ensureLoaded(messageID: Int, maxPages: Int = 5) async -> Bool {
        var pages = 0
        while !messages.contains(where: { $0.id == messageID }) {
            guard hasMore, pages < maxPages, let first = messages.first, first.id > messageID else { return false }
            await loadOlder()
            pages += 1
        }
        return true
    }

    func loadOlder() async {
        guard let first = messages.first, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await SocialAPI.room(id: room.id, before: first.id)
            let known = Set(messages.map(\.id))
            giftEffectShown.formUnion(page.messages.filter { $0.gift != nil }.map(\.id))
            messages.insert(contentsOf: page.messages.filter { !known.contains($0.id) }, at: 0)
            hasMore = page.hasMore
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tin đang được trả lời (thanh "Đang trả lời" trên ô soạn tin). Mọi kiểu gửi đều kèm theo.
    @Published var replyingTo: RoomMessage?

    /// Bỏ thanh trả lời sau khi gửi xong (nếu người dùng chưa đổi sang trả lời tin khác).
    private func clearReply(_ id: Int?) {
        if let id, replyingTo?.id == id { replyingTo = nil }
    }

    func send(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= Self.maxLength, !sending else { return false }
        sending = true
        defer { sending = false }
        let replyID = replyingTo?.id
        do {
            let message = try await SocialAPI.send(roomId: room.id, text: text, replyTo: replyID)
            clearReply(replyID)
            lastTypingSent = nil
            merge([message])
            if !room.joined {
                room.joined = true
                room.memberCount += 1
            }
            room.lastMessage = message.text
            room.lastMessageAt = message.createdAt
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Ảnh đang tải lên (hiện bong bóng chờ có tiến độ).
    struct PendingUpload: Identifiable {
        let id = UUID()
        let preview: UIImage
        var progress: Double = 0
    }

    @Published var uploads: [PendingUpload] = []

    /// Nén ảnh (JPEG ≤ 1600px, chất lượng 0,8) rồi gửi vào phòng.
    func sendImage(_ image: UIImage) async {
        guard let jpeg = SocialImageCompressor.jpeg(from: image) else {
            errorMessage = "Không đọc được ảnh này."
            return
        }
        let upload = PendingUpload(preview: image)
        uploads.append(upload)
        defer { uploads.removeAll { $0.id == upload.id } }
        let replyID = replyingTo?.id
        // Ảnh đang tải lên đã mang theo trả lời: bỏ thanh ngay để tin kế tiếp không trả lời trùng.
        clearReply(replyID)
        do {
            let message = try await SocialAPI.sendImage(roomId: room.id, text: "", jpeg: jpeg, replyTo: replyID) { [weak self] value in
                guard let self, let index = self.uploads.firstIndex(where: { $0.id == upload.id }) else { return }
                self.uploads[index].progress = value
            }
            merge([message])
            if !room.joined {
                room.joined = true
                room.memberCount += 1
            }
            room.lastMessage = message.text
            room.lastMessageAt = message.createdAt
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ message: RoomMessage) async {
        let before = messages
        messages.removeAll { $0.id == message.id }
        do {
            try await SocialAPI.deleteMessage(id: message.id)
        } catch {
            messages = before
            errorMessage = error.localizedDescription
        }
    }

    func setJoined(_ join: Bool) async {
        do {
            if join {
                room = try await SocialAPI.join(roomId: room.id)
            } else {
                room = try await SocialAPI.leave(roomId: room.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRoom() async -> Bool {
        do {
            try await SocialAPI.deleteRoom(id: room.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Thêm tin mới; trả về những tin thật sự mới.
    @discardableResult
    private func merge(_ incoming: [RoomMessage]) -> [RoomMessage] {
        let known = Set(messages.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return [] }
        messages.append(contentsOf: fresh)
        messages.sort { $0.id < $1.id }
        return fresh
    }
}

struct RoomChatView: View {
    let onUpdate: (ChatRoom) -> Void
    let onDeleted: () -> Void

    @StateObject private var model: RoomChatModel
    /// Micro của ô soạn tin. Giữ bằng @State (không theo dõi) để mức âm lượng micro đổi liên tục
    /// chỉ vẽ lại ô soạn tin, không vẽ lại cả danh sách tin nhắn.
    @State private var voice = RoomVoiceModel()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var selectedWord: SelectedWord?
    @State private var viewingImage: SocialImage?
    /// Hiệu ứng quà. @State (không theo dõi) để phát hiệu ứng không vẽ lại danh sách tin.
    @State private var giftCenter = GiftEffectCenter()
    /// Tin cần cuộn tới (bấm vào trích dẫn) và tin đang được tô sáng.
    @State private var scrollTarget: Int?
    @State private var highlightedID: Int?
    @State private var toast: String?
    @State private var composerFocused = false
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false

    private static let bottomID = "room-bottom"

    init(room: ChatRoom, onUpdate: @escaping (ChatRoom) -> Void, onDeleted: @escaping () -> Void) {
        _model = StateObject(wrappedValue: RoomChatModel(room: room))
        self.onUpdate = onUpdate
        self.onDeleted = onDeleted
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.hasMore {
                        Button {
                            Task { await model.loadOlder() }
                        } label: {
                            HStack(spacing: 6) {
                                if model.loadingOlder { ProgressView().controlSize(.small) }
                                Text("Tải tin cũ hơn")
                            }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.loadingOlder)
                    }

                    if model.loaded, model.messages.isEmpty {
                        VStack(spacing: 8) {
                            RoomEmoji(emoji: model.room.emoji, size: 64)
                            Text("Chưa có tin nhắn nào")
                                .font(.headline)
                            Text("Hãy chào mọi người bằng tiếng Trung: 大家好！")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }

                    let onlineIDs = model.onlineIDs
                    ForEach(model.messages) { message in
                        bubble(message, online: onlineIDs.contains(message.user.id))
                            .padding(.vertical, 3)
                            .padding(.horizontal, -4)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(socialRed.opacity(highlightedID == message.id ? 0.14 : 0))
                            )
                            .modifier(SwipeToReply { startReply(message) })
                            .id(message.id)
                    }

                    ForEach(model.uploads) { upload in
                        uploadBubble(upload)
                    }

                    if !model.typing.isEmpty {
                        TypingIndicator(users: model.typing)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if !model.loaded && model.errorMessage == nil {
                    ProgressView()
                }
            }
            .onChange(of: model.messages.last?.id) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                withAnimation(.easeIn(duration: 0.2)) { highlightedID = target }
                scrollTarget = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    guard highlightedID == target else { return }
                    withAnimation(.easeOut(duration: 0.5)) { highlightedID = nil }
                }
            }
            .onChange(of: model.uploads.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .onChange(of: composerFocused) { focused in
                guard focused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { onlineStrip }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RoomComposer(model: model, voice: voice, focused: $composerFocused)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .navigationBarTrailing) { menu }
        }
        .wordPopup($selectedWord)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .fullScreenCover(item: $viewingImage) { image in
            ZoomableImageViewer(url: image.imageURL)
        }
        // Hỏi tin mới mỗi 3 giây khi đang mở phòng; rời màn hình thì .task tự huỷ vòng lặp.
        .task {
            await model.load()
            // Lần trước bật rảnh tay thì mở micro lại khi đã vào phòng (xin quyền như hội thoại AI).
            if voice.handsFree, !voice.isListening {
                voice.listen()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await model.poll()
            }
        }
        .overlay { GiftEffectsOverlay(center: giftCenter) }
        .onReceive(model.giftArrived) { giftCenter.enqueue($0) }
        .animation(.easeInOut(duration: 0.2), value: model.typing.map(\.id))
        .onAppear {
            voice.activate { [model] text in await model.send(text) }
            voice.onError = { [model] message in model.errorMessage = message }
        }
        // Rời màn phòng thì báo máy chủ bỏ trạng thái đang online (không cần đợi kết quả), tắt micro / rảnh tay.
        .onDisappear {
            voice.deactivate()
            giftCenter.stop()
            model.userStoppedTyping()
            let id = model.room.id
            Task { try? await SocialAPI.roomAway(id: id) }
        }
        .onChange(of: model.room) { onUpdate($0) }
        .onChange(of: model.gone) { gone in
            guard gone else { return }
            onDeleted()
            dismiss()
        }
        .confirmationDialog("Xoá phòng “\(model.room.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá phòng", role: .destructive) {
                Task {
                    if await model.deleteRoom() {
                        onDeleted()
                        dismiss()
                    }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Toàn bộ tin nhắn trong phòng sẽ không xem được nữa.")
        }
        .alert("Có lỗi", isPresented: Binding(get: { model.errorMessage != nil && !model.gone },
                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Thanh tiêu đề

    private var ownerName: String {
        model.room.owner?.name ?? model.room.ownerName
    }

    /// Chạm vào tiêu đề để xem toàn bộ thành viên.
    private var header: some View {
        NavigationLink(value: RoomMembersRoute(room: model.room, typingIDs: model.typingIDs)) {
            HStack(spacing: 8) {
                Text(model.room.emoji).font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.room.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        if !ownerName.isEmpty {
                            Text("👑 \(ownerName)")
                            Text("·")
                        }
                        Text("👥 \(model.room.memberCount)")
                        if model.onlineCount > 0 {
                            Text("·")
                            OnlineDot(size: 6)
                            Text("\(model.onlineCount) online")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Xem thành viên")
    }

    /// Người đang online trong phòng: chủ phòng (👑) đứng đầu, rồi mình, rồi người khác.
    private var onlinePeople: [RoomMessage.User] {
        let myID = WebAccountStore.shared.user?.id ?? model.online.first?.id
        var people: [RoomMessage.User] = []
        var seen = Set<Int>()
        for user in model.online where seen.insert(user.id).inserted {
            people.append(user)
        }
        for member in model.room.members where member.online && seen.insert(member.id).inserted {
            people.append(RoomMessage.User(id: member.id, name: member.name, username: member.username, avatar: member.avatar))
        }
        func rank(_ user: RoomMessage.User) -> Int {
            if user.id == model.room.ownerId { return 0 }
            return user.id == myID ? 1 : 2
        }
        return people.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Dải dưới tiêu đề: chỉ những người đang online + link xem tất cả thành viên.
    @ViewBuilder
    private var onlineStrip: some View {
        if model.loaded {
            let people = onlinePeople
            let myID = WebAccountStore.shared.user?.id ?? model.online.first?.id
            let othersOnline = people.contains { $0.id != myID }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text("🟢 \(people.count) đang online")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    NavigationLink(value: RoomMembersRoute(room: model.room, typingIDs: model.typingIDs)) {
                        HStack(spacing: 3) {
                            Text("Xem tất cả \(model.room.memberCount) thành viên")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(socialRed)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(people, id: \.id) { user in
                            onlineAvatar(user, isMe: user.id == myID)
                        }
                        if !othersOnline {
                            Text("Chưa có ai khác online")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, people.isEmpty ? 0 : 2)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private func onlineAvatar(_ user: RoomMessage.User, isMe: Bool) -> some View {
        NavigationLink(value: user.socialUser(online: true)) {
            VStack(spacing: 3) {
                SocialAvatar(url: user.avatarURL, initial: user.initial, size: 36, online: true)
                    .overlay(alignment: .top) {
                        if user.id == model.room.ownerId {
                            Text("👑").font(.system(size: 12)).offset(y: -9)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if model.typingIDs.contains(user.id) {
                            TypingDots(dotSize: 3.5)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(.systemBackground)))
                                .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
                                .offset(x: 8, y: -4)
                        }
                    }
                Text(isMe ? "Bạn" : user.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            }
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMe ? "Bạn" : user.name)\(user.id == model.room.ownerId ? ", chủ phòng" : ""), đang online")
    }

    private var menu: some View {
        Menu {
            if model.room.joined {
                if !model.room.isOwner {
                    Button {
                        Task { await model.setJoined(false) }
                    } label: {
                        Label("Rời phòng", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } else {
                Button {
                    Task { await model.setJoined(true) }
                } label: {
                    Label("Tham gia", systemImage: "person.badge.plus")
                }
            }
            Section("Chủ phòng: 👑 \(ownerName)") {
                if model.room.isOwner {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Xoá phòng", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: Trả lời

    private func startReply(_ message: RoomMessage) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.15)) { model.replyingTo = message }
    }

    /// Bấm vào trích dẫn: cuộn tới tin gốc (tải thêm tin cũ nếu cần) và tô sáng.
    private func jumpToOriginal(_ reply: RoomMessage.ReplyRef) {
        guard !reply.deleted else {
            showToast("Tin nhắn gốc đã bị xoá")
            return
        }
        Task {
            if await model.ensureLoaded(messageID: reply.id) {
                // Đợi danh sách vẽ xong những tin vừa tải rồi mới cuộn.
                try? await Task.sleep(nanoseconds: 150_000_000)
                scrollTarget = reply.id
            } else {
                showToast("Tin nhắn gốc quá cũ")
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard toast == text else { return }
            withAnimation { toast = nil }
        }
    }

    /// Khối trích dẫn nhỏ ở đầu bong bóng: vạch đỏ, tên in đậm, 2 dòng nội dung.
    private func quoteBlock(_ reply: RoomMessage.ReplyRef, mine: Bool) -> some View {
        Button {
            jumpToOriginal(reply)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(socialRed)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.name.isEmpty ? "Tin nhắn" : reply.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(socialRed)
                        .lineLimit(1)
                    Group {
                        if reply.deleted {
                            Text("Tin nhắn đã bị xoá").italic()
                        } else {
                            Text(Self.snippet(text: reply.text, hasImage: reply.hasImage))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(maxWidth: 240, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(mine ? socialRed.opacity(0.07) : Color(.tertiarySystemFill))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trả lời \(reply.name): \(reply.deleted ? "tin đã bị xoá" : Self.snippet(text: reply.text, hasImage: reply.hasImage))")
        .accessibilityHint("Chạm để xem tin gốc")
    }

    static func snippet(text: String, hasImage: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return hasImage ? "📷 Hình ảnh" : "" }
        return hasImage ? "📷 " + trimmed : trimmed
    }

    // MARK: Tin nhắn

    @ViewBuilder
    private func bubble(_ message: RoomMessage, online: Bool) -> some View {
        if let gift = message.gift {
            GiftMessagePill(message: message, gift: gift) {
                giftCenter.enqueue(message)
            }
            .contextMenu {
                if message.mine || model.room.isOwner {
                    Button(role: .destructive) {
                        Task { await model.delete(message) }
                    } label: {
                        Label("Xoá", systemImage: "trash")
                    }
                }
            }
        } else {
            messageBubble(message, online: online)
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: RoomMessage, online: Bool) -> some View {
        let canDelete = message.mine || model.room.isOwner
        let isOwner = message.user.id == model.room.ownerId
        let hasHan = ChineseText.containsHan(message.text)
        HStack(alignment: .top, spacing: 8) {
            if message.mine {
                Spacer(minLength: 48)
            } else {
                NavigationLink(value: message.user.socialUser(online: online)) {
                    SocialAvatar(url: message.user.avatarURL, initial: message.user.initial, size: 32, online: online,
                                 ring: Color(.systemGroupedBackground))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xem tường của \(message.user.name)")
            }

            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if !message.mine {
                    HStack(spacing: 6) {
                        NavigationLink(value: message.user.socialUser(online: online)) {
                            HStack(spacing: 3) {
                                Text(message.user.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if isOwner {
                                    Text("👑")
                                        .font(.caption2)
                                        .accessibilityLabel("Chủ phòng")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Text(SocialFormat.time(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if hasHan {
                            speakButton(message)
                            translateButton(message)
                        }
                    }
                }

                if let reply = message.replyTo {
                    quoteBlock(reply, mine: message.mine)
                }

                if let image = message.image {
                    Button {
                        viewingImage = image
                    } label: {
                        SocialImageView(image: image, maxWidth: 230, maxHeight: 300, cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            startReply(message)
                        } label: {
                            Label("Trả lời", systemImage: "arrowshape.turn.up.left")
                        }
                        if canDelete {
                            Button(role: .destructive) {
                                Task { await model.delete(message) }
                            } label: {
                                Label("Xoá ảnh", systemImage: "trash")
                            }
                        }
                    }
                }

                if !message.text.isEmpty || message.image == nil {
                messageText(message)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.mine ? socialRed.opacity(0.13) : Color(.secondarySystemGroupedBackground))
                    )
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contextMenu {
                        Button {
                            startReply(message)
                        } label: {
                            Label("Trả lời", systemImage: "arrowshape.turn.up.left")
                        }
                        if hasHan {
                            Button {
                                voice.speak(message.text)
                            } label: {
                                Label("Nghe", systemImage: "speaker.wave.2")
                            }
                            Button {
                                model.toggleTranslation(message)
                            } label: {
                                if model.shownTranslations.contains(message.id) {
                                    Label("Ẩn bản dịch", systemImage: "character.bubble")
                                } else {
                                    Label("Dịch sang tiếng Việt", systemImage: "character.bubble")
                                }
                            }
                        }
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Sao chép", systemImage: "doc.on.doc")
                        }
                        if canDelete {
                            Button(role: .destructive) {
                                Task { await model.delete(message) }
                            } label: {
                                Label("Xoá tin nhắn", systemImage: "trash")
                            }
                        }
                    }
                }

                if message.mine {
                    HStack(spacing: 6) {
                        if hasHan {
                            speakButton(message)
                            translateButton(message)
                        }
                        Text(SocialFormat.time(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !message.mine {
                Spacer(minLength: 48)
            }
        }
    }

    /// Ảnh của mình đang tải lên: ảnh mờ + vòng tiến độ.
    private func uploadBubble(_ upload: RoomChatModel.PendingUpload) -> some View {
        let ratio = upload.preview.size.height > 0 ? upload.preview.size.width / upload.preview.size.height : 1
        let width: CGFloat = ratio >= 1 ? 230 : max(120, 300 * ratio)
        return HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 3) {
                Image(uiImage: upload.preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: min(300, width / ratio))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(0.55)
                    .overlay {
                        VStack(spacing: 6) {
                            ProgressView(value: upload.progress)
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .controlSize(.large)
                            Text(upload.progress < 1 ? "\(Int(upload.progress * 100))%" : "Đang xử lý…")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                    }
                Text("Đang gửi ảnh…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang gửi ảnh")
    }

    /// Nút loa nhỏ: đọc câu tiếng Trung bằng giọng tự nhiên (giống nút Nghe ở hội thoại AI).
    private func speakButton(_ message: RoomMessage) -> some View {
        Button {
            voice.speak(message.text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(socialRed)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nghe")
    }

    /// Nút "Dịch" nhỏ cạnh nút loa: hiện / ẩn nghĩa tiếng Việt dưới tin.
    private func translateButton(_ message: RoomMessage) -> some View {
        let shown = model.shownTranslations.contains(message.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { model.toggleTranslation(message) }
        } label: {
            Text("Dịch")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(shown ? .white : socialRed)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(shown ? socialRed : socialRed.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shown ? "Ẩn bản dịch" : "Dịch sang tiếng Việt")
    }

    /// Có chữ Hán thì hiện pinyin xanh phía trên từng từ; chạm vào từ để xem nghĩa.
    /// Đã bấm "Dịch" thì nghĩa tiếng Việt hiện bên dưới.
    @ViewBuilder
    private func messageText(_ message: RoomMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let words = model.words(for: message) {
                RubyText(words: words, hanziSize: 19, pinyinColor: .blue, showHanViet: showHanViet) {
                    selectedWord = SelectedWord(word: $0)
                }
            } else {
                Text(message.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.shownTranslations.contains(message.id) {
                Group {
                    if let vi = model.translations[message.id] {
                        Text(vi)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Đang dịch…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(.separator)).frame(height: 0.5).offset(y: -2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.translations[message.id])
    }
}

// MARK: - Nói trong phòng chat

/// Micro của phòng chat, giống khu trả lời của hội thoại AI:
/// micro lớn nói tiếng Trung (gửi luôn), micro VI nói tiếng Việt (dịch rồi xác nhận), ∞ rảnh tay.
@MainActor
final class RoomVoiceModel: ObservableObject {
    /// Rảnh tay: gửi xong một câu là micro tự mở lại. Nhớ theo tài khoản.
    @Published var handsFree = RoomChatPrefs.handsFree {
        didSet { RoomChatPrefs.handsFree = handsFree }
    }
    /// Đang nghe tiếng Việt (micro VI).
    @Published private(set) var isAskingInVietnamese = false
    /// Câu tiếng Trung vừa nói, đang chờ 1,5 giây trước khi gửi (còn kịp Huỷ).
    @Published private(set) var outgoing: String?
    /// Câu tiếng Việt vừa nói và bản dịch tiếng Trung, chờ người học bấm Gửi / Sửa.
    @Published private(set) var pendingVi: String?
    @Published private(set) var pendingZh: String?
    @Published private(set) var translating = false
    @Published private(set) var isSending = false

    var isListening: Bool { captureStore?.isListening ?? false }
    var transcript: String { captureStore?.transcript ?? "" }
    var level: Float { captureStore?.level ?? 0 }
    /// Đang ở chế độ gõ chữ: không tự mở micro (rảnh tay).
    var typing = false {
        didSet { if typing { stopListening() } }
    }

    var onError: (@MainActor (String) -> Void)?

    /// Tạo micro khi dùng lần đầu (View có thể dựng lại nhiều lần, không tạo AVAudioEngine thừa).
    private var captureStore: SpeechCapture?
    private var captureObserver: AnyCancellable?
    private var send: (@MainActor (String) async -> Bool)?
    private var active = false
    private var sendTask: Task<Void, Never>?
    private var translateTask: Task<Void, Never>?
    private var generation = 0

    private var capture: SpeechCapture {
        if let captureStore { return captureStore }
        let capture = SpeechCapture()
        captureObserver = capture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        capture.onError = { [weak self] message in
            Task { @MainActor in
                self?.finishVietnameseListening()
                self?.onError?(message)
            }
        }
        captureStore = capture
        return capture
    }

    func activate(send: @escaping @MainActor (String) async -> Bool) {
        self.send = send
        active = true
    }

    /// Rời màn phòng: tắt micro, dừng vòng rảnh tay, bỏ câu đang chờ.
    func deactivate() {
        active = false
        generation += 1
        captureStore?.cancel()
        finishVietnameseListening()
        sendTask?.cancel()
        sendTask = nil
        translateTask?.cancel()
        translateTask = nil
        outgoing = nil
        translating = false
        NaturalSpeaker.chinese.stop()
    }

    /// Chuyển sang gõ chữ: tắt micro.
    func stopListening() {
        generation += 1
        captureStore?.cancel()
        finishVietnameseListening()
    }

    // MARK: Micro tiếng Trung

    /// Bấm micro lớn: đang nghe thì chốt câu, chưa nghe thì bắt đầu nghe.
    func toggleMic() {
        if isListening {
            capture.finish()
        } else {
            NaturalSpeaker.all.forEach { $0.stop() }
            listen()
        }
    }

    func listen() {
        guard active, !typing, !isListening, outgoing == nil, !isSending else { return }
        // Đang đọc tin thì để đọc xong, tránh micro thu lại tiếng của máy.
        guard !NaturalSpeaker.chinese.isSpeaking else { return }
        clearPending()
        finishVietnameseListening()
        capture.start(targets: []) { [weak self] heard in
            Task { @MainActor in
                guard let self else { return }
                let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
                // Không nghe được gì: dừng vòng rảnh tay để người học chủ động bấm lại.
                guard !text.isEmpty else { return }
                self.queueSend(text)
            }
        }
    }

    /// Hiện câu vừa nói (có pinyin) 1,5 giây rồi gửi; bấm Huỷ trong lúc đó thì bỏ.
    private func queueSend(_ text: String) {
        sendTask?.cancel()
        outgoing = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sendTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, self.outgoing == text else { return }
            await self.deliver(text)
            self.outgoing = nil
        }
    }

    func cancelOutgoing() {
        sendTask?.cancel()
        sendTask = nil
        outgoing = nil
    }

    private func deliver(_ text: String) async {
        guard let send, active else { return }
        isSending = true
        let ok = await send(text)
        isSending = false
        if ok && handsFree { listenSoon() }
    }

    /// Rảnh tay: mở lại micro khi máy không còn đọc (thử lại vài lần).
    private func listenSoon(attempt: Int = 0) {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.4 : 0.5)) { [weak self] in
            guard let self, self.active, self.handsFree, self.generation == current, attempt < 30 else { return }
            guard !NaturalSpeaker.chinese.isSpeaking, self.outgoing == nil, !self.isSending, self.pendingVi == nil else {
                self.listenSoon(attempt: attempt + 1)
                return
            }
            self.listen()
        }
    }

    func toggleHandsFree() {
        handsFree.toggle()
        if handsFree {
            listen()
        } else if isListening {
            stopListening()
        }
    }

    // MARK: Micro tiếng Việt

    /// Nghe tiếng Việt, dịch sang tiếng Trung để người học xem lại rồi mới gửi.
    func askInVietnamese() {
        if isListening {
            capture.finish()
            return
        }
        guard active, !typing else { return }
        NaturalSpeaker.all.forEach { $0.stop() }
        cancelOutgoing()
        clearPending()
        isAskingInVietnamese = true
        capture.localeIdentifier = "vi-VN"
        capture.start(targets: []) { [weak self] heard in
            Task { @MainActor in
                guard let self else { return }
                self.finishVietnameseListening()
                let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.translate(text)
            }
        }
    }

    private func translate(_ text: String) {
        pendingVi = text
        pendingZh = nil
        translating = true
        translateTask?.cancel()
        translateTask = Task { [weak self] in
            do {
                let zh = try await SocialAPI.translate(text: text, to: "zh")
                guard let self, !Task.isCancelled, self.pendingVi == text else { return }
                self.pendingZh = zh
                self.translating = false
            } catch {
                guard let self, !Task.isCancelled, self.pendingVi == text else { return }
                self.clearPending()
                if !(error is CancellationError) { self.onError?(error.localizedDescription) }
            }
        }
    }

    /// Gửi bản dịch đã xem.
    func confirmPending() {
        guard let zh = pendingZh else { return }
        clearPending()
        Task { await deliver(zh) }
    }

    /// Lấy bản dịch ra để sửa trong ô gõ chữ.
    func takePendingForEditing() -> String {
        let text = pendingZh ?? pendingVi ?? ""
        clearPending()
        return text
    }

    func clearPending() {
        translateTask?.cancel()
        translateTask = nil
        pendingVi = nil
        pendingZh = nil
        translating = false
    }

    private func finishVietnameseListening() {
        isAskingInVietnamese = false
        captureStore?.localeIdentifier = "zh-CN"
    }

    // MARK: Nghe tin nhắn

    /// Đọc một tin tiếng Trung; tắt micro trước để loa và micro không tranh nhau.
    /// Rảnh tay thì đọc xong micro tự mở lại.
    func speak(_ text: String) {
        stopListening()
        NaturalSpeaker.chinese.speak(text, preferOpenAI: true, completion: { [weak self] in
            Task { @MainActor in
                guard let self, self.active, self.handsFree else { return }
                self.listenSoon()
            }
        })
    }
}

/// Ô soạn tin: mặc định là hàng micro (⌨️ · VI · micro lớn · ∞), bấm bàn phím để gõ chữ.
private struct RoomComposer: View {
    @ObservedObject var model: RoomChatModel
    @ObservedObject var voice: RoomVoiceModel
    @Binding var focused: Bool

    /// Gõ chữ hay nói: nhớ theo tài khoản.
    @State private var textMode = RoomChatPrefs.textMode
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var showGifts = false
    @State private var choosingPhotoSource = false
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false

    var body: some View {
        VStack(spacing: 8) {
            if !model.room.joined, model.loaded {
                HStack {
                    Text("Bạn chưa tham gia phòng này")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Tham gia") { Task { await model.setJoined(true) } }
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 4)
            }
            if let reply = model.replyingTo {
                replyBar(reply)
            }
            if textMode {
                textRow
            } else {
                if voice.isListening {
                    listeningStrip
                } else if let outgoing = voice.outgoing {
                    outgoingCard(outgoing)
                } else if voice.pendingVi != nil {
                    pendingCard
                }
                micRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, textMode ? 8 : 4)
        .background(.bar)
        .animation(.easeInOut(duration: 0.18), value: voice.isListening)
        .animation(.easeInOut(duration: 0.18), value: voice.outgoing)
        .animation(.easeInOut(duration: 0.18), value: voice.pendingVi)
        .onChange(of: fieldFocused) { focused = $0 }
        .onChange(of: draft) { value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.userStoppedTyping()
            } else {
                model.userIsTyping()
            }
        }
        .onChange(of: voice.transcript) { value in
            if !value.isEmpty { model.userIsTyping() }
        }
        .sheet(isPresented: $showGifts) {
            GiftSheet(model: model) { message in
                model.receiveSentGift(message)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.replyingTo?.id)
        .onChange(of: model.replyingTo?.id) { id in
            if id != nil, textMode { fieldFocused = true }
        }
        .onAppear { voice.typing = textMode }
        .onChange(of: textMode) {
            voice.typing = $0
            RoomChatPrefs.textMode = $0
        }
        .confirmationDialog("Gửi ảnh", isPresented: $choosingPhotoSource) {
            Button("Chọn từ thư viện") { pickingPhoto = true }
            Button("Chụp ảnh") { showCamera = true }
            Button("Huỷ", role: .cancel) {}
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    model.errorMessage = "Không đọc được ảnh này."
                    return
                }
                await model.sendImage(image)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await model.sendImage(image) }
            }
            .ignoresSafeArea()
        }
    }

    /// Thanh "Đang trả lời …" trên hàng micro / ô gõ chữ.
    private func replyBar(_ message: RoomMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(socialRed)
            RoundedRectangle(cornerRadius: 2)
                .fill(socialRed)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Đang trả lời \(message.mine ? "chính bạn" : message.user.name)")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(RoomChatView.snippet(text: message.text, hasImage: message.image != nil))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                model.replyingTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Huỷ trả lời")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Chọn ảnh: có máy ảnh thì hỏi thư viện / chụp, không thì mở thư viện luôn.
    private func choosePhoto() {
        voice.stopListening()
        if CameraPicker.isAvailable {
            choosingPhotoSource = true
        } else {
            pickingPhoto = true
        }
    }

    private func giftButton(size: CGFloat) -> some View {
        Button {
            voice.stopListening()
            showGifts = true
        } label: {
            Text("🎁")
                .font(.system(size: size * 0.48))
                .frame(width: size, height: size)
                .background(Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4).opacity(0.5), socialRed.opacity(0.18)],
                                                         startPoint: .top, endPoint: .bottom)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Tặng quà")
    }

    private func photoButton(size: CGFloat) -> some View {
        Button {
            choosePhoto()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.borderless)
        .disabled(!model.uploads.isEmpty && model.uploads.count >= 3)
        .accessibilityLabel("Gửi ảnh")
    }

    // MARK: Hàng micro

    private var micRow: some View {
        HStack(spacing: 8) {
            Button {
                voice.stopListening()
                textMode = true
                fieldFocused = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Gõ chữ thay vì nói")

            Button {
                voice.askInVietnamese()
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: voice.isAskingInVietnamese ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("VI")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(voice.isAskingInVietnamese ? .white : Color.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(voice.isAskingInVietnamese ? socialRed : Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
            .disabled(voice.translating || (voice.isListening && !voice.isAskingInVietnamese))
            .accessibilityLabel("Chưa biết nói tiếng Trung — nói tiếng Việt để dịch rồi gửi")

            Spacer(minLength: 0)
            micButton
            Spacer(minLength: 0)

            Button {
                voice.toggleHandsFree()
            } label: {
                Image(systemName: "infinity")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(voice.handsFree ? socialRed : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(voice.handsFree ? socialRed.opacity(0.14) : Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(voice.handsFree ? "Tắt chế độ rảnh tay" : "Bật chế độ rảnh tay")

            photoButton(size: 40)
            giftButton(size: 40)
        }
    }

    private var micButton: some View {
        let listening = voice.isListening && !voice.isAskingInVietnamese
        let busy = voice.isSending || model.sending
        return Button {
            voice.toggleMic()
        } label: {
            ZStack {
                if listening {
                    Circle()
                        .fill(socialRed.opacity(0.22))
                        .frame(width: 72 + CGFloat(voice.level) * 36, height: 72 + CGFloat(voice.level) * 36)
                        .animation(.easeOut(duration: 0.12), value: voice.level)
                }
                Circle()
                    .fill(busy ? Color.gray.opacity(0.5) : socialRed)
                    .frame(width: 72, height: 72)
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 84, height: 80)
        }
        .buttonStyle(.borderless)
        .disabled(busy || voice.isAskingInVietnamese)
        .accessibilityLabel(listening ? "Nói xong" : "Bấm để nói tiếng Trung")
    }

    // MARK: Chữ đang nghe / câu chờ gửi

    private var listeningStrip: some View {
        RoomTranscriptView(text: voice.transcript,
                           placeholder: voice.isAskingInVietnamese
                               ? "Đang nghe… nói bằng tiếng Việt câu bạn muốn nhắn"
                               : "Đang nghe… hãy nói bằng tiếng Trung")
            .padding(.horizontal, 4)
    }

    private func outgoingCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chineseText(text)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(voice.isSending ? "Đang gửi…" : "Sắp gửi…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !voice.isSending {
                    Button("Huỷ") { voice.cancelOutgoing() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(socialRed.opacity(0.08)))
        .transition(.opacity)
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let zh = voice.pendingZh {
                chineseText(zh)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang dịch sang tiếng Trung…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let vi = voice.pendingVi {
                Text("🇻🇳 \(vi)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    voice.clearPending()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Bỏ")
                Spacer()
                if let zh = voice.pendingZh {
                    Button {
                        NaturalSpeaker.chinese.speak(zh, preferOpenAI: true)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(socialRed)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Nghe")
                }
                Button {
                    draft = voice.takePendingForEditing()
                    textMode = true
                    fieldFocused = true
                } label: {
                    Text("Sửa")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(socialRed)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().strokeBorder(socialRed, lineWidth: 1.5))
                }
                .buttonStyle(.borderless)
                .disabled(voice.pendingZh == nil)
                Button {
                    voice.confirmPending()
                } label: {
                    Text("Gửi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(voice.pendingZh == nil ? Color(.systemGray3) : socialRed))
                }
                .buttonStyle(.borderless)
                .disabled(voice.pendingZh == nil)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .transition(.opacity)
    }

    @ViewBuilder
    private func chineseText(_ text: String) -> some View {
        if ChineseText.containsHan(text) {
            RubyText(words: ChineseText.words(for: text), hanziSize: 19, pinyinColor: .blue, showHanViet: showHanViet)
        } else {
            Text(text).font(.body)
        }
    }

    // MARK: Gõ chữ

    private var textRow: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tooLong = draft.count > RoomChatModel.maxLength
        return VStack(spacing: 4) {
            if ChineseText.containsHan(trimmed) {
                RubyText(words: ChineseText.words(for: trimmed), hanziSize: 16, pinyinColor: .blue, showHanViet: showHanViet)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    fieldFocused = false
                    textMode = false
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(socialRed))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Quay lại nói bằng micro")

                photoButton(size: 38)
                giftButton(size: 38)

                TextField("Nhắn bằng tiếng Trung…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($fieldFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))

                Button {
                    let text = draft
                    Task {
                        if await model.send(text) { draft = "" }
                    }
                } label: {
                    Group {
                        if model.sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(trimmed.isEmpty || tooLong ? Color(.systemGray3) : socialRed))
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty || tooLong || model.sending)
                .accessibilityLabel("Gửi")
            }
            if draft.count > RoomChatModel.maxLength - 50 {
                Text("\(draft.count)/\(RoomChatModel.maxLength)")
                    .font(.caption2)
                    .foregroundStyle(tooLong ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// Chữ đang nghe được, kèm pinyin khi là tiếng Trung (giống dải "đang nghe" của hội thoại AI).
private struct RoomTranscriptView: View {
    let text: String
    let placeholder: String
    private let maxWords = 16

    @State private var words: [PinyinWord] = []
    @State private var source = ""

    var body: some View {
        Group {
            if words.isEmpty {
                Text(text.isEmpty ? placeholder : text)
                    .font(.callout)
                    .foregroundStyle(text.isEmpty ? Color.secondary : socialRed)
                    .lineLimit(2)
            } else {
                RubyText(words: words, hanziSize: 20, hanziWeight: .semibold,
                         pinyinColor: socialRed.opacity(0.7), hanziColor: socialRed, showHanViet: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.12), value: words.count)
        .onAppear { rebuild(text) }
        .onChange(of: text) { rebuild($0) }
    }

    private func rebuild(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != source else { return }
        source = trimmed
        guard ChineseText.containsHan(trimmed) else {
            words = []
            return
        }
        let all = ChineseText.words(for: trimmed)
        words = all.count > maxWords ? Array(all.suffix(maxWords)) : all
    }
}

/// Vuốt sang phải một tin để trả lời: lộ biểu tượng ↩, rung nhẹ khi qua ngưỡng.
private struct SwipeToReply: ViewModifier {
    let onReply: () -> Void

    @State private var offset: CGFloat = 0
    @State private var armed = false
    @State private var horizontal: Bool?

    private let threshold: CGFloat = 64

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(armed ? .white : socialRed)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(armed ? socialRed : socialRed.opacity(0.14)))
                    .scaleEffect(armed ? 1.1 : max(0.4, offset / threshold))
                    .opacity(Double(min(1, offset / (threshold * 0.6))))
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onChanged { value in
                        // Chỉ nhận vuốt ngang, để cuộn dọc vẫn bình thường.
                        if horizontal == nil {
                            horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                        }
                        guard horizontal == true else { return }
                        let dx = max(0, value.translation.width)
                        offset = dx < threshold ? dx : threshold + (dx - threshold) * 0.25
                        let nowArmed = dx >= threshold
                        if nowArmed != armed {
                            armed = nowArmed
                            if nowArmed { UISelectionFeedbackGenerator().selectionChanged() }
                        }
                    }
                    .onEnded { _ in
                        if horizontal == true, armed { onReply() }
                        horizontal = nil
                        armed = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = 0 }
                    }
            )
    }
}

// MARK: - Đang gõ

/// Ba chấm nhấp nháy lần lượt.
struct TypingDots: View {
    var dotSize: CGFloat = 6
    var color: Color = .secondary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: dotSize * 0.6) {
                ForEach(0..<3, id: \.self) { i in
                    dot(level: Self.level(time: t, index: i))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func level(time: Double, index: Int) -> CGFloat {
        let angle: Double = time * 2 * Double.pi / 1.1 - Double(index) * 0.9
        return CGFloat(max(0, sin(angle)))
    }

    private func dot(level: CGFloat) -> some View {
        let size: CGFloat = dotSize
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(Double(0.35 + 0.65 * level))
            .offset(y: -size * 0.4 * level)
    }
}

/// "Lan đang gõ…" ở cuối danh sách tin: ảnh đại diện chồng nhau + bong bóng ba chấm.
private struct TypingIndicator: View {
    let users: [RoomMessage.User]

    private var label: String {
        switch users.count {
        case 1: return "\(users[0].name) đang gõ…"
        case 2: return "\(users[0].name) và \(users[1].name) đang gõ…"
        default: return "\(users.count) người đang gõ…"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: -10) {
                ForEach(Array(users.prefix(3).enumerated()), id: \.element.id) { index, user in
                    SocialAvatar(url: user.avatarURL, initial: user.initial, size: 26)
                        .background(Circle().fill(Color(.systemGroupedBackground)).padding(-1.5))
                        .zIndex(Double(3 - index))
                }
            }
            TypingDots(dotSize: 6)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Nhớ cách nhập theo tài khoản

/// Lựa chọn ô soạn tin (gõ chữ / micro, rảnh tay), lưu theo tài khoản web: "chatPrefs.<userId>".
enum RoomChatPrefs {
    private static var key: String { "chatPrefs.\(WebAccountStore.shared.user?.id ?? 0)" }

    private static var values: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var textMode: Bool {
        get { values["textMode"] ?? false }
        set { values["textMode"] = newValue }
    }

    static var handsFree: Bool {
        get { values["handsFree"] ?? false }
        set { values["handsFree"] = newValue }
    }
}

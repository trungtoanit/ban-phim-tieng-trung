//
//  ChatRoomsView.swift
//  Phòng chat công khai kiểu HelloTalk: ai cũng tạo được phòng, vào phòng nói chuyện bằng tiếng Trung.
//  Dùng chung dữ liệu với phong-chat.php của website (api/social.php). Tin mới được hỏi lại mỗi 3 giây.
//

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

    var joined: [ChatRoom] { rooms.filter(\.joined) }
    var explore: [ChatRoom] { rooms.filter { !$0.joined } }

    func load(query: String = "") async {
        do {
            rooms = try await SocialAPI.rooms(query: query)
            loaded = true
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
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
    @State private var path: [ChatRoom] = []
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
            .refreshable { await model.load(query: query) }
            .navigationDestination(for: ChatRoom.self) { room in
                RoomChatView(room: room,
                             onUpdate: { model.update($0) },
                             onDeleted: { model.remove(id: room.id) })
            }
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

    var body: some View {
        HStack(spacing: 12) {
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
            VStack(alignment: .trailing, spacing: 4) {
                Text("👥 \(room.memberCount)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let time = room.lastMessageAt, !SocialFormat.time(time).isEmpty {
                    Text(SocialFormat.time(time))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var preview: String {
        if let last = room.lastMessage, !last.isEmpty { return last }
        return room.description.isEmpty ? "Chưa có tin nhắn" : room.description
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

    func load() async {
        do {
            let page = try await SocialAPI.room(id: room.id)
            room = page.room
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
            merge(page.messages)
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

    func loadOlder() async {
        guard let first = messages.first, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await SocialAPI.room(id: room.id, before: first.id)
            let known = Set(messages.map(\.id))
            messages.insert(contentsOf: page.messages.filter { !known.contains($0.id) }, at: 0)
            hasMore = page.hasMore
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= Self.maxLength, !sending else { return false }
        sending = true
        defer { sending = false }
        do {
            let message = try await SocialAPI.send(roomId: room.id, text: text)
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

    private func merge(_ incoming: [RoomMessage]) {
        let known = Set(messages.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        messages.append(contentsOf: fresh)
        messages.sort { $0.id < $1.id }
    }
}

struct RoomChatView: View {
    let onUpdate: (ChatRoom) -> Void
    let onDeleted: () -> Void

    @StateObject private var model: RoomChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var confirmDelete = false
    @State private var selectedWord: SelectedWord?
    @FocusState private var composerFocused: Bool
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

                    ForEach(model.messages) { message in
                        bubble(message)
                            .id(message.id)
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
            .onChange(of: composerFocused) { focused in
                guard focused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .navigationBarTrailing) { menu }
        }
        .wordPopup($selectedWord)
        // Hỏi tin mới mỗi 3 giây khi đang mở phòng; rời màn hình thì .task tự huỷ vòng lặp.
        .task {
            await model.load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await model.poll()
            }
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

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.room.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.room.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(model.room.memberCount) thành viên")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
            Section("Chủ phòng: \(model.room.ownerName)") {
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

    // MARK: Tin nhắn

    @ViewBuilder
    private func bubble(_ message: RoomMessage) -> some View {
        let canDelete = message.mine || model.room.isOwner
        HStack(alignment: .top, spacing: 8) {
            if message.mine {
                Spacer(minLength: 48)
            } else {
                SocialAvatar(url: message.user.avatarURL, initial: message.user.initial, size: 32)
            }

            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if !message.mine {
                    HStack(spacing: 6) {
                        Text(message.user.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(SocialFormat.time(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

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

                if message.mine {
                    Text(SocialFormat.time(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !message.mine {
                Spacer(minLength: 48)
            }
        }
    }

    /// Có chữ Hán thì hiện pinyin xanh phía trên từng từ; chạm vào từ để xem nghĩa.
    @ViewBuilder
    private func messageText(_ message: RoomMessage) -> some View {
        if let words = model.words(for: message) {
            RubyText(words: words, hanziSize: 19, pinyinColor: .blue, showHanViet: showHanViet) {
                selectedWord = SelectedWord(word: $0)
            }
        } else {
            Text(message.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Ô soạn tin

    private var composer: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tooLong = draft.count > RoomChatModel.maxLength
        return VStack(spacing: 4) {
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Nhắn bằng tiếng Trung…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

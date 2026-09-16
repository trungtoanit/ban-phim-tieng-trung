//
//  FriendsView.swift
//  Bạn bè kiểu Duolingo: theo dõi nhau, bảng xếp hạng số câu nói trong tuần, gợi ý kết bạn.
//  Dữ liệu dùng chung với trang ban-be.php của website (api/social.php).
//

import SwiftUI

let socialRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct FriendsView: View {
    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if web.isSignedIn {
                    FriendsHomeView()
                } else {
                    SocialSignInCard(
                        icon: "person.2.fill",
                        title: "Học cùng bạn bè",
                        message: "Cần tài khoản để theo dõi bạn bè, xem ai nói nhiều câu nhất tuần và giữ chuỗi ngày cùng nhau."
                    )
                    .navigationTitle("Bạn bè")
                }
            }
            .homeBackButton()
        }
    }
}

// MARK: - Dữ liệu

@MainActor
final class FriendsModel: ObservableObject {
    @Published var payload = FriendsPayload.empty
    @Published var results: [SocialUser] = []
    @Published var loaded = false
    @Published var searching = false
    @Published var errorMessage: String?

    func load() async {
        do {
            payload = try await SocialAPI.friends()
            loaded = true
        } catch is CancellationError {
        } catch {
            // Lần tải đầu hỏng thì báo; tự làm mới lỗi thì im lặng.
            if !loaded { errorMessage = error.localizedDescription }
        }
    }

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }
        searching = true
        defer { searching = false }
        do {
            let users = try await SocialAPI.search(q)
            if !Task.isCancelled { results = users }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Theo dõi / bỏ theo dõi: đổi ngay trên màn hình, lỗi thì trả lại như cũ.
    /// Trả về hồ sơ mới của máy chủ, nil nếu lỗi.
    @discardableResult
    func toggleFollow(_ user: SocialUser) async -> SocialUser? {
        let follow = !user.following
        let before = (payload, results)
        apply(id: user.id) { $0.following = follow }
        do {
            let updated: SocialUser
            if follow {
                updated = try await SocialAPI.follow(userId: user.id)
            } else {
                updated = try await SocialAPI.unfollow(userId: user.id)
            }
            apply(id: user.id) {
                $0.following = updated.following
                $0.followsMe = updated.followsMe
            }
            await load()
            return updated
        } catch {
            (payload, results) = before
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func apply(id: Int, _ change: (inout SocialUser) -> Void) {
        func update(_ list: inout [SocialUser]) {
            for index in list.indices where list[index].id == id { change(&list[index]) }
        }
        update(&payload.following)
        update(&payload.followers)
        update(&payload.suggestions)
        update(&payload.leaderboard)
        update(&results)
    }
}

// MARK: - Màn chính

private struct FriendsHomeView: View {
    @StateObject private var model = FriendsModel()
    @State private var query = ""
    @State private var showFollowers = false

    private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        List {
            if isSearching {
                searchSection
            } else {
                listSection
                leaderboardSection
                suggestionsSection
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !model.loaded && model.errorMessage == nil && !isSearching {
                ProgressView("Đang tải…")
            }
        }
        .navigationTitle("Bạn bè")
        .navigationDestination(for: SocialUser.self) { user in
            SocialProfileView(user: user, model: model)
        }
        .searchable(text: $query, prompt: "Tìm theo tên hoặc @username")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        // Gõ xong 300ms mới tìm, để không gọi máy chủ theo từng chữ.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .refreshable { await model.load() }
        // Tải lần đầu rồi tự làm mới mỗi 30 giây khi màn hình đang mở.
        .task {
            await model.load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await model.load()
            }
        }
        .alert("Có lỗi", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Tìm kiếm

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if model.results.isEmpty {
                HStack {
                    if model.searching { ProgressView() }
                    Text(model.searching ? "Đang tìm…" : "Không tìm thấy ai.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.results) { user in
                    userRow(user)
                }
            }
        } header: {
            Text("Kết quả tìm kiếm")
        }
    }

    // MARK: Đang theo dõi / Người theo dõi

    private var listSection: some View {
        Section {
            Picker("", selection: $showFollowers) {
                Text("Đang theo dõi (\(model.payload.following.count))").tag(false)
                Text("Người theo dõi (\(model.payload.followers.count))").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            let users = showFollowers ? model.payload.followers : model.payload.following
            if users.isEmpty, model.loaded {
                Text(showFollowers
                     ? "Chưa có ai theo dõi bạn. Luyện nói đều đặn để lọt vào gợi ý của người khác nhé!"
                     : "Bạn chưa theo dõi ai. Tìm bạn bè ở ô tìm kiếm hoặc xem gợi ý bên dưới.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(users) { user in
                    userRow(user)
                }
            }
        }
    }

    // MARK: Bảng xếp hạng tuần

    @ViewBuilder
    private var leaderboardSection: some View {
        if !model.payload.leaderboard.isEmpty {
            Section {
                ForEach(Array(model.payload.leaderboard.enumerated()), id: \.element.id) { index, user in
                    Group {
                        if user.isMe {
                            leaderboardRow(rank: index + 1, user: user)
                        } else {
                            NavigationLink(value: user) {
                                leaderboardRow(rank: index + 1, user: user)
                            }
                        }
                    }
                    .listRowBackground(user.isMe ? socialRed.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                }
            } header: {
                Text("Bảng xếp hạng tuần")
            } footer: {
                Text("Số câu tiếng Trung đã nói trong tuần này (từ thứ Hai), gồm bạn và những người bạn theo dõi.")
            }
        }
    }

    private func leaderboardRow(rank: Int, user: SocialUser) -> some View {
        HStack(spacing: 12) {
            Group {
                switch rank {
                case 1: Text("🥇")
                case 2: Text("🥈")
                case 3: Text("🥉")
                default: Text("\(rank)").foregroundStyle(.secondary)
                }
            }
            .font(rank <= 3 ? .title3 : .subheadline.weight(.semibold))
            .frame(width: 30)

            SocialAvatar(url: user.avatarURL, initial: user.initial, size: 36)
            Text(user.isMe ? "Bạn" : user.name)
                .font(.subheadline.weight(user.isMe ? .bold : .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(user.weekSentences) câu")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(user.isMe ? socialRed : .primary)
                if user.streak > 0 {
                    Text("🔥 \(user.streak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Gợi ý

    @ViewBuilder
    private var suggestionsSection: some View {
        if !model.payload.suggestions.isEmpty {
            Section {
                ForEach(model.payload.suggestions) { user in
                    userRow(user)
                }
            } header: {
                Text("Gợi ý kết bạn")
            } footer: {
                Text("Những người học chăm chỉ trong 7 ngày qua.")
            }
        }
    }

    private func userRow(_ user: SocialUser) -> some View {
        NavigationLink(value: user) {
            SocialUserRow(user: user) {
                Task { await model.toggleFollow(user) }
            }
        }
    }
}

// MARK: - Dòng người dùng

struct SocialUserRow: View {
    let user: SocialUser
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SocialAvatar(url: user.avatarURL, initial: user.initial, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let handle = user.handle {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !user.isMe {
                FollowButton(user: user, action: onFollow)
            }
        }
        .padding(.vertical, 2)
    }

    private var statsLine: String {
        let week = "\(user.weekSentences) câu tuần này"
        return user.streak > 0 ? "🔥 \(user.streak) · \(week)" : week
    }
}

/// Nút viên: đỏ đặc "Theo dõi", viền "Đang theo dõi", "Theo dõi lại" khi người đó đã theo dõi mình.
struct FollowButton: View {
    let user: SocialUser
    var large = false
    let action: () -> Void

    private var title: String {
        if user.following { return "Đang theo dõi" }
        return user.followsMe ? "Theo dõi lại" : "Theo dõi"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if user.following {
                    Image(systemName: "checkmark")
                        .font(.system(size: large ? 13 : 10, weight: .bold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font((large ? Font.subheadline : .caption).weight(.semibold))
            .foregroundStyle(user.following ? socialRed : .white)
            .padding(.horizontal, large ? 22 : 12)
            .padding(.vertical, large ? 11 : 7)
            .frame(maxWidth: large ? .infinity : nil)
            .background {
                if user.following {
                    Capsule().strokeBorder(socialRed, lineWidth: 1.5)
                } else {
                    Capsule().fill(socialRed)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .animation(.easeInOut(duration: 0.15), value: user.following)
        .accessibilityLabel(title)
    }
}

/// Ảnh đại diện; không có ảnh thì là vòng tròn đỏ với chữ cái đầu tên.
struct SocialAvatar: View {
    let url: URL?
    let initial: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle()
            .fill(LinearGradient(colors: AppTab.friends.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(initial.isEmpty ? "?" : initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Hồ sơ

struct SocialProfileView: View {
    @ObservedObject var model: FriendsModel
    @State private var user: SocialUser
    @State private var busy = false

    init(user: SocialUser, model: FriendsModel) {
        _user = State(initialValue: user)
        self.model = model
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    SocialAvatar(url: user.avatarURL, initial: user.initial, size: 104)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    Text(user.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let handle = user.handle {
                        Text(handle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if user.followsMe {
                        Text("Đang theo dõi bạn")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                }
                .padding(.top, 12)

                if !user.isMe {
                    FollowButton(user: user, large: true) {
                        Task { await toggle() }
                    }
                    .disabled(busy)
                    .padding(.horizontal, 40)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    stat("🔥", "\(user.streak)", "chuỗi ngày")
                    stat("💬", "\(user.weekSentences)", "câu tuần này")
                    stat("📚", "\(user.totalSentences)", "tổng câu")
                    stat("👥", user.followersCount.map(String.init) ?? "–", "người theo dõi")
                    stat("➕", user.followingCount.map(String.init) ?? "–", "đang theo dõi")
                    stat("☀️", "\(user.todaySentences)", "câu hôm nay")
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func stat(_ emoji: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.title3)
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func reload() async {
        if let fresh = try? await SocialAPI.profile(id: user.id) {
            user = fresh
        }
    }

    private func toggle() async {
        busy = true
        defer { busy = false }
        let before = user
        let follow = !user.following
        user.following = follow
        if let count = user.followersCount { user.followersCount = max(0, count + (follow ? 1 : -1)) }
        if await model.toggleFollow(before) == nil {
            user = before
        } else {
            await reload()
        }
    }
}

// MARK: - Thẻ mời đăng nhập (dùng chung cho Bạn bè và Phòng chat)

struct SocialSignInCard: View {
    let icon: String
    let title: String
    let message: String

    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(LinearGradient(colors: AppTab.friends.colors, startPoint: .top, endPoint: .bottom)))
                VStack(spacing: 6) {
                    Text(title).font(.title3.weight(.bold))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                    PasswordLoginForm()
                    GoogleSignInButton()
                    if let error = web.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .padding(16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
